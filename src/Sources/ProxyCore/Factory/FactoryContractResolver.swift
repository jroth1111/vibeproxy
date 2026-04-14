import Foundation

public final class FactoryContractResolver {
    public struct WorkerBinding {
        public let canonicalModelID: String
        public let publicAlias: String
        public let requestModel: String

        public init(canonicalModelID: String, publicAlias: String, requestModel: String) {
            self.canonicalModelID = canonicalModelID
            self.publicAlias = publicAlias
            self.requestModel = requestModel
        }
    }

    public struct RescueMapping {
        public let retiredModelID: String
        public let currentModelID: String

        public init(retiredModelID: String, currentModelID: String) {
            self.retiredModelID = retiredModelID
            self.currentModelID = currentModelID
        }
    }

    private var workerBindings: [WorkerBinding] = []
    private var rescueMappings: [RescueMapping] = []

    public init() {}

    public func load(workerBindings: [WorkerBinding], rescueMappings: [RescueMapping]) {
        self.workerBindings = workerBindings
        self.rescueMappings = rescueMappings
    }

    public func resolveWorkerBinding(forModel model: String) -> WorkerBinding? {
        workerBindings.first { $0.canonicalModelID == model || $0.publicAlias == model }
    }

    public func rescueModelID(forRetired model: String) -> String? {
        rescueMappings.first { $0.retiredModelID == model }?.currentModelID
    }
}
