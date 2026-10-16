function fig = fcn_reuse_figure(name)
%FCN_REUSE_FIGURE returns the figure called name, cleared, or creates it
%   Plot functions called after every acquisition use it so that each kind
%   of plot keeps a single window that is updated, instead of opening a new
%   figure every time.

fig = findobj(groot, 'Type', 'figure', 'Name', name);
if isempty(fig)
    fig = figure('Name', name, 'NumberTitle', 'off');
else
    fig = fig(1);
    figure(fig);
    clf(fig);
end

end
