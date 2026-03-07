-- ============================================================================
-- QUERY 11: Unit Economics Deep Dive — Per-Ride and Per-Vehicle Profitability
-- ============================================================================
-- PURPOSE:
--   Compute revenue per ride, variable cost per ride, contribution margin
--   per ride, fixed cost per ride, and EBITDA per ride for each scenario
--   and month. Also calculates vehicle-level economics (revenue and EBITDA
--   per vehicle) and tracks how unit economics evolve over 12 months.
--   Answers: "Is each ride profitable, and is that improving or eroding?"
--
-- WHY SQL (NOT EXCEL):
--   Requires dividing five P&L metrics by Total Rides (a sixth metric from
--   the same table) for every scenario-month combination — meaning six
--   self-joins via conditional aggregation. Then layers LAG-based trend
--   analysis on the derived per-ride metrics, plus a second set of
--   divisions by Fleet Size for vehicle-level economics. Excel would need
--   12+ helper columns per scenario sheet, all referencing different source
--   rows. Adding a new metric (e.g., cost per km) requires one line in SQL
--   vs restructuring every sheet in Excel.
--
-- TECHNIQUES: Conditional aggregation (7-metric pivot), derived ratio
--             calculations, LAG on derived columns, multi-level unit
--             economics (per-ride and per-vehicle)
-- ============================================================================

WITH monthly_wide AS (
    -- Step 1: Pivot all needed metrics into columns
    SELECT
        Scenario,
        Month_Number,
        MAX(CASE WHEN Metric = 'Revenue (Net)'          THEN Value END) AS Revenue,
        MAX(CASE WHEN Metric = 'Total Rides'             THEN Value END) AS Rides,
        MAX(CASE WHEN Metric = 'Variable Costs'          THEN Value END) AS Variable_Costs,
        MAX(CASE WHEN Metric = 'Contribution Margin'     THEN Value END) AS Contribution_Margin,
        MAX(CASE WHEN Metric = 'Total Fixed Costs'       THEN Value END) AS Fixed_Costs,
        MAX(CASE WHEN Metric = 'EBITDA'                  THEN Value END) AS EBITDA,
        MAX(CASE WHEN Metric = 'Fleet Size (vehicles)'   THEN Value END) AS Fleet_Size
    FROM pl_monthly
    GROUP BY Scenario, Month_Number
),

unit_economics AS (
    -- Step 2: Compute per-ride and per-vehicle economics
    SELECT
        Scenario,
        Month_Number,
        Rides,
        Fleet_Size,
        Revenue / NULLIF(Rides, 0)              AS Rev_Per_Ride,
        Variable_Costs / NULLIF(Rides, 0)       AS VarCost_Per_Ride,
        Contribution_Margin / NULLIF(Rides, 0)  AS CM_Per_Ride,
        Fixed_Costs / NULLIF(Rides, 0)          AS FixCost_Per_Ride,
        EBITDA / NULLIF(Rides, 0)               AS EBITDA_Per_Ride,
        Revenue / NULLIF(Fleet_Size, 0)         AS Rev_Per_Vehicle,
        EBITDA / NULLIF(Fleet_Size, 0)          AS EBITDA_Per_Vehicle,
        Rides / NULLIF(Fleet_Size, 0)           AS Rides_Per_Vehicle
    FROM monthly_wide
),

with_trends AS (
    -- Step 3: Attach prior-month CM per ride for trend analysis
    SELECT
        u.*,
        LAG(u.CM_Per_Ride) OVER (
            PARTITION BY u.Scenario ORDER BY u.Month_Number
        ) AS Prev_CMPR
    FROM unit_economics u
)

SELECT
    Scenario,
    Month_Number                        AS Month,
    ROUND(Rev_Per_Ride, 4)              AS Rev_Per_Ride,
    ROUND(VarCost_Per_Ride, 4)          AS VarCost_Per_Ride,
    ROUND(CM_Per_Ride, 4)               AS CM_Per_Ride,
    ROUND(FixCost_Per_Ride, 4)          AS FixCost_Per_Ride,
    ROUND(EBITDA_Per_Ride, 4)           AS EBITDA_Per_Ride,
    -- MoM change in CM per ride (unit margin trend)
    ROUND(
        (CM_Per_Ride - Prev_CMPR)
        / NULLIF(Prev_CMPR, 0) * 100,
    4)                                  AS CM_Per_Ride_MoM_Pct,
    -- Unit CM margin: CM as % of revenue at the ride level
    ROUND(
        CM_Per_Ride / NULLIF(Rev_Per_Ride, 0) * 100,
    2)                                  AS Unit_CM_Margin_Pct,
    -- Vehicle-level economics
    ROUND(Rev_Per_Vehicle, 2)           AS Rev_Per_Vehicle,
    ROUND(EBITDA_Per_Vehicle, 2)        AS EBITDA_Per_Vehicle,
    ROUND(Rides_Per_Vehicle, 0)         AS Rides_Per_Vehicle
FROM with_trends
ORDER BY Scenario, Month_Number;

-- ============================================================================
-- EXPECTED OUTPUT (36 rows: 3 scenarios × 12 months)
-- ============================================================================
--
-- Key findings:
--
--   BASE SCENARIO — Healthy but slowly eroding unit economics:
--   • Rev per ride grows from €7.01 to €7.71 (+10% over 12 months),
--     driven by 1% monthly price growth.
--   • VarCost per ride grows from €2.13 to €2.51 (+18%), outpacing
--     revenue growth due to 1.5% monthly cost inflation.
--   • CM per ride still grows (€4.88 → €5.20) because the revenue
--     base is large enough to absorb the cost increase.
--   • Unit CM margin compresses slightly: 69.6% → 67.5%.
--   • Rides per vehicle is constant at 957/month (fleet growth adds
--     vehicles proportionally to rides).
--
--   HIGH SCENARIO — Expanding unit economics:
--   • Rev per ride grows from €12.90 to €15.67 (+21.5%) — the 2%
--     monthly price growth compounds aggressively.
--   • CM per ride grows from €10.58 to €13.14 (+24%) — price growth
--     outpaces cost inflation, so margins EXPAND.
--   • Unit CM margin IMPROVES: 82.0% → 83.9%.
--   • EBITDA per vehicle is €11,144 in Month 1 and reaches €13,916
--     by Month 12 — each vehicle becomes more profitable over time.
--
--   LOW SCENARIO — Collapsing unit economics:
--   • Rev per ride is FLAT at €3.42 (zero price growth).
--   • VarCost per ride grows from €2.30 to €3.02 (+31%) due to 2.5%
--     cost inflation with no offsetting price increases.
--   • CM per ride collapses from €1.12 to €0.40 — a 65% decline.
--     CM per ride MoM erosion accelerates: -5.2% in Month 2 to
--     -15.7% by Month 12.
--   • Unit CM margin falls from 32.6% to 11.6%.
--   • EBITDA per ride turns negative in Month 6 (€-0.05) and reaches
--     €-0.59 by Month 12. Each ride is destroying value.
--   • EBITDA per vehicle follows: €274 in Month 1 → €-466 by Month 12.
--
--   STRATEGIC INSIGHT:
--   • The Low scenario's unit economics are structurally unsustainable.
--     Variable cost per ride (€3.02) is converging toward revenue per
--     ride (€3.42) — a gap of just €0.40 by Month 12. If cost inflation
--     continues, the business reaches unit-level breakeven (CM = 0)
--     within a few more months, at which point every ride loses money
--     before any fixed costs are considered.
-- ============================================================================
