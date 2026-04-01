import CLIProxyObjCBridge
import Foundation

/// Wraps `session.dataTask(with:completionHandler:)` in an ObjC exception catcher.
///
/// When URLSession has been invalidated (e.g. by a config refresh), creating a dataTask
/// throws `NSGenericException` with reason "Task created in a session that has been invalidated".
/// Swift cannot catch NSException directly, so we use an ObjC bridge.
enum SafeDataTask {
    struct ExceptionInfo {
        let name: String
        let reason: String
    }

    /// Creates a dataTask safely. Returns (task, nil) on success, or (nil, exceptionInfo) on NSException.
    static func create(
        on session: URLSession,
        with request: URLRequest,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> (URLSessionDataTask?, ExceptionInfo?) {
        var resultTask: URLSessionDataTask?
        var resultException: ExceptionInfo?

        let exception = CLIProxyCatchException {
            resultTask = session.dataTask(with: request, completionHandler: completionHandler)
        }

        if let exception {
            resultException = ExceptionInfo(
                name: exception["name"] as? String ?? "NSGenericException",
                reason: exception["reason"] as? String ?? "unknown"
            )
        }

        return (resultTask, resultException)
    }
}
