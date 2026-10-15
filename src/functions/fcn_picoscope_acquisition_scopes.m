function [channelData, numSamples] = fcn_picoscope_acquisition_scopes(ps4000aDeviceObj, numChannels, probeVoltsPerUnit)
%FCN_PICOSCOPE_ACQUISITION_SCOPES captures one block on every PicoScope
%   and converts each channel's raw ADC volts into its physical unit (A or V).
%   The scopes 1 and 2 are captured one after the other,
%   so their data are NOT sample-aligned to each other.

numScopes = numel(ps4000aDeviceObj);
channelData = cell(1, numScopes);
numSamples = cell(1, numScopes);

for s = 1:numScopes

    [numSamples{s}, ~, channelData{s}, ~] = picoscope_acquisition(ps4000aDeviceObj{s}, numChannels{s});

    for ch = 1:numChannels{s}
        channelData{s}{ch} = channelData{s}{ch} / probeVoltsPerUnit{s}(ch);
    end

end

end
