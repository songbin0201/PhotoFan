// CameraViewModel.swift
// DanmakuCamera · ViewModels
//
// Phase 5 更新：
// - 接入真实 AgentService，移除 Mock 弹幕逻辑
// - 加入节流保护（跳过帧抖动剧烈或网络繁忙时的请求）
// - 接入 RetryHandler 处理网络失败
// - 错误状态自动恢复

import SwiftUI
import Combine
import CoreMedia

@MainActor
final class CameraViewModel: ObservableObject {

    // ── 子模块 ──
    let engine       = CameraEngine()
    let danmakuVM    = DanmakuViewModel()

    private let analyzer     = SceneAnalyzer()
    private let agentService = AgentService()
    private let retryHandler = RetryHandler()

    // ── 会话 ID ──
    private let sessionId = UUID().uuidString

    // ── 采帧循环 ──
    private var frameLoopTask: Task<Void, Never>?

    // ── 最新帧缓存 ──
    private var latestSampleBuffer: CMSampleBuffer?
    private let bufferLock = NSLock()

    // ── 节流：连续失败计数 ──
    private var consecutiveFailures = 0
    private let maxConsecutiveFailures = 3

    // ── 暂停采帧（错误退避期间）──
    private var isPaused = false

    // MARK: - 启动 / 停止

    func start() {
        analyzer.startMotionUpdates()
        engine.start()

        engine.onFrameOutput = { [weak self] buffer in
            self?.bufferLock.lock()
            self?.latestSampleBuffer = buffer
            self?.bufferLock.unlock()
        }

        startFrameLoop()
    }

    func stop() {
        frameLoopTask?.cancel()
        frameLoopTask = nil
        retryHandler.cancel()
        agentService.cancelCurrentRequest()
        analyzer.stopMotionUpdates()
        engine.stop()
    }

    // MARK: - 采帧循环

    private func startFrameLoop() {
        frameLoopTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: UInt64(AgentConfig.frameSampleInterval * 1_000_000_000)
                )
                guard !Task.isCancelled, !isPaused else { continue }
                await sendFrameToAgent()
            }
        }
    }

    // MARK: - 采帧 → 上传

    private func sendFrameToAgent() async {
        guard !agentService.isAnalyzing else { return }

        bufferLock.lock()
        let buffer = latestSampleBuffer
        bufferLock.unlock()
        guard let buffer else { return }

        guard let frameData = analyzer.captureFrame(from: buffer) else { return }
        guard frameData.count <= AgentConfig.maxFrameBytes else {
            print("[CameraViewModel] 帧过大(\(frameData.count / 1024)KB)，跳过")
            return
        }

        analyzer.isFocusing = engine.isAdjustingFocus
        let sensorData = analyzer.collectSensorData(from: nil)

        let activeTypes = danmakuVM.items
            .filter { $0.status == .pending || $0.status == .resolving }
            .map { $0.type.rawValue }

        let request = AnalyzeRequest(
            sessionId: sessionId,
            frame: frameData.base64EncodedString(),
            sensorData: sensorData,
            activeSuggestions: activeTypes
        )

        dispatchRequest(request)
    }

    // MARK: - 发起请求（含重试）

    private func dispatchRequest(_ request: AnalyzeRequest) {
        retryHandler.execute(
            action: { [weak self] in
                guard let self else { return }
                self.agentService.analyzeFrame(
                    request: request,
                    onEvent: { [weak self] event in
                        self?.handleAgentEvent(event, request: request)
                    },
                    onStateChange: { [weak self] state in
                        self?.handleStateChange(state)
                    }
                )
            },
            onFail: { [weak self] message in
                self?.danmakuVM.setConnectionState(.error(message))
                self?.scheduleErrorRecovery()
            }
        )
    }

    // MARK: - SSE 事件处理

    private func handleAgentEvent(_ event: AgentSSEEvent, request: AnalyzeRequest) {
        switch event {

        case .suggestion(let payload):
            guard let type = SuggestionType(rawValue: payload.type) else { return }
            danmakuVM.addSuggestion(id: payload.id, type: type, text: payload.text)
            consecutiveFailures = 0

        case .resolve(let payload):
            if let item = danmakuVM.items.first(where: { $0.id == payload.id }) {
                danmakuVM.resolve(type: item.type)
            }

        case .done:
            retryHandler.reset()
            consecutiveFailures = 0

        case .error(let message):
            print("[CameraViewModel] Agent error: \(message)")
            consecutiveFailures += 1

            if consecutiveFailures >= maxConsecutiveFailures {
                danmakuVM.setConnectionState(.error("连接异常，自动重连中..."))
                scheduleErrorRecovery()
            } else {
                retryHandler.scheduleRetry(
                    action: { [weak self] in
                        self?.dispatchRequest(request)
                    },
                    onFail: { [weak self] msg in
                        self?.danmakuVM.setConnectionState(.error(msg))
                        self?.scheduleErrorRecovery()
                    }
                )
            }
        }
    }

    // MARK: - 状态变化

    private func handleStateChange(_ state: AgentConnectionState) {
        danmakuVM.setConnectionState(state)
    }

    // MARK: - 错误恢复（暂停 10 秒后自动重连）

    private func scheduleErrorRecovery() {
        isPaused = true
        retryHandler.cancel()
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            consecutiveFailures = 0
            isPaused = false
            danmakuVM.setConnectionState(.idle)
            print("[CameraViewModel] 自动重连")
        }
    }

    // MARK: - 拍照

    func capturePhoto() {
        engine.capturePhoto()
    }
}
