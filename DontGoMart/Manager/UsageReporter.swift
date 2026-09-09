//
//  UsageReporter.swift
//  DontGoMart
//
//  익명 사용 통계 — 피드백과 같은 CloudKit 허브(iCloud.com.Ysoup.FeedbackHub)로 보낸다.
//  외부 분석 SDK 없이, 앱이 실제로 쓰이는지만 알기 위한 최소한의 계측이다.
//
//  보내는 것:
//    · 설치당 스냅샷 1개 (UsageSnapshot, 12시간에 한 번 덮어쓰기)
//      — 실행 횟수·설치 후 경과일·앱 버전·OS·로케일 + 아래 metrics
//    · 주요 행동 이벤트 (UsageEvent) — 공유·캘린더·마트 변경·후원 등
//
//  보내지 않는 것: 이름·이메일·기기 식별자 등 개인 식별 정보.
//  설치 식별은 기기·계정과 무관한 무작위 UUID(LeeoKit 이 만든다)라 재설치하면 새 사람이 된다.
//

import Foundation
import LeeoKit

enum AppUsage {

    /// 이 앱이 남기는 이벤트 이름.
    /// 호출부마다 문자열을 적으면 오타 하나가 대시보드에서 별개 이벤트가 되므로 여기서만 정의한다.
    enum Event: String {
        /// 휴무 소식 카드를 공유했다 (이 앱의 핵심 가치가 밖으로 나가는 순간)
        case share
        /// 휴무일 캘린더를 열었다
        case calendar
        /// 추적할 마트를 바꿨다
        case martChanged = "mart_changed"
        /// 나만의 마트를 저장했다
        case customMartSaved = "custom_mart_saved"
        /// 휴무 알림을 켰다
        case notificationOn = "notification_on"
        /// 후원이 완료됐다
        case tip
    }

    private static var reporter: LeeoUsageReporter {
        LeeoUsageReporter(spec: DontGoMartSpec.self)
    }

    /// 앱 시작 시 1회. 설치당 스냅샷 하나를 갱신한다(LeeoKit 이 12시간 간격으로 제한한다).
    static func reportSnapshot() {
        reporter.reportInBackground(metrics: metrics())
    }

    /// 같은 이벤트를 다시 보내기까지의 최소 간격.
    /// 캘린더 버튼처럼 한 자리에서 여러 번 눌리는 행동이 CloudKit 쓰기로 그대로 나가면
    /// 레코드가 폭발하고 "몇 번 눌렸나" 라는, 어차피 판단에 못 쓰는 숫자만 쌓인다.
    /// 보고 싶은 건 "이 설치가 이 행동을 하는가" 라서 하루 몇 건이면 충분하다.
    /// (LeeoUsageReporter 는 스냅샷만 쓰로틀하고 이벤트는 부르는 대로 보낸다 — 앱이 건다.)
    private static let eventInterval: TimeInterval = 6 * 3600

    /// 의미 있는 행동 1건.
    /// LeeoEngagement 카운트도 함께 올린다 — 만족도 프롬프트(`.leeoSatisfactionCheck`)와
    /// 리뷰 게이트가 이 수치를 보고 '충분히 써 본 사용자'인지 판단한다.
    /// 카운트는 매번 올리고, CloudKit 전송만 이벤트별로 6시간에 한 번으로 줄인다.
    static func log(_ event: Event) {
        _ = LeeoEngagement.shared.registerSignificantEvent()

        let key = "leeo.usage.lastEventAt.\(event.rawValue)"
        let defaults = UserDefaults.standard
        let last = defaults.double(forKey: key)
        let now = Date().timeIntervalSince1970
        guard last <= 0 || now - last >= eventInterval else { return }
        defaults.set(now, forKey: key)

        reporter.logEventInBackground(event.rawValue)
    }

    /// 이 앱만의 대략 지표. 스냅샷의 `metrics` JSON 한 칸에 담겨 스키마 필드를 늘리지 않는다.
    ///
    /// 매니저(MartSelectionManager 등)를 거치지 않고 App Group UserDefaults 를 직접 읽는다 —
    /// 앱 시작 직후 어느 스레드에서 불려도 안전해야 하고, 통계 때문에 매니저를 깨울 이유도 없다.
    private static func metrics() -> [String: Double] {
        let shared = UserDefaults(suiteName: Utillity.appGroupId)
        let local = UserDefaults.standard

        var out: [String: Double] = [:]

        // 추적 중인 마트 수 — 0이면 앱을 설치만 하고 설정을 안 한 사람이다
        if let keys = shared?.array(forKey: AppStorageKeys.selectedMartTypes) as? [String] {
            out["marts"] = Double(keys.count)
        } else {
            out["marts"] = 0
        }

        // 직접 만든 마트 수
        if let data = shared?.data(forKey: "customMarts"),
           let list = try? JSONDecoder().decode([CustomMart].self, from: data) {
            out["customMarts"] = Double(list.count)
        } else {
            out["customMarts"] = 0
        }

        // 알림을 실제로 쓰는가 (켬 여부 + 며칠 전 알림 + 전날 알림)
        let notificationOn = shared?.bool(forKey: AppStorageKeys.notificationEnabled) ?? false
        out["notification"] = notificationOn ? 1 : 0
        if notificationOn {
            out["leadDays"] = Double(NotificationManager.leadDays)
            out["beforeDay"] = NotificationManager.shared.beforeDayNotificationEnabled ? 1 : 0
        }

        // 누적 후원 횟수 (0이 대부분이다 — 후원자 비율을 보기 위한 값)
        out["tips"] = Double(local.integer(forKey: AppStorageKeys.tipCount))

        return out
    }
}
