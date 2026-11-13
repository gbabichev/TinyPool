//
//  Styles.swift
//  Tiny Pool
//
//  The same chunky, friendly look as Tiny Putt.
//

import SwiftUI

enum Ink {
    static let dark = Color(hex: 0x1F3A2D)
    static let cream = Color(hex: 0xF6EDCB)
    static let green = Color(hex: 0x3E9A5B)
}

/// A rounded button: cream by default, green when it is the main action.
struct PillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .heavy, design: .rounded))
            .foregroundStyle(prominent ? Color.white : Ink.dark)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .frame(maxWidth: 320)
            .background(Capsule().fill(prominent ? Ink.green : Ink.cream))
            .overlay(Capsule().stroke(.black.opacity(0.12), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The small round buttons over the table.
struct RoundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .heavy, design: .rounded))
            .foregroundStyle(Ink.dark)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Ink.cream))
            .overlay(Circle().stroke(.black.opacity(0.12), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

/// A flat pool ball for menus and the scoreboard. `number` nil draws a cue ball.
struct BallDot: View {
    var number: Int?
    var ring: Color = PoolColors.players[0]
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            if let number {
                let color = PoolColors.ball(number)
                let stripe = number > 8
                Circle().fill(stripe ? Color.white : color)
                if stripe {
                    Rectangle().fill(color).frame(height: size * 0.56).clipShape(Circle())
                }
                Circle().fill(.white).frame(width: size * 0.5, height: size * 0.5)
                if size >= 20 {
                    Text("\(number)")
                        .font(.system(size: size * 0.3, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                }
            } else {
                Circle().fill(.white)
                if ring != .clear { Circle().stroke(ring, lineWidth: size * 0.14).padding(size * 0.2) }
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 1))
        .overlay(alignment: .topLeading) {
            Circle().fill(.white.opacity(0.6)).frame(width: size * 0.22, height: size * 0.22)
                .offset(x: size * 0.18, y: size * 0.18)
        }
    }
}

/// A card on top of the game.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 14) { content }
            .padding(24)
            .frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Ink.cream))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.black.opacity(0.1), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 8)
            .padding(24)
    }
}

/// A sheet over the menu: cream, with a title and a Done button.
struct SheetFrame<Content: View>: View {
    let title: String
    let onDone: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Ink.cream.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Ink.dark)
                    Spacer()
                    Button("Done", action: onDone)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Ink.green)
                        .buttonStyle(.plain)
                }
                .padding(20)
                ScrollView {
                    VStack(spacing: 12) { content }
                        .frame(maxWidth: 480)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }
}

/// A row in a sheet: a title and a line under it, tappable.
struct OptionRow<Leading: View>: View {
    let title: String
    var subtitle: String?
    var selected = false
    @ViewBuilder var leading: Leading
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 18, weight: .heavy, design: .rounded))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .opacity(0.65)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Ink.green)
                }
            }
            .foregroundStyle(Ink.dark)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(selected ? 0.9 : 0.5)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Ink.green.opacity(selected ? 0.8 : 0), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}
