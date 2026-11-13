//
//  TableRenderer.swift
//  Tiny Pool
//
//  Draws the room, the table, the balls and the aiming overlay with flat shapes.
//

import SwiftUI
import simd

extension GraphicsContext {
    func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
}

enum TableRenderer {
    /// The room: carpet with a soft diamond pattern.
    static func drawRoom(_ ctx: inout GraphicsContext, size: CGSize, felt: Felt) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(felt.carpet))
        let step: CGFloat = 70
        var lines = Path()
        var x = -size.height
        while x < size.width {
            lines.move(to: CGPoint(x: x, y: 0)); lines.addLine(to: CGPoint(x: x + size.height, y: size.height))
            lines.move(to: CGPoint(x: x + size.height, y: 0)); lines.addLine(to: CGPoint(x: x, y: size.height))
            x += step
        }
        ctx.stroke(lines, with: .color(felt.carpetMark.opacity(0.55)), lineWidth: 2)
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, game: PoolGame) {
        let t = game.transform(for: size)
        drawRoom(&ctx, size: size, felt: game.felt)

        var w = ctx
        w.concatenate(t.affine)
        drawTable(&w, felt: game.felt)

        let time = game.animTime
        let balls = game.sim.balls

        // Balls on their way down a pocket: smaller and darker the deeper they are.
        for sink in game.sinks {
            let e = sink.depth * sink.depth * (3 - 2 * sink.depth)
            drawBall(&w, &ctx, t, kind: sink.kind, at: sink.pos, scale: 1 - 0.45 * e, opacity: 1,
                     ring: ringColor(game, sink.kind), orient: game.orient[sink.index],
                     dark: min(1, sink.depth * 1.5), shadow: 1 - sink.depth)
        }

        // Rings that show where each cue ball can be picked up (versus).
        if game.isSimultaneous {
            for p in 0..<game.mode.playerCount where game.canAim(p) && game.aims[p] == nil {
                guard let cue = game.cueBall(of: p) else { continue }
                let pulse = 0.5 + 0.5 * sin(time * 4 + Double(p))
                let r = CGFloat(Table.ballRadius) + 8 + 2 * CGFloat(pulse)
                w.stroke(w.circle(cue.pos.cg, r), with: .color(PoolColors.players[p].opacity(0.55 + 0.3 * pulse)),
                         style: StrokeStyle(lineWidth: 3, dash: [5, 5]))
            }
        }

        // Ball in hand: the cue ball can be carried anywhere.
        if game.canPlaceCue, let cue = game.cueBall(of: 0), game.aims[0] == nil {
            let pulse = 0.5 + 0.5 * sin(time * 5)
            let r = CGFloat(Table.ballRadius) + 9 + 3 * CGFloat(pulse)
            w.stroke(w.circle(cue.pos.cg, r), with: .color(PoolColors.players[game.turn].opacity(0.6 + 0.3 * pulse)),
                     style: StrokeStyle(lineWidth: 3, dash: [6, 5]))
        }

        for (i, b) in balls.enumerated() where b.onTable {
            var scale = 1.0
            if let p = b.player, let start = game.appeared[p] {
                // Pops in with a little overshoot.
                let k = max(0, min(1, (time - start) / 0.4))
                let c1 = 1.70158, c3 = c1 + 1
                scale = max(0.05, 1 + c3 * pow(k - 1, 3) + c1 * pow(k - 1, 2))
            }
            drawBall(&w, &ctx, t, kind: b.kind, at: b.pos, scale: scale, opacity: 1,
                     ring: ringColor(game, b.kind), orient: game.orient[i], dark: 0, shadow: 1)
        }

        // A ball going down slides under the leather lip of its pocket.
        for sink in game.sinks where sink.depth > 0.12 {
            let r = CGFloat(Table.pocketRadius(sink.pocketIndex))
            let a = min(1, (sink.depth - 0.12) * 4)
            w.stroke(w.circle(sink.pocket.cg, r + 3), with: .color(PoolColors.leather.opacity(a)), lineWidth: 6)
        }

        // Aim: guide first, then the cue on top.
        for (p, pull) in game.aims.sorted(by: { $0.key < $1.key }) {
            guard let cue = game.cueBall(of: p) else { continue }
            drawAim(&w, game: game, player: p, from: cue.pos, pull: pull)
        }
    }

    private static func ringColor(_ game: PoolGame, _ kind: BallKind) -> Color {
        guard case .cue(let p) = kind else { return .clear }
        // Taking turns, the ring colour says whose turn it is.
        return PoolColors.players[game.isSimultaneous ? p : game.turn]
    }

    // MARK: - The table

    private static func drawTable(_ w: inout GraphicsContext, felt: Felt) {
        let W = Table.width, H = Table.height, rail = Table.rail
        let outer = CGRect(x: -rail, y: -rail, width: W + 2 * rail, height: H + 2 * rail)
        let railShape = Path(roundedRect: outer, cornerRadius: 34)

        // A shadow on the carpet, then the wooden rail with a lighter top edge.
        w.fill(railShape.offsetBy(dx: 0, dy: 9), with: .color(.black.opacity(0.22)))
        w.fill(railShape, with: .color(PoolColors.wood))
        w.stroke(railShape, with: .color(PoolColors.woodDark), lineWidth: 4)
        w.stroke(Path(roundedRect: outer.insetBy(dx: 7, dy: 7), cornerRadius: 27), with: .color(PoolColors.woodLight.opacity(0.7)), lineWidth: 3)

        // The cushion strip, then the cloth.
        let cushion = CGRect(x: -16, y: -16, width: W + 32, height: H + 32)
        w.fill(Path(roundedRect: cushion, cornerRadius: 12), with: .color(felt.cushion))
        w.stroke(Path(roundedRect: cushion, cornerRadius: 12), with: .color(.black.opacity(0.18)), lineWidth: 2)
        let cloth = CGRect(x: 0, y: 0, width: W, height: H)
        w.fill(Path(cloth), with: .color(felt.cloth))
        // Soft light across the middle of the cloth.
        w.fill(Path(ellipseIn: cloth.insetBy(dx: W * 0.12, dy: H * 0.06)), with: .color(.white.opacity(0.05)))

        // Diamonds on the rail.
        for k in 1..<8 where k != 4 {
            let x = W * Double(k) / 8
            w.fill(diamond(CGPoint(x: x, y: -28)), with: .color(PoolColors.diamond))
            w.fill(diamond(CGPoint(x: x, y: H + 28)), with: .color(PoolColors.diamond))
        }
        for k in 1..<4 {
            let y = H * Double(k) / 4
            w.fill(diamond(CGPoint(x: -28, y: y)), with: .color(PoolColors.diamond))
            w.fill(diamond(CGPoint(x: W + 28, y: y)), with: .color(PoolColors.diamond))
        }

        // The head string and the spots.
        var string = Path()
        string.move(to: CGPoint(x: Table.headSpot.x, y: 0)); string.addLine(to: CGPoint(x: Table.headSpot.x, y: H))
        w.stroke(string, with: .color(.white.opacity(0.18)), lineWidth: 2)
        for spot in [Table.headSpot, Table.footSpot] {
            w.fill(w.circle(spot.cg, 3.5), with: .color(.white.opacity(0.3)))
        }

        // Pockets.
        for (k, c) in Table.pockets.enumerated() {
            let r = CGFloat(Table.pocketRadius(k))
            w.fill(w.circle(c.cg, r + 6), with: .color(PoolColors.leather))
            w.fill(w.circle(c.cg, r), with: .color(PoolColors.pocket))
            w.fill(w.circle(CGPoint(x: c.x - 3, y: c.y - 3), r * 0.55), with: .color(.black.opacity(0.35)))
        }
    }

    private static func diamond(_ c: CGPoint) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - 5)); p.addLine(to: CGPoint(x: c.x + 5, y: c.y))
        p.addLine(to: CGPoint(x: c.x, y: c.y + 5)); p.addLine(to: CGPoint(x: c.x - 5, y: c.y))
        p.closeSubpath()
        return p
    }

    // MARK: - Balls

    /// Points on the unit sphere in a band around `axis`, for painting stripes and rings that turn
    /// with the ball. `lo...hi` is how far along the axis the band runs (-1...1).
    private static func bandGrid(axis: SIMD3<Double>, lo: Double, hi: Double, rows: Int, cols: Int) -> [[SIMD3<Double>]] {
        let helper = abs(axis.z) > 0.9 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 0, 1)
        let u = simd_normalize(simd_cross(axis, helper))
        let v = simd_cross(axis, u)
        return (0...rows).map { i in
            let h = lo + (hi - lo) * Double(i) / Double(rows)
            let ring = (1 - h * h).squareRoot()
            return (0...cols).map { j in
                let a = Double(j) / Double(cols) * 2 * .pi
                return axis * h + (u * cos(a) + v * sin(a)) * ring
            }
        }
    }

    /// The stripe of a striped ball, and the two halves of a cue ball's ring.
    private static let stripeGrid = bandGrid(axis: SIMD3(0, 1, 0), lo: -0.56, hi: 0.56, rows: 4, cols: 28)
    private static let ringFront = bandGrid(axis: SIMD3(0, 0, 1), lo: 0.66, hi: 0.9, rows: 2, cols: 28)
    private static let ringBack = bandGrid(axis: SIMD3(0, 0, -1), lo: 0.66, hi: 0.9, rows: 2, cols: 28)

    /// The part of a band that faces us, as one filled shape.
    private static func band(_ grid: [[SIMD3<Double>]], _ q: simd_quatd, _ c: CGPoint, _ r: CGFloat) -> Path {
        let pts = grid.map { row in row.map { q.act($0) } }
        func pt(_ v: SIMD3<Double>) -> CGPoint { CGPoint(x: c.x + r * CGFloat(v.x), y: c.y + r * CGFloat(v.y)) }
        var path = Path()
        for i in 0..<(pts.count - 1) {
            for j in 0..<(pts[i].count - 1) {
                let a = pts[i][j], b = pts[i][j + 1], c2 = pts[i + 1][j + 1], d = pts[i + 1][j]
                guard a.z + b.z + c2.z + d.z > 0 else { continue }
                path.move(to: pt(a)); path.addLine(to: pt(b)); path.addLine(to: pt(c2)); path.addLine(to: pt(d))
                path.closeSubpath()
            }
        }
        return path
    }

    /// A round patch on the ball seen at an angle: squashed along the way it leans.
    private static func cap(_ w: SIMD3<Double>, _ c: CGPoint, _ r: CGFloat, radius: Double) -> Path {
        let along = CGFloat(radius) * r * CGFloat(max(0.02, w.z))
        let across = CGFloat(radius) * r
        let centre = CGPoint(x: c.x + r * CGFloat(w.x), y: c.y + r * CGFloat(w.y))
        let shape = Path(ellipseIn: CGRect(x: -along, y: -across, width: along * 2, height: across * 2))
        let angle = atan2(w.y, w.x)
        return shape.applying(CGAffineTransform(rotationAngle: CGFloat(angle)).concatenating(CGAffineTransform(translationX: centre.x, y: centre.y)))
    }

    private static func drawBall(_ w: inout GraphicsContext, _ screen: inout GraphicsContext, _ t: ViewTransform,
                                 kind: BallKind, at p: Vec, scale: Double, opacity: Double, ring: Color,
                                 orient q: simd_quatd, dark: Double, shadow: Double) {
        guard scale > 0.01 else { return }
        let c = p.cg
        let r = CGFloat(Table.ballRadius * scale)
        var b = w
        b.opacity = opacity

        // The shadow stays on the cloth.
        if shadow > 0.01 {
            b.fill(b.circle(CGPoint(x: c.x + 1.8, y: c.y + 2.8), r), with: .color(.black.opacity(0.3 * shadow)))
        }

        // Everything on the ball is clipped to its disc.
        var d = b
        d.clip(to: b.circle(c, r))
        let front = q.act(SIMD3<Double>(0, 0, 1)), back = q.act(SIMD3<Double>(0, 0, -1))

        switch kind {
        case .cue:
            d.fill(Path(CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.white))
            d.fill(band(ringFront, q, c, r), with: .color(ring))
            d.fill(band(ringBack, q, c, r), with: .color(ring))
        case .object(let number):
            let color = PoolColors.ball(number)
            d.fill(Path(CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(number > 8 ? .white : color))
            if number > 8 { d.fill(band(stripeGrid, q, c, r), with: .color(color)) }
            for n in [front, back] where n.z > 0.01 {
                d.fill(cap(n, c, r, radius: 0.6), with: .color(.white))
            }
        }
        if dark > 0 {
            d.fill(Path(CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(PoolColors.pocket.opacity(0.92 * dark)))
        }
        b.stroke(b.circle(c, r), with: .color(.black.opacity(0.25)), lineWidth: 1)
        b.fill(b.circle(CGPoint(x: c.x - r * 0.34, y: c.y - r * 0.34), r * 0.25), with: .color(.white.opacity(0.7 * (1 - dark))))

        // The number turns with the ball, and is drawn flat in screen space so it stays sharp.
        if case .object(let number) = kind, r * t.scale >= 5, dark < 0.7 {
            let lin = t.affine
            func screenAngle(_ v: SIMD3<Double>) -> Double {
                let sx = Double(lin.a) * v.x + Double(lin.c) * v.y
                let sy = Double(lin.b) * v.x + Double(lin.d) * v.y
                return atan2(sy, sx)
            }
            let base = screenAngle(SIMD3(0, -1, 0))
            for n in [front, back] where n.z > 0.4 {
                let up = q.act(SIMD3<Double>(0, -1, 0))
                let angle = screenAngle(up) - base
                var s = screen
                s.opacity = opacity * min(1, (n.z - 0.4) / 0.25) * (1 - dark)
                // Painted on: the number is cut off by the edge of its badge, never poking out.
                s.clip(to: cap(n, c, r, radius: 0.6).applying(lin))
                let at = t.toScreen(Vec(p.x + n.x * Double(r), p.y + n.y * Double(r)))
                s.translateBy(x: at.x, y: at.y)
                s.rotate(by: .radians(angle))
                let size = r * t.scale * 0.78 * CGFloat(0.55 + 0.45 * n.z)
                s.draw(Text("\(number)").font(.system(size: size, weight: .heavy, design: .rounded)).foregroundStyle(.black), at: .zero)
            }
        }
    }

    // MARK: - Aiming

    private static func drawAim(_ w: inout GraphicsContext, game: PoolGame, player: Int, from ball: Vec, pull: Vec) {
        let power = Shot.power(forPull: pull.length)
        let dir = pull.normalized
        let centre = ball.cg
        // Yellow when soft, shading to orange-red as the shot gets harder.
        let tint = Color(hue: 0.005 + 0.15 * (1 - power), saturation: 0.88, brightness: 1.0)
        let ringR: CGFloat = 24

        // The guide: where the cue ball goes, where it meets a ball, and where they go next.
        if let preview = game.previews[player] {
            drawDots(&w, preview.cue, startAt: Double(ringR) + 3, color: tint, fade: true)
            if let ghost = preview.ghost {
                // Where the cue ball will hit.
                w.stroke(w.circle(ghost.cg, CGFloat(Table.ballRadius)), with: .color(.white.opacity(0.85)),
                         style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                // With the hint on, also where the two balls go afterwards.
                if game.showGuide {
                    drawDots(&w, preview.target, startAt: Double(Table.ballRadius) + 2, color: .white, fade: true)
                    drawDots(&w, preview.after, startAt: Double(Table.ballRadius) + 2, color: tint.opacity(0.7), fade: true)
                }
            }
        }

        // The cue, behind the ball, drawn back further the harder the shot.
        let tip = centre - CGPoint(x: dir.x, y: dir.y).scaled(Double(ringR) + 2 + 30 * power)
        let length = 330.0
        let butt = tip - CGPoint(x: dir.x, y: dir.y).scaled(length)
        let side = CGPoint(x: -dir.y, y: dir.x)
        func taper(_ a: CGPoint, _ wa: CGFloat, _ b: CGPoint, _ wb: CGFloat) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: a.x + side.x * wa, y: a.y + side.y * wa))
            p.addLine(to: CGPoint(x: b.x + side.x * wb, y: b.y + side.y * wb))
            p.addLine(to: CGPoint(x: b.x - side.x * wb, y: b.y - side.y * wb))
            p.addLine(to: CGPoint(x: a.x - side.x * wa, y: a.y - side.y * wa))
            p.closeSubpath()
            return p
        }
        func along(_ f: Double) -> CGPoint { CGPoint(x: tip.x + (butt.x - tip.x) * f, y: tip.y + (butt.y - tip.y) * f) }
        let shadow = CGPoint(x: 2, y: 3)
        w.fill(taper(tip + shadow, 2.6, butt + shadow, 5.4), with: .color(.black.opacity(0.25)))
        w.fill(taper(tip, 2.6, along(0.62), 4.0), with: .color(PoolColors.maple))
        w.fill(taper(along(0.62), 4.0, butt, 5.4), with: .color(PoolColors.woodDark))
        w.fill(taper(along(0.62), 4.1, along(0.66), 4.3), with: .color(PoolColors.diamond))
        w.fill(taper(tip, 2.7, along(0.03), 2.9), with: .color(PoolColors.chalk))

        // The power ring around the ball.
        w.stroke(w.circle(centre, ringR), with: .color(.black.opacity(0.28)), lineWidth: 6)
        w.stroke(w.circle(centre, ringR), with: .color(.white.opacity(0.4)), lineWidth: 4)
        if power > 0.01 {
            var arc = Path()
            let steps = max(2, Int(power * 60))
            for i in 0...steps {
                let a = -Double.pi / 2 + Double(i) / Double(steps) * power * 2 * .pi
                let pt = CGPoint(x: centre.x + cos(a) * ringR, y: centre.y + sin(a) * ringR)
                if i == 0 { arc.move(to: pt) } else { arc.addLine(to: pt) }
            }
            w.stroke(arc, with: .color(tint), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
    }

    /// A trail of dots at fixed distances along a route, fading away along its length.
    private static func drawDots(_ w: inout GraphicsContext, _ points: [Vec], startAt: Double, color: Color, fade: Bool) {
        guard points.count > 1 else { return }
        var total = 0.0
        for i in 1..<points.count { total += points[i].distance(to: points[i - 1]) }
        var nextDot = startAt
        let gap = 13.0
        var travelled = 0.0
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let seg = a.distance(to: b)
            guard seg > 0 else { continue }
            while nextDot <= travelled + seg {
                let p = a + (b - a) * ((nextDot - travelled) / seg)
                let far = min(1, nextDot / 700)
                // Only the last dot fades in or out as the end of the route moves past it.
                let end = max(0, min(1, (total - nextDot + 4) / 8))
                let ease = end * end * (3 - 2 * end)
                w.fill(w.circle(p.cg, CGFloat(3.6 - 1.4 * far)), with: .color(color.opacity((1 - 0.6 * (fade ? far : 0)) * ease)))
                nextDot += gap
            }
            travelled += seg
        }
    }
}

private extension CGPoint {
    func scaled(_ k: Double) -> CGPoint { CGPoint(x: x * k, y: y * k) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
}
