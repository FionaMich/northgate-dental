"""Command line: `synthdata generate` writes SQL to stdout; `synthdata check-target` refuses unsafe databases."""

import argparse
import sys

from synthdata.generate import generate, to_sql
from synthdata.target import UnsafeTarget, check_target


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="synthdata", description="Synthetic dental data for Northgate Dental.")
    sub = parser.add_subparsers(dest="command", required=True)
    gen = sub.add_parser("generate", help="write idempotent SQL for synthetic patients to stdout")
    gen.add_argument("--patients", type=int, default=3000)
    gen.add_argument("--seed", type=int, default=2026)
    chk = sub.add_parser("check-target", help="exit 1 unless the database is staging or local")
    chk.add_argument("url")
    args = parser.parse_args(argv)

    if args.command == "check-target":
        try:
            check_target(args.url)
        except UnsafeTarget as e:
            print(f"refused: {e}", file=sys.stderr)  # never echo the URL, it contains a password
            return 1
        print("ok: target is staging or local")
        return 0

    sys.stdout.write(to_sql(generate(patients=args.patients, seed=args.seed)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
