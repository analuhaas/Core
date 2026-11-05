%% Plot PQ points - PQ exploration of 2026-10-22
% PQ exploration (main_supervisor_script_PQdiagram_HAAS_20261016): PQ points
% measured by PicoScope and by the board (ScopeMimicry) on the selected angle
% lines, the voltage and current curves of each point of those lines, and the
% alignment of v_c with its reference before and after the v_c regulation for
% one point.
%
% PQpoint files (sorted by date and time, as saved by the main script):
% - numCheckpoints untagged files: before alignment, after alignment (switch
%   open, no load - reference of the v_c regulation), switch closed
% - then one pair per point, tagged _before_vcreg / _after_vcreg: first the
%   numCalibration Jacobian calibration steps, then the angle lines
% The angle lines are found from the points themselves: along a line the
% points move away from the aligned point, so a new line starts when the
% distance to the aligned point drops.

clear, close all, clc

scriptDir = fileparts(mfilename('fullpath'));
if isempty(scriptDir)
    scriptDir = pwd; % run section by section
end
addpath(fullfile(scriptDir, '..', 'functions')); % fcn_FundamentalPhasor

%% Settings

dataFolder = fullfile(scriptDir, '20261022');
figuresFolder = fullfile(scriptDir, 'Figures', '20261022');
numCheckpoints = 3;      % untagged checkpoint files before the PQ points
idxReference = 2;        % checkpoint after alignment: reference of the v_c regulation
numCalibration = 2;      % Jacobian calibration points (pure-M, pure-phi) before the lines
linesToPlot = 1;         % angle lines whose points are plotted, e.g. 1 or [1 2]
pointForVcFigure = 7;    % point of the first line in linesToPlot shown in the v_c alignment figure
pointForPQFigure = 7;    % point of the first line in linesToPlot shown with the aligned point in the PQ diagram
f0 = 50;                 % [Hz]
saveFigures = true;      % export all figures to .png with figure_PP (last section)

%% Load the files

files = dir(fullfile(dataFolder, 'PQpoint_*.mat'));
[~, order] = sort({files.name}); % date and time first in the name -> chronological
files = files(order);
names = {files.name};

isBefore = contains(names, '_before_vcreg');
isAfter = contains(names, '_after_vcreg');
checkpointFiles = names(~isBefore & ~isAfter);
beforeFiles = names(isBefore);
afterFiles = names(isAfter);

if numel(checkpointFiles) ~= numCheckpoints
    warning('%d untagged checkpoint files found (expected %d).', numel(checkpointFiles), numCheckpoints);
end
numPairs = min(numel(beforeFiles), numel(afterFiles)); % a last point may have no after file (run stopped)

ref = load(fullfile(dataFolder, checkpointFiles{idxReference})); % after alignment, no load
aligned = load(fullfile(dataFolder, checkpointFiles{end}), 'Pfft', 'Qfft', 'Mp', 'phi_m'); % switch closed

before = cell(1, numPairs);
after = cell(1, numPairs);
for p = 1:numPairs
    before{p} = load(fullfile(dataFolder, beforeFiles{p}));
    after{p} = load(fullfile(dataFolder, afterFiles{p}));
    if abs(before{p}.Mp - after{p}.Mp) > 1e-6 || abs(before{p}.phi_m - after{p}.phi_m) > 1e-6
        warning('Pair %d: %s and %s do not have the same Mp/phi_m.', p, beforeFiles{p}, afterFiles{p});
    end
end

%% Find the angle lines

Mp0 = aligned.Mp;      % aligned point
phi0 = aligned.phi_m;
step_M = after{1}.Mp - Mp0;      % calibration steps, used to normalize the distance
step_phi = after{2}.phi_m - phi0;

idxPoints = numCalibration+1:numPairs; % exploration points (pairs index)
Mp_pts = cellfun(@(s) s.Mp, after(idxPoints));
phi_pts = cellfun(@(s) s.phi_m, after(idxPoints));
dist = hypot((Mp_pts - Mp0) / step_M, (phi_pts - phi0) / step_phi);

lineNumber = ones(size(dist));
for n = 2:numel(dist)
    lineNumber(n) = lineNumber(n-1) + (dist(n) < dist(n-1)); % distance drops -> new line
end
fprintf('\n%d exploration points on %d angle line(s) (%d points on line 1)\n', numel(dist), max(lineNumber), sum(lineNumber == 1));

sel = idxPoints(ismember(lineNumber, linesToPlot)); % pairs index of the plotted points
numSel = numel(sel);

P_pico = cellfun(@(s) s.Pfft, after(sel));
Q_pico = cellfun(@(s) s.Qfft, after(sel));
P_board = cellfun(@(s) mean(s.sm_P_board), after(sel));
Q_board = cellfun(@(s) mean(s.sm_Q_board), after(sel));

fprintf('\n  #   Mp      phi_m    | P_pico   Q_pico  | P_board  Q_board | Mp_AC   phi_AC  | v_c reg (iter)\n');
for k = 1:numSel
    s = after{sel(k)};
    fprintf('%3d   %.4f  %+.4f  | %7.2f  %7.2f | %7.2f  %7.2f | %.4f  %+.4f | %d (%d)\n', k, s.Mp, s.phi_m, ...
        P_pico(k), Q_pico(k), P_board(k), Q_board(k), s.Mp_AC, s.phi_AC, s.vcRegulated, s.vcRegIterations);
end

%% PQ diagram: PicoScope vs ScopeMimicry (after v_c regulation)

PQ_lim = ceil(max(abs([P_pico, Q_pico, P_board, Q_board])) / 5) * 5 + 5; % symmetric axes

figure(1), axis square, box on, grid on, hold on

plot(aligned.Pfft, aligned.Qfft, 'k+', 'MarkerSize', 10, 'LineWidth', 1);
plot(P_pico, Q_pico, 'o', 'LineWidth', 1);
% plot(P_board, Q_board, 'd', 'LineWidth', 1);
for k = 1:numSel
    % text(P_pico(k), Q_pico(k), "  " + k, 'Interpreter', 'latex')
end

xlim([-PQ_lim, PQ_lim])
ylim([-PQ_lim, PQ_lim])
ylabel('$Q$ [VAr]','Interpreter','latex')
xlabel('$P$ [W]','Interpreter','latex')
% legend('Aligned point','PicoScope','ScopeMimicry','Interpreter','latex','Location','best'), legend boxon % R2018b and later

%% PQ diagram: aligned point (switch closed) + one point before, then before and after the v_c regulation
% Circles: PicoScope, diamonds: ScopeMimicry. Same axes as figure 1, so the
% figures can be compared.

alignedSM = load(fullfile(dataFolder, checkpointFiles{end}), 'sm_P_board', 'sm_Q_board'); % switch closed, ScopeMimicry
P_aligned_board = mean(alignedSM.sm_P_board);
Q_aligned_board = mean(alignedSM.sm_Q_board);

sPQb = before{sel(pointForPQFigure)}; % point pointForPQFigure before the v_c regulation
P_before_pico = sPQb.Pfft;
Q_before_pico = sPQb.Qfft;
P_before_board = mean(sPQb.sm_P_board);
Q_before_board = mean(sPQb.sm_Q_board);
P_after_pico = P_pico(pointForPQFigure); % after the v_c regulation
Q_after_pico = Q_pico(pointForPQFigure);
P_after_board = P_board(pointForPQFigure);
Q_after_board = Q_board(pointForPQFigure);

colorAligned = [0 0 0];
colorBefore = [0.850 0.325 0.098];
colorAfter = [0 0.447 0.741];

% Aligned point + point before the v_c regulation
figure(2), axis square, box on, grid on, hold on

plot(aligned.Pfft, aligned.Qfft, 'o', 'Color', colorAligned, 'LineWidth', 1);
% plot(P_aligned_board, Q_aligned_board, 'd', 'Color', colorAligned, 'LineWidth', 1);
% plot(P_before_board, Q_before_board, 'd', 'Color', colorBefore, 'LineWidth', 1);

xlim([-PQ_lim, PQ_lim])
ylim([-PQ_lim, PQ_lim])
ylabel('$Q$ [VAr]','Interpreter','latex')
xlabel('$P$ [W]','Interpreter','latex')

% Aligned point + point before the v_c regulation
figure(3), axis square, box on, grid on, hold on

plot(aligned.Pfft, aligned.Qfft, 'o', 'Color', colorAligned, 'LineWidth', 1);
plot(P_before_pico, Q_before_pico, 'o', 'Color', colorBefore, 'LineWidth', 1);
% plot(P_aligned_board, Q_aligned_board, 'd', 'Color', colorAligned, 'LineWidth', 1);
% plot(P_before_board, Q_before_board, 'd', 'Color', colorBefore, 'LineWidth', 1);

xlim([-PQ_lim, PQ_lim])
ylim([-PQ_lim, PQ_lim])
ylabel('$Q$ [VAr]','Interpreter','latex')
xlabel('$P$ [W]','Interpreter','latex')
% legend('Aligned point (PicoScope)', sprintf('Point %d before $v_{c}$ regulation (PicoScope)', pointForPQFigure), ...
    % 'Aligned point (ScopeMimicry)', sprintf('Point %d before $v_{c}$ regulation (ScopeMimicry)', pointForPQFigure), ...
    % 'Interpreter','latex','Location','best'), legend boxon % R2018b and later
% title(sprintf('Point %d before $v_{c}$ regulation: $P$ = %.2f W, $Q$ = %.2f VAr', ...
    % pointForPQFigure, P_before_pico, Q_before_pico),'Interpreter','latex')

% Aligned point + point before and after the v_c regulation
figure(4), axis square, box on, grid on, hold on

plot(aligned.Pfft, aligned.Qfft, 'o', 'Color', colorAligned, 'LineWidth', 1);
plot(P_before_pico, Q_before_pico, 'o', 'Color', colorBefore, 'LineWidth', 1);
plot(P_after_pico, Q_after_pico, 'o', 'Color', colorAfter, 'LineWidth', 1);
% plot(P_aligned_board, Q_aligned_board, 'd', 'Color', colorAligned, 'LineWidth', 1);
% plot(P_before_board, Q_before_board, 'd', 'Color', colorBefore, 'LineWidth', 1);
% plot(P_after_board, Q_after_board, 'd', 'Color', colorAfter, 'LineWidth', 1);

xlim([-PQ_lim, PQ_lim])
ylim([-PQ_lim, PQ_lim])
ylabel('$Q$ [VAr]','Interpreter','latex')
xlabel('$P$ [W]','Interpreter','latex')
% legend('Aligned point (PicoScope)', sprintf('Point %d before $v_{c}$ regulation (PicoScope)', pointForPQFigure), ...
%     sprintf('Point %d after $v_{c}$ regulation (PicoScope)', pointForPQFigure), ...
%     'Aligned point (ScopeMimicry)', sprintf('Point %d before $v_{c}$ regulation (ScopeMimicry)', pointForPQFigure), ...
%     sprintf('Point %d after $v_{c}$ regulation (ScopeMimicry)', pointForPQFigure), ...
%     'Interpreter','latex','Location','best'), legend boxon % R2018b and later
% title(sprintf('Point %d: before $P$ = %.2f W, $Q$ = %.2f VAr $|$ after $P$ = %.2f W, $Q$ = %.2f VAr', ...
%     pointForPQFigure, P_before_pico, Q_before_pico, P_after_pico, Q_after_pico),'Interpreter','latex')

%% Voltage and current curves of each point: PicoScope (after v_c regulation)

for k = 1:numSel

    s = after{sel(k)};
    t_Pico = s.t_scope1; % [s]

    figure(10 + k), hold on

    subplot(3,1,1), box on, grid on, hold on

    plot(t_Pico,s.v_s,'-','LineWidth',1);
    plot(t_Pico,s.v_c,'-','LineWidth',1);

    ylim([-20, 20])
    ylabel('$v$ [V]','Interpreter','latex')
    legend('$v_{s}$','$v_{c}$','Interpreter','latex'), legend boxon % R2018b and later
    title(sprintf('P%d $|$ $M_p$ = %.4f, $\\phi_m$ = %+.4f rad (PicoScope)', ...
        k, s.Mp, s.phi_m),'Interpreter','latex')

    subplot(3,1,2), box on, grid on, hold on

    plot(t_Pico,s.v_dac,'-','LineWidth',1);

    ylabel('$v_{DAC}$ [V]','Interpreter','latex')

    subplot(3,1,3), box on, grid on, hold on

    plot(t_Pico,s.i_c_pos,'-','LineWidth',1);
    text(0.70,0.88,"$I_{rms}=$ "+string(round(s.Icpos_rms,2))+" A",'Units','normalized','BackgroundColor','w','Margin',1,'Interpreter','latex') % fixed place in the axes, readable over the curve

    ylabel('$i_{c}$ [A]','Interpreter','latex')
    xlabel('$time$ [s]','Interpreter','latex')

end

%% Voltage and current curves of point pointForPQFigure: PicoScope (before v_c regulation)
% Same format as the figures above (after v_c regulation), to compare them

s = before{sel(pointForPQFigure)};
t_Pico = s.t_scope1; % [s]

figure(60), hold on

subplot(3,1,1), box on, grid on, hold on

plot(t_Pico,s.v_s,'-','LineWidth',1);
plot(t_Pico,s.v_c,'-','LineWidth',1);

ylim([-20, 20])
ylabel('$v$ [V]','Interpreter','latex')
legend('$v_{s}$','$v_{c}$','Interpreter','latex'), legend boxon % R2018b and later
title(sprintf('P%d before $|$ $M_p$ = %.4f, $\\phi_m$ = %+.4f rad (PicoScope)', ...
    pointForPQFigure, s.Mp, s.phi_m),'Interpreter','latex')

subplot(3,1,2), box on, grid on, hold on

plot(t_Pico,s.v_dac,'-','LineWidth',1);

ylabel('$v_{DAC}$ [V]','Interpreter','latex')

subplot(3,1,3), box on, grid on, hold on

plot(t_Pico,s.i_c_pos,'-','LineWidth',1);
text(0.70,0.88,"$I_{rms}=$ "+string(round(s.Icpos_rms,2))+" A",'Units','normalized','BackgroundColor','w','Margin',1,'Interpreter','latex') % fixed place in the axes, readable over the curve

ylabel('$i_{c}$ [A]','Interpreter','latex')
xlabel('$time$ [s]','Interpreter','latex')

%% Voltage and current curves of each point: ScopeMimicry (board, after v_c regulation)

for k = 1:numSel

    s = after{sel(k)};
    t_SM = s.t_sm; % [s]

    figure(20 + k), hold on

    subplot(3,1,1), box on, grid on, hold on

    plot(t_SM,s.sm_Vgrid,'-','LineWidth',1);

    ylim([-20, 20])
    xlim([0, 0.1])
    ylabel('$v$ [V]','Interpreter','latex')
    legend('$v_{c}$ ($V_{grid}$)','Interpreter','latex'), legend boxon % R2018b and later
    title(sprintf('P%d $|$ $M_p$ = %.4f, $\\phi_m$ = %+.4f rad (ScopeMimicry)', ...
        k, s.Mp, s.phi_m),'Interpreter','latex')

    subplot(3,1,2), box on, grid on, hold on

    plot(t_SM,s.sm_sine,'-','LineWidth',1);

    ylim([-1.2, 1.2])
    xlim([0, 0.1])
    ylabel('sine [-]','Interpreter','latex')
    legend('sine $\leftrightarrow v_{DAC}$','Interpreter','latex'), legend boxon % R2018b and later

    subplot(3,1,3), box on, grid on, hold on

    plot(t_SM,s.sm_I1_low_value,'-','LineWidth',1);
    text(0.70,0.88,"$I_{rms}=$ "+string(round(rms(s.sm_I1_low_value),2))+" A",'Units','normalized','BackgroundColor','w','Margin',1,'Interpreter','latex') % fixed place in the axes, readable over the curve

    xlim([0, 0.1])
    ylabel('$i_{c}$ ($I_{1,low}$) [A]','Interpreter','latex')
    xlabel('$time$ [s]','Interpreter','latex')

end

%% Alignment of v_c with its reference, before and after the v_c regulation (one point)
% The captures start at unrelated instants, so each one is put on the time
% axis of the internal oscillator (DAC phasor minus the phi_AC applied during
% the capture). Reference: v_c at the end of the alignment (switch open, no load).

sB = before{sel(pointForVcFigure)};
sA = after{sel(pointForVcFigure)};

[tRef, VcRef] = fcn_oscillator_time(ref, f0);
[tB, VcB] = fcn_oscillator_time(sB, f0);
[tA, VcA] = fcn_oscillator_time(sA, f0);

figure(40), box on, grid on, hold on

plot(tRef*1e3,ref.v_c,'-','LineWidth',1);
plot(tB*1e3,sB.v_c,'--','LineWidth',1);

ylim([-20, 20])
ylabel('$v_{c}$ [V]','Interpreter','latex')
legend('$v_{c,ref}$','$v_{c}$ before regulation','Interpreter','latex','Location','northeast'), legend boxon % R2018b and later

figure(41), box on, grid on, hold on

plot(tRef*1e3,ref.v_c,'-','LineWidth',1);
plot(tA*1e3,sA.v_c,'--','LineWidth',1);

ylim([-20, 20])
ylabel('$v_{c}$ [V]','Interpreter','latex')
legend('$v_{c,ref}$','$v_{c}$ after regulation','Interpreter','latex','Location','northeast'), legend boxon % R2018b and later

figure(42), box on, grid on, hold on

plot(tRef*1e3,ref.v_dac,'-','LineWidth',1);
plot(tB*1e3,sB.v_dac,'--','LineWidth',1);
plot(tA*1e3,sA.v_dac,':','LineWidth',1.5);

ylabel('$v_{DAC}$ [V]','Interpreter','latex')
xlabel('$time$ on oscillator axis [ms]','Interpreter','latex')
legend(sprintf('alignment ($M_{AC}$ = %.3f)', ref.Mp_AC), sprintf('before regulation ($M_{AC}$ = %.3f)', sB.Mp_AC), ...
    sprintf('after regulation ($M_{AC}$ = %.3f)', sA.Mp_AC),'Interpreter','latex','Location','northeast'), legend boxon % R2018b and later

% Convergence of the v_c regulation of this point (one value per capture)
h = sA.vcRegHistory;

figure(43), box on, grid on, hold on

yyaxis left
plot(1:numel(h.Vc_rms), h.Vc_rms - abs(sA.VcClkRef), '-o', 'LineWidth', 1);
ylabel('$|V_{c}| - |V_{c,ref}|$ [V]','Interpreter','latex')
yyaxis right
plot(1:numel(h.ephi), rad2deg(h.ephi), '-s', 'LineWidth', 1);
ylabel('$\Delta\phi$ [$^o$]','Interpreter','latex')
xlabel('Iteration of the $v_{c}$ regulation','Interpreter','latex')
title(sprintf('Point %d $|$ $v_{c}$ regulation: %d iterations', pointForVcFigure, sA.vcRegIterations),'Interpreter','latex')

%% Checkpoints: initial point (not aligned), aligned point with the switch open and closed

checkpointTitles = {'IP', 'AP', 'SWC'};

for c = 1:numel(checkpointFiles)

    s = load(fullfile(dataFolder, checkpointFiles{c}));
    t_Pico = s.t_scope1; % [s]

    figure(50 + c), hold on

    subplot(3,1,1), box on, grid on, hold on

    plot(t_Pico,s.v_s,'-','LineWidth',1);
    plot(t_Pico,s.v_c,'-','LineWidth',1);

    ylim([-20, 20])
    ylabel('$v$ [V]','Interpreter','latex')
    legend('$v_{s}$','$v_{c}$','Interpreter','latex'), legend boxon % R2018b and later
    title(sprintf('%s $|$ $M_p$ = %.4f, $M_{AC}$ = %.4f, $\\phi_{AC}$ = %+.4f rad', ...
        checkpointTitles{min(c, end)}, s.Mp, s.Mp_AC, s.phi_AC),'Interpreter','latex')

    subplot(3,1,2), box on, grid on, hold on

    plot(t_Pico,s.v_dac,'-','LineWidth',1);

    ylabel('$v_{DAC}$ [V]','Interpreter','latex')

    subplot(3,1,3), box on, grid on, hold on

    plot(t_Pico,s.i_c_pos,'-','LineWidth',1);
    text(0.70,0.88,"$I_{rms}=$ "+string(round(s.Icpos_rms,3))+" A",'Units','normalized','BackgroundColor','w','Margin',1,'Interpreter','latex') % fixed place in the axes, readable over the curve

    ylabel('$i_{a}$ [A]','Interpreter','latex')
    xlabel('$time$ [s]','Interpreter','latex')

end

%% Save figures

if saveFigures
    addpath('C:\Users\ana\Documents\PhD\Presentations et livrables\Templates_Loic\figure_PP_QUEVAL_20231221\core') % Add figure_PP folder to the path
    if ~exist(figuresFolder, 'dir')
        mkdir(figuresFolder);
    end

    figure_PP(1,fullfile(figuresFolder,'PQ_diagram_PicoScope_ScopeMimicry.png'),'width',8.75,'height',6) % Export to .png
    figure_PP(2,fullfile(figuresFolder,sprintf('PQ_diagram_aligned_point.png',pointForPQFigure)),'width',8.75,'height',6) % Export to .png
    figure_PP(3,fullfile(figuresFolder,sprintf('PQ_diagram_aligned_point_and_point%d_before_vcreg.png',pointForPQFigure)),'width',8.75,'height',6) % Export to .png
    figure_PP(4,fullfile(figuresFolder,sprintf('PQ_diagram_aligned_point_and_point%d_before_after_vcreg.png',pointForPQFigure)),'width',8.75,'height',6) % Export to .png
    figure_PP(60,fullfile(figuresFolder,sprintf('point%d_curves_PicoScope_before_vcreg.png',pointForPQFigure)),'width',8.75,'height',6) % Export to .png

    for k = 1:numSel
        figure_PP(10 + k,fullfile(figuresFolder,sprintf('point%d_curves_PicoScope.png',k)),'width',8.75,'height',6) % Export to .png
        figure_PP(20 + k,fullfile(figuresFolder,sprintf('point%d_curves_ScopeMimicry.png',k)),'width',8.75,'height',6) % Export to .png
    end

    figure_PP(40,fullfile(figuresFolder,sprintf('point%d_vc_alignment_before.png',pointForVcFigure)),'width',8.75,'height',6) % Export to .png
    figure_PP(41,fullfile(figuresFolder,sprintf('point%d_vc_alignment_after.png',pointForVcFigure)),'width',8.75,'height',6) % Export to .png
    figure_PP(42,fullfile(figuresFolder,sprintf('point%d_vc_alignment_dac.png',pointForVcFigure)),'width',8.75,'height',6) % Export to .png
    figure_PP(43,fullfile(figuresFolder,sprintf('point%d_vc_regulation_convergence.png',pointForVcFigure)),'width',8.75,'height',6) % Export to .png

    checkpointFigureNames = {'checkpoint1_initial_not_aligned', 'checkpoint2_aligned_switch_open', 'checkpoint3_aligned_switch_closed'};
    for c = 1:numel(checkpointFiles)
        figure_PP(50 + c,fullfile(figuresFolder,[checkpointFigureNames{min(c, end)} '.png']),'width',8.75,'height',6) % Export to .png
    end
end

%% Local functions

function [tOsc, VcClk] = fcn_oscillator_time(s, f0)
% Time axis of a capture shifted onto the internal oscillator phase, and the
% v_c phasor in the oscillator frame (same as the v_c regulation)
dt = s.t_scope1(2) - s.t_scope1(1);
Pdac = fcn_FundamentalPhasor(s.v_dac, dt, f0);
Pvc = fcn_FundamentalPhasor(s.v_c, dt, f0);
tOsc = s.t_scope1 + mod(angle(Pdac) - s.phi_AC, 2*pi) / (2*pi*f0);
VcClk = Pvc * conj(Pdac) / abs(Pdac) * exp(1j * s.phi_AC);
end
