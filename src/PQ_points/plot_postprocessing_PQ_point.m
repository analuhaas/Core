%% Plot PQ points

load("PQpoint_20261013_181900.mat");
t_Pico = t_scope1; % [µs]
P_init = Pfft;
Q_init = Qfft;

figure(1), hold on
subplot(3,1,1), box on, grid on, hold on

plot(t_Pico,v_ac_2,'-','LineWidth',1);
plot(t_Pico,v_ac,'-','LineWidth',1);

ylim([-20, 20])
ylabel('$v$ [V]','Interpreter','latex')
legend('$v_{s}$','$v_{c}$','Interpreter','latex'), legend boxon % R2018b and later

subplot(3,1,2), box on, grid on, hold on

plot(t_Pico,v_dac,'-','LineWidth',1);

ylim([-1, 1])
ylabel('$v_{DAC}$ [V]','Interpreter','latex')

subplot(3,1,3), box on, grid on, hold on

plot(t_Pico,i_ac_2,'-','LineWidth',1);
text(0.07,1.4,"$I_{rms}=$ "+string(round(Ia_rms,2))+" A",'Interpreter','latex')

ylim([-2, 2])
ylabel('$i_{a}$ [A]','Interpreter','latex')
xlabel('$time$ [s]','Interpreter','latex')

figure(2), box on, grid on, hold on

plot(t_Pico,v_ac_2,'-','LineWidth',1);
plot(t_Pico,v_dac.*20,'-','LineWidth',1);

ylim([-20, 20])
ylabel('$v$ [V]','Interpreter','latex')
legend('$v_{s}$','$v_{DAC} \cdot 20$','Interpreter','latex'), legend boxon % R2018b and later
xlabel('$time$ [s]','Interpreter','latex')

figure(3), axis square, box on, grid on, hold on

plot(Pfft,Qfft,'o','LineWidth',1);

ylim([-50, 50])
xlim([-50, 50])
ylabel('$Q$ [VAr]','Interpreter','latex')
xlabel('$P$ [W]','Interpreter','latex')

%% Temperature plot

load("TempMonitor_20261013_193748.mat");

figure(4), box on, grid on, hold on

plot(tempMonitorTime_s./60,tempMonitorTemp2,'-o','LineWidth',1);
plot(tempMonitorTime_s./60,tempMonitorTemp1,'-o','LineWidth',1);

ylim([30, 40])
xlim([0, 30])
legend('$T_{Q1,case}$','$T_{Q1,drain}$','Interpreter','latex'), legend boxon % R2018b and later
ylabel('$T$ [$^o$C]','Interpreter','latex')
xlabel('$time$ [min]','Interpreter','latex')

%% v_s change

load("PQpoint_20261013_181900.mat");
t_Pico_init = t_scope1; % [µs]
vs_init = v_ac_2;
v_dac_init = v_dac;
load("PQpoint_20261013_183150.mat");
t_Pico_Mp09 = t_scope1; % [µs]
vs_Mp09 = v_ac_2;
v_dac_Mp09 = v_dac;
t_sync = 0.0103;

figure(5), box on, grid on, hold on

plot(t_Pico_init,vs_init,'-','LineWidth',1);
plot(t_Pico_Mp09+t_sync,vs_Mp09,'-','LineWidth',1);
% plot(t_Pico_init,v_dac_init.*20,'-','LineWidth',1);
% plot(t_Pico_Mp09+t_sync,v_dac_Mp09.*20,'-','LineWidth',1);

ylim([-20, 20])
xlim([0.02, 0.06])
ylabel('$v$ [V]','Interpreter','latex')
legend('$v_{s,init}$','$v_{s,Mp=0.09}$','Interpreter','latex'), legend boxon % R2018b and later
xlabel('$time$ [s]','Interpreter','latex')

load("PQpoint_20261013_183224.mat");
t_Pico_Mp09 = t_scope1; % [µs]
vs_Mp09 = v_ac_2;
v_dac_Mp09 = v_dac;
t_sync = 0.0002;

figure(6), box on, grid on, hold on

plot(t_Pico_init,vs_init,'-','LineWidth',1);
plot(t_Pico_init,v_dac_init.*20,'-','LineWidth',1);
plot(t_Pico_Mp09+t_sync,vs_Mp09,'-','LineWidth',1);
plot(t_Pico_Mp09+t_sync,v_dac_Mp09.*20,'-','LineWidth',1);

ylim([-20, 20])
xlim([0.02, 0.06])
ylabel('$v$ [V]','Interpreter','latex')
legend('$v_{s,init}$','$v_{DAC,init}$','$v_{s,Mp=0.09}$','$v_{DAC,Mp=0.09}$','Interpreter','latex'), legend boxon % R2018b and later
xlabel('$time$ [s]','Interpreter','latex')
%% Save figure
addpath('C:\Users\ana\Documents\PhD\Presentations et livrables\Templates_Loic\figure_PP_QUEVAL_20231221\core') % Add figure_PP folder to the path

% figure_PP(1,'Figures/FirstPQpoints/setMp0phi02_realigned.png','width',8.75,'height',6) % Export to .png
% figure_PP(2,'Figures/FirstPQpoints/vsvDACchange_setMp09_realigned.png','width',8.75,'height',6) % Export to .png
% figure_PP(3,'Figures/FirstPQpoints/multiple_PQ_points.png','width',8.75,'height',6) % Export to .png

% figure_PP(4,'Figures/FirstPQpoints/temp.png','width',8.75,'height',6) % Export to .png

figure_PP(6,'Figures/FirstPQpoints/vschange_afterregulation.png','width',8.75,'height',6) % Export to .png