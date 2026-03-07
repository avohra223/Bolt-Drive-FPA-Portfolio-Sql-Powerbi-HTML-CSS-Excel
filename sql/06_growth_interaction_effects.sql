-- ============================================================================
-- QUERY 06: Growth Scenario Interaction Effects — Additive vs Compounding
-- ============================================================================
-- PURPOSE:
--   Determine whether fleet growth and price growth combine additively or
--   produce a compounding interaction effect. For every (Fleet_Growth,
--   Price_Growth) pair, compare the actual outcome to the sum of the
--   individual effects: f(x,y) vs f(x,0) + f(0,y) - f(0,0). Any
--   difference is the interaction term — value created (or destroyed)
--   by pursuing both levers simultaneously.
--
-- WHY SQL (NOT EXCEL):
--   This analysis requires a four-way self-join on the same sensitivity
--   table: the origin cell (0,0), the fleet-only column (x,0), the
--   price-only row (0,y), and every interior cell (x,y). Excel would
--   need three separate VLOOKUP/INDEX-MATCH references per cell plus a
--   manual subtraction — and would break entirely if the grid dimensions
--   changed. The SQL approach scales to any grid size with zero changes.
--
-- TECHNIQUES: Four-way JOIN on the same table with different filter
--             conditions, arithmetic decomposition (additive baseline
--             vs actual), percentage-of-actual calculation
-- ============================================================================

WITH grid AS (
    SELECT Fleet_Growth, Price_Growth, Output, Value
    FROM sensitivity_growth
),

-- Anchor: the zero-growth baseline f(0, 0)
origin AS (
    SELECT Output, Value AS Origin_Value
    FROM grid
    WHERE Fleet_Growth = 0.0
      AND Price_Growth = 0.0
),

-- Isolated fleet growth effect: f(x, 0) — price growth held at zero
fleet_only AS (
    SELECT Fleet_Growth, Output, Value AS Fleet_Only_Value
    FROM grid
    WHERE Price_Growth = 0.0
),

-- Isolated price growth effect: f(0, y) — fleet growth held at zero
price_only AS (
    SELECT Price_Growth, Output, Value AS Price_Only_Value
    FROM grid
    WHERE Fleet_Growth = 0.0
),

-- Four-way join: for every interior (x,y) cell, compute the interaction
interaction AS (
    SELECT
        g.Fleet_Growth,
        g.Price_Growth,
        g.Output,
        g.Value                         AS Actual_Value,
        o.Origin_Value,
        fo.Fleet_Only_Value,
        po.Price_Only_Value,

        -- What the outcome WOULD be if the effects were purely additive
        (fo.Fleet_Only_Value + po.Price_Only_Value - o.Origin_Value)
            AS Additive_Expected,

        -- The interaction term: positive = compounding synergy
        g.Value - (fo.Fleet_Only_Value + po.Price_Only_Value - o.Origin_Value)
            AS Interaction_Effect,

        -- Interaction as a percentage of the actual outcome
        ROUND(
            (g.Value - (fo.Fleet_Only_Value + po.Price_Only_Value - o.Origin_Value))
            / NULLIF(g.Value, 0) * 100,
        4)                              AS Interaction_Pct_of_Actual
    FROM grid g
    JOIN origin o
        ON g.Output = o.Output
    JOIN fleet_only fo
        ON g.Fleet_Growth = fo.Fleet_Growth
       AND g.Output       = fo.Output
    JOIN price_only po
        ON g.Price_Growth = po.Price_Growth
       AND g.Output       = po.Output
    -- Only interior cells where both growth rates are non-zero
    WHERE g.Fleet_Growth > 0
      AND g.Price_Growth > 0
)

SELECT
    Fleet_Growth,
    Price_Growth,
    Output,
    CASE
        WHEN Output = 'FY_Net_Revenue'
            THEN ROUND(Actual_Value, 0)
        ELSE ROUND(Actual_Value, 4)
    END                                 AS Actual,
    CASE
        WHEN Output = 'FY_Net_Revenue'
            THEN ROUND(Additive_Expected, 0)
        ELSE ROUND(Additive_Expected, 4)
    END                                 AS Additive_Expected,
    CASE
        WHEN Output = 'FY_Net_Revenue'
            THEN ROUND(Interaction_Effect, 0)
        ELSE ROUND(Interaction_Effect, 4)
    END                                 AS Interaction_Effect,
    Interaction_Pct_of_Actual
FROM interaction
ORDER BY Output, Fleet_Growth, Price_Growth;

-- ============================================================================
-- EXPECTED OUTPUT (32 rows: 16 interior cells × 2 outputs)
-- ============================================================================
--
-- Key findings:
--
--   REVENUE — MEANINGFUL COMPOUNDING:
--   • Interaction effects are positive across every cell, confirming
--     fleet growth and price growth compound rather than merely add.
--   • At the extreme corner (6% fleet, 2% price), the interaction
--     contributes ~€2.4M (3.8% of actual FY revenue). This is revenue
--     that would be missed by a model that treated the levers as
--     independent.
--   • The interaction scales with both inputs: higher fleet growth AND
--     higher price growth together amplify the synergy, because more
--     vehicles earn at the higher price, and the price increase applies
--     to a growing fleet base.
--
--   EBITDA MARGIN — SMALL BUT CONSISTENT:
--   • Interaction effects on margin are positive but tiny (0.03% to
--     0.56% of actual margin). This makes sense: margin is a ratio,
--     so the compounding revenue effect in the numerator is partially
--     offset by proportionally higher costs in the denominator.
--   • Still, the interaction is always positive — pursuing both growth
--     levers simultaneously never hurts margin relative to pursuing
--     them individually.
--
--   STRATEGIC IMPLICATION:
--   • A management team debating "should we grow the fleet OR raise
--     prices?" is asking the wrong question. The data shows a synergy
--     worth up to €2.4M in FY revenue from doing both. The interaction
--     effect is not noise — it is real compounding value.
-- ============================================================================
