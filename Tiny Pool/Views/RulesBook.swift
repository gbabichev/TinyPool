//
//  RulesBook.swift
//  Tiny Pool
//
//  The little "?" rule book for each game.
//

import SwiftUI

extension Rules {
    /// Headings and short lines, in plain words.
    var book: [(heading: String, lines: [String])] {
        switch self {
        case .potPoints:
            [
                ("The goal", ["Score more points than everyone else.", "Every ball is 1 point. The black 8 is worth 3.", "When the table is clear, the highest score wins."]),
                ("How it works", ["Pull back anywhere and let go. Any ball is fair game.", "Against the computer you keep shooting while you keep potting. Miss, and it passes on.", "In Versus everyone shoots at once. A ball scores for whoever's cue ball sent it rolling."]),
                ("Scratch", ["Pot the cue ball and you lose 1 point. It comes back on the table."]),
            ]
        case .eightBall:
            [
                ("The goal", ["Pot all of your balls, then the black 8.", "Your balls are solids (1 to 7) or stripes (9 to 15)."]),
                ("Choosing", ["The table starts open. The first ball you pot decides your group, and your opponent gets the other."]),
                ("Each shot", ["Hit one of your own balls first. Pot one of yours and you shoot again.", "Once all yours are gone, hit the 8 first."]),
                ("Fouls", ["Pot the cue ball, hit nothing, or hit the wrong ball first.", "After a foul your opponent gets ball in hand: drag the cue ball anywhere, then shoot."]),
                ("Winning", ["Pot the 8 after clearing your group, with a clean shot.", "Pot the 8 too soon, or scratch while doing it, and you lose."]),
            ]
        case .nineBall:
            [
                ("The goal", ["Pot the 9 ball to win.", "The balls are 1 to 9."]),
                ("Each shot", ["Always hit the lowest number on the table first.", "Pot any ball with a clean shot and you shoot again.", "The 9 can go in any way: straight in, or off another ball."]),
                ("Fouls", ["Pot the cue ball, hit nothing, or hit the wrong ball first.", "Your opponent gets ball in hand: drag the cue ball anywhere, then shoot.", "If the 9 drops on a foul, it goes back on the table."]),
            ]
        case .timed:
            [
                ("The goal", ["Score as many points as you can in 60 seconds.", "The clock starts on your first shot."]),
                ("Scoring", ["Every ball is 1 point. The black 8 is worth 3.", "Pot the cue ball and you lose 1 point."]),
                ("Keep going", ["Clear the table and a fresh rack appears, so the clock is your only limit.", "Alone, beat your best score. In Versus everyone shoots at once and the top score wins."]),
            ]
        }
    }
}

struct RulesView: View {
    let rules: Rules
    let onDone: () -> Void

    var body: some View {
        SheetFrame(title: rules.title, onDone: onDone) {
            Text(rules.tagline)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Ink.dark.opacity(0.75))
                .multilineTextAlignment(.center)
            ForEach(Array(rules.book.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.heading)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(Ink.green).frame(width: 6, height: 6).padding(.top, 7)
                            Text(line)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .foregroundStyle(Ink.dark)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.55)))
            }
        }
    }
}

/// The little round "?" that opens a rule book.
struct HelpButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("?")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Ink.dark)
                .frame(width: 38, height: 38)
                .background(Circle().fill(.white.opacity(0.7)))
                .overlay(Circle().stroke(.black.opacity(0.12), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rules")
    }
}

extension Rules {
    /// A ball (or clock) that stands for the rule set.
    @ViewBuilder var icon: some View {
        switch self {
        case .potPoints: BallDot(number: 3, size: 30)
        case .eightBall: BallDot(number: 8, size: 30)
        case .nineBall: BallDot(number: 9, size: 30)
        case .timed:
            Image(systemName: "timer")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Ink.green))
        }
    }
}

/// The list of rule sets to pick from, each with its "?".
struct RulesPicker: View {
    let options: [Rules]
    let selection: Rules?
    /// Tapping a row either selects it, or (when `startsGame`) starts straight away.
    let onSelect: (Rules) -> Void
    let onHelp: (Rules) -> Void

    var body: some View {
        ForEach(options) { rules in
            HStack(spacing: 8) {
                OptionRow(title: rules.title, subtitle: rules.tagline, selected: selection == rules,
                          leading: { rules.icon }, action: { onSelect(rules) })
                HelpButton { onHelp(rules) }
            }
        }
    }
}
