/// Relative sizes preserve the desktop font and text scaling. Scope every rule
/// to our content so native controls, dialogs and navigation keep their styles.
enum NativeTypography {
    static let css = """
    .toastmonitor-window .tm-page-title {
        font-size: 1.75em;
        font-weight: 800;
    }
    .toastmonitor-window preferencesgroup > box > box.header > box.labels > label.heading {
        font-size: 1.23em;
        font-weight: 700;
    }
    .toastmonitor-window row:not(.entry) label.title {
        font-weight: 600;
        color: alpha(@window_fg_color, 0.9);
    }
    .toastmonitor-window row label.subtitle,
    .toastmonitor-window preferencesgroup > box > box.header > box.labels > label.dim-label,
    .toastmonitor-window .tm-secondary {
        font-size: 0.95em;
        font-weight: 400;
        opacity: 0.8;
    }
    .toastmonitor-window .tm-control-label {
        font-size: 1em;
        font-weight: 600;
        color: alpha(@window_fg_color, 0.85);
    }
    .toastmonitor-window .tm-value {
        font-size: 1.1em;
        font-weight: 700;
        font-feature-settings: "tnum";
    }
    """
}
