/// Relative text sizes follow GNOME's font settings, including text scaling.
enum NativeTypography {
    static let css = """
    .toastmonitor-window { background-color: @window_bg_color; }
    .toastmonitor-window .tm-heading { font-size: 1.1em; font-weight: 700; }
    .toastmonitor-window .tm-secondary { opacity: 0.72; font-weight: 400; }
    .toastmonitor-window .tm-value { font-weight: 600; font-feature-settings: "tnum"; }
    .toastmonitor-window .tm-stat-value { font-size: 2em; font-weight: 700; font-feature-settings: "tnum"; }
    .toastmonitor-window .tm-card { background-color: @view_bg_color; border-radius: 12px; }
    .toastmonitor-window .tm-segments { background-color: alpha(@window_fg_color, 0.07); border-radius: 7px; padding: 2px; }
    .toastmonitor-window .tm-segments button { padding: 5px 12px; min-height: 22px; border-radius: 5px; font-weight: 400; }
    .toastmonitor-window .tm-segments button:checked { background-color: @view_bg_color; box-shadow: 0 1px 3px alpha(black, 0.14); }
    .toastmonitor-window .tm-settings-tabs button { min-width: 104px; min-height: 76px; padding: 0; border-radius: 8px; }
    .toastmonitor-window .tm-settings-tabs button:checked { color: @accent_color; background-color: alpha(@window_fg_color, 0.06); }
    .toastmonitor-window .tm-settings-tabs image { -gtk-icon-size: 28px; }
    .toastmonitor-window preferencesgroup > box > box.header > box.labels > label.heading { font-size: 1.05em; font-weight: 700; }
    .toastmonitor-window row:not(.entry) label.title { font-weight: 400; }
    .toastmonitor-window .tm-dot { border-radius: 99px; }
    .toastmonitor-window .tm-color-0 { background-color: #7d9bff; }
    .toastmonitor-window .tm-color-1 { background-color: #d16e2b; }
    .toastmonitor-window .tm-color-2 { background-color: #52adc4; }
    .toastmonitor-window .tm-color-3 { background-color: #b052db; }
    .toastmonitor-window .tm-color-4 { background-color: #30b85e; }
    .toastmonitor-window .tm-color-5 { background-color: #5e6efd; }
    .toastmonitor-window .tm-share-0 progress { background-color: #7d9bff; }
    .toastmonitor-window .tm-share-1 progress { background-color: #d16e2b; }
    .toastmonitor-window .tm-share-2 progress { background-color: #52adc4; }
    .toastmonitor-window .tm-share-3 progress { background-color: #b052db; }
    .toastmonitor-window .tm-share-4 progress { background-color: #30b85e; }
    .toastmonitor-window .tm-share-5 progress { background-color: #5e6efd; }
    .toastmonitor-window .tm-table-heading { opacity: 0.72; font-size: 0.95em; }
    .toastmonitor-window .tm-session-icon { padding: 9px; border-radius: 9px; background-color: alpha(@accent_color, 0.12); color: @accent_color; }
    """
}
