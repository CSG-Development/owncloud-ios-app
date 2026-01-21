public enum HCL10n {
	public enum Common {
		public static let ok = "OK"
		public static let cancel = "Cancel"
	}

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

	public enum Auth {

		public enum OldLogin {
			public static let loadingViewTitle = "Logging in to your account"
			public static let incorrectEmailPassword = "Incorrect email or password"

			public enum EmailField {
				public static let title = "Email"
				public static let placeholder = "Enter email address"
			}
			public enum AddressField {
				public static let title = "Connecting to"
				public static let placeholder = "No device detected"
			}
			public enum PasswordField {
				public static let title = "Password"
				public static let placeholder = "Password"
			}
			public static let loginButtonTitle = "Login"
			public static let resetPasswordButtonTitle = "Reset Password"
			public static let serverNotFoundError = "An error ocurred while connecting to the server."
		}

		public enum Login {
			public static let loadingViewTitle = "Logging in to your account"
			public static let incorrectEmailPassword = "Incorrect email or password"
			public static let invalidEmail = "Please enter a valid email address"
			public static let connectionError = "Connection error. Unable to reach the server."

			public enum EmailField {
				public static let title = "Email"
				public static let placeholder = "Email"
			}

			public enum PasswordField {
				public static let title = "Password"
				public static let placeholder = "Password"
			}

			public enum DeviceDropdownField {
				public static let title = "Connecting to"
				public static let placeholder = "No device detected"
			}

			public static let loginButtonTitle = "Login"
			public static let nextButtonTitle = "Next"
			public static let resetPasswordButtonTitle = "Reset Password"
			public static let oldLoginButtonTitle = "Old login path"
			public static let detectingDevices = "Detecting devices..."
			public static let noDeviceDetected = "No device detected"
		}

		public enum UnableToConnect {
			public static let navbarTitle = "Unable to connect"

			public static let headerText = "We are unable to detect the Curator device. Please ensure the following:"
			public static let point1 = "Verify that the device is properly connected to the network and that the internet connection is stable"
			public static let point2 = "Make sure the device is powered on and functioning correctly"
			public static let point3 = "Check firewall settings to confirm they are not blocking the connection"
			public static let point4 = "If using a wireless connection, confirm the device is within range of the router"
			public static let point5 = "Your device and mobile phone must be on the same network"
			public static let footerText = "If you continue to experience issues, please contact our Support team for further assistance."
			public static let footerLinkText = "Support team"
			public static let retryButtonTitle = "Retry"
		}

		public enum UnableToDetect {
			public static let navbarTitle = "Unable to detect"

			public static let headerText = "We are unable to detect your device. Please ensure the following:"
			public static let point1 = "Verify that Personal Cloud is properly connected to your home network"
			public static let point2 = "Confirm that your internet has access to the web"
			public static let point3 = "Make sure Personal Cloud is powered on"
			public static let point4 = "Confirm that there are no firewall settings that block access to the internet"
			public static let point5 = "If Personal Cloud is attempting to connect via Wi-Fi, confirm that it is in range of your home router"
			public static let point6 = "Personal Cloud and your mobile device must be on the same network during the initial setup"
			public static let footerText = "If you continue to experience issues, please contact our Support team for further assistance."
			public static let footerLinkText = "Support team"
			public static let retryButtonTitle = "Retry"
		}

		public enum CodeVerification {
			public static let title = "Allow remote access"
			public static let description = "We have sent a one-time code to authorize this device to access your Curator. Check your email for the code and enter it here. If you do not see it in your inbox, please check your spam folder."

			public static let allowAccessButtonTitle = "Allow access"
			public static let resendCodeButtonTitle = "Resend code"
			public static let skipButtonTitle = "Skip"

			public static let invalidCodeError = "Incorrect code."
			public static let codeExpiredError = "Your code has expired."
			public static let emailNotRegisteredError = "Not allowed. Contact the device owner."
			public static let tooManyRequestsError = "Too many requests."
			public static let connectionError = "Connection error. Unable to reach the server."
		}
	}

	public enum Sharing {
		public static let sharingNotPossible = "Sharing not possible"
		public static let raNotAvilableDescription = "Sharing is not possible because remote access is not available."
		public static let publicNotAvilableDescription = "Sharing is not possible because the public link is unavailable."
	}

	public enum TrustPrompt {
		public static let title = "Untrusted server"
		public static let messageFormat = "Do you want to trust the server at %@?"
		public static let trust = "Trust"
	}
}
