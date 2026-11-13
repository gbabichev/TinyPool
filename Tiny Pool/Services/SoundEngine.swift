//
//  SoundEngine.swift
//  Tiny Pool
//

import AVFoundation

/// Tiny synthesized sound effects, made in code so the app ships no audio files.
/// Built the same way as Tiny Putt's engine.
final class SoundEngine {
    enum Effect {
        /// The cue striking the ball. `power` runs from 0 to 1.
        case cue(power: Double)
        /// Ball on ball. `impact` runs from 0 to 1.
        case clack(impact: Double)
        case cushion(impact: Double)
        case pocket
        case scratch
        case win
    }

    var isEnabled = true

    private static let sampleRate = 44_100.0

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var isReady = false
    private var idlePause: Task<Void, Never>?

    private var cueBuffers: [AVAudioPCMBuffer] = []
    private var clackBuffers: [AVAudioPCMBuffer] = []
    private var cushionBuffers: [AVAudioPCMBuffer] = []
    private var pocketBuffer: AVAudioPCMBuffer?
    private var scratchBuffer: AVAudioPCMBuffer?
    private var winBuffer: AVAudioPCMBuffer?

    init() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        #endif
        for _ in 0..<10 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        cueBuffers = [0.15, 0.5, 0.9].map(makeCue)
        clackBuffers = [0.15, 0.5, 0.9].map(makeClack)
        cushionBuffers = [0.15, 0.5, 0.9].map(makeCushion)
        pocketBuffer = makePocket()
        scratchBuffer = makeScratch()
        winBuffer = makeWin()
        do {
            try engine.start()
            isReady = true
            engine.pause()
        } catch {
            isReady = false
        }
    }

    /// Wakes a resting engine ahead of the first sound (restarting the audio hardware can take a
    /// few hundred milliseconds, so it is done when a drag begins rather than at the hit).
    func prepare() {
        guard isReady, isEnabled else { return }
        if !engine.isRunning {
            let engine = engine
            DispatchQueue.global(qos: .userInitiated).async { try? engine.start() }
        }
        scheduleIdlePause()
    }

    func play(_ effect: Effect) {
        guard isReady, isEnabled else { return }
        let buffer: AVAudioPCMBuffer?
        switch effect {
        case .cue(let power): buffer = cueBuffers[min(2, Int(power * 3))]
        case .clack(let impact): buffer = clackBuffers[min(2, Int(impact * 3))]
        case .cushion(let impact): buffer = cushionBuffers[min(2, Int(impact * 3))]
        case .pocket: buffer = pocketBuffer
        case .scratch: buffer = scratchBuffer
        case .win: buffer = winBuffer
        }
        guard let buffer else { return }
        if !engine.isRunning { try? engine.start() }
        scheduleIdlePause()
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    private func scheduleIdlePause() {
        idlePause?.cancel()
        idlePause = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self else { return }
            for player in players { player.stop() }
            engine.pause()
        }
    }

    // MARK: - Synthesis

    private func render(duration: Double, _ sample: (Double) -> Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(duration * Self.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let channel = unsafe buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            unsafe channel[i] = Float(max(-1, min(1, sample(Double(i) / Self.sampleRate))))
        }
        return buffer
    }

    /// A leather tip on a ball: a dry, short tock with a quick click on the front.
    private func makeCue(power: Double) -> AVAudioPCMBuffer {
        var lowpass = 0.0
        return render(duration: 0.2) { t in
            let raw = Double.random(in: -1...1)
            lowpass += (raw - lowpass) * 0.3
            let click = (raw - lowpass) * exp(-t * 600) * (0.6 + 0.6 * power)
            let tock = sin(2 * Double.pi * (210 - 40 * min(1, t * 25)) * t) * exp(-t * 48) * 0.7
            return (click + tock) * (0.45 + 0.5 * power)
        }
    }

    /// Two hard balls meeting: a bright glassy click with a short ring.
    private func makeClack(impact: Double) -> AVAudioPCMBuffer {
        let base = 2300 + 700 * impact
        let ratios: [Double] = [1.0, 1.59, 2.14]
        let gains: [Double] = [1.0, 0.5, 0.3]
        var lowpass = 0.0
        return render(duration: 0.16) { t in
            let raw = Double.random(in: -1...1)
            lowpass += (raw - lowpass) * 0.2
            let click = (raw - lowpass) * exp(-t * 1100) * 0.7
            var ring = 0.0
            for k in 0..<ratios.count {
                ring += sin(2 * Double.pi * base * ratios[k] * t) * gains[k] * exp(-t * (90 + 70 * Double(k)))
            }
            let body = sin(2 * Double.pi * 520 * t) * exp(-t * 60) * 0.25
            return (click + ring * 0.3 + body) * (0.3 + 0.7 * impact)
        }
    }

    /// A ball into rubber: a soft thud.
    private func makeCushion(impact: Double) -> AVAudioPCMBuffer {
        var lowpass = 0.0
        return render(duration: 0.14) { t in
            let raw = Double.random(in: -1...1)
            lowpass += (raw - lowpass) * 0.12
            let thud = sin(2 * Double.pi * (150 + 40 * impact) * t) * exp(-t * 38) * 0.8
            return (thud + lowpass * exp(-t * 90) * 0.5) * (0.25 + 0.75 * impact)
        }
    }

    /// A ball dropping into a pocket and rolling down the chute.
    private func makePocket() -> AVAudioPCMBuffer {
        var lowpass = 0.0
        return render(duration: 0.7) { t in
            let drop = sin(2 * Double.pi * (330 - 150 * min(1, t * 6)) * t) * exp(-t * 14) * 0.55
            let raw = Double.random(in: -1...1)
            lowpass += (raw - lowpass) * 0.06
            let roll = lowpass * (t > 0.08 ? 1 : 0) * exp(-t * 4.5) * 0.5 * (0.6 + 0.4 * sin(2 * Double.pi * 17 * t))
            let knock = t > 0.34 ? sin(2 * Double.pi * 420 * (t - 0.34)) * exp(-(t - 0.34) * 45) * 0.35 : 0
            return drop + roll + knock
        }
    }

    /// The cue ball lost: a low, sad two-note drop.
    private func makeScratch() -> AVAudioPCMBuffer {
        render(duration: 0.5) { t in
            let f = t < 0.22 ? 300.0 : 225.0
            let local = t < 0.22 ? t : t - 0.22
            return (sin(2 * Double.pi * f * t) + 0.3 * sin(4 * Double.pi * f * t)) * exp(-local * 9) * 0.3
        }
    }

    /// A short, happy arpeggio.
    private func makeWin() -> AVAudioPCMBuffer {
        let notes: [(Double, Double)] = [(523.25, 0), (659.25, 0.12), (783.99, 0.24), (1046.5, 0.36)]
        return render(duration: 1.0) { t in
            var v = 0.0
            for (f, start) in notes where t >= start {
                let l = t - start
                v += (sin(2 * Double.pi * f * l) + 0.25 * sin(4 * Double.pi * f * l)) * exp(-l * 5) * 0.2
            }
            return v
        }
    }
}
