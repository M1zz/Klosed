//
//  ClosedDayCalendarView.swift
//  DontGoMart
//
//  Created by hyunho lee on 2023/06/17.
//

import SwiftUI

struct ClosedDayCalendarView: View {
    @Binding var currentDate: Date
    @State private var currentMonth: Int = 0
    @StateObject private var martSelection = MartSelectionManager.shared

    private let weekdaySymbols = Weekday.symbols
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 24) {
            header
            weekdayRow
            monthGrid
            selectedDayDetail
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .onChange(of: currentMonth) {
            currentDate = monthDate()
        }
    }

    // MARK: - Header (월 이동)

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(yearMonth().year)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(yearMonth().month)
                    .font(.title.bold())
            }

            Spacer(minLength: 0)

            Button {
                withAnimation { currentMonth -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("이전 달"))

            Button {
                withAnimation { currentMonth += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("다음 달"))
        }
        .padding(.horizontal)
    }

    // MARK: - 요일 머리글

    private var weekdayRow: some View {
        HStack(spacing: 4) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, day in
                Text(day)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(index == 0 ? .red : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        // 각 날짜 칸이 요일까지 읽으므로 요일 머리글은 VoiceOver 에서 생략.
        .accessibilityHidden(true)
    }

    // MARK: - 날짜 그리드

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(extractDates()) { value in
                dayCell(value)
                    .onTapGesture { currentDate = value.date }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(cellAccessibilityLabel(for: value)))
                    .accessibilityAddTraits(cellAccessibilityTraits(for: value))
                    .accessibilityHidden(value.day == -1)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func dayCell(_ value: DateValue) -> some View {
        if value.day == -1 {
            Color.clear.frame(height: 48)
        } else {
            let isSelected = isSameDay(value.date, currentDate)
            let closedMarts = closedMarts(on: value.date)
            let isClosed = !closedMarts.isEmpty

            VStack(spacing: 4) {
                Text("\(value.day)")
                    .font(.body.weight(isClosed ? .bold : .regular))
                    .foregroundColor(dayTextColor(isSelected: isSelected, isClosed: isClosed, date: value.date))

                // 휴무 마트 색 점 (최대 3개)
                HStack(spacing: 3) {
                    ForEach(closedMarts.prefix(3)) { mart in
                        Circle()
                            .fill(isSelected ? Color.white : mart.type.themeColor)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color("Pink") : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isToday(value.date) && !isSelected ? Color("Pink") : Color.clear, lineWidth: 1.5)
            )
        }
    }

    private func dayTextColor(isSelected: Bool, isClosed: Bool, date: Date) -> Color {
        if isSelected { return .white }
        if isWeekend(date) { return .red }
        return .primary
    }

    // MARK: - 선택한 날 상세

    private var selectedDayDetail: some View {
        let closedMarts = closedMarts(on: currentDate)

        return VStack(alignment: .leading, spacing: 12) {
            Text(currentDate.formatted(date: .complete, time: .omitted))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if closedMarts.isEmpty {
                Text("휴무인 매장이 없습니다")
                    .foregroundColor(.secondary)
            } else {
                ForEach(closedMarts) { closedDay in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(closedDay.type.themeColor)
                            .frame(width: 12, height: 12)
                            .accessibilityHidden(true)
                        Text(closedDay.type.displayName)
                            .font(.body.weight(.semibold))
                        Spacer()
                        Text("휴무")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(closedDay.type.themeColor.opacity(0.12))
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(closedDay.type.displayName) 휴무"))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    // MARK: - Data helpers

    private func closedMarts(on date: Date) -> [MetaMartsClosedDays] {
        let selected = martSelection.getSelectedMartTypes()
        return tasks.filter { selected.contains($0.type) && isSameDay($0.taskDate, date) }
    }

    private func cellAccessibilityLabel(for value: DateValue) -> String {
        guard value.day != -1 else { return "" }
        let dateText = value.date.formatted(date: .complete, time: .omitted)
        let closed = closedMarts(on: value.date)
        if closed.isEmpty {
            return "\(dateText), " + String(localized: "휴무 없음", defaultValue: "No closing")
        }
        let names = closed.map { $0.type.displayName }.joined(separator: ", ")
        return "\(dateText), " + String(format: String(localized: "%@ 휴무", defaultValue: "%@ closed"), names)
    }

    private func cellAccessibilityTraits(for value: DateValue) -> AccessibilityTraits {
        guard value.day != -1 else { return [] }
        var traits: AccessibilityTraits = .isButton
        if isSameDay(value.date, currentDate) {
            traits.insert(.isSelected)
        }
        return traits
    }

    private func isSameDay(_ d1: Date, _ d2: Date) -> Bool {
        Calendar.current.isDate(d1, inSameDayAs: d2)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func isWeekend(_ date: Date) -> Bool {
        Calendar.current.component(.weekday, from: date) == 1 // 일요일
    }

    private func yearMonth() -> (year: String, month: String) {
        let calendar = Calendar.current
        let date = monthDate()
        let month = calendar.component(.month, from: date) - 1
        let year = calendar.component(.year, from: date)
        return ("\(year)", calendar.monthSymbols[month])
    }

    private func monthDate() -> Date {
        Calendar.current.date(byAdding: .month, value: currentMonth, to: Date()) ?? Date()
    }

    private func extractDates() -> [DateValue] {
        let calendar = Calendar.current
        let month = monthDate()

        var days = month.getAllDates().compactMap { date -> DateValue in
            let day = calendar.component(.day, from: date)
            return DateValue(day: day, date: date)
        }

        guard let firstDate = days.first?.date else { return days }
        let firstWeekday = calendar.component(.weekday, from: firstDate)
        for _ in 0..<firstWeekday - 1 {
            days.insert(DateValue(day: -1, date: Date()), at: 0)
        }
        return days
    }
}

#Preview {
    ClosedDayCalendarView(currentDate: .constant(Date()))
}
