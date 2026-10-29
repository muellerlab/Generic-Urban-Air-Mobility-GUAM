function ref = guamHeadlessRefInput(ref)
% Validate the existing GUAM timeseries trajectory contract (ft, s, rad).
fields = {'Vel_bIc_des', 'pos_des', 'chi_des', 'chi_dot_des'};
widths = [3 3 1 1];
for k = 1:numel(fields)
    name = fields{k};
    if ~isstruct(ref) || ~isscalar(ref) || ~isfield(ref, name) || ...
            ~isa(ref.(name), 'timeseries')
        error('GUAM:HeadlessTrajectory', '%s must be a timeseries.', name);
    end
    ts = ref.(name);
    t = ts.Time;
    data = ts.Data;
    if ~isnumeric(data) || ~isreal(data) || ~ismatrix(data) || ...
            size(data, 1) ~= numel(t) || size(data, 2) ~= widths(k) || ...
            numel(t) < 2 || any(~isfinite(t)) || any(diff(t) <= 0) || ...
            any(~isfinite(data(:)))
        error('GUAM:HeadlessTrajectory', ...
            '%s needs finite N-by-%d data and increasing times (N >= 2).', ...
            name, widths(k));
    end
    if k == 1
        time = t;
    elseif ~isequal(t, time)
        error('GUAM:HeadlessTrajectory', 'All reference signals must share a time grid.');
    end
end
% setupRefTimeseries scans every field; keep only supported reference inputs.
ref = struct('Vel_bIc_des', ref.Vel_bIc_des, 'pos_des', ref.pos_des, ...
    'chi_des', ref.chi_des, 'chi_dot_des', ref.chi_dot_des);
end
