public final class RunGate {
	private let q = DispatchQueue(label: "RunGate.lock")
	private var running = false

	/// Starts work if idle. Returns false if skipped.
	@discardableResult
	public func runIfIdle(_ work: @escaping (_ done: @escaping () -> Void) -> Void) -> Bool {
		var canStart = false
		q.sync {
			if !running {
				running = true
				canStart = true
			}
		}
		guard canStart else { return false }

		work { [weak self] in
			self?.q.async { self?.running = false }
		}
		return true
	}

	/// Resets the gate to idle state. Safe to call from any thread.
	public func reset() {
		q.async {
			self.running = false
		}
	}
}
