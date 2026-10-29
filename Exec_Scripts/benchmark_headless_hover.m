% Compare the existing hover-to-hover example and the reusable wrapper.
% Run in a disposable repository copy: the original setup saves its model.
cd(fileparts(fileparts(mfilename('fullpath'))));
addpath('Exec_Scripts');
benchRows = cell(4, 8);
benchSummaries = cell(4, 1);
benchSignals = {'Pos_bii', 'Vel_bIi', 'Q_i2b', 'Omeg_BIb'};
for benchRun = 1:4
    benchTotal = tic;
    if benchRun <= 2
        userStruct = struct('enablePlots', false, 'profileComponents', false);
        exam_Hover2Hover;
        benchSetupSeconds = toc(benchTotal);
        benchSimTimer = tic;
        out = sim(model, 'ReturnWorkspaceOutputs', 'on', 'Profile', 'off', ...
            'SimulationMode', 'normal');
        benchSimSeconds = toc(benchSimTimer);
        SimOut = out.logsout{1}.Values;
        benchInfo = out.SimulationMetadata.TimingInfo;
        benchInit = benchInfo.InitializationElapsedWallTime;
        benchExec = benchInfo.ExecutionElapsedWallTime;
        benchTerm = benchInfo.TerminationElapsedWallTime;
        benchLabel = sprintf('Original %d', benchRun);
    else
        if benchRun == 3
            close_system('GUAM', 0);
            session = prepareGuamHeadless(plan.RefInput);
            benchSetupSeconds = toc(benchTotal);
        else
            benchSetupSeconds = 0;
        end
        result = runGuamHeadless(session, plan.RefInput);
        SimOut = result.SimOut;
        benchSimSeconds = result.timing.simCallSeconds;
        benchInit = result.timing.initializationSeconds;
        benchExec = result.timing.executionSeconds;
        benchTerm = result.timing.terminationSeconds;
        benchLabel = sprintf('Headless %d', benchRun - 2);
    end
    benchSeconds = toc(benchTotal);
    benchInertial = SimOut.Vehicle.EOM.InertialData;
    if benchRun == 1
        benchReference = benchInertial;
        benchRotorReference = SimOut.Vehicle.PropAct.EngSpeed;
    end
    benchMaxDifference = 0;
    for benchSignal = benchSignals
        a = benchReference.(benchSignal{1});
        b = benchInertial.(benchSignal{1});
        assert(isequal(a.Time, b.Time));
        assert(all(isfinite(b.Data(:))));
        benchDifference = max(abs(a.Data(:) - b.Data(:)));
        assert(benchDifference <= 1e-10 * max(1, max(abs(a.Data(:)))));
        benchMaxDifference = max(benchMaxDifference, benchDifference);
    end
    a = benchRotorReference;
    b = SimOut.Vehicle.PropAct.EngSpeed;
    assert(isequal(a.Time, b.Time));
    assert(all(isfinite(b.Data(:))));
    assert(max(abs(a.Data(:) - b.Data(:))) <= 1e-10 * max(1, max(abs(a.Data(:)))));
    benchRows(benchRun,:) = {benchLabel, benchSetupSeconds, benchSimSeconds, ...
        benchInit, benchExec, benchTerm, benchSeconds, benchMaxDifference};
    benchSummaries{benchRun} = analyzeHoverTransfer(SimOut, plan);
    fprintf('BENCHMARK %s: setup %.3f s, simulation %.3f s, execution %.3f s, total %.3f s\n', ...
        benchLabel, benchSetupSeconds, benchSimSeconds, benchExec, benchSeconds);
    clear out result SimOut benchInertial
end
benchTable = cell2table(benchRows, 'VariableNames', {'Workflow', ...
    'SetupSeconds', 'SimCallSeconds', 'InitializationSeconds', ...
    'ExecutionSeconds', 'TerminationSeconds', 'TotalSeconds', 'MaxStateDifference'});
disp(benchTable);

% Exercise the array-size fix by changing from the full reference to a short
% trajectory with the same starting state, using the already prepared session.
shortPlan = planHoverTransfer([0 0 -100], [200 0 -100], 10, 1, ...
    'SampleTime', 0.05, 'HoldTime', 5);
shortResult = runGuamHeadless(session, shortPlan.RefInput);
shortPosition = shortResult.SimOut.Vehicle.EOM.InertialData.Pos_bii;
assert(abs(shortPosition.Time(end) - shortPlan.stopTime) < 1e-9);
assert(all(isfinite(shortPosition.Data(:))));
fprintf('Changed-length trajectory passed.\n');
report.timings = table2struct(benchTable);
report.flightSummaries = benchSummaries;
report.flightDuration = plan.stopTime;
report.changedLengthPassed = true;
fid = fopen('/tmp/guam_hover_benchmark.json', 'w');
assert(fid >= 0);
fprintf(fid, '%s\n', jsonencode(report, 'PrettyPrint', true));
fclose(fid);
close_system('GUAM', 0);
fprintf('HOVER BENCHMARK PASSED.\n');
