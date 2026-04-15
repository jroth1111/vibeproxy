import Foundation

public struct RouteTelemetryEvent: Equatable {
    public let timestamp: Date
    public let requestModel: String
    public let requestedAlias: String?
    public let canonicalModelID: String
    public let transportOutcome: String
    public let healthTransition: String?
    public let attemptLane: Int
    public let winnerAttemptLane: Int?
    public let failoverDepth: Int?
    public let finalWinnerRequestModel: String?
    public let failureClass: String?
    public let timeoutStage: DeadlineStage
    public let upstreamHTTPStatus: Int?
    public let retryCount: Int
    public let source: String
    public let firstByteLatencyMilliseconds: Int?
    public let totalLatencyMilliseconds: Int?
    public let inflightAtRequest: Int?
    public let proxyRequestID: String?
    public let callerRequestID: String?
    public let callerSessionID: String?
    public let requestShape: String?
    public let negotiatedApplicationProtocol: String?
    public let errorBodySnippet: String?
    public let terminalOutcomeMarker: String?
    public let failoverChain: String?
    public let firstSelectedCandidate: String?

    public init(
        timestamp: Date,
        requestModel: String,
        requestedAlias: String? = nil,
        canonicalModelID: String,
        transportOutcome: String,
        healthTransition: String? = nil,
        attemptLane: Int = 1,
        winnerAttemptLane: Int? = nil,
        failoverDepth: Int? = nil,
        finalWinnerRequestModel: String? = nil,
        failureClass: String?,
        timeoutStage: DeadlineStage,
        upstreamHTTPStatus: Int?,
        retryCount: Int,
        source: String,
        firstByteLatencyMilliseconds: Int? = nil,
        totalLatencyMilliseconds: Int? = nil,
        inflightAtRequest: Int? = nil,
        proxyRequestID: String? = nil,
        callerRequestID: String? = nil,
        callerSessionID: String? = nil,
        requestShape: String? = nil,
        negotiatedApplicationProtocol: String? = nil,
        errorBodySnippet: String? = nil,
        terminalOutcomeMarker: String? = nil,
        failoverChain: String? = nil,
        firstSelectedCandidate: String? = nil
    ) {
        self.timestamp = timestamp
        self.requestModel = requestModel
        self.requestedAlias = requestedAlias
        self.canonicalModelID = canonicalModelID
        self.transportOutcome = transportOutcome
        self.healthTransition = healthTransition
        self.attemptLane = attemptLane
        self.winnerAttemptLane = winnerAttemptLane
        self.failoverDepth = failoverDepth
        self.finalWinnerRequestModel = finalWinnerRequestModel
        self.failureClass = failureClass
        self.timeoutStage = timeoutStage
        self.upstreamHTTPStatus = upstreamHTTPStatus
        self.retryCount = retryCount
        self.source = source
        self.firstByteLatencyMilliseconds = firstByteLatencyMilliseconds
        self.totalLatencyMilliseconds = totalLatencyMilliseconds
        self.inflightAtRequest = inflightAtRequest
        self.proxyRequestID = proxyRequestID
        self.callerRequestID = callerRequestID
        self.callerSessionID = callerSessionID
        self.requestShape = requestShape
        self.negotiatedApplicationProtocol = negotiatedApplicationProtocol
        self.errorBodySnippet = errorBodySnippet
        self.terminalOutcomeMarker = terminalOutcomeMarker
        self.failoverChain = failoverChain
        self.firstSelectedCandidate = firstSelectedCandidate
    }
}
