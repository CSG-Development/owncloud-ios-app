import UIKit

public enum HCColor {
	// Constant/Primary
	public static let green = UIColor(hexString: "#6EBD49FF")
	public static let white = UIColor(hexString: "#FFFFFFFF")
	public static let black = UIColor(hexString: "#000000FF")

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
		// grey/grey
		public static let grey = UIColor(hexString: "#9E9E9EFF")
		// grey/grey darken-4
		public static let darken4 = UIColor(hexString: "#212121FF")
		// grey/grey darken-3
		public static let darken3 = UIColor(hexString: "#424242FF")
		// blue/grey lighten-3
		public static let lighten3 = UIColor(hexString: "#EEEEEEFF")
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
	}

	public enum Content {
		// Content/Border
		public static let border = UIColor(hexString: "#CBCDD3FF")
		//Content/Text primary
		public static func textPrimary(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#FFFFFFDE") : UIColor(hexString: "#000000DE")
		}
	}

	public enum Structure {
		// Structure/App Background
		public static let appBackground = UIColor(hexString: "#F0F1F5FF")
		// Structure/Menu Background
		public static func menuBackground(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#1D1E21FF") : UIColor(hexString: "#FFFFFFFF")
		}
	}

	public enum Interaction {
		// Interaction/Secondary Label
		public static func secondaryLabel(_ isDark: Bool) -> UIColor {
			isDark ? UIColor(hexString: "#212121FF") : UIColor(hexString: "#FFFFFFFF")
		}
	}
}
