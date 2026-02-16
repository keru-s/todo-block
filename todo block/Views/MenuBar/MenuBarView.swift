//
//  MenuBarView.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    private let indentWidth: CGFloat = 24
    private let itemHeight: CGFloat = 28

    // 状态管理
    @State private var selectionManager = SelectionManager()
    @State private var dropState: TodoListDropState = .none
    @State private var isDropFinalizing: Bool = false
    @State private var itemFrames: [UUID: CGRect] = [:]

    private var store: TodoStore { TodoStore.shared }

    private var todayItems: [TodoItem] {
        store.todayItems()
    }

    private var formattedToday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Text("今日待办")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(formattedToday)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if todayItems.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    todoListView
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .frame(minHeight: 50, maxHeight: 350)
            }

            Divider()

            // 底部操作栏
            HStack {
                Button(action: addTodayItem) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("添加")
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Spacer()

                if selectionManager.selectedItemIds.count > 1 {
                    Text("已选 \(selectionManager.selectedItemIds.count) 项")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 8)
                }

                Button("打开应用") {
                    openWindow(id: "mainWindow")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            bindClipboardContext()
            isDropFinalizing = false
        }
        .gesture(
            TapGesture().onEnded {
                bindClipboardContext()
                selectionManager.clearSelection()
            }
        )
        .onChange(of: store.focusRequestId) { _, newValue in
            guard let itemId = newValue, store.todoItemsCache[itemId] != nil else { return }
            bindClipboardContext()
            selectionManager.restoreFocus(to: itemId)
        }
        .onChange(of: todayItems.dropResetSnapshot) { _, _ in
            dropState = .none
            bindClipboardContext()
        }
        .onChange(of: store.dropIndicatorResetTrigger) { _, _ in
            dropState = .none
        }
        .onChange(of: selectionManager.focusedItemId) { _, _ in
            bindClipboardContext()
        }
        .onChange(of: selectionManager.selectedItemIds) { _, _ in
            bindClipboardContext()
        }
    }

    // MARK: - 待办列表（带拖拽支持）

    private var todoListView: some View {
        let items = todayItems

        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                VStack(spacing: 0) {
                    // 插入线（在当前项上方）
                    if case .insertAt(let insertIndex, let indentLevel) = dropState,
                        insertIndex == index
                    {
                        TodoInsertionIndicator(
                            indentLevel: indentLevel,
                            indentWidth: indentWidth
                        )
                    }

                    TodoItemView(
                        item: item,
                        allItems: items,
                        focusedItemId: $selectionManager.focusedItemId,
                        isSelected: selectionManager.selectedItemIds.contains(item.id),
                        hasMultipleSelection: selectionManager.selectedItemIds.count > 1,
                        cursorPosition: selectionManager.cursorPosition,
                        preferredHorizontalOffset: selectionManager.preferredHorizontalOffset,
                        verticalMoveDirection: selectionManager.verticalMoveDirection,
                        onSelect: { shiftPressed in
                            bindClipboardContext()
                            selectionManager.handleSelect(
                                item: item, allItems: items, shiftPressed: shiftPressed)
                        },
                        onFocus: { shiftPressed, cursorPosition in
                            bindClipboardContext()
                            selectionManager.handleSelect(
                                item: item, allItems: items, shiftPressed: shiftPressed,
                                cursorPosition: cursorPosition)
                        },
                        onEnterPressed: { createNewItemAfter(item) },
                        onDeletePressed: {
                            if selectionManager.selectedItemIds.contains(item.id) {
                                selectionManager.deleteSelectedItems(store: store) { _ in
                                    return items
                                }
                            }
                        },
                        onMoveUp: { position, horizontalOffset in
                            selectionManager.moveFocusUp(
                                from: item,
                                allItems: items,
                                cursorPosition: position,
                                preferredHorizontalOffset: horizontalOffset
                            )
                        },
                        onMoveDown: { position, horizontalOffset in
                            selectionManager.moveFocusDown(
                                from: item,
                                allItems: items,
                                cursorPosition: position,
                                preferredHorizontalOffset: horizontalOffset
                            )
                        },
                        onActivateInteraction: {
                            bindClipboardContext()
                        }
                    )
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TodoDropItemFramePreferenceKey.self,
                                value: [item.id: proxy.frame(in: .named("menubar-drop-area"))]
                            )
                        }
                    }
                    .id(item.id)
                }
            }

            // 插入线（在列表末尾）
            if case .insertAt(let insertIndex, let indentLevel) = dropState,
                insertIndex == items.count
            {
                TodoInsertionIndicator(
                    indentLevel: indentLevel,
                    indentWidth: indentWidth
                )
            }
        }
        .onDrop(
            of: [.text],
            delegate: TodoDropDelegate(
                destination: .scheduled(date: Date()),
                todoItems: items,
                store: store,
                dropState: $dropState,
                isDropFinalizing: $isDropFinalizing,
                itemFrames: itemFrames,
                indentWidth: indentWidth,
                itemHeight: itemHeight
            ))
        .coordinateSpace(name: "menubar-drop-area")
        .onPreferenceChange(TodoDropItemFramePreferenceKey.self) { value in
            itemFrames = value
        }
    }

    private var emptyStateView: some View {
        VStack {
            Text("今天没有待办事项")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            Button("添加待办") {
                addTodayItem()
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Actions

private extension MenuBarView {
    func addTodayItem() {
        bindClipboardContext()
        _ = store.getOrCreateTodaySection()
        let newItem = store.createItem(dayDate: Date())
        selectionManager.handleSelect(item: newItem, allItems: todayItems, shiftPressed: false)
    }

    func createNewItemAfter(_ item: TodoItem) {
        bindClipboardContext()
        let newItem = store.createItem(
            dayDate: Date(),
            afterItem: item,
            indentLevel: item.indentLevel
        )
        selectionManager.handleSelect(item: newItem, allItems: todayItems, shiftPressed: false)
    }

    func bindClipboardContext() {
        TodoClipboardManager.shared.activateListContext(
            scope: .today,
            store: store,
            selectionManager: selectionManager
        )
    }
}

#Preview {
    MenuBarView()
        .modelContainer(for: [TodoItem.self, DaySection.self], inMemory: true)
}
