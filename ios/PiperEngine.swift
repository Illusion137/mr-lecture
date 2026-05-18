import Foundation
import AVFoundation

// Piper TTS engine backed by sherpa-onnx (https://github.com/k2-fsa/sherpa-onnx).
//
// Setup required before use:
//   1. Add sherpa-onnx to your Podfile: `pod 'sherpa-onnx', '~> 1.10'`
//      OR download the XCFramework from https://github.com/k2-fsa/sherpa-onnx/releases
//      and add it to your project manually.
//   2. Call setPiperModel(onnxPath:tokensPath:) before calling getVoices/speak/exportBatch.
//   3. Download a Piper voice model from https://huggingface.co/rhasspy/piper-voices
//      (e.g. en_US-amy-medium: onnx ~20MB + tokens.txt).
//      For models that require espeak-ng, also place the `espeak-ng-data` directory
//      alongside the .onnx file — it will be discovered automatically.

#if canImport(SherpaOnnx)
import SherpaOnnx
#endif

class PiperEngine {
    private var tts: AnyObject?     // SherpaOnnxOfflineTts — typed as AnyObject to compile without the dep
    private var modelMeta: ModelMeta?
    fileprivate var audioPlayer: AVAudioPlayer?
    private let lock = NSLock()

    // MARK: - Setup

    func load(onnxPath: String, tokensPath: String) throws {
        #if canImport(SherpaOnnx)
        let modelDir = URL(fileURLWithPath: onnxPath).deletingLastPathComponent().path
        let dataDir = (modelDir as NSString).appendingPathComponent("espeak-ng-data")
        let resolvedDataDir = FileManager.default.fileExists(atPath: dataDir) ? dataDir : ""

        let vitsConfig = sherpaOnnxOfflineTtsVitsModelConfig(
            model: onnxPath,
            lexicon: "",
            tokens: tokensPath,
            dataDir: resolvedDataDir,
            noiseScale: 0.667,
            noiseScaleW: 0.8,
            lengthScale: 1.0
        )
        let modelConfig = sherpaOnnxOfflineTtsModelConfig(
            vits: vitsConfig,
            numThreads: Int32(ProcessInfo.processInfo.processorCount),
            debug: 0,
            provider: "cpu"
        )
        let config = sherpaOnnxOfflineTtsConfig(
            model: modelConfig,
            ruleFsts: "",
            maxNumSentences: 1
        )
        let instance = SherpaOnnxOfflineTts(config: config)
        lock.withLock {
            tts = instance
            modelMeta = ModelMeta(
                id: URL(fileURLWithPath: onnxPath).deletingPathExtension().lastPathComponent,
                onnxPath: onnxPath
            )
        }
        #else
        throw NSError(
            domain: "MrLecture",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey:
                "Piper engine requires sherpa-onnx. Add `pod 'sherpa-onnx', '~> 1.10'` to your Podfile."]
        )
        #endif
    }

    // MARK: - Public API

    func getVoices() -> [VoiceInfo] {
        guard let meta = lock.withLock({ modelMeta }) else { return [] }
        return [VoiceInfo(
            id: meta.id,
            name: meta.id,
            language: inferLanguage(from: meta.id),
            quality: inferQuality(from: meta.id),
            engine: .piper
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
                let delegate = PlaybackDelegate(continuation: continuation, engine: self)
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
                    defer { semaphore.signal() }
                    try self.generate(text: job.text, rate: options.rate, to: job.outputPath)
                }
            }
            try await group.waitForAll()
        }
    }

    // MARK: - Private

    private func generate(text: String, rate: Double?, to outputPath: String) throws {
        #if canImport(SherpaOnnx)
        guard let instance = lock.withLock({ tts }) as? SherpaOnnxOfflineTts else {
            throw NSError(
                domain: "MrLecture",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Piper model not loaded. Call setPiperModel() first."]
            )
        }
        let speed = Float(rate ?? 1.0)
        guard let audio = instance.generate(text: text, sid: 0, speed: speed) else {
            throw NSError(
                domain: "MrLecture",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Piper synthesis returned nil for text: \(text.prefix(80))"]
            )
        }
        // sherpa-onnx writes a standard WAV file directly
        let ok = audio.save(filename: outputPath)
        if !ok {
            throw NSError(
                domain: "MrLecture",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "Failed to save audio to \(outputPath)"]
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

    private func inferLanguage(from modelId: String) -> String {
        // Piper model names follow pattern: lang_REGION-name-quality
        // e.g. en_US-amy-medium → en-US
        let parts = modelId.split(separator: "-", maxSplits: 1)
        guard let langPart = parts.first else { return "en-US" }
        return langPart.replacingOccurrences(of: "_", with: "-")
    }

    private func inferQuality(from modelId: String) -> String {
        if modelId.hasSuffix("-high") { return "high" }
        if modelId.hasSuffix("-medium") { return "medium" }
        return "medium"
    }
}

// MARK: - Model metadata

private struct ModelMeta {
    let id: String
    let onnxPath: String
}

// MARK: - Playback delegate

private final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    let continuation: CheckedContinuation<Void, Error>
    weak var engine: PiperEngine?

    init(continuation: CheckedContinuation<Void, Error>, engine: PiperEngine) {
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
            userInfo: [NSLocalizedDescriptionKey: "Playback decode error"]
        ))
    }
}
