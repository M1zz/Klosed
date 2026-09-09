//
//  DontGoMartApp.swift
//  DontGoMart
//
//  Created by hyunho lee on 2023/06/15.
//

import SwiftUI
import LeeoKit

@main
struct DontGoMartApp: App {

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 앱 시작 시 즉시 tasks 초기화
        initializeTasks()
        LeeoEngagement.shared.registerLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ClosedDaysView()
                // 큰 글씨 접근성 옵션도 레이아웃이 깨지지 않는 선에서 지원.
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .leeoSatisfactionCheck(DontGoMartSpec.self)
                .onAppear {
                    WidgetManager.shared.updateWidget()
                    ReviewManager.incrementAppOpenCount()
                    ReviewManager.requestReviewIfAppropriate()

                    Task {
                        await setupSmartNotifications()
                    }

                    // 과거 Pro 구매자(후원자) 여부 확인 → 후원자 배지 표시
                    Task {
                        await SupporterManager.refresh()
                    }

                    // 익명 사용 스냅샷 (피드백과 같은 CloudKit 허브로, 12시간에 한 번)
                    AppUsage.reportSnapshot()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // 앱이 foreground 로 진입할 때마다 widget 데이터를 다시 push.
            // Provider 의 .after(nextMidnight) 정책과 함께 매일 최소 1회 갱신 보장.
            if newPhase == .active {
                WidgetManager.shared.updateWidget()
            }
        }
    }

    /// 내장 마트별 휴무 규칙. 커스텀 마트와 동일한 ClosurePattern 으로 선언한다.
    /// (예전엔 마트마다 generateBiweeklyTasks 를 명령형으로 나열했으나 데이터로 통일)
    private static let builtInMartRules: [(type: MartType, patterns: [ClosurePattern])] = [
        // 대형마트
        (.normal(type: .sunday),    [ClosurePattern(weeks: [.second, .fourth], weekday: .sunday)]),
        (.normal(type: .wednesday), [ClosurePattern(weeks: [.second, .fourth], weekday: .wednesday)]),
        (.normal(type: .mixed),     [ClosurePattern(weeks: [.second], weekday: .wednesday),
                                     ClosurePattern(weeks: [.fourth], weekday: .sunday)]),
        (.normal(type: .jeju),      [ClosurePattern(weeks: [.second], weekday: .friday),
                                     ClosurePattern(weeks: [.fourth], weekday: .saturday)]),
        // 코스트코
        (.costco(type: .normal),    [ClosurePattern(weeks: [.second, .fourth], weekday: .sunday)]),
        (.costco(type: .daegu),     [ClosurePattern(weeks: [.second, .fourth], weekday: .monday)]),
        (.costco(type: .ilsan),     [ClosurePattern(weeks: [.second, .fourth], weekday: .wednesday)]),
        (.costco(type: .ulsan),     [ClosurePattern(weeks: [.second], weekday: .wednesday),
                                     ClosurePattern(weeks: [.fourth], weekday: .sunday)]),
    ]

    private func initializeTasks() {
        // tasks 배열이 이미 초기화되어 있으면 스킵
        guard tasks.isEmpty else { return }

        let currentYear = Calendar.current.component(.year, from: Date())

        // 내장 마트: 선언형 규칙을 공통 엔진으로 펼친다 (작년~내년 3년치)
        for (martType, patterns) in Self.builtInMartRules {
            for targetYear in (currentYear - 1)...(currentYear + 1) {
                for date in ClosureRuleEngine.closedDates(patterns: patterns, year: targetYear) {
                    tasks.append(MetaMartsClosedDays(
                        type: martType,
                        task: [MartCloseData(title: martType.displayName)],
                        taskDate: date
                    ))
                }
            }
        }

        // 설날/추석 공휴일
        tasks.append(contentsOf: generateHolidayTasks(forYear: currentYear))

        // 커스텀 마트
        CustomMartManager.shared.loadCustomMarts()
        CustomMartManager.shared.updateTasksWithCustomMarts()

        debugLog("✅ Tasks 초기화 완료: \(tasks.count)개")
    }

    private func setupSmartNotifications() async {
        let notificationManager = NotificationManager.shared

        let userDefaults = UserDefaults(suiteName: Utillity.appGroupId)
        let isNotificationEnabled = userDefaults?.bool(forKey: AppStorageKeys.notificationEnabled) ?? false

        guard isNotificationEnabled else { return }

        let status = await notificationManager.checkAuthorizationStatus()

        switch status {
        case .authorized:
            await notificationManager.setupSmartNotifications(for: tasks)
        case .notDetermined:
            break
        default:
            break
        }
    }

    // 설날/추석 휴무일 생성 (음력 자동 계산 — 연도 하드코딩 없이 매년 유효)
    private func generateHolidayTasks(forYear year: Int) -> [MetaMartsClosedDays] {
        var tasks: [MetaMartsClosedDays] = []

        // 작년 ~ 내후년까지 넉넉히 (위젯 지평선 + 연말 롤오버 대비)
        for targetYear in (year - 1)...(year + 2) {
            // 설날: 음력 1월 1일, 추석: 음력 8월 15일
            let lunarHolidays: [(month: Int, day: Int, name: String)] = [
                (1, 1, "설날"),
                (8, 15, "추석")
            ]
            for holiday in lunarHolidays {
                if let date = Self.gregorianDate(lunarMonth: holiday.month, lunarDay: holiday.day, gregorianYear: targetYear) {
                    tasks.append(MetaMartsClosedDays(
                        type: .holiday,
                        task: [MartCloseData(title: holiday.name)],
                        taskDate: date
                    ))
                    debugLog("\(targetYear) - \(holiday.name) 추가")
                }
            }
        }

        return tasks
    }

    /// 음력(月/日)을 해당 양력 연도의 그레고리력 날짜로 변환.
    /// Foundation 의 중국식 음력(.chinese)이 한국 설날/추석과 동일한 규칙이라 이를 사용한다.
    /// 윤달(isLeapMonth)은 제외해 평달 기준으로 찾는다.
    static func gregorianDate(lunarMonth: Int, lunarDay: Int, gregorianYear: Int) -> Date? {
        var gregorian = Calendar(identifier: .gregorian)
        let seoul = TimeZone(identifier: "Asia/Seoul") ?? .current
        gregorian.timeZone = seoul
        var lunar = Calendar(identifier: .chinese)
        lunar.timeZone = seoul

        guard let yearStart = gregorian.date(from: DateComponents(year: gregorianYear, month: 1, day: 1)) else {
            return nil
        }
        for offset in 0..<366 {
            guard let candidate = gregorian.date(byAdding: .day, value: offset, to: yearStart) else { continue }
            let comps = lunar.dateComponents([.month, .day, .isLeapMonth], from: candidate)
            if comps.month == lunarMonth,
               comps.day == lunarDay,
               (comps.isLeapMonth ?? false) == false {
                return gregorian.startOfDay(for: candidate)
            }
        }
        return nil
    }
}
