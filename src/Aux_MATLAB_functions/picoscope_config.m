function [numChannels,channelLetters,enabledChannels,status,timeIntervalNanoSeconds] = picoscope_config(ps4000aDeviceObj,channelCoupling, channelRange, channelAnalogueOffset, useTrigger, triggerChannel, triggerThreshold, triggerDirection, triggerAutoMs, secondsPerDivision, numDivisions, samplesPerDivision)
%PICOSCOPE_CONFIG Summary of this function goes here
%   Detailed explanation goes here
%   channelCoupling, channelRange and channelAnalogueOffset each accept
%   either a scalar (applied to every channel, as before) or a vector
%   with one entry per channel (for units where different channels need
%   different settings, e.g. a current-clamp channel needing a smaller
%   voltage range than a plain voltage channel on the same scope).

%% ------------------------------------------------------------------
%  Enable all available channels
%  ------------------------------------------------------------------
% ps4000aDeviceObj.channelCount reports how many analog channels this
% particular unit has (2, 4 or 8). Enable channel A..(A+channelCount-1)
% so every channel the scope has is captured, not just Channel A.

numChannels = double(ps4000aDeviceObj.channelCount);
channelLetters = 'ABCDEFGH';
enabledChannels = 0:(numChannels - 1);

status.setChannel = cell(1, numChannels);

for ch = enabledChannels

    coupling = perChannelValue(channelCoupling, ch + 1, numChannels);
    range    = perChannelValue(channelRange, ch + 1, numChannels);
    offset   = perChannelValue(channelAnalogueOffset, ch + 1, numChannels);

    status.setChannel{ch + 1} = invoke(ps4000aDeviceObj, 'ps4000aSetChannel', ...
        ch, 1, coupling, range, offset);

end

fprintf('Enabled channels: %s\n', channelLetters(enabledChannels + 1));

% Set device resolution (PicoScope 4444 only)

if (ps4000aDeviceObj.isFlexResDevice == PicoConstants.TRUE)
    [status.setResolution] = invoke(ps4000aDeviceObj, 'ps4000aSetDeviceResolution', 14);
end

% ------------------------------------------------------------------
%  Timebase: translate "seconds/div" into a timebase index + sample count
% ------------------------------------------------------------------
% ps4000aGetTimebase2() tells you, for a given timebase index, what
% sample interval (ns) and max sample count you would actually get - the
% relationship between timebase index and interval is device- and
% resolution-dependent, so we query the driver rather than compute it
% ourselves. We search upward from timebase 0 (fastest) for the first
% index whose interval is at least as coarse as what we need to cover
% the desired window with the desired number of samples; this also
% naturally skips timebases the driver reports as invalid for the
% current channel/resolution configuration.
%
% With more than one channel enabled, the fastest timebase indices are
% genuinely invalid (the ADC has to time-share across channels), so
% starting the search at index 0 is expected to hit a few invalid
% indices before it converges. The driver reports each of those both as
% a status code (which the loop below already handles) and as a MATLAB
% warning printed to the console - the warning is just noise, not an
% error, so it is suppressed for the duration of this search only and
% restored immediately afterwards.

totalCaptureTimeSeconds = secondsPerDivision * numDivisions;
desiredNumSamples       = samplesPerDivision * numDivisions;
desiredSampleIntervalNs = (totalCaptureTimeSeconds / desiredNumSamples) * 1e9;

timebaseIndex = 0;
maxTimebaseSearch = 200000; % safety limit so a bad config can't loop forever

warningState = warning('off', 'all');
cleanupWarning = onCleanup(@() warning(warningState));

while (true)

    [statusGetTimebase2, timeIntervalNanoSeconds, maxSamples] = ...
        invoke(ps4000aDeviceObj, 'ps4000aGetTimebase2', timebaseIndex, 0);

    if (statusGetTimebase2 == PicoStatus.PICO_OK && ...
            double(timeIntervalNanoSeconds) >= desiredSampleIntervalNs)
        break;
    end

    timebaseIndex = timebaseIndex + 1;

    if (timebaseIndex > maxTimebaseSearch)
        error('Could not find a timebase matching the requested %.3f s/div with %d channels enabled.', ...
            secondsPerDivision, numChannels);
    end

end

clear cleanupWarning; % restore warnings as soon as the search is done

status.getTimebase2 = statusGetTimebase2;

fprintf('Timebase index: %d -> %.1f ns/sample (target was %.1f ns/sample for %.3f s/div)\n', ...
    timebaseIndex, double(timeIntervalNanoSeconds), desiredSampleIntervalNs, secondsPerDivision);

set(ps4000aDeviceObj, 'timebase', timebaseIndex);

numPostTriggerSamples = round(totalCaptureTimeSeconds * 1e9 / double(timeIntervalNanoSeconds));

if (numPostTriggerSamples > maxSamples)
    numPostTriggerSamples = maxSamples;
    warning('Requested capture window needs more samples than device memory allows; truncating to %d samples.', maxSamples);
end

set(ps4000aDeviceObj, 'numPreTriggerSamples', 0);
set(ps4000aDeviceObj, 'numPostTriggerSamples', numPostTriggerSamples);

% ------------------------------------------------------------------
%  Trigger configuration (optional)
%  ------------------------------------------------------------------
% If useTrigger is false, setSimpleTrigger is never called. The driver's
% default state on connect() has no trigger armed, so
% ps4000aRunBlock()/runBlock() starts capturing numPostTriggerSamples
% immediately when invoked - i.e. it grabs "whatever is on the input
% right now" rather than waiting for a signal condition. That is the
% answer to "can I acquire without configuring a trigger": yes, simply
% skip this section.

if (useTrigger)

    triggerGroupObj = get(ps4000aDeviceObj, 'Trigger');
    triggerGroupObj = triggerGroupObj(1);

    set(triggerGroupObj, 'autoTriggerMs', triggerAutoMs);

    [status.setSimpleTrigger] = invoke(triggerGroupObj, 'setSimpleTrigger', ...
        triggerChannel, triggerThreshold, triggerDirection);

else

    fprintf('Trigger disabled - block capture will start immediately (free-run).\n');

end
end

function value = perChannelValue(setting, channelIndex, numChannels)
%PERCHANNELVALUE Resolve a scalar-or-per-channel setting to one channel's value.
if (isscalar(setting))
    value = setting;
elseif (numel(setting) == numChannels)
    value = setting(channelIndex);
else
    error('picoscope_config:sizeMismatch', ...
        'Channel setting must be a scalar or a vector with one entry per channel (%d expected, got %d).', ...
        numChannels, numel(setting));
end
end

