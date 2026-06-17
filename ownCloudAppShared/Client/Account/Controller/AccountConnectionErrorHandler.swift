//
//  AccountConnectionErrorHandler.swift
//  ownCloudAppShared
//
//  Created by Felix Schwarz on 28.11.22.
//  Copyright © 2022 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2022, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://owncloud.org/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

import UIKit
import ownCloudSDK

public protocol AccountAuthenticationHandlerBookmarkEditingHandler: AnyObject {
	func handleAuthError(for viewController: UIViewController, error: NSError, editBookmark: OCBookmark?, preferredAuthenticationMethods: [OCAuthenticationMethodIdentifier]?)
}

open class AccountConnectionErrorHandler: NSObject, AccountConnectionCoreErrorHandler {
	var connection: AccountConnection
	var consumer: AccountConnectionConsumer?
	var context: ClientContext

	init(for context: ClientContext, connection: AccountConnection? = nil) {
		self.context = context
		self.connection = connection ?? context.accountConnection!

		super.init()

		consumer = AccountConnectionConsumer(owner: self, coreErrorHandler: self)
		self.connection.add(consumer: consumer!)
	}

	deinit {
		connection.remove(consumer: consumer!)
	}

	public func account(connnection: AccountConnection, handleError error: Error?, issue inIssue: OCIssue?) -> Bool {
		var issue = inIssue
		var nsError = error as NSError?

		Log.debug("Received error \(nsError?.description ?? "nil")), issue \(issue?.description ?? "nil")")

		if let authError = issue?.authenticationError {
			// Turn issues that are just converted authorization errors back into errors and discard the issue
			nsError = authError
			issue = nil
		}

		Log.debug("Received error \(nsError?.description ?? "nil")), issue \(issue?.description ?? "nil")")

		if nsError?.isAccountConnectionAuthenticationError == true {
			return false
		} else {
			// Drive path switch / reprobe for transient network errors (timeouts, unreachable, etc.)
			if let reportError = error ?? nsError {
				HCContext.shared.deviceReachabilityService.reportOperationError(reportError)
			}
			// Intentionally suppress native ownCloud issue UI.
			// Connectivity/auth recovery is handled by Curator flows (banner + RA verification).
			Log.debug("[STX-RA]: Suppressing native ownCloud error UI.")
		}

		return true
	}
}
