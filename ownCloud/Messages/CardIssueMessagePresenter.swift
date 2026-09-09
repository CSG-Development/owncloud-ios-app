//
//  CardIssueMessagePresenter.swift
//  ownCloud
//
//  Created by Felix Schwarz on 26.03.20.
//  Copyright © 2020 ownCloud GmbH. All rights reserved.
//

/*
    10| * Copyright (C) 2020, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://owncloud.org/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

import UIKit
import ownCloudSDK
import ownCloudAppShared

class CardIssueMessagePresenter: OCMessagePresenter {

	typealias CardIssueMessagePresenterViewControllerPresenter = (UIViewController) -> Void

	var bookmarkUUID : OCBookmarkUUID
	var presenter : CardIssueMessagePresenterViewControllerPresenter
	/// Presents a centered Curator overlay dialog (used for name-conflict keep-both messages).
	var overlayPresenter : CardIssueMessagePresenterViewControllerPresenter?

	var isShowingCard : Bool = false
	var oneCardLimit : Bool

	private var overlayTransitioningDelegate: CrossDissolveTransitioningDelegate?

	init(with bookmarkUUID: OCBookmarkUUID, limitToSingleCard: Bool, presenter: @escaping CardIssueMessagePresenterViewControllerPresenter, overlayPresenter: CardIssueMessagePresenterViewControllerPresenter? = nil) {
		self.bookmarkUUID = bookmarkUUID
		self.oneCardLimit = limitToSingleCard
		self.presenter = presenter
		self.overlayPresenter = overlayPresenter

		super.init()

		self.identifier = OCMessagePresenterIdentifier(rawValue: "card.\(bookmarkUUID.uuidString)")
	}

	override func presentationPriority(for message: OCMessage) -> OCMessagePresentationPriority {
		guard message.localizedTitle != nil,
		      let messageBookmarkUUID = message.bookmarkUUID,
		      let bookmarkUUID = bookmarkUUID as UUID?,
		      messageBookmarkUUID == bookmarkUUID else {
			return .wontPresent
		}

		// Name conflicts use the overlay dialog; never stack a second card on top.
		if FileConflictDialogViewController.isKeepBothConflict(message) {
			if !oneCardLimit || !isShowingCard {
				return .high
			}
			return .wontPresent
		}

		if !oneCardLimit || !isShowingCard {
			return .high
		}

		return .wontPresent
	}

	override func present(_ message: OCMessage, completionHandler: @escaping (OCMessagePresentationResult, OCMessageChoice?) -> Void) {
		if FileConflictDialogViewController.isKeepBothConflict(message), overlayPresenter != nil {
			presentFileConflictDialog(message, completionHandler: completionHandler)
			return
		}

		presentLegacyAlertCard(message, completionHandler: completionHandler)
	}

	private func presentFileConflictDialog(_ message: OCMessage, completionHandler: @escaping (OCMessagePresentationResult, OCMessageChoice?) -> Void) {
		let title = message.localizedTitle ?? HCL10n.FileConflict.title
		let subtitle = message.localizedDescription ?? ""
		let choices = FileConflictDialogViewController.orderedChoices(from: message)
		let similarMessages = similarKeepBothMessages(for: message)
		let showsApplyToAll = similarMessages.count > 1

		weak var presentedOverlay: UIViewController?

		let dialog = FileConflictDialogViewController(
			title: title,
			subtitle: subtitle,
			choices: choices,
			showsApplyToAll: showsApplyToAll
		) { [weak self] choiceIdentifier, applyToAll in
			guard let self else { return }

			let selected = message.choice(withIdentifier: choiceIdentifier)

			if applyToAll {
				for similar in similarMessages where similar.uuid != message.uuid {
					if let choice = similar.choice(withIdentifier: choiceIdentifier) {
						OCMessageQueue.global.resolveMessage(similar, with: choice)
					}
				}
			}

			let finish: () -> Void = {
				self.isShowingCard = false
				self.overlayTransitioningDelegate = nil
				completionHandler(.didPresent, selected)
				OCMessageQueue.global.setNeedsMessageHandling()
			}

			if let presentedOverlay {
				presentedOverlay.dismiss(animated: true, completion: finish)
			} else {
				finish()
			}
		}

		let overlay = AuthCardOverlayViewController(content: dialog)
		let animator = CrossDissolveTransitioningDelegate()
		overlay.transitioningDelegate = animator
		overlay.modalPresentationStyle = UIModalPresentationStyle.custom
		self.overlayTransitioningDelegate = animator
		presentedOverlay = overlay

		self.isShowingCard = true
		self.overlayPresenter?(overlay)
	}

	private func similarKeepBothMessages(for message: OCMessage) -> [OCMessage] {
		guard let category = message.categoryIdentifier else {
			return [message]
		}

		let bookmarkUUID = message.bookmarkUUID
		return OCMessageQueue.global.messages.filter { candidate in
			guard FileConflictDialogViewController.isKeepBothConflict(candidate),
			      candidate.categoryIdentifier == category else {
				return false
			}

			if let bookmarkUUID, let candidateUUID = candidate.bookmarkUUID {
				return candidateUUID == bookmarkUUID
			}

			return true
		}
	}

	private func presentLegacyAlertCard(_ message: OCMessage, completionHandler: @escaping (OCMessagePresentationResult, OCMessageChoice?) -> Void) {
		var options : [AlertOption] = []

		if let choices = message.choices {
			for choice in choices {
				let option = AlertOption(label: choice.label, type: choice.type, handler: { [weak self] (_, _) in
					self?.isShowingCard = false
					completionHandler(.didPresent, choice)
				})

				options.append(option)
			}
		}

		if options.count == 0 {
			options.append(AlertOption(label: OCLocalizedString("OK", nil), type: .default, handler: { [weak self] (_, _) in
				self?.isShowingCard = false
				completionHandler(.didPresent, nil)
			}))
		}

		if let localizedTitle = message.localizedTitle {
			var localizedHeader : String?

			if let messageBookmarkUUID = message.bookmarkUUID, (bookmarkUUID as UUID) != messageBookmarkUUID {
				if let messageBookmark = OCBookmarkManager.shared.bookmark(for: messageBookmarkUUID) {
					localizedHeader = messageBookmark.shortName
				}
			}

			let alertViewController = AlertViewController(localizedHeader: localizedHeader, localizedTitle: localizedTitle, localizedDescription: message.localizedDescription ?? "", options: options, dismissHandler: { [weak self] in
				self?.isShowingCard = false
				completionHandler(.didPresent, nil)
			})

			self.isShowingCard = true

			self.presenter(alertViewController)
		}
	}
}
