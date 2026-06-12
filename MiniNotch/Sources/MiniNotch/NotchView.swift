import SwiftUI

/// 刘海面板的 SwiftUI 视图（壳子版，无业务功能）。
///
/// 设计要点：
/// - 收起态：与刘海尺寸完全一致的黑色"假刘海"，视觉上跟真刘海融为一体
/// - 展开态：鼠标悬停时从刘海"长出来"，向下扩展显示内容区
/// - 所有圆角都用刘海下沿的圆角（~10pt）保持视觉一致性
struct NotchView: View {
    @State private var isExpanded = false

    let notchSize: CGSize
    let expandedSize: CGSize

    /// 当前可见尺寸 —— 悬停热区严格等于这个尺寸
    private var currentSize: CGSize {
        isExpanded ? expandedSize : notchSize
    }

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(cornerRadius: 10)
                .fill(.black)
                .shadow(color: .black.opacity(isExpanded ? 0.3 : 0), radius: 12, y: 4)

            if isExpanded {
                contentView
                    .frame(width: expandedSize.width, height: expandedSize.height)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // 关键：这一层 frame 决定 onHover 的热区。
        // 收起时只有刘海那一小块（水平居中、贴顶），展开后才是整个面板。
        .frame(width: currentSize.width, height: currentSize.height, alignment: .top)
        .contentShape(Rectangle())
        .contextMenu {
            Button("退出 MiniNotch") {
                NSApp.terminate(nil)
            }
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isExpanded = hovering
            }
        }
        // 外层撑满窗口，保证布局位置稳定（顶部居中）
        .frame(width: expandedSize.width, height: expandedSize.height, alignment: .top)
    }

    // MARK: - 展开态内容（占位，等待各模块接入）

    @ViewBuilder
    private var contentView: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: notchSize.height)

            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.6))
                Text("MiniNotch")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("壳子已就绪，等待功能接入")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - 刘海形状

struct NotchShape: Shape {
    var cornerRadius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let r = cornerRadius
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - r))
        path.addArc(
            center: CGPoint(x: rect.width - r, y: rect.height - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: r, y: rect.height))
        path.addArc(
            center: CGPoint(x: r, y: rect.height - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
