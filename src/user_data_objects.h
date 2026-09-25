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
 * @brief  ThingSet data object definitions for the sensor calibration:
 *         a read-only "Measurements" group holding the raw sensor values
 *         (conversion gain = 1, offset = 0) and a writable "Config" group
 *         to drive the converter from MATLAB.
 */

#include <stdint.h>
#include <string.h>

#include <thingset.h>
#include <thingset/sdk.h>

#define ID_ROOT        0x00

#define ID_MEAS         0x5
#define ID_MEAS_V_HIGH  0x50
#define ID_MEAS_V1_LOW  0x51
#define ID_MEAS_V2_LOW  0x52
#define ID_MEAS_I1_LOW  0x53
#define ID_MEAS_I2_LOW  0x54
#define ID_MEAS_I_HIGH  0x55
#define ID_MEAS_MODE    0x56

#define ID_CONFIG            0x6
#define ID_CONFIG_MODE       0x60
#define ID_CONFIG_DUTY_CYCLE 0x61
#define ID_CONFIG_BLINK_PERIOD 0x62

#define SUBSET_SER (1U << 0)

/* Raw sensor values, updated by the critical task in main.cpp. Since the
 * conversion parameters are set to gain = 1 and offset = 0, these are the
 * raw ADC values ("_raw" unit suffix). */
static float32_t V_high;
static float32_t V1_low_value;
static float32_t V2_low_value;
static float32_t I1_low_value;
static float32_t I2_low_value;
static float32_t I_high;

enum ConverterState : uint8_t
{
    IDLEMODE = 0,
    POWERMODE1 = 1, /* LEG1 at duty cycle 1.0: calibration of the LOW1 side */
    POWERMODE2 = 2  /* LEG2 at duty cycle 1.0: calibration of the LOW2 side */
};

/* Current converter mode, updated by main.cpp */
static uint8_t mode = IDLEMODE;

/* Writable over the ThingSet shell */
static uint8_t mode_asked = IDLEMODE;
/* LED blink half-period, in seconds */
static float32_t blink_period_s = 1.0F;

THINGSET_ADD_GROUP(ID_ROOT, ID_MEAS, "Measurements", THINGSET_NO_CALLBACK);

THINGSET_ADD_ITEM_FLOAT(ID_MEAS, ID_MEAS_V_HIGH, "rVHigh_raw", &V_high, 2,
                        THINGSET_ANY_R, SUBSET_SER);
THINGSET_ADD_ITEM_FLOAT(ID_MEAS, ID_MEAS_V1_LOW, "rV1Low_raw", &V1_low_value, 2,
                        THINGSET_ANY_R, SUBSET_SER);
THINGSET_ADD_ITEM_FLOAT(ID_MEAS, ID_MEAS_V2_LOW, "rV2Low_raw", &V2_low_value, 2,
                        THINGSET_ANY_R, SUBSET_SER);
THINGSET_ADD_ITEM_FLOAT(ID_MEAS, ID_MEAS_I1_LOW, "rI1Low_raw", &I1_low_value, 2,
                        THINGSET_ANY_R, SUBSET_SER);
THINGSET_ADD_ITEM_FLOAT(ID_MEAS, ID_MEAS_I2_LOW, "rI2Low_raw", &I2_low_value, 2,
                        THINGSET_ANY_R, SUBSET_SER);
THINGSET_ADD_ITEM_FLOAT(ID_MEAS, ID_MEAS_I_HIGH, "rIHigh_raw", &I_high, 2,
                        THINGSET_ANY_R, SUBSET_SER);
THINGSET_ADD_ITEM_UINT8(ID_MEAS, ID_MEAS_MODE, "rMode", &mode,
                        THINGSET_ANY_R, SUBSET_SER);

THINGSET_ADD_GROUP(ID_ROOT, ID_CONFIG, "Config", THINGSET_NO_CALLBACK);

/* 0 = idle, 1 = LEG1 at duty cycle 1.0, 2 = LEG2 at duty cycle 1.0 */
THINGSET_ADD_ITEM_UINT8(ID_CONFIG, ID_CONFIG_MODE, "wmode",
                        &mode_asked, THINGSET_ANY_RW, SUBSET_SER);
/* LED blink half-period, in seconds: writing it changes the blink rate
 * immediately, which shows live that the ThingSet link works */
THINGSET_ADD_ITEM_FLOAT(ID_CONFIG, ID_CONFIG_BLINK_PERIOD, "wBlinkPeriod_s",
                        &blink_period_s, 2, THINGSET_ANY_RW, SUBSET_SER);
