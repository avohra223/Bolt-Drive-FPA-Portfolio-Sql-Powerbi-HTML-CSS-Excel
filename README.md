# Bolt Drive FP&A Portfolio

Driver-based financial model for a ride-hailing business (Bolt Drive). Built from scratch as an end-to-end FP&A analysis: Excel model, Python data pipeline, SQLite database, 15 advanced SQL queries, interactive HTML dashboard, and Power BI dashboard.

**[View Interactive Dashboard](https://avohra223.github.io/Bolt-Drive-FPA-Portfolio-Sql-Powerbi-HTML-CSS-Excel/dashboard/)**

---

## What This Portfolio Demonstrates

This project models a fictional Bolt Drive car-sharing operation across three scenarios (Base, Low, High) over a 12-month horizon. It covers the full FP&A workflow: assumption setting, driver-based modelling, database architecture, analytical querying, and multi-format reporting.

The focus is on analysis that justifies each tool in the stack. Every SQL query does something Excel cannot do easily. Every dashboard visual shows something a single-scenario spreadsheet cannot show.

---

## Repository Structure

```
Bolt-Drive-FPA-Portfolio/
|
|-- excel/
|   |-- Bolt_Drive_FP&A_Model_Akhil_Vohra.xlsx    # 9-sheet driver-based model
|
|-- sql/
|   |-- 01_scenario_divergence_tracker.sql          # Widening cone of uncertainty
|   |-- 02_scenario_crossover_detection.sql         # Zero-line breach with interpolation
|   |-- 03_operating_leverage_comparison.sql         # DOL trajectory across scenarios
|   |-- 04_price_util_sensitivity_surface.sql        # Partial derivatives on sensitivity grid
|   |-- 05_marginal_impact_ranking.sql               # Which lever moves the needle most
|   |-- 06_growth_interaction_effects.sql            # Additive vs compounding synergy
|   |-- 07_revenue_growth_decomposition.sql          # Volume vs price vs mix attribution
|   |-- 08_cumulative_ebitda_payback.sql             # Fixed cost recovery timeline
|   |-- 09_cost_inflation_overtake.sql               # Margin compression detection
|   |-- 10_assumption_to_pl_flow_trace.sql           # Full model audit trail
|   |-- 11_unit_economics_deep_dive.sql              # Per-ride and per-vehicle profitability
|   |-- 12_pl_reconciliation_check.sql               # Data integrity validation (5 checks)
|   |-- 13_sensitivity_grid_completeness_audit.sql   # Grid shape and duplicate detection
|   |-- 14_scenario_weighted_expected_ebitda.sql      # Probability-weighted outcomes
|   |-- 15_margin_of_safety_analysis.sql             # Distance from breakeven
|
|-- dashboard/
|   |-- index.html                                   # Interactive 3-page HTML dashboard
|
|-- powerbi/
|   |-- Bolt_Drive_FPA_Dashboard.pbix                # Power BI file (requires Power BI Desktop)
|   |-- Bolt_Drive_FPA_Dashboard.pdf                 # PDF export for viewing without Power BI
|
|-- excel_to_sqlite.py                               # Python conversion script
|-- bolt_fpa.db                                      # SQLite database (9 tables)
```

---

## Excel Model

A 9-sheet driver-based financial model with three scenarios (Base, Low, High) controlled by a single scenario selector.

**Sheets:** Assumptions, Volume Engine, Revenue Engine, Variable Cost Engine, Fixed Cost Engine, P&L Projection (12M), Sensitivity Analysis, Dashboard, Cover

**Key design decisions:**
- All values are formula-driven (no hardcoded overrides)
- Engines are modular: changing one assumption cascades through volume, revenue, costs, and P&L automatically
- Sensitivity analysis covers two dimensions: Price/Min vs Utilization Rate, and Fleet Growth vs Price Growth
- 20 input assumptions across 5 categories drive the entire model

---

## Data Pipeline

`excel_to_sqlite.py` extracts structured data from the Excel model into a normalized SQLite database (`bolt_fpa.db`) with 9 tables:

| Table | Rows | Description |
|-------|------|-------------|
| pl_monthly | 396 | 3 scenarios x 12 months x 11 metrics (long format) |
| pl_fy_totals | 33 | Full-year aggregates per scenario |
| assumptions | 20 | All driver assumptions with Base/Low/High values |
| volume_engine | 11 | Operational activity calculations |
| revenue_engine | 12 | Revenue build-up from volume |
| variable_cost_engine | 13 | Per-ride and per-vehicle cost structure |
| fixed_cost_engine | 9 | Insurance, depreciation, platform overhead |
| sensitivity_price_util | 50 | 5x5 grid: Price/Min vs Utilization Rate |
| sensitivity_growth | 50 | 5x5 grid: Fleet Growth vs Price Growth |

---

## SQL Queries (15)

Every query requires SQL capabilities that Excel cannot replicate: cross-scenario pivoting, window functions, multi-table joins, sensitivity grid traversal, or governance checks.

### Cross-Scenario Analysis
| # | Query | Technique | Key Finding |
|---|-------|-----------|-------------|
| 01 | Scenario Divergence Tracker | Conditional aggregation, LAG, cumulative SUM | EBITDA spread widens from 7.7M to 16.8M over 12 months |
| 02 | Scenario Crossover Detection | LAG sign-change detection, linear interpolation | Low EBITDA crosses zero at Month 5.42 |
| 03 | Operating Leverage Comparison | Self-join pivot, derived DOL ratio | Low DOL explodes from 3.2x to 24.8x near breakeven |

### Sensitivity Analysis
| # | Query | Technique | Key Finding |
|---|-------|-----------|-------------|
| 04 | Price-Util Sensitivity Surface | Dual-partition LAG, partial derivatives | Price dominates margin in 20 of 25 grid cells |
| 05 | Marginal Impact Ranking | UNION ALL across tables, RANK | Rankings flip: Price Growth #1 for margin, Fleet Growth #1 for revenue |
| 06 | Growth Interaction Effects | Four-way self-join, additive decomposition | Fleet + price growth together generate 2.4M extra revenue (compounding) |

### Time-Series Intelligence
| # | Query | Technique | Key Finding |
|---|-------|-----------|-------------|
| 07 | Revenue Growth Decomposition | Multiplicative decomposition via LAG | Base: 77% volume / 22% price / 1% mix. Low: 100% volume (zero pricing power) |
| 08 | Cumulative EBITDA Payback | SUM OVER, threshold detection, interpolation | Base pays back in Month 1.78, High in Month 0.59, Low never |
| 09 | Cost Inflation Overtake | Multi-metric LAG growth rates | Base costs outpace revenue every month (gap: -0.60pp). Only High has positive gap |

### Cross-Engine Traceability
| # | Query | Technique | Key Finding |
|---|-------|-----------|-------------|
| 10 | Assumption-to-P&L Flow Trace | UNION ALL across 4 tables, 3-scenario pivot | 2x input differences amplify to 80x EBITDA differences (Month 1) |
| 11 | Unit Economics Deep Dive | 7-metric pivot, derived per-ride ratios | Low VarCost/Ride (3.02) converging on Rev/Ride (3.42) by Month 12 |

### Governance
| # | Query | Technique | Key Finding |
|---|-------|-----------|-------------|
| 12 | P&L Reconciliation Check | 11-metric pivot, 5 arithmetic validations | All 36 rows pass. Max variance: 0.01 (rounding) |
| 13 | Sensitivity Grid Completeness | COUNT DISTINCT, GROUP BY/HAVING, cross-table JOIN | Both grids complete (5x5x2), zero duplicates, base cases match |

### Strategic
| # | Query | Technique | Key Finding |
|---|-------|-----------|-------------|
| 14 | Scenario-Weighted Expected EBITDA | CTE weights, weighted aggregation, SUM OVER | Expected EBITDA exceeds Base by 45-85% (positively skewed distribution) |
| 15 | Margin of Safety Analysis | Derived breakeven revenue, LAG trend detection | Base: 89% safety buffer (contracting). Low: -150% by Month 12 |

---

## Dashboards

### Interactive HTML Dashboard
**[View Interactive Dashboard](https://avohra223.github.io/Bolt-Drive-FPA-Portfolio-Sql-Powerbi-HTML-CSS-Excel/dashboard/)**
Built with HTML, CSS, JavaScript, and Chart.js. Three pages:

- **Scenario Command Centre:** Multi-scenario EBITDA trajectories, cumulative payback, margin of safety gauges, scenario spread
- **Unit Economics & Costs:** Revenue vs variable cost per ride convergence, cost overtake detection, revenue decomposition, DOL trajectory
- **Sensitivity & Levers:** EBITDA margin heatmap, marginal impact rankings, growth interaction bubble chart, payback timeline

No software required to view. Accessible to anyone with a browser.

### Power BI Dashboard

Three-page dashboard with DAX measures, interactive filtering, and conditional formatting. Available as .pbix (requires Power BI Desktop) and .pdf (universal viewing).

- **Page 1:** KPI cards (5 metrics), EBITDA trajectory, EBITDA Margin % trajectory, FY EBITDA by scenario
- **Page 2:** Rev/Ride vs VarCost/Ride (small multiples), EBITDA/Ride, CM% trajectory, FY Revenue comparison
- **Page 3:** FY EBITDA comparison, cost structure breakdown, two sensitivity matrices with conditional formatting

---

## Key Findings

**The Amplification Cascade:** Input assumptions vary by 1.5-2x between scenarios, but EBITDA outcomes diverge by 80x in Month 1 and 350x at the FY level. The model is explosively sensitive to its inputs.

**The Low Scenario Story:** EBITDA crosses zero at Month 5.42. Revenue per ride is flat (zero pricing power), while variable costs climb 31% due to 2.5% monthly inflation. By Month 12, every ride destroys value (-0.59 per ride). Cumulative EBITDA turns negative by Month 10. The margin of safety collapses from 31% to -150%.

**The Base Case is Conservative:** Probability-weighted expected EBITDA exceeds the Base case by 45-85% because the High scenario upside massively outweighs the Low scenario downside. The distribution is positively skewed.

**Price is the Dominant Margin Lever:** Price growth ranks #1 for EBITDA margin improvement (1.85pp per unit), while fleet growth is #1 for revenue but last for margin. The optimal strategy depends on whether the business is optimizing for profitability or top-line growth.

**Costs Outpace Revenue Even in Base:** Total costs grow at 4.49% MoM vs revenue at 3.89% MoM. The margin of safety is slowly contracting (89.4% to 88.6% over 12 months). Over a multi-year horizon, this becomes a material risk.

---

## Tools

- **Excel:** Driver-based financial modelling (9 sheets, 20 assumptions, 3 scenarios)
- **Python:** Data pipeline (pandas, sqlite3) for Excel-to-SQLite conversion
- **SQLite:** Normalized relational database (9 tables, 396+ rows)
- **SQL:** 15 analytical queries (CTEs, window functions, self-joins, UNION ALL, conditional aggregation)
- **HTML/CSS/JS:** Interactive dashboard (Chart.js, 3 pages, embedded data)
- **Power BI:** DAX measures, multi-page report, conditional formatting, small multiples

---

## Author

**Akhil Vohra**
MBA Candidate, EDHEC Business School (2025-2026)
