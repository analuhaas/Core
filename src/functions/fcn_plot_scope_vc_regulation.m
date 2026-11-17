function figureHandle = fcn_plot_scope_vc_regulation(scopeMimicry)
%FCN_PLOT_SCOPE_VC_REGULATION plots the v_c regulation channels of the board ScopeMimicry
%   v_ref (sine) and v_c (Vgrid) with their instantaneous difference, then the
%   phasor values computed by regulate_vc_to_vref() once per grid period
%   (20 ms): |V_c| with |V_ref|, the amplitude error E_M and the phase error E_phi.
%
%   scopeMimicry: struct from fcn_scope_mimicry_acquisition (t + one field per channel)

tMs = scopeMimicry.t * 1e3;
Vref = max(abs(scopeMimicry.sine)); % [V peak] amplitude of the teaching sine

figureHandle = fcn_reuse_figure('ScopeMimicry v_c regulation'); % one window, updated at each call

% Instantaneous voltages
subplot(4, 1, 1), hold on, grid on, box on
plot(tMs, scopeMimicry.sine);
plot(tMs, scopeMimicry.Vgrid);
ylabel('Voltage (V)');
legend('v_{ref} (sine)', 'v_c (Vgrid)', 'Location', 'eastoutside');
title('ScopeMimicry v_c regulation');

% Instantaneous regulation error
subplot(4, 1, 2), hold on, grid on, box on
plot(tMs, scopeMimicry.vc_error);
ylabel('Voltage (V)');
legend(sprintf('v_{ref} - v_c (rms %.3f V)', rms(scopeMimicry.vc_error)), 'Location', 'eastoutside');

% Phasor amplitude and amplitude error
subplot(4, 1, 3), hold on, grid on, box on
yyaxis left
plot(tMs, scopeMimicry.Vc_amplitude);
yline(Vref, '--');
ylabel('Voltage (V peak)');
yyaxis right
plot(tMs, scopeMimicry.E_M);
ylabel('E_M (V)');
legend('|V_c|', '|V_{ref}|', 'E_M = |V_{ref}| - |V_c|', 'Location', 'eastoutside');

% Phase error
subplot(4, 1, 4), hold on, grid on, box on
plot(tMs, rad2deg(scopeMimicry.E_phi));
ylabel('E_\phi (deg)');
legend('E_\phi = \phi_{V_c} - \phi_{V_{ref}}', 'Location', 'eastoutside');

xlabel('Time (ms)');
drawnow;

end
