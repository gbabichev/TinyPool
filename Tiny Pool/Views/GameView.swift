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
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Ink.dark)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color(hex: 0xFFE9A6)))
                    .overlay(Capsule().stroke(.black.opacity(0.12), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: 3)
                    .padding(.top, inStatusStrip ? 130 : insets.top + 78)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .allowsHitTesting(false)
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

    private var restartButton: some View {
        Button { game.rematch() } label: { Image(systemName: "arrow.counterclockwise") }
            .accessibilityLabel("Rack again")
    }

    @ViewBuilder private var hud: some View {
        if inStatusStrip {
            HStack(spacing: 10) {
                exitButton
                Scoreboard(game: game)
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
                    restartButton
                }
                .padding(.horizontal, side)
                .buttonStyle(RoundButtonStyle())
            }
        }
    }
}

/// The pill at the top: shots and balls left in practice, the score against the computer, or
/// one chip per player in a versus game.
private struct Scoreboard: View {
    let game: PoolGame

    var body: some View {
        VStack(spacing: 3) {
            switch game.mode {
            case .practice:
                Text("PRACTICE")
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(1.5)
                Text("SHOTS \(game.shots) · LEFT \(game.ballsLeft)")
                    .font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.65)
            case .computer(let level):
                HStack(spacing: 12) {
                    chip(0, name: "You")
                    chip(1, name: level.title)
                }
                Text("LEFT \(game.ballsLeft) · 8-BALL = 3")
                    .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.5).opacity(0.55)
            case .versus(let n):
                HStack(spacing: 10) {
                    ForEach(0..<n, id: \.self) { chip($0, name: nil) }
                }
                Text("LEFT \(game.ballsLeft) · 8-BALL = 3")
                    .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.5).opacity(0.55)
            }
        }
        .foregroundStyle(Ink.dark)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Capsule().fill(Ink.cream))
        .overlay(Capsule().stroke(.black.opacity(0.12), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: 2)
    }

    private func chip(_ p: Int, name: String?) -> some View {
        let active = game.isComputerGame && game.turn == p
        return HStack(spacing: 5) {
            BallDot(number: nil, ring: PoolColors.players[p], size: 16)
            if let name {
                Text(name).font(.system(size: 12, weight: .bold, design: .rounded)).opacity(0.8)
            }
            Text("\(game.scores.indices.contains(p) ? game.scores[p] : 0)")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(PoolColors.players[p].opacity(active ? 0.25 : 0)))
    }
}

/// What shows when the table is cleared.
struct ResultCard: View {
    let game: PoolGame
    let onExit: () -> Void

    var body: some View {
        Card {
            switch game.mode {
            case .practice:
                Text("Table cleared!")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Ink.dark)
                Text("\(game.shots) \(game.shots == 1 ? "shot" : "shots")")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Ink.dark.opacity(0.7))
                if game.newBest {
                    banner("New best!")
                }
            case .computer:
                Text(game.winner == 0 ? "You win!" : game.winner == nil ? "A draw" : "The computer wins")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(Ink.dark)
                standings
            case .versus:
                Text(game.winner.map { "Player \($0 + 1) wins!" } ?? "A draw")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(Ink.dark)
                standings
            }
            Button("Play again") { game.rematch() }.buttonStyle(PillButtonStyle(prominent: true))
            Button("Menu", action: onExit).buttonStyle(PillButtonStyle())
        }
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
