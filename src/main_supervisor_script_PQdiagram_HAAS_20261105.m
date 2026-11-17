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
settle_s   = 0.3;            % wait after writing before capturing
maxCurrentClosingA = 0.1;

%  V_c regulation parameters (keeps v_c amplitude and phase fixed when current flows)
vcRegTolV       = 0.005;            % [V rms] amplitude tolerance on v_c
vcRegTolPhi     = 0.0005;   % [rad] phase tolerance on v_c (relative to the internal oscillator)
vcRegAlpha      = 1.0;            % fraction of the remaining error corrected per iteration
vcRegMaxStepM   = 0.5;           % max change of Mp_AC per iteration
vcRegMaxStepPhi = 0.5;            % [rad] max change of phi_AC per iteration
vcRegMaxIter    = 300;

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
% The board has two USB serial ports: the ThingSet shell
% (used by ts) and the console, where printk writes the ScopeMimicry dump.

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

[ps4000aDeviceObj, numChannels, channelLetters, timeIntervalNanoSeconds, probeVoltsPerUnit, probeUnit, Ts_Picoscope] = ...
    fcn_picoscope_setup(picoCfg, ps4000aEnuminfo);
numScopes = numel(ps4000aDeviceObj);

%% Start the equipments

input(sprintf('Startup DC supply: check if DC supply limit is at %g A, press enter to continue... ', dcSupplyLimitA), 's');
input('Startup DC supply: turn on DC supply, press enter to continue... ', 's');
input(sprintf('Startup AC source: check if Philibert limit is at %g A, press enter to continue... ', acSourceLimitA), 's');
input('Startup AC source: turn on Philibert (check + validate button), press enter to continue... ', 's');

%% Command converter to alignement mode, where v_s and v_c are initially at no sync
Mp_AC = 0.4;
phi_AC = 0.0;
Mp = 0.2;
phi_m = 0.0;
ts.write("Config", struct("wmode", 2)); %Power mode
ts.write("Config", struct("wMpAC", Mp_AC));
ts.write("Config", struct("wphi_AC", phi_AC));
pause(settle_s); %Allows the converter to regulate its voltage to v_ref before doing the alignement of v_s
%% Converter and PicoScope acquisition, process data - BEFORE V_S V_C ALIGNMENT CHECKPOINT

boardMeas = fcn_converter_acquisition(ts, measurements, MEAS);
[channelData, numSamples] = fcn_picoscope_acquisition_scopes(ps4000aDeviceObj, numChannels, probeVoltsPerUnit);
scopeMimicry = fcn_scope_mimicry_acquisition(ts, con, scopeTs, scopeTimeout_s);
fcn_plot_picoscope(channelData, numSamples, timeIntervalNanoSeconds, channelLetters, probeUnit, picoSerialNumbers, secondsPerDivision);
fcn_plot_scope_mimicry(scopeMimicry);

% Calculate active, reactive and DC power and save the PQ point
[Pfft, Qfft, Pdc] = fcn_save_PQ_point(channelData, chIdx, boardMeas, ...
    Mp, phi_m, Mp_AC, phi_AC, Ts, timeIntervalNanoSeconds, f0, f_switching, scopeMimicry);


%% Check if phasor transformation works

% Measures v_c and v_s voltages with PicoScope
% [~, ~, channelData, ~] = picoscope_acquisition(syncCfg.ps4000aDeviceObj, syncCfg.numChannels);
% v_c = channelData{idxVc} / scaleVc;
% v_s = channelData{idxVs} / scaleVs;
% time_Picoscope = Ts_Picoscope.*ones(1,length(channelData{idxVc}));

% Window of time with complete fundamental frequency periods (to avoid
% spectral leak
Ncycles = floor((time_Picoscope(end) - time_Picoscope(1)) * f0);
v_c = v_c(time_Picoscope<=time_Picoscope(1)+Ncycles/f0);
v_s = v_s(time_Picoscope<=time_Picoscope(1)+Ncycles/f0);
time_Picoscope = time_Picoscope(time_Picoscope<=time_Picoscope(1)+Ncycles/f0);
N = length(time_Picoscope); %number of samples within complete frequency periods

% Calculate phasors according to fundamental frequency
e  = exp(-1j*2*pi*f0*(time_Picoscope));
Vc = 2/N * sum(v_c .* e);
Vs = 2/N * sum(v_s .* e);

% Calculate errors (Vc is our reference at this stage, we want to regulate Vs to Vc)
VcRms = abs(Vc);
VsRms = abs(Vs);
Error_mag = VcRms - VsRms;
Error_phi = angle(Vs / Vc);   % phi_Vs - phi_Vc

% Plot phasors
real_part_Vc = VcRms * cos(0);
real_part_Vs = VsRms * cos(Error_phi);
imag_part_Vc = VcRms * sin(0);
imag_part_Vs = VsRms * sin(Error_phi);

figure(50), hold on, grid on, box on, axis equal,
pc = quiver(0, 0, real_part_Vc, imag_part_Vc, 0, 'LineWidth', 2, 'Color', 'r');
ps = quiver(0, 0, real_part_Vs, imag_part_Vs, 0, 'LineWidth', 2, 'Color', 'b');
xlim([-20 20]);
ylim([-20 20]);
xlabel('Re');
ylabel('Im');
legend('Phasor Vc', 'Phasor Vs');

%% Synchronize vs and vc automatically (switch must be OPEN)
% Ramps Mp (-> v_s) up from 0 and adjusts phi_AC until
% both voltages reach syncVref rms and are in phase.
%
% phi_m = 0 always.
%
% Attention: v_c is not regulated using MATLAB at this stage.

ts.write("Config", struct("wmode", 1)); %Alignment mode
pause(2); %Allows the converter to regulate its voltage to v_ref before doing the alignement of v_s

% Initializing amplitudes and phases
Mp_AC_init = 0.0;
phi_AC_init = 0.0;
syncAligned = false;

for k = 1:syncMaxIter

    % Sets AC source operation point
    ts.write("Config", struct("wMpAC", Mp_AC_init));
    ts.write("Config", struct("wphi_AC", phi_AC_init));
    pause(settle_s); % Pause before doing a new voltage measurement

    % Measures v_c and v_s voltages with PicoScope
    [~, ~, channelData, ~] = picoscope_acquisition(syncCfg.ps4000aDeviceObj, syncCfg.numChannels);
    v_c = channelData{idxVc} / scaleVc;
    v_s = channelData{idxVs} / scaleVs;
    time_Picoscope = Ts_Picoscope.*ones(1,length(channelData{idxVc}));

    % Window of time with complete fundamental frequency periods (to avoid
    % spectral leak
    Ncycles = floor((time_Picoscope(end) - time_Picoscope(1)) * f0);
    v_c = v_c(time_Picoscope<=time_Picoscope(1)+Ncycles/f0);
    v_s = v_s(time_Picoscope<=time_Picoscope(1)+Ncycles/f0);
    time_Picoscope = time_Picoscope(time_Picoscope<=time_Picoscope(1)+Ncycles/f0);
    N = length(time_Picoscope); %number of samples within complete frequency periods

    % Calculate phasors according to fundamental frequency
    e  = exp(-1j*2*pi*f0*(time_Picoscope));
    Vc = 2/N * sum(v_c .* e);
    Vs = 2/N * sum(v_s .* e);

    % Calculate errors (Vc is our reference at this stage, we want to regulate Vs to Vc)
    VcRms = abs(Vc);
    VsRms = abs(Vs);
    Error_mag = VcRms - VsRms;
    Error_phi = angle(Vs / Vc);   % phi_Vs - phi_Vc
    
    % Plot phasors
    real_part_Vc = VcRms * cos(0);
    imag_part_Vc = VcRms * sin(0);
    real_part_Vs = VsRms * cos(Error_phi);
    imag_part_Vs = VsRms * sin(Error_phi);
    
    delete(pc);
    delete(ps);
    pc = quiver(0, 0, real_part_Vc, imag_part_Vc, 0, 'LineWidth', 2, 'Color', 'r');
    ps = quiver(0, 0, real_part_Vs, imag_part_Vs, 0, 'LineWidth', 2, 'Color', 'b');

    % Verifies stop criteria according to tolerances
    if(Error_mag <= syncTolV && Error_phi <= syncTolPhi)
        syncAligned = true;
        break;
    end

    % Update modulation and phase magnitudes
    phi_AC = phi_AC + Error_phi;
    Delta_Mp_AC = Error_mag/VcRms;

    if Delta_Mp_AC > Max_delta_mod
        Mp_AC_init = Mp_AC_init + Max_delta_mod;
    elseif Delta_Mp_AC < -Max_delta_mod
        Mp_AC_init = Mp_AC_init - Max_delta_mod;
    else
        Mp_AC_init = Mp_AC_init + Delta_Mp_AC;
    end
    
end

if syncAligned
    fprintf('Sync: ALIGNED after %d iterations: Mp = %.4f, Mp_AC = %.4f, phi_AC = %.4f rad\n', ...
        k, Mp_init, Mp_AC_init, phi_AC_init);
else
    warning('Sync: NOT aligned after %d iterations - do NOT close the switch.', syncCfg.MaxIter);
end

% The board is now at the aligned point
Mp = Mp_init;
phi_m = phi_m_init;
Mp_AC = Mp_AC_init;
phi_AC = phi_AC_init;

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