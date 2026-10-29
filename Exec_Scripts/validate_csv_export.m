% Verify compact CSV values and RPM conversion without running or plotting a sim.
cd(fileparts(fileparts(mfilename('fullpath'))));
t = [0; 1; 2];
fixture.Vehicle.EOM.InertialData.Pos_bii = timeseries([1 2 3; 4 5 6; 7 8 9], t);
fixture.Vehicle.EOM.InertialData.Vel_bIi = timeseries(reshape(10:18, [3 1 3]), t);
fixture.Vehicle.EOM.InertialData.Q_i2b = timeseries(repmat([1 0 0 0], 3, 1), t);
fixture.Vehicle.EOM.InertialData.Omeg_BIb = timeseries(zeros(3, 3), t);
fixture.Vehicle.PropAct.EngSpeed = timeseries(2*pi*ones(3, 9), t);
exportSimOutCsv(fixture, '/tmp/guam_csv_fixture.csv');
actual = readmatrix('/tmp/guam_csv_fixture.csv', 'NumHeaderLines', 1);
expected = [t, [1 2 3; 4 5 6; 7 8 9], [10 11 12; 13 14 15; 16 17 18], ...
    repmat([1 0 0 0], 3, 1), zeros(3, 3), 60*ones(3, 9)];
assert(isequal(size(actual), [3 23]));
assert(max(abs(actual(:) - expected(:))) < 1e-12);
fixture.Vehicle.PropAct.EngSpeed = timeseries(zeros(3, 9), t + 0.1);
try
    exportSimOutCsv(fixture, '/tmp/guam_csv_bad_grid.csv');
    error('GUAM:CsvValidation', 'Mismatched timestamps were accepted.');
catch exception
    assert(strcmp(exception.identifier, 'GUAM:CsvTimeGrid'));
end
fprintf('Compact CSV fixture passed: sample ordering, 23 columns, RPM conversion and mismatched-time guard.\n');

loaded = load('Exec_Scripts/SimOut_case6.mat', 'SimOut');
exportTimer = tic;
exportSimOutCsv(loaded.SimOut, 'Exec_Scripts/SimOut_case6.csv');
fprintf('Compact hover CSV export took %.3f seconds.\n', toc(exportTimer));
actual = readmatrix('Exec_Scripts/SimOut_case6.csv', 'NumHeaderLines', 1);
paths = {'Vehicle.EOM.InertialData.Pos_bii', 'Vehicle.EOM.InertialData.Vel_bIi', ...
    'Vehicle.EOM.InertialData.Q_i2b', 'Vehicle.EOM.InertialData.Omeg_BIb', ...
    'Vehicle.PropAct.EngSpeed'};
reference = cell(numel(paths), 1);
column = 2;
for k = 1:numel(paths)
    signal = loaded.SimOut;
    names = strsplit(paths{k}, '.');
    for j = 1:numel(names)
        signal = signal.(names{j});
    end
    data = squeeze(signal.Data);
    if ~signal.IsTimeFirst
        data = data.';
    end
    csvPath = paths{k};
    if k == numel(paths)
        data = data * 60 / (2*pi);
        csvPath = 'Vehicle.PropAct.EngSpeed_rpm';
    end
    assert(isequal(actual(:,1), signal.Time(:)));
    exported = actual(:,column:column+size(data,2)-1);
    assert(max(abs(exported(:) - data(:))) <= 1e-14*max(1, max(abs(data(:)))));
    column = column + size(data,2);
    reference{k} = struct('path', csvPath, 'count', numel(signal.Time), ...
        'firstTime', signal.Time(1), 'lastTime', signal.Time(end), ...
        'minimum', min(data, [], 1), 'maximum', max(data, [], 1), ...
        'first', data(1,:), 'last', data(end,:));
end
assert(column == 24 && size(actual,2) == 23);
fid = fopen('/tmp/guam_csv_expected.json', 'w');
assert(fid >= 0);
fprintf(fid, '%s\n', jsonencode(reference));
fclose(fid);
fprintf('CSV EXPORT VALIDATION PASSED: all state and motor samples checked against MAT.\n');
