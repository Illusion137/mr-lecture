package com.mrlecture

import com.margelo.nitro.mrlecture.Engine
import com.margelo.nitro.mrlecture.ExportJob
import com.margelo.nitro.mrlecture.ExportOptions
import com.margelo.nitro.mrlecture.HybridMrLectureSpec
import com.margelo.nitro.mrlecture.SpeakOptions
import com.margelo.nitro.mrlecture.VoiceInfo
import com.margelo.nitro.core.Promise

class HybridMrLecture : HybridMrLectureSpec() {

    override fun setPiperModel(onnxPath: String, tokensPath: String) {
        throw UnsupportedOperationException("mr-lecture: Android not implemented")
    }

    override fun getVoices(engine: Engine): Promise<Array<VoiceInfo>> {
        throw UnsupportedOperationException("mr-lecture: Android not implemented")
    }

    override fun speak(text: String, engine: Engine, options: SpeakOptions): Promise<Unit> {
        throw UnsupportedOperationException("mr-lecture: Android not implemented")
    }

    override fun exportBatch(jobs: Array<ExportJob>, engine: Engine, options: ExportOptions): Promise<Unit> {
        throw UnsupportedOperationException("mr-lecture: Android not implemented")
    }
}
