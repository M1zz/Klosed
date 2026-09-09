import SwiftUI
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}
        
    private enum Constants {
        /// iOS 알림 제한 안전 임계값 (실제 제한: 64개)
        static let maxSafeNotificationCount = 60
        /// 알림 설정할 최대 일수 (앞으로 1년)
        static let maxNotificationDays = 365
    }
    
    // MARK: - Configuration Properties

    /// 선택 가능한 리드타임 프리셋(휴무 며칠 전 알림).
    static let leadDayPresets: [Int] = [1, 2, 3, 7]
    /// 기본 리드타임(일).
    static let defaultLeadDays: Int = 3

    /// 주 알림 리드타임(휴무 며칠 전). 사용자 설정, 미설정 시 기본값.
    static var leadDays: Int {
        let defaults = UserDefaults(suiteName: Utillity.appGroupId)
        guard defaults?.object(forKey: AppStorageKeys.notificationLeadDays) != nil else {
            return defaultLeadDays
        }
        let stored = defaults?.integer(forKey: AppStorageKeys.notificationLeadDays) ?? defaultLeadDays
        return leadDayPresets.contains(stored) ? stored : defaultLeadDays
    }

    /// 기본 알림 시각 — 설정 화면(@AppStorage)의 기본값과 반드시 같아야 한다.
    static let defaultNotificationHour = 9
    static let defaultNotificationMinute = 0

    /// 사용자 설정 알림 시간 가져오기.
    ///
    /// `integer(forKey:)` 는 값이 없을 때 0 을 돌려주므로 `?? 9` 로는 기본값을 줄 수 없다.
    /// (설정 화면은 @AppStorage 기본값 09:00 을 보여주는데 실제 알림은 00:00 에 가던 버그)
    /// 저장된 적이 있는지 `object(forKey:)` 로 먼저 확인한다.
    var notificationHour: Int {
        storedInt(AppStorageKeys.notificationHour, default: Self.defaultNotificationHour)
    }

    var notificationMinute: Int {
        storedInt(AppStorageKeys.notificationMinute, default: Self.defaultNotificationMinute)
    }

    /// 전날 '장보기 좋은 날' 알림. 설정 화면 기본값이 켜짐이므로 저장 전에도 켜짐으로 읽는다.
    /// (`bool(forKey:)` 는 값이 없으면 false 라, 화면은 켜짐인데 알림은 안 오던 버그)
    var beforeDayNotificationEnabled: Bool {
        let defaults = UserDefaults(suiteName: Utillity.appGroupId)
        guard let defaults, defaults.object(forKey: AppStorageKeys.beforeDayNotificationEnabled) != nil else {
            return true
        }
        return defaults.bool(forKey: AppStorageKeys.beforeDayNotificationEnabled)
    }

    /// 저장된 적 없는 키는 0 이 아니라 기본값으로 읽는다.
    private func storedInt(_ key: String, default fallback: Int) -> Int {
        let defaults = UserDefaults(suiteName: Utillity.appGroupId)
        guard let defaults, defaults.object(forKey: key) != nil else { return fallback }
        return defaults.integer(forKey: key)
    }
    
    // MARK: - Notification Types

    enum NotificationType: String, CaseIterable {
        /// 주 알림: 설정한 리드타임(N일 전)에 발송.
        case primary = "day1_before"
        /// 전날 '장보기 좋은 날' 알림 (사용자 토글).
        case beforeDayNotification = "before_day"

        var title: String {
            switch self {
            case .primary:
                return String(localized: "마트 휴무일 안내", defaultValue: "Store Closure Notice")
            case .beforeDayNotification:
                return String(localized: "🛒 장보기 좋은 날_notif", defaultValue: "🛒 Good Day to Shop")
            }
        }

        func body(for martType: MartType) -> String {
            let storeName = martType.notificationStoreName
            switch self {
            case .primary:
                let format = String(localized: "notification_first_body", defaultValue: "%@ will be closed in %lld days.")
                return String(format: format, storeName, NotificationManager.leadDays)
            case .beforeDayNotification:
                let format = String(localized: "notification_before_body", defaultValue: "%@ is closed tomorrow. Today is a good day to shop!")
                return String(format: format, storeName)
            }
        }

        var daysToSubtract: Int {
            switch self {
            case .primary:
                return NotificationManager.leadDays
            case .beforeDayNotification:
                return 1
            }
        }
    }
    
    // MARK: - Authorization Management
    
    /// 알림 권한 요청
    func requestAuthorization() async -> Bool {
        do {
            let authorized = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            
            if authorized {
                debugLog("✅ 알림 권한이 허용되었습니다.")
            } else {
                debugLog("❌ 알림 권한이 거부되었습니다.")
            }
            
            return authorized
        } catch {
            debugLog("❌ 알림 권한 요청 중 오류: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 현재 알림 권한 상태 확인
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }
    
    // MARK: - Smart Notification Setup
    
    /// 사용자 선택 매장의 가까운 미래 휴무일에 대해서만 알림 설정 (iOS 64개 제한 고려)
    func setupSmartNotifications(for allTasks: [MetaMartsClosedDays]) async {
        guard await validateNotificationPrerequisites() else { return }
        
        clearExistingNotifications()
        
        let targetTasks = await filterNotificationTargets(from: allTasks)
        let scheduledCount = await scheduleNotificationsForTasks(targetTasks)
        
        await validateAndLogResults(scheduledCount: scheduledCount)
    }
    
    // MARK: - Private Methods
    
    /// 1단계: 알림 설정 사전 조건 확인
    private func validateNotificationPrerequisites() async -> Bool {
        // 사용자 알림 설정 확인
        let userDefaults = UserDefaults(suiteName: Utillity.appGroupId)
        let isNotificationEnabled = userDefaults?.bool(forKey: AppStorageKeys.notificationEnabled) ?? false
        
        guard isNotificationEnabled else {
            return false
        }
        
        // 권한 확인
        let status = await checkAuthorizationStatus()
        guard status == .authorized else {
            debugLog("❌ 알림 권한이 없어 알림을 설정할 수 없습니다.")
            return false
        }
        
        return true
    }
    
    /// 2단계: 기존 알림 정리
    private func clearExistingNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    /// 3단계: 알림 대상 필터링
    private func filterNotificationTargets(from allTasks: [MetaMartsClosedDays]) async -> [MetaMartsClosedDays] {
        // 사용자 선택 매장만 필터링
        let userSelectedTasks = filterUserSelectedTasks(from: allTasks)
        
        // 가까운 미래의 휴무일만 필터링
        let nearFutureTasks = filterNearFutureTasks(from: userSelectedTasks)
        
        return nearFutureTasks
    }
    
    /// 4단계: 알림 스케줄링 실행
    private func scheduleNotificationsForTasks(_ tasks: [MetaMartsClosedDays]) async -> Int {
        var scheduledCount = 0

        // '장보기 좋은 날'(전날) 알림은 사용자 토글에 따라 포함/제외.
        let types: [NotificationType] = beforeDayNotificationEnabled
            ? NotificationType.allCases
            : [.primary]

        // 가까운 날짜부터 채우고 안전 임계값에서 멈춘다.
        // (iOS 는 앱당 64개까지만 보관한다 — 넘기면 OS 가 조용히 버려서
        //  '가끔 알림이 안 온다' 로 보인다. 먼 미래를 포기하고 가까운 날을 지킨다.)
        outer: for task in tasks {
            for notificationType in types {
                guard scheduledCount < Constants.maxSafeNotificationCount else {
                    debugLog("ℹ️ 알림 상한(\(Constants.maxSafeNotificationCount)개) 도달 — 이후 휴무일은 앱 실행 시 다시 채웁니다.")
                    break outer
                }
                let success = await scheduleNotification(
                    for: task.taskDate,
                    type: notificationType,
                    martType: task.type
                )
                if success {
                    scheduledCount += 1
                }
            }
        }
        
        return scheduledCount
    }
    
    /// 5단계: 결과 검증 및 로깅
    private func validateAndLogResults(scheduledCount: Int) async {
        // iOS 64개 제한 체크
        if scheduledCount > Constants.maxSafeNotificationCount {
            debugLog("⚠️ 알림 개수가 많습니다 (\(scheduledCount)개). iOS 제한으로 일부 알림이 누락될 수 있습니다.")
        }
    }
    
    /// 사용자가 선택한 매장의 휴무일만 필터링
    private func filterUserSelectedTasks(from tasks: [MetaMartsClosedDays]) -> [MetaMartsClosedDays] {
        // MartSelectionManager를 사용하여 선택된 마트 타입 가져오기
        let martSelection = MartSelectionManager.shared
        let selectedMartTypes = martSelection.getSelectedMartTypes()

        return tasks.filter { task in
            selectedMartTypes.contains(task.type)
        }
    }
    
    /// 가까운 미래의 휴무일만 필터링 (앞으로 90일)
    private func filterNearFutureTasks(from tasks: [MetaMartsClosedDays]) -> [MetaMartsClosedDays] {
        let today = Date()
        let futureLimit = Calendar.current.date(byAdding: .day, value: Constants.maxNotificationDays, to: today)!
        
        return tasks.filter { task in
            task.taskDate >= today && task.taskDate <= futureLimit
        }.sorted { $0.taskDate < $1.taskDate }
    }
    
    /// 개별 알림 스케줄링
    private func scheduleNotification(
        for closedDate: Date,
        type: NotificationType,
        martType: MartType
    ) async -> Bool {
        // 알림 날짜 계산
        guard let notificationDate = Calendar.current.date(
            byAdding: .day,
            value: -type.daysToSubtract,
            to: closedDate
        ) else {
            debugLog("❌ 알림 날짜 계산 실패: \(closedDate)")
            return false
        }
        
        // 알림 시간 설정 (사용자 설정 시간 사용)
        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: notificationDate)
        dateComponents.hour = self.notificationHour
        dateComponents.minute = self.notificationMinute
        dateComponents.second = 0
        
        guard let finalNotificationDate = Calendar.current.date(from: dateComponents) else {
            debugLog("❌ 최종 알림 시간 계산 실패")
            return false
        }
        
        // 과거 시간은 스킵
        if finalNotificationDate <= Date() {
            return false
        }
        
        // 알림 콘텐츠 생성
        let content = UNMutableNotificationContent()
        content.title = type.title
        content.body = type.body(for: martType)
        content.sound = .default
        
        // 메타데이터 추가
        content.categoryIdentifier = "MART_CLOSURE"
        content.userInfo = [
            "martType": martType.widgetDisplayName,
            "closedDate": ISO8601DateFormatter().string(from: closedDate),
            "notificationType": type.rawValue
        ]
        
        // 트리거 생성
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: false
        )
        
        // 고유 식별자 생성
        let identifier = generateIdentifier(
            for: closedDate,
            type: type,
            martType: martType
        )
        
        // 알림 요청 생성 및 등록
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
            
        } catch {
            debugLog("❌ 알림 설정 실패: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Utility Methods
    
    /// 알림 식별자 생성
    private func generateIdentifier(
        for closedDate: Date,
        type: NotificationType,
        martType: MartType
    ) -> String {
        let dateString = ISO8601DateFormatter().string(from: closedDate)
        let martTypeString = martType.widgetDisplayName.replacingOccurrences(of: " ", with: "_")
        return "mart_\(martTypeString)_\(dateString)_\(type.rawValue)"
    }
    
    /// 모든 알림 취소
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
