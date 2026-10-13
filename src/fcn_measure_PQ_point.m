function [P_out, Q_out, Vcap_meas, Idc_meas, iL_meas, vc_meas, vs_meas, T_Q1, T_L, PicoScope_overflow] = fcn_measure_PQ_point(meas_cfg, Mmod_loop, phimod_loop, settle_s)
%FCN_MEASURE_PQ_POINT experimental equivalent of fcn_simulate_PQ_point:
%commands the converter to the given (M,phi) operating point, waits
%settle_s, then gets the PicoScope waveforms and the board measurements.
%Returns the FFT active/reactive power (same method as
%fcn_GetPower_fullbridge) and the measured signals that replace the
%simulation outputs.
fcn_write_M_phi(meas_cfg.ts, Mmod_loop, phimod_loop)
pause(settle_s)

%PicoScope waveforms
[~, overflow, channelData, ~] = picoscope_acquisition(meas_cfg.ps4000aDeviceObj, meas_cfg.numChannels);

iL_meas = channelData{meas_cfg.idxIL} / meas_cfg.probeVoltsPerUnit(meas_cfg.idxIL); %inductor current (i_ac)
vc_meas = channelData{meas_cfg.idxVinv} / meas_cfg.probeVoltsPerUnit(meas_cfg.idxVinv); %inverter generated voltage (v_c)
vs_meas = channelData{meas_cfg.idxVgrid} / meas_cfg.probeVoltsPerUnit(meas_cfg.idxVgrid); %ac grid voltage (v_s)
PicoScope_overflow = any(overflow ~= 0); %PicoScope range exceeded on at least one channel

%board measurements
Vcap_meas = meas_cfg.ts.read(meas_cfg.measurements("VHigh")); %dc capacitor voltage, mean value [V]
Idc_meas = meas_cfg.ts.read(meas_cfg.measurements("IHigh")); %dc-side current, mean value [A]
T_Q1 = meas_cfg.ts.read(meas_cfg.measurements("Temp1")); %MOSFET Q1 temperature [degC]
T_L = meas_cfg.ts.read(meas_cfg.measurements("Temp2")); %inductance temperature [degC]
% icap, IMOS, VMOS, vL and v_AB are not measured

% dc capacitor voltage ripple will be calculated with the
% measured v_cap from scopemimicry

%FFT method of fcn_GetPower_fullbridge (fcn_GetPower has the same calculation,
%without the f_switching bin that is above the PicoScope Nyquist frequency)
[~, ~, Pfft, Qfft] = fcn_GetPower(vc_meas, iL_meas, meas_cfg.dtScope, meas_cfg.f0, meas_cfg.f_switching);
P_out = Pfft;
Q_out = Qfft;
end
