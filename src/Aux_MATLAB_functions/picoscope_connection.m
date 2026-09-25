function [ps4000aDeviceObj] = picoscope_connection(serialNumber)
%PICOSCOPE_CONNECTION Connect to a PicoScope 4000A series unit.
%   serialNumber (optional): serial number string of the unit to connect
%   to, e.g. 'AB123/456'. Required when more than one PicoScope is
%   connected to the PC, since an empty serial just grabs whichever unit
%   enumerates first. Find each unit's serial number by opening
%   PicoScope 6 with all units connected - the device selector lists the
%   serial of every connected scope. Omit/pass '' when only one scope is
%   connected.

if (nargin < 1)
    serialNumber = '';
end

ps4000aDeviceObj = icdevice('picotech_ps4000a_generic.mdd', serialNumber);

try
    connect(ps4000aDeviceObj);
catch causeErr
    delete(ps4000aDeviceObj);
    if (isempty(serialNumber))
        serialDesc = '(none specified - first available unit)';
    else
        serialDesc = serialNumber;
    end
    error('picoscope_connection:connectFailed', ...
        ['Could not connect to PicoScope with serial %s.\nLikely causes: ' ...
         'the serial does not match any connected unit, the unit is already ' ...
         'open in PicoScope 6 or another MATLAB session, or a previous run ' ...
         'left a stuck handle (try instrreset).\nUnderlying error: %s'], ...
        serialDesc, causeErr.message);
end

end

