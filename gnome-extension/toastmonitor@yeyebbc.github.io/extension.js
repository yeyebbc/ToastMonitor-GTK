import Cairo from 'cairo';
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Pango from 'gi://Pango';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

const BUS = 'io.github.yeyebbc.ToastMonitor';
const PATH = '/io/github/yeyebbc/ToastMonitor/Panel';
const IFACE = 'io.github.yeyebbc.ToastMonitor.Panel';

function label(text, style = '', wrap = false) {
    const actor = new St.Label({text, style_class: style, y_align: Clutter.ActorAlign.CENTER});
    // Derive secondary text from the active theme's foreground in light, dark,
    // and custom Shell themes instead of fixing a grey that only suits one.
    if (style.split(' ').includes('toastmonitor-muted'))
        actor.opacity = 204;
    if (wrap) {
        actor.clutter_text.line_wrap = true;
        actor.clutter_text.line_wrap_mode = Pango.WrapMode.WORD_CHAR;
        actor.clutter_text.ellipsize = Pango.EllipsizeMode.NONE;
    }
    return actor;
}

function button(text, accessibleName, callback, icon = null) {
    const actor = new St.Button({
        style_class: icon ? 'button toastmonitor-icon-button' : 'button toastmonitor-button',
        accessible_name: accessibleName,
        can_focus: true,
        reactive: true,
        x_expand: !icon,
        child: icon ? new St.Icon({icon_name: icon, style_class: 'popup-menu-icon'}) : label(text),
    });
    actor.connect('clicked', callback);
    return actor;
}

export default class ToastMonitorExtension extends Extension {
    enable() {
        this._enabled = true;
        this._cancellable = new Gio.Cancellable();
        this._signals = [];
        this._claimedOwner = null;
        this._raw = null;
        this._refreshError = null;
        this._period = 'today';
        this._activityMode = 'grid';
        this._build();
        this._proxy = new Gio.DBusProxy({
            g_connection: Gio.DBus.session,
            g_name: BUS,
            g_object_path: PATH,
            g_interface_name: IFACE,
            g_flags: Gio.DBusProxyFlags.DO_NOT_AUTO_START,
        });
        this._proxy.init_async(GLib.PRIORITY_DEFAULT, this._cancellable, (proxy, result) => {
            if (!this._enabled || proxy !== this._proxy)
                return;
            try {
                proxy.init_finish(result);
                this._signals.push(proxy.connect('notify::g-name-owner', () => this._ownerChanged()));
                this._signals.push(proxy.connect('g-properties-changed', () => this._read()));
                this._ownerChanged();
            } catch (error) {
                this._unavailable('Could not connect to ToastMonitor. Open the application and try again.');
            }
        });
    }

    _build() {
        this._indicator = new PanelMenu.Button(0.0, 'ToastMonitor');
        this._indicator.accessible_name = 'ToastMonitor usage';
        const panelBox = new St.BoxLayout({style_class: 'panel-status-menu-box'});
        panelBox.add_child(new St.Icon({
            gicon: Gio.FileIcon.new(this.dir.get_child('toastmonitor-token-symbolic.svg')),
            style_class: 'system-status-icon',
        }));
        this._panelLabel = label('…');
        panelBox.add_child(this._panelLabel);
        this._indicator.add_child(panelBox);
        Main.panel.addToStatusArea(this.uuid, this._indicator);

        const item = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
        // No menu-item hover background: the contents have their own controls.
        item.remove_style_class_name('popup-menu-item');
        item.remove_style_class_name('popup-inactive-menu-item');
        this._root = new St.BoxLayout({vertical: true, style_class: 'toastmonitor-popup', x_expand: true});
        item.add_child(this._root);
        this._indicator.menu.addMenuItem(item);

        const header = new St.BoxLayout({style_class: 'toastmonitor-header'});
        const title = label('ToastMonitor', 'toastmonitor-title', true);
        title.x_expand = true;
        header.add_child(title);
        this._refresh = button('', 'Refresh ToastMonitor usage', () => this._refreshNow(), 'view-refresh-symbolic');
        header.add_child(this._refresh);
        this._root.add_child(header);
        this._periods = new St.BoxLayout({style_class: 'toastmonitor-periods', x_expand: true});
        this._periodButtons = new Map();
        for (const [id, title] of [['today', 'Today'], ['week', '7 Days'], ['month', '30 Days'], ['all', 'All Time']]) {
            const control = button(title, `Show usage: ${title}`, () => {
                this._period = id;
                if (this._data)
                    this._render(this._data);
            });
            control.add_style_class_name('toastmonitor-period');
            control.toggle_mode = true;
            this._periodButtons.set(id, control);
            this._periods.add_child(control);
        }
        this._root.add_child(this._periods);
        this._content = new St.BoxLayout({vertical: true, style_class: 'toastmonitor-content', x_expand: true});
        this._scroll = new St.ScrollView({
            hscrollbar_policy: St.PolicyType.NEVER,
            vscrollbar_policy: St.PolicyType.AUTOMATIC,
            overlay_scrollbars: true,
            x_expand: true,
            child: this._content,
        });
        this._root.add_child(this._scroll);
        this._summary = new St.BoxLayout({vertical: true, style_class: 'toastmonitor-summary'});
        const total = new St.BoxLayout({style_class: 'toastmonitor-token-line'});
        this._tokens = label('—', 'toastmonitor-token-total');
        total.add_child(this._tokens);
        total.add_child(label('tokens', 'toastmonitor-muted'));
        this._summary.add_child(total);
        this._money = label('Spent —    Value —', 'toastmonitor-spend', true);
        this._summary.add_child(this._money);
        this._status = label('Connecting…', 'toastmonitor-muted toastmonitor-note', true);
        this._summary.add_child(this._status);
        this._content.add_child(this._summary);
        this._sources = this._section('Sources');
        this._accounts = this._section('Quota & Accounts');
        this._plansButton = button('', 'Open all plans and accounts', () => this._open('Plans'), 'go-next-symbolic');
        this._accountHeader = this._accounts.get_parent().get_first_child();
        // Section headings stay small; the arrow is a separate focusable action.
        const quotaHeading = new St.BoxLayout({style_class: 'toastmonitor-header'});
        this._accountHeader.ref();
        this._accounts.get_parent().remove_child(this._accountHeader);
        this._accountHeader.x_expand = true;
        quotaHeading.add_child(this._accountHeader);
        this._accountHeader.unref();
        quotaHeading.add_child(this._plansButton);
        this._accounts.get_parent().insert_child_at_index(quotaHeading, 0);
        this._activity = this._section('Activity');
        const activityHeading = this._activity.get_parent().get_first_child();
        activityHeading.ref();
        this._activity.get_parent().remove_child(activityHeading);
        const activityHeader = new St.BoxLayout({style_class: 'toastmonitor-header'});
        activityHeading.x_expand = true;
        activityHeader.add_child(activityHeading);
        activityHeading.unref();
        this._activeDays = label('', 'toastmonitor-muted');
        activityHeader.add_child(this._activeDays);
        activityHeader.add_child(button('', 'Show activity grid', () => {this._activityMode = 'grid'; this._drawActivity();}, 'view-grid-symbolic'));
        const activityChartButton = button('', 'Show daily activity chart', () => {this._activityMode = 'chart'; this._drawActivity();}, 'view-grid-symbolic');
        activityChartButton.child = new St.Icon({gicon: Gio.FileIcon.new(this.dir.get_child('toastmonitor-chart-symbolic.svg')), style_class: 'popup-menu-icon'});
        activityHeader.add_child(activityChartButton);
        this._activity.get_parent().insert_child_at_index(activityHeader, 0);
        this._activityCanvas = new St.DrawingArea({style_class: 'toastmonitor-activity', x_expand: true});
        this._activityCanvas.connect('repaint', area => this._paintActivity(area));
        this._activity.add_child(this._activityCanvas);
        this._notice = label('', 'toastmonitor-muted', true);
        this._notice.hide();
        this._root.add_child(this._notice);

        const footer = new St.BoxLayout({style_class: 'toastmonitor-actions'});
        footer.add_child(button('', 'Open ToastMonitor settings', () => this._open('Preferences'), 'preferences-system-symbolic'));
        this._quitButton = button('', 'Quit ToastMonitor', () => this._call('Quit', null, error => {
            if (error) this._showNotice('Could not quit. Open ToastMonitor and use Quit.');
            else this._indicator.menu.close();
        }), 'system-shutdown-symbolic');
        footer.add_child(this._quitButton);
        const spacer = new St.Widget({x_expand: true});
        footer.add_child(spacer);
        this._openButton = button('Open Dashboard', 'Open ToastMonitor dashboard', () => this._open('Overview'));
        this._openButton.x_expand = false;
        footer.add_child(this._openButton);
        this._root.add_child(footer);
        this._indicator.menu.connect('open-state-changed', (_menu, open) => {
            this._resize();
            if (this._claimedOwner)
                this._call('SetExpanded', new GLib.Variant('(b)', [open]));
            if (open)
                this._read();
        });
        this._monitorsChanged = Main.layoutManager.connect('monitors-changed', () => this._resize());
        this._resize();
        this._unavailable('Start ToastMonitor to see local usage and connected accounts.');
    }

    _section(title) {
        const section = new St.BoxLayout({vertical: true, style_class: 'toastmonitor-section'});
        section.add_child(label(title, 'toastmonitor-heading', true));
        const rows = new St.BoxLayout({vertical: true, style_class: 'toastmonitor-rows'});
        section.add_child(rows);
        this._content.add_child(section);
        return rows;
    }

    _resize() {
        const monitor = Main.layoutManager.primaryMonitor;
        const scale = St.ThemeContext.get_for_stage(global.stage).scale_factor;
        const width = Math.max(220, Math.min(380, (monitor?.width ?? 1280) / scale - 48));
        const height = Math.max(120, Math.min(650, (monitor?.height ?? 900) / scale - 220));
        this._root.set_style(`width: ${width}px;`);
        this._scroll.set_style(`max-height: ${height}px;`);
    }

    _ownerChanged() {
        if (this._refreshTimeout)
            GLib.source_remove(this._refreshTimeout);
        this._refreshTimeout = 0;
        this._refreshError = null;
        if (this._snapshotRetry)
            GLib.source_remove(this._snapshotRetry);
        this._snapshotRetry = 0;
        this._snapshotAttempts = 0;
        this._snapshotFetching = false;
        this._raw = null;
        this._sourceKey = this._accountKey = this._activityKey = null;
        this._claimedOwner = this._claimingOwner = null;
        if (!this._proxy.g_name_owner) {
            this._unavailable('ToastMonitor is not running. Start it to resume local usage monitoring.');
            return;
        }
        this._status.text = 'Connecting to ToastMonitor…';
        this._read();
    }

    _requestSnapshot() {
        if (this._snapshotFetching || this._snapshotRetry || !this._proxy?.g_name_owner)
            return;
        const proxy = this._proxy;
        const owner = proxy.g_name_owner;
        this._snapshotFetching = true;
        Gio.DBus.session.call(owner, PATH, 'org.freedesktop.DBus.Properties', 'Get',
            new GLib.Variant('(ss)', [IFACE, 'Snapshot']), new GLib.VariantType('(v)'),
            Gio.DBusCallFlags.NO_AUTO_START, 1500, this._cancellable, (connection, result) => {
                if (!this._enabled || this._proxy !== proxy || proxy.g_name_owner !== owner)
                    return;
                this._snapshotFetching = false;
                try {
                    const [value] = connection.call_finish(result).unpack();
                    proxy.set_cached_property('Snapshot', value);
                    this._read();
                } catch (error) {
                    if (this._raw)
                        return;
                    if (++this._snapshotAttempts >= 5) {
                        this._unavailable('The running ToastMonitor has no panel interface. Quit all copies and reopen the installed application.');
                        return;
                    }
                    this._snapshotRetry = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1000, () => {
                        this._snapshotRetry = 0;
                        this._requestSnapshot();
                        return GLib.SOURCE_REMOVE;
                    });
                }
            });
    }

    _claim() {
        const owner = this._proxy.g_name_owner;
        if (!owner || this._claimedOwner === owner || this._claimingOwner === owner)
            return;
        this._claimingOwner = owner;
        this._call('SetPanelActive', new GLib.Variant('(b)', [true]), error => {
            if (this._proxy.g_name_owner !== owner)
                return;
            this._claimingOwner = null;
            if (error) {
                this._unavailable('Update the ToastMonitor application to use this panel.');
                return;
            }
            this._claimedOwner = owner;
            this._call('SetExpanded', new GLib.Variant('(b)', [this._indicator.menu.isOpen]));
        });
    }

    _call(method, parameters = null, done = null) {
        if (!this._enabled || !this._proxy?.g_name_owner)
            return;
        this._proxy.call(method, parameters, Gio.DBusCallFlags.NO_AUTO_START, 10000, this._cancellable, (proxy, result) => {
            if (!this._enabled || proxy !== this._proxy)
                return;
            try {
                proxy.call_finish(result);
                done?.(null);
            } catch (error) {
                if (done)
                    done(error);
                else
                    this._showNotice('Action failed. Open ToastMonitor to check its status.');
            }
        });
    }

    _read() {
        if (!this._proxy?.g_name_owner)
            return;
        const raw = this._proxy.get_cached_property('Snapshot')?.deep_unpack();
        if (!raw) {
            this._requestSnapshot();
            return;
        }
        if (raw === this._raw)
            return;
        try {
            const data = JSON.parse(raw);
            if (data.version !== 1)
                throw new Error('Unsupported panel version');
            this._raw = raw;
            // GApplication owns its bus name before the panel object is registered.
            // Claim the tray only after a compatible Snapshot actually arrives.
            this._claim();
            this._refresh.reactive = !this._refreshTimeout;
            this._refresh.can_focus = true;
            this._quitButton.reactive = true;
            this._quitButton.can_focus = true;
            this._openButton.child.text = 'Open Dashboard';
            this._plansButton.show();
            this._periods.show();
            this._scroll.show();
            if (!this._refreshTimeout && !this._refreshError)
                this._notice.hide();
            this._panelLabel.text = data.ready ? data.tokens : '…';
            this._indicator.accessible_name = data.ready ? `ToastMonitor: ${data.tokenDetail} tokens today` : 'ToastMonitor: collecting usage';
            this._status.text = data.ready ? `Today · Usage updated ${new Date(data.updatedAt * 1000).toLocaleTimeString([], {hour: '2-digit', minute: '2-digit'})}` : 'Collecting local usage…';
            this._data = data;
            this._render(data);
        } catch (error) {
            this._unavailable('This application needs a compatible ToastMonitor panel update.');
        }
    }

    _render(data) {
        const period = data.periods?.find(p => p.id === this._period) ?? data;
        for (const [id, control] of this._periodButtons) {
            const title = data.periods?.find(p => p.id === id)?.title;
            if (title) control.child.text = title;
            control.reactive = id === 'today' || Boolean(data.periods?.some(p => p.id === id));
            control.checked = id === this._period;
        }
        this._tokens.text = data.ready ? String(period.tokens ?? '—') : '—';
        this._money.text = `Spent ${period.recordedSpend ?? '—'}    Value ${period.apiValue ?? '—'}`;
        this._money.accessible_name = `Recorded spend ${period.recordedSpend ?? 'unavailable'}, excluding subscriptions. Estimated API value ${period.apiValue ?? 'unavailable'}. ${period.calls ?? '0'} calls.`;
        this._sources.get_parent().visible = data.showSources !== false;
        this._accounts.get_parent().visible = data.showAccounts !== false;
        this._activity.get_parent().visible = data.showActivity !== false;
        const sources = period.sources ?? [];
        const sourceKey = JSON.stringify(sources);
        if (sourceKey !== this._sourceKey) {
            this._sourceKey = sourceKey;
            this._sourceRows(sources);
        }
        const accounts = (data.accounts ?? []).map(row => {
            if (!data.remainingQuota || !Number.isFinite(row.fraction)) return row;
            return {...row, value: `${Math.round((1 - row.fraction) * 100)}% remaining`, fraction: 1 - row.fraction};
        });
        const accountKey = JSON.stringify(accounts);
        if (accountKey !== this._accountKey) {
            this._accountKey = accountKey;
            this._rows(this._accounts, accounts, 'Connect accounts in Settings to see balances and quotas.');
        }
        this._activeDays.text = `${data.activeDays ?? 0} active days`;
        this._activityCanvas.accessible_name = `Activity during the past six months. ${data.activeDays ?? 0} active days in the past year.`;
        const activityKey = JSON.stringify(data.activity);
        if (activityKey !== this._activityKey) {
            this._activityKey = activityKey;
            this._drawActivity();
        }
    }

    _sourceColor(id) {
        return ({codex: '#7d9bff', claude: '#d47745', omp: '#54adbf', hermes: '#b34fdb', opencode: '#35b963', dsh: '#6674fd'})[id] ?? '#7d9bff';
    }

    _sourceRows(rows) {
        this._sources.destroy_all_children();
        if (!rows.length) {
            this._sources.add_child(label('No usage in this period.', 'toastmonitor-muted', true));
            return;
        }
        const track = new St.DrawingArea({style_class: 'toastmonitor-source-track', x_expand: true});
        track.connect('repaint', area => {
            const cr = area.get_context();
            const [width, height] = area.get_surface_size();
            let x = 0;
            for (const row of rows) {
                const color = this._sourceColor(row.id);
                const rgb = [1, 3, 5].map(index => parseInt(color.slice(index, index + 2), 16) / 255);
                const part = width * (row.fraction ?? 1 / rows.length);
                cr.setSourceRGB(...rgb); cr.rectangle(x, 0, part, height); cr.fill(); x += part;
            }
            cr.$dispose();
        });
        this._sources.add_child(track);
        for (const row of rows) {
            const line = new St.BoxLayout({style_class: 'toastmonitor-metric'});
            line.add_child(new St.Widget({style_class: 'toastmonitor-source-dot', style: `background-color: ${this._sourceColor(row.id)};`, y_align: Clutter.ActorAlign.CENTER}));
            const title = label(`${row.title}${row.fraction === undefined ? '' : `  (${(row.fraction * 100).toFixed(1)}%)`}`, 'toastmonitor-row-title', true);
            title.x_expand = true;
            line.add_child(title);
            line.add_child(label(String(row.value), 'toastmonitor-value'));
            this._sources.add_child(line);
        }
    }

    _drawActivity() {
        this._activityCanvas.queue_repaint();
    }

    _paintActivity(area) {
        const cells = this._data?.activity ?? [];
        const cr = area.get_context();
        cr.setAntialias(Cairo.Antialias.GRAY);
        const [width, height] = area.get_surface_size();
        if (!cells.length) { cr.$dispose(); return; }
        const max = Math.max(1, ...cells.map(c => c.tokens));
        if (this._activityMode === 'chart') {
            cr.setSourceRGBA(0.82, 0.43, 0.25, 0.9);
            cr.setLineWidth(2);
            cells.forEach((cell, i) => {
                const x = width * i / Math.max(1, cells.length - 1);
                const y = height - 8 - (height - 16) * cell.tokens / max;
                if (i === 0) cr.moveTo(x, y); else cr.lineTo(x, y);
            });
            cr.stroke();
        } else {
            const columns = Math.ceil(cells.length / 7), gap = 2;
            const size = Math.min((width - gap * (columns - 1)) / columns, (height - 22) / 7 - gap);
            const fg = area.get_theme_node().get_foreground_color();
            cr.selectFontFace('sans-serif', Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
            cr.setFontSize(10);
            cells.forEach((cell, i) => {
                const x = Math.floor(i / 7) * (size + gap), y = 20 + i % 7 * (size + gap);
                if (i % 7 === 0 && cell.month && i < cells.length - 14) {
                    cr.setSourceRGBA(fg.red / 255, fg.green / 255, fg.blue / 255, 0.7);
                    cr.moveTo(x, 12); cr.showText(cell.month);
                }
                if (cell.tokens > 0) cr.setSourceRGBA(0.82, 0.43, 0.25, 0.3 + 0.7 * Math.sqrt(cell.tokens / max));
                else cr.setSourceRGBA(fg.red / 255, fg.green / 255, fg.blue / 255, 0.09);
                cr.rectangle(x, y, size, size); cr.fill();
            });
        }
        cr.$dispose();
    }

    _rows(container, rows, emptyText) {
        container.destroy_all_children();
        if (!rows.length) {
            container.add_child(label(emptyText, 'toastmonitor-muted', true));
            return;
        }
        for (const row of rows) {
            const box = new St.BoxLayout({vertical: true, style_class: 'toastmonitor-data-row'});
            const top = new St.BoxLayout({style_class: 'toastmonitor-metric'});
            const title = label(String(row.title), 'toastmonitor-row-title', true);
            title.x_expand = true;
            top.add_child(title);
            top.add_child(label(String(row.value), 'toastmonitor-value'));
            box.add_child(top);
            box.add_child(label(String(row.detail), 'toastmonitor-muted', true));
            if (Number.isFinite(row.fraction)) {
                const track = new St.BoxLayout({style_class: 'toastmonitor-quota-track', x_expand: true});
                const fill = new St.Widget({style_class: 'toastmonitor-quota-fill', x_align: Clutter.ActorAlign.START});
                track.add_child(fill);
                track.connect('notify::allocation', () => {
                    fill.width = Math.max(0, track.width * Math.max(0, Math.min(1, row.fraction)));
                });
                box.add_child(track);
            }
            container.add_child(box);
        }
    }

    _unavailable(message) {
        this._panelLabel.text = '—';
        this._indicator.accessible_name = 'ToastMonitor: unavailable';
        this._status.text = message;
        this._showNotice(message);
        this._periods.hide();
        this._scroll.hide();
        this._plansButton.hide();
        this._refresh.reactive = false;
        this._refresh.can_focus = false;
        this._quitButton.reactive = false;
        this._quitButton.can_focus = false;
        this._openButton.child.text = this._proxy?.g_name_owner ? 'Open ToastMonitor' : 'Start ToastMonitor';
    }

    _showNotice(message) {
        this._notice.text = message;
        this._notice.show();
    }

    _launch() {
        const app = Gio.DesktopAppInfo.new('io.github.yeyebbc.ToastMonitor.desktop');
        if (!app) {
            this._showNotice('Install the ToastMonitor application first.');
            return;
        }
        try {
            app.launch([], global.create_app_launch_context(0, -1));
            this._indicator.menu.close();
        } catch (error) {
            this._showNotice('Could not start ToastMonitor. Check the application installation.');
        }
    }

    _open(page) {
        if (!this._proxy?.g_name_owner) {
            this._launch();
            return;
        }
        this._call('Open', new GLib.Variant('(s)', [page]), error => {
            if (error)
                this._showNotice('Could not open this page. Update or restart ToastMonitor.');
            else
                this._indicator.menu.close();
        });
    }

    _refreshNow() {
        if (!this._proxy?.g_name_owner || this._refreshTimeout)
            return;
        this._refresh.reactive = false;
        this._refreshError = null;
        this._showNotice('Refreshing local usage and connected accounts…');
        this._refreshTimeout = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 5, () => {
            this._refreshTimeout = 0;
            this._refresh.reactive = Boolean(this._proxy?.g_name_owner);
            if (!this._refreshError && this._proxy?.g_name_owner)
                this._notice.hide();
            return GLib.SOURCE_REMOVE;
        });
        this._call('Refresh', null, error => {
            if (error) {
                this._refreshError = 'Refresh failed. Open ToastMonitor to check its status.';
                this._showNotice(this._refreshError);
            }
        });
    }

    disable() {
        this._enabled = false;
        if (this._proxy?.g_name_owner) {
            // Separate cancellable: release the tray lease even when pending reads are cancelled.
            Gio.DBus.session.call(BUS, PATH, IFACE, 'SetPanelActive', new GLib.Variant('(b)', [false]),
                null, Gio.DBusCallFlags.NO_AUTO_START, 2000, null, null);
        }
        this._cancellable?.cancel();
        if (this._snapshotRetry)
            GLib.source_remove(this._snapshotRetry);
        this._snapshotRetry = 0;
        this._snapshotFetching = false;
        if (this._refreshTimeout)
            GLib.source_remove(this._refreshTimeout);
        this._refreshTimeout = 0;
        if (this._proxy) {
            for (const signal of this._signals)
                this._proxy.disconnect(signal);
        }
        if (this._monitorsChanged)
            Main.layoutManager.disconnect(this._monitorsChanged);
        this._monitorsChanged = 0;
        this._indicator?.destroy();
        this._indicator = this._proxy = this._cancellable = null;
        this._signals = [];
    }
}
