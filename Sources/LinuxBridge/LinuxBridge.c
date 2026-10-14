#include "LinuxBridge.h"
#include <gtk/gtk.h>
#include <gio/gio.h>
#include <libsecret/secret.h>
#include <unistd.h>
#include <string.h>

static const SecretSchema schema = {
    "io.github.yeyebbc.ToastMonitor", SECRET_SCHEMA_NONE,
    {{"account", SECRET_SCHEMA_ATTRIBUTE_STRING}, {NULL, 0}}
};
static _Thread_local int secret_failed;
char *tm_secret_get(const char *account) {
    GError *error = NULL;
    char *value = secret_password_lookup_sync(&schema, NULL, &error, "account", account, NULL);
    secret_failed = error != NULL;
    g_clear_error(&error);
    return value;
}
int tm_secret_set(const char *account, const char *value) {
    GError *error = NULL;
    int ok = secret_password_store_sync(&schema, SECRET_COLLECTION_DEFAULT, "ToastMonitor",
                                       value, NULL, &error, "account", account, NULL);
    secret_failed = !ok;
    g_clear_error(&error);
    return ok;
}
int tm_secret_delete(const char *account) {
    GError *error = NULL;
    int ok = secret_password_clear_sync(&schema, NULL, &error, "account", account, NULL);
    secret_failed = error != NULL;
    g_clear_error(&error);
    return ok;
}
int tm_secret_failed(void) { return secret_failed; }
void tm_secret_free(char *value) { secret_password_free(value); }
void tm_window_hide(void *window) { gtk_widget_set_visible(GTK_WIDGET(window), FALSE); }
void *tm_main_window(void) {
    GtkApplication *app = GTK_APPLICATION(g_application_get_default());
    GList *windows = gtk_application_get_windows(app);
    return windows ? windows->data : NULL;
}
static gboolean hide_on_close(GtkWindow *window, void *data) {
    gtk_widget_set_visible(GTK_WIDGET(window), FALSE);
    return TRUE;
}
void tm_window_keep_alive(void *window) {
    g_signal_connect(window, "close-request", G_CALLBACK(hide_on_close), NULL);
}
void tm_window_present(void *window) { gtk_window_present(GTK_WINDOW(window)); }
int tm_window_visible(void *window) { return gtk_widget_get_visible(GTK_WIDGET(window)); }
int tm_window_capture(void *window, const char *path) {
    GtkWidget *widget = GTK_WIDGET(window);
    int width = gtk_widget_get_width(widget), height = gtk_widget_get_height(widget);
    if (width <= 0 || height <= 0) return 0;
    GdkPaintable *paintable = gtk_widget_paintable_new(widget);
    GtkSnapshot *snapshot = gtk_snapshot_new();
    gdk_paintable_snapshot(paintable, GDK_SNAPSHOT(snapshot), width, height);
    GskRenderNode *node = gtk_snapshot_free_to_node(snapshot);
    g_object_unref(paintable);
    if (!node) return 0;
    GskRenderer *renderer = gtk_native_get_renderer(GTK_NATIVE(window));
    GdkTexture *texture = gsk_renderer_render_texture(renderer, node, NULL);
    int ok = gdk_texture_save_to_png(texture, path);
    g_object_unref(texture);
    gsk_render_node_unref(node);
    return ok;
}
void tm_app_hold(void) { g_application_hold(g_application_get_default()); }
void tm_app_release(void) { g_application_release(g_application_get_default()); }

static GDBusConnection *bus;
static GDBusNodeInfo *item_info, *menu_info;
static guint item_id, menu_id, name_id, watch_id, tick_id;
static guint32 menu_revision = 1;
static TMAction action_callback;
static TMTick tick_callback;
static char *current_label, *current_tooltip;
static const char *tray_icon_name = "toastmonitor-token-symbolic";
static char *tray_icon_theme_path;
static GDBusNodeInfo *panel_info;
static guint panel_id, panel_owner_watch;
static char *panel_snapshot, *panel_owner;

static const char *panel_xml =
"<node><interface name='io.github.yeyebbc.ToastMonitor.Panel'>"
"<property name='Snapshot' type='s' access='read'/>"
"<method name='Open'><arg name='page' type='s' direction='in'/></method>"
"<method name='Refresh'/>"
"<method name='SetPanelActive'><arg name='active' type='b' direction='in'/></method>"
"<method name='SetExpanded'><arg name='expanded' type='b' direction='in'/></method>"
"<signal name='SnapshotChanged'><arg name='snapshot' type='s'/></signal>"
"</interface></node>";

static void panel_status_changed(void) {
    if (bus && item_id)
        g_dbus_connection_emit_signal(bus, NULL, "/StatusNotifierItem", "org.kde.StatusNotifierItem", "NewStatus",
                                      g_variant_new("(s)", panel_owner ? "Passive" : "Active"), NULL);
}
static void panel_release(void) {
    if (panel_owner_watch) g_bus_unwatch_name(panel_owner_watch);
    panel_owner_watch = 0;
    g_clear_pointer(&panel_owner, g_free);
    if (action_callback) action_callback(8);
    panel_status_changed();
}
static void panel_owner_vanished(GDBusConnection *connection, const char *name, void *data) {
    panel_release();
}
static void panel_method(GDBusConnection *connection, const char *sender, const char *path,
                         const char *interface, const char *method, GVariant *parameters,
                         GDBusMethodInvocation *invocation, void *data) {
    if (!strcmp(method, "Open")) {
        const char *page;
        g_variant_get(parameters, "(&s)", &page);
        const char *pages[] = {"Overview", "Sessions", "Preferences", "", "", "Analysis", "Plans"};
        int action = -1;
        for (gsize i = 0; i < G_N_ELEMENTS(pages); i++)
            if (*pages[i] && !strcmp(page, pages[i])) { action = (int)i; break; }
        if (action < 0) {
            g_dbus_method_invocation_return_error_literal(invocation, G_DBUS_ERROR, G_DBUS_ERROR_INVALID_ARGS, "Unknown page");
            return;
        }
        if (action_callback) action_callback(action);
    } else if (!strcmp(method, "Refresh")) {
        if (action_callback) action_callback(3);
    } else if (!strcmp(method, "SetPanelActive")) {
        gboolean active;
        g_variant_get(parameters, "(b)", &active);
        if (active && g_strcmp0(panel_owner, sender)) {
            panel_release();
            panel_owner = g_strdup(sender);
            panel_owner_watch = g_bus_watch_name_on_connection(bus, sender, G_BUS_NAME_WATCHER_FLAGS_NONE,
                                                              NULL, panel_owner_vanished, NULL, NULL);
            panel_status_changed();
        } else if (!active && !g_strcmp0(panel_owner, sender)) {
            panel_release();
        }
    } else if (!strcmp(method, "SetExpanded")) {
        gboolean expanded;
        g_variant_get(parameters, "(b)", &expanded);
        if (!g_strcmp0(panel_owner, sender) && action_callback) action_callback(expanded ? 7 : 8);
    }
    g_dbus_method_invocation_return_value(invocation, NULL);
}
static GVariant *panel_property(GDBusConnection *connection, const char *sender, const char *path,
                                const char *interface, const char *property, GError **error, void *data) {
    return g_variant_new_string(panel_snapshot ? panel_snapshot : "{\"version\":1,\"ready\":false}");
}
static const GDBusInterfaceVTable panel_vtable = {panel_method, panel_property, NULL};

void tm_panel_update(const char *snapshot_json) {
    if (!g_strcmp0(panel_snapshot, snapshot_json)) return;
    g_free(panel_snapshot);
    panel_snapshot = g_strdup(snapshot_json);
    if (!bus || !panel_id) return;
    g_dbus_connection_emit_signal(bus, NULL, "/io/github/yeyebbc/ToastMonitor/Panel", "io.github.yeyebbc.ToastMonitor.Panel",
                                  "SnapshotChanged", g_variant_new("(s)", snapshot_json), NULL);
    GVariantBuilder changed;
    g_variant_builder_init(&changed, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(&changed, "{sv}", "Snapshot", g_variant_new_string(snapshot_json));
    g_dbus_connection_emit_signal(bus, NULL, "/io/github/yeyebbc/ToastMonitor/Panel", "org.freedesktop.DBus.Properties",
                                  "PropertiesChanged", g_variant_new("(sa{sv}as)", "io.github.yeyebbc.ToastMonitor.Panel", &changed, NULL), NULL);
}

static char *find_tray_icon_path(void) {
    // Resolve from the executable, so archives work without installation and
    // installed apps do not depend on the desktop launcher's working directory.
    char *executable = g_file_read_link("/proc/self/exe", NULL);
    if (!executable) return g_strdup("");
    char *directory = g_path_get_dirname(executable);
    g_free(executable);
    for (int depth = 0; depth < 6; depth++) {
        const char *roots[] = {"share/icons", "data/icons"};
        for (gsize i = 0; i < G_N_ELEMENTS(roots); i++) {
            char *path = g_build_filename(directory, roots[i], "hicolor", "scalable", "status", NULL);
            char *icon = g_strdup_printf("%s/%s.svg", path, tray_icon_name);
            gboolean found = g_file_test(icon, G_FILE_TEST_IS_REGULAR);
            g_free(icon);
            if (found) { g_free(directory); return path; }
            g_free(path);
        }
        char *parent = g_path_get_dirname(directory);
        gboolean at_root = !strcmp(parent, directory);
        g_free(directory);
        directory = parent;
        if (at_root) break;
    }
    g_free(directory);
    return g_strdup(""); // Let the host look in its standard icon theme paths.
}
static const char *item_xml =
"<node><interface name='org.kde.StatusNotifierItem'>"
"<method name='Activate'><arg type='i' direction='in'/><arg type='i' direction='in'/></method>"
"<method name='SecondaryActivate'><arg type='i' direction='in'/><arg type='i' direction='in'/></method>"
"<method name='ContextMenu'><arg type='i' direction='in'/><arg type='i' direction='in'/></method>"
"<method name='Scroll'><arg type='i' direction='in'/><arg type='s' direction='in'/></method>"
"<property name='Category' type='s' access='read'/><property name='Id' type='s' access='read'/>"
"<property name='Title' type='s' access='read'/><property name='Status' type='s' access='read'/>"
"<property name='WindowId' type='i' access='read'/><property name='IconName' type='s' access='read'/>"
"<property name='IconThemePath' type='s' access='read'/>"
"<property name='IconPixmap' type='a(iiay)' access='read'/><property name='OverlayIconName' type='s' access='read'/>"
"<property name='OverlayIconPixmap' type='a(iiay)' access='read'/><property name='AttentionIconName' type='s' access='read'/>"
"<property name='AttentionIconPixmap' type='a(iiay)' access='read'/><property name='AttentionMovieName' type='s' access='read'/>"
"<property name='ToolTip' type='(sa(iiay)ss)' access='read'/><property name='ItemIsMenu' type='b' access='read'/>"
"<property name='Menu' type='o' access='read'/><property name='XAyatanaLabel' type='s' access='read'/>"
"<property name='XAyatanaLabelGuide' type='s' access='read'/>"
"<signal name='NewTitle'/><signal name='NewToolTip'/><signal name='NewIcon'/>"
"<signal name='NewStatus'><arg type='s'/></signal>"
"<signal name='XAyatanaNewLabel'><arg type='s'/><arg type='s'/></signal>"
"</interface></node>";
static const char *menu_xml =
"<node><interface name='com.canonical.dbusmenu'>"
"<method name='GetLayout'><arg type='i' direction='in'/><arg type='i' direction='in'/><arg type='as' direction='in'/>"
"<arg type='u' direction='out'/><arg type='(ia{sv}av)' direction='out'/></method>"
"<method name='GetGroupProperties'><arg type='ai' direction='in'/><arg type='as' direction='in'/><arg type='a(ia{sv})' direction='out'/></method>"
"<method name='GetProperty'><arg type='i' direction='in'/><arg type='s' direction='in'/><arg type='v' direction='out'/></method>"
"<method name='Event'><arg type='i' direction='in'/><arg type='s' direction='in'/><arg type='v' direction='in'/><arg type='u' direction='in'/></method>"
"<method name='EventGroup'><arg type='a(isvu)' direction='in'/><arg type='ai' direction='out'/></method>"
"<method name='AboutToShow'><arg type='i' direction='in'/><arg type='b' direction='out'/></method>"
"<method name='AboutToShowGroup'><arg type='ai' direction='in'/><arg type='ai' direction='out'/><arg type='ai' direction='out'/></method>"
"<property name='Version' type='u' access='read'/><property name='TextDirection' type='s' access='read'/>"
"<property name='Status' type='s' access='read'/><property name='IconThemePath' type='as' access='read'/>"
"<signal name='LayoutUpdated'><arg type='u'/><arg type='i'/></signal>"
"</interface></node>";

static const char *menu_label(int id) {
    switch (id) {
        case 1: return current_label ? current_label : "Collecting usage…";
        case 2: return "Overview";
        case 3: return "Sessions";
        case 4: return "Preferences";
        case 5: return "Refresh Now";
        case 6: return "Quit ToastMonitor";
        default: return "";
    }
}
static GVariant *menu_properties(int id) {
    GVariantBuilder props;
    g_variant_builder_init(&props, G_VARIANT_TYPE("a{sv}"));
    if (id == 0) {
        g_variant_builder_add(&props, "{sv}", "children-display", g_variant_new_string("submenu"));
    } else {
        g_variant_builder_add(&props, "{sv}", "label", g_variant_new_string(menu_label(id)));
        g_variant_builder_add(&props, "{sv}", "enabled", g_variant_new_boolean(id != 1));
        g_variant_builder_add(&props, "{sv}", "visible", g_variant_new_boolean(TRUE));
    }
    return g_variant_builder_end(&props);
}
static GVariant *menu_layout(int id, int depth) {
    GVariantBuilder children;
    g_variant_builder_init(&children, G_VARIANT_TYPE("av"));
    if (id == 0 && depth != 0) {
        for (int child = 1; child <= 6; child++)
            g_variant_builder_add(&children, "v", menu_layout(child, 0));
    }
    return g_variant_new("(i@a{sv}@av)", id, menu_properties(id), g_variant_builder_end(&children));
}
static void menu_event(GVariant *event) {
    gint32 id;
    const char *name;
    GVariant *data;
    guint32 timestamp;
    g_variant_get(event, "(i&s@vu)", &id, &name, &data, &timestamp);
    if (strcmp(name, "clicked") == 0 && id >= 2 && id <= 6 && action_callback)
        action_callback(id - 2);
    g_variant_unref(data);
}
static void item_method(GDBusConnection *connection, const char *sender, const char *path,
                        const char *interface, const char *method, GVariant *parameters,
                        GDBusMethodInvocation *invocation, void *data) {
    if (strcmp(method, "Activate") == 0 && action_callback) action_callback(0);
    if (strcmp(method, "SecondaryActivate") == 0 && action_callback) action_callback(2);
    g_dbus_method_invocation_return_value(invocation, NULL);
}
static GVariant *item_property(GDBusConnection *connection, const char *sender, const char *path,
                               const char *interface, const char *property, GError **error, void *data) {
    if (!strcmp(property, "Category")) return g_variant_new_string("ApplicationStatus");
    if (!strcmp(property, "Id")) return g_variant_new_string("ToastMonitor");
    if (!strcmp(property, "Title")) return g_variant_new_string(current_label ? current_label : "ToastMonitor");
    if (!strcmp(property, "Status")) return g_variant_new_string(panel_owner ? "Passive" : "Active");
    if (!strcmp(property, "WindowId")) return g_variant_new_int32(0);
    if (!strcmp(property, "IconName")) return g_variant_new_string(tray_icon_name);
    if (!strcmp(property, "IconThemePath")) return g_variant_new_string(tray_icon_theme_path ? tray_icon_theme_path : "");
    if (g_str_has_suffix(property, "Pixmap")) return g_variant_new_array(G_VARIANT_TYPE("(iiay)"), NULL, 0);
    if (!strcmp(property, "ToolTip"))
        return g_variant_new("(s@a(iiay)ss)", tray_icon_name,
                             g_variant_new_array(G_VARIANT_TYPE("(iiay)"), NULL, 0),
                             "ToastMonitor", current_tooltip ? current_tooltip : "Collecting usage…");
    if (!strcmp(property, "ItemIsMenu")) return g_variant_new_boolean(FALSE);
    if (!strcmp(property, "Menu")) return g_variant_new_object_path("/MenuBar");
    if (!strcmp(property, "XAyatanaLabel")) return g_variant_new_string(current_label ? current_label : "");
    if (!strcmp(property, "XAyatanaLabelGuide")) return g_variant_new_string("999.9M");
    return g_variant_new_string("");
}
static void menu_method(GDBusConnection *connection, const char *sender, const char *path,
                        const char *interface, const char *method, GVariant *parameters,
                        GDBusMethodInvocation *invocation, void *data) {
    GVariant *result = NULL;
    if (!strcmp(method, "GetLayout")) {
        gint32 parent, depth;
        g_variant_get_child(parameters, 0, "i", &parent);
        g_variant_get_child(parameters, 1, "i", &depth);
        result = g_variant_new("(u@(ia{sv}av))", menu_revision, menu_layout(parent, depth));
    } else if (!strcmp(method, "AboutToShow")) {
        result = g_variant_new("(b)", FALSE);
    } else if (!strcmp(method, "AboutToShowGroup")) {
        result = g_variant_new("(@ai@ai)", g_variant_new_array(G_VARIANT_TYPE_INT32, NULL, 0),
                               g_variant_new_array(G_VARIANT_TYPE_INT32, NULL, 0));
    } else if (!strcmp(method, "Event")) {
        menu_event(parameters);
    } else if (!strcmp(method, "EventGroup")) {
        GVariant *events = g_variant_get_child_value(parameters, 0);
        for (gsize i = 0; i < g_variant_n_children(events); i++) {
            GVariant *event = g_variant_get_child_value(events, i);
            menu_event(event);
            g_variant_unref(event);
        }
        g_variant_unref(events);
        result = g_variant_new("(@ai)", g_variant_new_array(G_VARIANT_TYPE_INT32, NULL, 0));
    } else if (!strcmp(method, "GetGroupProperties")) {
        GVariantBuilder rows;
        g_variant_builder_init(&rows, G_VARIANT_TYPE("a(ia{sv})"));
        GVariant *ids = g_variant_get_child_value(parameters, 0);
        for (gsize i = 0; i < g_variant_n_children(ids); i++) {
            gint32 id;
            g_variant_get_child(ids, i, "i", &id);
            g_variant_builder_add(&rows, "(i@a{sv})", id, menu_properties(id));
        }
        g_variant_unref(ids);
        result = g_variant_new("(@a(ia{sv}))", g_variant_builder_end(&rows));
    } else if (!strcmp(method, "GetProperty")) {
        gint32 id;
        const char *name;
        g_variant_get(parameters, "(i&s)", &id, &name);
        GVariant *props = g_variant_ref_sink(menu_properties(id));
        GVariant *value = g_variant_lookup_value(props, name, NULL);
        if (value) { result = g_variant_new("(v)", value); g_variant_unref(value); }
        g_variant_unref(props);
        if (!result) {
            g_dbus_method_invocation_return_dbus_error(invocation, "com.canonical.dbusmenu.Error.UnknownProperty", "Unknown property");
            return;
        }
    }
    g_dbus_method_invocation_return_value(invocation, result);
}
static GVariant *menu_property(GDBusConnection *connection, const char *sender, const char *path,
                               const char *interface, const char *property, GError **error, void *data) {
    if (!strcmp(property, "Version")) return g_variant_new_uint32(3);
    if (!strcmp(property, "TextDirection")) return g_variant_new_string("ltr");
    if (!strcmp(property, "Status")) return g_variant_new_string("normal");
    return g_variant_new_strv(NULL, 0);
}
static const GDBusInterfaceVTable item_vtable = {item_method, item_property, NULL};
static const GDBusInterfaceVTable menu_vtable = {menu_method, menu_property, NULL};
static gboolean tick(void *data) { if (tick_callback) tick_callback(); return G_SOURCE_CONTINUE; }
static void watcher_appeared(GDBusConnection *connection, const char *name, const char *owner, void *data) {
    // Register by unique bus name. Re-register whenever the shell/extension restarts.
    g_dbus_connection_call(connection, name, "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher",
                           "RegisterStatusNotifierItem", g_variant_new("(s)", g_dbus_connection_get_unique_name(connection)),
                           NULL, G_DBUS_CALL_FLAGS_NONE, 5000, NULL, NULL, NULL);
}
int tm_tray_start(TMAction action, TMTick tick_fn) {
    tray_icon_theme_path = find_tray_icon_path();
    action_callback = action;
    tick_callback = tick_fn;
    tick_id = g_timeout_add(200, tick, NULL);
    GError *error = NULL;
    bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (!bus) { g_clear_error(&error); return 0; }
    item_info = g_dbus_node_info_new_for_xml(item_xml, &error);
    menu_info = g_dbus_node_info_new_for_xml(menu_xml, &error);
    if (!item_info || !menu_info) { g_clear_error(&error); return 0; }
    item_id = g_dbus_connection_register_object(bus, "/StatusNotifierItem", item_info->interfaces[0], &item_vtable, NULL, NULL, &error);
    menu_id = g_dbus_connection_register_object(bus, "/MenuBar", menu_info->interfaces[0], &menu_vtable, NULL, NULL, &error);
    g_clear_error(&error);
    panel_info = g_dbus_node_info_new_for_xml(panel_xml, NULL);
    if (panel_info)
        panel_id = g_dbus_connection_register_object(bus, "/io/github/yeyebbc/ToastMonitor/Panel", panel_info->interfaces[0],
                                                     &panel_vtable, NULL, NULL, NULL);
    char *name = g_strdup_printf("org.kde.StatusNotifierItem-%d-1", getpid());
    name_id = g_bus_own_name_on_connection(bus, name, G_BUS_NAME_OWNER_FLAGS_NONE, NULL, NULL, NULL, NULL);
    g_free(name);
    watch_id = g_bus_watch_name_on_connection(bus, "org.kde.StatusNotifierWatcher", G_BUS_NAME_WATCHER_FLAGS_NONE,
                                             watcher_appeared, NULL, NULL, NULL);
    return item_id && menu_id;
}
void tm_tray_update(const char *label, const char *tooltip) {
    if (g_strcmp0(current_label, label) == 0 && g_strcmp0(current_tooltip, tooltip) == 0) return;
    g_free(current_label); current_label = g_strdup(label);
    g_free(current_tooltip); current_tooltip = g_strdup(tooltip);
    if (!bus || !item_id) return;
    g_dbus_connection_emit_signal(bus, NULL, "/StatusNotifierItem", "org.kde.StatusNotifierItem", "NewTitle", NULL, NULL);
    g_dbus_connection_emit_signal(bus, NULL, "/StatusNotifierItem", "org.kde.StatusNotifierItem", "NewToolTip", NULL, NULL);
    g_dbus_connection_emit_signal(bus, NULL, "/StatusNotifierItem", "org.kde.StatusNotifierItem", "XAyatanaNewLabel",
                                  g_variant_new("(ss)", label, "999.9M"), NULL);
    menu_revision++;
    g_dbus_connection_emit_signal(bus, NULL, "/MenuBar", "com.canonical.dbusmenu", "LayoutUpdated", g_variant_new("(ui)", menu_revision, 0), NULL);
}
void tm_tray_stop(void) {
    panel_release();
    if (tick_id) g_source_remove(tick_id);
    if (watch_id) g_bus_unwatch_name(watch_id);
    if (name_id) g_bus_unown_name(name_id);
    if (bus && item_id) g_dbus_connection_unregister_object(bus, item_id);
    if (bus && menu_id) g_dbus_connection_unregister_object(bus, menu_id);
    if (bus && panel_id) g_dbus_connection_unregister_object(bus, panel_id);
    g_clear_pointer(&panel_info, g_dbus_node_info_unref);
    g_clear_pointer(&panel_snapshot, g_free);
    panel_id = 0;
    g_clear_pointer(&item_info, g_dbus_node_info_unref);
    g_clear_pointer(&menu_info, g_dbus_node_info_unref);
    g_clear_object(&bus);
    g_clear_pointer(&current_label, g_free);
    g_clear_pointer(&current_tooltip, g_free);
    g_clear_pointer(&tray_icon_theme_path, g_free);
    tick_id = watch_id = name_id = item_id = menu_id = 0;
}
