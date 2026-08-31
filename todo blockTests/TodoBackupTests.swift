//
//  TodoBackupTests.swift
//  todo blockTests
//
//  Created by Codex on 2026/8/26.
//

import SwiftData
import XCTest
@testable import todo_block

final class TodoBackupCodecTests: XCTestCase {
    func testRoundTripPreservesCompleteBackupDocument() throws {
        let exportedAt = Date(timeIntervalSince1970: 1_787_727_371.1234567)
        let createdAt = Date(timeIntervalSince1970: 1_787_000_000.9876543)
        let updatedAt = Date(timeIntervalSince1970: 1_787_100_000.456789)
        let itemID = try XCTUnwrap(
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")
        )
        let sectionID = try XCTUnwrap(
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")
        )
        let calendarDate = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let document = TodoBackupDocument(
            exportedAt: exportedAt,
            items: [
                TodoBackupItem(
                    id: itemID,
                    title: "Parent",
                    isCompleted: true,
                    indentLevel: 2,
                    sortOrder: 42.5,
                    containerKind: .scheduled,
                    dayDate: calendarDate,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            ],
            daySections: [
                TodoBackupDaySection(
                    id: sectionID,
                    date: calendarDate,
                    title: "Release day",
                    sortOrder: 7.25,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            ]
        )

        let data = try TodoBackupCodec.encode(document)
        let decoded = try TodoBackupCodec.decode(data)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.format, TodoBackupDocument.formatIdentifier)
        XCTAssertEqual(decoded.version, TodoBackupDocument.currentVersion)
        XCTAssertTrue(json.contains(#""containerKind" : "scheduled""#))
    }

    func testCalendarDateRemainsSameDayAcrossTimeZones() throws {
        let backupDate = TodoBackupCalendarDate(year: 2026, month: 8, day: 26)
        let document = TodoBackupDocument(
            exportedAt: Date(timeIntervalSince1970: 1_787_727_371),
            items: [
                TodoBackupItem(
                    id: UUID(),
                    title: "Cross timezone",
                    isCompleted: false,
                    indentLevel: 0,
                    sortOrder: 1,
                    containerKind: .scheduled,
                    dayDate: backupDate,
                    createdAt: Date(timeIntervalSince1970: 1_787_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_787_100_000)
                )
            ],
            daySections: []
        )

        let data = try TodoBackupCodec.encode(document)
        let decoded = try TodoBackupCodec.decode(data)
        let decodedDate = try XCTUnwrap(decoded.items.first?.dayDate)

        var singapore = Calendar(identifier: .gregorian)
        singapore.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Singapore"))
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

        let singaporeDate = try XCTUnwrap(decodedDate.date(in: singapore))
        let losAngelesDate = try XCTUnwrap(decodedDate.date(in: losAngeles))
        XCTAssertEqual(
            singapore.dateComponents([.year, .month, .day], from: singaporeDate),
            DateComponents(year: 2026, month: 8, day: 26)
        )
        XCTAssertEqual(
            losAngeles.dateComponents([.year, .month, .day], from: losAngelesDate),
            DateComponents(year: 2026, month: 8, day: 26)
        )
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("2026-08-26"))
    }

    func testMalformedNonASCIITimestampIsRejectedWithoutCrashing() {
        let multiByteCharacter = "a\u{301}\u{301}\u{301}\u{301}\u{301}\u{301}"
        let malformedTimestamp = "0000-00-00T00:00:\(multiByteCharacter)"
        XCTAssertEqual(malformedTimestamp.utf8.count, 30)
        XCTAssertLessThan(malformedTimestamp.count, 20)
        let json = """
        {
          "format": "todo-block-backup",
          "version": 1,
          "exportedAt": "\(malformedTimestamp)",
          "items": [],
          "daySections": []
        }
        """

        XCTAssertThrowsError(try TodoBackupCodec.decode(Data(json.utf8)))
    }

    func testUnknownContainerKindIsRejectedDuringDecode() {
        let json = """
        {
          "format": "todo-block-backup",
          "version": 1,
          "exportedAt": "2026-08-26T00:00:00.000000000Z",
          "items": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "title": "Unsupported container",
              "isCompleted": false,
              "indentLevel": 0,
              "sortOrder": 1,
              "containerKind": "archived",
              "dayDate": "2026-08-26",
              "createdAt": "2026-08-26T00:00:00.000000000Z",
              "updatedAt": "2026-08-26T00:00:00.000000000Z"
            }
          ],
          "daySections": []
        }
        """

        XCTAssertThrowsError(try TodoBackupCodec.decode(Data(json.utf8)))
    }
}

@MainActor
final class TodoBackupWorkflowTests: XCTestCase {
    private var modelContainer: ModelContainer?

    override func setUp() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TodoItem.self,
            DaySection.self,
            configurations: configuration
        )
        modelContainer = container
        TodoStore.shared.reset()
        TodoStore.shared.initialize(with: container.mainContext)
    }

    override func tearDown() async throws {
        TodoStore.shared.reset()
        modelContainer = nil
    }

    func testExportUsesLatestInMemoryFullBackupDataEvenWhenSaveStatusIsUnsaved() throws {
        let store = TodoStore.shared
        let scheduledDate = try makeDate(year: 2026, month: 8, day: 26, hour: 12)
        let longTermDate = try makeDate(year: 2026, month: 7, day: 3, hour: 12)
        let createdAt = Date(timeIntervalSince1970: 1_787_000_000.1234567)
        let updatedAt = Date(timeIntervalSince1970: 1_787_100_000.7654321)
        let exportedAt = Date(timeIntervalSince1970: 1_787_727_371.2345678)

        let scheduled = store.createItem(
            title: "Ship backup",
            isCompleted: true,
            dayDate: scheduledDate,
            indentLevel: 2
        )
        scheduled.sortOrder = 123.5
        scheduled.createdAt = createdAt
        scheduled.updatedAt = updatedAt

        let longTerm = store.createItem(
            title: "Long term",
            dayDate: longTermDate,
            containerKind: .longTermImportant
        )
        longTerm.sortOrder = 456.75
        longTerm.createdAt = createdAt.addingTimeInterval(10)
        longTerm.updatedAt = updatedAt.addingTimeInterval(10)

        let section = try XCTUnwrap(store.validDaySections.first)
        section.title = "Backup day"
        section.sortOrder = 88.25
        section.createdAt = createdAt.addingTimeInterval(20)
        section.updatedAt = updatedAt.addingTimeInterval(20)

        // 模拟 SwiftData 最近一次真实写盘失败。导出仍必须以当前内存状态为准。
        store.saveStatus = .unsaved

        let data = try TodoBackupWorkflow.exportData(
            from: store,
            exportedAt: exportedAt
        )
        let document = try TodoBackupCodec.decode(data)

        XCTAssertEqual(document.exportedAt, exportedAt)
        XCTAssertEqual(document.items.count, 2)
        XCTAssertEqual(document.daySections.count, 1)

        let scheduledBackup = try XCTUnwrap(document.items.first { $0.id == scheduled.id })
        XCTAssertEqual(scheduledBackup.title, "Ship backup")
        XCTAssertTrue(scheduledBackup.isCompleted)
        XCTAssertEqual(scheduledBackup.indentLevel, 2)
        XCTAssertEqual(scheduledBackup.sortOrder, 123.5)
        XCTAssertEqual(scheduledBackup.containerKind, .scheduled)
        XCTAssertEqual(scheduledBackup.dayDate, TodoBackupCalendarDate(year: 2026, month: 8, day: 26))
        XCTAssertEqual(scheduledBackup.createdAt, createdAt)
        XCTAssertEqual(scheduledBackup.updatedAt, updatedAt)

        let longTermBackup = try XCTUnwrap(document.items.first { $0.id == longTerm.id })
        XCTAssertEqual(longTermBackup.containerKind, .longTermImportant)
        XCTAssertEqual(longTermBackup.dayDate, TodoBackupCalendarDate(year: 2026, month: 7, day: 3))

        let sectionBackup = try XCTUnwrap(document.daySections.first)
        XCTAssertEqual(sectionBackup.id, section.id)
        XCTAssertEqual(sectionBackup.date, TodoBackupCalendarDate(year: 2026, month: 8, day: 26))
        XCTAssertEqual(sectionBackup.title, "Backup day")
        XCTAssertEqual(sectionBackup.sortOrder, 88.25)
        XCTAssertEqual(sectionBackup.createdAt, createdAt.addingTimeInterval(20))
        XCTAssertEqual(sectionBackup.updatedAt, updatedAt.addingTimeInterval(20))
        XCTAssertEqual(store.saveStatus, .unsaved)
    }

    func testDefaultExportFilenameUsesCalendarDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Singapore"))
        let date = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 8, day: 26, hour: 23)
            )
        )

        XCTAssertEqual(
            TodoBackupWorkflow.defaultExportFilename(exportedAt: date, calendar: calendar),
            "TodoBlock-Backup-2026-08-26.json"
        )
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Singapore"))
        return try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: year, month: month, day: day, hour: hour)
            )
        )
    }
}
