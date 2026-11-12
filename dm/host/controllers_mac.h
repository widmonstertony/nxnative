#pragma once
#import <Cocoa/Cocoa.h>
// Main-thread controller routing and a model-specific mapping panel.
void front_controllers_start(void);
NSMenu *front_controllers_menu(void);

#include "front.h"
void front_controllers_mouse(const dm_touch *touch);
void front_controllers_focus(int active);
void front_controllers_modal(int active);
void front_controllers_window(int active);

// Main-thread input for the Home quit prompt. Read physical buttons before remapping.
@class GCController;
GCController *front_controllers_quit_buttons(int *home, int *a, int *b);
void front_controllers_quit_prompt(int active);
// Up and down for the Home menu (home_quit.h): the d-pad or the left stick past HQ_STICK on any player's controller, before remapping
void front_controllers_menu_dirs(int *up, int *down);
void front_home_poll(void);

// Called on the main thread when mapped input reaches the game.
void front_game_input(void);

// The controller applet's prompt (front_mac.m front_ctrl_support): while it is up the game gets no controller input, the prompt reads A and B on any connected controller, and
// counts the controllers that are no player yet. front_cp_poll (front_mac.m) is called on each input and each connection change.
void front_controllers_applet(int active);
void front_controllers_applet_buttons(int *a, int *b);
int front_controllers_waiting(void);
int front_cp_poll(void);
