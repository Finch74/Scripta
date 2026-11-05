#ifndef SCRIPTA_CGTK_SHIM_H
#define SCRIPTA_CGTK_SHIM_H

// The GUI targets GTK 4.6 (Ubuntu 22.04, the base of the swift:6.0 image). APIs such as
// GtkFileChooserNative and GtkMessageDialog are deprecated in later releases but still work.
#define GDK_DISABLE_DEPRECATION_WARNINGS
#include <gtk/gtk.h>

// GApplicationFlags is a flag enum from GLib 2.74 on, imported differently by Swift depending on the version.
static inline GApplicationFlags scripta_application_flags(void) {
    return G_APPLICATION_HANDLES_OPEN;
}

// Swift cannot call C variadic functions: these wrappers expose the few that ScriptaGTK needs.

static inline void scripta_object_set_string(gpointer object, const char *property, const char *value) {
    g_object_set(object, property, value, NULL);
}

static inline void scripta_object_set_int(gpointer object, const char *property, int value) {
    g_object_set(object, property, value, NULL);
}

static inline void scripta_object_set_double(gpointer object, const char *property, double value) {
    g_object_set(object, property, value, NULL);
}

static inline GtkWidget *scripta_message_dialog_new(GtkWindow *parent, GtkMessageType type, GtkButtonsType buttons,
                                                    const char *message, const char *detail) {
    GtkWidget *dialog = gtk_message_dialog_new(parent, GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
                                               type, buttons, "%s", message);
    if (detail != NULL) {
        gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(dialog), "%s", detail);
    }
    return dialog;
}

#endif
