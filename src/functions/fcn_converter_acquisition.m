function boardMeas = fcn_converter_acquisition(ts, measurements, MEAS)
%FCN_CONVERTER_ACQUISITION reads the TWIST/SPIN board measurements via ThingSet
%   Returns a struct whose field names are the ThingSet short names
%   (e.g. boardMeas.VHigh, boardMeas.Temp1).
%   Every measurement of the measurements map is read: the map is built from
%   the board's ThingSet tree at connection, so the list follows the
%   firmware (user_data_objects.h) without having to be edited here.

names = string(keys(measurements));

for name = names
    boardMeas.(name) = ts.read(measurements(name));
end

% Flush all measurements and their current values at once.
% disp(ts.read(MEAS));

end
