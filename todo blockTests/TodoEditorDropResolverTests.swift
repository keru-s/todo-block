//
//  TodoEditorDropResolverTests.swift
//  todo blockTests
//

import CoreGraphics
import XCTest
@testable import todo_block

final class TodoEditorDropResolverTests: XCTestCase {
    func testHorizontalLocationResolvesIndentFromListContentOrigin() {
        let baseX: CGFloat = 120

        let rootDrop = TodoEditorDropResolver.resolvedDrop(
            destination: .longTerm(isUrgent: false),
            index: 1,
            x: baseX + 10,
            baseX: baseX,
            previousIndentLevel: 0
        )
        let childDrop = TodoEditorDropResolver.resolvedDrop(
            destination: .longTerm(isUrgent: false),
            index: 1,
            x: baseX + TodoDesignTokens.indentWidth + 4,
            baseX: baseX,
            previousIndentLevel: 0
        )

        XCTAssertEqual(rootDrop.indentLevel, 0)
        XCTAssertEqual(childDrop.indentLevel, 1)
    }

    func testHorizontalIndentClampsToPreviousItemPlusOne() {
        let drop = TodoEditorDropResolver.resolvedDrop(
            destination: .longTerm(isUrgent: false),
            index: 1,
            x: 400,
            baseX: 0,
            previousIndentLevel: 1
        )

        XCTAssertEqual(drop.indentLevel, 2)
    }

    func testTopInsertionAlwaysUsesRootIndent() {
        let drop = TodoEditorDropResolver.resolvedDrop(
            destination: .longTerm(isUrgent: false),
            index: 0,
            x: 400,
            baseX: 0,
            previousIndentLevel: nil
        )

        XCTAssertEqual(drop.indentLevel, 0)
    }
}
