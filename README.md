# Credit Risk Analytics in SQL

A SQL analysis of 200,000 Freddie Mac mortgages and their 12.7 million monthly payment records: which loans default, how fast, and what it costs. Built with DuckDB and Python.

**Status:** Phase 1 (load and validate) complete. Phase 2 (portfolio overview) next.

## Questions

1. How different was the credit mix of each origination year (vintage)?
2. How fast did each vintage default, and how did 2006–2007 loans compare with 2012 and 2019 loans?
3. Once a loan falls behind, how often does it recover or get worse?
4. Which borrower characteristics drive defaults, and what would tighter lending rules have cost and saved?
5. When loans default, how much is lost?

## Data

[Freddie Mac Single-Family Loan-Level Dataset](https://freddiemac.com/research/datasets/sf-loanlevel-dataset), sample files: a simple random sample of 50,000 loans per origination year. Release: [TODO: release number and date from the download page], with monthly performance through June 2026. Downloaded [TODO: date].

| Vintage | Why it's included |
| --- | --- |
| 2006 | Crisis-era lending |
| 2007 | The other crisis vintage, so two bad years can be compared |
| 2012 | Loans made after lending standards tightened |
| 2019 | Tight standards, then hit by COVID; the data flags forbearance and payment deferrals |

Each vintage has two pipe-delimited files with no header row:

| File | One row per | Fields |
| --- | --- | --- |
| `sample_orig_YYYY.txt` | loan | 31 (credit score, LTV, DTI, rate, state, ...) |
| `sample_perf_YYYY.txt` | loan per month | 35 (balance, delinquency status, payoff code, losses, ...) |

The data is free for non-commercial use after registering with Freddie Mac's Clarity Data Intelligence. Raw files are **not** included in this repository; only aggregated results are committed.

## Setup

```bash
conda create -n creditrisk python=3.11
conda activate creditrisk
pip install -r requirements.txt
```

## How to run

1. Download `sample_2006.zip`, `sample_2007.zip`, `sample_2012.zip`, and `sample_2019.zip`, and extract the `.txt` files directly into `data/raw/` (not into subfolders).
2. Optional setup check on made-up data: `python scripts/run_sql.py --selftest`
3. Run everything: `python scripts/run_sql.py` (or only some files, e.g. `python scripts/run_sql.py 03`)

Close any notebook connected to the database before running the script: DuckDB allows only one program to write to it at a time.

## Project structure

```
credit-risk-sql/
├── data/raw/            Freddie Mac files (not committed)
├── sql/
│   ├── 01_load.sql      views over the raw files, every column named
│   ├── 02_clean.sql     typed tables: loans, loan_months
│   └── 03_validate.sql  data-quality checks -> data_quality
├── scripts/run_sql.py   runs the SQL in order, saves summary tables to outputs/
├── outputs/             summary tables (CSV)
├── notebooks/           SQL exploration (Phase 1); charts (from Phase 2)
└── figures/
```

## Phases

- [x] **Phase 1: Load and validate** (typed tables, data-quality checks)
- [ ] Phase 2: Portfolio overview
- [ ] Phase 3: Delinquency and vintage curves
- [ ] Phase 4: Roll rates
- [ ] Phase 5: Risk segments, policy what-if, and review sample
- [ ] Phase 6: Loss severity and reporting

## Cleaning rules

- Missing-value codes become NULL: 9999 for credit scores; 999 for LTV, CLTV, DTI, MI %, and estimated LTV; 99 for units, borrowers, and property type; 9 for occupancy, purpose, channel, and first-time buyer.
- `YYYYMM` fields become dates (first day of the month).
- `dpd` is the delinquency status as months behind (00 → 0, 01 → 1, …); REO (`RA`) and not available (`XX`) are NULL in `dpd` and kept in `dpd_status`.
- `vintage` is the origination year, taken from the file name.

## Phase 1: Data quality

`sql/03_validate.sql` runs 19 checks and saves them to [`outputs/data_quality.csv`](outputs/data_quality.csv).

**Structural checks: all passed.**

| Check | Result |
| --- | --- |
| Loans per vintage | 50,000 in each |
| Duplicate loan IDs | 0 |
| Loans with out-of-range values | 0 |
| Loans with no monthly records | 0 |
| Monthly records with no matching loan | 0 |
| Duplicate loan-month records | 0 |
| Unexpected delinquency or zero-balance codes | 0 |
| Loans with more than one zero-balance record | 0 |
| Monthly records after a loan ended | 0 |
| Gaps between monthly records | 62 (informational; see below) |

**Coverage by vintage:**

| | 2006 | 2007 | 2012 | 2019 |
| --- | --- | --- | --- | --- |
| Monthly records | 3,206,738 | 3,015,985 | 4,538,907 | 1,977,122 |
| Missing credit score | 0.09% | 0.08% | 0.00% | 0.04% |
| Missing LTV | 0.02% | 0.00% | 0.01% | 0.00% |
| Missing DTI | 2.14% | 2.25% | **34.8%** | 0.06% |
| Reporting months | Jan 2006 – Jun 2026 | Dec 2006 – Jun 2026 | Jan 2012 – Jun 2026 | Jan 2019 – Jun 2026 |
| Ended in a foreclosure sale or short sale (codes 02, 03, 09) | 7.67% | 8.53% | 0.68% | 0.08% |

No interest rates are missing in any vintage.

### What the checks found

**1. A third of 2012 loans have no DTI, because of a refinance program.** All of the missing DTIs are refinances:

| 2012 loans | Loans | Missing DTI |
| --- | --- | --- |
| Purchases | 8,489 | 0% |
| Cash-out refinances, LTV 80% or below | 7,499 | 0% |
| No-cash-out refinances, LTV 80% or below | 21,260 | 29.5% |
| No-cash-out refinances, LTV above 80% | 12,744 | 87.2% |

Freddie Mac withholds DTI for every HARP loan (a Relief Refinance loan with LTV above 80%), and 2012 was one of HARP's busiest years. The 29.5% at lower LTVs most likely reflects the same treatment of the program's other loans; Phase 5 will confirm this with the Relief Refinance indicator. HARP ended in 2018, which is why 2019 has almost no missing DTI. **Effect:** DTI averages for 2012 describe only the two-thirds of loans that aren't relief refinances, so later tables show how many loans each DTI figure covers, and Phase 5 treats relief refinances as their own segment.

**2. 62 loans have a gap in their monthly records.** Each of the 62 loans has a single gap, and all of them are from 2006 (32) or 2007 (30). Gaps last a median of 5 months (range 2 to 57), and 54 of the 62 end between 2008 and 2014. In 58 cases the loan was already at least 6 months behind when the gap began, and in 51 of those, the delinquency after the gap equals the delinquency before it plus the months missed: the borrower simply kept not paying through months that weren't reported. **Handling:** the records are left as reported, with no filled-in months. Default timing is affected for at most 2 loans (current before a gap and 90+ days late after it). Roll-rate transitions in Phase 4 are counted only between records exactly one month apart.

**3. Forbearance codes are available for the COVID period.** Assistance-plan codes (F = forbearance, R = repayment plan, T = trial period) appear from January 2014 onward. 2019 loans have 28,291 loan-months in forbearance, three times as many as 2012 loans (9,419), even though they have fewer than half as many monthly records. Loans in forbearance are reported as delinquent when payments stop, so Phase 3 reports 2019's default rate both with and without forbearance months.

**4. A first look at the main result.** 7.7% of 2006 loans and 8.5% of 2007 loans ended in a foreclosure sale or short sale, compared with 0.7% of 2012 loans: more than 11 times as many. Phase 3 measures default more fully, including loans that went 90+ days late and later recovered.

## Sources

- [Freddie Mac: Single-Family Loan-Level Dataset](https://freddiemac.com/research/datasets/sf-loanlevel-dataset)
- [Freddie Mac: General User Guide, July 2026](https://www.freddiemac.com/fmac-resources/research/pdf/general_user_guide_july_2026.pdf)
- [Freddie Mac: Mortgage Forbearance and Performance during the Early Months of the COVID-19 Pandemic](https://www.freddiemac.com/research/insight/20210208-mortgage-forbearance-rate-during-COVID-19)
