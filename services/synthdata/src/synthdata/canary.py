"""Canary values: planted in one synthetic patient so any leak scan can prove they never escape (E26).

canary.txt is the single source; scripts/canary-scan.sh reads the same file.
"""

from pathlib import Path

CANARY_VALUES = [v for v in (Path(__file__).with_name("canary.txt").read_text().splitlines()) if v.strip()]
