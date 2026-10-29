function result = runGuamHeadless(session, ref)
% RUNGUAMHEADLESS Simulate a trajectory without prompts, plots or MAT saves.
% result = runGuamHeadless(session, ref)
% Prepare session with prepareGuamHeadless. Repeated trajectories must have
% the same start time, position, heading, heading rate and heading-frame
% velocity, so vehicle trim/controller initialization remains applicable.
% Each call starts a fresh simulation; Fast Restart is not enabled here.
started = tic;
ref = guamHeadlessRefInput(ref);
names = fieldnames(ref);
for k = 1:numel(names)
    name = names{k};
    old = session.reference.(name);
    current = ref.(name);
    if current.Time(1) ~= old.Time(1) || ...
            ~isequal(current.Data(1,:), old.Data(1,:))
        error('GUAM:HeadlessInitialCondition', ...
            'Changed starting condition in %s; prepare a new session.', name);
    end
end
if ~bdIsLoaded('GUAM')
    error('GUAM:HeadlessSession', 'Prepare a session before running the simulation.');
end

simIn = session.SimIn;
simIn.RefInputs = setupRefTimeseries(simIn, struct('RefInput', ref));
simIn.startTime = ref.pos_des.Time(1);
simIn.stopTime = ref.pos_des.Time(end);
parameters = session.parameters;
parameters.startTime = simIn.startTime;
parameters.stopTime = simIn.stopTime;
for k = 1:numel(names)
    ts = ref.(names{k});
    parameters.RefInputs.SimInput.(names{k}) = [ts.Time ts.Data];
end
% Trajectory arrays live inside the typed SimPar bus. Rebuild its schema so
% candidates can change their sample count, without repeating vehicle setup.
props.Description = 'L+C Tunable Parameters';
props.DataScope = 'Exported';
props.HeaderFile = 'Parameters.h';
props.Alignment = -1;
bus = buildBusObject(parameters, 'BUS_PARAM_', 'SimPar', props);
assignin('base', 'BUS_PARAM_SimPar', bus);
parameter = Simulink.Parameter;
parameter.Value = parameters;
parameter.DataType = 'Bus: BUS_PARAM_SimPar';
parameter.CoderInfo.StorageClass = 'ExportedGlobal';

input = Simulink.SimulationInput('GUAM');
input = input.setVariable('SimIn', simIn);
input = input.setVariable('SimPar', parameter);
input = input.setModelParameter('SimulationMode', 'normal', ...
    'StartTime', num2str(simIn.startTime, 17), ...
    'StopTime', num2str(simIn.stopTime, 17), ...
    'Profile', 'off', 'ReturnWorkspaceOutputs', 'on');
simulationStarted = tic;
output = sim(input);
result.timing.simCallSeconds = toc(simulationStarted);
result.SimOut = output.logsout{1}.Values;
info = output.SimulationMetadata.TimingInfo;
result.timing.initializationSeconds = info.InitializationElapsedWallTime;
result.timing.executionSeconds = info.ExecutionElapsedWallTime;
result.timing.terminationSeconds = info.TerminationElapsedWallTime;
result.timing.totalSeconds = toc(started);
end
