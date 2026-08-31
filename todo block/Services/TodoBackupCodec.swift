//
//  TodoBackupCodec.swift
//  todo block
//
//  Created by Codex on 2026/8/26.
//

import Foundation

/// 备份格式共用的定宽数字格式化：POSIX 区域、无分组、前导零补齐。
func todoBackupPadded(_ value: Int, minimumDigits: Int) -> String {
    value.formatted(
        .number
            .precision(.integerLength(minimumDigits))
            .grouping(.never)
            .locale(Locale(identifier: "en_US_POSIX"))
    )
}

enum TodoBackupCodec {
    static func encode(_ document: TodoBackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(TodoBackupTimestampCodec.encode(date))
        }
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> TodoBackupDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = TodoBackupTimestampCodec.decode(value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected UTC timestamp in yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSSZ format"
                )
            }
            return date
        }
        return try decoder.decode(TodoBackupDocument.self, from: data)
    }
}

private enum TodoBackupTimestampCodec {
    static func encode(_ date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: date
        )
        let year = todoBackupPadded(components.year ?? 0, minimumDigits: 4)
        let month = todoBackupPadded(components.month ?? 0, minimumDigits: 2)
        let day = todoBackupPadded(components.day ?? 0, minimumDigits: 2)
        let hour = todoBackupPadded(components.hour ?? 0, minimumDigits: 2)
        let minute = todoBackupPadded(components.minute ?? 0, minimumDigits: 2)
        let second = todoBackupPadded(components.second ?? 0, minimumDigits: 2)
        let nanosecond = todoBackupPadded(components.nanosecond ?? 0, minimumDigits: 9)
        return "\(year)-\(month)-\(day)T\(hour):\(minute):\(second).\(nanosecond)Z"
    }

    static func decode(_ value: String) -> Date? {
        guard
            value.count == 30,
            value.utf8.count == 30,
            value[value.index(value.startIndex, offsetBy: 4)] == "-",
            value[value.index(value.startIndex, offsetBy: 7)] == "-",
            value[value.index(value.startIndex, offsetBy: 10)] == "T",
            value[value.index(value.startIndex, offsetBy: 13)] == ":",
            value[value.index(value.startIndex, offsetBy: 16)] == ":",
            value[value.index(value.startIndex, offsetBy: 19)] == ".",
            value.last == "Z"
        else { return nil }

        func integer(_ range: Range<Int>) -> Int? {
            let lower = value.index(value.startIndex, offsetBy: range.lowerBound)
            let upper = value.index(value.startIndex, offsetBy: range.upperBound)
            return Int(value[lower ..< upper])
        }

        guard
            let year = integer(0 ..< 4),
            let month = integer(5 ..< 7),
            let day = integer(8 ..< 10),
            let hour = integer(11 ..< 13),
            let minute = integer(14 ..< 16),
            let second = integer(17 ..< 19),
            let nanosecond = integer(20 ..< 29),
            (1 ... 12).contains(month),
            (1 ... 31).contains(day),
            (0 ... 23).contains(hour),
            (0 ... 59).contains(minute),
            (0 ... 59).contains(second),
            (0 ... 999_999_999).contains(nanosecond)
        else { return nil }

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second,
            nanosecond: nanosecond
        )
        guard let date = calendar.date(from: components) else { return nil }
        let roundTrip = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        guard
            roundTrip.year == year,
            roundTrip.month == month,
            roundTrip.day == day,
            roundTrip.hour == hour,
            roundTrip.minute == minute,
            roundTrip.second == second
        else { return nil }
        return date
    }
}
