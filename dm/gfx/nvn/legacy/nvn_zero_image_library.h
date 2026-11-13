#pragma once
static id<MTLLibrary> zero_image_library(NSString *key, id<MTLLibrary> original, NSData *reflection,
        int *variant, int *image_aid, int *image_reg, int *image_format, NSError **error) {
    static NSDictionary *manifest;
    static NSDictionary *image_manifest;
    static dispatch_once_t once;
    NSString *directory = [g_msl_dir stringByAppendingPathComponent:@"zero-image-v1"];
    NSString *image_directory = [g_msl_dir stringByAppendingPathComponent:@"fragment-image-v1"];
    dispatch_once(&once, ^{
        NSData *data = [NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"manifest.json"]];
        manifest = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        data = [NSData dataWithContentsOfFile:[image_directory stringByAppendingPathComponent:@"manifest.json"]];
        image_manifest = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    });
    // A missing companion affects only fragment image writers on old GPUs.
    NSDictionary *record = manifest[@"shaders"][key];
    int image_variant = 0;
    if (!record) {
        record = image_manifest[@"shaders"][key];
        directory = image_directory;
        image_variant = 1;
    }
    NSString *reason = nil;
    NSDictionary *selected = image_variant ? image_manifest : manifest;
    NSString *kind = image_variant ? @"fragment-image-rg11b10-v1" : @"zero-image-clear-v1";
    NSString *proof = image_variant ? @"fragment-image-rg11b10-shadow-v1" : @"fragment-zero-writes-v1";
    if (![selected[@"schema"] isEqual:@1] || ![selected[@"chain"] isEqual:@DMSH_CHAIN] ||
        ![selected[@"kind"] isEqual:kind] || !record ||
        ![record[@"proof"] isEqual:proof] ||
        ![record[@"parameter_slot"] isEqual:@29] || ![record[@"image_aid"] isKindOfClass:NSNumber.class] ||
        ![record[@"image_reg"] isKindOfClass:NSNumber.class]) reason = @"Missing or unproven zero-image fragment companion";
    if (!reason && image_variant && ![record[@"pixel_format"] isEqual:@(MTLPixelFormatRG11B10Float)])
        reason = @"Fragment-image companion pixel format is not RG11B10Float";
    NSString *name = record[@"source"];
    if (!reason && (![name isKindOfClass:NSString.class] || ![name isEqual:name.lastPathComponent])) reason = @"Invalid zero-image source path";
    NSData *source = reason ? nil : [NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:name]];
    NSData *base = reason ? nil : [NSData dataWithContentsOfFile:[g_msl_dir stringByAppendingPathComponent:[key stringByAppendingString:@".metallib"]] options:NSDataReadingMappedIfSafe error:nil];
    if (!reason && (![record[@"source_sha256"] isEqual:nonpoint_digest(source)] ||
        ![record[@"base_library_sha256"] isEqual:nonpoint_digest(base)] ||
        ![record[@"reflection_sha256"] isEqual:nonpoint_digest(reflection)])) reason = @"Zero-image source, base library or reflection hash mismatch";
    if (reason) {
        if (error) *error = [NSError errorWithDomain:@"NVNZeroImage" code:1 userInfo:@{NSLocalizedDescriptionKey:reason}];
        return nil;
    }
    NSString *text = [[NSString alloc] initWithData:source encoding:NSUTF8StringEncoding];
    MTLCompileOptions *options = [MTLCompileOptions new]; options.languageVersion = MTLLanguageVersion3_0;
    options.preserveInvariance = YES; options.fastMathEnabled = NO;
    id<MTLLibrary> library = [g_dev newLibraryWithSource:text options:options error:error];
    if (library) {
        *variant = image_variant ? 2 : 1;
        *image_aid = [record[@"image_aid"] intValue]; *image_reg = [record[@"image_reg"] intValue];
        *image_format = image_variant ? [record[@"pixel_format"] intValue] : 0;
        if (image_variant) MLOG("Fragment-image %s: verified RG11B10 shadow proof, compatibility buffer 29", key.UTF8String);
        else MLOG("Zero-image fragment %s: verified zero-write proof, compatibility buffer 29", key.UTF8String);
    }
    return library;
}
