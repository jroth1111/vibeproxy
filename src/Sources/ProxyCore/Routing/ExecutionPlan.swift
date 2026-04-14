import Foundation

public enum ExecutionStageMode {
    case serial
    case race
    case hedge
}

public struct ExecutionStage {
    public let candidateModel: String
    public let routeIdentity: RouteIdentity
    public let mode: ExecutionStageMode
    public let isNVIDIA: Bool
    public let healthScore: Double

    public init(
        candidateModel: String,
        routeIdentity: RouteIdentity,
        mode: ExecutionStageMode = .serial,
        isNVIDIA: Bool = false,
        healthScore: Double = 500.0
    ) {
        self.candidateModel = candidateModel
        self.routeIdentity = routeIdentity
        self.mode = mode
        self.isNVIDIA = isNVIDIA
        self.healthScore = healthScore
    }
}

public struct ExecutionPlan {
    public let stages: [ExecutionStage]
    public let alias: String?
    public let failoverDepth: Int

    public init(stages: [ExecutionStage], alias: String? = nil, failoverDepth: Int = 0) {
        self.stages = stages
        self.alias = alias
        self.failoverDepth = failoverDepth
    }

    public var serialStages: [ExecutionStage] {
        stages.filter { $0.mode == .serial }
    }

    public var raceGroups: [[ExecutionStage]] {
        var groups: [[ExecutionStage]] = []
        var currentGroup: [ExecutionStage] = []
        for stage in stages {
            if stage.mode == .race {
                currentGroup.append(stage)
            } else {
                if !currentGroup.isEmpty {
                    groups.append(currentGroup)
                    currentGroup = []
                }
            }
        }
        if !currentGroup.isEmpty { groups.append(currentGroup) }
        return groups
    }

    public var isEmpty: Bool { stages.isEmpty }
}
