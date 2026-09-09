//
//  ClosedDaysView.swift
//  DontGoMart
//
//  Created by hyunho lee on 2023/06/15.
//

import SwiftUI
import WidgetKit
import StoreKit

struct ClosedDaysView: View {
    @State var currentDate: Date = Date()
    @State private var isShowingSettings = false
    @State private var isShowingCalendar = false
    @State private var isShowingShareCard = false
    @State private var isTipCardDismissed = false
    /// 공유 버튼 축소 여부 — 진입 직후엔 문구로 어필하고, 잠시 후 확성기 아이콘만 남긴다
    @State private var isShareButtonCollapsed = false
    /// 후원자 감사 리마인더(휴무일, 1년에 ~3번) 표시 여부
    @State private var isShowingSupporterThanks = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var martSelection = MartSelectionManager.shared
    @StateObject private var tipStore = CoffeeTipStore.shared

    var body: some View {
        NavigationStack {
            mainScrollView
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        if sharePayload != nil {
                            Button(action: {
                                ReviewManager.trackMeaningfulAction()
                                AppUsage.log(.share)
                                isShowingShareCard = true
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "megaphone.fill")
                                        .font(.caption)
                                        .accessibilityHidden(true)
                                    if !isShareButtonCollapsed {
                                        Text("주변 사람에게 휴무소식 알려주기")
                                            .font(.footnote.bold())
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)
                                            .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .trailing)))
                                    }
                                }
                                .padding(.horizontal, isShareButtonCollapsed ? 0 : 12)
                                .padding(.vertical, isShareButtonCollapsed ? 0 : 7)
                                // 접힌 상태는 고정 정사각 프레임 → Capsule 이 정원으로 렌더링되고
                                // 네비게이션 바 높이에 위아래가 잘리지 않는다
                                .frame(
                                    width: isShareButtonCollapsed ? 32 : nil,
                                    height: isShareButtonCollapsed ? 32 : nil
                                )
                                .background(Capsule().fill(Color("Pink")))
                                .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("주변 사람에게 휴무소식 알려주기"))
                            .accessibilityHint(Text("휴무 알림 카드를 만들어 공유합니다"))
                            .task {
                                // 문구를 읽을 시간을 준 뒤 확성기만 남기고 접는다
                                try? await Task.sleep(for: .seconds(3))
                                withAnimation(.spring(duration: 0.45, bounce: 0.25)) {
                                    isShareButtonCollapsed = true
                                }
                            }
                        } else {
                            // 마트 미선택 등 카드를 만들 수 없을 때는 텍스트 공유로 폴백
                            ShareLink(item: shareText) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .accessibilityLabel(Text("공유"))
                            .accessibilityHint(Text("오늘 영업 여부와 다가오는 휴무일을 공유합니다"))
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    settingsButton
                }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(isShowingSettings: $isShowingSettings)
        }
        .sheet(isPresented: $isShowingCalendar) {
            calendarSheet
        }
        .sheet(isPresented: $isShowingShareCard) {
            if let payload = sharePayload {
                ShareCardSheet(payload: payload, messageText: shareText)
                    .presentationDetents([.large])
            }
        }
        .onOpenURL { url in
            // 위젯 탭 딥링크 → 캘린더 열기
            if url.scheme == Utillity.deepLinkScheme, url.host == "calendar" {
                isShowingSettings = false
                isShowingCalendar = true
            }
        }
        .alert("후원 안내", isPresented: tipMessagePresented) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(tipStore.userMessage ?? "")
        }
        // 후원자 감사 리마인더 — 휴무일에 가끔(1년에 ~3번) '기부의 감사함을 잊지 않았다' 축하
        .overlay {
            if isShowingSupporterThanks {
                TipCelebrationView(
                    mode: .supporterReminder,
                    showsConfetti: !reduceMotion,
                    onDismiss: dismissSupporterThanks,
                    onTipAgain: tipStore.coffeeTip == nil ? nil : {
                        dismissSupporterThanks()
                        if let coffee = tipStore.coffeeTip {
                            Task { await tipStore.purchase(coffee) }
                        }
                    }
                )
                .transition(.opacity)
            }
        }
        // 메인 화면 커피 카드에서 후원했을 때의 감사 연출 (콘페티 + 감사 카드)
        .tipCelebrationOverlay()
    }

    private func dismissSupporterThanks() {
        withAnimation(.easeOut(duration: 0.35)) {
            isShowingSupporterThanks = false
        }
    }

    /// 구매 실패·승인 대기 알림 표시 여부 (닫으면 메시지를 비운다)
    private var tipMessagePresented: Binding<Bool> {
        Binding(
            get: { tipStore.userMessage != nil },
            set: { if !$0 { tipStore.userMessage = nil } }
        )
    }

    // MARK: - Subviews

    private var mainScrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                todayStatusCard
                if shouldShowTipCard {
                    coffeeTipCard
                }
                nextClosedDateCard
                calendarButton
                upcomingClosedDatesCard
            }
            .padding(.vertical)
        }
        .task {
            // 팁 상품을 미리 로드해 둔다 (카드/설정 화면 공용, 소모성이라 후원자도 재구매 가능)
            await tipStore.loadProductsIfNeeded()

            // 후원자에게는 휴무일에 가끔 감사 인사를 다시 전한다 (표시 즉시 주기 기록)
            if SupporterThanksPrompt.shouldShow(todayHasClosedMart: todayHasClosedMart) {
                SupporterThanksPrompt.markShown()
                withAnimation(.easeIn(duration: 0.2)) {
                    isShowingSupporterThanks = true
                }
            }
        }
    }

    private var settingsButton: some View {
        Button(action: {
            isShowingSettings.toggle()
        }) {
            Image(systemName: "gear")
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle().fill(Color("Pink"))
                )
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .accessibilityLabel(Text("설정"))
        .accessibilityHint(Text("매장 선택 및 알림 설정 화면을 엽니다"))
    }

    private var calendarSheet: some View {
        NavigationStack {
            ClosedDayCalendarView(currentDate: $currentDate)
                .navigationTitle("휴무일 캘린더")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("완료") {
                            isShowingCalendar = false
                        }
                    }
                }
        }
    }

    // MARK: - 오늘 갈 수 있나요? (가장 큰 한 가지 정보)

    private var todayStatusCard: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let selectedMartTypes = martSelection.getSelectedMartTypes()
        let todayClosedMarts = tasks.filter { task in
            selectedMartTypes.contains(task.type) && calendar.isDate(task.taskDate, inSameDayAs: today)
        }

        let hasNoSelection = selectedMartTypes.isEmpty
        let allClosed = !selectedMartTypes.isEmpty && selectedMartTypes.count == todayClosedMarts.count
        let hasClosedMart = !todayClosedMarts.isEmpty

        return VStack(spacing: 12) {
            HStack {
                Text("오늘 갈 수 있나요?")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }

            HStack(spacing: 16) {
                Text(hasNoSelection ? "⚙️" : (allClosed ? "🚫" : (hasClosedMart ? "⚠️" : "✅")))
                    .font(.system(size: 56))
                    .accessibilityHidden(true)

                todayStatusText(
                    hasNoSelection: hasNoSelection,
                    allClosed: allClosed,
                    hasClosedMart: hasClosedMart,
                    todayClosedMarts: todayClosedMarts
                )

                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(todayStatusColor(hasNoSelection: hasNoSelection, allClosed: allClosed, hasClosedMart: hasClosedMart).opacity(0.12))
        )
        .padding(.horizontal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(todayStatusAccessibilityLabel(
            hasNoSelection: hasNoSelection,
            allClosed: allClosed,
            hasClosedMart: hasClosedMart,
            todayClosedMarts: todayClosedMarts
        )))
    }

    private func todayStatusColor(hasNoSelection: Bool, allClosed: Bool, hasClosedMart: Bool) -> Color {
        if hasNoSelection { return .gray }
        if allClosed { return .red }
        if hasClosedMart { return .orange }
        return .green
    }

    private func todayStatusText(hasNoSelection: Bool, allClosed: Bool, hasClosedMart: Bool, todayClosedMarts: [MetaMartsClosedDays]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if hasNoSelection {
                Text("매장을 선택해주세요")
                    .font(.title2.bold())
                    .foregroundColor(.gray)
                Text("설정에서 추적할 매장을 고르세요")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if allClosed {
                Text("오늘 휴무예요")
                    .font(.title.bold())
                    .foregroundColor(.red)
            } else if hasClosedMart {
                Text("일부만 휴무예요")
                    .font(.title2.bold())
                    .foregroundColor(.orange)
                Text(todayClosedMarts.map { $0.type.displayName }.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("오늘 영업해요")
                    .font(.title.bold())
                    .foregroundColor(.green)
            }
        }
    }

    private func todayStatusAccessibilityLabel(hasNoSelection: Bool, allClosed: Bool, hasClosedMart: Bool, todayClosedMarts: [MetaMartsClosedDays]) -> String {
        if hasNoSelection {
            return String(localized: "매장이 선택되지 않았습니다. 설정에서 매장을 선택해주세요.", defaultValue: "No mart selected. Please choose one in settings.")
        }
        if allClosed {
            return String(localized: "오늘 선택한 모든 매장이 휴무입니다.", defaultValue: "All selected marts are closed today.")
        }
        if hasClosedMart {
            let names = todayClosedMarts.map { $0.type.displayName }.joined(separator: ", ")
            return String(format: String(localized: "오늘 일부 매장만 휴무입니다. %@ 휴무.", defaultValue: "Some marts closed today: %@."), names)
        }
        return String(localized: "오늘 선택한 모든 매장이 영업 중입니다.", defaultValue: "All selected marts are open today.")
    }

    // MARK: - 커피 후원 카드 (감사의 순간에만)

    /// 오늘 선택한 매장 중 하나라도 휴무인지 — 앱이 헛걸음을 막아준 '감사의 순간' 판정.
    private var todayHasClosedMart: Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let selected = martSelection.getSelectedMartTypes()
        return tasks.contains { task in
            selected.contains(task.type) && calendar.isDate(task.taskDate, inSameDayAs: today)
        }
    }

    private var shouldShowTipCard: Bool {
        // 방금 후원한 직후에는 감사 인사를 보여준다
        if tipStore.justThanked { return true }
        guard !isTipCardDismissed, tipStore.coffeeTip != nil else { return false }
        return CoffeeTipPrompt.shouldShow(todayHasClosedMart: todayHasClosedMart)
    }

    private var coffeeTipCard: some View {
        VStack(spacing: 12) {
            if tipStore.justThanked {
                HStack(spacing: 16) {
                    Text("☕️")
                        .font(.system(size: 40))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("감사합니다!")
                            .font(.headline)
                        Text("보내주신 응원이 큰 힘이 됩니다. (지금까지 ☕️ ×\(SupporterManager.tipCount))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("후원해주셔서 감사합니다. 지금까지 커피 \(SupporterManager.tipCount)잔을 보내주셨습니다."))
            } else {
                HStack(spacing: 16) {
                    Text("☕️")
                        .font(.system(size: 40))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("오늘 헛걸음을 막아드렸어요")
                            .font(.headline)
                        Text("도움이 되셨다면 커피 한 잔으로 응원해주세요.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    Button(action: {
                        if let coffee = tipStore.coffeeTip {
                            Task { await tipStore.purchase(coffee) }
                        }
                    }) {
                        HStack(spacing: 6) {
                            if tipStore.isPurchasing {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("커피 사주기 \(tipStore.coffeeTip?.displayPrice ?? "")")
                                .font(.subheadline.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.brown))
                        .foregroundColor(.white)
                    }
                    .disabled(tipStore.isPurchasing)
                    .accessibilityLabel(Text("커피 사주기, \(tipStore.coffeeTip?.displayPrice ?? "")"))
                    .accessibilityHint(Text("개발자에게 커피 한 잔 값을 후원합니다"))

                    Button(action: dismissTipCard) {
                        Text("다음에")
                            .font(.subheadline)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityHint(Text("후원 카드를 닫습니다. 30일 동안 다시 표시되지 않습니다"))
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.brown.opacity(0.1))
        )
        .padding(.horizontal)
    }

    private func dismissTipCard() {
        CoffeeTipPrompt.markDismissed()
        withAnimation {
            isTipCardDismissed = true
        }
    }

    // MARK: - 다음 휴무일

    private var nextClosedDateCard: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let selectedMartTypes = martSelection.getSelectedMartTypes()
        let nextClosedDate = tasks
            .filter { task in
                selectedMartTypes.contains(task.type) && task.taskDate >= today
            }
            .sorted { $0.taskDate < $1.taskDate }
            .first

        let daysUntil = nextClosedDate.flatMap { closedDate in
            calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: closedDate.taskDate)).day
        }

        let cardAccessibilityLabel: String
        if let days = daysUntil, let closedDate = nextClosedDate {
            let header = String(localized: "다음 휴무일", defaultValue: "Next closed day")
            let dateText = closedDate.taskDate.formatted(date: .long, time: .omitted)
            cardAccessibilityLabel = "\(header), \(closedDate.type.displayName), \(dateText), \(spokenDaysUntil(days))"
        } else {
            cardAccessibilityLabel = String(localized: "다음 휴무일 정보 없음", defaultValue: "No closed day info")
        }

        return VStack(spacing: 12) {
            HStack {
                Text("다음 휴무일")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }

            if let days = daysUntil, let closedDate = nextClosedDate {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(operationStatusManager.formatDDay(days))
                            .font(.title.bold())
                            .foregroundColor(Color("Pink"))
                        Text(closedDate.taskDate.formatted(date: .long, time: .omitted))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(closedDate.type.displayName)
                            .font(.subheadline.bold())
                            .foregroundColor(closedDate.type.themeColor)
                    }
                    Spacer()
                }
            } else {
                Text("휴무일 정보 없음")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(cardAccessibilityLabel))
    }

    private let operationStatusManager = OperationStatusManager.shared

    /// VoiceOver 가 D-Day 를 자연스럽게 읽도록 일수를 풀어서 표현한다.
    private func spokenDaysUntil(_ days: Int) -> String {
        if days <= 0 { return String(localized: "오늘 휴무", defaultValue: "Closed today") }
        if days == 1 { return String(localized: "내일 휴무", defaultValue: "Closed tomorrow") }
        return String(format: String(localized: "%lld일 남음", defaultValue: "%lld days left"), days)
    }

    // MARK: - 캘린더 버튼

    private var calendarButton: some View {
        Button(action: {
            isShowingCalendar = true
            ReviewManager.trackMeaningfulAction()
            AppUsage.log(.calendar)
        }) {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.title2)
                Text("휴무일 캘린더 보기")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color("Pink").opacity(0.12))
            .cornerRadius(16)
        }
        .foregroundColor(.primary)
        .padding(.horizontal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("휴무일 캘린더 보기"))
        .accessibilityHint(Text("달력에서 휴무일을 확인합니다"))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - 다가오는 휴무일

    private var upcomingClosedDatesCard: some View {
        let groups = upcomingGroups()

        return VStack(spacing: 14) {
            HStack {
                Text("다가오는 휴무일")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }

            if groups.isEmpty {
                Text("휴무일 정보가 없습니다")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                VStack(spacing: 10) {
                    ForEach(groups, id: \.date) { group in
                        closedDayCard(date: group.date, marts: group.marts, days: group.days)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal)
    }

    /// 휴무일을 날짜별로 묶어 한눈에 보이도록 한 카드.
    private func closedDayCard(date: Date, marts: [MetaMartsClosedDays], days: Int) -> some View {
        let calendar = Calendar.current
        let dayNumber = calendar.component(.day, from: date)
        let weekdayIndex = calendar.component(.weekday, from: date) // 1 = 일요일
        let weekdaySymbol = Weekday.symbol(calendarWeekday: weekdayIndex)
        let isSunday = weekdayIndex == 1
        // "9월" / "Sep" — 로케일의 축약 월 이름을 그대로 쓴다 (하드코딩하면 영어 화면에 "9월"이 남는다)
        let monthIndex = calendar.component(.month, from: date) - 1
        let monthText = calendar.shortMonthSymbols.indices.contains(monthIndex)
            ? calendar.shortMonthSymbols[monthIndex]
            : "\(monthIndex + 1)"
        let isSoon = days <= 3

        return HStack(spacing: 14) {
            // 달력 한 장 블록 (月 / 일 / 요일)
            VStack(spacing: 1) {
                Text(monthText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(dayNumber)")
                    .font(.title.bold())
                    .foregroundColor(isSunday ? .red : .primary)
                Text(weekdaySymbol)
                    .font(.caption2.bold())
                    .foregroundColor(isSunday ? .red : .secondary)
            }
            .frame(width: 60, height: 68)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSoon ? Color("Pink").opacity(0.15) : Color(.systemBackground))
            )

            // 직관적 상대 표현 + 휴무 마트 목록 (색상으로 구분)
            VStack(alignment: .leading, spacing: 6) {
                Text(relativeDayPhrase(date: date, days: days))
                    .font(.subheadline.bold())
                    .foregroundColor(isSoon ? Color("Pink") : .primary)

                ForEach(marts) { mart in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(mart.type.themeColor)
                            .frame(width: 8, height: 8)
                        Text(mart.type.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            // D-day 배지
            Text(operationStatusManager.formatDDay(days))
                .font(.subheadline.bold())
                .foregroundColor(isSoon ? .white : Color("Pink"))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isSoon ? Color("Pink") : Color("Pink").opacity(0.12))
                )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(groupAccessibilityLabel(date: date, marts: marts, days: days)))
    }

    // MARK: - 공유

    /// 공유 카드 데이터. 오늘 휴무면 오늘을, 아니면 가장 가까운 휴무일을 카드로 만든다.
    /// 마트 미선택 등으로 만들 수 없으면 nil (텍스트 공유로 폴백).
    private var sharePayload: ShareCardPayload? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let selected = martSelection.getSelectedMartTypes()
        guard !selected.isEmpty else { return nil }

        let todayClosed = tasks.filter { task in
            selected.contains(task.type) && calendar.isDate(task.taskDate, inSameDayAs: today)
        }
        if !todayClosed.isEmpty {
            return ShareCardPayload(
                phrase: String(localized: "오늘", defaultValue: "Today"),
                dateText: formattedCardDate(today),
                marts: todayClosed.map { ($0.type.displayName, $0.type.themeColor) },
                isToday: true
            )
        }

        guard let next = upcomingGroups().first else { return nil }
        return ShareCardPayload(
            phrase: relativeDayPhrase(date: next.date, days: next.days),
            dateText: formattedCardDate(next.date),
            marts: next.marts.map { ($0.type.displayName, $0.type.themeColor) },
            isToday: false
        )
    }

    /// 카드용 날짜 표기: "7월 13일 일요일" (로케일 자동 대응)
    private func formattedCardDate(_ date: Date) -> String {
        date.formatted(.dateTime.month().day().weekday(.wide))
    }

    /// 오늘 영업 여부 + 다가오는 휴무일을 사람이 읽기 좋은 텍스트로 만든다 (공유용).
    private var shareText: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let selected = martSelection.getSelectedMartTypes()

        var lines: [String] = ["🛒 " + String(localized: "돈꼬마트", defaultValue: "DontGoMart")]

        guard !selected.isEmpty else {
            lines.append("")
            lines.append(String(localized: "설정에서 마트를 선택하면 휴무일을 확인할 수 있어요.",
                                defaultValue: "Choose a store in Settings to see its closed days."))
            return lines.joined(separator: "\n")
        }

        // 오늘 상태
        let todayClosed = tasks.filter {
            selected.contains($0.type) && calendar.isDate($0.taskDate, inSameDayAs: today)
        }
        lines.append("")
        if todayClosed.isEmpty {
            lines.append(String(localized: "오늘은 영업해요 ✅", defaultValue: "Open today ✅"))
        } else if todayClosed.count == selected.count {
            lines.append(String(localized: "오늘은 휴무예요 🚫", defaultValue: "Closed today 🚫"))
        } else {
            let names = todayClosed.map { $0.type.displayName }.joined(separator: ", ")
            lines.append(String(format: String(localized: "오늘 일부 휴무: %@ ⚠️",
                                               defaultValue: "Some closed today: %@ ⚠️"), names))
        }

        // 다가오는 휴무일 (가까운 3건)
        let groups = upcomingGroups()
        if !groups.isEmpty {
            lines.append("")
            lines.append(String(localized: "다가오는 휴무일", defaultValue: "Upcoming closed days"))
            for group in groups.prefix(3) {
                let names = group.marts.map { $0.type.displayName }.joined(separator: ", ")
                // 날짜는 "9월 13일" / "Sep 13" 처럼 로케일이 정하는 표기를 그대로 쓴다.
                let dateText = group.date.formatted(.dateTime.month().day())
                lines.append("· " + String(format: String(localized: "%1$@ (%2$@) — %3$@ 휴무",
                                                          defaultValue: "%1$@ (%2$@) — %3$@ closed"),
                                           relativeDayPhrase(date: group.date, days: group.days),
                                           dateText, names))
            }
        }

        lines.append("")
        lines.append(String(localized: "마트 휴무일, 돈꼬마트로 미리 확인하세요.",
                            defaultValue: "Check store closing days ahead of time with DontGoMart."))
        return lines.joined(separator: "\n")
    }

    /// 다가오는 휴무일을 날짜별로 묶어 정렬된 배열로 반환한다 (가까운 8일치).
    private func upcomingGroups() -> [(date: Date, marts: [MetaMartsClosedDays], days: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let endDate = calendar.date(byAdding: .month, value: 3, to: today) ?? today

        let selectedMartTypes = martSelection.getSelectedMartTypes()
        let upcoming = tasks.filter { task in
            selectedMartTypes.contains(task.type) &&
            task.taskDate >= today &&
            task.taskDate <= endDate
        }
        .sorted { $0.taskDate < $1.taskDate }

        var order: [Date] = []
        var map: [Date: [MetaMartsClosedDays]] = [:]
        for task in upcoming {
            let day = calendar.startOfDay(for: task.taskDate)
            if map[day] == nil { order.append(day) }
            map[day, default: []].append(task)
        }

        return order.prefix(8).map { day in
            let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
            return (date: day, marts: map[day] ?? [], days: days)
        }
    }

    /// 다가오는 휴무일을 '오늘 / 내일 / 모레 / 이번 주 토요일 / 다음 주 일요일 / 토요일'
    /// 처럼 한눈에 와닿는 표현으로 바꾼다. D-day 숫자보다 직관적이다.
    private func relativeDayPhrase(date: Date, days: Int) -> String {
        if days <= 0 { return String(localized: "오늘", defaultValue: "Today") }
        if days == 1 { return String(localized: "내일", defaultValue: "Tomorrow") }
        if days == 2 { return String(localized: "모레", defaultValue: "In 2 days") }

        let calendar = Calendar.current
        let weekdayIndex = calendar.component(.weekday, from: date) // 1 = 일요일
        let weekday = Weekday.symbol(calendarWeekday: weekdayIndex)
        let weekdayName = String(format: String(localized: "%@요일", defaultValue: "%@"), weekday)

        let today = calendar.startOfDay(for: Date())
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today) else {
            return weekdayName
        }
        let nextWeekStart = thisWeek.end
        let weekAfterNextStart = calendar.date(byAdding: .weekOfYear, value: 1, to: nextWeekStart)

        if date < nextWeekStart {
            return String(format: String(localized: "이번 주 %@", defaultValue: "This %@"), weekdayName)
        }
        if let limit = weekAfterNextStart, date < limit {
            return String(format: String(localized: "다음 주 %@", defaultValue: "Next %@"), weekdayName)
        }
        // 2주 이상 떨어진 경우: 그냥 '일요일' 대신 몇 주 뒤인지 명시해 헷갈리지 않게 한다.
        let targetWeekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        let dayDiff = calendar.dateComponents([.day], from: thisWeek.start, to: targetWeekStart).day ?? 14
        let weeksOut = max(2, dayDiff / 7)
        return String(format: String(localized: "%lld주 뒤 %@", defaultValue: "in %lld weeks, %@"), weeksOut, weekdayName)
    }

    /// 날짜별 카드를 VoiceOver 가 한 문장으로 읽도록 라벨을 구성한다.
    private func groupAccessibilityLabel(date: Date, marts: [MetaMartsClosedDays], days: Int) -> String {
        var parts: [String] = [relativeDayPhrase(date: date, days: days)]
        parts.append(date.formatted(date: .complete, time: .omitted))
        let names = marts.map { $0.type.displayName }.joined(separator: ", ")
        parts.append(String(format: String(localized: "%@ 휴무", defaultValue: "%@ closed"), names))
        return parts.joined(separator: ", ")
    }
}

#Preview {
    ClosedDaysView()
}
