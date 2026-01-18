import Metal
import CoreImage
import simd

// MARK: - Log Profile Enum

enum NativeLogProfile: String, CaseIterable {
    // Fujifilm
    case fLog2 = "F-Log2"
    case fLog = "F-Log"
    // Sony
    case sLog3 = "S-Log3"
    case sLog3Cine = "S-Log3.Cine"
    // Panasonic
    case vLog = "V-Log"
    // Nikon
    case nLog = "N-Log"
    // Canon
    case canonLog2 = "Canon Log 2"
    case canonLog3 = "Canon Log 3"
    // ARRI
    case arriLogC3 = "ARRI LogC3"
    case arriLogC4 = "ARRI LogC4"
    // RED
    case log3G10 = "Log3G10"
    // Leica
    case lLog = "L-Log"
    // Blackmagic
    case davinciIntermediate = "DaVinci Intermediate"
    
    /// Metal kernel name for this profile
    var kernelName: String {
        switch self {
        case .fLog2: return "linearToFLog2"
        case .fLog: return "linearToFLog"
        case .sLog3, .sLog3Cine: return "linearToSLog3"
        case .vLog: return "linearToVLog"
        case .nLog: return "linearToNLog"
        case .canonLog2: return "linearToCanonLog2"
        case .canonLog3: return "linearToCanonLog3"
        case .arriLogC3: return "linearToArriLogC3"
        case .arriLogC4: return "linearToArriLogC4"
        case .log3G10: return "linearToLog3G10"
        case .lLog: return "linearToLLog"
        case .davinciIntermediate: return "linearToDaVinciIntermediate"
        }
    }
    
    /// Target color gamut matrix (XYZ → Target)
    var gamutMatrix: simd_float3x3 {
        switch self {
        case .fLog2, .fLog, .nLog, .lLog:
            return ColorMatrices.XYZ_to_Rec2020
        case .sLog3:
            return ColorMatrices.XYZ_to_SGamut3
        case .sLog3Cine:
            return ColorMatrices.XYZ_to_SGamut3Cine
        case .vLog:
            return ColorMatrices.XYZ_to_VGamut
        case .canonLog2, .canonLog3:
            return ColorMatrices.XYZ_to_CinemaGamut
        case .arriLogC3:
            return ColorMatrices.XYZ_to_AWG3
        case .arriLogC4:
            return ColorMatrices.XYZ_to_AWG4
        case .log3G10:
            return ColorMatrices.XYZ_to_REDWideGamut
        case .davinciIntermediate:
            return ColorMatrices.XYZ_to_DaVinciWideGamut
        }
    }
    
    /// Log-encoded value of 18% gray (middle gray)
    /// Used as pivot point for contrast adjustments
    /// These values are calculated by encoding 0.18 linear through each OETF
    var middleGray: Float {
        switch self {
        case .fLog2: return 0.383      // F-Log2(0.18) ≈ 0.383
        case .fLog: return 0.427       // F-Log(0.18) ≈ 0.427
        case .sLog3, .sLog3Cine: return 0.410  // S-Log3(0.18) ≈ 0.410
        case .vLog: return 0.423       // V-Log(0.18) ≈ 0.423
        case .nLog: return 0.346       // N-Log(0.18) ≈ 0.346
        case .canonLog2: return 0.392  // Canon Log 2(0.18) ≈ 0.392
        case .canonLog3: return 0.343  // Canon Log 3(0.18) ≈ 0.343
        case .arriLogC3: return 0.391  // LogC3(0.18) ≈ 0.391
        case .arriLogC4: return 0.418  // LogC4(0.18) ≈ 0.418
        case .log3G10: return 0.333    // Log3G10(0.18) ≈ 0.333
        case .lLog: return 0.450       // L-Log(0.18) ≈ 0.450
        case .davinciIntermediate: return 0.336  // DI(0.18) ≈ 0.336 (Blackmagic spec)
        }
    }
}


// MARK: - Pipeline Configuration

struct NativePipelineConfig {
    /// Log profile to use
    var logProfile: NativeLogProfile = .fLog2
    
    /// Exposure in EV stops (0 = neutral)
    var exposureEV: Float = 0
    
    /// Auto exposure enable (disabled by default - manual mode preferred)
    var autoExposure: Bool = false
    
    /// White balance multipliers (R, G, B) - applied in GPU shader
    /// Default (1,1,1) = no adjustment. Use camera WB from LibRawImage on load.
    var wbMultipliers: simd_float3 = simd_float3(1, 1, 1)
    
    /// White balance tint (-100 = green, +100 = magenta, 0 = neutral)
    var tint: Float = 0
    
    /// Soft clip knee point (linear value)
    var softClipKnee: Float = 0.9
    
    /// Soft clip ceiling
    var softClipCeiling: Float = 1.5
    
    /// Enable noise reduction
    var noiseReduction: Bool = false
    
    /// Saturation adjustment (1.0 = neutral, 0 = grayscale, 2 = double)
    var saturation: Float = 1.0
    
    /// Contrast adjustment (1.0 = neutral)
    var contrast: Float = 1.0
    
    /// Shadow recovery (-100 to +100, 0 = neutral, positive = lift shadows)
    var shadows: Float = 0.0
    
    /// Highlight recovery (-100 to +100, 0 = neutral, negative = compress highlights)
    var highlights: Float = 0.0
}

// MARK: - RAW Metadata

/// Metadata extracted from RAW file
struct RawMetadata {
    var cameraMaker: String?
    var cameraModel: String?
    var cameraWhitePoint: simd_float2?
    var colorTemperature: Float?
    var tint: Float?
    var iso: Int?
    var exposureTime: Double?
    var fNumber: Float?
    var imageSize: CGSize?
    var outputColorSpace: CGColorSpace?
}

// MARK: - Processing Result

struct NativePipelineResult {
    /// Processed CIImage
    var image: CIImage
    
    /// Auto-calculated exposure gain
    var autoExposureGain: Float = 1.0
    
    /// Auto-calculated exposure EV
    var autoExposureEV: Float = 0
    
    /// Processing time in milliseconds
    var processingTimeMs: Double = 0
    
    /// Metadata extracted from RAW
    var metadata: RawMetadata?
    
    /// Camera white balance multipliers (for UI initialization)
    var cameraWB: simd_float3 = simd_float3(1, 1, 1)
    
    /// Estimated color temperature in Kelvin
    var colorTemperature: Float = 6500
}

// MARK: - Native Color Pipeline

/// Full native Swift/Metal color pipeline
/// Replaces Python backend for RAW → Log → LUT processing
@MainActor
class NativeColorPipeline: ObservableObject {
    
    // MARK: - Properties
    
    /// Metal pipeline manager
    private let metalPipeline: MetalPipeline
    
    /// LibRaw decoder (XYZ output - wide gamut)
    private var librawDecoder: LibRawXYZDecoder?
    
    /// Current LUT (optional)
    private var currentLUT: Lut3D?
    
    /// CIContext for Core Image operations
    private let ciContext: CIContext
    
    /// Extended linear P3 color space
    private let linearP3: CGColorSpace
    
    /// Published processing state
    @Published var isProcessing: Bool = false
    @Published var lastResult: NativePipelineResult?
    
    /// Cached Log encoding kernels (pre-compiled for performance)
    private var logKernels: [NativeLogProfile: CIColorKernel] = [:]
    
    // MARK: - XYZ Texture Caching (for real-time slider updates)
    
    /// Cached XYZ texture (pure, no WB baked) - reused across parameter changes
    private var cachedXYZTexture: MTLTexture?
    
    /// URL of currently cached image (for cache invalidation)
    private var cachedImageURL: URL?
    
    /// Cached LibRaw metadata (WB multipliers, exposure, etc.)
    private var cachedMetadata: LibRawImage?
    
    /// Output texture (reused to avoid allocations)
    private var cachedOutputTexture: MTLTexture?
    
    // MARK: - Initialization
    
    init() throws {
        self.metalPipeline = try MetalPipeline()
        
        // Initialize LibRaw decoder for wide gamut XYZ output
        self.librawDecoder = LibRawXYZDecoder(device: metalPipeline.device)
        
        guard let linearP3 = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) else {
            throw MetalPipelineError.deviceNotFound
        }
        self.linearP3 = linearP3
        
        self.ciContext = CIContext(mtlDevice: metalPipeline.device, options: [
            .workingColorSpace: linearP3,
            .outputColorSpace: linearP3,
            .useSoftwareRenderer: false
        ])
        
        // Pre-compile all Log kernels for performance (avoid per-frame compilation)
        precompileLogKernels()
        
        print("🎬 NativeColorPipeline initialized with \(logKernels.count) pre-compiled Log kernels")
        print("   ✅ LibRaw XYZ decoder ready for wide gamut processing")
    }
    
    // MARK: - Kernel Pre-compilation
    
    private func precompileLogKernels() {
        for profile in NativeLogProfile.allCases {
            if let kernel = compileLogKernel(for: profile) {
                logKernels[profile] = kernel
                print("   ✅ Pre-compiled \(profile.rawValue) kernel")
            }
        }
    }
    
    private func compileLogKernel(for profile: NativeLogProfile) -> CIColorKernel? {
        let source = logKernelSource(for: profile)
        do {
            let kernels = try CIKernel.kernels(withMetalString: source)
            return kernels.first as? CIColorKernel
        } catch {
            print("❌ Failed to compile \(profile.rawValue) kernel: \(error)")
            return nil
        }
    }
    
    // MARK: - LUT Management
    
    /// Currently loaded LUT URL (for cache validation)
    private var currentLUTURL: URL?
    
    /// Cached CIColorCube data (avoid recreating every frame)
    private var cachedColorCubeData: Data?
    
    /// Load a .cube LUT file (with caching - only reloads if URL changed)
    func loadLUT(from url: URL) throws {
        // Skip if same LUT already loaded
        if currentLUTURL == url && currentLUT != nil {
            return
        }
        
        // Release old LUT first
        currentLUT = nil
        cachedColorCubeData = nil
        
        // Load new LUT
        currentLUT = try Lut3D(device: metalPipeline.device, cubeFileURL: url)
        currentLUTURL = url
        
        // Pre-cache the CIColorCube data
        cachedColorCubeData = currentLUT?.toCIColorCubeData()
        print("🎨 LUT loaded: \(url.lastPathComponent)")
    }
    
    /// Remove current LUT
    func removeLUT() {
        currentLUT = nil
        currentLUTURL = nil
        cachedColorCubeData = nil
        print("🎨 LUT removed")
    }
    
    // MARK: - LibRaw XYZ Pipeline Processing
    
    /// Map NativeLogProfile to Metal LogCurveType
    private func metalLogCurveType(for profile: NativeLogProfile) -> LogCurveType {
        switch profile {
        case .fLog2: return .fLog2
        case .fLog: return .fLog   // F-Log (v1) now separate from F-Log2
        case .sLog3, .sLog3Cine: return .sLog3
        case .vLog: return .vLog
        case .nLog: return .nLog
        case .canonLog2: return .canonLog2
        case .canonLog3: return .canonLog3
        case .arriLogC3: return .arriLogC3
        case .arriLogC4: return .arriLogC4
        case .log3G10: return .log3G10
        case .lLog: return .lLog
        case .davinciIntermediate: return .davinciIntermediate
        }
    }
    
    /// Process RAW using LibRaw XYZ pipeline (wide gamut)
    /// RAW → XYZ(D50) → Gamut → Log → LUT → Display
    /// Caches XYZ texture for real-time slider updates via updateProcessingFast()
    func processRAWWithLibRaw(
        url: URL,
        config: NativePipelineConfig,
        completion: @escaping (Result<NativePipelineResult, Error>) -> Void
    ) {
        let startTime = CFAbsoluteTimeGetCurrent()
        isProcessing = true
        
        Task {
            do {
                guard let decoder = librawDecoder else {
                    throw LibRawError.decodeFailed("LibRaw decoder not initialized")
                }
                
                // Check cache: if same URL and texture exists, use fast path
                var xyzImage: LibRawImage
                var inputTexture: MTLTexture
                let needsDecode = cachedImageURL != url || cachedXYZTexture == nil
                
                if needsDecode {
                    // Step 1: Decode RAW to XYZ (D65) using LibRaw
                    let decodeStart = CFAbsoluteTimeGetCurrent()
                    xyzImage = try decoder.decode(url: url)
                    let decodeTime = CFAbsoluteTimeGetCurrent() - decodeStart
                    print("📷 LibRaw decode: \(String(format: "%.3f", decodeTime))s")
                    
                    // Step 2: Create and cache input texture
                    inputTexture = try createTextureFromBuffer(
                        xyzImage.xyzBuffer,
                        width: xyzImage.width,
                        height: xyzImage.height
                    )
                    
                    // Cache for fast updates
                    cachedXYZTexture = inputTexture
                    cachedImageURL = url
                    cachedMetadata = xyzImage
                    
                    print("📦 XYZ texture cached for real-time updates")
                } else {
                    // Use cached texture (fast path)
                    inputTexture = cachedXYZTexture!
                    xyzImage = cachedMetadata!
                    print("⚡ Using cached XYZ texture (fast path)")
                }
                
                // Step 3: Get combined matrix (XYZ D65 → Target Gamut RGB)
                // Use precise vendor gamut matrix directly from NativeLogProfile
                let colorMatrix = config.logProfile.gamutMatrix
                
                // DEBUG: Analyze XYZ and predicted RGB values (only on first decode)
                if needsDecode {
                    self.analyzePipelineValues(
                        buffer: xyzImage.xyzBuffer,
                        width: xyzImage.width,
                        height: xyzImage.height,
                        colorMatrix: colorMatrix
                    )
                }
                
                // Step 4: Calculate exposure with smart compensation
                // Priority: DNG BaselineExposure > Hybrid Auto-Exposure
                // Then apply Log middle gray compensation
                
                var baseAutoEV: Float
                if xyzImage.hasBaselineExposure {
                    // Use DNG BaselineExposure + small boost (tends to be conservative)
                    baseAutoEV = xyzImage.baselineExposure + 0.5
                    print("📊 DNG BaselineExposure: \(String(format: "%+.2f", xyzImage.baselineExposure)) EV (+0.5 boost)")
                } else {
                    // Fallback: Hybrid auto-exposure (gray + white anchor)
                    baseAutoEV = calculateAutoExposureEV(
                        buffer: xyzImage.xyzBuffer,
                        width: xyzImage.width,
                        height: xyzImage.height
                    )
                }
                
                // Calculate Log middle gray compensation
                // This ensures images are properly exposed for the target Log profile
                let middleGrayCompensation = calculateMiddleGrayCompensation(
                    buffer: xyzImage.xyzBuffer,
                    width: xyzImage.width,
                    height: xyzImage.height,
                    currentEV: baseAutoEV,
                    targetMiddleGray: config.logProfile.middleGray
                )
                
                let calculatedAutoEV = baseAutoEV + middleGrayCompensation
                print("📊 Smart Auto-Exposure: base=\(String(format: "%+.2f", baseAutoEV)) compensation=\(String(format: "%+.2f", middleGrayCompensation)) → total=\(String(format: "%+.2f", calculatedAutoEV)) EV")
                
                // Determine which EV to use:
                // - Auto mode: use calculated auto EV + any manual offset
                // - Manual mode: use only manual EV (auto EV stored for reference)
                let effectiveEV: Float
                if config.autoExposure {
                    effectiveEV = config.exposureEV + calculatedAutoEV
                } else {
                    effectiveEV = config.exposureEV  // Manual mode: use only manual value
                }
                
                let exposureGain = pow(2.0, effectiveEV)
                print("📊 Exposure: manual=\(String(format: "%+.2f", config.exposureEV)) auto=\(String(format: "%+.2f", calculatedAutoEV)) mode=\(config.autoExposure ? "AUTO" : "MANUAL") → gain=\(String(format: "%.3f", exposureGain))×")
                
                // Step 5: Create uniforms for Metal kernel
                // Note: Camera WB is already applied by LibRaw during decode
                // wbMultipliers here is for RELATIVE adjustment only (1,1,1 = no change)
                // If user adjusts WB sliders, config.wbMultipliers will differ from (1,1,1)
                
                var uniforms = XYZPipelineUniforms(
                    colorMatrix: colorMatrix,
                    exposure: exposureGain,
                    softClipKnee: config.softClipKnee,
                    softClipCeiling: config.softClipCeiling,
                    logCurve: metalLogCurveType(for: config.logProfile),
                    saturation: config.saturation,
                    contrast: config.contrast,
                    contrastPivot: config.logProfile.middleGray,  // Precise pivot per Log profile
                    tint: config.tint,
                    wbMultipliers: config.wbMultipliers,  // Default (1,1,1) = no adjustment
                    shadows: config.shadows,
                    highlights: config.highlights
                )
                
                // Step 6: Create or reuse output texture
                if cachedOutputTexture == nil ||
                   cachedOutputTexture!.width != xyzImage.width ||
                   cachedOutputTexture!.height != xyzImage.height {
                    cachedOutputTexture = try metalPipeline.createTexture(
                        width: xyzImage.width,
                        height: xyzImage.height,
                        format: .rgba32Float,
                        usage: [.shaderRead, .shaderWrite],
                        storageMode: .shared
                    )
                }
                let outputTexture = cachedOutputTexture!
                
                // Step 7: Dispatch Metal compute kernel
                let gpuStart = CFAbsoluteTimeGetCurrent()
                
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    if let lut = currentLUT {
                        let lutTexture = lut.texture
                        // Use LUT-enabled pipeline with 3D texture
                        metalPipeline.dispatchComputeWithLUT(
                            pipelineName: "processXYZPipelineWithLUT",
                            inputTexture: inputTexture,
                            outputTexture: outputTexture,
                            lutTexture: lutTexture,
                            uniforms: &uniforms,
                            uniformsSize: MemoryLayout<XYZPipelineUniforms>.size
                        ) { success in
                            if success {
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: MetalPipelineError.commandBufferFailed)
                            }
                        }
                    } else {
                        // No LUT, use basic pipeline
                        metalPipeline.dispatchCompute(
                            pipelineName: "processXYZPipeline",
                            inputTexture: inputTexture,
                            outputTexture: outputTexture,
                            uniforms: &uniforms,
                            uniformsSize: MemoryLayout<XYZPipelineUniforms>.size
                        ) { success in
                            if success {
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: MetalPipelineError.commandBufferFailed)
                            }
                        }
                    }
                }
                
                let gpuTime = CFAbsoluteTimeGetCurrent() - gpuStart
                print("🎨 GPU processing: \(String(format: "%.3f", gpuTime))s")
                
                // Step 8: Convert output texture to CIImage for display
                let ciImage = CIImage(mtlTexture: outputTexture, options: [
                    .colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!
                ])?.oriented(.downMirrored)
                
                guard let finalImage = ciImage else {
                    throw MetalPipelineError.textureCreationFailed
                }
                
                let totalTime = CFAbsoluteTimeGetCurrent() - startTime
                print("✅ LibRaw pipeline total: \(String(format: "%.3f", totalTime))s\(needsDecode ? "" : " (cached)")")
                
                // Create result
                var result = NativePipelineResult(
                    image: finalImage,
                    autoExposureGain: exposureGain,
                    autoExposureEV: calculatedAutoEV,  // Always provide calculated auto EV for UI
                    processingTimeMs: totalTime * 1000,
                    metadata: nil,
                    cameraWB: xyzImage.wbMultipliers,  // Camera WB for UI initialization
                    colorTemperature: xyzImage.colorTemperature
                )
                result.metadata = RawMetadata(
                    cameraMaker: nil,
                    cameraModel: nil,
                    cameraWhitePoint: nil,
                    colorTemperature: nil,
                    tint: nil,
                    iso: nil,
                    exposureTime: nil,
                    fNumber: nil,
                    imageSize: CGSize(width: xyzImage.width, height: xyzImage.height),
                    outputColorSpace: nil
                )
                
                await MainActor.run {
                    self.lastResult = result
                    self.isProcessing = false
                    completion(.success(result))
                }
                
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Fast Processing (Cached Texture)
    
    /// Fast processing using cached XYZ texture - for real-time slider adjustments
    /// Only updates uniforms and dispatches shader, no RAW decoding or P3→XYZ conversion
    /// Works for both RAW (via processRAWWithLibRaw) and standard images (via processStandardImageWithMetal)
    func updateProcessingFast(
        config: NativePipelineConfig,
        completion: @escaping (Result<NativePipelineResult, Error>) -> Void
    ) {
        guard let inputTexture = cachedXYZTexture else {
            // No cache available - trigger full processing
            if let url = cachedImageURL {
                // RAW file fallback
                processRAWWithLibRaw(url: url, config: config, completion: completion)
            } else {
                // No fallback available for standard images (they need linearImage which we don't store)
                completion(.failure(MetalPipelineError.textureCreationFailed))
            }
            return
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Get optional metadata (only available for RAW files)
        let metadata = cachedMetadata
        
        Task {
            do {
                
                // Calculate exposure
                // For RAW: use baselineExposure from metadata when in auto mode
                // For standard images: just use config.exposureEV
                let baselineEV = metadata?.baselineExposure ?? 0
                let effectiveEV: Float = config.autoExposure ? 
                    (config.exposureEV + baselineEV) : config.exposureEV
                let exposureGain = pow(2.0, effectiveEV)
                
                // Reuse output texture
                guard let outputTexture = cachedOutputTexture else {
                    throw MetalPipelineError.textureCreationFailed
                }
                
                // RAW image processing (XYZ pipeline)
                // Use precise vendor gamut matrix directly from NativeLogProfile
                let colorMatrix = config.logProfile.gamutMatrix
                
                var uniforms = XYZPipelineUniforms(
                    colorMatrix: colorMatrix,
                    exposure: exposureGain,
                    softClipKnee: config.softClipKnee,
                    softClipCeiling: config.softClipCeiling,
                    logCurve: metalLogCurveType(for: config.logProfile),
                    saturation: config.saturation,
                    contrast: config.contrast,
                    contrastPivot: config.logProfile.middleGray,
                    tint: config.tint,
                    wbMultipliers: config.wbMultipliers,
                    shadows: config.shadows,
                    highlights: config.highlights
                )
                
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    if let lut = currentLUT {
                        metalPipeline.dispatchComputeWithLUT(
                            pipelineName: "processXYZPipelineWithLUT",
                            inputTexture: inputTexture,
                            outputTexture: outputTexture,
                            lutTexture: lut.texture,
                            uniforms: &uniforms,
                            uniformsSize: MemoryLayout<XYZPipelineUniforms>.size
                        ) { success in
                            success ? continuation.resume() : continuation.resume(throwing: MetalPipelineError.commandBufferFailed)
                        }
                    } else {
                        metalPipeline.dispatchCompute(
                            pipelineName: "processXYZPipeline",
                            inputTexture: inputTexture,
                            outputTexture: outputTexture,
                            uniforms: &uniforms,
                            uniformsSize: MemoryLayout<XYZPipelineUniforms>.size
                        ) { success in
                            success ? continuation.resume() : continuation.resume(throwing: MetalPipelineError.commandBufferFailed)
                        }
                    }
                }
                
                // Convert to CIImage (RAW needs .downMirrored due to texture Y-axis flip)
                guard let finalImage = CIImage(mtlTexture: outputTexture, options: [
                    .colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!
                ])?.oriented(.downMirrored) else {
                    throw MetalPipelineError.textureCreationFailed
                }
                
                let processingTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                print("⚡ Fast update: \(String(format: "%.1f", processingTime))ms")
                
                // Use metadata values if available, otherwise use defaults
                let result = NativePipelineResult(
                    image: finalImage,
                    autoExposureGain: exposureGain,
                    autoExposureEV: baselineEV,
                    processingTimeMs: processingTime,
                    metadata: nil,
                    cameraWB: metadata?.wbMultipliers ?? simd_float3(1, 1, 1),
                    colorTemperature: metadata?.colorTemperature ?? 6500
                )
                
                await MainActor.run {
                    // Don't update lastResult during real-time updates - it holds CIImage/MTLTexture refs
                    // lastResult is only needed for export and is set during initial processRAWWithLibRaw
                    completion(.success(result))
                }
                
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Create MTLTexture from XYZ buffer
    private func createTextureFromBuffer(_ buffer: MTLBuffer, width: Int, height: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,  // Full Float32 precision to match buffer
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        
        guard let texture = metalPipeline.device.makeTexture(descriptor: descriptor) else {
            throw MetalPipelineError.textureCreationFailed
        }
        
        // Copy buffer data to texture
        // XYZ buffer is RGB interleaved Float32, need to add alpha channel
        let bytesPerRow = width * 4 * MemoryLayout<Float>.size  // RGBA Float32
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: width, height: height, depth: 1))
        
        // Create RGBA buffer from RGB (Float32)
        let pixelCount = width * height
        let srcPtr = buffer.contents().bindMemory(to: Float.self, capacity: pixelCount * 3)
        var rgbaData = [Float](repeating: 0, count: pixelCount * 4)
        
        for i in 0..<pixelCount {
            rgbaData[i * 4 + 0] = srcPtr[i * 3 + 0]  // X/R
            rgbaData[i * 4 + 1] = srcPtr[i * 3 + 1]  // Y/G
            rgbaData[i * 4 + 2] = srcPtr[i * 3 + 2]  // Z/B
            rgbaData[i * 4 + 3] = 1.0                // A (full opacity)
        }
        
        rgbaData.withUnsafeBytes { ptr in
            texture.replace(region: region, mipmapLevel: 0, withBytes: ptr.baseAddress!, bytesPerRow: bytesPerRow)
        }
        
        return texture
    }
    
    /// Convert MTLTexture to CIImage by copying pixel data (avoids memory leak)
    /// This creates an independent CIImage that doesn't hold a reference to the texture
    private func textureToCIImage(_ texture: MTLTexture) -> CIImage? {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4 * MemoryLayout<Float>.size  // RGBA Float32
        let bufferSize = bytesPerRow * height
        
        // Read pixel data from GPU texture to CPU buffer
        var pixelData = [Float](repeating: 0, count: width * height * 4)
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: width, height: height, depth: 1))
        
        pixelData.withUnsafeMutableBytes { ptr in
            texture.getBytes(ptr.baseAddress!, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        }
        
        // Create CGImage from pixel data (Display P3, Float32)
        // Note: We flip Y here since Metal textures are upside-down
        let data = Data(bytes: pixelData, count: bufferSize)
        
        guard let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) else {
            return nil
        }
        
        // Create CIImage from raw data - this owns the data, not the texture
        let ciImage = CIImage(
            bitmapData: data,
            bytesPerRow: bytesPerRow,
            size: CGSize(width: width, height: height),
            format: .RGBAf,  // Float32 RGBA
            colorSpace: colorSpace
        )
        
        // Flip vertically (Metal textures are upside-down)
        return ciImage.oriented(.downMirrored)
    }
    
    // MARK: - Auto-Exposure Estimation
    
    /// Calculate auto-exposure EV using hybrid strategy:
    /// 1. Middle Gray Anchor: Target 18% gray for proper Log encoding
    /// 2. White Point Anchor: Prevent highlight clipping
    /// Uses the more conservative (smaller) EV to avoid overexposure
    ///
    /// - Parameters:
    ///   - buffer: Metal buffer containing Float32 XYZ data (RGB interleaved)
    ///   - width: Image width
    ///   - height: Image height
    /// - Returns: Recommended EV adjustment to normalize exposure
    private func calculateAutoExposureEV(buffer: MTLBuffer, width: Int, height: Int) -> Float {
        let srcPtr = buffer.contents().bindMemory(to: Float.self, capacity: width * height * 3)
        
        // Sample parameters
        let sampleStep = max(1, min(width, height) / 200)  // ~40000 samples for full image analysis
        
        // Statistics
        var totalY: Double = 0
        var maxY: Float = 0
        var sampleCount: Int = 0
        
        // Sample entire image with step for performance
        for y in stride(from: 0, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let pixelIndex = (y * width + x) * 3
                let yValue = srcPtr[pixelIndex + 1]  // Y channel (luminance)
                
                totalY += Double(yValue)
                maxY = max(maxY, yValue)
                sampleCount += 1
            }
        }
        
        let avgLuminance = Float(totalY / Double(sampleCount))
        
        // Strategy 1: Middle Gray Anchor (18% gray)
        let targetGray: Float = 0.18
        var grayEV: Float = 0
        if avgLuminance > 0.001 {
            grayEV = log2(targetGray / avgLuminance)
        } else {
            grayEV = 4.0  // Maximum boost for very dark images
        }
        
        // Strategy 2: White Point Anchor (prevent clipping)
        // Target: Keep maximum value below soft clip knee after exposure
        // Assuming soft clip starts at 0.9, we want max * gain < 0.9
        let targetWhite: Float = 0.9
        var whiteEV: Float = 6.0  // Default high value
        if maxY > 0.001 {
            whiteEV = log2(targetWhite / maxY)
        }
        
        // Hybrid: Use the more conservative (smaller) EV
        // This ensures we don't clip highlights while still brightening dark images
        let autoEV = min(grayEV, whiteEV)
        
        // Clamp to reasonable range: -4 to +6 EV
        let clampedEV = max(-4.0, min(6.0, autoEV))
        
        print("📊 Auto-exposure (hybrid):")
        print("   Gray anchor: avgY=\(String(format: "%.4f", avgLuminance)) → EV=\(String(format: "%+.2f", grayEV))")
        print("   White anchor: maxY=\(String(format: "%.4f", maxY)) → EV=\(String(format: "%+.2f", whiteEV))")
        print("   → Selected: EV=\(String(format: "%+.2f", clampedEV)) (\(grayEV <= whiteEV ? "gray" : "white") limited)")
        
        return clampedEV
    }
    
    /// Calculate middle gray compensation based on estimated Log output
    /// This ensures the image's middle gray falls at the correct position for the target Log profile
    /// - Parameters:
    ///   - buffer: Metal buffer containing Float32 XYZ data
    ///   - width: Image width
    ///   - height: Image height  
    ///   - currentEV: Current planned exposure EV
    ///   - targetMiddleGray: The Log profile's standard middle gray (e.g., 0.38 for F-Log2)
    /// - Returns: Additional EV compensation to apply
    private func calculateMiddleGrayCompensation(
        buffer: MTLBuffer,
        width: Int,
        height: Int,
        currentEV: Float,
        targetMiddleGray: Float
    ) -> Float {
        let srcPtr = buffer.contents().bindMemory(to: Float.self, capacity: width * height * 3)
        
        // Sample parameters - use center-weighted sampling for better exposure estimation
        let sampleStep = max(1, min(width, height) / 150)
        
        // Calculate weighted average luminance (center-weighted)
        let centerX = width / 2
        let centerY = height / 2
        let maxDist = sqrt(Float(centerX * centerX + centerY * centerY))
        
        var weightedSum: Double = 0
        var totalWeight: Double = 0
        
        for y in stride(from: 0, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let pixelIndex = (y * width + x) * 3
                let yValue = srcPtr[pixelIndex + 1]  // Y channel (luminance)
                
                // Center-weighted: pixels near center have higher weight
                let dx = Float(x - centerX)
                let dy = Float(y - centerY)
                let dist = sqrt(dx * dx + dy * dy)
                let weight = Double(1.0 - (dist / maxDist) * 0.5)  // 1.0 at center, 0.5 at corners
                
                weightedSum += Double(yValue) * weight
                totalWeight += weight
            }
        }
        
        let avgLuminance = Float(weightedSum / totalWeight)
        
        // Simulate exposure application
        let exposedLuminance = avgLuminance * pow(2.0, currentEV)
        
        // Estimate what the Log-encoded middle gray would be
        // Using a simplified Log approximation (actual encoding varies by profile)
        // For scene-referred 18% gray (0.18 linear), most Log profiles encode to their middleGray
        let linearMiddleGray: Float = 0.18
        
        // If exposed luminance equals 0.18, it should encode to targetMiddleGray
        // If it's different, we need compensation
        guard exposedLuminance > 0.001 else {
            return min(2.0, max(0.0, log2(linearMiddleGray / 0.01)))  // Very dark, boost needed
        }
        
        // Calculate how far off we are from ideal 18% gray
        let ratioToIdeal = linearMiddleGray / exposedLuminance
        
        // Convert to EV, but limit the compensation range
        var compensationEV = log2(ratioToIdeal)
        
        // Clamp compensation to reasonable range (-1 to +1.5 EV)
        // We don't want to over-brighten or over-darken
        compensationEV = max(-1.0, min(1.5, compensationEV))
        
        // Only apply compensation if image appears underexposed
        // (avoid making already bright images too bright)
        if compensationEV < 0 && exposedLuminance > linearMiddleGray {
            compensationEV = 0  // Already bright enough, no negative compensation
        }
        
        print("📊 Middle gray compensation: avgY=\(String(format: "%.4f", avgLuminance)) exposed=\(String(format: "%.4f", exposedLuminance)) target=\(String(format: "%.2f", targetMiddleGray)) → \(String(format: "%+.2f", compensationEV)) EV")
        
        return compensationEV
    }
    
    // MARK: - Pipeline Diagnostics
    
    /// Analyze XYZ values and simulate RGB matrix conversion to detect issues
    /// This helps diagnose contrast problems by checking for negative RGB values
    private func analyzePipelineValues(buffer: MTLBuffer, width: Int, height: Int, colorMatrix: simd_float3x3) {
        // Sample a grid of pixels for analysis (not all pixels for performance)
        let sampleStep = max(1, min(width, height) / 100)  // ~10000 samples max
        
        let srcPtr = buffer.contents().bindMemory(to: Float.self, capacity: width * height * 3)
        
        var xyzMin = SIMD3<Float>(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var xyzMax = SIMD3<Float>(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        var xyzSum = SIMD3<Double>(0, 0, 0)
        
        var rgbMin = SIMD3<Float>(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var rgbMax = SIMD3<Float>(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        var rgbSum = SIMD3<Double>(0, 0, 0)
        
        var negativeCount = 0
        var sampleCount = 0
        
        for y in stride(from: 0, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let pixelIndex = (y * width + x) * 3
                
                let xyz = SIMD3<Float>(
                    srcPtr[pixelIndex + 0],
                    srcPtr[pixelIndex + 1],
                    srcPtr[pixelIndex + 2]
                )
                
                // Simulate color matrix conversion
                let rgb = colorMatrix * xyz
                
                // Update XYZ stats
                xyzMin = min(xyzMin, xyz)
                xyzMax = max(xyzMax, xyz)
                xyzSum += SIMD3<Double>(Double(xyz.x), Double(xyz.y), Double(xyz.z))
                
                // Update RGB stats
                rgbMin = min(rgbMin, rgb)
                rgbMax = max(rgbMax, rgb)
                rgbSum += SIMD3<Double>(Double(rgb.x), Double(rgb.y), Double(rgb.z))
                
                // Count negative values
                if rgb.x < 0 || rgb.y < 0 || rgb.z < 0 {
                    negativeCount += 1
                }
                
                sampleCount += 1
            }
        }
        
        let xyzAvg = SIMD3<Float>(Float(xyzSum.x / Double(sampleCount)), 
                                  Float(xyzSum.y / Double(sampleCount)), 
                                  Float(xyzSum.z / Double(sampleCount)))
        let rgbAvg = SIMD3<Float>(Float(rgbSum.x / Double(sampleCount)), 
                                  Float(rgbSum.y / Double(sampleCount)), 
                                  Float(rgbSum.z / Double(sampleCount)))
        let negativePercent = Double(negativeCount) / Double(sampleCount) * 100
        
        print("🔬 Pipeline Diagnostics (\(sampleCount) samples):")
        print("   XYZ range: [\(String(format: "%.4f", xyzMin.x)), \(String(format: "%.4f", xyzMin.y)), \(String(format: "%.4f", xyzMin.z))] → [\(String(format: "%.4f", xyzMax.x)), \(String(format: "%.4f", xyzMax.y)), \(String(format: "%.4f", xyzMax.z))]")
        print("   XYZ avg: [\(String(format: "%.4f", xyzAvg.x)), \(String(format: "%.4f", xyzAvg.y)), \(String(format: "%.4f", xyzAvg.z))]")
        print("   RGB range: [\(String(format: "%.4f", rgbMin.x)), \(String(format: "%.4f", rgbMin.y)), \(String(format: "%.4f", rgbMin.z))] → [\(String(format: "%.4f", rgbMax.x)), \(String(format: "%.4f", rgbMax.y)), \(String(format: "%.4f", rgbMax.z))]")
        print("   RGB avg: [\(String(format: "%.4f", rgbAvg.x)), \(String(format: "%.4f", rgbAvg.y)), \(String(format: "%.4f", rgbAvg.z))]")
        print("   ⚠️ Negative RGB values: \(negativeCount)/\(sampleCount) (\(String(format: "%.2f", negativePercent))%)")
    }
    // MARK: - Processing
    
    // (Removed JPG/PNG processing code - only RAW is now supported)

    /// Process a pre-loaded linear CIImage through the pipeline
    /// For standard images (JPG, PNG) that have already been loaded and linearized
    /// Linear Image → Exposure → CST → Log → LUT → Display
    func processImage(
        linearImage: CIImage,
        config: NativePipelineConfig,
        completion: @escaping (Result<NativePipelineResult, Error>) -> Void
    ) {
        let startTime = CFAbsoluteTimeGetCurrent()
        isProcessing = true
        
        Task {
            // Step 1: Calculate exposure gain from manual EV
            let exposureGain = pow(2.0, config.exposureEV)
            
            // Step 2: Apply exposure and soft clip
            let exposedImage = applyExposure(
                to: linearImage,
                gain: exposureGain,
                softClipKnee: config.softClipKnee,
                softClipCeiling: config.softClipCeiling
            )
            
            // Step 3: Color space transform (sRGB/P3 → XYZ → Target Gamut)
            var transformedImage = exposedImage
            
            // Note: For standard images (JPG/PNG), WB is already baked
            // The wbMultipliers in config could be used for tint/temp adjustment
            // but Bradford CAT is removed since colorTemperature field was removed
            
            // Apply tint adjustment
            if config.tint != 0 {
                transformedImage = applyTint(to: transformedImage, amount: config.tint)
            }
            
            // P3/sRGB → XYZ (assuming input is P3 linear from matchedToWorkingSpace)
            transformedImage = applyMatrix(ColorMatrices.P3_to_XYZ, to: transformedImage)
            
            // XYZ → Target Gamut
            transformedImage = applyMatrix(config.logProfile.gamutMatrix, to: transformedImage)
            
            // Step 4: Apply saturation in LINEAR space
            if config.saturation != 1.0 {
                transformedImage = applySaturation(to: transformedImage, amount: config.saturation)
            }
            
            // Step 5: Apply Log encoding
            var logImage = applyLogEncoding(to: transformedImage, profile: config.logProfile)
            
            // Step 6: Apply contrast in LOG space
            if config.contrast != 1.0 {
                logImage = applyContrast(to: logImage, amount: config.contrast, pivot: config.logProfile.middleGray)
            }
            
            // Step 7: Apply LUT if available
            var finalImage = logImage
            if let lut = currentLUT {
                finalImage = applyLUT(lut, to: logImage)
            }
            
            let processingTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            
            let result = NativePipelineResult(
                image: finalImage,
                autoExposureGain: exposureGain,
                autoExposureEV: config.exposureEV,
                processingTimeMs: processingTime,
                metadata: nil
            )
            
            await MainActor.run {
                self.lastResult = result
                self.isProcessing = false
                completion(.success(result))
            }
        }
    }
    
    // MARK: - Core Image Filters
    
    private func applyExposure(to image: CIImage, gain: Float, softClipKnee: Float, softClipCeiling: Float) -> CIImage {
        // Use CIColorMatrix for exposure
        // Then use soft clip (for now, just exposure - soft clip in Metal shader later)
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(gain), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(gain), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(gain), w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
    }
    
    private func applyMatrix(_ matrix: simd_float3x3, to image: CIImage) -> CIImage {
        // Convert simd_float3x3 to CIColorMatrix parameters
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(matrix[0][0]), y: CGFloat(matrix[1][0]), z: CGFloat(matrix[2][0]), w: 0),
            "inputGVector": CIVector(x: CGFloat(matrix[0][1]), y: CGFloat(matrix[1][1]), z: CGFloat(matrix[2][1]), w: 0),
            "inputBVector": CIVector(x: CGFloat(matrix[0][2]), y: CGFloat(matrix[1][2]), z: CGFloat(matrix[2][2]), w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
    }
    
    /// Apply saturation adjustment in Log space
    /// Uses CIColorControls for efficient saturation adjustment
    private func applySaturation(to image: CIImage, amount: Float) -> CIImage {
        // CIColorControls works well for saturation in any color space
        return image.applyingFilter("CIColorControls", parameters: [
            "inputSaturation": amount,
            "inputBrightness": 0,
            "inputContrast": 1
        ])
    }
    
    /// Apply contrast adjustment in Log space with proper pivot
    /// Pivots around the Log-encoded middle gray for the specific profile
    private func applyContrast(to image: CIImage, amount: Float, pivot: Float) -> CIImage {
        // Contrast formula: output = (input - pivot) * contrast + pivot
        // Using CIColorMatrix: R' = R*contrast + pivot*(1-contrast)
        let bias = pivot * (1.0 - amount)
        
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(amount), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(amount), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(amount), w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: CGFloat(bias), y: CGFloat(bias), z: CGFloat(bias), w: 0)
        ])
    }
    
    /// Apply tint (Green-Magenta) adjustment in linear space
    /// This should be applied BEFORE Log encoding
    private func applyTint(to image: CIImage, amount: Float) -> CIImage {
        // Tint range: -100 (green) to +100 (magenta)
        // Matches Metal shader applyTint function for consistency
        // -100 to +100 maps to 0.60x to 1.40x multiplier (40% range)
        // Positive tint = reduce green = multiply green by <1
        // Negative tint = increase green = multiply green by >1
        
        // Scale factor: -100 → 1.40, 0 → 1.0, +100 → 0.60
        let greenMultiplier = 1.0 - (amount / 250.0)   // ±0.4 range
        
        // Compensate slightly on R/B for perceptual balance
        let rbMultiplier = 1.0 + (amount / 500.0)      // ±0.2 range
        
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(rbMultiplier), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(greenMultiplier), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(rbMultiplier), w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
    }
    
    private func applyLogEncoding(to image: CIImage, profile: NativeLogProfile) -> CIImage {
        // Use pre-compiled cached kernel for performance
        guard let kernel = logKernels[profile] else {
            print("⚠️ Log kernel not found for \(profile.rawValue), returning original")
            return image
        }
        
        if let output = kernel.apply(extent: image.extent, arguments: [image]) {
            print("✅ Applied \(profile.rawValue) Log encoding (cached kernel)")
            return output
        }
        
        print("⚠️ Log encoding failed for \(profile.rawValue)")
        return image
    }
    
    // MARK: - Log Kernel Source Code
    
    private func logKernelSource(for profile: NativeLogProfile) -> String {
        switch profile {
        case .fLog2:
            // Fujifilm F-Log2 Data Sheet Ver.1.0
            return """
                #include <CoreImage/CoreImage.h>
                extern "C" { namespace coreimage {
                    [[ stitchable ]] float4 linearToFLog2(sample_t s) {
                        float3 x = s.rgb;
                        float3 y;
                        const float a = 5.555556;
                        const float b = 0.064829;
                        const float c = 0.245281;
                        const float d = 0.384316;
                        const float e = 8.799461;
                        const float f = 0.092864;
                        const float cut = 0.000889;
                        for (int i = 0; i < 3; i++) {
                            if (x[i] >= cut) { y[i] = c * log10(a * x[i] + b) + d; }
                            else { y[i] = e * x[i] + f; }
                        }
                        return float4(y, s.a);
                    }
                }}
            """
            
        case .fLog:
            // Fujifilm F-Log (Original) Data Sheet
            return """
                #include <CoreImage/CoreImage.h>
                extern "C" { namespace coreimage {
                    [[ stitchable ]] float4 linearToFLog(sample_t s) {
                        float3 x = s.rgb;
                        float3 y;
                        const float a = 0.555556;
                        const float b = 0.009468;
                        const float c = 0.344676;
                        const float d = 0.790453;
                        const float e = 8.735631;
                        const float f = 0.092864;
                        const float cut = 0.00089;
                        for (int i = 0; i < 3; i++) {
                            if (x[i] >= cut) { y[i] = c * log10(a * x[i] + b) + d; }
                            else { y[i] = e * x[i] + f; }
                        }
                        return float4(y, s.a);
                    }
                }}
            """
            
        case .sLog3, .sLog3Cine:
            // Sony S-Log3 Technical Summary (same OETF for both, different gamut)
            return """
                #include <CoreImage/CoreImage.h>
                extern "C" { namespace coreimage {
                    [[ stitchable ]] float4 linearToSLog3(sample_t s) {
                        float3 x = s.rgb;
                        float3 y;
                        for (int i = 0; i < 3; i++) {
                            if (x[i] >= 0.01125000) {
                                y[i] = (420.0 + log10((x[i] + 0.01) / (0.18 + 0.01)) * 261.5) / 1023.0;
                            } else {
                                y[i] = (x[i] * (171.2102946929 - 95.0) / 0.01125000 + 95.0) / 1023.0;
                            }
                        }
                        return float4(y, s.a);
                    }
                }}
            """
            
        case .vLog:
            // Panasonic V-Log/V-Gamut Reference Manual Rev.1.0
            return """
                #include <CoreImage/CoreImage.h>
                extern "C" { namespace coreimage {
                    [[ stitchable ]] float4 linearToVLog(sample_t s) {
                        float3 x = s.rgb;
                        float3 y;
                        const float cut1 = 0.01;
                        const float b = 0.00873;
                        const float c = 0.241514;
                        const float d = 0.598206;
                        for (int i = 0; i < 3; i++) {
                            if (x[i] < cut1) { y[i] = 5.6 * x[i] + 0.125; }
                            else { y[i] = c * log10(x[i] + b) + d; }
                        }
                        return float4(y, s.a);
                    }
                }}
            """
            
        case .nLog:
            // Nikon N-Log Specification Document
            return """
                #include <CoreImage/CoreImage.h>
                extern "C" { namespace coreimage {
                    [[ stitchable ]] float4 linearToNLog(sample_t s) {
                        float3 x = s.rgb;
                        float3 y;
                        const float cut = 0.328;
                        for (int i = 0; i < 3; i++) {
                            if (x[i] < cut) {
                                y[i] = 650.0 * pow(x[i] + 0.0075, 1.0/3.0) / 1023.0;
                            } else {
                                y[i] = (150.0 * log(x[i]) + 619.0) / 1023.0;
                            }
                        }
                        return float4(y, s.a);
                    }
                }}
            """
            
        case .canonLog2:
            // Canon Cinema EOS White Paper - C-Log2
            return """
                #include <CoreImage/CoreImage.h>
                extern "C" { namespace coreimage {
                    [[ stitchable ]] float4 linearToCanonLog2(sample_t s) {
                        float3 x = s.rgb;
                        float3 y;
                        for (int i = 0; i < 3; i++) {
                            if (x[i] >= 0.0) {
                                y[i] = 0.092809 * log10(x[i] * 16.332 + 1.0) + 0.24544;
                            } else {
                                y[i] = -0.092809 * log10(-x[i] * 2.141 + 1.0) + 0.092809;
                            }
                        }
                        return float4(y, s.a);
                    }
                }}
            """
            
        case .canonLog3:
            // Canon Cinema EOS White Paper - C-Log3
            return """
                #include <CoreImage/CoreImage.h>
                extern "C" { namespace coreimage {
                    [[ stitchable ]] float4 linearToCanonLog3(sample_t s) {
                        float3 x = s.rgb;
                        float3 y;
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
                        return float4(y, s.a);
                    }
                }}
            """
            
        case .arriLogC3:
            // ARRI LogC EI800 Specification
            return """
                #include <CoreImage/CoreImage.h>
                extern "C" { namespace coreimage {
                    [[ stitchable ]] float4 linearToArriLogC3(sample_t s) {
                        float3 x = s.rgb;
                        float3 y;
                        const float cut = 0.010591;
                        const float a = 5.555556;
                        const float b = 0.052272;
                        const float c = 0.247190;
                        const float d = 0.385537;
                        const float e = 5.367655;
                        const float f = 0.092809;
                        for (int i = 0; i < 3; i++) {
                            if (x[i] > cut) { y[i] = c * log10(a * x[i] + b) + d; }
                            else { y[i] = e * x[i] + f; }
                        }
                        return float4(y, s.a);
                    }
                }}
            """
            
        case .arriLogC4:
            // ARRI LogC4 Specification
            return """
                #include <CoreImage/CoreImage.h>
                extern "C" { namespace coreimage {
                    [[ stitchable ]] float4 linearToArriLogC4(sample_t s) {
                        float3 x = s.rgb;
                        float3 y;
                        const float a = 2231.826398;
                        const float b = 0.131804;
                        const float c = 14.0;
                        const float sc = 7.0;
                        for (int i = 0; i < 3; i++) {
                            if (x[i] >= 0.0) { y[i] = (log2(a * x[i] + b) + c) / sc; }
                            else { y[i] = x[i] * sc; }
                        }
                        return float4(y, s.a);
                    }
                }}
            """
            
        case .log3G10:
            // RED IPP2 Specification - Log3G10
            return """
                #include <CoreImage/CoreImage.h>
                extern "C" { namespace coreimage {
                    [[ stitchable ]] float4 linearToLog3G10(sample_t s) {
                        float3 x = s.rgb;
                        float3 y;
                        const float a = 0.224282;
                        const float b = 155.975327;
                        const float c = 0.01;
                        const float g = 15.1927;
                        for (int i = 0; i < 3; i++) {
                            if (x[i] >= -c) {
                                y[i] = a * log10(b * (x[i] + c) + 1.0);
                            } else {
                                y[i] = (x[i] + c) * g;
                            }
                        }
                        return float4(y, s.a);
                    }
                }}
            """
            
        case .lLog:
            // Leica Camera AG L-Log Specification
            return """
                #include <CoreImage/CoreImage.h>
                extern "C" { namespace coreimage {
                    [[ stitchable ]] float4 linearToLLog(sample_t s) {
                        float3 x = s.rgb;
                        float3 y;
                        const float a = 8.0;
                        const float b = 0.09;
                        const float c = 0.27;
                        const float d = 1.3;
                        const float e = 0.0115;
                        const float f = 0.6;
                        const float cut = 0.006;
                        for (int i = 0; i < 3; i++) {
                            if (x[i] > cut) { y[i] = c * log10(d * x[i] + e) + f; }
                            else { y[i] = a * x[i] + b; }
                        }
                        return float4(y, s.a);
                    }
                }}
            """
            
        case .davinciIntermediate:
            // Blackmagic Design DaVinci Intermediate Specification
            // Uses log2-based OETF, middle gray at 0.336
            return """
                #include <CoreImage/CoreImage.h>
                extern "C" { namespace coreimage {
                    [[ stitchable ]] float4 linearToDaVinciIntermediate(sample_t s) {
                        float3 x = s.rgb;
                        float3 y;
                        // Official Blackmagic DI constants
                        const float DI_A = 0.0075;
                        const float DI_B = 7.0;
                        const float DI_C = 0.07329248;
                        const float DI_M = 10.44426855;
                        const float DI_LIN_CUT = 0.00262409;
                        for (int i = 0; i < 3; i++) {
                            if (x[i] > DI_LIN_CUT) {
                                y[i] = (log2(x[i] + DI_A) + DI_B) * DI_C;
                            } else {
                                y[i] = x[i] * DI_M;
                            }
                        }
                        return float4(y, s.a);
                    }
                }}
            """
        }
    }
    
    private func applyLUT(_ lut: Lut3D, to image: CIImage) -> CIImage {
        // Use CIColorCube with cached data (avoid recreating Data every frame)
        let filter = CIFilter.colorCube()
        filter.inputImage = image
        filter.cubeDimension = Float(lut.dimension)
        
        // Use cached data if available, otherwise create and cache
        if let cached = cachedColorCubeData {
            filter.cubeData = cached
        } else {
            let data = lut.toCIColorCubeData()
            cachedColorCubeData = data
            filter.cubeData = data
        }
        
        return filter.outputImage ?? image
    }
    
    // MARK: - Export
    
    /// Export processed image to file
    func export(
        result: NativePipelineResult,
        to url: URL,
        format: ExportFormat,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        
        do {
            switch format {
            case .tiff:
                try ciContext.writeTIFFRepresentation(
                    of: result.image,
                    to: url,
                    format: .RGBA16,
                    colorSpace: colorSpace,
                    options: [:]
                )
            case .heif:
                try ciContext.writeHEIF10Representation(
                    of: result.image,
                    to: url,
                    colorSpace: colorSpace,
                    options: [:]
                )
            }
            completion(true, nil)
        } catch {
            completion(false, error)
        }
    }
}
