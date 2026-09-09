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
    /// 실제 리뷰 작성 페이지로 간다.
    static let appStoreID: String? = "6450387984"

    /// 개인정보·지원 링크. GitHub Pages 로 올려 둔 페이지들이다(레포의 docs/).
    /// 설정 ▸ 지원 섹션이 이 선언에서 링크 행을 만든다 — 앱이 따로 넣지 않아도 항상 있다.
    static let legal = LeeoLegalConfig(
        privacyURL: URL(string: "https://m1zz.github.io/DontGoMart/privacy.html")!,
        supportURL: URL(string: "https://m1zz.github.io/DontGoMart/support.html")!,
        marketingURL: URL(string: "https://m1zz.github.io/DontGoMart/")!
    )

    /// 수익모델 — 전 기능 무료다. 페이월이 없고, 잠긴 기능도 없다.
    ///
    /// 파는 소모성 팁(coffee/cake/meal)이 있지만 `.credits` 가 아니다. 크레딧은 쓸 때마다
    /// 차감되는 잔액 모델인데, 이 앱의 팁은 차감되지 않는 순수 후원이라 '감사 연출 + 후원자
    /// 배지' 라는 앱 고유 로직(CoffeeTipStore)이 직접 다룬다. 결제가 기능을 열지 않으므로
    /// 계약상으로는 무료 앱이 맞다.
    static let monetization = LeeoMonetization.free
}
