// SceneAnalyzer.swift
// DanmakuCamera · Analysis
//
// 职责：本地传感器数据采集 + 帧截图，不做任何判断，交给后端 Agent
// 依赖：CMMotionManager（倾斜角）、AVFoundation（亮度/对焦状态）

import AVFoundation
import CoreMotion
import UIKit

// MARK: - 传感器数据结构

struct SensorData: Codable {
    let tiltX: Double       // 设备 X 轴倾斜角（度）
    let tiltY: Double       // 设备 Y 轴倾斜角（度）
    let brightness: Double  // 本地亮度初值（0~1，辅助 Agent）
    let isFocusing: Bool    // 当前是否正在对焦
}

// MARK: - SceneAnalyzer

final class SceneAnalyzer {

    // ── 运动传感器 ──
    private let motionManager = CMMotionManager()
    private var latestAttitude: CMAttitude?

    // ── 当前对焦状态（由 CameraEngine 注入）──
    var isFocusing: Bool = false

    // MARK: - 启动 / 停止

    func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            self?.latestAttitude = motion?.attitude
        }
    }

    func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }

    // MARK: - 采集传感器数据

    func collectSensorData(from device: AVCaptureDevice?) -> SensorData {
        // 倾斜角：从弧度转为角度
        let tiltX = latestAttitude.map { $0.pitch * (180 / .pi) } ?? 0
        let tiltY = latestAttitude.map { $0.roll  * (180 / .pi) } ?? 0

        // 本地亮度：从 ISO + 曝光时间粗略估算（0~1 归一化）
        let brightness = estimateBrightness(from: device)

        return SensorData(
            tiltX: tiltX,
            tiltY: tiltY,
            brightness: brightness,
            isFocusing: isFocusing
        )
    }

    // MARK: - 帧截图

    /// 将 CMSampleBuffer 转为压缩 JPEG（720p），用于上传 Agent
    func captureFrame(from sampleBuffer: CMSampleBuffer) -> Data? {
        guard
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return nil }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])

        // 缩放到 720p（短边 720）
        let scale = 720.0 / min(ciImage.extent.width, ciImage.extent.height)
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard
            let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent)
        else { return nil }

        let uiImage = UIImage(cgImage: cgImage)

        // JPEG 压缩质量 0.75，平衡画质与上传速度
        return uiImage.jpegData(compressionQuality: 0.75)
    }

    // MARK: - Private

    /// 用 ISO 和曝光时间粗略估算场景亮度（0~1）
    private func estimateBrightness(from device: AVCaptureDevice?) -> Double {
        guard let device else { return 0.5 }

        let iso = Double(device.iso)
        let exposureDuration = device.exposureDuration.seconds

        // EV 近似：log2(1 / (iso * exposureDuration / 100))
        // 正常室外约 EV 12~15，室内约 EV 6~9，暗室 < EV 3
        let ev = log2(100.0 / (iso * exposureDuration + 1e-10))

        // 归一化到 0~1（EV 0 → 0，EV 15 → 1）
        return max(0, min(1, ev / 15.0))
    }
}
