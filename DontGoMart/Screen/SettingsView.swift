//
//  SettingsView.swift
//  DontGoMart
//
//  Created by hyunho lee on 7/8/23.
//

import SwiftUI
import WidgetKit
import UIKit
import StoreKit
import LeeoKit

struct SettingsView: View {
    @Binding var isShowingSettings: Bool
    @AppStorage(AppStorageKeys.notificationEnabled, store: UserDefaults(suiteName: Utillity.appGroupId)) var isNotificationEnabled: Bool = false
    @AppStorage(AppStorageKeys.notificationHour, store: UserDefaults(suiteName: Utillity.appGroupId)) var notificationHour: Int = 9
    @AppStorage(AppStorageKeys.notificationMinute, store: UserDefaults(suiteName: Utillity.appGroupId)) var notificationMinute: Int = 0
    @AppStorage(AppStorageKeys.beforeDayNotificationEnabled, store: UserDefaults(suiteName: Utillity.appGroupId)) var beforeDayNotificationEnabled: Bool = true
    @AppStorage(AppStorageKeys.notificationLeadDays, store: UserDefaults(suiteName: Utillity.appGroupId)) var notificationLeadDays: Int = NotificationManager.defaultLeadDays
    @AppStorage(AppStorageKeys.isLegacySupporter) var isSupporter: Bool = false
    @AppStorage(AppStorageKeys.tipCount) var tipCount: Int = 0

    @StateObject private var martSelection = MartSelectionManager.shared
    @StateObject private var customMartManager = CustomMartManager.shared
    @StateObject private var tipStore = CoffeeTipStore.shared

    private let notificationManager = NotificationManager.shared
    @State private var showingPermissionAlert = false
    @State private var showingTimePicker = false
    @State private var showingCustomMartEditor = false
    @State private var editingCustomMart: CustomMart? = nil

    var body: some View {
        NavigationStack {
            Form {
                if isSupporter {
                    supporterSection
                }
                martSelectionSection
                customMartSection
                notificationSection
                supportSection
                Section {
                    LeeoSupportSection<DontGoMartSpec>()
                } header: {
                    Text("지원")
                }
            }
            .navigationTitle("매장선택")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") {
                        WidgetManager.shared.updateWidget()
                        isShowingSettings = false
                    }
                }
            }
            .onAppear {
                Task {
                    await checkAndSyncNotificationStatus()
                }
                Task {
                    await tipStore.loadProductsIfNeeded()
                }
            }
            .background(
                NotificationPermissionAlert(isPresented: $showingPermissionAlert)
            )
            .sheet(isPresented: $showingCustomMartEditor) {
                CustomMartEditView(editingMart: editingCustomMart)
            }
            .alert("후원 안내", isPresented: tipMessagePresented) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(tipStore.userMessage ?? "")
            }
        }
        // 설정 시트에서 후원했을 때의 감사 연출 (시트가 메인 화면을 덮으므로 여기에도 부착)
        .tipCelebrationOverlay()
    }

    /// 구매 실패·승인 대기 알림 표시 여부 (닫으면 메시지를 비운다)
    private var tipMessagePresented: Binding<Bool> {
        Binding(
            get: { tipStore.userMessage != nil },
            set: { if !$0 { tipStore.userMessage = nil } }
        )
    }

    // MARK: - Supporter Section (커피 후원자 감사 배지)

    private var supporterSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.title2)
                    .foregroundColor(.brown)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("후원자")
                            .font(.subheadline.bold())
                        if tipCount > 0 {
                            Text("☕️ ×\(tipCount)")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.brown.opacity(0.15)))
                        }
                    }
                    Text("앱을 응원해주셔서 감사합니다 ☕️")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("후원자. 지금까지 커피 \(tipCount)잔. 앱을 응원해주셔서 감사합니다."))
        }
    }

    // MARK: - Support Section (팁 후원 — 소모성이라 여러 번 가능)

    private var supportSection: some View {
        Section(
            header: Text("응원하기"),
            footer: Text("모든 기능은 계속 무료예요. 후원은 순수한 응원이며, 몇 번이든 보낼 수 있어요.")
        ) {
            switch tipStore.loadState {
            case .loaded:
                ForEach(tipStore.tipProducts, id: \.id) { product in
                    tipRow(for: product)
                }
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("후원 상품을 불러오는 중이에요")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .failed:
                Button {
                    Task { await tipStore.loadProductsIfNeeded() }
                } label: {
                    Label("후원 상품을 불러오지 못했어요. 다시 시도", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .accessibilityHint(Text("후원 상품 목록을 다시 불러옵니다"))
            }
        }
    }

    private func tipRow(for product: Product) -> some View {
        Button(action: {
            Task { await tipStore.purchase(product) }
        }) {
            HStack(spacing: 12) {
                Text(tipEmoji(for: product.id))
                    .font(.title2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tipTitle(for: product))
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Text(tipDescription(for: product))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if tipStore.isPurchasing {
                    ProgressView()
                } else {
                    Text(product.displayPrice)
                        .font(.subheadline.bold())
                        .foregroundColor(.brown)
                }
            }
            .padding(.vertical, 4)
        }
        .disabled(tipStore.isPurchasing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(tipTitle(for: product)), \(product.displayPrice)"))
        .accessibilityHint(Text("개발자에게 후원합니다"))
        .accessibilityAddTraits(.isButton)
    }

    private func tipEmoji(for productID: String) -> String {
        SupporterManager.emoji(for: productID)
    }

    /// ASC 메타데이터가 비었거나 제품 ID 그대로면 로컬 이름으로 대체한다
    /// (스토어 설정 실수로 사용자에게 원시 ID 가 노출되지 않도록).
    private func tipTitle(for product: Product) -> String {
        let name = product.displayName
        if !name.isEmpty, name != product.id { return name }
        switch product.id {
        case "com.dontgomart.tip.cake": return "케이크 한 조각"
        case "com.dontgomart.tip.meal": return "든든한 한 끼"
        default: return "커피 한 잔"
        }
    }

    private func tipDescription(for product: Product) -> String {
        let description = product.description
        if !description.isEmpty, description != product.id { return description }
        return "개발자에게 보내는 순수한 응원이에요"
    }

    // MARK: - Mart Selection Section

    private var martSelectionSection: some View {
        Section(header: Text("추적할 매장 선택 (여러개 가능)")) {
            // 대형마트 지역별
            martToggle(
                martType: .normal(type: .sunday),
                icon: "cart.fill",
                color: .blue,
                label: String(localized: "대형마트 (일요일 휴무)_label", defaultValue: "Supermarket (Sunday closed)")
            )

            martToggle(
                martType: .normal(type: .wednesday),
                icon: "cart.fill",
                color: .cyan,
                label: String(localized: "대형마트 (수요일 휴무)_label", defaultValue: "Supermarket (Wednesday closed)")
            )

            martToggle(
                martType: .normal(type: .mixed),
                icon: "cart.fill",
                color: .teal,
                label: String(localized: "대형마트 (울산 혼합)_label", defaultValue: "Supermarket (Ulsan mixed)")
            )

            martToggle(
                martType: .normal(type: .jeju),
                icon: "cart.fill",
                color: .mint,
                label: String(localized: "대형마트 (제주)_label", defaultValue: "Supermarket (Jeju)")
            )

            // 코스트코 지점별
            martToggle(
                martType: .costco(type: .normal),
                icon: "building.2.fill",
                color: .red,
                label: String(localized: "코스트코 일반매장_label", defaultValue: "Costco Regular")
            )

            martToggle(
                martType: .costco(type: .daegu),
                icon: "building.2.fill",
                color: .orange,
                label: String(localized: "코스트코 대구점_label", defaultValue: "Costco Daegu")
            )

            martToggle(
                martType: .costco(type: .ilsan),
                icon: "building.2.fill",
                color: .green,
                label: String(localized: "코스트코 일산점_label", defaultValue: "Costco Ilsan")
            )

            martToggle(
                martType: .costco(type: .ulsan),
                icon: "building.2.fill",
                color: .purple,
                label: String(localized: "코스트코 울산점_label", defaultValue: "Costco Ulsan")
            )

            // 공휴일
            martToggle(
                martType: .holiday,
                icon: "calendar.badge.exclamationmark",
                color: .pink,
                label: String(localized: "설날/추석 공휴일_label", defaultValue: "Lunar New Year/Chuseok Holidays")
            )
        }
    }

    private func martToggle(martType: MartType, icon: String, color: Color, label: String) -> some View {
        Toggle(isOn: Binding(
            get: { martSelection.isSelected(martType) },
            set: { _ in
                martSelection.toggleMart(martType)
                WidgetManager.shared.updateWidget()
            }
        )) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(label)
            }
        }
    }

    // MARK: - Custom Mart Section

    private var customMartSection: some View {
        Section(header: Text("나만의 마트")) {
            if customMartManager.customMarts.isEmpty {
                Text("자주 가는 마트의 휴무 패턴을 추가하세요")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(customMartManager.customMarts) { mart in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { mart.isEnabled && martSelection.isSelected(.custom(id: mart.id.uuidString)) },
                            set: { isOn in
                                var updatedMart = mart
                                updatedMart.isEnabled = isOn
                                customMartManager.updateCustomMart(updatedMart)

                                // toggleMart 를 쓰면 껐다 켤 때 선택이 어긋나므로 목표 상태로 직접 맞춘다
                                martSelection.setSelected(isOn, for: .custom(id: mart.id.uuidString))
                                WidgetManager.shared.updateWidget()
                            }
                        )) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: mart.color) ?? .gray)
                                    .frame(width: 12, height: 12)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mart.name)
                                        .font(.subheadline)
                                    Text(mart.patterns.map { $0.displayText }.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }

                        Button(action: {
                            editingCustomMart = mart
                            showingCustomMartEditor = true
                        }) {
                            Image(systemName: "pencil")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("\(mart.name) 수정"))

                        Button(action: {
                            customMartManager.deleteCustomMart(mart)
                            WidgetManager.shared.updateWidget()
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("\(mart.name) 삭제"))
                    }
                }
            }

            Button(action: {
                editingCustomMart = nil
                showingCustomMartEditor = true
            }) {
                Label("마트 추가", systemImage: "plus.circle.fill")
            }
        }
    }

    // MARK: - Notification Section

    private var notificationSection: some View {
        Section(header: Text("알림설정")) {
            Toggle("휴무일 알림", isOn: $isNotificationEnabled)
                .onChange(of: isNotificationEnabled) {
                    Task {
                        await handleNotificationToggle()
                    }
                }

            if isNotificationEnabled {
                Picker("알림 시점", selection: $notificationLeadDays) {
                    ForEach(NotificationManager.leadDayPresets, id: \.self) { days in
                        Text("\(days)일 전").tag(days)
                    }
                }
                .onChange(of: notificationLeadDays) {
                    Task {
                        await notificationManager.setupSmartNotifications(for: tasks)
                    }
                }

                Toggle("장보기 좋은 날 알림 (전날)", isOn: $beforeDayNotificationEnabled)
                    .onChange(of: beforeDayNotificationEnabled) {
                        Task {
                            await notificationManager.setupSmartNotifications(for: tasks)
                        }
                    }

                HStack {
                    Text("알림 시간")
                        .foregroundColor(.primary)
                    Spacer()
                    Button(action: {
                        showingTimePicker.toggle()
                    }) {
                        Text(String(format: "%02d:%02d", notificationHour, notificationMinute))
                            .foregroundColor(.blue)
                    }
                }

                if showingTimePicker {
                    HStack {
                        Spacer()
                        Picker("시", selection: $notificationHour) {
                            ForEach(0..<24) { hour in
                                Text("\(hour)시").tag(hour)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 100)

                        Picker("분", selection: $notificationMinute) {
                            ForEach([0, 30], id: \.self) { minute in
                                Text("\(minute)분").tag(minute)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 100)
                        Spacer()
                    }
                    .onChange(of: notificationHour) {
                        Task {
                            await notificationManager.setupSmartNotifications(for: tasks)
                        }
                    }
                    .onChange(of: notificationMinute) {
                        Task {
                            await notificationManager.setupSmartNotifications(for: tasks)
                        }
                    }
                }

                Text(notificationDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// 현재 알림 설정을 사람이 읽기 좋은 한 줄로.
    private var notificationDescription: String {
        // 문장을 조각내어 이어 붙이면 번역이 불가능하므로, 완성된 문장 두 개 중 하나를 고른다.
        let time = String(format: "%02d:%02d", notificationHour, notificationMinute)
        if beforeDayNotificationEnabled {
            return String(format: String(localized: "휴무일 %1$lld일 전과 전날 %2$@에 알림이 전송됩니다.",
                                         defaultValue: "You'll be notified %1$lld days before and the day before, at %2$@."),
                          notificationLeadDays, time)
        }
        return String(format: String(localized: "휴무일 %1$lld일 전 %2$@에 알림이 전송됩니다.",
                                     defaultValue: "You'll be notified %1$lld days before, at %2$@."),
                      notificationLeadDays, time)
    }

    // MARK: - Private Methods

    @MainActor
    private func handleNotificationToggle() async {
        if isNotificationEnabled {
            let status = await notificationManager.checkAuthorizationStatus()

            if status == .authorized {
                await notificationManager.setupSmartNotifications(for: tasks)
                debugLog("✅ [SettingsView] 알림이 활성화되었습니다.")
            } else if status == .denied {
                isNotificationEnabled = false
                showingPermissionAlert = true
                debugLog("❌ [SettingsView] 알림 권한이 거부된 상태입니다.")
            } else {
                let authorized = await notificationManager.requestAuthorization()
                if authorized {
                    await notificationManager.setupSmartNotifications(for: tasks)
                    debugLog("✅ [SettingsView] 알림 권한 허용 후 알림이 활성화되었습니다.")
                } else {
                    isNotificationEnabled = false
                    showingPermissionAlert = true
                    debugLog("❌ [SettingsView] 알림 권한이 거부되어 알림을 비활성화했습니다.")
                }
            }
        } else {
            notificationManager.cancelAllNotifications()
            debugLog("🔕 [SettingsView] 알림이 비활성화되었습니다.")
        }
    }

    @MainActor
    private func checkAndSyncNotificationStatus() async {
        let status = await notificationManager.checkAuthorizationStatus()

        if (status == .denied || status == .notDetermined) && isNotificationEnabled {
            isNotificationEnabled = false
        }

        if isNotificationEnabled && status == .authorized {
            await notificationManager.setupSmartNotifications(for: tasks)
        }
    }
}


struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(isShowingSettings: .constant(true))
    }
}

// MARK: - NotificationPermissionAlert

struct NotificationPermissionAlert: View {
    @Binding var isPresented: Bool

    var body: some View {
        EmptyView()
            .alert("알림 권한 필요", isPresented: $isPresented) {
                Button("설정으로 이동") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("취소", role: .cancel) { }
            } message: {
                Text("휴무일 알림을 받으려면 설정에서 알림 권한을 허용해주세요.")
            }
    }
}
