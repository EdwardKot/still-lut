import SwiftUI

// MARK: - Professional Color Grading Theme
// Inspired by DaVinci Resolve, Capture One, and Lightroom

/// Centralized theme management for professional color grading UI
enum Theme {
    // MARK: - Colors
    
    /// Background colors (layered depth system)
    enum Background {
        static let primary = Color(hex: 0x151515)      // Deepest background
        static let secondary = Color(hex: 0x1C1C1C)    // Panel background
        static let tertiary = Color(hex: 0x252525)     // Card/elevated
        static let quaternary = Color(hex: 0x2F2F2F)   // Control background
        static let elevated = Color(hex: 0x363636)     // Hover/active state
    }
    
    /// Text colors (refined hierarchy)
    enum Text {
        static let primary = Color(hex: 0xE8E8E8)      // Primary text
        static let secondary = Color(hex: 0x9A9A9A)    // Secondary/labels
        static let tertiary = Color(hex: 0x5C5C5C)     // Disabled/hints
        static let inverse = Color(hex: 0x151515)      // Text on accent
    }
    
    /// Accent colors (professional palette)
    enum Accent {
        static let orange = Color(hex: 0xE8A54B)       // Primary accent (warm amber)
        static let blue = Color(hex: 0x5B9BD5)         // Secondary accent (calm blue)
        static let green = Color(hex: 0x6ABF69)        // Success (muted green)
        static let red = Color(hex: 0xE05E5E)          // Error (soft red)
        static let purple = Color(hex: 0x9B7ED9)       // Highlight (soft purple)
        static let cyan = Color(hex: 0x5BC0BE)         // Info (teal)
    }
    
    /// Control colors (subtle and refined)
    enum Control {
        static let border = Color(hex: 0x404040)       // Subtle borders
        static let borderLight = Color(hex: 0x505050)  // Hover borders
        static let separator = Color(hex: 0x2A2A2A)    // Dividers
        static let slider = Color(hex: 0x3A3A3A)       // Slider track
        static let sliderFill = Color(hex: 0x4A4A4A)   // Slider inactive fill
        static let sliderThumb = Color(hex: 0xD5D5D5)  // Slider handle
        static let hover = Color(hex: 0x333333)        // Hover state
        static let selected = Color(hex: 0x3D3D3D)     // Selected state
    }
    
    // MARK: - Typography
    
    enum Font {
        static let sectionTitle = SwiftUI.Font.system(size: 10, weight: .semibold, design: .default)
        static let label = SwiftUI.Font.system(size: 11, weight: .regular)
        static let value = SwiftUI.Font.system(size: 11, weight: .medium).monospacedDigit()
        static let caption = SwiftUI.Font.system(size: 10, weight: .regular)
        static let button = SwiftUI.Font.system(size: 11, weight: .medium)
        static let title = SwiftUI.Font.system(size: 14, weight: .semibold)
        static let subtitle = SwiftUI.Font.system(size: 10, weight: .regular)
    }
    
    // MARK: - Dimensions
    
    enum Size {
        static let cornerRadius: CGFloat = 6
        static let cornerRadiusSmall: CGFloat = 4
        static let controlHeight: CGFloat = 26
        static let sectionSpacing: CGFloat = 16
        static let itemSpacing: CGFloat = 10
        static let panelPadding: CGFloat = 14
        static let panelWidth: CGFloat = 260
        static let sliderHeight: CGFloat = 22
    }
    
    // MARK: - Animations
    
    enum Animation {
        static let quick = SwiftUI.Animation.easeOut(duration: 0.12)
        static let smooth = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let spring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Custom View Modifiers

/// Section header style with refined tracking
struct SectionHeader: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Font.sectionTitle)
            .foregroundColor(Theme.Accent.orange)
            .textCase(.uppercase)
            .tracking(1.2)
    }
}

/// Control label style
struct ControlLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Font.label)
            .foregroundColor(Theme.Text.secondary)
    }
}

/// Value display style with monospaced digits
struct ValueDisplay: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Font.value)
            .foregroundColor(Theme.Text.primary)
    }
}

extension View {
    func sectionHeader() -> some View { modifier(SectionHeader()) }
    func controlLabel() -> some View { modifier(ControlLabel()) }
    func valueDisplay() -> some View { modifier(ValueDisplay()) }
}

// MARK: - Custom Button Styles

/// Primary accent button with subtle glow
struct AccentButtonStyle: ButtonStyle {
    var isEnabled: Bool = true
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.button)
            .foregroundColor(isEnabled ? Theme.Text.inverse : Theme.Text.tertiary)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Size.cornerRadius)
                        .fill(isEnabled ? Theme.Accent.orange : Theme.Background.quaternary)
                    
                    // Subtle inner highlight
                    if isEnabled {
                        RoundedRectangle(cornerRadius: Theme.Size.cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.15), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                }
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(Theme.Animation.quick, value: configuration.isPressed)
    }
}

/// Secondary button with refined border
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.button)
            .foregroundColor(Theme.Text.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.Size.cornerRadiusSmall)
                    .fill(configuration.isPressed ? Theme.Control.hover : Theme.Background.tertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Size.cornerRadiusSmall)
                    .stroke(
                        configuration.isPressed ? Theme.Control.borderLight : Theme.Control.border,
                        lineWidth: 1
                    )
            )
            .animation(Theme.Animation.quick, value: configuration.isPressed)
    }
}

/// Ghost button (minimal)
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.caption)
            .foregroundColor(configuration.isPressed ? Theme.Text.primary : Theme.Text.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Theme.Size.cornerRadiusSmall)
                    .fill(configuration.isPressed ? Theme.Control.hover : Color.clear)
            )
            .animation(Theme.Animation.quick, value: configuration.isPressed)
    }
}

// MARK: - Enhanced Slider with Center Mark

struct DarkSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 0.01
    var centerMark: Double? = nil  // Optional center mark (e.g., 1.0 for saturation/contrast)
    var defaultValue: Double? = nil  // Optional explicit default value for double-click reset
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onReset: (() -> Void)? = nil  // Called when double-tap resets the value
    
    @State private var isHovering = false
    @State private var isDragging = false
    
    /// The value to reset to on double-click (prioritize defaultValue > centerMark > range midpoint)
    private var resetValue: Double {
        if let def = defaultValue { return def }
        if let center = centerMark { return center }
        return (range.lowerBound + range.upperBound) / 2
    }
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let thumbX = (value - range.lowerBound) / (range.upperBound - range.lowerBound) * width
            let centerX = centerMark.map { ($0 - range.lowerBound) / (range.upperBound - range.lowerBound) * width }
            
            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.Control.slider)
                    .frame(height: 5)
                
                // Filled portion (from left to thumb)
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [Theme.Accent.orange.opacity(0.7), Theme.Accent.orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, min(thumbX, width)), height: 5)
                
                // Center mark indicator (if provided)
                if let cx = centerX {
                    Rectangle()
                        .fill(Theme.Text.tertiary)
                        .frame(width: 1.5, height: 11)
                        .offset(x: cx - 0.75)
                }
                
                // Thumb with subtle shadow and hover effect
                Circle()
                    .fill(Theme.Control.sliderThumb)
                    .frame(width: isHovering || isDragging ? 16 : 14, 
                           height: isHovering || isDragging ? 16 : 14)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .overlay(
                        Circle()
                            .stroke(Theme.Accent.orange.opacity(isDragging ? 0.8 : 0), lineWidth: 2)
                    )
                    .offset(x: thumbX - (isHovering || isDragging ? 8 : 7))
                    .animation(Theme.Animation.spring, value: isHovering)
                    .animation(Theme.Animation.spring, value: isDragging)
            }
            .contentShape(Rectangle())  // Make entire area tappable
            .onHover { hovering in
                isHovering = hovering
            }
            .gesture(
                DragGesture(minimumDistance: 3)  // Allow small movements to be taps
                    .onChanged { gesture in
                        isDragging = true
                        let newValue = range.lowerBound + (gesture.location.x / width) * (range.upperBound - range.lowerBound)
                        let stepped = (newValue / step).rounded() * step
                        value = min(max(stepped, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        // Double-tap detected - reset to default value
                        if let resetCallback = onReset {
                            // Let onReset handle the reset entirely (for complex cases like Optional bindings)
                            resetCallback()
                        } else {
                            // Default behavior: set value to resetValue
                            value = resetValue
                        }
                    }
            )
        }
        .frame(height: Theme.Size.sliderHeight)
    }
}

// MARK: - Section Container with Refined Styling

struct SectionCard<Content: View>: View {
    let title: String
    let content: Content
    
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Size.itemSpacing) {
            Text(title)
                .sectionHeader()
            
            content
        }
        .padding(Theme.Size.panelPadding)
        .background(
            RoundedRectangle(cornerRadius: Theme.Size.cornerRadius)
                .fill(Theme.Background.tertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Size.cornerRadius)
                        .stroke(Theme.Control.separator, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Status Bar Component

struct StatusBar: View {
    var leftText: String
    var rightText: String
    
    var body: some View {
        HStack {
            Text(leftText)
                .font(Theme.Font.caption)
                .foregroundColor(Theme.Text.tertiary)
            
            Spacer()
            
            Text(rightText)
                .font(Theme.Font.caption)
                .foregroundColor(Theme.Text.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.Background.secondary)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        SectionCard("Log Profile") {
            Text("F-Log2")
                .foregroundColor(Theme.Text.primary)
        }
        
        Button("导出") {}
            .buttonStyle(AccentButtonStyle())
        
        Button("取消") {}
            .buttonStyle(SecondaryButtonStyle())
        
        VStack(alignment: .leading, spacing: 8) {
            Text("饱和度")
                .controlLabel()
            DarkSlider(value: .constant(1.0), range: 0...2, centerMark: 1.0)
        }
        .padding()
        .background(Theme.Background.tertiary)
        .cornerRadius(Theme.Size.cornerRadius)
    }
    .padding()
    .background(Theme.Background.primary)
}
