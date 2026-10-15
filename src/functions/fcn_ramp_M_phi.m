function [Mp, phi_m] = fcn_ramp_M_phi(ts, Mp_start, phi_m_start, Mp_end, phi_m_end, rampMaxStepM, rampMaxStepPhi, rampStepPause_s)
%FCN_RAMP_M_PHI ramps the converter modulation amplitude Mp and phase phi_m
%linearly from (Mp_start, phi_m_start) to (Mp_end, phi_m_end)
%   The number of steps is chosen so that no step changes Mp by more than
%   rampMaxStepM nor phi_m by more than rampMaxStepPhi [rad]. Waits
%   rampStepPause_s after each step. Returns the final (Mp, phi_m) written.

numSteps = max([ceil(abs(Mp_end - Mp_start) / rampMaxStepM), ceil(abs(phi_m_end - phi_m_start) / rampMaxStepPhi), 1]);

fprintf('Ramp: Mp %.4f -> %.4f, phi_m %+.4f -> %+.4f rad in %d steps\n', ...
    Mp_start, Mp_end, phi_m_start, phi_m_end, numSteps);

for n = 1:numSteps

    Mp = Mp_start + (Mp_end - Mp_start) * n / numSteps;
    phi_m = phi_m_start + (phi_m_end - phi_m_start) * n / numSteps;

    ts.write("Config", struct("wMp", Mp));
    ts.write("Config", struct("wphi_m", phi_m));
    pause(rampStepPause_s);

end

end
