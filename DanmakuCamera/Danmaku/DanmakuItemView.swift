// DanmakuItemView.swift
// DanmakuCamera · Danmaku
//
// 单条弹幕：从右侧飘入 → 匀速向左 → 灰色/绿色状态切换 → 飘出后回调

import SwiftUI

// MARK: - 颜色 / 样式常量

private enum DanmakuStyle {

    // 灰色（pending）
    static let pendingBg        = Color(white: 0.18).opacity(0.82)
    static let pendingFg        = Color(white: 0.88)
    static let pendingBorder    = Color(white: 1.0).opacity(0.10)
    static let pendingDot       = Color(white: 0.65)
    static let pendingShadow    = Color.black.opacity(0.35)

    // 绿色（achieved）
    static let achievedBg       = Color(red: 0.10, green: 0.33, blue: 0.20).opacity(0.90)
    static let achievedFg       = Color(red: 0.65, green: 1.00, blue: 0.72)
    static let achievedBorder   = Color(red: 0.35, green: 0.88, blue: 0.50).opacity(0.40)
    static let achievedDot      = Color(red: 0.32, green: 0.90, blue: 0.52)
    static let achievedShadow   = Color(red: 0.20, green: 0.80, blue: 0.40).opacity(0.30)
}

// MARK: - DanmakuItemView

struct DanmakuItemView: View {

    let item: SuggestionItem
    let screenWidth: CGFloat
    var onExpired: (String) -> Void   // 飘出屏幕后通知 ViewModel

    // 飞行动画状态
    @State private var flyOffset: CGFloat = 0          // 初始值在 onAppear 中设置为屏幕右侧
    @State private var hasStartedFlying = false

    // 淡出状态（achieved 停留后渐隐）
    @State private var opacity: Double = 1.0

    // 是否已触发 expired 回调（防止重复）
    @State private var hasExpired = false

    // MARK: - Body

    var body: some View {
        pill
            .offset(x: flyOffset, y: item.lane.yOffset)
            .opacity(opacity)
            // 颜色过渡动画（pending → achieved）
            .animation(.easeInOut(duration: 0.45), value: item.status)
            .onAppear {
                startFlying()
            }
            // 当状态变为 achieved 时触发淡出
            .onChange(of: item.status) { _, newStatus in
                if newStatus == .achieved {
                    scheduleAchievedFadeOut()
                }
            }
    }

    // MARK: - 胶囊形状

    private var pill: some View {
        HStack(spacing: 7) {
            // 左侧状态圆点 / 勾
            statusIndicator

            // 建议文字
            Text(item.text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(backgroundColor)
                .overlay(
                    Capsule()
                        .strokeBorder(borderColor, lineWidth: 1)
                )
                .shadow(color: shadowColor, radius: 8, x: 0, y: 2)
        )
        .foregroundColor(foregroundColor)
        // 不允许换行，弹幕保持单行
        .fixedSize()
    }

    // MARK: - 状态指示器（圆点 → 勾）

    @ViewBuilder
    private var statusIndicator: some View {
        if item.status == .achieved {
            // 绿色勾圈
            ZStack {
                Circle()
                    .fill(DanmakuStyle.achievedDot)
                    .frame(width: 15, height: 15)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
            }
            .transition(.scale.combined(with: .opacity))
        } else {
            // 灰色圆点
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
        }
    }

    // MARK: - 动态颜色

    private var backgroundColor: Color {
        switch item.status {
        case .pending, .expired:   return DanmakuStyle.pendingBg
        case .resolving, .achieved: return DanmakuStyle.achievedBg
        }
    }

    private var foregroundColor: Color {
        switch item.status {
        case .pending, .expired:   return DanmakuStyle.pendingFg
        case .resolving, .achieved: return DanmakuStyle.achievedFg
        }
    }

    private var borderColor: Color {
        switch item.status {
        case .pending, .expired:   return DanmakuStyle.pendingBorder
        case .resolving, .achieved: return DanmakuStyle.achievedBorder
        }
    }

    private var dotColor: Color {
        switch item.status {
        case .pending, .expired:   return DanmakuStyle.pendingDot
        case .resolving, .achieved: return DanmakuStyle.achievedDot
        }
    }

    private var shadowColor: Color {
        switch item.status {
        case .pending, .expired:   return DanmakuStyle.pendingShadow
        case .resolving, .achieved: return DanmakuStyle.achievedShadow
        }
    }

    // MARK: - 飞行动画

    private func startFlying() {
        guard !hasStartedFlying else { return }
        hasStartedFlying = true

        // 起点：右侧屏幕外
        flyOffset = screenWidth + 300

        // 稍微延迟一帧，让 SwiftUI 确认初始位置后再启动动画
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.linear(duration: item.flyDuration)) {
                // 终点：左侧屏幕外（留足胶囊宽度余量）
                flyOffset = -(screenWidth + 400)
            }

            // 飞行结束后通知过期（只对 pending 状态触发，achieved 状态由 scheduleAchievedFadeOut 处理）
            DispatchQueue.main.asyncAfter(deadline: .now() + item.flyDuration) {
                guard item.status == .pending else { return }
                notifyExpired()
            }
        }
    }

    // MARK: - Achieved 停留 → 淡出

    private func scheduleAchievedFadeOut() {
        // 先停在当前位置（不再继续飘动）
        // 注意：SwiftUI 动画无法中途暂停，achieved 后的位置由动画时间点决定
        // 实际效果：变绿瞬间在当前位置，1.8s 后淡出

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.5)) {
                opacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                notifyExpired()
            }
        }
    }

    private func notifyExpired() {
        guard !hasExpired else { return }
        hasExpired = true
        onExpired(item.id)
    }
}

// MARK: - Preview

#Preview("弹幕单条 · Pending") {
    ZStack {
        Color.black.ignoresSafeArea()
        DanmakuItemView(
            item: .mock(
                type: .lighting,
                text: "画面偏暗，点击屏幕提亮",
                lane: DanmakuLane(index: 0, yOffset: 0)
            ),
            screenWidth: 390,
            onExpired: { _ in }
        )
    }
}

#Preview("弹幕单条 · Achieved") {
    ZStack {
        Color.black.ignoresSafeArea()
        // 直接构造 achieved 状态用于预览
        DanmakuItemView(
            item: {
                var item = SuggestionItem.mock(
                    type: .tilt,
                    text: "手机倾斜已校正 ✓",
                    lane: DanmakuLane(index: 0, yOffset: 0)
                )
                item.status = .achieved
                return item
            }(),
            screenWidth: 390,
            onExpired: { _ in }
        )
    }
}
