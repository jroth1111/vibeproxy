import Foundation

enum NVIDIATransportProtocolPreference: String, Equatable {
    case http1Only
}

struct NVIDIAStreamSinkPolicy: Equatable {
    let emitsDownstreamKeepalives: Bool
    let keepaliveIntervalSeconds: TimeInterval
    let keepaliveComment: String

    static let buffered = NVIDIAStreamSinkPolicy(
        emitsDownstreamKeepalives: false,
        keepaliveIntervalSeconds: 0,
        keepaliveComment: "keepalive"
    )

    static let streamed = NVIDIAStreamSinkPolicy(
        emitsDownstreamKeepalives: true,
        keepaliveIntervalSeconds: 8,
        keepaliveComment: " keepalive"
    )
}

struct NVIDIATransportPolicy: Equatable {
    let protocolPreference: NVIDIATransportProtocolPreference
    let requestTimeoutSeconds: TimeInterval
    let resourceTimeoutSeconds: TimeInterval
    let interChunkReadTimeoutSeconds: TimeInterval
    let waitsForConnectivity: Bool
    let sinkPolicy: NVIDIAStreamSinkPolicy

    static let direct = NVIDIATransportPolicy(
        protocolPreference: .http1Only,
        requestTimeoutSeconds: 300,
        resourceTimeoutSeconds: 360,
        interChunkReadTimeoutSeconds: 300,
        waitsForConnectivity: true,
        sinkPolicy: .streamed
    )

    func scaledTimeoutBudget(
        scaleTimeout: (TimeInterval) -> TimeInterval
    ) -> (request: TimeInterval, resource: TimeInterval) {
        (
            request: scaleTimeout(requestTimeoutSeconds),
            resource: scaleTimeout(resourceTimeoutSeconds)
        )
    }
}
