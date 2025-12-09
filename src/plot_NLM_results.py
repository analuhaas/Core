import pandas as pd
import matplotlib.pyplot as plt

# Load the CSV file
df = pd.read_csv('src/Data_records/2025-12-09_18-15-14-record.csv')

# Defina os períodos
scope_period = 1  # exemplo, ajuste conforme o seu caso
critical_task_period = 1e-6   # exemplo, ajuste conforme o seu caso

# Filtra dados (os quatro gráficos usam a mesma filtragem)
mask = (df.iloc[:, 0] > 0) & (df.iloc[:, 0] < 500)
t_filtered = df.iloc[:, 0][mask] * scope_period * critical_task_period  # tempo em segundos

# Dados do primeiro gráfico: m_u e m_l
m_u_filtered = df['m_u'][mask]


# Dados do primeiro gráfico: N_u e N_l
N_u_filtered = df['N_u'][mask]


# Dados dos gate signals
g_u_1_filtered = df['g_u_1'][mask]
g_u_2_filtered = df['g_u_2'][mask]
g_u_3_filtered = df['g_u_3'][mask]
g_u_4_filtered = df['g_u_4'][mask]
g_u_5_filtered = df['g_u_5'][mask]
v_c_1_filtered = df['v_c_1'][mask]
v_c_2_filtered = df['v_c_2'][mask]
v_c_3_filtered = df['v_c_3'][mask]
v_c_4_filtered = df['v_c_4'][mask]
v_c_5_filtered = df['v_c_5'][mask]

# Dados do primeiro gráfico: i_u
i_u_filtered = df['i_u'][mask]
i_u_filtered_LP = df['i_u_filtered'][mask]

# Cria os subplots
fig, axs = plt.subplots(8, 1, figsize=(10, 10), sharex=True)

# Subplot 1: N_u e N_l
axs[0].plot(t_filtered, N_u_filtered, label='Nb of inserted modules N_on_u')
axs[0].plot(t_filtered, m_u_filtered*5, label='Modulation signal m_u')
axs[0].set_ylabel('N_on [-]')
axs[0].set_title('NLM test for upper arm: i_u > 0 and v_c_1 < v_c_3 < v_c_2')
axs[0].legend()
axs[0].grid(True)

# Subplot 2: g_u_1
axs[1].plot(t_filtered, g_u_1_filtered, label='g_u_1 (1 = module ON, 0 = module OFF)', color='tab:blue')
axs[1].set_ylabel('g [-]')
axs[1].legend()
axs[1].grid(True)

# Subplot 3: g_u_2
axs[2].plot(t_filtered, g_u_2_filtered, label='g_u_2 (1 = module ON, 0 = module OFF)', color='tab:orange')
axs[2].set_ylabel('g [-]')
axs[2].legend()
axs[2].grid(True)

# Subplot 4: g_u_3
axs[3].plot(t_filtered, g_u_3_filtered, label='g_u_3 (1 = module ON, 0 = module OFF)', color='tab:green')
axs[3].set_ylabel('g [-]')
axs[3].legend()
axs[3].grid(True)

# Subplot 5: g_u_3
axs[4].plot(t_filtered, g_u_4_filtered, label='g_u_4 (1 = module ON, 0 = module OFF)', color='tab:red')
axs[4].set_ylabel('g [-]')
axs[4].legend()
axs[4].grid(True)

# Subplot 6: g_u_3
axs[5].plot(t_filtered, g_u_5_filtered, label='g_u_5 (1 = module ON, 0 = module OFF)', color='tab:purple')
axs[5].set_ylabel('g [-]')
axs[5].legend()
axs[5].grid(True)

# Subplot 7: g_u_1
axs[6].plot(t_filtered, v_c_1_filtered, label='v_c_1', color='tab:blue')
axs[6].plot(t_filtered, v_c_2_filtered, label='v_c_2', color='tab:orange')
axs[6].plot(t_filtered, v_c_3_filtered, label='v_c_3', color='tab:green')
axs[6].plot(t_filtered, v_c_4_filtered, label='v_c_4', color='tab:red')
axs[6].plot(t_filtered, v_c_5_filtered, label='v_c_5', color='tab:purple')
axs[6].set_ylabel('v_c [V]')
axs[6].legend()
axs[6].grid(True)

# Subplot 7: g_u_1
axs[7].plot(t_filtered, i_u_filtered, label='i_u', color='tab:blue')
axs[7].plot(t_filtered, i_u_filtered_LP, label='i_u_filtered', color='tab:orange')
axs[7].set_ylabel('i [A]')
axs[7].legend()
axs[7].grid(True)

# Ajusta layout
plt.tight_layout()

# Mostra o gráfico
plt.show()
