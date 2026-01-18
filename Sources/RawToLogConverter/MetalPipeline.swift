import Metal
import MetalKit
import CoreImage
import simd

// MARK: - Error Types

enum MetalPipelineError: Error, LocalizedError {
    case deviceNotFound
    case libraryCreationFailed
    case functionNotFound(String)
    case pipelineCreationFailed(String)
    case textureCreationFailed
    case commandBufferFailed
    case encoderCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .deviceNotFound: return "No Metal device found"
        case .libraryCreationFailed: return "Failed to create Metal library"
        case .functionNotFound(let name): return "Metal function not found: \(name)"
        case .pipelineCreationFailed(let msg): return "Pipeline creation failed: \(msg)"
        case .textureCreationFailed: return "Failed to create texture"
        case .commandBufferFailed: return "Failed to create command buffer"
        case .encoderCreationFailed: return "Failed to create compute encoder"
        }
    }
}

// MARK: - Bradford CAT Matrices

/// Bradford Chromatic Adaptation Transform matrices
/// Used for accurate white point adaptation (source → D65)
struct BradfordCAT {
    /// Bradford forward matrix (XYZ → LMS cone response)
    static let forward = simd_float3x3(rows: [
        simd_float3( 0.8951,  0.2664, -0.1614),
        simd_float3(-0.7502,  1.7135,  0.0367),
        simd_float3( 0.0389, -0.0686,  1.0296)
    ])
    
    /// Bradford inverse matrix (LMS → XYZ)
    static let inverse = simd_float3x3(rows: [
        simd_float3( 0.9869929, -0.1470543,  0.1599627),
        simd_float3( 0.4323053,  0.5183603,  0.0492912),
        simd_float3(-0.0085287,  0.0400428,  0.9684867)
    ])
    
    /// D65 standard illuminant chromaticity (x, y)
    static let D65: simd_float2 = simd_float2(0.31270, 0.32900)
    
    /// D50 standard illuminant chromaticity (x, y)
    static let D50: simd_float2 = simd_float2(0.34567, 0.35850)
    
    /// Convert chromaticity (x, y) to XYZ with Y=1
    static func chromaticityToXYZ(_ xy: simd_float2) -> simd_float3 {
        let x = xy.x
        let y = xy.y
        return simd_float3(x / y, 1.0, (1.0 - x - y) / y)
    }
    
    /// Calculate Bradford adaptation matrix from source white to destination white
    /// - Parameters:
    ///   - srcWhite: Source white point chromaticity (x, y)
    ///   - dstWhite: Destination white point chromaticity (x, y), default D65
    /// - Returns: 3x3 adaptation matrix to multiply with XYZ values
    static func adaptationMatrix(from srcWhite: simd_float2, to dstWhite: simd_float2 = D65) -> simd_float3x3 {
        let srcXYZ = chromaticityToXYZ(srcWhite)
        let dstXYZ = chromaticityToXYZ(dstWhite)
        
        // Convert to cone response domain
        let srcCone = forward * srcXYZ
        let dstCone = forward * dstXYZ
        
        // Diagonal scaling matrix
        let scale = simd_float3x3(diagonal: simd_float3(
            dstCone.x / srcCone.x,
            dstCone.y / srcCone.y,
            dstCone.z / srcCone.z
        ))
        
        // Final adaptation matrix: M^-1 * S * M
        return inverse * scale * forward
    }
    
    /// Pre-computed D50 → D65 adaptation matrix
    static let D50_to_D65 = adaptationMatrix(from: D50, to: D65)
}

// MARK: - Color Space Matrices (Float)

/// High-precision color space transformation matrices using SIMD
struct ColorMatrices {
    /// Display P3 (Linear, D65) → XYZ (D65)
    /// Source: colour-science library, Display P3 colorspace
    static let P3_to_XYZ = simd_float3x3(rows: [
        simd_float3(0.4865709486, 0.2656676932, 0.1982172852),
        simd_float3(0.2289745641, 0.6917385218, 0.0792869141),
        simd_float3(0.0000000000, 0.0451133819, 1.0439443689)
    ])
    
    /// sRGB (Linear, D65) → XYZ (D65)
    /// Source: IEC 61966-2-1:1999, sRGB color space specification
    /// Most JPG files are sRGB, not Display P3
    static let sRGB_to_XYZ = simd_float3x3(rows: [
        simd_float3(0.4124564, 0.3575761, 0.1804375),
        simd_float3(0.2126729, 0.7151522, 0.0721750),
        simd_float3(0.0193339, 0.1191920, 0.9503041)
    ])
    
    /// XYZ (D65) → ITU-R BT.2020 / F-Gamut
    /// Source: ITU-R BT.2020 specification
    static let XYZ_to_Rec2020 = simd_float3x3(rows: [
        simd_float3( 1.7166511880, -0.3556707838, -0.2533662814),
        simd_float3(-0.6666843518,  1.6164812366,  0.0157685458),
        simd_float3( 0.0176398574, -0.0427706133,  0.9421031212)
    ])
    
    /// XYZ (D65) → S-Gamut3 (Sony)
    static let XYZ_to_SGamut3 = simd_float3x3(rows: [
        simd_float3( 1.8467789693, -0.5259861230, -0.2105452114),
        simd_float3(-0.4441531566,  1.2594429028,  0.1493998071),
        simd_float3( 0.0408231292,  0.0156628005,  0.8682805350)
    ])
    
    /// XYZ (D65) → V-Gamut (Panasonic)
    static let XYZ_to_VGamut = simd_float3x3(rows: [
        simd_float3( 1.5890271270, -0.3133503604, -0.1808091984),
        simd_float3(-0.5341191671,  1.3962743855,  0.1023665344),
        simd_float3( 0.0000000000,  0.0000000000,  0.9056967220)
    ])
    
    /// Combined P3 → Rec.2020 matrix (for single-step conversion)
    static let P3_to_Rec2020 = XYZ_to_Rec2020 * P3_to_XYZ
    
    // MARK: - Additional Gamut Matrices for Extended Log Profile Support
    
    /// XYZ (D65) → S-Gamut3.Cine (Sony)
    /// S-Gamut3.Cine has slightly tighter primaries optimized for cinema workflow
    /// Source: Sony S-Log3/S-Gamut3.Cine Technical Summary
    static let XYZ_to_SGamut3Cine = simd_float3x3(rows: [
        simd_float3( 1.8408396620, -0.5308666090, -0.2096241400),
        simd_float3(-0.4452923760,  1.2583390200,  0.1511632020),
        simd_float3( 0.0408231290,  0.0156628000,  0.8682805350)
    ])
    
    /// XYZ (D65) → Cinema Gamut (Canon)
    /// Used for Canon Log 2 and Canon Log 3
    /// Source: Canon Cinema EOS White Paper
    static let XYZ_to_CinemaGamut = simd_float3x3(rows: [
        simd_float3( 1.5059159370, -0.2548349600, -0.1715045330),
        simd_float3(-0.4659192320,  1.3542697970,  0.0906014440),
        simd_float3(-0.0299206550,  0.0237817890,  0.9318181920)
    ])
    
    /// XYZ (D65) → ARRI Wide Gamut 3 (AWG3)
    /// Used for ARRI LogC3
    /// Source: ARRI LogC Specification
    static let XYZ_to_AWG3 = simd_float3x3(rows: [
        simd_float3( 1.7890590000, -0.4825720000, -0.2006980000),
        simd_float3(-0.6398640000,  1.3963550000,  0.1943630000),
        simd_float3(-0.0415300000,  0.0822450000,  0.8788420000)
    ])
    
    /// XYZ (D65) → ARRI Wide Gamut 4 (AWG4)
    /// Used for ARRI LogC4
    /// Source: ARRI LogC4 Specification
    static let XYZ_to_AWG4 = simd_float3x3(rows: [
        simd_float3( 1.8987220000, -0.5265110000, -0.2630360000),
        simd_float3(-0.7053000000,  1.5205200000,  0.1303120000),
        simd_float3(-0.0486690000,  0.1030730000,  0.8621000000)
    ])
    
    /// XYZ (D65) → RED Wide Gamut RGB
    /// Used for Log3G10
    /// Source: RED IPP2 Specification
    static let XYZ_to_REDWideGamut = simd_float3x3(rows: [
        simd_float3( 1.4128290000, -0.1783960000, -0.1499340000),
        simd_float3(-0.4930950000,  1.3451830000,  0.1127100000),
        simd_float3(-0.0140950000,  0.0547230000,  0.8762560000)
    ])
    
    /// XYZ (D65) → DaVinci Wide Gamut (DWG)
    /// Used for DaVinci Intermediate
    /// Source: Blackmagic Design DaVinci Wide Gamut Specification
    /// Primaries: R(0.8000, 0.3130), G(0.1682, 0.9877), B(0.0790, -0.1155), D65 white
    static let XYZ_to_DaVinciWideGamut = simd_float3x3(rows: [
        simd_float3( 1.5168982700, -0.2814611100, -0.1469458300),
        simd_float3(-0.6498311700,  1.4929222600,  0.1178976000),
        simd_float3( 0.0103477700, -0.0149178400,  0.9195942300)
    ])
}

// MARK: - Log Curve Type Enum

/// Log curve types for XYZ pipeline shader
/// Must match Metal enum LogCurveType
enum LogCurveType: UInt32, CaseIterable {
    case fLog2 = 0
    case fLog = 1             // F-Log (v1) - distinct from F-Log2
    case sLog3 = 2
    case vLog = 3
    case nLog = 4
    case canonLog2 = 5
    case canonLog3 = 6
    case arriLogC3 = 7
    case arriLogC4 = 8
    case log3G10 = 9
    case lLog = 10
    case davinciIntermediate = 11
    
    var displayName: String {
        switch self {
        case .fLog2: return "F-Log2"
        case .fLog: return "F-Log"
        case .sLog3: return "S-Log3"
        case .vLog: return "V-Log"
        case .nLog: return "N-Log"
        case .canonLog2: return "Canon Log 2"
        case .canonLog3: return "Canon Log 3"
        case .arriLogC3: return "ARRI LogC3"
        case .arriLogC4: return "ARRI LogC4"
        case .log3G10: return "RED Log3G10"
        case .lLog: return "L-Log"
        case .davinciIntermediate: return "DaVinci Intermediate"
        }
    }
}

// MARK: - XYZ Pipeline Uniforms

/// Uniforms for the XYZ pipeline kernel
/// Must match Metal struct XYZPipelineUniforms layout EXACTLY
/// Metal float3x3 is stored as 3 × float4 (48 bytes) with column padding
/// Metal float3 in struct is padded to 16 bytes (float4)
/// Total Metal size: 112 bytes
struct XYZPipelineUniforms {
    var colorMatrix: simd_float3x3      // 48 bytes (3 × float4 in Metal)
    var exposure: Float = 1.0           // 4 bytes
    var softClipKnee: Float = 0.8       // 4 bytes
    var softClipCeiling: Float = 1.0    // 4 bytes
    var logCurveType: UInt32 = 0        // 4 bytes
    // --- Adjustment parameters ---
    var saturation: Float = 1.0         // 4 bytes (1.0 = neutral)
    var contrast: Float = 1.0           // 4 bytes (1.0 = neutral)
    var contrastPivot: Float = 0.383    // 4 bytes (middle gray for contrast)
    var tint: Float = 0.0               // 4 bytes (green-magenta, 0 = neutral)
    // --- White Balance (applied in GPU for real-time adjustment) ---
    // Use float4 to match Metal's 16-byte padding for float3 in structs
    var wbMultipliers: simd_float4 = simd_float4(1, 1, 1, 0)  // 16 bytes
    // --- Shadow/Highlight recovery ---
    var shadows: Float = 0.0             // 4 bytes (-100 to +100, 0 = neutral)
    var highlights: Float = 0.0          // 4 bytes (-100 to +100, 0 = neutral)
    var padding3: Float = 0              // 4 bytes
    var padding4: Float = 0              // 4 bytes - total: 112 bytes
    
    init(colorMatrix: simd_float3x3, 
         exposure: Float = 1.0,
         softClipKnee: Float = 0.8,
         softClipCeiling: Float = 1.0,
         logCurve: LogCurveType = .fLog2,
         saturation: Float = 1.0,
         contrast: Float = 1.0,
         contrastPivot: Float = 0.383,
         tint: Float = 0.0,
         wbMultipliers: simd_float3 = simd_float3(1, 1, 1),
         shadows: Float = 0.0,
         highlights: Float = 0.0) {
        self.colorMatrix = colorMatrix
        self.exposure = exposure
        self.softClipKnee = softClipKnee
        self.softClipCeiling = softClipCeiling
        self.logCurveType = logCurve.rawValue
        self.saturation = saturation
        self.contrast = contrast
        self.contrastPivot = contrastPivot
        self.tint = tint
        // Convert float3 to float4 for proper Metal alignment
        self.wbMultipliers = simd_float4(wbMultipliers.x, wbMultipliers.y, wbMultipliers.z, 0)
        self.shadows = shadows
        self.highlights = highlights
    }
}

// MARK: - Metal Pipeline Manager


/// Core Metal pipeline manager for GPU-accelerated image processing
/// Handles device management, shader compilation, and compute dispatch
@MainActor
class MetalPipeline: ObservableObject {
    
    // MARK: - Properties
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private var library: MTLLibrary?
    var computePipelines: [String: MTLComputePipelineState] = [:]
    
    /// Cached trilinear sampler for LUT lookups (prevents memory leak)
    private var trilinearSampler: MTLSamplerState?
    
    /// Thread execution width for optimal dispatch
    var threadExecutionWidth: Int = 32
    
    /// Maximum threads per threadgroup
    var maxThreadsPerThreadgroup: Int = 1024
    
    // MARK: - Initialization
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalPipelineError.deviceNotFound
        }
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            throw MetalPipelineError.deviceNotFound
        }
        self.commandQueue = queue
        
        // Load Metal library with shaders
        try loadShaderLibrary()
        
        print("🔧 MetalPipeline initialized:")
        print("   Device: \(device.name)")
        print("   Thread execution width: \(threadExecutionWidth)")
        print("   Max threads/threadgroup: \(maxThreadsPerThreadgroup)")
    }
    
    // MARK: - Shader Management
    
    private func loadShaderLibrary() throws {
        // Metal shader source code
        let shaderSource = Self.metalShaderSource
        
        do {
            library = try device.makeLibrary(source: shaderSource, options: nil)
            print("   ✅ Metal library compiled successfully")
            
            // Pre-create compute pipelines
            try createComputePipeline(named: "colorTransform")
            try createComputePipeline(named: "flog2Encode")
            try createComputePipeline(named: "flog2EncodeBranchless")
            try createComputePipeline(named: "applyLUT3D")
            try createComputePipeline(named: "exposureAndSoftClip")
            
            // LibRaw XYZ Pipeline kernels
            try createComputePipeline(named: "processXYZPipeline")
            try createComputePipeline(named: "processXYZPipelineWithLUT")
            
            
        } catch {
            print("   ❌ Metal library compilation failed: \(error)")
            throw MetalPipelineError.libraryCreationFailed
        }
    }
    
    private func createComputePipeline(named functionName: String) throws {
        guard let library = library,
              let function = library.makeFunction(name: functionName) else {
            throw MetalPipelineError.functionNotFound(functionName)
        }
        
        do {
            let pipelineState = try device.makeComputePipelineState(function: function)
            computePipelines[functionName] = pipelineState
            
            // Update thread execution metrics
            if threadExecutionWidth == 32 {
                threadExecutionWidth = pipelineState.threadExecutionWidth
                maxThreadsPerThreadgroup = pipelineState.maxTotalThreadsPerThreadgroup
            }
            
            print("   ✅ Pipeline '\(functionName)' created")
        } catch {
            throw MetalPipelineError.pipelineCreationFailed(functionName)
        }
    }
    
    // MARK: - Texture Creation
    
    /// Create a texture with the specified format and dimensions
    func createTexture(width: Int, height: Int, 
                       format: MTLPixelFormat = .rgba32Float,
                       usage: MTLTextureUsage = [.shaderRead, .shaderWrite],
                       storageMode: MTLStorageMode = .private) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = usage
        descriptor.storageMode = storageMode
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MetalPipelineError.textureCreationFailed
        }
        return texture
    }
    
    /// Create a 3D texture for LUT
    func create3DTexture(dimension: Int, 
                         format: MTLPixelFormat = .rgba32Float) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.width = dimension
        descriptor.height = dimension
        descriptor.depth = dimension
        descriptor.pixelFormat = format
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared  // Need CPU access for upload
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MetalPipelineError.textureCreationFailed
        }
        return texture
    }
    
    // MARK: - Compute Dispatch
    
    /// Calculate optimal threadgroup size for a given texture size
    func optimalThreadgroupSize(for textureSize: MTLSize) -> MTLSize {
        // Use thread execution width as base
        let width = threadExecutionWidth
        let height = min(8, maxThreadsPerThreadgroup / width)
        return MTLSize(width: width, height: height, depth: 1)
    }
    
    /// Dispatch a compute shader asynchronously
    func dispatchCompute(
        pipelineName: String,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        uniforms: UnsafeRawPointer? = nil,
        uniformsSize: Int = 0,
        completion: @escaping (Bool) -> Void
    ) {
        guard let pipeline = computePipelines[pipelineName] else {
            print("❌ Pipeline not found: \(pipelineName)")
            completion(false)
            return
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("❌ Failed to create command buffer")
            completion(false)
            return
        }
        
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            print("❌ Failed to create compute encoder")
            completion(false)
            return
        }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        
        if let uniforms = uniforms, uniformsSize > 0 {
            encoder.setBytes(uniforms, length: uniformsSize, index: 0)
        }
        
        let gridSize = MTLSize(
            width: outputTexture.width,
            height: outputTexture.height,
            depth: 1
        )
        let threadgroupSize = optimalThreadgroupSize(for: gridSize)
        
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        
        // Async completion handler (NOT blocking CPU)
        commandBuffer.addCompletedHandler { buffer in
            // DO NOT use DispatchQueue.main.async here!
            // Callers use CheckedContinuation which properly resumes to the correct context.
            // Using main.async would deadlock when caller is @MainActor awaiting this.
            if buffer.status == .completed {
                completion(true)
            } else {
                print("❌ Command buffer failed: \(buffer.error?.localizedDescription ?? "unknown")")
                completion(false)
            }
        }
        
        commandBuffer.commit()
    }
    
    /// Dispatch a compute shader with LUT texture support
    func dispatchComputeWithLUT(
        pipelineName: String,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        lutTexture: MTLTexture,
        uniforms: UnsafeRawPointer? = nil,
        uniformsSize: Int = 0,
        completion: @escaping (Bool) -> Void
    ) {
        guard let pipeline = computePipelines[pipelineName] else {
            print("❌ Pipeline not found: \(pipelineName)")
            completion(false)
            return
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("❌ Failed to create command buffer")
            completion(false)
            return
        }
        
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            print("❌ Failed to create compute encoder")
            completion(false)
            return
        }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        encoder.setTexture(lutTexture, index: 2)
        
        // Use cached trilinear sampler for LUT (prevent memory leak)
        if trilinearSampler == nil {
            let samplerDescriptor = MTLSamplerDescriptor()
            samplerDescriptor.minFilter = .linear
            samplerDescriptor.magFilter = .linear
            samplerDescriptor.normalizedCoordinates = true
            trilinearSampler = device.makeSamplerState(descriptor: samplerDescriptor)
        }
        if let sampler = trilinearSampler {
            encoder.setSamplerState(sampler, index: 0)
        }
        
        if let uniforms = uniforms, uniformsSize > 0 {
            encoder.setBytes(uniforms, length: uniformsSize, index: 0)
        }
        
        let gridSize = MTLSize(
            width: outputTexture.width,
            height: outputTexture.height,
            depth: 1
        )
        let threadgroupSize = optimalThreadgroupSize(for: gridSize)
        
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        
        commandBuffer.addCompletedHandler { buffer in
            // DO NOT use DispatchQueue.main.async here - same reason as dispatchCompute
            if buffer.status == .completed {
                completion(true)
            } else {
                print("❌ Command buffer failed: \(buffer.error?.localizedDescription ?? "unknown")")
                completion(false)
            }
        }
        
        commandBuffer.commit()
    }
    
    // MARK: - Metal Shader Source
    
    static let metalShaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    
    // MARK: - Uniforms
    
    struct ColorTransformUniforms {
        float3x3 matrix;
        float exposure;
        float softClipKnee;
        float softClipCeiling;
    };
    
    // MARK: - Helper Functions
    
    // Soft clip using rational approximation (faster than tanh)
    inline float softClipRational(float x, float knee, float ceiling) {
        if (x <= knee) return x;
        float excess = x - knee;
        float range = ceiling - knee;
        return knee + range * excess / (range + excess);
    }
    
    inline float3 softClip3(float3 rgb, float knee, float ceiling) {
        return float3(
            softClipRational(rgb.r, knee, ceiling),
            softClipRational(rgb.g, knee, ceiling),
            softClipRational(rgb.b, knee, ceiling)
        );
    }
    
    // MARK: - Color Transform Kernel
    
    kernel void colorTransform(
        texture2d<float, access::read> input [[texture(0)]],
        texture2d<float, access::write> output [[texture(1)]],
        constant ColorTransformUniforms& uniforms [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
        
        float4 pixel = input.read(gid);
        float3 rgb = pixel.rgb;
        
        // Apply exposure (linear multiply)
        rgb *= uniforms.exposure;
        
        // Soft clip highlights
        rgb = softClip3(rgb, uniforms.softClipKnee, uniforms.softClipCeiling);
        
        // Apply color matrix
        rgb = uniforms.matrix * rgb;
        
        output.write(float4(rgb, pixel.a), gid);
    }
    
    // MARK: - F-Log2 Encoding (Branchless)
    
    kernel void flog2EncodeBranchless(
        texture2d<float, access::read> input [[texture(0)]],
        texture2d<float, access::write> output [[texture(1)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
        
        float4 pixel = input.read(gid);
        float3 x = max(pixel.rgb, float3(1e-10));  // Prevent log(0)
        
        // F-Log2 constants (Fujifilm F-Log2 Data Sheet Ver.1.0)
        const float a = 5.555556;
        const float b = 0.064829;
        const float c = 0.245281;
        const float d = 0.384316;
        const float e = 8.799461;
        const float f = 0.092864;
        const float cut = 0.000889;
        
        // Branchless implementation using step + mix
        float3 linear_part = e * x + f;
        float3 log_part = c * log10(a * x + b) + d;
        float3 selector = step(cut, x);  // 0 if x < cut, 1 if x >= cut
        
        float3 y = mix(linear_part, log_part, selector);
        
        output.write(float4(y, pixel.a), gid);
    }
    
    // MARK: - F-Log2 Encoding (Original with branches for comparison)
    
    kernel void flog2Encode(
        texture2d<float, access::read> input [[texture(0)]],
        texture2d<float, access::write> output [[texture(1)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
        
        float4 pixel = input.read(gid);
        float3 x = max(pixel.rgb, float3(1e-10));
        float3 y;
        
        const float a = 5.555556;
        const float b = 0.064829;
        const float c = 0.245281;
        const float d = 0.384316;
        const float e = 8.799461;
        const float f = 0.092864;
        const float cut = 0.000889;
        
        for (int i = 0; i < 3; i++) {
            if (x[i] >= cut) {
                y[i] = c * log10(a * x[i] + b) + d;
            } else {
                y[i] = e * x[i] + f;
            }
        }
        
        output.write(float4(y, pixel.a), gid);
    }
    
    // MARK: - Exposure and Soft Clip
    
    struct ExposureUniforms {
        float gain;
        float softClipKnee;
        float softClipCeiling;
    };
    
    kernel void exposureAndSoftClip(
        texture2d<float, access::read> input [[texture(0)]],
        texture2d<float, access::write> output [[texture(1)]],
        constant ExposureUniforms& uniforms [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
        
        float4 pixel = input.read(gid);
        float3 rgb = pixel.rgb * uniforms.gain;
        
        // Soft clip using rational approximation
        rgb = softClip3(rgb, uniforms.softClipKnee, uniforms.softClipCeiling);
        
        output.write(float4(rgb, pixel.a), gid);
    }
    
    // MARK: - 3D LUT Application
    
    // ================================================================
    // MARK: - Linear P3 to XYZ Conversion (for JPG/PNG)
    // (Removed linearP3ToXYZ kernel - was only used for JPG processing)
    
    
    kernel void applyLUT3D(
        texture2d<float, access::read> input [[texture(0)]],
        texture2d<float, access::write> output [[texture(1)]],
        texture3d<float, access::sample> lut [[texture(2)]],
        sampler lutSampler [[sampler(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
        
        float4 pixel = input.read(gid);
        float3 rgb = clamp(pixel.rgb, 0.0, 1.0);  // LUT expects [0, 1]
        
        // Sample LUT with trilinear interpolation (hardware accelerated)
        float3 lutted = lut.sample(lutSampler, rgb).rgb;
        
        output.write(float4(lutted, pixel.a), gid);
    }
    
    // ================================================================
    // MARK: - LibRaw XYZ Pipeline Unified Kernel
    // ================================================================
    // This kernel performs the entire color pipeline in a single GPU pass:
    // 1. XYZ(D50) → Target Gamut RGB (combined matrix with Bradford CAT)
    // 2. Exposure adjustment in linear space
    // 3. Highlight soft-clipping
    // 4. Linear → Log encoding (parametric coefficients)
    // 5. Optional LUT application
    // ================================================================
    
    // Log curve types for parametric encoding
    enum LogCurveType : uint {
        LOG_FLOG2 = 0,
        LOG_FLOG = 1,     // F-Log (v1) - distinct from F-Log2
        LOG_SLOG3 = 2,
        LOG_VLOG = 3,
        LOG_NLOG = 4,
        LOG_CLOG2 = 5,
        LOG_CLOG3 = 6,
        LOG_LOGC3 = 7,
        LOG_LOGC4 = 8,
        LOG_LOG3G10 = 9,
        LOG_LLOG = 10,
        LOG_DAVINCI = 11
    };
    
    struct XYZPipelineUniforms {
        float3x3 colorMatrix;      // Combined XYZ(D65)→Target matrix (48 bytes)
        float exposure;            // Linear gain (1.0 = no change)
        float softClipKnee;        // Start of soft clip (e.g., 0.8)
        float softClipCeiling;     // Maximum output value (e.g., 1.0)
        uint logCurveType;         // LogCurveType enum value
        // --- Adjustment parameters ---
        float saturation;          // Saturation (1.0 = neutral)
        float contrast;            // Contrast (1.0 = neutral)
        float contrastPivot;       // Middle gray pivot point for contrast
        float tint;                // Green-Magenta (-100 to +100)
        // --- White Balance (applied in GPU for real-time adjustment) ---
        float4 wbMultipliers;      // R, G, B, 0 gains (16 bytes, matches Swift simd_float4)
        // --- Shadow/Highlight recovery ---
        float shadows;             // -100 to +100 (positive = lift shadows)
        float highlights;          // -100 to +100 (negative = compress highlights)
        float padding3;
        float padding4;            // Total: 112 bytes
    };
    
    // Apply saturation adjustment in linear space
    inline float3 applySaturation(float3 rgb, float saturation) {
        if (saturation == 1.0) return rgb;
        // Use Rec.709 luminance weights for perceptual accuracy
        float luma = dot(rgb, float3(0.2126, 0.7152, 0.0722));
        return mix(float3(luma), rgb, saturation);
    }
    
    // Apply tint adjustment (green-magenta balance)
    inline float3 applyTint(float3 rgb, float tint) {
        if (tint == 0.0) return rgb;
        // Multiplicative tint adjustment - affects all tones equally
        // -100 to +100 maps to 0.60x to 1.40x multiplier (40% range)
        // Matches professional tools like Lightroom/Capture One
        float gMultiplier = 1.0 - (tint / 250.0);   // Positive = reduce green (magenta)
        float rbMultiplier = 1.0 + (tint / 500.0);  // Positive = boost red/blue slightly
        rgb.g *= gMultiplier;
        rgb.r *= rbMultiplier;
        rgb.b *= rbMultiplier;
        return rgb;
    }
    
    // Apply contrast adjustment in Log space with specific pivot point
    inline float3 applyContrast(float3 logRGB, float contrast, float pivot) {
        if (contrast == 1.0) return logRGB;
        // Contrast around middle gray pivot point
        return (logRGB - pivot) * contrast + pivot;
    }
    
    // ============================================================================
    // DaVinci Resolve HDR Wheels Style Shadow/Highlight Adjustment
    // ============================================================================
    //
    // KEY INSIGHT: In Log space, exposure adjustments are OFFSETS, not scales!
    //   - Linear space: exposure +1 stop = value × 2
    //   - Log space: exposure +1 stop = value + constant
    //
    // WHY OFFSETS PRESERVE DETAIL:
    //   Cloud pixels: L=0.90, L=0.70 → difference = 0.20
    //   After uniform offset -0.15: L=0.75, L=0.55 → difference = 0.20 (PRESERVED!)
    //
    // THE WEIGHT CONTROLS TRANSITION, NOT MAGNITUDE:
    //   - Zone center: weight=1.0 → full offset applied
    //   - Zone edge: weight=0.5 → 50% blend between original and offset result
    //   - Outside zone: weight=0.0 → no change
    //   - But ALL pixels inside the zone get the SAME offset amount
    //
    // ============================================================================
    
    inline float3 applyShadowHighlight(float3 logRGB, float shadows, float highlights, float pivot) {
        if (shadows == 0.0 && highlights == 0.0) return logRGB;
        
        // Calculate luminance for zone detection
        float luma = dot(logRGB, float3(0.2126, 0.7152, 0.0722));
        
        float3 result = logRGB;
        
        // ========== HIGHLIGHT ADJUSTMENT ==========
        if (highlights != 0.0) {
            // Smooth zone mask: 0 below pivot, gradual transition, 1 at bright highlights
            float highlightMask = smoothstep(pivot, pivot + 0.4, luma);
            
            if (highlightMask > 0.0) {
                // UNIFORM offset for all pixels (in log units, like exposure stops)
                // -100 → -0.4 log units (about -1.3 stops)
                // +100 → +0.3 log units (about +1 stop)
                float offset = highlights / 100.0 * 0.4;
                
                // Calculate adjusted value (same offset for ALL pixels in zone)
                float3 adjusted = logRGB + offset;
                
                // Blend: weight controls TRANSITION smoothness, not offset magnitude
                // All pixels in the zone get the same relative adjustment
                result = mix(logRGB, adjusted, highlightMask);
            }
        }
        
        // ========== SHADOW ADJUSTMENT ==========
        if (shadows != 0.0) {
            // Smooth zone mask: 1 at black, gradual transition, 0 above pivot
            float shadowMask = 1.0 - smoothstep(0.0, pivot, luma);
            
            if (shadowMask > 0.0) {
                // UNIFORM offset for shadow lift/crush
                // +100 → +0.35 log units (lift shadows)
                // -100 → -0.25 log units (crush shadows)
                float offset = shadows / 100.0 * 0.35;
                
                // Calculate adjusted value
                float3 adjusted = result + offset;
                
                // Blend with smooth transition
                result = mix(result, adjusted, shadowMask);
            }
        }
        
        // Soft clip protection
        result = clamp(result, -0.1, 1.1);
        
        return result;
    }


    
    // Parametric Log encoding with all supported curves
    inline float3 encodeLog(float3 linear, uint curveType) {
        float3 y;
        float3 x = max(linear, float3(1e-10));  // Prevent log(0)
        
        switch (curveType) {
            case LOG_FLOG2: {
                // Fujifilm F-Log2 (official spec from Fujifilm F-Log2 Data Sheet Ver.1.0)
                const float a = 5.555556, b = 0.064829, c = 0.245281;
                const float d = 0.384316, e = 8.799461, f = 0.092864, cut = 0.000889;
                float3 lin = e * x + f;
                float3 log_v = c * log10(a * x + b) + d;
                y = select(lin, log_v, x >= cut);
                break;
            }
            case LOG_FLOG: {
                // Fujifilm F-Log (v1) - official Fujifilm spec
                // Different from F-Log2: less aggressive curve
                const float a = 0.555556, b = 0.009468, c = 0.344676;
                const float d = 0.790453, e = 8.735631, f = 0.092864, cut = 0.00089;
                for (int i = 0; i < 3; i++) {
                    if (x[i] >= cut) {
                        y[i] = c * log10(a * x[i] + b) + d;
                    } else {
                        y[i] = e * x[i] + f;
                    }
                }
                break;
            }
            case LOG_SLOG3: {
                // Sony S-Log3
                const float cut = 0.01125;
                for (int i = 0; i < 3; i++) {
                    if (x[i] >= cut) {
                        y[i] = (420.0 + log10((x[i] + 0.01) / 0.19) * 261.5) / 1023.0;
                    } else {
                        y[i] = (x[i] * (171.2102946929 - 95.0) / 0.01125 + 95.0) / 1023.0;
                    }
                }
                break;
            }
            case LOG_VLOG: {
                // Panasonic V-Log
                const float cut = 0.01, b_v = 0.00873, c_v = 0.241514, d_v = 0.598206;
                float3 lin = 5.6 * x + 0.125;
                float3 log_v = c_v * log10(x + b_v) + d_v;
                y = select(lin, log_v, x >= cut);
                break;
            }
            case LOG_NLOG: {
                // Nikon N-Log
                const float cut = 0.328;
                for (int i = 0; i < 3; i++) {
                    if (x[i] < cut) {
                        y[i] = 650.0 * pow(x[i] + 0.0075, 1.0/3.0) / 1023.0;
                    } else {
                        y[i] = (150.0 * log(x[i]) + 619.0) / 1023.0;
                    }
                }
                break;
            }
            case LOG_CLOG2: {
                // Canon Log 2
                float3 pos = 0.092809 * log10(x * 16.332 + 1.0) + 0.24544;
                float3 neg = -0.092809 * log10(-x * 2.141 + 1.0) + 0.092809;
                y = select(neg, pos, x >= 0.0);
                break;
            }
            case LOG_CLOG3: {
                // Canon Log 3
                const float cut = 0.014;
                for (int i = 0; i < 3; i++) {
                    if (x[i] >= cut) {
                        y[i] = 0.069886 * log10(x[i] * 10.1596 + 1.0) + 0.20471;
                    } else if (x[i] >= -cut) {
                        y[i] = 2.336411 * x[i] + 0.073059;
                    } else {
                        y[i] = -0.069886 * log10(-x[i] * 10.1596 + 1.0) + 0.069886 - 0.073059;
                    }
                }
                break;
            }
            case LOG_LOGC3: {
                // ARRI LogC3 (EI800)
                const float cut = 0.010591, a = 5.555556, b_a = 0.052272;
                const float c_a = 0.247190, d_a = 0.385537, e_a = 5.367655, f_a = 0.092809;
                for (int i = 0; i < 3; i++) {
                    y[i] = (x[i] > cut) ? c_a * log10(a * x[i] + b_a) + d_a : e_a * x[i] + f_a;
                }
                break;
            }
            case LOG_LOGC4: {
                // ARRI LogC4
                const float a = 2231.826398, b_l = 0.131804, c_l = 14.0, sc = 7.0;
                for (int i = 0; i < 3; i++) {
                    y[i] = (x[i] >= 0.0) ? (log2(a * x[i] + b_l) + c_l) / sc : x[i] * sc;
                }
                break;
            }
            case LOG_LOG3G10: {
                // RED Log3G10
                const float a = 0.224282, b_r = 155.975327, c_r = 0.01, g = 15.1927;
                for (int i = 0; i < 3; i++) {
                    y[i] = (x[i] >= -c_r) ? a * log10(b_r * (x[i] + c_r) + 1.0) : (x[i] + c_r) * g;
                }
                break;
            }
            case LOG_LLOG: {
                // Leica L-Log
                const float cut = 0.006, a = 8.0, b_ll = 0.09;
                const float c_ll = 0.27, d_ll = 1.3, e_ll = 0.0115, f_ll = 0.6;
                for (int i = 0; i < 3; i++) {
                    y[i] = (x[i] > cut) ? c_ll * log10(d_ll * x[i] + e_ll) + f_ll : a * x[i] + b_ll;
                }
                break;
            }
            case LOG_DAVINCI: {
                // DaVinci Intermediate
                const float DI_A = 0.0075, DI_B = 7.0, DI_C = 0.07329248;
                const float DI_M = 10.44426855, DI_LIN_CUT = 0.00262409;
                for (int i = 0; i < 3; i++) {
                    y[i] = (x[i] > DI_LIN_CUT) ? (log2(x[i] + DI_A) + DI_B) * DI_C : x[i] * DI_M;
                }
                break;
            }
            default:
                y = x;  // Fallback: no encoding
                break;
        }
        
        return y;
    }
    
    // Unified XYZ Pipeline Kernel
    kernel void processXYZPipeline(
        texture2d<float, access::read> input [[texture(0)]],
        texture2d<float, access::write> output [[texture(1)]],
        constant XYZPipelineUniforms& uniforms [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
        
        // Read XYZ(D65) pixel (camera WB already applied by LibRaw)
        float4 pixel = input.read(gid);
        float3 xyz = pixel.rgb;
        
        // Step 1: XYZ(D65) → Target Gamut RGB
        float3 rgb = uniforms.colorMatrix * xyz;
        
        // Step 2: Apply relative WB adjustment in RGB space (for real-time tint/temp)
        // Default (1,1,1) = no adjustment, camera WB is already baked
        rgb *= uniforms.wbMultipliers.xyz;
        
        // Step 3: Apply exposure in linear space
        rgb *= uniforms.exposure;
        
        // Step 3: Apply tint in linear space (green-magenta balance)
        rgb = applyTint(rgb, uniforms.tint);
        
        // Step 4: Linear → Log encoding (preserves full HDR range)
        float3 logRGB = encodeLog(rgb, uniforms.logCurveType);
        
        // Step 5: Apply saturation in Log space (better hue stability)
        logRGB = applySaturation(logRGB, uniforms.saturation);
        
        // Step 6: Apply contrast in Log space (around middle gray pivot)
        logRGB = applyContrast(logRGB, uniforms.contrast, uniforms.contrastPivot);
        
        // Step 7: Apply shadow/highlight recovery in Log space
        logRGB = applyShadowHighlight(logRGB, uniforms.shadows, uniforms.highlights, uniforms.contrastPivot);
        
        output.write(float4(logRGB, pixel.a), gid);
    }
    
    // XYZ Pipeline with LUT (combined for single-pass efficiency)
    kernel void processXYZPipelineWithLUT(
        texture2d<float, access::read> input [[texture(0)]],
        texture2d<float, access::write> output [[texture(1)]],
        texture3d<float, access::sample> lut [[texture(2)]],
        sampler lutSampler [[sampler(0)]],
        constant XYZPipelineUniforms& uniforms [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
        
        // Read XYZ(D65) pixel (camera WB already applied by LibRaw)
        float4 pixel = input.read(gid);
        float3 xyz = pixel.rgb;
        
        // Step 1: XYZ(D65) → Target Gamut RGB
        float3 rgb = uniforms.colorMatrix * xyz;
        
        // Step 2: Apply relative WB adjustment in RGB space (for real-time tint/temp)
        rgb *= uniforms.wbMultipliers.xyz;
        
        // Step 3: Apply exposure
        rgb *= uniforms.exposure;
        
        // Step 3: Apply tint in linear space
        rgb = applyTint(rgb, uniforms.tint);
        
        // Step 4: Linear → Log encoding (preserves full HDR range)
        float3 logRGB = encodeLog(rgb, uniforms.logCurveType);
        
        // Step 5: Apply saturation in Log space (better hue stability)
        logRGB = applySaturation(logRGB, uniforms.saturation);
        
        // Step 6: Apply contrast in Log space (around middle gray pivot)
        logRGB = applyContrast(logRGB, uniforms.contrast, uniforms.contrastPivot);
        
        // Step 7: Apply shadow/highlight recovery in Log space
        logRGB = applyShadowHighlight(logRGB, uniforms.shadows, uniforms.highlights, uniforms.contrastPivot);
        
        // Step 8: Apply LUT (contains display transform and highlight roll-off)
        float3 final = lut.sample(lutSampler, clamp(logRGB, 0.0, 1.0)).rgb;
        
        output.write(float4(final, pixel.a), gid);
    }
    
    // (Removed Standard RGB Pipeline kernels - were only used for JPG processing)
    """
}
