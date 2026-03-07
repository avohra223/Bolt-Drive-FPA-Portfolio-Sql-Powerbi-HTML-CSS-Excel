-- ============================================================================
-- QUERY 02: Scenario Crossover Detection — Zero-Line Breach Identification
-- ============================================================================
-- PURPOSE:
--   Detect the exact month where any metric crosses the zero line (positive
--   to negative or vice versa) within each scenario. Uses linear interpolation
--   to estimate the fractional month of the crossover. Also counts how many
--   months each scenario sustains positive values before the breach.
--
-- WHY SQL (NOT EXCEL):
--   Sign-change detection across 3 scenarios × 12 months × multiple metrics
--   requires LAG to compare consecutive values, conditional filtering for
--   sign flips, and interpolation math — all in a single pass. Excel has no
--   native sign-change detection; you would need nested IF formulas per cell
--   and a separate helper row per metric per scenario. Adding a new metric
--   or scenario here requires zero structural changes to the query.
--
-- TECHNIQUES: LAG window function, CASE-based sign detection, linear
--             interpolation, LEFT JOIN for contextual aggregation
-- ============================================================================

WITH monthly_with_lag AS (
    -- Step 1: For each scenario and metric, attach the previous month's
    --         value alongside the current month's value
    SELECT
        Scenario,
        Month_Number,
        Metric,
        Value AS Current_Value,
        LAG(Value) OVER (
            PARTITION BY Scenario, Metric
            ORDER BY Month_Number
        )      AS Prev_Value
    FROM pl_monthly
    WHERE Metric IN (
        'EBITDA',
        'Contribution Margin',
        'Revenue (Net)',
        'EBITDA Margin %',
        'Contribution Margin %'
    )
),

sign_crossings AS (
    -- Step 2: Isolate rows where the sign flips between consecutive months.
    --         Interpolate the fractional month where the value passes through
    --         zero, assuming linear movement between the two data points.
    SELECT
        Scenario,
        Metric,
        Month_Number                        AS Crossing_Month,
        Prev_Value                          AS Value_Before,
        Current_Value                       AS Value_After,
        CASE
            WHEN Prev_Value >= 0 AND Current_Value < 0
                THEN 'Positive to Negative'
            WHEN Prev_Value < 0  AND Current_Value >= 0
                THEN 'Negative to Positive'
        END                                 AS Crossing_Direction,
        -- Linear interpolation: Month(n-1) + fraction where zero falls
        ROUND(
            (Month_Number - 1)
            + ABS(Prev_Value)
              / NULLIF(ABS(Prev_Value) + ABS(Current_Value), 0),
        2)                                  AS Interpolated_Zero_Month
    FROM monthly_with_lag
    WHERE Prev_Value IS NOT NULL
      AND (
            (Prev_Value >= 0 AND Current_Value < 0)
         OR (Prev_Value < 0  AND Current_Value >= 0)
          )
),

months_positive AS (
    -- Step 3: Count how many of the 12 months each scenario-metric pair
    --         remains at or above zero (sustainability gauge)
    SELECT
        Scenario,
        Metric,
        COUNT(*) AS Months_Remaining_Positive
    FROM pl_monthly
    WHERE Value >= 0
      AND Metric IN (
          'EBITDA',
          'Contribution Margin',
          'Revenue (Net)',
          'EBITDA Margin %',
          'Contribution Margin %'
      )
    GROUP BY Scenario, Metric
)

-- Final output: every zero-line breach with interpolated timing and context
SELECT
    sc.Scenario,
    sc.Metric,
    sc.Crossing_Direction,
    sc.Crossing_Month,
    sc.Interpolated_Zero_Month,
    ROUND(sc.Value_Before, 2)                       AS Value_Before_Crossing,
    ROUND(sc.Value_After, 2)                        AS Value_After_Crossing,
    ROUND(ABS(sc.Value_After - sc.Value_Before), 2) AS Absolute_Swing,
    mp.Months_Remaining_Positive                    AS Total_Months_Positive
FROM sign_crossings sc
LEFT JOIN months_positive mp
    ON sc.Scenario = mp.Scenario
   AND sc.Metric   = mp.Metric
ORDER BY sc.Scenario, sc.Metric, sc.Crossing_Month;

-- ============================================================================
-- EXPECTED OUTPUT (2 rows)
-- ============================================================================
-- Only the Low scenario breaches zero:
--
-- | Scenario | Metric         | Direction            | Month | Interp. | Before    | After      |
-- |----------|----------------|----------------------|-------|---------|-----------|------------|
-- | Low      | EBITDA         | Positive to Negative | 6     | 5.42    | 10,089.77 | -13,873.10 |
-- | Low      | EBITDA Margin% | Positive to Negative | 6     | 5.42    | 0.01      | -0.01      |
--
-- Key findings:
--   • The Low scenario's EBITDA turns negative at Month 6 (interpolated:
--     Month 5.42), meaning the business becomes loss-making roughly halfway
--     through the year under pessimistic assumptions.
--   • Base and High scenarios show NO crossovers — both remain profitable
--     across all 12 months, confirming the downside risk is concentrated
--     in the Low case.
--   • Contribution Margin stays positive even in Low, meaning the per-ride
--     economics are viable; it is the fixed cost base (insurance,
--     depreciation, platform overhead) that pushes EBITDA below zero.
-- ============================================================================
