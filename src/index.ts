import { NitroModules } from 'react-native-nitro-modules'
import type { MrLecture as ShumilSpec } from './specs/mr-lecture.nitro'

export const Shumil = NitroModules.createHybridObject<ShumilSpec>('MrLecture')

/** @deprecated Use {@link Shumil} instead. */
export const MrLecture = Shumil

export type { MrLecture as ShumilSpec } from './specs/mr-lecture.nitro'
export type {
  Engine,
  VoiceInfo,
  ExportJob,
  SpeakOptions,
  ExportOptions,
} from './specs/mr-lecture.nitro'
