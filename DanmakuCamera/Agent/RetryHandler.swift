// RetryHandler.swift
// DanmakuCamera · Agent
//
// 网络请求失败时的指数退避重试策略
// 避免网络波动导致弹幕长时间空白

import Foundation

// MARK: - 重试配置

struct RetryConfig {
    let maxAttempts: Int        // 最大重试次数
    let baseDelay: Double       // 初始等待时间（秒）
    let maxDelay: Double        // 最长等待时间上限（秒）
    let multiplier: Double      // 每次重试的延迟倍数

    static let `default` = RetryConfig(
        maxAttempts: 3,
        baseDelay: 1.0,
        maxDelay: 8.0,
        multiplier: 2.0
    )
}

// MARK: - RetryHandler

final class RetryHandler {

    private let config: RetryConfig
    private var currentAttempt = 0
    private var retryTask: Task<Void, Never>?

    init(config: RetryConfig = .default) {
        self.config = config
    }

    // MARK: - 执行（含重试）

    /// 执行 action，失败时按指数退避重试，最终失败回调 onFail
    func execute(
        action: @escaping () -> Void,
        onFail: @escaping (String) -> Void
    ) {
        currentAttempt = 0
        attempt(action: action, onFail: onFail)
    }

    // MARK: - 手动重置（请求成功后调用）

    func reset() {
        currentAttempt = 0
        retryTask?.cancel()
        retryTask = nil
    }

    // MARK: - 取消

    func cancel() {
        retryTask?.cancel()
        retryTask = nil
    }

    // MARK: - Private

    private func attempt(
        action: @escaping () -> Void,
        onFail: @escaping (String) -> Void
    ) {
        currentAttempt += 1

        if currentAttempt > config.maxAttempts {
            onFail("网络连接失败，请检查网络后重试")
            return
        }

        // 第一次直接执行，之后等待退避时间
        if currentAttempt == 1 {
            action()
        } else {
            let delay = min(
                config.baseDelay * pow(config.multiplier, Double(currentAttempt - 2)),
                config.maxDelay
            )
            print("[RetryHandler] 第 \(currentAttempt) 次重试，等待 \(String(format: "%.1f", delay))s")

            retryTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run { action() }
            }
        }
    }

    // 供 AgentService 在收到错误时触发下一次重试
    func scheduleRetry(
        action: @escaping () -> Void,
        onFail: @escaping (String) -> Void
    ) {
        attempt(action: action, onFail: onFail)
    }
}
