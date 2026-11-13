//
//  Palette.swift
//  Tiny Pool
//

import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// The cloth the table is covered in, and the carpet of the room around it.
enum Felt: String, CaseIterable, Identifiable {
    case green, blue, red, purple

    var id: String { rawValue }

    var name: String { rawValue.capitalized }

    var cloth: Color {
        switch self {
        case .green: Color(hex: 0x3FA564)
        case .blue: Color(hex: 0x3B8FC4)
        case .red: Color(hex: 0xC8504F)
        case .purple: Color(hex: 0x8B66C9)
        }
    }

    /// The cushion strip and the markings: a shade darker than the cloth.
    var cushion: Color {
        switch self {
        case .green: Color(hex: 0x2F8A50)
        case .blue: Color(hex: 0x2B76A8)
        case .red: Color(hex: 0xA73F3F)
        case .purple: Color(hex: 0x7050AE)
        }
    }

    var carpet: Color {
        switch self {
        case .green: Color(hex: 0x6A9B52)
        case .blue: Color(hex: 0x5A86A6)
        case .red: Color(hex: 0xB3706A)
        case .purple: Color(hex: 0x8878AA)
        }
    }

    var carpetMark: Color {
        switch self {
        case .green: Color(hex: 0x5A8A45)
        case .blue: Color(hex: 0x4D7899)
        case .red: Color(hex: 0xA2605B)
        case .purple: Color(hex: 0x796A9C)
        }
    }
}

enum PoolColors {
    static let wood = Color(hex: 0xB9814A)
    static let woodLight = Color(hex: 0xD9A56C)
    static let woodDark = Color(hex: 0x7C5230)
    static let leather = Color(hex: 0x4A2F1C)
    static let pocket = Color(hex: 0x14161B)
    static let diamond = Color(hex: 0xF6EDCB)
    static let maple = Color(hex: 0xEBD6A4)
    static let chalk = Color(hex: 0x4F9BE0)

    /// The colour of each player's cue ball ring.
    static let players: [Color] = [Color(hex: 0xE5484D), Color(hex: 0x3E7BFA), Color(hex: 0xF5A623), Color(hex: 0xA25CF0)]

    static func ball(_ number: Int) -> Color {
        switch (number - 1) % 8 {
        case 0: Color(hex: 0xF5C518)
        case 1: Color(hex: 0x2F5FD0)
        case 2: Color(hex: 0xE5484D)
        case 3: Color(hex: 0x7B4BC4)
        case 4: Color(hex: 0xF5822A)
        case 5: Color(hex: 0x2E9B54)
        case 6: Color(hex: 0x8E2B2B)
        default: Color(hex: 0x1E1E24)
        }
    }
}
