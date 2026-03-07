-- ============================================================================
-- QUERY 08: Cumulative EBITDA and Fixed Cost Payback Analysis
-- ============================================================================
-- PURPOSE:
--   Compute running cumulative EBITDA for each scenario and identify the
--   month where cumulative EBITDA first exceeds the full-year fixed cost
--   base (the "payback month"). Uses linear interpolation to pinpoint the
--   exact fractional month. For scenarios that never achieve payback, the
--   query tracks how cumulative EBITDA erodes over time.
--
-- WHY SQL (NOT EXCEL):
--   Requires a cumulative SUM window function, a LAG on that cumulative
--   sum (to detect the threshold crossing), a JOIN to a separate FY totals
--   table for the payback target, and conditional interpolation logic — all
--   operating across three scenarios simultaneously. In Excel, running
--   totals are easy for one scenario, but comparing three scenarios against
--   different payback targets with automatic threshold detection and
--   interpolation would require extensive helper columns and manual
--   cross-referencing. The SQL scales to any number of scenarios.
--
-- TECHNIQUES: SUM() OVER (cumulative window), LAG on a derived window
--             column (requires chained CTEs in SQLite), JOIN to FY totals,
--             conditional CASE with interpolation
-- ============================================================================

WITH ebitda_monthly AS (
    -- Step 1: Extract monthly EBITDA per scenario
    SELECT
        Scenario,
        Month_Number,
        Value AS EBITDA
    FROM pl_monthly
    WHERE Metric = 'EBITDA'
),

cumulative AS (
    -- Step 2: Compute running cumulative EBITDA
    SELECT
        Scenario,
        Month_Number,
        EBITDA,
        SUM(EBITDA) OVER (
            PARTITION BY Scenario
            ORDER BY Month_Number
        ) AS Cumulative_EBITDA
    FROM ebitda_monthly
),

with_lag AS (
    -- Step 3: Attach previous month's cumulative (needed for threshold
    --         crossing detection — SQLite requires a separate CTE for
    --         LAG on a window-derived column)
    SELECT
        Scenario,
        Month_Number,
        EBITDA,
        Cumulative_EBITDA,
        LAG(Cumulative_EBITDA) OVER (
            PARTITION BY Scenario
            ORDER BY Month_Number
        ) AS Prev_Cumulative
    FROM cumulative
),

fy_costs AS (
    -- Step 4: Get full-year fixed cost target per scenario
    --         This is the "investment" cumulative EBITDA must recover
    SELECT Scenario, FY_Total AS FY_Fixed_Costs
    FROM pl_fy_totals
    WHERE Metric = 'Total Fixed Costs'
)

-- Final output: monthly progression with payback detection
SELECT
    c.Scenario,
    c.Month_Number                          AS Month,
    ROUND(c.EBITDA, 2)                      AS Monthly_EBITDA,
    ROUND(c.Cumulative_EBITDA, 2)           AS Cumulative_EBITDA,
    ROUND(fc.FY_Fixed_Costs, 2)             AS FY_Fixed_Cost_Target,
    ROUND(
        c.Cumulative_EBITDA
        / NULLIF(fc.FY_Fixed_Costs, 0) * 100,
    2)                                      AS Pct_Fixed_Costs_Recovered,
    -- Flag the exact month where cumulative EBITDA first crosses the target
    CASE
        WHEN c.Cumulative_EBITDA >= fc.FY_Fixed_Costs
         AND (c.Prev_Cumulative IS NULL
              OR c.Prev_Cumulative < fc.FY_Fixed_Costs)
        THEN 'PAYBACK'
        ELSE NULL
    END                                     AS Payback_Flag,
    -- Linear interpolation of the exact fractional payback month
    CASE
        WHEN c.Cumulative_EBITDA >= fc.FY_Fixed_Costs
         AND (c.Prev_Cumulative IS NULL
              OR c.Prev_Cumulative < fc.FY_Fixed_Costs)
        THEN ROUND(
            (c.Month_Number - 1)
            + (fc.FY_Fixed_Costs - COALESCE(c.Prev_Cumulative, 0))
              / NULLIF(c.EBITDA, 0),
        2)
        ELSE NULL
    END                                     AS Interpolated_Payback
FROM with_lag c
JOIN fy_costs fc
    ON c.Scenario = fc.Scenario
ORDER BY c.Scenario, c.Month_Number;

-- ============================================================================
-- EXPECTED OUTPUT (36 rows: 3 scenarios × 12 months)
-- ============================================================================
--
-- Key findings:
--
--   BASE SCENARIO — Payback at Month 1.78:
--   • Cumulative EBITDA crosses the €3.78M fixed cost target in Month 2.
--     Interpolation places the exact payback at Month 1.78.
--   • By Month 12, cumulative EBITDA reaches €30.5M — roughly 8× the
--     fixed cost base. The business is highly cash-generative.
--
--   HIGH SCENARIO — Payback at Month 0.59:
--   • Month 1 EBITDA alone (€7.8M) already exceeds the full-year fixed
--     cost target (€4.6M). Interpolated payback is Month 0.59 — the
--     business effectively covers its entire annual fixed cost base in
--     the first three weeks.
--   • By Month 12, cumulative EBITDA is €140.7M (30× fixed costs).
--
--   LOW SCENARIO — Never achieves payback:
--   • Cumulative EBITDA peaks at €269,760 in Month 5 (just 8.85% of
--     the €3.05M fixed cost target), then begins declining as monthly
--     EBITDA turns negative from Month 6 onward.
--   • By Month 10, cumulative EBITDA itself turns negative (-€61,505),
--     meaning the business has consumed all prior accumulated earnings.
--   • By Month 12, cumulative EBITDA is -€394,120 — the business is
--     destroying value. Fixed costs are never recovered.
--
--   STRATEGIC IMPLICATION:
--   • The gap between scenarios is extreme: High recovers fixed costs
--     in 18 days, Base in ~24 days, and Low never recovers them at all.
--     This underscores how sensitive the model is to input assumptions,
--     particularly pricing and fleet utilization.
-- ============================================================================
