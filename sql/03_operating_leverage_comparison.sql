-- ============================================================================
-- QUERY 03: Operating Leverage Comparison Across Scenarios
-- ============================================================================
-- PURPOSE:
--   For each scenario and month, compute the cost structure split (fixed vs
--   variable as % of total costs), the Degree of Operating Leverage (DOL),
--   and the leverage multiplier (how much EBITDA growth amplifies or dampens
--   revenue growth). Reveals which scenario is most sensitive to volume
--   changes and how that sensitivity evolves over 12 months.
--
-- WHY SQL (NOT EXCEL):
--   Requires self-joining pl_monthly on itself (pivoting 7 metrics into
--   columns per scenario-month), then layering LAG-based growth rates on
--   two different metrics simultaneously, then dividing those growth rates.
--   In Excel this would need a dedicated pivot table per scenario plus
--   manual growth-rate columns plus a ratio column — all of which break
--   if the number of scenarios or metrics changes. The SQL handles any
--   number of scenarios with zero structural changes.
--
-- TECHNIQUES: Conditional aggregation (pivot), LAG window function,
--             derived ratio calculations, NULLIF division safety
-- ============================================================================

WITH cost_structure AS (
    -- Step 1: Pivot the long-format P&L into one row per scenario-month
    --         with Revenue, Variable Costs, Fixed Costs, CM, and EBITDA
    --         as separate columns
    SELECT
        Scenario,
        Month_Number,
        MAX(CASE WHEN Metric = 'Revenue (Net)'       THEN Value END) AS Revenue,
        MAX(CASE WHEN Metric = 'Variable Costs'       THEN Value END) AS Variable_Costs,
        MAX(CASE WHEN Metric = 'Total Fixed Costs'    THEN Value END) AS Fixed_Costs,
        MAX(CASE WHEN Metric = 'Contribution Margin'  THEN Value END) AS Contribution_Margin,
        MAX(CASE WHEN Metric = 'EBITDA'               THEN Value END) AS EBITDA
    FROM pl_monthly
    GROUP BY Scenario, Month_Number
),

leverage_metrics AS (
    -- Step 2: Compute the operating leverage indicators
    --   • Fixed Cost % of Total Costs: how "loaded" the cost base is
    --   • DOL (Contribution Margin / EBITDA): classic measure of how much
    --     a 1% change in revenue translates to EBITDA change
    --   • Revenue and EBITDA MoM growth rates (via LAG)
    --   • Leverage Multiplier: EBITDA growth / Revenue growth — shows
    --     the amplification (or dampening) effect in practice
    SELECT
        Scenario,
        Month_Number,
        Revenue,
        Variable_Costs,
        Fixed_Costs,
        Contribution_Margin,
        EBITDA,
        ROUND(Fixed_Costs / NULLIF(Variable_Costs + Fixed_Costs, 0) * 100, 2)
            AS Fixed_Cost_Pct_of_Total,
        ROUND(Contribution_Margin / NULLIF(EBITDA, 0), 2)
            AS Degree_of_Op_Leverage,
        ROUND(
            (Revenue - LAG(Revenue) OVER (PARTITION BY Scenario ORDER BY Month_Number))
            / NULLIF(LAG(Revenue) OVER (PARTITION BY Scenario ORDER BY Month_Number), 0) * 100,
        2) AS Revenue_MoM_Growth_Pct,
        ROUND(
            (EBITDA - LAG(EBITDA) OVER (PARTITION BY Scenario ORDER BY Month_Number))
            / NULLIF(LAG(EBITDA) OVER (PARTITION BY Scenario ORDER BY Month_Number), 0) * 100,
        2) AS EBITDA_MoM_Growth_Pct
    FROM cost_structure
)

SELECT
    Scenario,
    Month_Number                                                            AS Month,
    ROUND(Revenue, 2)                                                       AS Revenue,
    ROUND(Fixed_Costs, 2)                                                   AS Fixed_Costs,
    ROUND(Variable_Costs, 2)                                                AS Variable_Costs,
    Fixed_Cost_Pct_of_Total,
    Degree_of_Op_Leverage                                                   AS DOL,
    Revenue_MoM_Growth_Pct                                                  AS Rev_MoM_Pct,
    EBITDA_MoM_Growth_Pct                                                   AS EBITDA_MoM_Pct,
    ROUND(EBITDA_MoM_Growth_Pct / NULLIF(Revenue_MoM_Growth_Pct, 0), 2)    AS Leverage_Multiplier
FROM leverage_metrics
ORDER BY Scenario, Month_Number;

-- ============================================================================
-- EXPECTED OUTPUT (36 rows: 3 scenarios × 12 months)
-- ============================================================================
-- Key findings:
--
--   BASE SCENARIO:
--   • Fixed costs are ~19% of total costs, stable across the year.
--   • DOL hovers at 1.12-1.13 — modest leverage, meaning a 1% revenue
--     increase produces roughly a 1.12% EBITDA increase.
--   • Leverage Multiplier is ~0.90, meaning EBITDA growth slightly trails
--     revenue growth. This is because cost inflation (1.5%/month) partially
--     offsets the revenue tailwind from fleet and price growth.
--
--   HIGH SCENARIO:
--   • Fixed costs drop to ~13.4% of total costs — the larger fleet and
--     higher utilization dilute the fixed cost base.
--   • DOL is low at 1.03-1.04, indicating the business is almost entirely
--     variable-cost driven at scale. Very resilient to volume swings.
--   • Leverage Multiplier is ~1.04, meaning EBITDA slightly outpaces
--     revenue — healthy operating leverage in the right direction.
--
--   LOW SCENARIO:
--   • Fixed costs are ~24.7-25% of total costs — the highest share,
--     because the smaller fleet generates less revenue to absorb them.
--   • DOL explodes from 3.19 (Month 1) through 24.8 (Month 5) to
--     negative values from Month 6 onward — classic behaviour as EBITDA
--     approaches and then crosses zero. Near the breakeven point, even
--     tiny revenue changes cause massive EBITDA swings.
--   • This confirms the Low scenario is structurally fragile: the fixed
--     cost base is too large relative to the revenue the fleet generates.
-- ============================================================================
