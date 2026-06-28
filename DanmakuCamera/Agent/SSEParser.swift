// SSEParser.swift
// DanmakuCamera · Agent
//
// 将 URLSession 的字节流解析为强类型 AgentSSEEvent
// SSE 协议格式：
//   event: suggestion\n
//   data: {"id":"...","type":"...","text":"...","resolved":false}\n
//   \n

import Foundation

// MARK: - SSEParser

final class SSEParser {

    // 跨行缓冲区（处理分片传输）
    private var buffer = ""

    // 当前事件的临时字段
    private var currentEvent: String = ""
    private var currentData:  String = ""

    // MARK: - 追加字节流

    /// 每次 URLSession 收到新数据时调用，返回本次解析出的所有事件
    func append(_ data: Data) -> [AgentSSEEvent] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        buffer += text

        var events: [AgentSSEEvent] = []

        // 按行切割处理
        while let lineRange = buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex..<lineRange.lowerBound])
            buffer.removeSubrange(buffer.startIndex...lineRange.lowerBound)

            if let event = processLine(line) {
                events.append(event)
            }
        }

        return events
    }

    // MARK: - 逐行处理

    private func processLine(_ line: String) -> AgentSSEEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // 空行 → 一个完整事件结束，尝试解析
        if trimmed.isEmpty {
            return flushCurrentEvent()
        }

        // event: 字段
        if trimmed.hasPrefix("event:") {
            currentEvent = trimmed
                .dropFirst("event:".count)
                .trimmingCharacters(in: .whitespaces)
            return nil
        }

        // data: 字段（可能多行拼接）
        if trimmed.hasPrefix("data:") {
            let value = trimmed
                .dropFirst("data:".count)
                .trimmingCharacters(in: .whitespaces)
            currentData = currentData.isEmpty ? value : currentData + "\n" + value
            return nil
        }

        // id: / retry: 等其他字段忽略
        return nil
    }

    // MARK: - 事件构建

    private func flushCurrentEvent() -> AgentSSEEvent? {
        defer {
            currentEvent = ""
            currentData  = ""
        }

        guard !currentEvent.isEmpty, !currentData.isEmpty else { return nil }

        let dataBytes = Data(currentData.utf8)

        switch currentEvent {

        case "suggestion":
            guard let payload = try? JSONDecoder().decode(SuggestionPayload.self, from: dataBytes)
            else {
                return .error("suggestion JSON 解析失败: \(currentData)")
            }
            return .suggestion(payload)

        case "resolve":
            guard let payload = try? JSONDecoder().decode(ResolvePayload.self, from: dataBytes)
            else {
                return .error("resolve JSON 解析失败: \(currentData)")
            }
            return .resolve(payload)

        case "done":
            return .done

        case "error":
            let msg = (try? JSONDecoder().decode(ErrorPayload.self, from: dataBytes))?.message
                      ?? currentData
            return .error(msg)

        default:
            // 未知事件类型忽略
            return nil
        }
    }

    // MARK: - 重置（新会话开始时调用）

    func reset() {
        buffer       = ""
        currentEvent = ""
        currentData  = ""
    }
}
