import Foundation

public struct SmartAliasDefinition: Equatable {
    public let alias: String
    public let requestClass: String
    public let failover: String
    public let candidates: [String]
    public let healthSensitivity: HealthSensitivity

    public init(alias: String, requestClass: String, failover: String, candidates: [String], healthSensitivity: HealthSensitivity) {
        self.alias = alias
        self.requestClass = requestClass
        self.failover = failover
        self.candidates = candidates
        self.healthSensitivity = healthSensitivity
    }
}
