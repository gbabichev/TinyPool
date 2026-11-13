//
//  ShotPreview.swift
//  Tiny Pool
//
//  The aim hint: the route the cue ball will really take (the same physics as the shot) until it
//  meets a ball, then where both go. Plain data, so it can be timed on its own.
//

import Foundation

nonisolated struct ShotPreview: Sendable {
    var cue: [Vec] = []
    var ghost: Vec?
    var target: [Vec] = []
    var after: [Vec] = []

    static func make(in sim: Simulation, cue ci: Int, pull: Vec) -> ShotPreview {
        var probe = sim
        let power = Shot.power(forPull: pull.length)
        probe.launch(ci, velocity: pull.normalized * Shot.speed(forPull: pull.length))
        var events: [SimEvent] = []
        events.reserveCapacity(8)
        var preview = ShotPreview()
        preview.cue = [probe.balls[ci].pos]
        let maxLength = 260 + 620 * power

        func record(_ list: inout [Vec], _ p: Vec) {
            if let last = list.last, p.distance(to: last) < 4 { return }
            list.append(p)
        }

        var length = 0.0
        var steps = 0
        var contact: (other: Int, at: Vec)?
        while steps < 240 * 5, length < maxLength, probe.balls[ci].onTable, probe.balls[ci].vel != .zero {
            let before = probe.balls[ci].pos
            probe.step(events: &events)
            steps += 1
            length += probe.balls[ci].pos.distance(to: before)
            record(&preview.cue, probe.balls[ci].pos)
            for e in events {
                if case .clack(let a, let b, _, _) = e, a == ci || b == ci { contact = (a == ci ? b : a, probe.balls[ci].pos) }
                if case .pocketed(let i, _) = e, i == ci { length = maxLength }
            }
            events.removeAll(keepingCapacity: true)
            if contact != nil { break }
        }
        guard let contact else { return preview }

        preview.ghost = contact.at
        preview.cue.append(contact.at)
        preview.target = [probe.balls[contact.other].pos]
        preview.after = [probe.balls[ci].pos]
        var travelledTarget = 0.0, travelledAfter = 0.0
        var s = 0
        // Half a second after the hit is plenty to show where the two balls head.
        while s < 120, travelledTarget < 140 || travelledAfter < 90 {
            let t0 = probe.balls[contact.other].pos, c0 = probe.balls[ci].pos
            probe.step(events: &events)
            s += 1
            events.removeAll(keepingCapacity: true)
            if probe.balls[contact.other].onTable, travelledTarget < 140 {
                travelledTarget += probe.balls[contact.other].pos.distance(to: t0)
                record(&preview.target, probe.balls[contact.other].pos)
            }
            if probe.balls[ci].onTable, travelledAfter < 90 {
                travelledAfter += probe.balls[ci].pos.distance(to: c0)
                record(&preview.after, probe.balls[ci].pos)
            }
            if s % 8 == 0, !probe.isMoving { break }
        }
        return preview
    }
}
