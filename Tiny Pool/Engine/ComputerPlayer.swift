//
//  ComputerPlayer.swift
//  Tiny Pool
//
//  Three levels of computer opponent. They all work out real shots (a ghost-ball aim at a pocket),
//  and differ in how well they pick and how steady their hand is. The expert also tries its best
//  candidates on a copy of the table, using the very same physics, and keeps the one that pays.
//

import Foundation

nonisolated enum AILevel: Int, CaseIterable, Codable, Sendable, Identifiable {
    case beginner, intermediate, expert

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .beginner: "Beginner"
        case .intermediate: "Intermediate"
        case .expert: "Expert"
        }
    }

    var blurb: String {
        switch self {
        case .beginner: "Wild aim, wild power. A good first win."
        case .intermediate: "Picks sensible shots, misses now and then."
        case .expert: "Tests its shots first. Rarely misses."
        }
    }

    /// Aim wobble (standard deviation, in degrees) and power wobble (fraction).
    fileprivate var aimError: Double {
        switch self { case .beginner: 5.5; case .intermediate: 1.6; case .expert: 0.25 }
    }
    fileprivate var powerError: Double {
        switch self { case .beginner: 0.30; case .intermediate: 0.10; case .expert: 0.03 }
    }
}

/// What the computer needs to know about the rules to pick a legal shot.
nonisolated struct AIContext: Sendable {
    var rules: Rules
    /// The computer's own group (8-ball).
    var group: BallGroup?
    var isBreak: Bool
}

/// Where to put the cue ball (with ball in hand), and the shot to play from there.
nonisolated struct AIPlan: Sendable {
    var spot: Vec?
    var velocity: Vec
}

nonisolated enum ComputerPlayer {
    struct Candidate {
        var velocity: Vec
        var score: Double
    }

    static func plan(table sim: Simulation, cue: Int, level: AILevel, context: AIContext, inHand: Bool) -> AIPlan {
        var table = sim
        var spot: Vec?
        if inHand {
            let s = chooseSpot(table: sim, cue: cue, level: level, context: context)
            table.balls[cue].pos = s
            table.balls[cue].vel = .zero
            spot = s
        }
        return AIPlan(spot: spot, velocity: chooseShot(table: table, cue: cue, level: level, context: context))
    }

    private static func remaining(_ sim: Simulation) -> Set<Int> {
        Set(sim.balls.filter { $0.onTable }.compactMap { $0.number })
    }

    /// With ball in hand: a spot with a good shot from it. Beginners just drop it somewhere.
    private static func chooseSpot(table sim: Simulation, cue: Int, level: AILevel, context: AIContext) -> Vec {
        var spots: [Vec] = []
        var x = 90.0
        while x < Table.width - 60 {
            var y = 60.0
            while y < Table.height - 40 {
                let p = Vec(x, y)
                if sim.isFree(p, ignoring: cue, margin: 4) { spots.append(p) }
                y += 60
            }
            x += 70
        }
        guard !spots.isEmpty else { return sim.freeSpot(near: Table.headSpot, ignoring: cue) }
        if level == .beginner { return spots.randomElement()! }
        var scored: [(Vec, Double)] = []
        for p in spots {
            var t = sim
            t.balls[cue].pos = p
            let best = candidates(in: t, cue: cue, requireClear: true, allowed: allowed(context, t)).map(\.score).max() ?? -9
            scored.append((p, best))
        }
        scored.sort { $0.1 > $1.1 }
        let pool = level == .expert ? 1 : 3
        return scored.prefix(pool).randomElement()!.0
    }

    private static func allowed(_ context: AIContext, _ sim: Simulation) -> Set<Int> {
        Judge.allowedTargets(context.rules, group: context.group, remaining: remaining(sim))
    }

    /// The shot to play for the cue ball at `cue`: a velocity.
    static func chooseShot(table sim: Simulation, cue: Int, level: AILevel, context: AIContext) -> Vec {
        let allowed = self.allowed(context, sim)
        var candidates = self.candidates(in: sim, cue: cue, requireClear: level != .beginner, allowed: allowed)
        candidates.sort { $0.score > $1.score }

        var pick: Vec
        switch level {
        case .beginner:
            // Anything at all, even a shot with a ball in the way.
            if let c = candidates.randomElement(), Double.random(in: 0...1) < 0.8 {
                pick = c.velocity
            } else {
                pick = fallback(in: sim, cue: cue, hard: true, allowed: allowed)
            }
        case .intermediate:
            if let c = candidates.prefix(3).randomElement() {
                pick = c.velocity
            } else {
                pick = fallback(in: sim, cue: cue, hard: false, allowed: allowed)
            }
        case .expert:
            var best: (Vec, Double)?
            for c in candidates.prefix(14) {
                let value = trial(c.velocity, in: sim, cue: cue, context: context)
                if best == nil || value > best!.1 { best = (c.velocity, value) }
                if value >= 100 { break }
            }
            if let best, best.1 > 0 {
                pick = best.0
            } else {
                pick = fallback(in: sim, cue: cue, hard: false, allowed: allowed)
            }
        }
        return wobble(pick, level: level)
    }

    /// Hand shake: turns the shot a little and over- or under-hits it.
    private static func wobble(_ v: Vec, level: AILevel) -> Vec {
        let angle = gaussian() * level.aimError * .pi / 180
        let power = 1 + gaussian() * level.powerError
        let speed = min(Shot.maxSpeed, max(Shot.minSpeed, v.length * max(0.4, power)))
        return v.normalized.rotated(by: angle) * speed
    }

    private static func gaussian() -> Double {
        let u1 = Double.random(in: 0.0001...1), u2 = Double.random(in: 0...1)
        return max(-2.5, min(2.5, (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)))
    }

    /// No pocketing shot: just hit the nearest ball.
    private static func fallback(in sim: Simulation, cue: Int, hard: Bool, allowed: Set<Int>) -> Vec {
        let from = sim.balls[cue].pos
        let targets = sim.balls.indices.filter { sim.balls[$0].onTable && allowed.contains(sim.balls[$0].number ?? -1) }
        guard let t = targets.min(by: { from.distance(to: sim.balls[$0].pos) < from.distance(to: sim.balls[$1].pos) }) else {
            return Vec(300, 0)
        }
        let d = sim.balls[t].pos - from
        let speed = hard ? Shot.maxSpeed * 0.7 : Simulation.speed(forTravel: d.length + 160)
        return d.normalized * min(Shot.maxSpeed, max(Shot.minSpeed, speed))
    }

    /// Every ball and pocket pair that makes a shot, best first once sorted.
    static func candidates(in sim: Simulation, cue: Int, requireClear: Bool, allowed: Set<Int>) -> [Candidate] {
        let r = Table.ballRadius
        let from = sim.balls[cue].pos
        var out: [Candidate] = []
        for (b, ball) in sim.balls.enumerated() where ball.onTable && allowed.contains(ball.number ?? -1) {
            for (k, pocket) in Table.pockets.enumerated() {
                let toPocket = pocket - ball.pos
                let pocketDist = toPocket.length
                let dir = toPocket.normalized
                // Where the cue ball has to be to send the object ball that way.
                let ghost = ball.pos - dir * (r * 2)
                let aim = ghost - from
                let aimDist = aim.length
                guard aimDist > 1 else { continue }
                // Cut angle: 0 is a straight shot.
                let cosCut = aim.normalized.dot(dir)
                guard cosCut > 0.28 else { continue }
                // A ball hugging the cushion beside the pocket mouth cannot be played into it.
                if requireClear {
                    if !pathClear(sim, from: from, to: ghost, ignoring: [cue, b], width: r * 2) { continue }
                    if !pathClear(sim, from: ball.pos, to: pocket, ignoring: [cue, b], width: r * 2) { continue }
                    // The ghost ball spot must be on the table.
                    if !(ghost.x > r && ghost.x < Table.width - r && ghost.y > r && ghost.y < Table.height - r) { continue }
                }
                let total = aimDist + pocketDist
                // Stop-and-roll distance, plus enough over for the cut and the pocket jaws.
                let need = total * (1 + 0.5 * (1 - cosCut)) + 140
                let speed = min(Shot.maxSpeed, max(Shot.minSpeed, Simulation.speed(forTravel: need)))
                let value = Double(Table.value(of: ball.number ?? 1))
                let score = cosCut * 3 - total / 900 + value * 0.4 - (k == 1 || k == 4 ? 0.15 : 0)
                out.append(Candidate(velocity: aim.normalized * speed, score: score))
            }
        }
        return out
    }

    /// Whether a ball of width `width` can travel the segment without touching another ball.
    private static func pathClear(_ sim: Simulation, from: Vec, to: Vec, ignoring: [Int], width: Double) -> Bool {
        for (i, b) in sim.balls.enumerated() where b.onTable && !ignoring.contains(i) {
            if Vec.closest(from, to, to: b.pos).distance(to: b.pos) < width - 0.5 { return false }
        }
        return true
    }

    /// Plays a shot out on a copy of the table. Positive is good: what dropped, less penalties
    /// for fouls and for losing the cue ball; winning is worth the most.
    private static func trial(_ velocity: Vec, in sim: Simulation, cue: Int, context: AIContext) -> Double {
        var copy = sim
        copy.launch(cue, velocity: velocity)
        var events: [SimEvent] = []
        var report = ShotReport()
        var steps = 0
        while copy.isMoving, steps < Int(10 / Simulation.dt) {
            copy.step(events: &events)
            for e in events { report.record(e, cue: cue, balls: copy.balls) }
            events.removeAll(keepingCapacity: true)
            steps += 1
        }
        switch context.rules {
        case .potPoints, .timed:
            var score = 0.0
            for n in report.potted { score += Double(Table.value(of: n)) }
            if report.cuePotted { score -= 4 }
            return score
        case .eightBall, .nineBall:
            let before = remaining(sim)
            let verdict = context.rules == .eightBall
                ? Judge.eightBall(report, group: context.group, remaining: before, isBreak: context.isBreak)
                : Judge.nineBall(report, remaining: before)
            if verdict.shooterWins { return 100 }
            if verdict.shooterLoses { return -100 }
            if verdict.foul != nil { return -10 }
            return Double(report.potted.filter { $0 != 8 }.count) * 3 + (verdict.keepTurn ? 2 : 0)
        }
    }
}
