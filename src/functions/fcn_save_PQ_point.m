function [Pfft, Qfft, Pdc, eta, fileName] = fcn_save_PQ_point(channelData, chIdx, boardMeas, Mp, phi_m, Mp_AC, phi_AC, Ts, timeIntervalNanoSeconds, f0, f_switching)
%FCN_SAVE_PQ_POINT calculates the active and reactive power (FFT method) and
%the DC-side power of the measured PQ point and saves it, one file per
%point named by date and time
%   channelData: curves of both PicoScopes from fcn_picoscope_acquisition_scopes
%   chIdx: channel indices - PicoScope 1: Icpos, Vdac, Vs, Vc
%                            PicoScope 2: Udc, Idc, Icneg, Vs2
%   boardMeas: board measurements from fcn_converter_acquisition
%   Mp, phi_m, Mp_AC, phi_AC: commanded operating point

% PicoScope 1 (KP306/0011)
i_c_pos = channelData{1}{chIdx.Icpos}; % [A] AC current, positive conductor
v_dac = channelData{1}{chIdx.Vdac}; % [V] DAC output (AC source reference)
v_s = channelData{1}{chIdx.Vs}; % [V] AC source voltage
v_c = channelData{1}{chIdx.Vc}; % [V] converter voltage

% PicoScope 2 (KP310/0061)
u_dc = channelData{2}{chIdx.Udc}; % [V] DC-side voltage
i_dc = channelData{2}{chIdx.Idc}; % [A] DC-side current
i_c_neg = channelData{2}{chIdx.Icneg}; % [A] AC current, negative conductor
v_s_2 = channelData{2}{chIdx.Vs2}; % [V] AC source voltage (to align both scopes if needed)

% AC power from v_c and i_c_pos (same scope).
% DC power from u_dc and i_dc (same scope).
[~, ~, Pfft, Qfft, ~, ~, Pdc] = fcn_GetPower(v_c, i_c_pos, Ts, f0, u_dc, i_dc);

% Efficiency
if Pdc > 0 && Pfft > 0
    eta = Pfft / Pdc; % inverter mode: DC -> AC
elseif Pdc < 0 && Pfft < 0
    eta = Pdc / Pfft; % rectifier mode: AC -> DC
else
    eta = NaN;
end

Icpos_rms = rms(i_c_pos); % [A rms] PicoScope 1
Icneg_rms = rms(i_c_neg); % [A rms] PicoScope 2
Vs_rms = rms(v_s); % [V rms] PicoScope 1
Vc_rms = rms(v_c); % [V rms] PicoScope 1
Udc_mean = mean(u_dc); % [V] PicoScope 2
Idc_mean = mean(i_dc); % [A] PicoScope 2
T_j_temp1 = boardMeas.Temp1; % [degC] MOSFET temperature, board Temp1
T_j_temp2 = boardMeas.Temp2; % [degC] MOSFET temperature, board Temp2
t_scope1 = (0:numel(v_c) - 1).' * double(timeIntervalNanoSeconds{1}) * 1e-9; % [s] time vector of the PicoScope 1 curves
t_scope2 = (0:numel(u_dc) - 1).' * double(timeIntervalNanoSeconds{2}) * 1e-9; % [s] time vector of the PicoScope 2 curves

fileName = sprintf('PQpoint_%s.mat', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
save(fileName, ...
    'Pfft', 'Qfft', 'Pdc', 'eta', 'Mp_AC', 'phi_AC', 'Mp', 'phi_m', ...
    'Icpos_rms', 'Icneg_rms', 'Vs_rms', 'Vc_rms', 'Udc_mean', 'Idc_mean', 'T_j_temp1', 'T_j_temp2', ...
    't_scope1', 'i_c_pos', 'v_dac', 'v_s', 'v_c', ...
    't_scope2', 'u_dc', 'i_dc', 'i_c_neg', 'v_s_2');

fprintf('PQ point saved to %s | P = %.2f W, Q = %.2f VAr, Pdc = %.2f W, eta = %.2f %%\n', fileName, Pfft, Qfft, Pdc, 100*eta);

end
