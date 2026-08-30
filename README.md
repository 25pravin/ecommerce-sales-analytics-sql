# Olist E-Commerce Sales Analytics

SQL-driven analysis of **96,470 delivered orders** and **R$15.4M in revenue** from the Olist Brazilian e-commerce marketplace, spanning **Sept 2016 – Aug 2018** (23 months / ~2 years) of transaction history. Built end-to-end with SQLite, pandas, and 19 analytical SQL queries covering revenue trends, customer retention, delivery performance, and seller concentration — presented as an interactive dashboard.

**[▶ View Interactive Dashboard](https://25pravin.github.io/ecommerce-sales-analytics-sql/Dashboard.html)** | **[View all 19 SQL queries](https://25pravin.github.io/ecommerce-sales-analytics-sql/sql_queriesnb.html)**

---

## 1. Project Overview

This project turns Olist's raw relational e-commerce data (8 CSV tables) into a governed SQL data model and a set of 19 production-style analytical queries, answering concrete business questions about revenue, retention, delivery, and seller risk. Everything runs on a single self-contained SQLite database (`olist.db`) built from the source CSVs with pandas, queried with SQL (window functions, CTEs, views, correlated subqueries), and visualized in a static HTML/Chart.js dashboard — no external services, no build step.

The goal was to go beyond `SELECT * ... GROUP BY` and demonstrate the kind of SQL an analytics/BI role actually uses day to day: reusable views as a single source of truth, indexed and query-plan-verified performance, deduplication of messy source data, and statistical validation (Pearson correlation) of a business hypothesis.

## 2. Business Objective

Olist is a marketplace connecting small Brazilian sellers to major retail channels. Marketplaces succeed or fail on three levers: **how much revenue is flowing through the platform, how well customers are retained, and how reliably orders are delivered** (since delivery experience directly drives repeat purchase and seller reputation). The analysis was scoped around three business questions:

1. **Revenue & growth** — How is revenue trending month over month, and where is it concentrated (geography, customers, sellers)?
2. **Retention** — How many customers come back, how much revenue do repeat customers drive, and how long is the window before a customer's second purchase?
3. **Delivery & satisfaction** — Does delivery speed actually affect customer satisfaction (review scores), and how reliable is on-time delivery across the platform?

The findings are meant to point directly at business actions — a retention campaign, a delivery SLA review, a seller-concentration risk check — rather than being descriptive statistics for their own sake.

## 3. Dataset & Engineering

**Source:** [Olist Brazilian E-Commerce Public Dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle) — 8 relational CSV tables covering orders, order items, payments, reviews, customers, sellers, and geolocation (not included in this repo; download from Kaggle and run the loader to reproduce `olist.db` locally).

### 3.1 Loading

Each CSV is read with pandas, column names are stripped of stray whitespace, and each table is written into a fresh SQLite database (`olist.db`) via `to_sql(..., if_exists='replace')`:

| Table | Rows | Columns |
|---|---|---|
| `customers` | 99,441 | 5 |
| `geolocation` | 1,000,163 | 5 |
| `order_items` | 112,650 | 7 |
| `order_payments` | 103,886 | 5 |
| `order_reviews` | 99,224 | 7 |
| `orders` | 99,441 | 8 |
| `sellers` | 3,095 | 4 |
| `category_translation` | 71 | 2 |

### 3.2 Data cleaning & the modeling layer

Three SQL `VIEW`s were built to turn raw, messy relational tables into one clean, analysis-ready fact table:

**`clean_order_reviews`** — deduplicates review records. Some orders in the raw data have multiple review rows (e.g. late-arriving updates); this view keeps only the most recent review per order using `ROW_NUMBER()` partitioned by `order_id`, ordered by `review_answer_timestamp DESC`, keeping `rn = 1`.

**`order_revenue`** — aggregates `order_items` up to the order grain: `SUM(price)` as items revenue, `SUM(freight_value)` as freight revenue, and their sum as `total_revenue`, plus an `item_count`.

**`fact_orders`** — the single source of truth for all downstream queries. Joins `orders` → `customers` → `order_revenue` → `clean_order_reviews`, filters to `order_status = 'delivered'` with a non-null delivery date, and derives two calculated fields:
- `delivery_days = JULIANDAY(order_delivered_customer_date) − JULIANDAY(order_purchase_timestamp)`
- `delivery_buffer_days = JULIANDAY(order_estimated_delivery_date) − JULIANDAY(order_delivered_customer_date)`

This filter (delivered orders only, with a real delivery date) is what brings the raw 99,441 `orders` rows down to the **96,470-row analytical base** used throughout the project.

### 3.3 Performance

Indexes were added on the join/filter columns used across queries (`orders.customer_id`, `order_items.order_id`, `order_items.seller_id`, `order_payments.order_id`), and verified with `EXPLAIN QUERY PLAN` to confirm SQLite was using them (e.g. `SEARCH orders USING INDEX idx_orders_customer_id` instead of a full table scan).

## 4. Workflow

```
Kaggle CSVs
   │  pandas.read_csv + column cleanup
   ▼
olist.db (SQLite)  ── raw tables: customers, orders, order_items,
   │                   order_payments, order_reviews, sellers,
   │                   geolocation, category_translation
   │  SQL: ROW_NUMBER() dedup + joins
   ▼
Cleaning views  ──  clean_order_reviews → order_revenue → fact_orders
   │  SQL: 19 analytical queries (window functions, CTEs,
   │        correlated subqueries, views, indexing)
   ▼
Query results (pandas DataFrames)
   │  Pearson correlation (pandas) for the delivery↔review hypothesis
   ▼
dashboard/index.html  ──  static HTML + Chart.js, self-contained,
                           reads the computed KPIs, no server needed
```

Each of the 19 queries is independent and runs standalone against `fact_orders` (plus `order_items`, `order_payments`, and `sellers` where a query needs data below the order grain), so any query can be re-run or modified in isolation without rebuilding the pipeline.

## 5. The 19 SQL Queries — What Each Calculates and the Formula Behind It

### Revenue & Growth

**Q1 — Headline KPIs.**
Total revenue, total orders, total customers, and average order value in one row.
`AOV = SUM(total_revenue) / COUNT(DISTINCT order_id)`
→ **R$15,418,394.83 revenue · 96,470 orders · 93,350 customers · R$159.83 AOV**

**Q2 — Monthly revenue trend.**
Revenue and order count grouped by `strftime('%Y-%m', order_purchase_timestamp)`.
→ Revenue grows from R$143 in Sept 2016 to a peak of ~R$1.15M in Nov 2017 (Black Friday effect), then stabilizes around R$1.0–1.13M/month through mid-2018.

**Q8 — Month-over-month growth rate.**
Uses `LAG()` to pull the prior month's revenue alongside the current one, then computes both the absolute and percentage change:
`MoM % = 100 × (revenue − LAG(revenue)) / LAG(revenue)`
→ Growth is volatile in the early low-volume months, then settles into single-digit swings (roughly −13% to +16%) from late 2017 onward as the base matures.

**Q9 — Cumulative revenue growth trajectory.**
A running total using a window `SUM(SUM(total_revenue)) OVER (ORDER BY month)` — a sum-of-a-sum, since the monthly total itself is already an aggregate.
→ Cumulative revenue reaches the full **R$15.4M** by Aug 2018, growing in a steady, accelerating curve after the platform's ramp-up period.

**Q10 — 3-month moving average.**
Smooths month-to-month noise: `AVG(revenue) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)`.
→ Confirms the underlying trend is a steady climb to roughly R$1.0–1.1M/month, without the noise of individual monthly spikes/dips.

### Customer Retention

**Q3 — Repeat customer rate.**
The percentage of unique customers who placed more than one order:
`Repeat Rate % = 100 × COUNT(customers with >1 order) / COUNT(DISTINCT customer_unique_id)`
→ **3.0%** — only 1 in ~33 customers ever returns to buy again.

**Q11 — Pareto / revenue concentration among customers.**
Ranks customers into 100 percentile buckets by total spend using `NTILE(100) OVER (ORDER BY rev DESC)`, then sums the revenue contributed by the top 15 buckets versus the whole:
`% from top 15% = 100 × SUM(revenue WHERE pct_tile ≤ 15) / SUM(revenue)`
→ **46.71%** of all revenue comes from the top 15% of customers by spend.

**Q12 — Repeat purchase gap.**
A self-join on a `ROW_NUMBER()`-ranked purchase sequence per customer, joining each customer's 1st purchase to their 2nd:
`AVG(JULIANDAY(2nd order) − JULIANDAY(1st order))`
→ **81.2 days** average gap between a customer's first and second order — the natural window for a win-back campaign.

### Delivery & Satisfaction

**Q4 — On-time vs. late delivery rate and review-score impact.**
Buckets every order as On-Time or Late (`order_delivered_customer_date <= order_estimated_delivery_date`), then averages review score per bucket.
→ **92.0%** on-time (88,163 of 95,824 reviewed orders); on-time orders average a **4.29** review score vs. **2.57** for late orders — a 1.72-point gap.

**Q15 — Delivery-day deciles.**
Splits all orders into 10 equal-sized buckets by delivery time using `NTILE(10) OVER (ORDER BY delivery_days)`, reporting the min/max days per decile.
→ The fastest 10% of orders deliver in ≤4.2 days; the slowest 10% take 23.1–209.6 days, showing the tail risk hidden inside the platform-wide average.

**Q19 — Statistical correlation between delivery time and satisfaction.**
Pulls `(delivery_days, review_score)` pairs into pandas and computes the Pearson correlation coefficient:
`r = Cov(delivery_days, review_score) / (σ_delivery_days × σ_review_score)`
→ **r = −0.334** — a moderate negative correlation confirming that longer delivery times are statistically associated with lower satisfaction, not just visible in the on-time/late split above.

### Geography & Sellers

**Q5 — Revenue by customer state.**
Revenue and order count grouped by `customer_state`, ranked with `DENSE_RANK() OVER (ORDER BY SUM(total_revenue) DESC)`.
→ São Paulo (SP) dominates with **R$5.77M** (37% of total revenue) across 40,494 orders; Rio de Janeiro (RJ) and Minas Gerais (MG) follow at R$2.06M and R$1.82M.

**Q6 — Top 10 sellers by revenue.**
Sums `order_items.price` per seller (joined to delivered orders only), ranked descending, top 10 returned.
→ Top seller generated **R$226,988** across 1,124 orders; the top 10 span R$132K–R$227K each.

**Q13 — Seller revenue concentration (platform risk).**
Ranks all sellers by revenue with `RANK() OVER (ORDER BY revenue DESC)`, then computes what share the top 10 hold:
`Top-10 % = 100 × SUM(revenue WHERE rank ≤ 10) / SUM(revenue, all sellers)`
→ **13.27%** — the platform is not concentrated in a handful of sellers, unlike the customer-side Pareto skew.

**Q14 — Sellers with declining monthly revenue (early-warning flag).**
Computes each seller's monthly revenue, then uses `LAG(revenue) OVER (PARTITION BY seller_id ORDER BY month)` to compare each month to the seller's own prior month, filtering to `revenue < prev_month_revenue`.
→ Surfaces individual sellers trending downward month-over-month — a candidate account-health/churn-risk flag for the seller success team.

### Payments

**Q7 — Payment method mix.**
Transaction count and total value grouped by `payment_type`.
→ Credit card dominates with **R$12.54M** across 76,795 transactions (81% of payment value); boleto (a Brazilian bank-slip method) is second at R$2.87M.

**Q16 — Correlated subquery: above-average installment buyers.**
For each payment row, compares its installment count to that *same customer's own average* installment count across all their orders — the inner query re-evaluates per outer row (a true correlated subquery, not a static join):
```sql
WHERE op.payment_installments > (
  SELECT AVG(op2.payment_installments)
  FROM order_payments op2 ... WHERE o2.customer_id = o1.customer_id
)
```
→ Identifies individual transactions where a customer paid in more installments than their personal norm — useful for flagging financial-stress or high-value-purchase behavior at the customer level.

### Data Engineering / Infrastructure Queries

**Q17 — Reusable `vw_monthly_kpis` view.**
Materializes a monthly rollup (orders, customers, revenue, avg review score, avg delivery days) as a `VIEW`, so any future dashboard or query references one governed source instead of re-deriving the aggregation each time.

**Q18 — Index optimization + `EXPLAIN QUERY PLAN`.**
Adds indexes on the four most-joined/filtered columns (`orders.customer_id`, `order_items.order_id`, `order_items.seller_id`, `order_payments.order_id`) and confirms via `EXPLAIN QUERY PLAN` that SQLite switches from a full table scan to an index seek (`SEARCH ... USING INDEX`).

*(Query numbering follows the notebook: Q1–Q19 map to the 19 distinct analytical questions above; Q17–Q18 are infrastructure/performance queries rather than business-metric queries, and Q19 is the statistical validation query.)*

## 6. Headline Results

| Metric | Value |
|---|---|
| Total revenue | R$15,418,394.83 |
| Total delivered orders | 96,470 |
| Unique customers | 93,350 |
| Average order value | R$159.83 |
| Repeat customer rate | 3.0% |
| On-time delivery rate | 92.0% (88,163 of 95,824 reviewed orders) |
| On-time vs. late avg. review score | 4.29 vs. 2.57 |
| Delivery days ↔ review score correlation | r = −0.334 |
| Revenue from top 15% of customers | 46.71% |
| Top 10 sellers' share of platform revenue | 13.27% |
| Avg. days between a customer's 1st and 2nd order | 81.2 days |

**What these numbers mean for the business:**
- **Retention is the biggest lever.** Only 3% of customers ever order twice, yet the customers who do return account for a disproportionate share of revenue (top 15% of customers drive 46.71% of revenue). A win-back campaign timed around the ~81-day repeat-purchase window is the highest-leverage growth opportunity in the data.
- **Delivery speed is a satisfaction driver, not just an ops metric.** Late orders average a 2.57 review score versus 4.29 for on-time orders — a 1.7-point gap — and delivery time is moderately correlated with review score (r = −0.334) across the full order base, confirming the relationship holds beyond the simple on-time/late split.
- **The seller base is healthily diversified**, not platform-risk-concentrated: the top 10 sellers (out of thousands) account for only 13.27% of revenue.

---

## Dashboard

The dashboard (`dashboard/index.html`) is a single self-contained HTML file — no build step, no server required. Open it directly in a browser or host it with GitHub Pages.

It visualizes:
- Headline KPIs and 23-month revenue trend with 3-month moving average
- Cumulative revenue growth trajectory
- Month-over-month growth rate
- Delivery performance: on-time vs. late orders, review-score impact, and delivery-day decile distribution
- Revenue by customer state (top 10 of 27 states)
- Top 10 sellers by revenue
- Payment method mix
- Customer retention & concentration metrics (repeat rate, Pareto analysis, repurchase gap)

## SQL Techniques Demonstrated

- **Window functions:** `LAG()`, `RANK()`, `DENSE_RANK()`, `NTILE()`, `ROW_NUMBER()`, moving averages with `ROWS BETWEEN`, running totals with `SUM() OVER`
- **Correlated subqueries** (Q16 — per-customer installment comparison, re-evaluated per row)
- **CTEs (`WITH`)** for multi-stage aggregation pipelines
- **Reusable VIEWs** (`fact_orders`, `vw_monthly_kpis`) as a single source of truth for downstream BI tools
- **Data cleaning:** deduplicating late-arriving review records via `ROW_NUMBER()` partitioning
- **Query performance tuning:** added indexes on join/filter columns and verified usage with `EXPLAIN QUERY PLAN`
- **Statistical analysis in pandas:** Pearson correlation between delivery time and customer satisfaction

## Tech Stack

`SQLite` · `SQL (window functions, CTEs, views, indexing, correlated subqueries)` · `Python (pandas)` · `HTML/CSS/JS + Chart.js` for the dashboard

## Repository Structure

```
olist-sql-analytics/
├── README.md
├── sql/
│   └── queries.sql          # All 19 queries, documented, with real results noted inline
├── dashboard/
│   └── index.html           # Self-contained interactive dashboard
└── notebook/
    └── (place your .ipynb / .db here — excluded from git by default)
```

## Reproducing This Locally

1. Download the Olist dataset CSVs from Kaggle into a `data/` folder.
2. Run the loader (pandas → SQLite) to build `olist.db`, then run the cleaning script to create the `clean_order_reviews`, `order_revenue`, and `fact_orders` views (Section 0 of `sql/queries.sql`).
3. Run Q1–Q19 in order — each is independent and can be run standalone against `fact_orders`.
4. Open `dashboard/index.html` in a browser to see the results visualized.

---

*Built as a portfolio project to demonstrate applied SQL analytics: from raw relational data to a documented, reproducible, business-relevant set of findings.*
