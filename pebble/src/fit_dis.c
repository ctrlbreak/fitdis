#include "pebble_os.h"
#include "pebble_app.h"
#include "pebble_fonts.h"
#include <stdint.h>
#include <string.h>

#define MY_UUID { 0x51, 0x7B, 0xBE, 0x33, 0xFC, 0x34, 0x43, 0x10, 0x93, 0xAE, 0x04, 0xF6, 0x7C, 0x2B, 0xF5, 0xFD }
PBL_APP_INFO(MY_UUID,
             "Pebble Fit Dis", "Crazy Corporation",
             1, 0, /* App version */
             DEFAULT_MENU_ICON,
             APP_INFO_STANDARD_APP);

static struct FitDisData {
  Window window;
  TextLayer header_layer;
  TextLayer hr_layer;
//  BitmapLayer icon_layer;
//  uint32_t current_icon;
//  HeapBitmap icon_bitmap;
  AppSync sync;
  uint8_t sync_buffer[32];
} s_data;

enum {
  HEART_RATE_KEY = 0x0,         // TUPLE_CSTRING
};

// TODO: Error handling
static void sync_error_callback(DictionaryResult dict_error, AppMessageResult app_message_error, void *context) {
}

static void sync_tuple_changed_callback(const uint32_t key, const Tuple* new_tuple, const Tuple* old_tuple, void* context) {

  switch (key) {
  case HEART_RATE_KEY:
    // App Sync keeps the new_tuple around, so we may use it directly
    text_layer_set_text(&s_data.hr_layer, new_tuple->value->cstring);
    break;
  default:
    return;
  }
}

static void fitdis_app_init(AppContextRef ctx) {
  window_init(&s_data.window, "Main window");
  window_stack_push(&s_data.window, true /* Animated */);

  text_layer_init(&s_data.header_layer, GRect(0, 15, 144, 30));
  text_layer_set_text_alignment(&s_data.header_layer, GTextAlignmentCenter);
  text_layer_set_text(&s_data.header_layer, "Pat's Heart Rate");
  text_layer_set_font(&s_data.header_layer, fonts_get_system_font(FONT_KEY_GOTHIC_24_BOLD));
  layer_add_child(&s_data.window.layer, &s_data.header_layer.layer);

  text_layer_init(&s_data.hr_layer, GRect(0, 45, 144, 100));
  text_layer_set_text_alignment(&s_data.hr_layer, GTextAlignmentCenter);
  text_layer_set_text(&s_data.hr_layer, "-");
  text_layer_set_font(&s_data.hr_layer, fonts_get_system_font(FONT_KEY_BITHAM_42_BOLD));
  layer_add_child(&s_data.window.layer, &s_data.hr_layer.layer);

  Tuplet initial_values[] = {
    TupletCString(HEART_RATE_KEY, "-"),
  };
  app_sync_init(&s_data.sync, s_data.sync_buffer, sizeof(s_data.sync_buffer), initial_values, ARRAY_LENGTH(initial_values),
                sync_tuple_changed_callback, sync_error_callback, NULL);

}

static void fitdis_app_deinit(AppContextRef c) {
  app_sync_deinit(&s_data.sync);
}

void pbl_main(void *params) {
  PebbleAppHandlers handlers = {
    .init_handler = &fitdis_app_init,
    .deinit_handler = &fitdis_app_deinit,
    .messaging_info = {
      .buffer_sizes = {
        .inbound = 64,
        .outbound = 16,
      }
    }
  };
 app_event_loop(params, &handlers);
}
