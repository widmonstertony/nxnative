#pragma once
#import <Metal/Metal.h>
// Opt-in image-based interpolation, independent of MetalFX's depth/MV API.
// Caller serializes one queue and fences each of its three parameter slots.
@interface DmFrameGenerator : NSObject
@property(nonatomic, readonly) id<MTLResidencySet> residency;
@property(nonatomic, readonly) id<MTLTexture> currentTexture;
@property(nonatomic, readonly) NSUInteger width, height;
- (instancetype)initWithDevice:(id<MTLDevice>)device width:(NSUInteger)width height:(NSUInteger)height format:(MTLPixelFormat)format;
- (void)resetHistory;
// Copies the valid crop into owned history on every call. Returns a generated
// midpoint, or nil on first/reset/late frames. Real image: currentTexture.
- (id<MTLTexture>)encode:(id<MTL4CommandBuffer>)cb source:(id<MTLTexture>)source rect:(const NSUInteger[4])rect interval:(double)seconds slot:(int)slot;
@end
