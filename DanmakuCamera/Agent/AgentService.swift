// AgentService.swift
// DanmakuCamera · Agent
//
// 核心通信层：
// 1. 将帧图像 + 传感器数据 POST 到后端
// 2. 通过 SSE 长连接实时接收 Agent 推送的建议事件
// 3. 回调给 CameraViewModel 驱动弹幕更新

import Foundation

// MARK: - AgentService

final class AgentService: NSObject {

    // ── 配置 ──
    // 开发阶段指向本地 Mock 服务，上线后替换为真实域名
    private let baseURL: String

    // ── 状态 ──
    private(set) var isAnalyzing = false

    // ── SSE 解析器 ──
    private let parser = SSEParser()

    // ── 当前任务 ──
    private var currentTask: URLSessionDataTask?
    private var session: URLSession?

    // ── 事件回调 ──
    private var onEvent: ((AgentSSEEvent) -> Void)?
    private var onStateChange: ((AgentConnectionState) -> Void)?

    // MARK: - 初始化

    init(baseURL: String = AgentConfig.baseURL) {
        self.baseURL = baseURL
        super.init()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: - 发起分析请求

    func analyzeFrame(
        request: AnalyzeRequest,
        onEvent: @escaping (AgentSSEEvent) -> Void,
        onStateChange: @escaping (AgentConnectionState) -> Void
    ) {
        // 取消上一次未完成的请求
        cancelCurrentRequest()

        self.onEvent = onEvent
        self.onStateChange = onStateChange
        parser.reset()

        guard let url = URL(string: "\(baseURL)/api/analyze") else {
            onEvent(.error("无效的 API 地址"))
            return
        }

        // 序列化请求体
        guard let body = try? JSONEncoder().encode(request) else {
            onEvent(.error("请求序列化失败"))
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // 禁止缓存，保证 SSE 实时性
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData

        isAnalyzing = true
        onStateChange(.analyzing)

        currentTask = session?.dataTask(with: urlRequest)
        currentTask?.resume()
    }

    // MARK: - 取消

    func cancelCurrentRequest() {
        currentTask?.cancel()
        currentTask = nil
        isAnalyzing = false
        parser.reset()
    }
}

// MARK: - URLSessionDataDelegate（SSE 流处理）

extension AgentService: URLSessionDataDelegate {

    // 收到响应头
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            onEvent?(.error("非 HTTP 响应"))
            return
        }

        switch httpResponse.statusCode {
        case 200:
            DispatchQueue.main.async { [weak self] in
                self?.onStateChange?(.streaming)
            }
            completionHandler(.allow)

        case 401, 403:
            completionHandler(.cancel)
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?(.error("认证失败 (\(httpResponse.statusCode))"))
                self?.onStateChange?(.error("认证失败"))
            }

        case 429:
            completionHandler(.cancel)
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?(.error("请求过于频繁，请稍后重试"))
                self?.onStateChange?(.error("请求限流"))
            }

        default:
            completionHandler(.cancel)
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?(.error("服务器错误 (\(httpResponse.statusCode))"))
                self?.onStateChange?(.error("服务器错误"))
            }
        }
    }

    // 收到数据块（SSE 流式推送）
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        let events = parser.append(data)

        DispatchQueue.main.async { [weak self] in
            for event in events {
                self?.onEvent?(event)

                // done 事件 → 本次分析结束
                if case .done = event {
                    self?.isAnalyzing = false
                    self?.onStateChange?(.idle)
                }
            }
        }
    }

    // 请求完成（正常结束 or 取消）
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.isAnalyzing = false

            if let error = error as? URLError, error.code == .cancelled {
                // 主动取消，不需要上报
                self?.onStateChange?(.idle)
                return
            }

            if let error {
                self?.onEvent?(.error(error.localizedDescription))
                self?.onStateChange?(.error("网络异常"))
            } else {
                self?.onStateChange?(.idle)
            }
        }
    }
}

// MARK: - 配置常量

enum AgentConfig {
    /// 生产环境：Railway 部署地址
    static let baseURL = "https://photofan-backend-production.up.railway.app"

    /// 采帧间隔（秒）
    static let frameSampleInterval: Double = 2.0

    /// 单次上传的最大帧文件大小（字节）
    static let maxFrameBytes = 500_000  // 500KB
}
