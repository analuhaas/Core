function figureHandle = fcn_plot_vc_regulation(syncCapture, regCapture, f0)
%FCN_PLOT_VC_REGULATION compares v_c after the regulation with its reference
%from the alignment, together with the corresponding DAC voltages
%   syncCapture: last capture of the sync (fcn_sync_vs_vc), switch open, no load
%   regCapture: last capture of the v_c regulation (fcn_regulate_Vc)
%   Both have fields t [s], v_c, v_dac [V], Mp_AC, phi_AC [rad].
%
%   The two captures start at unrelated instants, so each one is put on the
%   time axis of the internal oscillator: the DAC phasor minus the phi_AC
%   applied during the capture gives the oscillator phase at its first sample.
%   On that axis the regulated v_c should lie on its reference, while the
%   DAC voltages differ by the correction applied by the regulation
%   (Mp_AC, phi_AC).

w0 = 2*pi*f0;

[tSync, VcSync] = oscillatorTime(syncCapture, f0, w0);
[tReg, VcReg] = oscillatorTime(regCapture, f0, w0);

ampError = abs(VcReg) - abs(VcSync); % [V rms]
phaseError = rad2deg(angle(VcReg / VcSync)); % [deg]

figureHandle = fcn_reuse_figure('v_c regulation vs alignment reference'); % one window, updated at each call

subplot(2, 1, 1), hold on, grid on, box on
plot(tSync * 1e3, syncCapture.v_c);
plot(tReg * 1e3, regCapture.v_c, '--');
ylabel('Voltage (V)');
legend('v_c reference (alignment, no load)', 'v_c after regulation', 'Location', 'eastoutside');
title(sprintf('v_c | reference %.2f V rms, regulated %.2f V rms | error %+.3f V rms, %+.3f deg', ...
    abs(VcSync), abs(VcReg), ampError, phaseError));

subplot(2, 1, 2), hold on, grid on, box on
plot(tSync * 1e3, syncCapture.v_dac);
plot(tReg * 1e3, regCapture.v_dac, '--');
xlabel('Time on the internal oscillator axis (ms)');
ylabel('Voltage (V)');
legend('v_{DAC} at alignment', 'v_{DAC} after regulation', 'Location', 'eastoutside');
title(sprintf('v_{DAC} | Mp_{AC} %.4f -> %.4f, \\phi_{AC} %+.4f -> %+.4f rad (%+.2f deg)', ...
    syncCapture.Mp_AC, regCapture.Mp_AC, syncCapture.phi_AC, regCapture.phi_AC, ...
    rad2deg(angle(exp(1j * (regCapture.phi_AC - syncCapture.phi_AC))))));

drawnow;

end

function [tOsc, VcClk] = oscillatorTime(capture, f0, w0)
% Time axis of a capture shifted onto the internal oscillator phase, and the
% v_c phasor in the oscillator frame
dt = capture.t(2) - capture.t(1);
Pdac = fcn_FundamentalPhasor(capture.v_dac, dt, f0);
Pvc = fcn_FundamentalPhasor(capture.v_c, dt, f0);
oscPhase0 = angle(Pdac) - capture.phi_AC; % oscillator phase at the first sample (+ constant)
tOsc = capture.t + mod(oscPhase0, 2*pi) / w0;
VcClk = Pvc * conj(Pdac) / abs(Pdac) * exp(1j * capture.phi_AC);
end
