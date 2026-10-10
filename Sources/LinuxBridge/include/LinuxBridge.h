#pragma once
#include <stdint.h>
typedef void (*TMAction)(int action);
typedef void (*TMTick)(void);
// Actions: 0 overview, 1 sessions, 2 settings, 3 refresh, 4 quit.
int tm_tray_start(TMAction action, TMTick tick);
void tm_tray_update(const char *label, const char *tooltip);
void tm_tray_stop(void);
void tm_window_hide(void *window);
void *tm_main_window(void);
void tm_window_keep_alive(void *window);
void tm_window_present(void *window);
int tm_window_visible(void *window);
int tm_window_capture(void *window, const char *path);
void tm_app_hold(void);
void tm_app_release(void);
char *tm_secret_get(const char *account);
int tm_secret_set(const char *account, const char *value);
int tm_secret_delete(const char *account);
int tm_secret_failed(void);
void tm_secret_free(char *value);
