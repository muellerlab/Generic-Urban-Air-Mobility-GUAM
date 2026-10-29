# GUAM session notes — 27 October 2026

These notes cover the requested performance breakdown, implemented changes,
CSV output for Python, and the limitation on individual motor loads.

## Performance

The tested hover-to-hover flight covers 20,000 ft, accelerates at 2 ft/s² to
180 ft/s, decelerates back to hover, and holds for 40 seconds. It represents
241.11 seconds of flight, using a 0.005-second simulation step (200 Hz).
Many model blocks are evaluated multiple times per step: the separate profile
recorded approximately 144,672 calls for several major blocks over about
48,222 integration steps. A simple reference trajectory therefore still
requires repeated controller, force/moment, dynamics, and sensor calculations.

The benchmark used MATLAB R2025b through the existing MATLAB distrobox,
normal Simulink mode, full output logging, and disabled plots, result-file
saving, and profiling. Totals exclude MATLAB process startup and the
subsequent flight-analysis report.

| Workflow | Setup | Simulink initialization | Execution | Other overhead | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Original, first/cold run | 37.03 s | 178.18 s | 51.38 s | 3.29 s | 269.88 s |
| Original, warm run | 5.23 s | 10.86 s | 51.58 s | 1.96 s | 69.63 s |
| Headless, including preparation | 3.40 s | 12.19 s | 51.68 s | 3.08 s | 70.35 s |
| Headless, reusing preparation | 0.00 s | 4.50 s | 53.85 s | 2.10 s | 60.45 s |

Other overhead is the measured total minus setup, initialization, and execution;
it includes termination, output extraction, and surrounding MATLAB work.

| Stage | Share of warm original total | Share of reused headless total |
| --- | ---: | ---: |
| Setup | 7.5% | 0.0% |
| Simulink initialization | 15.6% | 7.4% |
| Execution | 74.1% | 89.1% |
| Other overhead | 2.8% | 3.5% |

Reusing preparation saved **9.18 seconds per flight, or 13.2%** relative to
the warm original workflow (1.15× throughput). Numerical execution remained
around 52 seconds; it did not become faster. The first headless run alone
gave no overall improvement. These are individual sequential measurements,
not a repeated statistical benchmark. The very slow cold initialization
should not be treated as a recurring cost or credited to the wrapper's speedup.

### What setup does

Setup configures MATLAB paths; selects model variants, units, and reference
inputs; initializes vehicle/environment data and parameters; creates typed
signal buses; and configures the output mapping. The original workflow also
rebuilds the output bus and saves the model. In the warm baseline, path/model
handling took 2.69 seconds and output-bus/model saving took 1.48 seconds.
In the cold run, those stages took 15.70 and 19.30 seconds respectively.
These are sub-stages of setup, not additional costs.

Simulink initialization is separate: it prepares the model for execution,
including resolving blocks, dimensions, types, sample times, and initial
conditions. The headless wrapper still performs initialization for each run;
it does not currently use Fast Restart.

### Component costs from a separate profiling run

The profiler recorded **58.60 seconds of additive block self time**. That
diagnostic run reported **88.55 seconds of Simulink execution wall time**
and **127.84 seconds for the complete workflow**, including setup, saving,
plots, and profiling reports. These are different measurements from the
unprofiled benchmark above.

| Component | Profiled self time | Share of captured self time | Captured time / diagnostic workflow total |
| --- | ---: | ---: | ---: |
| Flight controller | 17.59 s | 30.0% | 13.8% |
| Equations of motion and derived state calculations | 13.50 s | 23.0% | 10.6% |
| Simulation infrastructure | 10.86 s | 18.5% | 8.5% |
| Aerodynamics subsystem | 7.01 s | 12.0% | 5.5% |
| Sensors | 4.56 s | 7.8% | 3.6% |
| All other profiled categories | 5.08 s | 8.7% | 4.0% |
| Total captured self time | 58.60 s | 100.0% | 45.8% |

The last column is an accounting ratio against the **127.84-second diagnostic
run only**, not a component share of the 69.63- or 60.45-second benchmark.
The remainder includes work outside captured block self time and workflow
stages such as setup and postprocessing. Profiling itself adds overhead.
Captured callbacks also include block startup and termination, so these
component times cannot be added to the setup table as nonoverlapping stages.
We have not directly measured per-component seconds in the unprofiled run.

The controller is the largest measured category. Repeated gain/matrix
interpolation and longitudinal/lateral pseudoinverse allocation contribute
to that cost. The equations-of-motion category includes rigid-body dynamics,
coordinate transformations, and derived state quantities. Aerodynamics is
substantial but does not dominate this profile. Its polynomial-model category
includes propeller effects; the small separately classified propulsion cost
does not represent all propulsion-related computation.

## Implemented changes

- Added reusable preparation and execution functions: `prepareGuamHeadless.m`
  and `runGuamHeadless.m`, with trajectory validation in `guamHeadlessRefInput.m`.
  They avoid prompts, automatic plots/result saves, repeated vehicle setup,
  and saving the model during preparation. Full selected simulation logs remain
  available in memory. Integration settings and model fidelity were unchanged.
- Fixed trajectory-array bus dimensions so a prepared session accepts a
  different trajectory sample count. Added example, validation, and benchmark
  scripts under `Exec_Scripts/`.
- Added stage timing and component-profile reporting through `guamTiming.m`
  and `guamComponentTiming.m`. The current `RUNME.m` enables component profiling
  by default; disable it with `userStruct.profileComponents=false` for ordinary
  performance measurements. The headless runner disables profiling explicitly.
- Added CSV export alongside MAT saving and changed the Python reader to CSV.

## CSV output for Python

`RUNME.m` saves both `Exec_Scripts/SimOut_caseN.mat` and
`Exec_Scripts/SimOut_caseN.csv`. The MAT file retains the full selected debug
output. `exportSimOutCsv.m` writes a compact CSV; `Scripts/plot_simout.py`
reads it without a MATLAB-file reader library. The Python script uses standard
CSV parsing, NumPy, and Matplotlib. Headless runs save files only when requested
explicitly by the calling code.

The **current selection is 23 columns**. Further additions for debugging or
acoustics remain undecided.

| Signal | CSV field prefix/name | Columns | Units |
| --- | --- | ---: | --- |
| Shared simulation timestamp | `time_s` | 1 | s |
| Position, inertial axes | `Vehicle.EOM.InertialData.Pos_bii` | 3 | ft |
| Velocity, inertial axes | `Vehicle.EOM.InertialData.Vel_bIi` | 3 | ft/s |
| Attitude, inertial-to-body quaternion | `Vehicle.EOM.InertialData.Q_i2b` | 4 | dimensionless |
| Body angular rates relative to inertial frame | `Vehicle.EOM.InertialData.Omeg_BIb` | 3 | rad/s |
| Motor speeds: eight lift rotors and one pusher | `Vehicle.PropAct.EngSpeed_rpm` | 9 | RPM |

Vector headers append `.Data[0]`, `.Data[1]`, etc. Motor speed is converted
from the logged rad/s using `RPM = rad/s × 60 / (2π)`. All signals must share
identical timestamps; the exporter rejects a mismatched time grid and does
not resample. Coordinates retain GUAM's native frame conventions; in this
flat-world example, position corresponds to north/east/down.

The saved hover result produced **48,223 rows × 23 columns in 0.720 seconds**.
MATLAB validation checked all exported state/motor samples against the saved
MAT data, including ordering, timestamps, and RPM conversion. This required
no new flight simulation. Plot verification is outside the requested scope.

The initial full-debug CSV contained 1,807 columns (1,643 data components and
164 separate timestamp columns) and took approximately 44 seconds to export.
Controller internals, particularly allocation matrices, dominated its width.
The current compact exporter avoids that postprocessing cost. Neither CSV
export timing is included in the headless benchmark totals above. A separate
diagnostic workflow measured MAT saving at 5.60 seconds and plotting at
5.84 seconds; those are also excluded from the headless benchmark.

## Individual motor forces and acoustics

The active Lift+Cruise polynomial aerodynamic model provides **combined
aircraft forces and moments**, including propulsion effects. It acts as an
aggregate fitted model for this purpose; it does not expose a validated
decomposition into the actual load on each motor/rotor.

In the polynomial variant of `AeroPropRef.slx`, the separate propulsion
diagnostic bus is wired to constant zeros, including its per-rotor thrust
and torque fields. These zeros are placeholders, not evidence of zero thrust.
The equations of motion still receive the combined aircraft forces/moments.
Motor speeds are populated separately and remain usable.

`LpC_aero_p_v2.m` also calls isolated rotor/propeller routines, but uses the
difference between rotating-body and zero-angular-rate calculations as a
damping correction. Those internal estimates are not a demonstrated breakdown
of the total fitted aircraft loads. Simply exporting them would not establish
validated individual rotor loading for an acoustic model. Reliable per-rotor
thrust/shaft torque would require additional modeling, wiring, and validation.

## Measurement sources

- `results/headless_hover_benchmark.json` and `.log`: full-flight benchmark.
- `Exec_Scripts/benchmark_headless_hover.m`: benchmark procedure.
- `Exec_Scripts/timing_logs/tpe506afd6_b12f_4115_bc04_1015e83a61bc.csv`:
  diagnostic workflow stage timings; matching `_components.csv`, `_blocks.csv`,
  and `_accounting.csv` contain the component profile.
- `Exec_Scripts/validate_csv_export.m`: CSV data validation procedure.
- `vehicles/Lift+Cruise/AeroProp/Polynomial/LpC_aero_p_v2.m` and
  `vehicles/Lift+Cruise/Subsystems/AeroPropRef.slx`: aggregate-force computation
  and placeholder propulsion outputs.
