function [tempMonitorTime_s, tempMonitorTemp1, tempMonitorTemp2, figureTemp, tempMonitorBurst1, tempMonitorBurst2, fileName] = fcn_monitor_temperature(ts, measurements, tempMonitorDuration_s, tempMonitorPeriod_s, tempBurstCount, tempBurstSpacing_s, tempAmbient)
%FCN_MONITOR_TEMPERATURE monitors the MOSFET temperature to check thermal steady state
%   Every tempMonitorPeriod_s for tempMonitorDuration_s, reads the MOSFET
%   temperature at two placements (board Temp1 and Temp2) tempBurstCount
%   times, spaced by tempBurstSpacing_s, and uses their mean as the reading
%   (fcn_read_temperature_burst). Each printed line also gives the
%   temperature rate over the last rateWindow_s (5 min), in °C/min.
%   When less than askBefore_s (10 min) of monitoring is left, the user is
%   asked whether more time is needed to reach thermal equilibrium; if yes,
%   extension_s (10 min) is added, and the question comes again near the
%   new end. Then plots the means so the user can judge if they are stable,
%   and saves the means and all the individual readings in
%   TempMonitor_<date>_<time>.mat.
%   Readings are scheduled every tempMonitorPeriod_s from the start time, so
%   the time taken by each read does not accumulate. If a reading is late
%   (e.g. while waiting for the user's answer), the schedule restarts from
%   it instead of taking the missed readings in a row. tempMonitorTime_s
%   holds the actual time of each reading.
%
%   tempAmbient (optional): ambient reading taken earlier with
%   fcn_read_temperature_burst, struct with fields Temp1, Temp2, Burst1,
%   Burst2 and time (datetime). Plotted at its time relative to the start of
%   the monitoring (negative, in minutes) and saved in the same file.
%
%   tempMonitorBurst1/2: number of readings x tempBurstCount, all individual readings

askBefore_s = 600;   % [s] ask for more time when less than this is left
extension_s = 600;   % [s] time added each time the user asks for more
rateWindow_s = 300;  % [s] window of the printed temperature rate

tempMonitorTime_s = zeros(1, 0);
tempMonitorTemp1 = zeros(1, 0);
tempMonitorTemp2 = zeros(1, 0);
tempMonitorBurst1 = zeros(0, tempBurstCount);
tempMonitorBurst2 = zeros(0, tempBurstCount);

tempMonitorEnd_s = tempMonitorDuration_s; % [s] end of the monitoring, extended if the user asks
askedForEnd_s = NaN;                       % end for which the user was already asked
rate1 = NaN;
rate2 = NaN;

tempMonitorStartTime = datetime('now');
tempMonitorStart = tic;
tNext = 0;
n = 0;
while tNext <= tempMonitorEnd_s

    pause(max(0, tNext - toc(tempMonitorStart)));

    n = n + 1;
    tempMonitorTime_s(n) = toc(tempMonitorStart);
    [tempMonitorTemp1(n), tempMonitorTemp2(n), tempMonitorBurst1(n, :), tempMonitorBurst2(n, :)] = ...
        fcn_read_temperature_burst(ts, measurements, tempBurstCount, tempBurstSpacing_s);

    % Temperature rate over the last rateWindow_s (shorter window at the start)
    j = find(tempMonitorTime_s <= tempMonitorTime_s(n) - rateWindow_s, 1, 'last');
    if isempty(j)
        j = 1;
    end
    rateWindowMin = (tempMonitorTime_s(n) - tempMonitorTime_s(j)) / 60;
    if rateWindowMin > 0
        rate1 = (tempMonitorTemp1(n) - tempMonitorTemp1(j)) / rateWindowMin;
        rate2 = (tempMonitorTemp2(n) - tempMonitorTemp2(j)) / rateWindowMin;
    end

    fprintf(['Temperature %3d | t = %5.1f / %5.1f min | T_MOSFET Temp1 = %.2f degC | Temp2 = %.2f degC (mean of %d)' ...
        ' | rate over last %.1f min: Temp1 %+.3f, Temp2 %+.3f degC/min\n'], ...
        n, tempMonitorTime_s(n) / 60, tempMonitorEnd_s / 60, tempMonitorTemp1(n), tempMonitorTemp2(n), ...
        tempBurstCount, rateWindowMin, rate1, rate2);

    % Less than askBefore_s left: ask once per end time whether more time is needed
    if tempMonitorEnd_s - tempMonitorTime_s(n) < askBefore_s && askedForEnd_s ~= tempMonitorEnd_s
        askedForEnd_s = tempMonitorEnd_s;
        answer = input(sprintf(['Temperature monitoring: %.1f min left. Rate over the last %.1f min: ' ...
            'Temp1 %+.3f, Temp2 %+.3f degC/min.\nIs more time needed to reach thermal equilibrium? ' ...
            'Add %.0f min? [y/n]: '], (tempMonitorEnd_s - tempMonitorTime_s(n)) / 60, rateWindowMin, ...
            rate1, rate2, extension_s / 60), 's');
        if any(strcmpi(strtrim(answer), {'y', 'yes'}))
            tempMonitorEnd_s = tempMonitorEnd_s + extension_s;
            fprintf('Temperature monitoring extended to %.1f min\n', tempMonitorEnd_s / 60);
        end
    end

    % Next reading; if late (e.g. waiting for the answer), restart the schedule from now
    tNext = tNext + tempMonitorPeriod_s;
    if tNext < toc(tempMonitorStart)
        tNext = toc(tempMonitorStart);
    end

end

% Save the means and all the individual readings (and the ambient reading if given)
fileName = sprintf('TempMonitor_%s.mat', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
save(fileName, 'tempMonitorTime_s', 'tempMonitorTemp1', 'tempMonitorTemp2', ...
    'tempMonitorBurst1', 'tempMonitorBurst2', 'tempMonitorPeriod_s', 'tempMonitorDuration_s', ...
    'tempMonitorEnd_s', 'tempBurstCount', 'tempBurstSpacing_s', 'tempMonitorStartTime');
hasAmbient = nargin >= 7;
if hasAmbient
    tempAmbientTime_s = seconds(tempAmbient.time - tempMonitorStartTime); % [s] negative: before the monitoring
    save(fileName, 'tempAmbient', 'tempAmbientTime_s', '-append');
end
fprintf('Temperature monitoring saved to %s\n', fileName);

figureTemp = figure('Name', 'MOSFET temperature monitoring', 'NumberTitle', 'off');
hold on;
plot(tempMonitorTime_s / 60, tempMonitorTemp1, '-o', tempMonitorTime_s / 60, tempMonitorTemp2, '-s');
legendEntries = {sprintf('Temp1 (mean of %d)', tempBurstCount), sprintf('Temp2 (mean of %d)', tempBurstCount)};
if hasAmbient
    ax = gca;
    ax.ColorOrderIndex = 1; % same colors as Temp1 / Temp2
    plot(tempAmbientTime_s / 60, tempAmbient.Temp1, 'p', tempAmbientTime_s / 60, tempAmbient.Temp2, 'p', ...
        'MarkerSize', 12);
    legendEntries = [legendEntries, {'Temp1 ambient (u_{dc} on)', 'Temp2 ambient (u_{dc} on)'}];
end
hold off;
grid on;
xlabel('Time from monitoring start (min)');
ylabel('T_{MOSFET} (°C)');
legend(legendEntries, 'Location', 'best');
title(sprintf('MOSFET temperature | rate over last %.1f min: Temp1 %+.3f, Temp2 %+.3f °C/min', ...
    rateWindowMin, rate1, rate2));
drawnow;

end
