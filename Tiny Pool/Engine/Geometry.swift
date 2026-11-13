//
//  Geometry.swift
//  Tiny Pool
//
//  Plain 2D vectors for the engine. Nothing here knows about SwiftUI.
//

import Foundation
import CoreGraphics

nonisolated struct Vec: Hashable, Sendable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }

    static let zero = Vec(0, 0)

    static func + (a: Vec, b: Vec) -> Vec { Vec(a.x + b.x, a.y + b.y) }
    static func - (a: Vec, b: Vec) -> Vec { Vec(a.x - b.x, a.y - b.y) }
    static func * (a: Vec, k: Double) -> Vec { Vec(a.x * k, a.y * k) }
    static func / (a: Vec, k: Double) -> Vec { Vec(a.x / k, a.y / k) }
    static prefix func - (a: Vec) -> Vec { Vec(-a.x, -a.y) }
    static func += (a: inout Vec, b: Vec) { a = a + b }
    static func -= (a: inout Vec, b: Vec) { a = a - b }

    var length: Double { (x * x + y * y).squareRoot() }
    var normalized: Vec { let l = length; return l > 1e-12 ? self / l : .zero }
    var cg: CGPoint { CGPoint(x: x, y: y) }

    func dot(_ o: Vec) -> Double { x * o.x + y * o.y }
    func distance(to o: Vec) -> Double { (self - o).length }

    /// Turned by `angle` radians.
    func rotated(by angle: Double) -> Vec {
        let c = cos(angle), s = sin(angle)
        return Vec(x * c - y * s, x * s + y * c)
    }

    /// The point on segment a-b nearest to p.
    static func closest(_ a: Vec, _ b: Vec, to p: Vec) -> Vec {
        let ab = b - a
        let l2 = ab.dot(ab)
        if l2 < 1e-12 { return a }
        let t = max(0, min(1, (p - a).dot(ab) / l2))
        return a + ab * t
    }
}
