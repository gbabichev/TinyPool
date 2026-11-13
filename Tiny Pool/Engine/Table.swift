//
//  Table.swift
//  Tiny Pool
//
//  The table: a fixed 2 : 1 world (like Tiny Putt's courses, the screen just scales it).
//  Ball centres live in 0...width, 0...height shrunk by the ball radius; the cushions are the
//  edges of that rectangle, and six pockets are cut into it.
//

import Foundation

nonisolated enum Table {
    static let width = 1000.0
    static let height = 500.0
    static let ballRadius = 11.0

    /// How far the wooden rail reaches out past the cushions (drawing only).
    static let rail = 40.0

    static let cornerPocket = 27.0
    static let sidePocket = 25.0

    /// Pocket centres: the corners sit a little outside the felt, the side pockets on the rail.
    static let pockets: [Vec] = [
        Vec(-5, -5), Vec(width / 2, -9), Vec(width + 5, -5),
        Vec(-5, height + 5), Vec(width / 2, height + 9), Vec(width + 5, height + 5),
    ]

    static func pocketRadius(_ i: Int) -> Double { (i == 1 || i == 4) ? sidePocket : cornerPocket }

    /// Cushions stop short of the pockets, so a ball can run into the mouth.
    static let cornerGap = 40.0
    static let sideGap = 34.0

    static let headSpot = Vec(250, height / 2)
    static let footSpot = Vec(700, height / 2)

    /// What a ball is worth. The black eight is the big one.
    static func value(of number: Int) -> Int { number == 8 ? 3 : 1 }
    static let totalValue = (1...15).reduce(0) { $0 + value(of: $1) }

    /// The colour order of a standard rack, apex first: the eight in the middle of the third row,
    /// a stripe and a solid in the back corners.
    static let rackOrder = [1, 9, 2, 10, 8, 3, 11, 4, 12, 5, 13, 6, 14, 15, 7]

    /// A triangle of the fifteen balls with its apex on the foot spot.
    static func rack() -> [(number: Int, pos: Vec)] {
        let d = ballRadius * 2 + 0.15
        let dx = d * 0.8660254
        var out: [(Int, Vec)] = []
        var k = 0
        for row in 0..<5 {
            for j in 0...row {
                let y = height / 2 + (Double(j) - Double(row) / 2) * d
                out.append((rackOrder[k], Vec(footSpot.x + Double(row) * dx, y)))
                k += 1
            }
        }
        return out
    }

    /// Cue-ball start spots for 1...4 players, along the head string.
    static func startSpots(count: Int) -> [Vec] {
        (0..<count).map { i in
            Vec(headSpot.x - (count > 2 ? 30 : 0) * (i % 2 == 0 ? 1 : 0), height * Double(i + 1) / Double(count + 1))
        }
    }
}

/// How a pull on the screen becomes a shot. Same idea as Tiny Putt: measured in world units, so
/// a shot feels the same on every screen size.
nonisolated enum Shot {
    static let maxPull: Double = 170
    static let minPull: Double = 14
    static let minSpeed: Double = 90
    static let maxSpeed: Double = 1900

    /// 0...1
    static func power(forPull length: Double) -> Double {
        max(0, min(1, (length - minPull) / (maxPull - minPull)))
    }

    static func speed(forPull length: Double) -> Double {
        // A little curve, so the soft end has more room.
        let p = power(forPull: length)
        return minSpeed + (maxSpeed - minSpeed) * (0.25 * p + 0.75 * p * p)
    }

    /// The pull that makes `speed`. The reverse of `speed(forPull:)`.
    static func pull(forSpeed speed: Double) -> Double {
        let t = max(0, min(1, (speed - minSpeed) / (maxSpeed - minSpeed)))
        // Solve 0.75 p² + 0.25 p = t.
        let p = (-0.25 + (0.0625 + 3 * t).squareRoot()) / 1.5
        return minPull + p * (maxPull - minPull)
    }
}
