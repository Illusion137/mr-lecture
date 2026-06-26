import Foundation

// Downloads TTS model files (Piper or Kokoro) from HuggingFace/sherpa-onnx
// to a caller-supplied directory.
//
// Models are sourced from the csukuangfj sherpa-onnx HuggingFace repos:
//   Piper: https://huggingface.co/csukuangfj/vits-piper-{lang}-{name}-{quality}
//   Kokoro: https://huggingface.co/csukuangfj/kokoro-en-v0_19
//
// The "sample cache" lives at <tmpDir>/shumil-sample/<engine>/<modelId>/ so
// that sampleVoice() can reuse a previous temp download, and downloadModel()
// can promote it to a permanent location instead of fetching again.

struct ModelDownloader {

    // MARK: - Public entry points

    /// Downloads all files for a Piper model (onnx + tokens.txt).
    /// - Parameter modelId: e.g. "en-US-ryan-low" or "en-US-amy-medium"
    /// - Returns: path to the .onnx file inside destDir
    static func downloadPiper(modelId: String, destDir: String) async throws -> String {
        let dir = URL(fileURLWithPath: destDir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let (base, onnxName) = piperURLs(modelId: modelId)

        let onnxDest = dir.appendingPathComponent(onnxName)
        let tokensDest = dir.appendingPathComponent("tokens.txt")

        if !FileManager.default.fileExists(atPath: onnxDest.path) {
            try await downloadFile(from: base + onnxName, to: onnxDest)
        }
        if !FileManager.default.fileExists(atPath: tokensDest.path) {
            try await downloadFile(from: base + "tokens.txt", to: tokensDest)
        }

        return onnxDest.path
    }

    /// Downloads all files for a Kokoro model (model.onnx + voices.bin + tokens.txt).
    /// - Parameter modelId: e.g. "kokoro-en-v0_19" (default if empty)
    /// - Returns: path to model.onnx inside destDir
    static func downloadKokoro(modelId: String, destDir: String) async throws -> String {
        let id = modelId.isEmpty ? "kokoro-en-v0_19" : modelId
        let dir = URL(fileURLWithPath: destDir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let base = "https://huggingface.co/csukuangfj/\(id)/resolve/main/"
        let modelDest = dir.appendingPathComponent("model.onnx")
        let voicesDest = dir.appendingPathComponent("voices.bin")
        let tokensDest = dir.appendingPathComponent("tokens.txt")

        if !FileManager.default.fileExists(atPath: modelDest.path) {
            try await downloadFile(from: base + "model.onnx", to: modelDest)
        }
        if !FileManager.default.fileExists(atPath: voicesDest.path) {
            try await downloadFile(from: base + "voices.bin", to: voicesDest)
        }
        if !FileManager.default.fileExists(atPath: tokensDest.path) {
            try await downloadFile(from: base + "tokens.txt", to: tokensDest)
        }

        return modelDest.path
    }

    // MARK: - Sample cache helpers

    /// Path used by sampleVoice() for temporary model storage.
    static func sampleCacheDir(engine: String, modelId: String) -> String {
        let tmp = FileManager.default.temporaryDirectory
        return tmp
            .appendingPathComponent("shumil-sample")
            .appendingPathComponent(engine)
            .appendingPathComponent(modelId)
            .path
    }

    /// Moves the sample-cache directory for (engine, modelId) into destDir,
    /// returning the primary model path. Falls back to false if not cached.
    static func promoteFromSampleCache(engine: String, modelId: String, destDir: String) -> String? {
        let cacheDir = sampleCacheDir(engine: engine, modelId: modelId)
        guard FileManager.default.fileExists(atPath: cacheDir) else { return nil }
        let dest = URL(fileURLWithPath: destDir)
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            // Move each file individually so we don't clobber existing files in destDir
            let items = try FileManager.default.contentsOfDirectory(atPath: cacheDir)
            for item in items {
                let src = URL(fileURLWithPath: cacheDir).appendingPathComponent(item)
                let dst = dest.appendingPathComponent(item)
                if FileManager.default.fileExists(atPath: dst.path) {
                    try FileManager.default.removeItem(at: dst)
                }
                try FileManager.default.moveItem(at: src, to: dst)
            }
            try? FileManager.default.removeItem(atPath: cacheDir)
        } catch {
            return nil
        }
        // Return primary model file path
        if engine == "kokoro" {
            return dest.appendingPathComponent("model.onnx").path
        } else {
            // Piper: find the .onnx file
            let items = (try? FileManager.default.contentsOfDirectory(atPath: dest.path)) ?? []
            if let onnx = items.first(where: { $0.hasSuffix(".onnx") }) {
                return dest.appendingPathComponent(onnx).path
            }
        }
        return nil
    }

    // MARK: - Private helpers

    private static func piperURLs(modelId: String) -> (base: String, onnxName: String) {
        // modelId e.g. "en-US-ryan-low" → repo "csukuangfj/vits-piper-en-US-ryan-low"
        let repoName = "vits-piper-\(modelId)"
        let base = "https://huggingface.co/csukuangfj/\(repoName)/resolve/main/"
        let onnxName = "\(modelId).onnx"
        return (base, onnxName)
    }

    private static func downloadFile(from urlString: String, to dest: URL) async throws {
        guard let url = URL(string: urlString) else {
            throw NSError(
                domain: "MrLecture",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "Invalid download URL: \(urlString)"]
            )
        }

        let (tmpURL, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(
                domain: "MrLecture",
                code: -11,
                userInfo: [NSLocalizedDescriptionKey: "Download failed (\(http.statusCode)): \(urlString)"]
            )
        }

        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tmpURL, to: dest)
    }
}
