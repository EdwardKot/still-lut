import SwiftUI
import UniformTypeIdentifiers

struct BatchView: View {
    @ObservedObject var batchProcessor: BatchProcessor
    @ObservedObject var imageProcessor: ImageProcessor
    
    @State private var inputFiles: [URL] = []
    @State private var outputDirectory: URL?
    @State private var showingInputPicker = false
    @State private var showingOutputPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("批量处理")
                .font(.headline)
            
            // Input selection
            GroupBox("输入文件") {
                VStack(alignment: .leading, spacing: 8) {
                    Button("选择文件夹...") {
                        selectInputFolder()
                    }
                    .disabled(batchProcessor.isProcessing)
                    
                    if !inputFiles.isEmpty {
                        Text("已选择 \(inputFiles.count) 个 RAW 文件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Output selection
            GroupBox("输出目录") {
                VStack(alignment: .leading, spacing: 8) {
                    Button("选择目录...") {
                        selectOutputFolder()
                    }
                    .disabled(batchProcessor.isProcessing)
                    
                    if let outputDir = outputDirectory {
                        Text(outputDir.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Processing settings info
            GroupBox("当前设置") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Log: \(imageProcessor.selectedLogProfile.rawValue)")
                    Text("曝光: \(imageProcessor.exposureMode == .auto ? "自动" : String(format: "%+.1f EV", imageProcessor.manualEV))")
                    if imageProcessor.wbTemp != 0 || imageProcessor.wbTint != 0 {
                        Text("白平衡: 已调整")
                    }
                    Text("格式: \(imageProcessor.exportFormat.rawValue)")
                    if imageProcessor.selectedLutURL != nil {
                        Text("LUT: ✓")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Divider()
            
            // Progress section
            if batchProcessor.isProcessing || batchProcessor.processedCount > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: batchProcessor.progress)
                        .progressViewStyle(.linear)
                    
                    HStack {
                        Text(batchProcessor.currentFileName)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Spacer()
                        
                        Text("\(batchProcessor.processedCount)/\(batchProcessor.totalCount)")
                            .font(.caption)
                            .monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                    
                    // Results summary
                    if !batchProcessor.isProcessing && batchProcessor.processedCount > 0 {
                        HStack {
                            Label("\(batchProcessor.successCount) 成功", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            
                            if batchProcessor.failedCount > 0 {
                                Label("\(batchProcessor.failedCount) 失败", systemImage: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                        .font(.caption)
                    }
                }
            }
            
            Spacer()
            
            // Action buttons
            HStack {
                if batchProcessor.isProcessing {
                    Button("取消") {
                        batchProcessor.cancel()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("开始处理") {
                        startProcessing()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canStartProcessing)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Computed Properties
    
    private var canStartProcessing: Bool {
        !inputFiles.isEmpty && outputDirectory != nil && !batchProcessor.isProcessing
    }
    
    // MARK: - Actions
    
    private func selectInputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择包含 RAW 文件的目录"
        
        if panel.runModal() == .OK, let url = panel.url {
            scanForRawFiles(in: url)
        }
    }
    
    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "选择输出目录"
        
        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
        }
    }
    
    private func scanForRawFiles(in directory: URL) {
        let fileManager = FileManager.default
        let rawExtensions = ["dng", "DNG", "cr2", "CR2", "cr3", "CR3", "nef", "NEF", 
                            "arw", "ARW", "raf", "RAF", "orf", "ORF", "rw2", "RW2"]
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            
            inputFiles = contents.filter { url in
                rawExtensions.contains(url.pathExtension)
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            
        } catch {
            print("Error scanning directory: \(error)")
            inputFiles = []
        }
    }
    
    private func startProcessing() {
        guard let outputDir = outputDirectory else { return }
        
        // Create settings from current ImageProcessor state
        let settings = BatchProcessingSettings(
            logProfile: imageProcessor.selectedLogProfile,
            exposureMode: imageProcessor.exposureMode,
            manualEV: imageProcessor.manualEV,
            autoExposureGain: imageProcessor.autoExposureGain,
            wbTemp: imageProcessor.wbTemp,
            wbTint: imageProcessor.wbTint,
            saturation: imageProcessor.saturation,
            contrast: imageProcessor.contrast,
            exportFormat: imageProcessor.exportFormat,
            lutURL: imageProcessor.selectedLutURL
        )
        
        batchProcessor.startBatch(
            inputFiles: inputFiles,
            outputDirectory: outputDir,
            settings: settings
        )
    }
}
