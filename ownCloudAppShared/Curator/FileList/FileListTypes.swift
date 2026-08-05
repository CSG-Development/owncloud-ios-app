import Foundation

enum FileListSupplementaryKind {
	static let spaceHeader = "file-list-space-header"
	static let statisticsFooter = "file-list-statistics-footer"
}

enum FileListSection: Int, CaseIterable {
	case zipOperations = 0
	case files = 1
}

enum FileListItemID {
	static let activity = "activity"
	static func isActivity(_ id: String) -> Bool { id == activity }
}

enum FileListContentState {
	case loading
	case empty
	case removed
	case hasContent
}
