// Query the actual device before offering a MetalFX path. Capability alone is
// not an implementation: interpolation still needs matched color/depth/motion
// history and correct presentation pacing; temporal upscaling needs jitter.
#pragma once
#import <MetalFX/MetalFX.h>

static inline void dm_graphics_capabilities(id<MTLDevice> device) {
    int spatial = 0, temporal = 0, interpolation = 0, interpolation4 = 0;
    if (@available(iOS 16.0, *)) {
        spatial = [MTLFXSpatialScalerDescriptor supportsDevice:device];
        temporal = [MTLFXTemporalScalerDescriptor supportsDevice:device];
    }
    if (@available(iOS 26.0, *)) {
        interpolation = [MTLFXFrameInterpolatorDescriptor supportsDevice:device];
        interpolation4 = [MTLFXFrameInterpolatorDescriptor supportsMetal4FX:device];
    }
    LOG("graphics capabilities: device=%s MetalFX spatial=%d temporal=%d frame_interpolation=%d frame_interpolation_metal4=%d; interpolation integration pending",
        device.name.UTF8String, spatial, temporal, interpolation, interpolation4);
}
