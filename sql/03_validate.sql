-- Phase 1, step 3: data-quality checks.
--
-- Builds one table, data_quality, with a row per check (and per vintage where it applies):
--   check_id, check_name, vintage, result, expected, passed
-- passed is TRUE/FALSE for checks with a clear right answer and NULL for "info" rows,
-- which are facts to record rather than pass or fail. run_sql.py prints the table and
-- saves it to outputs/data_quality.csv.

CREATE OR REPLACE TABLE data_quality AS
SELECT * FROM (

    -- 1. Each sample file should hold 50,000 loans.
    SELECT 1 AS check_id, 'Loans per vintage' AS check_name, vintage,
           CAST(count(*) AS VARCHAR) AS result, '50000' AS expected,
           count(*) = 50000 AS passed
    FROM loans
    GROUP BY vintage

    UNION ALL

    -- 2. Loan IDs should be unique.
    SELECT 2, 'Duplicate loan IDs', CAST(NULL AS INTEGER),
           CAST(count(*) AS VARCHAR), '0', count(*) = 0
    FROM (SELECT loan_id FROM loans GROUP BY loan_id HAVING count(*) > 1) AS dup

    UNION ALL

    -- 3. Characters 2-3 of the loan ID give its origination year (F07Q1... -> 2007).
    --    A small count can be legitimate if a file groups loans by first-payment date;
    --    a large count means a file is mislabeled. Info only.
    SELECT 3, 'Loan ID year differs from file year', vintage,
           CAST(count(*) FILTER (WHERE 2000 + TRY_CAST(substr(loan_id, 2, 2) AS INTEGER) <> vintage) AS VARCHAR),
           'near 0', CAST(NULL AS BOOLEAN)
    FROM loans
    GROUP BY vintage

    UNION ALL

    -- 4-7. Share of loans missing key fields, after missing-value codes became NULL. Info only.
    SELECT 4, 'Missing credit score (%)', vintage,
           CAST(round(100.0 * count(*) FILTER (WHERE fico IS NULL) / count(*), 2) AS VARCHAR),
           'info', CAST(NULL AS BOOLEAN)
    FROM loans
    GROUP BY vintage

    UNION ALL

    SELECT 5, 'Missing LTV (%)', vintage,
           CAST(round(100.0 * count(*) FILTER (WHERE ltv IS NULL) / count(*), 2) AS VARCHAR),
           'info', CAST(NULL AS BOOLEAN)
    FROM loans
    GROUP BY vintage

    UNION ALL

    SELECT 6, 'Missing DTI (%)', vintage,
           CAST(round(100.0 * count(*) FILTER (WHERE dti IS NULL) / count(*), 2) AS VARCHAR),
           'info', CAST(NULL AS BOOLEAN)
    FROM loans
    GROUP BY vintage

    UNION ALL

    SELECT 7, 'Missing interest rate (%)', vintage,
           CAST(round(100.0 * count(*) FILTER (WHERE orig_rate IS NULL) / count(*), 2) AS VARCHAR),
           'info', CAST(NULL AS BOOLEAN)
    FROM loans
    GROUP BY vintage

    UNION ALL

    -- 8. Values should sit inside Freddie Mac's documented ranges.
    SELECT 8, 'Loans with out-of-range values', vintage,
           CAST(count(*) FILTER (WHERE fico NOT BETWEEN 300 AND 850
                                    OR dti NOT BETWEEN 0 AND 65
                                    OR orig_rate <= 0
                                    OR orig_upb <= 0) AS VARCHAR),
           '0',
           count(*) FILTER (WHERE fico NOT BETWEEN 300 AND 850
                               OR dti NOT BETWEEN 0 AND 65
                               OR orig_rate <= 0
                               OR orig_upb <= 0) = 0
    FROM loans
    GROUP BY vintage

    UNION ALL

    -- 9. Every loan should have monthly records (anti-join: loans with no match).
    SELECT 9, 'Loans with no monthly records', CAST(NULL AS INTEGER),
           CAST(count(*) AS VARCHAR), '0', count(*) = 0
    FROM loans AS l
    LEFT JOIN (SELECT DISTINCT loan_id FROM loan_months) AS m ON l.loan_id = m.loan_id
    WHERE m.loan_id IS NULL

    UNION ALL

    -- 10. Every monthly record should belong to a loan.
    SELECT 10, 'Monthly records with no matching loan', CAST(NULL AS INTEGER),
           CAST(count(*) AS VARCHAR), '0', count(*) = 0
    FROM loan_months AS m
    LEFT JOIN loans AS l ON m.loan_id = l.loan_id
    WHERE l.loan_id IS NULL

    UNION ALL

    -- 11. One record per loan per month.
    SELECT 11, 'Duplicate loan-month records', CAST(NULL AS INTEGER),
           CAST(count(*) AS VARCHAR), '0', count(*) = 0
    FROM (SELECT loan_id, period FROM loan_months GROUP BY loan_id, period HAVING count(*) > 1) AS dup

    UNION ALL

    -- 12. Each loan's months should run without gaps (LAG compares each month with the one before;
    --     repeated months are caught by check 11).
    SELECT 12, 'Gaps between monthly records', CAST(NULL AS INTEGER),
           CAST(count(*) FILTER (WHERE date_diff('month', prev_period, period) > 1) AS VARCHAR),
           '0',
           count(*) FILTER (WHERE date_diff('month', prev_period, period) > 1) = 0
    FROM (
        SELECT loan_id, period,
               LAG(period) OVER (PARTITION BY loan_id ORDER BY period) AS prev_period
        FROM loan_months
    ) AS ordered

    UNION ALL

    -- 13. Delinquency status should be a number of months, RA (REO) or XX (not available).
    SELECT 13, 'Unexpected delinquency status codes', CAST(NULL AS INTEGER),
           CAST(count(*) FILTER (WHERE dpd_status IS NULL
                                    OR NOT (dpd_status IN ('RA', 'XX')
                                            OR regexp_matches(dpd_status, '^[0-9]+$'))) AS VARCHAR),
           '0',
           count(*) FILTER (WHERE dpd_status IS NULL
                               OR NOT (dpd_status IN ('RA', 'XX')
                                       OR regexp_matches(dpd_status, '^[0-9]+$'))) = 0
    FROM loan_months

    UNION ALL

    -- 14. Zero balance codes should be ones Freddie Mac documents.
    SELECT 14, 'Unexpected zero balance codes', CAST(NULL AS INTEGER),
           CAST(count(*) FILTER (WHERE zb_code NOT IN ('01', '02', '03', '09', '15', '16', '96')) AS VARCHAR),
           '0',
           count(*) FILTER (WHERE zb_code NOT IN ('01', '02', '03', '09', '15', '16', '96')) = 0
    FROM loan_months

    UNION ALL

    -- 15. A loan ends once: at most one zero-balance record per loan...
    SELECT 15, 'Loans with more than one zero-balance record', CAST(NULL AS INTEGER),
           CAST(count(*) AS VARCHAR), '0', count(*) = 0
    FROM (SELECT loan_id FROM loan_months WHERE zb_code IS NOT NULL GROUP BY loan_id HAVING count(*) > 1) AS multi

    UNION ALL

    -- 16. ...and no monthly records after it.
    SELECT 16, 'Monthly records after a loan ended', CAST(NULL AS INTEGER),
           CAST(count(*) AS VARCHAR), '0', count(*) = 0
    FROM loan_months AS m
    JOIN (
        SELECT loan_id, min(period) AS end_period
        FROM loan_months
        WHERE zb_code IS NOT NULL
        GROUP BY loan_id
    ) AS ended ON m.loan_id = ended.loan_id
    WHERE m.period > ended.end_period

    UNION ALL

    -- 17-18. Size and time span of each vintage. Info: these go in the README.
    SELECT 17, 'Monthly records', vintage,
           CAST(count(*) AS VARCHAR), 'info', CAST(NULL AS BOOLEAN)
    FROM loan_months
    GROUP BY vintage

    UNION ALL

    SELECT 18, 'Reporting months covered', vintage,
           CAST(min(period) AS VARCHAR) || ' to ' || CAST(max(period) AS VARCHAR),
           'info', CAST(NULL AS BOOLEAN)
    FROM loan_months
    GROUP BY vintage

    UNION ALL

    -- 19. A first look ahead to Phase 3: share of loans that ended in a credit event
    --     (third-party sale, short sale or charge-off, REO sale). Info only.
    SELECT 19, 'Loans ended by a credit event (%)', l.vintage,
           CAST(round(100.0 * count(*) FILTER (WHERE e.loan_id IS NOT NULL) / count(*), 2) AS VARCHAR),
           'info', CAST(NULL AS BOOLEAN)
    FROM loans AS l
    LEFT JOIN (
        SELECT DISTINCT loan_id FROM loan_months WHERE zb_code IN ('02', '03', '09')
    ) AS e ON l.loan_id = e.loan_id
    GROUP BY l.vintage

) AS checks
ORDER BY check_id, vintage;
