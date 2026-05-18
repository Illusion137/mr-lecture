import { NitroModules } from 'react-native-nitro-modules'
import type { MrLecture as MrLectureSpec } from './specs/mr-lecture.nitro'

export const MrLecture = NitroModules.createHybridObject<MrLectureSpec>('MrLecture')

export type { MrLecture as MrLectureSpec } from './specs/mr-lecture.nitro'
export type {
  Engine,
  VoiceInfo,
  ExportJob,
  SpeakOptions,
  ExportOptions,
} from './specs/mr-lecture.nitro'
