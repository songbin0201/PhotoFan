// CameraView.swift
// DanmakuCamera · Views
//
// Phase 5 更新：
// - 使用真实 CameraViewModel（移除 Mock 弹幕）
// - 加入网络错误 Banner
// - 加入网络恢复后的视觉反馈

import SwiftUI

// MARK: - CameraView

struct CameraView: View {

    @StateObject private var viewModel = CameraViewModel()
    @State private var showPhotoPreview = false
    @State private var shutterPressed   = false

    var body: some View {
        ZStack {
            cameraLayer
            GridLines()
            DanmakuView(viewModel: viewModel.danmakuVM)

            // 网络错误 Banner
            VStack {
                networkErrorBanner
                Spacer()
            }
            .padding(.top, 56)

            VStack {
                Spacer()
                controlBar
            }

            if viewModel.engine.permissionStatus == .denied {
                PermissionDeniedView()
            }

            if showPhotoPreview, let photo = viewModel.engine.capturedPhoto {
                PhotoPreviewSheet(image: photo) {
                    withAnimation(.easeOut(duration: 0.25)) { showPhotoPreview = false }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .onAppear   { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .onChange(of: viewModel.engine.capturedPhoto) { _, photo in
            if photo != nil {
                withAnimation(.easeIn(duration: 0.15)) { showPhotoPreview = true }
            }
        }
    }

    // MARK: - 相机层

    @ViewBuilder
    private var cameraLayer: some View {
        if viewModel.engine.permissionStatus == .authorized {
            CameraPreviewView(engine: viewModel.engine).ignoresSafeArea()
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    // MARK: - 网络错误 Banner

    @ViewBuilder
    private var networkErrorBanner: some View {
        if case .error(let msg) = viewModel.danmakuVM.connectionState {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 13, weight: .medium))
                Text(msg)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(red: 0.7, green: 0.2, blue: 0.15).opacity(0.90))
                    .overlay(Capsule().strokeBorder(Color.red.opacity(0.3), lineWidth: 1))
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: msg)
        }
    }

    // MARK: - 底部控制栏

    private var controlBar: some View {
        VStack(spacing: 0) {
            if viewModel.engine.isAdjustingFocus {
                Text("对焦中...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.yellow.opacity(0.85))
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
            HStack(spacing: 0) {
                thumbnailButton.frame(maxWidth: .infinity)
                shutterButton.frame(maxWidth: .infinity)
                flipButton.frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 50)
            .padding(.top, 16)
        }
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.65)],
                           startPoint: .top, endPoint: .bottom)
        )
        .animation(.easeInOut(duration: 0.2), value: viewModel.engine.isAdjustingFocus)
    }

    private var thumbnailButton: some View {
        Group {
            if let photo = viewModel.engine.capturedPhoto {
                Image(uiImage: photo)
                    .resizable().scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(0.3), lineWidth: 1))
                    .onTapGesture { withAnimation { showPhotoPreview = true } }
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.10))
                    .frame(width: 52, height: 52)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1))
            }
        }
    }

    private var shutterButton: some View {
        Button {
            shutterPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { shutterPressed = false }
            viewModel.capturePhoto()
        } label: {
            ZStack {
                Circle().fill(.white.opacity(0.95)).frame(width: 74, height: 74)
                Circle().strokeBorder(.white.opacity(0.4), lineWidth: 3).frame(width: 84, height: 84)
            }
        }
        .scaleEffect(shutterPressed ? 0.92 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: shutterPressed)
    }

    private var flipButton: some View {
        Button { viewModel.engine.flipCamera() } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 52, height: 52)
                .background(Circle().fill(.white.opacity(0.12)))
        }
    }
}

// MARK: - 三分法网格

private struct GridLines: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: w/3,   y: 0)); p.addLine(to: CGPoint(x: w/3,   y: h))
                p.move(to: CGPoint(x: w*2/3, y: 0)); p.addLine(to: CGPoint(x: w*2/3, y: h))
                p.move(to: CGPoint(x: 0, y: h/3));   p.addLine(to: CGPoint(x: w, y: h/3))
                p.move(to: CGPoint(x: 0, y: h*2/3)); p.addLine(to: CGPoint(x: w, y: h*2/3))
            }
            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - 权限被拒绝

private struct PermissionDeniedView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "camera.slash").font(.system(size: 44)).foregroundColor(.white.opacity(0.4))
                Text("需要相机权限").font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                Text("请前往「设置 → 隐私 → 相机」\n开启 PhotoFan 的访问权限")
                    .font(.system(size: 14)).foregroundColor(.white.opacity(0.5)).multilineTextAlignment(.center)
                Button("前往设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 15, weight: .medium)).foregroundColor(.white)
                .padding(.horizontal, 28).padding(.vertical, 10)
                .background(Capsule().fill(.white.opacity(0.15))).padding(.top, 8)
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
                HStack {
                    Spacer()
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(.white.opacity(0.12)))
                    }
                }
                .padding(.horizontal, 20).padding(.top, 60)
                Spacer()
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 16)
                Spacer()
                HStack(spacing: 44) {
                    ActionButton(icon: "trash",                 label: "删除", color: .red.opacity(0.85))  { onDismiss() }
                    ActionButton(icon: "square.and.arrow.down", label: "保存", color: .white.opacity(0.9)) {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil); onDismiss()
                    }
                    ActionButton(icon: "square.and.arrow.up",   label: "分享", color: .white.opacity(0.9)) {}
                }
                .padding(.bottom, 60)
            }
        }
    }
}

private struct ActionButton: View {
    let icon: String; let label: String; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 22, weight: .medium))
                Text(label).font(.system(size: 11))
            }
            .foregroundColor(color)
        }
    }
}

#Preview { CameraView() }
