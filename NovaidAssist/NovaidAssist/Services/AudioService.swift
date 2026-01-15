import Foundation
import AVFoundation

/// Service for capturing and playing audio during calls
@MainActor
class AudioService: ObservableObject {
    static let shared = AudioService()

    @Published var isMuted = false
    @Published var isRecording = false

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var playerNode: AVAudioPlayerNode?
    private var audioSession: AVAudioSession?

    private let audioQueue = DispatchQueue(label: "com.novaid.audioQueue")
    private var isAudioSetup = false
    private var audioFormat: AVAudioFormat?

    private init() {}

    /// Start audio capture and transmission
    func startAudioCapture() {
        audioQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                // Configure audio session
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
                try session.setActive(true)
                self.audioSession = session

                // Setup audio engine
                let engine = AVAudioEngine()
                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                self.audioFormat = format

                // Setup player node for playback
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                self.playerNode = player
                player.play()

                // Install tap to capture audio
                input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
                    guard let self = self, !self.isMuted else { return }

                    // Convert buffer to data and send
                    if let audioData = self.bufferToData(buffer: buffer) {
                        Task { @MainActor in
                            MultipeerService.shared.sendAudioData(audioData)
                        }
                    }
                }

                self.audioEngine = engine
                self.inputNode = input

                // Start engine
                try engine.start()

                Task { @MainActor in
                    self.isRecording = true
                    self.isAudioSetup = true
                    print("[Audio] Audio capture and playback started")
                }

            } catch {
                print("[Audio] Failed to start audio capture: \(error)")
            }
        }
    }

    /// Stop audio capture
    func stopAudioCapture() {
        audioQueue.async { [weak self] in
            guard let self = self else { return }

            self.playerNode?.stop()
            self.inputNode?.removeTap(onBus: 0)
            self.audioEngine?.stop()

            do {
                try self.audioSession?.setActive(false)
            } catch {
                print("[Audio] Failed to deactivate audio session: \(error)")
            }

            Task { @MainActor in
                self.isRecording = false
                self.isAudioSetup = false
                print("[Audio] Audio capture and playback stopped")
            }
        }
    }

    /// Play received audio data
    func playAudioData(_ data: Data) {
        audioQueue.async { [weak self] in
            guard let self = self,
                  let format = self.audioFormat,
                  let playerNode = self.playerNode else { return }

            // Convert data back to audio buffer
            if let buffer = self.dataToBuffer(data: data, format: format) {
                // Schedule buffer for playback
                playerNode.scheduleBuffer(buffer, completionHandler: nil)
            }
        }
    }

    /// Mute/unmute microphone
    func setMuted(_ muted: Bool) {
        isMuted = muted
        print("[Audio] Microphone \(muted ? "muted" : "unmuted")")
    }

    // MARK: - Helper Methods

    /// Convert AVAudioPCMBuffer to Data
    private func bufferToData(buffer: AVAudioPCMBuffer) -> Data? {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        let data = Data(bytes: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize))
        return data
    }

    /// Convert Data back to AVAudioPCMBuffer
    private func dataToBuffer(data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCapacity = UInt32(data.count) / format.streamDescription.pointee.mBytesPerFrame

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            return nil
        }

        buffer.frameLength = frameCapacity

        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        data.withUnsafeBytes { rawBufferPointer in
            guard let baseAddress = rawBufferPointer.baseAddress else { return }
            audioBuffer.mData?.copyMemory(from: baseAddress, byteCount: Int(audioBuffer.mDataByteSize))
        }

        return buffer
    }

    deinit {
        // Cleanup audio resources
        audioQueue.sync {
            self.playerNode?.stop()
            self.inputNode?.removeTap(onBus: 0)
            self.audioEngine?.stop()
            try? self.audioSession?.setActive(false)
        }
    }
}
