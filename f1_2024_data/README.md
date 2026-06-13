# F1 2024 Season Dataset — for Modeling & Simulation

Real 2024 Formula 1 data, reshaped into clean, join-friendly CSVs. **No values are
invented** — everything is pulled from public datasets and only reshaped/joined.

## Sources
- **[toUpperCase78/formula1-datasets](https://github.com/toUpperCase78/formula1-datasets)**
  — race, qualifying, sprint, drivers, teams, calendar (manually curated from official
  results).
- **[f1db/f1db](https://github.com/f1db/f1db)** release `v2026.6.2` — pit stops and
  per-round championship standings (open database, successor-grade to Ergast).

Both ultimately trace to official FIA/Formula1.com timing.

## Join keys
- **`Round`** (1–24) is the canonical race ordering — use it as the time axis for
  season-progression models.
- **`Track`** and **`GP Name`** identify the event; `circuits.csv` joins on `Track`.
- **`No`** (car number) / **`Driver`** (short name, e.g. *Max Verstappen*) are
  consistent across every table for clean joins.

## Files

| File | Rows | What it is |
|------|------|-----------|
| `race_results.csv` | 479 | Per-driver race finish: `Position, No, Driver, Team, Starting Grid, Laps, Time/Retired, Points, Set Fastest Lap, Fastest Lap Time` |
| `qualifying_results.csv` | 478 | Grid-setting quali: `Position, No, Driver, Team, Q1, Q2, Q3, Laps` |
| `sprint_results.csv` | 120 | Sprint race results (6 sprint weekends) |
| `sprint_qualifying_results.csv` | 120 | Sprint shootout (Q1/Q2/Q3) |
| `pit_stops.csv` | 825 | Every pit stop: `Stop, Lap, Duration(s)` per driver/race — strategy & stint modeling |
| `driver_standings_by_round.csv` | 519 | Cumulative driver championship points after each round |
| `constructor_standings_by_round.csv` | 240 | Cumulative constructor points (+ `Engine`) after each round |
| `circuits.csv` | 24 | Track features: `Number of Laps, Circuit Length(km), Race Distance(km), Lap Record, Turns, DRS Zones`, etc. |
| `drivers.csv` | 23 | Driver attributes: career podiums/points/championships, DOB, etc. |
| `teams.csv` | 9 | Team attributes: base, chassis, power unit, history |
| `driver_of_the_day.csv` | 24 | Fan-vote top-5 per race (engagement signal) |

## Modeling notes
- **Time/Retired** column mixes winner clock time (`1:31:44.742`), gaps (`+22.457`),
  lap-down (`+1 lap`) and DNF reasons (`DNF`, `Collision`, etc.) — parse before use.
- **Qualifying** Q1/Q2/Q3 are blank when a driver didn't reach that session — useful
  as a feature, but handle the missing values.
- **Starting Grid** can differ from quali position due to penalties — both are present
  so you can model the penalty delta.
- Lap-by-lap times and tyre-compound data are **not** included: those live only in the
  Ergast/Jolpica API, which was not reachable from this environment. Pit-stop laps +
  durations are the finest-grained timing data here.
- Suggested feature joins: `race_results` × `circuits` (track effects) ×
  `qualifying_results` (grid vs pace) × `pit_stops` (strategy) ×
  `driver_standings_by_round` (championship pressure / momentum).

## Rebuilding
`data_raw/build_dataset.py` regenerates everything from the raw source CSVs in
`data_raw/` (run `python3 data_raw/build_dataset.py`).
