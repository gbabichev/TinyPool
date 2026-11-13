//
//  HomeView.swift
//  Tiny Pool
//

import SwiftUI

struct HomeView: View {
    let game: PoolGame
    let onPlay: (GameMode) -> Void

    @State private var showingSettings = false
    @State private var showingComputer = false
    @State private var showingVersus = false

    var body: some View {
        ZStack {
            MenuScenery(felt: game.felt)
                .ignoresSafeArea()

            GeometryReader { geo in
                let isWide = geo.size.width > geo.size.height * 1.1
                let layout = isWide ? AnyLayout(HStackLayout(spacing: 56)) : AnyLayout(VStackLayout(spacing: 32))
                // Centred when it fits; scrolls on short screens.
                ScrollView {
                    layout {
                        hero
                        menu
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height - 32)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView(game: game) }
        .sheet(isPresented: $showingComputer) {
            ComputerSetupView(game: game) { level in
                game.lastLevel = level
                showingComputer = false
                onPlay(.computer(level))
            }
        }
        .sheet(isPresented: $showingVersus) {
            VersusSetupView(game: game) { count in
                game.lastVersusCount = count
                showingVersus = false
                onPlay(.versus(players: count))
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            HStack(spacing: -6) {
                BallDot(number: nil, ring: PoolColors.players[0], size: 46)
                BallDot(number: 8, size: 46)
            }
            Text("Tiny Pool")
                .font(.system(size: 54, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 0, x: 0, y: 4)
            Text("Pull back. Let go. Pot the lot.")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private var menu: some View {
        VStack(spacing: 14) {
            Button("Practice") { onPlay(.practice) }.buttonStyle(PillButtonStyle(prominent: true))
            Button("Vs Computer") { showingComputer = true }.buttonStyle(PillButtonStyle())
            Button("Versus") { showingVersus = true }.buttonStyle(PillButtonStyle())
            Button("Settings") { showingSettings = true }.buttonStyle(PillButtonStyle())
            if let best = game.bestPractice {
                Text("Practice best: cleared in \(best) \(best == 1 ? "shot" : "shots")")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

/// The carpet and a few balls rolled about it, as a backdrop for the menus.
struct MenuScenery: View {
    let felt: Felt

    var body: some View {
        Canvas { ctx, size in
            TableRenderer.drawRoom(&ctx, size: size, felt: felt)
            // A scatter of big, soft balls, placed by fractions so it suits any screen.
            let spots: [(Double, Double, Int, Double)] = [
                (0.10, 0.14, 3, 1.0), (0.88, 0.10, 9, 1.2), (0.82, 0.86, 5, 1.0), (0.14, 0.82, 12, 1.3),
                (0.04, 0.48, 14, 0.8), (0.96, 0.50, 6, 0.9), (0.52, 0.96, 10, 0.9),
            ]
            let base = min(size.width, size.height) * 0.08
            for (fx, fy, n, k) in spots {
                let c = CGPoint(x: size.width * fx, y: size.height * fy)
                let r = base * k
                ctx.fill(ctx.circle(CGPoint(x: c.x + r * 0.12, y: c.y + r * 0.2), r), with: .color(.black.opacity(0.14)))
                ctx.fill(ctx.circle(c, r), with: .color(n > 8 ? .white : PoolColors.ball(n)))
                if n > 8 {
                    var band = ctx
                    band.clip(to: ctx.circle(c, r))
                    band.fill(Path(CGRect(x: c.x - r, y: c.y - r * 0.56, width: r * 2, height: r * 1.12)), with: .color(PoolColors.ball(n)))
                }
                ctx.fill(ctx.circle(c, r * 0.5), with: .color(.white))
                ctx.draw(Text("\(n)").font(.system(size: r * 0.7, weight: .heavy, design: .rounded)).foregroundStyle(.black), at: c)
                ctx.fill(ctx.circle(CGPoint(x: c.x - r * 0.34, y: c.y - r * 0.34), r * 0.22), with: .color(.white.opacity(0.6)))
            }
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.18)))
        }
    }
}
