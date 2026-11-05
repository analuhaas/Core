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
syncTolV       = 0.005;            % [V rms] amplitude tolerance on each voltage
syncTolPhi     = 0.0005;   % [rad] phase tolerance
syncAlpha      = 0.5;            % fraction of the remaining error corrected per iteration
syncMaxStepM   = 0.1;           % max change of Mp / Mp_AC per iteration (ramp rate)
syncMaxStepPhi = 0.2;            % [rad] max change of phi_AC per iteration
syncVmin       = 2;              % [V rms] below this, gain and phase are not trusted -> blind ramp
syncVmax       = 15;             % [V rms] abort if either voltage exceeds this
syncMmax       = 0.95;           % Mp_AC above ~0.96 clips the DAC (0.52 offset)
syncMaxIter    = 30;
syncSettle_s   = 0.3;            % wait after writing before capturing
maxCurrentClosingA = 0.1;

%  V_c regulation parameters (keeps v_c amplitude and phase fixed when current flows)
vcRegTolV       = 0.005;            % [V rms] amplitude tolerance on v_c
vcRegTolPhi     = 0.0005;   % [rad] phase tolerance on v_c (relative to the internal oscillator)
vcRegAlpha      = 1.0;            % fraction of the remaining error corrected per iteration
vcRegMaxStepM   = 0.5;           % max change of Mp_AC per iteration
vcRegMaxStepPhi = 0.5;            % [rad] max change of phi_AC per iteration
vcRegMaxIter    = 300;
vcRegSettle_s   = 0.1;            % wait after writing before capturing

%  Ramp parameters of the converter operating point (Mp, phi_m)
rampMaxStepM    = 0.001;          % max change of Mp per step
rampMaxStepPhi  = 0.01;          % [rad] max change of phi_m per step
rampStepPause_s = 0.05;            % wait after each step

%  PQ plane exploration (as in fcn_step1_PQ_fullbridge_smallestconstraint_v3)
target_angle_deg = 0:30:330; % [°] direction to search (0° = +P axis, 90° = +Q axis). Vector to sweep several angles in one run.
step_M_init = 0.02; %initial step used to scan different modulation amplitudes (also the Jacobian calibration step)
step_phi_init = 0.04; %[rad] initial step used to scan different modulation phases (also the Jacobian calibration step)
step_M_jacobian = 0.1; %initial step used to scan different modulation amplitudes (also the Jacobian calibration step)
step_phi_jacobian = 0.2; %[rad] initial step used to scan different modulation phases (also the Jacobian calibration step)
delta_S_init = 5; %[VA] initial S step accepted from one PQ point to the next one
singular_tol = 1e-6; %below this |det(A)| the two calibration steps are considered numerically parallel
step_scale_min = 0.0; %per-iteration limits on the delta_S-based step_M/step_phi rescaling (avoids abrupt jumps)
step_scale_max = 1.2;

% Limits considered in the PQ diagram (measurable ones of the simulation)
If_lim = 4; %low-side fuse current limit [A rms] (rms of i_c_pos)
Il_lim = 13; %low-side inductance current limit [A rms] (rms of i_c_pos)
Tj_lim = 448; %MOSFET temperature limit [K] (board Temp1)
tempBurstCount = 10; %the temperature used by the constraint is the mean of this many Temp1 readings...
tempBurstSpacing_s = 0.1; %[s] ...spaced by this time

% Equipment limits - shown in the startup checks, set the equipment accordingly
converterSoftwareLimitA = 10; %[A peak] MAX_CURRENT and MAX_CURRENT_OPERATION in main.cpp
dcSupplyLimitA = 9; %[A] DC supply current limit
acSourceLimitA = 9; %[A] AC source (Philibert) current limit

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

input(sprintf('Startup converter: check if software limit (MAX_CURRENT in main.cpp) is at %g A, press enter to continue... ', converterSoftwareLimitA), 's');

MEAS = "Measurements";
KNOWN_PORTS = "";

if ~exist("ts", "var") || ~isvalid(ts) || ~ts.isOpen()
    ts = ThingSetTools(KNOWN_PORTS, 115200, 1.0, "2FE3", "", false);
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
input('Before PicoScope connection: Close all PicoScope windows, press enter to continue... ', 's');
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

input(sprintf('Startup DC supply: check if DC supply limit is at %g A, press enter to continue... ', dcSupplyLimitA), 's');
input('Startup DC supply: turn on DC supply, press enter to continue... ', 's');
input(sprintf('Startup AC source: check if Philibert limit is at %g A, press enter to continue... ', acSourceLimitA), 's');
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

%% Explore the PQ plane until the first constraint is activated
% Experimental version of fcn_step1_PQ_fullbridge_smallestconstraint_v3:
% Starts from the aligned point (P,Q)~=(0,0) (switch closed)
% Each angle line of target_angle_deg is followed by changing (M_p, phi_m)
% until at least one constraint is activated (black point).
% 
% Every point has v_c regulated (fcn_measure_PQ_point_vcreg):
% ramp of (M_p, phi_m) from the previous point, v_c regulation by the
% AC source starting from the regulated values of the previous point of
% the same angle line, then acquisition and saving.
% 
% After a black point, (M_p, phi_m) are ramped back down to the
% aligned point and the AC source is set back to its aligned values.

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

% Everything fcn_measure_PQ_point_vcreg needs to ramp, regulate, acquire and save a point
bench.ts = ts;
bench.con = con;
bench.measurements = measurements;
bench.MEAS = MEAS;
bench.ps4000aDeviceObj = ps4000aDeviceObj;
bench.numChannels = numChannels;
bench.probeVoltsPerUnit = probeVoltsPerUnit;
bench.timeIntervalNanoSeconds = timeIntervalNanoSeconds;
bench.channelLetters = channelLetters;
bench.probeUnit = probeUnit;
bench.picoSerialNumbers = picoSerialNumbers;
bench.secondsPerDivision = secondsPerDivision;
bench.chIdx = chIdx;
bench.Ts = Ts;
bench.f0 = f0;
bench.f_switching = f_switching;
bench.scopeTs = scopeTs;
bench.scopeTimeout_s = scopeTimeout_s;
bench.rampMaxStepM = rampMaxStepM;
bench.rampMaxStepPhi = rampMaxStepPhi;
bench.rampStepPause_s = rampStepPause_s;
bench.vcReg = vcReg;
bench.VcClkRef = VcClkRef;
bench.syncCapture = syncCapture;
bench.tempBurstCount = tempBurstCount;
bench.tempBurstSpacing_s = tempBurstSpacing_s;

% Initialize loop parameters
k = 0; %initialize counter

M = []; %modulation amplitude array that saves all M_p scanned
phi_m_scan = []; %modulation phase array that saves all phi_m scanned
theta_scan = []; %angle line that produced each scanned point
delta_S_step_fine = delta_S_init/2;


ts.write("Config", struct("wBlinkPeriod_s",tempBurstSpacing_s)); %Temp1 refreshed as often as it is read for the constraint
ts.write("Config", struct("wmode", 1));

% Initialize the live panel (one maximized window updated after each point, fcn_plot_live_panel)
figPanel = figure('Name', 'PQ exploration - live panel', 'NumberTitle', 'off', 'Color', 'w', 'WindowState', 'maximized');
panelCfg.chIdx = chIdx;
panelCfg.timeIntervalNanoSeconds = timeIntervalNanoSeconds;
panelCfg.syncCapture = syncCapture;
panelCfg.f0 = f0;
panelCfg.Tj_lim = Tj_lim;
hist.P0 = Pfft; %aligned point (switch closed checkpoint)
hist.Q0 = Qfft;
hist.P = []; hist.Q = []; hist.P_board = []; hist.Q_board = [];
hist.cls = []; hist.T1 = []; hist.T2 = []; hist.vcRegulated = true(1, 0);

% Jacobian calibration around the aligned point: anchor = switch closed
% checkpoint above, then one pure-M and one pure-phi regulated step

%anchor point (switch closed checkpoint, v_c already at its reference)
P0 = Pfft;
Q0 = Qfft;

%pure-M calibration step
k_vc = []; %gain dVc/dEs between AC source and v_c, unknown before the first regulation
[P_M, Q_M, ~, ~, ~, ~, ~, ~, ~, ~, k_vc, meas] = fcn_measure_PQ_point_vcreg(bench, Mp_init, phi_m_init, ...
    Mp_init+step_M_jacobian, phi_m_init, Mp_AC_init, phi_AC_init, k_vc);
panelCfg.label = 'Jacobian calibration: pure-M step';
fcn_plot_live_panel(figPanel, meas, hist, panelCfg);

%pure-phi calibration step (ramped directly from the pure-M step)
[P_phi, Q_phi, ~, ~, ~, ~, ~, ~, ~, ~, k_vc, meas] = fcn_measure_PQ_point_vcreg(bench, Mp_init+step_M_init, phi_m_init, ...
    Mp_init, phi_m_init+step_phi_jacobian, Mp_AC_init, phi_AC_init, k_vc);
panelCfg.label = 'Jacobian calibration: pure-\phi step';
fcn_plot_live_panel(figPanel, meas, hist, panelCfg);

%back to the aligned point
[Mp, phi_m] = fcn_ramp_M_phi(ts, Mp_init, phi_m_init+step_phi_init, Mp_init, phi_m_init, ...
    rampMaxStepM, rampMaxStepPhi, rampStepPause_s);
ts.write("Config", struct("wMpAC", Mp_AC_init));
ts.write("Config", struct("wphi_AC", phi_AC_init));

%A maps normalized steps u = [dM/step_M_init; dphi/step_phi_init] to [dP;dQ]
A = [P_M-P0, P_phi-P0; Q_M-Q0, Q_phi-Q0];

if(abs(det(A)) < singular_tol)
    warning('PQ exploration: pure-M and pure-phi steps produce (nearly) parallel PQ directions at (M=%g,phi=%g), increase step_M_init/step_phi_init.', Mp_init, phi_m_init)
end

fprintf('PQ exploration: anchor M = %.4f, phi = %+.4f rad | P0 = %.2f W, Q0 = %.2f VAr\n', Mp_init, phi_m_init, P0, Q0);
disp(A)

% Loop beginning to define PQ points in the target_angle_deg angle lines
for theta_deg_loop = target_angle_deg

    theta = deg2rad(theta_deg_loop);

    % Direction definition: solve the Jacobian for this angle's direction
    d = [cos(theta); sin(theta)]; %desired unit direction in the PQ plane
    u = A\d; %u = [u_M; u_phi], direction in units of (step_M_init, step_phi_init)
    u = u/norm(u); %unit-normalize so neither component is pinned/divided-by -> avoids blow-up when one axis barely contributes

    step_M = step_M_init * u(1);
    step_phi = step_phi_init * u(2);

    %first point of the line: one step away from the anchor (the anchor is already measured)
    Mmod_loop = Mp_init + step_M;
    phimod_loop = phi_m_init + step_phi;
    Mmod_prev = Mp_init; %point where the converter is, start of the next ramp
    phimod_prev = phi_m_init;
    Mp_AC_loop = Mp_AC_init; %AC source starts each angle line at its aligned values
    phi_AC_loop = phi_AC_init;
    delta_S_step = delta_S_init;
    S_prev = sqrt(P0^2 + Q0^2); %S of the previous point of this angle line
    numPointsLine = 0;
    black_point = false;

    fprintf('PQ exploration: angle line %g deg\n', theta_deg_loop);

    %black x point - at least one constraint is activated, setting the PQ diagram limit
    while(~black_point)

        k = k+1; %update counter
        numPointsLine = numPointsLine+1;

        %get input
        phi_m_scan(k) = phimod_loop;
        M(k) = Mmod_loop;
        theta_scan(k) = theta_deg_loop; %records which target_angle_deg produced this point

        %ramp, v_c regulation (warm started from the previous point of this angle line), acquisition and saving
        [P_fft_50Hz(k), Q_fft_50Hz(k), Mp_AC_loop, phi_AC_loop, vc_regulated(k), rmsIL(k), TJ(k), Pdc_meas(k), P_board(k), Q_board(k), k_vc, meas] = ...
            fcn_measure_PQ_point_vcreg(bench, Mmod_prev, phimod_prev, Mmod_loop, phimod_loop, Mp_AC_loop, phi_AC_loop, k_vc);
        Mmod_prev = Mmod_loop;
        phimod_prev = phimod_loop;
        Mp_AC_reg(k) = Mp_AC_loop; %regulated AC source amplitude
        phi_AC_reg(k) = phi_AC_loop; %regulated AC source phase [rad]

        constraints(1,k) = (rmsIL(k)-If_lim)/If_lim; %fuse current constraint
        constraints(2,k) = (rmsIL(k)-Il_lim)/Il_lim; %inductance current constraint
        constraints(3,k) = (TJ(k)-Tj_lim)/Tj_lim; %mosfet temperature constraint

        S(k) = sqrt(P_fft_50Hz(k)^2 + Q_fft_50Hz(k)^2);
        delta_S = abs(S(k)-S_prev);
        S_prev = S(k);

        fprintf('PQ exploration %d (line %g deg, point %d) | M %.4f, phi %+.4f rad | P %.2f W, Q %.2f VAr | I %.2f A rms, TJ %.1f K\n', ...
            k, theta_deg_loop, numPointsLine, M(k), phi_m_scan(k), P_fft_50Hz(k), Q_fft_50Hz(k), rmsIL(k), TJ(k));

        %verifies if we are close to constraints:
        %black x point - at least one constraint is activated, setting the PQ diagram limit
        %red point - we are in the 80% to 100% zone of at least one constraint, finer step_M is required
        %grey point - we are below the 80% to 100% zone of all constraints, not much detail is needed so big step_M can be used
        if(any(constraints(:,k)>=0)) %black x point - at least one constraint is activated, setting the PQ diagram limit
            index_over = find(constraints(:,k)>=0);  %finds indexes of the constraints that were activated
            point_class(k) = 2;
            black_point = true;

        elseif(any(constraints(:,k)>= -0.2)) %red point - we are in the 80% to 100% zone of at least one constraint, finer step_M is required
            delta_S_step = delta_S_step_fine;
            point_class(k) = 1;

        else %grey point - we are below the 80% to 100% zone of all constraints, not much detail is needed so big step_M can be used
            point_class(k) = 0;
        end

        %live panel: exploration so far and this point (v_c not regulated points circled in magenta)
        hist.P = P_fft_50Hz; hist.Q = Q_fft_50Hz;
        hist.P_board = P_board; hist.Q_board = Q_board;
        hist.cls = point_class;
        hist.T1(k) = meas.T1; hist.T2(k) = meas.T2;
        hist.vcRegulated = logical(vc_regulated);
        panelCfg.label = sprintf('PQ exploration | angle line %g deg, point %d (point %d in total)', theta_deg_loop, numPointsLine, k);
        fcn_plot_live_panel(figPanel, meas, hist, panelCfg);

        %next step: rescaled so that the next point is delta_S_step further in S,
        %limited to [step_scale_min, step_scale_max] times the previous step
        if(delta_S > 0)
            scale = delta_S_step/delta_S;
            if(scale < step_scale_min)
                scale = step_scale_min;
            elseif(scale > step_scale_max)
                scale = step_scale_max;
            end
            step_M = step_M * scale;
            step_phi = step_phi * scale;
        end

        %Update modulation amplitude for next loop
        Mmod_loop = Mmod_loop + step_M;

        %Update modulation phase for next loop
        phimod_loop = phimod_loop + step_phi;

    end

    %ramp down from the last measured point to the aligned point, then AC source back to its aligned values
    [Mp, phi_m] = fcn_ramp_M_phi(ts, Mmod_prev, phimod_prev, Mp_init, phi_m_init, ...
        rampMaxStepM, rampMaxStepPhi, rampStepPause_s);
    ts.write("Config", struct("wMpAC", Mp_AC_init));
    ts.write("Config", struct("wphi_AC", phi_AC_init));

end

Mp_AC = Mp_AC_init;
phi_AC = phi_AC_init;

% Export data of the exploration (each point is also saved in its own PQpoint file)
save(sprintf('PQexploration_%s.mat', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))), ...
    'Mp_init', 'phi_m_init', 'Mp_AC_init', 'phi_AC_init', 'VcClkRef', 'P0', 'Q0', 'A', 'target_angle_deg', ...
    'step_M_init', 'step_phi_init', 'delta_S_init', 'If_lim', 'Il_lim', 'Tj_lim', ...
    'M', 'phi_m_scan', 'theta_scan', 'P_fft_50Hz', 'Q_fft_50Hz', 'P_board', 'Q_board', 'Pdc_meas', ...
    'rmsIL', 'TJ', 'S', 'constraints', 'point_class', 'vc_regulated', 'Mp_AC_reg', 'phi_AC_reg');

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