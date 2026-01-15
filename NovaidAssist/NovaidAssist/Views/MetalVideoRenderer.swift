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
        metalLayer.displaySyncEnabled = true // Enable vsync for smooth rendering
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

        guard let vertexFunction = library.makeFunction(name: "vertex_main"),
              let fragmentFunction = library.makeFunction(name: "fragment_main") else {
            print("[Metal] ❌ Failed to load shader functions")
            return
        }

        // Create render pipeline descriptor
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalLayer.pixelFormat

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            print("[Metal] ✅ Render pipeline created")
        } catch {
            print("[Metal] ❌ Failed to create pipeline state: \(error)")
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

            // Create Metal texture from pixel buffer (zero-copy via IOSurface)
            guard let texture = self.createTexture(from: pixelBuffer) else {
                print("[Metal] ⚠️ Failed to create texture from pixel buffer")
                return
            }

            // Get drawable from Metal layer
            guard let drawable = self.metalLayer.nextDrawable() else {
                print("[Metal] ⚠️ Failed to get next drawable")
                return
            }

            // Render texture to drawable
            self.render(texture: texture, to: drawable)

            // Track FPS
            self.frameCount += 1
            self.logFPSIfNeeded()
        }
    }

    private func createTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Create Metal texture from pixel buffer via CVMetalTextureCache
        // This provides zero-copy access via IOSurface
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

        if result == kCVReturnSuccess, let cvTexture = textureOut {
            return CVMetalTextureGetTexture(cvTexture)
        } else {
            print("[Metal] ⚠️ Failed to create texture: \(result)")
            return nil
        }
    }

    private func render(texture: MTLTexture, to drawable: CAMetalDrawable) {
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

        // Setup frame update callback
        multipeerService.onVideoFrameReceived = { image in
            renderer.updateImage(image)
        }

        multipeerService.onFrozenFrameReceived = { image in
            renderer.updateImage(image)
        }

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
