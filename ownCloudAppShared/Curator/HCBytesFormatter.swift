public final class HCBytesFormatter {
	public static func formatBytesIEC(_ bytes: Int64, decimals: Int = 1) -> String {
		let units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"]
		let sign = bytes < 0 ? "-" : ""
		var value = Double(abs(bytes))
		var i = 0
		while value >= 1024, i < units.count - 1 {
			value /= 1024
			i += 1
		}
		if i == 0 { return "\(sign)\(Int(value)) \(units[i])" }
		return "\(sign)\(String(format: "%.\(decimals)f", value)) \(units[i])"
	}
}
