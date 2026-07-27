function [Pab, Qab, Pfft, Qfft, P, Q] = fcn_GetPower(v,i,Ts,f0,f_switching)
%FCN_GETPOWER Calculates the active and reactive power output on the AC
%side of the converter

%% output
% P, Q

%% Calculate power data with artificial single-phase v~ and i~ system method

v_hat = imag(hilbert(v));
i_hat = imag(hilbert(i));

Pab = 0.5*mean(v .* i + v_hat .* i_hat);
Qab = 0.5*mean(v_hat .* i - v .* i_hat);

%% Calculate power data with fft method

Fs = 1/Ts;     % sampling frequency
N = length(v);

V = fft(v)/N;
I = fft(i)/N;

k = round(f0*N/Fs) + 1;   % fundamental freq index

V1 = V(k);
I1 = I(k);

Vrms = abs(V1)*sqrt(2);
Irms = abs(I1)*sqrt(2);

phi = angle(V1) - angle(I1);

Pfft = Vrms*Irms*cos(phi);
Qfft = Vrms*Irms*sin(phi);

% ksw = round(f_switching*N/Fs) + 1;   % fundamental freq index
% 
% Vsw = V(ksw);
% Isw = I(ksw);
% 
% Vsw = abs(Vsw)*2;
% Isw = abs(Isw)*2;
%% Calculate power data by traditional formula
rms(v);
rms(i);
S = rms(v) * rms(i);
P = mean(v .* i).*ones(length(S),1);
Q = sqrt(S.^2 - P.^2);
end 
