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

    /// How wide the table (rail included) is on the screen.
    var tableScreenWidth: CGFloat {
        CGFloat(rotated ? Table.height + 2 * Table.rail : Table.width + 2 * Table.rail) * scale
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
    static let seconds = 0.28
}

enum Opponent: Equatable {
    case solo
    case computer(AILevel)
    case versus(players: Int)
}

/// A rule set and who is playing it.
struct GameMode: Equatable {
    var rules: Rules
    var opponent: Opponent

    static let practice = GameMode(rules: .potPoints, opponent: .solo)

    var playerCount: Int {
        switch opponent {
        case .solo: 1
        case .computer: 2
        case .versus(let n): n
        }
    }

    /// Everyone shoots at the same time, each with a cue ball of their own. Only the free-for-all
    /// rule sets can work that way; 8-ball and 9-ball are played a turn at a time.
    var isSimultaneous: Bool {
        if case .versus = opponent { return rules == .potPoints || rules == .timed }
        return false
    }
}

@MainActor
@Observable
final class PoolGame {
    enum Overlay: Equatable { case none, finished }

    // MARK: Observed (the menus and buttons show these)
    private(set) var mode = GameMode.practice
    private(set) var scores: [Int] = [0]
    /// Whose turn it is. Always 0 when everyone plays at once.
    private(set) var turn = 0
    private(set) var shots = 0
    private(set) var fouls = 0
    /// The numbers still on the table.
    private(set) var remaining: [Int] = []
    /// Who owns solids or stripes (8-ball).
    private(set) var groups: [BallGroup?] = [nil, nil]
    private(set) var ballInHand = false
    private(set) var secondsLeft = Rules.timedSeconds
    private(set) var overlay: Overlay = .none
    /// A short line over the table ("Scratch!", "+3").
    private(set) var banner: String?
    private(set) var newBest = false
    private(set) var matchWinner: Int?
    private(set) var resultNote: String?
    /// Held while the rule book is open.
    var isPaused = false

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
    var lastRules: Rules {
        didSet { defaults.set(lastRules.rawValue, forKey: Keys.rules) }
    }

    // MARK: Simulation state (redrawn every frame by the canvas, so not observed)
    @ObservationIgnored private(set) var sim = Simulation(balls: [])
    @ObservationIgnored private(set) var animTime = 0.0
    @ObservationIgnored private(set) var aims: [Int: Vec] = [:]
    @ObservationIgnored private(set) var previews: [Int: ShotPreview] = [:]
    /// Players whose hint needs working out again. It is done once per frame, not once per touch event.
    @ObservationIgnored private var previewDirty: Set<Int> = []
    @ObservationIgnored private(set) var sinks: [Sink] = []
    /// How each ball is turned, so it visibly rolls.
    @ObservationIgnored private(set) var orient: [simd_quatd] = []
    @ObservationIgnored private var lastPos: [Vec] = []
    /// When each cue ball last (re)appeared, for its pop-in.
    @ObservationIgnored private(set) var appeared: [Int: Double] = [:]
    @ObservationIgnored var topReserve: CGFloat = 70
    @ObservationIgnored var bottomReserve: CGFloat = 8
    /// The room left under the table when the two corner buttons need a strip of their own.
    @ObservationIgnored var tallBottomReserve: CGFloat = 62
    /// Whether the hint and help buttons sit in the bottom corners (they do, except in the Duo's gutter).
    @ObservationIgnored var cornerButtons = true

    private struct Touch {
        var player: Int
        var start: CGPoint
        var size: CGSize
        /// Carrying the cue ball to a new spot (ball in hand), rather than aiming.
        var placing: Bool
    }

    @ObservationIgnored private var cueIndex: [Int] = []
    @ObservationIgnored private var objectIndex: [Int: Int] = [:]
    @ObservationIgnored private var lastTick: Double?
    @ObservationIgnored private var accumulator = 0.0
    @ObservationIgnored private var touches: [AnyHashable: Touch] = [:]
    /// Every finger that is down, whether or not it picked up a cue ball.
    @ObservationIgnored private var fingers: Set<AnyHashable> = []
    /// A shot has been taken and the table has not come to rest yet (a turn at a time).
    @ObservationIgnored private var shotInFlight = false
    @ObservationIgnored private var report = ShotReport()
    @ObservationIgnored private var shotWasBreak = false
    @ObservationIgnored private var breakPending = true
    @ObservationIgnored private var pottedThisShot = 0
    @ObservationIgnored private var cueLostThisShot = false
    @ObservationIgnored private var respawnAt: [Int: Double] = [:]
    @ObservationIgnored private var finishAt: Double?
    @ObservationIgnored private var rerackAt: Double?
    @ObservationIgnored private var bannerUntil = 0.0
    @ObservationIgnored private var lastClack = -1.0
    @ObservationIgnored private var lastCushion = -1.0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var timerRunning = false
    @ObservationIgnored private var timeLeft = Double(Rules.timedSeconds)

    private enum AIState { case idle, thinking, aiming(start: Double, velocity: Vec) }
    @ObservationIgnored private var ai = AIState.idle
    @ObservationIgnored private var aiReadyAt = 0.0

    @ObservationIgnored private let sounds = SoundEngine()
    @ObservationIgnored private let haptics = Haptics()
    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Keys {
        static let sound = "soundOn", haptics = "hapticsOn", guide = "showGuide", felt = "felt"
        static let level = "lastLevel", versus = "lastVersus", rules = "lastRules"
        static let bestPractice = "bestPractice", bestNine = "bestNine", bestTimed = "bestTimed"
    }

    init() {
        isSoundOn = defaults.object(forKey: Keys.sound) as? Bool ?? true
        isHapticsOn = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        showGuide = defaults.object(forKey: Keys.guide) as? Bool ?? true
        felt = Felt(rawValue: defaults.string(forKey: Keys.felt) ?? "") ?? .green
        lastLevel = AILevel(rawValue: defaults.integer(forKey: Keys.level)) ?? .beginner
        lastVersusCount = max(2, min(4, defaults.object(forKey: Keys.versus) as? Int ?? 2))
        lastRules = Rules(rawValue: defaults.integer(forKey: Keys.rules)) ?? .potPoints
        sounds.isEnabled = isSoundOn
        haptics.isEnabled = isHapticsOn
        newGame(.practice)
    }

    // MARK: - Records

    var bestPractice: Int? {
        let v = defaults.integer(forKey: Keys.bestPractice)
        return v > 0 ? v : nil
    }

    func wins(against level: AILevel, rules: Rules) -> Int { defaults.integer(forKey: "wins\(rules.rawValue)_\(level.rawValue)") }

    // MARK: - Starting

    func newGame(_ mode: GameMode) {
        generation += 1
        self.mode = mode
        let players = mode.playerCount
        scores = Array(repeating: 0, count: players)
        groups = Array(repeating: nil, count: max(2, players))
        turn = 0
        shots = 0
        fouls = 0
        overlay = .none
        banner = nil
        newBest = false
        matchWinner = nil
        resultNote = nil
        ballInHand = false
        isPaused = false
        aims = [:]; previews = [:]; previewDirty = []; sinks = []; appeared = [:]; touches = [:]; fingers = []
        respawnAt = [:]
        finishAt = nil
        rerackAt = nil
        shotInFlight = false
        report = ShotReport()
        breakPending = true
        pottedThisShot = 0
        cueLostThisShot = false
        timerRunning = false
        timeLeft = Double(Rules.timedSeconds)
        secondsLeft = Rules.timedSeconds
        ai = .idle
        aiReadyAt = animTime + 1.0
        accumulator = 0
        haptics.endAll()

        var balls: [Ball] = []
        var cues: [Int] = []
        if mode.isSimultaneous {
            for (p, spot) in Table.startSpots(count: players).enumerated() {
                cues.append(balls.count)
                balls.append(Ball(kind: .cue(player: p), pos: spot))
            }
        } else {
            cues.append(0)
            balls.append(Ball(kind: .cue(player: 0), pos: Table.headSpot))
        }
        objectIndex = [:]
        for (number, pos) in Table.rack(for: mode.rules) {
            // A hair of jitter, so no two breaks play the same.
            let jitter = Vec(Double.random(in: -0.25...0.25), Double.random(in: -0.25...0.25))
            objectIndex[number] = balls.count
            balls.append(Ball(kind: .object(number: number), pos: pos + jitter))
        }
        sim = Simulation(balls: balls)
        orient = Array(repeating: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1), count: balls.count)
        lastPos = balls.map(\.pos)
        cueIndex = cues
        remaining = mode.rules.ballNumbers
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

    var ballsLeft: Int { remaining.count }
    var isSimultaneous: Bool { mode.isSimultaneous }
    var isComputerGame: Bool { if case .computer = mode.opponent { true } else { false } }
    var isComputersTurn: Bool { isComputerGame && turn == 1 }
    var lowestBall: Int? { remaining.min() }

    var playerNames: [String] {
        switch mode.opponent {
        case .solo: ["You"]
        case .computer(let level): ["You", level.title + " bot"]
        case .versus(let n): (1...n).map { "Player \($0)" }
        }
    }

    /// "Your turn" for you, "Player 2's turn" for everyone else.
    private func turnLine(_ player: Int) -> String {
        playerNames[player] == "You" ? "Your turn" : "\(playerNames[player])'s turn"
    }

    /// "Ball in hand for you", "Ball in hand for Player 2".
    private func handLine(_ player: Int) -> String {
        "Ball in hand for \(playerNames[player] == "You" ? "you" : playerNames[player])"
    }

    /// Whether the table is still enough to take a shot (a turn at a time).
    private var tableIsQuiet: Bool { !shotInFlight && !sim.isMoving }

    var isBusy: Bool {
        sim.isMoving || !aims.isEmpty || !sinks.isEmpty || !appeared.isEmpty || !respawnAt.isEmpty
            || isComputersTurn || banner != nil || timerRunning || ballInHand
    }

    /// Whether the picture changes by itself right now. A table at rest does not: it is drawn once
    /// and left alone, so it costs nothing until something moves.
    var needsRedraw: Bool {
        sim.isMoving || !aims.isEmpty || !sinks.isEmpty || !appeared.isEmpty || !respawnAt.isEmpty
    }

    /// The table gets a strip under it for the corner buttons only when it is too wide to leave them
    /// room at its sides: upright (it fills the width), but not on a wide screen (empty beside it).
    func transform(for size: CGSize) -> ViewTransform {
        let low = ViewTransform(view: size, topReserve: topReserve, bottomReserve: bottomReserve)
        guard cornerButtons, (size.width - low.tableScreenWidth) / 2 < 100 else { return low }
        return ViewTransform(view: size, topReserve: topReserve, bottomReserve: tallBottomReserve)
    }

    /// Whether `player`'s cue ball could be pulled back right now.
    func canAim(_ player: Int) -> Bool {
        guard overlay == .none, !isPaused, player < cueIndex.count else { return false }
        let ball = sim.balls[cueIndex[player]]
        guard ball.onTable, ball.vel == .zero else { return false }
        if isSimultaneous { return true }
        return player == 0 && !isComputersTurn && tableIsQuiet && finishAt == nil
    }

    /// The human may carry the cue ball somewhere before shooting.
    var canPlaceCue: Bool { ballInHand && canAim(0) }

    // MARK: - Touches

    /// A finger (or the mouse) went down. When everyone plays at once it picks up whichever of the
    /// player's own cue balls is nearest; otherwise it can start anywhere, like Tiny Putt. With
    /// ball in hand, a touch on the cue ball carries it.
    func touchBegan(_ id: AnyHashable, at point: CGPoint, size: CGSize) {
        guard fingers.insert(id).inserted else { return }
        let t = transform(for: size)
        if isSimultaneous {
            var best: (player: Int, d: CGFloat)?
            for p in cueIndex.indices where canAim(p) && !touches.values.contains(where: { $0.player == p }) {
                let c = t.toScreen(sim.balls[cueIndex[p]].pos)
                let d = hypot(c.x - point.x, c.y - point.y)
                if d <= max(70, 8 * t.scale * 11), best == nil || d < best!.d { best = (p, d) }
            }
            if let best { touches[id] = Touch(player: best.player, start: point, size: size, placing: false) }
        } else if canAim(0), !touches.values.contains(where: { $0.player == 0 }) {
            var placing = false
            if canPlaceCue {
                let c = t.toScreen(sim.balls[cueIndex[0]].pos)
                placing = hypot(c.x - point.x, c.y - point.y) <= 56
            }
            touches[id] = Touch(player: 0, start: point, size: size, placing: placing)
        }
    }

    func touchMoved(_ id: AnyHashable, to point: CGPoint) {
        guard let touch = touches[id] else { return }
        let p = touch.player
        guard canAim(p) else { cancelAim(p); return }
        let t = transform(for: touch.size)
        if touch.placing {
            let r = Table.ballRadius
            let w = t.toWorld(point)
            let target = Vec(max(r, min(Table.width - r, w.x)), max(r, min(Table.height - r, w.y)))
            let ci = cueIndex[0]
            sim.balls[ci].pos = sim.freeSpot(near: target, ignoring: ci)
            lastPos[ci] = sim.balls[ci].pos
            return
        }
        let pull = t.toWorld(touch.start) - t.toWorld(point)
        let length = pull.length
        guard length >= Shot.minPull else { cancelAim(p); return }
        if aims[p] == nil { sounds.prepare() }
        let clamped = pull * min(1, Shot.maxPull / length)
        aims[p] = clamped
        haptics.updateAim(player: p, power: Shot.power(forPull: length))
        previewDirty.insert(p)
    }

    func touchEnded(_ id: AnyHashable) {
        fingers.remove(id)
        guard let touch = touches.removeValue(forKey: id) else { return }
        if !touch.placing, let pull = aims[touch.player], canAim(touch.player) {
            fire(player: touch.player, pull: pull)
        }
        cancelAim(touch.player)
    }

    private func cancelAim(_ player: Int) {
        aims[player] = nil
        previews[player] = nil
        previewDirty.remove(player)
        haptics.endAim(player: player)
    }

    private func fire(player: Int, pull: Vec) {
        let length = pull.length
        let power = Shot.power(forPull: length)
        sim.launch(cueIndex[player], velocity: pull.normalized * Shot.speed(forPull: length))
        if !isSimultaneous {
            shots += 1
            shotInFlight = true
            report = ShotReport()
            shotWasBreak = breakPending
            breakPending = false
            pottedThisShot = 0
            cueLostThisShot = false
            ballInHand = false
        }
        if mode.rules == .timed { timerRunning = true }
        sounds.play(.cue(power: power))
        haptics.hit(power: power)
    }

    // MARK: - Frame update

    func advance(to date: Date) {
        let now = date.timeIntervalSinceReferenceDate
        defer { lastTick = now }
        guard let last = lastTick, !isPaused else { return }
        let dt = min(now - last, 1.0 / 15.0)
        guard dt > 0 else { return }
        animTime += dt

        if timerRunning, overlay == .none {
            timeLeft -= dt
            let s = max(0, Int(timeLeft.rounded(.up)))
            if s != secondsLeft { secondsLeft = s }
            if timeLeft <= 0 { timerRunning = false; finish() }
        }

        if overlay == .none, sim.isMoving {
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

        // Hints: once per frame, however many touch events came in. Balls moving elsewhere on the
        // table (everyone at once) change the route, so those are worked out again too.
        if sim.isMoving { previewDirty.formUnion(previews.keys) }
        for p in previewDirty {
            if let pull = aims[p], p < cueIndex.count { previews[p] = ShotPreview.make(in: sim, cue: cueIndex[p], pull: pull) }
        }
        previewDirty.removeAll(keepingCapacity: true)

        rollBalls()
        updateSinks(dt)
        for (p, t) in appeared where animTime - t > 0.4 { appeared[p] = nil }
        if banner != nil, animTime > bannerUntil { banner = nil }

        // Cue balls that were lost come back after a moment (everyone at once).
        for (p, due) in respawnAt where animTime >= due { respawn(p) }
        if let due = rerackAt, animTime >= due { rerackAt = nil; rackObjects() }

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

    // MARK: - Events

    private func handle(_ events: [SimEvent]) {
        for event in events {
            if !isSimultaneous { report.record(event, cue: cueIndex[0], balls: sim.balls) }
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
        let points = mode.rules.scoresPoints
        // Practising Pot Points alone has no score on screen (you are counting shots), so it shows no points either.
        var scoreIsShown = points
        if case .solo = mode.opponent, mode.rules == .potPoints { scoreIsShown = false }
        switch ball.kind {
        case .cue(let p):
            sounds.play(.scratch)
            haptics.scratch()
            if scoreIsShown {
                let owner = isSimultaneous ? p : turn
                if owner < scores.count { scores[owner] -= 1 }
                show("Scratch! −1")
            } else if points {
                show("Scratch!")
            }
            if isSimultaneous {
                respawnAt[p] = animTime + 1.3
            } else {
                cueLostThisShot = true
                if !shotInFlight { respawn(0) }
            }
        case .object(let number):
            remaining.removeAll { $0 == number }
            pottedThisShot += 1
            sounds.play(.pocket)
            haptics.clack(strength: 1)
            if scoreIsShown {
                let owner = isSimultaneous ? ball.credit : turn
                if let owner, owner < scores.count { scores[owner] += Table.value(of: number) }
                if number == 8 { show("Black eight! +3") }
            }
            if remaining.isEmpty {
                if mode.rules == .timed { rerackAt = animTime + 0.7 } else if mode.rules == .potPoints { finishAt = animTime + 0.9 }
            }
        }
    }

    private func respawn(_ player: Int) {
        respawnAt[player] = nil
        let i = cueIndex[player]
        let home = isSimultaneous ? Table.startSpots(count: mode.playerCount)[player] : Table.headSpot
        sim.balls[i].onTable = true
        sim.balls[i].vel = .zero
        sim.balls[i].pos = .zero          // out of the way while looking for a spot
        sim.balls[i].pos = sim.freeSpot(near: home, ignoring: i)
        lastPos[i] = sim.balls[i].pos
        orient[i] = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
        appeared[player] = animTime
    }

    /// Puts a potted ball back on the foot spot.
    private func respot(_ number: Int) {
        guard let i = objectIndex[number] else { return }
        sim.balls[i].onTable = true
        sim.balls[i].vel = .zero
        sim.balls[i].pos = .zero
        sim.balls[i].pos = sim.freeSpot(near: Table.footSpot, ignoring: i)
        lastPos[i] = sim.balls[i].pos
        orient[i] = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
        if !remaining.contains(number) { remaining.append(number); remaining.sort() }
    }

    /// A fresh rack (timed games, when the table is cleared).
    private func rackObjects() {
        for (number, pos) in Table.rack(for: .timed) {
            guard let i = objectIndex[number] else { continue }
            sim.balls[i].onTable = true
            sim.balls[i].vel = .zero
            sim.balls[i].credit = nil
            sim.balls[i].pos = pos
            lastPos[i] = pos
            orient[i] = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
        }
        remaining = Rules.timed.ballNumbers
        // A cue ball that was sitting where the rack goes is moved out of the way.
        for (p, i) in cueIndex.enumerated() where sim.balls[i].onTable && !sim.isFree(sim.balls[i].pos, ignoring: i, margin: 0) {
            let home = isSimultaneous ? Table.startSpots(count: mode.playerCount)[p] : Table.headSpot
            sim.balls[i].vel = .zero
            sim.balls[i].pos = sim.freeSpot(near: home, ignoring: i)
            lastPos[i] = sim.balls[i].pos
            appeared[p] = animTime
        }
        show("New rack!", for: 1.0)
    }

    private func show(_ text: String, for seconds: Double = 1.4) {
        banner = text
        bannerUntil = animTime + seconds
    }

    // MARK: - Turns

    private func passTurn() {
        guard mode.playerCount > 1 else { return }
        turn = (turn + 1) % mode.playerCount
    }

    private func shotEnded() {
        shotInFlight = false
        if cueLostThisShot { respawn(0) }
        switch mode.rules {
        case .timed:
            break
        case .potPoints:
            guard !remaining.isEmpty else { return }
            if isComputerGame {
                // Keep going while you keep potting. A miss or a scratch passes the table on.
                if pottedThisShot == 0 || cueLostThisShot {
                    passTurn()
                    show(turnLine(turn), for: 1.1)
                }
                nextShooter()
            }
        case .eightBall, .nineBall:
            judgeShot()
        }
    }

    private func nextShooter() {
        ai = .idle
        aiReadyAt = animTime + 0.9
    }

    /// The referee rules on the shot that just ended.
    private func judgeShot() {
        let before = Set(remaining).union(report.potted)
        let shooter = turn
        let verdict = mode.rules == .eightBall
            ? Judge.eightBall(report, group: groups[shooter], remaining: before, isBreak: shotWasBreak)
            : Judge.nineBall(report, remaining: before)
        let n = mode.playerCount
        let name = playerNames[shooter]

        if let group = verdict.assign, n == 2 {
            groups[shooter] = group
            groups[1 - shooter] = group.other
            show("\(name): \(group.name)", for: 1.6)
        }
        for number in verdict.respot { respot(number) }

        if verdict.shooterWins {
            endMatch(winner: shooter, note: mode.rules == .eightBall ? "\(name) potted the 8." : "\(name) potted the 9.")
            return
        }
        if verdict.shooterLoses {
            let other = n == 2 ? 1 - shooter : nil
            endMatch(winner: other, note: "\(name) \(verdict.loseReason ?? "lost").")
            return
        }
        if let foul = verdict.foul {
            fouls += 1
            sounds.play(.scratch)
            if n > 1 {
                passTurn()
                ballInHand = true
                show("Foul: \(foul)\n\(handLine(turn))", for: 2.4)
            } else {
                show("Foul: \(foul)", for: 1.8)
            }
        } else if !verdict.keepTurn, n > 1 {
            passTurn()
            show(turnLine(turn), for: 1.1)
        }
        nextShooter()
    }

    private func endMatch(winner: Int?, note: String) {
        matchWinner = winner
        resultNote = note
        finishAt = animTime + 0.7
    }

    // MARK: - The computer's turn

    private func runComputer() {
        guard case .computer(let level) = mode.opponent, turn == 1, overlay == .none, finishAt == nil,
              tableIsQuiet, !isPaused else { return }
        switch ai {
        case .idle:
            guard animTime >= aiReadyAt else { return }
            ai = .thinking
            let snapshot = sim, cue = cueIndex[0], id = generation
            let context = AIContext(rules: mode.rules, group: groups[1], isBreak: breakPending)
            let inHand = ballInHand
            Task {
                let plan = await Task.detached(priority: .userInitiated) {
                    ComputerPlayer.plan(table: snapshot, cue: cue, level: level, context: context, inHand: inHand)
                }.value
                self.computerChose(plan, generation: id)
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

    private func computerChose(_ plan: AIPlan, generation id: Int) {
        guard id == generation, case .thinking = ai else { return }
        if let spot = plan.spot {
            let ci = cueIndex[0]
            sim.balls[ci].pos = spot
            lastPos[ci] = spot
            appeared[0] = animTime
            ballInHand = false
        }
        ai = .aiming(start: animTime, velocity: plan.velocity)
        sounds.prepare()
    }

    // MARK: - The end

    private func finish() {
        finishAt = nil
        for p in cueIndex.indices { cancelAim(p) }
        touches = [:]; fingers = []
        newBest = false
        let rules = mode.rules
        switch mode.opponent {
        case .solo:
            switch rules {
            case .potPoints:
                newBest = record(Keys.bestPractice, value: shots, lowerIsBetter: true)
            case .nineBall:
                newBest = record(Keys.bestNine, value: shots, lowerIsBetter: true)
            case .timed:
                newBest = record(Keys.bestTimed, value: scores[0], lowerIsBetter: false)
            case .eightBall:
                break
            }
        case .computer(let level):
            if winner == 0 { defaults.set(wins(against: level, rules: rules) + 1, forKey: "wins\(rules.rawValue)_\(level.rawValue)") }
        case .versus:
            break
        }
        sounds.play(.win)
        haptics.success()
        overlay = .finished
    }

    /// Saves a personal best. True when this beat the old one (and there was one to beat).
    private func record(_ key: String, value: Int, lowerIsBetter: Bool) -> Bool {
        let old = defaults.integer(forKey: key)
        let better = old == 0 || (lowerIsBetter ? value < old : value > old)
        guard better, value > 0 || lowerIsBetter else { return false }
        defaults.set(value, forKey: key)
        return old != 0
    }

    func best(for rules: Rules) -> Int? {
        let key = rules == .nineBall ? Keys.bestNine : rules == .timed ? Keys.bestTimed : Keys.bestPractice
        let v = defaults.integer(forKey: key)
        return v > 0 ? v : nil
    }

    /// The final order, highest score first.
    var standings: [(player: Int, score: Int)] {
        scores.enumerated().map { ($0.offset, $0.element) }.sorted { $0.1 > $1.1 }
    }

    /// Who won, or nil for a draw (or when nobody did).
    var winner: Int? {
        if rulesDecideWinner { return matchWinner }
        let s = standings
        guard let first = s.first else { return nil }
        if s.count > 1, s[1].score == first.score { return nil }
        return first.player
    }

    /// 8-ball and 9-ball are won by the referee's ruling, the others by points.
    var rulesDecideWinner: Bool { mode.rules == .eightBall || mode.rules == .nineBall }
}
