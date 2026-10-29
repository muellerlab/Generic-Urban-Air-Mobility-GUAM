% Run from the repository root, interactively or with:
% matlab -batch "run('Exec_Scripts/example_headless.m')"
% MATLAB's run command may change directory to this script's folder.
cd(fileparts(fileparts(mfilename('fullpath'))));
addpath('Exec_Scripts');
plan = planHoverTransfer([0 0 -100], [200 0 -100], 10, 1, ...
    'SampleTime', 0.05, 'HoldTime', 5);
session = prepareGuamHeadless(plan.RefInput);
result = runGuamHeadless(session, plan.RefInput);
disp(result.timing);
% Actual flight data, retaining GUAM's existing nested timeseries format:
states = result.SimOut.Vehicle.EOM;
% Run more candidates without preparing again, provided their starting
% conditions match. Save result explicitly only when it is needed.
% At the end of a batch job, discard the in-memory output-bus configuration:
close_system('GUAM', 0);
