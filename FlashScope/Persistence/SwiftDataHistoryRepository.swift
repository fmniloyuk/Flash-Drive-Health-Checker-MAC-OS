import Foundation
import FlashScopeCore
import SwiftData

@Model
final class HistoryRecord {
    @Attribute(.unique) var sessionID: UUID
    var timestamp: Date
    var driveIdentityHash: String
    var payload: Data

    init(sessionID: UUID, timestamp: Date, driveIdentityHash: String, payload: Data) {
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.driveIdentityHash = driveIdentityHash
        self.payload = payload
    }
}

@MainActor
final class SwiftDataHistoryRepository: HistoryRepository {
    let container: ModelContainer
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(inMemoryOnly: Bool = false) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemoryOnly)
        container = try ModelContainer(for: HistoryRecord.self, configurations: configuration)
        context = ModelContext(container)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func save(_ session: TestSession) async throws {
        let payload = try encoder.encode(session)
        let id = session.id
        let descriptor = FetchDescriptor<HistoryRecord>()
        if let existing = try context.fetch(descriptor).first(where: { $0.sessionID == id }) {
            existing.timestamp = session.timestamp
            existing.driveIdentityHash = session.driveIdentityHash
            existing.payload = payload
        } else {
            context.insert(HistoryRecord(sessionID: id, timestamp: session.timestamp, driveIdentityHash: session.driveIdentityHash, payload: payload))
        }
        try context.save()
    }

    func sessions(for driveIdentityHash: String) async throws -> [TestSession] {
        var descriptor = FetchDescriptor<HistoryRecord>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 500
        return try context.fetch(descriptor)
            .filter { $0.driveIdentityHash == driveIdentityHash }
            .compactMap { try? decoder.decode(TestSession.self, from: $0.payload) }
    }

    func delete(_ sessionID: UUID) async throws {
        let records = try context.fetch(FetchDescriptor<HistoryRecord>())
        if let record = records.first(where: { $0.sessionID == sessionID }) {
            context.delete(record)
            try context.save()
        }
    }

    func deleteAll() async throws {
        for record in try context.fetch(FetchDescriptor<HistoryRecord>()) {
            context.delete(record)
        }
        try context.save()
    }

    func prune(olderThan cutoff: Date) throws {
        for record in try context.fetch(FetchDescriptor<HistoryRecord>()) where record.timestamp < cutoff {
            context.delete(record)
        }
        try context.save()
    }
}
