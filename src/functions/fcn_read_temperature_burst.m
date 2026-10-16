function [temp1, temp2, burst1, burst2] = fcn_read_temperature_burst(ts, measurements, tempBurstCount, tempBurstSpacing_s)
%FCN_READ_TEMPERATURE_BURST one averaged MOSFET temperature reading
%   Reads board Temp1 and Temp2 tempBurstCount times, spaced by
%   tempBurstSpacing_s (scheduled from the start of the burst), and returns
%   their means (temp1, temp2) and all the individual readings (burst1, burst2).

burst1 = NaN(1, tempBurstCount);
burst2 = NaN(1, tempBurstCount);

burstStart = tic;
for b = 1:tempBurstCount
    pause(max(0, (b - 1) * tempBurstSpacing_s - toc(burstStart)));
    burst1(b) = ts.read(measurements("Temp1"));
    burst2(b) = ts.read(measurements("Temp2"));
end

temp1 = mean(burst1);
temp2 = mean(burst2);

end
