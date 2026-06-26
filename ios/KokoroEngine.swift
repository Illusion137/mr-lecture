import Foundation
import AVFoundation

// Kokoro TTS engine backed by sherpa-onnx with CoreML acceleration.
//
// Setup required before use:
//   1. Call setKokoroModel(modelPath:voicesPath:tokensPath:) with paths to
//      the downloaded model files (see downloadModel in HybridMrLecture).
//   2. The provider is set to "coreml" automatically to use Apple Neural Engine.
//      Falls back to CPU if CoreML is unavailable on the device.
//
// Model files (download via MrLecture.downloadModel('kokoro', modelId, destDir)):
//   - <name>.onnx          — acoustic model
//   - voices.bin           — speaker embeddings
//   - tokens.txt           — vocabulary
//   - espeak-ng-data/      — phonemizer data (auto-discovered if present)

#if canImport(SherpaOnnx)
import SherpaOnnx
#endif

// Known Kokoro voice table: (sidOffset, name, language)
// The SID here is the index into the model's speaker list.
// For kokoro-en-v0_19 there are 11 speakers (SID 0-10).
private let kokoroKnownVoices: [(sid: Int, name: String, language: String)] = [
    (0,  "af",           "en-US"),
    (1,  "af_bella",     "en-US"),
    (2,  "af_nicole",    "en-US"),
    (3,  "af_sarah",     "en-US"),
    (4,  "af_sky",       "en-US"),
    (5,  "am_adam",      "en-US"),
    (6,  "am_michael",   "en-US"),
    (7,  "bf_emma",      "en-GB"),
    (8,  "bf_isabella",  "en-GB"),
    (9,  "bm_george",    "en-GB"),
    (10, "bm_lewis",     "en-GB"),
]

class KokoroEngine {
    private var tts: AnyObject?
    private var modelMeta: KokoroModelMeta?
    fileprivate var audioPlayer: AVAudioPlayer?
    private let lock = NSLock()

    // MARK: - Setup

    func load(modelPath: String, voicesPath: String, tokensPath: String) throws {
        #if canImport(SherpaOnnx)
        let modelDir = URL(fileURLWithPath: modelPath).deletingLastPathComponent().path
        let dataDir = (modelDir as NSString).appendingPathComponent("espeak-ng-data")
        let resolvedDataDir = FileManager.default.fileExists(atPath: dataDir) ? dataDir : ""

        let kokoroConfig = sherpaOnnxOfflineTtsKokoroModelConfig(
            model: modelPath,
            voices: voicesPath,
            tokens: tokensPath,
            dataDir: resolvedDataDir,
            lengthScale: 1.0
        )
        let modelConfig = sherpaOnnxOfflineTtsModelConfig(
            kokoro: kokoroConfig,
            numThreads: ProcessInfo.processInfo.processorCount,
            debug: 0,
            provider: "coreml"
        )
        var config = sherpaOnnxOfflineTtsConfig(
            model: modelConfig,
            ruleFsts: "",
            maxNumSentences: 1
        )
        let instance = SherpaOnnxOfflineTtsWrapper(config: &config)
        lock.withLock {
            tts = instance
            modelMeta = KokoroModelMeta(
                id: URL(fileURLWithPath: modelPath).deletingPathExtension().lastPathComponent,
                modelPath: modelPath
            )
        }
        #else
        throw NSError(
            domain: "MrLecture",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey:
                "Kokoro engine requires sherpa-onnx. Add `pod 'SherpaOnnx', :path => './SherpaOnnx'` to your Podfile."]
        )
        #endif
    }

    // MARK: - Public API

    func getVoices() -> [VoiceInfo] {
        #if canImport(SherpaOnnx)
        guard let instance = lock.withLock({ tts }) as? SherpaOnnxOfflineTtsWrapper else { return [] }
        let count = instance.numSpeakers
        if count <= 1 {
            // Single-speaker model — return one voice using the model filename as id
            let meta = lock.withLock { modelMeta }
            let id = meta?.id ?? "kokoro"
            return [VoiceInfo(id: id, name: id, language: "en-US", quality: "high", engine: .kokoro)]
        }
        // Multi-speaker: enumerate all SIDs; use known name table where available
        return (0..<count).map { sid in
            if let entry = kokoroKnownVoices.first(where: { $0.sid == sid }) {
                return VoiceInfo(
                    id: entry.name,
                    name: entry.name,
                    language: entry.language,
                    quality: "high",
                    engine: .kokoro
                )
            }
            return VoiceInfo(
                id: "\(sid)",
                name: "Speaker \(sid)",
                language: "en-US",
                quality: "high",
                engine: .kokoro
            )
        }
        #else
        return []
        #endif
    }

    func speak(text: String, options: SpeakOptions) async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try generate(text: text, voiceId: options.voiceId, rate: options.rate, to: tempURL.path)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let player = try AVAudioPlayer(contentsOf: tempURL)
                self.audioPlayer = player
                let delegate = KokoroPlaybackDelegate(continuation: continuation, engine: self)
                player.delegate = delegate
                player.play()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func exportBatch(jobs: [ExportJob], options: ExportOptions) async throws {
        let concurrency = Int(options.concurrency ?? Double(ProcessInfo.processInfo.processorCount))
        let semaphore = AsyncSemaphore(value: concurrency)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for job in jobs {
                group.addTask {
                    await semaphore.wait()
                    let result = Result { try self.generate(text: job.text, voiceId: options.voiceId, rate: options.rate, to: job.outputPath) }
                    await semaphore.signal()
                    try result.get()
                }
            }
            try await group.waitForAll()
        }
    }

    // MARK: - Private

    private func resolve(voiceId: String?) -> Int {
        guard let vid = voiceId, !vid.isEmpty else { return 0 }
        // Check known name table first (e.g. "af_bella" → 1)
        if let entry = kokoroKnownVoices.first(where: { $0.name == vid }) {
            return entry.sid
        }
        // Fall back to integer SID string (e.g. "3")
        return Int(vid) ?? 0
    }

    private func generate(text: String, voiceId: String?, rate: Double?, to outputPath: String) throws {
        #if canImport(SherpaOnnx)
        guard let instance = lock.withLock({ tts }) as? SherpaOnnxOfflineTtsWrapper else {
            throw NSError(
                domain: "MrLecture",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Kokoro model not loaded. Call setKokoroModel() first."]
            )
        }
        let sid = resolve(voiceId: voiceId)
        let speed = Float(rate ?? 1.0)
        let audio = instance.generate(text: text, sid: sid, speed: speed)
        if audio.n <= 0 {
            throw NSError(
                domain: "MrLecture",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Kokoro synthesis produced no audio for text: \(text.prefix(80))"]
            )
        }
        let savePath = outputPath.hasPrefix("file://") ? (URL(string: outputPath)?.path ?? outputPath) : outputPath
        let ok = audio.save(filename: savePath)
        if ok != 1 {
            throw NSError(
                domain: "MrLecture",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "Failed to save audio to \(savePath)"]
            )
        }
        #else
        throw NSError(
            domain: "MrLecture",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "sherpa-onnx not available"]
        )
        #endif
    }
}

// MARK: - Model metadata

private struct KokoroModelMeta {
    let id: String
    let modelPath: String
}

// MARK: - Playback delegate

private final class KokoroPlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    let continuation: CheckedContinuation<Void, Error>
    weak var engine: KokoroEngine?

    init(continuation: CheckedContinuation<Void, Error>, engine: KokoroEngine) {
        self.continuation = continuation
        self.engine = engine
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        engine?.audioPlayer = nil
        continuation.resume()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        engine?.audioPlayer = nil
        continuation.resume(throwing: error ?? NSError(
            domain: "MrLecture",
            code: -6,
            userInfo: [NSLocalizedDescriptionKey: "Kokoro playback decode error"]
        ))
    }
}
