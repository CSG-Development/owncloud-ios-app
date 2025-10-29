import Network

private func ntop(family: Int32, bytes: Data, capacity: Int32) -> String? {
	var buf = [CChar](repeating: 0, count: Int(capacity))
	return bytes.withUnsafeBytes { p in
		guard inet_ntop(family, p.baseAddress, &buf, socklen_t(capacity)) != nil else { return nil }
		return String(cString: buf)
	}
}

public extension IPv4Address {
	var string: String? {
		ntop(family: AF_INET, bytes: rawValue, capacity: Int32(INET_ADDRSTRLEN))
	}
}

public extension IPv6Address {	
	var string: String? {
		ntop(family: AF_INET6, bytes: rawValue, capacity: Int32(INET6_ADDRSTRLEN))
	}
}
