% Validate wrapper outputs against a direct sim call in the prepared workspace.
% Run from a fresh MATLAB process with GUAM closed.
cd(fileparts(fileparts(mfilename('fullpath'))));
addpath('Exec_Scripts');
plan = planHoverTransfer([0 0 -100], [200 0 -100], 10, 1, ...
    'SampleTime', 0.05, 'HoldTime', 5);
session = prepareGuamHeadless(plan.RefInput);
first = runGuamHeadless(session, plan.RefInput);
assert(all(isfinite(first.SimOut.Vehicle.EOM.InertialData.Pos_bii.Data(:))));
second = runGuamHeadless(session, plan.RefInput);
assertSameSignals(first.SimOut, second.SimOut);
fprintf('Repeated-run equivalence passed.\n');
baseline = sim('GUAM', 'ReturnWorkspaceOutputs', 'on', 'Profile', 'off');
assertSameSignals(first.SimOut, baseline.logsout{1}.Values);
fprintf('Direct sim equivalence passed.\n');

candidate = planHoverTransfer([0 0 -100], [300 0 -100], 10, 1, ...
    'SampleTime', 0.05, 'HoldTime', 5);
changed = runGuamHeadless(session, candidate.RefInput);
position = changed.SimOut.Vehicle.EOM.InertialData.Pos_bii;
assert(abs(position.Time(end) - candidate.stopTime) < 1e-9);
assert(all(isfinite(position.Data(:))));

invalid = candidate.RefInput;
invalid.chi_des = timeseries(invalid.chi_des.Data + 0.1, invalid.chi_des.Time);
try
    runGuamHeadless(session, invalid);
    error('GUAM:Validation', 'Changed starting heading was accepted.');
catch exception
    assert(strcmp(exception.identifier, 'GUAM:HeadlessInitialCondition'));
end
fprintf('HEADLESS VALIDATION PASSED: repeated outputs, direct sim equivalence, changed trajectory, initial-condition guard.\n');
fprintf('Preparation: %.3f s\n', session.setupSeconds);
disp(first.timing);
disp(second.timing);
disp(changed.timing);
close_system('GUAM', 0);

function assertSameSignals(a, b, path)
if nargin < 3
    path = 'SimOut';
end
if isa(a, 'timeseries')
    assert(isa(b, 'timeseries'));
    assert(isequal(a.Time, b.Time));
    assert(isequal(size(a.Data), size(b.Data)));
    finite = isfinite(a.Data(:));
    assert(isequal(finite, isfinite(b.Data(:))), path);
    % GUAM includes infinite actuator failure limits in its output buses.
    % Require nonfinite values, including NaN/Inf signs, to match as well.
    assert(isequaln(a.Data(~finite), b.Data(~finite)), path);
    if any(~finite)
        fprintf('Matching nonfinite debug samples: %s (%d)\n', path, sum(~finite));
    end
    scale = max([1; abs(double(a.Data(finite)))]);
    assert(all(abs(double(a.Data(finite)) - double(b.Data(finite))) <= 1e-10 * scale), path);
elseif isstruct(a)
    names = fieldnames(a);
    assert(isequal(names, fieldnames(b)));
    for k = 1:numel(names)
        assertSameSignals(a.(names{k}), b.(names{k}), [path '.' names{k}]);
    end
else
    assert(isequaln(a, b));
end
end
