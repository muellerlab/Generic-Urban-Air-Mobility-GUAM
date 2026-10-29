function result = guamTiming(action, value)
% GUAMTIMING Log wall-clock stages to the console and a CSV file.
% token = guamTiming('start', 'Stage'); guamTiming('stop', token);
% guamTiming('reset') starts a new log; guamTiming('summary') returns a table.
% Nested stage durations are inclusive and must not be added together.
persistent logFile stages durations
if nargin < 2
    value = [];
end
if isempty(logFile) || strcmp(action, 'reset')
    logDir = fullfile(fileparts(mfilename('fullpath')), 'Exec_Scripts', 'timing_logs');
    if ~isfolder(logDir)
        mkdir(logDir);
    end
    logFile = [tempname(logDir) '.csv'];
    stages = cell(0,1);
    durations = zeros(0,1);
    fid = fopen(logFile, 'w');
    if fid < 0
        error('GUAM:TimingLog', 'Cannot create timing log: %s', logFile);
    end
    fprintf(fid, 'Timestamp,Stage,Event,WallSeconds\n');
    fclose(fid);
    fprintf('[GUAM timing] Log: %s\n', logFile);
end
result = [];
switch action
    case 'reset'
        result = logFile;
        return
    case 'start'
        result = struct('Label', value, 'Timer', tic);
        label = value;
        event = 'START';
        elapsed = NaN;
    case {'stop', 'fail'}
        label = value.Label;
        elapsed = toc(value.Timer);
        if strcmp(action, 'fail')
            event = 'FAILED';
        else
            event = 'DONE';
        end
        stages{end+1,1} = label;
        durations(end+1,1) = elapsed;
        result = elapsed;
    case 'record'
        % Record Simulink's own elapsed-time measurements without timing them again.
        label = value.Label;
        elapsed = value.Seconds;
        event = 'SIMULINK';
        stages{end+1,1} = label;
        durations(end+1,1) = elapsed;
    case 'summary'
        result = table(stages, durations, 'VariableNames', {'Stage', 'WallSeconds'});
        disp(result);
        fprintf('[GUAM timing] Nested stages overlap; durations are not additive.\n');
        fprintf('[GUAM timing] Log: %s\n', logFile);
        return
    otherwise
        error('GUAM:TimingAction', 'Unknown timing action: %s', action);
end
stamp = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
fprintf('[GUAM timing] %s %-8s %s', stamp, event, label);
if ~isnan(elapsed)
    fprintf(' (%.3f s)', elapsed);
end
fprintf('\n');
fid = fopen(logFile, 'a');
if fid < 0
    error('GUAM:TimingLog', 'Cannot append timing log: %s', logFile);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '"%s","%s",%s,%.6f\n', stamp, strrep(label, '"', '""'), event, elapsed);
end
