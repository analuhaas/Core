function figureHandle = fcn_plot_picoscope(channelData, numSamples, timeIntervalNanoSeconds, channelLetters, probeUnit, picoSerialNumbers, secondsPerDivision)
%FCN_PLOT_PICOSCOPE plots each scope's channels in its own subplot

numScopes = numel(channelData);

figureHandle = figure('Name', 'PicoScope 4000 Series (A API) - Multi-scope Block Capture', ...
    'NumberTitle', 'off');

for s = 1:numScopes

    subplot(numScopes, 1, s);
    hold on;

    timeNs = double(timeIntervalNanoSeconds{s}) * double(0:numSamples{s} - 1);
    timeMs = timeNs / 1e6;

    numChannels = numel(channelData{s});
    legendEntries = cell(1, numChannels);

    for i = 1:numChannels

        plot(timeMs, channelData{s}{i});
        legendEntries{i} = sprintf('Channel %s (%s)', channelLetters{s}(i), probeUnit{s}{i});

    end

    hold off;

    title(sprintf('PicoScope %d (%s) - %.3f s/div', s, picoSerialNumbers{s}, secondsPerDivision));
    xlabel('Time (ms)');

    uniqueUnits = unique(probeUnit{s});
    if (isscalar(uniqueUnits))
        ylabel(sprintf('Amplitude (%s)', uniqueUnits{1}));
    else
        ylabel('Amplitude (see legend for units)');
    end

    grid on;
    legend(legendEntries);

end

end
