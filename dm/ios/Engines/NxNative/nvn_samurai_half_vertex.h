/* The old renderer's vertex descriptors cannot connect Half2 data to an
 * integer register. Let Metal decode the attribute as float and give the
 * translated code the same register bits Maxwell would produce. */
static uint64_t legacy_samurai_half_attributes(const pso_key *k, NvShader *vs) {
    const char *enable = getenv("DM_TEST_SAMURAI_HALF_VERTEX");
    if (!enable || strcmp(enable, "1") || strcmp(vs->key, "d21bdc731c2ea7f1_b")) return 0;
    uint64_t mask = 0;
    for (int i = 0; i < vs->rf.nv; ++i) {
        int loc = vs->rf.v[i].loc, a = vs->rf.v[i].nvn, ct = vs->rf.v[i].ct;
        if (a >= 0 && a < 16 && loc >= 0 && loc < 32 && (ct == NVN_CT_UINT || ct == NVN_CT_INT) &&
            vfmt(k->attr[a].fmt) == MTLVertexFormatHalf2) mask |= 1ull << loc;
    }
    return mask;
}

static NSString *legacy_half_vertex_source(NSString *input, uint64_t mask) {
    NSString *source = input;
    for (int loc = 0; loc < 32; ++loc) {
        if (!(mask & (1ull << loc))) continue;
        NSString *pattern = [NSString stringWithFormat:@"\\b(u?int4)\\s+(m_[0-9]+)\\s*\\[\\[attribute\\(%d\\)\\]\\];",loc];
        NSRegularExpression *rx = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        NSArray<NSTextCheckingResult *> *matches = [rx matchesInString:source options:0 range:NSMakeRange(0,source.length)];
        if (matches.count != 1) return nil;
        NSTextCheckingResult *m = matches.firstObject;
        NSString *type = [source substringWithRange:[m rangeAtIndex:1]];
        NSString *name = [source substringWithRange:[m rangeAtIndex:2]];
        NSString *newname = [@"dm_half_" stringByAppendingString:name];
        NSString *decl = [NSString stringWithFormat:@"float4 %@ [[attribute(%d)]];",newname,loc];
        source = [source stringByReplacingCharactersInRange:m.range withString:decl];
        NSString *field = [@"in." stringByAppendingString:name];
        NSString *cast = [NSString stringWithFormat:@"(as_type<%@>(float4(in.%@.xy, 0.0f, 1.0f)))",type,newname];
        NSString *pattern2 = [NSString stringWithFormat:@"\\b%@\\b",[NSRegularExpression escapedPatternForString:field]];
        NSRegularExpression *ref = [NSRegularExpression regularExpressionWithPattern:pattern2 options:0 error:nil];
        NSRange full = NSMakeRange(0,source.length);
        if (![ref numberOfMatchesInString:source options:0 range:full]) return nil;
        source = [ref stringByReplacingMatchesInString:source options:0 range:full withTemplate:[NSRegularExpression escapedTemplateForString:cast]];
    }
    return [source stringByReplacingOccurrencesOfString:@"[[point_size]]" withString:@"[[user(dm_unused_point_size)]]"];
}
static char legacy_samurai_half_functions;
static id<MTLFunction> legacy_samurai_half_variant(NvShader *vs, uint64_t mask) {
    @synchronized (vs) {
        NSMutableDictionary *funcs = objc_getAssociatedObject(vs, &legacy_samurai_half_functions);
        NSNumber *key = @(mask);
        id prior = funcs[key];
        if (prior) return prior == NSNull.null ? nil : prior;
        NSString *stem = @(vs->key);
        NSDictionary *manifest = nonpoint_sources_manifest();
        NSDictionary *record = manifest[@"shaders"][stem];
        NSString *base = [g_msl_dir stringByAppendingPathComponent:@"nonpoint-v1"];
        NSData *src = [NSData dataWithContentsOfFile:[base stringByAppendingPathComponent:[stem stringByAppendingString:@".metal"]]];
        NSData *libdata = nvn_shader_data(g_msl_dir, [g_msl_dir stringByAppendingPathComponent:[stem stringByAppendingString:@".metallib"]]);
        NSError *err = nil;
        id<MTLFunction> fn = nil;
        if ([manifest[@"schema"] isEqual:@1] && [manifest[@"chain"] isEqual:@(TONTON_SHADER_CHAIN)] &&
            [record[@"source_sha256"] isEqual:nonpoint_digest(src)] && [record[@"library_sha256"] isEqual:nonpoint_digest(libdata)]) {
            src = guarded_index_source(stem, src, libdata, &err);
            NSString *text = src ? [[NSString alloc] initWithData:src encoding:NSUTF8StringEncoding] : nil;
            text = text ? legacy_half_vertex_source(text, mask) : nil;
            if (text) {
                MTLCompileOptions *opts = [MTLCompileOptions new];
                opts.languageVersion = MTLLanguageVersion3_0;
                opts.preserveInvariance = YES;
                opts.fastMathEnabled = NO;
                id<MTLLibrary> lib = [g_dev newLibraryWithSource:text options:opts error:&err];
                fn = vs->specialized ? [lib newFunctionWithName:vs->fn.name constantValues:[MTLFunctionConstantValues new] error:&err] :
                    [lib newFunctionWithName:vs->fn.name];
                if (fn && vs->rf.nb && [fn newArgumentEncoderWithBufferIndex:vs->rf.abi].encodedLength != vs->arg_len) fn = nil;
            }
        }
        if (!funcs) {
            funcs = [NSMutableDictionary dictionary];
            objc_setAssociatedObject(vs, &legacy_samurai_half_functions, funcs, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        funcs[key] = fn ? (id)fn : NSNull.null;
        if (fn) MLOG("classic Samurai Half2 register conversion: shader=%s attributes=%#llx",vs->key,(unsigned long long)mask);
        else MLOG("[RED] classic Samurai Half2 conversion not available: shader=%s mask=%#llx: %s",vs->key,(unsigned long long)mask,err.localizedDescription.UTF8String);
        return fn;
    }
}
