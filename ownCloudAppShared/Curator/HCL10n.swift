public enum HCL10n {
	public enum Common {
		public static let ok = "OK"
		public static let cancel = "Cancel"
	}

	public enum Logo {
		public static let firstPart = "Personal Cloud "
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
			public static let title = "Welcome to Personal Cloud Files"
			public static let subtitle = "Securely upload, manage, and share your files with Personal Cloud Files, your private gateway to personal storage.\n\nWhether you're organizing files or sharing documents with family and friends, Personal Cloud Files keeps your data safe with simple access."
		}
		public enum Step_SyncFiles {
			public static let title = "Sync your files to Personal Cloud"
			public static let subtitle = "Use the desktop app to upload files directly from your computer to Personal Cloud Files.\n\nEnsure your files are synced and backed up to Personal Cloud for easy access across all your devices."
		}
		public enum Step_FileDeduplication {
			public static let title = "File deduplication"
			public static let subtitle = "Identify and manage duplicate files uploaded to your account.\n\nSee exactly how many copies exist and access them all from the Duplicates page."
		}
		public enum Step_Search {
			public static let title = "Quickly find what you need"
			public static let subtitle = "Search files on Personal Cloud by name, date, type, size, and folder."
		}
		public enum Step_SecureSharing {
			public static let title = "Secure sharing made simple"
			public static let subtitle = "Share files and folders securely with family and friends. You can control access by setting expiration dates for shared links so that files remain private over time."
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
		public enum Login {
			public static let loadingViewTitle = "Logging in to your account"
			public static let incorrectEmailPassword = "Incorrect email or password"
			public static let invalidEmail = "Please enter a valid email address"
			public static let connectionError = "Connection error. Unable to reach the server."
			public static let notAllowedEmailError = "Not allowed. Contact the device owner"

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
			public static let detectingDevices = "Detecting devices..."
			public static let noDeviceDetected = "No device detected"
		}

		public enum UnableToConnect {
			public static let navbarTitle = "Unable to connect"

			public static let headerText = "We are unable to detect the Personal Cloud device. Please ensure the following:"
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
			public static let description = "We have sent a one-time code to authorize this device to access your Personal Cloud. Check your email for the code and enter it here. If you do not see it in your inbox, please check your spam folder."

			public static let allowAccessButtonTitle = "Allow access"
			public static let resendCodeButtonTitle = "Resend code"
			public static let skipButtonTitle = "Skip"

			public static let invalidCodeError = "Incorrect code."
			public static let codeExpiredError = "Your code has expired."
			public static let tooManyRequestsError = "Too many requests."
			public static let connectionError = "Connection error. Unable to reach the server."
		}

		public enum Code500 {
			public static let title = "Unable to connect"
			public static let description = "Could not reach your Personal Cloud."
			public static let cancelButtonTitle = "Cancel"
			public static let retryButtonTitle = "Retry"
		}
		public enum CodeUnknownEmail {
			public static let title = "Email not registered"
			public static let description = "This email isn’t authorized to access this device. Please contact the owner."
			public static let cancelButtonTitle = "OK"
		}

		public enum TooManyRequests {
			public static let title = "Access to Personal Cloud"
			public static let description = "There have been too many attempts for access within the last minute. Please wait at least two minutes before retrying."
			public static let cancelButtonTitle = "OK"
		}

		public enum DevOptions {
			public static let title = "Developer options"
			public static let deviceTextFieldTitle = "Static device"
			public static let deviceTextFieldInvalidURLError = "Invalid URL"
			public static let settingsSwitchLabel = "Display settings on login"
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
