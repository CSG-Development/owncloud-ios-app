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
		public static let gray825 = UIColor(hexString: "#3D3D3DFF")
		public static let gray800 = UIColor(hexString: "#4F4F4FFF")
		public static let gray700 = UIColor(hexString: "#5D5D5DFF")
		public static let gray600 = UIColor(hexString: "#6D6D6DFF")
		public static let gray400 = UIColor(hexString: "#B0B0B0FF")
		public static let gray350 = UIColor(hexString: "#B8B8B8FF")
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

	public static let green = Green.green400
	public static let white = Neutral.white
	public static let black = Neutral.black

	public enum Grey {
		public static let grey = Neutral.medium
		public static let darken4 = Neutral.grayDarken4
		public static let darken3 = Neutral.grayDarken3
		public static let lighten3 = Neutral.gray150
	}

	public enum Transparencies {
		public static let greyDarken3_12 = Neutral.grayDarken3.withAlphaComponent(0.12)
		public static let white_12 = Neutral.white.withAlphaComponent(0.12)
		public static let black_87 = Neutral.black.withAlphaComponent(0.87)
		public static let green400_10 = Green.green400.withAlphaComponent(CGFloat(0x1A) / 255.0)
		public static let green400_12 = Green.green400.withAlphaComponent(0.12)
		public static let green400_20 = Green.green400.withAlphaComponent(0.20)
		public static let green300_12 = Green.green300.withAlphaComponent(0.12)
		public static let green300_20 = Green.green300.withAlphaComponent(0.20)
		public static let green500_20 = Green.green500.withAlphaComponent(0.20)
		public static let green700_12 = Green.green700.withAlphaComponent(0.12)
	}

	public enum Text {
		public static let darkModePrimary = Neutral.white
		public static let lightModePrimary = Transparencies.black_87

		public static func secondary(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#FFFFFFB2") : UIColor(hexString: "#00000099")
		}
	}

	public enum Content {
		public static func border(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#616161FF") : UIColor(hexString: "#CBCDD3FF")
		}

		public static func border2(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#616161FF") : UIColor(hexString: "#E0E0E0FF")
		}

		public static func textPrimary(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#FFFFFFDE") : UIColor(hexString: "#000000DE")
		}

		public static func textPrimaryInverted(_ isDark: Bool) -> UIColor {
			textPrimary(!isDark)
		}

		public static func textSecondary(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#FFFFFFB2") : UIColor(hexString: "#00000099")
		}

		public static func labels(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#FFFFFFCC") : UIColor(hexString: "#000000CC")
		}

		public static func gray2(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#B2B2B2FF") : UIColor(hexString: "#7A7A7AFF")
		}
		public static let gray3 = UIColor(hexString: "#B2B2B2FF")

		public static func disabledBackground(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#616161FF") : Neutral.gray150
		}

		public static func sliderBackground(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#616161FF") : UIColor(hexString: "#E0E0E0FF")
		}

		public static func iconBackground(_ isDark: Bool) -> UIColor {
			isDark ? Green.green300.withAlphaComponent(0.24) : Green.green700.withAlphaComponent(0.12)
		}
	}

	public enum Symbolic {
		public static func error(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#F28F8CFF") : UIColor(hexString: "#F44336FF")
		}
		public static func errorBackgroundTransparent(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#F28F8C3D") : UIColor(hexString: "#F443361F")
		}
		public static func errorBackgroundOpaque(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#3B100DFF") : UIColor(hexString: "#FEE8E7FF")
		}
	}

	public enum Interaction {
		public static func cta(_: Bool) -> UIColor {
			Green.green400
		}

		public static func ctaHighlighted(_ isDark: Bool) -> UIColor {
			isDark ? Green.green300 : Green.green400.darker(0.10)
		}

		public static func link(_ isDark: Bool) -> UIColor {
			Green.link(isDark)
		}

		public static func linkHighlighted(_: Bool) -> UIColor {
			Green.green400
		}

		public static func linkTransparent12(_ isDark: Bool) -> UIColor {
			isDark ? Transparencies.green300_12 : Transparencies.green700_12
		}

		public static func primarySolidNormal(_ isDark: Bool) -> UIColor {
			link(isDark)
		}

		public static func primarySolidNormalInverted(_ isDark: Bool) -> UIColor {
			link(!isDark)
		}

		public static func primaryTransparentNormal20(_: Bool) -> UIColor {
			Transparencies.green400_20
		}

		public static func primaryTransparentNormal12(_ isDark: Bool) -> UIColor {
			isDark ? Neutral.gray150.withAlphaComponent(0.12) : Transparencies.green700_12
		}

		public static func secondaryTransparentPressed12(_ isDark: Bool) -> UIColor {
			isDark ? Transparencies.green300_12 : Neutral.grayDarken3.withAlphaComponent(0.12)
		}

		public static func secondaryLabel(_ isDark: Bool) -> UIColor {
			isDark ? Neutral.grayDarken4 : Neutral.white
		}

		public static func destructiveSolidNormal(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#F2918AFF") : UIColor(hexString: "#A02A21FF")
		}

		public static func buttonsPrimarySolidOutlined(_ isDark: Bool) -> UIColor {
			link(isDark)
		}

		public static func primaryTransparentHover(_: Bool) -> UIColor {
			Transparencies.green300_20
		}

		public static func primaryTransparentPressed(_: Bool) -> UIColor {
			Transparencies.green500_20
		}

		public enum Buttons {
			public enum Primary {
				public static func solidNormal(_: Bool) -> UIColor {
					Green.green400
				}

				public static func solidHover(_: Bool) -> UIColor {
					Green.green300
				}

				public static func solidPressed(_: Bool) -> UIColor {
					Green.green200
				}

				public static func solidDisabled(_: Bool) -> UIColor {
					Neutral.gray100
				}
			}

			public enum Secondary {}
		}
	}

	public enum Structure {
		public static func appBackground(_ isDark: Bool) -> UIColor {
			isDark ? Neutral.gray800 : Neutral.gray200
		}

		public static func barBackground(_ isDark: Bool) -> UIColor {
			isDark ? Neutral.gray900 : Neutral.gray100
		}

		public static func menuBackground(_ isDark: Bool) -> UIColor {
			barBackground(isDark)
		}

		public static func cardBackground(_ isDark: Bool) -> UIColor {
			isDark ? Neutral.gray825 : Neutral.white
		}

		public static func whiteBackground(_ isDark: Bool) -> UIColor {
			isDark ? Neutral.black : Neutral.white
		}

		public static func snackbarBackground(_ isDark: Bool) -> UIColor {
			isDark ? Neutral.gray350 : Neutral.grayDarken4
		}

		public static func buttonBorderNormal(_ isDark: Bool) -> UIColor {
			isDark ? Neutral.gray350 : Neutral.gray600
		}
	}

	public enum Mockups {
		public static func overlayDefault(_: Bool) -> UIColor {
			Neutral.black.withAlphaComponent(0.50)
		}
	}

	public enum Constant {
		public static func primary(_: Bool) -> UIColor {
			Green.green400
		}

		public static func white(_: Bool) -> UIColor {
			Neutral.white
		}
	}
}
