import Foundation

public enum ResetPasswordError: Error, Equatable {
	case badRequest
	case serverError
	case generic
	case validationFailed
}

public enum ResetPasswordErrorType: Equatable, Sendable {
	case badRequest
	case serverError
	case generic
}

extension ResetPasswordError {
	public var asErrorType: ResetPasswordErrorType {
		switch self {
			case .badRequest:
				return .badRequest
			case .serverError:
				return .serverError
			case .generic, .validationFailed:
				return .generic
		}
	}
}

public enum ResetPasswordHTTPStatusMapping {
	public static func mapError(statusCode: Int) -> ResetPasswordError? {
		switch statusCode {
			case 204:
				return nil
			case 400:
				return .badRequest
			case 500:
				return .serverError
			default:
				return .generic
		}
	}
}
