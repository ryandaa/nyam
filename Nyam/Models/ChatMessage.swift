import Foundation

/// A single line in the coach conversation. `role` is the same shape the
/// Worker's `/chat` endpoint and OpenAI expect.
struct ChatMessage: Identifiable, Equatable {
    enum Role: String, Codable, Equatable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let text: String
    let date: Date

    init(id: UUID = UUID(), role: Role, text: String, date: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
    }
}
