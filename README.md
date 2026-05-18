<div style="text-align: center;" align="center">
    <h1>mr-lecture</h1>
</div>

High-performance batch text-to-speech to file for React Native iOS, built as a [Nitro Module](https://nitro.margelo.com). Two engines behind one API — Apple's **AVSpeechSynthesizer** (zero bundle overhead, excellent quality on iOS 17+) and **Piper** via [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) (400–900× realtime, consistent across all iOS versions). Android is stubbed. The design mirrors the desktop pipeline: synthesize each chunk to a file in parallel, stitch externally with ffmpeg.

# Installation

```bash
yarn add react-native-mr-lecture react-native-nitro-modules
```

Add to your `Podfile`:

```ruby
pod 'MrLecture', :path => '../mr-lecture'
```

Then run `pod install`.

For the **Piper engine** only, also add `sherpa-onnx` to your Podfile:

```ruby
pod 'sherpa-onnx', '~> 1.10'
```

# API

```typescript
import { MrLecture } from 'react-native-mr-lecture'
import type { Engine, VoiceInfo, ExportJob, SpeakOptions, ExportOptions } from 'react-native-mr-lecture'

// AVS engine — no setup required
// Piper engine — call once before use
MrLecture.setPiperModel('/path/to/model.onnx', '/path/to/tokens.txt')

// List installed voices
const voices: VoiceInfo[] = await MrLecture.getVoices('avs')
const piperVoices: VoiceInfo[] = await MrLecture.getVoices('piper')

// Live playback
await MrLecture.speak('Hello world', 'avs', { voiceId: 'com.apple.voice.enhanced.en-US.Zoe', rate: 1.0 })

// Batch export to files (the fast path)
const jobs: ExportJob[] = paragraphs.map((text, i) => ({
  text,
  outputPath: `/tmp/chunk_${i}.caf`,
}))
await MrLecture.exportBatch(jobs, 'avs', { concurrency: 6 })
```

### Options

| Field | Type | Default | Description |
|---|---|---|---|
| `voiceId` | `string` | system default | Voice identifier from `getVoices()` |
| `rate` | `number` | `1.0` | Speed multiplier (0.5 – 2.0) |
| `concurrency` | `number` | `min(8, cpuCount)` | Max parallel synthesis workers (`exportBatch` only) |

### VoiceInfo

```typescript
interface VoiceInfo {
  id: string        // pass back as voiceId
  name: string
  language: string  // e.g. "en-US"
  quality: string   // "default" | "enhanced" | "premium"  (avs)
                    // "medium"  | "high"                  (piper)
  engine: Engine    // "avs" | "piper"
}
```

# Piper Setup

1. Download a voice from [rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices), e.g. `en_US-amy-medium` (~20 MB) or `en_US-ryan-high` (~68 MB).
2. Each model ships as two files: `<name>.onnx` and `tokens.txt`. Place them somewhere accessible on the device (Documents, cache dir, etc.).
3. If the model requires espeak-ng phonemization, place the `espeak-ng-data/` directory alongside the `.onnx` file — it is discovered automatically.

```typescript
const modelPath = `${RNFS.DocumentDirectoryPath}/en_US-amy-medium.onnx`
const tokensPath = `${RNFS.DocumentDirectoryPath}/tokens.txt`
MrLecture.setPiperModel(modelPath, tokensPath)
```

# Codegen

If you modify the TypeScript spec (`src/specs/mr-lecture.nitro.ts`), regenerate native bridges with:

```bash
yarn codegen
```

This runs `nitrogen` and rebuilds the TypeScript output. Re-run `pod install` in your app after.
