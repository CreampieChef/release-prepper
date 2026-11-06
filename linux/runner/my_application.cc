#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// The size the window is created with when there is nothing recorded: the size
// the runner has always started with.
static const int kDefaultWidth = 1280;
static const int kDefaultHeight = 720;

// The format version this reader understands, which must stay equal to
// `schemaVersion` in `lib/feature/release/release.dart` — that is what writes
// the file. A file of a version this does not write is not read (`ai/doc.md`
// §7).
static const int kFormatVersion = 1;

// One token of the line. A token is a whole number or it is not one the app
// wrote, so "1440.5" is not read as 1440.
static gboolean parse_whole(const char* token, int* value) {
  char* end = nullptr;

  const long long parsed = g_ascii_strtoll(token, &end, 10);

  if (end == token || *end != '\0') {
    return FALSE;
  }

  *value = static_cast<int>(parsed);

  return TRUE;
}

// Reads the size the app recorded in the last run into width and height, and
// leaves them as they are when there is nothing to read: a file that is not
// there, cannot be read, is not three whole numbers, or is not the version the
// app writes. Nothing is reported for any of those, which is the same rule the
// app follows (`ai/doc.md` §7) — a size that cannot be read is not something
// the runner can show, and a run that starts at the default size is not an
// error.
//
// The file is read from the app data directory as `path_provider` resolves it:
// `XDG_DATA_HOME`, or `~/.local/share` when that is not set, plus the
// application id, which is what `g_get_user_data_dir` gives. path_provider's
// fallback to a directory named for the executable is not reproduced here, so
// such a directory is not read.
static void read_recorded_size(int* width, int* height) {
  g_autofree char* path = g_build_filename(
      g_get_user_data_dir(), APPLICATION_ID, "window_size.txt", nullptr);

  g_autofree char* contents = nullptr;
  gsize length = 0;

  if (!g_file_get_contents(path, &contents, &length, nullptr)) {
    return;
  }

  g_auto(GStrv) parts = g_strsplit_set(contents, " \t\r\n", -1);

  int values[3] = {0, 0, 0};
  int count = 0;

  for (char** part = parts; *part != nullptr; part++) {
    // An empty piece between two separators is not a token.
    if (**part == '\0') {
      continue;
    }

    int value;

    if (!parse_whole(*part, &value)) {
      return;
    }

    if (count < 3) {
      values[count] = value;
    }

    count++;
  }

  if (count != 3 || values[0] != kFormatVersion) {
    return;
  }

  // A window is never zero wide or zero tall, so a number outside that is not a
  // size the runner can use.
  if (values[1] <= 0 || values[2] <= 0) {
    return;
  }

  *width = values[1];
  *height = values[2];
}

// The app icon, resolved through the icon theme by the application id — the
// same name the .desktop file uses, which is what a desktop environment reads
// on Wayland, where a window has no icon of its own. This is what an X11
// session gets. An application id with no icon in the theme is reported rather
// than left as the default icon, so a build that did not install one is
// visible.
static void set_window_icon(GtkWindow* window) {
  GtkIconTheme* theme = gtk_icon_theme_get_default();

  if (!gtk_icon_theme_has_icon(theme, APPLICATION_ID)) {
    g_warning("App icon not found in the icon theme: %s", APPLICATION_ID);
    return;
  }

  gtk_window_set_icon_name(window, APPLICATION_ID);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "release_prepper");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "release_prepper");
  }

  // The size the window is created with is the one the app recorded in the last
  // run, or the default when there is nothing recorded. This is the only place
  // the size can be applied: the size a window is created with is what this
  // says, and a size asked for after the window exists is a request the desktop
  // may ignore, so an app that asked for it would show the user one window that
  // jumped (`ai/doc.md` §7).
  int width = kDefaultWidth;
  int height = kDefaultHeight;

  read_recorded_size(&width, &height);

  gtk_window_set_default_size(window, width, height);

  set_window_icon(window);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
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
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
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

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
