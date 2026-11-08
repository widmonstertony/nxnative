// Vulkan descriptors outlive the objects written into them (GitHub issue 68): a set names an image view, a sampler and a uniform buffer in element 1 of an 8-texture
// array and a buffer binding, as Super Mario Galaxy 2's shaders take them; the objects are destroyed and their host structs freed and overwritten, and the set bound
// for a draw still binds the texture, sampler state and buffer it was written with. Resetting the pool releases them
#include "../vk/hle_vk.m"
int dm_guest_as_contains(uintptr_t address) { (void)address; return 0; }
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t *g_mod; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }
void dm_vi_layer_crop(int c[4]) { c[0] = c[1] = c[2] = c[3] = 0; }
int dm_opmode(void) { return 1; }
static int checks, fails;
#define CHECK(c, msg) do { checks++; if (!(c)) { fails++; fprintf(stderr, "FAIL: %s\n", msg); } } while (0)

static void check_argument_arrays(void) {
    NSError *error = nil;
    id<MTLLibrary> library = [g_dev newLibraryWithSource:
        @"#include <metal_stdlib>\n"
         "using namespace metal;\n"
         "struct Resources { array<texture2d<float>, 512> textures [[id(0)]]; array<sampler, 64> samplers [[id(512)]]; };\n"
         "vertex float4 vs(uint i [[vertex_id]]) { return float4(i == 1 ? 3 : -1, i == 2 ? 3 : -1, 0, 1); }\n"
         "fragment float4 fs(float4 p [[position]], constant Resources& r [[buffer(0)]]) {"
         "  return r.textures[511 - uint(p.x)].sample(r.samplers[63 - uint(p.y)], float2(-0.1, 0.5));"
         "}" options:nil error:&error];
    CHECK(library, "Tier 2 descriptor arrays compile");
    if (!library) { fprintf(stderr, "%s\n", error.localizedDescription.UTF8String); return; }
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = [library newFunctionWithName:@"vs"]; pd.fragmentFunction = [library newFunctionWithName:@"fs"];
    pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
    id<MTLRenderPipelineState> pso = [g_dev newRenderPipelineStateWithDescriptor:pd error:&error];
    CHECK(pso, "Tier 2 descriptor arrays have a graphics pipeline");
    if (!pso) return;

    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:2 height:1 mipmapped:NO];
    td.storageMode = MTLStorageModeShared; td.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> source = [g_dev newTextureWithDescriptor:td];
    const uint8_t pixels[] = {255, 0, 0, 255, 0, 0, 255, 255};
    [source replaceRegion:MTLRegionMake2D(0, 0, 2, 1) mipmapLevel:0 withBytes:pixels bytesPerRow:8];
    td.width = 1; td.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> target = [g_dev newTextureWithDescriptor:td];
    VkSamplerCreateInfo sampler_ci = {.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO, .addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE};
    VkSampler sampler;
    h_vkCreateSampler(&g_device, &sampler_ci, NULL, &sampler);

    struct VkDescriptorSetLayout_T layout = {.n = 2, .total = 576, .b = {
        {.binding = 3, .count = 512, .base = 0, .type = VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, .dyn = -1},
        {.binding = 4, .count = 64, .base = 512, .type = VK_DESCRIPTOR_TYPE_SAMPLER, .dyn = -1},
    }};
    layout.idx[3] = 0; layout.idx[4] = 1;
    struct VkDescriptorSet_T descriptors = {.L = &layout, .d = zalloc(layout.total * sizeof(desc_t))};
    descriptors.d[511].tex = source; descriptors.d[575].smp = sampler->s;
    shinfo si = {.key = "t_vk_arg", .frag = 1, .nres = 2, .arg_slot = {1}, .res = {
        {.kind = 't', .binding = 3, .slot = 0, .count = 512},
        {.kind = 's', .binding = 4, .slot = 512, .count = 64},
    }};
    struct VkPipeline_T pipe = {0};
    pipe.args[1][0] = [pd.fragmentFunction newArgumentEncoderWithBufferIndex:0];
    CHECK(pipe.args[1][0], "fragment argument encoder is available");
    MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor renderPassDescriptor];
    rpd.colorAttachments[0].texture = target;
    rpd.colorAttachments[0].loadAction = MTLLoadActionClear; rpd.colorAttachments[0].storeAction = MTLStoreActionStore;
    subq_t submit = {0};
    rs_t s = {.cb = [g_q commandBuffer], .pipe = &pipe, .sq = &submit};
    s.re = [s.cb renderCommandEncoderWithDescriptor:rpd]; s.set[0].s = &descriptors;
    [s.re setRenderPipelineState:pso];
    if (pipe.args[1][0] && bind_res(&s, &si, 1)) [s.re drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [s.re endEncoding]; [s.cb commit]; [s.cb waitUntilCompleted];
    CHECK(s.cb.status == MTLCommandBufferStatusCompleted, "draw using indirect descriptors completed");
    uint8_t result[4] = {0};
    [target getBytes:result bytesPerRow:4 fromRegion:MTLRegionMake2D(0, 0, 1, 1) mipmapLevel:0];
    CHECK(result[0] == 255 && result[2] == 0, "texture 511 used sampler 63's clamp at the left edge");
    descriptors.d[511].tex = nil; descriptors.d[575].smp = nil;
    free(descriptors.d); h_vkDestroySampler(&g_device, sampler, NULL);
}

static void check_compute_dispatch(void) {
    NSError *error = nil;
    id<MTLLibrary> library = [g_dev newLibraryWithSource:
        @"#include <metal_stdlib>\n"
         "using namespace metal;\n"
         "kernel void fill(device uint *out [[buffer(0)]], constant uint& base [[buffer(1)]], uint i [[thread_position_in_grid]]) { out[i] = base + i; }"
         options:nil error:&error];
    CHECK(library, "compute test shader compiles");
    if (!library) return;
    shinfo shader = {.key = "t_vk_comp", .nres = 2, .local = {2, 1, 1}, .res = {
        {.kind = 'b', .binding = 3, .count = 1},
        {.kind = 'p', .slot = 1, .count = 1},
    }};
    struct VkShaderModule_T module = {.fn = [library newFunctionWithName:@"fill"], .si = &shader};
    struct VkPipelineLayout_T pipeline_layout = {.pc_size = 4};
    VkComputePipelineCreateInfo ci = {.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .layout = &pipeline_layout, .stage = {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = &module, .pName = "fill"}};
    VkPipeline pipeline = NULL;
    CHECK(h_vkCreateComputePipelines(&g_device, NULL, 1, &ci, NULL, &pipeline) == VK_SUCCESS && pipeline, "compute pipeline created");
    if (!pipeline) return;
    id<MTLBuffer> output = [g_dev newBufferWithLength:4 * sizeof(uint32_t) options:MTLResourceStorageModeShared];
    struct VkDescriptorSetLayout_T layout = {.n = 1, .total = 1, .b = {{.binding = 3, .count = 1, .dyn = -1}}};
    layout.idx[3] = 0;
    desc_t storage = {.buf = output};
    struct VkDescriptorSet_T descriptor = {.L = &layout, .d = &storage};
    VkDescriptorSet set = &descriptor;
    struct VkCommandBuffer_T commands = {0};
    h_vkCmdBindPipeline(&commands, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    h_vkCmdBindDescriptorSets(&commands, VK_PIPELINE_BIND_POINT_COMPUTE, &pipeline_layout, 0, 1, &set, 0, NULL);
    uint32_t base = 17;
    h_vkCmdPushConstants(&commands, &pipeline_layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof base, &base);
    h_vkCmdDispatch(&commands, 2, 1, 1);
    rs_t s = {.cb = [g_q commandBuffer]};
    replay(&s, &commands); [s.cb commit]; [s.cb waitUntilCompleted];
    CHECK(s.cb.status == MTLCommandBufferStatusCompleted, "recorded compute dispatch completed");
    const uint32_t *result = output.contents;
    CHECK(result[0] == 17 && result[1] == 18 && result[2] == 19 && result[3] == 20,
          "two workgroups receive their storage buffer and pushed value");
    h_vkDestroyPipeline(&g_device, pipeline, NULL);
    free(commands.buf);
}

static void check_viewport_forwarding(void) {
    NSError *error = nil;
    id<MTLLibrary> library = [g_dev newLibraryWithSource:
        @"#include <metal_stdlib>\n"
         "using namespace metal;\n"
         "struct Out { float4 pos [[position]]; uint viewport [[viewport_array_index]]; };\n"
         "vertex Out vs(uint i [[vertex_id]], uint instance [[instance_id]]) {"
         "  return {float4(i == 1 ? 3 : -1, i == 2 ? 3 : -1, 0, 1), instance};"
         "}\n"
         "fragment float4 fs(Out p [[stage_in]]) {"
         "  return float4(p.viewport == 0, p.viewport == 1, p.viewport == 2, 1);"
         "}" options:nil error:&error];
    CHECK(library, "viewport forwarding shader compiles");
    if (!library) return;
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = [library newFunctionWithName:@"vs"]; pd.fragmentFunction = [library newFunctionWithName:@"fs"];
    pd.inputPrimitiveTopology = MTLPrimitiveTopologyClassTriangle;
    pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
    struct VkPipeline_T pipeline = {.viewport_index = 1, .prim = MTLPrimitiveTypeTriangle};
    pipeline.pso = [g_dev newRenderPipelineStateWithDescriptor:pd error:&error];
    CHECK(pipeline.pso, "viewport forwarding graphics pipeline is available");
    if (!pipeline.pso) return;

    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:3 height:1 mipmapped:NO];
    td.storageMode = MTLStorageModeShared; td.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> target = [g_dev newTextureWithDescriptor:td];
    MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor renderPassDescriptor];
    rpd.colorAttachments[0].texture = target;
    rpd.colorAttachments[0].loadAction = MTLLoadActionClear; rpd.colorAttachments[0].storeAction = MTLStoreActionUnknown;
    const VkViewport views[] = {{0, 0, 1, 1, 0, 1}, {1, 0, 1, 1, 0, 1}, {2, 0, 1, 1, 0, 1}};
    const VkRect2D scissor = {{0, 0}, {3, 1}};
    struct VkCommandBuffer_T commands = {0};
    h_vkCmdBindPipeline(&commands, VK_PIPELINE_BIND_POINT_GRAPHICS, &pipeline);
    h_vkCmdSetViewport(&commands, 0, 3, views);
    h_vkCmdSetScissor(&commands, 0, 1, &scissor);
    h_vkCmdDraw(&commands, 3, 3, 0, 0);
    h_vkCmdEndRenderPass(&commands);
    rs_t s = {.cb = [g_q commandBuffer], .rpd = rpd, .rt_w = 3, .rt_h = 1, .st_col = {MTLStoreActionStore}};
    s.re = [s.cb renderCommandEncoderWithDescriptor:rpd];
    replay(&s, &commands); [s.cb commit]; [s.cb waitUntilCompleted];
    CHECK(s.cb.status == MTLCommandBufferStatusCompleted, "three-view draw completed");
    uint8_t result[12] = {0};
    const uint8_t expected[] = {255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255};
    [target getBytes:result bytesPerRow:12 fromRegion:MTLRegionMake2D(0, 0, 3, 1) mipmapLevel:0];
    CHECK(!memcmp(result, expected, sizeof expected), "each viewport received its own instance");
    free(commands.buf);
}

static void check_blended_attachment_load(void) {
    NSError *error = nil;
    id<MTLLibrary> library = [g_dev newLibraryWithSource:
        @"#include <metal_stdlib>\n"
         "using namespace metal;\n"
         "vertex float4 vs(uint i [[vertex_id]]) { return float4(i == 1 ? 3 : -1, i == 2 ? 3 : -1, 0, 1); }\n"
         "fragment float4 fs() { return float4(0, 0, 1, 0); }" options:nil error:&error];
    CHECK(library, "the transparent overlay shader compiles");
    if (!library) return;
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = [library newFunctionWithName:@"vs"];
    pd.fragmentFunction = [library newFunctionWithName:@"fs"];
    pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
    pd.colorAttachments[0].blendingEnabled = YES;
    pd.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pd.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pd.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorZero;
    pd.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOne;
    struct VkPipeline_T pipeline = {.blend_mask = 1, .prim = MTLPrimitiveTypeTriangle};
    pipeline.pso = [g_dev newRenderPipelineStateWithDescriptor:pd error:&error];
    CHECK(pipeline.pso, "the transparent overlay pipeline is available");
    if (!pipeline.pso) return;

    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];
    td.storageMode = MTLStorageModeShared; td.usage = MTLTextureUsageRenderTarget;
    struct VkImageView_T view = {.tex = [g_dev newTextureWithDescriptor:td]};
    struct VkFramebuffer_T fb = {.n = 1, .w = 4, .h = 4, .layers = 1, .v = {&view}};
    struct VkRenderPass_T scene = {.natt = 1, .ncol = 1, .col = {0}, .res = {-1}, .depth = -1,
        .att = {{.fmt = VK_FORMAT_R8G8B8A8_UNORM, .load = VK_ATTACHMENT_LOAD_OP_CLEAR, .store = VK_ATTACHMENT_STORE_OP_STORE}}};
    struct VkRenderPass_T overlay = scene;
    overlay.att[0].load = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    const VkClearValue red = {.color.float32 = {1, 0, 0, 1}};
    VkRenderPassBeginInfo begin = {.renderPass = &scene, .framebuffer = &fb, .renderArea = {{0, 0}, {4, 4}},
        .clearValueCount = 1, .pClearValues = &red};
    struct VkCommandBuffer_T commands = {0};
    h_vkCmdBeginRenderPass(&commands, &begin, VK_SUBPASS_CONTENTS_INLINE);
    h_vkCmdEndRenderPass(&commands);
    begin.renderPass = &overlay; begin.clearValueCount = 0;
    h_vkCmdBeginRenderPass(&commands, &begin, VK_SUBPASS_CONTENTS_INLINE);
    h_vkCmdBindPipeline(&commands, VK_PIPELINE_BIND_POINT_GRAPHICS, &pipeline);
    h_vkCmdDraw(&commands, 3, 1, 0, 0);
    h_vkCmdEndRenderPass(&commands);
    subq_t submit = {0};
    rs_t replay_state = {.cb = [g_q commandBuffer], .sq = &submit};
    replay(&replay_state, &commands);
    [replay_state.cb commit]; [replay_state.cb waitUntilCompleted];
    CHECK(replay_state.cb.status == MTLCommandBufferStatusCompleted, "the paired render passes completed");
    uint8_t pixel[4] = {0};
    const uint8_t expected[] = {255, 0, 0, 255};
    [view.tex getBytes:pixel bytesPerRow:4 fromRegion:MTLRegionMake2D(2, 2, 1, 1) mipmapLevel:0];
    CHECK(!memcmp(pixel, expected, sizeof expected), "the transparent pass blends over the previous stored red pixel");
    free(commands.buf);
}

int main(void) {
    __weak id<MTLTexture> wtex; __weak id<MTLSamplerState> wsmp; __weak id<MTLBuffer> wbuf;
    VkDevice dev = &g_device; VkDescriptorPool pool; VkDescriptorSet ds; VkDescriptorSetLayout L;
    @autoreleasepool {
        dev_init();
        VkImageCreateInfo ici = {.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, .imageType = VK_IMAGE_TYPE_2D, .format = VK_FORMAT_R8G8B8A8_UNORM, .extent = {4, 4, 1},
                                 .mipLevels = 1, .arrayLayers = 1, .samples = VK_SAMPLE_COUNT_1_BIT, .tiling = VK_IMAGE_TILING_OPTIMAL, .usage = VK_IMAGE_USAGE_SAMPLED_BIT};
        VkImage im; CHECK(h_vkCreateImage(dev, &ici, NULL, &im) == VK_SUCCESS, "image created");
        VkImageViewCreateInfo vci = {.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, .image = im, .viewType = VK_IMAGE_VIEW_TYPE_2D, .format = VK_FORMAT_R8G8B8A8_UNORM,
                                     .components = {VK_COMPONENT_SWIZZLE_B, VK_COMPONENT_SWIZZLE_G, VK_COMPONENT_SWIZZLE_R, VK_COMPONENT_SWIZZLE_A},   // a view texture of its own, not the image's
                                     .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}};
        VkImageView view; CHECK(h_vkCreateImageView(dev, &vci, NULL, &view) == VK_SUCCESS && view->tex && view->tex != im->tex, "swizzled view has its own texture");
        VkSamplerCreateInfo sci = {.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO, .magFilter = VK_FILTER_LINEAR, .minFilter = VK_FILTER_LINEAR};
        VkSampler smp; CHECK(h_vkCreateSampler(dev, &sci, NULL, &smp) == VK_SUCCESS && smp->s, "sampler created");
        VkBufferCreateInfo bci = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = 256, .usage = VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT};
        VkBuffer buf; h_vkCreateBuffer(dev, &bci, NULL, &buf);
        VkMemoryAllocateInfo mai = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = 4096, .memoryTypeIndex = 1};
        VkDeviceMemory mem; h_vkAllocateMemory(dev, &mai, NULL, &mem);
        CHECK(h_vkBindBufferMemory(dev, buf, mem, 512) == VK_SUCCESS, "buffer bound");
        wtex = view->tex; wsmp = smp->s; wbuf = mem->buf;

        VkDescriptorSetLayoutBinding lb[2] = {{0, VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 8, VK_SHADER_STAGE_FRAGMENT_BIT, NULL},
                                              {1, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1, VK_SHADER_STAGE_FRAGMENT_BIT, NULL}};
        VkDescriptorSetLayoutCreateInfo lci = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = 2, .pBindings = lb};
        h_vkCreateDescriptorSetLayout(dev, &lci, NULL, &L);
        VkDescriptorPoolCreateInfo pci = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .maxSets = 1};
        h_vkCreateDescriptorPool(dev, &pci, NULL, &pool);
        VkDescriptorSetAllocateInfo ai = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, .descriptorPool = pool, .descriptorSetCount = 1, .pSetLayouts = &L};
        h_vkAllocateDescriptorSets(dev, &ai, &ds);
        VkDescriptorImageInfo ii = {smp, view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
        VkDescriptorBufferInfo bi = {buf, 64, 128};
        VkWriteDescriptorSet w[2] = {{.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = 0, .dstArrayElement = 1, .descriptorCount = 1,
                                      .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .pImageInfo = &ii},
                                     {.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = 1, .descriptorCount = 1,
                                      .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .pBufferInfo = &bi}};
        h_vkUpdateDescriptorSets(dev, 2, w, 0, NULL);

        // The game destroys everything the set names, then the freed host structs are reused (the allocator's free-list word, then other objects' data)
        h_vkDestroyImageView(dev, view, NULL); h_vkDestroyImage(dev, im, NULL); h_vkDestroySampler(dev, smp, NULL); h_vkDestroyBuffer(dev, buf, NULL); h_vkFreeMemory(dev, mem, NULL);
        void *junk[4096];
        for (int i = 0; i < 4096; i++) { size_t n = 8 + 8 * (i % 8); junk[i] = malloc(n); memset(junk[i], 0xa5, n); }
        CHECK(wtex && wsmp && wbuf, "the descriptors keep the texture, sampler state and buffer alive");
        const desc_t *e = &ds->d[L->b[L->idx[0]].base + 1], *u = &ds->d[L->b[L->idx[1]].base];
        CHECK(e->tex == wtex && e->smp == wsmp, "element 1 holds the view's texture and the sampler state");
        CHECK(u->buf == wbuf && u->off == 512 + 64, "the buffer descriptor holds the memory's buffer at the buffer's offset plus its own");

        // A fragment shader taking c:0.0=0*8 and u:0.1=0, bound for a draw as pre_draw does
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:4 height:4 mipmapped:NO];
        td.usage = MTLTextureUsageRenderTarget; td.storageMode = MTLStorageModePrivate;
        MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor renderPassDescriptor];
        rpd.colorAttachments[0].texture = [g_dev newTextureWithDescriptor:td]; rpd.colorAttachments[0].loadAction = MTLLoadActionClear;
        shinfo si = {.key = "t_vk_desc", .frag = 1, .nres = 2, .res = {
            {.kind = 'c', .binding = 0, .count = 8}, {.kind = 'u', .binding = 1, .count = 1},
        }};
        rs_t s = {0}; s.cb = [g_q commandBuffer]; s.re = [s.cb renderCommandEncoderWithDescriptor:rpd]; s.set[0].s = ds;
        bind_res(&s, &si, 1);
        [s.re endEncoding]; s.re = nil; [s.cb commit]; [s.cb waitUntilCompleted];
        CHECK(s.cb.status == MTLCommandBufferStatusCompleted, "the bound pass completed");
        s.cb = nil;
        for (int i = 0; i < 4096; i++) free(junk[i]);
    }
    @autoreleasepool { h_vkResetDescriptorPool(dev, pool, 0); }
    CHECK(!wtex && !wsmp && !wbuf, "resetting the pool releases what its sets held");
    @autoreleasepool { check_argument_arrays(); }
    @autoreleasepool { check_compute_dispatch(); }
    @autoreleasepool { check_viewport_forwarding(); }
    @autoreleasepool { check_blended_attachment_load(); }
    // A stencil-aspect view of a depth-stencil image without the mutable-format flag (PR #106): an X32_Stencil8 view, which Metal's validation allows only with the format-view usage
    @autoreleasepool {
        VkFormat dsf[2] = {VK_FORMAT_D24_UNORM_S8_UINT, VK_FORMAT_D32_SFLOAT_S8_UINT};
        for (int i = 0; i < 2; i++) {
            VkImageCreateInfo ici = {.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, .imageType = VK_IMAGE_TYPE_2D, .format = dsf[i], .extent = {4, 4, 1}, .mipLevels = 1, .arrayLayers = 1,
                                     .samples = VK_SAMPLE_COUNT_1_BIT, .tiling = VK_IMAGE_TILING_OPTIMAL, .usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT};
            VkImage im; CHECK(h_vkCreateImage(dev, &ici, NULL, &im) == VK_SUCCESS && (im->tex.usage & MTLTextureUsagePixelFormatView), "a depth-stencil image has the format-view usage");
            VkImageViewCreateInfo vci = {.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, .image = im, .viewType = VK_IMAGE_VIEW_TYPE_2D, .format = dsf[i],
                                         .subresourceRange = {VK_IMAGE_ASPECT_STENCIL_BIT, 0, 1, 0, 1}};
            VkImageView sv; CHECK(h_vkCreateImageView(dev, &vci, NULL, &sv) == VK_SUCCESS && sv->tex.pixelFormat == MTLPixelFormatX32_Stencil8 && sv->tex.parentTexture == im->tex, "its stencil-aspect view is a stencil-only view of it");
            h_vkDestroyImageView(dev, sv, NULL); h_vkDestroyImage(dev, im, NULL);
        }
    }
    printf("Vulkan descriptors: %d checks, %d failed\n", checks, fails);
    return fails != 0;
}
