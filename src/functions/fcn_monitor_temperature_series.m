function [tempSeriesTime_s, tempSeriesTemp1, tempSeriesTemp2, figureTempSeries, fileName, figureTempHist] = fcn_monitor_temperature_series(ts, measurements, tempSeriesPoints, tempSeriesSpacing_s)
%FCN_MONITOR_TEMPERATURE_SERIES records a series of single MOSFET temperature readings
%   Reads the MOSFET temperature at two placements (board Temp1 and Temp2)
%   tempSeriesPoints times, spaced by tempSeriesSpacing_s, then plots them
%   over time and as histograms (mean and standard deviation in the titles),
%   and saves them in TempSeries_<date>_<time>.mat.
%   Readings are scheduled from the start time, so the time taken by each
%   read does not accumulate.

tempSeriesTime_s = (0:tempSeriesPoints - 1) * tempSeriesSpacing_s;
tempSeriesTemp1 = NaN(1, tempSeriesPoints);
tempSeriesTemp2 = NaN(1, tempSeriesPoints);

fprintf('Temperature series: %d points every %.2f s (%.1f min)\n', ...
    tempSeriesPoints, tempSeriesSpacing_s, tempSeriesTime_s(end) / 60);

tempSeriesStart = tic;
for n = 1:tempSeriesPoints

    pause(max(0, tempSeriesTime_s(n) - toc(tempSeriesStart)));

    tempSeriesTemp1(n) = ts.read(measurements("Temp1"));
    tempSeriesTemp2(n) = ts.read(measurements("Temp2"));

    if mod(n, 60) == 1 || n == tempSeriesPoints % progress line every 60 points
        fprintf('Temperature series %4d/%d | t = %5.1f min | Temp1 = %.2f degC | Temp2 = %.2f degC\n', ...
            n, tempSeriesPoints, tempSeriesTime_s(n) / 60, tempSeriesTemp1(n), tempSeriesTemp2(n));
    end

end

% Save all the readings
fileName = sprintf('TempSeries_%s.mat', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
save(fileName, 'tempSeriesTime_s', 'tempSeriesTemp1', 'tempSeriesTemp2', 'tempSeriesPoints', 'tempSeriesSpacing_s');
fprintf('Temperature series saved to %s\n', fileName);

figureTempSeries = figure('Name', 'MOSFET temperature series', 'NumberTitle', 'off');
plot(tempSeriesTime_s / 60, tempSeriesTemp1, tempSeriesTime_s / 60, tempSeriesTemp2);
grid on;
xlabel('Time (min)');
ylabel('T_{MOSFET} (°C)');
legend('Temp1', 'Temp2', 'Location', 'best');
title(sprintf('MOSFET temperature | %d points every %.2f s', tempSeriesPoints, tempSeriesSpacing_s));

% Histograms of the readings, with mean and standard deviation
numBins = 20;
figureTempHist = figure('Name', 'MOSFET temperature series - histograms', 'NumberTitle', 'off');

subplot(2, 1, 1), grid on, box on, hold on
histogram(tempSeriesTemp1, numBins);
xlabel('T1 (°C)');
ylabel('Number of readings');
title(sprintf('Temp1 | mean = %.2f °C, standard deviation = %.3f °C', ...
    mean(tempSeriesTemp1, 'omitnan'), std(tempSeriesTemp1, 'omitnan')));

subplot(2, 1, 2), grid on, box on, hold on
histogram(tempSeriesTemp2, numBins);
xlabel('T2 (°C)');
ylabel('Number of readings');
title(sprintf('Temp2 | mean = %.2f °C, standard deviation = %.3f °C', ...
    mean(tempSeriesTemp2, 'omitnan'), std(tempSeriesTemp2, 'omitnan')));

drawnow;

end
