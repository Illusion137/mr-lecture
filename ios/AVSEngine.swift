import Foundation
import AVFoundation

// Bounded parallel worker pool for AVSpeechSynthesizer export jobs.
// AVSpeechSynthesizer.write() is asynchronous and fires callbacks on a background thread.
// Each job creates its own synthesizer instance to avoid delegate collision.
class AVSEngine {

    // MARK: - Public API

    func getVoices() -> [VoiceInfo] {
        return AVSpeechSynthesisVoice.speechVoices()
            .sorted { qualityRank($0.quality) > qualityRank($1.quality) }
            .map { voice in
                VoiceInfo(
                    id: voice.identifier,
                    name: voice.name,
                    language: voice.language,
                    quality: qualityString(voice.quality),
                    engine: .avs
                )
            }
    }

    func speak(text: String, options: SpeakOptions) async throws {
        let session = SynthesisSession()
        let utterance = makeUtterance(text: text, voiceId: options.voiceId, rate: options.rate)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = LiveSpeakDelegate(continuation: continuation)
            session.synthesizer.delegate = delegate
            delegate.session = session  // keeps both alive until didFinish fires
            session.synthesizer.speak(utterance)
        }
    }

    func exportBatch(jobs: [ExportJob], options: ExportOptions) async throws {
        let maxConcurrency = Int(options.concurrency ?? Double(min(8, ProcessInfo.processInfo.processorCount)))
        let semaphore = AsyncSemaphore(value: maxConcurrency)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for job in jobs {
                group.addTask {
                    await semaphore.wait()
                    defer { semaphore.signal() }
                    try await self.exportOne(
                        text: job.text,
                        outputPath: job.outputPath,
                        voiceId: options.voiceId,
                        rate: options.rate
                    )
                }
            }
            try await group.waitForAll()
        }
    }

    // MARK: - Private

    private func exportOne(text: String, outputPath: String, voiceId: String?, rate: Double?) async throws {
        let session = SynthesisSession()
        let utterance = makeUtterance(text: text, voiceId: voiceId, rate: rate)
        let url = URL(fileURLWithPath: outputPath)

        // session is captured strongly by both the coroutine frame (local var) and the closure,
        // ensuring the synthesizer stays alive until the empty-buffer completion signal.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.synthesizer.write(utterance) { [session] buffer in
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

                if pcmBuffer.frameLength == 0 {
                    // Empty buffer = synthesis complete
                    guard !session.resumed else { return }
                    session.resumed = true
                    if let err = session.writeError {
                        continuation.resume(throwing: err)
                    } else {
                        continuation.resume()
                    }
                    return
                }

                if session.audioFile == nil {
                    do {
                        session.audioFile = try AVAudioFile(forWriting: url, settings: pcmBuffer.format.settings)
                    } catch {
                        session.writeError = error
                        return
                    }
                }

                if session.writeError == nil {
                    do {
                        try session.audioFile?.write(from: pcmBuffer)
                    } catch {
                        session.writeError = error
                    }
                }
            }
        }
    }

    private func makeUtterance(text: String, voiceId: String?, rate: Double?) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        let multiplier = Float(rate ?? 1.0)
        utterance.rate = min(
            AVSpeechUtteranceMaximumSpeechRate,
            max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * multiplier)
        )
        if let vid = voiceId, !vid.isEmpty {
            utterance.voice = AVSpeechSynthesisVoice(identifier: vid)
        }
        return utterance
    }

    private func qualityRank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium: return 2
        case .enhanced: return 1
        default: return 0
        }
    }

    private func qualityString(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: return "premium"
        case .enhanced: return "enhanced"
        default: return "default"
        }
    }
}

// MARK: - Synthesis session (carries state across the async callback boundary)

private final class SynthesisSession {
    let synthesizer = AVSpeechSynthesizer()
    var audioFile: AVAudioFile?
    var writeError: Error?
    var resumed = false
}

// MARK: - Delegate for live speak (keeps session + synthesizer alive until playback finishes)

private final class LiveSpeakDelegate: NSObject, AVSpeechSynthesizerDelegate {
    let continuation: CheckedContinuation<Void, Error>
    var session: SynthesisSession?  // strong ref breaks after resume

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        session = nil
        continuation.resume()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        session = nil
        continuation.resume(throwing: NSError(
            domain: "MrLecture",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Speech cancelled"]
        ))
    }
}

// MARK: - Async semaphore (DispatchSemaphore blocks the thread; this suspends the Task instead)

actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = value
    }

    func wait() async {
        if value > 0 {
            value -= 1
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    func signal() {
        if waiters.isEmpty {
            value += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
