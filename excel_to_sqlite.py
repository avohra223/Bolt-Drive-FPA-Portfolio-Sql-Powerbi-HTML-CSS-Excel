import pandas as pd
import sqlite3
import os

EXCEL_PATH = '/mnt/user-data/uploads/Bolt_Drive___FP_A_Model__Akhil_Vohra_.xlsx'
DB_PATH = '/home/claude/bolt_fpa.db'

if os.path.exists(DB_PATH):
    os.remove(DB_PATH)

conn = sqlite3.connect(DB_PATH)
xl = pd.read_excel(EXCEL_PATH, sheet_name=None)

# ── 1. ASSUMPTIONS ──────────────────────────────────────────────────────────
df = xl['Assumptions']

# Rows 3-8: Fleet & Utilization (cols: Driver Name, Unit, Base, Low, High, Active)
fleet = df.iloc[3:9, :].copy()
fleet.columns = ['Driver_Name','Unit','Base_Case','Low_Case','High_Case','Active_Value']
fleet = fleet.dropna(subset=['Driver_Name'])
fleet['Section'] = 'Fleet & Utilization'

# Rows 11-14: Pricing
pricing = df.iloc[11:15, :].copy()
pricing.columns = ['Driver_Name','Unit','Base_Case','Low_Case','High_Case','Active_Value']
pricing = pricing.dropna(subset=['Driver_Name'])
pricing['Section'] = 'Pricing'

# Rows 17-23: Variable Costs
var_costs = df.iloc[17:24, :].copy()
var_costs.columns = ['Driver_Name','Unit','Base_Case','Low_Case','High_Case','Active_Value']
var_costs = var_costs.dropna(subset=['Driver_Name'])
var_costs['Section'] = 'Variable Costs'

# Rows 26-29: Fixed Costs
fixed_costs = df.iloc[26:30, :].copy()
fixed_costs.columns = ['Driver_Name','Unit','Base_Case','Low_Case','High_Case','Active_Value']
fixed_costs = fixed_costs.dropna(subset=['Driver_Name'])
fixed_costs['Section'] = 'Fixed Costs'

# Rows 32-35: Growth
growth = df.iloc[32:36, :].copy()
growth.columns = ['Driver_Name','Unit','Base_Case','Low_Case','High_Case','Active_Value']
growth = growth.dropna(subset=['Driver_Name'])
growth['Section'] = 'Growth Drivers'

assumptions = pd.concat([fleet, pricing, var_costs, fixed_costs, growth], ignore_index=True)
assumptions = assumptions[['Section','Driver_Name','Unit','Base_Case','Low_Case','High_Case','Active_Value']]
assumptions.to_sql('assumptions', conn, if_exists='replace', index=False)
print(f"assumptions: {len(assumptions)} rows")

# ── 2. VOLUME ENGINE ─────────────────────────────────────────────────────────
df = xl['Volume Engine']
# Rows 10-22: metrics (Metric, Unit, Definition, Value)
vol = df.iloc[10:23, :].copy()
vol.columns = ['Metric','Unit','Definition','Value']
vol = vol[~vol['Metric'].astype(str).str.startswith('──')]
vol = vol.dropna(subset=['Metric'])
vol = vol[vol['Metric'] != 'Metric']
vol.to_sql('volume_engine', conn, if_exists='replace', index=False)
print(f"volume_engine: {len(vol)} rows")

# ── 3. REVENUE ENGINE ────────────────────────────────────────────────────────
df = xl['Revenue Engine']
# Rows 13-25: Revenue Calculations
rev = df.iloc[13:26, :].copy()
rev.columns = ['Metric','Unit','Definition','Value']
rev = rev.dropna(subset=['Metric'])
rev = rev[rev['Metric'] != 'Metric']
rev.to_sql('revenue_engine', conn, if_exists='replace', index=False)
print(f"revenue_engine: {len(rev)} rows")

# ── 4. VARIABLE COST ENGINE ──────────────────────────────────────────────────
df = xl['Variable Cost Engine']
# Rows 16-30
vc = df.iloc[16:31, :].copy()
vc.columns = ['Metric','Unit','Definition','Value']
vc = vc[~vc['Metric'].astype(str).str.startswith('──')]
vc = vc.dropna(subset=['Metric'])
vc = vc[vc['Metric'] != 'Metric']
vc.to_sql('variable_cost_engine', conn, if_exists='replace', index=False)
print(f"variable_cost_engine: {len(vc)} rows")

# ── 5. FIXED COST ENGINE ─────────────────────────────────────────────────────
df = xl['Fixed Cost Engine']
# Rows 13-23
fc = df.iloc[13:24, :].copy()
fc.columns = ['Metric','Unit','Definition','Value']
fc = fc[~fc['Metric'].astype(str).str.startswith('──')]
fc = fc.dropna(subset=['Metric'])
fc = fc[fc['Metric'] != 'Metric']
fc.to_sql('fixed_cost_engine', conn, if_exists='replace', index=False)
print(f"fixed_cost_engine: {len(fc)} rows")

# ── 6. P&L PROJECTION ────────────────────────────────────────────────────────
df = xl['P&L Projection (12M)']
# Row 8 = headers (Metric, Month 1 ... Month 12, FY Total)
# Rows 9-20 = data
pl_raw = df.iloc[8:21, :].copy()
pl_raw.columns = ['Metric','Month_1','Month_2','Month_3','Month_4','Month_5','Month_6',
                   'Month_7','Month_8','Month_9','Month_10','Month_11','Month_12','FY_Total']
pl_raw = pl_raw.dropna(subset=['Metric'])
pl_raw = pl_raw[pl_raw['Metric'] != 'Metric']

# Pivot to long format: one row per metric per month
metrics_to_keep = [
    'Fleet Size (vehicles)',
    'Revenue (Net)',
    'Variable Costs',
    'Contribution Margin',
    'Contribution Margin %',
    'Vehicle Fixed Costs (Total)',
    'Platform Overhead',
    'Total Fixed Costs',
    'EBITDA',
    'EBITDA Margin %'
]
pl_filtered = pl_raw[pl_raw['Metric'].isin(metrics_to_keep)].copy()

month_cols = [f'Month_{i}' for i in range(1, 13)]
pl_long = pl_filtered.melt(
    id_vars=['Metric'],
    value_vars=month_cols,
    var_name='Month',
    value_name='Value'
)
pl_long['Month_Number'] = pl_long['Month'].str.replace('Month_','').astype(int)
pl_long = pl_long[['Month_Number','Month','Metric','Value']].sort_values(['Month_Number','Metric'])

# Also keep FY totals as separate table
pl_fy = pl_filtered[['Metric','FY_Total']].copy()
pl_fy.columns = ['Metric','FY_Total']

pl_long.to_sql('pl_monthly', conn, if_exists='replace', index=False)
pl_fy.to_sql('pl_fy_totals', conn, if_exists='replace', index=False)
print(f"pl_monthly: {len(pl_long)} rows")
print(f"pl_fy_totals: {len(pl_fy)} rows")

# ── 7. SENSITIVITY ANALYSIS ──────────────────────────────────────────────────
df = xl['Sensitivity Analysis']

# Table 1A: Net Revenue | Price per Minute vs Utilization Rate (rows 3-8)
t1a_raw = df.iloc[3:9, :].copy()
util_rates = [0.50, 0.575, 0.65, 0.725, 0.80]
prices = [0.21, 0.25, 0.29, 0.33, 0.37]
rows_1a = []
for i, price in enumerate(prices):
    for j, util in enumerate(util_rates):
        val = t1a_raw.iloc[i+1, j+1]
        rows_1a.append({'Table':'1A','Output':'FY_Net_Revenue','Price_Per_Min':price,'Util_Rate':util,'Value':val})
sens_1a = pd.DataFrame(rows_1a)

# Table 1B: EBITDA Margin | Price per Minute vs Utilization Rate (rows 10-16)
t1b_raw = df.iloc[11:17, :].copy()
rows_1b = []
for i, price in enumerate(prices):
    for j, util in enumerate(util_rates):
        val = t1b_raw.iloc[i+1, j+1]
        rows_1b.append({'Table':'1B','Output':'FY_EBITDA_Margin','Price_Per_Min':price,'Util_Rate':util,'Value':val})
sens_1b = pd.DataFrame(rows_1b)

# Table 2A: Net Revenue | Fleet Growth vs Price Growth (rows 18-24)
fleet_growths = [0.0, 0.015, 0.03, 0.045, 0.06]
price_growths = [0.0, 0.005, 0.01, 0.015, 0.02]
t2a_raw = df.iloc[19:25, :].copy()
rows_2a = []
for i, fg in enumerate(fleet_growths):
    for j, pg in enumerate(price_growths):
        val = t2a_raw.iloc[i+1, j+1]
        rows_2a.append({'Table':'2A','Output':'FY_Net_Revenue','Fleet_Growth':fg,'Price_Growth':pg,'Value':val})
sens_2a = pd.DataFrame(rows_2a)

# Table 2B: EBITDA Margin | Fleet Growth vs Price Growth (rows 26-32)
t2b_raw = df.iloc[27:33, :].copy()
rows_2b = []
for i, fg in enumerate(fleet_growths):
    for j, pg in enumerate(price_growths):
        val = t2b_raw.iloc[i+1, j+1]
        rows_2b.append({'Table':'2B','Output':'FY_EBITDA_Margin','Fleet_Growth':fg,'Price_Growth':pg,'Value':val})
sens_2b = pd.DataFrame(rows_2b)

# Save sensitivity tables
sens_price_util = pd.concat([sens_1a, sens_1b], ignore_index=True)
sens_growth = pd.concat([sens_2a, sens_2b], ignore_index=True)

sens_price_util.to_sql('sensitivity_price_util', conn, if_exists='replace', index=False)
sens_growth.to_sql('sensitivity_growth', conn, if_exists='replace', index=False)
print(f"sensitivity_price_util: {len(sens_price_util)} rows")
print(f"sensitivity_growth: {len(sens_growth)} rows")

conn.close()
print("\nAll tables loaded successfully into bolt_fpa.db")

# Verify
conn2 = sqlite3.connect(DB_PATH)
tables = pd.read_sql("SELECT name FROM sqlite_master WHERE type='table'", conn2)
print("\nTables in database:")
for t in tables['name']:
    count = pd.read_sql(f"SELECT COUNT(*) as n FROM [{t}]", conn2).iloc[0,0]
    print(f"  {t}: {count} rows")
conn2.close()
