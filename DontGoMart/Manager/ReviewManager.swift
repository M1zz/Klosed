//
//  ReviewManager.swift
//  DontGoMart
//
//  Created by Claude on 2025/01/29.
//

import StoreKit
import SwiftUI
import UIKit

enum ReviewManager {
    private static let appOpenCountKey = "appOpenCount"
    private static let lastReviewRequestDateKey = "lastReviewRequestDate"
    private static let meaningfulActionsCountKey = "meaningfulActionsCount"
    private static let hasRequestedReviewKey = "hasRequestedReview"

    // App Store ID — DontGoMartSpec 과 같은 값을 써야 한다(두 곳에 다른 ID 가 있으면
    // 한쪽은 반드시 죽은 링크가 된다).
    private static let appStoreId = "6450387984"

    // 리뷰 요청 조건
    private static let minimumAppOpens = 5
    private static let minimumMeaningfulActions = 3
    private static let daysBetweenRequests = 90

    // MARK: - 앱 실행 횟수 관리

    /// 커피 후원 카드(CoffeeTipPrompt)도 리뷰와 동일한 신뢰 게이트를 쓰도록 공개한다.
    static var appOpenCount: Int {
        UserDefaults.standard.integer(forKey: appOpenCountKey)
    }

    static var meaningfulActionsCount: Int {
        UserDefaults.standard.integer(forKey: meaningfulActionsCountKey)
    }

    static func incrementAppOpenCount() {
        let defaults = UserDefaults.standard
        let currentCount = defaults.integer(forKey: appOpenCountKey)
        defaults.set(currentCount + 1, forKey: appOpenCountKey)
    }

    // MARK: - 유의미한 사용 추적

    /// 사용자가 유의미한 액션을 했을 때 호출 (휴무일 확인, 알림 설정 등)
    static func trackMeaningfulAction() {
        let defaults = UserDefaults.standard
        let currentCount = defaults.integer(forKey: meaningfulActionsCountKey)
        defaults.set(currentCount + 1, forKey: meaningfulActionsCountKey)
    }

    // MARK: - 인앱 리뷰 요청 (SKStoreReviewController)

    static func requestReviewIfAppropriate() {
        let defaults = UserDefaults.standard
        let appOpenCount = defaults.integer(forKey: appOpenCountKey)
        let meaningfulActions = defaults.integer(forKey: meaningfulActionsCountKey)

        // 앱을 최소 횟수 이상 열지 않았으면 요청하지 않음
        guard appOpenCount >= minimumAppOpens else { return }

        // 유의미한 액션을 최소 횟수 이상 하지 않았으면 요청하지 않음
        guard meaningfulActions >= minimumMeaningfulActions else { return }

        // 마지막 리뷰 요청 이후 충분한 시간이 지났는지 확인
        if let lastRequestDate = defaults.object(forKey: lastReviewRequestDateKey) as? Date {
            let daysSinceLastRequest = Calendar.current.dateComponents([.day], from: lastRequestDate, to: Date()).day ?? 0
            guard daysSinceLastRequest >= daysBetweenRequests else { return }
        }

        // 리뷰 요청
        requestReview()

        // 마지막 요청 날짜 저장
        defaults.set(Date(), forKey: lastReviewRequestDateKey)
    }

    private static func requestReview() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: windowScene)
        }
    }

    // MARK: - 앱스토어 리뷰 페이지 열기 (사용자 주도)

    /// 앱스토어 리뷰 작성 페이지로 직접 이동
    static func openAppStoreForReview() {
        guard let url = URL(string: "https://apps.apple.com/app/id\(appStoreId)?action=write-review") else {
            return
        }
        UIApplication.shared.open(url)
    }

    /// 앱스토어 앱 페이지로 이동
    static func openAppStorePage() {
        guard let url = URL(string: "https://apps.apple.com/app/id\(appStoreId)") else {
            return
        }
        UIApplication.shared.open(url)
    }
}
