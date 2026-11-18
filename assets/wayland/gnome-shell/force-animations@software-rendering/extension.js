/* Force GNOME Shell animations on software rendering.
 *
 * GNOME Shell inhibits animations whenever rendering is not hardware
 * accelerated (llvmpipe/swrast: VMs, CRD, VNC, RDP). That inhibit
 * overrides org.gnome.desktop.interface enable-animations.
 * global.force_animations is the supported override and can only be
 * set from inside the shell, hence this extension.
 *
 * St.Settings.slow_down_factor is also applied (default 2.5, override
 * with the GNOME_SHELL_SLOWDOWN_FACTOR environment variable).
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
