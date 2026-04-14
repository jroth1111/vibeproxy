import Foundation

public enum ClientStreamingMode {
    case preserve
    case rejectBufferedMitigation
}

public enum ToolChoiceMode {
    case preserve
    case rejectRequiredOrFunctionChoice
}

public struct RequestPolicy {
    public let minimumMaxTokens: Int?
    public let maximumMaxTokens: Int?
    public let strippedFields: Set<String>
    public let attemptTimeout: TimeInterval?
    public let firstResponseDeadline: TimeInterval?
    public let bufferedResponseDeadline: TimeInterval?
    public let transportRetries: Int
    public let semanticRetries: Int
    public let retryableFailureClasses: Set<FailureClass>
    public let retryBackoffMilliseconds: Int
    public let stripsReasoningFieldFromSuccess: Bool
    public let allowsThinkLeakRepair: Bool
    public let salvagesBestEffortRepair: Bool
    public let clientStreamingMode: ClientStreamingMode
    public let toolChoiceMode: ToolChoiceMode
    public let forcesKimiInstantMode: Bool

    public init(
        minimumMaxTokens: Int?,
        maximumMaxTokens: Int?,
        strippedFields: Set<String>,
        attemptTimeout: TimeInterval?,
        firstResponseDeadline: TimeInterval?,
        bufferedResponseDeadline: TimeInterval?,
        transportRetries: Int,
        semanticRetries: Int,
        retryableFailureClasses: Set<FailureClass>,
        retryBackoffMilliseconds: Int,
        stripsReasoningFieldFromSuccess: Bool,
        allowsThinkLeakRepair: Bool,
        salvagesBestEffortRepair: Bool,
        clientStreamingMode: ClientStreamingMode,
        toolChoiceMode: ToolChoiceMode,
        forcesKimiInstantMode: Bool
    ) {
        self.minimumMaxTokens = minimumMaxTokens
        self.maximumMaxTokens = maximumMaxTokens
        self.strippedFields = strippedFields
        self.attemptTimeout = attemptTimeout
        self.firstResponseDeadline = firstResponseDeadline
        self.bufferedResponseDeadline = bufferedResponseDeadline
        self.transportRetries = transportRetries
        self.semanticRetries = semanticRetries
        self.retryableFailureClasses = retryableFailureClasses
        self.retryBackoffMilliseconds = retryBackoffMilliseconds
        self.stripsReasoningFieldFromSuccess = stripsReasoningFieldFromSuccess
        self.allowsThinkLeakRepair = allowsThinkLeakRepair
        self.salvagesBestEffortRepair = salvagesBestEffortRepair
        self.clientStreamingMode = clientStreamingMode
        self.toolChoiceMode = toolChoiceMode
        self.forcesKimiInstantMode = forcesKimiInstantMode
    }
}
