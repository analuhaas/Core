function [numSamples,overflow,channelData,status] = picoscope_acquisition(ps4000aDeviceObj,numChannels)
%PICOSCOPE_ACQUISITION Summary of this function goes here
%   Detailed explanation goes here
blockGroupObj = get(ps4000aDeviceObj, 'Block');
blockGroupObj = blockGroupObj(1);

[status.runBlock] = invoke(blockGroupObj, 'runBlock', 0);

% getBlockData returns [numSamples, overflow, dataForEachEnabledChannel...]
% in channel order (A, B, C, ...). Build the output list dynamically so
% this works whether 2, 4 or 8 channels are enabled.
blockOutputs = cell(1, numChannels + 2);
[blockOutputs{:}] = invoke(blockGroupObj, 'getBlockData', 0, 0, 1, 0);

numSamples    = blockOutputs{1};
overflow      = blockOutputs{2};
channelData   = blockOutputs(3:end); % 1 x numChannels cell array

% The driver's getBlockData returns data in millivolts (it calls the
% underlying adc2mv() conversion internally), not volts - convert here so
% every caller downstream can treat channelData as volts consistently.
for ch = 1:numChannels
    channelData{ch} = channelData{ch} / 1000;
end

[status.stop] = invoke(ps4000aDeviceObj, 'ps4000aStop');

end

