//
//  MenuBarView.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import SwiftData
import SwiftUI

struct MenuBarView: View {
    let onOpenMainWindow: () -> Void

    init(onOpenMainWindow: @escaping () -> Void = {}) {
        self.onOpenMainWindow = onOpenMainWindow
    }

    private let indentWidth: CGFloat = 24
    private let itemHeight: CGFloat = 28
    private let dropAreaInset = TodoInsertionIndicator.visualHeight + 8

    // 状态管理
    @State private var selectionManager = SelectionManager()
    @State private var dropState: TodoListDropState = .none
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var draggingItemId: UUID?

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
                .contentShape(.rect)
                .coordinateSpace(name: "menubar-drop-area")
                .onPreferenceChange(TodoDropItemFramePreferenceKey.self) { value in
                    itemFrames = value
                }
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
                    onOpenMainWindow()
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
        }
        .gesture(
            TapGesture().onEnded {
                handleBackgroundTap()
            },
            including: .gesture
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

        return ZStack(alignment: .topLeading) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items.enumerated(), id: \.element.id) { _, item in
                    TodoItemView(
                        item: item,
                        allItems: items,
                        focusedItemId: $selectionManager.focusedItemId,
                        isSelected: selectionManager.selectedItemIds.contains(item.id),
                        hasMultipleSelection: selectionManager.selectedItemIds.count > 1,
                        cursorPosition: selectionManager.cursorPosition,
                        preferredHorizontalOffset: selectionManager.preferredHorizontalOffset,
                        verticalMoveDirection: selectionManager.verticalMoveDirection,
                        useSystemDragAndDrop: false,
                        handleDragCoordinateSpace: .named("menubar-drop-area"),
                        onHandleDragBegan: {
                            handleMenuBarDragBegan(itemId: item.id)
                        },
                        onHandleDragChanged: { location in
                            handleMenuBarDragChanged(
                                location: location,
                                itemId: item.id,
                                items: items
                            )
                        },
                        onHandleDragEnded: { location in
                            handleMenuBarDragEnded(
                                location: location,
                                itemId: item.id,
                                items: items
                            )
                        },
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
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            .padding(.vertical, dropAreaInset)

            TodoDropIndicatorOverlay(
                dropState: dropState,
                items: items,
                itemFrames: itemFrames,
                itemHeight: itemHeight,
                indentWidth: indentWidth
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
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

    func handleBackgroundTap() {
        bindClipboardContext()
        selectionManager.clearSelection()
    }

    func handleMenuBarDragBegan(itemId: UUID) {
        draggingItemId = itemId
    }

    func handleMenuBarDragChanged(location: CGPoint, itemId: UUID, items: [TodoItem]) {
        guard draggingItemId == itemId else { return }
        dropState = MenuBarManualReorderEngine.dropState(
            for: location,
            items: items,
            itemFrames: itemFrames,
            itemHeight: itemHeight,
            indentWidth: indentWidth
        )
    }

    func handleMenuBarDragEnded(location: CGPoint, itemId: UUID, items: [TodoItem]) {
        guard draggingItemId == itemId else { return }

        let finalDropState = MenuBarManualReorderEngine.dropState(
            for: location,
            items: items,
            itemFrames: itemFrames,
            itemHeight: itemHeight,
            indentWidth: indentWidth
        )
        dropState = finalDropState

        defer {
            draggingItemId = nil
            dropState = .none
        }

        MenuBarManualReorderEngine.performMove(
            draggedId: itemId,
            dropState: finalDropState,
            items: items,
            destination: .scheduled(date: Date()),
            store: store
        )
    }
}

#Preview {
    MenuBarView()
        .modelContainer(for: [TodoItem.self, DaySection.self], inMemory: true)
}
