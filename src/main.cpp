/*
 * Copyright (c) 2021-present LAAS-CNRS
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
 * @brief  This example demonstrates how to deploy a Buck converter with
 *         voltage mode control on the Twist power shield.
 *
 * @author Clément Foucher <clement.foucher@laas.fr>
 * @author Luiz Villa <luiz.villa@laas.fr>
 * @author Ayoub Farah Hassan <ayoub.farah-hassan@laas.fr>
 */

/*--------------OWNTECH APIs---------------------------------- */
#include "SpinAPI.h"
#include "ShieldAPI.h"
#include "TaskAPI.h"

/*--------------OWNTECH Libraries----------------------------- */


/*--------------ThingSet objects------------------------------ */
/* Raw measurements, mode and duty cycle exposed on the ThingSet shell */
#include "user_data_objects.h"

/*--------------SETUP FUNCTIONS DECLARATION------------------- */
/* Setups the hardware and software of the system */
void setup_routine();

/*--------------LOOP FUNCTIONS DECLARATION-------------------- */
/* Code to be executed in the background task */
void loop_application_task();
/* Code to be executed in real time in the critical task */
void loop_critical_task();

/*--------------USER VARIABLES DECLARATIONS------------------- */

/* [us] period of the control task */
static uint32_t control_task_period = 100;
/* [bool] state of the PWM (ctrl task) */
static bool pwm_enable = false;

/* Measure variables (the six raw sensor values are declared in
 * user_data_objects.h) */

static float32_t temp_1_value;
static float32_t temp_2_value;

/* Temporary storage fore measured value (ctrl task) */
static float meas_data;

static float32_t duty_cycle = 0.3F;

/*--------------------------------------------------------------- */

/*--------------SETUP FUNCTIONS------------------------------- */

/**
 * This is the setup routine.
 * Here the setup :
 *  - Initializes the power shield in Buck mode
 *  - Initializes the power shield sensors
 *  - Initializes the PID controller
 *  - Spawns three tasks.
 */
void setup_routine()
{
    /* Buck voltage mode */
    shield.power.initBuck(ALL);

    shield.sensors.enableDefaultTwistSensors();

    shield.power.disconnectCapacitor(LEG1);
    shield.power.disconnectCapacitor(LEG2);
    
    /* Enable switch control with max and min duty cycle*/
    shield.power.setDutyCycleMax(ALL,1.0);
    shield.power.setDutyCycleMin(ALL,0.0);

    shield.sensors.setConversionParametersLinear(V_HIGH, 1,0);
    shield.sensors.setConversionParametersLinear(V1_LOW, 1,0);
    shield.sensors.setConversionParametersLinear(V2_LOW, 1,0);
    shield.sensors.setConversionParametersLinear(I1_LOW, 1,0);
    shield.sensors.setConversionParametersLinear(I2_LOW, 1,0);
    shield.sensors.setConversionParametersLinear(I_HIGH, 1,0);

    /* Then declare tasks */
    uint32_t app_task_number = task.createBackground(loop_application_task);
    task.createCritical(loop_critical_task, 100);

    /* Finally, start tasks */
    task.startBackground(app_task_number);
    task.startCritical();
}

/*--------------LOOP FUNCTIONS-------------------------------- */

/**
 * This is the code loop of the background task
 * It blinks the LED and reads the temperature sensors. Measurements are
 * read over the ThingSet shell.
 */
void loop_application_task()
{
    /* Heartbeat: a blink rate change after writing Config/wBlinkPeriod_s
     * shows that the ThingSet link works */
    spin.led.toggle();

    if (mode != IDLEMODE)
    {
        shield.sensors.triggerTwistTempMeas(TEMP_SENSOR_1);
        shield.sensors.triggerTwistTempMeas(TEMP_SENSOR_2);

        meas_data = shield.sensors.getLatestValue(TEMP_SENSOR_1);
        if (meas_data != NO_VALUE) temp_1_value = meas_data;

        meas_data = shield.sensors.getLatestValue(TEMP_SENSOR_2);
        if (meas_data != NO_VALUE) temp_2_value = meas_data;
    }

    /* blink_period_s is writable over the ThingSet shell (Config/wBlinkPeriod_s) */
    if (blink_period_s < 0.05F) blink_period_s = 0.05F;
    task.suspendBackgroundMs((uint32_t)(blink_period_s * 1000.0F));
}

/**
 * This is the code loop of the critical task
 * This task runs at 10kHz.
 *  - It retrieves sensors values
 *  - It runs the PID controller
 *  - It update the PWM signals
 */
void loop_critical_task()
{
    meas_data = shield.sensors.getLatestValue(I1_LOW);
    if (meas_data != NO_VALUE) I1_low_value = meas_data;

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

    /* Mode requested over ThingSet (Config/wmode), unknown values -> idle */
    uint8_t new_mode = (mode_asked == POWERMODE1 || mode_asked == POWERMODE2)
                       ? mode_asked : IDLEMODE;

    /* Stop the PWM when the mode changes (to idle or to the other leg) */
    if (new_mode != mode && pwm_enable)
    {
        shield.power.stop(ALL);
        pwm_enable = false;
    }
    mode = new_mode;

    if (mode == POWERMODE1)
    {
        shield.power.setDutyCycle(LEG1, 1.0);
        if (!pwm_enable)
        {
            pwm_enable = true;
            shield.power.start(LEG1);
        }
    }
    else if (mode == POWERMODE2)
    {
        shield.power.setDutyCycle(LEG2, 1.0);
        if (!pwm_enable)
        {
            pwm_enable = true;
            shield.power.start(LEG2);
        }
    }

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
