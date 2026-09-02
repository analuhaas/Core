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

% Explicit candidate port, skipping auto-detection: on this machine,
% serialportlist()/findPorts() enumerate several virtual "Standard Serial
% over Bluetooth link" COM ports that Windows can take tens of seconds to
% respond about, making auto-detection very slow. The board exposes two
% USB\VID_2FE3&PID_0100 interfaces - COM39 (MI_00, the lowest-numbered
% interface) is the CONSOLE/UPLOAD port, COM40 (MI_02) is the dedicated
% ThingSet-shell port (see owntech/scripts/pre_bootloader_serial.py,
% which uses the same MI_00-is-console convention to pick the upload
% port). Only COM40 is listed here on purpose: opening COM39 asserts DTR
% like any serialport() connection, which appears to trigger the same
% reset-to-bootloader behavior pre_bootloader_serial.py uses
% (TouchSerialPort) to flash the board - observed as the running
% firmware's LED heartbeat stopping the moment ThingSetTools opens it,
% and both USB interfaces then failing at the OS level until the board
% is power-cycled. Update the port number if it enumerates differently on
% your machine, but do not add the console port back to this list.
KNOWN_PORTS = "";

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


%% commands

ts.write("Config", struct("wBlinkPeriod_s", 1.0));
ts.write("Config", struct("wMp", 0.6));
ts.write("Config", struct("wphi_m", 0.018));
ts.write("Config", struct("wMpAC", 0.6));
ts.write("Config", struct("wphi_AC", 0.018));
%% measures

disp(measurements.keys);
disp(measurements.values);

disp(ts.read(measurements("VHigh")));

% Flush all measurements and their current values at once.
disp(ts.read(MEAS));


%% close connection
ts.close();
