"""Run the project's SQL files, in order, against a local DuckDB database.

Usage, from the repository root:
    python scripts/run_sql.py              run every file in sql/
    python scripts/run_sql.py 02 03        run only the files whose names start with 02 or 03
    python scripts/run_sql.py --selftest   run the SQL on small made-up files to check your setup

Tables are stored in data/credit_risk.duckdb (not committed). Summary tables listed in
EXPORTS are also saved as CSV files in outputs/ (committed: aggregates only, never loan rows).
"""
import os
import random
import shutil
import sys
import time
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / "sql"

# Raw files and the number of pipe-separated fields each should have (Freddie Mac, July 2026 layout)
RAW_FILES = {"sample_orig_*.txt": 31, "sample_perf_*.txt": 35}

# Summary tables saved to outputs/ after every run
EXPORTS = {"data_quality": "data_quality.csv"}


def sql_statements(text):
    """Split a .sql file into statements: drop -- comments, then split on semicolons."""
    lines = [line.split("--", 1)[0] for line in text.splitlines()]
    return [s.strip() for s in "\n".join(lines).split(";") if s.strip()]


def check_raw_files(raw_dir):
    """Confirm the raw files are in place and have the expected number of fields."""
    ok = True
    print(f"Raw files in {raw_dir}:")
    for pattern, n_fields in RAW_FILES.items():
        files = sorted(raw_dir.glob(pattern))
        if not files:
            ok = False
            print(f"  No files matching {pattern}.")
            nested = sorted(raw_dir.rglob(pattern))
            if nested:
                print(f"  They're in a subfolder ({nested[0].relative_to(raw_dir)}): "
                      "move the .txt files directly into data/raw/.")
            elif pattern.startswith("sample_perf") and list(raw_dir.glob("sample_svcg_*.txt")):
                print("  Found sample_svcg_*.txt instead (an older file name): rename them to sample_perf_*.txt.")
            elif list(raw_dir.glob("*.zip")):
                print("  Found .zip files: extract the .txt files inside them into data/raw/.")
            continue
        for f in files:
            with open(f, encoding="utf-8", errors="replace") as fh:
                first_line = fh.readline().rstrip("\r\n")
            found = first_line.count("|") + 1
            flag = "ok" if found == n_fields else f"expected {n_fields} fields"
            print(f"  {f.name:<26}{f.stat().st_size / 1e6:9.1f} MB {found:4d} fields  {flag}")
            if found != n_fields:
                ok = False
    if not ok:
        print("\nFix the raw files above, then run again. If the field counts differ, Freddie Mac may\n"
              "have changed its file layout: compare with the file layout on the dataset page.")
    return ok


def run(work_dir, prefixes=()):
    """Run the SQL files with work_dir as the current folder (the SQL uses relative paths)."""
    os.chdir(work_dir)
    (work_dir / "data").mkdir(exist_ok=True)
    out_dir = work_dir / "outputs"
    out_dir.mkdir(exist_ok=True)

    sql_files = sorted(SQL_DIR.glob("*.sql"))
    if prefixes:
        sql_files = [f for f in sql_files if f.name.startswith(tuple(prefixes))]

    con = duckdb.connect(str(work_dir / "data" / "credit_risk.duckdb"))
    print(f"\nRunning SQL (DuckDB {duckdb.__version__}):")
    for sql_file in sql_files:
        start = time.time()
        for i, statement in enumerate(sql_statements(sql_file.read_text(encoding="utf-8")), 1):
            try:
                con.execute(statement)
            except Exception as err:
                print(f"\nError in {sql_file.name}, statement {i}:\n\n{statement[:400]}\n\n{err}")
                con.close()
                sys.exit(1)
        print(f"  {sql_file.name:<26}{time.time() - start:7.1f} s")

    for table, csv_name in EXPORTS.items():
        try:
            df = con.sql(f"SELECT * FROM {table}").df()
        except Exception:
            continue  # table not built yet
        df.convert_dtypes().to_csv(out_dir / csv_name, index=False)   # keeps whole numbers as 2007, not 2007.0
        print(f"  saved {table} to {(out_dir / csv_name).relative_to(work_dir)}")

    try:
        dq = con.sql("""
            SELECT check_id AS id, check_name AS "check",
                   coalesce(CAST(vintage AS VARCHAR), '') AS vintage, result, expected,
                   CASE WHEN passed THEN 'pass' WHEN NOT passed THEN 'FAIL' ELSE '' END AS status
            FROM data_quality
            ORDER BY data_quality.check_id, data_quality.vintage
        """).df()
        failed = dq[dq["status"] == "FAIL"]
    except Exception:
        dq = None
    if dq is not None:
        print("\nData-quality checks:\n")
        print(dq.to_string(index=False))
        if len(failed):
            print(f"\n{len(failed)} check(s) failed: " + "; ".join(
                f"{r['check']} {r['vintage']}".strip() for _, r in failed.iterrows()))
        else:
            print("\nAll pass/fail checks passed.")
    con.close()


def make_selftest_files(raw_dir, n_loans=200, seed=0):
    """Write small made-up files in Freddie Mac's format (two vintages) for a setup check."""
    rng = random.Random(seed)
    raw_dir.mkdir(parents=True, exist_ok=True)
    for vintage in (2007, 2019):
        orig_lines, perf_lines = [], []
        for i in range(n_loans):
            loan_id = f"F{vintage % 100:02d}Q{rng.randint(1, 4)}{i:07d}"
            year, month = vintage, rng.randint(2, 12)
            first_pay = f"{year}{month:02d}"
            upb = rng.choice([150000, 220000, 310000, 425000])
            orig = [
                rng.choice(["9999", "615", "680", "735", "790"]),  # credit score, sometimes missing
                first_pay, rng.choice(["Y", "N", "9"]), f"{year + 30}{month:02d}", "37980",
                rng.choice(["0", "25", "999"]), "1", rng.choice(["P", "I", "S"]),
                str(rng.randint(60, 97)), rng.choice(["28", "36", "44", "999"]), str(upb),
                str(rng.randint(60, 97)), f"{rng.uniform(3, 7):.3f}", rng.choice(["R", "B", "C"]),
                "N", "FRM", rng.choice(["DE", "PA", "NJ"]), "SF", "198", loan_id,
                rng.choice(["P", "C", "N"]), "360", "2", "OTHER", "N", "", "", "N", "2", "N",
                rng.choice(["9999", "701", "766"]),
            ]
            orig_lines.append("|".join(orig))

            n_months = rng.randint(6, 48)
            ending = rng.choice(["01", "01", "03", "09", ""])  # "" = still active
            dpd = 0
            for age in range(n_months):
                m = month - 1 + age
                period = f"{year + m // 12}{m % 12 + 1:02d}"
                last = age == n_months - 1
                if ending in ("03", "09") and age > n_months - 6:
                    dpd += 1                      # credit-event loans fall behind before they end
                elif rng.random() < 0.08:
                    dpd = min(dpd + 1, 3)
                elif rng.random() < 0.5:
                    dpd = 0
                status = "RA" if (last and ending == "09") else f"{dpd:02d}"
                zb = ending if last else ""
                perf = [""] * 35
                perf[0], perf[1], perf[2], perf[3] = loan_id, period, f"{upb * (1 - age / 400):.2f}", status
                perf[4], perf[5], perf[10] = str(age), str(360 - age), orig[12]
                if zb:
                    perf[8], perf[9], perf[26] = zb, period, f"{upb * 0.9:.2f}"
                    if zb in ("03", "09"):
                        perf[21] = f"{upb * rng.uniform(0.1, 0.4):.2f}"   # actual loss
                perf[25] = rng.choice(["999", "72", "88"])
                perf[32], perf[33] = "7", "OTHER"
                perf_lines.append("|".join(perf))
        (raw_dir / f"sample_orig_{vintage}.txt").write_text("\n".join(orig_lines) + "\n")
        (raw_dir / f"sample_perf_{vintage}.txt").write_text("\n".join(perf_lines) + "\n")


def main():
    args = sys.argv[1:]
    if "--selftest" in args:
        work_dir = ROOT / "data" / "selftest"
        shutil.rmtree(work_dir, ignore_errors=True)
        make_selftest_files(work_dir / "data" / "raw")
        print("Self-test: made-up files with 200 loans per vintage (2007 and 2019).\n")
        check_raw_files(work_dir / "data" / "raw")
        run(work_dir)
        print("\nSelf-test finished: every SQL file ran. 'Loans per vintage' fails on purpose here\n"
              "(the test files hold 200 loans, not 50,000). Delete data/selftest/ whenever you like.")
        return
    if not check_raw_files(ROOT / "data" / "raw"):
        sys.exit(1)
    run(ROOT, prefixes=args)


if __name__ == "__main__":
    main()
