public struct RouteLatencyDiagnostics: Equatable {
    public let averageFirstByteLatencyMilliseconds: Int?
    public let p95FirstByteLatencyMilliseconds: Int?
    public let averageTotalLatencyMilliseconds: Int?
    public let p95TotalLatencyMilliseconds: Int?
    public let slowFirstByteThresholdMilliseconds: Int?
    public let slowTotalThresholdMilliseconds: Int?
    public let pressureStatus: String

    public init(
        averageFirstByteLatencyMilliseconds: Int?,
        p95FirstByteLatencyMilliseconds: Int?,
        averageTotalLatencyMilliseconds: Int?,
        p95TotalLatencyMilliseconds: Int?,
        slowFirstByteThresholdMilliseconds: Int?,
        slowTotalThresholdMilliseconds: Int?,
        pressureStatus: String
    ) {
        self.averageFirstByteLatencyMilliseconds = averageFirstByteLatencyMilliseconds
        self.p95FirstByteLatencyMilliseconds = p95FirstByteLatencyMilliseconds
        self.averageTotalLatencyMilliseconds = averageTotalLatencyMilliseconds
        self.p95TotalLatencyMilliseconds = p95TotalLatencyMilliseconds
        self.slowFirstByteThresholdMilliseconds = slowFirstByteThresholdMilliseconds
        self.slowTotalThresholdMilliseconds = slowTotalThresholdMilliseconds
        self.pressureStatus = pressureStatus
    }
}
