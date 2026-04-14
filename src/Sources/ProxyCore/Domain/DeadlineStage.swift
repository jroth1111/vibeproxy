public enum DeadlineStage: String {
    case none = "none"
    case firstResponse = "first_response"
    case bufferedResponse = "buffered_response"
    case interChunkRead = "inter_chunk_read"
}
