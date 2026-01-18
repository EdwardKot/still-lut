import SwiftUI
import UniformTypeIdentifiers

/// Processing mode based on dropped content
enum ProcessingMode: Equatable {
    case empty
    case single(URL)
    case batch([URL])
    
    var isBatch: Bool {
        if case .batch = self { return true }
        return false
    }
    
    var fileCount: Int {
        switch self {
        case .empty: return 0
        case .single: return 1
        case .batch(let urls): return urls.count
        }
    }
}

struct ContentView: View {
    @StateObject private var processor = ImageProcessor()
    @StateObject private var batchProcessor = BatchProcessor()
    @State private var isTargeted = false
    @State private var processingMode: ProcessingMode = .empty
    @State private var outputDirectory: URL?
    
    // Debounce timer for slider changes
    @State private var debounceTimer: Timer?
    private let debounceDelay: TimeInterval = 0.4  // Wait 0.4 seconds after last change
    
    /// Debounced call to native processing
    /// Cancels previous timer and starts a new one, so processing only happens
    /// after the user stops adjusting for debounceDelay seconds
    private func debouncedProcess() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDelay, repeats: false) { _ in
            // CRITICAL: Must dispatch to MainActor since processWithNative is @MainActor
            Task { @MainActor in
                processor.processWithNative(forPreview: true)
            }
        }
    }
    
    var body: some View {
        HSplitView {
            // Left Panel: Controls
            controlsPanel
                .frame(minWidth: 240, maxWidth: 280)
            
            // Right Panel: Content Area
            contentArea
                .frame(minWidth: 500, minHeight: 500)
        }
        .background(Theme.Background.primary)
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Controls Panel
    private var controlsPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                // App Title
                appHeader
                
                // Section 1: Log Profile
                logProfileSection
                
                // Section 2: LUT
                lutSection
                
                // Section 3: Histogram (visual reference for adjustments)
                histogramSection
                
                // Section 4: Exposure
                exposureSection
                
                // Section 4: Color Adjustment
                colorSection
                
                Spacer(minLength: 20)
                
                // Section 5: Export
                exportSection
            }
            .padding(16)
        }
        .background(Theme.Background.secondary)
    }
    
    // MARK: - App Header
    private var appHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // App icon/logo area
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [Theme.Accent.orange, Theme.Accent.orange.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "camera.filters")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.Text.inverse)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("RAW to Log")
                        .font(Theme.Font.title)
                        .foregroundColor(Theme.Text.primary)
                    
                    Text("Professional Color Pipeline")
                        .font(Theme.Font.subtitle)
                        .foregroundColor(Theme.Text.tertiary)
                }
            }
            
            // Subtle separator
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Theme.Accent.orange.opacity(0.5), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Log Profile Section
    private var logProfileSection: some View {
        SectionCard("LOG PROFILE") {
            Menu {
                ForEach(LogProfile.allCases) { profile in
                    Button(profile.rawValue) {
                        processor.selectedLogProfile = profile
                        Task { @MainActor in
                            processor.processWithNative(forPreview: true)
                        }
                    }
                }
            } label: {
                HStack {
                    Text(processor.selectedLogProfile.rawValue)
                        .font(Theme.Font.label)
                        .foregroundColor(Theme.Text.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.Text.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Size.cornerRadius)
                        .fill(Theme.Background.quaternary)
                )
            }
            .menuStyle(.borderlessButton)
        }
    }
    
    // MARK: - LUT Section
    private var lutSection: some View {
        SectionCard("LUT") {
            if let url = processor.selectedLutURL {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Theme.Accent.green)
                            .font(.system(size: 12))
                        
                        Text(url.lastPathComponent)
                            .font(Theme.Font.caption)
                            .foregroundColor(Theme.Text.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    HStack(spacing: 8) {
                        Button("更换") { selectLUT() }
                            .buttonStyle(SecondaryButtonStyle())
                        
                        Button("移除") { processor.removeLut() }
                            .buttonStyle(GhostButtonStyle())
                    }
                }
            } else {
                Button(action: selectLUT) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 12))
                        Text("选择 .cube 文件")
                            .font(Theme.Font.label)
                    }
                    .foregroundColor(Theme.Text.secondary)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
    
    // MARK: - Histogram Section
    private var histogramSection: some View {
        Group {
            if case .single = processingMode {
                SectionCard("直方图") {
                    HistogramView(data: processor.histogramData)
                }
            }
        }
    }
    
    // MARK: - Exposure Section
    private var exposureSection: some View {
        SectionCard("曝光") {
            if processingMode.isBatch {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .foregroundColor(Theme.Accent.blue)
                        .font(.system(size: 12))
                    Text("批量模式：自动曝光")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.Text.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    // Auto/Manual Toggle
                    HStack(spacing: 0) {
                        ForEach(ExposureMode.allCases) { mode in
                            Button(mode.rawValue) {
                                processor.exposureMode = mode
                                Task { @MainActor in
                                    processor.processWithNative(forPreview: true)
                                }
                            }
                            .font(Theme.Font.label)
                            .foregroundColor(processor.exposureMode == mode ? Theme.Text.primary : Theme.Text.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Size.cornerRadius)
                                    .fill(processor.exposureMode == mode ? Theme.Background.quaternary : Color.clear)
                            )
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Size.cornerRadius)
                            .fill(Theme.Background.primary)
                    )
                    
                    if processor.exposureMode == .manual {
                        // EV Slider
                        VStack(spacing: 4) {
                            HStack {
                                Text("EV")
                                    .controlLabel()
                                Spacer()
                                Text(String(format: "%+.1f", processor.manualEV))
                                    .valueDisplay()
                            }
                            
                            DarkSlider(
                                value: $processor.manualEV,
                                range: -5...5,
                                step: 0.1,
                                defaultValue: 0,  // Reset to 0 EV on double-click
                                onReset: {
                                    // Reset EV to 0 and trigger exposure update
                                    print("🔄 EV slider onReset: setting manualEV=0 and calling applyExposureRealtime()")
                                    processor.manualEV = 0
                                    processor.applyExposureRealtime()
                                }
                            )
                            .onChange(of: processor.manualEV) { _, _ in
                                // Real-time exposure adjustment (GPU-accelerated, instant)
                                processor.applyExposureRealtime()
                            }
                        }
                    } else if case .single = processingMode {
                        HStack {
                            Text("增益: \(String(format: "%.2f×", processor.autoExposureGain))")
                            Spacer()
                            Text(String(format: "%+.1f EV", processor.autoExposureEV))
                        }
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.Text.secondary)
                    }
                }
            }
        }
        .opacity(processingMode.isBatch ? 0.6 : 1.0)
    }
    
    // MARK: - Color Section
    private var colorSection: some View {
        SectionCard("色彩") {
            if processingMode.isBatch {
                HStack(spacing: 6) {
                    Image(systemName: "slash.circle")
                        .foregroundColor(Theme.Text.tertiary)
                        .font(.system(size: 12))
                    Text("批量模式下不可用")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.Text.tertiary)
                }
            } else {
                VStack(spacing: 12) {
                    // Temperature - simplified -100 to +100 style
                    VStack(spacing: 4) {
                        HStack {
                            Text("色温")
                                .controlLabel()
                            Spacer()
                            if processor.wbTemp != 0 {
                                Text(processor.wbTemp > 0 ? "+\(Int(processor.wbTemp))" : "\(Int(processor.wbTemp))")
                                    .font(Theme.Font.caption)
                                    .foregroundColor(processor.wbTemp < 0 ? Color.orange : Color.blue)
                            } else {
                                Text("0")
                                    .font(Theme.Font.caption)
                                    .foregroundColor(Theme.Text.tertiary)
                            }
                        }
                        
                        DarkSlider(
                            value: $processor.wbTemp,
                            range: -100...100,
                            step: 1,
                            centerMark: 0,  // 0 = camera WB
                            defaultValue: 0,
                            onReset: {
                                processor.wbTemp = 0
                                processor.applyRealtimeAdjustments()
                            }
                        )
                        .onChange(of: processor.wbTemp) { _, _ in
                            processor.applyRealtimeAdjustments()
                        }
                    }
                    
                    // Tint (Green-Magenta) - Adobe Camera RAW style
                    VStack(spacing: 4) {
                        HStack {
                            Text("色调")
                                .controlLabel()
                            Spacer()
                            if processor.wbTint != 0 {
                                Text(processor.wbTint > 0 ? "+\(Int(processor.wbTint))" : "\(Int(processor.wbTint))")
                                    .font(Theme.Font.caption)
                                    .foregroundColor(processor.wbTint > 0 ? Color.pink : Color.green)
                            } else {
                                Text("0")
                                    .font(Theme.Font.caption)
                                    .foregroundColor(Theme.Text.tertiary)
                            }
                        }
                        
                        DarkSlider(
                            value: $processor.wbTint,
                            range: -100...100,
                            step: 1,
                            centerMark: processor.cameraWbTint,  // Camera original tint marker
                            defaultValue: 0,
                            onReset: {
                                // Reset tint to 0 and trigger processing
                                processor.wbTint = 0
                                processor.applyRealtimeAdjustments()
                            }
                        )
                        .onChange(of: processor.wbTint) { _, _ in
                            processor.applyRealtimeAdjustments()
                        }
                    }
                    
                    Divider()
                        .background(Theme.Background.quaternary)
                    
                    // Saturation adjustment
                    VStack(spacing: 4) {
                        HStack {
                            Text("饱和度")
                                .controlLabel()
                            Spacer()
                            Text(String(format: "%.0f%%", processor.saturation * 100))
                                .font(Theme.Font.caption)
                                .foregroundColor(processor.saturation != 1.0 ? Theme.Accent.blue : Theme.Text.tertiary)
                        }
                        
                        DarkSlider(
                            value: $processor.saturation,
                            range: 0...2,
                            step: 0.05,
                            centerMark: 1.0,
                            onReset: {
                                // Reset saturation to 1.0 and trigger processing
                                processor.saturation = 1.0
                                processor.applyRealtimeAdjustments()
                            }
                        )
                        .onChange(of: processor.saturation) { _, _ in
                            processor.applyRealtimeAdjustments()
                        }
                    }
                    
                    // Contrast adjustment
                    VStack(spacing: 4) {
                        HStack {
                            Text("对比度")
                                .controlLabel()
                            Spacer()
                            Text(String(format: "%.0f%%", processor.contrast * 100))
                                .font(Theme.Font.caption)
                                .foregroundColor(processor.contrast != 1.0 ? Theme.Accent.orange : Theme.Text.tertiary)
                        }
                        
                        DarkSlider(
                            value: $processor.contrast,
                            range: 0.5...2,
                            step: 0.05,
                            centerMark: 1.0,
                            onReset: {
                                // Reset contrast to 1.0 and trigger processing
                                processor.contrast = 1.0
                                processor.applyRealtimeAdjustments()
                            }
                        )
                        .onChange(of: processor.contrast) { _, _ in
                            processor.applyRealtimeAdjustments()
                        }
                    }
                    
                    Divider()
                        .background(Theme.Background.quaternary)
                    
                    // Highlights adjustment (above shadows - professional convention)
                    VStack(spacing: 4) {
                        HStack {
                            Text("高光")
                                .controlLabel()
                            Spacer()
                            Text(String(format: "%+.0f", processor.highlights))
                                .font(Theme.Font.caption)
                                .foregroundColor(processor.highlights != 0 ? Theme.Accent.orange : Theme.Text.tertiary)
                        }
                        
                        DarkSlider(
                            value: $processor.highlights,
                            range: -100...100,
                            step: 1,
                            centerMark: 0,
                            onReset: {
                                processor.highlights = 0
                                processor.applyRealtimeAdjustments()
                            }
                        )
                        .onChange(of: processor.highlights) { _, _ in
                            processor.applyRealtimeAdjustments()
                        }
                    }
                    
                    // Shadows adjustment
                    VStack(spacing: 4) {
                        HStack {
                            Text("阴影")
                                .controlLabel()
                            Spacer()
                            Text(String(format: "%+.0f", processor.shadows))
                                .font(Theme.Font.caption)
                                .foregroundColor(processor.shadows != 0 ? Theme.Accent.orange : Theme.Text.tertiary)
                        }
                        
                        DarkSlider(
                            value: $processor.shadows,
                            range: -100...100,
                            step: 1,
                            centerMark: 0,
                            onReset: {
                                processor.shadows = 0
                                processor.applyRealtimeAdjustments()
                            }
                        )
                        .onChange(of: processor.shadows) { _, _ in
                            processor.applyRealtimeAdjustments()
                        }
                    }
                    
                    // Reset button - show if anything has been adjusted
                    if processor.wbTemp != 0 || processor.wbTint != 0 || processor.saturation != 1.0 || processor.contrast != 1.0 || processor.shadows != 0 || processor.highlights != 0 {
                        Button("重置色彩") {
                            processor.wbTemp = 0
                            processor.wbTint = 0
                            processor.saturation = 1.0
                            processor.contrast = 1.0
                            processor.shadows = 0
                            processor.highlights = 0
                            Task { @MainActor in
                                processor.processWithNative(forPreview: true)
                            }
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                }
            }
        }
        .opacity(processingMode.isBatch ? 0.6 : 1.0)
    }
    
    // MARK: - Export Section
    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Format Toggle
            HStack {
                Text("HEIF")
                    .font(Theme.Font.caption)
                    .foregroundColor(processor.exportFormat == .heif ? Theme.Text.primary : Theme.Text.tertiary)
                
                Toggle("", isOn: Binding(
                    get: { processor.exportFormat == .tiff },
                    set: { processor.exportFormat = $0 ? .tiff : .heif }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.7)
                
                Text("TIFF 16-bit")
                    .font(Theme.Font.caption)
                    .foregroundColor(processor.exportFormat == .tiff ? Theme.Accent.orange : Theme.Text.tertiary)
            }
            
            // Export Button
            if case .empty = processingMode {
                // No file loaded - button disabled
            } else {
                Button(action: handleExport) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up.fill")
                            .font(.system(size: 12))
                        Text(processingMode.isBatch ? "导出 \(processingMode.fileCount) 张" : "导出")
                    }
                }
                .buttonStyle(AccentButtonStyle(isEnabled: !batchProcessor.isProcessing))
                .disabled(batchProcessor.isProcessing)
            }
            
            // Batch Progress
            if batchProcessor.isProcessing {
                VStack(spacing: 8) {
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.Control.slider)
                                .frame(height: 4)
                            
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.Accent.orange)
                                .frame(width: geo.size.width * batchProcessor.progress, height: 4)
                        }
                    }
                    .frame(height: 4)
                    
                    HStack {
                        Text(batchProcessor.currentFileName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("\(batchProcessor.processedCount)/\(batchProcessor.totalCount)")
                            .monospacedDigit()
                    }
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Text.secondary)
                    
                    Button("取消") { batchProcessor.cancel() }
                        .buttonStyle(GhostButtonStyle())
                }
            }
            
            // Results summary
            if !batchProcessor.isProcessing && batchProcessor.processedCount > 0 {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Theme.Accent.green)
                        Text("\(batchProcessor.successCount)")
                    }
                    
                    if batchProcessor.failedCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Theme.Accent.red)
                            Text("\(batchProcessor.failedCount)")
                        }
                    }
                }
                .font(Theme.Font.caption)
                .foregroundColor(Theme.Text.secondary)
            }
        }
        .padding(Theme.Size.panelPadding)
        .background(
            RoundedRectangle(cornerRadius: Theme.Size.cornerRadius)
                .fill(Theme.Background.tertiary)
        )
    }
    
    // MARK: - Content Area
    private var contentArea: some View {
        ZStack {
            Theme.Background.primary
            
            switch processingMode {
            case .empty:
                dropPrompt
                
            case .single:
                VStack(spacing: 0) {
                    fileToolbar
                    
                    if let image = processor.processedImage {
                        GeometryReader { geo in
                            Image(nsImage: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .padding(20)
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(Theme.Accent.orange)
                            Text("处理中...")
                                .font(Theme.Font.label)
                                .foregroundColor(Theme.Text.secondary)
                        }
                    }
                }
                
            case .batch(let urls):
                VStack(spacing: 0) {
                    fileToolbar
                    batchThumbnailView(urls: urls)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isTargeted ? Theme.Accent.orange : Color.clear, lineWidth: 2)
                .padding(4)
        )
    }
    
    // MARK: - Drop Prompt
    private var dropPrompt: some View {
        VStack(spacing: 24) {
            // Animated drop icon with glow
            ZStack {
                // Outer glow
                Circle()
                    .fill(Theme.Accent.orange.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Circle()
                    .fill(Theme.Background.tertiary)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(Theme.Control.border, lineWidth: 1)
                    )
                
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.Accent.orange, Theme.Accent.orange.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            VStack(spacing: 10) {
                Text("拖放 RAW 文件或文件夹")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.Text.primary)
                
                Text("支持 DNG, CR2, CR3, NEF, ARW, RAF, ORF, RW2 等格式")
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Text.tertiary)
            }
            
            HStack(spacing: 14) {
                Button {
                    openFile()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 11))
                        Text("打开文件")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button {
                    openFolder()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 11))
                        Text("打开文件夹")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.Background.secondary.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.Control.separator, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                )
        )
    }
    
    // MARK: - File Toolbar
    private var fileToolbar: some View {
        HStack(spacing: 12) {
            // Current file/folder info
            if case .single(let url) = processingMode {
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill")
                        .foregroundColor(Theme.Accent.orange)
                        .font(.system(size: 12))
                    Text(url.lastPathComponent)
                        .font(Theme.Font.label)
                        .foregroundColor(Theme.Text.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else if case .batch(let urls) = processingMode {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(Theme.Accent.orange)
                        .font(.system(size: 12))
                    Text("\(urls.count) 张照片")
                        .font(Theme.Font.label)
                        .foregroundColor(Theme.Text.primary)
                }
            }
            
            Spacer()
            
            // Action buttons
            Button { openFile() } label: {
                Image(systemName: "doc.badge.plus")
            }
            .buttonStyle(GhostButtonStyle())
            .help("打开文件")
            
            Button { openFolder() } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(GhostButtonStyle())
            .help("打开文件夹")
            
            Button { clearFiles() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(GhostButtonStyle())
            .help("清除")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.Background.secondary)
    }
    
    // MARK: - Batch Thumbnail View
    private func batchThumbnailView(urls: [URL]) -> some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 12)
            ], spacing: 12) {
                ForEach(urls, id: \.self) { url in
                    VStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.Size.cornerRadius)
                                .fill(Theme.Background.tertiary)
                                .aspectRatio(1, contentMode: .fit)
                            
                            if let thumbnail = loadThumbnail(for: url) {
                                Image(nsImage: thumbnail)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.Size.cornerRadius))
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 24))
                                    .foregroundColor(Theme.Text.tertiary)
                            }
                        }
                        
                        Text(url.deletingPathExtension().lastPathComponent)
                            .font(Theme.Font.caption)
                            .foregroundColor(Theme.Text.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(20)
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadThumbnail(for url: URL) -> NSImage? {
        // Quick thumbnail loading
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 200,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    
    private func selectLUT() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "cube")!]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "选择 .cube LUT 文件"
        
        if panel.runModal() == .OK, let url = panel.url {
            processor.loadLut(from: url)
        }
    }
    
    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "dng")!,
            UTType(filenameExtension: "arw")!,
            UTType(filenameExtension: "cr2")!,
            UTType(filenameExtension: "cr3")!,
            UTType(filenameExtension: "nef")!,
            UTType(filenameExtension: "raf")!,
            UTType(filenameExtension: "orf")!,
            UTType(filenameExtension: "rw2")!
        ]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            handleURL(url)
        }
    }
    
    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择包含 RAW 文件的文件夹"
        
        if panel.runModal() == .OK, let url = panel.url {
            handleURL(url)
        }
    }
    
    private func clearFiles() {
        processingMode = .empty
        processor.originalImage = nil
        processor.processedImage = nil
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        
        // Use loadObject to properly handle file URLs, which may include sandbox extensions
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                guard let url = url else {
                    print("Drop failed: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                DispatchQueue.main.async {
                    handleURL(url)
                }
            }
        }
    }
    
    private func handleURL(_ url: URL) {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        
        if isDir.boolValue {
            let rawExtensions = ["dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2"]
            do {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                let rawFiles = contents.filter { rawExtensions.contains($0.pathExtension.lowercased()) }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                
                if !rawFiles.isEmpty {
                    processingMode = .batch(rawFiles)
                    processor.wbTemp = 0
                    processor.wbTint = 0
                }
            } catch {
                print("Error scanning folder: \(error)")
            }
        } else {
            processingMode = .single(url)
            processor.loadRawImage(from: url)
        }
    }
    
    private func handleExport() {
        switch processingMode {
        case .empty:
            break
            
        case .single(let originalURL):
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.message = "选择导出目录"
            panel.prompt = "导出"
            
            if panel.runModal() == .OK, let outputDir = panel.url {
                let baseName = originalURL.deletingPathExtension().lastPathComponent
                let ext = processor.exportFormat == .heif ? "heic" : "tiff"
                let outputURL = outputDir.appendingPathComponent("\(baseName)_\(processor.selectedLogProfile.rawValue.replacingOccurrences(of: "-", with: "")).\(ext)")
                
                // Use native Swift/Metal pipeline for export (no Python dependency)
                processor.exportWithNative(to: outputURL) { success, error in
                    if success {
                        print("Export completed: \(outputURL.path)")
                    } else {
                        print("Export failed: \(error ?? "Unknown error")")
                    }
                }
            }
            
        case .batch(let urls):
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.message = "选择导出目录"
            panel.prompt = "导出"
            
            if panel.runModal() == .OK, let outputDir = panel.url {
                let settings = BatchProcessingSettings(
                    logProfile: processor.selectedLogProfile,
                    exposureMode: .auto,
                    manualEV: 0,
                    autoExposureGain: 1.0,
                    wbTemp: 0,
                    wbTint: 0,
                    saturation: processor.saturation,
                    contrast: processor.contrast,
                    exportFormat: processor.exportFormat,
                    lutURL: processor.selectedLutURL
                )
                
                batchProcessor.startBatch(
                    inputFiles: urls,
                    outputDirectory: outputDir,
                    settings: settings
                )
            }
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 600)
}
