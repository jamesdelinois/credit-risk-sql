-- Phase 1, step 2: build the two typed tables every later phase uses.
--
--   loans        one row per loan  (from orig_raw)
--   loan_months  one row per loan per month  (from perf_raw)
--
-- Cleaning rules:
--   * Missing-value codes become NULL: 9999 for credit scores; 999 for LTV, CLTV, DTI,
--     MI % and ELTV; 99 for units, borrowers and property type; 9 for occupancy,
--     purpose, channel and first-time buyer; 7 for valuation method; 000 for ZIP.
--   * YYYYMM text becomes a DATE on the first day of that month.
--   * dpd = delinquency status as a number of months behind (00 -> 0, 01 -> 1, ...).
--     REO ('RA') and not available ('XX') become NULL in dpd; dpd_status keeps the code.
--   * vintage = the origination year, taken from the file name (sample_orig_2007.txt -> 2007).

-- Reusable helpers (DuckDB macros)
CREATE OR REPLACE MACRO blank_to_null(s) AS NULLIF(trim(s), '');

CREATE OR REPLACE MACRO yyyymm_to_date(s) AS
    CASE
        WHEN regexp_matches(trim(s), '^[0-9]{6}$')
        THEN make_date(CAST(substr(trim(s), 1, 4) AS INTEGER), CAST(substr(trim(s), 5, 2) AS INTEGER), 1)
    END;

CREATE OR REPLACE TABLE loans AS
SELECT
    trim(loan_id)                                                         AS loan_id,
    TRY_CAST(regexp_extract(filename, '([0-9]{4})\.txt$', 1) AS INTEGER)  AS vintage,
    NULLIF(TRY_CAST(trim(fico) AS INTEGER), 9999)                         AS fico,
    NULLIF(TRY_CAST(trim(vantage_score) AS INTEGER), 9999)                AS vantage_score,
    yyyymm_to_date(first_payment_date)                                    AS first_payment_date,
    yyyymm_to_date(maturity_date)                                         AS maturity_date,
    TRY_CAST(trim(orig_upb) AS DOUBLE)                                    AS orig_upb,
    TRY_CAST(trim(orig_rate) AS DOUBLE)                                   AS orig_rate,
    TRY_CAST(trim(orig_term) AS INTEGER)                                  AS orig_term,
    NULLIF(TRY_CAST(trim(ltv) AS INTEGER), 999)                           AS ltv,
    NULLIF(TRY_CAST(trim(cltv) AS INTEGER), 999)                          AS cltv,
    NULLIF(TRY_CAST(trim(dti) AS INTEGER), 999)                           AS dti,
    NULLIF(TRY_CAST(trim(mi_pct) AS INTEGER), 999)                        AS mi_pct,
    NULLIF(TRY_CAST(trim(units) AS INTEGER), 99)                          AS units,
    NULLIF(TRY_CAST(trim(n_borrowers) AS INTEGER), 99)                    AS n_borrowers,
    NULLIF(blank_to_null(occupancy), '9')                                 AS occupancy,
    NULLIF(blank_to_null(purpose), '9')                                   AS purpose,
    NULLIF(blank_to_null(channel), '9')                                   AS channel,
    NULLIF(blank_to_null(first_time_buyer), '9')                          AS first_time_buyer,
    NULLIF(blank_to_null(property_type), '99')                            AS property_type,
    NULLIF(blank_to_null(valuation_method), '7')                          AS valuation_method,
    NULLIF(substr(blank_to_null(zip3), 1, 3), '000')                      AS zip3,
    blank_to_null(state)                                                  AS state,
    blank_to_null(msa)                                                    AS msa,
    blank_to_null(amortization_type)                                      AS amortization_type,
    blank_to_null(ppm_flag)                                               AS ppm_flag,
    blank_to_null(interest_only)                                          AS interest_only,
    blank_to_null(super_conforming)                                       AS super_conforming,
    blank_to_null(harp_flag)                                              AS harp_flag,
    blank_to_null(special_program)                                        AS special_program,
    blank_to_null(seller)                                                 AS seller
FROM orig_raw;

CREATE OR REPLACE TABLE loan_months AS
SELECT
    trim(loan_id)                                                         AS loan_id,
    TRY_CAST(regexp_extract(filename, '([0-9]{4})\.txt$', 1) AS INTEGER)  AS vintage,
    yyyymm_to_date(period)                                                AS period,
    TRY_CAST(trim(loan_age) AS INTEGER)                                   AS age,
    TRY_CAST(trim(months_to_maturity) AS INTEGER)                         AS months_to_maturity,
    TRY_CAST(trim(current_upb) AS DOUBLE)                                 AS current_upb,
    upper(blank_to_null(dpd_status))                                      AS dpd_status,
    TRY_CAST(trim(dpd_status) AS INTEGER)                                 AS dpd,
    CASE
        WHEN blank_to_null(zb_code) IS NOT NULL THEN lpad(trim(zb_code), 2, '0')
    END                                                                   AS zb_code,
    yyyymm_to_date(zb_date)                                               AS zb_date,
    TRY_CAST(trim(current_rate) AS DOUBLE)                                AS current_rate,
    blank_to_null(mod_flag)                                               AS mod_flag,
    blank_to_null(payment_deferral)                                       AS payment_deferral,
    blank_to_null(disaster_flag)                                          AS disaster_flag,
    blank_to_null(assistance_plan)                                        AS assistance_plan,
    NULLIF(TRY_CAST(trim(eltv) AS INTEGER), 999)                          AS eltv,
    yyyymm_to_date(ddlpi)                                                 AS last_paid_due_date,
    TRY_CAST(trim(zb_removal_upb) AS DOUBLE)                              AS zb_removal_upb,
    TRY_CAST(trim(mi_recoveries) AS DOUBLE)                               AS mi_recoveries,
    TRY_CAST(trim(net_sales_proceeds) AS DOUBLE)                          AS net_sales_proceeds,
    TRY_CAST(trim(non_mi_recoveries) AS DOUBLE)                           AS non_mi_recoveries,
    TRY_CAST(trim(total_expenses) AS DOUBLE)                              AS total_expenses,
    TRY_CAST(trim(actual_loss) AS DOUBLE)                                 AS actual_loss,
    TRY_CAST(trim(delinquent_interest) AS DOUBLE)                         AS delinquent_interest
FROM perf_raw;
