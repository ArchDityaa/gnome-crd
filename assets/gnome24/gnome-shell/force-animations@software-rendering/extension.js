/* extension.js -- Force GNOME Shell animations on software rendering.
 *
 * GNOME Shell (js/ui/main.js, AnimationsSettings) calls
 * St.Settings.inhibit_animations() whenever
 * backend.is_rendering_hardware_accelerated() is false (llvmpipe /
 * swrast, i.e. any GPU-less VM, CRD, VNC or RDP session). That
 * toolkit-level inhibit overrides
 * org.gnome.desktop.interface enable-animations, so the overview,
 * window, workspace and dash animations all become instant.
 *
 * GNOME's supported override is global.force_animations (a writable
 * Shell.Global property, blurb "Force animations to be enabled").
 * There is no GSetting and no environment variable for it, so it can
 * only be set from inside the shell -- i.e. from an extension.
 *
 * This extension additionally applies St.Settings.slow_down_factor so
 * animations run in slow motion (default factor 2.5, overridable via
 * the GNOME_SHELL_SLOWDOWN_FACTOR environment variable).
 */

import GLib from 'gi://GLib';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const LOG_PREFIX = '[force-animations]';
const DEFAULT_SLOWDOWN = 2.5;

export default class ForceAnimationsExtension extends Extension {
    enable() {
        this._previousForceAnimations = global.force_animations;
        this._previousSlowDownFactor = St.Settings.get().slow_down_factor;
        this._idleId = 0;

        const slowdownEnv = GLib.getenv('GNOME_SHELL_SLOWDOWN_FACTOR');
        const factor = slowdownEnv
            ? (parseFloat(slowdownEnv) || DEFAULT_SLOWDOWN)
            : DEFAULT_SLOWDOWN;

        global.force_animations = true;
        if (!isNaN(factor) && factor > 0.0) {
            St.Settings.get().slow_down_factor = factor;
        }

        const before = St.Settings.get().enable_animations;

        this._idleId = GLib.idle_add(GLib.PRIORITY_LOW, () => {
            this._idleId = 0;
            const settings = St.Settings.get();
            console.log(
                `${LOG_PREFIX} software_rendering=` +
                `${!global.backend.is_rendering_hardware_accelerated()} ` +
                `enable_animations_before=${before} ` +
                `enable_animations_now=${settings.enable_animations} ` +
                `slow_down_factor=${settings.slow_down_factor}`);
            return GLib.SOURCE_REMOVE;
        });
    }

    disable() {
        if (this._idleId) {
            GLib.source_remove(this._idleId);
            this._idleId = 0;
        }
        global.force_animations = this._previousForceAnimations ?? false;
        if (this._previousSlowDownFactor !== undefined) {
            St.Settings.get().slow_down_factor = this._previousSlowDownFactor;
        }
    }
}
