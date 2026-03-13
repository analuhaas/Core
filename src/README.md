# MMC arm - with CVB using overvoltage and overcurrent protection

Important remark: this code will be modified by adding a median filter to the voltage and current measurements used for protection criteria to avoid cutting converter operation only for measurement misreading or spikes.

## Objectives and context

The goal of this tutorial is to test a MMC stack built with TWIST boards operation with open-loop control using NLM modulation strategy with CVB. For that, we use the two circuit structure below. $R_{dec}$ resistance is connected in parallel to the stack for circuit #2 in order to emulate negative currents discharging the modules capacitor.

<img width="877" height="492" alt="image" src="https://github.com/user-attachments/assets/7ffc269f-ad4d-4e96-b236-9b2980b45c47" />

As in the individual module test, the boards serves as a HB module of the MMC by programming its second leg (LEG2) to be deactivated, having the following circuit. Observe that the HIGH terminals are open (Vhigh to GND).

<img width="930" height="292" alt="image" src="https://github.com/user-attachments/assets/3bc7e36b-9bef-45b2-9e8a-13c7874987e6" />

The NLM modulation consists of attributing levels according to the modulation signal amplitude using the function round such that the level attributed to the modulation signal is the nearest integer and its principle is represented here:

<img width="535" height="92" alt="image" src="https://github.com/user-attachments/assets/a7d0384c-7ccd-4b5b-b8bb-02fe5b1ab2db" />

For example, if the modulation signal is 2.6, it is going to be attributed to level 3. For the MMC, the modulation signal is a sinusoidal wave, making that the NLM modulation result is a stepped wave-form as shown:

<img width="696" height="477" alt="image" src="https://github.com/user-attachments/assets/652b14d5-0b4e-4edc-a10d-a62d95be79a6" />

This stepped wave-form output of the NLM indicates how many modules should be connected in the stack ($N_{\left(u,l\right),p}^{on}$) according to time.

The CVB algorithm consists of choosing which modules to connect in order to have equilibrated voltage between all modules. The CVB algorithm makes is choice according to measured capacitor voltages and stack current as described in the algorithm schematic:

<img width="945" height="390" alt="image" src="https://github.com/user-attachments/assets/e4291600-ff51-4ed6-85ec-379306f665cd" />

It then generates the command to connect or disconnect the modules by setting the gate command signals ($g_{\left(u,l\right),p}^{M1}$, $g_{\left(u,l\right),p}^{M2}$,..., $g_{\left(u,l\right),p}^{MN}$, to 1 (module connected) or 0 (module disconnected). The complete schematic of the open-loop control implemented:

<img width="677" height="296" alt="image" src="https://github.com/user-attachments/assets/12229f3c-7100-4309-bea4-1ddf11bbbbc0" />

The difference between this example and the arm CVB example is that overvoltage and overcurrent protections are implemented. The protections avoid material damage by setting a limit for capacitor voltage and current using the variables:

```
constexpr float32_t overvoltage_tolerance = 80.0F; //[V] Set overvoltage tolerance (default max TWIST voltage)
constexpr float32_t overcurrent_tolerance = 8.0F; //[A] Set overcurrent tolerance (default max TWIST current)
```

If the module reaches any of these limits, it sends an error message to the LEAD to stop arm operatio, putting all modules to blocked state (equivalent to IDLE). This is done on the lines of code on the communication reception_fucntion():
```
/* Verifies overvoltage protection criteria */
if(Cap_voltage > overvoltage_tolerance)
{
    mmc_frame_set_status_code(dataTX_mmc, OVER_VOLTAGE);
}
/* Verifies overcurrent protection criteria */
else if(Arm_current > overcurrent_tolerance)
{
    mmc_frame_set_status_code(dataTX_mmc, OVER_CURRENT);
}
else{
    mmc_frame_set_status_code(dataTX_mmc, POWER);
}
```

## Required Hardware list

- 6 TWIST boards with SPIN
- 6 independent DC power supplies of 6 V with minimum 0.5 A
- 1 DC power supply of (48 V, 5 A)
- Protection diode (at least 100 V)
- 2 resistors of 15\ \Omega
- 5 ethernet cables
- PC 64-bits (windows or linux)
- Oscilloscope
- Current probe
- 6 BNC adaptors to differential voltage measurement

## Required Software list

- Git
- Visual Studio Code with PlatformIO

## Get tutorial code from VScode

First, we need to load the Single module test code from the OwnTech example repository version in https://github.com/analuhaas/examples 
1.	In VScode, open the folder where you previously cloned OwnTech’s github.
2.	In platformio.ini file, substitute the owntech_examples variable link by https://github.com/analuhaas/examples.git 
3.	Go to platform.io icon <img width="35" height="36" alt="image" src="https://github.com/user-attachments/assets/a5ff4ce7-f50e-4b0f-ba3e-278e39ba8759" />, go to Examples Twist under the Project Tasks tab and click on “MMC arm – with CVB”.

<img width="456" height="358" alt="image" src="https://github.com/user-attachments/assets/2f3caa34-4f95-4899-8ae6-8140fafcd1a4" />

 
4.	Now you have the good code to execute the tutorial in your VScode.

## Modules hardware setup

Repeat for the 5 modules boards:

5.	Recommended for MMC use: Configure all 5 modules boards to feed the 6 V auxiliary input externally with feeder completely disconnected from the electrical circuit of the board.

- Connect an External Auxiliary DC Power Supply to the TWIST via the 6 V and DGND PINs. Make sure the External Auxiliary DC Power Supply is configured to deliver 6 V with limiting current above 0.5 A. Make sure this power supply OUTPUT IS OFF.

<img width="484" height="398" alt="image" src="https://github.com/user-attachments/assets/89267671-91ce-411c-99ab-36a19fc275a7" />


- Open the jumper JP5001 of the board by cutting the jumper connections using a cutter with an appropriate camera to see the area

<img width="905" height="407" alt="image" src="https://github.com/user-attachments/assets/84dd4df1-c966-4998-95a8-e7bf83aeee31" />


6.	If not done yet: Test the module using the low-frequency and high-frequency sequences as explained in Individual MMC module test.

## Stack Hardware setup

7.	Connect the boards in series using VLOW1 and GND terminals to form an MMC stack using banana cables (figure below).
8.	Connect to each module an External Auxiliary DC Power Supply to the TWIST via the 6 V and DGND PINs. Make sure the External Auxiliary DC Power Supplies are configured to deliver 6 V with limiting current above 0.5 A. Make sure these power supplies OUTPUT IS OFF (figure below).
9.	Connect the boards using ethernet cables as in the image (figure below).
10.	Connect the stack to the main DC power supply, R and Rdec resistances and diode (figure below).

!!! If using circuit#1, remove Rdec from the circuit. If using circuit #2, circuit exactly as in the image.

<img width="804" height="700" alt="image" src="https://github.com/user-attachments/assets/ae3bf984-800b-426d-9439-370ea5f45de4" />

11.	Connect the voltage and current measurements with the oscilloscope (figure below). 

<img width="945" height="1202" alt="image" src="https://github.com/user-attachments/assets/2417675d-3c91-4788-a488-e856fa2a799a" />

After making the connections and connecting the PC to the central controller board with the USB-C cable, you should have something like this:

<img width="2244" height="1684" alt="stack_test_hardware_ready" src="https://github.com/user-attachments/assets/63024a10-321a-41fe-8a15-76b63a56be7d" />

12.	Configure your Oscilloscope with PicoScope (tutorial using PicoScope 4444)

a.	Make sure it acquires the following measurements:

i.	Modules capacitor voltages (Vhigh to GND).

ii.	Stack current.

iii.	Stack voltage.

b.	Use a 10 s/div configuration with sampling interval around 1 µs (x5 smaller than critical task period)

<img width="238" height="458" alt="image" src="https://github.com/user-attachments/assets/3bdea09e-6b20-4ab2-a566-6c5924089539" />

c.	Configure it to trigger when the stack voltage rises up to 2 V.

<img width="380" height="551" alt="image" src="https://github.com/user-attachments/assets/3a5615e3-1104-4a32-88dd-26be1026328f" />

## Executing the tutorial Stack test

13.	Get the correct test code using “MMC arm – with CVB”  button.
14.	Optional: Change the test parameters to have a more specific test:

  a.	In code: NLM frequency, number of modules.

  b.	In circuit: Number of modules, resistance values (to reduce or increase current), DC supply voltage.
  
  
15.	Repeat to all 5 module boards M1, M2, M3, M4, M5:
  
  a.	Connect the board to the PC via a USB-C cable.
  
  b.	Build <img width="25" height="27" alt="image" src="https://github.com/user-attachments/assets/028ecb2b-5d25-4383-8ece-c51cb804c64f" /> and Upload <img width="34" height="25" alt="image" src="https://github.com/user-attachments/assets/5af20606-e19c-46fd-870b-326c0d855a70" /> the code main.cpp into the board.
  
  c.	Open the serial monitor and copy the board ID to the identification list in the code according to its function in the stack


```
  /* -------------- BOARD IDENTIFICATION ----------------------- */
  
  
  constexpr uint32_t UID_MMC_LEAD_BOARD = 0x002B002A;
  
  constexpr uint32_t UID_MMC_SM1_BOARD = 0x00330054;
  
  constexpr uint32_t UID_MMC_SM2_BOARD = 0x0033004B;
  
  constexpr uint32_t UID_MMC_SM3_BOARD = 0x00330049;
  
  constexpr uint32_t UID_MMC_SM4_BOARD = 0x0033004C;
  
  constexpr uint32_t UID_MMC_SM5_BOARD = 0x0031001B;
  
  constexpr uint32_t UID_MMC_SM6_BOARD = 0x11118888;
  
  constexpr uint32_t UID_MMC_SM7_BOARD = 0x11119999;
  
  constexpr uint32_t UID_MMC_SM8_BOARD = 0x1111AAA0;
  
  constexpr uint32_t UID_MMC_SM9_BOARD = 0x1111BBB1;
  
  constexpr uint32_t UID_MMC_SM10_BOARD = 0x1111CCC2;
```


  d.	Do again: Build <img width="25" height="27" alt="image" src="https://github.com/user-attachments/assets/028ecb2b-5d25-4383-8ece-c51cb804c64f" /> and Upload <img width="34" height="25" alt="image" src="https://github.com/user-attachments/assets/5af20606-e19c-46fd-870b-326c0d855a70" /> the code main.cpp into the board.


16. Build <img width="25" height="27" alt="image" src="https://github.com/user-attachments/assets/028ecb2b-5d25-4383-8ece-c51cb804c64f" /> and Upload <img width="34" height="25" alt="image" src="https://github.com/user-attachments/assets/5af20606-e19c-46fd-870b-326c0d855a70" /> the code main.cpp into the Central Controller board.
17. Make sure all modules External Auxiliary DC Power Supply are configured to deliver 6 V with limiting current above 0.5 A. TURN ON the External Auxiliary DC Power Supplies output.
18. After the capacitor voltages comes back to 0, TURN ON the main power supply $u_{dc}$.
19. After the modules are charged with stable voltages more and less at the same level, click “p” to start stack operation with NLM (with or without CVB).
20. After 20 s, TURN OFF the main power supply $u_{dc}$.
21. Click “i” to stop stack operation and put all boards in IDLE mode (blocked state).
22. TURN OFF all 6V External Auxiliary DC Power Supplies.

## Expected results

If you perform the stack test using 1 module only and surpass the voltage limit, you should have a result like this:

<img width="1472" height="673" alt="image" src="https://github.com/user-attachments/assets/16012de6-b28f-4337-95ce-30718bc936c0" />

If you perform the stack test using 1 module only and surpass the current limit, you should have a result like this:

<img width="1472" height="673" alt="image" src="https://github.com/user-attachments/assets/58b87250-8fd2-4f9c-8305-b327e7846531" />

We can see that in both situations the module is set to blocked state.

The results for arm test should be the same for the CVB code if the voltage and current limits are respected.

If you perform the stack test with CVB using circuit#1 at 50 Hz, you should expect an experimental result like this:

<img width="945" height="432" alt="image" src="https://github.com/user-attachments/assets/b53197df-0e04-4373-9a4e-19670d97a4fc" />

If you perform the stack test with CVB using circuit#2 at 50 Hz, you should expect an experimental result like this:

<img width="945" height="432" alt="image" src="https://github.com/user-attachments/assets/3a35088d-f8fa-441f-a22e-0f7094d812e8" />

For better results using circuit#2, add extra capacitance in parallel to high-side terminals (Vhigh and GND). You should expect an experimental result like this:

<img width="945" height="432" alt="image" src="https://github.com/user-attachments/assets/d177bde0-d9d4-441b-9ec5-e075368b804e" />
