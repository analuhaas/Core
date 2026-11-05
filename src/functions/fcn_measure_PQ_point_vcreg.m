function [P_out, Q_out, Mp_AC, phi_AC, vcRegulated, rmsIL, TJ, Pdc, P_board, Q_board, k_vc, meas] = fcn_measure_PQ_point_vcreg(bench, Mmod_from, phimod_from, Mmod_loop, phimod_loop, Mp_AC, phi_AC, k_vc)
%FCN_MEASURE_PQ_POINT_VCREG measures one (M,phi) operating point with v_c
%regulated by the AC source - experimental equivalent of fcn_simulate_PQ_point
%of fcn_step1_PQ_fullbridge_smallestconstraint_v3
%   1) ramps the converter from (Mmod_from, phimod_from) to (Mmod_loop,
%      phimod_loop) [rad] (fcn_ramp_M_phi)
%   2) regulates v_c back to its no-load reference by correcting the AC
%      source, starting from (Mp_AC, phi_AC) - the regulated values of the
%      previous point of the same angle line (fcn_regulate_Vc)
%   Before and after 2), acquires the board measurements, both PicoScopes and
%   ScopeMimicry and saves the point (fcn_save_PQ_point): two files per
%   point, tagged _before_vcreg and _after_vcreg. Both contain the v_c
%   reference VcClkRef; the _after_vcreg file also contains how the
%   regulation converged (vcRegHistory, vcRegIterations, vcRegulated, k_vc).
%   The returned values are those after the regulation.
%   k_vc: gain dVc/dEs between the AC source command and v_c, measured by the
%   v_c regulation and passed on from one point to the next ([] at the start)
%   meas: what the live panel (fcn_plot_live_panel) needs to show the point:
%   curves of both PicoScopes and ScopeMimicry, last capture of the v_c
%   regulation, efficiency and both MOSFET temperatures [degC]

ts = bench.ts;

%ramp the converter to the point (the AC source keeps the initial values)
fcn_ramp_M_phi(ts, Mmod_from, phimod_from, Mmod_loop, phimod_loop, ...
    bench.rampMaxStepM, bench.rampMaxStepPhi, bench.rampStepPause_s);

%acquisition of the point before vc regulation (AC source still at the
%regulated values of the previous point)
boardMeas = fcn_converter_acquisition(ts, bench.measurements, bench.MEAS);
channelData = fcn_picoscope_acquisition_scopes(bench.ps4000aDeviceObj, bench.numChannels, bench.probeVoltsPerUnit);
scopeMimicry = fcn_scope_mimicry_acquisition(ts, bench.con, bench.scopeTs, bench.scopeTimeout_s);

%calculate active, reactive and DC power and save the point before vc
%regulation (file tagged _before_vcreg, with the v_c reference)
fcn_save_PQ_point(channelData, bench.chIdx, boardMeas, ...
    Mmod_loop, phimod_loop, Mp_AC, phi_AC, bench.Ts, bench.timeIntervalNanoSeconds, bench.f0, bench.f_switching, scopeMimicry, ...
    "before_vcreg", struct('VcClkRef', bench.VcClkRef));

%regulate v_c by the AC source, started from (Mp_AC, phi_AC)
if nargin < 8
    k_vc = []; %gain dVc/dEs unknown before the first regulation
end
[Mp_AC, phi_AC, VcClk, vcRegulated, ~, regCapture, k_vc, vcRegIterations, vcRegHistory] = ...
    fcn_regulate_Vc(bench.vcReg, Mp_AC, phi_AC, bench.VcClkRef, k_vc);
fprintf('Vc regulation: Mp_AC = %.4f, phi_AC = %+.4f rad | Vc = %.2f V rms, phase error %+.2f deg\n', ...
    Mp_AC, phi_AC, abs(VcClk), rad2deg(angle(VcClk / bench.VcClkRef)));

%acquisition of the regulated point
boardMeas = fcn_converter_acquisition(ts, bench.measurements, bench.MEAS);
channelData = fcn_picoscope_acquisition_scopes(bench.ps4000aDeviceObj, bench.numChannels, bench.probeVoltsPerUnit);
scopeMimicry = fcn_scope_mimicry_acquisition(ts, bench.con, bench.scopeTs, bench.scopeTimeout_s);

%calculate active, reactive and DC power and save the point after vc
%regulation (file tagged _after_vcreg, with the v_c reference and how the
%regulation converged)
vcRegData.VcClkRef = bench.VcClkRef; %v_c phasor to hold (oscillator frame, no load)
vcRegData.VcClk = VcClk; %v_c phasor of the last regulation capture
vcRegData.vcRegulated = vcRegulated; %tolerances met
vcRegData.vcRegIterations = vcRegIterations; %number of captures of the regulation
vcRegData.vcRegHistory = vcRegHistory; %Mp_AC, phi_AC, VcClk, Vc_rms, ephi, k per iteration
vcRegData.k_vc = k_vc; %gain dVc/dEs passed on to the next point
[P_out, Q_out, Pdc, eta] = fcn_save_PQ_point(channelData, bench.chIdx, boardMeas, ...
    Mmod_loop, phimod_loop, Mp_AC, phi_AC, bench.Ts, bench.timeIntervalNanoSeconds, bench.f0, bench.f_switching, scopeMimicry, ...
    "after_vcreg", vcRegData);

%KPIs used by the constraints
rmsIL = rms(channelData{1}{bench.chIdx.Icpos}); %AC current [A rms] (i_c_pos, PicoScope 1)
[T1, T2] = fcn_read_temperature_burst(ts, bench.measurements, bench.tempBurstCount, bench.tempBurstSpacing_s); %means of tempBurstCount readings spaced by tempBurstSpacing_s [degC]
TJ = T1 + 273.15; %MOSFET temperature [K] (board Temp1)

%board active/reactive power
P_board = mean(scopeMimicry.P_board);
Q_board = mean(scopeMimicry.Q_board);

%data of the point for the live panel
meas.channelData = channelData;
meas.scopeMimicry = scopeMimicry;
meas.regCapture = regCapture;
meas.Mp = Mmod_loop;
meas.phi_m = phimod_loop;
meas.Mp_AC = Mp_AC;
meas.phi_AC = phi_AC;
meas.vcRegulated = vcRegulated;
meas.P = P_out;
meas.Q = Q_out;
meas.Pdc = Pdc;
meas.eta = eta;
meas.T1 = T1;
meas.T2 = T2;

end
