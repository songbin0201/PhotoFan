// AgentModels.swift
// DanmakuCamera · Agent
//
// 前后端通信的数据结构定义

import Foundation

// MARK: - 上行：客户端 → Agent

struct AnalyzeRequest: Codable {
    let sessionId: String           // 同一拍摄会话保持一致
    let frame: String               // Base64 编码的 JPEG 图像
    let sensorData: SensorData      // 本地传感器数据（辅助 Agent 判断）
    let activeSuggestions: [String] // 当前屏幕上已有的建议 type，避免重复推送

    enum CodingKeys: String, CodingKey {
        case sessionId        = "session_id"
        case frame
        case sensorData       = "sensor_data"
        case activeSuggestions = "active_suggestions"
    }
}

// MARK: - 下行：Agent → 客户端（SSE 事件）

/// SSE 原始事件（解析前）
struct RawSSEEvent {
    let event: String   // "suggestion" / "resolve" / "done" / "error"
    let data: String    // JSON 字符串
}

/// suggestion 事件的 payload
struct SuggestionPayload: Codable {
    let id: String
    let type: String        // 对应 SuggestionType.rawValue
    let text: String        // 中文建议文字
    let resolved: Bool

    enum CodingKeys: String, CodingKey {
        case id, type, text, resolved
    }
}

/// resolve 事件的 payload
struct ResolvePayload: Codable {
    let id: String
    let resolved: Bool
}

/// error 事件的 payload
struct ErrorPayload: Codable {
    let message: String
}

/// 解析完成后的强类型 SSE 事件
enum AgentSSEEvent {
    case suggestion(SuggestionPayload)
    case resolve(ResolvePayload)
    case done
    case error(String)
}
