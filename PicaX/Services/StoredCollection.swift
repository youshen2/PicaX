import Combine
import Foundation

/// Small user-created collections, included in settings backups through the picax. prefix.
@MainActor
final class StoredCollection<Record: Codable & Identifiable>: ObservableObject {
    @Published private(set) var records: [Record] = []
    private let key: String
    private let defaults: UserDefaults
    private var storedData: Data?
    private var observation: AnyCancellable?

    init(key: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
        reload()
        observation = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
    }

    // Avoid Swift 6.3.3's Release optimizer crash in synthesized generic deinitializers.
    // Cleanup only releases stored properties and needs no actor-isolated work.
    nonisolated deinit {}

    func put(_ record: Record) {
        var next = records
        if let index = next.firstIndex(where: { $0.id == record.id }) {
            next[index] = record
        } else {
            next.insert(record, at: 0)
        }
        save(next)
    }

    func remove(_ record: Record) { save(records.filter { $0.id != record.id }) }

    static func merging(existing: Data, imported: Data) -> Data? {
        guard let current = try? JSONDecoder().decode([Record].self, from: existing),
              let incoming = try? JSONDecoder().decode([Record].self, from: imported) else { return nil }
        var ids = Set(current.map(\.id))
        return try? JSONEncoder().encode(current + incoming.filter { ids.insert($0.id).inserted })
    }

    private func save(_ records: [Record]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        storedData = data
        defaults.set(data, forKey: key)
        self.records = records
    }

    private func reload() {
        let data = defaults.data(forKey: key)
        guard data != storedData else { return }
        storedData = data
        records = data.flatMap { try? JSONDecoder().decode([Record].self, from: $0) } ?? []
    }
}
