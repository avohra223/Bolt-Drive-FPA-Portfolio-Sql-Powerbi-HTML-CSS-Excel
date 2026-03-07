-- ============================================================================
-- QUERY 14: Scenario-Weighted Expected EBITDA
-- ============================================================================
-- PURPOSE:
--   Assign probability weights to the three scenarios (25% Low, 50% Base,
--   25% High) and compute a weighted expected EBITDA for each month.
--   Compares the probability-weighted expectation to the Base case alone
--   to reveal whether the Base case is optimistic or conservative relative
--   to the full distribution of outcomes. Also tracks the probability-
--   weighted downside and cumulative expected EBITDA.
--
-- WHY SQL (NOT EXCEL):
--   Requires joining a weights table to the monthly P&L, multiplying three
--   scenarios' EBITDA by their respective weights, aggregating into a
--   single expected value per month, then comparing to the Base case and
--   computing a running cumulative — all in one pass. Excel would need
--   a separate weights lookup, three weighted columns, a SUMPRODUCT per
--   month, a comparison column, and a running total column. Changing the
--   weights (e.g., from 25/50/25 to 20/60/20) requires editing one CTE
--   in SQL vs modifying every formula reference in Excel.
--
-- TECHNIQUES: CTE-based scenario weights, JOIN and weighted aggregation,
--             conditional MAX for Base case extraction, SUM() OVER for
--             cumulative totals, derived margin calculations
-- ============================================================================

WITH scenario_weights AS (
    -- Probability weights: adjust here to model different views
    -- Conservative: 25% Low / 50% Base / 25% High
    SELECT 'Low'  AS Scenario, 0.25 AS Weight
    UNION ALL
    SELECT 'Base' AS Scenario, 0.50 AS Weight
    UNION ALL
    SELECT 'High' AS Scenario, 0.25 AS Weight
),

monthly_metrics AS (
    -- Extract EBITDA and Revenue for each scenario-month
    SELECT
        Scenario,
        Month_Number,
        MAX(CASE WHEN Metric = 'EBITDA'         THEN Value END) AS EBITDA,
        MAX(CASE WHEN Metric = 'Revenue (Net)'  THEN Value END) AS Revenue,
        MAX(CASE WHEN Metric = 'EBITDA Margin %' THEN Value END) AS EBITDA_Margin
    FROM pl_monthly
    WHERE Metric IN ('EBITDA', 'Revenue (Net)', 'EBITDA Margin %')
    GROUP BY Scenario, Month_Number
),

weighted AS (
    -- Apply probability weights to each scenario's values
    SELECT
        m.Month_Number,
        m.Scenario,
        sw.Weight,
        m.EBITDA,
        m.Revenue,
        m.EBITDA_Margin,
        m.EBITDA  * sw.Weight       AS Weighted_EBITDA,
        m.Revenue * sw.Weight       AS Weighted_Revenue
    FROM monthly_metrics m
    JOIN scenario_weights sw
        ON m.Scenario = sw.Scenario
),

expected_values AS (
    -- Aggregate: sum weighted values, extract Base for comparison
    SELECT
        Month_Number,
        SUM(Weighted_EBITDA)            AS Expected_EBITDA,
        SUM(Weighted_Revenue)           AS Expected_Revenue,
        SUM(Weighted_EBITDA)
            / NULLIF(SUM(Weighted_Revenue), 0)
                                        AS Expected_EBITDA_Margin,
        -- Base case for comparison
        MAX(CASE WHEN Scenario = 'Base'
            THEN EBITDA END)            AS Base_EBITDA,
        MAX(CASE WHEN Scenario = 'Base'
            THEN Revenue END)           AS Base_Revenue,
        MAX(CASE WHEN Scenario = 'Base'
            THEN EBITDA_Margin END)     AS Base_EBITDA_Margin,
        -- Full range (High - Low) as uncertainty width
        MAX(CASE WHEN Scenario = 'High'
            THEN EBITDA END)
        - MAX(CASE WHEN Scenario = 'Low'
            THEN EBITDA END)            AS EBITDA_Range,
        -- Probability-weighted downside contribution
        MAX(CASE WHEN Scenario = 'Low'
            THEN EBITDA * Weight END)   AS Weighted_Low_EBITDA
    FROM weighted
    GROUP BY Month_Number
)

SELECT
    Month_Number                            AS Month,
    ROUND(Expected_EBITDA, 2)               AS Expected_EBITDA,
    ROUND(Base_EBITDA, 2)                   AS Base_EBITDA,
    ROUND(Expected_EBITDA - Base_EBITDA, 2) AS Exp_vs_Base_Delta,
    ROUND(
        (Expected_EBITDA - Base_EBITDA)
        / NULLIF(Base_EBITDA, 0) * 100,
    2)                                      AS Exp_vs_Base_Pct,
    ROUND(Expected_Revenue, 2)              AS Expected_Revenue,
    ROUND(Expected_EBITDA_Margin * 100, 2)  AS Expected_EBITDA_Margin_Pct,
    ROUND(Base_EBITDA_Margin * 100, 2)      AS Base_EBITDA_Margin_Pct,
    ROUND(EBITDA_Range, 2)                  AS EBITDA_Range_High_Low,
    ROUND(Weighted_Low_EBITDA, 2)           AS Prob_Weighted_Downside,
    -- Running cumulative expected EBITDA
    ROUND(SUM(Expected_EBITDA) OVER (
        ORDER BY Month_Number), 2)          AS Cumulative_Expected_EBITDA
FROM expected_values
ORDER BY Month_Number;

-- ============================================================================
-- EXPECTED OUTPUT (12 rows: 1 per month)
-- ============================================================================
--
-- Key findings:
--
--   THE BASE CASE IS CONSERVATIVE:
--   • Expected EBITDA exceeds Base EBITDA in every month, starting at
--     +44.5% in Month 1 and widening to +84.8% by Month 12.
--   • This is because the High scenario's upside (€7.8M to €16.7M
--     monthly EBITDA) massively outweighs the Low scenario's downside
--     (€96K to -€182K). The distribution is positively skewed.
--   • Cumulative expected EBITDA reaches €50.3M vs Base's €30.5M --
--     the probability-weighted view suggests the Base case understates
--     the likely outcome by roughly 65%.
--
--   EXPECTED MARGIN IS HIGHER AND IMPROVING:
--   • Expected EBITDA margin starts at 69.0% and rises to 71.2%,
--     while Base margin starts at 62.3% and declines to 59.8%.
--   • The expected margin improves because the High scenario's
--     expanding margins (driven by price growth outpacing costs)
--     dominate the weighted average.
--
--   PROBABILITY-WEIGHTED DOWNSIDE:
--   • The Low scenario's weighted EBITDA contribution starts at +€24K
--     in Month 1 (still positive) but turns negative from Month 6
--     onward, reaching -€45K by Month 12.
--   • Even at 25% probability weight, the Low scenario's drag is
--     negligible relative to the High scenario's contribution -- the
--     asymmetry is extreme.
--
--   STRATEGIC IMPLICATION:
--   • If management is using the Base case for planning, they may be
--     under-investing. The expected value of outcomes (given reasonable
--     probability weights) is substantially higher than Base alone.
--   • However, the widening EBITDA range (€7.7M in Month 1 to €16.8M
--     by Month 12) means the uncertainty is also growing -- higher
--     expected returns come with higher variance.
-- ============================================================================
