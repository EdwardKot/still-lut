# RAW+LUT - Agent Development Guide

This guide provides essential information for agentic coding working with this RAW-to-Log color converter project.

---

## Project Overview

**RAW+LUT** is a native macOS application that converts camera RAW files to professional Log formats with Metal GPU acceleration.

- **Platform**: macOS 14.0+ (Swift 5.9+)
- **Core Tech**: Swift Package Manager, Metal, SwiftUI, CoreImage
- **Purpose**: Photography/videography color pipeline processing

---

## Build Commands

### Swift Build
```bash
# Debug build
swift build

# Release build (for packaging)
swift build -c release

# Build executable path
.build/debug/RawToLogConverter   # Debug
.build/release/RawToLogConverter  # Release
```

### App Packaging
```bash
# Native Swift/Metal app (no Python dependency)
./package_native_app.sh

# Creates: dist/RawToLog.app
```

### Running Tests
```bash
# Run manual Swift pipeline test
swift Sources/RawToLogConverter/TestRunner.swift

# Run Python numerical accuracy test
python3 test_numerical_accuracy.py <swift_output.tiff> <python_reference.tiff>

# Run Python color space tests
python3 color_space_engine.py
```

**Note**: This project uses manual testing rather than `swift test` (no SPM tests configured).

---

## Code Style Guidelines

### Swift Code Style

#### File Organization
- Use `// MARK: - SectionName` comments for logical grouping
- Structure: Imports → MARK: Errors → MARK: Types → MARK: Implementation
- Example:
  ```swift
  // MARK: - Errors
  enum LibRawError: Error, LocalizedError { ... }

  // MARK: - Result Structure
  struct LibRawImage { ... }

  // MARK: - Decoder
  class LibRawXYZDecoder { ... }
  ```

#### Naming Conventions
- **Enums**: `NativeLogProfile`, `LibRawError` (PascalCase)
- **Cases**: `case fLog2`, `case sLog3` (camelCase)
- **Properties**: `var kernelName`, `let width` (camelCase)
- **Constants**: `ColorMatrices.XYZ_to_Rec2020` (PascalCase with dot notation)
- **Functions**: `func decode(url:)` (camelCase with parameter labels)

#### Type Safety
- Use typed errors with `LocalizedError` conformance:
  ```swift
  enum LibRawError: Error, LocalizedError {
      case decodeFailed(String)
      case fileNotFound

      var errorDescription: String? { ... }
  }
  ```

- Use computed properties for derived values:
  ```swift
  var kernelName: String {
      switch self { ... }
  }
  ```

#### Metal Integration
- Use `simd_float3` and `simd_float3x3` for color matrices
- Float32 for precision: `MTLBuffer` with Float32 (not Float16) to preserve 16-bit RAW
- Manual memory management: `defer { libraw_free_result(&result) }`

#### Swift Patterns
- Struct over class for data models
- Class with `private let device` for stateful components
- `@MainActor` for UI-thread operations
- Optional chaining over force unwrapping

### Python Code Style

#### Type Hints
```python
from typing import Optional, Tuple, List, Dict

def decode(url: str) -> Optional[Tuple[int, int]]:
    pass
```

#### Docstrings
```python
"""
Function description

Args:
    param1: Description

Returns:
    Type description
"""
```

#### Enum Classes
```python
class LogProfile(Enum):
    SLOG3 = ("S-Log3", "S-Gamut3")

    @property
    def display_name(self) -> str:
        return self.value[0]
```

---

## Import Organization

### Swift
```swift
import Foundation
import Metal
import CoreImage
import simd
import LibRawBridge  // Local C bridge
import SwiftUI
```
- Standard framework imports first
- Project-local imports last

### Python
```python
import os
import sys
from enum import Enum
from typing import Optional, Tuple
import numpy as np
import tifffile
import colour
```

---

## Project Structure

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
│   ├── Lut3D.swift
│   └── TestRunner.swift   # Manual testing

test/                      # Test assets (DNG files, LUTs, outputs)
docs/                      # Technical documentation
```

---

## Testing Strategy

1. **Manual Swift Tests**: Run `TestRunner.swift` after build to verify pipeline
2. **Python Reference**: `raw_to_log.py` serves as reference implementation
3. **Numerical Accuracy**: Compare Swift vs Python outputs pixel-by-pixel
4. **Test Images**: Use `test/IDG_20251014_162641_258.DNG` for validation

---

## Dependencies

### Swift (SPM)
- **LibRaw**: C library for RAW decoding (via C bridge)
- System frameworks: Metal, CoreImage, SwiftUI, AppKit

### Python (Testing Only)
- `rawpy>=0.19.0`
- `numpy>=1.21.0,<2.0.0`
- `tifffile>=2023.1.0`
- `scipy==1.10.1`
- `colour-science>=0.4.4`

---

## Key Technical Decisions

### Color Pipeline
- **Path**: RAW → XYZ (Linear, D65) → Target Gamut → Log
- **Avoid**: ProPhoto RGB intermediate (use XYZ directly)
- **Precision**: Float32 throughout pipeline to preserve 16-bit RAW data

### Metal Optimization
- **Compute Shaders**: Parallel pixel processing on GPU
- **3D LUTs**: Metal 3D textures with trilinear interpolation
- **Buffer Storage**: `.storageModeShared` for CPU-GPU data sharing

---

## Common Patterns

### Error Handling (Swift)
```swift
do {
    let result = try decoder.decode(url: url)
    // Use result
} catch LibRawError.fileNotFound {
    print("File not found")
} catch {
    print("Unknown error: \(error)")
}
```

### Color Matrix Application (Metal)
```swift
let matrix = ColorMatrices.XYZ_to_Rec2020
let transformed = matrix * xyzVector
```

### Resource Cleanup
```swift
let buffer = device.makeBuffer(...)
defer {
    // Cleanup automatically when scope exits
}
```

---

## File Naming

- **Swift files**: `PascalCase.swift` (e.g., `MetalPipeline.swift`)
- **Python files**: `snake_case.py` (e.g., `raw_to_log.py`)
- **Shaders**: Inline in Swift files as multiline strings

---

## Additional Notes

- This project includes Chinese comments in some files (bilingual documentation)
- Test runner paths are hardcoded: `/Users/edward/Documents/Antigravity/RAW+LUT/test/`
- No automated test suite - manual verification required after changes
- App bundles are signed ad-hoc: `codesign --force --deep --sign -`
