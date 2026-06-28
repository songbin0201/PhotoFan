// CameraViewModel.swift
// DanmakuCamera · ViewModels
//
// 总调度层：
// CameraEngine（帧） → SceneAnalyzer（传感器） → AgentService（上传）
//     → SSE 事件 → DanmakuViewModel（弹幕）

import SwiftUI
import Combine

@MainActor
final class CameraViewModel: ObservableObject {

    // ── 子模块 ──
    let engine       = CameraEngine()
    let danmakuVM    = DanmakuViewModel()

    private let analyzer     = SceneAnalyzer()
    private let agentService = AgentService()

    // ── 会话 ID（每次启动相机生成一个新会话）──
    private let sessionId = UUID().uuidString

    // ── 采帧定时器 ──
    private var frameTimer: Task<Void, Never>?

    // ── 最新帧缓存（定时器触发时取用）──
    private var latestSampleBuffer: CMSampleBuffer?
    private let bufferLock = NSLock()

    // MARK: - 启动

    func start() {
        analyzer.startMotionUpdates()
        engine.start()

        // 相机就绪后启动采帧循环
        engine.onFrameOutput = { [weak self] sampleBuffer in
            self?.bufferLock.lock()
            self?.latestSampleBuffer = sampleBuffer
            self?.bufferLock.unlock()
        }

        startFrameLoop()
    }

    // MARK: - 停止

    func stop() {
        frameTimer?.cancel()
        frameTimer = nil
        agentService.cancelCurrentRequest()
        analyzer.stopMotionUpdates()
        engine.stop()
    }

    // MARK: - 采帧循环（每 2 秒一次）

    private func startFrameLoop() {
        frameTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(AgentConfig.frameSampleInterval * 1_000_000_000))
                await sendFrameToAgent()
            }
        }
    }

    // MARK: - 核心：采帧 → 上传 → 处理 SSE

    private func sendFrameToAgent() async {
        // 若上一次请求还在进行中，跳过本次
        guard !agentService.isAnalyzing else { return }

        // 取最新帧
        bufferLock.lock()
        let buffer = latestSampleBuffer
        bufferLock.unlock()

        guard let buffer else { return }

        // 帧压缩
        guard let frameData = analyzer.captureFrame(from: buffer) else { return }

        // 超出大小限制则跳过（网络保护）
        guard frameData.count <= AgentConfig.maxFrameBytes else { return }

        // 传感器数据
        analyzer.isFocusing = engine.isAdjustingFocus
        let sensorData = analyzer.collectSensorData(from: nil)

        // 当前屏幕上已有的建议 type，传给后端避免重复
        let activeTypes = danmakuVM.items
            .filter { $0.status == .pending || $0.status == .resolving }
            .map { $0.type.rawValue }

        let request = AnalyzeRequest(
            sessionId: sessionId,
            frame: frameData.base64EncodedString(),
            sensorData: sensorData,
            activeSuggestions: activeTypes
        )

        // 发起请求
        agentService.analyzeFrame(request: request) { [weak self] event in
            self?.handleAgentEvent(event)
        } onStateChange: { [weak self] state in
            self?.danmakuVM.setConnectionState(state)
        }
    }

    // MARK: - SSE 事件处理

    private func handleAgentEvent(_ event: AgentSSEEvent) {
        switch event {

        case .suggestion(let payload):
            // 将 type 字符串映射到枚举
            guard let type = SuggestionType(rawValue: payload.type) else { return }
            danmakuVM.addSuggestion(id: payload.id, type: type, text: payload.text)

        case .resolve(let payload):
            // 通过 id 找到对应 type 后 resolve
            if let item = danmakuVM.items.first(where: { $0.id == payload.id }) {
                danmakuVM.resolve(type: item.type)
            }

        case .done:
            // AgentService 已自动更新 connectionState → .idle
            break

        case .error(let message):
            print("[CameraViewModel] Agent error: \(message)")
            danmakuVM.setConnectionState(.error("分析异常，请稍后重试"))
            // 3 秒后自动清除错误状态
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                danmakuVM.setConnectionState(.idle)
            }
        }
    }

    // MARK: - 拍照

    func capturePhoto() {
        engine.capturePhoto()
    }
}
