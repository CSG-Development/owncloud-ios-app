//
//  TrashRestoreConflictChecker.swift
//  ownCloud
//
//  Copyright © 2025 ownCloud GmbH. All rights reserved.
//

import UIKit
import ownCloudSDK
import ownCloudAppShared

struct TrashRestoreItemOutcome {
	let item: OCItem
	let error: Error?
	let skipped: Bool
}

enum TrashRestoreConflictChecker {
	private static let maximumRenameAttempts = 100

	static func originalLocation(for item: OCItem) -> String? {
		guard let destinationPath = item.value(forLocalAttribute: OCLocalAttribute.trashOriginalLocation) as? String,
		      !destinationPath.isEmpty else {
			return nil
		}
		return destinationPath
	}

	static func displayName(for item: OCItem) -> String {
		if let originalFilename = item.value(forLocalAttribute: OCLocalAttribute.trashOriginalFilename) as? String,
		   !originalFilename.isEmpty {
			return originalFilename
		}
		if let location = originalLocation(for: item) {
			let name = (location as NSString).lastPathComponent
			if !name.isEmpty {
				return name
			}
		}
		return item.name ?? ""
	}

	static func conflictsAtDestination(for item: OCItem, connection: OCConnection, completion: @escaping (Bool) -> Void) {
		guard let destinationPath = originalLocation(for: item) else {
			completion(false)
			return
		}

		pathIsOccupied(destinationPath, item: item, connection: connection, completion: completion)
	}

	/// `name (1).ext`, matching the keep-both restore used by the server CLI and Android.
	static func bracketedName(for fileName: String, index: Int) -> String {
		let lowercased = fileName.lowercased()
		for suffix in [".tar.gz", ".tar.bz2", ".tar.bz"] where lowercased.hasSuffix(suffix) {
			let base = String(fileName.dropLast(suffix.count))
			let extensionPart = String(fileName.suffix(suffix.count))
			return "\(base) (\(index))\(extensionPart)"
		}

		let name = fileName as NSString
		let pathExtension = name.pathExtension
		if pathExtension.isEmpty {
			return "\(fileName) (\(index))"
		}
		return "\(name.deletingPathExtension) (\(index)).\(pathExtension)"
	}

	static func replacingLastPathComponent(of path: String, with fileName: String) -> String {
		let original = path as NSString
		let parent = original.deletingLastPathComponent
		if parent.isEmpty || parent == "/" {
			return path.hasPrefix("/") ? "/" + fileName : fileName
		}
		return (parent as NSString).appendingPathComponent(fileName)
	}

	static func firstAvailableRelativePath(for item: OCItem,
	                                       connection: OCConnection,
	                                       reservedPaths: Set<String>,
	                                       completion: @escaping (String?) -> Void) {
		guard let originalPath = originalLocation(for: item) else {
			completion(nil)
			return
		}

		let fileName = (originalPath as NSString).lastPathComponent
		probeAvailablePath(originalPath: originalPath,
		                   fileName: fileName,
		                   item: item,
		                   connection: connection,
		                   reservedPaths: reservedPaths,
		                   index: 1,
		                   completion: completion)
	}

	private static func probeAvailablePath(originalPath: String,
	                                       fileName: String,
	                                       item: OCItem,
	                                       connection: OCConnection,
	                                       reservedPaths: Set<String>,
	                                       index: Int,
	                                       completion: @escaping (String?) -> Void) {
		guard index <= maximumRenameAttempts else {
			completion(nil)
			return
		}

		let candidate = replacingLastPathComponent(of: originalPath, with: bracketedName(for: fileName, index: index))
		if reservedPaths.contains(candidate) {
			probeAvailablePath(originalPath: originalPath,
			                   fileName: fileName,
			                   item: item,
			                   connection: connection,
			                   reservedPaths: reservedPaths,
			                   index: index + 1,
			                   completion: completion)
			return
		}

		pathIsOccupied(candidate, item: item, connection: connection) { occupied in
			if occupied {
				probeAvailablePath(originalPath: originalPath,
				                   fileName: fileName,
				                   item: item,
				                   connection: connection,
				                   reservedPaths: reservedPaths,
				                   index: index + 1,
				                   completion: completion)
				return
			}
			completion(candidate)
		}
	}

	private static func pathIsOccupied(_ path: String, item: OCItem, connection: OCConnection, completion: @escaping (Bool) -> Void) {
		let location = OCLocation(driveID: item.driveID, path: path)
		_ = connection.retrieveItemList(at: location, depth: 0, options: nil) { error, foundItems in
			OnMainThread {
				completion(error == nil && !(foundItems ?? []).isEmpty)
			}
		}
	}
}

/// Asks Replace / Keep both / Skip when a trashed item's original name is already in the destination, then restores.
final class TrashRestoreCoordinator {
	private enum Action {
		case pending
		case standard
		/// Delete the live item at the original path, then restore with the same request used when there is no conflict.
		case replace
		case webDAV(path: String, overwrite: Bool)
		case skipped
		case unresolved
	}

	private struct Plan {
		let item: OCItem
		var action: Action
	}

	private enum Choice {
		case replace
		case keepBoth
		case skip
	}

	private let items: [OCItem]
	private let core: OCCore
	private let present: (UIViewController) -> Bool
	private let setBusy: (Bool) -> Void
	private let completion: ([TrashRestoreItemOutcome]) -> Void

	private var plans: [Plan] = []
	private var outcomes: [TrashRestoreItemOutcome] = []
	private var reservedPaths = Set<String>()
	private var policy: Choice?
	private var didPauseForDialog = false
	private var retainSelf: TrashRestoreCoordinator?
	private var overlayTransitioningDelegate: CrossDissolveTransitioningDelegate?
	private weak var presentedOverlay: UIViewController?

	private static let replaceIdentifier = OCMessageChoiceIdentifier(rawValue: "replaceExisting")
	private static let keepBothIdentifier = OCMessageChoiceIdentifier(rawValue: "keepBoth")

	static func perform(items: [OCItem],
	                    core: OCCore,
	                    present: @escaping (UIViewController) -> Bool,
	                    setBusy: @escaping (Bool) -> Void,
	                    completion: @escaping ([TrashRestoreItemOutcome]) -> Void) {
		let coordinator = TrashRestoreCoordinator(items: items, core: core, present: present, setBusy: setBusy, completion: completion)
		coordinator.retainSelf = coordinator
		coordinator.start()
	}

	private init(items: [OCItem],
	             core: OCCore,
	             present: @escaping (UIViewController) -> Bool,
	             setBusy: @escaping (Bool) -> Void,
	             completion: @escaping ([TrashRestoreItemOutcome]) -> Void) {
		self.items = items
		self.core = core
		self.present = present
		self.setBusy = setBusy
		self.completion = completion
	}

	private func start() {
		setBusy(true)
		scan(at: 0)
	}

	private func finish() {
		overlayTransitioningDelegate = nil
		presentedOverlay = nil
		let completion = self.completion
		let outcomes = self.outcomes
		retainSelf = nil
		completion(outcomes)
	}

	private func scan(at index: Int) {
		guard index < items.count else {
			beginResolving(at: 0)
			return
		}

		let item = items[index]
		if item.isPendingTrashItem {
			plans.append(Plan(item: item, action: .pending))
			scan(at: index + 1)
			return
		}

		TrashRestoreConflictChecker.conflictsAtDestination(for: item, connection: core.connection) { [weak self] conflicts in
			guard let self else { return }
			if conflicts, TrashRestoreConflictChecker.originalLocation(for: item) != nil {
				self.plans.append(Plan(item: item, action: .unresolved))
			} else {
				self.plans.append(Plan(item: item, action: .standard))
			}
			self.scan(at: index + 1)
		}
	}

	private func beginResolving(at index: Int) {
		if !didPauseForDialog, plans.contains(where: { if case .unresolved = $0.action { return true }; return false }) {
			didPauseForDialog = true
			setBusy(false)
		}
		resolve(at: index)
	}

	private func resolve(at index: Int) {
		guard index < plans.count else {
			beginExecution()
			return
		}

		guard case .unresolved = plans[index].action else {
			continueResolving(at: index + 1)
			return
		}

		let item = plans[index].item
		guard let originalPath = TrashRestoreConflictChecker.originalLocation(for: item) else {
			plans[index].action = .standard
			continueResolving(at: index + 1)
			return
		}

		if let policy {
			apply(policy, to: index, originalPath: originalPath)
			return
		}

		let remainingConflicts = plans[(index + 1)...].contains { plan in
			if case .unresolved = plan.action { return true }
			return false
		}
		presentDialog(for: item, showsApplyToAll: remainingConflicts) { [weak self] choice, applyToAll in
			guard let self else { return }
			if applyToAll {
				self.policy = choice
			}
			self.apply(choice, to: index, originalPath: originalPath)
		}
	}

	private func apply(_ choice: Choice, to index: Int, originalPath: String) {
		switch choice {
		case .skip:
			plans[index].action = .skipped
			continueResolving(at: index + 1)
		case .replace:
			if reservedPaths.contains(originalPath) {
				assignUniquePath(to: index, overwrite: false)
			} else {
				reservedPaths.insert(originalPath)
				plans[index].action = .replace
				continueResolving(at: index + 1)
			}
		case .keepBoth:
			assignUniquePath(to: index, overwrite: false)
		}
	}

	private func assignUniquePath(to index: Int, overwrite: Bool) {
		let item = plans[index].item
		TrashRestoreConflictChecker.firstAvailableRelativePath(for: item, connection: core.connection, reservedPaths: reservedPaths) { [weak self] path in
			guard let self else { return }
			if let path {
				self.reservedPaths.insert(path)
				self.plans[index].action = .webDAV(path: path, overwrite: overwrite)
			} else {
				self.plans[index].action = .unresolved
			}
			self.continueResolving(at: index + 1)
		}
	}

	private func continueResolving(at index: Int) {
		DispatchQueue.main.async { [weak self] in
			self?.resolve(at: index)
		}
	}

	private func presentDialog(for item: OCItem, showsApplyToAll: Bool, decision: @escaping (Choice, Bool) -> Void) {
		let fileName = TrashRestoreConflictChecker.displayName(for: item)
		let dialog = FileConflictDialogViewController(
			title: HCL10n.FileConflict.title,
			subtitle: FileConflictDialogViewController.subtitle(forFileName: fileName),
			choices: FileConflictDialogViewController.defaultChoices(),
			showsApplyToAll: showsApplyToAll
		) { [weak self] identifier, applyToAll in
			guard let self else { return }
			let choice = Self.choice(for: identifier)
			let finish = {
				decision(choice, applyToAll)
			}
			if let overlay = self.presentedOverlay {
				overlay.dismiss(animated: true, completion: finish)
			} else {
				finish()
			}
		}

		let overlay = AuthCardOverlayViewController(content: dialog)
		let animator = CrossDissolveTransitioningDelegate()
		overlay.transitioningDelegate = animator
		overlay.modalPresentationStyle = .custom
		overlayTransitioningDelegate = animator
		presentedOverlay = overlay

		if !present(overlay) {
			policy = .skip
			decision(.skip, true)
		}
	}

	private static func choice(for identifier: OCMessageChoiceIdentifier) -> Choice {
		if identifier == replaceIdentifier {
			return .replace
		}
		if identifier == keepBothIdentifier {
			return .keepBoth
		}
		return .skip
	}

	private func beginExecution() {
		let hasWork = plans.contains { plan in
			if case .skipped = plan.action { return false }
			return true
		}
		if didPauseForDialog && hasWork {
			setBusy(true)
		}
		execute(at: 0)
	}

	private func execute(at index: Int) {
		guard index < plans.count else {
			finish()
			return
		}

		let plan = plans[index]
		switch plan.action {
		case .skipped:
			outcomes.append(TrashRestoreItemOutcome(item: plan.item, error: nil, skipped: true))
			continueExecution(at: index + 1)
		case .pending:
			attempt(plan.item, at: index) { [weak self] completion in
				self?.core.restoreTrashedItem(plan.item) { error, _, _, _ in
					completion(error)
				}
			}
		case .standard:
			attempt(plan.item, at: index) { [weak self] completion in
				guard let self else {
					completion(nil)
					return
				}
				self.restoreDefault(plan.item, completion: completion)
			}
		case .replace:
			attempt(plan.item, at: index) { [weak self] completion in
				guard let self else {
					completion(nil)
					return
				}
				self.restoreReplacingExisting(plan.item, completion: completion)
			}
		case .webDAV(let path, let overwrite):
			attempt(plan.item, at: index) { [weak self] completion in
				guard let self else {
					completion(nil)
					return
				}
				_ = self.core.connection.restoreTrashedItem(plan.item, toRelativeFilesPath: path, overwrite: overwrite) { error in
					self.finishRestore(plan.item, error: error, completion: completion)
				}
			}
		case .unresolved:
			outcomes.append(TrashRestoreItemOutcome(item: plan.item, error: TrashErrorPresentation.nameConflictNSError, skipped: false))
			continueExecution(at: index + 1)
		}
	}

	private func continueExecution(at index: Int) {
		DispatchQueue.main.async { [weak self] in
			self?.execute(at: index)
		}
	}

	private func restoreDefault(_ item: OCItem, completion: @escaping (Error?) -> Void) {
		_ = core.connection.restoreTrashedItem(item) { [weak self] error in
			guard let self else {
				completion(error)
				return
			}
			self.finishRestore(item, error: error, completion: completion)
		}
	}

	/// Drive restore always uses the original name. Move the live item aside, restore, then drop every Trash entry that replace left behind.
	private func restoreReplacingExisting(_ item: OCItem, completion: @escaping (Error?) -> Void) {
		trashIdentities { [weak self] before in
			guard let self else {
				completion(nil)
				return
			}
			self.deleteDestinationItem(for: item) { deleteError, _ in
				if let deleteError, !Self.isItemNotFound(deleteError) {
					completion(deleteError)
					return
				}
				let didDeleteLiveItem = (deleteError == nil)
				self.restoreDefault(item) { restoreError in
					guard restoreError == nil else {
						completion(restoreError)
						return
					}
					self.removeReplaceLeftoversFromTrash(restored: item, idsBeforeDelete: before, expectDisplacedItem: didDeleteLiveItem, completion: completion)
				}
			}
		}
	}

	private func trashIdentities(completion: @escaping (Set<String>?) -> Void) {
		_ = core.connection.retrieveTrashedItems(completionHandler: { error, items in
			OnMainThread {
				guard error == nil, let items else {
					completion(nil)
					return
				}
				completion(Set(items.flatMap { Self.trashKeys($0) }))
			}
		})
	}

	/// Deletes Trash entries by trash URL. Matching the live file ID would permanently delete the restored file.
	private func removeReplaceLeftoversFromTrash(restored item: OCItem, idsBeforeDelete: Set<String>?, expectDisplacedItem: Bool, attempt: Int = 0, completion: @escaping (Error?) -> Void) {
		guard let path = TrashRestoreConflictChecker.originalLocation(for: item) else {
			completion(nil)
			return
		}

		let location = OCLocation(driveID: item.driveID, path: path)
		_ = core.connection.retrieveItemList(at: location, depth: 0, options: nil) { [weak self] error, foundItems in
			OnMainThread {
				guard let self else {
					completion(nil)
					return
				}
				guard error == nil, let foundItems, !foundItems.isEmpty else {
					completion(nil)
					return
				}

				self.core.connection.retrieveTrashedItems(completionHandler: { listError, trashItems in
					OnMainThread {
						guard listError == nil, let trashItems else {
							completion(nil)
							return
						}

						let restoredKeys = Self.trashKeys(item)
						let leftovers = trashItems.filter { candidate in
							let keys = Self.trashKeys(candidate)
							if !restoredKeys.isDisjoint(with: keys) {
								return true
							}
							guard let idsBeforeDelete, !keys.isEmpty else { return false }
							return keys.isDisjoint(with: idsBeforeDelete)
						}

						if leftovers.isEmpty, expectDisplacedItem, attempt < 2 {
							DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
								self.removeReplaceLeftoversFromTrash(restored: item, idsBeforeDelete: idsBeforeDelete, expectDisplacedItem: true, attempt: attempt + 1, completion: completion)
							}
							return
						}

						self.deleteTrashBinItems(leftovers, restoredKeys: restoredKeys, completion: completion)
					}
				})
			}
		}
	}

	private func deleteTrashBinItems(_ items: [OCItem], restoredKeys: Set<String>, completion: @escaping (Error?) -> Void) {
		guard let item = items.first else {
			completion(nil)
			return
		}

		let remainder = Array(items.dropFirst())
		let isRestoredItem = !restoredKeys.isDisjoint(with: Self.trashKeys(item))
		_ = core.connection.deleteTrashedItem(fromTrashBin: item) { [weak self] error in
			guard let self else {
				completion(nil)
				return
			}
			// The restored file keeps its file ID, so a graph purge of that ID would delete the live file.
			// A different Trash entry created by moving the old file aside can be purged by file ID.
			if error != nil, !isRestoredItem {
				_ = self.core.connection.permanentlyDeleteTrashedItem(item) { _ in
					self.deleteTrashBinItems(remainder, restoredKeys: restoredKeys, completion: completion)
				}
				return
			}
			self.deleteTrashBinItems(remainder, restoredKeys: restoredKeys, completion: completion)
		}
	}

	private static func trashKeys(_ item: OCItem) -> Set<String> {
		var keys = Set<String>()
		if let path = item.path, !path.isEmpty {
			var normalized = path
			while normalized.hasPrefix("/") {
				normalized.removeFirst()
			}
			while normalized.hasSuffix("/"), !normalized.isEmpty {
				normalized.removeLast()
			}
			if !normalized.isEmpty {
				keys.insert("path:" + normalized)
			}
		}
		if let fileID = item.fileID, !fileID.isEmpty {
			keys.insert("id:" + fileID)
		}
		return keys
	}

	private func deleteDestinationItem(for item: OCItem, completion: @escaping (Error?, String?) -> Void) {
		guard let path = TrashRestoreConflictChecker.originalLocation(for: item) else {
			completion(nil, nil)
			return
		}

		let location = OCLocation(driveID: item.driveID, path: path)
		_ = core.connection.retrieveItemList(at: location, depth: 0, options: nil) { [weak self] error, foundItems in
			OnMainThread {
				guard let self else {
					completion(error, nil)
					return
				}
				guard error == nil, let existing = foundItems?.first else {
					completion(nil, nil)
					return
				}

				if (existing.path ?? "").isEmpty {
					existing.path = path
				}
				if (existing.driveID ?? "").isEmpty {
					existing.driveID = item.driveID
				}

				let displacedFileID = existing.fileID
				let eventTarget = OCEventTarget(ephermalEventHandlerBlock: { event, _ in
					OnMainThread {
						completion(event.error, displacedFileID)
					}
				}, userInfo: nil, ephermalUserInfo: nil)
				_ = self.core.connection.delete(existing, requireMatch: false, resultTarget: eventTarget)
			}
		}
	}

	private static func isItemNotFound(_ error: Error) -> Bool {
		(error as NSError).isOCError(withCode: .itemNotFound)
	}

	private func finishRestore(_ item: OCItem, error: Error?, completion: @escaping (Error?) -> Void) {
		if let error {
			completion(error)
			return
		}
		core.removeTrashedItem(fromCache: item) { cacheError in
			completion(cacheError)
		}
	}

	private func attempt(_ item: OCItem, at index: Int, attemptCount: Int = 0, operation: @escaping (@escaping (Error?) -> Void) -> Void) {
		operation { [weak self] error in
			guard let self else { return }
			OnMainThread {
				if let error, attemptCount < 1, TrashErrorPresentation.isTransientLockError(error) {
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
						self.attempt(item, at: index, attemptCount: attemptCount + 1, operation: operation)
					}
					return
				}
				self.outcomes.append(TrashRestoreItemOutcome(item: item, error: error, skipped: false))
				self.continueExecution(at: index + 1)
			}
		}
	}
}
