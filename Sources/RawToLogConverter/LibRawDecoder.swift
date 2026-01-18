//
// LibRawDecoder.swift
// Swift wrapper for LibRaw XYZ decoding
//

import Foundation
import Metal
import simd
import LibRawBridge

// MARK: - Errors

enum LibRawError: Error, LocalizedError {
    case decodeFailed(String)
    case metalBufferCreationFailed
    case fileNotFound
    
    var errorDescription: String? {
        switch self {
        case .decodeFailed(let message):
            return "LibRaw decode failed: \(message)"
        case .metalBufferCreationFailed:
            return "Failed to create Metal buffer"
        case .fileNotFound:
            return "RAW file not found"
        }
    }
}

// MARK: - Result Structure

/// Decoded XYZ image from LibRaw
struct LibRawImage {
    /// Image width in pixels
    let width: Int
    /// Image height in pixels
    let height: Int
    /// XYZ pixel data as Metal buffer (Float32 - pure, no WB baked)
    let xyzBuffer: MTLBuffer
    /// Bytes per row
    let bytesPerRow: Int
    /// DNG BaselineExposure in EV (0 if not available)
    let baselineExposure: Float
    /// True if baselineExposure was read from DNG metadata
    let hasBaselineExposure: Bool
    /// Camera white balance multipliers (R, G, B) - normalized so G=1.0
    let wbMultipliers: simd_float3
    /// Estimated color temperature in Kelvin (from camera metadata)
    let colorTemperature: Float
}

// MARK: - Decoder

/// LibRaw-based RAW decoder outputting linear XYZ (D65)
class LibRawXYZDecoder {
    
    private let device: MTLDevice
    
    init(device: MTLDevice) {
        self.device = device
    }
    
    /// Decode RAW file to linear XYZ color space
    /// - Parameter url: Path to RAW file
    /// - Returns: LibRawImage with XYZ data in Metal buffer
    func decode(url: URL) throws -> LibRawImage {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LibRawError.fileNotFound
        }
        
        // Call C bridge function
        var result = url.path.withCString { path in
            libraw_decode_to_xyz(path)
        }
        
        // Ensure cleanup
        defer {
            libraw_free_result(&result)
        }
        
        // Check for errors
        guard result.success else {
            let errorMsg = withUnsafePointer(to: &result.errorMessage) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 256) { cString in
                    String(cString: cString)
                }
            }
            throw LibRawError.decodeFailed(errorMsg)
        }
        
        // Convert uint16 XYZ data to Float32 and upload to GPU
        // Using Float32 instead of Float16 to preserve full 16-bit RAW precision
        // Float16 only has 11-bit mantissa = 2048 levels vs 65536 levels in RAW
        let pixelCount = Int(result.width) * Int(result.height) * 3
        let bufferSize = pixelCount * MemoryLayout<Float>.size  // Float32
        
        guard let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            throw LibRawError.metalBufferCreationFailed
        }
        
        // Convert uint16 normalized to Float32 (preserves full precision)
        let srcPtr = result.data!
        let dstPtr = buffer.contents().bindMemory(to: Float.self, capacity: pixelCount)
        
        // Parallel conversion for performance
        DispatchQueue.concurrentPerform(iterations: pixelCount / 1024 + 1) { block in
            let start = block * 1024
            let end = min(start + 1024, pixelCount)
            for i in start..<end {
                dstPtr[i] = Float(srcPtr[i]) / 65535.0
            }
        }
        
        print("📸 LibRaw: Decoded \(result.width)×\(result.height) to XYZ (D65) [Float32] - NO WB BAKED")
        
        // Extract WB multipliers for GPU application
        let wbMultipliers = simd_float3(
            result.wbMultipliers.0,
            result.wbMultipliers.1,
            result.wbMultipliers.2
        )
        print("🎨 Camera WB: R=\(String(format: "%.3f", wbMultipliers.x)) G=\(String(format: "%.3f", wbMultipliers.y)) B=\(String(format: "%.3f", wbMultipliers.z)) (~\(Int(result.colorTemperature))K)")
        
        // Log baseline exposure if available
        if result.hasBaselineExposure {
            print("📊 DNG BaselineExposure: \(String(format: "%+.2f", result.baselineExposure)) EV")
        }
        
        return LibRawImage(
            width: Int(result.width),
            height: Int(result.height),
            xyzBuffer: buffer,
            bytesPerRow: Int(result.width) * 3 * MemoryLayout<Float>.size,
            baselineExposure: result.baselineExposure,
            hasBaselineExposure: result.hasBaselineExposure,
            wbMultipliers: wbMultipliers,
            colorTemperature: result.colorTemperature
        )
    }
}
