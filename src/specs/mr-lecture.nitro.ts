import type { HybridObject } from 'react-native-nitro-modules'

export type Engine = 'avs' | 'piper'

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
  getVoices(engine: Engine): Promise<VoiceInfo[]>
  speak(text: string, engine: Engine, options: SpeakOptions): Promise<void>
  exportBatch(jobs: ExportJob[], engine: Engine, options: ExportOptions): Promise<void>
}
