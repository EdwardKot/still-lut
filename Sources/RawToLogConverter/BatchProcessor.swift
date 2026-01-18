import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

/// Settings for batch processing
struct BatchProcessingSettings {
    let logProfile: LogProfile
    let exposureMode: ExposureMode
    let manualEV: Double
    let autoExposureGain: Double
    let wbTemp: Double     // -100 to +100, 0 = camera WB
    let wbTint: Double     // -100 to +100
    let saturation: Double // 0.0 = grayscale, 1.0 = no change
    let contrast: Double   // 1.0 = no change
    let exportFormat: ExportFormat
    let lutURL: URL?       // LUT file URL (loaded by NativeColorPipeline)
}

/// Result for each file in batch
enum BatchFileResult {
    case success(URL, URL)  // input, output
    case failed(URL, Error)
    case skipped(URL, String)
}

/// Batch processor using NativeColorPipeline for consistent color science
/// Uses LibRaw XYZ pipeline - same as single-file processing
@MainActor
class BatchProcessor: ObservableObject {
    // MARK: - Published State
    @Published var isProcessing: Bool = false
    @Published var progress: Double = 0.0
    @Published var currentFileName: String = ""
    @Published var processedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var results: [BatchFileResult] = []
    
    // MARK: - Private State
    private var processingTask: Task<Void, Never>?
    private var pipeline: NativeColorPipeline?
    
    // MARK: - Computed Properties
    var successCount: Int {
        results.filter { if case .success = $0 { return true }; return false }.count
    }
    
    var failedCount: Int {
        results.filter { if case .failed = $0 { return true }; return false }.count
    }
    
    init() {
        // Initialize NativeColorPipeline (same as ImageProcessor)
        do {
            pipeline = try NativeColorPipeline()
            print("BatchProcessor: Initialized with NativeColorPipeline (LibRaw XYZ)")
        } catch {
            print("BatchProcessor: Failed to initialize NativeColorPipeline: \(error)")
        }
    }
    
    // MARK: - Public Methods
    
    /// Start batch processing
    func startBatch(
        inputFiles: [URL],
        outputDirectory: URL,
        settings: BatchProcessingSettings
    ) {
        guard !isProcessing else { return }
        
        isProcessing = true
        progress = 0.0
        processedCount = 0
        totalCount = inputFiles.count
        results = []
        
        processingTask = Task {
            await processBatch(
                files: inputFiles,
                outputDir: outputDirectory,
                settings: settings
            )
        }
    }
    
    /// Cancel ongoing batch processing
    func cancel() {
        processingTask?.cancel()
        processingTask = nil
    }
    
    /// Reset all state
    func reset() {
        cancel()
        isProcessing = false
        progress = 0.0
        currentFileName = ""
        processedCount = 0
        totalCount = 0
        results = []
    }
    
    // MARK: - Private Processing Methods
    
    private func processBatch(
        files: [URL],
        outputDir: URL,
        settings: BatchProcessingSettings
    ) async {
        // Load LUT once for entire batch
        if let lutURL = settings.lutURL {
            do {
                try pipeline?.loadLUT(from: lutURL)
                print("🎨 BatchProcessor: LUT loaded - \(lutURL.lastPathComponent)")
            } catch {
                print("⚠️ BatchProcessor: Failed to load LUT: \(error)")
            }
        } else {
            pipeline?.removeLUT()
        }
        
        for (index, fileURL) in files.enumerated() {
            // Check for cancellation
            if Task.isCancelled {
                await MainActor.run {
                    isProcessing = false
                    currentFileName = "已取消"
                }
                return
            }
            
            await MainActor.run {
                currentFileName = fileURL.lastPathComponent
                progress = Double(index) / Double(files.count)
            }
            
            // Process file with autoreleasepool for memory management
            await processFileAsync(
                fileURL,
                outputDir: outputDir,
                settings: settings
            )
        }
        
        await MainActor.run {
            isProcessing = false
            progress = 1.0
            currentFileName = "完成"
        }
    }
    
    private func processFileAsync(
        _ fileURL: URL,
        outputDir: URL,
        settings: BatchProcessingSettings
    ) async {
        guard let pipeline = pipeline else {
            await MainActor.run {
                results.append(.failed(fileURL, NSError(
                    domain: "BatchProcessor",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Pipeline 未初始化"]
                )))
                processedCount += 1
            }
            return
        }
        
        // Build config from settings
        var config = NativePipelineConfig()
        
        // Map LogProfile to NativeLogProfile
        switch settings.logProfile {
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
        
        config.exposureEV = Float(settings.exposureMode == .manual ? settings.manualEV : 0)
        config.autoExposure = settings.exposureMode == .auto
        
        // Convert wbTemp (-100 to +100) to WB multipliers
        if settings.wbTemp != 0 {
            let scale = Float(settings.wbTemp / 100.0) * 0.3
            config.wbMultipliers = SIMD3<Float>(1.0 + scale, 1.0, 1.0 - scale)
        }
        
        config.tint = Float(settings.wbTint)
        config.saturation = Float(settings.saturation)
        config.contrast = Float(settings.contrast)
        
        // Process using LibRaw XYZ pipeline (async continuation wrapper)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pipeline.processRAWWithLibRaw(url: fileURL, config: config) { [weak self] result in
                Task { @MainActor in
                    guard let self = self else {
                        continuation.resume()
                        return
                    }
                    
                    switch result {
                    case .success(let pipelineResult):
                        // Export to file
                        let baseName = fileURL.deletingPathExtension().lastPathComponent
                        let ext = settings.exportFormat == .heif ? "heic" : "tiff"
                        let outputURL = outputDir.appendingPathComponent("\(baseName)_processed.\(ext)")
                        
                        pipeline.export(result: pipelineResult, to: outputURL, format: settings.exportFormat) { success, error in
                            Task { @MainActor in
                                if success {
                                    self.results.append(.success(fileURL, outputURL))
                                } else {
                                    self.results.append(.failed(fileURL, error ?? NSError(
                                        domain: "BatchProcessor",
                                        code: 5,
                                        userInfo: [NSLocalizedDescriptionKey: "导出失败"]
                                    )))
                                }
                                self.processedCount += 1
                                continuation.resume()
                            }
                        }
                        
                    case .failure(let error):
                        self.results.append(.failed(fileURL, error))
                        self.processedCount += 1
                        continuation.resume()
                    }
                }
            }
        }
    }
}
