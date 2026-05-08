#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlView* view;
  FlMethodChannel* channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Header bar button callbacks
static void on_headerbar_newtab(GtkButton* button, MyApplication* self) {
  if (self->channel == nullptr) return;
  g_autoptr(FlValue) args = fl_value_new_string("newTab");
  fl_method_channel_invoke_method(self->channel, "headerbar_action", args,
                                  nullptr, nullptr, nullptr);
}

static void on_headerbar_search(GtkButton* button, MyApplication* self) {
  if (self->channel == nullptr) return;
  g_autoptr(FlValue) args = fl_value_new_string("search");
  fl_method_channel_invoke_method(self->channel, "headerbar_action", args,
                                  nullptr, nullptr, nullptr);
}

static void on_headerbar_settings(GtkButton* button, MyApplication* self) {
  if (self->channel == nullptr) return;
  g_autoptr(FlValue) args = fl_value_new_string("settings");
  fl_method_channel_invoke_method(self->channel, "headerbar_action", args,
                                  nullptr, nullptr, nullptr);
}

static void on_headerbar_dictate(GtkButton* button, MyApplication* self) {
  if (self->channel == nullptr) return;
  g_autoptr(FlValue) args = fl_value_new_string("dictate");
  fl_method_channel_invoke_method(self->channel, "headerbar_action", args,
                                  nullptr, nullptr, nullptr);
}

// Context menu callbacks for terminal operations
static void on_menu_copy(GtkMenuItem* item, MyApplication* self) {
  if (self->channel == nullptr) return;
  g_autoptr(FlValue) args = fl_value_new_string("copy");
  fl_method_channel_invoke_method(self->channel, "headerbar_action", args,
                                  nullptr, nullptr, nullptr);
}

static void on_menu_paste(GtkMenuItem* item, MyApplication* self) {
  if (self->channel == nullptr) return;
  g_autoptr(FlValue) args = fl_value_new_string("paste");
  fl_method_channel_invoke_method(self->channel, "headerbar_action", args,
                                  nullptr, nullptr, nullptr);
}

static void on_menu_select_all(GtkMenuItem* item, MyApplication* self) {
  if (self->channel == nullptr) return;
  g_autoptr(FlValue) args = fl_value_new_string("selectAll");
  fl_method_channel_invoke_method(self->channel, "headerbar_action", args,
                                  nullptr, nullptr, nullptr);
}

static void add_menu_item(GtkWidget* menu, const gchar* label,
                          GCallback callback, MyApplication* self) {
  GtkWidget* item = gtk_menu_item_new_with_label(label);
  g_signal_connect(item, "activate", callback, self);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), item);
}

static gboolean on_btn_box_button_press(GtkWidget* widget,
                                        GdkEventButton* event,
                                        MyApplication* self) {
  if (event->button == 3 && self->channel != nullptr) {
    GtkWidget* menu = gtk_menu_new();
    add_menu_item(menu, "new tab", G_CALLBACK(on_headerbar_newtab), self);
    add_menu_item(menu, "copy", G_CALLBACK(on_menu_copy), self);
    add_menu_item(menu, "paste", G_CALLBACK(on_menu_paste), self);
    add_menu_item(menu, "select all", G_CALLBACK(on_menu_select_all), self);
    gtk_widget_show_all(menu);
    gtk_menu_popup_at_pointer(GTK_MENU(menu), (GdkEvent*)event);
    return TRUE;
  }
  return FALSE;
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    // Enable CSD on GNOME and Pantheon (Elementary OS)
    if (g_strcmp0(wm_name, "GNOME Shell") != 0 &&
        g_strcmp0(wm_name, "Mutter") != 0 &&
        g_strcmp0(wm_name, "Pantheon") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif

  GtkHeaderBar* header_bar = nullptr;
  if (use_header_bar) {
    header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Termisol");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Termisol");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  self->view = view;
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // Setup header bar action buttons and method channel on GNOME
  if (use_header_bar && header_bar != nullptr) {
    FlEngine* engine = fl_view_get_engine(self->view);
    if (engine != nullptr) {
      self->channel = fl_method_channel_new(
          fl_engine_get_binary_messenger(engine), "com.termisol/headerbar",
          FL_METHOD_CODEC(fl_standard_method_codec_new()));

      GtkWidget* btn_box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
      gtk_style_context_add_class(gtk_widget_get_style_context(btn_box),
                                  "linked");
      gtk_widget_add_events(btn_box, GDK_BUTTON_PRESS_MASK);
      g_signal_connect(btn_box, "button-press-event",
                       G_CALLBACK(on_btn_box_button_press), self);

      GtkWidget* newtab_btn =
          gtk_button_new_from_icon_name("tab-new-symbolic", GTK_ICON_SIZE_BUTTON);
      gtk_widget_set_tooltip_text(newtab_btn, "New Terminal");
      g_signal_connect(newtab_btn, "clicked",
                       G_CALLBACK(on_headerbar_newtab), self);
      gtk_box_pack_start(GTK_BOX(btn_box), newtab_btn, FALSE, FALSE, 0);

      GtkWidget* search_btn = gtk_button_new_from_icon_name(
          "system-search-symbolic", GTK_ICON_SIZE_BUTTON);
      gtk_widget_set_tooltip_text(search_btn, "Search");
      g_signal_connect(search_btn, "clicked",
                       G_CALLBACK(on_headerbar_search), self);
      gtk_box_pack_start(GTK_BOX(btn_box), search_btn, FALSE, FALSE, 0);

      GtkWidget* settings_btn = gtk_button_new_from_icon_name(
          "open-menu-symbolic", GTK_ICON_SIZE_BUTTON);
      gtk_widget_set_tooltip_text(settings_btn, "Settings");
      g_signal_connect(settings_btn, "clicked",
                       G_CALLBACK(on_headerbar_settings), self);
      gtk_box_pack_start(GTK_BOX(btn_box), settings_btn, FALSE, FALSE, 0);

      GtkWidget* dictate_btn = gtk_button_new_from_icon_name(
          "audio-input-microphone-symbolic", GTK_ICON_SIZE_BUTTON);
      gtk_widget_set_tooltip_text(dictate_btn, "Dictate");
      g_signal_connect(dictate_btn, "clicked",
                       G_CALLBACK(on_headerbar_dictate), self);
      gtk_box_pack_start(GTK_BOX(btn_box), dictate_btn, FALSE, FALSE, 0);

      gtk_header_bar_pack_end(GTK_HEADER_BAR(header_bar), btn_box);
      gtk_widget_show_all(btn_box);
    }
  }

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  if (self->channel != nullptr) {
    g_object_unref(self->channel);
    self->channel = nullptr;
  }
  if (self->view != nullptr) {
    self->view = nullptr;
  }
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->view = nullptr;
  self->channel = nullptr;
}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
