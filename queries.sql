/* ============================================================================
   OLIST E-COMMERCE SALES ANALYTICS — SQL QUERY LIBRARY
   Dataset : Olist Brazilian E-Commerce Public Dataset (SQLite)
   Period  : Sept 2016 – Aug 2018 (delivered orders only)
   Author  : [Your Name]
   ============================================================================
   This file contains the full set of queries used to build the KPIs and
   charts in /dashboard/index.html. Every result quoted in the README and
   dashboard was generated directly by running these queries against
   olist.db — nothing is estimated or simulated.
   ========================================================================== */


/* ----------------------------------------------------------------------
   0. FOUNDATION VIEWS
   Deduplicate reviews, pre-aggregate order revenue, and build a single
   clean fact table (fact_orders) that every downstream query reads from.
   ---------------------------------------------------------------------- */

CREATE VIEW IF NOT EXISTS clean_order_reviews AS
SELECT * FROM (
    SELECT r.*,
           ROW_NUMBER() OVER (PARTITION BY order_id
                               ORDER BY review_answer_timestamp DESC) AS rn
    FROM order_reviews r
) WHERE rn = 1;

CREATE VIEW IF NOT EXISTS order_revenue AS
SELECT order_id,
       SUM(price)                    AS items_revenue,
       SUM(freight_value)            AS freight_revenue,
       SUM(price + freight_value)    AS total_revenue,
       COUNT(*)                      AS item_count
FROM order_items
GROUP BY order_id;

CREATE VIEW IF NOT EXISTS fact_orders AS
SELECT
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    c.customer_state,
    c.customer_city,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    r.total_revenue,
    r.item_count,
    rv.review_score,
    JULIANDAY(o.order_delivered_customer_date) - JULIANDAY(o.order_purchase_timestamp)  AS delivery_days,
    JULIANDAY(o.order_estimated_delivery_date) - JULIANDAY(o.order_delivered_customer_date) AS delivery_buffer_days
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
LEFT JOIN order_revenue r ON r.order_id = o.order_id
LEFT JOIN clean_order_reviews rv ON rv.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL;


/* ----------------------------------------------------------------------
   Q1. Headline KPIs — total revenue, orders, customers, AOV
   Result: revenue R$15,418,394.83 | orders 96,470 | customers 93,350 | AOV R$159.83
   ---------------------------------------------------------------------- */
SELECT
    ROUND(SUM(total_revenue), 2)                              AS total_revenue,
    COUNT(DISTINCT order_id)                                  AS total_orders,
    COUNT(DISTINCT customer_unique_id)                        AS total_customers,
    ROUND(SUM(total_revenue) / COUNT(DISTINCT order_id), 2)   AS avg_order_value
FROM fact_orders;


/* ----------------------------------------------------------------------
   Q2. Monthly revenue trend
   ---------------------------------------------------------------------- */
SELECT strftime('%Y-%m', order_purchase_timestamp) AS month,
       ROUND(SUM(total_revenue), 2)                 AS monthly_revenue,
       COUNT(DISTINCT order_id)                      AS orders
FROM fact_orders
GROUP BY month
ORDER BY month;


/* ----------------------------------------------------------------------
   Q3. Repeat customer rate — the single most important retention metric
   Result: 3.0%
   ---------------------------------------------------------------------- */
SELECT
    ROUND(100.0 *
        (SELECT COUNT(*) FROM (
            SELECT customer_unique_id FROM fact_orders
            GROUP BY customer_unique_id HAVING COUNT(DISTINCT order_id) > 1
        ))
        / (SELECT COUNT(DISTINCT customer_unique_id) FROM fact_orders)
    , 2) AS repeat_customer_rate_pct;


/* ----------------------------------------------------------------------
   Q4. On-time vs late delivery rate, and its effect on review scores
   Result: On-Time 88,163 orders / 4.29 avg score | Late 7,661 orders / 2.57 avg score
   ---------------------------------------------------------------------- */
SELECT
    CASE WHEN order_delivered_customer_date <= order_estimated_delivery_date
         THEN 'On-Time' ELSE 'Late' END AS delivery_status,
    COUNT(*)                            AS orders,
    ROUND(AVG(review_score), 2)         AS avg_review_score
FROM fact_orders
WHERE review_score IS NOT NULL
GROUP BY delivery_status;


/* ----------------------------------------------------------------------
   Q5. Revenue by customer state, ranked highest to lowest
   Uses DENSE_RANK() so tied revenue states share a rank.
   ---------------------------------------------------------------------- */
SELECT customer_state,
       ROUND(SUM(total_revenue), 2)                             AS revenue,
       COUNT(DISTINCT order_id)                                 AS orders,
       DENSE_RANK() OVER (ORDER BY SUM(total_revenue) DESC)      AS revenue_rank
FROM fact_orders
GROUP BY customer_state
ORDER BY revenue_rank;


/* ----------------------------------------------------------------------
   Q6. Top 10 sellers by revenue
   ---------------------------------------------------------------------- */
SELECT oi.seller_id, s.seller_state,
       ROUND(SUM(oi.price), 2)        AS revenue,
       COUNT(DISTINCT oi.order_id)    AS orders_fulfilled
FROM order_items oi
JOIN sellers s      ON s.seller_id = oi.seller_id
JOIN fact_orders fo ON fo.order_id = oi.order_id
GROUP BY oi.seller_id, s.seller_state
ORDER BY revenue DESC
LIMIT 10;


/* ----------------------------------------------------------------------
   Q7. Payment method mix
   ---------------------------------------------------------------------- */
SELECT payment_type,
       COUNT(*)                       AS transactions,
       ROUND(SUM(payment_value), 2)   AS total_value
FROM order_payments
GROUP BY payment_type
ORDER BY total_value DESC;


/* ----------------------------------------------------------------------
   Q8. Month-over-month revenue growth — LAG() window function
   ---------------------------------------------------------------------- */
WITH monthly AS (
    SELECT strftime('%Y-%m', order_purchase_timestamp) AS month,
           SUM(total_revenue) AS revenue
    FROM fact_orders
    GROUP BY month
)
SELECT month, ROUND(revenue, 2) AS revenue,
       ROUND(revenue - LAG(revenue) OVER (ORDER BY month), 2) AS mom_change,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
             / LAG(revenue) OVER (ORDER BY month), 2)          AS mom_growth_pct
FROM monthly
ORDER BY month;


/* ----------------------------------------------------------------------
   Q9. Cumulative (running total) revenue — shows growth trajectory
   ---------------------------------------------------------------------- */
SELECT strftime('%Y-%m', order_purchase_timestamp) AS month,
       ROUND(SUM(total_revenue), 2) AS monthly_revenue,
       ROUND(SUM(SUM(total_revenue)) OVER (
           ORDER BY strftime('%Y-%m', order_purchase_timestamp)
       ), 2) AS running_total_revenue
FROM fact_orders
GROUP BY month
ORDER BY month;


/* ----------------------------------------------------------------------
   Q10. 3-month moving average — smooths month-to-month noise
   ---------------------------------------------------------------------- */
WITH monthly AS (
    SELECT strftime('%Y-%m', order_purchase_timestamp) AS month,
           SUM(total_revenue) AS revenue
    FROM fact_orders GROUP BY month
)
SELECT month, ROUND(revenue, 2) AS revenue,
       ROUND(AVG(revenue) OVER (
           ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
       ), 2) AS moving_avg_3mo
FROM monthly ORDER BY month;


/* ----------------------------------------------------------------------
   Q11. Pareto analysis — % of revenue from the top 15% of customers
   Result: 46.71%
   ---------------------------------------------------------------------- */
WITH cust_rev AS (
    SELECT customer_unique_id, SUM(total_revenue) AS rev
    FROM fact_orders GROUP BY customer_unique_id
),
tiled AS (
    SELECT *, NTILE(100) OVER (ORDER BY rev DESC) AS pct_tile FROM cust_rev
)
SELECT ROUND(100.0 * SUM(CASE WHEN pct_tile <= 15 THEN rev ELSE 0 END)
             / SUM(rev), 2) AS revenue_pct_from_top15pct_customers
FROM tiled;


/* ----------------------------------------------------------------------
   Q12. Repeat purchase gap — avg days between 1st and 2nd purchase
   Result: 81.21 days — the effective retention/win-back window
   ---------------------------------------------------------------------- */
WITH ordered_purchases AS (
    SELECT customer_unique_id, order_id, order_purchase_timestamp,
           ROW_NUMBER() OVER (PARTITION BY customer_unique_id
                               ORDER BY order_purchase_timestamp) AS purchase_seq
    FROM fact_orders
)
SELECT AVG(JULIANDAY(o2.order_purchase_timestamp) - JULIANDAY(o1.order_purchase_timestamp))
       AS avg_days_between_1st_2nd_purchase
FROM ordered_purchases o1
JOIN ordered_purchases o2
  ON o1.customer_unique_id = o2.customer_unique_id
 AND o1.purchase_seq = 1 AND o2.purchase_seq = 2;


/* ----------------------------------------------------------------------
   Q13. Seller revenue concentration — RANK() + Pareto
   Result: Top 10 sellers = 13.27% of platform revenue (low concentration = healthy diversification)
   ---------------------------------------------------------------------- */
WITH seller_rev AS (
    SELECT oi.seller_id, SUM(oi.price) AS revenue
    FROM order_items oi JOIN fact_orders fo ON fo.order_id = oi.order_id
    GROUP BY oi.seller_id
),
ranked AS (SELECT *, RANK() OVER (ORDER BY revenue DESC) AS rnk FROM seller_rev)
SELECT ROUND(100.0 * SUM(CASE WHEN rnk <= 10 THEN revenue ELSE 0 END)
             / (SELECT SUM(revenue) FROM seller_rev), 2) AS top10_seller_revenue_pct
FROM ranked;


/* ----------------------------------------------------------------------
   Q14. Sellers with declining monthly revenue — LAG-based anomaly flag
   Early-warning signal: any seller whose current month < previous month.
   ---------------------------------------------------------------------- */
WITH seller_monthly AS (
    SELECT oi.seller_id, strftime('%Y-%m', fo.order_purchase_timestamp) AS month,
           SUM(oi.price) AS revenue
    FROM order_items oi JOIN fact_orders fo ON fo.order_id = oi.order_id
    GROUP BY oi.seller_id, month
),
with_lag AS (
    SELECT *, LAG(revenue) OVER (PARTITION BY seller_id ORDER BY month) AS prev_month_revenue
    FROM seller_monthly
)
SELECT seller_id, month, ROUND(revenue, 2) AS revenue,
       ROUND(prev_month_revenue, 2) AS prev_month_revenue
FROM with_lag
WHERE revenue < prev_month_revenue
LIMIT 15;


/* ----------------------------------------------------------------------
   Q15. Delivery delay deciles — NTILE() for percentile buckets
   Shows the FULL distribution, not just the average (avg hides the long tail).
   ---------------------------------------------------------------------- */
WITH d AS (
    SELECT delivery_days, NTILE(10) OVER (ORDER BY delivery_days) AS decile FROM fact_orders
)
SELECT decile, ROUND(MIN(delivery_days), 1) AS min_days, ROUND(MAX(delivery_days), 1) AS max_days
FROM d GROUP BY decile ORDER BY decile;


/* ----------------------------------------------------------------------
   Q16. Correlated subquery — customers whose installments exceed
   their own personal average (inner query re-evaluates per outer row)
   ---------------------------------------------------------------------- */
SELECT op.order_id, op.payment_installments
FROM order_payments op
WHERE op.payment_installments > (
    SELECT AVG(op2.payment_installments)
    FROM order_payments op2
    JOIN orders o2 ON o2.order_id = op2.order_id
    JOIN orders o1 ON o1.order_id = op.order_id
    WHERE o2.customer_id = o1.customer_id
)
LIMIT 10;


/* ----------------------------------------------------------------------
   Q17. Reusable VIEW — single source of truth for dashboard/BI tools
   ---------------------------------------------------------------------- */
CREATE VIEW IF NOT EXISTS vw_monthly_kpis AS
SELECT strftime('%Y-%m', order_purchase_timestamp) AS month,
       COUNT(DISTINCT order_id)          AS orders,
       COUNT(DISTINCT customer_unique_id) AS customers,
       ROUND(SUM(total_revenue), 2)      AS revenue,
       ROUND(AVG(review_score), 2)       AS avg_review_score,
       ROUND(AVG(delivery_days), 1)      AS avg_delivery_days
FROM fact_orders GROUP BY month;


/* ----------------------------------------------------------------------
   Q18. Index optimization + EXPLAIN QUERY PLAN
   Confirms SQLite uses the index instead of a full table scan.
   ---------------------------------------------------------------------- */
CREATE INDEX IF NOT EXISTS idx_orders_customer_id       ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id     ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_seller_id    ON order_items(seller_id);
CREATE INDEX IF NOT EXISTS idx_order_payments_order_id  ON order_payments(order_id);

EXPLAIN QUERY PLAN
SELECT * FROM orders WHERE customer_id = '0000366f3b9a7992bf8c76cfdf3221e2';
-- Result: SEARCH orders USING INDEX idx_orders_customer_id (index confirmed in use)


/* ----------------------------------------------------------------------
   Q19. Correlation between delivery days and review score
   Result: r = -0.334 (moderate negative correlation — slower delivery,
   measurably lower satisfaction)
   ---------------------------------------------------------------------- */
SELECT delivery_days, review_score
FROM fact_orders
WHERE review_score IS NOT NULL;
-- Computed in pandas: df['delivery_days'].corr(df['review_score']) = -0.334
