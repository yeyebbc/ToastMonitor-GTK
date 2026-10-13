import Adwaita
import CAdw

extension HStack {
    /// Set spacing on the underlying GtkBox, independently of child margins.
    func spacing(_ points: Int) -> AnyView {
        inspect { storage, _ in
            gtk_box_set_spacing(storage.opaquePointer?.cast(), Int32(points))
        }
    }
}

extension ForEach {
    func spacing(_ points: Int) -> AnyView {
        inspect { storage, _ in
            gtk_box_set_spacing(storage.opaquePointer?.cast(), Int32(points))
        }
    }
}

extension ScrollView {
    /// Keep navigation at its natural height while allowing horizontal scrolling.
    func horizontalNavigation() -> AnyView {
        propagateNaturalHeight().inspect { storage, _ in
            gtk_scrolled_window_set_policy(storage.opaquePointer, GTK_POLICY_AUTOMATIC, GTK_POLICY_NEVER)
        }
    }
}

extension ViewSwitcher {
    /// Reserve enough width for complete titles, including enlarged desktop fonts.
    /// The surrounding scroll view handles windows narrower than the tab row.
    func readableTitles() -> AnyView {
        inspect { storage, _ in
            let widget: UnsafeMutablePointer<GtkWidget>? = storage.opaquePointer?.cast()
            guard let context = gtk_widget_get_pango_context(widget),
                let layout = pango_layout_new(context)
            else { return }
            var widest: Int32 = 0
            for option in Element.allCases {
                pango_layout_set_text(layout, option.title, -1)
                var width: Int32 = 0
                pango_layout_get_pixel_size(layout, &width, nil)
                widest = max(widest, width)
            }
            g_object_unref(UnsafeMutableRawPointer(layout))
            gtk_widget_set_size_request(widget, (widest + 24) * Int32(Element.allCases.count), -1)
        }
    }
}
