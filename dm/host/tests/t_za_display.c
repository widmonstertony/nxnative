// Exercise the real module guards, read-only protection guard and mutable HUD
// callback against an anonymous guest mapping, without game assets or a GPU.
#include <assert.h>
#include <math.h>
#include "../hle_za_display.c"
static module_t modules[1];
module_t *g_mod = modules;
int g_nmod;
static void (*hud_callback)(uint64_t *, int);
void gate_obs_set(int id, void (*fn)(uint64_t *, int)) {
    assert(id == OBS_ZA_HUD_RECT); hud_callback = fn;
}
int gate_obs_present(int id) { return id == OBS_ZA_HUD_RECT; }
int main(int argc, char **argv) {
    const char *ratio = argc > 1 ? argv[1] : "76:35";
    double width, height;
    assert(sscanf(ratio, "%lf:%lf", &width, &height) == 2 && height > 0);
    float r[4];
    assert(!za_display_rect(NAN, r)); assert(!za_display_rect(0, r));
    assert(za_display_rect(16.0 / 9, r)); assert(fabs(r[0]) < .001 && r[2] == 1920);
    assert(za_display_rect(76.0 / 35, r));
    assert(fabs(r[0] - 174.0350877) < .001);
    assert(fabs(r[2] - 1571.9298246) < .001);
    assert(fabs((r[2] / 1920) * (76.0 / 35) - 16.0 / 9) < 1e-6);
    vm_address_t addr = 0; vm_size_t len = 0x31a0000;
    assert(vm_allocate(mach_task_self(), &addr, len, VM_FLAGS_ANYWHERE) == KERN_SUCCESS);
    g_nmod = 1; module_t *m = &g_mod[0];
    strcpy(m->name, "main"); strcpy(m->build_id, "b1f12fd919eae86ab8a978317677e64b");
    m->base = (uint8_t *)addr; m->size = len;
    m->text_end = 0x3163f70; m->ro_off = 0x3164000; m->data_off = 0x3bc2000;
    uint32_t *p = (uint32_t *)(addr + 0x319fc7c); *p = 0x3fe38e39;
    setenv("DM_ZA_FULLSCREEN", "1", 1); setenv("DM_ZA_ASPECT", ratio, 1);
    m->build_id[0] = '0'; dm_za_display_init();
    assert(!dm_za_fullscreen_active() && *p == 0x3fe38e39);
    m->build_id[0] = 'b'; *p = 0; dm_za_display_init();
    assert(!dm_za_fullscreen_active() && *p == 0);
    *p = 0x3fe38e39;
    assert(vm_protect(mach_task_self(), addr, len, 0, VM_PROT_READ) == KERN_SUCCESS);
    dm_za_display_init(); assert(!dm_za_fullscreen_active());
    assert(vm_protect(mach_task_self(), addr, len, 0, VM_PROT_READ | VM_PROT_WRITE) == KERN_SUCCESS);
    dm_za_display_init(); assert(dm_za_fullscreen_active());
    float aspect; memcpy(&aspect, p, sizeof aspect); assert(fabs(aspect - width / height) < 1e-6);
    uint64_t regs[31], saved[31];
    for (int i = 0; i < 31; i++) regs[i] = saved[i] = 0x123000 + i;
    struct { uint32_t unused; float rect[4]; } native = {0, {0, 0, 1920, 1080}};
    regs[9] = saved[9] = (uint64_t)(uintptr_t)&native;
    hud_callback(regs, 0);
    for (int i = 0; i < 31; i++) if (i != 9) assert(regs[i] == saved[i]);
    memcpy(r, (char *)(uintptr_t)regs[9] + 4, sizeof r);
    assert(fabs((r[2] / 1920) * width / height - 16.0 / 9) < 1e-6);
    assert(fabs(r[0] - (1920 - r[2]) * .5) < .001 && r[1] == 0 && r[3] == 1080);
    native.rect[2] = 1280; native.rect[3] = 720;
    regs[9] = saved[9]; hud_callback(regs, 0);
    memcpy(r, (char *)(uintptr_t)regs[9] + 4, sizeof r);
    assert(fabs((r[2] / 1280) * width / height - 16.0 / 9) < 1e-6 && r[3] == 720);
    native.rect[2] = 500; native.rect[3] = 300;
    regs[9] = saved[9]; hud_callback(regs, 0);
    assert(regs[9] == saved[9] && native.rect[2] == 500 && native.rect[3] == 300);
    assert(vm_deallocate(mach_task_self(), addr, len) == KERN_SUCCESS);
    printf("PASS: %s camera/HUD geometry, build/byte/protection guards and saved-x9 callback\n", ratio);
}
