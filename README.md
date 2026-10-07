# QuantumDock

> **QUANTUM-DOCK: DeepSpace OS** is a tactical space navigation and orbital mechanics simulator developed natively in Lazarus/Free Pascal. 

Players must navigate a fragile cargo module to a moving space station using realistic Keplerian physics. Manage thrust, fuel, avionics battery, and hull integrity through a custom-rendered, retro-industrial tactical terminal interface. 

This is not a casual arcade game; it's a hardcore survival simulation where every orbital burn counts.

---

## ✨ Key Features

* **Multithreaded Keplerian Physics Engine:** Accurate gravitational pull, orbital velocities, and trajectory simulations running on a dedicated background thread.
* **Ghost Trajectory Prediction:** Plan your maneuvers using UI sliders to visualize your future orbit (burn nodes and free-coast trajectories) before executing them.
* **Hardcore Resource Management:**
  * **Fuel:** Finite resource. Requires intercepting random orbital fuel capsules to survive long missions.
  * **Battery:** Avionics constantly drain power. Prolonged drifting results in a dead ship.
  * **Hull Integrity:** Approaching the planet's atmosphere or the edge of the radar screen causes rapid structural decay.
* **Relative Velocity Docking:** Success requires matching the station's orbital speed and trajectory. Hitting the docking port at a relative velocity > 100 m/s will result in a critical hull breach.
* **Custom UI & Rendering:** Built entirely using `BGRABitmap` for off-screen buffered rendering, featuring CRT scanlines, glitch effects, and tactical geometries.
* **SQLite Telemetry Logging:** Background queue-based SQLite integration that logs your mission parameters, maneuver commands, and success/failure rates into `telemetry.db`.

---

## 📸 Screenshots




---

## ⚙️ Compilation & Setup

To compile and run this project from the source code, you need:

1. **Lazarus IDE** (v2.2.0 or newer recommended) / Free Pascal Compiler.
2. **BGRABitmap Package:** Install via Lazarus Online Package Manager (OPM).
3. **External DLLs:**
   * `sqlite3.dll` (for telemetry database).
   * `bass.dll` (for audio engine).
   * *Make sure to place these DLLs in the same directory as the compiled executable.*

**Build Instructions:**
1. Clone this repository: `git clone https://github.com/YourUsername/Quantum-Dock.git`
2. Open `QuantumDock.lpi` in Lazarus.
3. Hit `F9` to Compile and Run.

---

## 🕹️ How to Play

1. **Analyze the Orbit:** Observe the relative positions of the Cargo (Cyan) and the Station (Orange).
2. **Plan the Burn:** Use the `Power` and `Angle` sliders. Watch the Ghost Trajectory line to predict where your maneuver will take you.
3. **Execute:** Choose a burn duration (10s, 30s, 60s, or Custom) and hit **EXECUTE**.
4. **Intercept Fuel:** If a blue diamond (Fuel Capsule) appears, adjust your orbit to intercept it before your fuel runs out.
5. **Match Velocity:** Do not fly straight into the station! Ensure your **Rel.Vel** (Relative Velocity) is below `100.0 m/s` (turns green) before entering the station's docking radius.

---

