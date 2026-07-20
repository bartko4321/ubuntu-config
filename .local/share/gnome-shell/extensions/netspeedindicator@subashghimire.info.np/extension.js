/* extension.js
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

import GObject from "gi://GObject";
import GLib from "gi://GLib";
import Gio from "gi://Gio";
import Clutter from "gi://Clutter";
import St from "gi://St";

import * as Main from "resource:///org/gnome/shell/ui/main.js";
import * as PanelMenu from "resource:///org/gnome/shell/ui/panelMenu.js";
import { Extension } from "resource:///org/gnome/shell/extensions/extension.js";

import {
  DEFAULT_REFRESH_INTERVAL,
  DEFAULT_SPEED_UNITS,
  DEFAULT_VIRTUAL_IFACE_PREFIXES
} from "./utils/config.js";

import {
  isVirtualIface,
  toSpeedString
} from "./utils/utils.js";

const PROC_NET_DEV_PATH = "/proc/net/dev";

// Indicator class
const Indicator = GObject.registerClass(
  class Indicator extends PanelMenu.Button {
    _init() {
      super._init(0.0, "Net Speed Indicator", true);

      this._label = new St.Label({
        y_align: Clutter.ActorAlign.CENTER,
        text: toSpeedString({ down: 0, up: 0 }, DEFAULT_SPEED_UNITS)
      });

      this.add_child(this._label);
    }

    setText(text) {
      this._label.set_text(text);
    }
  }
);

// Main Extension class
export default class NetSpeedIndicator extends Extension {
  constructor(metadata) {
    super(metadata);

    this._metadata = metadata;
    this._uuid = metadata.uuid;
    this._refreshInterval = metadata.refreshInterval || DEFAULT_REFRESH_INTERVAL;
    this._speedUnits = metadata.speedUnits || DEFAULT_SPEED_UNITS;
    this._virtualIfacePrefixes = metadata.virtualIfacePrefixes || DEFAULT_VIRTUAL_IFACE_PREFIXES;
  }

  enable() {
    this._textDecoder = new TextDecoder();
    this._lastSum = { down: 0, up: 0 };
    this._timeout = null;

    this._indicator = new Indicator();
    this._addIndicatorToPanel();

    this._timeout = GLib.timeout_add_seconds(
      GLib.PRIORITY_DEFAULT, this._refreshInterval, () => {
        this._updateSpeed();
        return GLib.SOURCE_CONTINUE;
      }
    );
  }

  _addIndicatorToPanel() {
    if (Main.panel && typeof Main.panel.addToStatusArea === "function") {
      Main.panel.addToStatusArea(this._uuid, this._indicator, 0, "right");
      return;
    }

    if (Main.panel && Main.panel.statusArea && Main.panel.statusArea.rightBox && typeof Main.panel.statusArea.rightBox.insert_child_at_index === "function") {
      Main.panel.statusArea.rightBox.insert_child_at_index(this._indicator, 0);
      return;
    }

    log(`Net Speed Indicator: unable to add panel indicator for shell ${this._metadata.shellVersion || "unknown"}`);
  }

  disable() {
    if (this._indicator) {
      this._indicator.destroy();
      this._indicator = null;
    }
    this._textDecoder = null;
    this._lastSum = null;
    if (this._timeout) {
      GLib.source_remove(this._timeout);
      this._timeout = null;
    }
  }

  _updateSpeed() {
    const inputFile = Gio.File.new_for_path(PROC_NET_DEV_PATH);
    inputFile.load_contents_async(null, (file, result) => {
      try {
        const [, content] = file.load_contents_finish(result);
        const speed = this._calculateSpeed(
          this._textDecoder.decode(content)
        );
        const text = toSpeedString(speed, this._speedUnits);
        this._indicator.setText(text);
      } catch (e) {
        console.error(`Error reading network speed: ${e.message}`);
      }
    });
  }

  _calculateSpeed(data) {
    const speed = { down: 0, up: 0 };

    const sum = data.split("\n")
      .map(line => line.trim().split(/\W+/))
      .filter(fields => fields.length > 2)
      .map(fields => ({
        name: fields[0],
        down: Number.parseInt(fields[1]),
        up: Number.parseInt(fields[9])
      }))
      .filter(iface => !isNaN(iface.down) && !isNaN(iface.up) && !isVirtualIface(iface.name, this._virtualIfacePrefixes))
      .reduce((sum, iface) => ({
        down: sum.down + iface.down,
        up: sum.up + iface.up
      }), { down: 0, up: 0 });

    if (this._lastSum.down === 0) this._lastSum.down = sum.down;
    if (this._lastSum.up === 0) this._lastSum.up = sum.up;

    speed.down = (sum.down - this._lastSum.down) / this._refreshInterval;
    speed.up = (sum.up - this._lastSum.up) / this._refreshInterval;

    this._lastSum = sum;
    return speed;
  }
}