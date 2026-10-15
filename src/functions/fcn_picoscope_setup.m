function [ps4000aDeviceObj, numChannels, channelLetters, timeIntervalNanoSeconds, probeVoltsPerUnit, probeUnit, dtScope] = fcn_picoscope_setup(picoCfg, ps4000aEnuminfo)
%FCN_PICOSCOPE_SETUP sizes the channel ranges, then connects and configures
%every PicoScope in picoCfg.picoSerialNumbers.
%   picoCfg: struct with the USER SETTINGS FOR PICOSCOPE CONFIGURATION
%   (picoSerialNumbers, channelCoupling, channelRange, channelAnalogueOffset,
%   useTrigger, triggerChannel, triggerThreshold, triggerDirection,
%   triggerAutoMs, secondsPerDivision, numDivisions, samplesPerDivision,
%   currentProbeChannelList, currentProbeVoltsPerAmp, maxExpectedCurrentA,
%   voltageChannelList, maxExpectedVoltageV, dacSerial, dacChannel,
%   maxExpectedDacV).
%   ps4000aEnuminfo: from ps4000aSetConfig().
%
% Each PicoScope is its own independent icdevice object with its own
% clock, so connection/config/acquisition is repeated per unit. Since
% each unit runs its own runBlock() call one after the other, the two
% captures are NOT sample-aligned to each other in time. If that
% requirement ever changes, both units would need to share a hardware
% trigger (external trigger signal wired into both units' EXT input) with
% both armed before the shared trigger fires.

%% Channel ranges

[currentProbeRangeIndex, currentProbeRangeVolts] = pico_select_voltage_range( ...
    ps4000aEnuminfo, picoCfg.maxExpectedCurrentA * picoCfg.currentProbeVoltsPerAmp);

fprintf('Current probe channels sized for %.1f A peak -> %.2f V -> range %.2f V (index %d)\n', ...
    picoCfg.maxExpectedCurrentA, picoCfg.maxExpectedCurrentA * picoCfg.currentProbeVoltsPerAmp, ...
    currentProbeRangeVolts, currentProbeRangeIndex);

[voltageChannelRangeIndex, voltageChannelRangeVolts] = pico_select_voltage_range( ...
    ps4000aEnuminfo, picoCfg.maxExpectedVoltageV);

fprintf('Voltage channels sized for %.1f V peak -> range %.2f V (index %d)\n', ...
    picoCfg.maxExpectedVoltageV, voltageChannelRangeVolts, voltageChannelRangeIndex);

[dacRangeIndex, dacRangeVolts] = pico_select_voltage_range( ...
    ps4000aEnuminfo, picoCfg.maxExpectedDacV);

fprintf('DAC channel sized for %.1f V peak -> range %.2f V (index %d)\n', ...
    picoCfg.maxExpectedDacV, dacRangeVolts, dacRangeIndex);

%% Connection and configuration of each PicoScope

numScopes = numel(picoCfg.picoSerialNumbers);

ps4000aDeviceObj  = cell(1, numScopes);
numChannels       = cell(1, numScopes);
channelLetters    = cell(1, numScopes);
timeIntervalNanoSeconds = cell(1, numScopes);
probeVoltsPerUnit = cell(1, numScopes); % 1 for plain voltage channels, currentProbeVoltsPerAmp for clamp channels
probeUnit         = cell(1, numScopes); % 'V' or 'A' per channel, for labeling

for s = 1:numScopes

    serial = picoCfg.picoSerialNumbers{s};

    ps4000aDeviceObj{s} = picoscope_connection(serial);

    numChannelsThisScope = double(ps4000aDeviceObj{s}.channelCount);

    channelRangeThisScope = repmat(picoCfg.channelRange, 1, numChannelsThisScope);
    probeVoltsPerUnit{s}  = ones(1, numChannelsThisScope);
    probeUnit{s}          = repmat({'V'}, 1, numChannelsThisScope);

    for row = 1:size(picoCfg.currentProbeChannelList, 1)

        if (strcmp(serial, picoCfg.currentProbeChannelList{row, 1}))

            ch = picoCfg.currentProbeChannelList{row, 2};
            channelRangeThisScope(ch) = currentProbeRangeIndex;
            probeVoltsPerUnit{s}(ch)  = picoCfg.currentProbeVoltsPerAmp;
            probeUnit{s}{ch}          = 'A';

        end

    end

    for row = 1:size(picoCfg.voltageChannelList, 1)

        if (strcmp(serial, picoCfg.voltageChannelList{row, 1}))

            channelRangeThisScope(picoCfg.voltageChannelList{row, 2}) = voltageChannelRangeIndex;
            % probeVoltsPerUnit / probeUnit stay at their defaults (1, 'V') -
            % no scaling needed for a direct, unattenuated connection.

        end

    end

    if (strcmp(serial, picoCfg.dacSerial))

        channelRangeThisScope(picoCfg.dacChannel) = dacRangeIndex;
        % direct voltage input - probeVoltsPerUnit / probeUnit stay at (1, 'V')

    end

    [numChannels{s}, channelLetters{s}, ~, ~, timeIntervalNanoSeconds{s}] = picoscope_config( ...
        ps4000aDeviceObj{s}, picoCfg.channelCoupling, channelRangeThisScope, picoCfg.channelAnalogueOffset, ...
        picoCfg.useTrigger, picoCfg.triggerChannel, picoCfg.triggerThreshold, picoCfg.triggerDirection, picoCfg.triggerAutoMs, ...
        picoCfg.secondsPerDivision, picoCfg.numDivisions, picoCfg.samplesPerDivision);

end

dtScope = double(timeIntervalNanoSeconds{1}) * 1e-9;  % actual scope sample time (PicoScope 1)

end
