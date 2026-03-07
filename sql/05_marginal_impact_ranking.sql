-- ============================================================================
-- QUERY 05: Marginal Impact Ranking — Which Lever Moves the Needle Most?
-- ============================================================================
-- PURPOSE:
--   Across BOTH sensitivity tables (price-utilization and growth), compute
--   how much each of the four business levers (price per minute, utilization
--   rate, fleet growth rate, price growth rate) shifts FY Net Revenue and
--   FY EBITDA Margin relative to the Base case. Ranks levers by average
--   absolute sensitivity per unit of change to answer: "If I can only
--   improve one thing, what should it be?"
--
-- WHY SQL (NOT EXCEL):
--   The four levers live in two different sensitivity tables with different
--   column structures. Comparing them requires: (a) anchoring each table to
--   the same Base case values, (b) computing deltas along one axis while
--   holding the other constant, (c) normalising to a per-unit basis so
--   different scales (€/min vs % vs pp) are comparable, and (d) ranking
--   across all four levers in a single result set. This is a UNION ALL
--   across four CTEs followed by an aggregation and RANK — something that
--   would require four separate Excel analyses manually stitched together.
--
-- TECHNIQUES: CTE-based modular extraction, UNION ALL across heterogeneous
--             tables, AVG/MIN/MAX aggregation, RANK window function
-- ============================================================================

WITH base_anchors AS (
    -- Base case values (Price=€0.29, Util=65%, Fleet Growth=3%, Price Growth=1%)
    -- These are the centre points of both sensitivity grids
    SELECT 'FY_Net_Revenue'   AS Output, 50118355.0 AS Base_Value
    UNION ALL
    SELECT 'FY_EBITDA_Margin' AS Output, 0.6419     AS Base_Value
),

-- ========================================================================
-- LEVER 1: Price per Minute (from sensitivity_price_util, hold Util=0.65)
-- ========================================================================
price_sensitivity AS (
    SELECT
        'Price_Per_Min'             AS Lever,
        s.Output,
        s.Price_Per_Min             AS Lever_Value,
        s.Value,
        b.Base_Value,
        s.Value - b.Base_Value      AS Delta_from_Base,
        (s.Value - b.Base_Value)
            / NULLIF(s.Price_Per_Min - 0.29, 0) AS Delta_Per_Unit
    FROM sensitivity_price_util s
    JOIN base_anchors b ON s.Output = b.Output
    WHERE s.Util_Rate     = 0.65        -- Hold utilization at base
      AND s.Price_Per_Min != 0.29       -- Exclude base itself
),

-- ========================================================================
-- LEVER 2: Utilization Rate (from sensitivity_price_util, hold Price=0.29)
-- ========================================================================
util_sensitivity AS (
    SELECT
        'Util_Rate'                 AS Lever,
        s.Output,
        s.Util_Rate                 AS Lever_Value,
        s.Value,
        b.Base_Value,
        s.Value - b.Base_Value      AS Delta_from_Base,
        (s.Value - b.Base_Value)
            / NULLIF(s.Util_Rate - 0.65, 0)    AS Delta_Per_Unit
    FROM sensitivity_price_util s
    JOIN base_anchors b ON s.Output = b.Output
    WHERE s.Price_Per_Min = 0.29        -- Hold price at base
      AND s.Util_Rate     != 0.65       -- Exclude base itself
),

-- ========================================================================
-- LEVER 3: Fleet Growth Rate (from sensitivity_growth, hold Price Growth=1%)
-- ========================================================================
fleet_growth_sensitivity AS (
    SELECT
        'Fleet_Growth'              AS Lever,
        s.Output,
        s.Fleet_Growth              AS Lever_Value,
        s.Value,
        b.Base_Value,
        s.Value - b.Base_Value      AS Delta_from_Base,
        (s.Value - b.Base_Value)
            / NULLIF(s.Fleet_Growth - 0.03, 0)  AS Delta_Per_Unit
    FROM sensitivity_growth s
    JOIN base_anchors b ON s.Output = b.Output
    WHERE s.Price_Growth  = 0.01        -- Hold price growth at base
      AND s.Fleet_Growth  != 0.03       -- Exclude base itself
),

-- ========================================================================
-- LEVER 4: Price Growth Rate (from sensitivity_growth, hold Fleet Growth=3%)
-- ========================================================================
price_growth_sensitivity AS (
    SELECT
        'Price_Growth'              AS Lever,
        s.Output,
        s.Price_Growth              AS Lever_Value,
        s.Value,
        b.Base_Value,
        s.Value - b.Base_Value      AS Delta_from_Base,
        (s.Value - b.Base_Value)
            / NULLIF(s.Price_Growth - 0.01, 0)  AS Delta_Per_Unit
    FROM sensitivity_growth s
    JOIN base_anchors b ON s.Output = b.Output
    WHERE s.Fleet_Growth  = 0.03        -- Hold fleet growth at base
      AND s.Price_Growth  != 0.01       -- Exclude base itself
),

-- Combine all four levers into a single dataset
all_levers AS (
    SELECT * FROM price_sensitivity
    UNION ALL SELECT * FROM util_sensitivity
    UNION ALL SELECT * FROM fleet_growth_sensitivity
    UNION ALL SELECT * FROM price_growth_sensitivity
),

-- Aggregate: average absolute sensitivity, worst/best case deltas
lever_ranking AS (
    SELECT
        Lever,
        Output,
        AVG(ABS(Delta_Per_Unit))    AS Avg_Abs_Sensitivity,
        MIN(Delta_from_Base)        AS Worst_Case_Delta,
        MAX(Delta_from_Base)        AS Best_Case_Delta,
        COUNT(*)                    AS Data_Points
    FROM all_levers
    GROUP BY Lever, Output
)

-- Final ranking: which lever has the highest marginal impact?
SELECT
    Lever,
    Output,
    CASE
        WHEN Output = 'FY_Net_Revenue'
            THEN ROUND(Avg_Abs_Sensitivity, 0)
        ELSE ROUND(Avg_Abs_Sensitivity, 4)
    END                             AS Avg_Sensitivity_Per_Unit,
    CASE
        WHEN Output = 'FY_Net_Revenue'
            THEN ROUND(Worst_Case_Delta, 0)
        ELSE ROUND(Worst_Case_Delta, 4)
    END                             AS Worst_Case_Delta,
    CASE
        WHEN Output = 'FY_Net_Revenue'
            THEN ROUND(Best_Case_Delta, 0)
        ELSE ROUND(Best_Case_Delta, 4)
    END                             AS Best_Case_Delta,
    Data_Points,
    RANK() OVER (
        PARTITION BY Output
        ORDER BY Avg_Abs_Sensitivity DESC
    )                               AS Impact_Rank
FROM lever_ranking
ORDER BY Output, Impact_Rank;

-- ============================================================================
-- EXPECTED OUTPUT (8 rows: 4 levers × 2 outputs)
-- ============================================================================
--
-- EBITDA MARGIN RANKING:
-- +------+-----------------+---------------------+--------+
-- | Rank | Lever           | Avg Sensitivity/Unit | Range  |
-- +------+-----------------+---------------------+--------+
-- |  1   | Price_Growth    | 1.8475 pp per 1pp   | ±1.9pp |
-- |  2   | Price_Per_Min   | 1.1169 pp per €1    | -11/+7pp|
-- |  3   | Util_Rate       | 0.1558 pp per 1pp   | ±2.9pp |
-- |  4   | Fleet_Growth    | 0.0725 pp per 1pp   | ±0.2pp |
-- +------+-----------------+---------------------+--------+
--
-- NET REVENUE RANKING:
-- +------+-----------------+---------------------+-----------+
-- | Rank | Lever           | Avg Sensitivity/Unit | Range     |
-- +------+-----------------+---------------------+-----------+
-- |  1   | Fleet_Growth    | €291M per 1pp       | -€8M/+€10M|
-- |  2   | Price_Growth    | €258M per 1pp       | ±€2.5M   |
-- |  3   | Price_Per_Min   | €151M per €1        | ±€12M    |
-- |  4   | Util_Rate       | €77M per 1pp        | ±€11.6M  |
-- +------+-----------------+---------------------+-----------+
--
-- Key findings:
--   • THE RANKINGS FLIP. For margin, Price Growth is #1 and Fleet Growth
--     is last. For revenue, Fleet Growth is #1 and Util Rate is last.
--     This means the optimal strategy depends on whether the business is
--     optimising for profitability or top-line growth.
--
--   • Price Growth is the strongest margin lever (1.85pp per 1pp change)
--     because it compounds monthly — a 1pp higher monthly price growth
--     rate accumulates across 12 months, amplifying its margin impact.
--
--   • Fleet Growth dominates revenue (€291M per 1pp) because more vehicles
--     directly scale ride volume, but it barely moves margin (Rank #4)
--     because the associated variable and fixed costs scale proportionally.
--
--   • Price Per Minute has the widest asymmetric range on margin (-11pp
--     downside vs +7pp upside), indicating diminishing returns at higher
--     price points — a pricing ceiling exists.
-- ============================================================================
