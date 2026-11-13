//
//  SetupViews.swift
//  Tiny Pool
//
//  The sheets for picking the rules, an opponent or the players, and the settings.
//

import SwiftUI

/// Which rule sets each way of playing offers.
enum Offer {
    static let solo: [Rules] = [.potPoints, .nineBall, .timed]
    static let computer: [Rules] = [.potPoints, .eightBall, .nineBall]
    static let versus: [Rules] = [.potPoints, .timed, .eightBall, .nineBall]

    /// How many players a rule set can have in Versus.
    static func playerRange(_ rules: Rules) -> ClosedRange<Int> { rules == .eightBall ? 2...2 : 2...4 }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(Ink.dark.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
    }
}

/// Practice: pick a game, and it starts.
struct PracticeSetupView: View {
    let game: PoolGame
    let onStart: (Rules) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var help: Rules?

    var body: some View {
        SheetFrame(title: "Practice", onDone: { dismiss() }) {
            Text("Just you and the table. Pick a game to start.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.dark.opacity(0.75))
            RulesPicker(options: Offer.solo, selection: nil, onSelect: onStart, onHelp: { help = $0 })
        }
        .sheet(item: $help) { rules in RulesView(rules: rules) { help = nil } }
    }
}

struct ComputerSetupView: View {
    let game: PoolGame
    let onStart: (Rules, AILevel) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rules: Rules
    @State private var help: Rules?

    init(game: PoolGame, onStart: @escaping (Rules, AILevel) -> Void) {
        self.game = game
        self.onStart = onStart
        _rules = State(initialValue: Offer.computer.contains(game.lastRules) ? game.lastRules : .potPoints)
    }

    var body: some View {
        SheetFrame(title: "Vs Computer", onDone: { dismiss() }) {
            SectionLabel("Game")
            RulesPicker(options: Offer.computer, selection: rules, onSelect: { rules = $0 }, onHelp: { help = $0 })
            SectionLabel("Opponent")
            ForEach(AILevel.allCases) { level in
                let wins = game.wins(against: level, rules: rules)
                OptionRow(title: level.title,
                          subtitle: level.blurb + (wins > 0 ? "  ·  \(wins) \(wins == 1 ? "win" : "wins")" : ""),
                          selected: false,
                          leading: { BallDot(number: [3, 5, 8][level.rawValue], size: 30) },
                          action: { onStart(rules, level) })
            }
        }
        .sheet(item: $help) { rules in RulesView(rules: rules) { help = nil } }
    }
}

struct VersusSetupView: View {
    let game: PoolGame
    let onStart: (Rules, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rules: Rules
    @State private var help: Rules?

    init(game: PoolGame, onStart: @escaping (Rules, Int) -> Void) {
        self.game = game
        self.onStart = onStart
        _rules = State(initialValue: Offer.versus.contains(game.lastRules) ? game.lastRules : .potPoints)
    }

    private var atOnce: Bool { rules == .potPoints || rules == .timed }

    var body: some View {
        SheetFrame(title: "Versus", onDone: { dismiss() }) {
            SectionLabel("Game")
            RulesPicker(options: Offer.versus, selection: rules, onSelect: { rules = $0 }, onHelp: { help = $0 })
            Text(atOnce
                 ? "Everyone plays at once on one screen, each with a cue ball of their own colour. Pull back from your own ring."
                 : "Pass the device: players take a turn at a time and share one cue ball.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.dark.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.vertical, 4)
            SectionLabel("Players")
            ForEach(2...4, id: \.self) { n in
                let allowed = Offer.playerRange(rules).contains(n)
                OptionRow(title: "\(n) players",
                          subtitle: allowed ? (n == 2 ? "Head to head" : n == 3 ? "A crowd of three" : "Full house") : "\(rules.title) is a two-player game",
                          selected: false,
                          leading: {
                              HStack(spacing: -8) {
                                  ForEach(0..<n, id: \.self) { BallDot(number: nil, ring: PoolColors.players[$0], size: 24) }
                              }
                          },
                          action: { onStart(rules, n) })
                .disabled(!allowed)
                .opacity(allowed ? 1 : 0.45)
            }
            #if os(macOS)
            if atOnce {
                Text("A mouse is one pointer, so on a Mac you take it in turns. On an iPad or iPhone, everyone can shoot together.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Ink.dark.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            #endif
        }
        .sheet(item: $help) { rules in RulesView(rules: rules) { help = nil } }
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
