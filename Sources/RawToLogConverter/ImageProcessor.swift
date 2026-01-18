import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

enum LogProfile: String, CaseIterable, Identifiable {
    // Sony
    case sLog3 = "S-Log3"
    case sLog3Cine = "S-Log3.Cine"
    // Panasonic
    case vLog = "V-Log"
    // Fujifilm
    case fLog = "F-Log"
    case fLog2 = "F-Log2"
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
    
    var id: String { rawValue }
}

enum ExposureMode: String, CaseIterable, Identifiable {
    case auto = "自动"
    case manual = "手动"
    
    var id: String { rawValue }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case heif = "HEIF 10-bit"
    case tiff = "TIFF 16-bit"
    
    var id: String { rawValue }
}

class ImageProcessor: ObservableObject {
    @Published var originalImage: CIImage?
    @Published var processedImage: CGImage?
    @Published var selectedLogProfile: LogProfile = .sLog3
    
    // Exposure control (manual mode only - auto exposure removed)
    @Published var exposureMode: ExposureMode = .manual
    @Published var manualEV: Double = 0.0  // Range: -4.0 to +4.0
    @Published var autoExposureGain: Double = 1.0  // Calculated automatically
    @Published var autoExposureEV: Double = 0.0    // Auto EV for display
    
    // White Balance control (simplified style)
    // Temperature: -100 (warm/yellow) to +100 (cool/blue), 0 = camera WB
    // Tint: -100 (green) to +100 (magenta)
    @Published var wbTemp: Double = 0.0      // -100 to +100, 0 = camera WB
    @Published var wbTint: Double = 0.0      // -100 to +100
    @Published var cameraWbKelvin: Double = 5500  // Camera's original WB (for reference)
    @Published var cameraWbTint: Double = 0  // Camera's original tint
    
    // Saturation and Contrast adjustments (Log-space accurate)
    @Published var saturation: Double = 1.0   // 0.0 = grayscale, 1.0 = no change, 2.0 = double
    @Published var contrast: Double = 1.0     // 1.0 = no change, uses Log-specific middle gray pivot
    
    // Shadow/Highlight recovery (Log-space, pre-LUT)
    @Published var shadows: Double = 0.0      // -100 to +100, positive = lift shadows
    @Published var highlights: Double = 0.0   // -100 to +100, negative = compress highlights
    
    // Export format
    @Published var exportFormat: ExportFormat = .heif  // Default to HEIF 10-bit
    
    // Processing state
    @Published var isProcessing: Bool = false
    @Published var histogramData: HistogramData?  // Real-time histogram
    var inputURL: URL?  // Store input file URL for processing
    private var tempOutputURL: URL?
    
    // Native Swift/Metal pipeline (sole processing path)
    // Note: Initialized lazily on first access from MainActor context
    private var _nativePipeline: NativeColorPipeline?
    private var _nativePipelineInitialized = false
    
    @MainActor
    private var nativePipeline: NativeColorPipeline? {
        if !_nativePipelineInitialized {
            _nativePipelineInitialized = true
            do {
                _nativePipeline = try NativeColorPipeline()
            } catch {
                print("⚠️ Failed to initialize NativeColorPipeline: \(error)")
            }
        }
        return _nativePipeline
    }
    
    // Cache for native pipeline processing
    private var cachedLogImage: CIImage?
    private var baselineLogImage: CIImage?
    
    // Display context for final output (sRGB gamma for screen)
    // CRITICAL: Disable intermediate caching to prevent memory leak during real-time updates
    private let displayContext = CIContext(options: [
        .cacheIntermediates: false
    ])
    
    // Linear working context - CRITICAL for correct color science
    // All RAW processing and Log encoding must happen in linear light
    private let linearContext: CIContext = {
        // Use extended linear Display P3 - linear light, wide gamut, no clipping
        guard let linearP3 = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) else {
            fatalError("Failed to create linear P3 color space")
        }
        return CIContext(options: [
            .workingColorSpace: linearP3,
            .outputColorSpace: linearP3
        ])
    }()
    
    // Passthrough context for Log-encoded output
    // CRITICAL: Use LINEAR color spaces to prevent gamma application
    // After F-Log2 encoding, values are already non-linear (Log-encoded)
    // If we use sRGB/displayP3 (which have gamma), CIContext applies ANOTHER gamma on top
    // Solution: Use linear color space so no gamma conversion happens
    private let passthroughContext: CIContext = {
        // Use extendedLinearSRGB - this is linear (gamma 1.0) so no conversion happens
        guard let linearSRGB = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) else {
            fatalError("Failed to create linear sRGB color space")
        }
        return CIContext(options: [
            .workingColorSpace: linearSRGB,
            .outputColorSpace: linearSRGB
        ])
    }()
    
    // Linear P3 color space reference
    private let linearP3ColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
    
    init() {
        // Native pipeline is initialized lazily via nativePipeline property
        print("ImageProcessor initialized")
    }
    
    // MARK: - RAW Image Loading
    
    @MainActor
    func loadRawImage(from url: URL) {
        // Store URL for potential export
        self.inputURL = url
        
        // Detect file type (only RAW files are supported)
        let fileExtension = url.pathExtension.lowercased()
        let rawExtensions = ["dng", "raw", "cr2", "cr3", "nef", "arw", "orf", "rw2", "raf", "pef", "srw", "3fr", "fff", "iiq"]
        
        guard rawExtensions.contains(fileExtension) else {
            print("❌ Unsupported file type: \(fileExtension.uppercased())")
            print("   Only RAW files are supported (DNG, RAF, ARW, CR2, NEF, etc.)")
            return
        }
        
        // RAW file - will be processed by LibRaw XYZ pipeline
        print("📸 Loading RAW file: \(url.lastPathComponent)")
        
        // Use default camera white balance values
        // LibRaw extracts actual camera WB from RAW metadata
        self.cameraWbKelvin = 5500  // Default daylight (LibRaw may override)
        self.cameraWbTint = 0
        
        // Process directly with native LibRaw pipeline
        self.processWithNative(forPreview: true)
    }
    
    // (Removed loadStandardImage - only RAW files are now supported)
    
    /// Verify linearity by sampling center pixels
    /// - For 18% gray: linear ≈ 0.18, gamma 2.2 ≈ 0.46
    private func verifyLinearityAtCenter(image: CIImage, label: String) {
        let extent = image.extent
        let centerX = extent.origin.x + extent.width / 2
        let centerY = extent.origin.y + extent.height / 2
        let sampleSize = 100
        
        let sampleRect = CGRect(
            x: centerX - CGFloat(sampleSize/2),
            y: centerY - CGFloat(sampleSize/2),
            width: CGFloat(sampleSize),
            height: CGFloat(sampleSize)
        )
        
        // Use linear context for accurate sampling
        guard let linearP3 = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) else { return }
        let context = CIContext(options: [
            .workingColorSpace: linearP3,
            .outputColorSpace: linearP3
        ])
        
        // Render to bitmap
        var bitmap = [Float](repeating: 0, count: sampleSize * sampleSize * 4)
        context.render(image, toBitmap: &bitmap, rowBytes: sampleSize * 4 * MemoryLayout<Float>.size,
                       bounds: sampleRect, format: .RGBAf, colorSpace: linearP3)
        
        // Calculate average RGB
        var sumR: Float = 0, sumG: Float = 0, sumB: Float = 0
        let pixelCount = sampleSize * sampleSize
        for i in 0..<pixelCount {
            sumR += bitmap[i * 4 + 0]
            sumG += bitmap[i * 4 + 1]
            sumB += bitmap[i * 4 + 2]
        }
        
        let avgR = sumR / Float(pixelCount)
        let avgG = sumG / Float(pixelCount)
        let avgB = sumB / Float(pixelCount)
        let avgLuma = 0.2126 * avgR + 0.7152 * avgG + 0.0722 * avgB
        
        print("   🔬 \(label):")
        print("      Center 100x100 avg RGB: (\(String(format: "%.4f", avgR)), \(String(format: "%.4f", avgG)), \(String(format: "%.4f", avgB)))")
        print("      Average luminance: \(String(format: "%.4f", avgLuma))")
        print("      Interpretation: \(avgLuma < 0.3 ? "likely LINEAR" : avgLuma > 0.4 ? "likely GAMMA" : "UNCLEAR")")
    }
    
    @Published var selectedLutURL: URL?
    private(set) var lutData: Data?
    private(set) var lutDimension: Int = 0
    
    // ... init ...
    
    /// Load a 3D LUT from a .cube file
    /// This updates the UI immediately and triggers re-processing if an image is loaded
    func loadLut(from url: URL) {
        print("🎨 Loading LUT: \(url.lastPathComponent)")
        
        // Load and parse LUT data
        guard let (data, dimension) = LutLoader.loadCubeFile(from: url) else {
            print("❌ Failed to parse LUT file: \(url.lastPathComponent)")
            return
        }
        
        // Update published state (triggers UI update)
        self.selectedLutURL = url
        self.lutData = data
        self.lutDimension = dimension
        print("✅ LUT loaded: \(dimension)x\(dimension)x\(dimension)")
        
        // Re-process image if one is loaded
        guard inputURL != nil else {
            print("ℹ️ No image loaded, LUT will be applied when image is loaded")
            return
        }
        
        // Use native pipeline (faster, avoids Python dependency issues)
        Task { @MainActor in
            processWithNative(forPreview: true)
        }
    }
    
    /// Remove the currently loaded LUT
    func removeLut() {
        print("🎨 LUT removed")
        self.selectedLutURL = nil
        self.lutData = nil
        self.lutDimension = 0
        
        // Re-process image if one is loaded
        guard inputURL != nil else { return }
        
        Task { @MainActor in
            processWithNative(forPreview: true)
        }
    }
    
    // MARK: - Native Swift Processing
    
    /// Process RAW file using fully native Swift/Metal pipeline
    /// No Python dependency - faster startup, more reliable
    @MainActor
    func processWithNative(forPreview: Bool = false) {
        guard let inputURL = inputURL else {
            print("ERROR: No input URL available for native processing")
            return
        }
        
        guard let pipeline = nativePipeline else {
            print("ERROR: NativeColorPipeline not available")
            return
        }
        
        // Build native config from current settings
        var config = NativePipelineConfig()
        
        // Map LogProfile to NativeLogProfile (complete 1:1 mapping)
        switch selectedLogProfile {
        case .fLog2: config.logProfile = .fLog2
        case .fLog: config.logProfile = .fLog
        case .sLog3: config.logProfile = .sLog3
        case .sLog3Cine: config.logProfile = .sLog3Cine
        case .vLog: config.logProfile = .vLog
        case .nLog: config.logProfile = .nLog
        case .canonLog2: config.logProfile = .canonLog2
        case .canonLog3: config.logProfile = .canonLog3
        case .arriLogC3: config.logProfile = .arriLogC3
        case .arriLogC4: config.logProfile = .arriLogC4
        case .log3G10: config.logProfile = .log3G10
        case .lLog: config.logProfile = .lLog
        case .davinciIntermediate: config.logProfile = .davinciIntermediate
        }
        
        config.exposureEV = Float(exposureMode == .manual ? manualEV : 0)
        config.autoExposure = exposureMode == .auto
        
        // Convert wbTemp (-100 to +100) to relative WB multipliers
        // 0 = camera WB (no adjustment), negative = warmer, positive = cooler
        if wbTemp != 0.0 {
            // -100 to +100 maps to ±0.3 gain adjustment
            let scale = Float(wbTemp / 100.0) * 0.3
            let rGain: Float = 1.0 + scale  // Positive temp = boost red (cooler look)
            let bGain: Float = 1.0 - scale  // Positive temp = reduce blue
            config.wbMultipliers = SIMD3<Float>(rGain, 1.0, bGain)
        }
        // wbTemp = 0 → wbMultipliers stays (1,1,1) = camera WB unchanged
        
        // Pass saturation and contrast adjustments
        config.saturation = Float(saturation)
        config.contrast = Float(contrast)
        config.tint = Float(wbTint)
        config.shadows = Float(shadows)
        config.highlights = Float(highlights)
        
        // Load LUT if available
        if let lutURL = selectedLutURL {
            do {
                try pipeline.loadLUT(from: lutURL)
            } catch {
                print("⚠️ Failed to load LUT: \(error)")
            }
        } else {
            pipeline.removeLUT()
        }
        
        isProcessing = true
        
        // Define shared completion handler
        let handleResult: (Result<NativePipelineResult, Error>) -> Void = { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let pipelineResult):
                // Cache results
                self.autoExposureGain = Double(pipelineResult.autoExposureGain)
                self.autoExposureEV = Double(pipelineResult.autoExposureEV)
                
                // If in manual mode and manualEV is still at default (0), 
                // initialize it with auto-calculated EV as starting point
                if self.exposureMode == .manual && abs(self.manualEV) < 0.01 && abs(pipelineResult.autoExposureEV) > 0.01 {
                    self.manualEV = Double(pipelineResult.autoExposureEV)
                    print("📊 Manual EV initialized to auto value: \(String(format: "%+.2f", self.manualEV))")
                }
                
                // Render to CGImage for display
                if let cgImage = self.displayContext.createCGImage(
                    pipelineResult.image,
                    from: pipelineResult.image.extent,
                    format: .RGBA8,
                    colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!
                ) {
                    self.processedImage = cgImage
                    self.histogramData = HistogramData.compute(from: cgImage)
                    self.cachedLogImage = pipelineResult.image
                    
                    // Only update baseline when processing with EV=0
                    let effectiveEV = self.exposureMode == .manual ? self.manualEV : 0.0
                    if abs(effectiveEV) < 0.01 {
                        self.baselineLogImage = pipelineResult.image
                        print("✅ Processing complete in \(String(format: "%.1f", pipelineResult.processingTimeMs))ms (baseline updated)")
                    } else {
                        print("✅ Processing complete in \(String(format: "%.1f", pipelineResult.processingTimeMs))ms (EV=\(effectiveEV))")
                    }
                }
                
            case .failure(let error):
                print("❌ Processing failed: \(error)")
            }
            
            self.isProcessing = false
        }
        
        // Process RAW file with LibRaw XYZ pipeline
        pipeline.processRAWWithLibRaw(url: inputURL, config: config, completion: handleResult)
    }
    
    /// Export using native pipeline (no Python)
    @MainActor
    func exportWithNative(to outputURL: URL, completion: @escaping (Bool, String?) -> Void) {
        guard let pipeline = nativePipeline,
              let result = pipeline.lastResult else {
            completion(false, "Native pipeline not available")
            return
        }
        
        pipeline.export(result: result, to: outputURL, format: exportFormat) { success, error in
            if success {
                completion(true, nil)
            } else {
                completion(false, error?.localizedDescription)
            }
        }
    }
    
    // MARK: - Hybrid Architecture: Real-time Exposure Adjustment
    
    /// Guard to prevent overlapping updates
    private var isUpdatingRealtime = false
    
    /// Apply exposure/color adjustments in real-time using GPU-accelerated cached texture
    /// Uses NativeColorPipeline.updateProcessingFast() for instant slider response
    /// Both RAW and standard images (JPG/PNG) now use cached XYZ texture for fast updates
    @MainActor
    func applyRealtimeAdjustments() {
        
        guard let pipeline = nativePipeline else {
            print("ERROR: NativeColorPipeline not available")
            return
        }
        
        // Prevent overlapping updates - skip if previous is still processing
        guard !isUpdatingRealtime else {
            return
        }
        isUpdatingRealtime = true
        
        // Build config from current settings
        var config = NativePipelineConfig()
        
        // Map LogProfile to NativeLogProfile
        switch selectedLogProfile {
        case .fLog2: config.logProfile = .fLog2
        case .fLog: config.logProfile = .fLog
        case .sLog3: config.logProfile = .sLog3
        case .sLog3Cine: config.logProfile = .sLog3Cine
        case .vLog: config.logProfile = .vLog
        case .nLog: config.logProfile = .nLog
        case .canonLog2: config.logProfile = .canonLog2
        case .canonLog3: config.logProfile = .canonLog3
        case .arriLogC3: config.logProfile = .arriLogC3
        case .arriLogC4: config.logProfile = .arriLogC4
        case .log3G10: config.logProfile = .log3G10
        case .lLog: config.logProfile = .lLog
        case .davinciIntermediate: config.logProfile = .davinciIntermediate
        }
        
        config.exposureEV = Float(exposureMode == .manual ? manualEV : 0)
        config.autoExposure = exposureMode == .auto
        config.saturation = Float(saturation)
        config.contrast = Float(contrast)
        config.tint = Float(wbTint)
        config.shadows = Float(shadows)
        config.highlights = Float(highlights)
        
        // Convert wbTemp (-100 to +100) to WB multipliers
        if wbTemp != 0.0 {
            let scale = Float(wbTemp / 100.0) * 0.3
            config.wbMultipliers = SIMD3<Float>(1.0 + scale, 1.0, 1.0 - scale)
        }
        
        // Use GPU-accelerated fast update (reuses cached XYZ texture)
        pipeline.updateProcessingFast(config: config) { [weak self] result in
            guard let self = self else { return }
            
            // Reset guard
            self.isUpdatingRealtime = false
            
            switch result {
            case .success(let pipelineResult):
                // Use autoreleasepool to ensure CIImage is released after CGImage creation
                autoreleasepool {
                    if let cgImage = self.displayContext.createCGImage(
                        pipelineResult.image,
                        from: pipelineResult.image.extent,
                        format: .RGBA8,
                        colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!
                    ) {
                        self.processedImage = cgImage
                        self.histogramData = HistogramData.compute(from: cgImage)
                    }
                }
                // Don't cache cached LogImage for every update - only on major changes
                
            case .failure(let error):
                print("❌ Fast update failed: \(error)")
            }
        }
    }
    
    /// Legacy function for compatibility - calls new unified adjustment
    @MainActor
    func applyExposureRealtime() {
        applyRealtimeAdjustments()
    }
    
    /// Apply color temperature/tint adjustments in real-time
    @MainActor
    func applyRealtimeColorTemperature() {
        processWithNative(forPreview: true)
    }
}
