# Still-LUT - Professional RAW to Log Color Processor

<div align="center">

[![macOS](https://img.shields.io/badge/macOS-14.0+-blue?logo=apple)](https://www.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange?logo=swift)](https://swift.org)
[![Metal](https://img.shields.io/badge/Metal-GPU%20Acceleration-green?logo=apple)](https://developer.apple.com/metal/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![GitHub](https://img.shields.io/badge/GitHub-still--lut-lightgrey?logo=github)](https://github.com/yourusername/still-lut)

**Transform your RAW photos into cinematic Log footage**

</div>

---

## 🎬 What is Still-LUT?

**Still-LUT** is a native macOS application designed for photographers and colorists, converting camera RAW files to professional Log formats with GPU-accelerated processing via Metal.

Simply put: **Shoot RAW, Get Cinematic Colors!**

---

## ✨ Core Features

### 📸 Professional Log Curve Support (13 Profiles)
- **Sony**: S-Log3, S-Log3.Cine
- **Panasonic**: V-Log
- **Fujifilm**: F-Log, F-Log2
- **Nikon**: N-Log
- **Canon**: Canon Log 2, Canon Log 3
- **ARRI**: LogC3 (EI800), LogC4
- **RED**: Log3G10
- **Leica**: L-Log
- **Blackmagic**: DaVinci Intermediate

### 📷 Extensive Camera Support
- **iPhone DNG** (ProRAW)
- **Sony ARW**
- **Canon CR2/CR3**
- **Nikon NEF**
- **Fujifilm RAF**
- **Olympus ORF**
- **Panasonic RW2**

### 🚀 Native Performance
- **Metal GPU Acceleration** - High-speed processing of large RAW files
- **Zero Dependencies** - No Python, Homebrew, or third-party software required
- **Real-time Preview** - Instant feedback while adjusting parameters
- **Batch Processing** - Process entire folders with one click

### 🎨 Professional Color Science
- **Precise Color Gamut Conversion** - P3 → S-Gamut3 / V-Gamut / Rec.2020, etc.
- **Manual/Auto Exposure** - EV ±4 stops adjustment
- **White Balance Control** - Color temperature (Kelvin) + Tint
- **Saturation/Contrast** - Precise adjustments in Log space
- **3D LUT Application** - Support for standard .cube format

### 📤 Export Options
- **HEIF 10-bit** - High compression, wide color gamut
- **TIFF 16-bit** - Lossless archival quality

---

## 🖥️ Usage

1. **Drag & Drop** - Drag RAW files or folders into the app
2. **Select Log Profile** - Choose based on your LUT or workflow
3. **Load LUT** (Optional) - Select .cube file
4. **Adjust Parameters** - Exposure, white balance, colors
5. **Export** - Choose format and save

---

## 💡 Typical Workflows

```
iPhone ProRAW → F-Log2 Conversion → Film LUT → HEIF 10-bit
                     ↓
          Perfect match for FUJIFILM Film Simulation
```

```
Sony ARW → S-Log3 Conversion → Color Grade LUT → TIFF 16-bit
               ↓
          Import to DaVinci Resolve for further grading
```

---

## 🔧 System Requirements

- **macOS 14.0 (Sonoma)** or higher
- **Apple Silicon (M1/M2/M3)** or Intel Mac
- **GPU** - Metal-compatible graphics card

---

## 📊 Technical Highlights

| Feature | Implementation |
|---------|-----------------|
| RAW Decoding | Core Image CIRAWFilter |
| Color Science | Precise 3x3 matrix transformation (XYZ intermediate) |
| Log Encoding | Metal Shaders (GPU accelerated) |
| LUT Application | Metal 3D Texture + Trilinear Interpolation |
| UI | SwiftUI (Native dark theme) |

---

## 🛠️ Installation

### Building from Source

#### Prerequisites

1. **macOS 14.0 (Sonoma)** or higher
2. **Swift 5.9+** (included with Xcode 15.0+)
3. **LibRaw** - C library for RAW decoding

#### Install LibRaw (Required)

**Using Homebrew (recommended):**
```bash
# Install LibRaw
brew install libraw
```

**Manual installation:**
```bash
# Download and compile LibRaw
git clone https://github.com/LibRaw/LibRaw.git
cd LibRaw
./configure
make
sudo make install
```

#### Build the App

```bash
# Clone repository
git clone https://github.com/yourusername/still-lut.git
cd still-lut

# Build .app bundle
./package_native_app.sh
```

The app will be created at `dist/RawToLog.app`.

### Dependencies

- **LibRaw**: C library for RAW decoding (via C bridge)
- System frameworks: Metal, CoreImage, SwiftUI, AppKit

---

---

## 🎁 Why Choose Still-LUT?

| Feature | Still-LUT | Lightroom | DaVinci Resolve |
|---------|-----------|-----------|-----------------|
| Log Curves | ✅ 13 profiles | ❌ | ✅ Video-focused |
| iPhone DNG | ✅ | ✅ | ⚠️ Complex workflow |
| 3D LUT | ✅ | ❌ | ✅ |
| Batch Processing | ✅ | ✅ | ⚠️ Complex |
| App Size | ~15MB | 2GB+ | 4GB+ |
| Dependencies | None | Subscription | None |

---

## 📁 Project Structure

```
Sources/RawToLogConverter/
├── LibRaw/              # C bridge (LibRawBridge.mm)
├── Assets.xcassets/      # App icons
├── Main files:
│   ├── RawToLogConverterApp.swift
│   ├── ContentView.swift
│   ├── MetalPipeline.swift
│   ├── NativeColorPipeline.swift
│   ├── ImageProcessor.swift
│   ├── LibRawDecoder.swift
│   ├── ColorSpaceEngine.swift
│   └── Lut3D.swift

dev/                       # Development tools and testing (not included in release)
├── test/                  # Test assets and outputs
├── python/                # Python reference implementations
├── docs/                  # Technical documentation
└── scripts/               # Old packaging scripts
```

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- [LibRaw](https://www.libraw.org/) - RAW decoding library
- [colour-science](https://colour-science.org/) - Color science reference implementation
- Apple's CoreImage framework - Native RAW processing

---

<div align="center">

**Made with 💜 for photographers who love cinematic colors**

[🔗 GitHub](https://github.com/yourusername/still-lut) | [📧 Feedback](mailto:your.email@example.com) | [⭐ Star](https://github.com/yourusername/still-lut)

</div>
