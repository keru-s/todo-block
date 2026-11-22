import SwiftUI

struct TodoEditorDatePicker: View {
    let onCancel: () -> Void
    let onConfirm: (Date) -> Void
    let canConfirm: (Date) -> Bool

    @State private var selection: Date
    @State private var visibleMonth: Date
    @FocusState private var isCalendarFocused: Bool

    private let calendar: Calendar
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    init(
        date: Date,
        canConfirm: @escaping (Date) -> Bool,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (Date) -> Void
    ) {
        let calendar = Calendar.current
        self.calendar = calendar
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.canConfirm = canConfirm
        _selection = State(initialValue: calendar.startOfDay(for: date))
        _visibleMonth = State(initialValue: date)
    }

    var body: some View {
        let canConfirmSelection = canConfirm(selection)
        let monthStart = calendar.dateInterval(of: .month, for: visibleMonth)?.start ?? visibleMonth
        let weekdayOffset = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let weekdays = calendar.veryShortStandaloneWeekdaySymbols
        let days = (0..<42).compactMap { index in
            calendar.date(byAdding: .day, value: index - weekdayOffset, to: monthStart)
                .map { calendar.startOfDay(for: $0) }
        }

        VStack(spacing: 12) {
            HStack(spacing: 4) {
                Text(visibleMonth, format: .dateTime.year().month(.wide))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                monthButton("上个月", symbol: "chevron.backward", offset: -1)
                monthButton("下个月", symbol: "chevron.forward", offset: 1)
            }

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(0..<7) { index in
                    Text(weekdays[(calendar.firstWeekday - 1 + index) % 7])
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 20)
                        .accessibilityHidden(true)
                }

                ForEach(days, id: \.self) { date in
                    TodoEditorCalendarDay(
                        date: date,
                        dayNumber: calendar.component(.day, from: date),
                        isCurrentMonth: calendar.isDate(date, equalTo: visibleMonth, toGranularity: .month),
                        isToday: calendar.isDateInToday(date),
                        isSelected: date == selection,
                        showsKeyboardFocus: isCalendarFocused && date == selection,
                        action: { select(date) }
                    )
                }
            }
            .accessibilityLabel("日历")
            .focusable(interactions: .edit)
            .focusEffectDisabled()
            .focused($isCalendarFocused)
            .onMoveCommand(perform: moveSelection)

            Divider()

            HStack(spacing: 8) {
                if canConfirmSelection {
                    Button("今天") { select(.now) }
                        .buttonStyle(.borderless)
                        .help("选择今天")
                } else {
                    Text("该日期已有待办")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("确认") { onConfirm(selection) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConfirmSelection)
            }
            .controlSize(.regular)
        }
        .frame(width: 258)
        .padding(16)
        .background(TodoDesignTokens.windowBackground)
        .fixedSize()
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
        .defaultFocus($isCalendarFocused, true)
    }

    private func monthButton(_ title: String, symbol: String, offset: Int) -> some View {
        Button {
            if let nextMonth = calendar.date(byAdding: .month, value: offset, to: visibleMonth) {
                visibleMonth = nextMonth
            }
        } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(TodoEditorCalendarButtonStyle())
        .accessibilityLabel(title)
        .help(title)
    }

    private func select(_ date: Date) {
        selection = calendar.startOfDay(for: date)
        visibleMonth = selection
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let offset: Int
        switch direction {
        case .left: offset = -1
        case .right: offset = 1
        case .up: offset = -7
        case .down: offset = 7
        @unknown default: return
        }
        guard let nextDay = calendar.date(byAdding: .day, value: offset, to: selection) else { return }
        select(nextDay)
    }
}

private struct TodoEditorCalendarDay: View {
    let date: Date
    let dayNumber: Int
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let showsKeyboardFocus: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(dayNumber, format: .number)
                .font(.callout.weight(isSelected || isToday ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isCurrentMonth || isSelected || isToday ? .primary : .secondary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .overlay(alignment: .bottom) {
                    if isToday {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 4, height: 4)
                            .padding(.bottom, 3)
                    }
                }
        }
        .buttonStyle(TodoEditorCalendarButtonStyle(
            isSelected: isSelected, showsKeyboardFocus: showsKeyboardFocus
        ))
        .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).year().month().day()))
        .accessibilityValue(isToday ? "今天" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TodoEditorCalendarButtonStyle: ButtonStyle {
    var isSelected = false
    var showsKeyboardFocus = false
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        let isHighlighted = isSelected || configuration.isPressed || isHovered
        configuration.label
            .background(isHighlighted ? TodoDesignTokens.selectionTint : Color.clear, in: shape)
            .overlay {
                if isSelected {
                    shape.strokeBorder(
                        Color.accentColor.opacity(showsKeyboardFocus ? 1 : 0.6),
                        lineWidth: showsKeyboardFocus ? 2 : 1
                    )
                }
            }
            .contentShape(shape)
            .onHover { isHovered = $0 }
    }
}
