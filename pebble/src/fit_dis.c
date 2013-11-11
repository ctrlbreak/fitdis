#include <pebble.h>
#include <stdint.h>
#include <string.h>

static struct FitDisData {
  Window *window;
  TextLayer *header_layer;
  TextLayer *hr_layer;
  AppSync sync;
  uint8_t sync_buffer[32];
} s_data;

enum {
  HEART_RATE_KEY = 0x0,         // TUPLE_CSTRING
};

static void sync_error_callback(DictionaryResult dict_error, AppMessageResult app_message_error, void *context) {
  APP_LOG(APP_LOG_LEVEL_DEBUG, "App Message Sync Error: %d", app_message_error);
}

static void sync_tuple_changed_callback(const uint32_t key, const Tuple* new_tuple, const Tuple* old_tuple, void* context) {
  switch (key) {
  case HEART_RATE_KEY:
    // App Sync keeps the new_tuple around, so we may use it directly
    text_layer_set_text(s_data.hr_layer, new_tuple->value->cstring);
    break;
  default:
    return;
  }
}

static void window_load(Window *window) {
  Layer *window_layer = window_get_root_layer(window);

  s_data.header_layer = text_layer_create(GRect(0, 15, 144, 30));
  text_layer_set_text_alignment(s_data.header_layer, GTextAlignmentCenter);
  text_layer_set_text(s_data.header_layer, "Pat's Heart Rate");
  text_layer_set_font(s_data.header_layer, fonts_get_system_font(FONT_KEY_GOTHIC_24_BOLD));
  layer_add_child(window_layer, text_layer_get_layer(s_data.header_layer));

  s_data.hr_layer = text_layer_create(GRect(0, 65, 144, 100));
  text_layer_set_text_alignment(s_data.hr_layer, GTextAlignmentCenter);
  text_layer_set_text(s_data.hr_layer, "-");
  text_layer_set_font(s_data.hr_layer, fonts_get_system_font(FONT_KEY_BITHAM_42_BOLD));
  layer_add_child(window_layer, text_layer_get_layer(s_data.hr_layer));

  Tuplet initial_values[] = {
    TupletCString(HEART_RATE_KEY, "-"),
  };
  app_sync_init(&s_data.sync, s_data.sync_buffer, sizeof(s_data.sync_buffer), initial_values, ARRAY_LENGTH(initial_values),
                sync_tuple_changed_callback, sync_error_callback, NULL);
}

static void window_unload(Window *window) {
  app_sync_deinit(&s_data.sync);
  text_layer_destroy(s_data.header_layer);
  text_layer_destroy(s_data.hr_layer);
}

static void init() {
  s_data.window = window_create();
  //window_set_background_color(s_data.window, GColorBlack);
  window_set_fullscreen(s_data.window, true);
  window_set_window_handlers(s_data.window, (WindowHandlers) {
    .load = window_load,
    .unload = window_unload
  });

  const int inbound_size = 64;
  const int outbound_size = 16;
  app_message_open(inbound_size, outbound_size);

  const bool animated = true;
  window_stack_push(s_data.window, animated);
}

static void deinit() {
  window_destroy(s_data.window);
}

int main(void) {
  init();
  app_event_loop();
  deinit();
}
