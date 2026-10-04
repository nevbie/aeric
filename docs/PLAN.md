# aeric: feature plan, feasibility and effort

aeric started as a **pre-flight** planner (flyability, live thermal estimates, thermal history).
This plan covers turning it into a full paragliding app that you also use **in the air** and
**after landing**, comparable to XCTrack, FlySkyHy, Burnair or SeeYou Navigator.

Effort is in **person-weeks for one experienced Flutter developer**. Feasibility:
- **High**: well understood, with building blocks available.
- **Medium**: doable, but needs real tuning, a backend, or platform workarounds.
- **Low**: hard to make reliable, or blocked by legal, data or platform problems.

## Already in the repository (v0.1)

| Area | Status |
|---|---|
| Flyability per site and hour, best window, site ranking | done (`lib/core/flyability.dart`, `day_planner.dart`) |
| Thermal estimate per hour from radiation, temperature, cloud cover, wind and wind direction | done (`thermal_model.dart`) |
| Live thermals: today so far vs. 5 years of history, percentile, trends, hourly history table | done (`live_thermal.dart`, `thermal_climatology.dart`) |
| Open-Meteo forecast + ERA5 archive clients, disk cache | done |
| CI: analyze, tests, Android APK, unsigned iOS build | done |

## Feature list

### In-flight core

| # | Feature | Feasibility | Effort | Notes |
|---|---|---|---|---|
| F1 | **Variometer** from the phone barometer + audio beeps | Medium | 2–3 | Pressure → altitude, then a Kalman filter. Fusing baro with the accelerometer gives a usable vario; a raw phone baro is too slow and noisy. **iOS:** `CMAltimeter` only delivers about 1 Hz, so it lags noticeably; recommend a Bluetooth vario (I1) for serious use. Tones: generate PCM in Dart (rising pitch and beep rate with climb, sink tone below a threshold) and play with low latency (`flutter_pcm_sound`/`flutter_soloud`). Needs background audio on iOS. |
| F2 | Altitude (GPS + baro, QNH setting), ground speed, heading/track | High | 1 | `geolocator` with best-for-navigation accuracy, plus the baro altitude. Needs an Android foreground service and the iOS "location" background mode. |
| F3 | **Thermal assistant**: map of lift around you while circling, centering aid, averaged climb | Medium | 2–3 | Pure maths: detect circling from the heading rate, keep the last ~60 s of (position, vario) samples drift-corrected by the wind (F4), and draw them coloured by climb. Shows the best-lift direction and an arrow to shift the circle. Averaging: 30 s and per-thermal average, and the climb gained in the current thermal. |
| F4 | **Wind from drift while circling** | High | 1 | Fit a circle to the ground-speed vectors of one or more full turns. Its centre offset is the wind vector (the standard method in XCTrack and LK8000). On straight flight, fall back to the min/max ground speed. |
| F5 | **Glide ratio, required L/D, final glide** to a goal or landing | High | 1–1.5 | Current L/D from ground speed / sink over 20–30 s. Required L/D = distance / (height − safety margin − goal elevation). Final glide uses the wind and a simple polar (trim speed and sink, set in settings). |
| F6 | **Customisable instrument screen** (widgets on pages) | Medium | 2–3 | Grid of resizable widgets (vario, altitude, AGL, ground speed, wind, L/D, thermal assistant, map, task, airspace), several pages, swipe to switch. Layouts saved as JSON so they can be shared. Big buttons and a high-contrast sunlight theme. |

### Navigation and competition

| # | Feature | Feasibility | Effort | Notes |
|---|---|---|---|---|
| N1 | Waypoints and routes | High | 1 | Import `.wpt`/`.cup` (SeeYou) and GPX, create on the map. |
| N2 | **Competition tasks**: SSS (exit/enter, start time/gates), turnpoint cylinders, ESS, goal (cylinder/line), deadline | Medium | 2–3 | Task state machine: which point is next, tagging cylinders, start gates. Must match the FAI/CIVL rules exactly, so test heavily with real tracks. |
| N3 | **Import tasks by QR code or file** (XCTrack format) | High | 1 | `.xctsk` is documented JSON; QR codes carry `XCTSK:` + compact JSON (v2 uses polyline encoding). Camera scanner via `mobile_scanner`. Also accept QR codes made by XCTrack and the task creator websites. |
| N4 | **Optimised route through the cylinders**, distance and time to the next point and goal | Medium | 1–2 | Iteratively find the touch point on each cylinder that shortens the path (standard approach), recomputed on each GPS fix from the current position. Time = distance / (ground speed toward the target, using the wind). |

### Safety and airspace

| # | Feature | Feasibility | Effort | Notes |
|---|---|---|---|---|
| S1 | **Airspace overlay (OpenAIR)** with horizontal and vertical distance warnings | Medium | 2–3 | OpenAIR parser (polygons, arcs `DA`/`DB`, circles; FL/AGL/MSL limits). Warnings use the predicted position in 30–60 s. AGL limits need terrain (S4). Data from openaip.net (free key, check the licence) or a user-supplied file. **Must be dependable:** extensive tests and a clear disclaimer. |
| S2 | **Live tracking** and sharing with friends or a retrieve driver | Medium | 3–5 | Needs a backend (e.g. Supabase or a small server), a share link and a viewer web page. Cheaper first step: send to existing services (XContest Live, FANET/OGN glider network) where their APIs allow it. |
| S3 | **Crash or no-movement detection with SOS** | Low/Medium | 3–5 | Detection is easy to prototype (sudden deceleration, then no movement) but hard to make reliable without false alarms. **Platform limits:** iOS does not let apps send SMS automatically, and Google Play restricts `SEND_SMS`. Realistic options: loud alarm and countdown, then a push/SMS **via the S2 backend** with the last position. Liability means it ships as a labelled aid. |
| S4 | **Terrain clearance and height above ground** | High | 1–2 | Height above ground = altitude − terrain elevation. Terrain from Copernicus DEM / SRTM tiles (30 m), downloaded per region and stored on the phone. Also feeds F5 (glide over terrain) and S1. |

### Maps and data

| # | Feature | Feasibility | Effort | Notes |
|---|---|---|---|---|
| D1 | **Offline topo maps** | Medium | 2–4 | `flutter_map` + vector or raster tiles stored offline (MBTiles/PMTiles). The tile provider must allow bulk downloads, so self-host (e.g. OpenTopoMap-style PMTiles per region) or license them. A 3D terrain view in Flutter is much harder (+4–6, e.g. via MapLibre native); a 2D map with hillshade covers most of the use. |
| D2 | **Thermal hotspot overlay** (kk7) | Medium | 0.5–1 | Technically just a tile overlay. **Licence:** thermal.kk7.ch tiles need permission for use in an app; ask the author first. Alternative: our own hotspots from public IGC tracks (much more work). |
| D3 | **Takeoff and landing database** | Medium | 1–3 | paraglidingearth.com has an API; DHV Geländedatenbank and other national databases have licence conditions to check. Add user-created sites with wind sector, elevation and notes, which also feed the Fly and Thermals tabs. |

### Weather and planning

| # | Feature | Feasibility | Effort | Notes |
|---|---|---|---|---|
| W1 | **Site forecast**: wind at altitude, cloud base, thermal strength (RASP / Meteo-Parapente style) | Medium | 2–4 | Partly done. Next: Open-Meteo pressure-level temperature and wind (1000–500 hPa) → an emagram per hour, thermal top via the parcel method instead of the surface-only estimate, wind-by-altitude chart, and a foehn warning (pressure difference across the Alps). |
| W2 | **Live wind stations** near takeoff | Medium | 1–2 | Holfuy, Windy stations, Pioupiou/OpenWindMap (open API), MeteoSwiss/ZAMG/DWD open data. Licences differ per network; start with the open ones. Also gives real measurements to correct the "now" thermal estimate. |
| W3 | Flyability score per site | High | done / 0.5 | Add a pilot level setting (beginner/intermediate/XC) that changes the thresholds. |

### After the flight

| # | Feature | Feasibility | Effort | Notes |
|---|---|---|---|---|
| A1 | **IGC recording and signing**, logbook, statistics | High (recording) / Medium (signing) | 1.5–2 | The IGC file writer is simple. Auto takeoff and landing detection. Logbook stored on the phone (`sqflite`/`drift`) with airtime, distance (free/FAI triangle), max altitude and max climb. **Signing:** a G-record needs your own key, and XContest only accepts it for **apps it has validated**, so ask XContest early. |
| A2 | **Upload to XContest** (and others), replay, 3D export (KML for Google Earth) | Medium | 1–3 | KML/KMZ export with an extruded track: 0.5. Replay on the map: 1. XContest upload: they have no open public API, so it needs their cooperation; the fallback is "share IGC" or opening their upload page. |

### Integrations

| # | Feature | Feasibility | Effort | Notes |
|---|---|---|---|---|
| I1 | **Bluetooth varios** (XC Tracer, Skytraxx, FlyMaster, BlueFly…) | Medium | 2–3 | Bluetooth LE via `flutter_blue_plus`; most send NMEA-style sentences (`LK8EX1`, `LXWP0`, `PRS`, `$XCTRC`, `POV`), so one parser handles many devices. Gives fast, accurate pressure (fixes F1's iOS problem) and often GPS. Testing needs the real devices. |
| I2 | Audio callouts (altitude, glide, airspace, task) | High | 0.5–1 | `flutter_tts`, mixed with the vario tones. |
| I3 | Watch apps (Garmin, Apple Watch) | Low/Medium | 4–8 each | Neither can be written in Flutter: Garmin needs Connect IQ (Monkey C), Apple Watch needs native SwiftUI + WatchConnectivity. Do this last. |

## Recommended order

Most in-flight logic is **pure maths** and can go into `lib/core/` with unit tests, like the
thermal model. That includes the vario filter, wind from circling, L/D and final glide, IGC
writer, OpenAIR parser, XCTrack task parser and route optimisation. It can be built and tested
before anyone flies with it.

1. **v0.2 Fly with it** (≈ 8–10 weeks): F2, F1 (phone barometer + tones), F4, F5, S4, A1 (recording
   + logbook, unsigned), a simple fixed instrument screen, I2. Track export as IGC/KML (part of A2).
2. **v0.3 XC** (≈ 8–10 weeks): S1 airspace, F3 thermal assistant, N1–N4 tasks with QR import and the
   optimised route, F6 customisable screens, I1 Bluetooth varios.
3. **v0.4 Maps and weather** (≈ 6–10 weeks): D1 offline topo, D3 site database, W1 emagram forecast,
   W2 wind stations (and use them in the live thermal estimate), D2 kk7 if allowed.
4. **v0.5 Connected** (≈ 6–12 weeks + backend): S2 live tracking, S3 SOS, A2 XContest/replay, signing,
   then I3 watch apps.

Total for everything: roughly **35–55 person-weeks**, plus running costs (backend, tiles, map data).

## Platform notes (Flutter, Android + iOS)

- **Background:** a flight runs 1–6 h with the screen often off. It needs an Android foreground
  service (`location`), the iOS `location` + `audio` background modes and a wakelock option.
  Battery testing is essential.
- **App store review:** apps with continuous background location get closer scrutiny. Justify it
  in the store listing (flight recording, vario).
- **Testing without flying:** replay recorded IGC files and sensor logs through the same pipeline
  (a "simulator" mode). This makes it possible to develop and test in CI.
- **Safety:** airspace, SOS and terrain features are aids. Label them clearly, and never present
  them as certified equipment.
