// Optional signed game image, following NX2Apple Route C / nxnative PR #729.
// Set before preload. Host HLE tables always remain in the app executable.
#pragma once
#ifdef __cplusplus
extern "C" {
#endif
int dm_set_game_image_header(const void *header);
#ifdef __cplusplus
}
#endif
