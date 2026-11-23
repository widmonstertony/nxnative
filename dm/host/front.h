// Host front end (Mac: front_mac.m; iOS: dm/ios separately implements the same-named interface).
#pragma once
#include <stdlib.h>
// Metal reads HUD switches when the first device is made. Called before host preload and again after the launcher applies its settings; explicit environment values win.
static inline void front_hud_env(void) {
    const char *e = getenv("DM_METAL_HUD");
    if (!e || !atoi(e)) return;
    setenv("MTL_HUD_ENABLED", "1", 0);
    // Spatial scaling has no temporal exposure: showing that HUD metric makes the MetalFX rows flicker.
    setenv("MTL_HUD_HIDE_METALFX_METRICS", "1", 0);
}
// Run the guest: with a window the guest runs on its own thread and the main thread belongs to the system UI; without a window it runs directly on the current thread.
void front_run(void (*guest)(void));
// The CAMetalLayer the graphics backend presents frames to (NULL when there is no window)
void *front_metal_layer(void);
// HDR present (Mac front_mac.m, DM_HDR_PRESENT=1 with a window; off by default, and nothing changes when off): the layer is RGBA16Float with extended dynamic range (EDR), in
// the colorspace DM_HDR_PRESENT_KIND names: pq (the default) BT.2100 PQ for a 10-bit HDR10 picture, scrgb extended linear sRGB for an FP16 scRGB picture. nvn_mtl.m present_now
// draws the game's picture into it (passed through when it is in that encoding, converted when it is not, an SDR picture included). 0 = off (no window, iOS, unit tests:
// nvn_mtl.m's weak default), FRONT_HDR_PQ, FRONT_HDR_SCRGB. Any thread, after the window is up
enum { FRONT_HDR_OFF = 0, FRONT_HDR_PQ = 1, FRONT_HDR_SCRGB = 2 };
int front_hdr_present(void);
// Paper white in nits (DM_HDR_PAPER_WHITE, default 203, the BT.2408 reference vi::QueryDisplayHdrPaperWhite reports): the level an SDR or scRGB 1.0 picture is put at in PQ, and
// the PQ level that macOS shows at SDR white (the HDR10 metadata's optical output scale). Any thread
float front_hdr_paper_white(void);
// The HDR10 metadata of the PQ layer (CAEDRMetadata): the content's largest luminance in nits, e.g. from the game's vi::SetLayerNextHdrExtendedContentLuminanceRangeMetadata.
// DM_HDR_MAX_NITS sets the first value (default 1000; 0 = no metadata, macOS's default tone mapping) and, when set, wins over later calls. Only a change is applied. Any thread
void front_hdr_content_max_nits(float nits);
// The game's content gamut (vi::SetLayerNextHdrContentGamutMetadata; hle_vi.c forwards it while it answers HDR on): the gamut of the content inside the PQ signal, which is
// BT.2020 either way: 0 BT.709 (Ocarina of Time), 1 Display P3 (Mario Kart World); agl's PQ pass applies the matching matrix to BT.2020 before encoding. -1 = none sent, or
// cleared. Noted (logged) on each change; the present does not need it. Any thread
void front_hdr_content_gamut(int gamut);
// 1 only with DM_HDR_GAMUT=709, a diagnostic: the present then takes the PQ picture as BT.709 and converts it to BT.2020 (present.metal fs_hdr). 0 otherwise (auto, the
// default, and 2020): the PQ picture is BT.2020 and copied as it is, whatever the content gamut. Any thread
int front_hdr_primaries_709(void);
// The window's screen's extended dynamic range, as NSScreen reports it (kept up to date on screen and brightness changes): potential = the most the display can ever show
// (maximumPotentialExtendedDynamicRangeColorComponentValue), current = the most it shows now (maximumExtendedDynamicRangeColorComponentValue; it moves with brightness and
// only rises above 1 while an EDR layer is on screen), reference = the reference preset's (maximumReferenceExtendedDynamicRangeColorComponentValue, 0 = not a reference
// preset). 1.0 = SDR white. Returns 0 and leaves them alone when not known (no window, iOS, unit tests: hle_vi.c's weak default). Any thread
int front_screen_edr(float *potential, float *current, float *reference);
// The panel's peak luminance in nits estimated from the EDR headroom: potential × SDR white, with SDR white taken as 100 nits in a reference preset (Apple's reference presets
// put EDR 1.0 at 100 nits) and DM_HDR_SDR_NITS (default 100) otherwise; 0 = not known. An estimate: macOS does not report nits. Any thread
int front_screen_peak_nits(void);
// The highest refresh rate of the screen the game is shown on in Hz, 0 = not known (front_mac.m: the window's screen; front_ios.m: the game view's screen, 60 in Low Power Mode). Any thread
int front_screen_max_fps(void);
// The screen's native refresh rate before front_screen_match temporarily switched it to a lower fixed rate in fullscreen (front_mac.m; on iOS, same as front_screen_max_fps). Any thread
int front_screen_capable_fps(void);
// The pixel size of the display the game is shown on: on the Mac the window's screen in its current mode (the main display before the window is up) (a scaled Retina mode's pixels), an iPhone's or iPad's screen (nativeBounds).
// Returns 0 and leaves w, h alone when not known (no front end: graphics unit tests). Any thread
int front_display_pixels(int *w, int *h);
// The pixel size of the largest screen attached, in its current mode (Mac front_mac.m: by area; DM_DISPLAY_BUFFER=max, hle_vi.c). Returns 0 and leaves w, h alone when not known. Any thread
int front_display_pixels_largest(int *w, int *h);
// Whether the window's current screen mode supports variable refresh (Mac front_mac.m; none on iOS). Any thread
int front_screen_variable_refresh(void);
// The frame rate the display link paces the game at (60, 30, 120; nvn_mtl.m link_sync): in fullscreen, a screen whose refresh rate is not a multiple of it is switched, while the game runs,
// to a mode of the same size whose rate is, and back when the window leaves fullscreen or that screen (front_mac.m; none on iOS). Called from the present thread
void front_screen_match(int fps);
// Whether startup fullscreen or a screen mode switch is still settling, so the display link waits before starting (front_mac.m; none on iOS). Any thread
int front_screen_settling(void);
// The shape of the picture the game presents (nvn_mtl.m present_now, present_shape: the layer's, not the crop's, w x h), called when its width / height changes: the front end
// lays the picture out in that shape instead of 16:9, so a profile with screen_aspect under DM_SCREEN_ASPECT (1920x1344) fills a 1.43:1 screen and touches map onto the picture
// as drawn. Before the first call the picture is 16:9. Called from the present thread; the front end switches to its main thread and does not block
void front_picture_shape(int w, int h);
// Progress screen of the first-start prepare step (nvn_mtl.m warm_prepare: "Preparing shaders" while the pipelines of the prewarm lists are built before the game's first frame):
// title and done of total shown over the game's view (a dark screen, the title, a bar and a count), updated on each call; title NULL hides it. Any thread; the front end switches to its main
// thread and does not block. Nothing is shown without a window
void front_progress(const char *title, long done, long total);
// An app that hosts the game view and has a look of its own (a launcher holding several games) can draw that progress itself: set before the game starts, with a window the hook gets each
// front_progress call's values on the front end's main thread (title NULL when the step ends; the title is valid during the call) and the front end shows no screen of its own.
// NULL (the default): the front end's screen above
extern void (*front_progress_hook)(const char *title, long done, long total);
#include <stdint.h>
#include <stddef.h>
// Text input box (for the software keyboard swkbd): the main thread shows a native input box and the calling thread blocks until the user confirms / cancels.
// All text is UTF-8; max_chars is the maximum character count (0 = unlimited, only a hint for the front end; truncation is done uniformly by the caller hle_swkbd.c in UTF-16 units).
// Confirm returns 1 and writes the result into out (including the terminating 0); cancel returns 0;
// with no window (front_metal_layer() == NULL) nothing is shown and -1 is returned.
int front_text_input(const char *title, const char *sub, const char *guide, const char *initial, int max_chars, char *out, int out_cap);
// Controller applet prompt (hle_hid.c ctrl_support, ctrl_prompt.h; GitHub issue #1640): the game wants min to max players (max <= 0: no maximum) and sees fewer. The main thread shows a
// prompt over the game while controllers join and the calling thread blocks until it closes. 1: done (A or Return with the minimum in, the maximum in, or nobody left to join);
// 0: closed (B, Escape); -1 with no window: nothing shown, the caller answers as the player closing it
int front_ctrl_support(int min, int max);

// Account applet: choices are already filtered by the host's selection settings.
// Return a displayed user's slot, FRONT_USER_CREATE, FRONT_USER_SKIP, or FRONT_USER_CANCEL.
// Synchronous on the guest thread, native UI on the main thread. No window: cancel,
// never infer a user from controllers. Creation/skip actions appear only when allowed.
typedef struct { int slot, open; char nickname[33]; } front_user;
enum { FRONT_USER_CANCEL = -1, FRONT_USER_CREATE = -2, FRONT_USER_SKIP = -3 };
int front_user_select(const front_user *users, int count, int allow_create, int allow_skip);

// Early start of host loading (main.c): reading the NSO / relocation / forced takeover / prefetch start are moved to a background thread, in parallel with the front end (UIKit launch chain, Metal view);
// the dm_main / main called afterwards waits for it to finish. For call timing and preconditions see the comments in main.c (set DM_ROMFS and the other environment variables and the cwd first; arguments identical item by item to those of the later main).
void dm_host_preload_start(int argc, char **argv);
// iOS: names the loaded image that carries the game's embedded module sections (loader.c map_image, nro_pieces), for an app that links them into a framework it dlopens from its signed bundle.
// Set it before dm_host_preload_start, once: the loader reads it on the preload thread and at every later NRO load. Returns 1 for a valid image. Not set, they are read from the executable.
int dm_set_game_image_header(const void *mh);

// Touchscreen (implemented by the host's hle_touch.c; called by the iOS / Mac front end): whenever the set of touch points changes (down / move / up / cancel) the whole set is pushed once; n = 0 = all lifted.
// id = finger slot number 0–15 (the lowest free slot on down, unchanged until up; used directly as finger_id); x / y = normalized coordinates [0,1) on the output frame, origin at top left.
// The host converts to the panel coordinates the game reads, 1280x720 (x·1280, y·720), and latches short taps (a down and up between two reads is reported at least once). May be called from any thread.
typedef struct { uint32_t id; float x, y; } dm_touch;
void dm_touch_set(const dm_touch *t, int n);
void dm_touch_script(const dm_touch *t, int n);   // scripted touches (DM_KEYS, DM_CTL; hle_hid.c): as dm_touch_set, but never recorded by DM_REC

// Save not written (called by the host's hle_fs.c; the iOS front end provides a strong implementation of the same name that shows the native prompt "Not enough storage. Progress was not saved"; the default weak implementation only logs).
// Timing: when a save write fails (disk full etc.) within one of the game's save transactions (between two Commits), so that this Commit is refused and the previously committed save is unchanged, it is called once per refused transaction;
// the next transaction that succeeds commits as usual, and the front end need not do any recovery. err = the first failing errno (ENOSPC = 28 means out of space). Called on the game thread; the front end switches to the main thread itself and must not block
void front_save_failed(int err);

// GPU lost (called by the graphics backend's nvn_mtl.m gpu_lost_check, once): the first command buffer came back MTL4CommandQueueErrorAccessRevoked, so macOS runs none of the process's GPU work
// any more and nothing is drawn again. By then presents have stopped and the game's waits for the GPU are released, so the game runs on with nothing on screen until the front end ends it.
// The Mac front end leaves full screen, says why in an alert and quits with exit status 70; without a window it ends the run as the default weak implementation (nvn_mtl.m) does, which the iOS
// front end keeps: a FATAL line and an abort. Called on Metal's feedback queue; the front end switches to the main thread itself and must not block
void front_gpu_lost(void);

// Offline HTML pages (the web applet's offline pages; hle_web.c): a web view over the game picture (web_apple.m, Mac and iPhone). Called from guest threads; the front end works on its main
// thread. front_web_open: dir = the folder the document path is relative to (an HtmlDocument's html-document), path = the document path with its query, callback = the URL prefix whose
// loading ends the page (exit reason 3, the URL as the last URL), hidden = loaded without being shown until front_web_show. 0 = opened; -1 = no web view (no window): the caller's
// stand-in answers. front_web_send hands the page a content message (its nx "message" event); front_web_close removes the page. The defaults (hle_web.c, weak) have no web view
typedef struct { uint32_t repeat_delay, repeat_pulse; } dm_web_opts;   // key repeat in frames (the argument's SetKeyRepeatFrame); 0 = the browser's default
int front_web_open(const char *dir, const char *path, const char *callback, int hidden, const dm_web_opts *opts);
void front_web_show(void);
void front_web_send(const char *msg, size_t n);
void front_web_close(void);
void front_web_shot(const char *path);
// The front end's reports (any thread): a content message from the page (nx.sendMessage); the page ended (exit reason 0 end, 1 back, 3 callback URL; url NULL = none); it could not be loaded
void dm_web_message(const char *msg, size_t n);
void dm_web_ended(uint32_t reason, const char *url);
void dm_web_failed(const char *why);

// The program an oe::ExecuteProgram or oe::RequestToRelaunchApplication recorded starts at the app's next start (the iOS app, DM_EXEC_OUT, hle_oe.c): called on the guest thread after the record is
// written and before the graceful exit. index = the program, name = its profile's name. The iOS front end names it on screen for about 1.5 s and schedules a local notification that opens the app
// again, when the player allowed notifications (else it asks on screen to open the app again); it returns when the notification is scheduled. With no DM_EXEC_OUT (an app of one program, which asks to start itself again) it asks the player on
// screen to open the app again. The default (hle_oe.c, weak) returns at once
void front_program_handoff(int index, const char *name);

// Legacy TonTon touch layout follows the exact-build skill panel lifetime.
int dm_za_skill_layout_active(void);
