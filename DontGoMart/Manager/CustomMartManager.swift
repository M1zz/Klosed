//
//  CustomMartManager.swift
//  DontGoMart
//
//  Created by Claude on 1/20/25.
//

import Foundation
import Combine

class CustomMartManager: ObservableObject {
    static let shared = CustomMartManager()
    private init() {
        loadCustomMarts()
    }

    @Published var customMarts: [CustomMart] = []

    private let customMartsKey = "customMarts"

    // 커스텀 마트 로드
    func loadCustomMarts() {
        guard let data = UserDefaults(suiteName: Utillity.appGroupId)?.data(forKey: customMartsKey) else {
            customMarts = []
            return
        }

        do {
            customMarts = try JSONDecoder().decode([CustomMart].self, from: data)
            debugLog("✅ 커스텀 마트 로드 성공: \(customMarts.count)개")
        } catch {
            debugLog("❌ 커스텀 마트 로드 실패: \(error)")
            customMarts = []
        }
    }

    // 커스텀 마트 저장
    func saveCustomMarts() {
        do {
            let data = try JSONEncoder().encode(customMarts)
            UserDefaults(suiteName: Utillity.appGroupId)?.set(data, forKey: customMartsKey)
            debugLog("✅ 커스텀 마트 저장 성공: \(customMarts.count)개")
        } catch {
            debugLog("❌ 커스텀 마트 저장 실패: \(error)")
        }
    }

    // 커스텀 마트 추가
    func addCustomMart(_ mart: CustomMart) {
        customMarts.append(mart)
        saveCustomMarts()
        updateTasksWithCustomMarts()
    }

    // 커스텀 마트 수정
    func updateCustomMart(_ mart: CustomMart) {
        if let index = customMarts.firstIndex(where: { $0.id == mart.id }) {
            customMarts[index] = mart
            saveCustomMarts()
            updateTasksWithCustomMarts()
        }
    }

    // 커스텀 마트 삭제
    func deleteCustomMart(_ mart: CustomMart) {
        customMarts.removeAll { $0.id == mart.id }
        saveCustomMarts()
        updateTasksWithCustomMarts()
        // 선택 목록에 죽은 키가 남지 않도록 함께 정리
        MartSelectionManager.shared.setSelected(false, for: .custom(id: mart.id.uuidString))
    }

    // 커스텀 마트의 휴무일을 tasks에 통합
    func updateTasksWithCustomMarts() {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())

        // 기존 커스텀 마트 태스크 제거
        tasks.removeAll { task in
            if case .custom = task.type {
                return true
            }
            return false
        }

        // 활성화된 커스텀 마트의 휴무일 추가
        for customMart in customMarts where customMart.isEnabled {
            // 올해와 내년 휴무일 계산
            let thisYearDates = customMart.calculateClosedDates(for: currentYear)
            let nextYearDates = customMart.calculateClosedDates(for: currentYear + 1)
            let allDates = thisYearDates + nextYearDates

            // tasks에 추가
            for date in allDates {
                let task = MetaMartsClosedDays(
                    type: .custom(id: customMart.id.uuidString),
                    task: [MartCloseData(
                        title: String(format: String(localized: "%@ 휴무일",
                                                    defaultValue: "%@ closed"), customMart.name)
                    )],
                    taskDate: date
                )
                tasks.append(task)
            }
        }

        // 날짜순 정렬
        tasks.sort { $0.taskDate < $1.taskDate }

        debugLog("✅ tasks 업데이트 완료: 총 \(tasks.count)개")
    }

    // ID로 커스텀 마트 찾기
    func getCustomMart(byId id: String) -> CustomMart? {
        return customMarts.first { $0.id.uuidString == id }
    }
}
