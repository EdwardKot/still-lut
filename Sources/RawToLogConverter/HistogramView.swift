import SwiftUI

/// RGB Histogram data structure with clipping detection
struct HistogramData {
    var red: [UInt32]
    var green: [UInt32]
    var blue: [UInt32]
    var maxValue: UInt32
    
    // Clipping detection
    var shadowClipping: Bool = false   // Pixels at 0
    var highlightClipping: Bool = false // Pixels at 255
    var shadowClipCount: UInt32 = 0
    var highlightClipCount: UInt32 = 0
    
    static let binCount = 256
    
    init() {
        red = [UInt32](repeating: 0, count: Self.binCount)
        green = [UInt32](repeating: 0, count: Self.binCount)
        blue = [UInt32](repeating: 0, count: Self.binCount)
        maxValue = 1
    }
    
    /// Compute histogram from CGImage with clipping detection
    static func compute(from cgImage: CGImage) -> HistogramData {
        var data = HistogramData()
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bitsPerComponent = cgImage.bitsPerComponent
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        
        guard let dataProvider = cgImage.dataProvider,
              let pixelData = dataProvider.data,
              let bytes = CFDataGetBytePtr(pixelData) else {
            return data
        }
        
        // Sample every Nth pixel for performance
        let stepX = max(1, width / 256)
        let stepY = max(1, height / 256)
        
        var totalPixels: UInt32 = 0
        
        for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                
                let r: UInt8
                let g: UInt8
                let b: UInt8
                
                if bitsPerComponent == 16 {
                    r = bytes[offset + 1]
                    g = bytes[offset + 3]
                    b = bytes[offset + 5]
                } else {
                    r = bytes[offset]
                    g = bytes[offset + 1]
                    b = bytes[offset + 2]
                }
                
                data.red[Int(r)] += 1
                data.green[Int(g)] += 1
                data.blue[Int(b)] += 1
                
                // Detect clipping
                if r == 0 || g == 0 || b == 0 {
                    data.shadowClipCount += 1
                }
                if r == 255 || g == 255 || b == 255 {
                    data.highlightClipCount += 1
                }
                
                totalPixels += 1
            }
        }
        
        // Find max for normalization (exclude extreme bins for better visualization)
        let middleRange = 5..<251
        data.maxValue = max(
            data.red[middleRange].max() ?? 1,
            data.green[middleRange].max() ?? 1,
            data.blue[middleRange].max() ?? 1
        )
        
        // Clipping threshold: > 0.5% of pixels
        let clipThreshold = totalPixels / 200
        data.shadowClipping = data.shadowClipCount > clipThreshold
        data.highlightClipping = data.highlightClipCount > clipThreshold
        
        return data
    }
}

/// Capture One-inspired RGB Histogram View
/// Clean, minimal design with smooth RGB curves and subtle clipping indicators
struct HistogramView: View {
    let data: HistogramData?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Pure dark background - no border, clean look
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(white: 0.06))
                
                if let data = data {
                    // Histogram curves
                    Canvas { context, size in
                        let width = size.width
                        let height = size.height
                        let binWidth = width / CGFloat(HistogramData.binCount)
                        let maxVal = CGFloat(max(data.maxValue, 1))
                        
                        // Draw RGB channels with additive blending effect
                        // Blue first (back), then Green, then Red (front)
                        drawSmoothChannel(
                            context: context, 
                            bins: data.blue,
                            color: Color(red: 0.3, green: 0.5, blue: 1.0),
                            width: width, height: height, 
                            binWidth: binWidth, maxVal: maxVal
                        )
                        
                        drawSmoothChannel(
                            context: context, 
                            bins: data.green,
                            color: Color(red: 0.3, green: 0.9, blue: 0.4),
                            width: width, height: height, 
                            binWidth: binWidth, maxVal: maxVal
                        )
                        
                        drawSmoothChannel(
                            context: context, 
                            bins: data.red,
                            color: Color(red: 1.0, green: 0.4, blue: 0.35),
                            width: width, height: height, 
                            binWidth: binWidth, maxVal: maxVal
                        )
                        
                        // Subtle clipping glow on edges
                        if data.shadowClipping {
                            let gradient = Gradient(colors: [
                                Color.red.opacity(0.4),
                                Color.red.opacity(0.0)
                            ])
                            let rect = CGRect(x: 0, y: 0, width: 12, height: height)
                            context.fill(
                                Path(rect),
                                with: .linearGradient(
                                    gradient,
                                    startPoint: CGPoint(x: 0, y: height/2),
                                    endPoint: CGPoint(x: 12, y: height/2)
                                )
                            )
                        }
                        
                        if data.highlightClipping {
                            let gradient = Gradient(colors: [
                                Color.red.opacity(0.0),
                                Color.red.opacity(0.4)
                            ])
                            let rect = CGRect(x: width - 12, y: 0, width: 12, height: height)
                            context.fill(
                                Path(rect),
                                with: .linearGradient(
                                    gradient,
                                    startPoint: CGPoint(x: width - 12, y: height/2),
                                    endPoint: CGPoint(x: width, y: height/2)
                                )
                            )
                        }
                    }
                    .padding(4)
                } else {
                    // Minimal placeholder
                    Text("—")
                        .font(.system(size: 10, weight: .light))
                        .foregroundColor(Color(white: 0.3))
                }
            }
        }
        .frame(height: 60)
    }
    
    /// Draw a single RGB channel with smooth curves and gradient fill
    private func drawSmoothChannel(
        context: GraphicsContext,
        bins: [UInt32],
        color: Color,
        width: CGFloat,
        height: CGFloat,
        binWidth: CGFloat,
        maxVal: CGFloat
    ) {
        // Build smooth path using moving average
        var smoothedValues: [CGFloat] = []
        let windowSize = 3
        
        for i in 0..<bins.count {
            var sum: CGFloat = 0
            var count: CGFloat = 0
            for j in max(0, i - windowSize)...min(bins.count - 1, i + windowSize) {
                sum += CGFloat(bins[j])
                count += 1
            }
            let value = sum / count
            // Log-like scaling for better visualization
            let normalized = value > 0 ? pow(value / maxVal, 0.5) : 0
            smoothedValues.append(normalized)
        }
        
        // Create filled path
        var path = Path()
        path.move(to: CGPoint(x: 0, y: height))
        
        for (index, normalizedValue) in smoothedValues.enumerated() {
            let x = CGFloat(index) * binWidth
            let y = height - (normalizedValue * height * 0.92)
            
            if index == 0 {
                path.addLine(to: CGPoint(x: x, y: y))
            } else {
                // Use quadratic curve for smoothness
                let prevX = CGFloat(index - 1) * binWidth
                let controlX = (prevX + x) / 2
                path.addQuadCurve(
                    to: CGPoint(x: x, y: y),
                    control: CGPoint(x: controlX, y: y)
                )
            }
        }
        
        path.addLine(to: CGPoint(x: width, y: height))
        path.closeSubpath()
        
        // Gradient fill from color to transparent
        let gradient = Gradient(colors: [
            color.opacity(0.6),
            color.opacity(0.2)
        ])
        
        context.fill(
            path,
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: width/2, y: 0),
                endPoint: CGPoint(x: width/2, y: height)
            )
        )
        
        // Subtle stroke on top edge for definition
        var strokePath = Path()
        strokePath.move(to: CGPoint(x: 0, y: height - (smoothedValues[0] * height * 0.92)))
        
        for (index, normalizedValue) in smoothedValues.enumerated() {
            let x = CGFloat(index) * binWidth
            let y = height - (normalizedValue * height * 0.92)
            strokePath.addLine(to: CGPoint(x: x, y: y))
        }
        
        context.stroke(strokePath, with: .color(color.opacity(0.8)), lineWidth: 0.5)
    }
}

#Preview {
    VStack(spacing: 20) {
        // Normal exposure
        HistogramView(data: {
            var d = HistogramData()
            for i in 20..<236 {
                d.red[i] = UInt32(sin(Double(i - 20) / 40.0) * 1000 + 500)
                d.green[i] = UInt32(sin(Double(i - 20) / 30.0 + 1) * 800 + 400)
                d.blue[i] = UInt32(sin(Double(i - 20) / 50.0 + 2) * 1200 + 300)
            }
            d.maxValue = 1700
            d.shadowClipping = false
            d.highlightClipping = false
            return d
        }())
        .padding(.horizontal)
        
        // With clipping
        HistogramView(data: {
            var d = HistogramData()
            for i in 0..<256 {
                d.red[i] = UInt32(max(0, 1500 - abs(i - 200) * 15))
                d.green[i] = UInt32(max(0, 1200 - abs(i - 180) * 12))
                d.blue[i] = UInt32(max(0, 1000 - abs(i - 220) * 10))
            }
            d.red[255] = 2000
            d.green[255] = 1800
            d.red[0] = 1500
            d.maxValue = 1500
            d.shadowClipping = true
            d.highlightClipping = true
            return d
        }())
        .padding(.horizontal)
        
        // Empty
        HistogramView(data: nil)
            .padding(.horizontal)
    }
    .padding()
    .background(Color(white: 0.12))
}
