// CameraEngine.swift
// DanmakuCamera · Camera
//
// AVCaptureSession 管理：预览流 + 帧输出 + 拍照

import AVFoundation
import UIKit
import Combine

// MARK: - 权限状态

enum CameraPermissionStatus {
    case notDetermined
    case authorized
    case denied
}

// MARK: - CameraEngine

final class CameraEngine: NSObject, ObservableObject {

    // ── 对外暴露 ──
    @Published private(set) var permissionStatus: CameraPermissionStatus = .notDetermined
    @Published private(set) var isRunning = false
    @Published private(set) var isAdjustingFocus = false
    @Published private(set) var capturedPhoto: UIImage?

    // 每帧回调 → SceneAnalyzer 使用
    var onFrameOutput: ((CMSampleBuffer) -> Void)?

    // ── AVFoundation 核心 ──
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var videoDevice: AVCaptureDevice?

    // ── 串行队列 ──
    private let sessionQueue = DispatchQueue(label: "com.photofan.sessionQueue")
    private let frameQueue   = DispatchQueue(label: "com.photofan.frameQueue")

    // ── KVO ──
    private var focusObserver: NSKeyValueObservation?

    // MARK: - 启动流程

    func start() {
        checkPermission { [weak self] granted in
            guard granted else { return }
            self?.sessionQueue.async {
                self?.configureSession()
                self?.session.startRunning()
                DispatchQueue.main.async {
                    self?.isRunning = true
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async {
                self?.isRunning = false
            }
        }
        focusObserver?.invalidate()
    }

    // MARK: - 权限

    private func checkPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.permissionStatus = .authorized }
            completion(true)

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionStatus = granted ? .authorized : .denied
                }
                completion(granted)
            }

        default:
            DispatchQueue.main.async { self.permissionStatus = .denied }
            completion(false)
        }
    }

    // MARK: - Session 配置

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // ── 视频输入 ──
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let videoInput = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(videoInput)
        else {
            session.commitConfiguration()
            return
        }
        session.addInput(videoInput)
        videoDevice = device

        // ── 帧输出（SceneAnalyzer 用）──
        videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            // 固定竖屏方向
            videoOutput.connection(with: .video)?.videoRotationAngle = 90
        }

        // ── 照片输出 ──
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
        }

        session.commitConfiguration()

        // KVO 监听对焦状态
        observeFocusState(device: device)
    }

    // MARK: - 对焦状态监听

    private func observeFocusState(device: AVCaptureDevice) {
        focusObserver = device.observe(\.isAdjustingFocus, options: [.new]) { [weak self] _, change in
            DispatchQueue.main.async {
                self?.isAdjustingFocus = change.newValue ?? false
            }
        }
    }

    // MARK: - 点击对焦

    func focus(at point: CGPoint, in viewSize: CGSize) {
        guard let device = videoDevice else { return }

        // 将屏幕坐标转换为 AVFoundation 坐标系（0~1）
        let focusPoint = CGPoint(
            x: point.y / viewSize.height,
            y: 1.0 - point.x / viewSize.width
        )

        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = focusPoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = focusPoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {
            print("[CameraEngine] Focus error: \(error)")
        }
    }

    // MARK: - 曝光调整

    func adjustExposure(bias: Float) {
        guard let device = videoDevice else { return }
        let clampedBias = max(device.minExposureTargetBias,
                              min(device.maxExposureTargetBias, bias))
        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(clampedBias)
            device.unlockForConfiguration()
        } catch {
            print("[CameraEngine] Exposure error: \(error)")
        }
    }

    // MARK: - 拍照

    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - 前后摄像头切换

    func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()

            // 移除现有输入
            self.session.inputs.forEach { self.session.removeInput($0) }

            // 切换摄像头位置
            let currentPosition = self.videoDevice?.position ?? .back
            let newPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back

            guard
                let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                let newInput = try? AVCaptureDeviceInput(device: newDevice),
                self.session.canAddInput(newInput)
            else {
                self.session.commitConfiguration()
                return
            }

            self.session.addInput(newInput)
            self.videoDevice = newDevice
            self.videoOutput.connection(with: .video)?.videoRotationAngle = 90
            self.session.commitConfiguration()

            self.observeFocusState(device: newDevice)
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraEngine: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // 直接回调给 SceneAnalyzer，不在此处做任何处理
        onFrameOutput?(sampleBuffer)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraEngine: AVCapturePhotoCaptureDelegate {

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data)
        else { return }

        DispatchQueue.main.async { [weak self] in
            self?.capturedPhoto = image
        }
    }
}
