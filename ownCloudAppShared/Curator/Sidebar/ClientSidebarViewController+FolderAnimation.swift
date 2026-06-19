import UIKit
import ownCloudSDK
import ownCloudApp

extension ClientSidebarViewController {

	// MARK: - Toggle

	func toggleFolder(_ entry: SidebarMenuEntry, accountController: AccountController?) {
		let isExpanded = expandedFolderRefs.contains { $0.isEqual(entry.itemReference) }
		if isExpanded {
			expandedFolderRefs.removeAll { $0.isEqual(entry.itemReference) }
			collapseFolder(entry, animated: true)
		} else {
			expandedFolderRefs.append(entry.itemReference)
			expandFolder(entry, accountController: accountController, animated: true)
		}
	}

	// MARK: - Expand

	func expandFolder(_ entry: SidebarMenuEntry, accountController: AccountController?, animated: Bool) {
		guard let children = entry.children, !children.isEmpty,
			  let parentContainer = rowContainersByItemRef[entry.itemReference],
			  let parentIndex = contentStackView.arrangedSubviews.firstIndex(of: parentContainer)
		else { return }

		rowViewsByItemRef[entry.itemReference]?.setDisclosureExpanded(true, animated: animated)

		var insertIndex = parentIndex + 1
		var insertedContainers: [UIView] = []

		for child in children {
			let container = makeRowContainer(for: child, accountController: accountController)
			if animated {
				container.isHidden = true
				container.alpha = 0
			}
			contentStackView.insertArrangedSubview(container, at: insertIndex)
			insertedContainers.append(container)
			insertIndex += 1
		}

		contentStackView.layoutIfNeeded()

		guard animated else {
			updateShouldShowDouble()
			return
		}

		animateFolderRows(insertedContainers, revealed: true, duration: MenuAnimation.expandDuration) { _ in
			self.updateShouldShowDouble()
		}
	}

	// MARK: - Collapse

	private func collapseFolder(_ entry: SidebarMenuEntry, animated: Bool) {
		var containersToRemove: [UIView] = []
		collectDescendantContainers(for: entry, into: &containersToRemove)

		rowViewsByItemRef[entry.itemReference]?.setDisclosureExpanded(false, animated: animated)

		guard !containersToRemove.isEmpty else {
			updateShouldShowDouble()
			return
		}

		let removeAll = {
			containersToRemove.forEach { self.removeRowContainer($0) }
			self.updateShouldShowDouble()
		}

		guard animated else {
			removeAll()
			return
		}

		animateFolderRows(containersToRemove, revealed: false, duration: MenuAnimation.collapseDuration) { _ in
			removeAll()
		}
	}

	// MARK: - Helpers

	func ensureFolderExpanded(_ itemReference: OCDataItemReference, accountController: AccountController) {
		guard !expandedFolderRefs.contains(where: { $0.isEqual(itemReference) }) else { return }
		let entries = SidebarMenuBuilder.entries(for: accountController, expandedFolderRefs: expandedFolderRefs)
		guard let folderEntry = entries.first(where: { $0.kind == .folder && $0.itemReference.isEqual(itemReference) }) else { return }
		expandedFolderRefs.append(itemReference)
		expandFolder(folderEntry, accountController: accountController, animated: false)
	}

	private func collectDescendantContainers(for entry: SidebarMenuEntry, into result: inout [UIView]) {
		guard let children = entry.children else { return }
		for child in children {
			if let container = rowContainersByItemRef[child.itemReference] {
				result.append(container)
			}
			if child.kind == .folder,
			   expandedFolderRefs.contains(where: { $0.isEqual(child.itemReference) }) {
				expandedFolderRefs.removeAll { $0.isEqual(child.itemReference) }
				collectDescendantContainers(for: child, into: &result)
			}
		}
	}

	private func removeRowContainer(_ container: UIView) {
		container.isHidden = false
		container.alpha = 1
		contentStackView.removeArrangedSubview(container)
		container.removeFromSuperview()
		if let itemRef = rowContainersByItemRef.first(where: { $0.value === container })?.key {
			rowContainersByItemRef.removeValue(forKey: itemRef)
			rowViewsByItemRef.removeValue(forKey: itemRef)
		}
	}

	func animateFolderRows(
		_ views: [UIView],
		revealed: Bool,
		duration: TimeInterval,
		completion: ((Bool) -> Void)? = nil
	) {
		UIView.animate(
			withDuration: duration,
			delay: 0,
			options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState],
			animations: {
				views.forEach {
					$0.isHidden = !revealed
					$0.alpha = revealed ? 1 : 0
				}
				self.contentStackView.layoutIfNeeded()
				self.scrollView.layoutIfNeeded()
			},
			completion: completion
		)
	}
}
