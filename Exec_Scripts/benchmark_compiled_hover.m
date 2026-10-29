% Probe standalone C++ generation and benchmark compiled Simulink execution.
% Run only in a disposable repository copy, from that copy's root.
cd(fileparts(fileparts(mfilename('fullpath'))));
addpath('Exec_Scripts');
plan = planHoverTransfer([0 0 -100], [20000 0 -100], 180, 2, ...
    'SampleTime', 0.05, 'HoldTime', 40);
session = prepareGuamHeadless(plan.RefInput);
compiledReport.products = {ver().Name};
compiledReport.standaloneGenerated = false;
compiledReport.standaloneFailure = '';
set_param('GUAM', 'TargetLang', 'C++', 'GenCodeOnly', 'on');
try
    slbuild('GUAM');
    compiledReport.standaloneGenerated = true;
    fprintf('Standalone C++ source generation succeeded.\n');
catch exception
    compiledReport.standaloneFailure = exception.message;
    fprintf('Standalone C++ build probe: %s\n', exception.message);
end
set_param('GUAM', 'SimTargetLang', 'C++');
compiledReport.modes = cell(3, 1);
for compiledRun = 1:3
    if compiledRun == 1
        compiledMode = 'normal';
    else
        compiledMode = 'rapid-accelerator';
    end
    fprintf('BEGIN compiled benchmark: %s, run %d\n', compiledMode, compiledRun);
    compiledTimer = tic;
    try
        compiledOutput = sim('GUAM', 'ReturnWorkspaceOutputs', 'on', ...
            'Profile', 'off', 'SimulationMode', compiledMode);
    catch exception
        compiledReport.runtimeFailure = getReport(exception, 'extended', 'hyperlinks', 'off');
        writeCompiledReport(compiledReport);
        rethrow(exception);
    end
    compiledElapsed = toc(compiledTimer);
    compiledInfo = compiledOutput.SimulationMetadata.TimingInfo;
    compiledSimOut = compiledOutput.logsout{1}.Values;
    if compiledRun == 1
        compiledReference = compiledSimOut;
        compiledMaxRelative = 0;
    else
        compiledMaxRelative = compareCompiledSignals(compiledReference, compiledSimOut, 'SimOut');
    end
    compiledSummary = analyzeHoverTransfer(compiledSimOut, plan);
    compiledReport.modes{compiledRun} = struct('mode', compiledMode, ...
        'totalSeconds', compiledElapsed, ...
        'initializationSeconds', compiledInfo.InitializationElapsedWallTime, ...
        'executionSeconds', compiledInfo.ExecutionElapsedWallTime, ...
        'terminationSeconds', compiledInfo.TerminationElapsedWallTime, ...
        'maxRelativeSignalDifference', compiledMaxRelative, 'flight', compiledSummary);
    writeCompiledReport(compiledReport);
    fprintf('COMPILED BENCHMARK: %s total %.3f s, execution %.3f s, max scaled difference %.3g\n', ...
        compiledMode, compiledElapsed, compiledInfo.ExecutionElapsedWallTime, compiledMaxRelative);
    clear compiledOutput compiledSimOut
end
close_system('GUAM', 0);
fprintf('COMPILED HOVER BENCHMARK PASSED.\n');

function difference = compareCompiledSignals(a, b, path)
difference = 0;
if isa(a, 'timeseries')
    assert(isa(b, 'timeseries'), path);
    assert(isequal(size(a.Data), size(b.Data)), path);
    assert(max(abs(a.Time - b.Time)) < 1e-8, path);
    finite = isfinite(a.Data(:));
    assert(isequal(finite, isfinite(b.Data(:))), path);
    assert(isequaln(a.Data(~finite), b.Data(~finite)), path);
    if any(finite)
        difference = max(abs(double(a.Data(finite)) - double(b.Data(finite)))) / ...
            max([1; abs(double(a.Data(finite)))]);
    end
    assert(difference <= 1e-7, 'GUAM:CompiledMismatch', ...
        '%s differs by %.3g relative to signal scale.', path, difference);
elseif isstruct(a)
    fields = fieldnames(a);
    assert(isequal(fields, fieldnames(b)), path);
    for k = 1:numel(fields)
        difference = max(difference, compareCompiledSignals(a.(fields{k}), ...
            b.(fields{k}), [path '.' fields{k}]));
    end
else
    assert(isequaln(a, b), path);
end
end

function writeCompiledReport(report)
fid = fopen('/tmp/guam_compiled_hover_benchmark.json', 'w');
assert(fid >= 0);
fprintf(fid, '%s\n', jsonencode(report, 'PrettyPrint', true));
fclose(fid);
end
