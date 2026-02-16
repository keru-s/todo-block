//
//  LongTermListView.swift
//  todo block
//
//  Created by Codex on 2026/2/16.
//

import SwiftData
import SwiftUI

struct LongTermListView: View {
    var isActiveContext: Bool = true

    @State private var selectionManager = SelectionManager()

    private var store: TodoStore { TodoStore.shared }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading) {
                    LongTermBucketView(
                        title: "紧急",
                        isUrgent: true,
                        selectionManager: selectionManager,
                        onItemCreated: { itemId in
                            scrollToItem(itemId, proxy: proxy)
                        },
                        onInteraction: {
                            bindClipboardContextIfNeeded()
                        }
                    )

                    LongTermBucketView(
                        title: "重要",
                        isUrgent: false,
                        selectionManager: selectionManager,
                        onItemCreated: { itemId in
                            scrollToItem(itemId, proxy: proxy)
                        },
                        onInteraction: {
                            bindClipboardContextIfNeeded()
                        }
                    )
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                bindClipboardContextIfNeeded()
            }
            .onChange(of: selectionManager.focusedItemId) { _, newValue in
                bindClipboardContextIfNeeded()
                if let itemId = newValue {
                    scrollToItem(itemId, proxy: proxy)
                }
            }
            .onChange(of: selectionManager.selectedItemIds) { _, _ in
                bindClipboardContextIfNeeded()
            }
            .onChange(of: isActiveContext) { _, newValue in
                guard newValue else { return }
                bindClipboardContextIfNeeded()
            }
            .onChange(of: store.focusRequestId) { _, newValue in
                guard let itemId = newValue, store.todoItemsCache[itemId] != nil else { return }
                bindClipboardContextIfNeeded()
                selectionManager.restoreFocus(to: itemId)
                scrollToItem(itemId, proxy: proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func scrollToItem(_ itemId: UUID, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(itemId, anchor: .center)
        }
    }

    private func bindClipboardContextIfNeeded() {
        guard isActiveContext else { return }
        TodoClipboardManager.shared.activateListContext(
            scope: .longTerm,
            store: store,
            selectionManager: selectionManager
        )
    }
}

#Preview {
    LongTermListView()
        .modelContainer(for: [TodoItem.self, DaySection.self], inMemory: true)
}
