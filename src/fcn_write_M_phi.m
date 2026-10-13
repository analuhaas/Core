function [] = fcn_write_M_phi(ts, Mmod, phimod)
%FCN_WRITE_M_PHI commands the converter modulation amplitude and phase
ts.write("Config", struct("wMp", Mmod));
ts.write("Config", struct("wphi_m", phimod));
end
