//
//  TodoItemView.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import SwiftData
import SwiftUI

struct TodoItemView: View {
    @Bindable var item: TodoItem
    let allItems: [TodoItem]
    @Binding var focusedItemId: UUID?
    var isSelected: Bool = false
    var hasMultipleSelection: Bool = false
    var cursorPosition: Int = 0
    var preferredHorizontalOffset: CGFloat? = nil
    var verticalMoveDirection: VerticalMoveDirection? = nil
    var useSystemDragAndDrop: Bool = false
    var handleDragCoordinateSpace: CoordinateSpace = .global
    var onHandleDragBegan: (() -> Void)? = nil
    var onHandleDragChanged: ((CGPoint) -> Void)? = nil
    var onHandleDragEnded: ((CGPoint) -> Void)? = nil

    var onSelect: (Bool) -> Void = { _ in }
    var onFocus: (Bool, Int?) -> Void = { _, _ in }
    var onEnterPressed: () -> Void
    var onDeletePressed: () -> Void
    var onMoveUp: (Int, CGFloat?) -> Void
    var onMoveDown: (Int, CGFloat?) -> Void
    var onActivateInteraction: () -> Void = {}

    private let indentWidth: CGFloat = TodoDesignTokens.indentWidth

    @State private var isHoveringDragHandle: Bool = false
    @State private var editingText: String = ""
    @State private var shouldFocus: Bool = false
    @State private var isComposingText: Bool = false

    private var store: TodoStore { TodoStore.shared }

    private var isFocused: Bool {
        focusedItemId == item.id
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if item.indentLevel > 0 {
                Spacer()
                    .frame(width: CGFloat(item.indentLevel) * indentWidth)
            }

            TodoItemDragHandleView(
                isHovering: $isHoveringDragHandle,
                item: item,
                useSystemDragAndDrop: useSystemDragAndDrop,
                dragCoordinateSpace: handleDragCoordinateSpace,
                onManualDragBegan: onHandleDragBegan,
                onManualDragChanged: onHandleDragChanged,
                onManualDragEnded: onHandleDragEnded
            )

            TodoItemCheckboxView(
                isCompleted: item.isCompleted,
                onToggle: toggleComplete
            )

            TodoItemEditorContainer(
                item: item,
                store: store,
                editingText: $editingText,
                shouldFocus: $shouldFocus,
                isComposingText: $isComposingText,
                hasMultipleSelection: hasMultipleSelection,
                cursorPosition: cursorPosition,
                preferredHorizontalOffset: preferredHorizontalOffset,
                verticalMoveDirection: verticalMoveDirection,
                onTab: { store.indentItem(item) },
                onShiftTab: { store.outdentItem(item) },
                onReturn: onEnterPressed,
                onBackspace: onDeletePressed,
                onFocus: { shiftPressed, cursorPosition in
                    onActivateInteraction()
                    onFocus(shiftPressed, cursorPosition)
                },
                onCompositionChange: { composing in
                    isComposingText = composing
                },
                onUpArrow: { position, horizontalOffset in
                    onMoveUp(position, horizontalOffset)
                },
                onDownArrow: { position, horizontalOffset in
                    onMoveDown(position, horizontalOffset)
                }
            )
        }
        .padding(.vertical, 4)
        .background(isSelected ? TodoDesignTokens.selectionTint : Color.clear)
        .contentShape(.rect)
        .simultaneousGesture(
            TapGesture()
                .modifiers(.shift)
                .onEnded { _ in
                    onActivateInteraction()
                    onSelect(true)
                }
        )
        .gesture(
            TapGesture().onEnded {
                onActivateInteraction()
                onSelect(false)
            }
        )
        .onChange(of: focusedItemId) { oldValue, newValue in
            if newValue == item.id {
                editingText = item.title
                shouldFocus = true
            } else if oldValue == item.id {
                shouldFocus = false
            }
        }
        .onAppear {
            editingText = item.title
            if isFocused {
                shouldFocus = true
            }
        }
    }

    private func toggleComplete() {
        store.toggleComplete(item)
    }
}

private struct TodoItemDragHandleView: View {
    @Binding var isHovering: Bool
    let item: TodoItem
    let useSystemDragAndDrop: Bool
    let dragCoordinateSpace: CoordinateSpace
    let onManualDragBegan: (() -> Void)?
    let onManualDragChanged: ((CGPoint) -> Void)?
    let onManualDragEnded: ((CGPoint) -> Void)?
    @State private var hasStartedManualDrag: Bool = false

    var body: some View {
        Rectangle()
            .fill(isHovering ? Color.gray.opacity(0.5) : Color.clear)
            .frame(width: 20, height: 20)
            .overlay {
                if isHovering {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                }
            }
            .onHover { hovering in
                isHovering = hovering
            }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: dragCoordinateSpace)
                    .onChanged { value in
                        if hasStartedManualDrag == false {
                            hasStartedManualDrag = true
                            onManualDragBegan?()
                        }
                        onManualDragChanged?(value.location)
                    }
                    .onEnded { value in
                        if hasStartedManualDrag {
                            onManualDragEnded?(value.location)
                        }
                        hasStartedManualDrag = false
                    }
            )
    }
}

/// 共享的完成态图标:统一 row checkbox 与 drag preview 的 icon 渲染。
private struct TodoCheckboxIcon: View {
    let isCompleted: Bool

    var body: some View {
        Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
            .font(.system(size: 14))
            .foregroundStyle(isCompleted ? .green : .gray)
    }
}

struct TodoItemDragPreviewView: View {
    let item: TodoItem

    var body: some View {
        HStack(spacing: 4) {
            TodoCheckboxIcon(isCompleted: item.isCompleted)
            Text(item.title.isEmpty ? "待办事项" : item.title)
                .font(.system(size: 14))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(TodoDesignTokens.windowBackground)
        .clipShape(.rect(cornerRadius: TodoDesignTokens.dragPreviewCornerRadius))
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}

private struct TodoItemCheckboxView: View {
    let isCompleted: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            TodoCheckboxIcon(isCompleted: isCompleted)
        }
        .buttonStyle(.plain)
        .frame(width: 20, height: 20)
        .padding(.trailing, 6)
    }
}

private struct TodoItemEditorContainer: View {
    @Bindable var item: TodoItem
    let store: TodoStore
    @Binding var editingText: String
    @Binding var shouldFocus: Bool
    @Binding var isComposingText: Bool
    let hasMultipleSelection: Bool
    let cursorPosition: Int
    let preferredHorizontalOffset: CGFloat?
    let verticalMoveDirection: VerticalMoveDirection?
    let onTab: () -> Void
    let onShiftTab: () -> Void
    let onReturn: () -> Void
    let onBackspace: () -> Void
    let onFocus: (Bool, Int?) -> Void
    let onCompositionChange: (Bool) -> Void
    let onUpArrow: (Int, CGFloat?) -> Void
    let onDownArrow: (Int, CGFloat?) -> Void

    var body: some View {
        CustomTextEditor(
            text: $editingText,
            isCompleted: item.isCompleted,
            shouldFocus: $shouldFocus,
            hasMultipleSelection: hasMultipleSelection,
            cursorPosition: cursorPosition,
            preferredHorizontalOffset: preferredHorizontalOffset,
            verticalMoveDirection: verticalMoveDirection,
            onTab: onTab,
            onShiftTab: onShiftTab,
            onReturn: onReturn,
            onBackspace: onBackspace,
            onFocus: onFocus,
            onCompositionChange: onCompositionChange,
            onUpArrow: onUpArrow,
            onDownArrow: onDownArrow
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topLeading) {
            if editingText.isEmpty && isComposingText == false {
                Text("待办事项")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .padding(.top, 4)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: item.title) { _, newValue in
            if editingText != newValue {
                editingText = newValue
            }
        }
        .onChange(of: editingText) { _, newValue in
            item.title = newValue
            store.scheduleSave()
        }
    }
}

#Preview {
    PreviewContent()
}

private struct PreviewContent: View {
    let container: ModelContainer
    let item: TodoItem

    init() {
        container = TodoPreviewSupport.bootstrap()

        item = TodoItem(title: "测试待办事项", indentLevel: 0)
        container.mainContext.insert(item)
    }

    var body: some View {
        TodoItemView(
            item: item,
            allItems: [item],
            focusedItemId: .constant(item.id),
            onEnterPressed: {},
            onDeletePressed: {},
            onMoveUp: { _, _ in },
            onMoveDown: { _, _ in }
        )
        .modelContainer(container)
        .padding()
    }
}
