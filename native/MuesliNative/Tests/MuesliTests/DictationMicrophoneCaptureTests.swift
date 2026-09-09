import Foundation
import Testing
@testable import MuesliNativeApp

@Suite("DictationMicrophoneCapture")
struct DictationMicrophoneCaptureTests {
    @Test("dictation captures through voice processing first, raw audio queue as fallback")
    func dictationPrefersVoiceProcessedCapture() {
        let recorder = FallbackStreamingDictationRecorder.dictationMicrophone(directoryName: "muesli-test-dictation")

        let primary = recorder.primaryRecorderForDebug as? StreamingMicRecorder
        #expect(primary != nil)
        #expect(primary?.enablesVoiceProcessing == true)
        #expect(recorder.fallbackRecorderForDebug is AudioQueueInputRecorder)
    }

    @Test("meeting microphone capture stays raw")
    func meetingCaptureDoesNotEnableVoiceProcessing() {
        let recorder = StreamingMicRecorder(directoryName: "muesli-test-meeting")
        #expect(recorder.enablesVoiceProcessing == false)
    }
}
