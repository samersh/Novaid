import Foundation
import AVFoundation

/// Service for capturing and playing audio during calls
/// Enhanced with better format handling and buffer management
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
    private var inputFormat: AVAudioFormat?

    // Standard format for transmission (16kHz mono for voice, lower bandwidth)
    private let transmissionSampleRate: Double = 16000
    private let transmissionChannels: UInt32 = 1

    // Converter for format conversion
    private var converter: AVAudioConverter?

    private init() {}

    /// Start audio capture and transmission
    func startAudioCapture() {
        print("[Audio] Starting audio capture...")

        audioQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                // Check microphone permission
                let permissionStatus = AVAudioSession.sharedInstance().recordPermission
                print("[Audio] Microphone permission status: \(permissionStatus.rawValue)")

                if permissionStatus == .denied {
                    print("[Audio] ERROR: Microphone permission denied!")
                    return
                } else if permissionStatus == .undetermined {
                    print("[Audio] Requesting microphone permission...")
                    AVAudioSession.sharedInstance().requestRecordPermission { granted in
                        print("[Audio] Microphone permission granted: \(granted)")
                        if granted {
                            // Retry starting audio
                            self.startAudioCapture()
                        }
                    }
                    return
                }

                // Configure audio session
                print("[Audio] Configuring audio session...")
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
                try session.setActive(true)
                self.audioSession = session
                print("[Audio] Audio session activated")

                // Setup audio engine
                print("[Audio] Setting up audio engine...")
                let engine = AVAudioEngine()
                let input = engine.inputNode
                let inputFormat = input.outputFormat(forBus: 0)
                self.inputFormat = inputFormat
                print("[Audio] Input Format - Sample Rate: \(inputFormat.sampleRate), Channels: \(inputFormat.channelCount)")

                // Create standard transmission format (16kHz mono PCM)
                guard let transmissionFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: self.transmissionSampleRate,
                    channels: self.transmissionChannels,
                    interleaved: false
                ) else {
                    print("[Audio] ❌ Failed to create transmission format")
                    return
                }
                print("[Audio] Transmission Format - Sample Rate: \(transmissionFormat.sampleRate), Channels: \(transmissionFormat.channelCount)")

                // Create converter for format conversion
                guard let converter = AVAudioConverter(from: inputFormat, to: transmissionFormat) else {
                    print("[Audio] ❌ Failed to create audio converter")
                    return
                }
                self.converter = converter
                print("[Audio] ✅ Audio converter created")

                // Setup player node for playback (use transmission format for consistency)
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: transmissionFormat)
                self.playerNode = player
                player.play()
                print("[Audio] Player node attached and started with transmission format")

                // Install tap to capture audio - convert and send
                input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
                    guard let self = self, !self.isMuted else { return }

                    // Convert to transmission format and send
                    if let convertedBuffer = self.convertBuffer(buffer, using: converter, to: transmissionFormat),
                       let audioData = self.bufferToData(buffer: convertedBuffer, format: transmissionFormat) {
                        Task { @MainActor in
                            MultipeerService.shared.sendAudioData(audioData)
                        }
                    }
                }
                print("[Audio] Audio tap installed - capturing and converting audio")

                self.audioEngine = engine
                self.inputNode = input

                // Start engine
                try engine.start()
                print("[Audio] Audio engine started successfully")

                Task { @MainActor in
                    self.isRecording = true
                    self.isAudioSetup = true
                    print("[Audio] ✅ Audio capture and playback started")
                }

            } catch {
                print("[Audio] ❌ Failed to start audio capture: \(error.localizedDescription)")
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
            guard let self = self else { return }

            guard let playerNode = self.playerNode else {
                print("[Audio] ⚠️ Player node not ready")
                return
            }

            // Create transmission format (must match sender's format)
            guard let transmissionFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: self.transmissionSampleRate,
                channels: self.transmissionChannels,
                interleaved: false
            ) else {
                print("[Audio] ⚠️ Failed to create playback format")
                return
            }

            // Convert data back to audio buffer using transmission format
            if let buffer = self.dataToBuffer(data: data, format: transmissionFormat) {
                // Schedule buffer for immediate playback
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

    /// Convert audio buffer to standard transmission format
    private func convertBuffer(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Calculate output frame capacity
        let inputFrameCount = buffer.frameLength
        let ratio = format.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = UInt32(Double(inputFrameCount) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputFrameCapacity) else {
            print("[Audio] ⚠️ Failed to create output buffer")
            return nil
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if status == .error {
            print("[Audio] ⚠️ Conversion error: \(error?.localizedDescription ?? "unknown")")
            return nil
        }

        return outputBuffer
    }

    /// Convert AVAudioPCMBuffer to Data with format info
    private func bufferToData(buffer: AVAudioPCMBuffer, format: AVAudioFormat) -> Data? {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        guard let mData = audioBuffer.mData else {
            print("[Audio] ⚠️ No data in audio buffer")
            return nil
        }

        let data = Data(bytes: mData, count: Int(audioBuffer.mDataByteSize))
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
