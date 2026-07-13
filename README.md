# Olist E-Commerce Sales Analytics

SQL-driven analysis of **96,470 delivered orders** and **R$15.4M in revenue** from the Olist Brazilian e-commerce marketplace, spanning **Sept 2016 – Aug 2018 (23 months / ~2 years)** of transaction history. Built end-to-end with SQLite, pandas, and 19 analytical queries covering revenue trends, customer retention, delivery performance, and seller concentration — presented as an interactive dashboard.

**[▶ View Interactive Dashboard](https://25pravin.github.io/-ecommerce-sales-rfm-analysis/)**[View all 19 SQL queries](./sql/queries.html)**

---

## Key findings

| Metric | Value |
|---|---|
| Total revenue | R$15,418,394.83 |
| Total delivered orders | 96,470 |
| Unique customers | 93,350 |
| Average order value | R$159.83 |
| Repeat customer rate | 3.0% |
| On-time delivery rate | 92.0% (88,163 of 95,824 reviewed orders) |
| On-time vs late avg. review score | 4.29 vs 2.57 |
| Delivery days ↔ review score correlation | r = −0.334 |
| Revenue from top 15% of customers | 46.71% |
| Top 10 sellers' share of platform revenue | 13.27% |
| Avg. days between a customer's 1st and 2nd order | 81.2 days |

**What these numbers mean for the business:**
- **Retention is the biggest lever.** Only 3% of customers ever order twice, yet the customers who do return account for a disproportionate share of revenue (top 15% of customers drive 46.71% of revenue). A win-back campaign targeted around the ~81-day repeat-purchase window is the highest-leverage growth opportunity in the data.
- **Delivery speed is a satisfaction driver, not just an ops metric.** Late orders average a 2.57 review score versus 4.29 for on-time orders — a 1.7-point gap — and delivery time is moderately correlated with review score (r = −0.334) across the full order base.
- **The seller base is healthily diversified**, not platform-risk-concentrated: the top 10 sellers (out of thousands) account for only 13.27% of revenue.

---

## Dashboard

The dashboard (`/dashboard/index.html`) is a single self-contained HTML file — no build step, no server required. Open it directly in a browser or host it with GitHub Pages.

It visualizes:
- Headline KPIs and 23-month revenue trend with 3-month moving average
- Cumulative revenue growth trajectory
- Month-over-month growth rate
- Delivery performance: on-time vs. late orders, review-score impact, and delivery-day decile distribution
- Revenue by customer state (top 10 of 27 states)
- Top 10 sellers by revenue
- Payment method mix
- Customer retention & concentration metrics (repeat rate, Pareto analysis, repurchase gap)

## SQL techniques demonstrated

This project was built to showcase production-style SQL, not just basic `SELECT` statements:

- **Window functions:** `LAG()`, `RANK()`, `DENSE_RANK()`, `NTILE()`, `ROW_NUMBER()`, moving averages with `ROWS BETWEEN`
- **Correlated subqueries** (Q16 — per-customer installment comparison)
- **CTEs (`WITH`)** for multi-stage aggregation pipelines
- **Reusable VIEWs** (`fact_orders`, `vw_monthly_kpis`) as a single source of truth for downstream BI tools
- **Data cleaning**: deduplicating late-arriving review records via `ROW_NUMBER()` partitioning
- **Query performance tuning**: added indexes on join/filter columns and verified usage with `EXPLAIN QUERY PLAN`
- **Statistical analysis in pandas**: Pearson correlation between delivery time and customer satisfaction

## Tech stack

`SQLite` · `SQL (window functions, CTEs, views, indexing)` · `Python (pandas)` · `HTML/CSS/JS + Chart.js` for the dashboard

## Dataset

[Olist Brazilian E-Commerce Public Dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle) — 8 relational tables covering orders, order items, payments, reviews, customers, sellers, and geolocation. Raw CSVs are not included in this repo (see `.gitignore`); download them from Kaggle and run the loader in `notebook/` to reproduce `olist.db` locally.

## Repository structure

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

## Reproducing this locally

1. Download the Olist dataset CSVs from Kaggle into a `data/` folder.
2. Run the loader queries in `sql/queries.sql` (Section 0) against a new SQLite database to build `fact_orders`.
3. Run Q1–Q19 in order — each is independent and can be run standalone against `fact_orders`.
4. Open `dashboard/index.html` in a browser to see the results visualized.

---

*Built as a portfolio project to demonstrate applied SQL analytics: from raw relational data to a documented, reproducible, business-relevant set of findings.*
