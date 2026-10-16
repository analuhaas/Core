function figureHandle = fcn_plot_scope_mimicry(scopeMimicry)
%FCN_PLOT_SCOPE_MIMICRY plots the board ScopeMimicry measurements
%   Each legend says to which PicoScope measurement the ScopeMimicry channel
%   corresponds (v_c, v_s, i_c_pos, i_c_neg, u_dc, i_dc, v_dac). The internal
%   control variables (duty cycles, modulation, state) are not plotted.
%   The active and reactive powers computed by the board (P_board, Q_board)
%   are plotted when the capture has them.
%
%   scopeMimicry: struct from fcn_scope_mimicry_acquisition (t + one field per channel)

tMs = scopeMimicry.t * 1e3;
hasPower = isfield(scopeMimicry, 'P_board') && isfield(scopeMimicry, 'Q_board');
numRows = 5 + hasPower;

figureHandle = fcn_reuse_figure('ScopeMimicry measurements'); % one window, updated at each call

% AC voltage: V1_low - V2_low, converter terminal voltage (= v_s once the switch is closed)
subplot(numRows, 1, 1), hold on, grid on, box on
plot(tMs, scopeMimicry.Vgrid);
ylabel('Voltage (V)');
legend('Vgrid \leftrightarrow v_c (v_s when switch closed)', 'Location', 'eastoutside');
title('ScopeMimicry measurements');

% AC currents of both legs
subplot(numRows, 1, 2), hold on, grid on, box on
plot(tMs, scopeMimicry.I1_low_value);
plot(tMs, scopeMimicry.I2_low_value);
ylabel('Current (A)');
legend('I1\_low \leftrightarrow i_{c,pos}', 'I2\_low \leftrightarrow i_{c,neg}', 'Location', 'eastoutside');

% Internal oscillator driving the DAC (unitless, same phase as v_dac)
subplot(numRows, 1, 3), hold on, grid on, box on
plot(tMs, scopeMimicry.sine);
ylabel('sine (-)');
legend('sine \leftrightarrow v_{DAC}', 'Location', 'eastoutside');

% DC side
subplot(numRows, 1, 4), hold on, grid on, box on
yyaxis left
plot(tMs, scopeMimicry.Vdc);
ylabel('Voltage (V)');
yyaxis right
plot(tMs, scopeMimicry.idc);
ylabel('Current (A)');
legend('Vdc \leftrightarrow u_{dc}', 'idc \leftrightarrow i_{dc}', 'Location', 'eastoutside');

% Temperatures (board Temp1 and Temp2)
subplot(numRows, 1, 5), hold on, grid on, box on
plot(tMs, scopeMimicry.T1);
plot(tMs, scopeMimicry.T2);
ylabel('T (°C)');
legend('T1 (Temp1)', 'T2 (Temp2)', 'Location', 'eastoutside');

% Active and reactive power computed by the board (SOGI + dq on Vgrid and I1_low)
if hasPower
    subplot(numRows, 1, 6), hold on, grid on, box on
    plot(tMs, scopeMimicry.P_board);
    plot(tMs, scopeMimicry.Q_board);
    ylabel('P (W), Q (VAr)');
    legend(sprintf('P\\_board (mean %.2f W) \\leftrightarrow P_{fft}', mean(scopeMimicry.P_board)), ...
        sprintf('Q\\_board (mean %.2f VAr) \\leftrightarrow Q_{fft}', mean(scopeMimicry.Q_board)), ...
        'Location', 'eastoutside');
end

xlabel('Time (ms)');
drawnow;

end
