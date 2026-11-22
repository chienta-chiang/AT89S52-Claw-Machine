; =============================================================================
; File:        claw_machine.asm
; Target MCU:  AT89S52 (8052 Architecture, 12 MHz Crystal Oscillator)
; Project:     AT89S52 (8052)-Based Three-Axis Claw Machine
; Award:       2nd Place, Microprocessor Final Project Competition
;              Department of Electrical Engineering, Feng Chia University
;
; Description:
;   8051 Assembly firmware governing IR coin detection, manual X/Y stepper
;   gantry positioning, external interrupt-driven Z-axis descent/ascent,
;   Timer 0-timed SG90 servo pulses, and limit-switch-based homing
;   with bounded step counts.
;
; Pin Assignment:
;   P1.0 - P1.3 : Z-Axis Bipolar Stepper Motor Driver (DOWN / UP)
;   P1.4        : SG90 Claw Servo Pulse Signal (CATCH / LOOSE)
;   P1.5        : RLEFTBTN  - Y-Axis Homing Micro-Switch (polled during RFRONT)
;   P1.6        : RFRONTBTN - X-Axis Homing Micro-Switch (polled during RLEFT)
;   P1.7        : INFRARED  - 940 nm IR Coin Sensor Input
;   P2.0 - P2.3 : X-Axis Bipolar Stepper Motor Driver (LEFT / RIGHT / RLEFT)
;   P2.4 - P2.7 : Y-Axis Bipolar Stepper Motor Driver (FRONT / BACK / RFRONT)
;   P3.2 / INT0 : Catch Arcade Button (External Interrupt 0, Falling-Edge)
;   P3.4        : FRONTBTN  - Directional Button: Front (Active-Low)
;   P3.5        : BACKBTN   - Directional Button: Back  (Active-Low)
;   P3.6        : LEFTBTN   - Directional Button: Left  (Active-Low)
;   P3.7        : RIGHTBTN  - Directional Button: Right (Active-Low)
; =============================================================================

ORG 0000H
        FRONTBTN  EQU P3.4          ; Directional arcade button: Front
        BACKBTN   EQU P3.5          ; Directional arcade button: Back
        LEFTBTN   EQU P3.6          ; Directional arcade button: Left
        RIGHTBTN  EQU P3.7          ; Directional arcade button: Right
        RLEFTBTN  EQU P1.5          ; Homing micro-switch polled during RFRONT
        RFRONTBTN EQU P1.6          ; Homing micro-switch polled during RLEFT
        INFRARED  EQU P1.7          ; 940 nm IR emitter/receiver coin detector
        AJMP MAIN                   ; Jump past interrupt vector table on reset

ORG 0003H
        AJMP EXInterrupt0           ; External Interrupt 0 vector (Catch button P3.2)

; =============================================================================
; Initialization & Coin Insertion Polling
; =============================================================================
MAIN:
        SETB FRONTBTN               ; Configure P3.4-P3.7 as quasi-bidirectional inputs
        SETB BACKBTN
        SETB LEFTBTN
        SETB RIGHTBTN
        SETB RLEFTBTN               ; Configure P1.5-P1.6 micro-switches as inputs
        SETB RFRONTBTN
        CLR  INFRARED               ; Clear P1.7 latch (drives this 8051 pin low; see firmware review)

START:
        JB   INFRARED, LOOP         ; Poll IR coin sensor; unlock game when coin detected
        AJMP START

; =============================================================================
; Active Game Loop: Enable Catch Interrupt & Poll Directional Buttons
; =============================================================================
LOOP:
        CLR  INFRARED
        SETB EA                     ; Enable global interrupts
        SETB IT0                    ; Configure INT0 (P3.2) for falling-edge trigger
        SETB EX0                    ; Enable External Interrupt 0 (Catch button)

LOOP1:
        JNB  FRONTBTN, FRONT1       ; Poll Front button (active-low)
        JNB  BACKBTN,  BACK1        ; Poll Back button  (active-low)
        JNB  LEFTBTN,  LEFT1        ; Poll Left button  (active-low)
        JNB  RIGHTBTN, RIGHT1       ; Poll Right button (active-low)
        AJMP LOOP1

FRONT1:
        MOV  R0, #7                 ; 7 full 4-step cycles per button press
        LJMP FRONT

BACK1:
        MOV  R0, #7
        LJMP BACK

LEFT1:
        MOV  R0, #7
        LJMP LEFT

RIGHT1:
        MOV  R0, #7
        LJMP RIGHT

; =============================================================================
; Y-Axis Stepper Routines (P2.4 - P2.7): FRONT & BACK
; =============================================================================
FRONT:
        SETB P2.4                   ; Step 1: P2.7..P2.4 = 0101B
        CLR  P2.5
        SETB P2.6
        CLR  P2.7
        ACALL DELAY

        CLR  P2.4                   ; Step 2: P2.7..P2.4 = 0110B
        SETB P2.5
        ACALL DELAY

        CLR  P2.6                   ; Step 3: P2.7..P2.4 = 1010B
        SETB P2.7
        ACALL DELAY

        SETB P2.4                   ; Step 4: P2.7..P2.4 = 1001B
        CLR  P2.5
        ACALL DELAY

        DJNZ R0, FRONT
        LJMP LOOP

BACK:
        SETB P2.4                   ; Step 1 (Reverse): P2.7..P2.4 = 1001B
        CLR  P2.5
        CLR  P2.6
        SETB P2.7
        ACALL DELAY

        CLR  P2.4                   ; Step 2 (Reverse): P2.7..P2.4 = 1010B
        SETB P2.5
        ACALL DELAY

        SETB P2.6                   ; Step 3 (Reverse): P2.7..P2.4 = 0110B
        CLR  P2.7
        ACALL DELAY

        SETB P2.4                   ; Step 4 (Reverse): P2.7..P2.4 = 0101B
        CLR  P2.5
        ACALL DELAY

        DJNZ R0, BACK
        LJMP LOOP

; =============================================================================
; X-Axis Stepper Routines (P2.0 - P2.3): LEFT & RIGHT
; =============================================================================
LEFT:
        SETB P2.0                   ; Step 1: P2.3..P2.0 = 0101B
        CLR  P2.1
        SETB P2.2
        CLR  P2.3
        ACALL DELAY

        CLR  P2.0                   ; Step 2: P2.3..P2.0 = 0110B
        SETB P2.1
        ACALL DELAY

        CLR  P2.2                   ; Step 3: P2.3..P2.0 = 1010B
        SETB P2.3
        ACALL DELAY

        SETB P2.0                   ; Step 4: P2.3..P2.0 = 1001B
        CLR  P2.1
        ACALL DELAY

        DJNZ R0, LEFT
        LJMP LOOP

RIGHT:
        SETB P2.0                   ; Step 1 (Reverse): P2.3..P2.0 = 1001B
        CLR  P2.1
        CLR  P2.2
        SETB P2.3
        ACALL DELAY

        CLR  P2.0                   ; Step 2 (Reverse): P2.3..P2.0 = 1010B
        SETB P2.1
        ACALL DELAY

        SETB P2.2                   ; Step 3 (Reverse): P2.3..P2.0 = 0110B
        CLR  P2.3
        ACALL DELAY

        SETB P2.0                   ; Step 4 (Reverse): P2.3..P2.0 = 0101B
        CLR  P2.1
        ACALL DELAY

        DJNZ R0, RIGHT
        LJMP LOOP

; =============================================================================
; External Interrupt 0 ISR (EXInterrupt0):
;   1. Z-Axis Descent (DOWN)
;   2. SG90 Claw Closure (CATCH)
;   3. Z-Axis Ascent (UP)
;   4. Limit-Switch-Based Homing with Bounded Step Counts (RFRONT -> RLEFT)
;   5. SG90 Claw Release (LOOSE) & Return to Coin Polling
; =============================================================================
EXInterrupt0:
        MOV  R0, #255               ; 255 4-step cycles for Z-axis spool descent

DOWN:
        SETB P1.0                   ; Z-Axis Step 1: P1.3..P1.0 = 0101B
        CLR  P1.1
        SETB P1.2
        CLR  P1.3
        ACALL DELAY

        CLR  P1.0                   ; Z-Axis Step 2: P1.3..P1.0 = 0110B
        SETB P1.1
        ACALL DELAY

        CLR  P1.2                   ; Z-Axis Step 3: P1.3..P1.0 = 1010B
        SETB P1.3
        ACALL DELAY

        SETB P1.0                   ; Z-Axis Step 4: P1.3..P1.0 = 1001B
        CLR  P1.1
        ACALL DELAY

        DJNZ R0, DOWN

; --- SG90 Servo Actuation: Close Claw (2.0 ms pulses via DELAY2) ---
CATCH:
        MOV  R0, #5                 ; Outer loop: 5 * 150 = 750 servo pulses
CATCH1:
        MOV  R1, #150
CATCH2:
        SETB P1.4
        ACALL DELAY2                ; 2.0 ms high pulse (Timer 0: 0F830H)
        CLR  P1.4
        ACALL DELAY2                ; 2.0 ms low period
        DJNZ R1, CATCH2
        DJNZ R0, CATCH1

; --- Z-Axis Ascent ---
        MOV  R0, #255               ; 255 4-step cycles to hoist claw back to top
UP:
        SETB P1.0                   ; Z-Axis Step 1 (Reverse): P1.3..P1.0 = 1001B
        CLR  P1.1
        CLR  P1.2
        SETB P1.3
        ACALL DELAY

        CLR  P1.0                   ; Z-Axis Step 2 (Reverse): P1.3..P1.0 = 1010B
        SETB P1.1
        ACALL DELAY

        SETB P1.2                   ; Z-Axis Step 3 (Reverse): P1.3..P1.0 = 0110B
        CLR  P1.3
        ACALL DELAY

        SETB P1.0                   ; Z-Axis Step 4 (Reverse): P1.3..P1.0 = 0101B
        CLR  P1.1
        ACALL DELAY

        DJNZ R0, UP

        SETB P1.0                   ; Set Z-axis driver lines high after ascent
        SETB P1.1
        SETB P1.2
        SETB P1.3

; --- Limit-Switch-Based Homing: RFRONT (P2.4-P2.7, Bounded at 255 Cycles) ---
RFRONT:
        MOV  R0, #255               ; Maximum step bound if limit switch not triggered
RFRONT1:
        SETB P2.4
        CLR  P2.5
        CLR  P2.6
        SETB P2.7
        ACALL DELAY

        CLR  P2.4
        SETB P2.5
        ACALL DELAY

        SETB P2.6
        CLR  P2.7
        ACALL DELAY

        SETB P2.4
        CLR  P2.5
        ACALL DELAY

        JNB  P1.5, RLEFT            ; Poll micro-switch P1.5; branch to RLEFT if hit
        DJNZ R0, RFRONT1

; --- Limit-Switch-Based Homing: RLEFT (P2.0-P2.3, Bounded at 400 Cycles) ---
RLEFT:
        MOV  R1, #2                 ; Outer loop bound (2 * 200 = 400 max 4-step cycles)
RLEFT1:
        MOV  R0, #200
RLEFT2:
        SETB P2.0
        CLR  P2.1
        SETB P2.2
        CLR  P2.3
        ACALL DELAY

        CLR  P2.0
        SETB P2.1
        ACALL DELAY

        CLR  P2.2
        SETB P2.3
        ACALL DELAY

        SETB P2.0
        CLR  P2.1
        ACALL DELAY

        JNB  P1.6, LOOSE            ; Poll micro-switch P1.6; branch to LOOSE if hit
        DJNZ R0, RLEFT2
        DJNZ R1, RLEFT1

; --- SG90 Servo Actuation: Open Claw over Prize Chute (1.0 ms pulses via DELAY3) ---
LOOSE:
        MOV  R0, #5                 ; Outer loop: 5 * 75 = 375 servo pulses
LOOSE1:
        MOV  R1, #75
LOOSE2:
        SETB P1.4
        ACALL DELAY3                ; 1.0 ms high pulse (Timer 0: 0FC18H)
        CLR  P1.4
        ACALL DELAY3                ; 1.0 ms low period
        DJNZ R1, LOOSE2
        DJNZ R0, LOOSE1

        CLR  EA                     ; Disable interrupts (EA stays 0 after RETI until a direction move re-enters LOOP)
        CLR  IT0
        CLR  EX0
        LJMP START1

DO:
        RETI                        ; Return from External Interrupt 0

START1:
        JB   INFRARED, DO           ; Wait for coin sensor state before exiting ISR
        AJMP START1

; =============================================================================
; Timing & Delay Subroutines (12 MHz Clock -> 1.0 us Machine Cycle)
; =============================================================================

; Software delay for stepper phase commutation (~5.3 ms per step)
DELAY:
        MOV  R3, #100
DL:
        MOV  R4, #25
        DJNZ R4, $
        DJNZ R3, DL
        RET

; Timer 0 Polled Delay: 2.0 ms (65536 - 2000 = 63536 = 0F830H) for SG90 Catch
DELAY2:
        MOV  TMOD, #01H             ; Timer 0 Mode 1 (16-bit non-auto-reload timer)
        MOV  TL0,  #030H
        MOV  TH0,  #0F8H
        SETB TR0
        AJMP WAIT

; Timer 0 Polled Delay: 1.0 ms (65536 - 1000 = 64536 = 0FC18H) for SG90 Release
DELAY3:
        MOV  TMOD, #01H             ; Timer 0 Mode 1 (16-bit non-auto-reload timer)
        MOV  TL0,  #18H
        MOV  TH0,  #0FCH
        SETB TR0

WAIT:
        JB   TF0, OK                ; Poll Timer 0 overflow flag
        AJMP WAIT

OK:
        CLR  TR0                    ; Stop Timer 0 and clear overflow flag
        CLR  TF0
        RET

END
