import UIKit

public enum HCColor {
	// Constant/Primary
	public static let green = UIColor(hexString: "#6EBD49FF")
	public static let white = UIColor(hexString: "#FFFFFFFF")
	public static let black = UIColor(hexString: "#000000FF")

	public enum Blue {
		// blue/blue darken-1
		static let darken1 = UIColor(hexString: "#1E88E5FF")
		// blue/blue darken-2
		static let darken2 = UIColor(hexString: "#1976D2FF")
		// blue/blue lighten-2
		static let lighten2 = UIColor(hexString: "#64B5F6FF")
		// blue/blue lighten-3
		static let lighten3 = UIColor(hexString: "#90CAF9FF")
	}

	public enum Grey {
		// grey/grey
		static let grey = UIColor(hexString: "#9E9E9EFF")
		// grey/grey darken-4
		static let darken4 = UIColor(hexString: "#212121FF")
		// grey/grey darken-3
		static let darken3 = UIColor(hexString: "#424242FF")
		// blue/grey lighten-3
		static let lighten3 = UIColor(hexString: "#EEEEEEFF")
	}

	public enum Transparencies {
		static let greyDarken3_12 = HCColor.Grey.darken3.withAlphaComponent(0.12)
		static let blueDarken1_12 = HCColor.Blue.darken1.withAlphaComponent(0.12)
		static let blueLighten3_12 = HCColor.Blue.lighten3.withAlphaComponent(0.12)
		static let white_12 = HCColor.white.withAlphaComponent(0.12)
		static let black_87 = HCColor.white.withAlphaComponent(0.87)
	}

	public enum Text {
		// text/Dark mode/Primary
		static let darkModePrimary = UIColor(hexString: "#FFFFFFFF")
		// text/Light mode/Primary
		static let lightModePrimary = HCColor.Transparencies.black_87
	}
}
