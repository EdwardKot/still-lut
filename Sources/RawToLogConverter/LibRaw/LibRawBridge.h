//
// LibRawBridge.h
// C interface for LibRaw decoding to XYZ color space
//

#ifndef LibRawBridge_h
#define LibRawBridge_h

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Result structure for LibRaw decoding
typedef struct {
  uint16_t *data;         // XYZ pixel data (interleaved RGB as XYZ)
  int width;              // Image width in pixels
  int height;             // Image height in pixels
  int stride;             // Bytes per row
  bool success;           // Decoding success flag
  char errorMessage[256]; // Error description if failed
  // DNG metadata for exposure
  float baselineExposure;   // DNG BaselineExposure tag (EV), 0 if not available
  bool hasBaselineExposure; // True if baselineExposure was read from DNG
  // Camera white balance (not baked into XYZ data)
  float wbMultipliers[3]; // Camera WB: R, G, B gains (normalized so G=1.0)
  float colorTemperature; // Estimated color temperature in Kelvin
} LibRawResult;

/// Decode RAW file to linear XYZ (D50 white point)
/// @param filePath Path to RAW file (.DNG, .ARW, .CR2, etc.)
/// @return Result structure with XYZ data or error
LibRawResult libraw_decode_to_xyz(const char *filePath);

/// Free memory allocated by libraw_decode_to_xyz
/// @param result Pointer to result structure
void libraw_free_result(LibRawResult *result);

#ifdef __cplusplus
}
#endif

#endif /* LibRawBridge_h */
