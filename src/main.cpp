/*
 * Copyright (c) 2026-present LAAS-CNRS
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
 * @brief  This example deploys the test of a MMC Half-Bridge (HB) module using a low-frequency sequence, now modified to be independent of a programmable source.
 *         This research was funded in whole by the French National Research Agency (ANR) under the project CARROTS "ANR-24-CE05-0920-01".
 *
 * @author Ayoub Farah Hassan <ayoub.farah-hassan@laas.fr>
 * @author Ana Luiza Haas Bezerra <ana-luiza.haas-bezerra@centralesupelec.fr>
 * @author Zaid Jabbar <zaid.jabbar@grenoble-inp.fr>
 * @author Luiz Villa <luiz.villa@laas.fr>
 * @author Jean Alinei <jean.alinei@owntech.org>
 * @author Noemi Lanciotti <noemi.lanciotti@centralesupelec.fr>
 * @author Loïc Quéval <loic.queval@centralesupelec.fr>
 */

/*--------------Zephyr---------------------------------------- */
#include <zephyr/console/console.h>

/*--------------OWNTECH APIs---------------------------------- */
#include "SpinAPI.h"
#include "ShieldAPI.h"
#include "TaskAPI.h"

/*--------------OWNTECH Libraries----------------------------- */
#include "arm_math_types.h"
#include <ScopeMimicry.h>

/*--------------SETUP FUNCTIONS DECLARATION------------------- */
/* Setups the hardware and software of the system */
void setup_routine();

/*--------------LOOP FUNCTIONS DECLARATION-------------------- */
/* Code to be executed in the background task - only sets up boards LEDs and prints measurements in terminal */
void loop_application_task();
/* Code to be executed in real time in the critical task - executes MODULE control logics */
void loop_critical_task();
/* Code to be executed in the communication task - serves to send command to board via PC using USB-C cable */
void loop_communication_task();

/*--------------USER VARIABLES DECLARATIONS------------------- */

/* [us] period of the control task */
static uint32_t control_task_period = 100; // µs
static const float32_t Ts = control_task_period * 1e-6F; // s
/* [bool] state of the PWM (ctrl task) */
static bool pwm_enable = false;

float32_t duty_cycle = 0.3;

uint8_t received_serial_char;

/* Measure variables */

static float32_t V1_low_value = 0;
static float32_t V2_low_value;
static float32_t I1_low_value;
static float32_t I2_low_value;
static float32_t I_high;
static float32_t V_high;

/* Temporary storage fore measured value (ctrl task) */
static float meas_data;

/* Scope variables */

static const uint16_t NB_DATAS = 2048; //Number of data acquired
static ScopeMimicry scope(NB_DATAS, 5); // Scope configuration with 5 channels
static bool is_downloading; // Records data if true
static bool enable_acq = false; // Sets trigger moment if true
static uint32_t scope_timer = 0;
static uint32_t scope_period = 10; // scope acquire data every t = scope_period (10) * critical_task_period (100 µs) = 1 ms;

/* SM test variables */

static uint8_t g = 2; // Gate signal of test module - define if it is at connected (1), disconnected (0) or blocked (2) state.
static float32_t g_float; // Gate signal of test module - Used for gate signal acquisition by scopemimicry
static float seq_timer = 0; // Counts time in the low-frequency sequence
static uint32_t critical_task_timer = 0;
static const float32_t decalage_source = 0;
static bool Vsource_turnoff_indicator = false; // Used to reset low-frequency sequence
static bool Vsource_ON_once_indicator = false;
static float32_t I_on = 0.5; // Current value when VDC is still ON
static float counter_ONOFF;
static float32_t f_sw_HF = 50; // Frequency of the test in Hz
static float32_t HF_period = 1/f_sw_HF; // Period of the test in s
/*--------------------------------------------------------------- */

/* --------------- LIST OF POSSIBLE BOARD MODES ------------------*/
enum serial_interface_menu_mode
{
    IDLEMODE = 0, // Before starting the low-frequency sequence
    FIRSTSEQUENCEMODE = 1, // Executes first part of sequence (VDC is ON)
    SECONDSEQUENCEMODE = 2, // Executes second part of sequence (VDC is OFF)
};

uint8_t mode = IDLEMODE;

/*--------------SCOPE FUNCTIONS------------------------------- */

/* Trigger function for scope manager */
bool a_trigger() {
    return enable_acq;
}

/* Records scope data */
void dump_scope_datas(ScopeMimicry &scope)  {
    uint8_t *buffer = scope.get_buffer();
    /* We divide by 4 (4 bytes per float data) */
    uint16_t buffer_size = scope.get_buffer_size() >> 2;
    printk("begin record\n");
    printk("#");
    for (uint16_t k=0;k < scope.get_nb_channel(); k++) {
        printk("%s,", scope.get_channel_name(k));
    }
    printk("\n");
    printk("# %d\n", scope.get_final_idx());
    for (uint16_t k=0;k < buffer_size; k++) {
        printk("%08x\n", *((uint32_t *)buffer + k));
        task.suspendBackgroundUs(100);
    }
    printk("end record\n");
}



/*--------------SETUP FUNCTIONS------------------------------- */

/**
 * This is the setup routine.
 * It is used to call functions that will initialize your spin, power shields
 * and tasks.
 */
void setup_routine()
{
    /* Buck mode */
    shield.power.initBuck(ALL);

    shield.sensors.enableDefaultTwistSensors();

    /* Disconnect or connect electrolytical capacitors from low-side */
    shield.power.connectCapacitor(LEG1);
    shield.power.disconnectCapacitor(LEG2);

    /* Enable switch control with max and min duty cycle of 1 and 0 */
    shield.power.setDutyCycleMax(ALL,1.0);
    shield.power.setDutyCycleMin(ALL,0.0);

    /* Configures scopemimicry measured variables */
    scope.connectChannel(I1_low_value, "I_SM"); // Module current
    scope.connectChannel(V1_low_value, "V_SM"); // Module voltage
    scope.connectChannel(g_float, "state"); // 1 = connected; 0 = disconnected; 2 = blocked
    scope.connectChannel(seq_timer, "time");
    scope.connectChannel(V_high, "V_high"); // Module capacitor voltage
    scope.set_trigger(&a_trigger);
    scope.set_delay(0.0F);
    scope.start();

    shield.sensors.setConversionParametersLinear(V_HIGH, 0.0298174F, -0.116135F);
    shield.sensors.setConversionParametersLinear(I_HIGH, 0.00542287F, -10.9166F);
    shield.sensors.setConversionParametersLinear(V1_LOW, 0.0452099F, -89.9364F);
    shield.sensors.setConversionParametersLinear(I1_LOW, 0.0056548F, -11.6536F);
    shield.sensors.setConversionParametersLinear(V2_LOW, 0.045172F, -88.5664F);
    shield.sensors.setConversionParametersLinear(I2_LOW, 0.00576626F, -12.6195F);

    /* Then declare tasks */
    uint32_t app_task_number = task.createBackground(loop_application_task);
    uint32_t com_task_number = task.createBackground(loop_communication_task);
    task.createCritical(loop_critical_task, control_task_period);

    /* Finally, start tasks */
    task.startBackground(app_task_number);
    task.startBackground(com_task_number);
    task.startCritical();
}

/*--------------LOOP FUNCTIONS-------------------------------- */

/**
 * This is the communication task.
 * It is used to send to the board via the computer the desired mode
 * IDLE (i) = before starting the sequence.
 * FIRST SEQUENCE (f) = start MMC module test with sequence.
 * SECOND SEQUENCE (s) = start second part of sequence (automatically changed when VDC OFF).
 *
 * It also sends scope data retrieve commands (r).
 */
void loop_communication_task()
{
    received_serial_char = console_getchar();
    switch (received_serial_char)
    {
    case 'h':
        /*----------SERIAL INTERFACE MENU----------------------- */
        printk(" ________________________________________ \n"
               "|     ---- MENU module LF test ----      |\n"
               "|     press i : idle mode                |\n"
               "|     press f : sequence first part mode |\n"
               "|     press s : sequence second part mode|\n"
               "|     press r : download datas           |\n"
               "|________________________________________|\n\n");
        /*------------------------------------------------------ */
        break;
    case 'i':
        printk("idle mode\n");
        mode = IDLEMODE;
        break;
    case 'f':
        printk("first sequence part\n");
        mode = FIRSTSEQUENCEMODE;
        enable_acq = true;
        seq_timer = 0;
        break;
    case 's':
        printk("second sequence part\n");
        mode = SECONDSEQUENCEMODE;
        seq_timer = 0.45F;
        break;
    case 'r':
        is_downloading = true;
        enable_acq = false;
        break;
    default:
        break;
    }
}

/**
 * This is the code loop of the background task
 * It runs perpetually. Here a `suspendBackgroundMs` is used to pause during
 * 1000ms between each LED toggles.
 * Hence we expect the LED to blink each 1 seconds.
 * 
 * It also prints some measurements in the terminal for user verification.
 */
void loop_application_task()
{
    if (mode == IDLEMODE)
    {
        spin.led.turnOff();
        if (is_downloading) {
            dump_scope_datas(scope);
        }
        is_downloading = false;
    }
    else if (mode == SECONDSEQUENCEMODE) // VDC is OFF
    {
        spin.led.turnOn();
    }
    else if (mode == FIRSTSEQUENCEMODE) // VDC is ON
    {
        spin.led.toggle();
    }

        printk("%.3f:", (double)I1_low_value);
        printk("%.3f:", (double)V1_low_value);
        printk("%.3f:", (double)g);
        printk("%.3f:", (double)Vsource_ON_once_indicator);
        printk("%.3f:", (double)seq_timer);
        printk("%.3f:", (double)critical_task_timer);
        printk("%.3f:", (double)scope_timer);
        printk("%i:", mode);
        printk("\n");
    task.suspendBackgroundMs(1000);
}

/**
 * This is the code loop of the critical task
 * It is executed every 100 micro-seconds defined in the setup_software
 * function.
 *
 * In the critical task, we implement the module control that will
 * run in Real Time during the test.
 * 
 * The critical task coordinates the module through the low-frequency test sequence.
 */
void loop_critical_task()
{
    /* Acquire voltage and current measurements of the module */
    meas_data = shield.sensors.getLatestValue(I1_LOW);
    if (meas_data != NO_VALUE) I1_low_value = -meas_data;
    
    meas_data = shield.sensors.getLatestValue(V1_LOW);
    if (meas_data != NO_VALUE) V1_low_value = meas_data;
    
    meas_data = shield.sensors.getLatestValue(V2_LOW);
    if (meas_data != NO_VALUE) V2_low_value = meas_data;

    meas_data = shield.sensors.getLatestValue(I2_LOW);
    if (meas_data != NO_VALUE) I2_low_value = meas_data;

    meas_data = shield.sensors.getLatestValue(I_HIGH);
    if (meas_data != NO_VALUE) I_high = meas_data;

    meas_data = shield.sensors.getLatestValue(V_HIGH);
    if (meas_data != NO_VALUE) V_high = meas_data;


    if (mode == IDLEMODE) // Before starting the low-frequency sequence
    {
        if (pwm_enable == true)
        {
            shield.power.stop(ALL);
        }
        pwm_enable = false;

        if (V1_low_value<2) // If VDC is OFF, sequence can be restarted without uploading code in the board again
        {
            Vsource_ON_once_indicator = false;
        }

        if (V1_low_value>=2 && Vsource_ON_once_indicator == false) // If VDC is ON, starts sequence with small delay
        {
            mode = FIRSTSEQUENCEMODE; // Starts sequence with first part
            enable_acq = true; // Starts scope data acquistion
            Vsource_ON_once_indicator = true;
            seq_timer = 0;
        }
    }

    else if (mode == FIRSTSEQUENCEMODE) // Executes sequence first part
    {
        
        if(seq_timer >= 0.0F && seq_timer < 0.1F) // Blocked state from 0 to 0.1 s
        {
            g=2;

        }
        if(seq_timer >= 0.1F && seq_timer < 0.2F) // Connected state from 0.1 to 0.2 s
        {
            g=1;
        }
        if(seq_timer >= 0.2F && seq_timer < 0.3F) // Disconnected state from 0.2 to 0.3 s
        {
            g=0;
            counter_ONOFF = 0;

        }
        if(seq_timer >= 0.3F && seq_timer < 0.4F) // Switches between disconnected and connected state from 0.3 to 0.4 s
        {
            /* Pulse generation at HF frequency */
            if (counter_ONOFF <= HF_period/2 - Ts) // Disconnected at first half of period
            {
                g = 0;
            }
            if (counter_ONOFF > HF_period/2 - Ts) // Connected at second half of period
            {
                g = 1;
            }
            if (counter_ONOFF >= HF_period) // reset counter if passes period value
            {
                g = 0;
                counter_ONOFF = 0;
            }
            counter_ONOFF += Ts;
        }
        if(seq_timer >= 0.4F) // Disconnected state from 0.4 s waiting for VDC to be turned OFF to start second part of the test sequence
        {
            g=0;
            counter_ONOFF = 0;
            if (I1_low_value < I_on && seq_timer >= 0.45F) // If VDC is TURNED OFF, pass to second part of the sequence
            {
                mode = SECONDSEQUENCEMODE;
                seq_timer = 0.45F;
            }
        }

        seq_timer += Ts;
    }
    else if (mode == SECONDSEQUENCEMODE) // Executes sequence second part
    {

        /* seq_timer starts at 0.45 s (set when leaving the first part) */
        if(seq_timer >= 0.45F && seq_timer < 0.7F) // Disconnected state from 0.45 to 0.5 s
        {
            g=0;
        }
        if(seq_timer >= 0.7F && seq_timer < 0.8F) // Blocked state from 0.5 to 0.6 s
        {
            g=2;
        }
        if(seq_timer >= 0.8F && seq_timer < 0.9F) // Connected state from 0.6 to 0.75 s
        {
            g=1;
        }
        if(seq_timer >= 0.9F) // Returns to IDLEMODE
        {
            mode = IDLEMODE;
        }

        seq_timer += Ts;
    }

    /* Scope data acquisition */
    g_float = (float)g;
        
    if (scope_timer == scope_period)
    {
        scope.acquire();
        scope_timer = 0;
    }
    scope_timer++;

    /* Module states programming */
    if(g == 0) //If g = 0, module is at disconnected state
    {
        shield.power.setDutyCycle(LEG1,0.0); // Duty cycle = 0 makes Q1 open and Q2 closed
        if (!pwm_enable)
        {
            pwm_enable = true;
            shield.power.start(LEG1);
        }
    }
    if(g == 1) //If g = 1, module is at connected state
    {
        shield.power.setDutyCycle(LEG1,1.0); // Duty cycle = 1 makes Q1 closed and Q2 open
        if (!pwm_enable)
        {
            pwm_enable = true;
            shield.power.start(LEG1);
        }
    }            
    if(g == 2) //If g = 2, module is at blocked state
    {
        if (pwm_enable == true)
        {
            shield.power.stop(ALL); // Makes Q1 open and Q2 open
        }
        pwm_enable = false;
    }
    critical_task_timer++;

}

/**
 * This is the main function of this example
 * This function is generic and does not need editing.
 */
int main(void)
{
    setup_routine();

    return 0;
}