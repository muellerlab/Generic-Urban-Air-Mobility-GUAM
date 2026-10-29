function session = prepareGuamHeadless(ref)
% PREPAREGUAMHEADLESS Prepare the default Lift+Cruise vehicle once.
% Run from the repository root. ref uses GUAM timeseries in ft, s, rad.
% Sets GUAM variables in the base workspace and runs setupPath (which resets
% the MATLAB path). Keep that workspace and loaded model for subsequent runs.
% Does not copy output functions or save models. Uses current mySimOutFunc.
ref = guamHeadlessRefInput(ref);
root = fileparts(mfilename('fullpath'));
if ~strcmp(pwd, root)
    error('GUAM:HeadlessDirectory', 'Run from the GUAM repository root: %s', root);
end
if bdIsLoaded('GUAM')
    error('GUAM:HeadlessLoaded', ...
        'Close GUAM before preparing a session; save any edits you want to keep.');
end
started = tic;
assignin('base', 'userStruct', struct('variants', struct('refInputType', 3)));
assignin('base', 'target', struct('RefInput', ref));
assignin('base', 'SimIn', struct());
% Existing bus builders and model expressions require the base workspace.
evalin('base', [ ...
    'setupPath; setupVariantStruct; ' ...
    'SimIn = setupTypes(SimIn, userStruct.variants); setupSwitches; ' ...
    'SimIn.Units = setUnits(''ft'', ''slug''); ' ...
    'SimIn = setup(SimIn, target); setupParameters(SimIn); ' ...
    'setupVariants; setupBuses;']);

% Configure the current output mapping in memory. The standard bus builder
% also saves GUAM; deliberately omit that operation here.
fullOutput = Simulink.Bus.createMATLABStruct('BUS_SIM_OUT');
selectedOutput = mySimOutFunc(fullOutput);
bus = buildBusObject(selectedOutput, 'BUS_USER_', 'SIM_OUT');
assignin('base', 'BUS_USER_SIM_OUT', bus);
load_system('GUAM');
diagram = get_param('GUAM', 'Object');
chart = find(diagram, '-isa', 'Stateflow.EMChart', ...
    'Path', 'GUAM/Vehicle Simulation/SimOut_Selection');
chart.Outputs.DataType = 'Bus: BUS_USER_SIM_OUT';
set_param('GUAM/Vehicle Simulation/SimOutputs', ...
    'OutDataTypeStr', 'Bus: BUS_USER_SIM_OUT');

session.SimIn = evalin('base', 'SimIn');
parameter = evalin('base', 'SimPar');
session.parameters = parameter.Value;
session.reference = ref;
session.setupSeconds = toc(started);
end
