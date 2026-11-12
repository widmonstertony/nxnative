// The Home button's hold and quit prompt (home_quit.h): the hold time, letting go early, A and B in the prompt, a button already held when it opens, Home closing it,
// the settle phase that keeps the closing B from the game, losing the focus, the hold indicator, the switch, a front end's texts and the setting's log word; the Home
// menu of a short press: its rows with and without the launcher's, moving through them, Resume, Back to console mode and resuming from it, Quit asking first
#include "../home_quit.h"
#include <stdio.h>

static int checks, fails;
#define CHECK(c, msg) do { checks++; if (!(c)) { fails++; fprintf(stderr, "FAIL: %s (line %d)\n", msg, __LINE__); } } while (0)

int main(void) {
    home_quit q = {0};
    CHECK(hq_step(&q, 0, 0, 0, 0) == HQ_IDLE, "nothing pressed: idle");
    CHECK(hq_step(&q, 1.0, 1, 0, 0) == HQ_HOLDING, "Home pressed: the hold starts");
    CHECK(hq_ring(&q, 1.1) == -1, "a short press shows no indicator");
    CHECK(hq_ring(&q, 1.0 + HQ_RING_S + (HQ_HOLD_S - HQ_RING_S) / 2) > 0.49 && hq_ring(&q, 1.0 + HQ_RING_S + (HQ_HOLD_S - HQ_RING_S) / 2) < 0.51, "half way the ring is half full");
    CHECK(hq_step(&q, 2.9, 1, 0, 0) == HQ_HOLDING, "1.9 s: still holding");
    CHECK(!hq_blocks_input(q.phase), "the game keeps its input while Home is held");
    CHECK(hq_step(&q, 3.0, 1, 0, 0) == HQ_PROMPT, "2 s: the prompt opens");
    CHECK(hq_ring(&q, 3.0) == -1, "the indicator goes when the prompt opens");
    CHECK(hq_blocks_input(q.phase), "the prompt takes the controllers");
    CHECK(hq_step(&q, 3.5, 0, 0, 0) == HQ_PROMPT, "letting go of Home keeps the prompt open");
    CHECK(hq_step(&q, 4.0, 0, 1, 0) == HQ_QUIT, "A quits");
    CHECK(hq_step(&q, 4.1, 0, 0, 0) == HQ_QUIT, "quit is final");
    hq_cancel(&q);
    CHECK(q.phase == HQ_QUIT, "a focus loss after quit changes nothing");

    q = (home_quit){0};
    hq_step(&q, 0, 1, 0, 0);
    CHECK(hq_step(&q, 1.0, 0, 0, 0) == HQ_IDLE, "let go before 2 s: nothing happens");
    CHECK(hq_step(&q, 5.0, 0, 0, 0) == HQ_IDLE, "and nothing later either");

    q = (home_quit){0};
    hq_step(&q, 0, 1, 0, 0); hq_step(&q, 2.0, 1, 0, 0);
    CHECK(hq_step(&q, 2.5, 1, 0, 1) == HQ_SETTLE, "B closes the prompt");
    CHECK(hq_blocks_input(q.phase), "the B that closed it does not reach the game");
    CHECK(hq_step(&q, 2.6, 1, 0, 0) == HQ_SETTLE, "Home still down: still settling");
    CHECK(hq_step(&q, 2.7, 0, 0, 0) == HQ_IDLE, "all up: the game has the controllers again");
    CHECK(hq_step(&q, 2.8, 1, 0, 0) == HQ_HOLDING, "a new press starts a new hold");

    q = (home_quit){0};
    hq_step(&q, 0, 1, 1, 1);
    CHECK(hq_step(&q, 2.0, 1, 1, 1) == HQ_PROMPT, "A and B held through the hold: the prompt opens");
    CHECK(hq_step(&q, 2.1, 1, 1, 1) == HQ_PROMPT, "an A or B already held when it opens does not count");
    CHECK(hq_step(&q, 2.2, 1, 0, 1) == HQ_PROMPT, "A released, B still held");
    CHECK(hq_step(&q, 2.3, 1, 1, 1) == HQ_QUIT, "A pressed again quits");

    q = (home_quit){0};
    hq_step(&q, 0, 1, 0, 0); hq_step(&q, 2.0, 1, 0, 0);
    CHECK(hq_step(&q, 2.1, 1, 0, 0) == HQ_PROMPT, "Home still held from the hold does not close it");
    hq_step(&q, 2.2, 0, 0, 0);
    CHECK(hq_step(&q, 2.3, 1, 0, 0) == HQ_SETTLE, "a new press of Home closes it");

    q = (home_quit){0};
    hq_step(&q, 0, 1, 0, 0); hq_step(&q, 2.0, 1, 0, 0);
    CHECK(hq_step(&q, 2.1, 0, 1, 1) == HQ_SETTLE, "A and B at once: the safe one wins");

    q = (home_quit){0};
    hq_step(&q, 0, 1, 0, 0); hq_step(&q, 2.0, 1, 0, 0);
    hq_cancel(&q);
    CHECK(q.phase == HQ_IDLE && !hq_blocks_input(q.phase), "a focus loss closes the prompt");
    CHECK(hq_step(&q, 3.0, 1, 0, 0) == HQ_IDLE, "a Home held through the focus change needs a new press");
    hq_step(&q, 3.1, 0, 0, 0);
    CHECK(hq_step(&q, 3.2, 1, 0, 0) == HQ_HOLDING, "then a press holds again");

    // The Home menu (LNPANDY/NX2Apple#952): a short press opens it, a hold still opens the quit prompt
    q = (home_quit){.menu = 1};
    CHECK(hq_step(&q, 0, 1, 0, 0) == HQ_HOLDING, "menu on: Home pressed starts a hold");
    CHECK(hq_step(&q, 0.2, 0, 0, 0) == HQ_MENU, "let go within 0.5 s: the menu opens");
    CHECK(hq_blocks_input(q.phase), "the menu takes the controllers");
    CHECK(q.sel == 0 && hq_menu_row(&q) == HQ_ROW_RESUME, "the menu opens on Resume");
    CHECK(hq_step(&q, 0.3, 0, 1, 0) == HQ_SETTLE, "A on Resume: the game goes on, once A is up");
    CHECK(hq_step(&q, 0.4, 0, 0, 0) == HQ_IDLE, "all up: the game has the controllers again");

    q = (home_quit){.menu = 1};
    hq_step(&q, 0, 1, 0, 0);
    CHECK(hq_step(&q, 1.0, 0, 0, 0) == HQ_IDLE, "let go after 0.5 s and before 2 s: nothing");
    hq_step(&q, 2.0, 1, 0, 0);
    CHECK(hq_step(&q, 4.0, 1, 0, 0) == HQ_PROMPT, "menu on: a 2 s hold still opens the quit prompt");
    CHECK(hq_step(&q, 4.1, 0, 0, 0) == HQ_PROMPT, "letting go after the hold keeps the prompt, no menu");

    q = (home_quit){0};
    hq_step(&q, 0, 1, 0, 0);
    CHECK(hq_step(&q, 0.2, 0, 0, 0) == HQ_IDLE, "menu off (DM_HOME_MENU=0): a short press does nothing");

    // Without the launcher: Resume and Quit
    q = (home_quit){.menu = 1};
    int rows[HQ_ROWS];
    CHECK(hq_menu_rows(&q, rows) == 2 && rows[0] == HQ_ROW_RESUME && rows[1] == HQ_ROW_QUIT, "without DM_HOME_MENU_LAUNCHER: Resume and Quit only");
    q.launcher = 1;
    CHECK(hq_menu_rows(&q, rows) == 3 && rows[1] == HQ_ROW_CONSOLE, "with it: Back to console mode in the middle");

    // Navigation: down, down, clamped at the end, up; a held direction moves once
    q = (home_quit){.menu = 1, .launcher = 1};
    hq_step_nav(&q, 0, 1, 0, 0, 0, 0); hq_step_nav(&q, 0.1, 0, 0, 0, 0, 0);
    CHECK(q.phase == HQ_MENU, "the menu is open");
    hq_step_nav(&q, 0.2, 0, 0, 0, 0, 1);
    CHECK(hq_menu_row(&q) == HQ_ROW_CONSOLE, "down: Back to console mode");
    hq_step_nav(&q, 0.3, 0, 0, 0, 0, 1);
    CHECK(hq_menu_row(&q) == HQ_ROW_CONSOLE, "down held: no repeat");
    hq_step_nav(&q, 0.4, 0, 0, 0, 0, 0); hq_step_nav(&q, 0.5, 0, 0, 0, 0, 1);
    CHECK(hq_menu_row(&q) == HQ_ROW_QUIT, "down again: Quit");
    hq_step_nav(&q, 0.6, 0, 0, 0, 0, 0); hq_step_nav(&q, 0.7, 0, 0, 0, 0, 1);
    CHECK(hq_menu_row(&q) == HQ_ROW_QUIT, "down on the last row stays there");
    hq_step_nav(&q, 0.8, 0, 0, 0, 0, 0); hq_step_nav(&q, 0.9, 0, 0, 0, 1, 0);
    CHECK(hq_menu_row(&q) == HQ_ROW_CONSOLE, "up: back to Back to console mode");
    hq_step_nav(&q, 1.0, 0, 0, 0, 0, 0); hq_step_nav(&q, 1.1, 0, 0, 0, 1, 0); hq_step_nav(&q, 1.2, 0, 0, 0, 0, 0); hq_step_nav(&q, 1.3, 0, 0, 0, 1, 0);
    CHECK(hq_menu_row(&q) == HQ_ROW_RESUME, "up on the first row stays there");
    hq_step_nav(&q, 1.4, 0, 0, 0, 0, 0); hq_step_nav(&q, 1.5, 0, 0, 0, 0, 1);
    CHECK(hq_step_nav(&q, 1.6, 0, 1, 0, 0, 1) == HQ_PAUSED, "A on Back to console mode: paused in the background");
    CHECK(hq_blocks_input(q.phase), "the paused game gets no controller input");
    hq_cancel(&q);
    CHECK(q.phase == HQ_PAUSED, "hiding the game (a focus loss) keeps it paused");
    CHECK(hq_step_nav(&q, 2.0, 1, 1, 0, 0, 0) == HQ_PAUSED, "buttons while paused change nothing");
    hq_resumed(&q);
    CHECK(q.phase == HQ_SETTLE && hq_blocks_input(q.phase), "shown again: settling until the buttons are up");
    CHECK(hq_step_nav(&q, 3.0, 1, 0, 0, 0, 0) == HQ_SETTLE, "Home still held: still settling");
    CHECK(hq_step_nav(&q, 3.1, 0, 0, 0, 0, 0) == HQ_IDLE, "all up: the game plays again");
    CHECK(hq_step_nav(&q, 3.2, 1, 0, 0, 0, 0) == HQ_HOLDING, "and a new press of Home works");
    hq_resumed(&q);
    CHECK(q.phase == HQ_HOLDING, "hq_resumed outside the background changes nothing");

    // Quit in the menu asks first: the A that chose it does not confirm it
    q = (home_quit){.menu = 1};
    hq_step_nav(&q, 0, 1, 0, 0, 0, 0); hq_step_nav(&q, 0.1, 0, 0, 0, 0, 0); hq_step_nav(&q, 0.2, 0, 0, 0, 0, 1);
    CHECK(hq_menu_row(&q) == HQ_ROW_QUIT, "without the launcher, down goes straight to Quit");
    CHECK(hq_step_nav(&q, 0.3, 0, 1, 0, 0, 0) == HQ_PROMPT, "A on Quit: the quit prompt");
    CHECK(hq_step_nav(&q, 0.4, 0, 1, 0, 0, 0) == HQ_PROMPT, "the A still held does not quit");
    hq_step_nav(&q, 0.5, 0, 0, 0, 0, 0);
    CHECK(hq_step_nav(&q, 0.6, 0, 1, 0, 0, 0) == HQ_QUIT, "a new A quits");

    // B and Home close the menu; buttons held when it opens do not count
    q = (home_quit){.menu = 1};
    hq_step(&q, 0, 1, 0, 1);
    CHECK(hq_step(&q, 0.1, 0, 0, 1) == HQ_MENU, "B held through the press: the menu opens and stays");
    hq_step(&q, 0.2, 0, 0, 0);
    CHECK(hq_step(&q, 0.3, 0, 0, 1) == HQ_SETTLE, "a new B resumes");
    q = (home_quit){.menu = 1};
    hq_step(&q, 0, 1, 1, 0);
    CHECK(hq_step(&q, 0.1, 0, 1, 0) == HQ_MENU, "A held through the press does not choose Resume");
    q = (home_quit){.menu = 1};
    hq_step(&q, 0, 1, 0, 0); hq_step(&q, 0.1, 0, 0, 0);
    CHECK(hq_step(&q, 0.5, 1, 0, 0) == HQ_SETTLE, "a new press of Home resumes");
    q = (home_quit){.menu = 1, .launcher = 1};
    hq_step(&q, 0, 1, 0, 0); hq_step(&q, 0.1, 0, 0, 0);
    hq_step_nav(&q, 0.2, 0, 0, 0, 0, 1);
    CHECK(hq_step_nav(&q, 0.3, 0, 1, 1, 0, 0) == HQ_SETTLE, "A and B at once in the menu: B wins");
    q = (home_quit){.menu = 1};
    hq_step(&q, 0, 1, 0, 0); hq_step(&q, 0.1, 0, 0, 0);
    hq_cancel(&q);
    CHECK(q.phase == HQ_IDLE, "a focus loss closes the menu");
    hq_step(&q, 0.5, 1, 0, 0);
    CHECK(hq_step(&q, 0.6, 0, 0, 0) == HQ_IDLE, "a Home held through the focus loss opens nothing when let go");

    // DM_HOME_QUIT=0 with the menu on: the hold does nothing, the short press still opens the menu
    q = (home_quit){.menu = 1, .no_hold = 1};
    hq_step(&q, 0, 1, 0, 0);
    CHECK(hq_ring(&q, 1.5) == -1, "no hold: no indicator");
    CHECK(hq_step(&q, 3.0, 1, 0, 0) == HQ_HOLDING, "no hold: no prompt after 2 s");
    CHECK(hq_step(&q, 3.1, 0, 0, 0) == HQ_IDLE, "and letting go late does nothing");
    hq_step(&q, 4.0, 1, 0, 0);
    CHECK(hq_step(&q, 4.1, 0, 0, 0) == HQ_MENU, "a short press opens the menu");

    CHECK(!hq_launcher(NULL) && !hq_launcher("0") && !hq_launcher("") && hq_launcher("1"), "DM_HOME_MENU_LAUNCHER: only 1 turns the row on");

    CHECK(hq_enabled(NULL) && hq_enabled("1") && hq_enabled(""), "on by default");
    CHECK(!hq_enabled("0"), "DM_HOME_QUIT=0: off");

    char out[64];
    hq_text_line("Hold\nQuit Zelda?\nLost\nQuit\nCancel", HQ_TEXT_TITLE, "d", out, sizeof out);
    CHECK(!strcmp(out, "Quit Zelda?"), "a line of the text");
    hq_text_line("Hold\nQuit Zelda?\nLost\nQuit\nCancel", HQ_TEXT_CANCEL, "d", out, sizeof out);
    CHECK(!strcmp(out, "Cancel"), "the last line");
    hq_text_line("Hold\n\nLost", HQ_TEXT_TITLE, "Quit Mario?", out, sizeof out);
    CHECK(!strcmp(out, "Quit Mario?"), "an empty line takes the default");
    hq_text_line("Hold", HQ_TEXT_QUIT, "Quit", out, sizeof out);
    CHECK(!strcmp(out, "Quit"), "a missing line takes the default");
    hq_text_line(NULL, HQ_TEXT_HOLD, "Keep holding to quit", out, sizeof out);
    CHECK(!strcmp(out, "Keep holding to quit"), "no text: the defaults");
    const char *nine = "Hold\nQuit Zelda?\nLost\nQuit\nCancel\nResume\nBack to console mode\nZelda";
    hq_text_line(nine, HQ_TEXT_RESUME, "d", out, sizeof out);
    CHECK(!strcmp(out, "Resume"), "the menu's Resume line comes after the prompt's five");
    hq_text_line(nine, HQ_TEXT_CONSOLE, "d", out, sizeof out);
    CHECK(!strcmp(out, "Back to console mode"), "then Back to console mode");
    hq_text_line(nine, HQ_TEXT_MENU_TITLE, "d", out, sizeof out);
    CHECK(!strcmp(out, "Zelda"), "then the menu's title");
    hq_text_line("Hold\nQuit Zelda?\nLost\nQuit\nCancel", HQ_TEXT_RESUME, "Resume", out, sizeof out);
    CHECK(!strcmp(out, "Resume"), "an old launcher's five lines: the menu's texts are English");
    char small[4]; hq_text_line("Abcdef", 0, "d", small, sizeof small);
    CHECK(!strcmp(small, "Abc"), "a long line is cut to the buffer");

    CHECK(!strcmp(hq_in_app_name(0), "system") && !strcmp(hq_in_app_name(1), "app") && !strcmp(hq_in_app_name(-1), "unavailable"), "the setting's words");
    CHECK(!strcmp(hq_in_app_name(0x7fffffffffffffffL), "off"), "disabled is off");

    printf("t_home_quit: %d checks, %d failed\n", checks, fails);
    return fails != 0;
}
