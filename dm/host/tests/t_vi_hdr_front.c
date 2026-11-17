// The front end and the log as t_vi_hdr sees them: strong definitions of what hle_vi.c (and dm.h's dm_log) define weak, set by the test's globals. A file of its own,
// as a strong definition in the translation unit that includes hle_vi.c would clash with its weak one
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

int t_front_hdr, t_front_peak, t_content_calls, t_log_lines, t_hdr_lines, t_gamut = -2, t_gamut_calls;
float t_content_max;
char t_last_line[512];

int front_hdr_present(void) { return t_front_hdr; }
int front_screen_peak_nits(void) { return t_front_peak; }
void front_hdr_content_max_nits(float nits) { t_content_max = nits; t_content_calls++; }
void front_hdr_content_gamut(int gamut) { t_gamut = gamut; t_gamut_calls++; }
// The screens as t_vi_bufmax sets them: the window's (front_display_pixels) and the largest attached (front_display_pixels_largest); 0 size = not known
int t_disp_w, t_disp_h, t_big_w, t_big_h;
int front_display_pixels(int *w, int *h) { if (!t_disp_w) return 0; *w = t_disp_w; *h = t_disp_h; return 1; }
int front_display_pixels_largest(int *w, int *h) { if (!t_big_w) return 0; *w = t_big_w; *h = t_big_h; return 1; }
void dm_log(const char *fmt, ...) {
    va_list ap; va_start(ap, fmt); vsnprintf(t_last_line, sizeof t_last_line, fmt, ap); va_end(ap);
    t_log_lines++;
    if (strstr(t_last_line, "[hdr]")) t_hdr_lines++;
}
