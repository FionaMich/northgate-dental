# Northgate Dental

A dental practice system and patient app for a fictional US dental group with three locations: Back Bay, Cambridge and Quincy.

**All data in this project is synthetic.** No real patient data is used anywhere.

## What exists so far

- **Database (Supabase Postgres):**
  - organisation, locations, services and prices, staff, roster;
  - row level security on every table, and a second sign-in factor (2FA) required for staff;
  - an append-only audit log.
- **Synthetic data:** a Python generator that creates about 3,000 dental patients with visits, charts and treatment plans, plus named test personas and a canary record for leak scans.
- **Scheduling:**
  - appointments that cannot double-book a clinician or a room;
  - appointment history with version numbers;
  - patient linking with one-time codes, and parent access to a child's records;
  - available slots, 10-minute holds and self-booking.
- **CI:** six required checks on every pull request:
  - secret scan;
  - private file guard;
  - documentation style;
  - Conventional Commit titles;
  - database tests (pgTAP);
  - generator tests (pytest).

## Repository layout

| Path | What it holds |
| --- | --- |
| `supabase/migrations/` | Every database change, in order |
| `supabase/tests/` | pgTAP tests, including allowed and refused cases for each role |
| `supabase/seed.sql` | The organisation: locations, hours, rooms, services, prices and synthetic staff |
| `services/synthdata/` | Synthetic data generator (Python 3.12, uv) |
| `scripts/` | Local helpers: database tests, canary scan, mobile toolchain setup |
| `.github/workflows/` | CI, staging deploy and staging data load |

## Setting up a development machine

Tested on Ubuntu (x86_64).

### Database and generator

1. Install Docker, the [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started) and [uv](https://docs.astral.sh/uv/getting-started/installation/).
2. Run the database tests exactly as CI does:

   ```bash
   scripts/test-db.sh    # fresh database, migrations, seed, 50 generated patients, then every pgTAP test
   supabase stop         # free the memory afterwards
   ```

   The script starts only the Postgres container, not the whole Supabase stack, so it needs about 1.6 GB of disk for the image. Run it before every push that touches `supabase/`.
3. Run the generator tests:

   ```bash
   cd services/synthdata && uv run pytest
   ```

### Mobile toolchain (Flutter for Android)

One script installs everything the Flutter app needs to build Android APKs. It installs into `~/development` and needs no admin password:

```bash
scripts/setup-mobile.sh
source ~/.bashrc
flutter doctor
```

It installs:

| Tool | Version | Where |
| --- | --- | --- |
| Flutter SDK (includes Dart) | 3.50.0 stable | `~/development/flutter` |
| Temurin JDK | 17 | `~/development/jdk-17` |
| Android command-line tools, platform tools, Android 36 platform, build tools 36.0.0 | latest | `~/development/android-sdk` |

How it works:

- **Checksums:** every download is checked against its published checksum before it is unpacked.
- **Re-running:** running the script again skips the steps that are already done.
- **Environment:** it adds `JAVA_HOME`, `ANDROID_HOME` and the tool folders to `PATH` in `~/.bashrc`.
- **Licences and analytics:** it accepts the Android SDK licences and turns off Flutter and Dart analytics.

The Linux desktop build packages (clang, CMake, GTK) are not needed, because the app targets Android only. `flutter doctor` reports them as missing, and that warning can be ignored.

## Branches and pull requests

- **Branches:** work happens on `feat/...` branches.
- **Pull requests:** every pull request targets `develop` and is squash-merged once all six checks pass.
- **Releases:** `main` holds releases.
