// DanmakuView.swift
// DanmakuCamera · Danmaku
//
// 弹幕总容器：叠加在相机预览层上方
// 包含弹幕层 + AI 分析指示器

import SwiftUI

// MARK: - DanmakuView

struct DanmakuView: View {

    @ObservedObject var viewModel: DanmakuViewModel

    // 读取屏幕宽度，传给每条弹幕用于计算飞行距离
    private var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    var body: some View {
        ZStack(alignment: .top) {

            // ── 弹幕层 ──
            GeometryReader { _ in
                ForEach(viewModel.items) { item in
                    DanmakuItemView(
                        item: item,
                        screenWidth: screenWidth,
                        onExpired: { id in
                            viewModel.itemDidExpire(id: id)
                        }
                    )
                }
            }

            // ── AI 分析指示器 ──
            if viewModel.connectionState.isActive {
                AIIndicatorView(state: viewModel.connectionState)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding(.top, 58)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.connectionState.isActive)
        // 弹幕层不拦截触摸事件，相机操作透传
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - AI 分析指示器

private struct AIIndicatorView: View {

    let state: AgentConnectionState
    @State private var dotOpacity: Double = 1.0

    var body: some View {
        HStack(spacing: 7) {
            // 呼吸动画圆点
            Circle()
                .fill(Color(red: 0.5, green: 0.85, blue: 1.0))
                .frame(width: 6, height: 6)
                .opacity(dotOpacity)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    ) {
                        dotOpacity = 0.25
                    }
                }

            Text(state.displayText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(white: 0.82))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(white: 0.0).opacity(0.55))
                .overlay(
                    Capsule()
                        .strokeBorder(Color(white: 1.0).opacity(0.12), lineWidth: 1)
                )
        )
        .compositingGroup()  // blur 不穿透
    }
}

// MARK: - Mock 数据驱动的 Preview

#Preview("弹幕系统完整预览") {
    MockCameraPreview()
}

// 模拟相机背景 + 弹幕系统联动的完整场景
private struct MockCameraPreview: View {

    @StateObject private var viewModel = DanmakuViewModel()
    @State private var sceneName = "等待场景..."

    var body: some View {
        ZStack {
            // 模拟相机背景
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.10, blue: 0.18),
                    Color(red: 0.04, green: 0.06, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // 模拟三分法网格
            GridOverlay()

            // 弹幕层
            DanmakuView(viewModel: viewModel)

            // 底部控制（仅 Preview 使用）
            VStack {
                Spacer()
                Text(sceneName)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        MockButton("📉 曝光") { runScene(.darkScene) }
                        MockButton("📐 倾斜") { runScene(.tiltScene) }
                        MockButton("🖼 构图") { runScene(.compositionScene) }
                        MockButton("🌫 模糊") { runScene(.blurScene) }
                        MockButton("✨ 完整") { runScene(.fullScene) }
                        MockButton("🗑 重置") { resetAll() }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            // Preview 启动时自动播放完整场景
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                runScene(.fullScene)
            }
        }
    }

    // MARK: - Mock 场景

    enum MockScene {
        case darkScene, tiltScene, compositionScene, blurScene, fullScene
    }

    private func resetAll() {
        // 触发所有 item 过期
        for item in viewModel.items {
            viewModel.itemDidExpire(id: item.id)
        }
        sceneName = "已重置"
    }

    private func runScene(_ scene: MockScene) {
        resetAll()
        viewModel.setConnectionState(.analyzing)
        sceneName = sceneName(for: scene)

        switch scene {
        case .darkScene:
            delay(1.2) {
                viewModel.setConnectionState(.streaming)
                viewModel.addSuggestion(id: "d1", type: .lighting, text: "画面偏暗，点击屏幕提亮")
            }
            delay(2.0) {
                viewModel.addSuggestion(id: "d2", type: .stability, text: "尝试增加曝光补偿")
                viewModel.setConnectionState(.idle)
            }
            delay(4.5) { viewModel.resolve(type: .lighting) }
            delay(5.2) { viewModel.resolve(type: .stability) }

        case .tiltScene:
            delay(1.2) {
                viewModel.setConnectionState(.streaming)
                viewModel.addSuggestion(id: "t1", type: .tilt, text: "手机倾斜了，请保持水平")
                viewModel.setConnectionState(.idle)
            }
            delay(2.0) {
                viewModel.addSuggestion(id: "t2", type: .other, text: "水平仪偏差约 8°")
            }
            delay(4.5) { viewModel.resolve(type: .tilt) }
            delay(5.0) { viewModel.resolve(type: .other) }

        case .compositionScene:
            delay(1.2) {
                viewModel.setConnectionState(.streaming)
                viewModel.addSuggestion(id: "c1", type: .composition, text: "主体偏左，向右移动构图")
                viewModel.setConnectionState(.idle)
            }
            delay(2.0) {
                viewModel.addSuggestion(id: "c2", type: .other, text: "参考三分法调整位置")
            }
            delay(4.5) { viewModel.resolve(type: .composition) }
            delay(5.0) { viewModel.resolve(type: .other) }

        case .blurScene:
            delay(1.2) {
                viewModel.setConnectionState(.streaming)
                viewModel.addSuggestion(id: "b1", type: .stability, text: "画面模糊，请稳住手机")
                viewModel.setConnectionState(.idle)
            }
            delay(2.0) {
                viewModel.addSuggestion(id: "b2", type: .focus, text: "等待对焦完成...")
            }
            delay(4.5) { viewModel.resolve(type: .stability) }
            delay(5.0) { viewModel.resolve(type: .focus) }

        case .fullScene:
            // 多问题同时存在，依次解决
            delay(1.5) {
                viewModel.setConnectionState(.streaming)
                viewModel.addSuggestion(id: "f1", type: .lighting,    text: "画面偏暗，点击提亮")
            }
            delay(2.2) {
                viewModel.addSuggestion(id: "f2", type: .tilt,        text: "手机倾斜 6°，保持水平")
            }
            delay(2.9) {
                viewModel.addSuggestion(id: "f3", type: .composition, text: "主体偏左，向右移动")
                viewModel.setConnectionState(.idle)
            }
            // 用户依次纠正
            delay(5.5) { viewModel.resolve(type: .tilt) }
            delay(7.5) { viewModel.resolve(type: .lighting) }
            delay(9.5) { viewModel.resolve(type: .composition) }
            // 新建议出现
            delay(10.5) {
                viewModel.setConnectionState(.analyzing)
                delay(1.0) {
                    viewModel.setConnectionState(.streaming)
                    viewModel.addSuggestion(id: "f4", type: .focus, text: "轻触主体重新对焦")
                    viewModel.setConnectionState(.idle)
                }
                delay(3.0) { viewModel.resolve(type: .focus) }
            }
        }
    }

    private func sceneName(for scene: MockScene) -> String {
        switch scene {
        case .darkScene:         return "场景：曝光调整"
        case .tiltScene:         return "场景：水平校正"
        case .compositionScene:  return "场景：构图调整"
        case .blurScene:         return "场景：对焦等待"
        case .fullScene:         return "场景：完整演示"
        }
    }

    private func delay(_ seconds: Double, action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
    }
}

// MARK: - 辅助子视图

private struct MockButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color(white: 1.0).opacity(0.10))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color(white: 1.0).opacity(0.15), lineWidth: 1)
                        )
                )
        }
    }
}

private struct GridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                // 三分法竖线
                p.move(to: CGPoint(x: w / 3, y: 0))
                p.addLine(to: CGPoint(x: w / 3, y: h))
                p.move(to: CGPoint(x: w * 2 / 3, y: 0))
                p.addLine(to: CGPoint(x: w * 2 / 3, y: h))
                // 三分法横线
                p.move(to: CGPoint(x: 0, y: h / 3))
                p.addLine(to: CGPoint(x: w, y: h / 3))
                p.move(to: CGPoint(x: 0, y: h * 2 / 3))
                p.addLine(to: CGPoint(x: w, y: h * 2 / 3))
            }
            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        }
        .ignoresSafeArea()
    }
}
