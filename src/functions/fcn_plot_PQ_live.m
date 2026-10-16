function fcn_plot_PQ_live(figurePQ, PQ_aligned, PQ_before, PQ_after, PQ_board_before, PQ_board_after)
%FCN_PLOT_PQ_LIVE redraws the live PQ diagram of the PQ circle test
%   PQ_aligned: [P Q] measured right after the switch was closed (aligned point)
%   PQ_before, PQ_after: one row [P Q] per PQ point, before and after the v_c
%   regulation, from the PicoScope (FFT method) - NaN for points not measured yet
%   PQ_board_before, PQ_board_after (optional): same, computed by the board
%   (mean of the ScopeMimicry channels P_board and Q_board), drawn as diamonds
%   The figure is brought to the front so the user can follow the test live.

hasBoard = nargin >= 6;

figure(figurePQ);
clf;
hold on, grid on, box on

numPoints = size(PQ_after, 1);
colorAfter = [0 0.447 0.741];
colorBoard = [0.850 0.325 0.098];
colorBefore = [0.6 0.6 0.6];

% How the regulation moved each point (PicoScope)
for k = 1:numPoints
    plot([PQ_before(k, 1), PQ_after(k, 1)], [PQ_before(k, 2), PQ_after(k, 2)], '-', ...
        'Color', colorBefore, 'HandleVisibility', 'off');
end

plot(PQ_aligned(1), PQ_aligned(2), 'k+', 'MarkerSize', 12, 'LineWidth', 1.5);
plot(PQ_before(:, 1), PQ_before(:, 2), 'o', 'Color', colorBefore, 'MarkerSize', 7);
plot(PQ_after(:, 1), PQ_after(:, 2), 'o', 'Color', colorAfter, 'MarkerFaceColor', colorAfter, 'MarkerSize', 7);
legendEntries = {'Aligned point (switch closed)', 'Before v_c regulation (PicoScope)', 'After v_c regulation (PicoScope)'};

if hasBoard
    plot(PQ_board_before(:, 1), PQ_board_before(:, 2), 'd', 'Color', colorBefore, 'MarkerSize', 7);
    plot(PQ_board_after(:, 1), PQ_board_after(:, 2), 'd', 'Color', colorBoard, 'MarkerFaceColor', colorBoard, 'MarkerSize', 7);
    legendEntries = [legendEntries, {'Before v_c regulation (board)', 'After v_c regulation (board)'}];
end

% Point numbers next to the regulated points
for k = 1:numPoints
    if ~isnan(PQ_after(k, 1))
        text(PQ_after(k, 1), PQ_after(k, 2), sprintf('  %d', k), 'Color', colorAfter);
    end
end

axis equal
xlabel('P (W)');
ylabel('Q (VAr)');
legend(legendEntries, 'Location', 'bestoutside');
title(sprintf('PQ diagram | %d / %d points', sum(~isnan(PQ_after(:, 1))), numPoints));
drawnow;

end
