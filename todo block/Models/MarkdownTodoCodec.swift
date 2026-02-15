//
//  MarkdownTodoCodec.swift
//  todo block
//
//  Created by Codex on 2026/2/15.
//

import Foundation

struct MarkdownTodoEntry: Equatable {
    let title: String
    let isCompleted: Bool
    let indentLevel: Int
}

enum MarkdownTodoCodec {
    private static let indentUnit = 2
    private static let listLineRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)(?:[-*+]|\d+\.)\s+(?:\[( |x|X)\]\s+)?(.*)$"#
    )

    /// 导出为 Markdown checklist，默认将最小层级归零。
    static func encode(items: [TodoItem], normalizeBaseIndent: Bool = true) -> String {
        guard !items.isEmpty else { return "" }

        let baseIndent =
            if normalizeBaseIndent {
                items.map(\.indentLevel).min() ?? 0
            } else {
                0
            }

        return items
            .map { item in
                let relativeIndent = max(0, item.indentLevel - baseIndent)
                let indent = String(repeating: " ", count: relativeIndent * indentUnit)
                let checkbox = item.isCompleted ? "[x]" : "[ ]"
                return "\(indent)- \(checkbox) \(item.title)"
            }
            .joined(separator: "\n")
    }

    /// 从 Markdown checklist/list 导入 todo 项（缩进按 2 空格一级解析）。
    static func decode(
        _ markdown: String,
        baseIndentLevel: Int = 0,
        maxIndentLevel: Int = TodoItem.maxIndentLevel
    ) -> [MarkdownTodoEntry] {
        markdown
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .compactMap { parse(line: String($0)) }
            .map { parsed in
                let finalIndent = clamp(parsed.indentLevel + baseIndentLevel, max: maxIndentLevel)
                return MarkdownTodoEntry(
                    title: parsed.title,
                    isCompleted: parsed.isCompleted,
                    indentLevel: finalIndent
                )
            }
    }

    private static func parse(line: String) -> MarkdownTodoEntry? {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let match = listLineRegex.firstMatch(in: line, range: fullRange) else {
            return nil
        }

        let leadingWhitespace = nsLine.substring(with: match.range(at: 1))
        let indentSpaces = countIndentSpaces(in: leadingWhitespace)
        let indentLevel = indentSpaces / indentUnit

        let isCompleted: Bool
        if match.range(at: 2).location != NSNotFound {
            let marker = nsLine.substring(with: match.range(at: 2))
            isCompleted = marker.lowercased() == "x"
        } else {
            isCompleted = false
        }

        let title = nsLine.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
        return MarkdownTodoEntry(title: title, isCompleted: isCompleted, indentLevel: indentLevel)
    }

    private static func countIndentSpaces(in text: String) -> Int {
        text.reduce(into: 0) { result, char in
            if char == "\t" {
                result += indentUnit
            } else if char == " " {
                result += 1
            }
        }
    }

    private static func clamp(_ value: Int, max maxValue: Int) -> Int {
        min(max(0, value), maxValue)
    }
}
