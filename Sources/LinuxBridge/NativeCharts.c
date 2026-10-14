#include "LinuxBridge.h"
#include <gtk/gtk.h>
#include <math.h>

typedef struct {
    int mode, count, series;
    double *values;
    int *colors;
    char **labels;
} Chart;

static const double palette[][3] = {
    {0.49,0.61,1}, {0.82,0.43,0.17}, {0.32,0.68,0.77},
    {0.69,0.32,0.86}, {0.19,0.72,0.37}, {0.37,0.43,0.99}
};
static void clear_chart(void *data) {
    Chart *c = data;
    g_free(c->values); g_free(c->colors); g_strfreev(c->labels); g_free(c);
}
static void color(cairo_t *cr, int index) {
    const double *rgb = palette[ABS(index) % 6];
    cairo_set_source_rgb(cr, rgb[0], rgb[1], rgb[2]);
}
static void text(GtkWidget *widget, cairo_t *cr, const char *value, double x, double y) {
    PangoLayout *layout = gtk_widget_create_pango_layout(widget, value);
    cairo_move_to(cr, x, y); pango_cairo_show_layout(cr, layout); g_object_unref(layout);
}
static void draw(GtkDrawingArea *area, cairo_t *cr, int w, int h, void *data) {
    Chart *c = data;
    GdkRGBA fg;
    gtk_widget_get_color(GTK_WIDGET(area), &fg);
    #define FG(a) cairo_set_source_rgba(cr, fg.red, fg.green, fg.blue, (a))
    if (c->mode == 1) {
        int weeks = (c->count + 6) / 7;
        if (!weeks) return;
        double gap = 3, left = 30, top = 24;
        double cell = fmin((w - left) / weeks - gap, (h - 50) / 7.0 - gap);
        double max = 1;
        for (int i = 0; i < c->count; i++) max = fmax(max, c->values[i]);
        FG(0.65); text(GTK_WIDGET(area), cr, "Mon", 0, top);
        text(GTK_WIDGET(area), cr, "Wed", 0, top + (cell + gap) * 2);
        text(GTK_WIDGET(area), cr, "Fri", 0, top + (cell + gap) * 4);
        text(GTK_WIDGET(area), cr, "Sun", 0, top + (cell + gap) * 6);
        for (int i = 0; i < c->count; i++) {
            int col = i / 7, row = i % 7;
            if (row == 0 && c->labels && c->labels[i] && *c->labels[i]) {
                FG(0.65); text(GTK_WIDGET(area), cr, c->labels[i], left + col * (cell + gap), 0);
            }
            if (c->values[i] <= 0) FG(0.07);
            else cairo_set_source_rgba(cr, 0.82, 0.43, 0.25, 0.28 + 0.72 * sqrt(c->values[i] / max));
            cairo_rectangle(cr, left + col * (cell + gap), top + row * (cell + gap), cell, cell);
            cairo_fill(cr);
        }
        FG(0.65); text(GTK_WIDGET(area), cr, "Less", w - 145, h - 20);
        for (int i = 0; i < 5; i++) {
            cairo_set_source_rgba(cr, 0.82, 0.43, 0.25, 0.15 + i * 0.2);
            cairo_rectangle(cr, w - 110 + i * 12, h - 17, 9, 9); cairo_fill(cr);
        }
        FG(0.65); text(GTK_WIDGET(area), cr, "More", w - 45, h - 20);
        return;
    }
    if (c->mode == 2) {
        double sum = 0, x = 0;
        for (int i = 0; i < c->count; i++) sum += c->values[i];
        if (sum <= 0) { FG(0.07); cairo_rectangle(cr, 0, 0, w, h); cairo_fill(cr); return; }
        for (int i = 0; i < c->count; i++) {
            double width = w * c->values[i] / sum;
            color(cr, c->colors[i]); cairo_rectangle(cr, x, 0, width, h); cairo_fill(cr); x += width;
        }
        return;
    }
    int series = MAX(1, c->series), days = c->count / series;
    double max = 1, left = 58, top = 12, bottom = h - 30, width = w - left;
    for (int day = 0; day < days; day++) {
        double sum = 0;
        for (int s = 0; s < series; s++) sum += c->values[day * series + s];
        max = fmax(max, sum);
    }
    max *= 1.1;
    for (int i = 0; i < 4; i++) {
        double y = top + (bottom - top) * i / 3.0;
        FG(0.09); cairo_set_line_width(cr, 1); cairo_move_to(cr, left, y); cairo_line_to(cr, w, y); cairo_stroke(cr);
        double n = max * (3 - i) / 3;
        char buf[32];
        if (c->mode == 3) g_snprintf(buf, sizeof buf, "$%.2f", n);
        else if (n >= 1e9) g_snprintf(buf, sizeof buf, "%.1fB", n/1e9);
        else if (n >= 1e6) g_snprintf(buf, sizeof buf, "%.1fM", n/1e6);
        else if (n >= 1000) g_snprintf(buf, sizeof buf, "%.0fk", n/1000);
        else g_snprintf(buf, sizeof buf, "%.0f", n);
        FG(0.65); text(GTK_WIDGET(area), cr, buf, 0, y - 6);
    }
    for (int d = 0; d < days; d++) {
        double x = left + width * d / days, y = bottom;
        for (int s = 0; s < series; s++) {
            int index = d * series + s;
            double height = (bottom - top) * c->values[index] / max;
            color(cr, c->colors[index]);
            cairo_rectangle(cr, x + 2, y - height, fmax(1, width / days - 5), height); cairo_fill(cr); y -= height;
        }
        if (d % MAX(1, days / 6) == 0 && c->labels && c->labels[d]) {
            FG(0.65); text(GTK_WIDGET(area), cr, c->labels[d], x, bottom + 8);
        }
    }
    #undef FG
}
void *tm_chart_new(void) {
    GtkWidget *widget = gtk_drawing_area_new();
    Chart *chart = g_new0(Chart, 1);
    g_object_set_data_full(G_OBJECT(widget), "tm-chart", chart, clear_chart);
    gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(widget), draw, chart, NULL);
    gtk_widget_set_hexpand(widget, TRUE);
    return widget;
}
void tm_chart_update(void *widget, int mode, const double *values, int count, int series,
                     const int *colors, const char *labels, const char *summary) {
    Chart *c = g_object_get_data(G_OBJECT(widget), "tm-chart");
    g_free(c->values); g_free(c->colors); g_strfreev(c->labels);
    c->mode = mode; c->count = count; c->series = series;
    c->values = g_memdup2(values, count * sizeof(double));
    c->colors = g_memdup2(colors, count * sizeof(int));
    c->labels = g_strsplit(labels, "\n", -1);
    gtk_widget_set_tooltip_text(GTK_WIDGET(widget), summary);
    gtk_accessible_update_property(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_PROPERTY_LABEL, summary, -1);
    gtk_widget_queue_draw(GTK_WIDGET(widget));
}
