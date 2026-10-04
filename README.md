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

- **Flight** (v0.2): in-flight instruments.
  - **Vario**: phone barometer with a Kalman filter (GPS altitude if there is no barometer),
    calibrated on the launch height. Audio beeps get higher and faster with lift; a low tone
    sounds in strong sink.
  - Altitude, height above ground (Copernicus DEM via Open-Meteo), ground speed and track.
  - **Wind from drift while circling**, 30 s average climb, and the thermal average and gain.
  - **Glide**: current L/D, plus final glide to the nearest known landing field (needed L/D and
    arrival height including wind and a 150 m margin).
  - Voice callouts when leaving a thermal. Recording runs in the background (Android foreground
    service, iOS background location and audio) and auto-saves after landing.
- **Logbook** (v0.2):
  - recorded flights, plus **IGC import** (single files or the ZIP from XContest → My flights →
    Download: IGC)
  - statistics, thermals found in each flight, replay through the instruments (10×), and export as
    IGC or KML for Google Earth
  - every thermal is tagged with the weather of its hour (wind, cloud cover, temperature from
    ERA5), so the map can show **My thermals like today**: thermals you found in weather similar to
    the forecast (wind direction ±45°, wind speed ±10 km/h, cloud cover ±35 %)
- The kk7 **Hotspots/Skyways** layers follow the season and time of day (kk7 `jan/apr/jul/oct` ×
  morning/midday/evening after sunrise) instead of the whole year.

- **v0.3** additions:
  - **Landing fields** for every favourite takeoff (DHV/club data), used for final glide. Long-press
    the map to add your own takeoffs and landings.
  - **Settings**: pilot and glider (written into the IGC), polar, safety margin, vario
    thresholds and volume, voice, manual QNH.
  - **XC history (Leonardo)**: XC flights that started at a takeoff, by wind direction, cloud
    cover, takeoff time and month, and how many were flown in weather like today's.
  - **Airspace**: OpenAIR import or URL, map layer, warnings for inside, entry within 60 s and
    proximity, with voice.
  - **Bluetooth varios**: LK8EX1, LXWP0, XC Tracer, OpenVario, BlueFly, NMEA GPS. The
    device's pressure replaces the phone barometer.
  - **Thermal assistant**: drift-corrected lift map with an arrow to the core.
  - **Competition tasks**: XCTrack QR or `.xctsk` import, optimised route, start gates,
    turnpoints, ESS and goal with callouts, cylinders on the map.
  - **Instrument pages**: swipe between pages, tap the edit button to change, add or remove
    tiles (17 instruments).

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
dart run flutter_launcher_icons        # app icon from assets/icon/
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
