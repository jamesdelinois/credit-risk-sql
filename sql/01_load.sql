-- Phase 1, step 1: point DuckDB at the raw Freddie Mac sample files.
--
-- The files are pipe-delimited with no header row, so every column is named here in the
-- order of Freddie Mac's file layout (July 2026): 31 origination fields, 35 performance fields.
-- Every column is read as text; 02_clean.sql converts the types and missing-value codes.
--
-- These are views, not tables: nothing is copied, and DuckDB reads the files whenever a
-- query uses them. filename = true adds a column with each row's source file, which is
-- how 02_clean.sql gets each loan's vintage (origination year).

CREATE OR REPLACE VIEW orig_raw AS
SELECT *
FROM read_csv(
    'data/raw/sample_orig_*.txt',
    delim = '|',
    header = false,
    filename = true,
    columns = {
        'fico': 'VARCHAR',                 -- 1  credit score at origination (9999 = missing)
        'first_payment_date': 'VARCHAR',   -- 2  YYYYMM
        'first_time_buyer': 'VARCHAR',     -- 3  Y, N, 9 = missing
        'maturity_date': 'VARCHAR',        -- 4  YYYYMM
        'msa': 'VARCHAR',                  -- 5  metro area code
        'mi_pct': 'VARCHAR',               -- 6  mortgage insurance % (999 = missing)
        'units': 'VARCHAR',                -- 7  1-4 (99 = missing)
        'occupancy': 'VARCHAR',            -- 8  P primary, I investment, S second home, 9 = missing
        'cltv': 'VARCHAR',                 -- 9  combined loan-to-value (999 = missing)
        'dti': 'VARCHAR',                  -- 10 debt-to-income (999 = missing)
        'orig_upb': 'VARCHAR',             -- 11 original balance, nearest $1,000
        'ltv': 'VARCHAR',                  -- 12 loan-to-value (999 = missing)
        'orig_rate': 'VARCHAR',            -- 13 interest rate on the note
        'channel': 'VARCHAR',              -- 14 R retail, B broker, C correspondent, T other, 9 = missing
        'ppm_flag': 'VARCHAR',             -- 15 prepayment penalty, Y/N
        'amortization_type': 'VARCHAR',    -- 16 FRM or ARM
        'state': 'VARCHAR',                -- 17 two-letter state
        'property_type': 'VARCHAR',        -- 18 SF, PU, CO, CP, MH, 99 = missing
        'zip3': 'VARCHAR',                 -- 19 first three digits of ZIP (000 = unknown)
        'loan_id': 'VARCHAR',              -- 20 loan identifier, e.g. F07Q1XXXXXXX
        'purpose': 'VARCHAR',              -- 21 P purchase, C cash-out refi, N no-cash-out refi, R refi, 9 = missing
        'orig_term': 'VARCHAR',            -- 22 term in months
        'n_borrowers': 'VARCHAR',          -- 23 number of borrowers (99 = missing)
        'seller': 'VARCHAR',               -- 24 seller name
        'super_conforming': 'VARCHAR',     -- 25 Y/N
        'pre_harp_loan_id': 'VARCHAR',     -- 26 earlier loan ID for HARP refinances
        'special_program': 'VARCHAR',      -- 27 H, F, R, or blank
        'harp_flag': 'VARCHAR',            -- 28 Y/N
        'valuation_method': 'VARCHAR',     -- 29 1-4, 7 = missing
        'interest_only': 'VARCHAR',        -- 30 Y/N
        'vantage_score': 'VARCHAR'         -- 31 VantageScore 4.0 (9999 = missing)
    }
);

CREATE OR REPLACE VIEW perf_raw AS
SELECT *
FROM read_csv(
    'data/raw/sample_perf_*.txt',
    delim = '|',
    header = false,
    filename = true,
    columns = {
        'loan_id': 'VARCHAR',                -- 1  loan identifier
        'period': 'VARCHAR',                 -- 2  reporting month, YYYYMM
        'current_upb': 'VARCHAR',            -- 3  current balance
        'dpd_status': 'VARCHAR',             -- 4  00 current, 01 30-59 days, 02 60-89, 03 90-119 ..., RA REO, XX unknown
        'loan_age': 'VARCHAR',               -- 5  months since origination
        'months_to_maturity': 'VARCHAR',     -- 6  remaining months
        'defect_settlement_date': 'VARCHAR', -- 7  YYYYMM
        'mod_flag': 'VARCHAR',               -- 8  Y this month, P earlier, blank = never modified
        'zb_code': 'VARCHAR',                -- 9  how the loan ended: 01 paid off, 02/03/09 credit events, 15, 16, 96
        'zb_date': 'VARCHAR',                -- 10 YYYYMM the balance reached zero
        'current_rate': 'VARCHAR',           -- 11 current interest rate
        'non_interest_upb': 'VARCHAR',       -- 12 non-interest-bearing balance
        'ddlpi': 'VARCHAR',                  -- 13 due date of last paid installment, YYYYMM
        'mi_recoveries': 'VARCHAR',          -- 14 negative = recovery
        'net_sales_proceeds': 'VARCHAR',     -- 15 sale proceeds
        'non_mi_recoveries': 'VARCHAR',      -- 16 negative = recovery
        'total_expenses': 'VARCHAR',         -- 17
        'legal_costs': 'VARCHAR',            -- 18
        'maintenance_costs': 'VARCHAR',      -- 19
        'taxes_insurance': 'VARCHAR',        -- 20
        'misc_expenses': 'VARCHAR',          -- 21
        'actual_loss': 'VARCHAR',            -- 22 positive = loss
        'cum_mod_cost': 'VARCHAR',           -- 23 cumulative modification cost
        'step_rate_flag': 'VARCHAR',         -- 24 Y/N
        'payment_deferral': 'VARCHAR',       -- 25 C current, P prior
        'eltv': 'VARCHAR',                   -- 26 estimated current LTV (999 = missing)
        'zb_removal_upb': 'VARCHAR',         -- 27 balance when the loan was removed
        'delinquent_interest': 'VARCHAR',    -- 28 delinquent accrued interest
        'disaster_flag': 'VARCHAR',          -- 29 Y = delinquency due to a disaster
        'assistance_plan': 'VARCHAR',        -- 30 F, R, T, or blank
        'current_mod_cost': 'VARCHAR',       -- 31 this month's modification cost
        'interest_upb': 'VARCHAR',           -- 32 interest-bearing balance
        'mi_cancel_flag': 'VARCHAR',         -- 33 Y, N, 7 = n/a
        'servicer': 'VARCHAR',               -- 34 servicer name
        'cramdown_costs': 'VARCHAR'          -- 35 bankruptcy cramdown costs
    }
);
