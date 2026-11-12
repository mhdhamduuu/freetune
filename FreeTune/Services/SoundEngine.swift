import AVFoundation

/// Real-time audio processing chain:
///   playerNode -> 5-band EQ -> immersive reverb (widener) -> main mixer
/// Used for downloaded songs so EQ / Bass Boost / Immersive Sound are heard
/// in real time. Runs on the shared AVAudioEngine.
final class SoundEngine {
    let engine = AVAudioEngine()
    let playerNode = AVAudioPlayerNode()

    private let eq = AVAudioUnitEQ(numberOfBands: 5)
    private let reverb = AVAudioUnitReverb()
    private var attached = false
    private var connectedFormat: AVAudioFormat?

    private let bandFrequencies: [Double] = [60, 230, 910, 3600, 14000]

    var isRunning: Bool { engine.isRunning }

    /// Push current SoundSettings into the audio units (safe while playing).
    func applySettings(_ settings: SoundSettings) {
        for index in 0..<5 {
            let band = eq.bands[index]
            switch index {
            case 0: band.filterType = .lowShelf
            case 4: band.filterType = .highShelf
            default: band.filterType = .parametric
            }
            band.frequency = Float(bandFrequencies[index])
            var gain = settings.eqGains[index]
            if index == 0 { gain += settings.bassBoost }
            band.gain = Float(max(-24, min(24, gain)))
            band.bypass = false
        }
        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = settings.spatialEnabled ? 14 : 0
    }

    private func ensureChain(format: AVAudioFormat) throws {
        if !attached {
            engine.attach(playerNode)
            engine.attach(eq)
            engine.attach(reverb)
            attached = true
        }
        if connectedFormat != format {
            engine.disconnectNodeOutput(playerNode)
            engine.disconnectNodeOutput(eq)
            engine.disconnectNodeOutput(reverb)
            engine.connect(playerNode, to: eq, format: format)
            engine.connect(eq, to: reverb, format: format)
            engine.connect(reverb, to: engine.mainMixerNode, format: format)
            connectedFormat = format
        }
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    /// Schedules the file starting at `resumeAt` seconds.
    /// Returns the file duration in seconds.
    @discardableResult
    func play(fileURL: URL, resumeAt: Double, generation: Int, completion: @escaping (Int) -> Void) throws -> Double {
        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat
        try ensureChain(format: format)

        let totalFrames = AVAudioFramePosition(file.length)
        let sampleRate = format.sampleRate
        let duration = Double(totalFrames) / sampleRate

        let startFrame = AVAudioFramePosition(resumeAt * sampleRate)
        let framesRemaining = totalFrames - startFrame
        if framesRemaining <= 0 {
            return duration
        }

        playerNode.stop()
        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(framesRemaining),
            at: nil,
            completionHandler: { completion(generation) }
        )
        playerNode.play()
        return duration
    }

    func pause() {
        playerNode.pause()
    }

    func resume() {
        playerNode.play()
    }

    func stopAll() {
        playerNode.stop()
        if engine.isRunning {
            engine.stop()
        }
    }

    /// Current playback position in seconds (segment offset + node time).
    func currentPosition(segmentStart: Double) -> Double? {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0 else { return nil }
        return segmentStart + Double(playerTime.sampleTime) / playerTime.sampleRate
    }
}
