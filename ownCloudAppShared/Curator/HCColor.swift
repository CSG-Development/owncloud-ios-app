import UIKit

public enum HCColor {
	public static let clear = UIColor.clear

	/// Unique Seagate green tokens. Each hex is defined once.
	public enum Green {
		/// Seagate green 200
		public static let green200 = UIColor(hexString: "#A9E196FF")
		/// Seagate green 300
		public static let green300 = UIColor(hexString: "#8CD873FF")
		/// Seagate green 400
		public static let green400 = UIColor(hexString: "#6EBE49FF")
		/// Seagate green 500
		public static let green500 = UIColor(hexString: "#55A72FFF")
		/// Seagate green 700
		public static let green700 = UIColor(hexString: "#2F743CFF")

		public static func cta(_: Bool) -> UIColor { green400 }
		public static func link(_ isDark: Bool) -> UIColor { isDark ? green300 : green700 }
	}

	/// Unique neutral tokens. Each hex is defined once.
	public enum Neutral {
		public static let white = UIColor(hexString: "#FFFFFFFF")
		public static let black = UIColor(hexString: "#000000FF")
		public static let gray900 = UIColor(hexString: "#191919FF")
		public static let gray850 = UIColor(hexString: "#2C2C2CFF")
		public static let gray800 = UIColor(hexString: "#4F4F4FFF")
		public static let gray700 = UIColor(hexString: "#5D5D5DFF")
		public static let gray600 = UIColor(hexString: "#6D6D6DFF")
		public static let gray400 = UIColor(hexString: "#B0B0B0FF")
		public static let gray300 = UIColor(hexString: "#D1D1D1FF")
		public static let gray200 = UIColor(hexString: "#E7E7E7FF")
		public static let gray150 = UIColor(hexString: "#EEEEEEFF")
		public static let gray100 = UIColor(hexString: "#F6F6F6FF")
		public static let grayDarken3 = UIColor(hexString: "#424242FF")
		public static let grayDarken4 = UIColor(hexString: "#212121FF")
		public static let medium = UIColor(hexString: "#9E9E9EFF")

		public static func disabledFill(_ isDark: Bool) -> UIColor {
			isDark ? gray100.withAlphaComponent(0.30) : gray900.withAlphaComponent(0.20)
		}
	}

	// Constant/Primary
	public static let green = Green.green400
	public static let white = Neutral.white
	public static let black = Neutral.black

	public enum Blue {
		// blue/blue darken-1
		public static let darken1 = UIColor(hexString: "#1E88E5FF")
		// blue/blue darken-2
		public static let darken2 = UIColor(hexString: "#1976D2FF")
		// blue/blue lighten-2
		public static let lighten2 = UIColor(hexString: "#64B5F6FF")
		// blue/blue lighten-3
		public static let lighten3 = UIColor(hexString: "#90CAF9FF")
	}

	public enum Grey {
		public static let grey = Neutral.medium
		public static let darken4 = Neutral.grayDarken4
		public static let darken3 = Neutral.grayDarken3
		public static let lighten3 = Neutral.gray150
	}

	public enum Transparencies {
		public static let greyDarken3_12 = HCColor.Grey.darken3.withAlphaComponent(0.12)
		public static let blueDarken1_12 = HCColor.Blue.darken1.withAlphaComponent(0.12)
		public static let blueLighten3_12 = HCColor.Blue.lighten3.withAlphaComponent(0.12)
		public static let white_12 = HCColor.white.withAlphaComponent(0.12)
		public static let black_87 = HCColor.black.withAlphaComponent(0.87)
	}

	public enum Text {
		// text/Dark mode/Primary
		public static let darkModePrimary = UIColor(hexString: "#FFFFFFFF")
		// text/Light mode/Primary
		public static let lightModePrimary = HCColor.Transparencies.black_87

		// Content/Text secondary
		public static func secondary(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#FFFFFFB2") : UIColor(hexString: "#00000099")
		}
	}

	public enum Content {
		// Content/Border
		public static func border(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#616161FF") : UIColor(hexString: "#CBCDD3FF")
		}

		// Content/Border 2
		public static func border2(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#616161FF") : UIColor(hexString: "#E0E0E0FF")
		}

		// Content/Text primary
		public static func textPrimary(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#FFFFFFDE") : UIColor(hexString: "#000000DE")
		}

		// Content/Text primary inverted
		public static func textPrimaryInverted(_ isDark: Bool) -> UIColor {
			textPrimary(!isDark)
		}

		// Content/Text secondary
		public static func textSecondary(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#FFFFFFB2") : UIColor(hexString: "#00000099")
		}

		// Content/Labels
		public static func labels(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#FFFFFFCC") : UIColor(hexString: "#000000CC")
		}

		// Content/Gray 2
		public static func gray2(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#B2B2B2FF") : UIColor(hexString: "#7A7A7AFF")
		}
		public static let gray3 = UIColor(hexString: "#B2B2B2FF")

		// Content/Disabled BG
		public static func disabledBackground(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#616161FF") : UIColor(hexString: "#EEEEEEFF")
		}

		// Content/SliderBG
		public static func sliderBackground(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#616161FF") : UIColor(hexString: "#E0E0E0FF")
		}

		// Content/Icon Background
		public static func iconBackground(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#64B5F63D") : UIColor(hexString: "#1976D21F")
		}
	}

    public enum Symbolic {
        // Symbolic/Error
        public static func error(_ isDark: Bool) -> UIColor {
            isDark ? UIColor(hexString: "#F28F8CFF") : UIColor(hexString: "#F44336FF")
        }
		// Symbolic/Error Background Transparent
		public static func errorBackgroundTransparent(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#F28F8C3D") : UIColor(hexString: "#F443361F")
		}
		// Symbolic/Error Background Opaque
		public static func errorBackgroundOpaque(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#3B100DFF") : UIColor(hexString: "#FEE8E7FF")
		}
    }

	public enum Interaction {
		// Interaction/Primary Solid Normal
		public static func primarySolidNormal(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#64B5F6FF") : UIColor(hexString: "#1976D2FF")
		}

		// Interaction/Primary Solid Normal inverted
		public static func primarySolidNormalInverted(_ isDark: Bool) -> UIColor {
			primarySolidNormal(!isDark)
		}

		// Interaction/Primary Transparent Normal 20
		public static func primaryTransparentNormal20(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#64B5F63D") : UIColor(hexString: "#1976D233")
		}

		// Interaction/Primary Transparent Normal 12
		public static func primaryTransparentNormal12(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#EEEEEE1F") : UIColor(hexString: "#1976D21F")
		}

		// Interaction/Secondary Transparent Pressed 12
		public static func secondaryTransparentPressed12(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#64B5F61F") : UIColor(hexString: "#4242421F")
		}

		// Interaction/Secondary Label
		public static func secondaryLabel(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#212121FF") : UIColor(hexString: "#FFFFFFFF")
		}
		// Interaction/Destructive Solid Normal
		public static func destructiveSolidNormal(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#F2918AFF") : UIColor(hexString: "#A02A21FF")
		}

		// Interaction/Buttons Primary Solid Outlined
		public static func buttonsPrimarySolidOutlined(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#64B5F6FF") : UIColor(hexString: "#1976D2FF")
		}
	}

	public enum Structure {
		// Structure/App Background
		public static func appBackground(_ isDark: Bool) -> UIColor {
			isDark ? Neutral.gray800 : Neutral.gray200
		}
		// Structure/Menu Background
		public static func menuBackground(_ isDark: Bool) -> UIColor {
			isDark ? Neutral.gray900 : Neutral.gray100
		}
		// Structure/Card Background
		public static func cardBackground(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#262729FF") : UIColor(hexString: "#FFFFFFFF")
		}
		// Structure/White Background
		public static func whiteBackground(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#000000FF") : UIColor(hexString: "#FFFFFFFF")
		}

		// Structure/Snackbar Background
		public static func snackbarBackground(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#B8B8B8FF") : UIColor(hexString: "#212121FF")
		}
	}
	public enum Mockups {
		// Mockups/Overlay default
		public static func overlayDefault(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#00000080") : UIColor(hexString: "#00000080")
		}
	}

	public enum Constant {
		// Constant/Primary
		public static func primary(_: Bool) -> UIColor {
			Green.green400
		}

		// Constant/white
		public static func white(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#FFFFFFFF") : UIColor(hexString: "#FFFFFFFF")
		}
	}
}
