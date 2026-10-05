function X = fcn_FundamentalPhasor(x, Ts, f0)
%FCN_FUNDAMENTALPHASOR RMS phasor of the f0 component of a sampled signal
%   Single-bin DFT over the largest whole number of f0 periods contained in
%   x, so the DC offset, harmonics and switching ripple are rejected.
%   abs(X) is the fundamental rms value and angle(X) its phase [rad]
%   relative to the first sample. Two signals captured on the same scope
%   (same time base) can be compared directly with angle(X1/X2).

if ~isscalar(Ts) || ~(Ts > 0)
    error('fcn_FundamentalPhasor: Ts must be a positive scalar (got %s).', mat2str(Ts));
end

x = x(:);
N =round(floor(numel(x) * Ts * f0) / (f0 * Ts));   % samples in whole periods
if N < 1
    error('fcn_FundamentalPhasor: capture shorter than one period of f0.');
end

t = (0:N-1).' * Ts;
X = sqrt(2) / N * sum(x(1:N) .* exp(-1j * 2*pi*f0 * t));
end
