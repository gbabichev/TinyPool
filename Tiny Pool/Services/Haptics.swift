//
//  Haptics.swift
//  Tiny Pool
//

import Foundation
#if os(iOS)
import UIKit
#endif

/// Small taps for the cue, the balls and the pockets. Only iPhone has the hardware; the Mac does
/// nothing on purpose (no buzzing a trackpad). Aiming buzz is tracked per player, so two friends
/// pulling back at once both feel it.
final class Haptics {
    var isEnabled = true {
        didSet { if !isEnabled { endAll() } }
    }

    #if os(iOS)
    private let tap = UIImpactFeedbackGenerator(style: .rigid)
    private let buzz = UIImpactFeedbackGenerator(style: .medium)
    private var aimTask: Task<Void, Never>?
    private var aimPowers: [Int: Double] = [:]
    #endif

    static var isAvailable: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    func hit(power: Double) {
        #if os(iOS)
        guard isEnabled else { return }
        let style: UIImpactFeedbackGenerator.FeedbackStyle = power > 0.66 ? .heavy : power > 0.33 ? .medium : .light
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }

    func clack(strength: Double) {
        #if os(iOS)
        guard isEnabled else { return }
        tap.impactOccurred(intensity: max(0.3, min(1, strength)))
        tap.prepare()
        #endif
    }

    /// A buzz that builds as the cue is pulled back: silent at first, stronger and faster the
    /// harder the shot.
    func updateAim(player: Int, power: Double) {
        #if os(iOS)
        guard isEnabled else { return }
        aimPowers[player] = max(0, min(1, power))
        guard aimTask == nil else { return }
        buzz.prepare()
        aimTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let p = self.aimPowers.values.max() ?? 0
                if p > 0.03 {
                    self.buzz.impactOccurred(intensity: CGFloat(0.1 + 0.9 * p * p))
                    self.buzz.prepare()
                }
                try? await Task.sleep(for: .seconds(0.09 - 0.055 * p))
            }
        }
        #endif
    }

    func endAim(player: Int) {
        #if os(iOS)
        aimPowers[player] = nil
        if aimPowers.isEmpty { endAll() }
        #endif
    }

    func endAll() {
        #if os(iOS)
        aimTask?.cancel()
        aimTask = nil
        aimPowers.removeAll()
        #endif
    }

    func pocket() {
        #if os(iOS)
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.9)
        #endif
    }

    func scratch() {
        #if os(iOS)
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    func success() {
        #if os(iOS)
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}
