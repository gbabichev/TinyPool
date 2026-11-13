//
//  PoolGame.swift
//  Tiny Pool
//
//  The whole game: the table, the shot being aimed, and who is playing. One model drives all
//  three modes.
//
//  Scoring is the same everywhere and easy to follow: every ball you pot is a point, the black
//  eight is worth three, and losing your cue ball costs one. Clear the table and the highest
//  score wins.
//

import SwiftUI
import Observation
import simd

/// Maps the table onto the screen. The table (rail included) is scaled to fill the space left
/// under the scoreboard, and turned a quarter turn when that makes it bigger (a phone held
/// upright). The room around it just carries on past the edges.
struct ViewTransform {
    let scale: CGFloat
    let rotated: Bool
    private let focus = CGPoint(x: Table.width / 2, y: Table.height / 2)
    private let anchor: CGPoint

    init(view: CGSize, topReserve: CGFloat, bottomReserve: CGFloat) {
        let pad = 16.0
        let fw = CGFloat(Table.width + 2 * Table.rail + 2 * pad)
        let fh = CGFloat(Table.height + 2 * Table.rail + 2 * pad)
        let availH = max(40, view.height - topReserve - bottomReserve)
        let upright = max(0.001, min(view.width / fw, availH / fh))
        let turned = max(0.001, min(view.width / fh, availH / fw))
        rotated = turned > upright
        scale = rotated ? turned : upright
        anchor = CGPoint(x: view.width / 2, y: topReserve + availH / 2)
    }

    var affine: CGAffineTransform {
        // Turned, the rack end of the table points up and the cue end sits under your thumb.
        rotated
            ? CGAffineTransform(a: 0, b: -scale, c: scale, d: 0, tx: anchor.x - scale * focus.y, ty: anchor.y + scale * focus.x)
            : CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: anchor.x - scale * focus.x, ty: anchor.y - scale * focus.y)
    }

    func toWorld(_ p: CGPoint) -> Vec {
        let dx = (p.x - anchor.x) / scale, dy = (p.y - anchor.y) / scale
        return rotated ? Vec(Double(focus.x - dy), Double(focus.y + dx)) : Vec(Double(focus.x + dx), Double(focus.y + dy))
    }

    func toScreen(_ v: Vec) -> CGPoint { v.cg.applying(affine) }
}

/// What a shot is about to do: the cue ball's route to its first ball, then where the two go.
struct ShotPreview {
    var cue: [Vec] = []
    var ghost: Vec?
    var target: [Vec] = []
    var after: [Vec] = []
}

/// A ball on its way down a pocket. It keeps the speed it had, is pulled to the middle of the
/// hole, and shrinks and darkens as it drops.
struct Sink {
    var kind: BallKind
    var index: Int
    var pos: Vec
    var vel: Vec
    var pocket: Vec
    var pocketIndex: Int
    /// 0 at the rim, 1 at the bottom.
    var depth = 0.0
    static let seconds = 0.5
}

enum GameMode: Equatable {
    case practice
    case computer(AILevel)
    case versus(players: Int)

    var playerCount: Int {
        switch self {
        case .practice: 1
        case .computer: 2
        case .versus(let n): n
        }
    }
}

@MainActor
@Observable
final class PoolGame {
    enum Overlay: Equatable { case none, finished }

    // MARK: Observed (the menus and buttons show these)
    private(set) var mode: GameMode = .practice
    private(set) var scores: [Int] = [0]
    /// Whose turn it is (practice and computer games). Always 0 in a versus game: everyone plays at once.
    private(set) var turn = 0
    private(set) var shots = 0
    private(set) var ballsLeft = 15
    private(set) var overlay: Overlay = .none
    /// A short line over the table ("Scratch!", "+3").
    private(set) var banner: String?
    private(set) var newBest = false

    var isSoundOn: Bool {
        didSet { defaults.set(isSoundOn, forKey: Keys.sound); sounds.isEnabled = isSoundOn }
    }
    var isHapticsOn: Bool {
        didSet { defaults.set(isHapticsOn, forKey: Keys.haptics); haptics.isEnabled = isHapticsOn }
    }
    var showGuide: Bool {
        didSet { defaults.set(showGuide, forKey: Keys.guide) }
    }
    var felt: Felt {
        didSet { defaults.set(felt.rawValue, forKey: Keys.felt) }
    }
    var lastLevel: AILevel {
        didSet { defaults.set(lastLevel.rawValue, forKey: Keys.level) }
    }
    var lastVersusCount: Int {
        didSet { defaults.set(lastVersusCount, forKey: Keys.versus) }
    }

    // MARK: Simulation state (redrawn every frame by the canvas, so not observed)
    @ObservationIgnored private(set) var sim = Simulation(balls: [])
    @ObservationIgnored private(set) var animTime = 0.0
    @ObservationIgnored private(set) var aims: [Int: Vec] = [:]
    @ObservationIgnored private(set) var previews: [Int: ShotPreview] = [:]
    @ObservationIgnored private(set) var sinks: [Sink] = []
    /// How each ball is turned, so it visibly rolls.
    @ObservationIgnored private(set) var orient: [simd_quatd] = []
    @ObservationIgnored private var lastPos: [Vec] = []
    /// When each cue ball last (re)appeared, for its pop-in.
    @ObservationIgnored private(set) var appeared: [Int: Double] = [:]
    @ObservationIgnored var topReserve: CGFloat = 70
    @ObservationIgnored var bottomReserve: CGFloat = 8

    @ObservationIgnored private var cueIndex: [Int] = []
    @ObservationIgnored private var lastTick: Double?
    @ObservationIgnored private var accumulator = 0.0
    @ObservationIgnored private var touches: [AnyHashable: (player: Int, start: CGPoint, size: CGSize)] = [:]
    /// Every finger that is down, whether or not it picked up a cue ball.
    @ObservationIgnored private var fingers: Set<AnyHashable> = []
    /// A shot has been taken and the table has not come to rest yet (practice and computer games).
    @ObservationIgnored private var shotInFlight = false
    @ObservationIgnored private var pottedThisShot = 0
    @ObservationIgnored private var cueLostThisShot = false
    @ObservationIgnored private var respawnAt: [Int: Double] = [:]
    @ObservationIgnored private var finishAt: Double?
    @ObservationIgnored private var bannerUntil = 0.0
    @ObservationIgnored private var lastClack = -1.0
    @ObservationIgnored private var lastCushion = -1.0
    @ObservationIgnored private var generation = 0

    private enum AIState { case idle, thinking, aiming(start: Double, velocity: Vec) }
    @ObservationIgnored private var ai = AIState.idle
    @ObservationIgnored private var aiReadyAt = 0.0

    @ObservationIgnored private let sounds = SoundEngine()
    @ObservationIgnored private let haptics = Haptics()
    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Keys {
        static let sound = "soundOn", haptics = "hapticsOn", guide = "showGuide", felt = "felt"
        static let level = "lastLevel", versus = "lastVersus"
        static let bestPractice = "bestPractice"
    }

    init() {
        isSoundOn = defaults.object(forKey: Keys.sound) as? Bool ?? true
        isHapticsOn = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        showGuide = defaults.object(forKey: Keys.guide) as? Bool ?? true
        felt = Felt(rawValue: defaults.string(forKey: Keys.felt) ?? "") ?? .green
        lastLevel = AILevel(rawValue: defaults.integer(forKey: Keys.level)) ?? .beginner
        lastVersusCount = max(2, min(4, defaults.object(forKey: Keys.versus) as? Int ?? 2))
        sounds.isEnabled = isSoundOn
        haptics.isEnabled = isHapticsOn
        newGame(.practice)
    }

    // MARK: - Records

    var bestPractice: Int? {
        let v = defaults.integer(forKey: Keys.bestPractice)
        return v > 0 ? v : nil
    }

    func wins(against level: AILevel) -> Int { defaults.integer(forKey: "wins\(level.rawValue)") }

    // MARK: - Starting

    func newGame(_ mode: GameMode) {
        generation += 1
        self.mode = mode
        let players = mode.playerCount
        scores = Array(repeating: 0, count: players)
        turn = 0
        shots = 0
        overlay = .none
        banner = nil
        newBest = false
        aims = [:]; previews = [:]; sinks = []; appeared = [:]; touches = [:]; fingers = []
        respawnAt = [:]
        finishAt = nil
        shotInFlight = false
        pottedThisShot = 0
        cueLostThisShot = false
        ai = .idle
        aiReadyAt = animTime + 1.0
        accumulator = 0
        haptics.endAll()

        var balls: [Ball] = []
        var cues: [Int] = []
        if case .versus(let n) = mode {
            for (p, spot) in Table.startSpots(count: n).enumerated() {
                cues.append(balls.count)
                balls.append(Ball(kind: .cue(player: p), pos: spot))
            }
        } else {
            cues.append(0)
            balls.append(Ball(kind: .cue(player: 0), pos: Table.headSpot))
        }
        for (number, pos) in Table.rack() {
            // A hair of jitter, so no two breaks play the same.
            let jitter = Vec(Double.random(in: -0.25...0.25), Double.random(in: -0.25...0.25))
            balls.append(Ball(kind: .object(number: number), pos: pos + jitter))
        }
        sim = Simulation(balls: balls)
        orient = Array(repeating: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1), count: balls.count)
        lastPos = balls.map(\.pos)
        cueIndex = cues
        ballsLeft = 15
        for p in cues.indices { appeared[p] = animTime }
    }

    func rematch() { newGame(mode) }

    /// Back to a clean menu state.
    func leave() {
        generation += 1
        haptics.endAll()
        aims = [:]; previews = [:]; touches = [:]; fingers = []
    }

    // MARK: - Reading the state

    func cueBall(of player: Int) -> Ball? {
        player < cueIndex.count ? sim.balls[cueIndex[player]] : nil
    }

    var isVersus: Bool { if case .versus = mode { true } else { false } }
    var isComputerGame: Bool { if case .computer = mode { true } else { false } }
    var isComputersTurn: Bool { isComputerGame && turn == 1 }

    var playerNames: [String] {
        switch mode {
        case .practice: ["You"]
        case .computer(let level): ["You", level.title + " bot"]
        case .versus(let n): (1...n).map { "Player \($0)" }
        }
    }

    /// Whether the table is still enough to take a shot (turn-based games).
    private var tableIsQuiet: Bool { !shotInFlight && !sim.isMoving && sinks.isEmpty }

    var isBusy: Bool {
        sim.isMoving || !aims.isEmpty || !sinks.isEmpty || !appeared.isEmpty || !respawnAt.isEmpty
            || isComputersTurn || banner != nil
    }

    func transform(for size: CGSize) -> ViewTransform {
        ViewTransform(view: size, topReserve: topReserve, bottomReserve: bottomReserve)
    }

    /// Whether `player` could be pulled back right now.
    func canAim(_ player: Int) -> Bool {
        guard overlay == .none, player < cueIndex.count else { return false }
        let ball = sim.balls[cueIndex[player]]
        guard ball.onTable, ball.vel == .zero else { return false }
        if isVersus { return true }
        return player == 0 && turn == 0 && tableIsQuiet
    }

    // MARK: - Touches

    /// A finger (or the mouse) went down. In a versus game it picks up whichever of the player's
    /// own cue balls is nearest; in the other modes it can start anywhere, like Tiny Putt.
    func touchBegan(_ id: AnyHashable, at point: CGPoint, size: CGSize) {
        guard fingers.insert(id).inserted else { return }
        if isVersus {
            let t = transform(for: size)
            var best: (player: Int, d: CGFloat)?
            for p in cueIndex.indices where canAim(p) && !touches.values.contains(where: { $0.player == p }) {
                let d = hypot(t.toScreen(sim.balls[cueIndex[p]].pos).x - point.x, t.toScreen(sim.balls[cueIndex[p]].pos).y - point.y)
                if d <= max(70, 8 * t.scale * 11), best == nil || d < best!.d { best = (p, d) }
            }
            if let best { touches[id] = (best.player, point, size) }
        } else if canAim(0), !touches.values.contains(where: { $0.player == 0 }) {
            touches[id] = (0, point, size)
        }
    }

    func touchMoved(_ id: AnyHashable, to point: CGPoint) {
        guard let touch = touches[id] else { return }
        let p = touch.player
        guard canAim(p) else { cancelAim(p); return }
        let t = transform(for: touch.size)
        let pull = t.toWorld(touch.start) - t.toWorld(point)
        let length = pull.length
        guard length >= Shot.minPull else { cancelAim(p); return }
        if aims[p] == nil { sounds.prepare() }
        let clamped = pull * min(1, Shot.maxPull / length)
        aims[p] = clamped
        haptics.updateAim(player: p, power: Shot.power(forPull: length))
        previews[p] = showGuide ? makePreview(for: p, pull: clamped) : nil
    }

    func touchEnded(_ id: AnyHashable) {
        fingers.remove(id)
        guard let touch = touches.removeValue(forKey: id) else { return }
        if let pull = aims[touch.player], canAim(touch.player) {
            fire(player: touch.player, pull: pull)
        }
        cancelAim(touch.player)
    }

    private func cancelAim(_ player: Int) {
        aims[player] = nil
        previews[player] = nil
        haptics.endAim(player: player)
    }

    private func fire(player: Int, pull: Vec) {
        let length = pull.length
        let power = Shot.power(forPull: length)
        sim.launch(cueIndex[player], velocity: pull.normalized * Shot.speed(forPull: length))
        if !isVersus {
            shots += 1
            shotInFlight = true
            pottedThisShot = 0
            cueLostThisShot = false
        }
        sounds.play(.cue(power: power))
        haptics.hit(power: power)
    }

    // MARK: - Aim guide

    /// The route the cue ball will really take (the same physics as the shot) until it meets a
    /// ball, then where both go.
    private func makePreview(for player: Int, pull: Vec) -> ShotPreview {
        var probe = sim
        let ci = cueIndex[player]
        let power = Shot.power(forPull: pull.length)
        probe.launch(ci, velocity: pull.normalized * Shot.speed(forPull: pull.length))
        var events: [SimEvent] = []
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
        while s < 240, travelledTarget < 140 || travelledAfter < 90 {
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
            if !probe.isMoving { break }
        }
        return preview
    }

    // MARK: - Frame update

    func advance(to date: Date) {
        let now = date.timeIntervalSinceReferenceDate
        defer { lastTick = now }
        guard let last = lastTick else { return }
        let dt = min(now - last, 1.0 / 15.0)
        guard dt > 0 else { return }
        animTime += dt

        if sim.isMoving {
            accumulator += dt
            var events: [SimEvent] = []
            while accumulator >= Simulation.dt {
                sim.step(events: &events)
                accumulator -= Simulation.dt
            }
            handle(events)
        } else {
            accumulator = 0
        }

        rollBalls()
        updateSinks(dt)
        for (p, t) in appeared where animTime - t > 0.4 { appeared[p] = nil }
        if banner != nil, animTime > bannerUntil { banner = nil }

        // Cue balls that were lost come back after a moment (versus games).
        for (p, due) in respawnAt where animTime >= due { respawn(p) }

        if shotInFlight, !sim.isMoving { shotEnded() }
        runComputer()
        if let due = finishAt, animTime >= due, !sim.isMoving { finish() }
    }

    // MARK: - Rolling and dropping

    /// Turns each ball by how far it rolled: a ball that moves a distance `d` turns by `d / radius`
    /// about the axis across its path.
    private func rollBalls() {
        for i in sim.balls.indices where sim.balls[i].onTable {
            roll(i, from: lastPos[i], to: sim.balls[i].pos)
            lastPos[i] = sim.balls[i].pos
        }
    }

    private func roll(_ i: Int, from: Vec, to: Vec) {
        let d = to - from
        let dist = d.length
        guard dist > 1e-4, dist < 80 else { return }
        let axis = SIMD3<Double>(-d.y, d.x, 0) / dist
        orient[i] = (simd_quatd(angle: dist / Table.ballRadius, axis: axis) * orient[i]).normalized
    }

    private func updateSinks(_ dt: Double) {
        guard !sinks.isEmpty else { return }
        var left = dt
        while left > 0 {
            let h = min(left, 1.0 / 120)
            left -= h
            for k in sinks.indices {
                var s = sinks[k]
                let before = s.pos
                // Pulled to the middle of the hole, with a little drag: it swings in and settles.
                s.vel += ((s.pocket - s.pos) * 650 - s.vel * 7) * h
                s.pos += s.vel * h
                // It cannot go past the back of the pocket.
                let off = s.pos - s.pocket
                let limit = Table.pocketRadius(s.pocketIndex) * 0.65
                if off.length > limit {
                    s.pos = s.pocket + off * (limit / off.length)
                    s.vel = s.vel * 0.25
                }
                s.depth = min(1, s.depth + h / Sink.seconds)
                roll(s.index, from: before, to: s.pos)
                sinks[k] = s
            }
        }
        sinks.removeAll { $0.depth >= 1 }
    }

    private func handle(_ events: [SimEvent]) {
        for event in events {
            switch event {
            case .clack(_, _, let speed, _):
                let impact = min(1, speed / 700)
                if animTime - lastClack > 0.025 {
                    sounds.play(.clack(impact: impact))
                    if speed > 120 { haptics.clack(strength: impact) }
                    lastClack = animTime
                }
            case .cushion(_, let speed):
                if animTime - lastCushion > 0.03 {
                    sounds.play(.cushion(impact: min(1, speed / 700)))
                    lastCushion = animTime
                }
            case .pocketed(let i, let pocket):
                pocketed(i, pocket: pocket)
            }
        }
    }

    private func pocketed(_ i: Int, pocket: Int) {
        let ball = sim.balls[i]
        sinks.append(Sink(kind: ball.kind, index: i, pos: ball.pos, vel: ball.sunkVel, pocket: Table.pockets[pocket], pocketIndex: pocket))
        switch ball.kind {
        case .cue(let p):
            // The cue ball dropped.
            let owner = isVersus ? p : turn
            if owner < scores.count { scores[owner] -= 1 }
            sounds.play(.scratch)
            haptics.scratch()
            show("Scratch! −1")
            if isVersus {
                respawnAt[p] = animTime + 1.3
            } else {
                cueLostThisShot = true
                if !shotInFlight { respawn(0) }
            }
        case .object(let number):
            let owner = isVersus ? ball.credit : turn
            let value = Table.value(of: number)
            if let owner, owner < scores.count { scores[owner] += value }
            pottedThisShot += 1
            ballsLeft = sim.balls.filter { $0.onTable && $0.number != nil }.count
            sounds.play(.pocket)
            haptics.clack(strength: 1)
            if number == 8 { show("Black eight! +3") }
            if ballsLeft == 0 { finishAt = animTime + 0.9 }
        }
    }

    private func respawn(_ player: Int) {
        respawnAt[player] = nil
        let i = cueIndex[player]
        let home = isVersus ? Table.startSpots(count: mode.playerCount)[player] : Table.headSpot
        sim.balls[i].onTable = true
        sim.balls[i].vel = .zero
        sim.balls[i].pos = .zero          // out of the way while looking for a spot
        sim.balls[i].pos = sim.freeSpot(near: home, ignoring: i)
        lastPos[i] = sim.balls[i].pos
        orient[i] = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
        appeared[player] = animTime
    }

    private func show(_ text: String, for seconds: Double = 1.4) {
        banner = text
        bannerUntil = animTime + seconds
    }

    // MARK: - Turns

    private func shotEnded() {
        shotInFlight = false
        if cueLostThisShot { respawn(0) }
        guard ballsLeft > 0 else { return }
        switch mode {
        case .practice, .versus:
            break
        case .computer:
            // Keep going while you keep potting. A miss or a scratch passes the table on.
            let keeps = pottedThisShot > 0 && !cueLostThisShot
            if !keeps {
                turn = 1 - turn
                show(turn == 0 ? "Your turn" : "\(playerNames[1])'s turn", for: 1.1)
            }
            ai = .idle
            aiReadyAt = animTime + 0.9
        }
    }

    // MARK: - The computer's turn

    private func runComputer() {
        guard case .computer(let level) = mode, turn == 1, overlay == .none, finishAt == nil,
              tableIsQuiet else { return }
        switch ai {
        case .idle:
            guard animTime >= aiReadyAt else { return }
            ai = .thinking
            let snapshot = sim, cue = cueIndex[0], id = generation
            Task {
                let velocity = await Task.detached(priority: .userInitiated) {
                    ComputerPlayer.chooseShot(table: snapshot, cue: cue, level: level)
                }.value
                self.computerChose(velocity, generation: id)
            }
        case .thinking:
            break
        case .aiming(let start, let velocity):
            // The pull draws back over a moment, like a person lining up.
            let target = Shot.pull(forSpeed: velocity.length)
            let t = min(1, (animTime - start) / 0.9)
            let eased = t * t * (3 - 2 * t)
            let length = Shot.minPull + 2 + (target - Shot.minPull - 2) * eased
            aims[0] = velocity.normalized * length
            haptics.endAim(player: 0)
            if t >= 1 {
                aims[0] = nil
                ai = .idle
                aiReadyAt = .infinity
                fire(player: 0, pull: velocity.normalized * target)
            }
        }
    }

    private func computerChose(_ velocity: Vec, generation id: Int) {
        guard id == generation, case .thinking = ai else { return }
        ai = .aiming(start: animTime, velocity: velocity)
        sounds.prepare()
    }

    // MARK: - The end

    private func finish() {
        finishAt = nil
        for p in cueIndex.indices { cancelAim(p) }
        touches = [:]; fingers = []
        newBest = false
        switch mode {
        case .practice:
            let best = defaults.integer(forKey: Keys.bestPractice)
            if best == 0 || shots < best {
                defaults.set(shots, forKey: Keys.bestPractice)
                newBest = best != 0 || shots > 0
            }
        case .computer(let level):
            if scores[0] > scores[1] { defaults.set(wins(against: level) + 1, forKey: "wins\(level.rawValue)") }
        case .versus:
            break
        }
        sounds.play(.win)
        haptics.success()
        overlay = .finished
    }

    /// The final order, highest score first.
    var standings: [(player: Int, score: Int)] {
        scores.enumerated().map { ($0.offset, $0.element) }.sorted { $0.1 > $1.1 }
    }

    /// Who won, or nil for a draw at the top.
    var winner: Int? {
        let s = standings
        guard let first = s.first else { return nil }
        if s.count > 1, s[1].score == first.score { return nil }
        return first.player
    }
}
