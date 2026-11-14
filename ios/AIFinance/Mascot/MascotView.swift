import SwiftUI

/// 吉祥物「小白菜」：戴白菜頭套的火柴人。
/// 身體是八個關節角度，每個動作是角度隨時間變化的一組數值（移植自網頁版動作庫）。
/// 角度 0° 是垂直向下，正值往畫面右邊轉；手肘與膝蓋是相對於上一節的角度。
enum MascotAction: Equatable {
    enum Direction { case up, right, down, left }

    case idle, wave, think, cheer, shrug, oops, bow
    case point(Direction)
}

/// 取景：全身，或只取頭到手（放在小格子裡用）。
enum MascotCrop {
    case full, bust

    var viewBox: CGRect {
        switch self {
        case .full: return CGRect(x: 0, y: -50, width: 320, height: 450)
        case .bust: return CGRect(x: 60, y: 20, width: 200, height: 210)
        }
    }
}

struct MascotView: View {
    let action: MascotAction
    var crop: MascotCrop = .full

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var previous: MascotAction?
    @State private var switchedAt = Date.distantPast

    /// 畫面測試用啟動參數 -stillMascot 讓吉祥物靜止，測試才不會一直等動畫停下來。
    private static let still = ProcessInfo.processInfo.arguments.contains("-stillMascot")
    private static let blendSeconds = 0.28

    var body: some View {
        let paused = reduceMotion || Self.still
        // App 裡有自己的 TimelineView（主畫面），這裡要寫明是 SwiftUI 的。
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { timeline in
            let pose = currentPose(at: timeline.date, paused: paused)
            let seconds = paused ? 0.3 : timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                MascotRenderer.draw(pose, seconds: seconds, crop: crop, in: &context, size: size)
            }
        }
        .aspectRatio(crop.viewBox.width / crop.viewBox.height, contentMode: .fit)
        .accessibilityHidden(true)
        .onChange(of: action) { old, _ in
            previous = old
            switchedAt = Date()
        }
    }

    private func currentPose(at date: Date, paused: Bool) -> MascotPose {
        if paused { return MascotPose.make(action, at: 0.3) }
        let sinceSwitch = date.timeIntervalSince(switchedAt)
        if let previous, sinceSwitch < Self.blendSeconds {
            // 換動作時用 0.28 秒從上一個姿勢滑過去。
            let k = max(0, sinceSwitch / Self.blendSeconds)
            let from = MascotPose.make(previous, at: max(0, date.timeIntervalSince(start)))
            let to = MascotPose.make(action, at: max(0, sinceSwitch))
            return MascotPose.mix(from, to, k * k * (3 - 2 * k))
        }
        let base = previous == nil ? start : switchedAt
        return MascotPose.make(action, at: max(0, date.timeIntervalSince(base)))
    }
}

// MARK: - 姿勢

struct MascotPose {
    enum Mouth { case smile, open, wavy, flat }

    var ry = 0.0, lean = 0.0, head = 0.0, hy = 0.0, sh = 0.0
    var lS = -38.0, lE = 143.0, rS = 38.0, rE = -143.0
    var lH = -14.0, lK = 0.0, rH = 14.0, rK = 0.0
    var eyeH = 12.0, lookX = 0.0, lookY = 0.0, brow = 2.0, browY = 0.0
    var squash = 0.0, tl = 1.0, hs = 1.0
    var mouth = Mouth.smile
    var happy = false, bubble = false, sweat = false

    private static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let k = max(0, min(1, (x - a) / (b - a)))
        return k * k * (3 - 2 * k)
    }

    static func make(_ action: MascotAction, at t: Double) -> MascotPose {
        var p = MascotPose()
        switch action {
        case .idle:
            let b = sin(t * 2.2)
            p.sh = -1.2 * b
            p.hy = -1.2 * b
            p.lean = 1.4 * sin(t * 1.1)
            p.head = 1.5 * sin(t * 0.9)
            p.eyeH = t.truncatingRemainder(dividingBy: 3.6) > 3.46 ? 1.5 : 12

        case .wave:
            p.rS = 110
            p.rE = 40 + 22 * sin(t * 9)
            p.lS = -16
            p.lE = -6
            p.head = 5 + 2 * sin(t * 4.5)
            p.lean = 2
            p.brow = 5
            p.browY = -1
            p.hy = -sin(t * 4.5)

        case .point(let direction):
            let k = sin(t * 5)
            p.brow = 4
            switch direction {
            case .right:
                p.rS = 92; p.rE = 0; p.lS = -40; p.lE = 100
                p.lean = 3 + 1.5 * k; p.head = 3; p.lookX = 3
            case .left:
                p.lS = -92; p.lE = 0; p.rS = 40; p.rE = -100
                p.lean = -3 - 1.5 * k; p.head = -3; p.lookX = -3
            case .up:
                p.rS = 105; p.rE = 62; p.lS = -40; p.lE = 100
                p.hy = -1.5 * k; p.sh = -1.5 * k; p.head = -4; p.lookY = -3; p.lookX = 1
            case .down:
                p.rS = 30; p.rE = 8; p.lS = -40; p.lE = 100
                p.lean = 2; p.head = 9 + 1.5 * k; p.lookY = 3.5; p.lookX = 2
            }

        case .think:
            p.rS = 42; p.rE = 165; p.lS = -30; p.lE = 120
            p.head = -8 + 1.5 * sin(t * 1.6)
            p.lean = -1.5
            p.lookX = -2; p.lookY = -3
            p.brow = 3; p.browY = -2
            p.bubble = true
            p.mouth = .flat

        case .cheer:
            let period = 0.72
            let phase = t.truncatingRemainder(dividingBy: period) / period
            let h = phase < 0.8 ? sin(.pi * phase / 0.8) : 0
            let s = phase >= 0.8 ? sin(.pi * (phase - 0.8) / 0.2) : 0
            let w = sin(t * 15)
            p.ry = -34 * h
            p.squash = 0.07 * s
            p.lS = -105; p.lE = -62 - 8 * w
            p.rS = 105; p.rE = 62 + 8 * w
            p.lH = -14 - 12 * h; p.lK = 34 * h
            p.rH = 14 + 12 * h; p.rK = -34 * h
            p.brow = -4; p.browY = -3
            p.happy = true
            p.mouth = .open
            p.head = 0.9 * w

        case .shrug:
            let c = t.truncatingRemainder(dividingBy: 2.4)
            let u = smooth(0, 0.3, c) * (1 - smooth(1.5, 1.9, c))
            p.sh = -6 * u
            p.lS = -16 - 14 * u; p.lE = -6 - 82 * u
            p.rS = 16 + 14 * u; p.rE = 6 + 82 * u
            p.head = 8 * u
            p.brow = 2 - 12 * u; p.browY = -3 * u
            p.mouth = u > 0.4 ? .wavy : .smile
            p.lookY = -u

        case .oops:
            p.rS = 112; p.rE = 45 + 7 * sin(t * 12)
            p.lS = -16; p.lE = -6
            p.head = 9; p.lean = 2
            p.brow = -12; p.browY = -1
            p.lookY = 3; p.lookX = -1
            p.mouth = .wavy
            p.sweat = true

        case .bow:
            let c = t.truncatingRemainder(dividingBy: 2.6)
            let u = smooth(0, 0.45, c) * (1 - smooth(1.5, 2.0, c))
            p.lS = -12; p.lE = -4; p.rS = 12; p.rE = 4
            p.tl = 1 - 0.3 * u
            p.hs = 1 - 0.14 * u
            p.hy = 8 * u
            p.lookY = 6 * u
            p.eyeH = 12 - 10.5 * smooth(0.4, 0.8, u)
            p.brow = 2; p.browY = 2 * u
        }
        return p
    }

    /// 兩個姿勢之間的內插：數值照比例，表情過半才換。
    static func mix(_ a: MascotPose, _ b: MascotPose, _ k: Double) -> MascotPose {
        func l(_ path: KeyPath<MascotPose, Double>) -> Double {
            a[keyPath: path] + (b[keyPath: path] - a[keyPath: path]) * k
        }
        var p = k < 0.5 ? a : b
        p.ry = l(\.ry); p.lean = l(\.lean); p.head = l(\.head); p.hy = l(\.hy); p.sh = l(\.sh)
        p.lS = l(\.lS); p.lE = l(\.lE); p.rS = l(\.rS); p.rE = l(\.rE)
        p.lH = l(\.lH); p.lK = l(\.lK); p.rH = l(\.rH); p.rK = l(\.rK)
        p.eyeH = l(\.eyeH); p.lookX = l(\.lookX); p.lookY = l(\.lookY)
        p.brow = l(\.brow); p.browY = l(\.browY)
        p.squash = l(\.squash); p.tl = l(\.tl); p.hs = l(\.hs)
        return p
    }
}

// MARK: - 繪製

enum MascotRenderer {
    // 骨架尺寸（單位是畫布座標，不是 pt）。
    private static let hipX = 160.0, hipY = 260.0, ground = 380.0
    private static let thigh = 62.0, shin = 62.0, torso = 78.0
    private static let shoulderDrop = 12.0, shoulderHalf = 6.0
    private static let upper = 44.0, fore = 44.0

    // 顏色。四肢在深色模式要反白才看得到；頭套和臉兩種模式共用。
    private static let limb = Color(light: 0x39323A, dark: 0xD9D3DB)
    private static let ink = Color(light: 0x2B2329, dark: 0x2B2329)
    private static let leaf = Color(light: 0x93D45E, dark: 0x93D45E)
    private static let leafDark = Color(light: 0x4F9A2E, dark: 0x4F9A2E)
    private static let leafDeep = Color(light: 0x2E5E14, dark: 0x2E5E14)
    private static let stalk = Color(light: 0xF4F2DC, dark: 0xF4F2DC)
    private static let face = Color(light: 0xFFFFFF, dark: 0xF3F1F4)
    private static let sweatBlue = Color(light: 0x7EC3EA, dark: 0x7EC3EA)

    private static func direction(_ degrees: Double) -> CGPoint {
        let r = degrees * .pi / 180
        return CGPoint(x: sin(r), y: cos(r))
    }

    private static func move(_ p: CGPoint, _ v: CGPoint, _ length: Double) -> CGPoint {
        CGPoint(x: p.x + v.x * length, y: p.y + v.y * length)
    }

    private static func line(_ a: CGPoint, _ b: CGPoint) -> Path {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        return path
    }

    private static func stroke(_ width: Double) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }

    static func draw(_ p: MascotPose, seconds: Double, crop: MascotCrop, in context: inout GraphicsContext, size: CGSize) {
        let box = crop.viewBox
        let scale = min(size.width / box.width, size.height / box.height)
        var root = context
        root.translateBy(x: (size.width - box.width * scale) / 2, y: (size.height - box.height * scale) / 2)
        root.scaleBy(x: scale, y: scale)
        root.translateBy(x: -box.minX, y: -box.minY)

        let hip = CGPoint(x: hipX, y: hipY + p.ry)
        let up = direction(180 - p.lean)
        let torsoLength = torso * p.tl
        let neck = move(hip, up, torsoLength)
        var shoulder = move(hip, up, torsoLength - shoulderDrop)
        shoulder.y += p.sh

        // 地上的影子，跳起來時變小變淡。
        let lift = max(0, -p.ry / 40)
        let shadowW = 62 * (1 - lift * 0.35), shadowH = 8 * (1 - lift * 0.35)
        root.fill(
            Path(ellipseIn: CGRect(x: hipX - shadowW, y: ground + 7 - shadowH, width: shadowW * 2, height: shadowH * 2)),
            with: .color(.black.opacity(0.16 * (1 - lift * 0.5)))
        )

        // 落地時以腳底為中心壓扁一下。
        var body = root
        body.translateBy(x: hipX, y: ground)
        body.scaleBy(x: 1 + p.squash * 0.6, y: 1 - p.squash)
        body.translateBy(x: -hipX, y: -ground)

        let limbShade = GraphicsContext.Shading.color(limb)
        for (hipAngle, kneeAngle, side) in [(p.lH, p.lK, -1.0), (p.rH, p.rK, 1.0)] {
            let knee = move(hip, direction(hipAngle), thigh)
            let ankle = move(knee, direction(hipAngle + kneeAngle), shin)
            body.stroke(line(hip, knee), with: limbShade, style: stroke(9))
            body.stroke(line(knee, ankle), with: limbShade, style: stroke(9))
            body.stroke(line(ankle, CGPoint(x: ankle.x + side * 12, y: ankle.y + 1)), with: limbShade, style: stroke(9))
        }
        body.stroke(line(hip, CGPoint(x: neck.x, y: neck.y + p.sh * 0.5)), with: limbShade, style: stroke(9))

        var head = body
        head.translateBy(x: neck.x, y: neck.y + p.hy + p.sh * 0.5)
        head.rotate(by: .degrees(p.head + p.lean))
        head.scaleBy(x: 1, y: p.hs)
        drawHead(p, seconds: seconds, in: &head)

        for (index, arm) in [(p.lS, p.lE), (p.rS, p.rE)].enumerated() {
            let origin = CGPoint(x: shoulder.x + (index == 0 ? -shoulderHalf : shoulderHalf), y: shoulder.y)
            let elbow = move(origin, direction(arm.0), upper)
            let hand = move(elbow, direction(arm.0 + arm.1), fore)
            body.stroke(line(origin, elbow), with: limbShade, style: stroke(8.5))
            body.stroke(line(elbow, hand), with: limbShade, style: stroke(8.5))
        }

        if p.bubble {
            // 思考時頭邊冒三顆泡泡。
            let dots: [(Double, Double, Double)] = [(-58, -104, 4), (-70, -120, 5.5), (-86, -140, 7.5)]
            for (i, dot) in dots.enumerated() {
                let opacity = 0.35 + 0.65 * max(0, sin(seconds * 3 - Double(i) * 0.9))
                body.fill(
                    Path(ellipseIn: CGRect(x: neck.x + dot.0 - dot.2, y: neck.y + dot.1 - dot.2, width: dot.2 * 2, height: dot.2 * 2)),
                    with: .color(Theme.accent.opacity(opacity))
                )
            }
        }
    }

    /// 白菜頭套與臉。原點在脖子，往上是負的 y。
    private static func drawHead(_ p: MascotPose, seconds: Double, in context: inout GraphicsContext) {
        // 兩側的外葉。
        var outer = Path()
        outer.move(to: CGPoint(x: -40, y: -92))
        outer.addCurve(to: CGPoint(x: -52, y: -6), control1: CGPoint(x: -68, y: -78), control2: CGPoint(x: -72, y: -34))
        outer.addCurve(to: CGPoint(x: -40, y: -92), control1: CGPoint(x: -44, y: -22), control2: CGPoint(x: -42, y: -50))
        outer.move(to: CGPoint(x: 40, y: -92))
        outer.addCurve(to: CGPoint(x: 52, y: -6), control1: CGPoint(x: 68, y: -78), control2: CGPoint(x: 72, y: -34))
        outer.addCurve(to: CGPoint(x: 40, y: -92), control1: CGPoint(x: 44, y: -22), control2: CGPoint(x: 42, y: -50))
        context.fill(outer, with: .color(leafDark))

        // 頂端一圈捲捲的葉緣。
        let frills: [(Double, Double, Double)] = [
            (-46, -70, 15), (-37, -92, 18), (-20, -108, 19), (0, -114, 20), (20, -108, 19), (37, -92, 18), (46, -70, 15),
        ]
        for frill in frills {
            context.fill(
                Path(ellipseIn: CGRect(x: frill.0 - frill.2, y: frill.1 - frill.2, width: frill.2 * 2, height: frill.2 * 2)),
                with: .color(leaf)
            )
        }

        // 菜身。
        var bodyPath = Path()
        bodyPath.move(to: CGPoint(x: 0, y: -116))
        bodyPath.addCurve(to: CGPoint(x: 50, y: -48), control1: CGPoint(x: 38, y: -116), control2: CGPoint(x: 50, y: -84))
        bodyPath.addCurve(to: CGPoint(x: 0, y: 8), control1: CGPoint(x: 50, y: -12), control2: CGPoint(x: 34, y: 8))
        bodyPath.addCurve(to: CGPoint(x: -50, y: -48), control1: CGPoint(x: -34, y: 8), control2: CGPoint(x: -50, y: -12))
        bodyPath.addCurve(to: CGPoint(x: 0, y: -116), control1: CGPoint(x: -50, y: -84), control2: CGPoint(x: -38, y: -116))
        bodyPath.closeSubpath()
        context.fill(bodyPath, with: .color(leaf))

        // 底部的白色菜梗，上緣是波浪。
        var stalkPath = Path()
        stalkPath.move(to: CGPoint(x: -47, y: -22))
        stalkPath.addQuadCurve(to: CGPoint(x: -16, y: -20), control: CGPoint(x: -31, y: -34))
        stalkPath.addQuadCurve(to: CGPoint(x: 16, y: -20), control: CGPoint(x: 0, y: -34))
        stalkPath.addQuadCurve(to: CGPoint(x: 47, y: -22), control: CGPoint(x: 31, y: -34))
        stalkPath.addCurve(to: CGPoint(x: 0, y: 8), control1: CGPoint(x: 44, y: -2), control2: CGPoint(x: 30, y: 8))
        stalkPath.addCurve(to: CGPoint(x: -47, y: -22), control1: CGPoint(x: -30, y: 8), control2: CGPoint(x: -44, y: -2))
        stalkPath.closeSubpath()
        context.fill(stalkPath, with: .color(stalk))

        // 葉面的反光。
        var shine = Path()
        shine.move(to: CGPoint(x: -34, y: -84))
        shine.addQuadCurve(to: CGPoint(x: -8, y: -106), control: CGPoint(x: -26, y: -100))
        context.stroke(shine, with: .color(.white.opacity(0.4)), style: stroke(5))

        // 臉。
        context.fill(Path(ellipseIn: CGRect(x: -33, y: -79, width: 66, height: 66)), with: .color(leafDeep))
        let faceCircle = Path(ellipseIn: CGRect(x: -30, y: -76, width: 60, height: 60))
        context.fill(faceCircle, with: .color(face))
        context.stroke(faceCircle, with: .color(ink), lineWidth: 3)

        let inkShade = GraphicsContext.Shading.color(ink)
        let ex = p.lookX, ey = p.lookY
        for side in [-1.0, 1.0] {
            let cx = side * 11 + ex, cy = -48 + ey
            if p.happy {
                var eye = Path()
                eye.move(to: CGPoint(x: cx - 5, y: cy + 3))
                eye.addQuadCurve(to: CGPoint(x: cx + 5, y: cy + 3), control: CGPoint(x: cx, y: cy - 6))
                context.stroke(eye, with: inkShade, style: stroke(3.6))
            } else {
                let h = max(1.5, p.eyeH)
                context.fill(
                    Path(roundedRect: CGRect(x: cx - 2.3, y: cy - h / 2, width: 4.6, height: h), cornerRadius: min(2.3, h / 2)),
                    with: inkShade
                )
            }
            let bx = side * 12 + ex * 0.5, by = -61 + p.browY + ey * 0.5
            let angle = p.brow * .pi / 180
            let c = 8 * cos(angle), s = 8 * sin(angle)
            context.stroke(
                line(CGPoint(x: bx - side * c, y: by + s), CGPoint(x: bx + side * c, y: by - s)),
                with: inkShade, style: stroke(3.4)
            )
        }

        let mx = ex * 0.5, my = -30 + ey * 0.5
        var mouth = Path()
        switch p.mouth {
        case .smile:
            mouth.move(to: CGPoint(x: mx - 6, y: my - 1))
            mouth.addQuadCurve(to: CGPoint(x: mx + 6, y: my - 1), control: CGPoint(x: mx, y: my + 5))
            context.stroke(mouth, with: inkShade, style: stroke(3))
        case .open:
            mouth.move(to: CGPoint(x: mx - 7, y: my - 2))
            mouth.addQuadCurve(to: CGPoint(x: mx + 7, y: my - 2), control: CGPoint(x: mx, y: my + 10))
            mouth.closeSubpath()
            context.fill(mouth, with: inkShade)
        case .wavy:
            mouth.move(to: CGPoint(x: mx - 7, y: my))
            mouth.addQuadCurve(to: CGPoint(x: mx, y: my), control: CGPoint(x: mx - 3.5, y: my - 4))
            mouth.addQuadCurve(to: CGPoint(x: mx + 7, y: my), control: CGPoint(x: mx + 3.5, y: my + 4))
            context.stroke(mouth, with: inkShade, style: stroke(3))
        case .flat:
            context.stroke(line(CGPoint(x: mx - 5, y: my), CGPoint(x: mx + 5, y: my)), with: inkShade, style: stroke(3))
        }

        if p.sweat {
            // 抓頭時額角滑下一滴汗。
            let d = (seconds * 0.9).truncatingRemainder(dividingBy: 1)
            let y = -84 + d * 6
            var drop = Path()
            drop.move(to: CGPoint(x: -36, y: y))
            drop.addQuadCurve(to: CGPoint(x: -36, y: y + 9), control: CGPoint(x: -41, y: y + 7))
            drop.addQuadCurve(to: CGPoint(x: -36, y: y), control: CGPoint(x: -31, y: y + 7))
            context.fill(drop, with: .color(sweatBlue.opacity(1 - d * 0.6)))
        }
    }
}
