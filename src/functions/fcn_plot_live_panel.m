function fcn_plot_live_panel(fig, meas, hist, cfg)
%FCN_PLOT_LIVE_PANEL redraws the live panel of the PQ exploration (one
%maximized window, 2 x 3 tiles, updated after each point)
%   Upper left:   PicoScope curves (v_s, v_c / i_c_pos, i_c_neg)
%   Lower left:   ScopeMimicry curves (Vgrid / I1_low, I2_low)
%   Upper middle: v_c after the regulation vs its reference from the alignment,
%                 with the DAC voltages, on the internal oscillator time axis
%   Lower middle: MOSFET temperature of each measured PQ point
%   Upper right:  PQ diagram (aligned point, grey/red/black points, board P/Q)
%   Lower right:  values of the last point, PicoScope vs ScopeMimicry
%
%   meas: last point, from fcn_measure_PQ_point_vcreg
%   hist: exploration so far - P0, Q0 (aligned point) and one value per
%         measured point: P, Q, P_board, Q_board, cls (0 grey, 1 red,
%         2 black), T1, T2 [degC], vcRegulated
%   cfg:  chIdx, timeIntervalNanoSeconds, syncCapture, f0, Tj_lim [K], label
%         (text of the panel title)

figure(fig);
clf(fig);
main = tiledlayout(fig, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
title(main, sprintf('%s | M_p = %.4f, \\phi_m = %+.4f rad', cfg.label, meas.Mp, meas.phi_m), 'FontWeight', 'bold');

s1 = meas.channelData{1};
s2 = meas.channelData{2};
t1 = (0:numel(s1{cfg.chIdx.Vc}) - 1).' * double(cfg.timeIntervalNanoSeconds{1}) * 1e-9 * 1e3; % [ms]
t2 = (0:numel(s2{cfg.chIdx.Icneg}) - 1).' * double(cfg.timeIntervalNanoSeconds{2}) * 1e-9 * 1e3; % [ms]
sm = meas.scopeMimicry;
tsm = sm.t * 1e3; % [ms]

%% Upper left: PicoScope curves
tl = tiledlayout(main, 2, 1, 'TileSpacing', 'tight');
tl.Layout.Tile = 1;
title(tl, 'PicoScope', 'FontWeight', 'bold');
ax = nexttile(tl); hold(ax, 'on'), grid(ax, 'on'), box(ax, 'on')
plot(ax, t1, s1{cfg.chIdx.Vs}, t1, s1{cfg.chIdx.Vc}, 'LineWidth', 1);
ylabel(ax, 'v [V]'), legend(ax, 'v_s', 'v_c', 'Location', 'eastoutside'), ylim(ax, [-20 20])
ax = nexttile(tl); hold(ax, 'on'), grid(ax, 'on'), box(ax, 'on')
plot(ax, t1, s1{cfg.chIdx.Icpos}, t2, s2{cfg.chIdx.Icneg}, 'LineWidth', 1);
ylabel(ax, 'i [A]'), xlabel(ax, 'time [ms]'), legend(ax, 'i_{c,pos}', 'i_{c,neg}', 'Location', 'eastoutside')

%% Lower left: ScopeMimicry curves
tl = tiledlayout(main, 2, 1, 'TileSpacing', 'tight');
tl.Layout.Tile = 4;
title(tl, 'ScopeMimicry (board)', 'FontWeight', 'bold');
ax = nexttile(tl); hold(ax, 'on'), grid(ax, 'on'), box(ax, 'on')
plot(ax, tsm, sm.Vgrid, 'LineWidth', 1);
ylabel(ax, 'v [V]'), legend(ax, 'V_{grid} (v_c)', 'Location', 'eastoutside'), ylim(ax, [-20 20])
ax = nexttile(tl); hold(ax, 'on'), grid(ax, 'on'), box(ax, 'on')
plot(ax, tsm, sm.I1_low_value, tsm, sm.I2_low_value, 'LineWidth', 1);
ylabel(ax, 'i [A]'), xlabel(ax, 'time [ms]'), legend(ax, 'I_{1,low}', 'I_{2,low}', 'Location', 'eastoutside')

%% Upper middle: v_c regulation vs alignment reference (oscillator time axis)
ref = cfg.syncCapture;
reg = meas.regCapture;
[tRef, VcRef] = oscillatorTime(ref, cfg.f0);
[tReg, VcReg] = oscillatorTime(reg, cfg.f0);
regText = 'converged';
if ~meas.vcRegulated
    regText = 'NOT converged';
end
tl = tiledlayout(main, 2, 1, 'TileSpacing', 'tight');
tl.Layout.Tile = 2;
title(tl, sprintf('v_c regulation (%s) | error %+.3f V rms, %+.3f deg', regText, ...
    abs(VcReg) - abs(VcRef), rad2deg(angle(VcReg / VcRef))), 'FontWeight', 'bold');
ax = nexttile(tl); hold(ax, 'on'), grid(ax, 'on'), box(ax, 'on')
plot(ax, tRef * 1e3, ref.v_c, tReg * 1e3, reg.v_c, '--', 'LineWidth', 1);
ylabel(ax, 'v_c [V]'), legend(ax, 'reference (alignment)', 'after regulation', 'Location', 'eastoutside'), ylim(ax, [-20 20])
ax = nexttile(tl); hold(ax, 'on'), grid(ax, 'on'), box(ax, 'on')
plot(ax, tRef * 1e3, ref.v_dac, tReg * 1e3, reg.v_dac, '--', 'LineWidth', 1);
ylabel(ax, 'v_{DAC} [V]'), xlabel(ax, 'time on oscillator axis [ms]')
legend(ax, sprintf('alignment (M_{AC} %.3f)', ref.Mp_AC), sprintf('regulated (M_{AC} %.3f)', reg.Mp_AC), 'Location', 'eastoutside')

%% Lower middle: MOSFET temperature of each measured PQ point
ax = nexttile(main, 5); hold(ax, 'on'), grid(ax, 'on'), box(ax, 'on')
if ~isempty(hist.T1)
    plot(ax, 1:numel(hist.T1), hist.T1, '-o', 1:numel(hist.T2), hist.T2, '-s', 'LineWidth', 1);
    legend(ax, 'Temp1', 'Temp2', 'Location', 'southeast')
    ylim(ax, [floor(min([hist.T1, hist.T2])) - 2, ceil(max([hist.T1, hist.T2])) + 2])
end
xlabel(ax, 'PQ point'), ylabel(ax, 'T [°C]')
title(ax, sprintf('Temperatures (mean of readings) | T_{j,lim} = %.0f °C on Temp1', cfg.Tj_lim - 273.15))

%% Upper right: PQ diagram
ax = nexttile(main, 3); hold(ax, 'on'), grid(ax, 'on'), box(ax, 'on'), axis(ax, 'square')
% Each series starts with a NaN (not drawn) so that its line exists even
% while it has no point yet: plot with empty data creates no line, which
% would shift the legend entries
hPQ(1) = plot(ax, [NaN, hist.P0], [NaN, hist.Q0], 'ob', 'MarkerSize', 9);
hPQ(2) = plot(ax, [NaN, hist.P(hist.cls == 0)], [NaN, hist.Q(hist.cls == 0)], '.', 'Color', [0.6 0.6 0.6], 'MarkerSize', 14);
hPQ(3) = plot(ax, [NaN, hist.P(hist.cls == 1)], [NaN, hist.Q(hist.cls == 1)], '.r', 'MarkerSize', 14);
hPQ(4) = plot(ax, [NaN, hist.P(hist.cls == 2)], [NaN, hist.Q(hist.cls == 2)], 'xk', 'MarkerSize', 10, 'LineWidth', 1.5);
hPQ(5) = plot(ax, [NaN, hist.P_board], [NaN, hist.Q_board], 'd', 'Color', [0 0.447 0.741], 'MarkerSize', 5);
hPQ(6) = plot(ax, [NaN, hist.P(~hist.vcRegulated)], [NaN, hist.Q(~hist.vcRegulated)], 'om', 'MarkerSize', 9);
hPQ(7) = plot(ax, [NaN, meas.P], [NaN, meas.Q], 'p', 'Color', [0.929 0.694 0.125], 'MarkerSize', 12, 'LineWidth', 1.2); %last point
PQ_lim = max([5, ceil(max(abs([hist.P, hist.Q, hist.P_board, hist.Q_board, meas.P, meas.Q])) / 5) * 5 + 5]);
xlim(ax, [-PQ_lim PQ_lim]), ylim(ax, [-PQ_lim PQ_lim])
xlabel(ax, 'P_c [W]'), ylabel(ax, 'Q_c [VAr]'), title(ax, sprintf('PQ diagram | %d points', numel(hist.P)))
legend(hPQ, {'aligned point', 'grey point', 'red point', 'black point (constraint)', 'board (ScopeMimicry)', ...
    'v_c not regulated', 'last point'}, 'Location', 'eastoutside')

%% Lower right: values of the last point
ax = nexttile(main, 6); axis(ax, 'off'); title(ax, 'Last point values');

Pdc_board = mean(sm.Vdc .* sm.idc);
eta_board = efficiency(mean(sm.P_board), Pdc_board);
rows = {
    'v_c AC (rms)',  sprintf('%6.2f V', rms(s1{cfg.chIdx.Vc})),     sprintf('%6.2f V', rms(sm.Vgrid));
    'i_c AC (rms)',  sprintf('%6.2f A', rms(s1{cfg.chIdx.Icpos})),  sprintf('%6.2f A', rms(sm.I1_low_value));
    'u_{dc} (mean)', sprintf('%6.2f V', mean(s2{cfg.chIdx.Udc})),   sprintf('%6.2f V', mean(sm.Vdc));
    'i_{dc} (mean)', sprintf('%6.2f A', mean(s2{cfg.chIdx.Idc})),   sprintf('%6.2f A', mean(sm.idc));
    'P',             sprintf('%6.2f W', meas.P),                    sprintf('%6.2f W', mean(sm.P_board));
    'Q',             sprintf('%6.2f VAr', meas.Q),                  sprintf('%6.2f VAr', mean(sm.Q_board));
    'P_{dc}',        sprintf('%6.2f W', meas.Pdc),                  sprintf('%6.2f W', Pdc_board);
    '\eta',          sprintf('%6.2f %%', 100 * meas.eta),           sprintf('%6.2f %%', 100 * eta_board);
    };
x = [0.02 0.40 0.72]; y0 = 0.92; dy = 0.10;
text(ax, x(2), y0, 'PicoScope', 'FontWeight', 'bold', 'FontSize', 12);
text(ax, x(3), y0, 'ScopeMimicry', 'FontWeight', 'bold', 'FontSize', 12);
for r = 1:size(rows, 1)
    y = y0 - r * dy;
    text(ax, x(1), y, rows{r, 1}, 'FontSize', 12);
    text(ax, x(2), y, rows{r, 2}, 'FontSize', 12, 'FontName', 'Consolas', 'Interpreter', 'none');
    text(ax, x(3), y, rows{r, 3}, 'FontSize', 12, 'FontName', 'Consolas', 'Interpreter', 'none');
end
text(ax, x(1), y0 - 9.2 * dy, sprintf('Mp_{AC} = %.4f, \\phi_{AC} = %+.4f rad | v_c regulation: %s', ...
    meas.Mp_AC, meas.phi_AC, regText), 'FontSize', 11);

drawnow;

end

function [tOsc, VcClk] = oscillatorTime(capture, f0)
% Time axis of a capture shifted onto the internal oscillator phase, and the
% v_c phasor in the oscillator frame (see fcn_plot_vc_regulation)
dt = capture.t(2) - capture.t(1);
Pdac = fcn_FundamentalPhasor(capture.v_dac, dt, f0);
Pvc = fcn_FundamentalPhasor(capture.v_c, dt, f0);
tOsc = capture.t + mod(angle(Pdac) - capture.phi_AC, 2*pi) / (2*pi*f0);
VcClk = Pvc * conj(Pdac) / abs(Pdac) * exp(1j * capture.phi_AC);
end

function eta = efficiency(Pac, Pdc)
% Output / input power for the actual power flow direction (as fcn_save_PQ_point)
if Pdc > 0 && Pac > 0
    eta = Pac / Pdc; % inverter mode: DC -> AC
elseif Pdc < 0 && Pac < 0
    eta = Pdc / Pac; % rectifier mode: AC -> DC
else
    eta = NaN;
end
end
