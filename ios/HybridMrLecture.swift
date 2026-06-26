import Foundation
import NitroModules

class HybridMrLecture: HybridMrLectureSpec {
    private let avsEngine = AVSEngine()
    private let piperEngine = PiperEngine()
    private let kokoroEngine = KokoroEngine()

    // MARK: - Model setup

    func setPiperModel(onnxPath: String, tokensPath: String) throws {
        try piperEngine.load(onnxPath: onnxPath, tokensPath: tokensPath)
    }

    func setKokoroModel(modelPath: String, voicesPath: String, tokensPath: String) throws {
        try kokoroEngine.load(modelPath: modelPath, voicesPath: voicesPath, tokensPath: tokensPath)
    }

    // MARK: - Model download

    func downloadModel(engine: String, modelId: String, destDir: String) throws -> Promise<String> {
        return Promise.async {
            // Promote from sample cache first (avoids re-download if sampleVoice ran first)
            if let cached = ModelDownloader.promoteFromSampleCache(engine: engine, modelId: modelId, destDir: destDir) {
                return cached
            }
            switch engine {
            case "piper":
                return try await ModelDownloader.downloadPiper(modelId: modelId, destDir: destDir)
            case "kokoro":
                return try await ModelDownloader.downloadKokoro(modelId: modelId, destDir: destDir)
            default:
                throw NSError(
                    domain: "MrLecture",
                    code: -20,
                    userInfo: [NSLocalizedDescriptionKey: "downloadModel: unknown engine '\(engine)'. Use 'piper' or 'kokoro'."]
                )
            }
        }
    }

    // MARK: - Sample voice

    func sampleVoice(engine: Engine, text: String, options: SpeakOptions) throws -> Promise<Void> {
        return Promise.async {
            switch engine {
            case .avs:
                try await self.avsEngine.speak(text: text, options: options)

            case .piper:
                // Use loaded model if available, otherwise fetch a lightweight sample model
                if self.piperEngine.getVoices().isEmpty {
                    let sampleModelId = "en-US-ryan-low"
                    let cacheDir = ModelDownloader.sampleCacheDir(engine: "piper", modelId: sampleModelId)
                    let onnxPath = try await ModelDownloader.downloadPiper(modelId: sampleModelId, destDir: cacheDir)
                    let tokensPath = (onnxPath as NSString).deletingLastPathComponent + "/tokens.txt"
                    try self.piperEngine.load(onnxPath: onnxPath, tokensPath: tokensPath)
                }
                try await self.piperEngine.speak(text: text, options: options)

            case .kokoro:
                if self.kokoroEngine.getVoices().isEmpty {
                    let sampleModelId = "kokoro-en-v0_19"
                    let cacheDir = ModelDownloader.sampleCacheDir(engine: "kokoro", modelId: sampleModelId)
                    let modelPath = try await ModelDownloader.downloadKokoro(modelId: sampleModelId, destDir: cacheDir)
                    let voicesPath = (modelPath as NSString).deletingLastPathComponent + "/voices.bin"
                    let tokensPath = (modelPath as NSString).deletingLastPathComponent + "/tokens.txt"
                    try self.kokoroEngine.load(modelPath: modelPath, voicesPath: voicesPath, tokensPath: tokensPath)
                }
                try await self.kokoroEngine.speak(text: text, options: options)
            }
        }
    }

    // MARK: - Voices

    func getVoices(engine: Engine) throws -> Promise<[VoiceInfo]> {
        return Promise.async {
            switch engine {
            case .avs: return self.avsEngine.getVoices()
            case .piper: return self.piperEngine.getVoices()
            case .kokoro: return self.kokoroEngine.getVoices()
            }
        }
    }

    // MARK: - Speak

    func speak(text: String, engine: Engine, options: SpeakOptions) throws -> Promise<Void> {
        return Promise.async {
            switch engine {
            case .avs: try await self.avsEngine.speak(text: text, options: options)
            case .piper: try await self.piperEngine.speak(text: text, options: options)
            case .kokoro: try await self.kokoroEngine.speak(text: text, options: options)
            }
        }
    }

    // MARK: - Batch export

    func exportBatch(jobs: [ExportJob], engine: Engine, options: ExportOptions) throws -> Promise<Void> {
        return Promise.async {
            switch engine {
            case .avs: try await self.avsEngine.exportBatch(jobs: jobs, options: options)
            case .piper: try await self.piperEngine.exportBatch(jobs: jobs, options: options)
            case .kokoro: try await self.kokoroEngine.exportBatch(jobs: jobs, options: options)
            }
        }
    }
}
