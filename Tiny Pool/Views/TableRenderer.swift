//
//  TableRenderer.swift
//  Tiny Pool
//
//  Draws the room, the table, the balls and the aiming overlay with flat shapes.
//

import SwiftUI

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

        // Balls on their way down a pocket.
        for sink in game.sinks {
            let k = min(1, (time - sink.start) / Sink.duration)
            let e = k * k
            let pos = sink.from + (sink.pocket - sink.from) * e
            drawBall(&w, &ctx, t, kind: sink.kind, at: pos, scale: 1 - 0.5 * e, opacity: 1 - 0.7 * e, ring: ringColor(game, sink.kind))
        }

        // Rings that show where each cue ball can be picked up (versus).
        if game.isVersus {
            for p in 0..<game.mode.playerCount where game.canAim(p) && game.aims[p] == nil {
                guard let cue = game.cueBall(of: p) else { continue }
                let pulse = 0.5 + 0.5 * sin(time * 4 + Double(p))
                let r = CGFloat(Table.ballRadius) + 7 + 2 * CGFloat(pulse)
                w.stroke(w.circle(cue.pos.cg, r), with: .color(PoolColors.players[p].opacity(0.55 + 0.3 * pulse)),
                         style: StrokeStyle(lineWidth: 3, dash: [5, 5]))
            }
        }

        for (i, b) in balls.enumerated() where b.onTable {
            var scale = 1.0
            if let p = b.player, let start = game.appeared[p] {
                // Pops in with a little overshoot.
                let k = max(0, min(1, (time - start) / 0.4))
                let c1 = 1.70158, c3 = c1 + 1
                scale = max(0.05, 1 + c3 * pow(k - 1, 3) + c1 * pow(k - 1, 2))
            }
            _ = i
            drawBall(&w, &ctx, t, kind: b.kind, at: b.pos, scale: scale, opacity: 1, ring: ringColor(game, b.kind))
        }

        // Aim: guide first, then the cue on top.
        for (p, pull) in game.aims.sorted(by: { $0.key < $1.key }) {
            guard let cue = game.cueBall(of: p) else { continue }
            drawAim(&w, game: game, player: p, from: cue.pos, pull: pull)
        }
    }

    private static func ringColor(_ game: PoolGame, _ kind: BallKind) -> Color {
        guard case .cue(let p) = kind else { return .clear }
        // In a game against the computer the ring says whose turn it is.
        return PoolColors.players[game.isComputerGame ? game.turn : p]
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

    private static func drawBall(_ w: inout GraphicsContext, _ screen: inout GraphicsContext, _ t: ViewTransform,
                                 kind: BallKind, at p: Vec, scale: Double, opacity: Double, ring: Color) {
        guard scale > 0.01 else { return }
        let c = p.cg
        let r = CGFloat(Table.ballRadius * scale)
        var b = w
        b.opacity = opacity

        // The shadow stays on the cloth.
        b.fill(b.circle(CGPoint(x: c.x + 1.8, y: c.y + 2.8), r), with: .color(.black.opacity(0.3)))

        switch kind {
        case .cue:
            b.fill(b.circle(c, r), with: .color(.white))
            b.stroke(b.circle(c, r * 0.58), with: .color(ring), lineWidth: r * 0.3)
        case .object(let number):
            let color = PoolColors.ball(number)
            b.fill(b.circle(c, r), with: .color(number > 8 ? .white : color))
            if number > 8 {
                var band = b
                band.clip(to: b.circle(c, r))
                band.fill(Path(CGRect(x: c.x - r, y: c.y - r * 0.56, width: r * 2, height: r * 1.12)), with: .color(color))
            }
            b.fill(b.circle(c, r * 0.52), with: .color(.white))
        }
        b.stroke(b.circle(c, r), with: .color(.black.opacity(0.25)), lineWidth: 1)
        b.fill(b.circle(CGPoint(x: c.x - r * 0.34, y: c.y - r * 0.34), r * 0.25), with: .color(.white.opacity(0.7)))

        // The number is drawn the right way up whatever way the table is turned.
        if case .object(let number) = kind, r * t.scale >= 6 {
            var s = screen
            s.opacity = opacity
            let at = t.toScreen(p)
            s.draw(Text("\(number)").font(.system(size: r * t.scale * 0.72, weight: .heavy, design: .rounded)).foregroundStyle(.black), at: at)
        }
    }

    // MARK: - Aiming

    private static func drawAim(_ w: inout GraphicsContext, game: PoolGame, player: Int, from ball: Vec, pull: Vec) {
        let power = Shot.power(forPull: pull.length)
        let dir = pull.normalized
        let centre = ball.cg
        // Yellow when soft, shading to orange-red as the shot gets harder.
        let tint = Color(hue: 0.005 + 0.15 * (1 - power), saturation: 0.88, brightness: 1.0)
        let ringR: CGFloat = 19

        // The guide: where the cue ball goes, where it meets a ball, and where they go next.
        if let preview = game.previews[player] {
            drawDots(&w, preview.cue, startAt: Double(ringR) + 3, color: tint, fade: true)
            if let ghost = preview.ghost {
                w.stroke(w.circle(ghost.cg, CGFloat(Table.ballRadius)), with: .color(.white.opacity(0.85)),
                         style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                drawDots(&w, preview.target, startAt: Double(Table.ballRadius) + 2, color: .white, fade: true)
                drawDots(&w, preview.after, startAt: Double(Table.ballRadius) + 2, color: tint.opacity(0.7), fade: true)
            }
        }

        // The cue, behind the ball, drawn back further the harder the shot.
        let tip = centre - CGPoint(x: dir.x, y: dir.y).scaled(Double(ringR) + 2 + 26 * power)
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
        let gap = 11.0
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
                w.fill(w.circle(p.cg, CGFloat(3.0 - 1.2 * far)), with: .color(color.opacity((1 - 0.6 * (fade ? far : 0)) * ease)))
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
