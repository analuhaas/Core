function cal = calibration_fit_plot(calFile)
%CALIBRATION_FIT_PLOT Fit and plot the calibration points saved in a .mat file.
%   cal = calibration_fit_plot(calFile) loads the points saved by the
%   calibration_supervisor_LOW* scripts, fits "PicoScope = gain * raw + offset"
%   for each sensor with 2+ points, plots them, prints the firmware
%   setConversionParametersLinear() lines and saves gain/offset in the file.
%
%   cal = calibration_fit_plot() opens a file dialog in Data_records.
%
%   Example:
%       calibration_fit_plot("Data_records/calibration_board_01_LOW1.mat");

if nargin < 1 || strlength(string(calFile)) == 0
    startDir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'Data_records');
    [name, folder] = uigetfile(fullfile(startDir, 'calibration_*.mat'), 'Select a calibration file');
    if isequal(name, 0)
        cal = [];
        return
    end
    calFile = fullfile(folder, name);
end

load(calFile, 'cal');

sensorNames = cal.sensorNames;
units       = cal.units;
nSensors    = numel(sensorNames);

gain   = nan(1, nSensors);
offset = nan(1, nSensors);

% One figure per calibration file, so LOW1 and LOW2 can be open side by side.
figTag = "sensorCalibration_" + cal.boardName;
fig = findobj('Type', 'figure', 'Tag', figTag);
if isempty(fig)
    fig = figure('Tag', figTag, 'NumberTitle', 'off');
end
fig.Name = "Sensor calibration - " + cal.boardName;
figure(fig); clf(fig);
tl = tiledlayout(fig, 'flow', 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, sprintf('%s - %d point(s)', cal.boardName, size(cal.boardRaw, 1)), 'Interpreter', 'none');

pointColor  = [0.16 0.44 0.74];
latestColor = [0.85 0.37 0.01];
fitColor    = [0.45 0.45 0.45];

for s = 1:nSensors
    ax = nexttile(tl);
    hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');

    x = cal.boardRaw(:, s);
    y = cal.pico(:, s);
    valid = ~isnan(x) & ~isnan(y);

    if nnz(valid) >= 2 && numel(unique(x(valid))) >= 2
        coeffs = polyfit(x(valid), y(valid), 1);
        gain(s) = coeffs(1);
        offset(s) = coeffs(2);
        residual = y(valid) - polyval(coeffs, x(valid));
        xFit = linspace(min(x(valid)), max(x(valid)), 2);
        plot(ax, xFit, polyval(coeffs, xFit), '-', 'Color', fitColor, 'LineWidth', 1.5, ...
            'DisplayName', 'Linear fit');
        subtitle(ax, sprintf('gain = %.6g, offset = %.6g, max err = %.3g %s', ...
            gain(s), offset(s), max(abs(residual)), units{s}));
    end

    if any(valid)
        errorbar(ax, x(valid), y(valid), cal.boardStd(valid, s), 'horizontal', 'o', 'Color', pointColor, ...
            'MarkerFaceColor', pointColor, 'MarkerSize', 6, 'LineWidth', 1, 'DisplayName', 'Points');
    end
    if valid(end)
        plot(ax, x(end), y(end), 'o', 'MarkerSize', 9, 'LineWidth', 2, ...
            'Color', latestColor, 'DisplayName', 'Latest point');
    end

    title(ax, sensorNames{s}, 'Interpreter', 'none');
    xlabel(ax, 'Board raw value');
    ylabel(ax, sprintf('PicoScope (%s)', units{s}));
    if ~any(valid)
        text(ax, 0.5, 0.5, 'Not wired to the PicoScope', 'Units', 'normalized', ...
            'HorizontalAlignment', 'center', 'Color', fitColor);
    elseif s == 1
        legend(ax, 'Location', 'northwest');
    end
    hold(ax, 'off');
end

cal.gain = gain;
cal.offset = offset;
save(calFile, 'cal');

fprintf('\n%s (%d point(s))\n', cal.boardName, size(cal.boardRaw, 1));
if any(~isnan(gain))
    fprintf('Firmware conversion parameters (value = gain * raw + offset):\n');
    for s = find(~isnan(gain))
        fprintf('    shield.sensors.setConversionParametersLinear(%s, %.6gF, %.6gF);\n', ...
            sensorNames{s}, gain(s), offset(s));
    end
else
    fprintf('Not enough points to fit yet (2 different points needed per sensor).\n');
end

end
