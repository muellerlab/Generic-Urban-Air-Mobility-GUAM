function exportSimOutCsv(SimOut, filename)
% EXPORTSIMOUTCSV Save time, 13 vehicle-state components and 9 motor RPMs.
% States use GUAM native units: ft, ft/s, dimensionless Q_i2b, and rad/s.
% Motor speeds are converted from rad/s to RPM. All signals must share times.
paths = {'Vehicle.EOM.InertialData.Pos_bii', ...
    'Vehicle.EOM.InertialData.Vel_bIi', ...
    'Vehicle.EOM.InertialData.Q_i2b', ...
    'Vehicle.EOM.InertialData.Omeg_BIb', ...
    'Vehicle.PropAct.EngSpeed'};
widths = [3 3 4 3 9];
headers = {'time_s'};
columns = cell(1, numel(paths) + 1);
for k = 1:numel(paths)
    signal = SimOut;
    names = strsplit(paths{k}, '.');
    for j = 1:numel(names)
        signal = signal.(names{j});
    end
    [time, data] = readSignal(signal, paths{k}, widths(k));
    if k == 1
        columns{1} = time;
    elseif ~isequal(time, columns{1})
        error('GUAM:CsvTimeGrid', ...
            '%s timestamps differ from the vehicle state; CSV export does not resample.', paths{k});
    end
    headerPath = paths{k};
    if k == numel(paths)
        data = data * 60 / (2*pi);
        headerPath = 'Vehicle.PropAct.EngSpeed_rpm';
    end
    columns{k+1} = data;
    headers = [headers, arrayfun(@(n) sprintf('%s.Data[%d]', headerPath, n), ...
        0:widths(k)-1, 'UniformOutput', false)]; %#ok<AGROW>
end
rows = [columns{:}];
fid = fopen(filename, 'w');
if fid < 0
    error('GUAM:CsvExport', 'Cannot open CSV file: %s', filename);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', strjoin(headers, ','));
format = [repmat('%.17g,', 1, size(rows, 2)-1), '%.17g\n'];
fprintf(fid, format, rows.');
[message, number] = ferror(fid);
if number ~= 0
    error('GUAM:CsvExport', 'CSV write failed: %s', message);
end
fprintf('Saved CSV: %s (%d rows, %d columns)\n', filename, size(rows, 1), size(rows, 2));
end

function [time, data] = readSignal(signal, path, width)
if ~isa(signal, 'timeseries')
    error('GUAM:CsvExport', '%s must be a timeseries.', path);
end
time = double(signal.Time(:));
data = signal.Data;
if isempty(time) || any(~isfinite(time)) || any(diff(time) < 0)
    error('GUAM:CsvExport', '%s needs finite, nondecreasing timestamps.', path);
end
if ~isnumeric(data) || ~isreal(data)
    error('GUAM:CsvExport', '%s must contain real numeric samples.', path);
end
if ~signal.IsTimeFirst
    data = permute(data, [ndims(data), 1:ndims(data)-1]);
end
if size(data, 1) ~= numel(time) || numel(data) ~= numel(time)*width
    error('GUAM:CsvExport', '%s must have %d components per sample.', path, width);
end
data = reshape(double(data), numel(time), width);
end
