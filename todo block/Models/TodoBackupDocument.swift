//
//  TodoBackupDocument.swift
//  todo block
//
//  Created by Codex on 2026/8/26.
//

import Foundation

/// 与设备时区无关的日历日期。JSON 中固定编码为 yyyy-MM-dd。
nonisolated struct TodoBackupCalendarDate: Codable, Equatable, Hashable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year ?? 1
        self.month = components.month ?? 1
        self.day = components.day ?? 1
    }

    func date(in calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
            .map { calendar.startOfDay(for: $0) }
    }

    var canonicalString: String {
        let year = todoBackupPadded(year, minimumDigits: 4)
        let month = todoBackupPadded(month, minimumDigits: 2)
        let day = todoBackupPadded(day, minimumDigits: 2)
        return "\(year)-\(month)-\(day)"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard
            parts.count == 3,
            parts[0].count == 4,
            parts[1].count == 2,
            parts[2].count == 2,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2]),
            (1 ... 12).contains(month),
            (1 ... 31).contains(day)
        else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected calendar date in yyyy-MM-dd format"
            )
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid calendar date"
            )
        }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid calendar date"
            )
        }

        self.init(year: year, month: month, day: day)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(canonicalString)
    }
}

nonisolated struct TodoBackupItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let indentLevel: Int
    let sortOrder: Double
    let containerKind: TodoContainerKind
    let dayDate: TodoBackupCalendarDate
    let createdAt: Date
    let updatedAt: Date
}

nonisolated struct TodoBackupDaySection: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let date: TodoBackupCalendarDate
    let title: String
    let sortOrder: Double
    let createdAt: Date
    let updatedAt: Date
}

/// Todo Block 的权威全量备份文档。
nonisolated struct TodoBackupDocument: Codable, Equatable, Sendable {
    static let formatIdentifier = "todo-block-backup"
    static let currentVersion = 1

    let format: String
    let version: Int
    let exportedAt: Date
    let items: [TodoBackupItem]
    let daySections: [TodoBackupDaySection]

    init(
        format: String = Self.formatIdentifier,
        version: Int = Self.currentVersion,
        exportedAt: Date,
        items: [TodoBackupItem],
        daySections: [TodoBackupDaySection]
    ) {
        self.format = format
        self.version = version
        self.exportedAt = exportedAt
        self.items = items
        self.daySections = daySections
    }
}
