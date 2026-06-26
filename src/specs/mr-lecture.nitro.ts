import type { HybridObject } from 'react-native-nitro-modules'

export type Engine = 'avs' | 'piper' | 'kokoro'

export interface VoiceInfo {
  id: string
  name: string
  language: string
  quality: string
  engine: Engine
}

export interface ExportJob {
  text: string
  outputPath: string
}

export interface SpeakOptions {
  voiceId?: string
  rate?: number
}

export interface ExportOptions {
  voiceId?: string
  rate?: number
  concurrency?: number
}

export interface MrLecture extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  setPiperModel(onnxPath: string, tokensPath: string): void
  setKokoroModel(modelPath: string, voicesPath: string, tokensPath: string): void
  /** Downloads model files for 'piper' or 'kokoro'. Returns the path to the primary model file. */
  downloadModel(engine: string, modelId: string, destDir: string): Promise<string>
  /** Speaks text, auto-downloading a sample model to a temp dir if the engine isn't loaded yet. */
  sampleVoice(engine: Engine, text: string, options: SpeakOptions): Promise<void>
  getVoices(engine: Engine): Promise<VoiceInfo[]>
  speak(text: string, engine: Engine, options: SpeakOptions): Promise<void>
  exportBatch(jobs: ExportJob[], engine: Engine, options: ExportOptions): Promise<void>
}
