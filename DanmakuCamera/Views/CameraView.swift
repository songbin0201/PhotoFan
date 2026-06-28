// CameraView.swift
// DanmakuCamera · Views
//
// 主视图：相机预览 + 弹幕层 + 快门控制栏
// Phase 2 完成后的完整相机界面（AgentService 在 Phase 4 接入）

import SwiftUI

// MARK: - CameraView

struct CameraView: View {

    @StateObject private var engine       = CameraEngine()
    @StateObject private var danmakuVM    = DanmakuViewModel()

    // 拍照后预览
    @State private var showPhotoPreview   = false

    // 快门按压反馈
    @State private var shutterPressed     = false

    var body: some View {
        ZStack {
            // ── 层 1：相机预览 ──
            cameraLayer

            // ── 层 2：三分法网格 ──
            GridLines()

            // ── 层 3：弹幕叠加 ──
            DanmakuView(viewModel: danmakuVM)

            // ── 层 4：底部控制栏 ──
            VStack {
                Spacer()
                controlBar
            }

            // ── 层 5：权限被拒绝提示 ──
            if engine.permissionStatus == .denied {
                PermissionDeniedView()
            }

            // ── 层 6：拍照预览蒙层 ──
            if showPhotoPreview, let photo = engine.capturedPhoto {
                PhotoPreviewSheet(image: photo) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showPhotoPreview = false
                    }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .onAppear {
            engine.start()
            startMockDanmaku()     // Phase 4 接入 AgentService 后移除此行
        }
        .onDisappear {
            engine.stop()
        }
        // 监听拍照结果
        .onChange(of: engine.capturedPhoto) { photo in
            if photo != nil {
                withAnimation(.easeIn(duration: 0.15)) {
                    showPhotoPreview = true
                }
            }
        }
    }

    // MARK: - 相机层

    @ViewBuilder
    private var cameraLayer: some View {
        if engine.permissionStatus == .authorized {
            CameraPreviewView(engine: engine)
                .ignoresSafeArea()
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    // MARK: - 底部控制栏

    private var controlBar: some View {
        VStack(spacing: 0) {
            // 对焦状态提示
            if engine.isAdjustingFocus {
                Text("对焦中...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.yellow.opacity(0.8))
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }

            HStack(spacing: 0) {
                // 左：缩略图占位
                thumbnailButton
                    .frame(maxWidth: .infinity)

                // 中：快门
                shutterButton
                    .frame(maxWidth: .infinity)

                // 右：翻转摄像头
                flipButton
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 50)
            .padding(.top, 20)
        }
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .animation(.easeInOut(duration: 0.2), value: engine.isAdjustingFocus)
    }

    // 缩略图
    private var thumbnailButton: some View {
        Group {
            if let photo = engine.capturedPhoto {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                    )
                    .onTapGesture {
                        withAnimation { showPhotoPreview = true }
                    }
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.10))
                    .frame(width: 52, height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    )
            }
        }
    }

    // 快门
    private var shutterButton: some View {
        Button {
            triggerShutter()
        } label: {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.95))
                    .frame(width: 74, height: 74)
                Circle()
                    .strokeBorder(.white.opacity(0.4), lineWidth: 3)
                    .frame(width: 84, height: 84)
            }
        }
        .scaleEffect(shutterPressed ? 0.92 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: shutterPressed)
    }

    // 翻转
    private var flipButton: some View {
        Button {
            engine.flipCamera()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 52, height: 52)
                .background(Circle().fill(.white.opacity(0.12)))
        }
    }

    // MARK: - 快门触发

    private func triggerShutter() {
        shutterPressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            shutterPressed = false
        }
        engine.capturePhoto()
    }

    // MARK: - Mock 弹幕（Phase 4 前临时使用）
    // AgentService 接入后，这段逻辑由 CameraViewModel 统一管理

    private func startMockDanmaku() {
        let mockSequence: [(Double, SuggestionType, String, String)] = [
            (1.5,  .lighting,    "m1", "画面偏暗，点击屏幕提亮"),
            (2.5,  .tilt,        "m2", "手机倾斜 5°，请保持水平"),
            (3.5,  .composition, "m3", "主体偏左，向右移动构图"),
            (7.0,  .lighting,    "m1", ""),   // resolve
            (9.0,  .tilt,        "m2", ""),   // resolve
            (11.0, .composition, "m3", ""),   // resolve
            (12.5, .focus,       "m4", "轻触主体重新对焦"),
            (15.5, .focus,       "m4", ""),   // resolve
        ]

        for (delay, type, id, text) in mockSequence {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if text.isEmpty {
                    danmakuVM.resolve(type: type)
                } else {
                    danmakuVM.addSuggestion(id: id, type: type, text: text)
                }
            }
        }
    }
}

// MARK: - 三分法网格

private struct GridLines: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: w / 3, y: 0)); p.addLine(to: CGPoint(x: w / 3, y: h))
                p.move(to: CGPoint(x: w * 2 / 3, y: 0)); p.addLine(to: CGPoint(x: w * 2 / 3, y: h))
                p.move(to: CGPoint(x: 0, y: h / 3)); p.addLine(to: CGPoint(x: w, y: h / 3))
                p.move(to: CGPoint(x: 0, y: h * 2 / 3)); p.addLine(to: CGPoint(x: w, y: h * 2 / 3))
            }
            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - 权限被拒绝提示

private struct PermissionDeniedView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "camera.slash")
                    .font(.system(size: 44))
                    .foregroundColor(.white.opacity(0.5))
                Text("需要相机权限")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                Text("请前往「设置 → 隐私 → 相机」\n开启 PhotoFan 的访问权限")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                Button("前往设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
                .background(Capsule().fill(.white.opacity(0.15)))
                .padding(.top, 8)
            }
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - 拍照预览

private struct PhotoPreviewSheet: View {
    let image: UIImage
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部关闭
                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(.white.opacity(0.12)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)

                Spacer()

                // 照片
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)

                Spacer()

                // 底部操作
                HStack(spacing: 40) {
                    ActionButton(icon: "trash", label: "删除", color: .red.opacity(0.8)) {
                        onDismiss()
                    }
                    ActionButton(icon: "square.and.arrow.down", label: "保存", color: .white.opacity(0.9)) {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                        onDismiss()
                    }
                    ActionButton(icon: "square.and.arrow.up", label: "分享", color: .white.opacity(0.9)) {
                        // 分享逻辑
                    }
                }
                .padding(.bottom, 60)
            }
        }
    }
}

private struct ActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                Text(label)
                    .font(.system(size: 11))
            }
            .foregroundColor(color)
        }
    }
}

// MARK: - Preview

#Preview {
    CameraView()
}
