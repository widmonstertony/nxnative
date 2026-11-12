// Quit with the Home button (Mac front end, front_mac.m; LNPANDY/NX2Apple#336). Holding Home (the logo button on Xbox and PlayStation pads) for HQ_HOLD_S seconds opens a
// "Quit?" prompt over the game: A quits (the same exit as ⌘Q), B or a new press of Home closes it. Letting go of Home before the time is up does nothing. A and B are
// GameController's buttonA and buttonB (by label: the bottom button on an Xbox or PlayStation pad, the one printed A on a Nintendo pad), not the Switch buttons the game
// gets. Direct Triton reports use Guide and the physical A and B labels. Pure, so tests/t_home_quit.c checks it without a controller or a window.
//
// The hold works wherever the press reaches the host: controller_add_gc claims Home on each native pad (preferredSystemGestureState = GCSystemGestureStateDisabled), and
// macOS 27 respects the claim when the Home button setting for apps lets the app decide (front_mac.m logs the setting). When the system takes Home anyway (it opens the
// Games app or the player's chosen app), the game window loses the focus and whatever was shown closes (hq_cancel). DM_HOME_QUIT=0 turns it off. A front end passes the
// texts in the player's language as DM_HOME_QUIT_TEXT (hq_text_line, docs/frontends.md), English otherwise.
//
// A short press of Home (let go within HQ_TAP_S) opens the Home menu instead (LNPANDY/NX2Apple#952): Resume, Back to console mode (only when a launcher started the game
// and asked for it, DM_HOME_MENU_LAUNCHER=1) and Quit, chosen with up and down and A; B or a new press of Home resumes. Quit opens the quit prompt above, so ending the
// game is asked first. Back to console mode puts the game in HQ_PAUSED: the front end pauses it as a minimized window, hides it and shows the launcher, and
// hq_resumed takes it back when the game is shown again. DM_HOME_MENU=0 turns the menu off (a short press does nothing, as before).
#pragma once
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#define HQ_HOLD_S 2.0    // how long Home is held before the prompt opens
#define HQ_RING_S 0.3    // the hold indicator shows only after this, so a short press shows nothing
#define HQ_TAP_S 0.5     // Home let go within this is a short press: it opens the Home menu
#define HQ_STICK 0.5     // a stick moved this far (of its range) up or down moves the menu's selection, as the d-pad does

typedef enum {
    HQ_IDLE,      // nothing shown, the game has its input
    HQ_HOLDING,   // Home is held: the indicator fills up
    HQ_PROMPT,    // the prompt is open: the game gets no controller input
    HQ_SETTLE,    // the prompt was closed: the game gets controller input again once Home, A and B are all up, so the B that closed it never reaches the game
    HQ_QUIT,      // A was pressed in the prompt: the front end quits (final)
    HQ_MENU,      // the Home menu is open: the game gets no controller input
    HQ_PAUSED,    // Back to console mode was chosen: the front end pauses the game in the background until hq_resumed
} hq_phase;

// The rows of the Home menu, in the order they are shown
enum { HQ_ROW_RESUME, HQ_ROW_CONSOLE, HQ_ROW_QUIT, HQ_ROWS };

typedef struct {
    hq_phase phase;
    double since;     // when the hold started (seconds, any clock that only goes forward)
    int home;         // Home was down at the last step (a press is a change from up to down)
    int a_up, b_up;   // A and B have been up since the prompt opened: a button already held when it opens does not count
    int up, down;     // up and down were held at the last step (a move is a change from up to down)
    int sel;          // the selected row of the menu (an index into hq_menu_rows)
    // Set by the front end before the first step; all 0 is today's hold to quit alone
    int menu;         // a short press opens the Home menu (DM_HOME_MENU)
    int launcher;     // the menu has Back to console mode (DM_HOME_MENU_LAUNCHER=1)
    int no_hold;      // holding Home does not open the quit prompt (DM_HOME_QUIT=0)
} home_quit;

// Whether the hold does anything: on unless DM_HOME_QUIT=0 (env: its value, NULL when unset). DM_HOME_MENU reads the same way
static inline int hq_enabled(const char *env) { return !(env && !strcmp(env, "0")); }
// Whether the launcher asked for Back to console mode: DM_HOME_MENU_LAUNCHER=1 only
static inline int hq_launcher(const char *env) { return env && !strcmp(env, "1"); }

// The rows the menu shows (HQ_ROW_*), into rows; returns how many
static inline int hq_menu_rows(const home_quit *q, int rows[HQ_ROWS]) {
    int n = 0;
    rows[n++] = HQ_ROW_RESUME;
    if (q->launcher) rows[n++] = HQ_ROW_CONSOLE;
    rows[n++] = HQ_ROW_QUIT;
    return n;
}
// The row the selection is on (HQ_ROW_*)
static inline int hq_menu_row(const home_quit *q) {
    int rows[HQ_ROWS], n = hq_menu_rows(q, rows);
    return rows[q->sel < 0 ? 0 : q->sel >= n ? n - 1 : q->sel];
}

// One step with the buttons as they are now (pressed on any controller) at time now, up and down being the d-pad or a stick (only the menu reads them). Called on
// every change of a button and, while anything is shown, from a timer.
static inline hq_phase hq_step_nav(home_quit *q, double now, int home, int a, int b, int up, int down) {
    int pressed = home && !q->home, moved_up = up && !q->up, moved_down = down && !q->down;
    q->home = home; q->up = up; q->down = down;
    switch (q->phase) {
    case HQ_IDLE:
        if (pressed) { q->phase = HQ_HOLDING; q->since = now; }
        break;
    case HQ_HOLDING:
        if (!home) {   // let go: a short press opens the menu, a longer one was a hold let go too early
            if (q->menu && now - q->since < HQ_TAP_S) { q->phase = HQ_MENU; q->sel = 0; q->a_up = !a; q->b_up = !b; }
            else q->phase = HQ_IDLE;
        } else if (!q->no_hold && now - q->since >= HQ_HOLD_S) { q->phase = HQ_PROMPT; q->a_up = !a; q->b_up = !b; }
        break;
    case HQ_MENU: {
        if (!a) q->a_up = 1;
        if (!b) q->b_up = 1;
        int rows[HQ_ROWS], n = hq_menu_rows(q, rows);
        if ((b && q->b_up) || pressed) { q->phase = HQ_SETTLE; break; }   // B or Home resumes; with A and B at once the safe one wins
        if (a && q->a_up) {
            int row = hq_menu_row(q);
            if (row == HQ_ROW_RESUME) q->phase = HQ_SETTLE;
            else if (row == HQ_ROW_CONSOLE) q->phase = HQ_PAUSED;
            else { q->phase = HQ_PROMPT; q->a_up = 0; q->b_up = !b; }   // Quit asks first: the A that chose it does not confirm it
            break;
        }
        if (moved_up && !moved_down && q->sel > 0) q->sel--;
        else if (moved_down && !moved_up && q->sel < n - 1) q->sel++;
        break;
    }
    case HQ_PAUSED:
        break;
    case HQ_PROMPT:
        if (!a) q->a_up = 1;
        if (!b) q->b_up = 1;
        if ((b && q->b_up) || pressed) q->phase = HQ_SETTLE;   // B or Home closes it; with A and B at once the safe one wins
        else if (a && q->a_up) q->phase = HQ_QUIT;
        break;
    case HQ_SETTLE:
        if (!home && !a && !b) q->phase = HQ_IDLE;
        break;
    case HQ_QUIT:
        break;
    }
    return q->phase;
}
// The same without up and down (the hold and the prompt alone)
static inline hq_phase hq_step(home_quit *q, double now, int home, int a, int b) { return hq_step_nav(q, now, home, a, b, 0, 0); }

// The window lost focus (another app, the Games app the system opened for Home): whatever was shown closes. A Home still held needs a new press. A game paused in the
// background stays so until hq_resumed: hiding it is what takes its focus
static inline void hq_cancel(home_quit *q) { if (q->phase != HQ_QUIT && q->phase != HQ_PAUSED) { q->phase = HQ_IDLE; q->home = 1; } }
// The game paused in the background is shown again: it gets controller input once Home, A and B are all up, and a Home still held needs a new press
static inline void hq_resumed(home_quit *q) { if (q->phase == HQ_PAUSED) { q->phase = HQ_SETTLE; q->home = 1; } }

// The game gets no controller input in these phases
static inline int hq_blocks_input(hq_phase p) { return p == HQ_PROMPT || p == HQ_SETTLE || p == HQ_QUIT || p == HQ_MENU || p == HQ_PAUSED; }

// How full the hold indicator is (0 to 1), -1 while it is not shown (also when the hold does not quit)
static inline double hq_ring(const home_quit *q, double now) {
    if (q->phase != HQ_HOLDING || q->no_hold) return -1;
    double t = (now - q->since - HQ_RING_S) / (HQ_HOLD_S - HQ_RING_S);
    return t < 0 ? -1 : t > 1 ? 1 : t;
}

// The texts, in this order, one per line of DM_HOME_QUIT_TEXT: the hold indicator, the prompt's title, its note, the quit button (also the menu's Quit row), the cancel
// button, then the Home menu's Resume row, its Back to console mode row and its title. The menu's lines come last, so a front end that passes the first five still works
enum { HQ_TEXT_HOLD, HQ_TEXT_TITLE, HQ_TEXT_NOTE, HQ_TEXT_QUIT, HQ_TEXT_CANCEL, HQ_TEXT_RESUME, HQ_TEXT_CONSOLE, HQ_TEXT_MENU_TITLE, HQ_TEXTS };
// Line i of text into out; an empty or missing line (or no text) gives def. The titles' defaults have the game's name: def is the caller's
static inline void hq_text_line(const char *text, int i, const char *def, char *out, size_t cap) {
    const char *s = text;
    for (int k = 0; s && k < i; k++) { s = strchr(s, '\n'); if (s) s++; }
    size_t n = 0;
    if (s) { const char *e = strchr(s, '\n'); n = e ? (size_t)(e - s) : strlen(s); }
    if (!n) { snprintf(out, cap, "%s", def); return; }
    if (n >= cap) n = cap - 1;
    memcpy(out, s, n); out[n] = 0;
}

// GameController's Home button setting for apps (GCControllerHomeButtonSettingInAppAction, macOS 27) as the word the log line names it by:
// "system" (the system keeps Home whatever the app asks), "app" (the app decides), "off" (the system does nothing with Home in apps),
// "unavailable" (could not be read)
static inline const char *hq_in_app_name(long v) {
    return v == 0 ? "system" : v == 1 ? "app" : v == -1 ? "unavailable" : v > 1 ? "off" : "unavailable";
}
