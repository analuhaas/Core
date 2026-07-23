%
% Copyright (c) 2021-present LAAS-CNRS
%
%   This program is free software: you can redistribute it and/or modify
%   it under the terms of the GNU General Public License as published by
%   the Free Software Foundation, either version 2 of the License, or
%   (at your option) any later version.
%
%   This program is distributed in the hope that it will be useful,
%   but WITHOUT ANY WARRANTY; without even the implied warranty of
%   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%   GNU General Public License for more details.
%
%   You should have received a copy of the GNU General Public License
%   along with this program.  If not, see <https://www.gnu.org/licenses/>.
%
% SPDX-License-Identifier: GPL-2.0-or-later
%
% @author Luiz Villa <luiz.villa@laas.fr>
%

% thingset_example.m
%
% Usage example for ThingSetTools: discovers the device's ThingSet
% objects, auto-builds a {short_name: path} map for the Measurements
% group, reads a single measurement and the whole group, and writes a
% Config value.

%% code start
MEAS = "Measurements";

% Explicit candidate ports, skipping auto-detection: on this machine,
% serialportlist()/findPorts() enumerate several virtual "Standard Serial
% over Bluetooth link" COM ports that Windows can take tens of seconds to
% respond about, making auto-detection very slow. The board's console and
% ThingSet-shell interfaces were found at COM39 and COM40 (both
% USB\VID_2FE3&PID_0100, via Device Manager / Win32_PnPEntity) - update
% these if the board enumerates differently on your machine, or pass ""
% to fall back to auto-detection.
KNOWN_PORTS = ["COM39", "COM40"];

% Reuse an already-open connection across re-runs of this section instead
% of reconnecting every time: closing and immediately reopening the same
% USB-CDC port (what a bare `clear all` + reconnect does) can race the
% Windows driver's release of the port and fail with ConnectionFailed -
% see ThingSetTools.connect(). Run `clear ts` (or `ts.close()`) first if
% you actually want to force a fresh connection (e.g. after a board
% reset).
if ~exist("ts", "var") || ~isvalid(ts) || ~ts.isOpen()
    ts = ThingSetTools(KNOWN_PORTS, 115200, 1.0, "2FE3", "", true);
end
ts.discover();

% Auto-build {short_name: full_path} for every measurement, e.g.
% "rV1Low_V" -> name "V1Low" (between the leading "r" and the "_V" unit).
measurements = containers.Map("KeyType", "char", "ValueType", "any");
for name = ts.fetchChildren(MEAS)
    tok = regexp(char(name), "^r(.+)_(\w+)$", "tokens", "once");
    if ~isempty(tok)
        measurements(tok{1}) = char(MEAS + "/" + name);
    end
end

disp(measurements.keys);
disp(measurements.values);

disp(ts.read(measurements("V1Low")));

% Flush all measurements and their current values at once.
disp(ts.read(MEAS));


%% commands

disp(measurements.keys);
disp(measurements.values);

disp(ts.read(measurements("V1Low")));

% Flush all measurements and their current values at once.
disp(ts.read(MEAS));

ts.write("Config", struct("wBlinkPeriod_s", 0.5));

%% close connection
ts.close();
