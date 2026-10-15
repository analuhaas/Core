function [tempMonitorTime_s, tempMonitorTemp1, tempMonitorTemp2, figureTemp] = fcn_monitor_temperature(ts, measurements, tempMonitorDuration_s, tempMonitorPeriod_s)
%FCN_MONITOR_TEMPERATURE monitors the MOSFET temperature to check thermal steady state
%   Reads the MOSFET temperature at two placements (board Temp1 and Temp2)
%   every tempMonitorPeriod_s for tempMonitorDuration_s, then plots them so
%   the user can judge if they are stable.
%   Readings are scheduled from the start time, so the time taken by each
%   read does not accumulate.

numTempReadings = floor(tempMonitorDuration_s / tempMonitorPeriod_s) + 1; % includes the reading at t = 0
tempMonitorTime_s = (0:numTempReadings - 1) * tempMonitorPeriod_s;
tempMonitorTemp1 = NaN(1, numTempReadings);
tempMonitorTemp2 = NaN(1, numTempReadings);

tempMonitorStart = tic;
for n = 1:numTempReadings

    pause(max(0, tempMonitorTime_s(n) - toc(tempMonitorStart)));

    tempMonitorTemp1(n) = ts.read(measurements("Temp1"));
    tempMonitorTemp2(n) = ts.read(measurements("Temp2"));

    fprintf('Temperature %2d/%d | t = %5.1f min | T_MOSFET Temp1 = %.2f degC | Temp2 = %.2f degC\n', ...
        n, numTempReadings, tempMonitorTime_s(n) / 60, tempMonitorTemp1(n), tempMonitorTemp2(n));

end

figureTemp = figure('Name', 'MOSFET temperature monitoring', 'NumberTitle', 'off');
plot(tempMonitorTime_s / 60, tempMonitorTemp1, '-o', tempMonitorTime_s / 60, tempMonitorTemp2, '-s');
grid on;
xlabel('Time (min)');
ylabel('T_{MOSFET} (°C)');
legend('Temp1', 'Temp2', 'Location', 'best');
if numTempReadings > 1
    title(sprintf('MOSFET temperature | last %.0f s: \\DeltaT_1 = %+.2f °C, \\DeltaT_2 = %+.2f °C', ...
        tempMonitorPeriod_s, tempMonitorTemp1(end) - tempMonitorTemp1(end - 1), ...
        tempMonitorTemp2(end) - tempMonitorTemp2(end - 1)));
else
    title('MOSFET temperature');
end
drawnow;

end
