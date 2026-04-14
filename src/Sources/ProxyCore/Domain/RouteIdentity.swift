public struct RouteIdentity: Equatable {
    public let providerID: String
    public let canonicalModelID: String

    public init(providerID: String, canonicalModelID: String) {
        self.providerID = providerID
        self.canonicalModelID = canonicalModelID
    }

    public var routeHealthKey: String {
        "\(providerID)::\(canonicalModelID)"
    }
}
