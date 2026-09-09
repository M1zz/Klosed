//
//  DontGoMartSpec.swift
//  DontGoMart
//

import Foundation
import LeeoKit

enum DontGoMartSpec: LeeoAppSpec {
    static let appName = "돈꼬마트"
    static let developerEmail = "mizzking75@gmail.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.FeedbackHub", appIdentifier: "com.leeo.DontGoMart")

    /// App Store 숫자 ID. 있어야 설정의 '리뷰 남기기' 가 시스템 평점 팝업 대신
    /// 실제 리뷰 작성 페이지로 간다 (ReviewManager 가 쓰던 것과 같은 ID).
    static let appStoreID: String? = "6450679498"

    /// 인앱 결제 설정 — 여기서 공용 스토어(LeeoStore)에 맡기는 건 '후원자 배지의 근거'가 되는
    /// 과거 비소비성 커피(레거시) 권한 판정뿐이다. StoreKit 2 의 currentEntitlements 순회·검증을
    /// LeeoKit 이 대신하고, 앱은 소유 여부만 읽는다.
    ///
    /// 신규로 파는 소모성 팁(coffee/cake/meal)은 여기 넣지 않는다 — 잔액 모델이 아니라
    /// '후원 카운트 + iCloud 미러링 + 감사 연출' 이라는 앱 고유 로직이라 CoffeeTipStore 가 직접 다룬다.
    static let paywall: LeeoPaywallConfig? = LeeoPaywallConfig(
        productIDs: [SupporterManager.legacyProductID],
        cacheSuiteName: Utillity.appGroupId
    )
}
