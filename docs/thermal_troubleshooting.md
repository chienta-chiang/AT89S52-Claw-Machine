# Thermal Troubleshooting & Power-Electronics Case Study

[← Back to README](../README.md)

| Stage | Summary |
| :--- | :--- |
| [1. Observed problem](#1-observed-problem) | Stepper motors gradually weakened during long runs in the closed cabinet |
| [2. Investigation](#2-investigation) | The uncooled TO-220 driver transistors in the sealed electronics bay were hot to the touch |
| [3. Implemented solution](#3-implemented-solution) | 24 TO-220 heatsinks, a sidewall cooling fan, ventilation openings |
| [4. Observed outcome](#4-observed-outcome) | Symptom did not recur in later integration tests or during the competition |
| [5. 2026 analysis](#5-2026-analysis-why-the-drivers-ran-hot) | Bridge cannot switch cleanly (cross-coupled low side, high-side PNP turn-off), supply in current limit, MCU pin overload, no freewheeling diodes, firmware drive timing, missing decoupling |
| [6. Proposed redesign](#6-proposed-redesign) | Two versions: within the 2023 no-driver-IC rule, and without it |

> [!NOTE]
> **Method.** Sections 1–4 describe the 2023 build. Section 5 is a 2026 analysis derived from the schematic, the bench-supply settings, component datasheets, the firmware, and a DC circuit model ([`analysis/hbridge_dc_sim.py`](../analysis/hbridge_dc_sim.py), output in [`analysis/sim_output.txt`](../analysis/sim_output.txt)). No temperatures, currents, voltages, or waveforms were measured in 2023, and nobody recorded whether the bench supply was in current limit. Figures in §5 are estimates and model results, not measurements.

---

## 1. Observed Problem

Each axis worked in short bench tests with the cabinet open. After several consecutive games with the cabinet closed, the stepper motors moved sluggishly and lost torque.

## 2. Investigation

The three H-bridge boards sit in a closed wooden/acrylic bay under the prize floor. The 24 TO-220 transistors had no heatsinks and were hot to the touch. With no airflow through the bay, heat from the driver stage had nowhere to go.

## 3. Implemented Solution

![Driver boards with heatsinks and the sidewall fan](images/internal_pcbs_and_cooling.png)

1. **Heatsinks:** a finned aluminum heatsink on every MJE2955T and MJE3055T (8 per board, 24 in total). Each heatsink came with a pre-applied double-sided adhesive thermal pad and was stuck directly onto one transistor's tab; no screws, mica washers, or separate insulators were used.
2. **Forced air:** a SUPERRED CHB7012EBS-OA-P fan (12 V, 0.28 A) on the cabinet sidewall. Only the 15 V / 1.0 A channel of the bench supply was free, so the fan ran from it directly, 25% above its 12 V rating.
3. **Ventilation:** openings in the cabinet panel so the fan could move air across the driver boards.

**Electrical isolation of the heatsinks.** A TO-220 tab is connected to the collector, and in this bridge every collector is a motor output node. The adhesive pads were not specified as electrical insulators, so each heatsink should be treated as live. The heatsinks are mounted one per transistor and, as far as the photo shows, do not touch each other. Contact between the two transistors of one leg would be harmless (both collectors are the same output node), but contact between legs or boards would short two outputs.

## 4. Observed Outcome

| Aspect | Before | After |
| :--- | :--- | :--- |
| Driver cooling | Bare TO-220 packages | 24 heatsinks + sidewall fan |
| Bay airflow | Sealed | Fan + vents |
| Behavior | Motors weakened over continuous runs | Symptom did not recur in later tests or during competition judging |

This is a qualitative observation, not a controlled comparison: the number of consecutive games, the room temperature, and the duty cycle were not recorded before or after the retrofit, so the later runs may also have been shorter or cooler.

---

## 5. 2026 Analysis: Why the Drivers Ran Hot

The cooling retrofit treated the symptom. Looking back at the circuit, the way the bridges were biased and switched points to the drive stage itself as the main heat source.

**Circuit.** The H-bridge is drawn in [hardware_and_pcb.md §4](hardware_and_pcb.md#4-discrete-bjt-h-bridge-driver) ([annotated schematic](images/bjt_hbridge_schematic_annotated.png)). The MCU drives only the two high-side PNP bases, each through 1 kΩ. Each output node drives the *opposite* low-side NPN base through 1 kΩ (cross-coupling). The 3 Ω winding sits between OUT A and OUT B.

### 5.1 The bridge could not switch cleanly

Two faults compound. The first is built into the topology and is present even at the intended 5 V; the second appears only because the rail was raised to 15.1 V.

#### Fault 1: the cross-coupled low side cannot saturate

Take input `(1, 0)`: the left PNP is on, current should flow OUT A → winding → OUT B → right NPN, and the left NPN should be off.

- The left NPN's base is fed from OUT B, so it stays off only if OUT B is below about 0.6 V.
- Then OUT A can be at most 0.6 V + I<sub>W</sub>R<sub>W</sub>, and the right NPN, whose base is fed from OUT A, gets at most about I<sub>W</sub>R<sub>W</sub> / R<sub>B</sub> of base current.
- To sink the winding current it needs β · I<sub>W</sub>R<sub>W</sub> / R<sub>B</sub> ≥ I<sub>W</sub>, that is

$$\beta \gtrsim \frac{R_B}{R_W} = \frac{1\text{ k}\Omega}{3\ \Omega} \approx 330$$

The MJE3055T is specified at h<sub>FE</sub> = 20–70 at 4 A; even allowing a higher gain at lower current, it is far short of 330. The low side therefore settles in its linear region: OUT B sits a few volts above ground, the "off" left NPN conducts, and part of the current from the left PNP flows straight to ground without entering the winding.

The DC model puts numbers on this. At the intended **+5 V** rail with a perfect 5 V logic drive (the high-side PNP that should be off is fully off), **42–45% of the bridge current bypasses the winding**, and the winding gets only **0.06–0.19 A** against its 1.2 A rating (h<sub>FE</sub> swept 30–100). That is consistent with the team's experience that the motors lacked torque at 5 V. The design was based on an online reference circuit ([hardware_and_pcb.md §8](hardware_and_pcb.md#8-references)); the gain requirement above shows that, with these parts and a 3 Ω load, the topology cannot work as a saturated switch.

#### Fault 2: at 15.1 V the high-side PNPs could not turn off

The schematic labels the H-bridge rail **+5 V** and connects each AT89S52 pin straight to a PNP base through 1 kΩ, with no level shifter. On the bench, that rail was set to **15.1 V with a 1.56 A current limit**. These settings were kept fixed for every test and for the competition demo.

**At the intended +5 V,** base current would be only

$$I_B \approx \frac{5.0 - 0.7}{1\text{ k}\Omega} = 4.3\text{ mA}$$

The datasheet specifies h<sub>FE</sub> = 20–70 only at I<sub>C</sub> = 4 A; at lower currents a power BJT's gain is typically higher. Even assuming a gain of 100, 4.3 mA of base current supports only about 0.43 A of collector current, well below the motors' 1.2 A rating. The team raised the rail to 15.1 V because the motors lacked torque at 5 V.

**At a 15.1 V rail,** the PNP emitter sits well above the MCU's logic-high level. The figures below assume the rail actually stays at 15.1 V and a logic-low pin sits at 0 V; both assumptions are revisited next, so these are **nominal upper bounds**, not operating points.

- **Pin low:** $I_B \le (15.1 - 0.7 - 0)/1\text{ k}\Omega = 14.4\text{ mA}$, so the PNP is on, as intended. A real pin sinking this much current is no longer at 0 V (the datasheet guarantees V<sub>OL</sub> = 0.45 V only at 1.6 mA), which lowers the figure.
- **Pin high:** an 8051 pin written high has only a weak pull-up. Current from the PNP base pulls the pin above V<sub>CC</sub> until its upper protection diode clamps it near V<sub>CC</sub> + 0.6 V. With V<sub>CC</sub> at 6.6 V (§5.2), the pin clamps near 7.2 V (or ≈ 5.6 V at a nominal 5 V V<sub>CC</sub>), giving

$$I_B \le \frac{15.1 - 0.7 - 7.2}{1\text{ k}\Omega} \approx 7.2\text{ mA}\quad(\approx 8.8\text{ mA at }V_{\text{CC}} = 5\text{ V})$$

So the "off" PNP still conducts, and up to about 7.2–8.8 mA per pin is pushed back into the logic supply. This mechanism exists only while the rail is above roughly 7.9 V (the 7.2 V clamp plus one V<sub>BE</sub>).

#### Consequence: the supply was almost certainly in current limit

With both faults, every driven bridge passes shoot-through current from rail to ground, and the Z bridges at `1111` do too whenever the rail is above about 7.9 V. At idle the four X/Y bridges hold a drive pattern and the two Z bridges sit at `1111` (§5.5). In the DC model, these six bridges would draw **3.1–9.8 A at 15.1 V**, two to six times the 1.56 A limit, for any gain from 30 to 100. A bench supply cannot deliver that; it leaves constant-voltage mode, holds 1.56 A, and lets its output fall. The model places the rail at **about 6–10 V at idle and 4–9 V while Z moves**.

Whether the supply's CC indicator was lit in 2023 is not known, so this is a strong inference rather than an observation. It matters for every number in §5.2–§5.3: the 15.1 V figures are upper bounds, and the model's current-limited operating point is the better estimate. At that point:

| Quantity (current-limited model, h<sub>FE</sub> 30–100) | Value |
| :--- | :---: |
| Motor rail | ≈ 4–10 V |
| Current per logic-low pin | 3–9 mA (V<sub>OL</sub> ≈ 0.2–1.3 V) |
| Back-feed per logic-high pin | 0–2.4 mA |
| Winding current per driven winding | 0.09–0.22 A |

Of the 1.56 A, only a small fraction reaches the windings; the rest is shoot-through in the bridges.

### 5.2 MCU pin loading and logic supply

Per the AT89S52 datasheet, steady-state sink current is limited to **10 mA per pin**, **15 mA per 8-bit port** (ports 1–3), and **71 mA for all pins combined**. The logic channel (CH1, 6.6 V) feeds the AT89S52 directly with no regulator, so V<sub>CC</sub> is 6.6 V rather than 5 V, exactly the datasheet's absolute maximum rating. The SG90 servo shares the same rail. Rail settings and component ratings are in [hardware_and_pcb.md §2](hardware_and_pcb.md#2-power-distribution).

| Case | Nominal upper bound (15.1 V rail, V<sub>OL</sub> = 0) | Current-limited model | Limit |
| :--- | :---: | :---: | :---: |
| One pin low | 14.4 mA (1.4× limit) | 3–9 mA | 10 mA per pin |
| Port 2 (X + Y, 4 pins low) | 57.6 mA (3.8× limit) | 12–36 mA (19–36 mA at idle, 1.3–2.4× limit; 12–31 mA while Z moves) | 15 mA per port |
| Whole chip (Z also moving, 6 pins low) | 86.4 mA (1.2× limit) | 19–47 mA | 71 mA total |

**Why the MCU survived.** At the nominal bound, eight logic-high pins (four on Port 2, four on the Z port at `1111`) would each push about 7.2 mA, roughly 58 mA in total, back into the 6.6 V rail. That is comparable to everything the rail feeds, and a linear bench supply can source current but cannot sink it, so the rail could have been pushed above 6.6 V. The current-limited operating point removes most of this: with the motor rail at 4–10 V, the back-feed falls to 0–2.4 mA per pin, and the per-pin sink current falls to within the 10 mA rating. At idle, Port 2 most likely still exceeded its 15 mA port limit, but by far less than the nominal 3.8×; while Z moves, the model brackets it on both sides of the limit. This is a plausible explanation for why the AT89S52 showed no failures or latch-up during the competition, not a verified one.

### 5.3 Power budget and junction temperature

**Input power.** Because the bridges pass shoot-through current (§5.1) and the X/Y bridges stay energized at idle (§5.5), the motor rail draws current continuously. The supply settings give a hard upper bound that holds whatever the operating point:

$$P_{\text{in}} \le 15.1\text{ V} \times 1.56\text{ A} \approx 23.6\text{ W}$$

If the supply was in current limit (§5.1), the rail was lower and so was the power: the model gives **6–16 W**. This power splits as

$$P_{\text{in}} = P_{\text{BJT}} + P_{\text{base}} + P_{\text{winding}} + P_{\text{other}}$$

**Windings.** Every winding current is drawn from the same 1.56 A rail, so the windings together can never carry more than 1.56 A. If all of it were shared equally and none went to shoot-through, copper loss in the 3 Ω windings would be (1.56 A / n)² × 3 Ω × n: about 1.2 W across six windings or 1.8 W across four. Because most of the current is shoot-through, the model gives only 0.1–0.6 W.

**Base resistors.** At the nominal 15.1 V bound, a 1 kΩ base resistor on a logic-low pin dissipates (14.4 mA)² × 1 kΩ ≈ 0.21 W, close to the 0.25 W rating of a standard ¼ W resistor. At the current-limited point the model gives 0.1–0.6 W for all 24 base resistors together.

**Transistors.** Nearly all the input power ends up in the transistors: the model gives **6–15 W** in total. Since winding and other losses cannot be negative, the assumption-free bound remains P<sub>BJT</sub> ≤ P<sub>in</sub> ≤ 23.6 W.

**Per-transistor dissipation.** The 24 transistors do not share this power equally. In the model the average is **0.24–0.64 W** per transistor, and the hottest device, the conducting high-side PNP of a driven bridge (which is not saturated, §5.1), dissipates up to about **1.3 W**.

**Junction temperature.** T<sub>J</sub> = T<sub>amb</sub> + P × R<sub>θJA</sub>.

- *Before the retrofit:* R<sub>θJA</sub> ≈ 62.5 °C/W, the MJE2955T datasheet value for a single device in still free air, with the bay assumed at 40 °C. Twenty-four devices in a sealed box heat each other and the air around them, so both assumptions are optimistic: the "before" column is a **lower bound**.
- *After the retrofit:* heatsink, adhesive thermal pad, and forced air, assumed R<sub>θJA</sub> ≈ 15–25 °C/W (including the pad's interface resistance, which is higher than screwed mounting with thermal grease) and bay air at 25–30 °C. This is a rough range, not a datasheet figure.

| Assumed dissipation per transistor | Before retrofit (lower bound) | After retrofit |
| :--- | :---: | :---: |
| 0.25 W (lightly loaded device) | ≈ 56 °C | ≈ 29–36 °C |
| 0.65 W (model average, upper end) | ≈ 81 °C | ≈ 35–46 °C |
| 1.3 W (hottest device in the model) | ≈ 121 °C | ≈ 45–63 °C |

**What the scenarios show.** Without cooling, the hottest devices were likely above 100 °C and possibly closer to the 150 °C junction limit once heat build-up in the sealed bay is included, which matches "hot to the touch" and justifies the retrofit. With heatsinks and the fan, every scenario drops well below 70 °C.

**What the analysis does not explain.** The link between driver temperature and the loss of torque is not established. The intuitive mechanism is that BJT gain rises with temperature, so a hotter driver passes more shoot-through current and leaves less of the fixed 1.56 A for the windings. The DC model does not reproduce this: when all transistors are heated together from 25 °C to 100 °C, the rail sags (for example 8.5 V → 7.2 V at h<sub>FE</sub> = 50), but the winding current rises slightly (0.16 A → 0.22 A) because the low-side NPNs pull harder. Effects the model leaves out, such as uneven heating between devices, winding inductance during stepping, and heating of the motors and the salvaged linear rails, could each matter, and none can be checked without measurements. What can be said is that the cooling retrofit was followed by the symptom disappearing; the analysis explains why the drivers ran hot, but the causal path from heat to torque loss remains an open question.

### 5.4 No freewheeling diodes

MOSFETs have a built-in body diode; the MJE2955T and MJE3055T do not, and no external diodes were fitted. Each phase change interrupts winding current, and the energy stored in the winding inductance ($E = \frac{1}{2}LI^2$) has no defined path for recirculation. It must be dissipated somewhere in the switching transistors, the base networks, the wiring, or the supply; how it divides among them was not measured.

This is mainly a **voltage-stress and reliability** concern, not a significant heat source. The winding inductance is not documented; assuming about 5 mH, typical of this motor class, and the model's winding currents of 0.09–0.22 A, each interruption stores 0.02–0.12 mJ. At about 189 steps/s (§5.5) that is roughly 4–23 mW per moving motor, small next to the watts of shoot-through loss in §5.3. The risk is the voltage spike at each interruption, which can stress the transistors and couple onto the supply (§5.6).

### 5.5 Firmware contributions

From [`src/claw_machine.asm`](../src/claw_machine.asm) (12 MHz crystal, so one machine cycle is 1 µs; one step every ≈ 5.3 ms):

- **X/Y bridges never turn off.** After each move or homing pass, Port 2 stays at its last step pattern (`1001` or `0101`), so the X and Y bridges conduct continuously while the machine waits. The Z pins are set to `1111` after `UP`, but at a rail above about 7.9 V even `1111` cannot turn the PNPs off (§5.1). This is a 100% duty-cycle load and the main firmware contribution to driver heat.
- **Brief `(0, 0)` during some phase changes.** A phase change is written as two bit instructions, so for 1 µs the bridge inputs sit in an intermediate state. About half of the phase changes pass through `(0, 0)` (for example `CLR P2.4` and then `SETB P2.5`); the rest pass through `(1, 1)` (for example `SETB P2.4` and then `CLR P2.5`). In the `(0, 0)` state both high-side PNPs turn on while the outgoing NPN may still be conducting during its storage time (typically several µs), which can add a brief shoot-through pulse. Even counting the storage time, this occupies well under 0.1% of the time between steps, so its thermal contribution is negligible next to the idle energization above; it matters as a source of current spikes, not heat.

### 5.6 Power integrity: no local decoupling

The schematics and board layouts show no local decoupling anywhere in the system:

- **Main board.** The only capacitors are the two crystal capacitors (C1, C2) and the reset capacitor (C3). There is no bypass capacitor between the AT89S52's VCC and GND pins.
- **H-bridge boards.** The driver schematic and layout show no local bypass or bulk capacitor at the motor-rail input. The resulting rail transients were not measured.

These statements describe the drawings. As far as the team recalls, no capacitors were added by hand before the competition, and none are visible on the driver boards in the 2023 photo; the main board is partly hidden by wiring, so the photo cannot fully confirm this.

In this build that matters for three reasons:

1. Every phase change interrupts winding current with no freewheeling path (§5.4). With no local capacitance at the boards, the resulting di/dt acts on the inductance of the supply wiring and can appear as ringing on the motor rail at the transistors.
2. The 6.6 V logic rail is unregulated and shared by the AT89S52 and the SG90 servo (§5.2), and it also absorbs any base current pushed back through the MCU pins' clamp diodes (§5.1). Servo current steps and that back-fed current both disturb an MCU supply that already sits at the AT89S52's 6.6 V absolute maximum.
3. The reset capacitor connects RST to VCC, so fast supply transients couple directly onto the reset pin.

No random resets were noticed during testing or the competition. Plausible reasons: the bench supply's own output capacitance smooths the rail, and a transient would have to lift RST by several volts, to the input-high threshold of about 0.7 × V<sub>CC</sub> ≈ 4.6 V, for at least two machine cycles to cause a reset. No supply waveforms were captured in 2023, so the size of these effects is unknown; they are risks identified from the drawings, not observed failures. Both versions of the redesign (§6) add local capacitance at each board.

---

## 6. Proposed Redesign

The competition banned integrated driver ICs (for example L298N and L293D) and pre-built driver modules ([hardware_and_pcb.md §4](hardware_and_pcb.md#4-discrete-bjt-h-bridge-driver)). The redesign is therefore given in two versions. A half-bridge gate-driver IC such as the IR2104 would probably also fall under that rule, so it appears only in version B.

### Version A: within the 2023 rule (discrete parts only)

1. **MOSFET H-bridges with a level-shifted high side.** Use a P-channel MOSFET on each high side and an N-channel MOSFET on each low side. The high-side gate is pulled down through a small NPN level shifter and back to the rail through a resistor; no bootstrap capacitor is involved, so the switch can stay on indefinitely for holding torque. A full 15 V swing is within the usual ±20 V gate-source rating, but a resistive divider or a 12 V Zener from gate to source keeps inductive spikes on the rail from overstressing the gate. Drive each leg from one MCU pin through a complementary discrete stage, so that each input sets one output node high or low and `(0, 0)` and `(1, 1)` become braking states instead of shoot-through states. This keeps the existing two pins per bridge.
2. **Dead time and an all-off state.** Give each gate an RC turn-on delay with a diode for fast turn-off, so a leg's two MOSFETs are never on together during a transition; this hardware dead time protects every phase change without firmware help. The two leg inputs alone have no all-off state, so add one enable line per motor that gates all four switches of both bridges off. Port 0 is unused and has eight spare pins for the three enables; its outputs are open-drain, so each needs an external pull-up resistor. It is used for PWM chopping (item 4) and for de-energizing an idle axis.
3. **Freewheeling.** The MOSFET body diodes give winding current a path at each phase change. Optionally add a Schottky diode such as the 1N5822 (40 V, 3 A, ≈ 0.5 V forward drop) across each switch to carry that current with lower loss and faster recovery than the body diode.
4. **Current regulation.** Sense winding current with a low-side shunt and chop the bridge with PWM to hold it at the 1.2 A rating (with a discrete comparator, or timed by the MCU), instead of relying on transistor voltage drop and the bench supply's current limit.

### Version B: without the rule

1. **Integrated stepper drivers.** One integrated stepper-driver IC per motor (for example DRV8825, TMC2209, or TB67S109) replaces the whole power stage: MOSFET bridges, dead time, current sensing, PWM current regulation, microstepping, and thermal and overcurrent protection, each rated above the motors' 1.2 A winding current. This is what a production design would use.
2. **If a discrete MOSFET stage is kept,** a half-bridge gate driver such as the IR2104 (two per H-bridge) supplies dead time and drives N-channel MOSFETs on both sides. The IR2104 powers its high-side gate from a bootstrap capacitor that recharges only while the low-side switch is on, so it cannot hold a high-side MOSFET on at 100% duty. It must run with the current-regulating PWM chopper (item 4 of Version A) switching continuously, including at standstill, with the duty kept below 100% so the bootstrap capacitor is refreshed every cycle.

### Common to both versions

1. **Cleaner firmware drive.** Write each 4-bit phase pattern in one instruction (`MOV`, or masked `ANL`/`ORL`). Shoot-through during a phase change is prevented in hardware (the RC dead time in Version A, the driver's internal sequencing in Version B); where an enable or all-off control exists, the firmware can also blank the bridge briefly between phases. Switch the X/Y windings off (or to reduced current) when the gantry is idle.
2. **Regulated supply rails.** Feed the AT89S52 from a regulated 5.0 V rail, put the SG90 servo on its own 5–6 V regulator so claw-stall current does not load or force up the MCU supply, and run the 12 V fan from a 12 V supply.
3. **Local decoupling.** Place a 0.1 µF ceramic capacitor at the AT89S52 VCC pin, and bulk electrolytic plus ceramic capacitance at the rail entry of each H-bridge board, so switching current is supplied locally instead of through the harness.
4. **Insulated heatsink mounting.** If heatsinks are still needed, mount each TO-220 with an insulating pad rated for electrical isolation, or give each heatsink enough clearance that live tabs cannot touch.
5. **Measure.** Log rail voltage and current, the supply's CV/CC state, and case temperatures during a long run. That would settle the open question in §5.3.

[← Back to README](../README.md)
