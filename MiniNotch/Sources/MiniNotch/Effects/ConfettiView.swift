import SwiftUI

// ============================================================
// 完成撒花（effects spec）
//
// Canvas + TimelineView 实现，~30 个彩色粒子从发射点喷出，
// 抛物线下落 + 旋转 + 淡出，总时长 ~1.2s，60fps。
//
// 用法（叠在岛体/卡片 overlay 上，trigger 递增即喷一次）：
//
//   @State private var confetti = 0
//
//   islandBody.overlay {
//       ConfettiBurst(trigger: confetti)
//   }
//   // 完成 todo 时：confetti += 1
//
// 特性：
// - 未触发 / 播完后视图为空，零开销（TimelineView 不存在，无帧回调）
// - 减弱动态效果开启时不播放
// - allowsHitTesting(false)，绝不挡鼠标
// ============================================================

/// 单次撒花爆发。`trigger` 变化（通常递增）时从发射点喷一次粒子。
struct ConfettiBurst: View {
    /// 触发计数：变化即播放一次（初始值不播放）
    let trigger: Int
    /// 发射点（相对坐标，默认中心）。CelebrationOverlay 用底部发射点做烟花。
    var origin: UnitPoint = .center
    /// 发射模式：burst = 四散小爆（完成单个 todo）；fountain = 向上喷射（庆祝烟花）
    var mode: ConfettiMode = .burst
    /// 粒子数量
    var particleCount: Int = 30

    @State private var particles: [ConfettiParticle] = []
    @State private var startDate: Date = .distantPast
    @State private var playing = false
    /// 播放轮次（用于 task(id:) 取消旧的停止倒计时）
    @State private var epoch = 0

    /// 总时长（含淡出）
    private static let duration: Double = 1.2

    var body: some View {
        ZStack {
            if playing {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSince(startDate)
                        guard t >= 0 else { return }
                        let originPoint = CGPoint(
                            x: origin.x * size.width,
                            y: origin.y * size.height
                        )
                        for particle in particles {
                            particle.draw(in: &context, at: t, origin: originPoint)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            // 减弱动态效果：禁用粒子（effects spec 降级要求）
            guard !MotionPreference.reduceMotion else { return }
            particles = ConfettiParticle.makeBurst(count: particleCount, mode: mode)
            startDate = Date()
            playing = true
            epoch += 1
        }
        // 播完拆掉 TimelineView，回到零开销状态；连击时旧倒计时被取消
        .task(id: epoch) {
            guard playing else { return }
            try? await Task.sleep(for: .seconds(Self.duration + 0.1))
            guard !Task.isCancelled else { return }
            playing = false
            particles = []
        }
    }
}

/// 发射模式
enum ConfettiMode {
    /// 从发射点四散小爆（完成单个 todo）
    case burst
    /// 强力向上喷射、抛物线落下（庆祝烟花，发射点放底部）
    case fountain
}

// MARK: - 粒子

/// 单个撒花粒子：发射时刻确定初速/颜色/旋转，之后位置纯函数计算（无逐帧状态）。
struct ConfettiParticle {
    /// 初速度 (pt/s)，y 向下为正
    var velocity: CGVector
    var color: Color
    /// 粒子尺寸（矩形长边）
    var size: CGFloat
    /// 初始旋转角 + 角速度 (rad/s)
    var rotation: Double
    var spin: Double
    /// true = 圆粒子，false = 小矩形
    var isCircle: Bool
    /// 出生延迟（错开发射，更自然）
    var delay: Double

    /// 重力加速度 (pt/s²)
    private static let gravity: Double = 580

    /// 撒花调色板：来源色全套（DS.sourceColor）+ 金色（DS.Colors.gold）
    private static var palette: [Color] {
        TodoSource.allCases.map { DS.sourceColor($0) } + [DS.Colors.gold]
    }

    static func makeBurst(count: Int, mode: ConfettiMode) -> [ConfettiParticle] {
        (0..<count).map { _ in
            let velocity: CGVector
            switch mode {
            case .burst:
                // 全向小爆，略偏上
                let angle = Double.random(in: 0..<(2 * .pi))
                let speed = Double.random(in: 90...240)
                velocity = CGVector(
                    dx: cos(angle) * speed,
                    dy: sin(angle) * speed - 110 // 整体上抛一点
                )
            case .fountain:
                // 向上喷射 ±28°，速度大，烟花感
                let angle = -Double.pi / 2 + Double.random(in: -0.5...0.5)
                let speed = Double.random(in: 450...780)
                velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
            }
            return ConfettiParticle(
                velocity: velocity,
                color: palette.randomElement() ?? DS.Colors.gold,
                size: CGFloat.random(in: 4...7),
                rotation: Double.random(in: 0..<(2 * .pi)),
                spin: Double.random(in: -10...10),
                isCircle: Bool.random() && Bool.random(), // ~25% 圆粒子
                delay: Double.random(in: 0...0.12)
            )
        }
    }

    /// 在时间 t 绘制粒子（位置 = 抛物线，透明度 = 末段淡出）
    func draw(in context: inout GraphicsContext, at t: Double, origin: CGPoint) {
        let life = t - delay
        guard life > 0 else { return }
        // 末段 0.35s 淡出
        let fadeStart = 1.2 - 0.35
        let opacity = life < fadeStart ? 1.0 : max(0, 1 - (life - fadeStart) / 0.35)
        guard opacity > 0 else { return }

        let x = origin.x + velocity.dx * life
        let y = origin.y + velocity.dy * life + 0.5 * Self.gravity * life * life
        let angle = rotation + spin * life

        var layer = context
        layer.opacity = opacity
        layer.translateBy(x: x, y: y)
        layer.rotate(by: .radians(angle))
        if isCircle {
            let r = size * 0.45
            layer.fill(
                Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)),
                with: .color(color)
            )
        } else {
            layer.fill(
                Path(CGRect(x: -size / 2, y: -size * 0.3, width: size, height: size * 0.6)),
                with: .color(color)
            )
        }
    }
}
