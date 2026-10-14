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
        const title = label('ToastMonitor', 'toastmonitor-title');
        title.x_expand = true;
        header.add_child(title);
        this._refresh = button('', 'Refresh ToastMonitor usage', () => this._refreshNow(), 'view-refresh-symbolic');
        header.add_child(this._refresh);
        this._root.add_child(header);
        this._status = label('Connecting…', 'toastmonitor-muted', true);
        this._root.add_child(this._status);

        this._content = new St.BoxLayout({vertical: true, style_class: 'toastmonitor-content', x_expand: true});
        this._scroll = new St.ScrollView({
            hscrollbar_policy: St.PolicyType.NEVER,
            vscrollbar_policy: St.PolicyType.AUTOMATIC,
            overlay_scrollbars: true,
            x_expand: true,
            child: this._content,
        });
        this._root.add_child(this._scroll);
        this._summary = new St.BoxLayout({vertical: true, style_class: 'toastmonitor-section'});
        this._values = {};
        for (const [key, title] of [['tokens', 'Tokens'], ['calls', 'Model Calls'],
            ['apiValue', 'API Value'], ['recordedSpend', 'Recorded Spend']]) {
            const row = new St.BoxLayout({style_class: 'toastmonitor-metric'});
            const name = label(title);
            name.x_expand = true;
            row.add_child(name);
            this._values[key] = label('—', 'toastmonitor-value');
            row.add_child(this._values[key]);
            this._summary.add_child(row);
        }
        this._summary.add_child(label('API value is an estimate. Recorded spend excludes subscription fees.',
            'toastmonitor-muted toastmonitor-note', true));
        this._content.add_child(this._summary);
        this._sources = this._section('Sources');
        this._accounts = this._section('Plans & Accounts');
        this._notice = label('', 'toastmonitor-muted', true);
        this._notice.hide();
        this._root.add_child(this._notice);

        const footer = new St.BoxLayout({style_class: 'toastmonitor-actions'});
        this._openButton = button('Open Overview', 'Open ToastMonitor overview', () => this._open('Overview'));
        footer.add_child(this._openButton);
        footer.add_child(button('Preferences', 'Open ToastMonitor preferences', () => this._open('Preferences')));
        this._root.add_child(footer);
        this._plansButton = button('View All Plans', 'Open ToastMonitor plans', () => this._open('Plans'));
        this._root.add_child(this._plansButton);
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
        section.add_child(label(title, 'toastmonitor-heading'));
        const rows = new St.BoxLayout({vertical: true, style_class: 'toastmonitor-rows'});
        section.add_child(rows);
        this._content.add_child(section);
        return rows;
    }

    _resize() {
        const monitor = Main.layoutManager.primaryMonitor;
        const scale = St.ThemeContext.get_for_stage(global.stage).scale_factor;
        const width = Math.max(220, Math.min(360, (monitor?.width ?? 1280) / scale - 48));
        const height = Math.max(120, Math.min(520, (monitor?.height ?? 900) / scale - 260));
        this._root.set_style(`width: ${width}px;`);
        this._scroll.set_style(`max-height: ${height}px;`);
    }

    _ownerChanged() {
        this._raw = null;
        this._sourceKey = this._accountKey = null;
        this._claimedOwner = this._claimingOwner = null;
        if (!this._proxy.g_name_owner) {
            this._unavailable('ToastMonitor is not running. Start it to resume local usage monitoring.');
            return;
        }
        this._status.text = 'Connecting to ToastMonitor…';
        this._read();
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
        if (!raw || raw === this._raw)
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
            this._openButton.child.text = 'Open Overview';
            this._plansButton.show();
            this._scroll.show();
            this._notice.hide();
            this._panelLabel.text = data.ready ? data.tokens : '…';
            this._indicator.accessible_name = data.ready ? `ToastMonitor: ${data.tokenDetail} tokens today` : 'ToastMonitor: collecting usage';
            this._status.text = data.ready ? `Today · Usage updated ${new Date(data.updatedAt * 1000).toLocaleTimeString([], {hour: '2-digit', minute: '2-digit'})}` : 'Collecting local usage…';
            for (const key of Object.keys(this._values))
                this._values[key].text = data.ready ? String(data[key] ?? '—') : '—';
            if (JSON.stringify(data.sources) !== this._sourceKey) {
                this._sourceKey = JSON.stringify(data.sources);
                this._rows(this._sources, data.sources ?? [], 'No usage collected today.');
            }
            if (JSON.stringify(data.accounts) !== this._accountKey) {
                this._accountKey = JSON.stringify(data.accounts);
                this._rows(this._accounts, data.accounts ?? [], 'Connect accounts in Preferences to see balances and quotas.');
            }
        } catch (error) {
            this._unavailable('This application needs a compatible ToastMonitor panel update.');
        }
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
            const title = label(String(row.title), '', true);
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
        this._scroll.hide();
        this._plansButton.hide();
        this._refresh.reactive = false;
        this._refresh.can_focus = false;
        this._openButton.child.text = 'Start ToastMonitor';
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
        this._showNotice('Refreshing local usage and connected accounts…');
        this._call('Refresh', null, error => {
            if (error)
                this._showNotice('Refresh failed. Open ToastMonitor to check its status.');
        });
        this._refreshTimeout = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 5, () => {
            this._refreshTimeout = 0;
            this._refresh.reactive = Boolean(this._proxy?.g_name_owner);
            this._notice.hide();
            return GLib.SOURCE_REMOVE;
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
