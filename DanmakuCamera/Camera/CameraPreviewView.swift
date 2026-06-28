// CameraPreviewView.swift
// DanmakuCamera · Camera
//
// 将 AVCaptureVideoPreviewLayer 包装为 SwiftUI View
// 支持点击对焦 + 对焦动画框

import SwiftUI
import AVFoundation

// MARK: - CameraPreviewView

struct CameraPreviewView: UIViewRepresentable {

    let engine: CameraEngine

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.configure(with: engine.session)

        // 点击对焦手势
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(engine: engine)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        let engine: CameraEngine

        init(engine: CameraEngine) {
            self.engine = engine
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let point = gesture.location(in: gesture.view)
            let viewSize = gesture.view?.bounds.size ?? .zero
            engine.focus(at: point, in: viewSize)

            // 显示对焦动画框
            if let previewView = gesture.view as? CameraPreviewUIView {
                previewView.showFocusIndicator(at: point)
            }
        }
    }
}

// MARK: - CameraPreviewUIView

final class CameraPreviewUIView: UIView {

    // AVFoundation 预览层
    private var previewLayer: AVCaptureVideoPreviewLayer?

    // 对焦指示框
    private let focusIndicator = FocusIndicatorView()

    // MARK: - 配置

    func configure(with session: AVCaptureSession) {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        self.layer.insertSublayer(layer, at: 0)
        previewLayer = layer

        // 对焦框初始隐藏
        focusIndicator.alpha = 0
        addSubview(focusIndicator)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    // MARK: - 对焦动画

    func showFocusIndicator(at point: CGPoint) {
        let size: CGFloat = 72
        focusIndicator.frame = CGRect(
            x: point.x - size / 2,
            y: point.y - size / 2,
            width: size,
            height: size
        )

        focusIndicator.layer.removeAllAnimations()

        // 出现 + 缩小
        focusIndicator.alpha = 1
        focusIndicator.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)

        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            self.focusIndicator.transform = .identity
        } completion: { _ in
            // 停留后淡出
            UIView.animate(withDuration: 0.4, delay: 0.8) {
                self.focusIndicator.alpha = 0
            }
        }
    }
}

// MARK: - 对焦框视图

private final class FocusIndicatorView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        layer.borderColor = UIColor.systemYellow.cgColor
        layer.borderWidth = 1.5
        layer.cornerRadius = 2
    }

    required init?(coder: NSCoder) { fatalError() }

    // 四角装饰线
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setStrokeColor(UIColor.systemYellow.cgColor)
        ctx.setLineWidth(2.0)

        let length: CGFloat = 14
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            // 左上
            (CGPoint(x: 0, y: length), CGPoint(x: 0, y: 0), CGPoint(x: length, y: 0)),
            // 右上
            (CGPoint(x: rect.width - length, y: 0), CGPoint(x: rect.width, y: 0), CGPoint(x: rect.width, y: length)),
            // 左下
            (CGPoint(x: 0, y: rect.height - length), CGPoint(x: 0, y: rect.height), CGPoint(x: length, y: rect.height)),
            // 右下
            (CGPoint(x: rect.width - length, y: rect.height), CGPoint(x: rect.width, y: rect.height), CGPoint(x: rect.width, y: rect.height - length))
        ]

        for (start, mid, end) in corners {
            ctx.move(to: start)
            ctx.addLine(to: mid)
            ctx.addLine(to: end)
        }
        ctx.strokePath()
    }
}

// MARK: - Preview（使用模拟背景，不需要真实相机）

#Preview("相机预览占位") {
    ZStack {
        LinearGradient(
            colors: [Color(red: 0.07, green: 0.10, blue: 0.18),
                     Color(red: 0.04, green: 0.06, blue: 0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        Text("相机预览\n（需真机运行）")
            .font(.system(size: 14))
            .foregroundColor(.white.opacity(0.4))
            .multilineTextAlignment(.center)
    }
}
