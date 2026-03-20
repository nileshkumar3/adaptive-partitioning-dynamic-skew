#!/usr/bin/env python3
"""Plot results: throughput bar chart and optional consumer lag time series."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


def load_kv_table(path: Path) -> list[tuple[str, float]]:
    rows: list[tuple[str, float]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = re.split(r"[\t,]+", line)
        if len(parts) < 2:
            continue
        key = parts[0].strip()
        try:
            val = float(parts[1])
        except ValueError:
            continue
        rows.append((key, val))
    return rows


def load_lag_timeseries(path: Path) -> tuple[list[float], list[float]]:
    ts: list[float] = []
    lag: list[float] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("unix_ts"):
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            parts = re.split(r"\s+", line)
        if len(parts) < 2:
            continue
        try:
            t0 = float(parts[0])
            lag0 = float(parts[1])
        except ValueError:
            continue
        ts.append(t0)
        lag.append(lag0)
    return ts, lag


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="Project root (contains results/)",
    )
    ap.add_argument(
        "--throughput-out",
        type=Path,
        default=None,
        help="Output PNG for throughput (default plots/throughput.png)",
    )
    ap.add_argument(
        "--lag-out",
        type=Path,
        default=None,
        help="Output PNG for lag series (default plots/lag.png)",
    )
    ap.add_argument(
        "--lag-ts",
        type=Path,
        default=None,
        help="Lag TSV path (default results/lag_timeseries.tsv)",
    )
    args = ap.parse_args()
    results = args.root / "results"
    tp_path = results / "throughput.txt"
    lag_path = args.lag_ts or (results / "lag_timeseries.tsv")

    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError as e:
        raise SystemExit("matplotlib is required: pip install matplotlib") from e

    plots_dir = args.root / "plots"
    plots_dir.mkdir(parents=True, exist_ok=True)

    if tp_path.is_file():
        data = load_kv_table(tp_path)
        if data:
            labels = [d[0] for d in data]
            vals = [d[1] for d in data]
            fig, ax = plt.subplots(figsize=(10, 4))
            ax.bar(range(len(labels)), vals, color="#2c6aa0")
            ax.set_xticks(range(len(labels)))
            ax.set_xticklabels(labels, rotation=35, ha="right")
            ax.set_ylabel("messages / s")
            ax.set_title("Throughput by scenario (throughput.txt)")
            fig.tight_layout()
            tout = args.throughput_out or (plots_dir / "throughput.png")
            fig.savefig(tout, dpi=150)
            print(f"wrote {tout}")
        else:
            print(f"skip throughput plot: no numeric rows in {tp_path}")
    else:
        print(f"skip throughput plot: missing {tp_path}")

    if lag_path.is_file():
        ts, lag = load_lag_timeseries(lag_path)
        if ts:
            t0 = ts[0]
            x = [t - t0 for t in ts]
            fig, ax = plt.subplots(figsize=(10, 4))
            ax.plot(x, lag, color="#a02c4e", linewidth=1.2)
            ax.set_xlabel("time (s) from first sample")
            ax.set_ylabel("total lag (messages)")
            ax.set_title("Consumer group lag (lag_timeseries.tsv)")
            fig.tight_layout()
            lout = args.lag_out or (plots_dir / "lag.png")
            fig.savefig(lout, dpi=150)
            print(f"wrote {lout}")
        else:
            print(f"skip lag plot: no rows in {lag_path}")
    else:
        print(f"skip lag plot: missing {lag_path}")


if __name__ == "__main__":
    main()
