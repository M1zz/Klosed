//
//  StoreKitManager.swift
//  DontGoMart
//
//  Created by hyunho lee on 2023/06/21.
//

import Foundation
import StoreKit
import UIKit
import LeeoKit

/// 후원자 판별과 누적 후원 횟수를 관리한다.
///
/// 전 기능은 무료이고, 팁 IAP 는 기능 잠금이 아니라 순수 후원이다.
/// 후원자에게는 감사 표시(후원자 배지 + ☕️ 카운트)만 제공한다.
///
/// 영속화 전략:
/// - 과거 비소비성(com.dontgomart.Coffee) 구매자는 Apple 이 구매 기록을 영구 보관하므로
///   `Transaction.currentEntitlements` 로 재설치·기기 변경 후에도 복원된다.
/// - 새 팁은 소모성(Consumable)이라 entitlement 에 남지 않으므로,
///   로컬 UserDefaults + iCloud Key-Value Store 에 미러링해 재설치에도 유지한다.
enum SupporterManager {
    /// 과거 비소비성 커피 상품 (배지 복원 앵커, 신규 판매 없음)
    static let legacyProductID = "com.dontgomart.Coffee"

    /// 신규 판매하는 소모성 팁 상품들 (가격 오름차순 의도)
    static let tipProductIDs: [String] = [
        "com.dontgomart.tip.coffee",
        "com.dontgomart.tip.cake",
        "com.dontgomart.tip.meal",
    ]

    /// 후원으로 인정하는 전체 상품 ID
    static var allSupporterProductIDs: Set<String> {
        Set(tipProductIDs).union([legacyProductID])
    }

    /// 과거 비소비성 커피(레거시) 권한을 판정하는 공용 스토어.
    /// StoreKit 2 의 `Transaction.currentEntitlements` 순회·서명 검증은
    /// LeeoKit 의 `LeeoStore` 가 담당한다. 여기서는 소유 여부만 읽어 쓴다.
    /// (소모성 팁은 아래 CoffeeTipStore 가 앱 고유 로직으로 계속 직접 처리한다.)
    ///
    /// 구성을 Spec 이 아니라 여기서 만드는 이유: 이 앱은 `.free` 라 페이월이 없다.
    /// Spec 에 paywall 을 선언하면 "무료 모델인데 페이월이 있다" 는 모순이 되어
    /// Preflight 가 오류로 잡는다. 이건 파는 화면이 아니라 옛 구매자를 알아보는 조회일 뿐이다.
    @MainActor
    static let entitlementStore = LeeoStore(config: LeeoPaywallConfig(
        productIDs: [legacyProductID],
        cacheSuiteName: Utillity.appGroupId
    ))

    /// 상품별 대표 이모지 (목록 행·구매 성공 연출 공용)
    static func emoji(for productID: String) -> String {
        switch productID {
        case "com.dontgomart.tip.cake": return "🍰"
        case "com.dontgomart.tip.meal": return "🍱"
        default: return "☕️"
        }
    }

    /// 현재 후원자 배지를 표시해야 하는지.
    static var isSupporter: Bool {
        UserDefaults.standard.bool(forKey: AppStorageKeys.isLegacySupporter)
    }

    /// 누적 후원 횟수 (배지에 ☕️ ×N 으로 표시)
    static var tipCount: Int {
        UserDefaults.standard.integer(forKey: AppStorageKeys.tipCount)
    }

    /// 팁 1건을 기록한다: 카운트 증가 + 후원자 플래그 + iCloud 미러링.
    @MainActor
    static func recordTip() {
        let defaults = UserDefaults.standard
        let kvs = NSUbiquitousKeyValueStore.default

        // 다른 기기에서 후원한 기록이 iCloud 에 있으면 큰 쪽 기준으로 누적한다
        let mergedBase = max(defaults.integer(forKey: AppStorageKeys.tipCount),
                             Int(kvs.longLong(forKey: AppStorageKeys.tipCount)))
        let newCount = mergedBase + 1

        defaults.set(newCount, forKey: AppStorageKeys.tipCount)
        defaults.set(true, forKey: AppStorageKeys.isLegacySupporter)
        kvs.set(Int64(newCount), forKey: AppStorageKeys.tipCount)
        kvs.set(true, forKey: AppStorageKeys.isLegacySupporter)
        kvs.synchronize()

        // 방금 구매 감사 연출을 봤으므로, 감사 리마인더 주기의 기준점을 오늘로 맞춘다
        defaults.set(Date().timeIntervalSince1970, forKey: AppStorageKeys.supporterThanksShownAt)
    }

    /// 앱 시작 시 후원자 상태를 복원한다.
    /// 1) 과거 비소비성 구매 → entitlement 로 확인
    /// 2) 소모성 팁 → iCloud KVS 와 로컬 중 큰 값으로 병합
    /// 한 번 후원자로 인정되면 유지한다(환불·오프라인 등으로 인사가 사라지지 않도록 회수하지 않음).
    static func refresh() async {
        // 과거 비소비성 커피 권한 확인을 공용 스토어(LeeoStore)에 위임한다.
        // (StoreKit 순회·검증은 LeeoKit 이 처리하고, 우리는 결과만 읽는다.)
        await entitlementStore.refreshEntitlements()

        await MainActor.run {
            let legacy = entitlementStore.purchasedProductIDs.contains(legacyProductID)
            let defaults = UserDefaults.standard
            let kvs = NSUbiquitousKeyValueStore.default
            kvs.synchronize()

            var count = max(defaults.integer(forKey: AppStorageKeys.tipCount),
                            Int(kvs.longLong(forKey: AppStorageKeys.tipCount)))
            var supporter = legacy
                || defaults.bool(forKey: AppStorageKeys.isLegacySupporter)
                || kvs.bool(forKey: AppStorageKeys.isLegacySupporter)

            // 과거 비소비성 구매자는 커피 1잔으로 쳐준다 (카운트 기록이 없던 시절 구매)
            if legacy && count == 0 {
                count = 1
            }
            if count > 0 {
                supporter = true
            }

            defaults.set(count, forKey: AppStorageKeys.tipCount)
            defaults.set(supporter, forKey: AppStorageKeys.isLegacySupporter)
            if supporter {
                kvs.set(Int64(count), forKey: AppStorageKeys.tipCount)
                kvs.set(true, forKey: AppStorageKeys.isLegacySupporter)
                kvs.synchronize()
            }
        }
    }
}

// MARK: - CoffeeTipStore (팁 구매)

/// 팁 IAP 의 상품 로드·구매를 담당한다.
///
/// 결제는 '기능 획득' 이 아니라 '감사' 의 순간에 일어난다는 전제로,
/// 메인 화면의 노출 시점은 `CoffeeTipPrompt` 가 판정한다.
/// 소모성 상품이라 같은 상품을 여러 번 결제할 수 있다.
@MainActor
final class CoffeeTipStore: ObservableObject {
    static let shared = CoffeeTipStore()

    /// 팁 상품들(가격 오름차순). 네트워크/StoreKit 설정이 없으면 빈 배열 (이때 메인 화면 카드는 숨긴다).
    @Published private(set) var tipProducts: [Product] = []
    @Published private(set) var isPurchasing = false
    /// 방금 구매를 마쳤을 때 잠깐 감사 메시지를 보여주기 위한 플래그.
    @Published private(set) var justThanked = false
    /// 구매 성공 연출 트리거 — 성공할 때마다 1 증가하고, 화면은 onChange 로
    /// 콘페티 + 감사 카드(TipCelebrationView)를 재생한다 (심사 2.1 '구매 무반응' 대응).
    @Published private(set) var celebrationCount = 0
    /// 방금 후원받은 상품 ID (연출 이모지 선택용)
    @Published private(set) var lastTippedProductID: String?
    /// 상품 로드 진행 상태. 설정 화면은 실패 시 '다시 시도' 를 노출한다
    /// (심사 리젝 2.1(b) 대응 — 로드 실패로 화면이 무반응처럼 보이지 않게).
    enum ProductLoadState { case loading, loaded, failed }
    @Published private(set) var loadState: ProductLoadState = .loading
    /// 구매 실패·승인 대기 등 사용자에게 알려야 하는 결과. 알림으로 표시 후 nil 로 되돌린다.
    @Published var userMessage: String?

    /// 메인 화면 카드에서 쓰는 기본(최저가) 팁 = 커피 한 잔.
    var coffeeTip: Product? { tipProducts.first }

    private var updatesTask: Task<Void, Never>?

    private init() {
        // 구매 도중 앱 종료·Ask to Buy 승인 등으로 뒤늦게 도착하는 트랜잭션 처리
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(transactionResult: result)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProductsIfNeeded() async {
        guard tipProducts.isEmpty else { return }
        loadState = .loading
        do {
            let products = try await Product.products(for: SupporterManager.tipProductIDs)
            tipProducts = products.sorted { $0.price < $1.price }
        } catch {
            debugLog("❌ 팁 상품 로드 실패: \(error)")
        }
        // 스토어가 상품 0개를 돌려준 경우(미등록 등)도 실패로 취급해 재시도를 열어둔다
        loadState = tipProducts.isEmpty ? .failed : .loaded

        // 이전 실행에서 finish 되지 못한 트랜잭션이 있으면 마저 처리한다
        for await result in Transaction.unfinished {
            await handle(transactionResult: result)
        }
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    SupporterManager.recordTip()
                    justThanked = true
                    celebrate(productID: transaction.productID)
                } else {
                    userMessage = "구매를 확인하지 못했어요. 잠시 후 다시 시도해주세요."
                }
            case .pending:
                // Ask to Buy 등 승인 대기 — 승인되면 Transaction.updates 리스너가 반영한다
                userMessage = "구매 승인을 기다리고 있어요. 승인되면 자동으로 반영됩니다."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            debugLog("❌ 팁 구매 실패: \(error)")
            userMessage = "구매 중 문제가 발생했어요. 잠시 후 다시 시도해주세요."
        }
    }

    /// purchase() 직접 경로 밖에서 도착한 트랜잭션(미완료 복구, Ask to Buy 승인 등) 처리.
    private func handle(transactionResult result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        guard SupporterManager.allSupporterProductIDs.contains(transaction.productID) else { return }
        guard transaction.revocationDate == nil else { return }

        // 소모성 팁만 카운트한다 (비소비성 legacy 는 refresh() 의 entitlement 복원이 담당)
        if SupporterManager.tipProductIDs.contains(transaction.productID) {
            SupporterManager.recordTip()
            justThanked = true
            celebrate(productID: transaction.productID)
        }
        await transaction.finish()
    }

    /// 구매 성공 순간의 즉각 피드백: 연출 트리거 + 성공 햅틱 + VoiceOver 안내.
    /// 시각 연출(콘페티·감사 카드)은 `.tipCelebrationOverlay()` 를 붙인 화면이 재생한다.
    private func celebrate(productID: String) {
        lastTippedProductID = productID
        celebrationCount += 1
        AppUsage.log(.tip)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(
            notification: .announcement,
            argument: String(
                localized: "후원해주셔서 정말 감사합니다. 보내주신 응원이 큰 힘이 됩니다.",
                defaultValue: "Thank you so much for your support. It means a lot."
            )
        )
    }
}

// MARK: - CoffeeTipPrompt (후원 카드 노출 판정)

/// 커피 후원 카드를 '언제' 보여줄지 판정한다.
///
/// 원칙: 기능이 아니라 감사에 과금한다. 감사가 정점인 순간은
/// 앱이 헛걸음을 막아준 순간(= 오늘이 휴무일인 걸 확인한 순간)이므로,
/// 그날에만 + 신뢰가 쌓인 사용자(리뷰 요청과 동일 게이트)에게만 노출한다.
enum CoffeeTipPrompt {
    /// 리뷰 요청과 동일한 신뢰 게이트 (설치 직후 노출 방지)
    private static let minimumAppOpens = 5
    private static let minimumMeaningfulActions = 3
    /// '다음에' 를 누른 뒤 다시 보여주기까지의 간격
    private static let cooldownDays = 30

    static func shouldShow(todayHasClosedMart: Bool) -> Bool {
        // 감사의 순간이 아니면 노출하지 않는다
        guard todayHasClosedMart else { return false }
        // 이미 후원한 사용자에게 메인 화면에서 다시 조르지 않는다 (재후원은 설정에서)
        guard !SupporterManager.isSupporter else { return false }
        // 앱의 가치를 충분히 경험하기 전에는 요청하지 않는다
        // (DEBUG 빌드는 게이트를 건너뛰어 휴무일이면 바로 카드를 확인할 수 있게 한다)
#if !DEBUG
        guard ReviewManager.appOpenCount >= minimumAppOpens,
              ReviewManager.meaningfulActionsCount >= minimumMeaningfulActions else { return false }
#endif

        let dismissedAt = UserDefaults.standard.double(forKey: AppStorageKeys.tipCardDismissedAt)
        if dismissedAt > 0 {
            let dismissedDate = Date(timeIntervalSince1970: dismissedAt)
            let days = Calendar.current.dateComponents([.day], from: dismissedDate, to: Date()).day ?? 0
            guard days >= cooldownDays else { return false }
        }
        return true
    }

    static func markDismissed() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: AppStorageKeys.tipCardDismissedAt)
    }
}

// MARK: - SupporterThanksPrompt (후원자 감사 리마인더 노출 판정)

/// 이미 후원한 사용자에게 '보내주신 기부의 감사함을 잊지 않았다' 는 축하를
/// 휴무일에 가끔 다시 보여줄지 판정한다 (재응원 버튼 포함).
///
/// 원칙: 감사는 반복되면 소음이 된다. 1년에 3번 정도(최소 120일 간격)만,
/// 앱이 실제로 헛걸음을 막아준 날(휴무일)에만 보여준다.
enum SupporterThanksPrompt {
    /// 1년에 3번 정도 = 최소 120일 간격
    private static let minimumIntervalDays = 120

    static func shouldShow(todayHasClosedMart: Bool) -> Bool {
        // 감사의 순간(휴무일)이 아니면 보여주지 않는다
        guard todayHasClosedMart else { return false }
        guard SupporterManager.isSupporter, SupporterManager.tipCount > 0 else { return false }

        let last = UserDefaults.standard.double(forKey: AppStorageKeys.supporterThanksShownAt)
        // 기준점이 없는 기존 후원자는 다음 휴무일에 한 번 보여주고 주기를 시작한다
        guard last > 0 else { return true }
        let lastDate = Date(timeIntervalSince1970: last)
        let days = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
        return days >= minimumIntervalDays
    }

    static func markShown() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: AppStorageKeys.supporterThanksShownAt)
    }
}
