// DanmakuViewModel.swift
// DanmakuCamera · ViewModels
//
// 管理弹幕队列的完整生命周期：
// 新增 → 去重 → 分配轨道 → 变绿 → 移除

import SwiftUI
import Combine

// MARK: - 轨道管理器

private final class LaneManager {

    // 屏幕上的可用轨道（Y 偏移量），避开顶部状态栏和底部快门区域
    private let lanes: [DanmakuLane] = (0..<6).map { i in
        DanmakuLane(index: i, yOffset: CGFloat(100 + i * 58))
    }

    // 当前被占用的轨道 index
    private var occupiedIndices = Set<Int>()

    /// 申请一个空闲轨道；全满时随机返回任意轨道
    func acquire() -> DanmakuLane {
        let free = lanes.filter { !occupiedIndices.contains($0.index) }
        let lane = free.randomElement() ?? lanes.randomElement()!
        occupiedIndices.insert(lane.index)
        return lane
    }

    /// 弹幕移除后释放轨道
    func release(_ lane: DanmakuLane) {
        occupiedIndices.remove(lane.index)
    }
}

// MARK: - DanmakuViewModel

@MainActor
final class DanmakuViewModel: ObservableObject {

    // ── 对外暴露 ──
    @Published private(set) var items: [SuggestionItem] = []
    @Published private(set) var connectionState: AgentConnectionState = .idle

    // ── 内部状态 ──
    private let laneManager = LaneManager()
    private var typeIndex: [SuggestionType: String] = [:]  // type → item.id，用于去重和 resolve
    private var cleanupTimers: [String: Task<Void, Never>] = [:]

    // 同屏最多弹幕数，超过时丢弃低优先级
    private let maxVisibleItems = 5

    // 变绿后停留时长（秒）
    private let resolvedLingerDuration: Double = 1.8

    // MARK: - 新增建议

    /// 从后端收到新建议时调用（Phase 4 接入 AgentService 后对接）
    /// 现阶段由 Mock / Preview 直接调用
    func addSuggestion(id: String, type: SuggestionType, text: String) {

        // 1. 去重：同类型建议已存在则忽略
        if typeIndex[type] != nil { return }

        // 2. 容量控制：超出上限则不推送
        let activeCount = items.filter {
            $0.status == .pending || $0.status == .resolving
        }.count
        if activeCount >= maxVisibleItems { return }

        // 3. 分配轨道并创建 item
        let lane = laneManager.acquire()
        let item = SuggestionItem.mock(id: id, type: type, text: text, lane: lane)

        // 4. 记录索引、加入队列
        typeIndex[type] = id
        items.append(item)
    }

    // MARK: - 标记已解决

    /// 后端推送 resolve 事件时调用（或本地传感器判断后调用）
    func resolve(type: SuggestionType) {
        guard
            let itemId = typeIndex[type],
            let idx = items.firstIndex(where: { $0.id == itemId })
        else { return }

        // 过渡态 → 触发颜色动画
        items[idx].status = .resolving

        // 短暂延迟后切换到 achieved（让 SwiftUI 捕捉到两次状态变化）
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
            guard let i = items.firstIndex(where: { $0.id == itemId }) else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                items[i].status = .achieved
                items[i].resolvedAt = Date()
            }

            // 停留后淡出移除
            scheduleCleanup(id: itemId, delay: resolvedLingerDuration)
        }
    }

    // MARK: - 弹幕飘出屏幕后回调

    /// DanmakuItemView 飞行动画结束时调用
    func itemDidExpire(id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let lane = items[idx].lane
        let type = items[idx].type

        items.remove(at: idx)
        typeIndex.removeValue(forKey: type)
        laneManager.release(lane)
        cleanupTimers.removeValue(forKey: id)
    }

    // MARK: - 连接状态（供 CameraView 显示 AI 指示器）

    func setConnectionState(_ state: AgentConnectionState) {
        connectionState = state
    }

    // MARK: - Private

    private func scheduleCleanup(id: String, delay: Double) {
        cleanupTimers[id]?.cancel()
        cleanupTimers[id] = Task {
            let ns = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            itemDidExpire(id: id)
        }
    }
}

// MARK: - Agent 连接状态（供 UI 显示分析指示器）

enum AgentConnectionState: Equatable {
    case idle
    case analyzing   // 正在上传帧，等待 Agent 响应
    case streaming   // 正在接收 SSE 建议流
    case error(String)

    var displayText: String {
        switch self {
        case .idle:           return ""
        case .analyzing:      return "AI 分析中"
        case .streaming:      return "接收建议中"
        case .error(let msg): return msg
        }
    }

    var isActive: Bool {
        switch self {
        case .analyzing, .streaming: return true
        default: return false
        }
    }
}
