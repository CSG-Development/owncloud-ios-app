//
//  FileNameConflictCoordinator.swift
//  ownCloud
//
//  Preflight name conflicts for copy/move, then present a single card dialog.
//

import UIKit
import ownCloudSDK
import ownCloudAppShared

enum FileNameConflictOperation {
	case copy
	case move
}

final class FileNameConflictCoordinator {

	typealias ProgressHandler = (Progress) -> Void

	private let items: [OCItem]
	private let destination: OCItem
	private let operation: FileNameConflictOperation
	private let core: OCCore
	private let clientContext: ClientContext
	private let publishProgress: ProgressHandler
	private let completion: () -> Void

	private var overlayTransitioningDelegate: CrossDissolveTransitioningDelegate?
	private weak var presentedOverlay: UIViewController?
	private var reservedNames = Set<String>()
	/// Keeps the coordinator alive across async cache lookups and dialog presentation.
	private var retainSelf: FileNameConflictCoordinator?

	private static let forceReplaceOption = OCCoreOption(rawValue: OCConnectionOptionKey.forceReplaceKey.rawValue)
	private static let replaceIdentifier = OCMessageChoiceIdentifier(rawValue: "replaceExisting")
	private static let keepBothIdentifier = OCMessageChoiceIdentifier(rawValue: "keepBoth")

	init(items: [OCItem],
	     destination: OCItem,
	     operation: FileNameConflictOperation,
	     core: OCCore,
	     clientContext: ClientContext,
	     publishProgress: @escaping ProgressHandler,
	     completion: @escaping () -> Void) {
		self.items = items
		self.destination = destination
		self.operation = operation
		self.core = core
		self.clientContext = clientContext
		self.publishProgress = publishProgress
		self.completion = completion
	}

	static func perform(items: [OCItem],
			    to destination: OCItem,
			    operation: FileNameConflictOperation,
			    core: OCCore,
			    clientContext: ClientContext,
			    publishProgress: @escaping ProgressHandler,
			    completion: @escaping () -> Void) {
		let coordinator = FileNameConflictCoordinator(
			items: items,
			destination: destination,
			operation: operation,
			core: core,
			clientContext: clientContext,
			publishProgress: publishProgress,
			completion: completion
		)
		coordinator.retainSelf = coordinator
		coordinator.start()
	}

	private func finish() {
		overlayTransitioningDelegate = nil
		presentedOverlay = nil
		retainSelf = nil
		completion()
	}

	private func start() {
		guard let location = destination.location, let database = core.vault.database else {
			schedule(items: items, replace: false)
			finish()
			return
		}

		database.retrieveCacheItems(at: location, itemOnly: false, completionHandler: { [weak self] _, _, _, cachedItems in
			OnMainThread {
				self?.evaluateCachedItems(cachedItems ?? [])
			}
		})
	}

	private func evaluateCachedItems(_ cachedItems: [OCItem]) {
		var occupiedNames = Set<String>()
		for child in cachedItems {
			guard let name = child.name, child.localID != destination.localID else { continue }
			occupiedNames.insert(name)
		}

		var clearItems: [OCItem] = []
		var conflictingItems: [OCItem] = []
		var namesInBatch = Set<String>()

		for item in items {
			guard let name = item.name else { continue }

			if operation == .move, item.parentLocalID == destination.localID {
				continue
			}

			let collidesWithDestination = occupiedNames.contains(name) && !cachedItems.contains(where: { $0.name == name && $0.localID == item.localID })
			let collidesInBatch = namesInBatch.contains(name)

			if collidesWithDestination || collidesInBatch {
				conflictingItems.append(item)
			} else {
				clearItems.append(item)
				namesInBatch.insert(name)
			}
		}

		schedule(items: clearItems, replace: false)
		presentConflicts(conflictingItems)
	}

	private func presentConflicts(_ conflicts: [OCItem]) {
		guard !conflicts.isEmpty else {
			finish()
			return
		}

		let first = conflicts[0]
		let fileName = first.name ?? ""
		let remaining = Array(conflicts.dropFirst())
		let showsApplyToAll = !remaining.isEmpty

		let dialog = FileConflictDialogViewController(
			title: HCL10n.FileConflict.title,
			subtitle: FileConflictDialogViewController.subtitle(forFileName: fileName),
			choices: FileConflictDialogViewController.defaultChoices(),
			showsApplyToAll: showsApplyToAll
		) { [weak self] identifier, applyToAll in
			guard let self else { return }

			let finishChoice = {
				self.handleChoice(identifier, applyToAll: applyToAll, current: first, remaining: remaining)
			}

			if let overlay = self.presentedOverlay {
				overlay.dismiss(animated: true, completion: finishChoice)
			} else {
				finishChoice()
			}
		}

		let overlay = AuthCardOverlayViewController(content: dialog)
		let animator = CrossDissolveTransitioningDelegate()
		overlay.transitioningDelegate = animator
		overlay.modalPresentationStyle = .custom
		overlayTransitioningDelegate = animator
		presentedOverlay = overlay

		if !clientContext.present(overlay, animated: true) {
			handleChoice(.cancel, applyToAll: true, current: first, remaining: remaining)
		}
	}

	private func handleChoice(_ identifier: OCMessageChoiceIdentifier, applyToAll: Bool, current: OCItem, remaining: [OCItem]) {
		presentedOverlay = nil
		overlayTransitioningDelegate = nil

		let targets: [OCItem] = applyToAll ? [current] + remaining : [current]
		let leftover = applyToAll ? [] : remaining

		if identifier == Self.replaceIdentifier {
			schedule(items: targets, replace: true)
			presentConflicts(leftover)
			return
		}

		if identifier == Self.keepBothIdentifier {
			keepBoth(items: targets) { [weak self] in
				self?.presentConflicts(leftover)
			}
			return
		}

		presentConflicts(leftover)
	}

	private func keepBoth(items: [OCItem], done: @escaping () -> Void) {
		guard let item = items.first, let name = item.name, let location = destination.location else {
			done()
			return
		}

		let reserved = reservedNames
		core.suggestUnusedNameBased(on: name, at: location, isDirectory: item.type == .collection, using: .bracketed, filteredBy: { suggested in
			!reserved.contains(suggested)
		}, resultHandler: { [weak self] suggestedName, _ in
			OnMainThread {
				guard let self else {
					done()
					return
				}

				let uniqueName = suggestedName ?? name
				self.reservedNames.insert(uniqueName)
				self.schedule(item: item, name: uniqueName, replace: false)
				self.keepBoth(items: Array(items.dropFirst()), done: done)
			}
		})
	}

	private func schedule(items: [OCItem], replace: Bool) {
		for item in items {
			guard let name = item.name else { continue }
			schedule(item: item, name: name, replace: replace)
		}
	}

	private func schedule(item: OCItem, name: String, replace: Bool) {
		let options: [OCCoreOption: Any]? = replace ? [Self.forceReplaceOption: true] : nil
		let location = destination.location
		let progress: Progress?

		switch operation {
		case .move:
			progress = core.move(item, to: destination, withName: name, options: options) { error, _, _, _ in
				if error != nil {
					Log.error("Error \(String(describing: error)) moving \(name) to \(String(describing: location))")
				}
			}
		case .copy:
			progress = core.copy(item, to: destination, withName: name, options: options) { error, _, _, _ in
				if error != nil {
					Log.error("Error \(String(describing: error)) copying \(name) to \(String(describing: location))")
				}
			}
		}

		if let progress {
			publishProgress(progress)
		}
	}
}
