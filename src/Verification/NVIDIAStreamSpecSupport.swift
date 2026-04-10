import Foundation

final class NVIDIAStreamFailureRecorder {
    private(set) var failures: [String] = []

    func recordFailure(_ message: String) {
        failures.append(message)
    }

    func finish() {
        guard failures.isEmpty else {
            failures.forEach { fputs("FAIL: \($0)\n", stderr) }
            exit(1)
        }
    }
}

func runNVIDIAStreamSpec(
    _ name: String,
    recorder: NVIDIAStreamFailureRecorder,
    _ body: () throws -> Void
) {
    do {
        try body()
        print("PASS: \(name)")
    } catch {
        recorder.recordFailure("\(name): threw unexpected error \(error)")
    }
}

func expectNVIDIAEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ message: String,
    recorder: NVIDIAStreamFailureRecorder
) {
    guard actual == expected else {
        recorder.recordFailure("\(message) — expected \(expected), got \(actual)")
        return
    }
}

func expectNVIDIATrue(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    recorder: NVIDIAStreamFailureRecorder
) {
    guard condition() else {
        recorder.recordFailure(message)
        return
    }
}
