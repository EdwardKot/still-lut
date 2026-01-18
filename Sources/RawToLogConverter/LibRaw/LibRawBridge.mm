//
// LibRawBridge.mm
// Objective-C++ implementation for LibRaw decoding
//

#import "LibRawBridge.h"
#import <libraw/libraw.h>
#import <stdlib.h>
#import <string.h>

LibRawResult libraw_decode_to_xyz(const char *filePath) {
  LibRawResult result = {0};
  result.data = NULL;
  result.success = false;

  LibRaw processor;

  // Open RAW file
  int ret = processor.open_file(filePath);
  if (ret != LIBRAW_SUCCESS) {
    snprintf(result.errorMessage, sizeof(result.errorMessage),
             "Failed to open file: %s", libraw_strerror(ret));
    return result;
  }

  // Configure output parameters for XYZ color space
  processor.imgdata.params.output_color = 5; // XYZ color space
  processor.imgdata.params.gamm[0] = 1.0;    // Linear gamma (no curve)
  processor.imgdata.params.gamm[1] = 1.0;
  processor.imgdata.params.no_auto_bright = 1; // No auto brightness
  processor.imgdata.params.output_bps = 16;    // 16-bit output
  processor.imgdata.params.use_camera_wb =
      1; // Apply camera WB during decode (Bayer RGB space)
  processor.imgdata.params.use_auto_wb = 0; // No auto WB
  processor.imgdata.params.half_size = 0;   // Full resolution
  processor.imgdata.params.user_qual = 3;   // AHD demosaic (high quality)

  // Highlight recovery mode (prevents blown highlights)
  // 0 = Clip (default - hard clipping to white, can cause magenta/cyan
  // fringing) 1 = Unclip (use raw sensor values - may produce color shifts) 2 =
  // Blend (recommended - intelligently mix clipped pixels with valid data) 3-9
  // = Reconstruct (progressively aggressive: 3=conservative, 9=most aggressive)
  processor.imgdata.params.highlight =
      2; // Blend mode - best quality/speed balance

  // Unpack RAW data
  ret = processor.unpack();
  if (ret != LIBRAW_SUCCESS) {
    snprintf(result.errorMessage, sizeof(result.errorMessage),
             "Failed to unpack: %s", libraw_strerror(ret));
    return result;
  }

  // Process RAW data
  ret = processor.dcraw_process();
  if (ret != LIBRAW_SUCCESS) {
    snprintf(result.errorMessage, sizeof(result.errorMessage),
             "Failed to process: %s", libraw_strerror(ret));
    return result;
  }

  // Get processed image in memory
  int errorCode = 0;
  libraw_processed_image_t *image = processor.dcraw_make_mem_image(&errorCode);
  if (!image || errorCode != LIBRAW_SUCCESS) {
    snprintf(result.errorMessage, sizeof(result.errorMessage),
             "Failed to create memory image: %s",
             errorCode ? libraw_strerror(errorCode) : "null image");
    return result;
  }

  // Validate output format
  if (image->colors != 3 || image->bits != 16) {
    snprintf(result.errorMessage, sizeof(result.errorMessage),
             "Unexpected format: colors=%d, bits=%d", image->colors,
             image->bits);
    LibRaw::dcraw_clear_mem(image);
    return result;
  }

  // Allocate and copy data (caller owns this memory)
  size_t dataSize = (size_t)image->width * image->height * 3 * sizeof(uint16_t);
  result.data = (uint16_t *)malloc(dataSize);
  if (!result.data) {
    snprintf(result.errorMessage, sizeof(result.errorMessage),
             "Memory allocation failed");
    LibRaw::dcraw_clear_mem(image);
    return result;
  }

  memcpy(result.data, image->data, dataSize);
  result.width = image->width;
  result.height = image->height;
  result.stride = image->width * 3 * sizeof(uint16_t);
  result.success = true;

  // Extract DNG BaselineExposure if available
  // LibRaw stores this at imgdata.color.dng_levels.baseline_exposure
  float baselineExp = processor.imgdata.color.dng_levels.baseline_exposure;
  if (baselineExp != 0.0f || processor.imgdata.idata.dng_version != 0) {
    // DNG file with baseline exposure info
    result.baselineExposure = baselineExp;
    result.hasBaselineExposure = true;
  } else {
    result.baselineExposure = 0.0f;
    result.hasBaselineExposure = false;
  }

  // Extract camera white balance multipliers
  // LibRaw stores these in cam_mul[] - normalize so G=1.0
  float *cam_mul = processor.imgdata.color.cam_mul;
  float g_norm =
      cam_mul[1] > 0 ? cam_mul[1] : 1.0f;        // Green channel as reference
  result.wbMultipliers[0] = cam_mul[0] / g_norm; // R gain
  result.wbMultipliers[1] = 1.0f;                // G gain (normalized)
  result.wbMultipliers[2] = cam_mul[2] / g_norm; // B gain

  // Estimate color temperature from WB multipliers (rough approximation)
  // Higher R/B ratio = warmer (higher Kelvin when compensating)
  float rb_ratio = result.wbMultipliers[0] / result.wbMultipliers[2];
  // Empirical formula: ~6500K is neutral, adjust based on R/B ratio
  result.colorTemperature = 6500.0f / rb_ratio;

  // Cleanup
  LibRaw::dcraw_clear_mem(image);

  return result;
}

void libraw_free_result(LibRawResult *result) {
  if (result && result->data) {
    free(result->data);
    result->data = NULL;
  }
}
