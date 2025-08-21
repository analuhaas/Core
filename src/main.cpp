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
 * @brief  This example shows how to blink the onboard LED of the Spin board.
 *
 * @author Clément Foucher <clement.foucher@laas.fr>
 * @author Luiz Villa <luiz.villa@laas.fr>
 * @author Ayoub Farah Hassan <ayoub.farah-hassan@laas.fr>
 */

/*--------------Zephyr---------------------------------------- */
#include <zephyr/console/console.h>

/* --------------OWNTECH APIs---------------------------------- */
#include "SpinAPI.h"
#include "TaskAPI.h"

/* --------------External libraries---------------------------- */
#include "stdlib.h" // C standard library, obtain atoi function

/* --------------SETUP FUNCTIONS DECLARATION------------------- */

/* Setups the hardware and software of the system */
void setup_routine();

/* --------------LOOP FUNCTIONS DECLARATION-------------------- */

/* Code to be executed in the slow communication task */
void loop_communication_task();
/* Code to be executed in the background task */
void loop_background_task();
/* Code to be executed in real time in the critical task */
void loop_critical_task();


/* --------------USER VARIABLES DECLARATIONS------------------- */
/* Serial command */
uint8_t received_serial_char;

/* Voltage reference */
static float32_t voltage_reference = 5;

/* Pad variables */
char buffer[4]; 
int index = 0;
float new_voltage_reference = 0.0;
bool enter_captured = false; 

/* LIST OF POSSIBLE MODES FOR THE OWNTECH CONVERTER */
enum serial_interface_menu_mode
{
    IDLEMODE = 0,
    POWERMODE
};

uint8_t mode = IDLEMODE;

/* --------------SETUP FUNCTIONS------------------------------- */

/**
 * This is the setup routine.
 * It is used to call functions that will initialize your spin, power shields
 * and tasks.
 *
 * In this example, we spawn a background task.
 * An optional critical task can be initialized by uncommenting the two
 * commented lines.
 */
void setup_routine()
{
    /* Declare task */
    uint32_t background_task_number = task.createBackground(loop_background_task);
    uint32_t com_task_number = task.createBackground(loop_communication_task);

    /* Uncomment following line if you use the critical task */
    /* task.createCritical(loop_critical_task, 500); */

    /* Finally, start tasks */
    task.startBackground(background_task_number);
    task.startBackground(com_task_number);
    /* Uncomment following line if you use the critical task */
    /* task.startCritical(); */
}

/* --------------LOOP FUNCTIONS-------------------------------- */

/**
 * This is the code loop of the background task
 * It runs perpetually. Here a `suspendBackgroundMs` is used to pause during
 * 1000ms between each LED toggles.
 * Hence we expect the LED to blink each second.
 */
void loop_background_task()
{
    if (mode == IDLEMODE)
    {
        /* Task content */
        spin.led.toggle();

    }
    if (mode == POWERMODE)
    {
        spin.led.turnOn();
        printk("%1.f:", voltage_reference);
        printk("\n");
    }

    /* Pause between two runs of the task */
    task.suspendBackgroundMs(1000);
}

/**
 * This tasks implements a minimalistic USB serial interface to control
 * the buck converter.
 */
void loop_communication_task()
{
    received_serial_char = console_getchar();
    switch (received_serial_char)
    {
    case 'h':
        /*----------SERIAL INTERFACE MENU----------------------- */
        printk(" ________________________________________ \n"
            "|     ---- MENU buck voltage mode ----   |\n"
            "|     press i : idle mode                |\n"
            "|     press p : power mode               |\n"
            "|     press r : record data              |\n"
            "|     press a : toggle enable_acq var    |\n"
            "|________________________________________|\n\n");
        /*------------------------------------------------------ */
        break;
    case 'i':
        printk("idle mode\n");
        mode = IDLEMODE;
        break;
    case 'p':
        printk("power mode\n");
        printk("Voltage output is initialized at %f V\n", voltage_reference);
        printk("Enter the new voltage output (between 0 and 10 V): ");
        mode = POWERMODE;
        break;
    default:
        break;
    }
    
     
    
    if (received_serial_char == '\n') {
        enter_captured = true; 
    }
    
    else if (received_serial_char >= '0' && received_serial_char <= '9' && index < 3) {
        buffer[index] = received_serial_char;
        buffer[index+1] = '\0';
        index++;
    }

    if (enter_captured == true) {
        new_voltage_reference = atoi(buffer);
        if (new_voltage_reference < 0 || new_voltage_reference > 10) {
            index = 0;
            buffer[0] = '\0';
            printk("Invalid input. Voltage reference must be between 0 and 10 V.\n");
        } else {
            voltage_reference = new_voltage_reference;
            index = 0;
            buffer[0] = '\0';
            printk("Voltage reference set to %f V.\n", voltage_reference);
        }
        enter_captured = false;
    }
    
}

/**
 * Uncomment lines in setup_routine() to use critical task.
 *
 * This is the code loop of the critical task
 * It is executed every 500 micro-seconds defined in the setup_software
 * function. You can use it to execute an ultra-fast code with
 * the highest priority which cannot be interrupted by the background tasks.
 *
 * In the critical task, you can implement your control algorithm that will
 * run in Real Time and control your power flow.
 */
void loop_critical_task()
{

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
