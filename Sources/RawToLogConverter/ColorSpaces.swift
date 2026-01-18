import CoreImage

struct ColorMatrix {
    let r: CIVector
    let g: CIVector
    let b: CIVector
    let a: CIVector
    
    // MARK: - Identity
    
    static let identity = ColorMatrix(
        r: CIVector(x: 1, y: 0, z: 0, w: 0),
        g: CIVector(x: 0, y: 1, z: 0, w: 0),
        b: CIVector(x: 0, y: 0, z: 1, w: 0),
        a: CIVector(x: 0, y: 0, z: 0, w: 1)
    )
    
    /// Bradford Chromatic Adaptation Transform: D50 → D65
    /// Used to convert from DNG's D50 white point to video standard D65
    /// Pre-computed matrix from Bradford CAT formula
    static let Bradford_D50_to_D65 = ColorMatrix(
        r: CIVector(x:  0.9555766, y: -0.0230393, z:  0.0631636, w: 0),
        g: CIVector(x: -0.0282895, y:  1.0099416, z:  0.0210077, w: 0),
        b: CIVector(x:  0.0122982, y: -0.0204830, z:  1.3299098, w: 0),
        a: CIVector(x: 0, y: 0, z: 0, w: 1)
    )
    
    // MARK: - Display P3 → XYZ (D65)
    
    /// Display P3 (Linear, D65) → XYZ (D65)
    /// Source: Display P3 color space specification (ICC profile)
    /// This matrix matches colour-science's RGB_to_XYZ for Display P3
    static let P3_to_XYZ = ColorMatrix(
        r: CIVector(x: 0.4865709486, y: 0.2656676932, z: 0.1982172852, w: 0),
        g: CIVector(x: 0.2289745641, y: 0.6917385218, z: 0.0792869141, w: 0),
        b: CIVector(x: 0.0000000000, y: 0.0451133819, z: 1.0439443689, w: 0),
        a: CIVector(x: 0, y: 0, z: 0, w: 1)
    )
    
    // MARK: - XYZ (D65) → Target Gamut Matrices
    // These matrices convert from CIE XYZ (D65 white point) to various video color gamuts
    // All matrices are row-major: output_R = dot(input_XYZ, r.xyz), etc.
    
    /// XYZ (D65) → S-Gamut3 (Sony)
    /// Source: Sony S-Log3/S-Gamut3 Technical Summary
    /// S-Gamut3 primaries: R(0.730, 0.280), G(0.140, 0.855), B(0.100, -0.050)
    static let XYZ_to_SGamut3 = ColorMatrix(
        r: CIVector(x:  1.8467789693, y: -0.5259861230, z: -0.2105452114, w: 0),
        g: CIVector(x: -0.4441531566, y:  1.2594429028, z:  0.1493998071, w: 0),
        b: CIVector(x:  0.0408231292, y:  0.0156628005, z:  0.8682805350, w: 0),
        a: CIVector(x: 0, y: 0, z: 0, w: 1)
    )
    
    /// XYZ (D65) → V-Gamut (Panasonic)
    /// Source: Panasonic V-Log/V-Gamut White Paper (2014)
    /// V-Gamut primaries: R(0.730, 0.280), G(0.165, 0.840), B(0.100, -0.030)
    static let XYZ_to_VGamut = ColorMatrix(
        r: CIVector(x:  1.5890271270, y: -0.3133503604, z: -0.1808091984, w: 0),
        g: CIVector(x: -0.5341191671, y:  1.3962743855, z:  0.1023665344, w: 0),
        b: CIVector(x:  0.0000000000, y:  0.0000000000, z:  0.9056967220, w: 0),
        a: CIVector(x: 0, y: 0, z: 0, w: 1)
    )
    
    /// XYZ (D65) → Rec.2020/F-Gamut (Fujifilm F-Log2 uses Rec.2020 primaries)
    /// Source: ITU-R BT.2020 / Fujifilm F-Log2 Data Sheet
    /// Rec.2020 primaries: R(0.708, 0.292), G(0.170, 0.797), B(0.131, 0.046)
    static let XYZ_to_Rec2020 = ColorMatrix(
        r: CIVector(x:  1.7166511880, y: -0.3556707838, z: -0.2533662814, w: 0),
        g: CIVector(x: -0.6666843518, y:  1.6164812366, z:  0.0157685458, w: 0),
        b: CIVector(x:  0.0176398574, y: -0.0427706133, z:  0.9421031212, w: 0),
        a: CIVector(x: 0, y: 0, z: 0, w: 1)
    )
    
    /// Alias for F-Log2 (uses Rec.2020 primaries)
    static let XYZ_to_FGamut = XYZ_to_Rec2020
    
    /// XYZ (D65) → Cinema Gamut (Canon)
    /// Source: Canon C-Log Technical Reference
    static let XYZ_to_CinemaGamut = ColorMatrix(
        r: CIVector(x:  1.5059159370, y: -0.2548349600, z: -0.1715045330, w: 0),
        g: CIVector(x: -0.4659192320, y:  1.3542697970, z:  0.0906014440, w: 0),
        b: CIVector(x: -0.0299206550, y:  0.0237817890, z:  0.9318181920, w: 0),
        a: CIVector(x: 0, y: 0, z: 0, w: 1)
    )
    
    /// XYZ (D65) → ARRI Wide Gamut 3
    /// Source: ARRI LogC specification
    static let XYZ_to_AWG3 = ColorMatrix(
        r: CIVector(x:  1.7890590000, y: -0.4825720000, z: -0.2006980000, w: 0),
        g: CIVector(x: -0.6398640000, y:  1.3963550000, z:  0.1943630000, w: 0),
        b: CIVector(x: -0.0415300000, y:  0.0822450000, z:  0.8788420000, w: 0),
        a: CIVector(x: 0, y: 0, z: 0, w: 1)
    )
    
    /// XYZ (D65) → ARRI Wide Gamut 4
    /// Source: ARRI LogC4 specification
    static let XYZ_to_AWG4 = ColorMatrix(
        r: CIVector(x:  1.8987220000, y: -0.5265110000, z: -0.2630360000, w: 0),
        g: CIVector(x: -0.7053000000, y:  1.5205200000, z:  0.1303120000, w: 0),
        b: CIVector(x: -0.0486690000, y:  0.1030730000, z:  0.8621000000, w: 0),
        a: CIVector(x: 0, y: 0, z: 0, w: 1)
    )
    
    /// XYZ (D65) → RED Wide Gamut RGB
    /// Source: RED IPP2 specification
    static let XYZ_to_REDWideGamut = ColorMatrix(
        r: CIVector(x:  1.4128290000, y: -0.1783960000, z: -0.1499340000, w: 0),
        g: CIVector(x: -0.4930950000, y:  1.3451830000, z:  0.1127100000, w: 0),
        b: CIVector(x: -0.0140950000, y:  0.0547230000, z:  0.8762560000, w: 0),
        a: CIVector(x: 0, y: 0, z: 0, w: 1)
    )
    
    /// XYZ (D65) → DaVinci Wide Gamut (DWG)
    /// Source: Blackmagic Design DaVinci Wide Gamut Specification
    /// Primaries: R(0.8000, 0.3130), G(0.1682, 0.9877), B(0.0790, -0.1155)
    static let XYZ_to_DaVinciWideGamut = ColorMatrix(
        r: CIVector(x:  1.5168982700, y: -0.2814611100, z: -0.1469458300, w: 0),
        g: CIVector(x: -0.6498311700, y:  1.4929222600, z:  0.1178976000, w: 0),
        b: CIVector(x:  0.0103477700, y: -0.0149178400, z:  0.9195942300, w: 0),
        a: CIVector(x: 0, y: 0, z: 0, w: 1)
    )
    
    // MARK: - Display P3 → Target Gamut Matrices
    // CIRAWFilter outputs linear RGB in Display P3 color space
    // These matrices convert from Display P3 (D65) to target video gamuts (D65)
    // Computed as: XYZ_to_TargetGamut × P3_to_XYZ
    
    /// Display P3 (Linear) → S-Gamut3 (Sony)
    /// S-Gamut3 is wider than P3, so this expands the color volume
    static let P3_to_SGamut3 = ColorMatrix(
        r: CIVector(x:  0.8874553442, y:  0.0831005722, z:  0.0294440836, w: 0),
        g: CIVector(x: -0.0873405188, y:  1.0331358912, z:  0.0542046276, w: 0),
        b: CIVector(x:  0.0045617610, y: -0.0065406080, z:  1.0019788470, w: 0),
        a: CIVector(x: 0, y: 0, z: 0, w: 1)
    )
    
    /// Display P3 (Linear) → V-Gamut (Panasonic)
    static let P3_to_VGamut = ColorMatrix(
        r: CIVector(x:  0.8755766389, y:  0.0954166651, z:  0.0290066960, w: 0),
        g: CIVector(x: -0.0999369413, y:  1.0616700251, z:  0.0382669162, w: 0),
        b: CIVector(x:  0.0000000000, y:  0.0000000000, z:  1.0000000000, w: 0),
        a: CIVector(x: 0, y: 0, z: 0, w: 1)
    )
    
    /// Display P3 (Linear) → Rec.2020/F-Gamut
    /// Rec.2020 is wider than P3, this is a gamut expansion
    static let P3_to_Rec2020 = ColorMatrix(
        r: CIVector(x:  0.7538987994, y:  0.1985279083, z:  0.0475732923, w: 0),
        g: CIVector(x:  0.0457191802, y:  0.9416464766, z:  0.0126343432, w: 0),
        b: CIVector(x: -0.0012107850, y:  0.0176017247, z:  0.9836090603, w: 0),
        a: CIVector(x: 0, y: 0, z: 0, w: 1)
    )
    
    /// Alias for F-Log2
    static let P3_to_FGamut = P3_to_Rec2020
    
    /// Display P3 (Linear) → S-Gamut3.Cine (Sony)
    /// S-Gamut3.Cine has slightly different primaries for cinema workflow
    static let P3_to_SGamut3Cine = ColorMatrix(
        r: CIVector(x:  0.8613538461, y:  0.1055430769, z:  0.0331030770, w: 0),
        g: CIVector(x: -0.0770553846, y:  1.0226400000, z:  0.0544153846, w: 0),
        b: CIVector(x:  0.0046769231, y: -0.0083384615, z:  1.0036615384, w: 0),
        a: CIVector(x: 0, y: 0, z: 0, w: 1)
    )
    
    /// Display P3 (Linear) → Cinema Gamut (Canon)
    /// Used for Canon Log 2 and Canon Log 3
    static let P3_to_CinemaGamut = ColorMatrix(
        r: CIVector(x:  0.8233000000, y:  0.1389000000, z:  0.0378000000, w: 0),
        g: CIVector(x: -0.0372000000, y:  0.9944000000, z:  0.0428000000, w: 0),
        b: CIVector(x:  0.0024000000, y: -0.0116000000, z:  1.0092000000, w: 0),
        a: CIVector(x: 0, y: 0, z: 0, w: 1)
    )
    
    /// Display P3 (Linear) → ARRI Wide Gamut 3 (AWG3)
    /// Used for ARRI LogC3
    static let P3_to_AWG3 = ColorMatrix(
        r: CIVector(x:  0.8054000000, y:  0.1497000000, z:  0.0449000000, w: 0),
        g: CIVector(x: -0.0354000000, y:  0.9819000000, z:  0.0535000000, w: 0),
        b: CIVector(x:  0.0036000000, y: -0.0142000000, z:  1.0106000000, w: 0),
        a: CIVector(x: 0, y: 0, z: 0, w: 1)
    )
    
    /// Display P3 (Linear) → ARRI Wide Gamut 4 (AWG4)
    /// Used for ARRI LogC4
    static let P3_to_AWG4 = ColorMatrix(
        r: CIVector(x:  0.7931000000, y:  0.1604000000, z:  0.0465000000, w: 0),
        g: CIVector(x: -0.0298000000, y:  0.9723000000, z:  0.0575000000, w: 0),
        b: CIVector(x:  0.0042000000, y: -0.0168000000, z:  1.0126000000, w: 0),
        a: CIVector(x: 0, y: 0, z: 0, w: 1)
    )
    
    /// Display P3 (Linear) → RED Wide Gamut RGB
    /// Used for Log3G10
    static let P3_to_REDWideGamut = ColorMatrix(
        r: CIVector(x:  0.7856000000, y:  0.1658000000, z:  0.0486000000, w: 0),
        g: CIVector(x: -0.0276000000, y:  0.9678000000, z:  0.0598000000, w: 0),
        b: CIVector(x:  0.0048000000, y: -0.0186000000, z:  1.0138000000, w: 0),
        a: CIVector(x: 0, y: 0, z: 0, w: 1)
    )
}

extension CIImage {
    func applyingColorMatrix(_ matrix: ColorMatrix) -> CIImage {
        return self.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": matrix.r,
            "inputGVector": matrix.g,
            "inputBVector": matrix.b,
            "inputAVector": matrix.a
        ])
    }
}
