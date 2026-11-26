#!/usr/bin/env python3
"""
DC operating-point model of the 2023 discrete BJT H-bridges (2026 analysis).

Supports the estimates in docs/thermal_troubleshooting.md §5. It is a model, not a measurement:
nothing was measured on the 2023 hardware.

Circuit
-------
One H-bridge channel exactly as drawn in docs/images/bjt_hbridge_schematic_annotated.png:
IN1 -> 1 kOhm -> right PNP base, IN2 -> 1 kOhm -> left PNP base, each output node -> 1 kOhm ->
opposite low-side NPN base, 3 Ohm winding between OUT A and OUT B. No freewheeling diodes.

MCU pins: a logic-0 pin is a resistance R_ON to ground (the AT89S52 datasheet only guarantees
V_OL = 0.45 V at 1.6 mA, so R_ON is swept). A logic-1 pin is the upper protection diode clamping to
the logic rail (the weak pull-up is neglected).

Machine states
--------------
idle / X-Y move : four X/Y bridges at (1,0) or (0,1), two Z bridges at (1,1)  (firmware after UP)
Z move          : all six bridges at (1,0) or (0,1)

Bench supply CH2 was set to 15.1 V with a 1.56 A current limit. If the six bridges would draw more
than 1.56 A at 15.1 V, a lab supply leaves constant-voltage mode and holds 1.56 A; the script then
lowers the rail until the six bridges draw 1.56 A and reports that operating point.

Sections printed
----------------
1. The bridge at its intended +5 V rail (5 V logic): how much of the bridge current bypasses the winding.
2. The 2023 settings (15.1 V / 1.56 A, 6.6 V logic): current-limited operating point and power split.
3. The same operating point at 25 / 60 / 100 degC (BJT temperature model, winding copper tempco).

Model limits
------------
* Generic Gummel-Poon BJT parameters, not vendor models of the MJE2955T/MJE3055T. Current gain BF,
  the dominant unknown, is swept from 30 to 100.
* DC only: no winding inductance, switching, or self-heating; all devices share one temperature.

Requires ngspice on PATH (Linux/WSL: `apt install ngspice`; macOS: `brew install ngspice`; Windows:
the ngspice console build, with ngspice.exe or ngspice_con.exe on PATH). Run: python3 hbridge_dc_sim.py
"""
import os
import re
import shutil
import subprocess
import tempfile

R_BASE = 1e3       # base resistors
R_WIND = 3.0       # winding resistance at 25 degC (NEMA 17, 3 Ohm)
I_LIMIT = 1.56     # CH2 current limit
V_SET = 15.1       # CH2 voltage setting
V_LOGIC = 6.6      # CH1 logic rail as set in 2023
NGSPICE = shutil.which("ngspice_con") or shutil.which("ngspice") or "ngspice"


def run_ngspice(netlist):
    """Run ngspice in batch mode on a temporary netlist file (portable: no /dev/stdin)."""
    fd, path = tempfile.mkstemp(suffix=".cir")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(netlist)
        return subprocess.run([NGSPICE, "-b", path], capture_output=True, text=True).stdout
    finally:
        os.remove(path)


def bridge(vrail, in1, in2, bf, ron=60, vcc=V_LOGIC, temp=25):
    """Solve one bridge. Returns currents, voltages and powers."""
    rw = R_WIND * (1 + 0.0039 * (temp - 25))

    def pin(name, level):
        if level == 0:
            return f"R{name} {name} 0 {ron}\n"
        return f"D{name} {name} vccn DCL\n"

    m = (f"IS=1e-12 BF={bf} BR=4 VAF=100 IKF=4 RB=1 RC=0.05 RE=0.02 NE=1.5 ISE=1e-11 "
         f"XTB=1.5 XTI=3 EG=1.11")
    # the first line of a SPICE netlist is its title, so the netlist starts with a blank line
    net = f"""
* hbridge
.options temp={temp} tnom=25
.model PNPm PNP({m})
.model NPNm NPN({m})
.model DCL D(IS=1e-14 N=1)
Vrail rail 0 {vrail}
Vcc vccn 0 {vcc}
QPL A bL rail PNPm
R2 bL in2 {R_BASE}
QPR B bR rail PNPm
R1 bR in1 {R_BASE}
QNL A bnL 0 NPNm
R3 bnL B {R_BASE}
QNR B bnR 0 NPNm
R4 bnR A {R_BASE}
Rw A B {rw}
{pin('in1', in1)}{pin('in2', in2)}
.control
op
print -i(vrail) v(a) v(b) v(bl) v(br) v(bnl) v(bnr) v(in1) v(in2)
print @qpl[p] @qpr[p] @qnl[p] @qnr[p] @qnl[ic] @qnr[ic]
.endc
.end
"""
    out = run_ngspice(net)
    v = {k: float(x) for k, x in re.findall(r"^(\S+)\s*=\s*([-\d.e+]+)", out, re.M)}
    if "-i(vrail)" not in v:
        raise RuntimeError("ngspice failed:\n" + out[-1500:])
    i_w = (v["v(a)"] - v["v(b)"]) / rw
    rb_drops = [v["v(bl)"] - v["v(in2)"], v["v(br)"] - v["v(in1)"],
                v["v(b)"] - v["v(bnl)"], v["v(a)"] - v["v(bnr)"]]
    # current flowing from each PNP base INTO its MCU pin
    i_pin = {1: (v["v(br)"] - v["v(in1)"]) / R_BASE, 2: (v["v(bl)"] - v["v(in2)"]) / R_BASE}
    lvl = {1: in1, 2: in2}
    p_bjt = [v["@qpl[p]"], v["@qpr[p]"], v["@qnl[p]"], v["@qnr[p]"]]
    return dict(
        i_rail=v["-i(vrail)"], i_w=abs(i_w), p_in=vrail * v["-i(vrail)"],
        p_wind=i_w ** 2 * rw, p_base=sum(x * x / R_BASE for x in rb_drops),
        p_bjt=sum(p_bjt), p_bjt_max=max(p_bjt),
        i_bypass=v["@qnl[ic]"],   # left low-side NPN: carries current that never enters the winding
        sink=[i_pin[k] for k in (1, 2) if lvl[k] == 0],
        backfeed=[i_pin[k] for k in (1, 2) if lvl[k] == 1],
        v_ol=[v[f"v(in{k})"] for k in (1, 2) if lvl[k] == 0],
    )


def system(vrail, state, bf, ron, temp=25):
    driven = bridge(vrail, 1, 0, bf, ron, temp=temp)
    if state == "zmove":
        parts = [driven] * 6
    else:
        parts = [driven] * 4 + [bridge(vrail, 1, 1, bf, ron, temp=temp)] * 2
    tot = {k: sum(p[k] for p in parts) for k in ("i_rail", "p_in", "p_wind", "p_base", "p_bjt")}
    tot["p_bjt_max"] = max(p["p_bjt_max"] for p in parts)
    tot["backfeed_max"] = max([x for p in parts for x in p["backfeed"]] or [0.0])
    return tot, driven


def operating_point(state, bf, ron, temp=25):
    demand = system(V_SET, state, bf, ron, temp)[0]["i_rail"]
    if demand <= I_LIMIT:
        return (V_SET, demand) + system(V_SET, state, bf, ron, temp)
    lo, hi = 1.0, V_SET            # bisection on the rail voltage: total current = I_LIMIT
    for _ in range(25):
        mid = (lo + hi) / 2
        if system(mid, state, bf, ron, temp)[0]["i_rail"] < I_LIMIT:
            lo = mid
        else:
            hi = mid
    return (lo, demand) + system(lo, state, bf, ron, temp)


if __name__ == "__main__":
    print("1. Intended design: +5 V bridge rail, 5 V logic, input (1,0)")
    print("BF | bridge current | winding current | bypass via 'off' low-side NPN")
    for bf in (30, 50, 100):
        b = bridge(5.0, 1, 0, bf, vcc=5.0)
        print(f"{bf} | {b['i_rail']:.3f} A | {b['i_w']:.3f} A | {b['i_bypass']:.3f} A "
              f"({b['i_bypass'] / b['i_rail']:.0%})")

    print("\n2. 2023 settings: 15.1 V / 1.56 A motor rail, 6.6 V logic rail")
    print("state | BF | R_ON | demand @15.1 V | rail | P_in | P_BJT total | P_BJT avg/max per device | "
          "P_wind | P_base | I_wind | I_sink per low pin | V_OL | back-feed per high pin (max)")
    for state in ("idle", "zmove"):
        for bf in (30, 50, 100):
            for ron in (60, 150):
                v, dem, t, d = operating_point(state, bf, ron)
                print(f"{state} | {bf} | {ron} | {dem:.2f} A | {v:.1f} V | {t['p_in']:.1f} W | "
                      f"{t['p_bjt']:.1f} W | {t['p_bjt'] / 24:.2f} / {t['p_bjt_max']:.2f} W | "
                      f"{t['p_wind']:.2f} W | {t['p_base']:.2f} W | {d['i_w']:.2f} A | "
                      f"{max(d['sink']) * 1e3:.1f} mA | {max(d['v_ol']):.2f} V | "
                      f"{t['backfeed_max'] * 1e3:.1f} mA")

    print("\n3. Temperature sensitivity (idle state, R_ON = 60 Ohm, all devices at one temperature)")
    print("BF | T | rail | winding current")
    for bf in (30, 50, 100):
        for temp in (25, 60, 100):
            v, dem, t, d = operating_point("idle", bf, 60, temp)
            print(f"{bf} | {temp} degC | {v:.2f} V | {d['i_w']:.3f} A")
