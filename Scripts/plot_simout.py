# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "matplotlib"]
# ///
"""Plot GUAM simulation truth signals in separate figure windows.

Run from the repository root:
    uv run Scripts/plot_simout.py Exec_Scripts/SimOut_case6.csv
    uv run Scripts/plot_simout.py output.csv --plots pos_vel attitude

Alternatively install numpy and matplotlib and use python3.
RUNME saves CSV alongside MAT. To export an existing result in MATLAB:
    loaded = load('Exec_Scripts/SimOut_case6.mat', 'SimOut');
    exportSimOutCsv(loaded.SimOut, 'Exec_Scripts/SimOut_case6.csv');

Edit AXES and PLOTS below to choose panels, fields/components, or units.
Paths are relative to SimOut; component indices are ZERO-BASED in Python.
Reads the compact 23-column CSV with a shared time_s column; no resampling.
Roll/pitch/yaw are derived from the scalar-first inertial-to-body quaternion
using the 3-2-1 Euler convention, in degrees. Quaternions are not plotted.
Motor speeds are already RPM.
The default units assume GUAM's feet/slug/second configuration.
"""

import argparse
import csv
from dataclasses import dataclass
from pathlib import Path
import sys

import numpy as np


@dataclass(frozen=True)
class Signal:
    path: str
    labels: tuple[str, ...]
    columns: tuple[int, ...] = ()  # Empty selects all components.
    scale: float = 1.0
    colors: tuple[str, ...] = ()
    euler: bool = False


@dataclass(frozen=True)
class Plot:
    title: str
    ylabel: str
    signals: tuple[Signal, ...]


XYZ = ("r", "g", "b")
DEGREES = 180.0 / np.pi
INERTIAL = "Vehicle.EOM.InertialData"
MOTOR_RPM = "Vehicle.PropAct.EngSpeed_rpm"

# Panels use logged plant truth; Euler angles are derived from Q_i2b.
AXES = {
    "pos": Plot("Position — inertial axes", "Position (ft)", (
        Signal(f"{INERTIAL}.Pos_bii", ("X / North", "Y / East", "Z / Down"), colors=XYZ),
    )),
    "vel": Plot("Velocity — inertial axes", "Velocity (ft/s)", (
        Signal(f"{INERTIAL}.Vel_bIi", ("Vx", "Vy", "Vz"), colors=XYZ),
    )),
    "euler": Plot("Euler angles — 3-2-1 roll, pitch, yaw", "Angle (deg)", (
        Signal(f"{INERTIAL}.Q_i2b", ("Roll", "Pitch", "Yaw"),
               scale=DEGREES, colors=XYZ, euler=True),
    )),
    "ang_vel": Plot("Angular velocity — body axes, relative to inertial", "Rate (deg/s)", (
        Signal(f"{INERTIAL}.Omeg_BIb", ("p", "q", "r"), scale=DEGREES, colors=XYZ),
    )),
    "hover_rpm": Plot("Lift motor speeds", "Motor speed (RPM)", (
        Signal(MOTOR_RPM, tuple(f"Rotor {i}" for i in range(1, 9)), tuple(range(8))),
    )),
    "pusher_rpm": Plot("Pusher motor speed", "Motor speed (RPM)", (
        Signal(MOTOR_RPM, ("Pusher (motor 9)",), (8,)),
    )),
}


# One entry = one figure with two vertically stacked, shared-time axes.
PLOTS = {
    "pos_vel": ("Position and velocity", ("pos", "vel")),
    "attitude": ("Angular velocity and Euler angles", ("ang_vel", "euler")),
    "motor_rpm": ("Lift and pusher motor speeds", ("hover_rpm", "pusher_rpm")),
}


def load_simout(path, signal_paths=None):
    """Read requested state/RPM signals with the shared simulation time."""
    path = Path(path)
    with path.open(newline="") as csv_file:
        reader = csv.reader(csv_file)
        headers = next(reader, [])
        if not headers or len(set(headers)) != len(headers):
            raise ValueError("CSV headers must be nonempty and unique.")
        columns = {name: index for index, name in enumerate(headers)}
        if "time_s" not in columns:
            raise ValueError("Compact CSV must contain the shared time_s column.")
        if signal_paths is None:
            signal_paths = [name.removesuffix(".Data[0]") for name in headers if name.endswith(".Data[0]")]
        selected = []
        layout = {}
        for signal in dict.fromkeys(signal_paths):
            if f"{signal}.Data[0]" not in columns:
                continue
            components = []
            index = 0
            while f"{signal}.Data[{index}]" in columns:
                components.append(columns[f"{signal}.Data[{index}]"])
                index += 1
            if not components:
                raise ValueError(f"{signal}: missing Data[0] column.")
            start = len(selected)
            selected.extend([columns["time_s"], *components])
            layout[signal] = slice(start, len(selected))
        if not selected:
            raise ValueError("No requested signal columns were found in the CSV.")
        # Convert only the selected numeric columns.
        rows = (",".join(row[index] for index in selected) for row in reader)
        try:
            values = np.loadtxt(rows, delimiter=",", ndmin=2)
        except IndexError as exc:
            raise ValueError("CSV row has fewer columns than its header.") from exc
    if not values.size:
        raise ValueError("CSV contains no samples.")
    return {signal: values[:, span] for signal, span in layout.items()}


def samples(root, path):
    """Return times and an N-sample by C-component array without resampling."""
    values = root[path]
    time, data = values[:, 0], values[:, 1:]
    if not len(time) or not np.all(np.isfinite(time)) or np.any(np.diff(time) < 0):
        raise ValueError(f"{path}: timestamps must be nonempty, finite, and nondecreasing.")
    return time, data


def quaternion_to_euler(data):
    """Convert scalar-first GUAM Q_i2b to 3-2-1 roll/pitch/yaw (radians)."""
    if data.shape[1] != 4:
        raise ValueError("Q_i2b must have four scalar-first quaternion components.")
    norms = np.linalg.norm(data, axis=1)
    if np.any(~np.isfinite(norms) | (norms == 0)):
        raise ValueError("Q_i2b must contain finite, nonzero quaternions.")
    w, x, y, z = (data / norms[:, None]).T
    roll = np.arctan2(2 * (w*x + y*z), 1 - 2 * (x*x + y*y))
    pitch = np.arcsin(np.clip(2 * (w*y - z*x), -1, 1))
    yaw = np.arctan2(2 * (w*z + x*y), 1 - 2 * (y*y + z*z))
    return np.column_stack((roll, pitch, yaw))


def make_figure(root, key, spec):
    title, panel_keys = spec
    # Read all fields before making a window so missing data skips a whole figure.
    panels = []
    for panel_key in panel_keys:
        panel = AXES[panel_key]
        series = []
        for signal in panel.signals:
            time, data = samples(root, signal.path)
            if signal.euler:
                data = quaternion_to_euler(data)
            columns = signal.columns or tuple(range(data.shape[1]))
            if len(signal.labels) != len(columns):
                raise ValueError(f"{key}: labels and selected components must have equal lengths.")
            if any(c < 0 or c >= data.shape[1] for c in columns):
                raise ValueError(f"{signal.path}: requested columns {columns}, shape is {data.shape}.")
            values = data[:, columns] * signal.scale
            for i, label in enumerate(signal.labels):
                finite = values[:, i][np.isfinite(values[:, i])]
                bounds = f"{finite.min():.6g} .. {finite.max():.6g}" if len(finite) else "no finite values"
                source = (f"Euler derived from CSV {signal.path}.Data[0:4]" if signal.euler
                          else f"CSV {signal.path}.Data[{columns[i]}]")
                print(f"{key}: {source} -> {label}: "
                      f"n={len(time)}, t={time[0]:.6g}..{time[-1]:.6g} s, "
                      f"range={bounds}, nonfinite={len(time)-len(finite)} (scale={signal.scale:g})")
            series.append((signal, time, values))
        panels.append((panel, series))

    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(len(panels), 1, num=title, figsize=(10, 8),
                             sharex=True, squeeze=False, layout="constrained")
    fig.suptitle(title)
    for ax, (panel, series) in zip(axes[:, 0], panels):
        for signal, time, values in series:
            for i, label in enumerate(signal.labels):
                color = {"color": signal.colors[i]} if signal.colors else {}
                ax.plot(time, values[:, i], label=label, **color)
        ax.set(title=panel.title, ylabel=panel.ylabel)
        ax.grid(True, alpha=0.35)
        ax.legend()
    axes[-1, 0].set_xlabel("Time (s)")
    return fig


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("csv_file", type=Path)
    parser.add_argument("--plots", nargs="+", choices=tuple(PLOTS), default=list(PLOTS))
    parser.add_argument("--save-dir", type=Path, help="Also save each figure as a PNG.")
    parser.add_argument("--no-show", action="store_true", help="Use a noninteractive backend (for batch export).")
    args = parser.parse_args()
    if args.no_show:
        import matplotlib
        matplotlib.use("Agg")
    try:
        root = load_simout(args.csv_file, [
            signal.path for key in args.plots for panel in PLOTS[key][1]
            for signal in AXES[panel].signals
        ])
    except (OSError, ValueError, KeyError) as exc:
        parser.exit(1, f"Error: {exc}\n")

    if args.save_dir:
        args.save_dir.mkdir(parents=True, exist_ok=True)
    count = 0
    for key in dict.fromkeys(args.plots):
        try:
            fig = make_figure(root, key, PLOTS[key])
        except KeyError as exc:
            print(f"Skipping {key}: missing field {exc}. This signal must be included in the exported CSV.", file=sys.stderr)
            continue
        except ValueError as exc:
            parser.exit(1, f"Error: {exc}\n")
        count += 1
        if args.save_dir:
            fig.savefig(args.save_dir / f"{key}.png", dpi=150)
    if not count:
        parser.exit(1, "No requested signals were available.\n")
    import matplotlib.pyplot as plt
    if not args.no_show:
        plt.show()
    else:
        plt.close("all")


if __name__ == "__main__":
    main()
