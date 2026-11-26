# Project Attribution & Personal Contributions

[← Back to README](README.md)

| | |
| :--- | :--- |
| **Project** | AT89S52 three-axis claw machine |
| **Course** | EEEN213 The Experiment of Micro-Processor System, Department of Electrical Engineering, Feng Chia University |
| **Built** | June 2023 (sophomore year, Spring 2023 semester; second semester of academic year 111) |
| **Recognition** | 2nd Place, Microprocessor Final Project Competition |
| **Team** | 5 undergraduate students |
| **Repository** | Reconstructed and documented in 2026 |

Names and student IDs of teammates and faculty are omitted for privacy.

---

## Contribution Labels

| Label | Meaning |
| :--- | :--- |
| **Lead** | I carried out the main work; teammates assisted at times |
| **Shared** | Done jointly with one or more teammates |
| **Team** | Whole-team effort; I was one of several contributors |
| **Sole** | Done entirely by me |

---

## My Contributions

| Area | Label | What I did |
| :--- | :---: | :--- |
| PCB fabrication & soldering | **Lead** | Ran the photolithographic fabrication workflow for all four boards (UV exposure, development, CuCl₂ etching, shearing, drilling) and hand-soldered the components, including the 24 TO-220 transistors. Process details: [hardware_and_pcb.md §7](docs/hardware_and_pcb.md#7-pcb-layout--fabrication) |
| Schematic capture & PCB layout | **Shared** | Drew and reviewed the OrCAD Capture schematics and Layout routing for the main board and the H-bridge driver boards |
| Thermal retrofit | **Team** | Helped fit the heatsinks, the sidewall fan, and the ventilation openings after the motors weakened in long enclosed runs |
| Integration & testing | **Team** | Took part in continuity checks, system wiring, three-axis motion and claw tests, limit-switch homing checks, and fixing wiring faults (loose jumpers, common-ground problems, shorts) |
| 2026 documentation & analysis | **Sole** | This repository: English documentation, diagrams, the annotated H-bridge schematic, the power/thermal analysis in [thermal_troubleshooting.md](docs/thermal_troubleshooting.md) with its ngspice DC model of the H-bridges ([`analysis/`](analysis/hbridge_dc_sim.py)), and the firmware review in [firmware_and_control.md](docs/firmware_and_control.md) |

---

## Team Scope (Not Claimed as My Work)

These parts were delivered by teammates or by the team as a whole, and are documented here for completeness:

- **Mechanical build:** salvaged Delta 3D-printer rails, laser-cut cabinet and console, 3D-printed claw
- **Firmware:** the 8051 assembly program in [`src/claw_machine.asm`](src/claw_machine.asm)
- **Coin detection:** selection and testing of the IR coin sensor

---

All rights reserved. No open-source license is provided.
