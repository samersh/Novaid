import SwiftUI
import Metal
import MetalKit
import AVFoundation
import CoreVideo

/// Metal-based video renderer for low-latency video display
/// Based on WebRTC and Zoho Lens best practices with CVMetalTextureCache zero-copy rendering
class MetalVideoRenderer: UIView {

    // MARK: - Metal Components
    private var metalLayer: CAMetalLayer!
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var yuvPipelineState: MTLRenderPipelineState!  // For YUV textures
    private var textureCache: CVMetalTextureCache!
    private var displayLink: CADisplayLink?

    // MARK: - Video Properties
    private var currentPixelBuffer: CVPixelBuffer?
    private var currentTexture: MTLTexture?
    private let renderQueue = DispatchQueue(label: "com.novaid.metalRender")

    // Aspect ratio handling (.fit mode to show full frame)
    private var videoAspectRatio: CGFloat = 9.0 / 16.0 // Default portrait

    // MARK: - Performance Tracking
    private var frameCount: Int = 0
    private var lastFPSLog: Date = Date()

    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupMetal()
        setupDisplayLink()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMetal()
        setupDisplayLink()
    }

    // MARK: - Metal Setup
    private func setupMetal() {
        // Get default Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("[Metal] ❌ Failed to create Metal device")
            return
        }
        self.device = device

        // Create command queue
        guard let commandQueue = device.makeCommandQueue() else {
            print("[Metal] ❌ Failed to create command queue")
            return
        }
        self.commandQueue = commandQueue

        // Setup Metal layer
        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false // Allow readback for debugging
        // Note: displaySyncEnabled is macOS only. On iOS, VSync is handled via CADisplayLink
        metalLayer.maximumDrawableCount = 2 // Double buffering for lower latency
        metalLayer.frame = bounds
        layer.addSublayer(metalLayer)

        // Create CVMetalTextureCache for zero-copy rendering
        var textureCacheOut: CVMetalTextureCache?
        let result = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &textureCacheOut
        )

        if result == kCVReturnSuccess, let textureCache = textureCacheOut {
            self.textureCache = textureCache
            print("[Metal] ✅ CVMetalTextureCache created successfully")
        } else {
            print("[Metal] ❌ Failed to create CVMetalTextureCache: \(result)")
            return
        }

        // Setup render pipeline
        setupPipeline()

        print("[Metal] ✅ Metal renderer initialized successfully")
    }

    private func setupPipeline() {
        // Create shader library
        guard let library = device.makeDefaultLibrary() else {
            print("[Metal] ❌ Failed to create shader library")
            return
        }

        guard let vertexFunction = library.makeFunction(name: "vertex_main") else {
            print("[Metal] ❌ Failed to load vertex shader")
            return
        }

        // Setup BGRA pipeline (for UIImage fallback)
        if let fragmentFunction = library.makeFunction(name: "fragment_main") {
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = metalLayer.pixelFormat

            do {
                pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                print("[Metal] ✅ BGRA render pipeline created")
            } catch {
                print("[Metal] ❌ Failed to create BGRA pipeline: \(error)")
            }
        }

        // Setup YUV pipeline (for direct CVPixelBuffer from ARKit)
        if let fragmentYUVFunction = library.makeFunction(name: "fragment_yuv") {
            let yuvDescriptor = MTLRenderPipelineDescriptor()
            yuvDescriptor.vertexFunction = vertexFunction
            yuvDescriptor.fragmentFunction = fragmentYUVFunction
            yuvDescriptor.colorAttachments[0].pixelFormat = metalLayer.pixelFormat

            do {
                yuvPipelineState = try device.makeRenderPipelineState(descriptor: yuvDescriptor)
                print("[Metal] ✅ YUV render pipeline created (fixes color issues)")
            } catch {
                print("[Metal] ❌ Failed to create YUV pipeline: \(error)")
            }
        }
    }

    // MARK: - Display Link (VSync Synchronization)
    private func setupDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkCallback))
        displayLink?.preferredFramesPerSecond = 60 // Match display refresh rate
        displayLink?.add(to: .main, forMode: .common)
        print("[Metal] ✅ CADisplayLink setup for VSync synchronization")
    }

    @objc private func displayLinkCallback() {
        // Render on display refresh (vsync synchronized)
        renderFrame()
    }

    // MARK: - Public API

    /// Update with new pixel buffer (zero-copy via IOSurface)
    func updatePixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        renderQueue.async { [weak self] in
            guard let self = self else { return }
            self.currentPixelBuffer = pixelBuffer

            // Update aspect ratio based on pixel buffer dimensions
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            DispatchQueue.main.async {
                self.videoAspectRatio = CGFloat(width) / CGFloat(height)
            }
        }
    }

    /// Update with UIImage (fallback for frozen frames)
    func updateImage(_ image: UIImage) {
        // Convert UIImage to CVPixelBuffer for consistent rendering
        if let pixelBuffer = image.toPixelBuffer() {
            updatePixelBuffer(pixelBuffer)
        }
    }

    // MARK: - Rendering

    private func renderFrame() {
        renderQueue.async { [weak self] in
            guard let self = self else { return }

            guard let pixelBuffer = self.currentPixelBuffer else {
                // No frame to render yet
                return
            }

            // Get drawable from Metal layer
            guard let drawable = self.metalLayer.nextDrawable() else {
                print("[Metal] ⚠️ Failed to get next drawable")
                return
            }

            // Check pixel format and render accordingly
            let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

            if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
               pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
                // YUV bi-planar (NV12) - ARKit native format
                self.renderYUV(pixelBuffer: pixelBuffer, to: drawable)
            } else {
                // BGRA or other format - fallback
                self.renderBGRA(pixelBuffer: pixelBuffer, to: drawable)
            }

            // Track FPS
            self.frameCount += 1
            self.logFPSIfNeeded()
        }
    }

    /// Render YUV bi-planar pixel buffer (fixes blue color issue)
    private func renderYUV(pixelBuffer: CVPixelBuffer, to drawable: CAMetalDrawable) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Create Y texture (luma plane)
        var yTextureOut: CVMetalTexture?
        let yResult = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .r8Unorm,  // Single channel (Y)
            width,
            height,
            0,  // Plane 0 (Y)
            &yTextureOut
        )

        guard yResult == kCVReturnSuccess,
              let yTexture = yTextureOut,
              let yMetalTexture = CVMetalTextureGetTexture(yTexture) else {
            print("[Metal] ⚠️ Failed to create Y texture")
            return
        }

        // Create UV texture (chroma plane)
        var uvTextureOut: CVMetalTexture?
        let uvResult = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .rg8Unorm,  // Two channels (UV)
            width / 2,
            height / 2,
            1,  // Plane 1 (UV)
            &uvTextureOut
        )

        guard uvResult == kCVReturnSuccess,
              let uvTexture = uvTextureOut,
              let uvMetalTexture = CVMetalTextureGetTexture(uvTexture) else {
            print("[Metal] ⚠️ Failed to create UV texture")
            return
        }

        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("[Metal] ⚠️ Failed to create command buffer")
            return
        }

        // Create render pass descriptor
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        // Create render command encoder
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            print("[Metal] ⚠️ Failed to create render encoder")
            return
        }

        renderEncoder.setRenderPipelineState(yuvPipelineState)

        // Set YUV textures
        renderEncoder.setFragmentTexture(yMetalTexture, index: 0)  // Y plane
        renderEncoder.setFragmentTexture(uvMetalTexture, index: 1)  // UV plane

        // Draw full-screen quad
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

        renderEncoder.endEncoding()

        // Present drawable
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Render BGRA pixel buffer (fallback for UIImage)
    private func renderBGRA(pixelBuffer: CVPixelBuffer, to drawable: CAMetalDrawable) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Create Metal texture from pixel buffer
        var textureOut: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &textureOut
        )

        guard result == kCVReturnSuccess,
              let cvTexture = textureOut,
              let texture = CVMetalTextureGetTexture(cvTexture) else {
            print("[Metal] ⚠️ Failed to create BGRA texture")
            return
        }

        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("[Metal] ⚠️ Failed to create command buffer")
            return
        }

        // Create render pass descriptor
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        // Create render command encoder
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            print("[Metal] ⚠️ Failed to create render encoder")
            return
        }

        renderEncoder.setRenderPipelineState(pipelineState)

        // Set texture
        renderEncoder.setFragmentTexture(texture, index: 0)

        // Draw full-screen quad
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

        renderEncoder.endEncoding()

        // Present drawable
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Performance Monitoring

    private func logFPSIfNeeded() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFPSLog)

        if elapsed >= 2.0 {
            let fps = Double(frameCount) / elapsed
            print("[Metal] 📊 Rendering at \(String(format: "%.1f", fps)) FPS")
            frameCount = 0
            lastFPSLog = now
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        metalLayer.frame = bounds
    }

    // MARK: - Cleanup

    deinit {
        displayLink?.invalidate()
        displayLink = nil
        print("[Metal] Metal renderer cleaned up")
    }
}

// MARK: - SwiftUI Wrapper

struct MetalVideoView: UIViewRepresentable {
    @ObservedObject var multipeerService = MultipeerService.shared

    func makeUIView(context: Context) -> MetalVideoRenderer {
        let renderer = MetalVideoRenderer(frame: .zero)
        context.coordinator.renderer = renderer

        // Setup H.264 decoder for WebRTC-style low-latency video
        let videoCodec = VideoCodecService.shared
        context.coordinator.videoCodec = videoCodec

        // SPS/PPS: Initialize decoder when format description arrives (sent once at stream start)
        multipeerService.onSPSPPSReceived = { spsData, ppsData in
            print("[MetalVideoView] 🎬 Received SPS/PPS, initializing decoder...")
            let success = videoCodec.setupDecoderFromSPSPPS(spsData: spsData, ppsData: ppsData)
            if success {
                print("[MetalVideoView] ✅ Decoder initialized and ready for frames!")
            } else {
                print("[MetalVideoView] ❌ Failed to initialize decoder from SPS/PPS")
            }
        }

        // PRIMARY: H.264 compressed frames (WebRTC-style - 20-100x smaller, <200ms latency)
        multipeerService.onH264DataReceived = { h264Data in
            videoCodec.decode(data: h264Data)
        }

        // Connect decoder output to renderer
        videoCodec.onDecodedFrame = { pixelBuffer in
            renderer.updatePixelBuffer(pixelBuffer)
        }

        // FALLBACK: Direct CVPixelBuffer transmission (for backwards compatibility)
        multipeerService.onPixelBufferReceived = { pixelBuffer in
            renderer.updatePixelBuffer(pixelBuffer)
        }

        // LEGACY: UIImage frames (DEPRECATED, for backwards compatibility)
        multipeerService.onVideoFrameReceived = { image in
            renderer.updateImage(image)
        }

        multipeerService.onFrozenFrameReceived = { image in
            renderer.updateImage(image)
        }

        // ADAPTIVE STREAMING: QoS monitoring callbacks (Chalk-style)
        multipeerService.onQoSMetricsReceived = { rttMs, jitterMs, packetLossPct in
            print("[QoS] 📊 Received metrics from iPhone - RTT: \(String(format: "%.1f", rttMs))ms, " +
                  "Jitter: \(String(format: "%.1f", jitterMs))ms, " +
                  "Loss: \(String(format: "%.2f", packetLossPct))%")
        }

        multipeerService.onStreamingModeChanged = { mode in
            print("[QoS] 🎯 iPhone changed streaming mode to: \(mode)")
            // iPad can adjust UI or display mode indicator
        }

        multipeerService.onFrameMetadataReceived = { metadata in
            print("[QoS] 📸 Received frame metadata for freeze-frame mode (frameId: \(metadata.frameId))")
            // Store metadata for potential annotation on frozen frames
        }

        print("[MetalVideoView] ✅ H.264 decoder connected to Metal renderer")
        return renderer
    }

    func updateUIView(_ uiView: MetalVideoRenderer, context: Context) {
        // Updates handled by callbacks
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var renderer: MetalVideoRenderer?
        var videoCodec: VideoCodecService?
    }
}

// MARK: - UIImage Extension

extension UIImage {
    /// Convert UIImage to CVPixelBuffer for Metal rendering
    func toPixelBuffer() -> CVPixelBuffer? {
        let width = Int(size.width)
        let height = Int(size.height)

        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue!
        ] as CFDictionary

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            return nil
        }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)

        UIGraphicsPushContext(context)
        draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()

        return buffer
    }
}
