%% Plot PQ points - tests of 2026-10-16
% PQ circle test (main_supervisor_script_PQdiagram_HAAS_20261016): PQ points
% measured by PicoScope and by the board (ScopeMimicry), and the voltage and
% current curves of each point.
% Temperature test (main_supervisor_script_PQdiagram_temptest_HAAS_20261016):
% temperature monitoring and histograms of the temperature series.
%
% PQpoint files order (sorted by date and time, as saved by the main script):
% - the first numCheckpoints files: before alignment, after alignment, switch closed
% - then one pair per PQ point: before and after the v_c regulation
% Only the points after the v_c regulation are plotted.

clear, close all, clc

scriptDir = fileparts(mfilename('fullpath'));
if isempty(scriptDir)
    scriptDir = pwd; % run section by section
end

%% Settings

dataFolder = fullfile(scriptDir, '20261016');
figuresFolder = fullfile(scriptDir, 'Figures', '20261016');
numCheckpoints = 3;   % checkpoint files before the PQ points
saveFigures = true;   % export all figures to .png with figure_PP (last section)

tempMonitorFile = 'TempMonitor_20261016_142219.mat';
tempSeriesFile = 'TempSeries_20261016_143957.mat';

%% Load the PQ points (after the v_c regulation)

files = dir(fullfile(dataFolder, 'PQpoint_*.mat'));
[~, order] = sort({files.name}); % date and time first in the name -> chronological
files = files(order);

numPoints = (numel(files) - numCheckpoints) / 2;
if numPoints ~= floor(numPoints) || numPoints < 1
    error('%d PQpoint files: expected %d checkpoints followed by pairs (before/after regulation).', ...
        numel(files), numCheckpoints);
end

pts = cell(1, numPoints);
for k = 1:numPoints
    fileBefore = files(numCheckpoints + 2*k - 1).name;
    fileAfter = files(numCheckpoints + 2*k).name;
    pts{k} = load(fullfile(dataFolder, fileAfter));
    sBefore = load(fullfile(dataFolder, fileBefore), 'Mp', 'phi_m');
    if abs(sBefore.Mp - pts{k}.Mp) > 1e-6 || abs(sBefore.phi_m - pts{k}.phi_m) > 1e-6
        warning('PQ point %d: %s and %s do not have the same Mp/phi_m.', k, fileBefore, fileAfter);
    end
end

P_pico = cellfun(@(s) s.Pfft, pts);
Q_pico = cellfun(@(s) s.Qfft, pts);
P_board = cellfun(@(s) mean(s.sm_P_board), pts);
Q_board = cellfun(@(s) mean(s.sm_Q_board), pts);

fprintf('\n  #   Mp      phi_m    | P_pico   Q_pico  | P_board  Q_board\n');
for k = 1:numPoints
    fprintf('%3d   %.4f  %+.3f   | %7.2f  %7.2f | %7.2f  %7.2f\n', k, pts{k}.Mp, pts{k}.phi_m, ...
        P_pico(k), Q_pico(k), P_board(k), Q_board(k));
end

%% PQ diagram: PicoScope vs ScopeMimicry (after v_c regulation)

PQ_lim = ceil(max(abs([P_pico, Q_pico, P_board, Q_board])) / 5) * 5 + 5; % symmetric axes

figure(1), axis square, box on, grid on, hold on

plot(P_pico, Q_pico, 'o', 'LineWidth', 1);
plot(P_board, Q_board, 'd', 'LineWidth', 1);

xlim([-PQ_lim, PQ_lim])
ylim([-PQ_lim, PQ_lim])
ylabel('$Q$ [VAr]','Interpreter','latex')
xlabel('$P$ [W]','Interpreter','latex')
legend('PicoScope','ScopeMimicry','Interpreter','latex'), legend boxon % R2018b and later

%% Voltage and current curves of each PQ point: PicoScope

for k = 1:numPoints

    s = pts{k};
    t_Pico = s.t_scope1; % [s]

    figure(10 + k), hold on

    subplot(3,1,1), box on, grid on, hold on

    plot(t_Pico,s.v_s,'-','LineWidth',1);
    plot(t_Pico,s.v_c,'-','LineWidth',1);

    ylim([-20, 20])
    ylabel('$v$ [V]','Interpreter','latex')
    legend('$v_{s}$','$v_{c}$','Interpreter','latex'), legend boxon % R2018b and later
    title(sprintf('Point %d | $M_p$ = %.4f, $\\phi_m$ = %+.3f rad | $P$ = %.2f W, $Q$ = %.2f VAr (PicoScope)', ...
        k, s.Mp, s.phi_m, s.Pfft, s.Qfft),'Interpreter','latex')

    subplot(3,1,2), box on, grid on, hold on

    plot(t_Pico,s.v_dac,'-','LineWidth',1);

    ylabel('$v_{DAC}$ [V]','Interpreter','latex')

    subplot(3,1,3), box on, grid on, hold on

    plot(t_Pico,s.i_c_pos,'-','LineWidth',1);
    text(0.07,1.4,"$I_{rms}=$ "+string(round(s.Icpos_rms,2))+" A",'Interpreter','latex')

    ylim([-2, 2])
    ylabel('$i_{c}$ [A]','Interpreter','latex')
    xlabel('$time$ [s]','Interpreter','latex')

end

%% Voltage and current curves of each PQ point: ScopeMimicry (board)

for k = 1:numPoints

    s = pts{k};
    t_SM = s.t_sm; % [s]

    figure(20 + k), hold on

    subplot(3,1,1), box on, grid on, hold on

    plot(t_SM,s.sm_Vgrid,'-','LineWidth',1);

    ylim([-20, 20])
    xlim([0, 0.1])
    ylabel('$v$ [V]','Interpreter','latex')
    legend('$v_{c}$ ($V_{grid}$)','Interpreter','latex'), legend boxon % R2018b and later
    title(sprintf('Point %d | $M_p$ = %.4f, $\\phi_m$ = %+.3f rad | $P$ = %.2f W, $Q$ = %.2f VAr (ScopeMimicry)', ...
        k, s.Mp, s.phi_m, mean(s.sm_P_board), mean(s.sm_Q_board)),'Interpreter','latex')

    subplot(3,1,2), box on, grid on, hold on

    plot(t_SM,s.sm_sine,'-','LineWidth',1);

    ylim([-1.2, 1.2])
    xlim([0, 0.1])
    ylabel('sine [-]','Interpreter','latex')
    legend('sine $\leftrightarrow v_{DAC}$','Interpreter','latex'), legend boxon % R2018b and later

    subplot(3,1,3), box on, grid on, hold on
    n = length(s.sm_I1_low_value);
    plot(t_SM,s.sm_I1_low_value,'-','LineWidth',1);
    text(0.07,1.4,"$I_{rms}=$ "+string(round(rms(s.sm_I1_low_value(n-200:n)),2))+" A",'Interpreter','latex')

    ylim([-2, 2])
    xlim([0, 0.1])
    ylabel('$i_{c}$ ($I_{1,low}$) [A]','Interpreter','latex')
    xlabel('$time$ [s]','Interpreter','latex')

end

%% Temperature monitoring (temperature test)

load(fullfile(dataFolder, tempMonitorFile));

figure(30), box on, grid on, hold on

plot(tempMonitorTime_s./60,tempMonitorTemp2,'-o','LineWidth',1);
plot(tempMonitorTime_s./60,tempMonitorTemp1,'-o','LineWidth',1);
if exist('tempAmbient', 'var') % ambient reading when u_dc was turned on, before the monitoring
    ax = gca; ax.ColorOrderIndex = 1; % same colors as Temp2 / Temp1
    plot(tempAmbientTime_s/60,tempAmbient.Temp2,'p','MarkerSize',5,'LineWidth',1);
    plot(tempAmbientTime_s/60,tempAmbient.Temp1,'p','MarkerSize',5,'LineWidth',1);
    legend('$T_{Q1,case}$','$T_{Q1,drain}$','$T_{Q1,case}$ ambient','$T_{Q1,drain}$ ambient', ...
        'Interpreter','latex','Location','best'), legend boxon % R2018b and later
else
    legend('$T_{Q1,case}$','$T_{Q1,drain}$','Interpreter','latex','Location','best'), legend boxon % R2018b and later
end

ylabel('$T$ [$^o$C]','Interpreter','latex')
xlabel('$time$ [min]','Interpreter','latex')
title(sprintf('Mean of %d readings %.1f s apart, every %.0f s', ...
    tempBurstCount, tempBurstSpacing_s, tempMonitorPeriod_s),'Interpreter','latex')

%% Histograms of the temperature series (temperature test)

load(fullfile(dataFolder, tempSeriesFile));

numBins = 20;

figure(31), hold on

subplot(2,1,1), box on, grid on, hold on

histogram(tempSeriesTemp2, numBins);
xlabel('$T_{Q1,case}$ [$^o$C]','Interpreter','latex')
ylabel('Number of readings','Interpreter','latex')
title(sprintf('$T_{Q1,case}$ | mean = %.2f $^o$C, standard deviation = %.3f $^o$C', ...
    mean(tempSeriesTemp2,'omitnan'), std(tempSeriesTemp2,'omitnan')),'Interpreter','latex')

subplot(2,1,2), box on, grid on, hold on

histogram(tempSeriesTemp1, numBins);
xlabel('$T_{Q1,drain}$ [$^o$C]','Interpreter','latex')
ylabel('Number of readings','Interpreter','latex')
title(sprintf('$T_{Q1,drain}$ | mean = %.2f $^o$C, standard deviation = %.3f $^o$C', ...
    mean(tempSeriesTemp1,'omitnan'), std(tempSeriesTemp1,'omitnan')),'Interpreter','latex')

%% Save figures

if saveFigures
    addpath('C:\Users\ana\Documents\PhD\Presentations et livrables\Templates_Loic\figure_PP_QUEVAL_20231221\core') % Add figure_PP folder to the path
    if ~exist(figuresFolder, 'dir')
        mkdir(figuresFolder);
    end

    figure_PP(1,fullfile(figuresFolder,'PQ_diagram_PicoScope_ScopeMimicry.png'),'width',8.75,'height',6) % Export to .png

    for k = 1:numPoints
        figure_PP(10 + k,fullfile(figuresFolder,sprintf('point%d_curves_PicoScope.png',k)),'width',8.75,'height',6) % Export to .png
        figure_PP(20 + k,fullfile(figuresFolder,sprintf('point%d_curves_ScopeMimicry.png',k)),'width',8.75,'height',6) % Export to .png
    end

    figure_PP(30,fullfile(figuresFolder,'temperature_monitoring.png'),'width',8.75,'height',6) % Export to .png
    figure_PP(31,fullfile(figuresFolder,'temperature_series_histograms.png'),'width',8.75,'height',6) % Export to .png
end
