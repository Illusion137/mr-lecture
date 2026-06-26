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
        guard let meta = lock.withLock({ modelMeta }) else { return [] }
        return [VoiceInfo(
            id: meta.id,
            name: meta.id,
            language: "en-US",
            quality: "high",
            engine: .kokoro
        )]
    }

    func speak(text: String, options: SpeakOptions) async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try generate(text: text, rate: options.rate, to: tempURL.path)

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
                    let result = Result { try self.generate(text: job.text, rate: options.rate, to: job.outputPath) }
                    await semaphore.signal()
                    try result.get()
                }
            }
            try await group.waitForAll()
        }
    }

    // MARK: - Private

    private func generate(text: String, rate: Double?, to outputPath: String) throws {
        #if canImport(SherpaOnnx)
        guard let instance = lock.withLock({ tts }) as? SherpaOnnxOfflineTtsWrapper else {
            throw NSError(
                domain: "MrLecture",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Kokoro model not loaded. Call setKokoroModel() first."]
            )
        }
        let speed = Float(rate ?? 1.0)
        let audio = instance.generate(text: text, sid: 0, speed: speed)
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
