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

% PQ diagram scan parameters (experimental version of fcn_step1_PQ_fullbridge_smallestconstraint_v3)
target_angle_deg = 0:30:30; % [°] direction to search (0° = +P axis, 90° = +Q axis). Vector to sweep several angles in one run.
step_M_init = 0.1; % initial step used to scan different modulation amplitudes (also the Jacobian calibration step)
step_phi_init = 0.05; % [rad] initial step used to scan different modulation phases (also the Jacobian calibration step)
delta_S_init = 10; % [VA] initial S step accepted from one PQ point to the next one
zero_tol = 0.5; % [VA] acceptable |S| residual to accept the aligned point as the (P,Q)=(0,0) departure point
Mmax = 0.95; % maximum modulation amplitude M_p allowed during the scan
settle_elec_s = 0.5; % [s] wait before measuring a point used only for P and Q (Jacobian calibration, return ramp)
settle_thermal_s = 10; % [s] wait before measuring a scanned point (temperatures must settle) - TO BE MEASURED
return_steps = 10; % nb of steps of the ramp back to the departure point after each angle line
PQ_axis_lim = 100; % [W]/[VAr] axis limits of the real time PQ figure
PQ_save_file = 'PQ_scan_experimental.mat'; % file where the scan results are saved

% Limits considered in the PQ diagram
If_lim = 1.5; %low-side fuse current limit [A rms]
Il_lim = 13; %low-side inductance current limit [A rms]
% Iripple_lim = 1.5; %inductance current ripple limit [App] - not measured yet (PicoScope sampling << f_switching)
Tj_lim = 448; %MOSFET temperature limit [K] (board Temp1)
Tl_lim = 448; %inductance temperature limit [K] (board Temp2) - TO BE UPDATED
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
idxIL = idxIb; % iL (inductor current) = i_ac = channel B
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

input('Current probes: turn on current probes, press enter to continue... ', 's');
input('Before PicoScope connection: Check if current probes offset is close to 0 with PicoScope, press enter to continue... ', 's');

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

%% Start the equipments

input('Startup converter: check if software limit is at 2 A, press enter to continue... ', 's');
input('Startup DC supply: check if DC supply limit is at 2 A, press enter to continue... ', 's');
input('Startup DC supply: turn on DC supply, press enter to continue... ', 's');
input('Startup AC source: check if Philibert limit is at 2 A, press enter to continue... ', 's');
input('Startup AC source: turn on Philibert (check + validate button), press enter to continue... ', 's');

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

%% Command converter to a scan PQ diagram
% Gets the main KPIs from PicoScope and board measurements to define the
% Full-bridge converter PQ diagram until the first constraint is activated,
% on each angle line of target_angle_deg.
% 
% Only (M_p, phi_m) of the converter are changed - the AC source (Mp_AC,
% phi_AC) stays at the aligned values found by the sync section.
%
% Equivalence with measurements:
% Vcap -> board VHigh, Pdc -> VHigh*IHigh,
% iL -> i_ac (PicoScope), vinv -> v_c (PicoScope), vgrid -> v_s (PicoScope),
% TJ -> board Temp1, TL -> board Temp2.
% Not measured: icap, IMOS, VMOS, vL, v_AB and IL ripple (for now).

% Initialize loop parameters
k = 0; %initialize counter

Mmod_anchor = Mp_init; %aligned point, (P,Q)~=(0,0) departure point
phimod_anchor = phi_m_init;

M = []; %modulation amplitude array that saves all M_p scanned
phi_m = []; %modulation phase array that saves all phi_m scanned
theta_scan = []; %angle line that produced each scanned point
delta_S_step_fine = delta_S_init/2;
singular_tol = 1e-6; %below this |det(A)| the two calibration steps are considered numerically parallel
max_zero_iter = 3; %Newton correction iterations allowed to find that point
step_scale_min = 0.5; %per-iteration clamp on the delta_S-based step_M/step_phi rescaling (avoids abrupt jumps)
step_scale_max = 2;
constraint_names = {'fuse current', 'inductance current', 'MOSFET current', 'IL ripple', 'MOSFET temperature', 'inductance temperature'};

% Everything fcn_measure_PQ_point needs to command and measure one point
meas_cfg.ts = ts;
meas_cfg.measurements = measurements;
meas_cfg.ps4000aDeviceObj = ps4000aDeviceObj{1};
meas_cfg.numChannels = numChannels{1};
meas_cfg.probeVoltsPerUnit = probeVoltsPerUnit{1};
meas_cfg.idxVinv = idxVc;
meas_cfg.idxVgrid = idxVs;
meas_cfg.idxIL = idxIL;
meas_cfg.dtScope = dtScope;
meas_cfg.f0 = f0;
meas_cfg.f_switching = f_switching;

% The scope saturates before the current constraints if its range is too small
if sqrt(2)*min(If_lim, Il_lim) > currentProbeRangeVolts/currentProbeVoltsPerAmp
    warning('PQ scan: current channel range (%.2f A peak) is below the current limits - the scan will stop on scope overflow instead.', ...
        currentProbeRangeVolts/currentProbeVoltsPerAmp)
end

% AC source set to aligned values
ts.write("Config", struct("wMpAC", Mp_AC_init));
ts.write("Config", struct("wphi_AC", phi_AC_init));

% Initialize figure to verify PQ diagram in real time
figure(75), axis square, hold on, grid on, box on

xlabel('$P_c$ [W]','interpreter','latex')
ylabel('$Q_c$ [VAr]','interpreter','latex')

xlim([-PQ_axis_lim, PQ_axis_lim])
ylim([-PQ_axis_lim, PQ_axis_lim])

% Find the true (P,Q)=(0,0) departure point near (Mmod_anchor,phimod_anchor) and calibrate the local
% Jacobian there once. Both are shared by every angle in target_angle_deg.
% Calibration points only need P and Q, so they use the short electrical settle time.

for it = 1:max_zero_iter

    %anchor point
    [P0, Q0, X0_Vcap_meas, X0_Idc_meas, X0_iL_meas, X0_vc_meas, X0_vs_meas, X0_T_Q1, X0_T_L, X0_PicoScope_overflow] = fcn_measure_PQ_point(meas_cfg, Mmod_anchor, phimod_anchor, settle_elec_s);

    %pure-M calibration step
    [P_M, Q_M, XM_Vcap_meas, XM_Idc_meas, XM_iL_meas, XM_vc_meas, XM_vs_meas, XM_T_Q1, XM_T_L, XM_PicoScope_overflow] = fcn_measure_PQ_point(meas_cfg, Mmod_anchor+step_M_init, phimod_anchor, settle_elec_s);

    %pure-phi calibration step
    [P_phi, Q_phi, Xphi_Vcap_meas, Xphi_Idc_meas, Xphi_iL_meas, Xphi_vc_meas, Xphi_vs_meas, Xphi_T_Q1, Xphi_T_L, Xphi_PicoScope_overflow] = fcn_measure_PQ_point(meas_cfg, Mmod_anchor, phimod_anchor+step_phi_init, settle_elec_s);

    %calibration steps must stay far from the limits - otherwise step_M_init/step_phi_init are too big
    if any([X0_PicoScope_overflow, XM_PicoScope_overflow, Xphi_PicoScope_overflow]) || ...
            max([rms(X0_iL_meas), rms(XM_iL_meas), rms(Xphi_iL_meas)]) > min(If_lim, Il_lim)
        fcn_write_M_phi(ts, Mp_init, phi_m_init);
        error('PQ scan: current limit or scope overflow during Jacobian calibration - reduce step_M_init/step_phi_init. Converter back to the aligned point.')
    end

    %A maps normalized steps u = [dM/step_M_init; dphi/step_phi_init] to [dP;dQ]
    A = [P_M-P0, P_phi-P0; Q_M-Q0, Q_phi-Q0];

    if abs(det(A)) < singular_tol
        warning('PQ scan: pure-M and pure-phi steps produce (nearly) parallel PQ directions at (M=%g,phi=%g), cannot refine the zero point further.', Mmod_anchor, phimod_anchor)
        break
    end

    if hypot(P0,Q0) <= zero_tol
        break
    end

    u0 = A\(-[P0;Q0]); %Newton correction towards (P,Q)=(0,0), in units of (step_M_init,step_phi_init)
    Mmod_anchor = Mmod_anchor + u0(1)*step_M_init;
    phimod_anchor = phimod_anchor + u0(2)*step_phi_init;
end

if hypot(P0,Q0) > zero_tol
    warning('PQ scan: Newton correction did not reach |S|<=%g after %d iteration(s) (final |S|=%g); continuing with the best anchor found.', zero_tol, max_zero_iter, hypot(P0,Q0))
end

fprintf('PQ scan: departure point Mp = %.4f, phi_m = %+.4f rad | P0 = %.2f W, Q0 = %.2f VAr\n', Mmod_anchor, phimod_anchor, P0, Q0);
plot(P0,Q0,'ob','MarkerSize',9) % refined (P,Q)~=(0,0) anchor shared by every angle below
drawnow

% Loop beginning to define PQ points in the target_angle_deg angle lines
for theta_deg_loop = target_angle_deg

    theta = deg2rad(theta_deg_loop); %conversion from rad to degrees

    % Direction definition: solve the Jacobian for this angle's direction
    d = [cos(theta); sin(theta)]; %desired unit direction in the PQ plane
    u = A\d; %u = [u_M; u_phi], direction in units of (step_M_init, step_phi_init)
    u = u/norm(u); %unit-normalize so neither component is pinned/divided-by -> avoids blow-up when one axis barely contributes

    step_M = step_M_init * u(1);
    step_phi = step_phi_init * u(2);

    Mmod_loop = Mmod_anchor;
    phimod_loop = phimod_anchor;
    Mmod_written = Mmod_anchor; %last point commanded to the converter, start of the return ramp
    phimod_written = phimod_anchor;
    delta_S_step = delta_S_init;
    delta_S = delta_S_init;
    S_prev = NaN; %S of the previous point of this angle line (not of the previous angle)
    black_point = false;

    %black x point - at least one constraint is activated, setting the PQ diagram limit
    while(~black_point)

        if(Mmod_loop > Mmax || Mmod_loop < 0) %modulation limit reached before any constraint
            warning('PQ scan: theta = %d deg stopped at the modulation limit (M_p = %.4f) before any constraint.', theta_deg_loop, Mmod_loop)
            break
        end

        idx_done = intersect(find(round(M,4) == round(Mmod_loop,4)), find(round(phi_m,4) == round(phimod_loop,4)));

        if(isempty(idx_done)) %verifies if the (M_p, phi_m) point was already scanned in order to avoid over measuring
            %if the (M_p, phi_m) point is NEW, we measure it
            k = k+1; %update counter (only for new points, so the arrays have no gaps)

            %get input
            phi_m(k) = phimod_loop;
            M(k) = Mmod_loop;
            theta_scan(k) = theta_deg_loop; %records which target_angle_deg produced this point, for step2 to isolate a single angle afterward

            [P_iter, Q_iter, Vcap_meas, Idc_meas, iL_meas, vc_meas, vs_meas, T_Q1, T_L, PicoScope_overflow] = fcn_measure_PQ_point(meas_cfg, Mmod_loop, phimod_loop, settle_thermal_s);
            Mmod_written = Mmod_loop;
            phimod_written = phimod_loop;

            %save power
            P(k) = P_iter; %active power
            Q(k) = Q_iter; %reactive power
            S(k) = sqrt(P(k)^2 + Q(k)^2);

            %calculate KPIs
            % IL_ripple(k) = fcn_ripple_calc(iL_meas,f_switching,dtScope); %inductor current ripple - needs PicoScope sampling >> f_switching
            dVcap(k) = Vcap_meas; %(TO BE UPDATED AFTER)
            maxVcap(k) = Vcap_meas + Vcap_meas/2; %mean value + half the peak-to-peak ripple (TO BE UPDATED AFTER)
            rmsIL(k) = rms(iL_meas);
            maxIL(k) = max(abs(iL_meas));
            dIL(k) = max(iL_meas)-min(iL_meas);
            rmsVinv(k) = rms(vc_meas);
            rmsVgrid(k) = rms(vs_meas);
            Pdc_meas(k) = Vcap_meas*Idc_meas; %dc-side power from the board mean values
            TJ(k) = T_Q1 + 273.15; %MOSFET Q1 temperature [K] (board Temp1 [degC])
            TL(k) = T_L + 273.15; %inductance temperature [K] (board Temp2 [degC])
            overflow_scan(k) = PicoScope_overflow; %PicoScope range exceeded on at least one channel

            constraints(1,k) = (rmsIL(k)-If_lim)/If_lim; %fuse current constraint
            constraints(2,k) = (rmsIL(k)-Il_lim)/Il_lim; %inductance current constraint
            constraints(3,k) = NaN; %mosfet current constraint - IMOS not measured
            constraints(4,k) = NaN; %inductor current ripple constraint - not measured yet
            constraints(5,k) = (TJ(k)-Tj_lim)/Tj_lim; %mosfet temperature constraint
            constraints(6,k) = (TL(k)-Tl_lim)/Tl_lim; %inductance temperature constraint

            if(~isnan(S_prev))
                delta_S = abs(S(k)-S_prev);
            else
                delta_S = delta_S_init;
            end
            S_prev = S(k);

            fprintf('PQ theta %3d deg | pt %3d | Mp %.4f phi_m %+.4f | P %7.2f W Q %7.2f VAr | IL %.2f A rms | TJ %.1f K TL %.1f K\n', ...
                theta_deg_loop, k, M(k), phi_m(k), P(k), Q(k), rmsIL(k), TJ(k), TL(k));

            %verifies if we are close to constraints:
            %black x point - at least one constraint is activated (or the scope saturates), setting the PQ diagram limit
            %red point - we are in the 80% to 100% zone of at least one constraint, finer step_M is required
            %grey point - we are below the 80% to 100% zone of all constraints, not much detail is needed so big step_M can be used
            if(any(constraints(:,k)>=0) || overflow_scan(k)) %black x point
                index_over = find(constraints(:,k)>=0);  %finds indexes of the constraints that were activated
                if(overflow_scan(k))
                    fprintf('PQ theta %3d deg | limit: PicoScope overflow\n', theta_deg_loop);
                else
                    fprintf('PQ theta %3d deg | limit: %s\n', theta_deg_loop, strjoin(constraint_names(index_over), ', '));
                end
                plot(P(k),Q(k),'xk','MarkerSize',9)
                black_point = true;

            elseif(any(constraints(:,k)>= -0.2)) %red point
                delta_S_step = delta_S_step_fine;
                plot(P(k),Q(k),'.r','MarkerSize',9)

            else %grey point
                plot(P(k),Q(k),'.','Color',"#EBEBEB",'MarkerSize',9)
            end
            drawnow

        else
            S_prev = S(idx_done(1)); %point already measured (e.g. the departure point), continue from its S
        end

        if(delta_S > 0)
            scale = delta_S_step/delta_S;
            scale = min(max(scale, step_scale_min), step_scale_max); %clamp so a single noisy delta_S can't cause a huge jump
            step_M = step_M * scale;
            step_phi = step_phi * scale;
        end

        %Update modulation amplitude for next loop
        Mmod_loop = Mmod_loop + step_M;

        %Update modulation phase for next loop
        phimod_loop = phimod_loop + step_phi;

    end

    %Ramp back from the last commanded point to the departure point before the next angle line
    for r = 1:return_steps
        fcn_write_M_phi(ts, Mmod_written + (Mmod_anchor-Mmod_written)*r/return_steps, ...
            phimod_written + (phimod_anchor-phimod_written)*r/return_steps);
        pause(settle_elec_s)
    end

end

% Export data
save(PQ_save_file, 'M', 'phi_m', 'theta_scan', 'target_angle_deg', 'Mmod_anchor', 'phimod_anchor', 'A', ...
    'P', 'Q', 'S', 'dVcap', 'maxVcap', 'rmsIL', 'maxIL', 'dIL', ...
    'rmsVinv', 'rmsVgrid', 'Pdc_meas', 'TJ', 'TL', 'overflow_scan', 'constraints', 'constraint_names', ...
    'If_lim', 'Il_lim', 'Tj_lim', 'Tl_lim', 'Mp_AC_init', 'phi_AC_init', '-v7.3')
fprintf('PQ scan: %d points saved to %s\n', k, PQ_save_file);

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
%% Disconnect PicoScope devices

for s = 1:numScopes

    disconnect(ps4000aDeviceObj{s});
    delete(ps4000aDeviceObj{s});

end
%% Disconnect TWIST/SPIN
ts.close();

%% Stop the equipments

input('DC supply: turn off DC supply, press enter to continue... ', 's');
input('AC source: turn off Philibert (uncheck + validate button), press enter to continue... ', 's');
input('Current probes: turn off current probes, press enter to continue... ', 's');
