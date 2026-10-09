import Foundation
import ScreenCaptureKit

// Only an explicit denial from the capture API requires the authorization flow.
// A legacy Core Graphics preflight result is diagnostic, not a capture result.
func requiresScreenCapturePermission(_ error: Error?) -> Bool {
    guard let error else { return false }
    let value = error as NSError
    return value.domain == SCStreamErrorDomain && value.code == SCStreamError.Code.userDeclined.rawValue
}
