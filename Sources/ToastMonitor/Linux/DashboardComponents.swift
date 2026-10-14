import Adwaita
import CAdw
import Foundation
import LinuxBridge

struct NativeChart: View {
    var mode = 0
    var values: [Double]
    var series = 1
    var colors: [Int32]
    var labels: [String] = []
    var height = 200
    var summary: String

    var view: Body {
        Bin().inspect { storage, _ in
            let bin: UnsafeMutablePointer<AdwBin>? = storage.opaquePointer?.cast()
            let chart: UnsafeMutableRawPointer
            if let existing = adw_bin_get_child(bin) {
                chart = UnsafeMutableRawPointer(existing)
            } else {
                chart = tm_chart_new()!
                adw_bin_set_child(bin, chart.assumingMemoryBound(to: GtkWidget.self))
            }
            values.withUnsafeBufferPointer { numbers in
                colors.withUnsafeBufferPointer { palette in
                    tm_chart_update(chart, Int32(mode), numbers.baseAddress, Int32(values.count),
                                    Int32(series), palette.baseAddress, labels.joined(separator: "\n"), summary)
                }
            }
        }.frame(minHeight: height)
    }
}

struct NativeSegments: View {
    let labels: [String]
    let selected: Int
    let select: (Int) -> Void
    struct Option: Identifiable { let id: Int; let label: String }
    var view: Body {
        HStack {
            ForEach(labels.enumerated().map { Option(id: $0.offset, label: $0.element) }, horizontal: true) { option in
                ToggleButton().label(option.label)
                    .active(.init(get: { selected == option.id }, set: { if $0 { select(option.id) } }))
                    .style("flat")
            }.inspectOnAppear { storage in NativeToggleGroup.apply(storage.opaquePointer?.cast()) }
        }.spacing(0).style("tm-segments").halign(.start)
    }
}

struct DashboardStat: Identifiable {
    let id: String
    let value: String
    let help: String
    init(_ title: String, _ value: String, _ help: String = "") { id = title; self.value = value; self.help = help }
}

struct DashboardStats: View {
    let stats: [DashboardStat]
    var view: Body {
        HStack {
            ForEach(stats, horizontal: true) { stat in
                VStack {
                    Text(stat.id).xalign(0).style("tm-secondary")
                    Text(stat.value).xalign(0).selectable().style("tm-stat-value")
                }.spacing(6).padding(16).hexpand().cardSurface().tooltip(stat.help)
            }.spacing(12).hexpand().inspect { storage, _ in gtk_box_set_homogeneous(storage.opaquePointer?.cast(), 1) }
        }
    }
}

struct BreakdownEntry: Identifiable {
    let id: String
    let tokens: Int64
    var calls: Int64 = 0
    var cost: Double = 0
    let color: Int32
}

struct BreakdownCard: View {
    let title: String
    let entries: [BreakdownEntry]
    var view: Body {
        VStack {
            Text(title).xalign(0).style("tm-heading")
            NativeChart(mode: 2, values: entries.map { Double($0.tokens) }, colors: entries.map(\.color), height: 8,
                        summary: entries.map { "\($0.id): \(Format.full($0.tokens)) tokens" }.joined(separator: "; "))
            if entries.isEmpty {
                Text("No usage in this period").xalign(0).style("tm-secondary").padding(8, .top)
            } else {
                ForEach(entries) { entry in
                    HStack {
                        NativeDot(color: entry.color)
                        Text(entry.id).xalign(0).ellipsize().hexpand()
                        Text(String(format: "%.1f%%", Double(entry.tokens) / Double(max(1, entries.reduce(0) { $0 + $1.tokens })) * 100))
                            .style("tm-secondary")
                        Text(Format.compact(entry.tokens)).xalign(1).style("tm-value").frame(minWidth: 65)
                    }.spacing(12).padding(4, [.top, .bottom])
                }.spacing(6)
            }
            Text("").vexpand()
        }.spacing(14).padding(18).frame(minHeight: 185).hexpand().cardSurface()
    }
}

struct ActivityCard: View {
    let heatmap: [Int64: Int64]
    var view: Body {
        VStack {
            HStack {
                Text("Activity").xalign(0).style("tm-heading").hexpand()
                Text("\(heatmap.values.filter { $0 > 0 }.count) active days in the past year").style("tm-secondary")
            }.spacing(12)
            NativeChart(mode: 1, values: days.map { Double(heatmap[DashboardDate.key($0)] ?? 0) },
                        colors: Array(repeating: 1, count: days.count), labels: monthLabels,
                        height: 190, summary: "Activity in the past year. \(heatmap.values.filter { $0 > 0 }.count) active days.")
        }.spacing(16).padding(18).cardSurface()
    }
    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = (calendar.component(.weekday, from: today) + 5) % 7
        let start = calendar.date(byAdding: .day, value: -364 - weekday, to: today)!
        return (0..<(365 + weekday)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    private var monthLabels: [String] {
        let formatter = DateFormatter(); formatter.dateFormat = "MMM"
        var previous = -1
        return days.enumerated().map { index, day in
            let month = Calendar.current.component(.month, from: day)
            guard index % 7 == 0, month != previous, index < days.count - 14 else { return "" }
            previous = month
            return formatter.string(from: day)
        }
    }
}

enum DashboardColors {
    static func index(_ tool: String) -> Int32 {
        switch tool {
        case "codex": return 0
        case "claude": return 1
        case "omp": return 2
        case "hermes": return 3
        case "opencode": return 4
        default: return 5
        }
    }
}

struct NativeSymbol: View {
    let name: String
    var view: Body {
        Bin().inspect { storage, _ in
            if adw_bin_get_child(storage.opaquePointer?.cast()) == nil {
                adw_bin_set_child(storage.opaquePointer?.cast(), gtk_image_new_from_icon_name(name))
            }
        }
    }
}

enum DashboardDate {
    static func key(_ date: Date) -> Int64 {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = c.year ?? 0
        let month = c.month ?? 0
        let day = c.day ?? 0
        return Int64(year * 10000 + month * 100 + day)
    }
    static func dates(_ count: Int) -> [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<count).compactMap { Calendar.current.date(byAdding: .day, value: $0 - count + 1, to: today) }
    }
}

enum NativeToggleGroup {
    static func apply(_ box: UnsafeMutablePointer<GtkWidget>?) {
        guard let first = gtk_widget_get_first_child(box) else { return }
        var next = gtk_widget_get_next_sibling(first)
        while let child = next {
            gtk_toggle_button_set_group(UnsafeMutableRawPointer(child).assumingMemoryBound(to: GtkToggleButton.self),
                                        UnsafeMutableRawPointer(first).assumingMemoryBound(to: GtkToggleButton.self))
            next = gtk_widget_get_next_sibling(child)
        }
    }
}

extension AnyView {
    /// Put the existing child margins inside the painted surface.
    func cardSurface() -> AnyView { Bin().child { self }.style("tm-card") }
}

struct NativeDot: View {
    let color: Int32
    var view: Body {
        Bin().frame(minWidth: 7, minHeight: 7).style("tm-dot").style("tm-color-\(color)").valign(.center)
    }
}
