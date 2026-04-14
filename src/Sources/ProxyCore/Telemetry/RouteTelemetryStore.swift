import Foundation

public final class RouteTelemetryStore {
    private var events: [RouteTelemetryEvent] = []
    private let maxEventsPerRoute: Int
    private let maxGlobalEvents: Int
    private let queue = DispatchQueue(label: "io.automaze.vibeproxy.telemetry-store")

    public init(maxEventsPerRoute: Int = 100, maxGlobalEvents: Int = 10000) {
        self.maxEventsPerRoute = maxEventsPerRoute
        self.maxGlobalEvents = maxGlobalEvents
    }

    public func record(_ event: RouteTelemetryEvent) {
        queue.sync {
            events.append(event)
            if events.count > maxGlobalEvents {
                events.removeFirst(events.count - maxGlobalEvents)
            }
        }
    }

    public func recentEvents(limit: Int = 50) -> [RouteTelemetryEvent] {
        queue.sync {
            Array(events.suffix(limit))
        }
    }

    public func eventsForRoute(canonicalModelID: String, limit: Int = 20) -> [RouteTelemetryEvent] {
        queue.sync {
            let filtered = events.filter { $0.canonicalModelID == canonicalModelID }
            return Array(filtered.suffix(limit))
        }
    }

    public func clear() {
        queue.sync { events.removeAll() }
    }
}
