//
//  GameView.swift
//  Tiny Pool
//

import SwiftUI

struct GameView: View {
    let game: PoolGame
    let onExit: () -> Void
    @Environment(\.screenInsets) private var insets
    /// The corner buttons sit the same distance from both side edges: the wider gutter wins.
    private var side: CGFloat { max(insets.leading, insets.trailing) }
    /// A tall gutter along the top (the Duo in portrait) holds the clock and Wi-Fi. The HUD moves
    /// up into it as one compact row, so it neither sits far below nor lands on those icons.
    private var inStatusStrip: Bool { insets.top > 70 }
    @State private var showingRules = false

    var body: some View {
        ZStack {
            // The table fills the whole screen, behind the notch and the Duo's side strip.
            GeometryReader { geo in
                WorldView(game: game)
                    .contentShape(Rectangle())
                    .gesture(touchGesture(size: geo.size))
            }
            .ignoresSafeArea()

            hud
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(.container, edges: inStatusStrip ? .top : [])

            if let banner = game.banner {
                Text(banner)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Ink.dark)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: 0xFFE9A6)))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.black.opacity(0.12), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: 3)
                    .padding(.top, inStatusStrip ? 130 : insets.top + 78)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            if game.canPlaceCue {
                Text("Ball in hand: drag the cue ball anywhere, or pull back to shoot")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Ink.dark)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Ink.cream))
                    .overlay(Capsule().stroke(.black.opacity(0.12), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: 2)
                    .padding(.horizontal, 24)
                    .padding(.bottom, insets.bottom + 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if game.overlay != .none {
                Color.black.opacity(0.25).ignoresSafeArea()
                ResultCard(game: game, onExit: onExit)
                    .transition(.scale(scale: 0.92))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { game.topReserve = $0 > 70 ? 84 : $0 + 62 }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { game.bottomReserve = $0 + 8 }
        .animation(.spring(duration: 0.35), value: game.overlay)
        .animation(.spring(duration: 0.3), value: game.banner)
        .sheet(isPresented: $showingRules, onDismiss: { game.isPaused = false }) {
            RulesView(rules: game.mode.rules) { showingRules = false }
        }
    }

    /// Several fingers at once on a touch screen (each one pulls its own cue ball), one pointer on a Mac.
    private func touchGesture(size: CGSize) -> some Gesture {
        #if os(macOS)
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                game.touchBegan(0, at: value.startLocation, size: size)
                game.touchMoved(0, to: value.location)
            }
            .onEnded { _ in game.touchEnded(0) }
        #else
        SpatialEventGesture()
            .onChanged { events in
                for event in events {
                    if event.phase == .active {
                        game.touchBegan(event.id, at: event.location, size: size)
                        game.touchMoved(event.id, to: event.location)
                    } else {
                        game.touchEnded(event.id)
                    }
                }
            }
            .onEnded { events in
                for event in events { game.touchEnded(event.id) }
            }
        #endif
    }

    // MARK: - HUD

    private var exitButton: some View {
        Button(action: onExit) { Image(systemName: "xmark") }
            .accessibilityLabel("Menu")
    }

    private var rulesButton: some View {
        Button {
            game.isPaused = true
            showingRules = true
        } label: { Image(systemName: "questionmark") }
            .accessibilityLabel("Rules")
    }

    private var restartButton: some View {
        Button { game.rematch() } label: { Image(systemName: "arrow.counterclockwise") }
            .accessibilityLabel("Rack again")
    }

    @ViewBuilder private var hud: some View {
        if inStatusStrip {
            HStack(spacing: 10) {
                exitButton
                Scoreboard(game: game)
                rulesButton
                restartButton
            }
            .buttonStyle(RoundButtonStyle())
            .padding(.top, 14)
        } else {
            ZStack(alignment: .top) {
                Scoreboard(game: game)
                HStack {
                    exitButton
                    Spacer()
                    rulesButton
                    restartButton
                }
                .padding(.horizontal, side)
                .buttonStyle(RoundButtonStyle())
            }
        }
    }
}

/// The pill at the top: it shows what matters for the rule set being played.
private struct Scoreboard: View {
    let game: PoolGame

    private func clock(_ s: Int) -> String { "\(s / 60):" + String(format: "%02d", s % 60) }

    var body: some View {
        VStack(spacing: 3) {
            switch (game.mode.rules, game.mode.opponent) {
            case (.potPoints, .solo):
                Text("PRACTICE")
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(1.5)
                line("SHOTS \(game.shots) · LEFT \(game.ballsLeft)")
            case (.nineBall, .solo):
                Text("9-BALL")
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(1.5)
                line("HIT THE \(game.lowestBall ?? 9) · SHOTS \(game.shots) · FOULS \(game.fouls)")
            case (.timed, .solo):
                HStack(spacing: 14) {
                    Label(clock(game.secondsLeft), systemImage: "timer")
                        .font(.system(size: 17, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text("SCORE \(game.scores.first ?? 0)")
                        .font(.system(size: 17, weight: .heavy, design: .rounded)).monospacedDigit()
                }
                line(game.secondsLeft == Rules.timedSeconds ? "THE CLOCK STARTS ON YOUR FIRST SHOT" : "LEFT \(game.ballsLeft) · 8-BALL = 3")
            case (.potPoints, _):
                chips(named: game.isComputerGame)
                line("LEFT \(game.ballsLeft) · 8-BALL = 3")
            case (.timed, _):
                HStack(spacing: 12) {
                    Label(clock(game.secondsLeft), systemImage: "timer")
                        .font(.system(size: 15, weight: .heavy, design: .rounded)).monospacedDigit()
                    chips(named: false)
                }
                line(game.secondsLeft == Rules.timedSeconds ? "THE CLOCK STARTS ON THE FIRST SHOT" : "LEFT \(game.ballsLeft) · 8-BALL = 3")
            case (.eightBall, _):
                chips(named: true)
                line(game.groups[0] == nil ? "OPEN TABLE · FIRST BALL POTTED CHOOSES" : "POT YOURS, THEN THE 8")
            case (.nineBall, _):
                chips(named: game.isComputerGame)
                line("HIT THE \(game.lowestBall ?? 9) FIRST")
            }
        }
        .foregroundStyle(Ink.dark)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Capsule().fill(Ink.cream))
        .overlay(Capsule().stroke(.black.opacity(0.12), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: 2)
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.5)
            .opacity(0.55)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    @ViewBuilder private func chips(named: Bool) -> some View {
        let names = game.playerNames
        HStack(spacing: named ? 12 : 10) {
            ForEach(0..<game.mode.playerCount, id: \.self) { p in
                chip(p, name: named ? (p == 0 ? "You" : names[p].replacingOccurrences(of: " bot", with: "")) : nil)
            }
        }
    }

    private func chip(_ p: Int, name: String?) -> some View {
        let turnBased = !game.isSimultaneous
        let active = turnBased && game.mode.playerCount > 1 && game.turn == p
        let rules = game.mode.rules
        return HStack(spacing: 5) {
            BallDot(number: nil, ring: PoolColors.players[p], size: 16)
            if let name {
                Text(name).font(.system(size: 12, weight: .bold, design: .rounded)).opacity(0.8)
            }
            if rules == .eightBall {
                if let g = game.groups[p] {
                    Text("\(g.name.prefix(1)) \(game.remaining.filter { g.contains($0) }.count)")
                        .font(.system(size: 15, weight: .heavy, design: .rounded)).monospacedDigit()
                }
            } else if rules.scoresPoints {
                Text("\(game.scores.indices.contains(p) ? game.scores[p] : 0)")
                    .font(.system(size: 17, weight: .heavy, design: .rounded)).monospacedDigit()
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(PoolColors.players[p].opacity(active ? 0.25 : 0)))
    }
}

/// What shows when a game ends.
struct ResultCard: View {
    let game: PoolGame
    let onExit: () -> Void

    private func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

    var body: some View {
        Card {
            switch game.mode.opponent {
            case .solo:
                switch game.mode.rules {
                case .timed:
                    title("Time!")
                    sub("Score \(game.scores.first ?? 0)")
                case .nineBall:
                    title("Nine down!")
                    sub("\(plural(game.shots, "shot")) · \(plural(game.fouls, "foul"))")
                default:
                    title("Table cleared!")
                    sub(plural(game.shots, "shot"))
                }
                if game.newBest { banner("New best!") }
            case .computer:
                title(game.winner == 0 ? "You win!" : game.winner == nil ? "A draw" : "The computer wins")
                extras
            case .versus:
                title(game.winner.map { "Player \($0 + 1) wins!" } ?? "A draw")
                extras
            }
            Button("Play again") { game.rematch() }.buttonStyle(PillButtonStyle(prominent: true))
            Button("Menu", action: onExit).buttonStyle(PillButtonStyle())
        }
    }

    /// The reason, and the points where the game has points.
    @ViewBuilder private var extras: some View {
        if let note = game.resultNote { sub(note) }
        if game.mode.rules.scoresPoints { standings }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .heavy, design: .rounded))
            .foregroundStyle(Ink.dark)
            .multilineTextAlignment(.center)
    }

    private func sub(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(Ink.dark.opacity(0.7))
            .multilineTextAlignment(.center)
    }

    private var standings: some View {
        let top = game.standings.first?.score
        return VStack(spacing: 8) {
            ForEach(game.standings, id: \.player) { entry in
                HStack(spacing: 8) {
                    BallDot(number: nil, ring: PoolColors.players[entry.player], size: 22)
                    Text(game.playerNames[entry.player])
                    if entry.score == top, game.winner != nil {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: 0xE0A526))
                    }
                    Spacer()
                    Text("\(entry.score)").monospacedDigit()
                }
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Ink.dark)
            }
        }
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundStyle(Ink.dark)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(hex: 0xFFE9A6)))
            .overlay(Capsule().stroke(.black.opacity(0.12), lineWidth: 1.5))
    }
}

/// The table, drawn on its own so a redraw does not re-evaluate the buttons above it. It also
/// runs the game clock: about 60 times a second while anything moves, and far less when the
/// game is at rest.
private struct WorldView: View {
    let game: PoolGame
    @State private var frame = 0

    var body: some View {
        Canvas { ctx, size in
            // Reading `frame` ties each redraw to the game clock.
            _ = frame
            TableRenderer.draw(&ctx, size: size, game: game)
        }
        .task {
            while !Task.isCancelled {
                game.advance(to: .now)
                frame &+= 1
                try? await Task.sleep(for: game.isBusy ? .milliseconds(16) : .milliseconds(33))
            }
        }
    }
}
