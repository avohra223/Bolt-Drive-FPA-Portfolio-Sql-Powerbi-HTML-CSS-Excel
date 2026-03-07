WITH price_util_audit AS (
    -- Grid shape and completeness for the Price × Utilization table
    SELECT
        'sensitivity_price_util'                AS Table_Name,
        COUNT(*)                                AS Total_Rows,
        COUNT(DISTINCT Price_Per_Min)           AS Distinct_Input_A,
        COUNT(DISTINCT Util_Rate)               AS Distinct_Input_B,
        COUNT(DISTINCT Output)                  AS Distinct_Outputs,
        COUNT(DISTINCT Price_Per_Min)
            * COUNT(DISTINCT Util_Rate)
            * COUNT(DISTINCT Output)            AS Expected_Rows,
        SUM(CASE WHEN Value IS NULL
            THEN 1 ELSE 0 END)                  AS Null_Values
    FROM sensitivity_price_util
),

growth_audit AS (
    -- Grid shape and completeness for the Fleet Growth × Price Growth table
    SELECT
        'sensitivity_growth'                    AS Table_Name,
        COUNT(*)                                AS Total_Rows,
        COUNT(DISTINCT Fleet_Growth)            AS Distinct_Input_A,
        COUNT(DISTINCT Price_Growth)            AS Distinct_Input_B,
        COUNT(DISTINCT Output)                  AS Distinct_Outputs,
        COUNT(DISTINCT Fleet_Growth)
            * COUNT(DISTINCT Price_Growth)
            * COUNT(DISTINCT Output)            AS Expected_Rows,
        SUM(CASE WHEN Value IS NULL
            THEN 1 ELSE 0 END)                  AS Null_Values
    FROM sensitivity_growth
),

-- Duplicate detection: count how many (input, input, output) groups
-- have more than one row
pu_dup_count AS (
    SELECT COUNT(*) AS Dup_Groups
    FROM (
        SELECT Price_Per_Min, Util_Rate, Output
        FROM sensitivity_price_util
        GROUP BY Price_Per_Min, Util_Rate, Output
        HAVING COUNT(*) > 1
    )
),

gr_dup_count AS (
    SELECT COUNT(*) AS Dup_Groups
    FROM (
        SELECT Fleet_Growth, Price_Growth, Output
        FROM sensitivity_growth
        GROUP BY Fleet_Growth, Price_Growth, Output
        HAVING COUNT(*) > 1
    )
),

-- Cross-table base case reconciliation:
-- Price=0.29 / Util=0.65 should match Fleet_Growth=0.03 / Price_Growth=0.01
base_case_check AS (
    SELECT
        pu.Output,
        pu.Value                                AS PU_Base_Value,
        gr.Value                                AS GR_Base_Value,
        ROUND(ABS(pu.Value - gr.Value), 4)      AS Variance
    FROM sensitivity_price_util pu
    JOIN sensitivity_growth gr
        ON pu.Output = gr.Output
    WHERE pu.Price_Per_Min = 0.29 AND pu.Util_Rate = 0.65
      AND gr.Fleet_Growth  = 0.03 AND gr.Price_Growth = 0.01
)

-- Combine all audit results into a single output
SELECT
    '1_GRID_COMPLETENESS'               AS Audit_Check,
    p.Table_Name,
    p.Total_Rows,
    p.Expected_Rows,
    p.Distinct_Input_A || ' x '
        || p.Distinct_Input_B || ' x '
        || p.Distinct_Outputs           AS Grid_Shape,
    p.Null_Values,
    CASE
        WHEN p.Total_Rows = p.Expected_Rows AND p.Null_Values = 0
        THEN 'PASS' ELSE 'FAIL'
    END                                 AS Status
FROM price_util_audit p

UNION ALL
SELECT
    '1_GRID_COMPLETENESS',
    g.Table_Name, g.Total_Rows, g.Expected_Rows,
    g.Distinct_Input_A || ' x '
        || g.Distinct_Input_B || ' x '
        || g.Distinct_Outputs,
    g.Null_Values,
    CASE
        WHEN g.Total_Rows = g.Expected_Rows AND g.Null_Values = 0
        THEN 'PASS' ELSE 'FAIL'
    END
FROM growth_audit g

UNION ALL
SELECT
    '2_DUPLICATE_CHECK',
    'sensitivity_price_util',
    pu.Dup_Groups,
    0,
    NULL,
    NULL,
    CASE WHEN pu.Dup_Groups = 0 THEN 'PASS' ELSE 'FAIL' END
FROM pu_dup_count pu

UNION ALL
SELECT
    '2_DUPLICATE_CHECK',
    'sensitivity_growth',
    gr.Dup_Groups,
    0,
    NULL,
    NULL,
    CASE WHEN gr.Dup_Groups = 0 THEN 'PASS' ELSE 'FAIL' END
FROM gr_dup_count gr

UNION ALL
SELECT
    '3_BASE_CASE_CROSS_CHECK',
    b.Output,
    b.PU_Base_Value,
    b.GR_Base_Value,
    NULL,
    b.Variance,
    CASE WHEN b.Variance = 0 THEN 'PASS' ELSE 'FAIL' END
FROM base_case_check b;
