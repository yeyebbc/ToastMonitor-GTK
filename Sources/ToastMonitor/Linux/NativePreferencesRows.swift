import Adwaita

/// Give dynamic and conditional rows a real GtkListBox parent. PreferencesGroup
/// otherwise treats their view-builder wrappers as content below its row list.
struct NativePreferencesRow: Identifiable {
    let id: String
    let content: AnyView

    init(_ id: String, _ content: AnyView) {
        self.id = id
        self.content = content
    }
}

struct NativePreferencesRows: View {
    let rows: [NativePreferencesRow]

    var view: Body {
        List(rows, selection: nil) { row in
            row.content
        }.boxedList()
    }
}
