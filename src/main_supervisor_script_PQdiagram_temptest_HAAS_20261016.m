%% Supervisor script
%Description to be added

clc,clear all,close all,

addpath("functions\")
%% ------------------------------------------------------------------
%  USER SETTINGS FOR TEST CONFIGURATION - edit these to match what you need
%  ------------------------------------------------------------------

% Test configuration parameters
f0 = 50;
f_switching = 200e3;
syncVref       = 12;             % [V rms] target for both v_c and v_s

%  V_c and V_s alignment parameters
syncTolV       = 0.02;            % [V rms] amplitude tolerance on each voltage
syncTolPhi     = 0.001;   % [rad] phase tolerance
syncAlpha      = 0.5;            % fraction of the remaining error corrected per iteration
syncMaxStepM   = 0.03;           % max change of Mp / Mp_AC per iteration (ramp rate)
syncMaxStepPhi = 0.1;            % [rad] max change of phi_AC per iteration
syncVmin       = 2;              % [V rms] below this, gain and phase are not trusted -> blind ramp
syncVmax       = 15;             % [V rms] abort if either voltage exceeds this
syncMmax       = 0.95;           % Mp_AC above ~0.96 clips the DAC (0.52 offset)
syncMaxIter    = 30;
syncSettle_s   = 0.3;            % wait after writing before capturing
maxCurrentClosingA = 0.1;

%  V_c regulation parameters (keeps v_c amplitude and phase fixed when current flows)
vcRegTolV       = 0.02;            % [V rms] amplitude tolerance on v_c
vcRegTolPhi     = 0.001;   % [rad] phase tolerance on v_c (relative to the internal oscillator)
vcRegAlpha      = 0.5;            % fraction of the remaining error corrected per iteration
vcRegMaxStepM   = 0.03;           % max change of Mp_AC per iteration
vcRegMaxStepPhi = 0.1;            % [rad] max change of phi_AC per iteration
vcRegMaxIter    = 20;
vcRegSettle_s   = 0.1;            % wait after writing before capturing

%  MOSFET temperature monitoring parameters (to check thermal steady state)
tempMonitorDuration_s = 3600;      % [s] total monitoring time (30 min)
tempMonitorPeriod_s   = 60;       % [s] time between two temperature readings (1 min)
tempBurstCount        = 30;       % each reading is the mean of this many single readings...
tempBurstSpacing_s    = 0.1;      % [s] ...spaced by this time

%  MOSFET temperature series parameters (single readings, no averaging)
tempSeriesPoints    = 1000;       % number of Temp1/Temp2 readings
tempSeriesSpacing_s = 1;          % [s] time between two readings

%  Ramp parameters of the converter operating point (Mp, phi_m)
rampMaxStepM    = 0.001;          % max change of Mp per step
rampMaxStepPhi  = 0.0001;          % [rad] max change of phi_m per step
rampStepPause_s = 0.05;            % wait after each step

%  ScopeMimicry parameters (board scope, dumped on the console port)
consolePort    = "";              % board console port, e.g. "COM41" - "" = the board port not used by ThingSet
scopeTs        = 100e-6;          % [s] ScopeMimicry sample time (CONTROL_TASK_PERIOD_US in main.cpp)
scopeTimeout_s = 10;              % [s] max time to wait for the capture and for the dump
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

% Serial numbers of the two PicoScope units.
picoSerialNumbers = {'KP306/0011','KP310/0061'}; % <-- EDIT to your two units' serials

% Current-clamp probes:
currentProbeChannelList = { ...
    'KP306/0011', 1; ... % Channel A (i_c_pos)
    'KP310/0061', 2; ... % Channel B (i_dc)
    'KP310/0061', 3; ... % Channel C (i_c_neg)
    };
currentProbeVoltsPerAmp = 0.1;    % 100 mV/A
maxExpectedCurrentA     = 5;     % size the range for this; today's signal is ~2 A

% These channels are all direct (1:1, no attenuation) voltage inputs
% using the same ~20 V peak configuration as channel D on KP306/0011 -
% they only need a bigger electrical range, no scale factor since
% nothing is dividing the voltage down.
voltageChannelList = { ...
    'KP306/0011', 2; ... % Channel B
    'KP306/0011', 3; ... % Channel C
    'KP306/0011', 4; ... % Channel D
    'KP310/0061', 4; ... % Channel D
    };
maxExpectedVoltageV = 20;  % peak volts

% Differential voltage probes: the scope sees the measured voltage divided by
% the probe attenuation. The range is sized for maxExpectedDiffProbeV / attenuation
% and the curves are scaled back to the measured voltage.
% One row per probe: {serial, channel (1-based), attenuation}.
diffProbeChannelList = { ...
    'KP310/0061', 1, 10; ... % Channel A (u_dc), differential probe 1/10
    };
maxExpectedDiffProbeV = 60;  % [V] peak measured voltage (before the probe attenuation)

% DAC output of the SPIN board (input of the power amplifier that generates
% v_s).
dacSerial       = 'KP306/0011';
maxExpectedDacV = 2;   % peak volts (DAC output range 0-2 V)

% PicoScope 1 (KP306/0011):
% i_c_pos = channel A (index 1), v_DAC output = channel B (index 2),
% v_s = channel C (index 3), v_c = channel D (index 4).
idxIcpos = 1;  
idxVdac = 2;
idxVs = 3;
idxVc = 4;
% PicoScope 2 (KP310/0061):
% u_dc = channel A (index 1), i_dc = channel B (index 2),
% i_c_neg = channel C (index 3), v_s = channel D (index 4).
idxUdc = 1;
idxIdc = 2;
idxIcneg = 3;
idxVs2 = 4;

% Channel indices used by fcn_save_PQ_point (PicoScope 1 / PicoScope 2)
chIdx.Icpos = idxIcpos;
chIdx.Vdac = idxVdac;
chIdx.Vs = idxVs;
chIdx.Vc = idxVc;
chIdx.Udc = idxUdc;
chIdx.Idc = idxIdc;
chIdx.Icneg = idxIcneg;
chIdx.Vs2 = idxVs2;

%% Configuring Thingset communication with TWIST/SPIN board

input('Board code: upload boards code with PlatformIO in VSCode, press enter to continue... ', 's');
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

%% Opening the console port of the TWIST/SPIN board (ScopeMimicry dump)
% The board has two USB serial ports with the same VID: the ThingSet shell
% (used by ts) and the console, where printk writes the ScopeMimicry dump.
% Opened like ThingSetTools does, WITHOUT FlowControl: a DTR/RTS mismatch
% resets the board into its bootloader.

if consolePort == ""
    consolePort = setdiff(ThingSetTools.findPorts("2FE3", "", false), ts.Port);
end
if numel(consolePort) ~= 1
    error('Console port not found (candidates: %s) - set consolePort in the user settings.', strjoin(consolePort, ", "));
end
con = serialport(consolePort, 115200, "Timeout", 5);
configureTerminator(con, "LF");
fprintf('Console port (ScopeMimicry): %s | ThingSet port: %s\n', consolePort, ts.Port);

%% Command converter to initial configuration

ts.write("Config", struct("wBlinkPeriod_s",1.0));
ts.write("Config", struct("wmode", 0));
ts.write("Config", struct("wMp", 0.0));
ts.write("Config", struct("wphi_m", 0.0));
ts.write("Config", struct("wMpAC", 0.0));
ts.write("Config", struct("wphi_AC", 0.0));

%% Load PicoScope configuration information and device connection

input('Current probes: turn on current probes, press enter to continue... ', 's');
input('Before PicoScope connection: Check if current probes offset is close to 0 with PicoScope, press enter to continue... ', 's');
input('Voltage probe: turn on voltage probe, press enter to continue... ', 's');

[ps4000aStructs, ps4000aEnuminfo] = ps4000aSetConfig(); % DO NOT EDIT THIS LINE.

%% PicoScope connection, configuration

% Everything fcn_picoscope_setup needs from the USER SETTINGS FOR PICOSCOPE CONFIGURATION
picoCfg.picoSerialNumbers = picoSerialNumbers;
picoCfg.channelCoupling = channelCoupling;
picoCfg.channelRange = channelRange;
picoCfg.channelAnalogueOffset = channelAnalogueOffset;
picoCfg.useTrigger = useTrigger;
picoCfg.triggerChannel = triggerChannel;
picoCfg.triggerThreshold = triggerThreshold;
picoCfg.triggerDirection = triggerDirection;
picoCfg.triggerAutoMs = triggerAutoMs;
picoCfg.secondsPerDivision = secondsPerDivision;
picoCfg.numDivisions = numDivisions;
picoCfg.samplesPerDivision = samplesPerDivision;
picoCfg.currentProbeChannelList = currentProbeChannelList;
picoCfg.currentProbeVoltsPerAmp = currentProbeVoltsPerAmp;
picoCfg.maxExpectedCurrentA = maxExpectedCurrentA;
picoCfg.voltageChannelList = voltageChannelList;
picoCfg.maxExpectedVoltageV = maxExpectedVoltageV;
picoCfg.diffProbeChannelList = diffProbeChannelList;
picoCfg.maxExpectedDiffProbeV = maxExpectedDiffProbeV;
picoCfg.dacSerial = dacSerial;
picoCfg.dacChannel = idxVdac;
picoCfg.maxExpectedDacV = maxExpectedDacV;

[ps4000aDeviceObj, numChannels, channelLetters, timeIntervalNanoSeconds, probeVoltsPerUnit, probeUnit, dtScope] = ...
    fcn_picoscope_setup(picoCfg, ps4000aEnuminfo);
numScopes = numel(ps4000aDeviceObj);

%% Start the equipments

input('Startup converter: check if software limit is at 2 A, press enter to continue... ', 's');
input('Temperature measure: check if the temperature sensors are on the MOSFET drain/case, press enter to continue... ', 's');
input('Startup DC supply: check if DC supply limit is at 2 A, press enter to continue... ', 's');
input('Startup DC supply: turn on DC supply, press enter to continue... ', 's');

%% Ambient MOSFET temperature (right after u_dc is turned on)
% Taken before the sync: from here on the switch heats up only by having
% u_dc applied, so this is the reference at ambient temperature. Same
% reading as the monitoring (mean of tempBurstCount readings spaced by
% tempBurstSpacing_s); it is added to the monitoring plot and file.
ts.write("Config", struct("wBlinkPeriod_s",0.1)); % Temp1/Temp2 refreshed every 0.1 s, as during the monitoring

pause(5); % Wait for MCU startup

tempAmbient.time = datetime('now');
[tempAmbient.Temp1, tempAmbient.Temp2, tempAmbient.Burst1, tempAmbient.Burst2] = ...
    fcn_read_temperature_burst(ts, measurements, tempBurstCount, tempBurstSpacing_s);
fprintf('Ambient temperature | T_MOSFET Temp1 = %.2f degC | Temp2 = %.2f degC (mean of %d)\n', ...
    tempAmbient.Temp1, tempAmbient.Temp2, tempBurstCount);

ts.write("Config", struct("wBlinkPeriod_s",1.0));

%% Start the AC source

input('Startup AC source: check if Philibert limit is at 2 A, press enter to continue... ', 's');
input('Startup AC source: turn on Philibert (check + validate button), press enter to continue... ', 's');

%% Command converter to a certain voltage where v_s and v_c are no sync
Mp = 0.2;
phi_m = 0.0;
Mp_AC = 0.4;
phi_AC = 0.0;
ts.write("Config", struct("wmode", 1));
ts.write("Config", struct("wMp", Mp));
ts.write("Config", struct("wphi_m", phi_m));
ts.write("Config", struct("wMpAC", Mp_AC));
ts.write("Config", struct("wphi_AC", phi_AC));
%% Converter and PicoScope acquisition, process data - BEFORE V_S V_C ALIGNMENT CHECKPOINT

boardMeas = fcn_converter_acquisition(ts, measurements, MEAS);
[channelData, numSamples] = fcn_picoscope_acquisition_scopes(ps4000aDeviceObj, numChannels, probeVoltsPerUnit);
scopeMimicry = fcn_scope_mimicry_acquisition(ts, con, scopeTs, scopeTimeout_s);
fcn_plot_picoscope(channelData, numSamples, timeIntervalNanoSeconds, channelLetters, probeUnit, picoSerialNumbers, secondsPerDivision);
fcn_plot_scope_mimicry(scopeMimicry);

% Calculate active, reactive and DC power and save the PQ point
[Pfft, Qfft, Pdc] = fcn_save_PQ_point(channelData, chIdx, boardMeas, ...
    Mp, phi_m, Mp_AC, phi_AC, Ts, timeIntervalNanoSeconds, f0, f_switching, scopeMimicry);

%% Synchronize vs and vc automatically (switch must be OPEN)
% Ramps Mp (-> v_c) and Mp_AC (-> v_s) up from 0 and adjusts phi_AC until
% both voltages reach syncVref rms and are in phase, with phi_m = 0 fixed.
% Also gives VcClkRef phasor, the no-load reference of the v_c regulation.

% Everything fcn_sync_vs_vc needs to command the converter/AC source and measure v_c, v_s
syncCfg.ts = ts;
syncCfg.ps4000aDeviceObj = ps4000aDeviceObj{1};
syncCfg.numChannels = numChannels{1};
syncCfg.probeVoltsPerUnit = probeVoltsPerUnit{1};
syncCfg.idxVc = idxVc;
syncCfg.idxVs = idxVs;
syncCfg.idxVdac = idxVdac;
syncCfg.dtScope = dtScope;
syncCfg.f0 = f0;
syncCfg.Vref = syncVref;
syncCfg.TolV = syncTolV;
syncCfg.TolPhi = syncTolPhi;
syncCfg.Alpha = syncAlpha;
syncCfg.MaxStepM = syncMaxStepM;
syncCfg.MaxStepPhi = syncMaxStepPhi;
syncCfg.Vmin = syncVmin;
syncCfg.Vmax = syncVmax;
syncCfg.Mmax = syncMmax;
syncCfg.MaxIter = syncMaxIter;
syncCfg.Settle_s = syncSettle_s;

[Mp_init, Mp_AC_init, phi_m_init, phi_AC_init, VcClkRef, syncAligned, syncCapture] = fcn_sync_vs_vc(syncCfg);

% The board is now at the aligned point: keep the operating point variables
% consistent with it (used by the next acquisitions and file names)
Mp = Mp_init; phi_m = phi_m_init; Mp_AC = Mp_AC_init; phi_AC = phi_AC_init;

if syncAligned
    input('Sync: start procedure to close the switch, press enter to continue... ', 's');
end
%% Converter and PicoScope acquisition, process data - AFTER V_S V_C ALIGNMENT CHECKPOINT

boardMeas = fcn_converter_acquisition(ts, measurements, MEAS);
[channelData, numSamples] = fcn_picoscope_acquisition_scopes(ps4000aDeviceObj, numChannels, probeVoltsPerUnit);
scopeMimicry = fcn_scope_mimicry_acquisition(ts, con, scopeTs, scopeTimeout_s);
fcn_plot_picoscope(channelData, numSamples, timeIntervalNanoSeconds, channelLetters, probeUnit, picoSerialNumbers, secondsPerDivision);
fcn_plot_scope_mimicry(scopeMimicry);

% Calculate active, reactive and DC power and save the PQ point
[Pfft, Qfft, Pdc] = fcn_save_PQ_point(channelData, chIdx, boardMeas, ...
    Mp, phi_m, Mp_AC, phi_AC, Ts, timeIntervalNanoSeconds, f0, f_switching, scopeMimicry);

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
    IaRms = rms(channelData{1}{idxIcpos} / probeVoltsPerUnit{1}(idxIcpos));

    fprintf('Switch closing %d/%d | I_A (ch A) = %.3f A rms\n', ...
        step, numResistorSteps + 1, IaRms);

    if IaRms > maxCurrentClosingA
        warning('Switch closing: current above %.1f A rms (max current for switch manipulation exceeded).', ...
            maxCurrentClosingA);
    end

end
%% Converter and PicoScope acquisition, process data - AFTER SWITCH CLOSED CHECKPOINT

boardMeas = fcn_converter_acquisition(ts, measurements, MEAS);
[channelData, numSamples] = fcn_picoscope_acquisition_scopes(ps4000aDeviceObj, numChannels, probeVoltsPerUnit);
scopeMimicry = fcn_scope_mimicry_acquisition(ts, con, scopeTs, scopeTimeout_s);
fcn_plot_picoscope(channelData, numSamples, timeIntervalNanoSeconds, channelLetters, probeUnit, picoSerialNumbers, secondsPerDivision);
fcn_plot_scope_mimicry(scopeMimicry);

% Calculate active, reactive and DC power and save the PQ point
[Pfft, Qfft, Pdc] = fcn_save_PQ_point(channelData, chIdx, boardMeas, ...
    Mp, phi_m, Mp_AC, phi_AC, Ts, timeIntervalNanoSeconds, f0, f_switching, scopeMimicry);

%% Command converter to a certain PQ point

Delta_Mp = 0.07;
Delta_phi = 0.0;

% Ramps (Mp, phi_m) from the aligned point (Mp_init, phi_m_init) to the target
Mp_target = Mp_init+Delta_Mp;
phi_m_target = Delta_phi;
Mp_AC = Mp_AC_init;
phi_AC = phi_AC_init;

ts.write("Config", struct("wBlinkPeriod_s",1.0));
ts.write("Config", struct("wmode", 1));
ts.write("Config", struct("wMpAC", Mp_AC));
ts.write("Config", struct("wphi_AC", phi_AC));
[Mp, phi_m] = fcn_ramp_M_phi(ts, Mp_init, phi_m_init, Mp_target, phi_m_target, ...
    rampMaxStepM, rampMaxStepPhi, rampStepPause_s);

% Converter and PicoScope acquisition, process data - AFTER SETTING PQ CHECKPOINT

boardMeas = fcn_converter_acquisition(ts, measurements, MEAS);
[channelData, numSamples] = fcn_picoscope_acquisition_scopes(ps4000aDeviceObj, numChannels, probeVoltsPerUnit);
scopeMimicry = fcn_scope_mimicry_acquisition(ts, con, scopeTs, scopeTimeout_s);
fcn_plot_picoscope(channelData, numSamples, timeIntervalNanoSeconds, channelLetters, probeUnit, picoSerialNumbers, secondsPerDivision);
fcn_plot_scope_mimicry(scopeMimicry);

% Calculate active, reactive and DC power and save the PQ point
[Pfft, Qfft, Pdc] = fcn_save_PQ_point(channelData, chIdx, boardMeas, ...
    Mp, phi_m, Mp_AC, phi_AC, Ts, timeIntervalNanoSeconds, f0, f_switching, scopeMimicry);

% Regulate v_c amplitude and phase at this PQ point
% v_s is generated by a power amplifier + transformer and the closed switch
% adds a voltage drop between v_s and v_c, so v_c drops and shifts with the
% converter current. Mp_AC and phi_AC are corrected until v_c is back to the
% amplitude (syncVref) and phase (relative to the internal oscillator) it had
% at no load at the end of the sync - like an ideal grid at the converter
% terminals. The converter operating point (Mp, phi_m) is not changed.

% Everything fcn_regulate_Vc needs to command the AC source and measure v_c, v_s
vcReg.ts = ts;
vcReg.ps4000aDeviceObj = ps4000aDeviceObj{1};
vcReg.numChannels = numChannels{1};
vcReg.probeVoltsPerUnit = probeVoltsPerUnit{1};
vcReg.idxVc = idxVc;
vcReg.idxVs = idxVs;
vcReg.idxVdac = idxVdac;
vcReg.dtScope = dtScope;
vcReg.f0 = f0;
vcReg.TolV = vcRegTolV;
vcReg.TolPhi = vcRegTolPhi;
vcReg.Alpha = vcRegAlpha;
vcReg.MaxStepM = vcRegMaxStepM;
vcReg.MaxStepPhi = vcRegMaxStepPhi;
vcReg.MaxIter = vcRegMaxIter;
vcReg.Settle_s = vcRegSettle_s;
vcReg.Mmax = syncMmax;
vcReg.Vmax = syncVmax;

[Mp_AC, phi_AC, VcClk, vcRegulated, ~, regCapture] = fcn_regulate_Vc(vcReg, Mp_AC, phi_AC, VcClkRef);

fprintf('Vc regulation: Mp_AC = %.4f, phi_AC = %+.4f rad | Vc = %.2f V rms, phase error %+.2f deg\n', ...
    Mp_AC, phi_AC, abs(VcClk), rad2deg(angle(VcClk / VcClkRef)));

% v_c after the regulation vs its reference from the alignment, with the DAC voltages
fcn_plot_vc_regulation(syncCapture, regCapture, f0);

% Converter and PicoScope acquisition, process data - AFTER V_C REGULATION CHECKPOINT

boardMeas = fcn_converter_acquisition(ts, measurements, MEAS);
[channelData, numSamples] = fcn_picoscope_acquisition_scopes(ps4000aDeviceObj, numChannels, probeVoltsPerUnit);
scopeMimicry = fcn_scope_mimicry_acquisition(ts, con, scopeTs, scopeTimeout_s);
fcn_plot_picoscope(channelData, numSamples, timeIntervalNanoSeconds, channelLetters, probeUnit, picoSerialNumbers, secondsPerDivision);
fcn_plot_scope_mimicry(scopeMimicry);

% Calculate active, reactive and DC power and save the PQ point
[Pfft, Qfft, Pdc] = fcn_save_PQ_point(channelData, chIdx, boardMeas, ...
    Mp, phi_m, Mp_AC, phi_AC, Ts, timeIntervalNanoSeconds, f0, f_switching, scopeMimicry);

%% Monitor MOSFET temperature to check thermal steady state
% Every tempMonitorPeriod_s for tempMonitorDuration_s, reads Temp1 and Temp2
% tempBurstCount times spaced by tempBurstSpacing_s and uses their mean, then
% plots them so the user can judge if they are stable, together with the
% ambient reading taken when u_dc was turned on. Means, all the individual
% readings and the ambient reading are saved in TempMonitor_*.mat.
ts.write("Config", struct("wBlinkPeriod_s",0.1));

[tempMonitorTime_s, tempMonitorTemp1, tempMonitorTemp2, figureTemp] = ...
    fcn_monitor_temperature(ts, measurements, tempMonitorDuration_s, tempMonitorPeriod_s, ...
    tempBurstCount, tempBurstSpacing_s, tempAmbient);

%% Monitor MOSFET temperature - series of single readings
% Reads Temp1 and Temp2 tempSeriesPoints times spaced by tempSeriesSpacing_s
% (no averaging), then plots them. Saved in TempSeries_*.mat.

ts.write("Config", struct("wBlinkPeriod_s",1.0));
[tempSeriesTime_s, tempSeriesTemp1, tempSeriesTemp2, figureTempSeries] = ...
    fcn_monitor_temperature_series(ts, measurements, tempSeriesPoints, tempSeriesSpacing_s);

%% Converter and PicoScope acquisition, process data

boardMeas = fcn_converter_acquisition(ts, measurements, MEAS);
[channelData, numSamples] = fcn_picoscope_acquisition_scopes(ps4000aDeviceObj, numChannels, probeVoltsPerUnit);
scopeMimicry = fcn_scope_mimicry_acquisition(ts, con, scopeTs, scopeTimeout_s);
fcn_plot_picoscope(channelData, numSamples, timeIntervalNanoSeconds, channelLetters, probeUnit, picoSerialNumbers, secondsPerDivision);
fcn_plot_scope_mimicry(scopeMimicry);

% Calculate active, reactive and DC power and save the PQ point
[Pfft, Qfft, Pdc] = fcn_save_PQ_point(channelData, chIdx, boardMeas, ...
    Mp, phi_m, Mp_AC, phi_AC, Ts, timeIntervalNanoSeconds, f0, f_switching, scopeMimicry);

%% Command converter to aligned PQ point
% Ramps (Mp, phi_m) back from the current PQ point to the aligned point
% (Mp_init, phi_m_init), then sets the AC source back to its aligned values

[Mp, phi_m] = fcn_ramp_M_phi(ts, Mp, phi_m, Mp_init, phi_m_init, rampMaxStepM, rampMaxStepPhi, rampStepPause_s);

Mp_AC = Mp_AC_init;
phi_AC = phi_AC_init;
ts.write("Config", struct("wMpAC", Mp_AC));
ts.write("Config", struct("wphi_AC", phi_AC));

%% Open the switch gradually through the parallel resistors
% Steps 1: switch open.
% Step 2-7: take out one resistance added in parallel (from short circuit
% towards a open circuit).

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
    IaRms = rms(channelData{1}{idxIcpos} / probeVoltsPerUnit{1}(idxIcpos));

    fprintf('Switch opening %d/%d | I_A (ch A) = %.3f A rms\n', ...
        step, numResistorSteps + 1, IaRms);

    if IaRms > maxCurrentClosingA
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
delete(con); % console port (ScopeMimicry)

%% Stop the equipments

input('DC supply: turn off DC supply, press enter to continue... ', 's');
input('AC source: turn off Philibert (uncheck + validate button), press enter to continue... ', 's');
input('Current probes: turn off current probes, press enter to continue... ', 's');