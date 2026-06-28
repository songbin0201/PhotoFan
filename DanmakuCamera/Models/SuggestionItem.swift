// SuggestionItem.swift
// DanmakuCamera · Models
//
// 弹幕建议的核心数据模型，贯穿整个 DanmakuSystem

import SwiftUI

// MARK: - 建议类型

enum SuggestionType: String, Codable, CaseIterable {
    case lighting    = "lighting"      // 光线问题（过暗 / 过曝 / 逆光）
    case composition = "composition"   // 构图问题（偏移 / 三分法）
    case stability   = "stability"     // 稳定性（抖动 / 模糊）
    case focus       = "focus"         // 对焦问题
    case tilt        = "tilt"          // 水平仪倾斜
    case other       = "other"         // 其他（镜头污渍等）

    /// 同一类型的建议在屏幕上只保留一条
    var deduplicationKey: String { rawValue }
}

// MARK: - 建议状态

enum SuggestionStatus: Equatable {
    case pending     // 灰色：问题存在，等待用户调整
    case resolving   // 过渡态：正在播放变绿动画
    case achieved    // 绿色：问题已解决
    case expired     // 飘出屏幕后待移除
}

// MARK: - 弹幕轨道

/// 屏幕垂直方向划分为若干轨道，避免弹幕堆叠
struct DanmakuLane: Equatable {
    let index: Int
    let yOffset: CGFloat  // 相对于弹幕容器顶部的偏移量
}

// MARK: - 核心模型

struct SuggestionItem: Identifiable, Equatable {

    // ── 标识 ──
    let id: String              // 后端生成的唯一 ID（Phase 4 接入后使用）
    let type: SuggestionType

    // ── 内容 ──
    let text: String            // Agent 生成的自然语言建议（支持中文）

    // ── 状态 ──
    var status: SuggestionStatus = .pending
    var resolvedAt: Date?       // 变绿时间，用于计算停留时长

    // ── 动画布局 ──
    var lane: DanmakuLane       // 分配的轨道
    let spawnedAt: Date         // 生成时间
    let flyDuration: Double     // 飘过屏幕的总时长（秒）

    // ── 工厂方法：Mock 数据 ──
    static func mock(
        id: String = UUID().uuidString,
        type: SuggestionType,
        text: String,
        lane: DanmakuLane
    ) -> SuggestionItem {
        SuggestionItem(
            id: id,
            type: type,
            text: text,
            lane: lane,
            spawnedAt: Date(),
            flyDuration: Double.random(in: 8.0...11.0)
        )
    }

    static func == (lhs: SuggestionItem, rhs: SuggestionItem) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status
    }
}
