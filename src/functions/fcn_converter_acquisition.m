function boardMeas = fcn_converter_acquisition(ts, measurements, MEAS)
%FCN_CONVERTER_ACQUISITION reads the TWIST/SPIN board measurements via ThingSet
%   Returns a struct whose field names are the ThingSet short names
%   (e.g. boardMeas.VHigh, boardMeas.Temp1), then prints all
%   measurements and their current values at once.

names = ["VHigh", "IHigh", "I1rms", "I2rms", "Vhighripple", "Temp1", "Temp2", "PowerP", "PowerQ"];
% names(end+1) = "Mode";

for name = names
    boardMeas.(name) = ts.read(measurements(name));
end

% Flush all measurements and their current values at once.
% disp(ts.read(MEAS));

end
