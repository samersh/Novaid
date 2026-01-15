import Foundation
import CoreVideo
import Accelerate

/// Service for efficient CVPixelBuffer transmission
/// Direct pixel data transmission without JPEG conversion for lower latency and proper color handling
class PixelBufferTransmissionService {

    // MARK: - Encoding (Sender)

    /// Serialize CVPixelBuffer to Data for transmission
    /// This preserves native YUV format and avoids color space conversions
    static func encodePixelBuffer(_ pixelBuffer: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        // Create header with metadata
        var header = PixelBufferHeader(
            width: Int32(width),
            height: Int32(height),
            pixelFormat: pixelFormat,
            planeCount: Int32(CVPixelBufferGetPlaneCount(pixelBuffer))
        )

        var data = Data()

        // Append header
        withUnsafeBytes(of: &header) { headerBytes in
            data.append(contentsOf: headerBytes)
        }

        // Handle planar vs non-planar formats
        if CVPixelBufferIsPlanar(pixelBuffer) {
            // YUV planar format (e.g., 420v, 420f)
            let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)

            for plane in 0..<planeCount {
                guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane) else {
                    print("[PixelBuffer] ❌ Failed to get plane \(plane) base address")
                    return nil
                }

                let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)
                let planeHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
                let planeSize = bytesPerRow * planeHeight

                // Append plane data
                data.append(Data(bytes: baseAddress, count: planeSize))
            }
        } else {
            // Non-planar format (e.g., BGRA)
            guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                print("[PixelBuffer] ❌ Failed to get base address")
                return nil
            }

            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
            let bufferSize = bytesPerRow * bufferHeight

            data.append(Data(bytes: baseAddress, count: bufferSize))
        }

        return data
    }

    // MARK: - Decoding (Receiver)

    /// Deserialize Data back to CVPixelBuffer
    static func decodePixelBuffer(from data: Data) -> CVPixelBuffer? {
        // Extract header
        let headerSize = MemoryLayout<PixelBufferHeader>.size
        guard data.count > headerSize else {
            print("[PixelBuffer] ❌ Data too small for header")
            return nil
        }

        var header = PixelBufferHeader(width: 0, height: 0, pixelFormat: 0, planeCount: 0)
        _ = withUnsafeMutableBytes(of: &header) { headerBytes in
            data.copyBytes(to: headerBytes, from: 0..<headerSize)
        }

        let width = Int(header.width)
        let height = Int(header.height)
        let pixelFormat = header.pixelFormat

        // Create pixel buffer
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any],
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            print("[PixelBuffer] ❌ Failed to create pixel buffer: \(status)")
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        var offset = headerSize

        // Copy data back into pixel buffer
        if CVPixelBufferIsPlanar(buffer) {
            let planeCount = CVPixelBufferGetPlaneCount(buffer)

            for plane in 0..<planeCount {
                guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(buffer, plane) else {
                    print("[PixelBuffer] ❌ Failed to get plane \(plane) base address")
                    return nil
                }

                let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane)
                let planeHeight = CVPixelBufferGetHeightOfPlane(buffer, plane)
                let planeSize = bytesPerRow * planeHeight

                guard offset + planeSize <= data.count else {
                    print("[PixelBuffer] ❌ Not enough data for plane \(plane)")
                    return nil
                }

                data.copyBytes(to: baseAddress.assumingMemoryBound(to: UInt8.self), from: offset..<(offset + planeSize))
                offset += planeSize
            }
        } else {
            guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
                print("[PixelBuffer] ❌ Failed to get base address")
                return nil
            }

            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            let bufferHeight = CVPixelBufferGetHeight(buffer)
            let bufferSize = bytesPerRow * bufferHeight

            guard offset + bufferSize <= data.count else {
                print("[PixelBuffer] ❌ Not enough data for buffer")
                return nil
            }

            data.copyBytes(to: baseAddress.assumingMemoryBound(to: UInt8.self), from: offset..<(offset + bufferSize))
        }

        return buffer
    }
}

// MARK: - Header Structure

/// Metadata for transmitted pixel buffer
struct PixelBufferHeader {
    let width: Int32
    let height: Int32
    let pixelFormat: OSType  // CVPixelFormatType
    let planeCount: Int32
}
