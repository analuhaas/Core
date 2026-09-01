%% Supervisor script
%Description to be added

clc,clear all,close all,

addpath("Aux_MATLAB_functions");
%% ------------------------------------------------------------------
%  USER SETTINGS FOR TEST CONFIGURATION - edit these to match what you need
%  ------------------------------------------------------------------

f0 = 50;
f_switching = 200e3;

%% ------------------------------------------------------------------
%  USER SETTINGS FOR PICOSCOPE CONFIGURATION - edit these to match what you need
%  ------------------------------------------------------------------

% Time/div emulation. PicoScope's on-screen grid is 10 horizontal
% divisions, so total capture window = secondsPerDivision * 10.
secondsPerDivision = 0.010;   % 0.010 = 10 ms/div, 0.005 = 5 ms/div, ...
numDivisions       = 10;
samplesPerDivision = 1000;    % resolution you want within each division
Ts = secondsPerDivision/samplesPerDivision;

% Channel settings applied to every enabled channel (edit per-channel
% below if you need different ranges/coupling per input).
channelCoupling      = 1;  % 1 = ps4000aEnuminfo.enPS4000ACoupling.PS4000A_DC
channelRange          = 8;  % 8 = ps4000aEnuminfo.enPS4000ARange.PS4000A_5V
channelAnalogueOffset = 0.0;

% Trigger switch.
useTrigger = false;   % true = arm a simple trigger, false = free-run capture

% Simple trigger settings (only used if useTrigger = true)
triggerChannel   = 0;    % 0 = Channel A
triggerThreshold = 500;  % mV
triggerDirection = 2;    % 2 = ps4000aEnuminfo.enPS4000AThresholdDirection.PS4000A_RISING
triggerAutoMs    = 1000; % force a trigger after this many ms if none occurs

% Serial numbers of the two PicoScope units. Find these by opening
% PicoScope 6 with both units connected - the device selector lists the
% serial of each connected scope. These are NOT interchangeable with
% each other - each string must match one physical unit.
picoSerialNumbers = {'KP306/0011','KP310/0061'}; % <-- EDIT to your two units' serials

% Current-clamp probe: KP306/0011 channels A and B are wired to a clamp
% that outputs 0.1 V per 1 A measured (a "100 mV/A" clamp), not a plain
% voltage probe. Channel A already feeds i_ac below - without this
% scaling that signal is raw ADC volts, not amps, and the power
% calculation would be off by a factor of 1/currentProbeVoltsPerAmp.
currentProbeSerial      = 'KP306/0011';
currentProbeChannels    = [1 2];  % Channel A, Channel B (1-based)
currentProbeVoltsPerAmp = 0.1;    % 100 mV/A
maxExpectedCurrentA     = 2;     % size the range for this; today's signal is ~2 A

% These channels are all direct (1:1, no attenuation) voltage inputs
% using the same ~20 V peak configuration as channel D on KP306/0011 -
% they only need a bigger electrical range, no scale factor since
% nothing is dividing the voltage down.
voltageChannelList = { ...
    'KP306/0011', 4; ... % Channel D
    'KP306/0011', 3; ... % Channel C
    'KP310/0061', 1; ... % Channel A
    'KP310/0061', 2; ... % Channel B
    'KP310/0061', 4; ... % Channel D
    };
maxExpectedVoltageV = 20;  % peak volts

%% Load PicoScope configuration information and device connection

[ps4000aStructs, ps4000aEnuminfo] = ps4000aSetConfig(); % DO NOT EDIT THIS LINE.

[currentProbeRangeIndex, currentProbeRangeVolts] = pico_select_voltage_range( ...
    ps4000aEnuminfo, maxExpectedCurrentA * currentProbeVoltsPerAmp);

[voltageChannelRangeIndex, voltageChannelRangeVolts] = pico_select_voltage_range( ...
    ps4000aEnuminfo, maxExpectedVoltageV);

%% PicoScope connection, configuration
% Each PicoScope is its own independent icdevice object with its own
% clock, so connection/config/acquisition is repeated per unit. Since
% each unit runs its own runBlock() call one after the other, the two
% captures are NOT sample-aligned to each other in time - that is fine
% here because the two scopes are being read independently rather than
% needing phase-matched channels across units. If that requirement ever
% changes, both units would need to share a hardware trigger (external
% trigger signal wired into both units' EXT input) with both armed
% before the shared trigger fires, which is a bigger structural change
% than what's below.

numScopes = numel(picoSerialNumbers);

ps4000aDeviceObj  = cell(1, numScopes);
numChannels       = cell(1, numScopes);
channelLetters    = cell(1, numScopes);
timeIntervalNanoSeconds = cell(1, numScopes);
numSamples        = cell(1, numScopes);
channelData       = cell(1, numScopes);
probeVoltsPerUnit = cell(1, numScopes); % 1 for plain voltage channels, currentProbeVoltsPerAmp for clamp channels
probeUnit         = cell(1, numScopes); % 'V' or 'A' per channel, for labeling

for s = 1:numScopes

    ps4000aDeviceObj{s} = picoscope_connection(picoSerialNumbers{s});

    numChannelsThisScope = double(ps4000aDeviceObj{s}.channelCount);

    channelRangeThisScope = repmat(channelRange, 1, numChannelsThisScope);
    probeVoltsPerUnit{s}  = ones(1, numChannelsThisScope);
    probeUnit{s}          = repmat({'V'}, 1, numChannelsThisScope);

    if (strcmp(picoSerialNumbers{s}, currentProbeSerial))

        channelRangeThisScope(currentProbeChannels) = currentProbeRangeIndex;
        probeVoltsPerUnit{s}(currentProbeChannels)  = currentProbeVoltsPerAmp;
        [probeUnit{s}{currentProbeChannels}] = deal('A');

    end

    for row = 1:size(voltageChannelList, 1)

        if (strcmp(picoSerialNumbers{s}, voltageChannelList{row, 1}))

            channelRangeThisScope(voltageChannelList{row, 2}) = voltageChannelRangeIndex;
            % probeVoltsPerUnit / probeUnit stay at their defaults (1, 'V') -
            % no scaling needed for a direct, unattenuated connection.

        end

    end

    [numChannels{s}, channelLetters{s}, ~, ~, timeIntervalNanoSeconds{s}] = picoscope_config( ...
        ps4000aDeviceObj{s}, channelCoupling, channelRangeThisScope, channelAnalogueOffset, ...
        useTrigger, triggerChannel, triggerThreshold, triggerDirection, triggerAutoMs, ...
        secondsPerDivision, numDivisions, samplesPerDivision);

end

%% Configuring Thingset communication with TWIST/SPIN board

MEAS = "Measurements";
KNOWN_PORTS = "";

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

%% Command converter to start operating
ts.write("Config", struct("wBlinkPeriod_s", 0.1));
ts.write("Config", struct("wmode", 0));

%% Command AC source to sync
ts.write("Config", struct("wMpAC", 0.4));
ts.write("Config", struct("wphi_AC", 0.0));

%% Command converter to sync
ts.write("Config", struct("wMp", 0.43));
ts.write("Config", struct("wphi_m", 0.0));

%% PicoScope acquisition
for s = 1:numScopes

    [numSamples{s}, ~, channelData{s}, ~] = picoscope_acquisition(ps4000aDeviceObj{s}, numChannels{s});

    % Convert each channel's raw ADC volts into its physical unit
    % (Amps for current-clamp channels, unchanged for plain voltage
    % channels where probeVoltsPerUnit is 1).
    for ch = 1:numChannels{s}
        channelData{s}{ch} = channelData{s}{ch} / probeVoltsPerUnit{s}(ch);
    end

end

%% Process data
% Plot each scope's channels in its own subplot.

figure1 = figure('Name', 'PicoScope 4000 Series (A API) - Multi-scope Block Capture', ...
    'NumberTitle', 'off');

for s = 1:numScopes

    subplot(numScopes, 1, s);
    hold on;

    timeNs = double(timeIntervalNanoSeconds{s}) * double(0:numSamples{s} - 1);
    timeMs = timeNs / 1e6;

    legendEntries = cell(1, numChannels{s});

    for i = 1:numChannels{s}

        plot(timeMs, channelData{s}{i});
        legendEntries{i} = sprintf('Channel %s (%s)', channelLetters{s}(i), probeUnit{s}{i});

    end

    hold off;

    title(sprintf('PicoScope %d (%s) - %.3f s/div', s, picoSerialNumbers{s}, secondsPerDivision));
    xlabel('Time (ms)');

    uniqueUnits = unique(probeUnit{s});
    if (isscalar(uniqueUnits))
        ylabel(sprintf('Amplitude (%s)', uniqueUnits{1}));
    else
        ylabel('Amplitude (see legend for units)');
    end

    grid on;
    legend(legendEntries);

end

v_ac = channelData{1}{4};
i_ac_2 = channelData{1}{1};
v_ac_2 = channelData{1}{3};
i_ac = channelData{1}{2};

%% Command converter to PQ point
ts.write("Config", struct("wMp", 0.53));
ts.write("Config", struct("wphi_m", 0.0));
%% Converter acquisition

V_high_value = ts.read(measurements("VHigh"));
I_high_value = ts.read(measurements("IHigh"));
I1_peak_running = ts.read(measurements("I1rms"));
I2_peak_running = ts.read(measurements("I2rms"));
Vhigh_ripple_pp = ts.read(measurements("Vhighripple"));
temp_1_value = ts.read(measurements("Temp1"));
temp_2_value = ts.read(measurements("Temp2"));
temp_1_value = ts.read(measurements("PowerP"));
temp_2_value = ts.read(measurements("PowerQ"));
mode = ts.read(measurements("Mode"));

% Flush all measurements and their current values at once.
disp(ts.read(MEAS));

%% PicoScope acquisition
for s = 1:numScopes

    [numSamples{s}, ~, channelData{s}, ~] = picoscope_acquisition(ps4000aDeviceObj{s}, numChannels{s});

    % Convert each channel's raw ADC volts into its physical unit
    % (Amps for current-clamp channels, unchanged for plain voltage
    % channels where probeVoltsPerUnit is 1).
    for ch = 1:numChannels{s}
        channelData{s}{ch} = channelData{s}{ch} / probeVoltsPerUnit{s}(ch);
    end

end

%% Process data
% Plot each scope's channels in its own subplot.

figure1 = figure('Name', 'PicoScope 4000 Series (A API) - Multi-scope Block Capture', ...
    'NumberTitle', 'off');

for s = 1:numScopes

    subplot(numScopes, 1, s);
    hold on;

    timeNs = double(timeIntervalNanoSeconds{s}) * double(0:numSamples{s} - 1);
    timeMs = timeNs / 1e6;

    legendEntries = cell(1, numChannels{s});

    for i = 1:numChannels{s}

        plot(timeMs, channelData{s}{i});
        legendEntries{i} = sprintf('Channel %s (%s)', channelLetters{s}(i), probeUnit{s}{i});

    end

    hold off;

    title(sprintf('PicoScope %d (%s) - %.3f s/div', s, picoSerialNumbers{s}, secondsPerDivision));
    xlabel('Time (ms)');

    uniqueUnits = unique(probeUnit{s});
    if (isscalar(uniqueUnits))
        ylabel(sprintf('Amplitude (%s)', uniqueUnits{1}));
    else
        ylabel('Amplitude (see legend for units)');
    end

    grid on;
    legend(legendEntries);

end

v_ac = channelData{1}{4};
i_ac_2 = channelData{1}{1};
v_ac_2 = channelData{1}{3};
i_ac = channelData{1}{2};

%% Calculate active and reactive power

[Pab, Qab, Pfft, Qfft, P, Q] = fcn_GetPower(v_ac,i_ac,Ts,f0,f_switching);

%% Disconnect devices

for s = 1:numScopes

    disconnect(ps4000aDeviceObj{s});
    delete(ps4000aDeviceObj{s});

end

%% close connection thingset
ts.close();