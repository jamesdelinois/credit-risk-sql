# Credit Risk Analytics in SQL

A SQL analysis of 200,000 Freddie Mac mortgages and their monthly payment histories: which loans default, how fast, and what it costs. Built with DuckDB and Python.

**Status:** Phase 1 (load and validate) in progress.

## Questions

1. How different was the credit mix of each origination year (vintage)?
2. How fast did each vintage default, and how did 2006–2007 loans compare with 2012 and 2019 loans?
3. Once a loan falls behind, how often does it recover or get worse?
4. Which borrower characteristics drive defaults, and what would tighter lending rules have cost and saved?
5. When loans default, how much is lost?

## Data

[Freddie Mac Single-Family Loan-Level Dataset](https://freddiemac.com/research/datasets/sf-loanlevel-dataset), sample files: a simple random sample of 50,000 loans per origination year. This project uses the 2006, 2007, 2012, and 2019 vintages.

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

1. Download `sample_2006.zip`, `sample_2007.zip`, `sample_2012.zip`, and `sample_2019.zip`, and extract the `.txt` files into `data/raw/`.
2. Optional setup check on made-up data: `python scripts/run_sql.py --selftest`
3. Run everything: `python scripts/run_sql.py` (or only some files, e.g. `python scripts/run_sql.py 03`)

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
├── notebooks/           charts (from Phase 2)
└── figures/
```

## Phases

- [ ] **Phase 1: Load and validate** (typed tables, data-quality checks)
- [ ] Phase 2: Portfolio overview
- [ ] Phase 3: Delinquency and vintage curves
- [ ] Phase 4: Roll rates
- [ ] Phase 5: Risk segments, policy what-if, and review sample
- [ ] Phase 6: Loss severity and reporting

## Phase 1: Data quality

_Results go here after the first full run (from `outputs/data_quality.csv`)._

## Cleaning rules

- Missing-value codes become NULL: 9999 for credit scores; 999 for LTV, CLTV, DTI, MI %, and estimated LTV; 99 for units, borrowers, and property type; 9 for occupancy, purpose, channel, and first-time buyer.
- `YYYYMM` fields become dates (first day of the month).
- `dpd` is the delinquency status as months behind (00 → 0, 01 → 1, …); REO (`RA`) and not available (`XX`) are NULL in `dpd` and kept in `dpd_status`.
- `vintage` is the origination year, taken from the file name.

## Sources

- [Freddie Mac: Single-Family Loan-Level Dataset](https://freddiemac.com/research/datasets/sf-loanlevel-dataset)
- [Freddie Mac: General User Guide, July 2026](https://www.freddiemac.com/fmac-resources/research/pdf/general_user_guide_july_2026.pdf)
