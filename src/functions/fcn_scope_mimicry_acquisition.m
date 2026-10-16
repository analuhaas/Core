function [scopeMimicry, scopeNames, scopeData] = fcn_scope_mimicry_acquisition(ts, con, scopeTs, timeout_s)
%FCN_SCOPE_MIMICRY_ACQUISITION captures and retrieves the board's ScopeMimicry buffer
%   The capture is armed and the dump is asked over ThingSet (Config/wScopeArm,
%   Config/wScopeDump), and the data are read on the board's console port,
%   where dump_scope_datas() prints them:
%       begin record
%       #name1,name2,...,         <- channel names
%       ## idx                    <- final index of the circular buffer
%       41a3d70a                  <- one float32 per line, 8 hex digits
%       ...
%       end record
%
%   ts: ThingSetTools connection (ThingSet shell port)
%   con: serialport object of the console port (the other port of the board)
%   scopeTs: [s] ScopeMimicry sample time (control task period)
%   timeout_s: [s] max time to wait for the capture and for the dump
%
%   scopeMimicry: struct with the time vector t [s] and one field per channel
%   scopeNames: channel names, scopeData: samples x channels (oldest first)

% Arm and trigger a new capture, then wait until it is complete
flush(con);
ts.write("Config", struct("wScopeArm", 1));
t0 = tic;
while true
    scopeState = ts.read("Measurements/rScopeState");
    if isstring(scopeState) || ischar(scopeState)
        scopeState = str2double(scopeState); % garbled response: NaN, treated as not ready
    end
    if isequal(scopeState, 2)
        break;
    end
    if toc(t0) > timeout_s
        error('ScopeMimicry: capture not complete after %.1f s (last state read: %s).', timeout_s, mat2str(scopeState));
    end
    pause(0.05);
end

% Ask the dump and read the console port until "end record"
flush(con);
ts.write("Config", struct("wScopeDump", 1));
txt = "";
t0 = tic;
while ~contains(txt, "end record")
    if con.NumBytesAvailable > 0
        txt = txt + string(read(con, con.NumBytesAvailable, "char"));
    else
        pause(0.05);
    end
    if toc(t0) > timeout_s
        error('ScopeMimicry: dump not complete after %.1f s.', timeout_s);
    end
end

% Keep only the dumped block and parse it
lines = strtrim(splitlines(extractBetween(txt, "begin record", "end record")));
lines = lines(lines ~= "");
scopeNames = split(erase(lines(1), "#"), ","); % channel names
scopeNames = scopeNames(scopeNames ~= "");
finalIdx = sscanf(erase(lines(2), "#"), "%d"); % final index of the circular buffer
vals = typecast(uint32(hex2dec(lines(3:end))), 'single'); % hex -> float32

% One row per sample (the last, incomplete row is dropped), oldest sample first
nCh = numel(scopeNames);
nRows = floor(numel(vals) / nCh);
scopeData = reshape(double(vals(1:nRows*nCh)), nCh, nRows).';
scopeData = circshift(scopeData, -(finalIdx + 1));

scopeMimicry.t = (0:nRows-1).' * scopeTs; % [s]
for ch = 1:nCh
    scopeMimicry.(matlab.lang.makeValidName(scopeNames(ch))) = scopeData(:, ch);
end

fprintf('ScopeMimicry: %d channels x %d samples retrieved\n', nCh, nRows);

end
