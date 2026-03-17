#!/usr/bin/env python3
from __future__ import annotations

import argparse
import io
import re
from pathlib import Path
from typing import Iterable

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


DEFAULT_RECORDS_DIR = Path("src") / "Data_records"
DEFAULT_DT_US = 100.0

UPPER_GATE_CHANNELS = [f"g_u_{index}" for index in range(1, 6)]
CAPACITOR_CHANNELS = [f"v_c_{index}" for index in range(1, 6)]
CURRENT_CHANNELS = ["i_u", "i_l"]
MODULE_COUNT_CHANNELS = ["N_u", "N_l"]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Plot the latest ScopeMimicry recording for the current MMC-arm firmware, "
            "or a specific record file."
        )
    )
    parser.add_argument(
        "record",
        nargs="?",
        type=Path,
        help="Path to a ScopeMimicry .txt record. Defaults to the newest file in src/Data_records.",
    )
    parser.add_argument(
        "--dt-us",
        type=float,
        default=DEFAULT_DT_US,
        help="Sampling period in microseconds used to build the time axis.",
    )
    parser.add_argument(
        "--save",
        action="store_true",
        help="Save the generated figure next to the record as a .png file.",
    )
    parser.add_argument(
        "--no-show",
        action="store_true",
        help="Build the figure without opening the matplotlib window.",
    )
    return parser.parse_args()


def find_latest_record(records_dir: Path) -> Path:
    if not records_dir.exists():
        raise FileNotFoundError(
            f"Folder not found: {records_dir}. Pass a record file explicitly."
        )

    records = sorted(
        [
            *records_dir.glob("*-record.txt"),
            *records_dir.glob("*-record.csv"),
        ],
        key=lambda path: path.stat().st_mtime,
    )
    if not records:
        raise FileNotFoundError(
            f"No ScopeMimicry record found in {records_dir}. Pass a record file explicitly."
        )
    return records[-1]


def cleanup_dataframe(df: pd.DataFrame) -> pd.DataFrame:
    unnamed_columns = [column for column in df.columns if str(column).startswith("Unnamed:")]
    if unnamed_columns:
        df = df.drop(columns=unnamed_columns)
    if df.columns.size > 0 and str(df.columns[0]).strip() == "":
        df = df.iloc[:, 1:]
    df.columns = [str(column).lstrip("#").strip() for column in df.columns]
    return df


def is_csv_like(lines: list[str]) -> bool:
    if not lines:
        return False
    first_line = lines[0].strip()
    normalized_first_line = first_line.lstrip("#").strip()
    if "," not in normalized_first_line:
        return False
    if len(lines) < 2:
        return True
    second_line = lines[1].strip()
    return "," in second_line


def load_csv_like_record(lines: list[str]) -> pd.DataFrame:
    normalized_lines = lines[:]
    if normalized_lines:
        normalized_lines[0] = normalized_lines[0].lstrip("#").strip()
    csv_buffer = io.StringIO("\n".join(normalized_lines))
    return cleanup_dataframe(pd.read_csv(csv_buffer))


def parse_scalar_line(value: str) -> float:
    stripped = value.strip()
    try:
        return float(stripped)
    except ValueError:
        normalized = re.sub(r"\.{2,}", ".", stripped)
        return float(normalized)


def is_integer_line(value: str) -> bool:
    stripped = value.strip()
    if not stripped:
        return False
    if stripped.startswith("#"):
        stripped = stripped[1:].strip()
    return re.fullmatch(r"[+-]?\d+", stripped) is not None


def load_scope_record(record_path: Path) -> pd.DataFrame:
    lines = record_path.read_text(encoding="utf-8").splitlines()

    if record_path.suffix.lower() == ".csv" or is_csv_like(lines):
        return load_csv_like_record(lines)

    if len(lines) < 3:
        raise ValueError(f"Invalid ScopeMimicry record: {record_path}")

    header = lines.pop(0).lstrip("#").strip()
    names = [name.strip() for name in header.split(",") if name.strip()]
    if not names:
        raise ValueError(f"Missing channel names in {record_path}")

    final_idx = None
    if lines and (lines[0].lstrip().startswith("#") or is_integer_line(lines[0])):
        final_idx = int(lines.pop(0).replace("#", "").strip())

    values_list: list[float] = []
    invalid_lines: list[tuple[int, str]] = []
    for line_index, line in enumerate(lines, start=3):
        if not line.strip():
            continue
        try:
            values_list.append(parse_scalar_line(line))
        except ValueError:
            values_list.append(np.nan)
            invalid_lines.append((line_index, line.strip()))

    if invalid_lines:
        print(
            f"Warning: {len(invalid_lines)} invalid samples found in {record_path.name}; "
            f"they were replaced with NaN."
        )

    values = np.asarray(values_list, dtype=float)
    channel_count = len(names)
    if values.size % channel_count != 0:
        valid_size = values.size - (values.size % channel_count)
        print(
            f"Warning: trimming {values.size - valid_size} trailing samples from {record_path.name} "
            f"to match {channel_count} channels."
        )
        values = values[:valid_size]

    data = values.reshape(-1, channel_count)
    if final_idx is not None and final_idx >= 0:
        data = np.roll(data, -(final_idx + 1), axis=0)

    return pd.DataFrame(data, columns=names)


def available_columns(df: pd.DataFrame, columns: Iterable[str]) -> list[str]:
    return [column for column in columns if column in df.columns]


def add_step_lines(ax: plt.Axes, x_axis: np.ndarray, df: pd.DataFrame, columns: list[str]) -> None:
    for column in columns:
        ax.step(x_axis, df[column], where="post", label=column, linewidth=1.4)


def add_digital_lines(ax: plt.Axes, x_axis: np.ndarray, df: pd.DataFrame, columns: list[str]) -> None:
    for offset, column in enumerate(columns):
        ax.step(
            x_axis,
            df[column] + offset,
            where="post",
            label=column,
            linewidth=1.4,
        )
    if columns:
        ax.set_yticks(np.arange(len(columns)) + 0.5, [column.replace("g_u_", "SM") for column in columns])


def plot_scope_record(df: pd.DataFrame, dt_us: float, title: str) -> plt.Figure:
    x_axis = np.arange(len(df)) * dt_us

    fig, axes = plt.subplots(4, 1, figsize=(14, 10), sharex=True, constrained_layout=True)
    fig.suptitle(title)

    module_columns = available_columns(df, MODULE_COUNT_CHANNELS)
    gate_columns = available_columns(df, UPPER_GATE_CHANNELS)
    capacitor_columns = available_columns(df, CAPACITOR_CHANNELS)
    current_columns = available_columns(df, CURRENT_CHANNELS)

    add_step_lines(axes[0], x_axis, df, module_columns)
    axes[0].set_ylabel("Modules")
    axes[0].set_title("Inserted submodules")

    add_digital_lines(axes[1], x_axis, df, gate_columns)
    axes[1].set_ylabel("Gate")
    axes[1].set_title("Upper-arm gate commands")

    add_step_lines(axes[2], x_axis, df, capacitor_columns)
    axes[2].set_ylabel("Voltage [V]")
    axes[2].set_title("Capacitor voltages")

    add_step_lines(axes[3], x_axis, df, current_columns)
    axes[3].set_ylabel("Current [A]")
    axes[3].set_xlabel(f"Time [{dt_us:.3f} us/sample]")
    axes[3].set_title("Arm currents")

    for ax in axes:
        ax.grid(True, alpha=0.3)
        handles, labels = ax.get_legend_handles_labels()
        if handles:
            ax.legend(loc="upper right", ncols=min(5, len(handles)))

    return fig


def main() -> int:
    args = parse_args()
    record_path = args.record if args.record else find_latest_record(DEFAULT_RECORDS_DIR)
    record_path = record_path.resolve()

    df = load_scope_record(record_path)
    fig = plot_scope_record(df, args.dt_us, record_path.name)

    if args.save:
        output_path = record_path.with_suffix(".png")
        fig.savefig(output_path, dpi=200)
        print(f"Saved plot to {output_path}")

    if not args.no_show:
        plt.show()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
