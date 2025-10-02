public enum HCL10n {
	public enum Logo {
		public static let firstPart = "Curator "
		public static let secondPart = "Files"
	}

	public enum Welcome {
		public static let startSetupButtonTitle = "Start setup"
		public static let settingsButtonTitle = "Settings"
	}

	public enum Onboarding {
		public static let doneButtonTitle = "Done"
		public static let skipButtonTitle = "Skip"

		public enum Step_ManageFiles {
			public static let title = "Manage all your synced files"
			public static let subtitle = "You can move, copy, delete. You can move, copy, delete.You can move, copy, delete.You can move, copy, delete. You can move, copy, delete"
		}
		public enum Step_ShareFiles {
			public static let title = "Share files and folders"
			public static let subtitle = "You can share privately or publicly. You can share privately or publicly. You can share privately or publicly. You can share privately or publicly"
		}
		public enum Step_MultiAccount {
			public static let title = "Multi account"
			public static let subtitle = "Connect to all your owncloud Servers. Connect to all your owncloud Servers. Connect to all your owncloud Servers. Connect to all your owncloud Servers"
		}
		public enum Step_CameraUploads {
			public static let title = "Camera uploads"
			public static let subtitle = "Your pictures/videos automatically uploaded. Your pictures/videos automatically uploaded. Your pictures/videos automatically uploaded. Your pictures/videos automatically uploaded"
		}
		public enum Step_VideoStreaming {
			public static let title = "Video streaming"
			public static let subtitle = "Play your videos without downloding them. Play your videos without downloding them. Play your videos without downloding them. Play your videos without downloding them"
		}
	}

	public enum Sidebar {
		public static let storageSpace = "Storage space"
		public static func used(_ a: String, of b: String) -> String { "\(a) of \(b) used" }
		public static let unlimitedSpace = "Unlimited space"
		public static let signOut = "Sign out"
	}

	public enum TabBar {
		public static let files = "Files"
		public static let search = "Search"
		public static let status = "Status"
		public static let offline = "Offline"
	}

	public enum Search {
		public enum Empty {
			public static let title = "Search for your files"
		}
	}

	public enum Offline {
		public enum Empty {
			public static let title = "No files available offline"
			public static let subtitle = "Files and folders you mark as available offline will show up here."
		}
	}

	public enum ImageCropAction {
		public static let name = "Crop/rotate image"

		public enum SaveAlert {
			public static let title = "Save File"
			public static let overwrite = "Overwrite original"
			public static let saveACopy = "Save as copy"
			public static let discard = "Discard changes"
		}
	}
}
