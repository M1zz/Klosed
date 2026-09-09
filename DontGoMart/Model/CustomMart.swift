//
//  CustomMart.swift
//  DontGoMart
//
//  Created by Claude on 1/20/25.
//

import Foundation

// 주차 선택 (1-5주차)
enum WeekOfMonth: Int, Codable, CaseIterable {
    case first = 1
    case second = 2
    case third = 3
    case fourth = 4
    case fifth = 5

    var displayName: String {
        String(format: String(localized: "%lld주차", defaultValue: "Week %lld"), rawValue)
    }
}

// 요일 선택
enum Weekday: Int, Codable, CaseIterable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    /// 요일 한 글자(한국어 "일", 영어 "Sun"). 사용자 로케일의 캘린더 심볼을 그대로 쓴다 —
    /// 하드코딩하면 영어 화면에 한글 요일이 그대로 노출된다.
    var displayName: String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let index = rawValue - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }

    /// 요일 전체 이름(한국어 "일요일", 영어 "Sunday"). VoiceOver 라벨 등 문장에 쓴다.
    var fullName: String {
        let symbols = Calendar.current.weekdaySymbols
        let index = rawValue - 1
        return symbols.indices.contains(index) ? symbols[index] : displayName
    }

    /// Calendar.component(.weekday) 값(1=일 … 7=토)으로 Weekday 를 얻는다.
    init?(calendarWeekday: Int) {
        self.init(rawValue: calendarWeekday)
    }

    /// 요일 심볼 한 글자 목록 (일~토). 여러 화면에서 공통 사용.
    static let symbols: [String] = allCases
        .sorted { $0.rawValue < $1.rawValue }
        .map { $0.displayName }

    /// Calendar 의 weekday 값(1=일)에 해당하는 심볼 한 글자.
    static func symbol(calendarWeekday: Int) -> String {
        Weekday(rawValue: calendarWeekday)?.displayName ?? ""
    }
}

// 휴무 반복 방식
// - weekOfMonth: 매월 정해진 주차 (예: 2·4주차 화요일). 월마다 리셋되므로 격주와 다름.
// - biweekly: 격주 (시작일부터 정확히 14일 간격). 월 경계와 무관하게 계속 이어짐.
enum ClosureFrequency: String, Codable {
    case weekOfMonth
    case biweekly
}

// 커스텀 마트 패턴
struct ClosurePattern: Hashable, Identifiable {
    let id: UUID
    let weeks: Set<WeekOfMonth>  // weekOfMonth 방식에서 선택된 주차들 (예: [2, 4])
    let weekday: Weekday  // 요일
    let frequency: ClosureFrequency  // 반복 방식
    let anchorDate: Date?  // biweekly(격주) 기준 시작일 — 이 날 + 14일마다 휴무

    init(id: UUID = UUID(),
         weeks: Set<WeekOfMonth> = [],
         weekday: Weekday,
         frequency: ClosureFrequency = .weekOfMonth,
         anchorDate: Date? = nil) {
        self.id = id
        self.weeks = weeks
        self.weekday = weekday
        self.frequency = frequency
        self.anchorDate = anchorDate
    }

    /// 격주 기준일 표기(9/13). 한국어를 하드코딩하지 않고 사용자 로케일의 월·일 순서를 따른다.
    private static let anchorFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("Md")
        return f
    }()

    var displayText: String {
        switch frequency {
        case .biweekly:
            if let anchor = anchorDate {
                return String(format: String(localized: "격주 %1$@요일 · %2$@ 시작",
                                             defaultValue: "Every other %1$@ · from %2$@"),
                              weekday.displayName, Self.anchorFormatter.string(from: anchor))
            }
            return String(format: String(localized: "격주 %@요일", defaultValue: "Every other %@"),
                          weekday.displayName)
        case .weekOfMonth:
            // 모든 주차가 선택되면 '매주'로 간결하게 표시 (매주 화요일 등)
            if weeks.count == WeekOfMonth.allCases.count {
                return String(format: String(localized: "매주 %@요일", defaultValue: "Every %@"),
                              weekday.displayName)
            }
            let weekText = weeks.sorted(by: { $0.rawValue < $1.rawValue })
                .map { $0.displayName }
                .joined(separator: ", ")
            return String(format: String(localized: "%1$@ %2$@요일", defaultValue: "%1$@ · %2$@"),
                          weekText, weekday.displayName)
        }
    }
}

// 기존 저장 데이터(주차 방식만 있던 시절) 호환을 위해 frequency/anchorDate 는 없으면 기본값 사용
extension ClosurePattern: Codable {
    enum CodingKeys: String, CodingKey {
        case id, weeks, weekday, frequency, anchorDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        weeks = try c.decodeIfPresent(Set<WeekOfMonth>.self, forKey: .weeks) ?? []
        weekday = try c.decode(Weekday.self, forKey: .weekday)
        frequency = try c.decodeIfPresent(ClosureFrequency.self, forKey: .frequency) ?? .weekOfMonth
        anchorDate = try c.decodeIfPresent(Date.self, forKey: .anchorDate)
    }
}

// 사용자 정의 마트
struct CustomMart: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String  // 마트 이름
    var patterns: [ClosurePattern]  // 여러 패턴 가능 (예: 2,4주 일요일 + 3주 수요일)
    var color: String  // 색상 hex
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, patterns: [ClosurePattern], color: String = "#FF6B6B", isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.patterns = patterns
        self.color = color
        self.isEnabled = isEnabled
    }

    // 특정 연도의 휴무일 계산 (내장·커스텀 공통 엔진에 위임)
    func calculateClosedDates(for year: Int) -> [Date] {
        ClosureRuleEngine.closedDates(patterns: patterns, year: year)
    }
}

/// 휴무 규칙(ClosurePattern) → 특정 연도의 실제 날짜 목록으로 펼치는 단일 계산 엔진.
/// 내장 마트와 커스텀 마트가 동일하게 사용한다. (예전엔 내장 마트가 별도의
/// Calendar.Weekday/Ordinal + findPatternDay 로직을 썼으나 이 엔진으로 통일)
enum ClosureRuleEngine {
    static func closedDates(patterns: [ClosurePattern], year: Int, calendar: Calendar = .current) -> [Date] {
        var closedDates: [Date] = []

        // 격주(biweekly): 기준일부터 정확히 14일 간격
        for pattern in patterns where pattern.frequency == .biweekly {
            closedDates.append(contentsOf: biweeklyDates(anchor: pattern.anchorDate, year: year, calendar: calendar))
        }

        // 주차(weekOfMonth): 매월 정해진 주차의 요일
        for month in 1...12 {
            for pattern in patterns where pattern.frequency == .weekOfMonth {
                let weekdayDates = getDatesForWeekday(pattern.weekday, inMonth: month, year: year, calendar: calendar)
                for week in pattern.weeks where week.rawValue <= weekdayDates.count {
                    closedDates.append(weekdayDates[week.rawValue - 1])
                }
            }
        }

        return closedDates.sorted()
    }

    // 격주 휴무일: anchor(기준 시작일)에서 정확히 14일 간격으로, 지정 연도에 속하는 날짜들
    private static func biweeklyDates(anchor: Date?, year: Int, calendar: Calendar) -> [Date] {
        guard let anchor else { return [] }
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let yearEnd = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) else {
            return []
        }

        var dates: [Date] = []
        var current = calendar.startOfDay(for: anchor)

        while current > yearStart {
            guard let prev = calendar.date(byAdding: .day, value: -14, to: current) else { break }
            current = prev
        }
        while current < yearStart {
            guard let next = calendar.date(byAdding: .day, value: 14, to: current) else { break }
            current = next
        }
        while current <= yearEnd {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 14, to: current) else { break }
            current = next
        }

        return dates
    }

    // 특정 월의 특정 요일 날짜들
    private static func getDatesForWeekday(_ weekday: Weekday, inMonth month: Int, year: Int, calendar: Calendar) -> [Date] {
        guard let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) else {
            return []
        }

        var dates: [Date] = []
        var currentDate = monthStart
        while currentDate <= monthEnd {
            if calendar.component(.weekday, from: currentDate) == weekday.rawValue {
                dates.append(currentDate)
            }
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }

        return dates
    }
}
