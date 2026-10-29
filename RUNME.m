% This script is a toplevel script that executes the users desired example case:

addpath('./Exec_Scripts/');
u_choice = input(sprintf('Specify the desired example case to run:\n\t(1) Sinusoidal Timeseries\n\t(2) Hover to Transition Timeseries\n\t(3) Cruise Climbing Turn Timeseries\n\t(4) Ramp demo\n\t(5) Piecewise Bezier Trajectory\n\t(6) Hover to Hover (Accelerate/Forward Flight/Decelerate)\nUser Input: '));

if ~ismember(u_choice, 1:6)
    fprintf('User needs to supply selection choice (1-6)\n');
    return
end
timingLogFile = guamTiming('reset');
runTimer = guamTiming('start', 'Total run');
stageTimer = guamTiming('start', 'Preprocessing: example preparation');
try
switch u_choice
    case 1
        exam_TS_Sinusoidal_traj;
    case 2
        exam_TS_Hover2Cruise_traj
    case 3
        exam_TS_Cruise_Climb_Turn_traj
    case 4
        exam_RAMP
    case 5 
        if ~exist("userStruct",'var')
            addpath('./Bez_Functions/');
        end
        exam_Bezier;
    case 6
        exam_Hover2Hover;
    otherwise
        fprintf('User needs to supply selection choice (1-6)\n')
        return
end
guamTiming('stop', stageTimer);

% Execute the model and save SimOut for Animate_SimOut
% Component profiling is on by default; disable for normal speed benchmarks.
if ~isfield(userStruct, 'profileComponents')
    userStruct.profileComponents = true;
end
componentTiming = table;
blockTiming = table;
profileAccounting = table;
profileMode = 'off';
if userStruct.profileComponents
    profileMode = 'on';
    fprintf('[GUAM profile] Component profiling enabled (adds measurement overhead).\n');
end
stageTimer = guamTiming('start', 'Simulation: sim call');
simResult = sim(model, 'ReturnWorkspaceOutputs', 'on', 'Profile', profileMode);
guamTiming('stop', stageTimer);
simTiming = simResult.SimulationMetadata.TimingInfo;
timingFields = {'InitializationElapsedWallTime', 'ExecutionElapsedWallTime', ...
    'TerminationElapsedWallTime', 'TotalElapsedWallTime'};
for timingIndex = 1:numel(timingFields)
    guamTiming('record', struct('Label', ['Simulink: ' timingFields{timingIndex}], ...
        'Seconds', simTiming.(timingFields{timingIndex})));
end
stageTimer = guamTiming('start', 'Postprocessing: extract logged output');
logsout = simResult.logsout;
SimOut = logsout{1}.Values;
guamTiming('stop', stageTimer);
stageTimer = guamTiming('start', 'Postprocessing: save MAT file');
save(sprintf('./Exec_Scripts/SimOut_case%d.mat', u_choice), 'SimOut');
guamTiming('stop', stageTimer);
stageTimer = guamTiming('start', 'Postprocessing: save CSV file');
exportSimOutCsv(SimOut, sprintf('./Exec_Scripts/SimOut_case%d.csv', u_choice));
guamTiming('stop', stageTimer);
if u_choice == 6
    stageTimer = guamTiming('start', 'Postprocessing: hover transfer analysis');
    analyzeHoverTransfer(SimOut, plan);
    guamTiming('stop', stageTimer);
end
% Create sample output plots
if ~isfield(userStruct, 'enablePlots') || userStruct.enablePlots
    stageTimer = guamTiming('start', 'Postprocessing: plots');
    simPlots_GUAM;
    drawnow; % Include pending figure rendering in the plotting time.
    guamTiming('stop', stageTimer);
end
if userStruct.profileComponents
    stageTimer = guamTiming('start', 'Postprocessing: component profiling report');
    [profileLogDir, profileLogName] = fileparts(timingLogFile);
    [componentTiming, blockTiming, profileAccounting] = guamComponentTiming( ...
        simTiming.ProfilerData, simTiming.ExecutionElapsedWallTime, ...
        fullfile(profileLogDir, profileLogName));
    guamTiming('stop', stageTimer);
end
guamTiming('stop', runTimer);
timingSummary = guamTiming('summary');
catch runError
    guamTiming('fail', stageTimer);
    guamTiming('fail', runTimer);
    timingSummary = guamTiming('summary');
    rethrow(runError);
end
