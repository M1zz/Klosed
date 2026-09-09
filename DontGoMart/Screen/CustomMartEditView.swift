//
//  CustomMartEditView.swift
//  DontGoMart
//
//  Created by Claude on 1/20/25.
//

import SwiftUI

struct CustomMartEditView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var customMartManager = CustomMartManager.shared

    let editingMart: CustomMart?
    @State private var martName: String = ""
    @State private var patterns: [ClosurePattern] = []
    @State private var selectedColor: Color = .red
    @State private var showingPatternEditor = false

    init(editingMart: CustomMart? = nil) {
        self.editingMart = editingMart

        if let mart = editingMart {
            _martName = State(initialValue: mart.name)
            _patterns = State(initialValue: mart.patterns)
            _selectedColor = State(initialValue: Color(hex: mart.color) ?? .red)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("마트 정보")) {
                    TextField("마트 이름 (예: 홈플러스 강남점)", text: $martName)

                    ColorPicker("마트 색상", selection: $selectedColor)
                }

                Section(header: Text("휴무 패턴")) {
                    if patterns.isEmpty {
                        Text("패턴을 추가해주세요")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(patterns) { pattern in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pattern.displayText)
                                        .font(.subheadline)
                                }
                                Spacer()
                                Button(action: {
                                    patterns.removeAll { $0.id == pattern.id }
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button(action: {
                        showingPatternEditor = true
                    }) {
                        Label("패턴 추가", systemImage: "plus.circle.fill")
                    }
                }

                Section {
                    Button(action: saveMart) {
                        Text(editingMart == nil ? "추가" : "저장")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                    .disabled(martName.isEmpty || patterns.isEmpty)
                }
            }
            .navigationTitle(editingMart == nil ? "커스텀 마트 추가" : "커스텀 마트 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingPatternEditor) {
                PatternEditorView { newPattern in
                    patterns.append(newPattern)
                }
            }
        }
    }

    private func saveMart() {
        let colorHex = selectedColor.toHex() ?? "#FF6B6B"

        if let existing = editingMart {
            let updated = CustomMart(
                id: existing.id,
                name: martName,
                patterns: patterns,
                color: colorHex,
                isEnabled: existing.isEnabled
            )
            customMartManager.updateCustomMart(updated)
        } else {
            let newMart = CustomMart(
                name: martName,
                patterns: patterns,
                color: colorHex
            )
            customMartManager.addCustomMart(newMart)
        }

        dismiss()
    }
}

// MARK: - Pattern Editor View (매주 / 격주 / 매월 주차)

struct PatternEditorView: View {
    @Environment(\.dismiss) var dismiss
    let onSave: (ClosurePattern) -> Void

    private enum PatternMode: String, CaseIterable, Identifiable {
        case weekly = "매주"
        case biweekly = "격주"
        case monthly = "매월 주차"
        var id: String { rawValue }

        /// 세그먼트 라벨. rawValue 를 그대로 Text 에 넣으면 번역이 붙지 않으므로 여기서 조회한다.
        var title: String {
            switch self {
            case .weekly:   return String(localized: "매주", defaultValue: "Weekly")
            case .biweekly: return String(localized: "격주", defaultValue: "Every 2 weeks")
            case .monthly:  return String(localized: "매월 주차", defaultValue: "By week of month")
            }
        }

        var guide: String {
            switch self {
            case .weekly:
                return String(localized: "쉬는 요일을 고르면 매주 그 요일에 휴무로 반복돼요.",
                              defaultValue: "Pick a weekday and it repeats as a closed day every week.")
            case .biweekly:
                return String(localized: "첫 휴무일을 고르면 그 날부터 2주에 한 번씩 휴무로 반복돼요. (2·4주차와 달리 월과 무관하게 14일 간격)",
                              defaultValue: "Pick the first closed day and it repeats every 2 weeks from then on. (Exactly 14 days apart, regardless of the month.)")
            case .monthly:
                return String(localized: "매월 정해진 주차·요일에 휴무일 때 사용하세요. (예: 2·4주차 화요일)",
                              defaultValue: "Use this when the store closes on set weeks each month. (e.g. 2nd and 4th Tuesday)")
            }
        }
    }

    private static let previewFormatter: DateFormatter = {
        let f = DateFormatter()
        // 요일은 앞의 "격주 수요일" 에서 이미 말하므로 날짜만 — 로케일이 9/13 / 13/9 순서를 정한다.
        f.setLocalizedDateFormatFromTemplate("Md")
        return f
    }()

    @State private var mode: PatternMode = .weekly

    // 매주 모드: 선택된 요일들
    @State private var weeklyWeekdays: Set<Weekday> = []
    // 격주 모드: 첫 휴무일 (이 날 + 14일마다). 요일은 이 날짜에서 자동 도출.
    @State private var biweeklyStart: Date = Calendar.current.startOfDay(for: Date())
    // 매월 주차 모드: (주차, 요일) 조합
    @State private var selectedCells: Set<GridCell> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("휴무 방식", selection: $mode) {
                        ForEach(PatternMode.allCases) { m in Text(m.title).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top)

                    Text(mode.guide)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    switch mode {
                    case .weekly:
                        weekdaySelector
                    case .biweekly:
                        biweeklyEditor
                    case .monthly:
                        PatternGridView(selectedCells: $selectedCells)
                            .padding(.horizontal)
                    }

                    if let preview = previewText {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("선택된 패턴")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(preview)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("패턴 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("추가") { savePatterns() }
                        .disabled(!isValid)
                }
            }
        }
    }

    // MARK: 매주 — 요일 칩 선택

    private var weekdaySelector: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases, id: \.self) { weekday in
                let selected = weeklyWeekdays.contains(weekday)
                Button {
                    if selected { weeklyWeekdays.remove(weekday) }
                    else { weeklyWeekdays.insert(weekday) }
                } label: {
                    Text(weekday.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(selected ? Color.pink : Color(.systemGray5))
                        .foregroundColor(selected ? .white : weekdayColor(weekday))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("매주 \(weekday.fullName)"))
                .accessibilityValue(Text(selected ? "선택됨" : "선택 안 됨"))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal)
    }

    // MARK: 격주 — 첫 휴무일 선택

    private var biweeklyEditor: some View {
        VStack(spacing: 12) {
            DatePicker("첫 휴무일",
                       selection: $biweeklyStart,
                       displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding(.horizontal)
        }
    }

    private func weekdayColor(_ weekday: Weekday) -> Color {
        switch weekday {
        case .sunday: return .red
        case .saturday: return .blue
        default: return .primary
        }
    }

    // MARK: 유효성 / 미리보기 / 저장

    private var isValid: Bool {
        switch mode {
        case .weekly:   return !weeklyWeekdays.isEmpty
        case .biweekly: return true
        case .monthly:  return !selectedCells.isEmpty
        }
    }

    private var previewText: String? {
        switch mode {
        case .weekly:
            guard !weeklyWeekdays.isEmpty else { return nil }
            let names = weeklyWeekdays.sorted { $0.rawValue < $1.rawValue }
                .map { $0.displayName }
                .joined(separator: ", ")
            return String(format: String(localized: "매주 %@요일", defaultValue: "Every %@"), names)

        case .biweekly:
            let start = Calendar.current.startOfDay(for: biweeklyStart)
            let wd = weekday(from: start)
            let dates = biweeklyPreviewDates(from: start, count: 3)
                .map { Self.previewFormatter.string(from: $0) }
                .joined(separator: ", ")
            return String(format: String(localized: "격주 %1$@요일 · %2$@ …", defaultValue: "Every other %1$@ · %2$@ …"),
                          wd.displayName, dates)

        case .monthly:
            guard !selectedCells.isEmpty else { return nil }
            var groups: [Weekday: Set<WeekOfMonth>] = [:]
            for cell in selectedCells { groups[cell.weekday, default: []].insert(cell.week) }
            let texts = groups.keys.sorted { $0.rawValue < $1.rawValue }.map { weekday -> String in
                let weeks = groups[weekday] ?? []
                if weeks.count == WeekOfMonth.allCases.count {
                    return String(format: String(localized: "매주 %@요일", defaultValue: "Every %@"), weekday.displayName)
                }
                let weekText = weeks.sorted { $0.rawValue < $1.rawValue }
                    .map { "\($0.rawValue)" }.joined(separator: ",")
                return String(format: String(localized: "%1$@주 %2$@요일", defaultValue: "Week %1$@ · %2$@"),
                              weekText, weekday.displayName)
            }
            return texts.joined(separator: " / ")
        }
    }

    private func weekday(from date: Date) -> Weekday {
        let wd = Calendar.current.component(.weekday, from: date)
        return Weekday(rawValue: wd) ?? .sunday
    }

    private func biweeklyPreviewDates(from start: Date, count: Int) -> [Date] {
        let calendar = Calendar.current
        var date = calendar.startOfDay(for: start)
        var result: [Date] = []
        for _ in 0..<count {
            result.append(date)
            date = calendar.date(byAdding: .day, value: 14, to: date) ?? date
        }
        return result
    }

    private func savePatterns() {
        switch mode {
        case .weekly:
            // 각 요일을 '모든 주차 선택' = 매주 패턴으로 저장
            let everyWeek = Set(WeekOfMonth.allCases)
            for weekday in weeklyWeekdays {
                onSave(ClosurePattern(weeks: everyWeek, weekday: weekday, frequency: .weekOfMonth))
            }

        case .biweekly:
            let start = Calendar.current.startOfDay(for: biweeklyStart)
            onSave(ClosurePattern(weekday: weekday(from: start),
                                  frequency: .biweekly,
                                  anchorDate: start))

        case .monthly:
            var groups: [Weekday: Set<WeekOfMonth>] = [:]
            for cell in selectedCells { groups[cell.weekday, default: []].insert(cell.week) }
            for (weekday, weeks) in groups {
                onSave(ClosurePattern(weeks: weeks, weekday: weekday, frequency: .weekOfMonth))
            }
        }

        dismiss()
    }
}

// MARK: - Grid Cell Model

struct GridCell: Hashable {
    let week: WeekOfMonth
    let weekday: Weekday
}

// MARK: - Pattern Grid View (7x5)

struct PatternGridView: View {
    @Binding var selectedCells: Set<GridCell>

    private let weekdays = Weekday.allCases
    private let weeks = WeekOfMonth.allCases

    var body: some View {
        VStack(spacing: 8) {
            // 요일 헤더
            HStack(spacing: 4) {
                // 빈 코너
                Text("")
                    .frame(width: 36)

                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday.displayName)
                        .font(.caption)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(weekdayColor(weekday))
                }
            }
            // 각 셀이 요일을 읽으므로 요일 머리글은 VoiceOver 에서 생략.
            .accessibilityHidden(true)

            // 5주차 행들
            ForEach(weeks, id: \.self) { week in
                HStack(spacing: 4) {
                    // 주차 라벨
                    Text("\(week.rawValue)주")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 36)

                    // 요일 버튼들
                    ForEach(weekdays, id: \.self) { weekday in
                        GridCellButton(
                            week: week,
                            weekday: weekday,
                            isSelected: selectedCells.contains(GridCell(week: week, weekday: weekday)),
                            onTap: {
                                toggleCell(week: week, weekday: weekday)
                            }
                        )
                    }
                }
            }
        }
    }

    private func toggleCell(week: WeekOfMonth, weekday: Weekday) {
        let cell = GridCell(week: week, weekday: weekday)
        if selectedCells.contains(cell) {
            selectedCells.remove(cell)
        } else {
            selectedCells.insert(cell)
        }
    }

    private func weekdayColor(_ weekday: Weekday) -> Color {
        switch weekday {
        case .sunday: return .red
        case .saturday: return .blue
        default: return .primary
        }
    }
}

// MARK: - Grid Cell Button

struct GridCellButton: View {
    let week: WeekOfMonth
    let weekday: Weekday
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.pink : Color(.systemGray5))
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(week.rawValue)주차 \(weekday.displayName)"))
        .accessibilityValue(Text(isSelected
            ? String(localized: "선택됨", defaultValue: "Selected")
            : String(localized: "선택 안 됨", defaultValue: "Not selected")))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    CustomMartEditView()
}
