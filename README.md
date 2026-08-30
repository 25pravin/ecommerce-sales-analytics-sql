# Olist E-Commerce Sales Analytics
### SQL-Driven Business Intelligence on a Real Brazilian Marketplace Dataset

> **One-line pitch:** I analyzed 96,470 delivered orders (R$15.4M in revenue) from Olist's Brazilian marketplace using 19 production-style SQL queries, uncovered three concrete business insights, and packaged everything into a self-contained interactive dashboard.

**[▶ View Interactive Dashboard](https://25pravin.github.io/ecommerce-sales-analytics-sql/Dashboard.html)** | **[View all 19 SQL Queries](https://25pravin.github.io/ecommerce-sales-analytics-sql/sql_queriesnb.html)**

---

## 1. What Is This Project? (30-second intro)

This is an end-to-end sales analytics project built on the **Olist Brazilian E-Commerce dataset** — a real, publicly available dataset with 8 relational tables (orders, order items, payments, reviews, customers, sellers, geolocation, product-category translation).

I used it to answer four business questions:
1. How is revenue trending over time?
2. Why don't customers come back?
3. Does delivery speed actually affect customer satisfaction?
4. Is the seller base risky (concentrated) or healthy (diversified)?

**Scope:** 96,470 delivered orders · R$15,418,394.83 total revenue · 93,350 unique customers · Sept 2016 – Aug 2018 (23 months)

---

## 2. The Pipeline (how I built it — say this when asked "walk me through your process")



- **Data layer:** Loaded raw Olist CSVs into SQLite, consolidated the core order-level data into a `fact_orders` view as a single source of truth.
- **Analysis layer:** Wrote 19 independent, documented SQL queries — each runs standalone against `fact_orders` (bringing in other tables like `sellers` or `order_payments` only where a specific question needs them).
- **Statistics layer:** Used pandas for deeper analysis, e.g. Pearson correlation between delivery time and review scores.
- **Presentation layer:** Built a single self-contained HTML dashboard (Chart.js) — no server, no build step, just open it in a browser.

---

## 3. The Data Model — How `fact_orders` and `vw_monthly_kpis` Are Actually Built

Two layered SQL views sit at the center of this project — every one of the 19 queries and the dashboard read from these instead of re-joining raw tables from scratch.

**`fact_orders` — the core order-level fact table.** It is *not* a combination of all 8 raw tables. It's built from four sources: `orders` and `customers` are joined directly, plus two cleaned/aggregated helper views — `order_revenue` (rolls up `order_items` into one row per order, since an order can have multiple line items) and `clean_order_reviews` (dedupes `order_reviews` using `ROW_NUMBER()`, since a customer can leave more than one review per order). The resulting view holds one row per delivered order, with order dates, customer state/city, total revenue, item count, review score, and computed delivery-time fields.

`sellers` and `order_payments` are deliberately *not* baked into `fact_orders` — they're joined in only on the specific queries that need them (seller leaderboards, seller concentration, payment mix, installment analysis). This keeps the fact table lean and avoids duplicating order-level rows, since a single order can have multiple sellers or multiple payment installments. `geolocation` and `category_translation` are loaded into SQLite but aren't used by the current 19 queries.

**`vw_monthly_kpis` — a monthly rollup built on top of `fact_orders`.** It doesn't touch raw tables at all; it aggregates the 96,470 order-level rows in `fact_orders` down to one row per calendar month (23 rows), with orders, unique customers, revenue, average review score, and average delivery days per month. It exists so that every trend chart (revenue over time, month-over-month growth, moving averages) can just query this view instead of repeating the same monthly `GROUP BY` logic — a "single source of truth" pattern: if the revenue calculation logic ever changes, it's updated in one place, not in every query that depends on it.

**Mental model:** `fact_orders` is raw, order-level detail (one row per order); `vw_monthly_kpis` is its monthly rollup — like a PivotTable, but as a live SQL view. Both are defined in `sql/queries.sql` (Section 0 and Query 17 respectively).

---

## 4. Headline Numbers (say these first — they set the scale of the project)

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

---

## 5. The Three Insights (this is the core of your explanation — tell it like a story)

### 🔴 Insight 1 — Retention is the biggest lever
Only **3% of customers** ever order a second time. But the customers who *do* return are extremely valuable: the **top 15% of customers drive 46.71% of revenue**. On average, a returning customer comes back after **81.2 days**.

**So what?** A win-back campaign timed around the ~81-day mark is the single highest-leverage growth opportunity in this data — you're not guessing when to re-engage customers, the data tells you.

*Technique used: `NTILE()` for the Pareto/revenue-concentration split, `LAG()` to calculate the gap between a customer's 1st and 2nd order.*

---

### 🟠 Insight 2 — Delivery speed is a satisfaction driver, not just an ops metric
92% of orders arrive on time. But late orders average a review score of **2.57**, versus **4.29** for on-time orders — a **1.7-point gap**. This holds up statistically too: delivery time and review score are moderately correlated (**r = −0.334**) across the entire order base.

**So what?** Delivery isn't just a logistics KPI — it's directly tied to customer sentiment and, by extension, repeat business and reviews. Ops and CX teams should treat delivery SLAs as a retention lever, not just a cost metric.

*Technique used: `ROW_NUMBER()` partitioning to deduplicate late-arriving review records before running correlation, so the stats aren't skewed by duplicate data.*

---

### 🟢 Insight 3 — The seller base is healthily diversified
Out of thousands of sellers on the platform, the **top 10 sellers account for only 13.27%** of total revenue.

**So what?** This is a good sign for platform resilience — no small handful of sellers has outsized leverage. If one seller left tomorrow, the platform wouldn't take a major revenue hit. This is the kind of check a marketplace risk/ops team would want before investing further.

*Technique used: `RANK()` / `DENSE_RANK()` to build the seller revenue leaderboard.*

---

## 6. Technical Depth (for when someone asks "what SQL did you actually use?")

This wasn't built with basic `SELECT` statements — it demonstrates production-style SQL:

| Technique | Where it's used |
|---|---|
| **Window functions** | `LAG()`, `RANK()`, `DENSE_RANK()`, `NTILE()`, `ROW_NUMBER()`, moving averages via `ROWS BETWEEN` |
| **Correlated subqueries** | Query 16 — per-customer installment comparison |
| **CTEs (`WITH`)** | Multi-stage aggregation pipelines |
| **Reusable VIEWs** | `fact_orders`, `vw_monthly_kpis` — layered so every downstream query/dashboard reads from a single source of truth (see Section 3 for exactly how these are built) |
| **Data cleaning** | Deduplicating late-arriving review records via `ROW_NUMBER()` partitioning (`clean_order_reviews`) |
| **Performance tuning** | Indexes on join/filter columns (`orders.customer_id`, `order_items.order_id`, `order_items.seller_id`, `order_payments.order_id`), verified with `EXPLAIN QUERY PLAN` |
| **Statistical analysis (pandas)** | Pearson correlation between delivery time and customer satisfaction |

---

## 7. The Dashboard (what to show if someone wants to *see* it)

`dashboard/index.html` — a single self-contained file, no build step or server needed. Open it directly, or view it live: **[View Interactive Dashboard](https://25pravin.github.io/ecommerce-sales-analytics-sql/Dashboard.html)**

It visualizes:
- Headline KPIs + 23-month revenue trend (3-month moving average)
- Cumulative revenue growth trajectory
- Month-over-month growth rate
- Delivery performance: on-time vs. late orders, review-score impact, delivery-day decile distribution
- Revenue by customer state (top 10 of 27 states)
- Top 10 sellers by revenue
- Payment method mix
- Customer retention & concentration metrics (repeat rate, Pareto analysis, repurchase gap)

---

## 8. Tech Stack & Dataset

**Stack:** `SQLite` · `SQL (window functions, CTEs, views, indexing)` · `Python (pandas)` · `HTML/CSS/JS + Chart.js`

**Dataset:** [Olist Brazilian E-Commerce Public Dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle) — 8 relational tables covering orders, order items, payments, reviews, customers, sellers, geolocation, and product-category translation. Raw CSVs aren't checked into the repo (see `.gitignore`); download from Kaggle and run the loader in `notebook/` to reproduce `olist.db` locally.

---

## 9. Repository Structure






---

## 10. How to Reproduce This Locally

1. Download the Olist dataset CSVs from Kaggle into a `data/` folder.
2. Run the loader queries in `sql/queries.sql` (Section 0) against a new SQLite database to build `clean_order_reviews`, `order_revenue`, and `fact_orders`.
3. Run Q1–Q19 in order — each is independent and can be run standalone against `fact_orders`.
4. Open `dashboard/index.html` in a browser to see the results visualized.

---

## 11. 30-Second Elevator Pitch (memorize this line)

> "I built an end-to-end SQL analytics project on a real 96,000-order e-commerce dataset — used window functions, CTEs, and correlated subqueries to go beyond basic SQL, and turned raw transaction data into three concrete business recommendations: target win-back campaigns at the 81-day mark, treat delivery speed as a retention driver not just an ops metric, and confirmed the seller base isn't a concentration risk. Everything's packaged into a self-contained interactive dashboard anyone can open in a browser."

---

*Built as a portfolio project to demonstrate applied SQL analytics: from raw relational data to a documented, reproducible, business-relevant set of findings.*
