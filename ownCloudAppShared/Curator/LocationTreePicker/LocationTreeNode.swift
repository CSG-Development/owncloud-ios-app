import ownCloudSDK

struct LocationTreeNode {
	enum State {
		case idle
		case loading
		case loaded
		case failed(Error)

		var isLoading: Bool {
			if case .loading = self { return true }
			return false
		}
	}

	let id: OCPath
	let parentID: OCPath?
	let title: String
	let state: State
	let childrenIDs: [OCPath]?
}
