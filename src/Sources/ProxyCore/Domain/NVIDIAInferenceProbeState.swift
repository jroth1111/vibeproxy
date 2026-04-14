import Foundation

public struct NVIDIAInferenceProbeState: Equatable {
    public let lastProbeAt: Date
    public let lastStatus: NVIDIAInferenceProbeStatus
    public let lastSuccessAt: Date?
    public let lastFailureAt: Date?
    public let lastFailureClass: String?
    public let lastTimeoutStage: DeadlineStage
    public let lastUpstreamHTTPStatus: Int?
    public let lastTransportOutcome: String
    public let lastFirstByteLatencyMilliseconds: Int?
    public let lastTotalLatencyMilliseconds: Int?

    public init(
        lastProbeAt: Date,
        lastStatus: NVIDIAInferenceProbeStatus,
        lastSuccessAt: Date?,
        lastFailureAt: Date?,
        lastFailureClass: String?,
        lastTimeoutStage: DeadlineStage,
        lastUpstreamHTTPStatus: Int?,
        lastTransportOutcome: String,
        lastFirstByteLatencyMilliseconds: Int?,
        lastTotalLatencyMilliseconds: Int?
    ) {
        self.lastProbeAt = lastProbeAt
        self.lastStatus = lastStatus
        self.lastSuccessAt = lastSuccessAt
        self.lastFailureAt = lastFailureAt
        self.lastFailureClass = lastFailureClass
        self.lastTimeoutStage = lastTimeoutStage
        self.lastUpstreamHTTPStatus = lastUpstreamHTTPStatus
        self.lastTransportOutcome = lastTransportOutcome
        self.lastFirstByteLatencyMilliseconds = lastFirstByteLatencyMilliseconds
        self.lastTotalLatencyMilliseconds = lastTotalLatencyMilliseconds
    }
}
