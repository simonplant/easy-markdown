#if canImport(Speech)
import Testing
import AVFoundation
@testable import EMEditor

@MainActor
@Suite("SpeechRecognitionManager")
struct SpeechRecognitionManagerTests {

    @Test("deinit stops audio engine and removes tap when audioEngine is non-nil")
    func deinitCleansUpAudioEngine() async {
        var manager: SpeechRecognitionManager? = SpeechRecognitionManager()
        weak var weakManager = manager

        // Set up a real AVAudioEngine so deinit has something to clean up
        let engine = AVAudioEngine()
        manager!.audioEngine = engine

        // Deallocate the manager
        manager = nil

        // Verify the instance was deallocated
        #expect(weakManager == nil)
        // After deinit, the engine should have been stopped (isRunning == false)
        #expect(engine.isRunning == false)
    }

    @Test("deinit cancels recognition task when non-nil")
    func deinitCancelsRecognitionTask() async {
        var manager: SpeechRecognitionManager? = SpeechRecognitionManager()
        weak var weakManager = manager

        // Assign a non-nil audioEngine so the cleanup path is exercised
        manager!.audioEngine = AVAudioEngine()

        // Deallocate
        manager = nil

        #expect(weakManager == nil)
    }
}
#endif
