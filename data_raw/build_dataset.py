#!/usr/bin/env python3
"""Build a clean, coherent F1 2024 dataset for modeling & simulation.

Sources (all real data, fetched from GitHub):
  - toUpperCase78/formula1-datasets  (race/qualifying/sprint/drivers/teams/calendar)
  - f1db/f1db release v2026.6.2       (pit stops, per-round championship standings)
No values are invented; this script only reshapes and joins the source CSVs.
"""
import csv, os, zipfile

RAW = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(RAW), "f1_2024_data")
F1DB = os.path.join(RAW, "f1db")
os.makedirs(OUT, exist_ok=True)

# Extract the f1db release zip on first run (the extracted folder is gitignored).
if not os.path.isdir(F1DB):
    with zipfile.ZipFile(os.path.join(RAW, "f1db-csv.zip")) as z:
        z.extractall(F1DB)


def read(name):
    with open(os.path.join(RAW, name), newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def read_f1db(name):
    with open(os.path.join(F1DB, name), newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def write(name, fieldnames, rows):
    with open(os.path.join(OUT, name), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)
    print(f"  wrote {name}: {len(rows)} rows")


# ---- Round <-> Track mapping (race results are already in chronological order) ----
race = read("Formula1_2024season_raceResults.csv")
track_order = []
for r in race:
    if r["Track"] not in track_order:
        track_order.append(r["Track"])
round_by_track = {t: i + 1 for i, t in enumerate(track_order)}
track_by_round = {i + 1: t for i, t in enumerate(track_order)}

calendar = read("Formula1_2024season_calendar.csv")
gp_by_round = {int(r["Round"]): r["GP Name"] for r in calendar}


def with_round(rows):
    """Prepend Round / GP Name to a Track-keyed table, sorted by round then position."""
    out = []
    for r in rows:
        rnd = round_by_track[r["Track"]]
        nr = {"Round": rnd, "GP Name": gp_by_round[rnd]}
        nr.update(r)
        out.append(nr)
    out.sort(key=lambda x: (x["Round"], int(x.get("Position", 0)) if str(x.get("Position", "")).isdigit() else 999))
    return out


print("Building core result tables...")
# 1. Race results
rows = with_round(race)
write("race_results.csv", ["Round", "GP Name"] + list(race[0].keys()), rows)

# 2. Qualifying results
q = read("Formula1_2024season_qualifyingResults.csv")
write("qualifying_results.csv", ["Round", "GP Name"] + list(q[0].keys()), with_round(q))

# 3. Sprint race results
sr = read("Formula1_2024season_sprintResults.csv")
write("sprint_results.csv", ["Round", "GP Name"] + list(sr[0].keys()), with_round(sr))

# 4. Sprint qualifying results
sq = read("Formula1_2024season_sprintQualifyingResults.csv")
write("sprint_qualifying_results.csv", ["Round", "GP Name"] + list(sq[0].keys()), with_round(sq))

# 5. Driver of the day
dotd = read("Formula1_2024season_driverOfTheDayVotes.csv")
write("driver_of_the_day.csv", ["Round", "GP Name"] + list(dotd[0].keys()), with_round(dotd))

print("Building reference tables...")
# 6. Circuits (calendar) + Track key for joining
circ = []
for r in calendar:
    rnd = int(r["Round"])
    nr = {"Track": track_by_round[rnd]}
    nr.update(r)
    circ.append(nr)
write("circuits.csv", ["Track"] + list(calendar[0].keys()), circ)

# 7. Drivers, 8. Teams (pass-through)
drv = read("Formula1_2024season_drivers.csv")
write("drivers.csv", list(drv[0].keys()), drv)
team = read("Formula1_2024season_teams.csv")
write("teams.csv", list(team[0].keys()), team)

print("Building f1db-derived tables (2024 only)...")
# name maps from f1db
drv_name = {r["id"]: r["fullName"] for r in read_f1db("f1db-drivers.csv")}
con_name = {r["id"]: r["name"] for r in read_f1db("f1db-constructors.csv")}
drv_abbr = {r["id"]: r["abbreviation"] for r in read_f1db("f1db-drivers.csv")}

# Consistent display names/numbers taken from the season drivers table so that
# every output joins cleanly on "Driver No" (number) or short driver name.
no_to_short = {r["No"]: r["Driver"] for r in drv}
abbr_to_short = {r["Abbreviation"]: r["Driver"] for r in drv}
abbr_to_no = {r["Abbreviation"]: r["No"] for r in drv}

# 9. Pit stops
pit_out = []
for r in read_f1db("f1db-races-pit-stops.csv"):
    if r["year"] != "2024":
        continue
    rnd = int(r["round"])
    millis = r["timeMillis"]
    pit_out.append({
        "Round": rnd,
        "GP Name": gp_by_round.get(rnd, ""),
        "Track": track_by_round.get(rnd, ""),
        "Driver No": r["driverNumber"],
        "Driver": no_to_short.get(r["driverNumber"], drv_name.get(r["driverId"], r["driverId"])),
        "Team": con_name.get(r["constructorId"], r["constructorId"]),
        "Stop": r["stop"],
        "Lap": r["lap"],
        "Duration(s)": round(int(millis) / 1000, 3) if millis else "",
    })
pit_out.sort(key=lambda x: (x["Round"], int(x["Driver No"]) if str(x["Driver No"]).isdigit() else 999, int(x["Stop"])))
write("pit_stops.csv", ["Round", "GP Name", "Track", "Driver No", "Driver", "Team", "Stop", "Lap", "Duration(s)"], pit_out)

# 10. Driver championship standings after each round
ds_out = []
for r in read_f1db("f1db-races-driver-standings.csv"):
    if r["year"] != "2024":
        continue
    rnd = int(r["round"])
    abbr = drv_abbr.get(r["driverId"], "")
    ds_out.append({
        "Round": rnd,
        "GP Name": gp_by_round.get(rnd, ""),
        "Position": r["positionNumber"],
        "Driver No": abbr_to_no.get(abbr, ""),
        "Driver": abbr_to_short.get(abbr, drv_name.get(r["driverId"], r["driverId"])),
        "Points": r["points"],
        "Championship Won": r["championshipWon"],
    })
ds_out.sort(key=lambda x: (x["Round"], int(x["Position"]) if str(x["Position"]).isdigit() else 999))
write("driver_standings_by_round.csv", ["Round", "GP Name", "Position", "Driver No", "Driver", "Points", "Championship Won"], ds_out)

# 11. Constructor championship standings after each round
cs_out = []
for r in read_f1db("f1db-races-constructor-standings.csv"):
    if r["year"] != "2024":
        continue
    rnd = int(r["round"])
    cs_out.append({
        "Round": rnd,
        "GP Name": gp_by_round.get(rnd, ""),
        "Position": r["positionNumber"],
        "Team": con_name.get(r["constructorId"], r["constructorId"]),
        "Engine": r["engineManufacturerId"],
        "Points": r["points"],
        "Championship Won": r["championshipWon"],
    })
cs_out.sort(key=lambda x: (x["Round"], int(x["Position"]) if str(x["Position"]).isdigit() else 999))
write("constructor_standings_by_round.csv", ["Round", "GP Name", "Position", "Team", "Engine", "Points", "Championship Won"], cs_out)

print("Done.")
