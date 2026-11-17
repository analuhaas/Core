/*
 *
 * Copyright (c) 2024-present LAAS-CNRS
 *
 *   This program is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU Lesser General Public License as published by
 *   the Free Software Foundation, either version 2.1 of the License, or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU Lesser General Public License for more details.
 *
 *   You should have received a copy of the GNU Lesser General Public License
 *   along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: LGPL-2.1
 */

/**
 * @brief  This file is the main application code for the open-loop inverter
 *         example. It implements a sinusoidal open-loop PWM strategy that
 *         drives an H-bridge inverter using a local oscillator without any
 *         closed-loop feedback or grid synchronization.
 *
 * @author Luiz Villa <luiz.villa@laas.fr>
 */

 /*--------------OWNTECH APIs---------------------------------- */
#include <math.h>
#include <float.h>
#include "TaskAPI.h"
#include "ShieldAPI.h"
#include "SpinAPI.h"
#include "user_data_objects.h"

/* From control library */
#include "trigo.h"
#include "filters.h"
#include "transform.h"
#include "ScopeMimicry.h"
#include "zephyr/console/console.h"

/* From single_phase_inverter library. */
#include "sogi.h"

#define DUTY_MIN 0.1F
#define DUTY_MAX 0.9F

/*--------------SETUP FUNCTIONS DECLARATION------------------- */
/* Setups the hardware and software of the system */
void setup_routine();

/*--------------LOOP FUNCTIONS DECLARATION-------------------- */
/* Code to be executed in the slow communication task */
void loop_communication_task();
/* Code to be executed in the background task */
void loop_application_task();
/* Code to be executed in real time in the critical task */
void loop_critical_task();

/*--------------SUPPORT FUNCTIONS DECLARATION----------------- */
/* Reports whether the scope capture should trigger */
bool a_trigger();
/* Clamps a floating-point value inside the requested range */
float32_t saturate(float32_t value, float32_t min, float32_t max);
/* Returns the DC bus voltage, or a fallback before sensing is valid */
float32_t control_bus_voltage();
/* Starts both PWM legs once and records the output state */
void start_pwm_outputs();
/* Stops both PWM legs once and records the output state */
void stop_pwm_outputs();
/* Advances the local oscillator and updates the sine voltage reference */
void update_teaching_sine();
void update_AC_source_sine();
void update_modulation_sine();
/* Applies clamped complementary duty cycles to the H-bridge legs */
void apply_complementary_duty(float32_t duty);
/* Streams a completed ScopeMimicry capture over the serial console */
void dump_scope_datas(ScopeMimicry &scope_to_dump);
/* Adjusts the local sine voltage amplitude used by the open-loop PWM */
void adjust_amplitude(float32_t step);
/* Registers scope channels and starts capture for the open-loop example */
void setup_scope();
/* Reads sensor values and derives the measured grid voltage */
void read_measurements();
/* Checks both measured currents against the protection threshold */
bool overcurrent_detected();
/* Calculate the active and reactive power on the AC side */
void calculate_power();

void regulate_vc_to_vref();

/*--------------USER VARIABLES DECLARATIONS------------------- */

/* Control task period in microseconds */
static constexpr uint32_t CONTROL_TASK_PERIOD_US = 100;
/* Control task period in seconds */
static constexpr float32_t TS = CONTROL_TASK_PERIOD_US * 1.0e-6F;
/* Fallback DC bus voltage in volts before sensing is valid */
static constexpr float32_t DC_BUS_FALLBACK = 20.0F;
/* Grid frequency in hertz */
static constexpr float32_t F0 = 50.0F;
/* Grid pulsation in radians per second */
static constexpr float32_t W0 = 2.0F * PI * F0;
/* Maximum current for overcurrent protection in amps */
static constexpr float32_t MAX_CURRENT = 10.0F;
/* Maximum current for overcurrent protection in amps */
static constexpr float32_t MAX_CURRENT_OPERATION = 10.0F;
/* Number of critical task samples in one grid period (TS * RMS_WINDOW_SAMPLES = 1/F0) */
static constexpr uint32_t RMS_WINDOW_SAMPLES = static_cast<uint32_t>(1.0F / (F0 * TS) + 0.5F);
/* sqrt(2), used to convert a sinusoid peak value into an RMS value */
static constexpr float32_t SQRT2 = 1.41421356F;
/* [s] Time constant of the EMA/IIR mean-square RMS estimator (~1 grid period) */
static constexpr float32_t RMS_EMA_TAU = 0.02F;
/* Discrete EMA gain derived from RMS_EMA_TAU and the control task period */
static constexpr float32_t RMS_EMA_ALPHA = TS / RMS_EMA_TAU;
/* Size of the scope buffer for data recording */
static constexpr uint32_t SCOPE_BUFFER_SIZE = 1024;
/* One scope sample every SCOPE_DECIMATION control steps (sample time = SCOPE_DECIMATION * TS) */
static constexpr uint32_t SCOPE_DECIMATION = 2;
/* Number of channels recorded in the scope for diagnostics */
static constexpr uint8_t SCOPE_CHANNEL_COUNT = 15;

/* State of the PWM outputs */
static bool pwm_enable = false;
/* State of scope data downloading */
static bool is_downloading = false;
/* State to trigger the scope capture */
static bool trigger = false;

/* Variable to store the last received serial character */
static uint8_t received_serial_char;
/* Current operating mode of the inverter */
// static uint8_t mode = IDLEMODE;
/* Last requested operating mode from the serial interface */
// static uint8_t mode_asked = IDLEMODE;

/* [V] Low-side filtered measurement of voltage 1 */
static float32_t V1_low_value;
/* [V] Low-side filtered measurement of voltage 2 */
static float32_t V2_low_value;
/* [A] Low-side filtered measurement of current 1 */
static float32_t I1_low_value;
/* [A] Low-side filtered measurement of current 2 */
static float32_t I2_low_value;
/* [A] High-side raw measurement of current */
// static float32_t I_high;
/* [V] High-side raw measurement of voltage */
// static float32_t V_high;
/* [V] Further filtered high-side voltage for control */
static float32_t V_high_filt;
/* [V] Measured grid voltage from the difference of low-side measurements */
static float32_t Vgrid_meas;
/* [V] Temporary variable for storing sensor measurements */
// static float32_t meas_data;


/* [V] Mean of V_high over the current grid period window */
static float32_t Vhigh_mean;
/* [V] Running minimum of V_high in the current grid period window */
static float32_t Vhigh_min_running = FLT_MAX;
/* [V] Running maximum of V_high in the current grid period window */
static float32_t Vhigh_max_running = -FLT_MAX;
/* [V] Running sum of V_high in the current grid period window */
static float32_t Vhigh_sum;

/* [V] Amplitude of the local teaching sine wave */
static float32_t V_ref = 12*sqrtf(2.0F);
/* [V] Instantaneous v_c regulation error, sine - Vgrid_meas */
static float32_t vc_error;
/* [V] Peak amplitude of the v_c phasor, from regulate_vc_to_vref() (once per grid period) */
static float32_t Vc_amplitude;
/* [V] Amplitude error V_ref - |V_c|, from regulate_vc_to_vref() (once per grid period) */
static float32_t vc_amplitude_error;
/* [rad] Phase error of v_c relative to the teaching sine, > 0 : v_c leads (once per grid period) */
static float32_t vc_phase_error;
// static float32_t Mp_AC_source = 0.0F;
/* [V] Amplitude of the local teaching sine wave */
// static float32_t Mp = 0.0F;
/* [rad] Phase angle of the local teaching sine wave */
// static float32_t phi_AC_source;
static float32_t phi_sine_modulo;
/* [rad] Phase angle of the AC source control sine wave */
static float32_t phi_AC_source_modulo;
static float32_t phi_AC_source_old;
static float32_t delta_phi_AC_source;
/* [rad] Phase angle of the reference duty cycle sine wave */
// static float32_t phi_m;
static float32_t phi_m_modulo;
static float32_t phi_m_old;
static float32_t delta_phi_m;
/* [No unit] Instantaneous value of the local teaching sine wave */
static float32_t sine;
/* [No unit] Instantaneous value of the AC source control sine wave */
static float32_t sine_ACsource;
/* [No unit] Instantaneous value of the reference duty cycle sine wave */
static float32_t sine_modulation;
/* [V] Instantaneous local grid voltage from the teaching sine */
static float32_t local_vgrid;
/* [V] Instantaneous local grid voltage from the teaching sine */
static float32_t local_modulation;

/* [No unit] Duty cycle computed from the local sine and DC bus voltage */
static float32_t delta_duty_cycle = 0.5F;
/* [No unit] Duty cycle for leg 1 of the H-bridge */
static float32_t duty_cycle_1 = 0.5F;
/* [No unit] Duty cycle for leg 2 of the H-bridge */
static float32_t duty_cycle_2 = 0.5F;
/* [No unit] Scope variable for the current operating mode */
static float32_t state_mode_scope;
/* Counter for the number of critical task iterations */
static uint32_t critical_task_counter;

/* First-order low-pass filter for the high-side voltage measurement */
static LowPassFirstOrderFilter vHighFilter(TS, 0.1F);
/* ScopeMimicry instance for recording control variables and diagnostics */
static ScopeMimicry scope(SCOPE_BUFFER_SIZE, SCOPE_CHANNEL_COUNT);

/* Synchronization variables */
static uint32_t dac_value;

/* SOGI resonance gain, shared by the voltage and current SOGI filters */
static constexpr float32_t Kr = 500.0F;
/* SOGI filter extracting the orthogonal (alpha/beta) components of Vgrid_meas */
static Sogi sogi_v;
/* SOGI filter extracting the orthogonal (alpha/beta) components of I1_low_value */
static Sogi sogi_i;
/* [V] Clarke (alpha/beta) components of the grid voltage, from sogi_v */
static clarke_t Vab;
/* [A] Clarke (alpha/beta) components of the grid current, from sogi_i */
static clarke_t Iab;
/* [V] dq components of the grid voltage, rotated from Vab by phi_m */
static dqo_t Vdq;
/* [A] dq components of the grid current, rotated from Iab by phi_m */
static dqo_t Idq;
/* [W, VAR] Active (d) and reactive (q) AC-side power computed from Vdq/Idq */
static dqo_t power;
// static float32_t power_d;
// static float32_t power_q;
/*--------------------------------------------------------------- */

/**********************  SUPPORT FUNCTIONS  ***************************/

/**
 * @brief Reports whether the scope capture should trigger.
 */
bool a_trigger()
{
    return trigger;
}

/**
 * @brief Clamps a floating-point value inside the requested range.
 */
float32_t saturate(float32_t value, float32_t min, float32_t max)
{
    if (value > max) {
        return max;
    }
    if (value < min) {
        return min;
    }
    return value;
}

/**
 * @brief Returns the measured DC bus voltage, or a fallback before sensing is valid.
 */
float32_t control_bus_voltage()
{
    if (V_high_filt > 1.0F) {
        return V_high_filt;
    }
    return DC_BUS_FALLBACK;
}

/**
 * @brief Starts both PWM legs once and records the output state.
 */
void start_pwm_outputs()
{
    if (!pwm_enable) {
        shield.power.start(ALL);
        pwm_enable = true;
    }
}

/**
 * @brief Stops both PWM legs once and records the output state.
 */
void stop_pwm_outputs()
{
    if (pwm_enable) {
        shield.power.stop(ALL);
        pwm_enable = false;
    }
}

/**
 * @brief Advances the local teaching oscillator and updates the sine voltage reference.
 */
void update_teaching_sine()
{
    phi_sine_modulo = ot_modulo_2pi(phi_sine_modulo + W0 * TS);
    sine = V_ref * ot_sin(phi_sine_modulo); // reference sine to follow in voltage
}

/**
 * @brief Updates the AC source control sine wave.
 */
void update_AC_source_sine()
{   
    delta_phi_AC_source = phi_AC_source - phi_AC_source_old;
    phi_AC_source_modulo = ot_modulo_2pi(phi_AC_source_modulo + delta_phi_AC_source + W0 * TS);
    sine_ACsource = ot_sin(phi_AC_source_modulo);

    dac_value = (0.52F + ( Mp_AC_source * sine_ACsource / 2.0F )) * 4000;
    phi_AC_source_old = phi_AC_source;
}

/**
 * @brief Updates the modulation control sine wave.
 */
void update_modulation_sine()
{   
    delta_phi_m = phi_m - phi_m_old;
    phi_m_modulo = ot_modulo_2pi(phi_m_modulo + delta_phi_m + W0 * TS);
    sine_modulation = ot_sin(phi_m_modulo);

    delta_duty_cycle = 0.5F + ( Mp * sine_modulation / 2.0F );
    phi_m_old = phi_m;
}

/**
 * @brief regulates vc voltage to the reference voltage, acting on Mp and phi_m.
 *
 * The phasor of Vgrid_meas in the frame of the teaching sine is built from a
 * window of one grid period, so Mp and phi_m are corrected once every
 * 20 ms. Needs the switch OPEN: with the switch closed, v_c is imposed by the AC
 * source, Mp can't remove the error and it would ramp up to its limit.
 */
void regulate_vc_to_vref()
{
    /* Leave false while the supervisor writes Mp, and never true together with
     * the one of regulate_vs_to_vref (both use Vgrid_meas) */
    static constexpr bool REGULATION_ENABLED = true;
    /* [No unit] Fraction of the error corrected per grid period */
    static constexpr float32_t ALPHA = 1.0F;
    /* [No unit] Fraction of the error corrected per grid period */
    static constexpr float32_t BETHA = 1.0F;
    /* [V] Peak voltage below which the measured phase is not trusted */
    static constexpr float32_t V_MIN = 2.0F * SQRT2;
    /* Modulation limit */
    static constexpr float32_t M_MAX = 0.9F;
    /* Max change of Mp per grid period */
    static constexpr float32_t MAX_STEP_M = 0.1F;
    /* [rad] Max change of phi_m per grid period */
    static constexpr float32_t MAX_STEP_PHI = 0.05F;

    static float32_t sum_sin;
    static float32_t sum_cos;
    static uint32_t window_samples;

    if (!REGULATION_ENABLED || mode != VCREGMODE) {
        sum_sin = 0.0F;
        sum_cos = 0.0F;
        window_samples = 0;
        return;
    }

    /* Called before update_teaching_sine(): phi_sine_modulo is still the phase of the
     * control step in which Vgrid_meas was read */
    sum_sin += Vgrid_meas * ot_sin(phi_sine_modulo);
    sum_cos += Vgrid_meas * ot_cos(phi_sine_modulo);
    window_samples++;
    if (window_samples < RMS_WINDOW_SAMPLES) {
        return;
    }

    /* For Vgrid_meas = V * sin(phi_sine_modulo + phi): sum_sin -> V * cos(phi) * N / 2 and
     * sum_cos -> V * sin(phi) * N / 2 */
    const float32_t V_re = 2.0F * sum_sin / RMS_WINDOW_SAMPLES;
    const float32_t V_im = 2.0F * sum_cos / RMS_WINDOW_SAMPLES;
    const float32_t V_c = sqrtf(V_re * V_re + V_im * V_im);
    sum_sin = 0.0F;
    sum_cos = 0.0F;
    window_samples = 0;

    /* v_c peak is Mp * Vdc on an H-bridge, so the amplitude error is scaled by Vdc */
    const float32_t E_M = V_ref - V_c;
    const float32_t step_M = saturate(ALPHA * E_M / control_bus_voltage(), -MAX_STEP_M, MAX_STEP_M);
    Mp = saturate(Mp + step_M, 0, M_MAX);
    Vc_amplitude = V_c;
    vc_amplitude_error = E_M;

    if (V_c > V_MIN) {
        /* > 0 : v_c leads the reference, so the modulation phase has to go back */
        const float32_t E_phi = atan2f(V_im, V_re);
        const float32_t step_phi = saturate(BETHA * E_phi, -MAX_STEP_PHI, MAX_STEP_PHI);
        phi_m = phi_m - step_phi;
        vc_phase_error = E_phi;
    }
}

/**
 * @brief Applies clamped complementary duty cycles to the H-bridge legs.
 */
void apply_complementary_duty(float32_t duty)
{
    duty_cycle_1 = saturate(duty, DUTY_MIN, DUTY_MAX);
    duty_cycle_2 = saturate(1.0F - duty, DUTY_MIN, DUTY_MAX);
    shield.power.setDutyCycle(LEG1, duty_cycle_1);
    shield.power.setDutyCycle(LEG2, duty_cycle_2);
}

/**
 * @brief Streams a completed ScopeMimicry capture over the serial console.
 */
void dump_scope_datas(ScopeMimicry &scope_to_dump)
{
    scope_to_dump.reset_dump();
    printk("begin record\n");
    while (scope_to_dump.get_dump_state() != finished) {
        printk("%s", scope_to_dump.dump_datas());
        task.suspendBackgroundUs(100);
    }
    printk("end record\n");
}

/**
 * @brief Adjusts the local sine voltage amplitude used by the open-loop PWM.
 */
void adjust_amplitude_converter(float32_t step)
{
    Mp =
        saturate(Mp + step, 0.0F, 1.0F);
}

/**
 * @brief Adjusts the local sine voltage amplitude used by the open-loop PWM.
 */
void adjust_amplitude_ACsource(float32_t step)
{
    Mp_AC_source =
        saturate(Mp_AC_source + step, 0.0F, 1.0F);
}

/**
 * @brief Adjusts the local sine voltage phase used by the open-loop PWM.
 */
void adjust_phase_converter(float32_t step)
{
    phi_m =
        ot_modulo_2pi(phi_m + step);
}

/**
 * @brief Adjusts the local sine voltage phase used by the open-loop PWM.
 */
void adjust_phase_ACsource(float32_t step)
{
    phi_AC_source =
        ot_modulo_2pi(phi_AC_source + step);
}

/**
 * @brief Registers scope channels and starts capture for the open-loop example.
 */
void setup_scope()
{
    scope.connectChannel(I1_low_value, "I1_low_value");
    scope.connectChannel(I2_low_value, "I2_low_value");
    scope.connectChannel(Vgrid_meas, "Vgrid");
    scope.connectChannel(V_high_filt, "Vdc");
    scope.connectChannel(power_d, "P_board");   /* active power from calculate_power() [W] */
    scope.connectChannel(power_q, "Q_board");   /* reactive power from calculate_power() [VAr] */
    scope.connectChannel(sine, "sine");                       /* v_ref [V] */
    scope.connectChannel(delta_duty_cycle, "duty_cycle");
    /* v_c regulation. The 15 channels x 1024 samples are allocated on the heap,
     * which has no room for more channels: these replace duty_cycle_1/2,
     * sine_modulation and state */
    scope.connectChannel(vc_error, "vc_error");               /* v_ref - v_c [V] */
    scope.connectChannel(Vc_amplitude, "Vc_amplitude");       /* |V_c| peak [V] */
    scope.connectChannel(vc_amplitude_error, "E_M");          /* V_ref - |V_c| [V] */
    scope.connectChannel(vc_phase_error, "E_phi");            /* phase of v_c - phase of v_ref [rad] */
    scope.connectChannel(I_high_value, "idc");
    scope.connectChannel(temp_1_value, "T1");
    scope.connectChannel(temp_2_value, "T2");
    /* No pre-trigger samples: the capture is re-armed and triggered in the same
     * control step (Config/wScopeArm), so a pre-trigger part of the buffer would
     * still hold samples of the previous capture. */
    scope.set_delay(0.0F);
    scope.set_trigger(a_trigger);
    scope.start();
}

/**
 * @brief Reads the latest sensor values and derives the measured grid voltage.
 */
void read_measurements()
{
    meas_data = shield.sensors.getLatestValue(I1_LOW);
    if (meas_data != NO_VALUE) I1_low_value = meas_data;

    meas_data = shield.sensors.getLatestValue(V1_LOW);
    if (meas_data != NO_VALUE) V1_low_value = meas_data;

    meas_data = shield.sensors.getLatestValue(V2_LOW);
    if (meas_data != NO_VALUE) V2_low_value = meas_data;

    meas_data = shield.sensors.getLatestValue(I2_LOW);
    if (meas_data != NO_VALUE) I2_low_value = meas_data;

    meas_data = shield.sensors.getLatestValue(V_HIGH);
    if (meas_data != NO_VALUE) V_high_value = meas_data;

    meas_data = shield.sensors.getLatestValue(I_HIGH);
    if (meas_data != NO_VALUE) I_high_value = meas_data;

    V_high_filt = vHighFilter.calculateWithReturn(V_high_value);
    Vgrid_meas = V1_low_value - V2_low_value;
}

/**
 * @brief Calculates active and reactive power using sogi and dq0 transform (single phase application).
 */
void calculate_power()
{
    Vab = sogi_v.calc(Vgrid_meas,W0);
    Iab = sogi_i.calc(I1_low_value,W0);

    Vdq = Transform::rotation_to_dqo(Vab, phi_m);
    Idq = Transform::rotation_to_dqo(Iab, phi_m);

    power.d = 0.5F * (Vdq.d * Idq.d + Vdq.q * Idq.q);
    power.q = 0.5F * (Idq.d * Vdq.q - Idq.q * Vdq.d);

    power_d = power.d;
    power_q = power.q;
}

/**
 * @brief Checks both measured currents against the protection threshold.
 */
bool overcurrent_detected()
{
    return I1_low_value > MAX_CURRENT ||
           I1_low_value < -MAX_CURRENT ||
           I2_low_value > MAX_CURRENT ||
           I2_low_value < -MAX_CURRENT;
}

/**
 * @brief Checks both measured currents against the protection threshold.
 */
bool overcurrent_detected_operation()
{
    return I1_low_value > MAX_CURRENT_OPERATION ||
           I1_low_value < -MAX_CURRENT_OPERATION ||
           I2_low_value > MAX_CURRENT_OPERATION ||
           I2_low_value < -MAX_CURRENT_OPERATION;
}


/*----------------------- END OF SUPPORT FUNCTIONS ------------------------- */

/*----------------------- MAIN APPLICATION CODE ---------------------------- */

/**
 * @brief Configures hardware, scope capture, and OwnTech task scheduling.
 */
void setup_routine()
{
    spin.pwm.initFixedFrequency(200000);
    shield.power.setDeadTime(LEG1, 20, 20);
    shield.power.setDeadTime(LEG2, 20, 20);
    shield.sensors.enableDefaultTwistSensors();
    shield.power.disconnectCapacitor(LEG1);
    shield.power.disconnectCapacitor(LEG2);
    shield.power.initBuck(LEG1);
    shield.power.initBuck(LEG2);

    setup_scope();

    shield.sensors.setConversionParametersLinear(V_HIGH, 0.0300473F, 0.288949F);
    shield.sensors.setConversionParametersLinear(V1_LOW, 0.045065666F, -90.9069F);
    shield.sensors.setConversionParametersLinear(V2_LOW, 0.045077775F, -91.036082F);
    shield.sensors.setConversionParametersLinear(I1_LOW, 0.0049823408F, -10.452284F);
    shield.sensors.setConversionParametersLinear(I2_LOW, 0.004929446F, -10.234404F);
    shield.sensors.setConversionParametersLinear(I_HIGH, 0.00511002F, -10.4447F);

    uint32_t app_task_number = task.createBackground(loop_application_task);
    // uint32_t com_task_number = task.createBackground(loop_communication_task);
    task.createCritical(loop_critical_task, CONTROL_TASK_PERIOD_US);
    task.startBackground(app_task_number);
    // task.startBackground(com_task_number);
    task.startCritical();

    sogi_v.init(Kr, TS);
    sogi_i.init(Kr, TS);
}

/**
 * @brief Handles serial commands for mode changes, tuning, and scope capture.
 */
void loop_communication_task()
{
    while (1) {
        received_serial_char = console_getchar();
        switch (received_serial_char) {
        case 'h':
            printk(" ________________________________________\n");
            printk("|     open-loop sine PWM                 |\n");
            printk("|     i : idle                           |\n");
            printk("|     p : power                          |\n");
            printk("|     u/j : phi +/- 0.01 rad             |\n");
            printk("|     o/l : phi_ACsource +/- 0.01 rad    |\n");
            printk("|     d/c : Mp +/- 1 %                   |\n");
            printk("|     f/v : Mp_ACsource +/- 1 %          |\n");
            printk("|     r : retrieve scope data            |\n");
            printk("|     t : trigger scope data             |\n");
            printk("|________________________________________|\n\n");
            break;
        case 'i':
            mode_asked = IDLEMODE;
            break;
        case 'p':
            if (!is_downloading) {
                scope.start();
                mode_asked = POWERMODE;
                critical_task_counter = 0;
            }
            break;
        case 'g':
            if (!is_downloading) {
                scope.start();
                mode_asked = VCREGMODE;
                critical_task_counter = 0;
            }
            break;
        case 'u':
            adjust_phase_converter(0.01F);
            break;
        case 'j':
            adjust_phase_converter(-0.01F);
            break;
        case 'o':
            adjust_phase_ACsource(0.01F);
            break;
        case 'l':
            adjust_phase_ACsource(-0.01F);
            break;
        case 'd':
            adjust_amplitude_converter(0.01F);
            break;
        case 'c':
            adjust_amplitude_converter(-0.01F);
            break;
        case 'f':
            adjust_amplitude_ACsource(0.01F);
            break;
        case 'v':
            adjust_amplitude_ACsource(-0.01F);
            break;
        case 'r':
            is_downloading = true;
            trigger = false;
            break;
        case 't':
            trigger = true;
            break;
        default:
            break;
        }
    }
}

/**
 * @brief Runs the low-rate state machine and status reporting.
 */
void loop_application_task()
{
    spin.led.toggle();

    shield.sensors.triggerTwistTempMeas(TEMP_SENSOR_1);
    meas_data = shield.sensors.getLatestValue(TEMP_SENSOR_1);
    if (meas_data != NO_VALUE) temp_1_value = meas_data;

    shield.sensors.triggerTwistTempMeas(TEMP_SENSOR_2);
    meas_data = shield.sensors.getLatestValue(TEMP_SENSOR_2);
    if (meas_data != NO_VALUE) temp_2_value = meas_data;

    switch (mode) {
    case IDLEMODE:
        if (mode_asked == POWERMODE) {
            mode = POWERMODE;
            critical_task_counter = 0;
        }
        if (mode_asked == VCREGMODE) {
            mode = VCREGMODE;
            critical_task_counter = 0;
            /* Capture the start of the v_c regulation (armed and triggered by the
             * critical task, same as Config/wScopeArm) */
            scope_arm_asked = 1;
        }
        // spin.led.turnOn();
        break;
    case POWERMODE:
        if (mode_asked == IDLEMODE) {
            mode = IDLEMODE;
        }
        // spin.led.toggle();
        break;
    case VCREGMODE:
        if (mode_asked == IDLEMODE) {
            mode = IDLEMODE;
        }
        // spin.led.toggle();
        break;
    case ERRORMODE:
        break;
    default:
        mode = ERRORMODE;
        break;
    }

    if (mode_asked == IDLEMODE) {
        mode = IDLEMODE;
    }

    /* Dump the captured buffer on the console port when asked over ThingSet
     * (Config/wScopeDump), same as the 'r' serial command */
    if (scope_dump_asked) {
        scope_dump_asked = 0;
        is_downloading = true;
        trigger = false;
    }

    if (is_downloading) {
        dump_scope_datas(scope);
        is_downloading = false;
    }

    /* blink_period_s is writable over the ThingSet shell (Config/wBlinkPeriod_s) */
    task.suspendBackgroundMs((uint32_t)(blink_period_s * 1000.0f));
}

/**
 * @brief Runs the 10 kHz control loop, protection checks, and PWM updates.
 */
void loop_critical_task()
{
    critical_task_counter++;
    
    spin.dac.setConstValue(2, 1, dac_value);

    if (overcurrent_detected()) {
        mode = ERRORMODE;
    }

    if (mode == POWERMODE) {
        update_teaching_sine();
        update_AC_source_sine();
        update_modulation_sine();
        apply_complementary_duty(delta_duty_cycle);
        start_pwm_outputs();

        if (critical_task_counter > 20 && overcurrent_detected()) {
            mode = ERRORMODE;
        }
        if (critical_task_counter > 1000 && overcurrent_detected_operation()) {
            mode = ERRORMODE;
            trigger = true;
        }
    } else if (mode == VCREGMODE) {
        regulate_vc_to_vref();
        update_teaching_sine();
        update_AC_source_sine();
        update_modulation_sine();
        apply_complementary_duty(delta_duty_cycle);
        start_pwm_outputs();

        if (critical_task_counter > 20 && overcurrent_detected()) {
            mode = ERRORMODE;
        }
        if (critical_task_counter > 1000 && overcurrent_detected_operation()) {
            mode = ERRORMODE;
            trigger = true;
        }

    } else {
        stop_pwm_outputs();
        // spin.led.turnOff();
    }

    read_measurements();
    calculate_power();
    /* sine and the Vgrid_meas just read belong to the same control step */
    vc_error = sine - Vgrid_meas;

    state_mode_scope = static_cast<float32_t>(mode);

    /* Re-arm and trigger a new capture when asked over ThingSet (Config/wScopeArm).
     * start() resets the previous trigger edge, so trigger = true is seen as a new
     * rising edge. Ignored while dumping, to keep the buffer frozen. */
    if (scope_arm_asked && !is_downloading) {
        scope_arm_asked = 0;
        scope.start();
        trigger = true;
    }
    if (critical_task_counter % SCOPE_DECIMATION == 0) {
        scope_state = static_cast<uint8_t>(scope.acquire());
    }
}

/**
 * @brief Application entry point.
 */
int main(void)
{
    setup_routine();
    return 0;
}