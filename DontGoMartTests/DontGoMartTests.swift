//
//  DontGoMartTests.swift
//  DontGoMartTests
//
//  Created by 황석현 on 11/18/24.
//

import Foundation
import Testing
import StoreKit
import StoreKitTest
import LeeoKit
@testable import DontGoMart

struct DontGoMartTests {

    /// LeeoKit 계약(LeeoAppSpec)이 배포 가능한 상태인지.
    ///
    /// Preflight 는 "무료 모델인데 페이월을 선언했다", "privacyURL 이 https 가 아니다" 처럼
    /// 컴파일은 되지만 심사·운영에서 터지는 모순을 잡는다. LeeoKit 을 올릴 때 계약이
    /// 조용히 어긋나는 걸 여기서 막는다.
    @Test func specIsReleasable() {
        let issues = LeeoPreflight.audit(DontGoMartSpec.self)
        let errors = issues.filter { $0.severity == .error }
        #expect(errors.isEmpty, "계약 오류: \(errors.map(\.message).joined(separator: " / "))")
    }

    /// 2·4주 수요일 휴무 규칙이 단일 엔진에서 올바른 날짜를 내는지.
    /// (구 generateBiweeklyTasks 테스트를 ClosureRuleEngine 기준으로 대체)
    @Test func biweeklyWednesdayRule() {
        let patterns = [ClosurePattern(weeks: [.second, .fourth], weekday: .wednesday)]
        let dates2024 = ClosureRuleEngine.closedDates(patterns: patterns, year: 2024).sorted()

        // 매월 2·4번째 수요일 → 12개월 × 2 = 24건
        #expect(dates2024.count == 24)

        // 2024년 1월의 둘째 수요일은 1월 10일
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let comps = calendar.dateComponents([.month, .day], from: dates2024[0])
        #expect(comps.month == 1)
        #expect(comps.day == 10)
    }

    /// 팁 상품 3종(소모성)이 StoreKit 설정에서 실제로 로드되는지.
    /// 앱의 CoffeeTipStore 가 쓰는 것과 동일한 상품 ID 목록으로 확인한다.
    @Test func tipProductsLoad() async throws {
        let session = try SKTestSession(configurationFileNamed: "CoffeeConfiguration")
        session.disableDialogs = true
        defer { session.clearTransactions() }

        let products = try await Product.products(for: SupporterManager.tipProductIDs)
        #expect(products.count == 3)

        // 가격 오름차순 첫 상품(메인 카드의 원탭 구매 대상)은 커피여야 한다
        let sorted = products.sorted { $0.price < $1.price }
        #expect(sorted.first?.id == "com.dontgomart.tip.coffee")

        // 전 상품이 소모성(반복 결제 가능)이어야 한다
        for product in products {
            #expect(product.type == .consumable)
        }
    }
}
