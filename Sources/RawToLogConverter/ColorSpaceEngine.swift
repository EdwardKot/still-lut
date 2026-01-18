import Foundation
import simd

// MARK: - White Points

/// Standard illuminant chromaticity coordinates (CIE 1931 xy)
enum WhitePoint: String, CaseIterable {
    case D50 = "D50"
    case D65 = "D65"
    case D60 = "D60"
    
    /// Chromaticity coordinates (x, y)
    var chromaticity: SIMD2<Double> {
        switch self {
        case .D50: return SIMD2(0.34567, 0.35850)
        case .D65: return SIMD2(0.31270, 0.32900)
        case .D60: return SIMD2(0.32168, 0.33767)
        }
    }
    
    /// XYZ tristimulus values (normalized Y=1)
    var xyz: SIMD3<Double> {
        let (x, y) = (chromaticity.x, chromaticity.y)
        return SIMD3(x / y, 1.0, (1 - x - y) / y)
    }
}

// MARK: - Color Space Definition

/// Represents an RGB color space defined by chromaticity primaries and white point
struct ColorSpaceDefinition {
    let name: String
    let primaries: (r: SIMD2<Double>, g: SIMD2<Double>, b: SIMD2<Double>)
    let whitePoint: WhitePoint
    
    // Cached matrices (computed lazily)
    private var _rgbToXYZ: simd_double3x3?
    private var _xyzToRGB: simd_double3x3?
    
    /// Standard color space definitions
    static let sRGB = ColorSpaceDefinition(
        name: "sRGB",
        primaries: (
            r: SIMD2(0.640, 0.330),
            g: SIMD2(0.300, 0.600),
            b: SIMD2(0.150, 0.060)
        ),
        whitePoint: .D65
    )
    
    static let displayP3 = ColorSpaceDefinition(
        name: "Display P3",
        primaries: (
            r: SIMD2(0.680, 0.320),
            g: SIMD2(0.265, 0.690),
            b: SIMD2(0.150, 0.060)
        ),
        whitePoint: .D65
    )
    
    static let proPhotoRGB = ColorSpaceDefinition(
        name: "ProPhoto RGB",
        primaries: (
            r: SIMD2(0.7347, 0.2653),
            g: SIMD2(0.1596, 0.8404),
            b: SIMD2(0.0366, 0.0001)
        ),
        whitePoint: .D50  // ProPhoto uses D50
    )
    
    static let rec2020 = ColorSpaceDefinition(
        name: "ITU-R BT.2020",
        primaries: (
            r: SIMD2(0.708, 0.292),
            g: SIMD2(0.170, 0.797),
            b: SIMD2(0.131, 0.046)
        ),
        whitePoint: .D65
    )
    
    static let acesCG = ColorSpaceDefinition(
        name: "ACEScg",
        primaries: (
            r: SIMD2(0.713, 0.293),
            g: SIMD2(0.165, 0.830),
            b: SIMD2(0.128, 0.044)
        ),
        whitePoint: .D60  // ACES uses D60
    )
    
    static let sGamut3 = ColorSpaceDefinition(
        name: "S-Gamut3",
        primaries: (
            r: SIMD2(0.730, 0.280),
            g: SIMD2(0.140, 0.855),
            b: SIMD2(0.100, -0.050)
        ),
        whitePoint: .D65
    )
    
    static let vGamut = ColorSpaceDefinition(
        name: "V-Gamut",
        primaries: (
            r: SIMD2(0.730, 0.280),
            g: SIMD2(0.165, 0.840),
            b: SIMD2(0.100, -0.030)
        ),
        whitePoint: .D65
    )
}

// MARK: - Color Space Engine

/// Engine for dynamic color space matrix computation
class ColorSpaceEngine {
    
    /// Singleton instance
    static let shared = ColorSpaceEngine()
    
    /// Cache for computed matrices
    private var matrixCache: [String: simd_double3x3] = [:]
    
    private init() {}
    
    // MARK: - Matrix Computation from Chromaticities
    
    /// Compute RGB→XYZ matrix from primaries and white point
    /// Reference: Bruce Lindbloom's RGB/XYZ Matrix Derivation
    func computeRGBtoXYZ(primaries: (r: SIMD2<Double>, g: SIMD2<Double>, b: SIMD2<Double>),
                         whitePoint: WhitePoint) -> simd_double3x3 {
        let cacheKey = "rgb2xyz_\(primaries.r)_\(primaries.g)_\(primaries.b)_\(whitePoint.rawValue)"
        
        if let cached = matrixCache[cacheKey] {
            return cached
        }
        
        // Primary chromaticities to XYZ (assuming Y=1 for each)
        let Xr = primaries.r.x / primaries.r.y
        let Yr = 1.0
        let Zr = (1 - primaries.r.x - primaries.r.y) / primaries.r.y
        
        let Xg = primaries.g.x / primaries.g.y
        let Yg = 1.0
        let Zg = (1 - primaries.g.x - primaries.g.y) / primaries.g.y
        
        let Xb = primaries.b.x / primaries.b.y
        let Yb = 1.0
        let Zb = (1 - primaries.b.x - primaries.b.y) / primaries.b.y
        
        // Matrix of primary XYZ values
        let M = simd_double3x3(columns: (
            SIMD3(Xr, Yr, Zr),
            SIMD3(Xg, Yg, Zg),
            SIMD3(Xb, Yb, Zb)
        ))
        
        // White point XYZ
        let W = whitePoint.xyz
        
        // Solve for scaling factors: M * S = W
        let S = simd_inverse(M) * W
        
        // Scale each column by the corresponding S factor
        let result = simd_double3x3(columns: (
            M.columns.0 * S.x,
            M.columns.1 * S.y,
            M.columns.2 * S.z
        ))
        
        matrixCache[cacheKey] = result
        return result
    }
    
    /// Compute XYZ→RGB matrix (inverse of RGB→XYZ)
    func computeXYZtoRGB(primaries: (r: SIMD2<Double>, g: SIMD2<Double>, b: SIMD2<Double>),
                         whitePoint: WhitePoint) -> simd_double3x3 {
        let rgbToXYZ = computeRGBtoXYZ(primaries: primaries, whitePoint: whitePoint)
        return simd_inverse(rgbToXYZ)
    }
    
    /// Get RGB→XYZ matrix for a color space
    func rgbToXYZ(for colorSpace: ColorSpaceDefinition) -> simd_double3x3 {
        return computeRGBtoXYZ(primaries: colorSpace.primaries, whitePoint: colorSpace.whitePoint)
    }
    
    /// Get XYZ→RGB matrix for a color space
    func xyzToRGB(for colorSpace: ColorSpaceDefinition) -> simd_double3x3 {
        return computeXYZtoRGB(primaries: colorSpace.primaries, whitePoint: colorSpace.whitePoint)
    }
    
    // MARK: - Bradford Chromatic Adaptation
    
    /// Bradford cone response matrix
    private let bradfordMatrix = simd_double3x3(columns: (
        SIMD3( 0.8951000,  0.2664000, -0.1614000),
        SIMD3(-0.7502000,  1.7135000,  0.0367000),
        SIMD3( 0.0389000, -0.0685000,  1.0296000)
    ))
    
    /// Inverse Bradford matrix
    private lazy var bradfordInverse: simd_double3x3 = {
        simd_inverse(bradfordMatrix)
    }()
    
    /// Compute Bradford chromatic adaptation transform from source to destination white point
    func bradfordCAT(from source: WhitePoint, to destination: WhitePoint) -> simd_double3x3 {
        if source == destination {
            return matrix_identity_double3x3
        }
        
        let cacheKey = "bradford_\(source.rawValue)_\(destination.rawValue)"
        if let cached = matrixCache[cacheKey] {
            return cached
        }
        
        // Source and destination white points in XYZ
        let srcXYZ = source.xyz
        let dstXYZ = destination.xyz
        
        // Convert to cone response space
        let srcCone = bradfordMatrix * srcXYZ
        let dstCone = bradfordMatrix * dstXYZ
        
        // Diagonal scaling matrix
        let scale = simd_double3x3(diagonal: SIMD3(
            dstCone.x / srcCone.x,
            dstCone.y / srcCone.y,
            dstCone.z / srcCone.z
        ))
        
        // Complete transform: M^-1 * Scale * M
        let result = bradfordInverse * scale * bradfordMatrix
        
        matrixCache[cacheKey] = result
        return result
    }
    
    // MARK: - Composite Matrix Computation
    
    /// Compute matrix to convert from source color space to destination color space
    /// Handles white point adaptation automatically using Bradford CAT
    func conversionMatrix(from source: ColorSpaceDefinition, 
                          to destination: ColorSpaceDefinition) -> simd_double3x3 {
        let cacheKey = "convert_\(source.name)_\(destination.name)"
        if let cached = matrixCache[cacheKey] {
            return cached
        }
        
        // Step 1: Source RGB → XYZ (in source white point)
        let srcToXYZ = rgbToXYZ(for: source)
        
        // Step 2: Chromatic adaptation if white points differ
        let cat = bradfordCAT(from: source.whitePoint, to: destination.whitePoint)
        
        // Step 3: XYZ → Destination RGB
        let xyzToDst = xyzToRGB(for: destination)
        
        // Composite: dst = xyzToDst * cat * srcToXYZ * src
        let result = xyzToDst * cat * srcToXYZ
        
        matrixCache[cacheKey] = result
        return result
    }
    
    // MARK: - LibRaw XYZ Pipeline Support
    
    /// Compute combined matrix for LibRaw XYZ (D50) → Target Gamut RGB conversion
    /// DEPRECATED: LibRaw output_color=5 actually outputs D65, not D50
    /// Use xyzD65ToTargetGamut instead
    func xyzD50ToTargetGamut(_ target: ColorSpaceDefinition) -> simd_float3x3 {
        let cacheKey = "xyzD50_to_\(target.name)"
        if let cached = matrixCache[cacheKey] {
            return toFloat(cached)
        }
        
        // Bradford chromatic adaptation: D50 → target white point
        let cat = bradfordCAT(from: .D50, to: target.whitePoint)
        
        // XYZ (adapted to target white point) → Target RGB
        let xyzToTarget = xyzToRGB(for: target)
        
        // Combined: target_rgb = xyzToTarget * cat * xyz_d50
        let combined = xyzToTarget * cat
        
        matrixCache[cacheKey] = combined
        return toFloat(combined)
    }
    
    /// Compute combined matrix for LibRaw XYZ (D65) → Target Gamut RGB conversion
    /// This is the CORRECT function for LibRaw output_color=5 which outputs XYZ D65
    /// Most video color spaces (Rec.2020, S-Gamut3, V-Gamut, etc.) use D65, so no CAT needed
    func xyzD65ToTargetGamut(_ target: ColorSpaceDefinition) -> simd_float3x3 {
        let cacheKey = "xyzD65_to_\(target.name)"
        if let cached = matrixCache[cacheKey] {
            return toFloat(cached)
        }
        
        let combined: simd_double3x3
        
        if target.whitePoint == .D65 {
            // Target is D65: Direct XYZ→RGB conversion, no CAT needed
            combined = xyzToRGB(for: target)
        } else {
            // Target is not D65: Need chromatic adaptation D65 → target white point
            let cat = bradfordCAT(from: .D65, to: target.whitePoint)
            let xyzToTarget = xyzToRGB(for: target)
            combined = xyzToTarget * cat
        }
        
        matrixCache[cacheKey] = combined
        return toFloat(combined)
    }
    
    /// Get all target gamut matrices for batch processing (precompute)
    func precomputeAllXYZD50Matrices() -> [String: simd_float3x3] {
        let targets: [ColorSpaceDefinition] = [
            .sRGB, .displayP3, .proPhotoRGB, .rec2020, 
            .acesCG, .sGamut3, .vGamut
        ]
        var result: [String: simd_float3x3] = [:]
        for target in targets {
            result[target.name] = xyzD50ToTargetGamut(target)
        }
        return result
    }
    
    // MARK: - Float32 Conversion for Metal
    
    /// Convert Double matrix to Float for Metal shaders
    func toFloat(_ matrix: simd_double3x3) -> simd_float3x3 {
        return simd_float3x3(
            SIMD3<Float>(Float(matrix.columns.0.x), Float(matrix.columns.0.y), Float(matrix.columns.0.z)),
            SIMD3<Float>(Float(matrix.columns.1.x), Float(matrix.columns.1.y), Float(matrix.columns.1.z)),
            SIMD3<Float>(Float(matrix.columns.2.x), Float(matrix.columns.2.y), Float(matrix.columns.2.z))
        )
    }
    
    // MARK: - Verification
    
    /// Verify matrix accuracy with known color values
    func verifyMatrix(_ matrix: simd_double3x3, 
                      input: SIMD3<Double>, 
                      expected: SIMD3<Double>, 
                      tolerance: Double = 1e-6) -> Bool {
        let result = matrix * input
        let delta = simd_length(result - expected)
        return delta < tolerance
    }
}

// MARK: - Unit Tests Extension

extension ColorSpaceEngine {
    
    /// Run self-verification tests
    func runSelfTests() -> Bool {
        print("Running ColorSpaceEngine self-tests...")
        
        // Test 1: sRGB primary red → XYZ
        let sRGBtoXYZ = rgbToXYZ(for: .sRGB)
        let _ = sRGBtoXYZ * SIMD3<Double>(1, 0, 0) // redXYZ used for reference
        // sRGB red primary should be approximately (0.4124, 0.2126, 0.0193)
        let expectedRedXYZ = SIMD3<Double>(0.4124564, 0.2126729, 0.0193339)
        let test1 = verifyMatrix(sRGBtoXYZ, input: SIMD3(1, 0, 0), expected: expectedRedXYZ, tolerance: 1e-4)
        print("  Test 1 (sRGB Red → XYZ): \(test1 ? "✅" : "❌")")
        
        // Test 2: Round-trip sRGB → XYZ → sRGB
        let xyzToSRGB = xyzToRGB(for: .sRGB)
        let roundTrip = xyzToSRGB * sRGBtoXYZ
        let _ = matrix_identity_double3x3  // Keep for reference but mark as intentionally unused
        var test2 = true
        for i in 0..<3 {
            for j in 0..<3 {
                let expected = (i == j) ? 1.0 : 0.0
                if abs(roundTrip[i][j] - expected) > 1e-10 {
                    test2 = false
                }
            }
        }
        print("  Test 2 (sRGB round-trip): \(test2 ? "✅" : "❌")")
        
        // Test 3: Bradford D65 → D50 → D65 round-trip
        let d65ToD50 = bradfordCAT(from: .D65, to: .D50)
        let d50ToD65 = bradfordCAT(from: .D50, to: .D65)
        let catRoundTrip = d50ToD65 * d65ToD50
        var test3 = true
        for i in 0..<3 {
            for j in 0..<3 {
                let expected = (i == j) ? 1.0 : 0.0
                if abs(catRoundTrip[i][j] - expected) > 1e-10 {
                    test3 = false
                }
            }
        }
        print("  Test 3 (Bradford round-trip): \(test3 ? "✅" : "❌")")
        
        let allPassed = test1 && test2 && test3
        print("ColorSpaceEngine self-tests: \(allPassed ? "ALL PASSED ✅" : "SOME FAILED ❌")")
        return allPassed
    }
}
