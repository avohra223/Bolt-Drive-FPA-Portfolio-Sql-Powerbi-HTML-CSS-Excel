WITH monthly_wide AS (
    -- Step 1: Pivot P&L metrics into columns
    SELECT
        Scenario,
        Month_Number,
        MAX(CASE WHEN Metric = 'Revenue (Net)'       THEN Value END) AS Revenue,
        MAX(CASE WHEN Metric = 'EBITDA'               THEN Value END) AS EBITDA,
        MAX(CASE WHEN Metric = 'Contribution Margin'  THEN Value END) AS Contribution_Margin,
        MAX(CASE WHEN Metric = 'Total Fixed Costs'    THEN Value END) AS Fixed_Costs,
        MAX(CASE WHEN Metric = 'Variable Costs'       THEN Value END) AS Variable_Costs
    FROM pl_monthly
    GROUP BY Scenario, Month_Number
),

margin_of_safety AS (
    -- Step 2: Compute breakeven revenue and margin of safety
    --
    -- Breakeven Revenue = Fixed Costs / CM%
    -- where CM% = Contribution Margin / Revenue
    --
    -- At breakeven, all contribution margin is consumed by fixed costs,
    -- leaving EBITDA = 0. Any revenue above breakeven is the "safety buffer."
    SELECT
        Scenario,
        Month_Number,
        Revenue,
        EBITDA,
        Fixed_Costs,
        Contribution_Margin,
        -- Breakeven revenue: the minimum revenue to cover fixed costs
        Fixed_Costs / NULLIF(
            Contribution_Margin / NULLIF(Revenue, 0), 0
        )                                   AS Breakeven_Revenue,
        -- Margin of Safety (absolute €)
        Revenue - Fixed_Costs / NULLIF(
            Contribution_Margin / NULLIF(Revenue, 0), 0
        )                                   AS MoS_Absolute,
        -- Margin of Safety (% of actual revenue)
        (Revenue - Fixed_Costs / NULLIF(
            Contribution_Margin / NULLIF(Revenue, 0), 0
        )) / NULLIF(Revenue, 0) * 100       AS MoS_Pct
    FROM monthly_wide
),

with_trend AS (
    -- Step 3: Compute MoM change in margin of safety and classify the trend
    SELECT
        m.*,
        m.MoS_Pct - LAG(m.MoS_Pct) OVER (
            PARTITION BY m.Scenario
            ORDER BY m.Month_Number
        )                                   AS MoS_Pct_Change,
        -- Revenue as a multiple of breakeven (how many "breakevens" of
        -- headroom does the business have?)
        m.Revenue / NULLIF(
            m.Breakeven_Revenue, 0
        )                                   AS Rev_to_BE_Multiple
    FROM margin_of_safety m
)

SELECT
    Scenario,
    Month_Number                            AS Month,
    ROUND(Revenue, 2)                       AS Revenue,
    ROUND(Breakeven_Revenue, 2)             AS Breakeven_Revenue,
    ROUND(MoS_Absolute, 2)                  AS MoS_Absolute,
    ROUND(MoS_Pct, 2)                       AS MoS_Pct,
    ROUND(MoS_Pct_Change, 4)               AS MoS_MoM_Change_pp,
    CASE
        WHEN MoS_Pct_Change > 0 THEN 'EXPANDING'
        WHEN MoS_Pct_Change < 0 THEN 'CONTRACTING'
        ELSE NULL
    END                                     AS MoS_Trend,
    ROUND(Rev_to_BE_Multiple, 2)            AS Rev_to_BE_Multiple
FROM with_trend
ORDER BY Scenario, Month_Number;
