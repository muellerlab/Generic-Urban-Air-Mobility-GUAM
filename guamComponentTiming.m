function [componentTiming, blockTiming, profileAccounting] = guamComponentTiming(profilerData, executionWallSeconds, filePrefix)
% GUAMCOMPONENTTIMING Partition Simulink profiler self time by GUAM component.
% Each hierarchy node contributes its self time to exactly one component.
% Includes all profiled callbacks, including block startup and termination.
% Inclusive total times are exported for drill-down but are never summed.
root = profilerData.rootUINode;
rows = collectNodes(root);
blockTiming = cell2table(rows, 'VariableNames', ...
    {'BlockPath', 'Component', 'SelfSeconds', 'InclusiveSeconds', 'Calls'});
blockTiming = sortrows(blockTiming, 'SelfSeconds', 'descend');
components = ["Turbulence"; "Atmosphere"; "Other environment"; ...
    "Aerodynamics"; "Propulsion"; "Combined aero/propulsion"; ...
    "Flight control"; "Actuators"; "Equations of motion"; ...
    "Sensors"; "Power system"; "Landing gear"; "Reference inputs"; ...
    "Output and assertions"; "Other model blocks"; "Simulation infrastructure"];
seconds = zeros(numel(components),1);
for index = 1:numel(components)
    seconds(index) = sum(blockTiming.SelfSeconds(blockTiming.Component == components(index)));
end
profiledSeconds = sum(seconds);
percent = zeros(size(seconds));
if profiledSeconds > 0
    percent = 100*seconds/profiledSeconds;
end
componentTiming = table(components, seconds, percent, 'VariableNames', ...
    {'Component', 'SelfSeconds', 'PercentOfProfiledTime'});
componentTiming = sortrows(componentTiming, 'SelfSeconds', 'descend');
componentTiming(end+1,:) = {"TOTAL (sum of self times)", profiledSeconds, sum(percent)};
profileAccounting = table(["Sum of component self times"; ...
    "Profiler root inclusive time"; "Simulink execution wall time"], ...
    [profiledSeconds; double(root.totalTime); executionWallSeconds], ...
    'VariableNames', {'Measurement', 'Seconds'});

% Save the raw profile first so it is available for the Simulink Profiler UI.
save([filePrefix '_profile.mat'], 'profilerData', 'executionWallSeconds');
writetable(componentTiming, [filePrefix '_components.csv']);
writetable(blockTiming, [filePrefix '_blocks.csv']);
writetable(profileAccounting, [filePrefix '_accounting.csv']);
fprintf('\n[GUAM profile] Component profiler breakdown (seconds):\n');
disp(componentTiming);
disp(profileAccounting);
fprintf('[GUAM profile] Self times are additive; inclusive block times are not.\n');
fprintf('[GUAM profile] Includes profiled startup/termination callbacks as well as timestep work.\n');
fprintf('[GUAM profile] Zero means no separately timed active blocks in that category.\n');
fprintf('[GUAM profile] Profiling adds overhead; component time need not equal execution wall time.\n');
fprintf('[GUAM profile] Files: %s_{components,blocks,accounting}.csv and %s_profile.mat\n', ...
    filePrefix, filePrefix);
end

function rows = collectNodes(node)
path = string(node.path);
rows = {path, classifyComponent(path), double(node.selfTime), ...
    double(node.totalTime), double(node.numberOfCalls)};
children = node.children;
for index = 1:numel(children)
    rows = [rows; collectNodes(children(index))]; %#ok<AGROW>
end
end

function component = classifyComponent(path)
% Match the most specific GUAM subsystem before matching its ancestors.
path = lower(regexprep(path, '\s+', ' '));
if ~contains(path, '/')
    component = "Simulation infrastructure";
elseif contains(path, 'turbulence') || contains(path, 'dryden')
    component = "Turbulence";
elseif contains(path, 'atmos76') || contains(path, 'atmosphere') || contains(path, '/atmos list')
    component = "Atmosphere";
elseif contains(path, '/environment')
    component = "Other environment";
elseif contains(path, 'reference inputs') || contains(path, 'genctrl inputs')
    component = "Reference inputs";
elseif contains(path, 'vehicle generalized control') || contains(path, 'lift+cruise control') || contains(path, '/baseline')
    component = "Flight control";
elseif contains(path, 'actuator dynamics') || contains(path, 'surfengref')
    component = "Actuators";
elseif contains(path, 'vehicle eom') || contains(path, 'vehicleeomref')
    component = "Equations of motion";
elseif contains(path, '/sensors')
    component = "Sensors";
elseif contains(path, '/powersystem')
    component = "Power system";
elseif contains(path, '/gearsystem')
    component = "Landing gear";
elseif contains(path, 'l+c polynomial model') || contains(path, '/aerodynamic forces')
    component = "Aerodynamics";
elseif contains(path, '/engine forces') || contains(path, '/propulsion forces') || contains(path, 'total angular momentum')
    component = "Propulsion";
elseif contains(path, 'propulsion and aerodynamic') || contains(path, 'aeropropref')
    % The S-function variant computes combined forces; do not invent a split.
    component = "Combined aero/propulsion";
elseif contains(path, 'simout') || contains(path, 'assertion')
    component = "Output and assertions";
else
    component = "Other model blocks";
end
end
