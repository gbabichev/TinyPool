//
//  SetupViews.swift
//  Tiny Pool
//
//  The sheets for picking an opponent, picking the players, and the settings.
//

import SwiftUI

struct ComputerSetupView: View {
    let game: PoolGame
    let onStart: (AILevel) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetFrame(title: "Vs Computer", onDone: { dismiss() }) {
            Text("Take turns at the table. Keep potting and you keep the cue. Miss, and it passes on.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.dark.opacity(0.75))
                .multilineTextAlignment(.center)
            ForEach(AILevel.allCases) { level in
                let wins = game.wins(against: level)
                OptionRow(title: level.title,
                          subtitle: level.blurb + (wins > 0 ? "  ·  \(wins) \(wins == 1 ? "win" : "wins")" : ""),
                          selected: game.lastLevel == level,
                          leading: { BallDot(number: [3, 5, 8][level.rawValue], size: 30) },
                          action: { onStart(level) })
            }
        }
    }
}

struct VersusSetupView: View {
    let game: PoolGame
    let onStart: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetFrame(title: "Versus", onDone: { dismiss() }) {
            Text("Everyone plays at once on one screen, each with a cue ball of their own colour. Pull back from your own ring. Pot a ball your cue ball sent rolling and the point is yours.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.dark.opacity(0.75))
                .multilineTextAlignment(.center)
            ForEach(2...4, id: \.self) { n in
                OptionRow(title: "\(n) players",
                          subtitle: n == 2 ? "Head to head" : n == 3 ? "A crowd of three" : "Full house",
                          selected: game.lastVersusCount == n,
                          leading: {
                              HStack(spacing: -8) {
                                  ForEach(0..<n, id: \.self) { BallDot(number: nil, ring: PoolColors.players[$0], size: 24) }
                              }
                          },
                          action: { onStart(n) })
            }
            #if os(macOS)
            Text("A mouse is one pointer, so on a Mac you take it in turns. On an iPad or iPhone, everyone can shoot together.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.dark.opacity(0.55))
                .multilineTextAlignment(.center)
            #endif
        }
    }
}

struct SettingsView: View {
    @Bindable var game: PoolGame
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetFrame(title: "Settings", onDone: { dismiss() }) {
            toggleRow("Sound", isOn: $game.isSoundOn)
            // The Mac never buzzes the trackpad, so the switch only exists on iPhone and iPad.
            if Haptics.isAvailable {
                toggleRow("Haptics", isOn: $game.isHapticsOn)
            }
            toggleRow("Aim guide", isOn: $game.showGuide)
            VStack(alignment: .leading, spacing: 12) {
                Text("Table cloth")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Ink.dark)
                HStack(spacing: 14) {
                    ForEach(Felt.allCases) { felt in
                        Button { game.felt = felt } label: {
                            Circle().fill(felt.cloth)
                                .frame(width: 44, height: 44)
                                .overlay(Circle().stroke(Ink.dark, lineWidth: game.felt == felt ? 3.5 : 0))
                                .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(felt.name)
                    }
                    Spacer()
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.55)))
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Ink.dark)
        }
        .tint(Ink.green)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.55)))
    }
}
