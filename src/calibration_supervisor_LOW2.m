%% Sensor calibration supervisor
% Acquires ONE calibration point per execution for the six board sensors
% (V_HIGH, V1_LOW, V2_LOW, I1_LOW, I2_LOW, I_HIGH):
%   1. connects to the board (ThingSet shell) and to the PicoScope(s),
%      reusing the connections if they are still open from a previous run;
%   2. reads the raw board measurements N_BOARD_READS times and averages;
%   3. captures the same signals once with the PicoScope and takes the mean;
%   4. appends the point to Data_records/calibration_<boardName>.mat and
%      plots every point recorded so far, with the linear fit
%      "PicoScope = gain * raw + offset" once there are 2+ points.
%
% The firmware must run with setConversionParametersLinear(X, 1, 0) on
% every sensor (raw values), which is the case of src/main.cpp.
%
% Typical use: set the power supply to an operating point, run this
% script, change the operating point, run it again, ... When all points
% are recorded, copy the printed setConversionParametersLinear() lines.

clc;
% No "clear all" on purpose: ts and pico are kept between runs so the
% connections are not closed/reopened every time.

% mfilename is empty when the code is run with "Run Section", so fall back
% to locating this script by name, then to the current folder.
scriptDir = fileparts(mfilename('fullpath'));
if isempty(scriptDir)
    scriptDir = fileparts(which('calibration_supervisor_LOW2'));
end
if isempty(scriptDir)
    scriptDir = pwd;
end
addpath('Aux_MATLAB_functions');
addpath('Data_records');

%% ------------------------------------------------------------------
%  USER SETTINGS - calibration
%  ------------------------------------------------------------------

boardName = "board_M6_LOW2";   % one calibration file per board

N_BOARD_READS      = 10;   % board reads averaged per point
BOARD_READ_PAUSE_S = 0.05; % pause between two board reads
SETTLE_TIME_S      = 1.0;  % wait after writing the converter config

% Converter command sent before measuring (HB module fed from low side,
% LEG2 at duty cycle 1 -> V_HIGH = V2_LOW).
BOARD_MODE = 2;     % 0 = idle, 1 = LEG1 at duty 1.0 (LOW1), 2 = LEG2 at duty 1.0 (LOW2)

RESET_POINTS      = false; % true = discard the points already saved for boardName
DISCONNECT_AT_END = true; % true = set board idle and close board + PicoScope

% ThingSet port: "" = auto-detection, or e.g. "COM40" to skip it.
KNOWN_PORTS = "";

% LED blink half-period written once connected. The board blinks every
% 1 s after reset: if the LED blinks at this faster rate, ThingSet works.
BLINK_PERIOD_S = 0.5;

%% ------------------------------------------------------------------
%  USER SETTINGS - PicoScope
%  ------------------------------------------------------------------

% One row per board sensor:
%   sensor, ThingSet item, PicoScope serial, channel (1 = A, 2 = B, ...),
%   probe gain [V per unit] (1 = direct/1:1, 0.1 = 10:1 probe or 100 mV/A clamp),
%   maximum expected value [unit] (sizes the PicoScope range), unit.
% Set the channel to NaN for a sensor that is not wired to the PicoScope
% in this run: its board value is still recorded, but no point is plotted.
sensorMap = { ...
    'V_HIGH', 'rVHigh_raw', '10133/0147', 1,   0.1, 50, 'V'; ...
    'I_HIGH', 'rIHigh_raw', '10133/0147', 2,   0.1,  2, 'A'; ...
    'V2_LOW', 'rV2Low_raw', '10133/0147', 3,   0.1, 50, 'V'; ...
    'I2_LOW', 'rI2Low_raw', '10133/0147', 4,   0.1,  2, 'A'; ...
    };

% Capture window = secondsPerDivision * numDivisions. The DC value is the
% mean over the window, so keep it a multiple of any ripple period.
secondsPerDivision = 0.002;   % 2 ms/div -> 20 ms window
numDivisions       = 10;
samplesPerDivision = 1000;

channelCoupling       = 1;   % 1 = PS4000A_DC (calibration is DC)
defaultChannelRange   = 8;   % 8 = PS4000A_5V, used on channels not in sensorMap
channelAnalogueOffset = 0.0;

% Largest input range of the PicoScope model, in volts at the scope input
% (e.g. 50 for a PicoScope 4824A). A sensor needing more stops the script.
picoMaxRangeV = 50;

%% ------------------------------------------------------------------
%  Sensor map checks
%  ------------------------------------------------------------------

sensorNames  = sensorMap(:, 1)';
tsItems      = sensorMap(:, 2)';
picoSerialOf = sensorMap(:, 3)';
picoChannel  = cell2mat(sensorMap(:, 4))';
probeGain    = cell2mat(sensorMap(:, 5))';
maxExpected  = cell2mat(sensorMap(:, 6))';
units        = sensorMap(:, 7)';
nSensors     = numel(sensorNames);

wired = ~isnan(picoChannel);
wiredKeys = string(picoSerialOf(wired)) + "/" + string(picoChannel(wired));
if numel(unique(wiredKeys)) < numel(wiredKeys)
    error('calibration:sensorMap', 'Two sensors are mapped to the same PicoScope channel.');
end
picoSerials = unique(picoSerialOf(wired), 'stable');

%% ------------------------------------------------------------------
%  Board connection (ThingSet)
%  ------------------------------------------------------------------

MEAS = "Measurements";

if ~exist("ts", "var") || ~isa(ts, "ThingSetTools") || ~isvalid(ts) || ~ts.isOpen()
    ts = ThingSetTools(KNOWN_PORTS, 115200, 1.0, "2FE3", "", false);
    fprintf('Board connected on %s\n', ts.Port);
end

boardItems = string(ts.fetchChildren(MEAS));
missing = setdiff(string(tsItems), boardItems);
if ~isempty(missing)
    error('calibration:thingset', ...
        'Board does not expose %s. Is the calibration firmware flashed?', strjoin(missing, ', '));
end

% Live diagnosis: the LED blink rate changes if the ThingSet link works.
ts.write("Config", struct("wBlinkPeriod_s", BLINK_PERIOD_S));

%% ------------------------------------------------------------------
%  PicoScope connection and configuration
%  ------------------------------------------------------------------

[ps4000aStructs, ps4000aEnuminfo] = ps4000aSetConfig(); % DO NOT EDIT THIS LINE.

picoReady = exist('pico', 'var') && isstruct(pico) && ...
    isequal(sort({pico.serial}), sort(picoSerials));
if picoReady
    for p = 1:numel(pico)
        picoReady = picoReady && isvalid(pico(p).dev) && strcmpi(pico(p).dev.Status, 'open');
    end
end

if ~picoReady
    if exist('pico', 'var') && isstruct(pico)
        for p = 1:numel(pico)
            try disconnect(pico(p).dev); delete(pico(p).dev); catch, end
        end
    end
    pico = struct('serial', {}, 'dev', {}, 'numChannels', {});
    for p = 1:numel(picoSerials)
        pico(p).serial = picoSerials{p};
        pico(p).dev = picoscope_connection(picoSerials{p});
        fprintf('PicoScope %s connected\n', picoSerials{p});
    end
end

% (Re)configure every run so changes in sensorMap are applied.
for p = 1:numel(pico)
    nCh = double(pico(p).dev.channelCount);
    rangeIdx = repmat(defaultChannelRange, 1, nCh);
    for s = find(wired & strcmp(picoSerialOf, pico(p).serial))
        if picoChannel(s) > nCh
            error('calibration:sensorMap', 'PicoScope %s has only %d channels (%s mapped to %d).', ...
                pico(p).serial, nCh, sensorNames{s}, picoChannel(s));
        end
        requiredV = 1.2 * maxExpected(s) * probeGain(s); % same 20% margin as pico_select_voltage_range
        if requiredV > picoMaxRangeV
            error('calibration:range', ...
                ['%s needs %.0f V at the PicoScope input (%g %s x probe gain %g, +20%% margin), ' ...
                 'more than the %g V range. Probe gain is the scope volts per unit: 0.1 for a ' ...
                 '10:1 probe. Otherwise lower the maximum expected value.'], ...
                sensorNames{s}, requiredV, maxExpected(s), units{s}, probeGain(s), picoMaxRangeV);
        end
        rangeIdx(picoChannel(s)) = pico_select_voltage_range( ...
            ps4000aEnuminfo, maxExpected(s) * probeGain(s));
    end
    try
        pico(p).numChannels = picoscope_config(pico(p).dev, channelCoupling, rangeIdx, ...
            channelAnalogueOffset, false, 0, 0, 0, 0, ...
            secondsPerDivision, numDivisions, samplesPerDivision);
    catch ME
        % Drop the connection so the next run reconnects from scratch
        % instead of reusing a PicoScope that no longer responds.
        for q = 1:numel(pico)
            try disconnect(pico(q).dev); delete(pico(q).dev); catch, end
        end
        clear pico;
        error('calibration:picoConfig', ...
            ['PicoScope configuration failed, connection closed. If the next run fails ' ...
             'again, unplug and replug the PicoScope USB cable.\n%s'], ME.message);
    end
end

%% ------------------------------------------------------------------
%  Converter command
%  ------------------------------------------------------------------

ts.write("Config", struct("wmode", BOARD_MODE));
pause(SETTLE_TIME_S);


%% ------------------------------------------------------------------
%  Calibration method: change VLOW1 5 times and execute this code each time
%  ------------------------------------------------------------------

% ------------------------------------------------------------------
%  Board acquisition: N_BOARD_READS reads of the whole Measurements group
%  ------------------------------------------------------------------

boardSamples = nan(N_BOARD_READS, nSensors);
for k = 1:N_BOARD_READS
    m = ts.read(MEAS);
    if k == 1 && isfield(m, 'rMode') && m.rMode ~= BOARD_MODE
        warning('calibration:mode', 'Board reports mode %d, %d was requested.', m.rMode, BOARD_MODE);
    end
    for s = 1:nSensors
        boardSamples(k, s) = double(m.(tsItems{s}));
    end
    pause(BOARD_READ_PAUSE_S);
end
boardMean = mean(boardSamples, 1);
boardStd  = std(boardSamples, 0, 1);

% ------------------------------------------------------------------
%  PicoScope acquisition: 1 capture, mean over the capture window
%  ------------------------------------------------------------------

picoMean = nan(1, nSensors);
for p = 1:numel(pico)
    [~, overflow, channelData] = picoscope_acquisition(pico(p).dev, pico(p).numChannels);
    for s = find(wired & strcmp(picoSerialOf, pico(p).serial))
        ch = picoChannel(s);
        if bitget(double(overflow), ch)
            warning('calibration:overflow', '%s: PicoScope channel %c over range.', ...
                sensorNames{s}, 'A' + ch - 1);
        end
        picoMean(s) = mean(double(channelData{ch})) / probeGain(s);
    end
end

fprintf('\n%-8s %14s %12s %14s\n', 'Sensor', 'Board raw', 'std', 'PicoScope');
for s = 1:nSensors
    fprintf('%-8s %14.3f %12.3f %12.4f %s\n', sensorNames{s}, ...
        boardMean(s), boardStd(s), picoMean(s), units{s});
end

% ------------------------------------------------------------------
%  Save the point
%  ------------------------------------------------------------------

dataDir = 'Data_records';
if ~isfolder(dataDir)
    mkdir(dataDir);
end
calFile = fullfile(dataDir, "calibration_" + boardName + ".mat");

if isfile(calFile) && ~RESET_POINTS
    load(calFile, 'cal');
    if ~isequal(cal.sensorNames, sensorNames)
        error('calibration:file', '%s was recorded with different sensors.', calFile);
    end
else
    cal = struct('boardName', boardName, 'sensorNames', {sensorNames}, 'units', {units}, ...
        'time', datetime.empty(0, 1), ...
        'boardRaw', zeros(0, nSensors), 'boardStd', zeros(0, nSensors), ...
        'pico', zeros(0, nSensors));
end

cal.time(end+1, 1)     = datetime('now');
cal.boardRaw(end+1, :) = boardMean;
cal.boardStd(end+1, :) = boardStd;
cal.pico(end+1, :)     = picoMean;

save(calFile, 'cal');
fprintf('\nPoint %d saved to %s\n', size(cal.boardRaw, 1), calFile);

%% ------------------------------------------------------------------
%  Converter command
%  ------------------------------------------------------------------

ts.write("Config", struct("wmode", 0));
pause(SETTLE_TIME_S);
disp(ts.read(MEAS));
%% ------------------------------------------------------------------
%  Fit and plot every point recorded so far
%  ------------------------------------------------------------------
% Loads the .mat file, so it also works later on its own, e.g.
%   calibration_fit_plot("Data_records/calibration_board_01_LOW1.mat")
% or calibration_fit_plot() to pick the file in a dialog.
calFile = fullfile(dataDir, "calibration_" + boardName + ".mat");
cal = calibration_fit_plot(calFile);

%% ------------------------------------------------------------------
%  Disconnect (only when DISCONNECT_AT_END = true)
%  ------------------------------------------------------------------

if DISCONNECT_AT_END
    ts.write("Config", struct("wmode", 0));
    ts.write("Config", struct("wBlinkPeriod_s", 1.0));
    ts.close();
    clear ts;
    for p = 1:numel(pico)
        disconnect(pico(p).dev);
        delete(pico(p).dev);
    end
    clear pico;
    fprintf('Board set to idle, board and PicoScope disconnected.\n');
end
