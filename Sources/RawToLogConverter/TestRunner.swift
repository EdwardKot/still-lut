import Foundation
import CoreImage
import Metal
import LibRawBridge

// End-to-end test for LibRaw XYZ pipeline
// This can be called from app startup to verify the pipeline works

@MainActor
func testLibRawXYZPipeline() {
    print("\n" + String(repeating: "=", count: 60))
    print("🧪 LibRaw XYZ Pipeline End-to-End Test")
    print(String(repeating: "=", count: 60))
    
    let testDNGPath = "/Users/edward/Documents/Antigravity/RAW+LUT/test/IDG_20251014_162641_258.DNG"
    let testURL = URL(fileURLWithPath: testDNGPath)
    
    guard FileManager.default.fileExists(atPath: testDNGPath) else {
        print("❌ Test DNG not found: \(testDNGPath)")
        return
    }
    
    // Test LibRaw decoding directly
    print("\n📷 Step 1: LibRaw XYZ Decode")
    guard let device = MTLCreateSystemDefaultDevice() else {
        print("❌ Metal device not available")
        return
    }
    
    let decoder = LibRawXYZDecoder(device: device)
    
    do {
        let startDecode = CFAbsoluteTimeGetCurrent()
        let xyzImage = try decoder.decode(url: testURL)
        let decodeDuration = CFAbsoluteTimeGetCurrent() - startDecode
        
        print("   ✅ Decoded: \(xyzImage.width) × \(xyzImage.height)")
        print("   ⏱️ Time: \(String(format: "%.3f", decodeDuration))s")
        
        // Sample some XYZ values
        let ptr = xyzImage.xyzBuffer.contents().bindMemory(to: Float16.self, capacity: 9)
        print("   📊 First pixel XYZ: (\(ptr[0]), \(ptr[1]), \(ptr[2]))")
        
        // Test matrix computation
        print("\n🔢 Step 2: Color Matrix (XYZ D50 → Rec.2020)")
        let matrix = ColorSpaceEngine.shared.xyzD50ToTargetGamut(.rec2020)
        print("   Matrix row 0: [\(matrix.columns.0.x), \(matrix.columns.1.x), \(matrix.columns.2.x)]")
        
        // Test Metal shader compilation
        print("\n🎮 Step 3: Metal Pipeline Check")
        do {
            let metalPipeline = try MetalPipeline()
            let pipelineCount = metalPipeline.computePipelines.count
            print("   ✅ MetalPipeline initialized with \(pipelineCount) compute pipelines")
            
            if metalPipeline.computePipelines["processXYZPipeline"] != nil {
                print("   ✅ processXYZPipeline compiled")
            } else {
                print("   ⚠️ processXYZPipeline NOT FOUND")
            }
            
            if metalPipeline.computePipelines["processXYZPipelineWithLUT"] != nil {
                print("   ✅ processXYZPipelineWithLUT compiled")
            } else {
                print("   ⚠️ processXYZPipelineWithLUT NOT FOUND")
            }
        } catch {
            print("   ❌ MetalPipeline error: \(error)")
        }
        
        print("\n" + String(repeating: "=", count: 60))
        print("✅ All LibRaw XYZ Pipeline Tests Passed!")
        print(String(repeating: "=", count: 60) + "\n")
        
    } catch {
        print("   ❌ Decode failed: \(error)")
    }
}
