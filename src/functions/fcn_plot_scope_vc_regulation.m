function figureHandle = fcn_plot_scope_vc_regulation(scopeMimicry, tLimMs)
%FCN_PLOT_SCOPE_VC_REGULATION plots the v_c regulation channels of the board ScopeMimicry
%   v_ref (sine) and v_c (Vgrid) with their instantaneous difference, then the
%   dq components of v_c computed by regulate_vc_to_vref() at every control step,
%   before (Vd_raw, Vq_raw) and after (Vd, Vq = PI inputs) the 20 Hz low-pass filter,
%   with their references V_d_ref = V_ref and V_q_ref = 0 (constants, drawn as lines)
%   and the mean dq errors in the legends.
%
%   scopeMimicry: struct from fcn_scope_mimicry_acquisition (t + one field per channel)
%   tLimMs (optional): [ms] time axis limits [tStart tEnd]. When given, the plot goes
%   in a separate window ('... (zoom)') and the rms of v_ref - v_c is computed on
%   these limits only.

tMs = scopeMimicry.t * 1e3;
Vref = max(abs(scopeMimicry.sine)); % [V peak] amplitude of the teaching sine

if nargin < 2 || isempty(tLimMs)
    tLimMs = [];
    figName = 'ScopeMimicry v_c regulation';
    inLim = true(size(tMs));
else
    figName = 'ScopeMimicry v_c regulation (zoom)';
    inLim = tMs >= tLimMs(1) & tMs <= tLimMs(2);
end

figureHandle = fcn_reuse_figure(figName); % one window, updated at each call

% Instantaneous voltages
ax(1) = subplot(4, 1, 1); hold on, grid on, box on
plot(tMs, scopeMimicry.sine);
plot(tMs, scopeMimicry.Vgrid);
ylabel('Voltage (V)');
legend('v_{ref} (sine)', 'v_c (Vgrid)', 'Location', 'eastoutside');
title(figName);

% Instantaneous regulation error
ax(2) = subplot(4, 1, 2); hold on, grid on, box on
plot(tMs, scopeMimicry.vc_error);
ylabel('Voltage (V)');
legend(sprintf('v_{ref} - v_c (rms %.3f V)', rms(scopeMimicry.vc_error(inLim))), 'Location', 'eastoutside');

% Captures of the phasor (per grid period) regulation have E_M/E_phi instead of Vd/Vq
if ~isfield(scopeMimicry, 'Vd')
    % Phasor amplitude and amplitude error
    ax(3) = subplot(4, 1, 3); hold on, grid on, box on
    yyaxis left
    plot(tMs, scopeMimicry.Vc_amplitude);
    yline(Vref, '--');
    ylabel('Voltage (V peak)');
    yyaxis right
    plot(tMs, scopeMimicry.E_M);
    ylabel('E_M (V)');
    legend('|V_c|', '|V_{ref}|', 'E_M = |V_{ref}| - |V_c|', 'Location', 'eastoutside');

    % Phase error
    ax(4) = subplot(4, 1, 4); hold on, grid on, box on
    plot(tMs, rad2deg(scopeMimicry.E_phi));
    ylabel('E_\phi (deg)');
    legend('E_\phi = \phi_{V_c} - \phi_{V_{ref}}', 'Location', 'eastoutside');

    xlabel('Time (ms)');
    if ~isempty(tLimMs)
        linkaxes(ax, 'x');
        xlim(ax(1), tLimMs);
        ylim(ax(1), fcn_padded_lim([scopeMimicry.sine(inLim); scopeMimicry.Vgrid(inLim)]));
        ylim(ax(2), fcn_padded_lim(scopeMimicry.vc_error(inLim)));
        yyaxis(ax(3), 'left');
        ylim(ax(3), fcn_padded_lim([scopeMimicry.Vc_amplitude(inLim); Vref]));
        yyaxis(ax(3), 'right');
        ylim(ax(3), fcn_padded_lim(scopeMimicry.E_M(inLim)));
        ylim(ax(4), fcn_padded_lim(rad2deg(scopeMimicry.E_phi(inLim))));
    end
    drawnow;
    return
end

% Mean dq errors seen by the PIs (filtered V_d/V_q), over tLimMs when given
E_d = mean(Vref - scopeMimicry.Vd(inLim));
E_q = mean(0 - scopeMimicry.Vq(inLim));

% d axis: V_d (raw and filtered) and its reference V_d_ref = V_ref
ax(3) = subplot(4, 1, 3); hold on, grid on, box on
plot(tMs, scopeMimicry.Vd_raw, 'Color', [0.6 0.6 0.6]);
plot(tMs, scopeMimicry.Vd, 'LineWidth', 1.2);
plot(tMs, scopeMimicry.Vc_amplitude, ':');
yline(Vref, '--');
ylabel('V_d (V)');
legend('V_d raw', 'V_d filtered (PI input)', '|V_c|', ...
    sprintf('V_{d,ref} = V_{ref} (mean error %.3f V)', E_d), 'Location', 'eastoutside');

% q axis: V_q (raw and filtered) and its reference V_q_ref = 0
ax(4) = subplot(4, 1, 4); hold on, grid on, box on
plot(tMs, scopeMimicry.Vq_raw, 'Color', [0.6 0.6 0.6]);
plot(tMs, scopeMimicry.Vq, 'LineWidth', 1.2);
yline(0, '--');
ylabel('V_q (V)');
legend('V_q raw', 'V_q filtered (PI input)', ...
    sprintf('V_{q,ref} = 0 (mean error %.3f V)', E_q), 'Location', 'eastoutside');

xlabel('Time (ms)');

if ~isempty(tLimMs)
    linkaxes(ax, 'x');
    xlim(ax(1), tLimMs);
    % y limits from the samples inside tLimMs only (else the start transient sets them)
    ylim(ax(1), fcn_padded_lim([scopeMimicry.sine(inLim); scopeMimicry.Vgrid(inLim)]));
    ylim(ax(2), fcn_padded_lim(scopeMimicry.vc_error(inLim)));
    ylim(ax(3), fcn_padded_lim([scopeMimicry.Vd_raw(inLim); scopeMimicry.Vd(inLim); ...
        scopeMimicry.Vc_amplitude(inLim); Vref]));
    ylim(ax(4), fcn_padded_lim([scopeMimicry.Vq_raw(inLim); scopeMimicry.Vq(inLim); 0]));
end
drawnow;

end

function lim = fcn_padded_lim(x)
%FCN_PADDED_LIM [min max] of x with a 10 % margin (non-zero range if x is constant)
lo = min(x);
hi = max(x);
margin = 0.1 * max(hi - lo, max(abs([lo hi])) * 1e-3 + eps);
lim = [lo - margin, hi + margin];
end
