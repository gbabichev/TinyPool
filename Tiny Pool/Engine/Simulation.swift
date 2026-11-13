//
//  Simulation.swift
//  Tiny Pool
//
//  The ball physics. Deterministic and fixed-step, so the game, the aiming guide and the
//  computer players all agree on what a shot does.
//

import Foundation

nonisolated enum BallKind: Hashable, Sendable {
    /// A cue ball belongs to one player (0...3).
    case cue(player: Int)
    case object(number: Int)
}

nonisolated struct Ball: Sendable {
    var kind: BallKind
    var pos: Vec
    var vel = Vec.zero
    var onTable = true
    /// How fast it was going when a pocket took it (for the drop animation).
    var sunkVel = Vec.zero
    /// The player who last sent this ball on its way (object balls only). Whoever's cue ball
    /// reaches it, directly or through other balls, gets the credit when it drops.
    var credit: Int?

    var isCue: Bool { if case .cue = kind { true } else { false } }
    var number: Int? { if case .object(let n) = kind { n } else { nil } }
    var player: Int? { if case .cue(let p) = kind { p } else { nil } }
    var speed: Double { vel.length }
}

nonisolated enum SimEvent: Sendable {
    /// Two balls met (`speed` is how fast they came together).
    case clack(a: Int, b: Int, speed: Double, at: Vec)
    case cushion(ball: Int, speed: Double)
    case pocketed(ball: Int, pocket: Int)
}

nonisolated struct Simulation: Sendable {
    static let dt = 1.0 / 240.0

    /// Rolling resistance: a steady drag plus one that grows with speed, so a hard shot rolls
    /// a long way and a soft one stops soon.
    static let drag = 105.0
    static let air = 0.5
    static let stopSpeed = 9.0
    static let cushionBounce = 0.78
    static let ballBounce = 0.96

    var balls: [Ball]

    var isMoving: Bool { balls.contains { $0.onTable && $0.vel != .zero } }

    func isMoving(_ i: Int) -> Bool { balls[i].onTable && balls[i].vel != .zero }

    /// How far a ball sent off at `speed` travels on its own before it stops.
    static func travel(forSpeed v: Double) -> Double {
        v / air - (drag / (air * air)) * log(1 + air * v / drag)
    }

    /// The speed that makes a ball roll `distance` and stop.
    static func speed(forTravel distance: Double) -> Double {
        var lo = 0.0, hi = 4000.0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if travel(forSpeed: mid) < distance { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    mutating func launch(_ index: Int, velocity: Vec) {
        balls[index].vel = velocity
    }

    /// One fixed step.
    mutating func step(events: inout [SimEvent]) {
        let dt = Self.dt
        let r = Table.ballRadius
        let w = Table.width, h = Table.height

        for i in balls.indices where balls[i].onTable {
            guard balls[i].vel != .zero else { continue }
            balls[i].pos += balls[i].vel * dt
            let s = balls[i].vel.length
            let ns = s - (Self.drag + Self.air * s) * dt
            balls[i].vel = ns <= Self.stopSpeed ? .zero : balls[i].vel * (ns / s)
        }

        // Cushions.
        for i in balls.indices where balls[i].onTable {
            var p = balls[i].pos, v = balls[i].vel
            let e = Self.cushionBounce
            let sideLo = w / 2 - Table.sideGap, sideHi = w / 2 + Table.sideGap
            let gap = Table.cornerGap
            // Left and right (clear of the corner pockets).
            if p.y > gap, p.y < h - gap {
                if p.x < r { p.x = r; if v.x < 0 { events.append(.cushion(ball: i, speed: -v.x)); v.x = -v.x * e; v.y *= 0.985 } }
                if p.x > w - r { p.x = w - r; if v.x > 0 { events.append(.cushion(ball: i, speed: v.x)); v.x = -v.x * e; v.y *= 0.985 } }
            }
            // Top and bottom (clear of the corner and side pockets).
            let clearOfPockets = (p.x > gap && p.x < sideLo) || (p.x > sideHi && p.x < w - gap)
            if clearOfPockets {
                if p.y < r { p.y = r; if v.y < 0 { events.append(.cushion(ball: i, speed: -v.y)); v.y = -v.y * e; v.x *= 0.985 } }
                if p.y > h - r { p.y = h - r; if v.y > 0 { events.append(.cushion(ball: i, speed: v.y)); v.y = -v.y * e; v.x *= 0.985 } }
            }
            balls[i].pos = p
            balls[i].vel = v.length < Self.stopSpeed ? .zero : v
        }

        // Balls against balls.
        let n = balls.count
        for i in 0..<n where balls[i].onTable {
            for j in (i + 1)..<n where balls[j].onTable {
                let d = balls[j].pos - balls[i].pos
                let dist2 = d.dot(d)
                let minDist = r * 2
                guard dist2 < minDist * minDist else { continue }
                let dist = max(dist2.squareRoot(), 1e-6)
                let nrm = d / dist
                // Pull them apart.
                let push = (minDist - dist) / 2
                balls[i].pos -= nrm * push
                balls[j].pos += nrm * push
                let rel = (balls[i].vel - balls[j].vel).dot(nrm)
                guard rel > 0 else { continue }
                let speedI = balls[i].speed, speedJ = balls[j].speed
                // Credit moves from the faster ball to the slower one.
                if speedI >= speedJ { passCredit(from: i, to: j) } else { passCredit(from: j, to: i) }
                let impulse = (1 + Self.ballBounce) * rel / 2
                balls[i].vel -= nrm * impulse
                balls[j].vel += nrm * impulse
                events.append(.clack(a: i, b: j, speed: rel, at: balls[i].pos + nrm * r))
            }
        }

        // Pockets.
        for i in balls.indices where balls[i].onTable {
            let p = balls[i].pos
            var hit: Int?
            for (k, c) in Table.pockets.enumerated() where p.distance(to: c) < Table.pocketRadius(k) { hit = k; break }
            if hit == nil, p.x < -r || p.x > w + r || p.y < -r || p.y > h + r {
                // Anything that got out past the cushions drops into the nearest pocket.
                hit = Table.pockets.indices.min { p.distance(to: Table.pockets[$0]) < p.distance(to: Table.pockets[$1]) }
            }
            if let hit {
                balls[i].onTable = false
                balls[i].sunkVel = balls[i].vel
                balls[i].vel = .zero
                events.append(.pocketed(ball: i, pocket: hit))
            }
        }
    }

    private mutating func passCredit(from a: Int, to b: Int) {
        guard balls[b].number != nil else { return }
        if let p = balls[a].player { balls[b].credit = p } else if let c = balls[a].credit { balls[b].credit = c }
    }

    /// Runs until everything stops (or `maxSeconds`).
    mutating func settle(maxSeconds: Double = 12, events: inout [SimEvent]) {
        var steps = 0
        let limit = Int(maxSeconds / Self.dt)
        while isMoving, steps < limit { step(events: &events); steps += 1 }
    }

    /// Whether `spot` is free of balls (with some room to spare).
    func isFree(_ spot: Vec, ignoring: Int? = nil, margin: Double = 2) -> Bool {
        let r = Table.ballRadius
        guard spot.x >= r, spot.x <= Table.width - r, spot.y >= r, spot.y <= Table.height - r else { return false }
        for (i, b) in balls.enumerated() where b.onTable && i != ignoring {
            if b.pos.distance(to: spot) < r * 2 + margin { return false }
        }
        return true
    }

    /// The nearest free spot to `target`, searched in rings outwards.
    func freeSpot(near target: Vec, ignoring: Int? = nil) -> Vec {
        if isFree(target, ignoring: ignoring) { return target }
        for ring in 1...60 {
            let rad = Double(ring) * 8
            let count = max(8, ring * 6)
            for k in 0..<count {
                let a = Double(k) / Double(count) * 2 * .pi
                let p = Vec(target.x + cos(a) * rad, target.y + sin(a) * rad)
                if isFree(p, ignoring: ignoring) { return p }
            }
        }
        return target
    }
}
