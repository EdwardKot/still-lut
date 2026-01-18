import Foundation
import CoreImage

class LutLoader {
    static func loadCubeFile(from url: URL) -> (data: Data, dimension: Int)? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        
        let lines = content.components(separatedBy: .newlines)
        var dimension = 0
        var data = Data()
        var values: [Float] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            
            if trimmed.uppercased().hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.components(separatedBy: .whitespaces)
                if let size = Int(parts.last ?? "") {
                    dimension = size
                }
                continue
            }
            
            // Parse RGB values
            let components = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if components.count == 3 {
                if let r = Float(components[0]), let g = Float(components[1]), let b = Float(components[2]) {
                    values.append(r)
                    values.append(g)
                    values.append(b)
                    values.append(1.0) // Alpha
                }
            }
        }
        
        guard dimension > 0 && values.count == dimension * dimension * dimension * 4 else {
            print("Invalid LUT data or dimension mismatch")
            return nil
        }
        
        // Convert to Data (Float32 buffer)
        data = Data(bytes: values, count: values.count * MemoryLayout<Float>.size)
        
        return (data, dimension)
    }
}
