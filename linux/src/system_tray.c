#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libappindicator/app-indicator.h>
#include <gtk/gtk.h>

typedef struct {
    AppIndicator *indicator;
    GtkWidget *menu;
    char *icon_path;
} TrayData;

static TrayData tray_data = {0};

// Callback functions for menu items
static void on_new_terminal(GtkWidget *widget, gpointer data) {
    // Send message to Flutter via method channel
    system("echo 'new_terminal' > /tmp/termisol_tray_action");
}

static void on_show_window(GtkWidget *widget, gpointer data) {
    system("echo 'show_window' > /tmp/termisol_tray_action");
}

static void on_preferences(GtkWidget *widget, gpointer data) {
    system("echo 'preferences' > /tmp/termisol_tray_action");
}

static void on_quit(GtkWidget *widget, gpointer data) {
    system("echo 'quit' > /tmp/termisol_tray_action");
    gtk_main_quit();
}

int setup_linux_tray(const char *icon_path, const char *tooltip) {
    gtk_init(NULL, NULL);
    
    // Create menu
    tray_data.menu = gtk_menu_new();
    
    // Create menu items
    GtkWidget *new_terminal = gtk_menu_item_new_with_label("New Terminal");
    GtkWidget *show_window = gtk_menu_item_new_with_label("Show Window");
    GtkWidget *preferences = gtk_menu_item_new_with_label("Preferences");
    GtkWidget *separator = gtk_separator_menu_item_new();
    GtkWidget *quit = gtk_menu_item_new_with_label("Quit");
    
    // Add items to menu
    gtk_menu_shell_append(GTK_MENU_SHELL(tray_data.menu), new_terminal);
    gtk_menu_shell_append(GTK_MENU_SHELL(tray_data.menu), show_window);
    gtk_menu_shell_append(GTK_MENU_SHELL(tray_data.menu), preferences);
    gtk_menu_shell_append(GTK_MENU_SHELL(tray_data.menu), separator);
    gtk_menu_shell_append(GTK_MENU_SHELL(tray_data.menu), quit);
    
    // Connect signals
    g_signal_connect(new_terminal, "activate", G_CALLBACK(on_new_terminal), NULL);
    g_signal_connect(show_window, "activate", G_CALLBACK(on_show_window), NULL);
    g_signal_connect(preferences, "activate", G_CALLBACK(on_preferences), NULL);
    g_signal_connect(quit, "activate", G_CALLBACK(on_quit), NULL);
    
    // Show menu items
    gtk_widget_show_all(new_terminal);
    gtk_widget_show_all(show_window);
    gtk_widget_show_all(preferences);
    gtk_widget_show_all(separator);
    gtk_widget_show_all(quit);
    
    // Create app indicator
    tray_data.indicator = app_indicator_new(
        "termisol",
        icon_path ? icon_path : "terminal",
        APP_INDICATOR_CATEGORY_APPLICATION_STATUS
    );
    
    app_indicator_set_status(tray_data.indicator, APP_INDICATOR_STATUS_ACTIVE);
    app_indicator_set_menu(tray_data.indicator, GTK_MENU(tray_data.menu));
    app_indicator_set_title(tray_data.indicator, tooltip ? tooltip : "Termisol Terminal");
    
    return 0;
}

void cleanup_linux_tray() {
    if (tray_data.indicator) {
        g_object_unref(G_OBJECT(tray_data.indicator));
        tray_data.indicator = NULL;
    }
    
    if (tray_data.menu) {
        gtk_widget_destroy(tray_data.menu);
        tray_data.menu = NULL;
    }
}

void run_tray_loop() {
    gtk_main();
}