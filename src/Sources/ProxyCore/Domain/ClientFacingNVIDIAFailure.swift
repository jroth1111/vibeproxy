public struct ClientFacingNVIDIAFailure {
    public let statusCode: Int
    public let message: String
    public let reasonCode: String?

    public init(statusCode: Int, message: String, reasonCode: String? = nil) {
        self.statusCode = statusCode
        self.message = message
        self.reasonCode = reasonCode
    }
}
