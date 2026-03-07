-- ============================================================================
-- QUERY 01: Scenario Divergence Tracker — Widening Cone of Uncertainty
-- ============================================================================
-- PURPOSE:
--   For each month, measure the spread between High and Low scenario outcomes
--   for Revenue, Contribution Margin, and EBITDA. Track how this "cone of
--   uncertainty" widens over the 12-month forecast horizon and at what rate.
--
-- WHY SQL (NOT EXCEL):
--   The source data is in long format (Scenario × Month × Metric). Pivoting
--   three scenarios into columns, computing spreads, then layering LAG-based
--   month-over-month growth on top of those spreads requires chained CTEs
--   and window functions. Excel would need a dedicated helper sheet per metric
--   and manual cross-referencing between scenarios — none of which scales
--   if a fourth scenario is added later.
--
-- TECHNIQUES: Conditional aggregation (pivot), LAG window function, 
--             cumulative SUM OVER, chained CTEs
-- ============================================================================

WITH scenario_pivot AS (
    -- Step 1: Pivot the long-format table so each row has High / Base / Low
    --         side by side for a given month and metric
    SELECT
        Month_Number,
        Metric,
        MAX(CASE WHEN Scenario = 'High' THEN Value END) AS High_Value,
        MAX(CASE WHEN Scenario = 'Base' THEN Value END) AS Base_Value,
        MAX(CASE WHEN Scenario = 'Low'  THEN Value END) AS Low_Value
    FROM pl_monthly
    WHERE Metric IN ('Revenue (Net)', 'Contribution Margin', 'EBITDA')
    GROUP BY Month_Number, Metric
),

spreads AS (
    -- Step 2: Compute the absolute spread (High - Low) and express it
    --         as a percentage of the Base case for context
    SELECT
        Month_Number,
        Metric,
        High_Value,
        Base_Value,
        Low_Value,
        (High_Value - Low_Value)                                        AS Absolute_Spread,
        ROUND((High_Value - Low_Value) / NULLIF(Base_Value, 0) * 100, 2) AS Spread_Pct_of_Base
    FROM scenario_pivot
),

spread_with_growth AS (
    -- Step 3: Layer on month-over-month spread growth (how fast is
    --         uncertainty expanding?) and a running cumulative spread
    SELECT
        s.Month_Number,
        s.Metric,
        s.Low_Value,
        s.Base_Value,
        s.High_Value,
        s.Absolute_Spread,
        s.Spread_Pct_of_Base,
        ROUND(
            (s.Absolute_Spread
             - LAG(s.Absolute_Spread) OVER (PARTITION BY s.Metric ORDER BY s.Month_Number))
            / NULLIF(
                LAG(s.Absolute_Spread) OVER (PARTITION BY s.Metric ORDER BY s.Month_Number), 0)
            * 100,
        2) AS Spread_MoM_Growth_Pct,
        SUM(s.Absolute_Spread)
            OVER (PARTITION BY s.Metric ORDER BY s.Month_Number)        AS Cumulative_Spread
    FROM spreads s
)

-- Final output
SELECT
    Month_Number                        AS Month,
    Metric,
    ROUND(Low_Value, 2)                 AS Low,
    ROUND(Base_Value, 2)                AS Base,
    ROUND(High_Value, 2)                AS High,
    ROUND(Absolute_Spread, 2)           AS Spread_High_Low,
    Spread_Pct_of_Base                  AS Spread_as_Pct_of_Base,
    Spread_MoM_Growth_Pct               AS Spread_MoM_Growth,
    ROUND(Cumulative_Spread, 2)         AS Cumulative_Spread
FROM spread_with_growth
ORDER BY Metric, Month_Number;

-- ============================================================================
-- EXPECTED OUTPUT (36 rows: 3 metrics × 12 months)
-- ============================================================================
-- Key findings:
--   • The EBITDA spread starts at ~€7.7M in Month 1 and widens to ~€16.8M
--     by Month 12 — the cone of uncertainty more than doubles.
--   • Spread grows at a steady ~7.3-7.5% month-over-month across all three
--     metrics, indicating compounding divergence driven by growth rate
--     differences between scenarios.
--   • Spread as a % of Base rises from ~369% to ~551% for EBITDA, meaning
--     by year-end the range of outcomes is over 5× the Base case value.
--     This signals high model sensitivity to input assumptions.
-- ============================================================================
