-- ============================================================================
-- QUERY 09: Cost Inflation Overtake Analysis — Margin Compression Detection
-- ============================================================================
-- PURPOSE:
--   Track the month-over-month growth rate of Revenue versus Total Costs
--   (Variable + Fixed) for each scenario. Identifies months where cost
--   growth outpaces revenue growth ("cost overtake"), signalling margin
--   compression. Breaks down cost growth into variable and fixed components
--   to diagnose which cost category is driving the compression.
--
-- WHY SQL (NOT EXCEL):
--   Requires computing MoM growth rates (via LAG) on four separate metrics
--   simultaneously (Revenue, Total Costs, Variable Costs, Fixed Costs),
--   then comparing the growth rates within each row and flagging overtake
--   events — all across three scenarios in a single pass. Excel would need
--   four separate growth-rate columns per scenario sheet, a comparison
--   column, and a conditional flag column. Changing the cost breakdown
--   (e.g., adding a new cost category) would require restructuring every
--   sheet. The SQL handles it with one additional line in the pivot.
--
-- TECHNIQUES: Conditional aggregation (pivot), LAG window function on
--             multiple metrics, derived growth-gap calculation, CASE-based
--             threshold flagging
-- ============================================================================

WITH monthly_wide AS (
    -- Step 1: Pivot Revenue and cost metrics into columns
    SELECT
        Scenario,
        Month_Number,
        MAX(CASE WHEN Metric = 'Revenue (Net)'     THEN Value END) AS Revenue,
        MAX(CASE WHEN Metric = 'Variable Costs'     THEN Value END) AS Variable_Costs,
        MAX(CASE WHEN Metric = 'Total Fixed Costs'  THEN Value END) AS Fixed_Costs
    FROM pl_monthly
    GROUP BY Scenario, Month_Number
),

with_growth AS (
    -- Step 2: Compute MoM growth rates for Revenue, Total Costs,
    --         Variable Costs, and Fixed Costs independently
    SELECT
        Scenario,
        Month_Number,
        Revenue,
        Variable_Costs,
        Fixed_Costs,
        Variable_Costs + Fixed_Costs                AS Total_Costs,

        -- Revenue growth
        ROUND(
            (Revenue - LAG(Revenue) OVER w)
            / NULLIF(LAG(Revenue) OVER w, 0) * 100,
        4)                                          AS Revenue_MoM_Pct,

        -- Total cost growth (variable + fixed combined)
        ROUND(
            ((Variable_Costs + Fixed_Costs)
             - LAG(Variable_Costs + Fixed_Costs) OVER w)
            / NULLIF(LAG(Variable_Costs + Fixed_Costs) OVER w, 0) * 100,
        4)                                          AS Total_Cost_MoM_Pct,

        -- Variable cost growth (diagnostic: rides × per-ride costs)
        ROUND(
            (Variable_Costs - LAG(Variable_Costs) OVER w)
            / NULLIF(LAG(Variable_Costs) OVER w, 0) * 100,
        4)                                          AS VarCost_MoM_Pct,

        -- Fixed cost growth (diagnostic: fleet-linked + platform overhead)
        ROUND(
            (Fixed_Costs - LAG(Fixed_Costs) OVER w)
            / NULLIF(LAG(Fixed_Costs) OVER w, 0) * 100,
        4)                                          AS FixCost_MoM_Pct
    FROM monthly_wide
    WINDOW w AS (PARTITION BY Scenario ORDER BY Month_Number)
)

-- Step 3: Compare growth rates, compute the gap, and flag overtake events
SELECT
    Scenario,
    Month_Number                                    AS Month,
    ROUND(Revenue, 2)                               AS Revenue,
    ROUND(Total_Costs, 2)                           AS Total_Costs,
    Revenue_MoM_Pct,
    Total_Cost_MoM_Pct,
    VarCost_MoM_Pct,
    FixCost_MoM_Pct,
    ROUND(Revenue_MoM_Pct - Total_Cost_MoM_Pct, 4) AS Growth_Gap,
    CASE
        WHEN Total_Cost_MoM_Pct > Revenue_MoM_Pct
        THEN 'COST OVERTAKE'
        ELSE NULL
    END                                             AS Overtake_Flag
FROM with_growth
WHERE Month_Number > 1      -- Month 1 has no prior period for growth calc
ORDER BY Scenario, Month_Number;

-- ============================================================================
-- EXPECTED OUTPUT (33 rows: 3 scenarios × 11 months)
-- ============================================================================
--
-- Key findings:
--
--   BASE SCENARIO — Persistent cost overtake (Growth Gap: ~-0.60pp):
--   • Revenue grows at ~3.89% MoM while total costs grow at ~4.49% MoM.
--     Costs outpace revenue every single month.
--   • Variable costs lead the overtake at ~4.55% MoM (driven by fleet
--     growth of 3% + cost inflation of 1.5% compounding together).
--   • Fixed costs grow at ~4.24% MoM (fleet-linked insurance and
--     depreciation scaling with fleet expansion).
--   • Despite the cost overtake, the business remains profitable because
--     revenue is ~2.6× total costs in absolute terms — the margin is
--     compressing slowly, not collapsing.
--
--   HIGH SCENARIO — Revenue comfortably outpaces costs (Growth Gap: ~+1.07pp):
--   • Revenue grows at ~6.87% MoM vs total costs at ~5.80% MoM.
--     The growth gap is positive and WIDENING over time (+1.06 in Month 2
--     to +1.09 by Month 12), meaning margins are expanding.
--   • This is driven by 2% monthly price growth compounding on top of
--     5% fleet growth — the price lever creates a revenue tailwind that
--     costs cannot match.
--
--   LOW SCENARIO — Severe cost overtake (Growth Gap: ~-2.49pp):
--   • Revenue grows at only 1.0% MoM (pure fleet growth, no pricing
--     power) while costs grow at ~3.49% MoM.
--   • The growth gap of -2.49pp is over 4× worse than the Base case.
--     Cost inflation at 2.5% per month overwhelms the 1% fleet growth.
--   • This is the structural cause behind the EBITDA crossover identified
--     in Query 02 and the payback failure in Query 08.
--
--   DIAGNOSTIC INSIGHT:
--   • Variable costs grow faster than fixed costs in all scenarios
--     because they scale with both fleet growth AND cost inflation,
--     while fixed costs scale only with fleet growth (insurance,
--     depreciation) plus a smaller inflation effect on platform overhead.
-- ============================================================================
