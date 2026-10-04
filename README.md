# aeric

Paragliding-only planner, built with **Flutter** for Android and iOS. It is the flying half of
[ericapp](https://github.com/nevbie/ericapp), without the motorcycle parts, plus thermal
estimates.

- **Fly**: today, tomorrow or the day after, with sites ranked by their best flyable window. Each
  site gets an hourly traffic light with reasons (wind direction vs. launch sector, strength, gusts,
  wind aloft, rain, CAPE, cloud base) and an estimated thermal climb for each hour.
- **Favourites**: on first start these are the Northern Black Forest takeoffs: Loffenau Teufelsmühle (W, NW),
  Merkur (W, NE), Hornisgrinde Katzenkopf, and Oppenau (Rossbühl, Sandkopf, Schäfersfeld, Ibacher Holzplatz).
  The data comes from the DHV site database. Star a site to add or remove it; the Fly tab shows favourites
  by default.
- **Map** (Thermik-Karte, like ericapp): a topographic map (OpenTopoMap) with
  - a **thermal heatmap**: estimated climb on a 10×10 grid around the favourites, by hour or best hour of
    the day, for today and the next two days. 🔍 loads the grid for the visible area.
  - **Hotspots** and **Skyways**: historical thermals from thermal.kk7.ch, computed from XContest flights
    (non-commercial use only).
  - takeoff markers coloured by the day's best window (gold ring = favourite). Tap one for its window and
    **Live thermals**.
- **Thermals**: a live thermal estimate for the selected site:
  - **Now**: estimated climb, updraft w\*, thermal top or cumulus base, height above takeoff,
    temperature, cloud cover, wind, and sun on the ground.
  - **Trends** from the last hours: heating rate, clouds building or clearing, wind picking up,
    when today's peak comes and how long thermals stay usable.
  - **Today vs. history**: temperature, cloud cover and wind compared with the same hour in the
    same season of previous years. Shows how today's thermals rank against those days
    (percentile), with an hour-by-hour chart of today against the historical median and middle 50 %.
  - **Thermal climatology**: for each hour of the day over the last 5 years (±15 days around
    today): median climb, share of days with usable thermals, mean temperature, cloud cover,
    mean wind speed with prevailing direction, and median thermal top.

## How thermals are inferred

Historical hours (Open-Meteo ERA5 archive) and today's hours (Open-Meteo forecast, including the
already elapsed hours via `past_days=1`) run through the same model. That keeps the comparison
fair (`lib/core/thermal_model.dart`):

1. **Sun on the ground**: modelled shortwave radiation, or clear-sky radiation (sun position)
   reduced by **cloud cover** (Kasten & Czeplak).
2. **Heat flux** H ≈ 30 % of the radiation.
3. **Thermal depth**: how far the morning stable layer has been eroded. This is the geometric
   mean of two estimates. One comes from the heat accumulated since sunrise (encroachment
   model). The other comes from the observed **temperature** rise since the morning minimum. The
   depth is capped at the cumulus base, (T − dew point) × 125 m.
4. **Updraft** w\* = (g/T · H/ρcₚ · depth)^⅓ (Deardorff), weakened in strong **wind**. Climb is
   about 1.5 w\* minus the glider's sink. **Wind direction** flags the lee side of the launch.

The estimates are uncertain (easily ±50 %). Treat them as a relative guide (today against
another day, one hour against another), not as a vario reading.

## Build

The repo contains only `lib/`, `test/` and `pubspec.yaml`. The platform folders are generated:

```sh
flutter pub get
flutter analyze && flutter test        # logic + widget smoke test
flutter create --platforms=android,ios --org com.nevbie --project-name aeric .
python3 tool/patch_platforms.py
flutter build apk --release            # Android
flutter build ios --release            # iOS (needs macOS + Xcode; signing for devices)
```

GitHub Actions runs analyze and tests on every push. It also builds the Android APK (uploaded as
an artifact) and an unsigned iOS build to prove the iOS target compiles.

See **[docs/PLAN.md](docs/PLAN.md)** for the roadmap (in-flight vario, thermal assistant, tasks, airspace, IGC logbook, …).

## Layout

- `lib/core/` is pure Dart, unit-tested and free of Flutter imports: Open-Meteo forecast and
  archive clients, flyability rules, day planner, sun position, thermal model, climatology, live
  inference, sample sites.
- `lib/services/` handles HTTP, the disk cache for the immutable archive responses, and app state.
- `lib/ui/` has the Fly and Thermals screens.

Data: weather from [Open-Meteo](https://open-meteo.com) (forecast and historical ERA5). Using it
without a key is free for non-commercial use only; a commercial release needs their paid plan.

> Planning aid only. Always judge conditions on site and follow local rules and airspace.
