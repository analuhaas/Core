%% Supervisor script
%Description to be added

clc,clear all,close all,

%% ------------------------------------------------------------------
%  USER SETTINGS FOR TEST CONFIGURATION - edit these to match what you need
%  ------------------------------------------------------------------

% Test configuration parameters
f0 = 50;
f_switching = 200e3;
syncVref       = 12;             % [V rms] target for both v_c and v_s

%  V_c and V_s alignment parameters
syncTolV       = 0.1;            % [V rms] amplitude tolerance on each voltage
syncTolPhi     = deg2rad(0.5);   % [rad] phase tolerance (0.5 deg ~ 0.1 V vector error at 12 V)
syncAlpha      = 0.5;            % fraction of the remaining error corrected per iteration
syncMaxStepM   = 0.03;           % max change of Mp / Mp_AC per iteration (ramp rate)
syncMaxStepPhi = 0.1;            % [rad] max change of phi_AC per iteration
syncVmin       = 2;              % [V rms] below this, gain and phase are not trusted -> blind ramp
syncVmax       = 15;             % [V rms] abort if either voltage exceeds this
syncMmax       = 0.95;           % Mp_AC above ~0.96 clips the DAC (0.52 offset)
syncMaxIter    = 30;
syncSettle_s   = 0.3;            % wait after writing before capturing
maxCurrentClosingA = 0.1;
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
picoSerialNumbers = {'KP306/0011'}; % <-- EDIT to your two units' serials
% picoSerialNumbers = {'KP306/0011','KP310/0061'}; % <-- EDIT to your two units' serials

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
    % 'KP310/0061', 1; ... % Channel A
    % 'KP310/0061', 2; ... % Channel B
    % 'KP310/0061', 4; ... % Channel D
    };
maxExpectedVoltageV = 20;  % peak volts

% v_c = channel D (index 4), v_s = channel C (index 3).
idxVc = 4;
idxVs = 3;
% i_c_pos = channel A (index 1), i_c_neg = channel B (index 2).
idxIa = 1;   % Channel A (i_ac_2)
idxIb = 2;   % Channel B (i_ac)
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

%% Command converter to initial configuration

ts.write("Config", struct("wBlinkPeriod_s",1.0));
ts.write("Config", struct("wmode", 0));
ts.write("Config", struct("wMp", 0.0));
ts.write("Config", struct("wphi_m", 0.0));
ts.write("Config", struct("wMpAC", 0.0));
ts.write("Config", struct("wphi_AC", 0.0));

%% Load PicoScope configuration information and device connection

[ps4000aStructs, ps4000aEnuminfo] = ps4000aSetConfig(); % DO NOT EDIT THIS LINE.

[currentProbeRangeIndex, currentProbeRangeVolts] = pico_select_voltage_range( ...
    ps4000aEnuminfo, maxExpectedCurrentA * currentProbeVoltsPerAmp);

fprintf('Current probe channels sized for %.1f A peak -> %.2f V -> range %.2f V (index %d)\n', ...
    maxExpectedCurrentA, maxExpectedCurrentA * currentProbeVoltsPerAmp, ...
    currentProbeRangeVolts, currentProbeRangeIndex);

[voltageChannelRangeIndex, voltageChannelRangeVolts] = pico_select_voltage_range( ...
    ps4000aEnuminfo, maxExpectedVoltageV);

fprintf('Voltage channels sized for %.1f V peak -> range %.2f V (index %d)\n', ...
    maxExpectedVoltageV, voltageChannelRangeVolts, voltageChannelRangeIndex);

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
dtScope = double(timeIntervalNanoSeconds{1}) * 1e-9;  % actual scope sample time

%% Synchronize vs and vc automatically (switch must be OPEN)
% Ramps Mp (-> v_c) and Mp_AC (-> v_s) up from 0 and adjusts phi_AC until
% both voltages reach syncVref rms and are in phase, with phi_m = 0 fixed.
% v_c and v_s are generated by the same firmware oscillator (same W0), so
% once aligned they stay aligned.

% Auxiliary function that limits to max value (positive and negative)
clip = @(x, lim) min(max(x, -lim), lim);

% Initializing amplitudes and phases
Mp_init = 0.0;
Mp_AC_init = 0.0;
phi_m_init = 0.0;
phi_AC_init = 0.0;

% phiSign = d(angle(vs/vc)) / d(phi_AC): +1 if increasing phi_AC moves v_s
% ahead of v_c.
phiSign = 1;
phiSignKnown = false;

% Write first commands
ts.write("Config", struct("wBlinkPeriod_s", 0.5));
ts.write("Config", struct("wphi_m", phi_m_init));
ts.write("Config", struct("wmode", 1));

syncAligned = false;
dphiPrev = NaN;     % phase error at the previous valid iteration
dPhiACPrev = 0;     % phi_AC step applied after that measurement

for k = 1:syncMaxIter

    % Sets converter/AC source operation point
    ts.write("Config", struct("wMp", Mp_init));
    ts.write("Config", struct("wMpAC", Mp_AC_init));
    ts.write("Config", struct("wphi_AC", phi_AC_init));
    pause(syncSettle_s); % Pause before doing a new voltage measurement

    % Measures v_c and v_s voltages and transform them to phasors to be able to analyse
    % its phases
    [numSamples{1}, ~, channelData{1}, ~] = picoscope_acquisition(ps4000aDeviceObj{1}, numChannels{1});
    Vc = fcn_FundamentalPhasor(channelData{1}{idxVc} / probeVoltsPerUnit{1}(idxVc), dtScope, f0);
    Vs = fcn_FundamentalPhasor(channelData{1}{idxVs} / probeVoltsPerUnit{1}(idxVs), dtScope, f0);
    VcRms = abs(Vc);
    VsRms = abs(Vs);
    phaseValid = min(VcRms, VsRms) > syncVmin;
    dphi = angle(Vs / Vc);   % > 0 : v_s leads v_c

    fprintf('Sync %2d | Mp %.4f Mp_AC %.4f phi_AC %+.3f | Vc %5.2f Vs %5.2f V | dphi %+6.2f deg | |Vs-Vc| %.2f V\n', ...
        k, Mp_init, Mp_AC_init, phi_AC_init, VcRms, VsRms, rad2deg(dphi), abs(Vs - Vc));

    if max(VcRms, VsRms) > syncVmax
        ts.write("Config", struct("wMp", 0.0));
        ts.write("Config", struct("wMpAC", 0.0));
        error('Sync aborted: voltage above %.1f V rms, Mp and Mp_AC set to 0.', syncVmax);
    end

    % Verifies end criteria: if v_c and v_s voltages are aligned in
    % amplitude and phase
    if abs(VcRms - syncVref) < syncTolV && abs(VsRms - syncVref) < syncTolV ...
            && phaseValid && abs(dphi) < syncTolPhi
        syncAligned = true;
        break;
    end

    % Identify the sign of phi_AC from the response to the previous phase
    % step. Only trusted if the measured slope is close to +/-1 and the step is big enough.
    if ~phiSignKnown && phaseValid && ~isnan(dphiPrev) && abs(dPhiACPrev) >= 0.02
        slope = angle(exp(1j * (dphi - dphiPrev))) / dPhiACPrev;
        if abs(slope) > 0.5 && abs(slope) < 2
            phiSign = sign(slope);
            phiSignKnown = true;
            fprintf('Sync: phi_AC sign identified: %+d (slope %.2f)\n', phiSign, slope);
        end
    end

    % Amplitudes update: proportional correction using the gain V/M,
    % or a blind ramp while the voltage is too small to be measured.
    if VcRms > syncVmin && Mp_init > 0
        dMp = syncAlpha * (syncVref - VcRms) * Mp_init / VcRms;
    else
        dMp = syncMaxStepM;
    end
    if VsRms > syncVmin && Mp_AC_init > 0
        dMpAC = syncAlpha * (syncVref - VsRms) * Mp_AC_init / VsRms;
    else
        dMpAC = syncMaxStepM;
    end
    % Limits variation of modulation amplitude to syncMaxStepM (both
    % positive and negative values)
    Mp_init    = min(max(Mp_init    + clip(dMp,   syncMaxStepM), 0), syncMmax);
    Mp_AC_init = min(max(Mp_AC_init + clip(dMpAC, syncMaxStepM), 0), syncMmax);

    % Phase: only corrected once both voltages are measurable.
    if phaseValid
        % Limits variation of modulation phase to syncMaxStepPhi (both
        % positive and negative values)
        dPhiAC = -clip(syncAlpha * dphi / phiSign, syncMaxStepPhi);
        dphiPrev = dphi;
    else
        dPhiAC = 0;
        dphiPrev = NaN;
    end
    dPhiACPrev = dPhiAC;
    phi_AC_init = angle(exp(1j * (phi_AC_init + dPhiAC)));   % keep in (-pi, pi]

end

% Plot the last capture of the loop (the one that met the alignment
% criteria) to check v_c and v_s visually before closing the switch.
vcSync = channelData{1}{idxVc} / probeVoltsPerUnit{1}(idxVc);
vsSync = channelData{1}{idxVs} / probeVoltsPerUnit{1}(idxVs);
tSyncMs = (0:numel(vcSync) - 1) * dtScope * 1e3;

figureSync = figure('Name', 'Alignment of v_c and v_s', 'NumberTitle', 'off');

subplot(2, 1, 1);
plot(tSyncMs, vcSync, tSyncMs, vsSync);
grid on;
ylabel('Voltage (V)');
legend('v_c (ch D)', 'v_s (ch C)');
title(sprintf('Iteration %d | V_c = %.2f V, V_s = %.2f V rms | \\Delta\\phi = %+.2f deg', ...
    k, VcRms, VsRms, rad2deg(dphi)));

subplot(2, 1, 2);
plot(tSyncMs, vsSync - vcSync);
grid on;
xlabel('Time (ms)');
ylabel('v_s - v_c (V)');
title(sprintf('Difference | fundamental |V_s - V_c| = %.2f V rms', abs(Vs - Vc)));

drawnow;   % show the figure before input() blocks

if syncAligned
    fprintf('Sync: ALIGNED after %d iterations: Mp = %.4f, Mp_AC = %.4f, phi_AC = %.4f rad\n', ...
        k, Mp_init, Mp_AC_init, phi_AC_init);
    input('Sync: start procedure to close the switch, press enter to continue... ', 's');
else
    warning('Sync: NOT aligned after %d iterations - do NOT close the switch.', syncMaxIter);
end

%% Close the switch gradually through the parallel resistors
% Steps 1-6: one resistance added in parallel (from open circuit
% towards a small resistance).
% Step 7: switch closed. After each manual
% action, the rms currents on channels A and B are measured and printed.

if ~syncAligned
    error('Switch closing: v_c and v_s are not aligned - procedure not started.');
end

numResistorSteps = 6;

for step = 1:numResistorSteps + 1

    if step <= numResistorSteps
        input(sprintf('Switch closing %d/%d: add parallel resistance %d, press enter to continue... ', ...
            step, numResistorSteps + 1, step), 's');
    else
        input(sprintf('Switch closing %d/%d: close the switch, press enter to continue... ', ...
            step, numResistorSteps + 1), 's');
    end

    [numSamples{1}, ~, channelData{1}, ~] = picoscope_acquisition(ps4000aDeviceObj{1}, numChannels{1});
    IaRms = rms(channelData{1}{idxIa} / probeVoltsPerUnit{1}(idxIa));
    IbRms = rms(channelData{1}{idxIb} / probeVoltsPerUnit{1}(idxIb));

    fprintf('Switch closing %d/%d | I_A (ch A) = %.3f A rms | I_B (ch B) = %.3f A rms\n', ...
        step, numResistorSteps + 1, IaRms, IbRms);

    if max(IaRms, IbRms) > maxCurrentClosingA
        warning('Switch closing: current above %.1f A rms (max current for switch manipulation exceeded).', ...
            maxCurrentClosingA);
    end

end

%% Command converter to a certain PQ point
Mp = Mp_init;
phi_m = 0.0;
Mp_AC = Mp_AC_init;
phi_AC = phi_AC_init;
ts.write("Config", struct("wMp", Mp));
ts.write("Config", struct("wphi_m", phi_m));
ts.write("Config", struct("wMpAC", Mp_AC));
ts.write("Config", struct("wphi_AC", phi_AC));
%% Converter acquisition

V_high_value = ts.read(measurements("VHigh"));
I_high_value = ts.read(measurements("IHigh"));
I1_low_rms = ts.read(measurements("I1rms"));
I2_low_rms = ts.read(measurements("I2rms"));
Vhigh_ripple_pp = ts.read(measurements("Vhighripple"));
temp_1_value = ts.read(measurements("Temp1"));
temp_2_value = ts.read(measurements("Temp2"));
powerP = ts.read(measurements("PowerP"));
powerQ = ts.read(measurements("PowerQ"));
% mode = ts.read(measurements("Mode"));
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


%% Command converter to aligned PQ point
Mp = Mp_init;
phi_m = 0.0;
Mp_AC = Mp_AC_init;
phi_AC = phi_AC_init;
ts.write("Config", struct("wMp", Mp));
ts.write("Config", struct("wphi_m", phi_m));
ts.write("Config", struct("wMpAC", Mp_AC));
ts.write("Config", struct("wphi_AC", phi_AC));

%% Open the switch gradually through the parallel resistors
% Steps 1: switch open.
% Step 2-7: take out one resistance added in parallel (from short circuit
% towards a open circuit). After each manual
% action, the rms currents on channels A and B are measured and printed.

if ~syncAligned
    error('Switch open: v_c and v_s are not aligned - procedure must NOT be started.');
end

numResistorSteps = 6;

for step = 1:numResistorSteps + 1

    if step > 1
        input(sprintf('Switch opening %d/%d: take out parallel resistance %d, press enter to continue... ', ...
            step, numResistorSteps + 1, step), 's');
    else
        input(sprintf('Switch opening %d/%d: open the switch, press enter to continue... ', ...
            step, numResistorSteps + 1), 's');
    end

    [numSamples{1}, ~, channelData{1}, ~] = picoscope_acquisition(ps4000aDeviceObj{1}, numChannels{1});
    IaRms = rms(channelData{1}{idxIa} / probeVoltsPerUnit{1}(idxIa));
    IbRms = rms(channelData{1}{idxIb} / probeVoltsPerUnit{1}(idxIb));

    fprintf('Switch opening %d/%d | I_A (ch A) = %.3f A rms | I_B (ch B) = %.3f A rms\n', ...
        step, numResistorSteps + 1, IaRms, IbRms);

    if max(IaRms, IbRms) > maxCurrentClosingA
        warning('Switch opening: current above %.1f A rms (max current for switch manipulation exceeded).', ...
            maxCurrentClosingA);
    end

end

%% Command converter and AC source back to initial configuration

ts.write("Config", struct("wBlinkPeriod_s",1.0));
ts.write("Config", struct("wmode", 0));
ts.write("Config", struct("wMp", 0.0));
ts.write("Config", struct("wphi_m", 0.0));
ts.write("Config", struct("wMpAC", 0.0));
ts.write("Config", struct("wphi_AC", 0.0));
%% Disconnect devices

for s = 1:numScopes

    disconnect(ps4000aDeviceObj{s});
    delete(ps4000aDeviceObj{s});

end
%% close connection
ts.close();
