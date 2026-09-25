function [rangeIndex, rangeVolts] = pico_select_voltage_range(ps4000aEnuminfo, requiredPeakVoltage, marginFactor)
%PICO_SELECT_VOLTAGE_RANGE Pick the smallest PicoScope input range that
%covers +/- requiredPeakVoltage.
%   [rangeIndex, rangeVolts] = pico_select_voltage_range(ps4000aEnuminfo, requiredPeakVoltage)
%   [rangeIndex, rangeVolts] = pico_select_voltage_range(ps4000aEnuminfo, requiredPeakVoltage, marginFactor)
%
%   requiredPeakVoltage is the largest voltage the input signal can reach
%   (e.g. maxExpectedCurrentA * voltsPerAmp for a current clamp).
%   marginFactor (default 1.2) adds headroom so the signal doesn't sit
%   right at the edge of the range and risk clipping on overshoot/noise.
%
%   Reads the available ranges from ps4000aEnuminfo.enPS4000ARange (the
%   struct/enum names encode the voltage, e.g. PS4000A_5V, PS4000A_200MV)
%   instead of a hardcoded table, so it adapts to whatever ranges the
%   connected model actually exposes.

if (nargin < 3 || isempty(marginFactor))
    marginFactor = 1.2;
end

rangeNames = fieldnames(ps4000aEnuminfo.enPS4000ARange);

rangeVoltsAll = nan(numel(rangeNames), 1);
rangeIndexAll = nan(numel(rangeNames), 1);

for i = 1:numel(rangeNames)

    name = rangeNames{i};
    tok = regexp(name, '_(\d+)(MV|V)$', 'tokens', 'once');

    if (isempty(tok))
        continue; % skip non-numeric entries, e.g. PS4000A_MAX_RANGES
    end

    value = str2double(tok{1});

    if (strcmpi(tok{2}, 'MV'))
        volts = value / 1000;
    else
        volts = value;
    end

    rangeVoltsAll(i) = volts;
    rangeIndexAll(i) = double(ps4000aEnuminfo.enPS4000ARange.(name));

end

valid = ~isnan(rangeVoltsAll);
rangeVoltsAll = rangeVoltsAll(valid);
rangeIndexAll = rangeIndexAll(valid);

[rangeVoltsSorted, order] = sort(rangeVoltsAll);
rangeIndexSorted = rangeIndexAll(order);

neededVolts = requiredPeakVoltage * marginFactor;
choice = find(rangeVoltsSorted >= neededVolts, 1, 'first');

if (isempty(choice))

    [rangeVolts, choice] = max(rangeVoltsSorted);
    rangeIndex = rangeIndexSorted(choice);

    warning('pico_select_voltage_range:exceedsMaxRange', ...
        ['Required peak voltage %.3f V (with margin) exceeds the largest ' ...
         'available range (%.3f V); using the largest range instead - the ' ...
         'signal may clip.'], neededVolts, rangeVolts);

else

    rangeIndex = rangeIndexSorted(choice);
    rangeVolts = rangeVoltsSorted(choice);

end

end
