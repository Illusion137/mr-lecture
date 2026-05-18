import Foundation
import NitroModules

class HybridMrLecture: HybridMrLectureSpec {
    private let avsEngine = AVSEngine()
    private let piperEngine = PiperEngine()

    func setPiperModel(onnxPath: String, tokensPath: String) throws {
        try piperEngine.load(onnxPath: onnxPath, tokensPath: tokensPath)
    }

    func getVoices(engine: Engine) throws -> Promise<[VoiceInfo]> {
        return Promise.async {
            switch engine {
            case .avs: return self.avsEngine.getVoices()
            case .piper: return self.piperEngine.getVoices()
            }
        }
    }

    func speak(text: String, engine: Engine, options: SpeakOptions) throws -> Promise<Void> {
        return Promise.async {
            switch engine {
            case .avs: try await self.avsEngine.speak(text: text, options: options)
            case .piper: try await self.piperEngine.speak(text: text, options: options)
            }
        }
    }

    func exportBatch(jobs: [ExportJob], engine: Engine, options: ExportOptions) throws -> Promise<Void> {
        return Promise.async {
            switch engine {
            case .avs: try await self.avsEngine.exportBatch(jobs: jobs, options: options)
            case .piper: try await self.piperEngine.exportBatch(jobs: jobs, options: options)
            }
        }
    }
}
