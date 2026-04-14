import Foundation

public struct RequestShape: Equatable {
    public enum HTTPMethod: String {
        case GET, POST, PUT, DELETE, PATCH
    }
    public enum StreamMode {
        case streaming, buffered
    }
    public enum ContentClass {
        case plainText
        case typedContent
        case multimodal
        case empty
    }

    public let method: HTTPMethod
    public let path: String
    public let surface: String
    public let model: String?
    public let streamMode: StreamMode
    public let toolsCount: Int
    public let toolChoice: String?
    public let contentClass: ContentClass
    public let hasMedia: Bool

    public init(
        method: HTTPMethod,
        path: String,
        surface: String,
        model: String? = nil,
        streamMode: StreamMode = .buffered,
        toolsCount: Int = 0,
        toolChoice: String? = nil,
        contentClass: ContentClass = .plainText,
        hasMedia: Bool = false
    ) {
        self.method = method
        self.path = path
        self.surface = surface
        self.model = model
        self.streamMode = streamMode
        self.toolsCount = toolsCount
        self.toolChoice = toolChoice
        self.contentClass = contentClass
        self.hasMedia = hasMedia
    }

    public var isWorker: Bool {
        surface == "worker" || model == "worker"
    }

    public var isStreaming: Bool {
        streamMode == .streaming
    }

    public var hasTools: Bool {
        toolsCount > 0
    }

    public var descriptor: String {
        let stream = isStreaming ? "stream" : "buffered"
        let tools = hasTools ? "+\(toolsCount)tools" : ""
        let content = contentClass == .typedContent ? "+typed" : ""
        return "\(method.rawValue):\(surface):\(stream)\(tools)\(content)"
    }
}
