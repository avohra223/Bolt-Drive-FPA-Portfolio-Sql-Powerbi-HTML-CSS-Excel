-- ============================================================================
-- QUERY 07: Revenue Growth Decomposition — Volume vs Price vs Mix Effect
-- ============================================================================
-- PURPOSE:
--   For each month and scenario, decompose total revenue change into three
--   components: (1) Volume Effect — extra revenue from more rides at the
--   prior month's price, (2) Price Effect — extra revenue from higher
--   pricing on the prior month's ride volume, and (3) Mix Effect — the
--   cross-term from both changing simultaneously. Reveals which growth
--   driver is actually propelling the business forward.
--
-- WHY SQL (NOT EXCEL):
--   Requires computing Revenue per Ride (a derived metric not in the source
--   data), applying LAG to both Rides and RPR simultaneously, then
--   performing three separate multiplication-based decompositions per row.
--   In Excel, this would need: a helper column for RPR, two more helper
--   columns for lagged values, three decomposition columns, and three
--   percentage columns — all of which must be repeated per scenario on
--   separate sheets. SQL does it for all scenarios in one pass and handles
--   any number of months or scenarios without restructuring.
--
-- TECHNIQUES: Conditional aggregation (pivot), derived metric (RPR),
--             LAG window function on multiple columns, multiplicative
--             decomposition (Volume/Price/Mix attribution)
-- ============================================================================

WITH monthly_wide AS (
    -- Step 1: Pivot Revenue and Rides into columns per scenario-month
    SELECT
        Scenario,
        Month_Number,
        MAX(CASE WHEN Metric = 'Revenue (Net)' THEN Value END) AS Revenue,
        MAX(CASE WHEN Metric = 'Total Rides'   THEN Value END) AS Rides
    FROM pl_monthly
    WHERE Metric IN ('Revenue (Net)', 'Total Rides')
    GROUP BY Scenario, Month_Number
),

with_unit_economics AS (
    -- Step 2: Derive Revenue per Ride (RPR) and attach prior-month values
    --         for Revenue, Rides, and RPR using LAG
    SELECT
        Scenario,
        Month_Number,
        Revenue,
        Rides,
        Revenue / NULLIF(Rides, 0)          AS Rev_Per_Ride,
        LAG(Revenue) OVER (
            PARTITION BY Scenario ORDER BY Month_Number)    AS Prev_Revenue,
        LAG(Rides) OVER (
            PARTITION BY Scenario ORDER BY Month_Number)    AS Prev_Rides,
        LAG(Revenue / NULLIF(Rides, 0)) OVER (
            PARTITION BY Scenario ORDER BY Month_Number)    AS Prev_RPR
    FROM monthly_wide
),

decomposition AS (
    -- Step 3: Multiplicative decomposition of revenue change
    --   Total Change = Volume Effect + Price Effect + Mix Effect
    --
    --   Volume Effect = (Rides_t - Rides_t-1) × RPR_t-1
    --     "Revenue gained from additional rides at the old price"
    --
    --   Price Effect  = (RPR_t - RPR_t-1) × Rides_t-1
    --     "Revenue gained from higher pricing on the old ride volume"
    --
    --   Mix Effect    = (Rides_t - Rides_t-1) × (RPR_t - RPR_t-1)
    --     "Cross-term: new rides at the new price increment"
    SELECT
        Scenario,
        Month_Number,
        Revenue,
        Rides,
        ROUND(Rev_Per_Ride, 4)                                  AS Rev_Per_Ride,
        Revenue - Prev_Revenue                                  AS Total_Rev_Change,
        (Rides - Prev_Rides) * Prev_RPR                         AS Volume_Effect,
        (Rev_Per_Ride - Prev_RPR) * Prev_Rides                  AS Price_Effect,
        (Rides - Prev_Rides) * (Rev_Per_Ride - Prev_RPR)        AS Mix_Effect
    FROM with_unit_economics
    WHERE Prev_Revenue IS NOT NULL
)

SELECT
    Scenario,
    Month_Number                                                AS Month,
    ROUND(Total_Rev_Change, 2)                                  AS Total_Rev_Change,
    ROUND(Volume_Effect, 2)                                     AS Volume_Effect,
    ROUND(Price_Effect, 2)                                      AS Price_Effect,
    ROUND(Mix_Effect, 2)                                        AS Mix_Effect,
    ROUND(Volume_Effect / NULLIF(Total_Rev_Change, 0) * 100, 2) AS Volume_Pct,
    ROUND(Price_Effect  / NULLIF(Total_Rev_Change, 0) * 100, 2) AS Price_Pct,
    ROUND(Mix_Effect    / NULLIF(Total_Rev_Change, 0) * 100, 2) AS Mix_Pct
FROM decomposition
ORDER BY Scenario, Month_Number;

-- ============================================================================
-- EXPECTED OUTPUT (33 rows: 3 scenarios × 11 months, Month 1 excluded)
-- ============================================================================
--
-- Key findings:
--
--   BASE SCENARIO (~77% Volume / ~22% Price / ~1% Mix):
--   • Volume is the primary revenue driver at roughly 3:1 over price.
--     This reflects the 3% monthly fleet growth compounding into more
--     rides, while the 1% monthly price growth has a proportionally
--     smaller (but consistent) contribution.
--   • The Mix Effect is negligible (~0.67%), meaning the interaction
--     between volume and price growth is minimal at these rates.
--   • The split is remarkably stable month-over-month, indicating
--     consistent growth dynamics with no structural shifts.
--
--   HIGH SCENARIO (~73% Volume / ~26% Price / ~1.3% Mix):
--   • Price contributes a larger share than in Base (26% vs 22%)
--     because the High case has 2% monthly price growth (vs 1% Base)
--     and a higher starting price per minute (€0.38 vs €0.29).
--   • The Mix Effect is larger (~1.3%) due to the compounding of
--     5% fleet growth with 2% price growth — both are aggressive.
--   • Monthly revenue increments grow from ~€676K to ~€1.3M,
--     reflecting the compounding effect of simultaneous growth.
--
--   LOW SCENARIO (100% Volume / 0% Price / 0% Mix):
--   • Revenue growth is ENTIRELY volume-driven. Revenue per ride is
--     flat at €3.42 across all 12 months because the Low case assumes
--     0% monthly price growth.
--   • This makes the Low scenario uniquely vulnerable: it has only
--     one growth lever (fleet expansion at 1%/month), and that lever
--     is too weak to overcome the cost inflation (2.5%/month), which
--     is why EBITDA turns negative by Month 6.
-- ============================================================================
