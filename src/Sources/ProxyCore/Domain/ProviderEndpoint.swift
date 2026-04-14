public struct ProviderEndpoint: Equatable {
    public let providerID: String
    public let baseURL: String
    public let proxyURL: String
    public let apiKey: String?

    public init(providerID: String, baseURL: String, proxyURL: String, apiKey: String?) {
        self.providerID = providerID
        self.baseURL = baseURL
        self.proxyURL = proxyURL
        self.apiKey = apiKey
    }
}
