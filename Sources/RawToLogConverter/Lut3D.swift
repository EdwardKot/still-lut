import Metal
import simd

// MARK: - LUT Error Types

enum Lut3DError: Error, LocalizedError {
    case invalidFile
    case parseFailed(String)
    case dimensionMismatch(expected: Int, actual: Int)
    case textureCreationFailed
    case unsupportedFormat
    
    var errorDescription: String? {
        switch self {
        case .invalidFile: return "Invalid LUT file"
        case .parseFailed(let msg): return "LUT parsing failed: \(msg)"
        case .dimensionMismatch(let expected, let actual): 
            return "LUT dimension mismatch: expected \(expected)³, got \(actual) entries"
        case .textureCreationFailed: return "Failed to create 3D texture"
        case .unsupportedFormat: return "Unsupported LUT format"
        }
    }
}

// MARK: - LUT Metadata

struct LutMetadata {
    var title: String?
    var dimension: Int = 0
    var domainMin: simd_float3 = simd_float3(0, 0, 0)
    var domainMax: simd_float3 = simd_float3(1, 1, 1)
    var dataCount: Int = 0
}

// MARK: - 3D LUT

/// Native Metal 3D LUT implementation
/// Supports .cube files with hardware trilinear interpolation
class Lut3D {
    
    // MARK: - Properties
    
    /// Metal 3D texture containing LUT data
    let texture: MTLTexture
    
    /// Metal sampler for trilinear interpolation
    let sampler: MTLSamplerState
    
    /// LUT metadata
    let metadata: LutMetadata
    
    /// LUT dimension (e.g., 33, 64, 65)
    var dimension: Int { metadata.dimension }
    
    // MARK: - Initialization
    
    /// Create LUT from .cube file
    init(device: MTLDevice, cubeFileURL: URL) throws {
        // Parse .cube file
        let (data, metadata) = try Self.parseCubeFile(url: cubeFileURL)
        self.metadata = metadata
        
        // Create 3D texture
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.width = metadata.dimension
        descriptor.height = metadata.dimension
        descriptor.depth = metadata.dimension
        descriptor.pixelFormat = .rgba32Float  // Full precision
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared  // Allow CPU upload
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw Lut3DError.textureCreationFailed
        }
        self.texture = texture
        
        // Upload LUT data to texture
        // .cube format uses R-varies-fastest ordering
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: metadata.dimension, height: metadata.dimension, depth: metadata.dimension)
        )
        
        let bytesPerRow = metadata.dimension * 4 * MemoryLayout<Float>.size
        let bytesPerImage = bytesPerRow * metadata.dimension
        
        texture.replace(
            region: region,
            mipmapLevel: 0,
            slice: 0,
            withBytes: data,
            bytesPerRow: bytesPerRow,
            bytesPerImage: bytesPerImage
        )
        
        // Create sampler with trilinear interpolation
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .notMipmapped
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.rAddressMode = .clampToEdge
        
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw Lut3DError.textureCreationFailed
        }
        self.sampler = sampler
        
        print("🎨 LUT3D loaded:")
        print("   Title: \(metadata.title ?? "Untitled")")
        print("   Dimension: \(metadata.dimension)³")
        print("   Domain: [\(metadata.domainMin)] → [\(metadata.domainMax)]")
    }
    
    /// Create LUT from raw float data
    init(device: MTLDevice, data: [Float], dimension: Int, title: String? = nil) throws {
        let expectedCount = dimension * dimension * dimension * 4  // RGBA
        guard data.count == expectedCount else {
            throw Lut3DError.dimensionMismatch(expected: dimension * dimension * dimension, actual: data.count / 4)
        }
        
        var metadata = LutMetadata()
        metadata.title = title
        metadata.dimension = dimension
        metadata.dataCount = data.count / 4
        self.metadata = metadata
        
        // Create 3D texture
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.width = dimension
        descriptor.height = dimension
        descriptor.depth = dimension
        descriptor.pixelFormat = .rgba32Float
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw Lut3DError.textureCreationFailed
        }
        self.texture = texture
        
        // Upload data
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: dimension, height: dimension, depth: dimension)
        )
        
        texture.replace(
            region: region,
            mipmapLevel: 0,
            slice: 0,
            withBytes: data,
            bytesPerRow: dimension * 4 * MemoryLayout<Float>.size,
            bytesPerImage: dimension * dimension * 4 * MemoryLayout<Float>.size
        )
        
        // Create sampler
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.rAddressMode = .clampToEdge
        
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw Lut3DError.textureCreationFailed
        }
        self.sampler = sampler
    }
    
    // MARK: - .cube File Parser
    
    /// Parse .cube LUT file to RGBA float array
    /// - Parameter url: Path to .cube file
    /// - Returns: Tuple of (RGBA float data, metadata)
    static func parseCubeFile(url: URL) throws -> ([Float], LutMetadata) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw Lut3DError.invalidFile
        }
        
        var metadata = LutMetadata()
        var rgbData: [(Float, Float, Float)] = []
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            // Parse metadata
            if trimmed.hasPrefix("TITLE") {
                // Extract title (may be quoted)
                let parts = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                metadata.title = parts.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                continue
            }
            
            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2, let dim = Int(parts[1]) {
                    metadata.dimension = dim
                }
                continue
            }
            
            if trimmed.hasPrefix("DOMAIN_MIN") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 4,
                   let r = Float(parts[1]),
                   let g = Float(parts[2]),
                   let b = Float(parts[3]) {
                    metadata.domainMin = simd_float3(r, g, b)
                }
                continue
            }
            
            if trimmed.hasPrefix("DOMAIN_MAX") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 4,
                   let r = Float(parts[1]),
                   let g = Float(parts[2]),
                   let b = Float(parts[3]) {
                    metadata.domainMax = simd_float3(r, g, b)
                }
                continue
            }
            
            // Skip other headers
            if trimmed.contains("_") {
                continue
            }
            
            // Parse RGB values
            let parts = trimmed.split(separator: " ").compactMap { Float($0) }
            if parts.count >= 3 {
                rgbData.append((parts[0], parts[1], parts[2]))
            }
        }
        
        // Validate
        let expectedCount = metadata.dimension * metadata.dimension * metadata.dimension
        guard metadata.dimension > 0 else {
            throw Lut3DError.parseFailed("LUT_3D_SIZE not found")
        }
        
        guard rgbData.count == expectedCount else {
            throw Lut3DError.dimensionMismatch(expected: expectedCount, actual: rgbData.count)
        }
        
        metadata.dataCount = rgbData.count
        
        // Convert RGB to RGBA (add alpha = 1.0)
        // .cube format: R varies fastest, then G, then B
        // Metal 3D texture expects: x (R) varies fastest, then y (G), then z (B)
        // This matches .cube ordering, so we can use data directly
        var rgba: [Float] = []
        rgba.reserveCapacity(rgbData.count * 4)
        
        for (r, g, b) in rgbData {
            rgba.append(r)
            rgba.append(g)
            rgba.append(b)
            rgba.append(1.0)  // Alpha
        }
        
        return (rgba, metadata)
    }
    
    // MARK: - CIColorCube Compatibility
    
    /// Create Data for CIColorCube filter (for Core Image compatibility)
    func toCIColorCubeData() -> Data {
        // CIColorCube expects RGBA float data in premultiplied format
        let dim = metadata.dimension
        
        // Read back from texture
        var buffer = [Float](repeating: 0, count: dim * dim * dim * 4)
        
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: dim, height: dim, depth: dim)
        )
        
        texture.getBytes(
            &buffer,
            bytesPerRow: dim * 4 * MemoryLayout<Float>.size,
            bytesPerImage: dim * dim * 4 * MemoryLayout<Float>.size,
            from: region,
            mipmapLevel: 0,
            slice: 0
        )
        
        return Data(bytes: buffer, count: buffer.count * MemoryLayout<Float>.size)
    }
}

// MARK: - LUT Application Extension for MetalPipeline

extension MetalPipeline {
    
    /// Apply 3D LUT to input texture
    func applyLUT(
        _ lut: Lut3D,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        completion: @escaping (Bool) -> Void
    ) {
        guard let pipeline = computePipelines["applyLUT3D"] else {
            print("❌ applyLUT3D pipeline not found")
            completion(false)
            return
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            completion(false)
            return
        }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        encoder.setTexture(lut.texture, index: 2)
        encoder.setSamplerState(lut.sampler, index: 0)
        
        let gridSize = MTLSize(
            width: outputTexture.width,
            height: outputTexture.height,
            depth: 1
        )
        let threadgroupSize = optimalThreadgroupSize(for: gridSize)
        
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        
        commandBuffer.addCompletedHandler { buffer in
            DispatchQueue.main.async {
                completion(buffer.status == .completed)
            }
        }
        
        commandBuffer.commit()
    }
}
