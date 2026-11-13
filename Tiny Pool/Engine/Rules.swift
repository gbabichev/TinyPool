//
//  Rules.swift
//  Tiny Pool
//
//  The four rule sets, and the referee. The referee is plain data in, verdict out, so the game
//  and the computer players judge a shot the very same way.
//

import Foundation

nonisolated enum Rules: Int, CaseIterable, Identifiable, Sendable {
    case potPoints, eightBall, nineBall, timed

    var id: Int { rawValue }

    static let timedSeconds = 60

    var title: String {
        switch self {
        case .potPoints: "Pot Points"
        case .eightBall: "Classic 8-Ball"
        case .nineBall: "9-Ball"
        case .timed: "Timed"
        }
    }

    var tagline: String {
        switch self {
        case .potPoints: "Any ball goes. Most points wins."
        case .eightBall: "Solids or stripes, then the black 8."
        case .nineBall: "Lowest ball first. Pot the 9 to win."
        case .timed: "60 seconds. Pot as many as you can."
        }
    }

    /// Whether points are counted as balls drop.
    var scoresPoints: Bool { self == .potPoints || self == .timed }

    /// The numbers on the table at the start.
    var ballNumbers: [Int] { self == .nineBall ? Array(1...9) : Array(1...15) }
}

nonisolated enum BallGroup: Sendable, Equatable {
    case solids, stripes

    var other: BallGroup { self == .solids ? .stripes : .solids }
    func contains(_ n: Int) -> Bool { self == .solids ? (1...7).contains(n) : (9...15).contains(n) }
    var name: String { self == .solids ? "Solids" : "Stripes" }
}

/// What happened in one shot.
nonisolated struct ShotReport: Sendable {
    /// The number of the first object ball the cue ball touched.
    var firstContact: Int?
    /// Numbers potted, in order.
    var potted: [Int] = []
    var cuePotted = false

    mutating func record(_ event: SimEvent, cue: Int, balls: [Ball]) {
        switch event {
        case .clack(let a, let b, _, _):
            if firstContact == nil, a == cue || b == cue {
                firstContact = balls[a == cue ? b : a].number
            }
        case .pocketed(let i, _):
            if i == cue { cuePotted = true } else if let n = balls[i].number { potted.append(n) }
        case .cushion:
            break
        }
    }
}

/// The referee's ruling on a shot.
nonisolated struct Verdict: Sendable {
    var foul: String?
    var keepTurn = false
    var shooterWins = false
    var shooterLoses = false
    var loseReason: String?
    /// The group the shooter now owns (8-ball, when the table was open).
    var assign: BallGroup?
    /// Balls to put back on the table.
    var respot: [Int] = []
}

nonisolated enum Judge {
    /// `remaining` is every number that was on the table before the shot.
    static func eightBall(_ r: ShotReport, group: BallGroup?, remaining: Set<Int>, isBreak: Bool) -> Verdict {
        var v = Verdict()
        let mine = group.map { g in remaining.filter { g.contains($0) } } ?? []
        let onEight = group != nil && mine.isEmpty

        if r.cuePotted {
            v.foul = "Scratch"
        } else if let first = r.firstContact {
            if onEight {
                if first != 8 { v.foul = "Aim for the 8 now" }
            } else if first == 8 {
                v.foul = "Hit the 8 too soon"
            } else if let g = group, !g.contains(first) {
                v.foul = "Hit the wrong group"
            }
        } else {
            v.foul = "No ball hit"
        }

        if r.potted.contains(8) {
            if isBreak {
                v.respot = [8]              // the eight on the break goes back up
            } else if v.foul == nil, onEight {
                v.shooterWins = true
                return v
            } else {
                v.shooterLoses = true
                v.loseReason = v.foul != nil ? "potted the 8 on a foul" : "potted the 8 too soon"
                return v
            }
        }

        var g = group
        if g == nil, v.foul == nil, let first = r.potted.first(where: { $0 != 8 }) {
            g = first < 8 ? .solids : .stripes
            v.assign = g
        }
        if v.foul == nil, let g, r.potted.contains(where: { g.contains($0) }) { v.keepTurn = true }
        return v
    }

    static func nineBall(_ r: ShotReport, remaining: Set<Int>) -> Verdict {
        var v = Verdict()
        let lowest = remaining.min() ?? 9
        if r.cuePotted {
            v.foul = "Scratch"
        } else if let first = r.firstContact {
            if first != lowest { v.foul = "Hit the \(lowest) first" }
        } else {
            v.foul = "No ball hit"
        }
        if r.potted.contains(9) {
            if v.foul == nil { v.shooterWins = true; return v }
            v.respot = [9]
        }
        if v.foul == nil, !r.potted.isEmpty { v.keepTurn = true }
        return v
    }

    /// The balls a player may legally hit first.
    static func allowedTargets(_ rules: Rules, group: BallGroup?, remaining: Set<Int>) -> Set<Int> {
        switch rules {
        case .potPoints, .timed:
            return remaining
        case .nineBall:
            return remaining.min().map { [$0] } ?? []
        case .eightBall:
            guard let group else { return remaining.subtracting([8]) }
            let mine = remaining.filter { group.contains($0) }
            return mine.isEmpty ? [8] : Set(mine)
        }
    }
}
