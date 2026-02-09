struct OnboardingPage: Equatable {
	let imageNameLight: String
	let imageNameDark: String
	let installAppImageNameLight: String?
	let installAppImageNameDark: String?
	let title: String
	let subtitle: String

	init(
		imageNameLight: String,
		imageNameDark: String,
		installAppImageNameLight: String? = nil,
		installAppImageNameDark: String? = nil,
		title: String, subtitle: String
	) {
		self.imageNameLight = imageNameLight
		self.imageNameDark = imageNameDark
		self.installAppImageNameLight = installAppImageNameLight
		self.installAppImageNameDark = installAppImageNameDark
		self.title = title
		self.subtitle = subtitle
	}
}
