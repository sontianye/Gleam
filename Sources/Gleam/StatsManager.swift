import Foundation

/// Tracks smile statistics and persists them across launches.
actor StatsManager {

    // MARK: - Types

    struct DailyStat: Codable, Sendable {
        let date: String          // "yyyy-MM-dd"
        var smileCount: Int
        var peakHour: Int         // 0–23, hour with most smiles
        var hourBuckets: [Int]    // 24 buckets
    }

    // MARK: - State

    private var stats: [String: DailyStat] = [:]
    private let storeURL: URL

    // MARK: - Init

    init() {
        storeURL = URL.gleamSupportDirectory.appendingPathComponent("stats.json")
        // Inline load: same reasoning as PhotoManager — actor is not observable yet at init.
        if let data = try? Data(contentsOf: URL.gleamSupportDirectory.appendingPathComponent("stats.json")),
           let decoded = try? JSONDecoder().decode([String: DailyStat].self, from: data) {
            stats = decoded
        }
    }

    // MARK: - Public

    func recordSmile(at date: Date = Date()) {
        let key = Self.dayKey(from: date)
        let hour = Calendar.current.component(.hour, from: date)

        if stats[key] == nil {
            stats[key] = DailyStat(date: key, smileCount: 0, peakHour: hour, hourBuckets: Array(repeating: 0, count: 24))
        }
        stats[key]!.smileCount += 1
        stats[key]!.hourBuckets[hour] += 1
        stats[key]!.peakHour = stats[key]!.hourBuckets.enumerated().max(by: { $0.element < $1.element })?.offset ?? hour
        persist()
    }

    func todayCount() -> Int {
        stats[Self.dayKey(from: Date())]?.smileCount ?? 0
    }

    func weeklyCount(for date: Date = Date()) -> Int {
        let keys = weekKeys(for: date)
        return keys.compactMap { stats[$0]?.smileCount }.reduce(0, +)
    }

    func peakHourThisWeek(for date: Date = Date()) -> Int? {
        let keys = weekKeys(for: date)
        var combined = Array(repeating: 0, count: 24)
        for key in keys {
            guard let buckets = stats[key]?.hourBuckets else { continue }
            for (i, v) in buckets.enumerated() { combined[i] += v }
        }
        return combined.enumerated().max(by: { $0.element < $1.element })?.offset
    }

    func dailyStats(last days: Int) -> [DailyStat] {
        let calendar = Calendar.current
        return (0..<days).compactMap { offset -> DailyStat? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return stats[Self.dayKey(from: date)]
        }.reversed()
    }

    // MARK: - Private

    private static func dayKey(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func weekKeys(for date: Date) -> [String] {
        let calendar = Calendar.current
        return (0..<7).compactMap { offset -> String? in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: date) else { return nil }
            return Self.dayKey(from: d)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([String: DailyStat].self, from: data) else { return }
        stats = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        try? data.write(to: storeURL)
    }
}
