use [Olist-E-Commerce];
go


/*===========================================================
  CUSTOMER_360 (Optimal ~55 Columns)  |  SQL Server (T-SQL)
  Grain: 1 row per customer_unique_id
  Notes:
   - Uses GETDATE() as "as_of_date"
   - Churn threshold = 180 days (change @churn_days)
===========================================================*/

CREATE OR ALTER VIEW dbo.customer_360
AS
WITH
params AS (
    SELECT
        CAST(GETDATE() AS date) AS as_of_date,
        180 AS churn_days
),

/* 1) Customer base (identity + location) */
cust AS (
    SELECT
        c.customer_unique_id,
        MIN(c.customer_id) AS first_customer_id,
        MAX(c.customer_city) AS customer_city,
        MAX(c.customer_state) AS customer_state,
        MAX(c.customer_zip_code_prefix) AS customer_zip_code_prefix
    FROM dbo.customers c
    GROUP BY c.customer_unique_id
),

/* 2) Geo enrichment: avg lat/lng by zip+state (best-effort) */
geo_zip_state AS (
    SELECT
        g.geolocation_zip_code_prefix,
        g.geolocation_state,
        AVG(CAST(g.geolocation_lat AS float)) AS customer_latitude,
        AVG(CAST(g.geolocation_lng AS float)) AS customer_longitude
    FROM dbo.geolocation g
    GROUP BY g.geolocation_zip_code_prefix, g.geolocation_state
),

cust_geo AS (
    SELECT
        cu.*,
        gz.customer_latitude,
        gz.customer_longitude
    FROM cust cu
    LEFT JOIN geo_zip_state gz
        ON gz.geolocation_zip_code_prefix = cu.customer_zip_code_prefix
       AND gz.geolocation_state = cu.customer_state
),

/* 3) Orders at customer_unique_id grain */
orders_base AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_status,
        o.order_purchase_timestamp,
        CAST(o.order_purchase_timestamp AS date) AS purchase_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date
    FROM dbo.orders o
    INNER JOIN dbo.customers c
        ON c.customer_id = o.customer_id
),

orders_agg AS (
    SELECT
        ob.customer_unique_id,

        MIN(ob.purchase_date) AS first_purchase_date,
        MAX(ob.purchase_date) AS last_purchase_date,

        COUNT(DISTINCT ob.order_id) AS total_orders,

        SUM(CASE WHEN ob.order_status = 'delivered' THEN 1 ELSE 0 END) AS delivered_orders,
        SUM(CASE WHEN ob.order_status = 'canceled'  THEN 1 ELSE 0 END) AS canceled_orders,
        SUM(CASE WHEN ob.order_status <> 'delivered' THEN 1 ELSE 0 END) AS undelivered_orders,

        /* on-time / late only meaningful for delivered with estimated date */
        SUM(CASE
                WHEN ob.order_status = 'delivered'
                 AND ob.order_delivered_customer_date IS NOT NULL
                 AND ob.order_estimated_delivery_date IS NOT NULL
                 AND CAST(ob.order_delivered_customer_date AS date) <= CAST(ob.order_estimated_delivery_date AS date)
                THEN 1 ELSE 0
            END) AS on_time_deliveries,

        SUM(CASE
                WHEN ob.order_status = 'delivered'
                 AND ob.order_delivered_customer_date IS NOT NULL
                 AND ob.order_estimated_delivery_date IS NOT NULL
                 AND CAST(ob.order_delivered_customer_date AS date) > CAST(ob.order_estimated_delivery_date AS date)
                THEN 1 ELSE 0
            END) AS late_deliveries,

        /* delivery durations (days), delivered only */
        AVG(CASE
                WHEN ob.order_status = 'delivered'
                 AND ob.order_delivered_customer_date IS NOT NULL
                THEN CAST(DATEDIFF(day, ob.order_purchase_timestamp, ob.order_delivered_customer_date) AS float)
            END) AS avg_delivery_days,

        /* days late (only for late deliveries) */
        AVG(CASE
                WHEN ob.order_status = 'delivered'
                 AND ob.order_delivered_customer_date IS NOT NULL
                 AND ob.order_estimated_delivery_date IS NOT NULL
                 AND CAST(ob.order_delivered_customer_date AS date) > CAST(ob.order_estimated_delivery_date AS date)
                THEN CAST(DATEDIFF(day, ob.order_estimated_delivery_date, ob.order_delivered_customer_date) AS float)
            END) AS avg_days_late,

        /* cohort */
        CONVERT(char(7), MIN(ob.purchase_date), 120) AS acquisition_cohort_month,

        /* active months */
        COUNT(DISTINCT CONVERT(char(7), ob.purchase_date, 120)) AS active_months_count
    FROM orders_base ob
    GROUP BY ob.customer_unique_id
),

/* 4) Median delivery days (window) */
delivery_median AS (
    SELECT DISTINCT
        ob.customer_unique_id,
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY DATEDIFF(day, ob.order_purchase_timestamp, ob.order_delivered_customer_date)
        ) OVER (PARTITION BY ob.customer_unique_id) AS median_delivery_days
    FROM orders_base ob
    WHERE ob.order_status = 'delivered'
      AND ob.order_delivered_customer_date IS NOT NULL
),

/* 5) Interpurchase metrics: avg/max gaps + first-to-second gap */
order_dates AS (
    SELECT
        ob.customer_unique_id,
        ob.purchase_date,
        ROW_NUMBER() OVER (PARTITION BY ob.customer_unique_id ORDER BY ob.purchase_date, ob.order_id) AS rn,
        LAG(ob.purchase_date) OVER (PARTITION BY ob.customer_unique_id ORDER BY ob.purchase_date, ob.order_id) AS prev_purchase_date
    FROM orders_base ob
),

gaps AS (
    SELECT
        customer_unique_id,
        AVG(CAST(DATEDIFF(day, prev_purchase_date, purchase_date) AS float)) AS avg_days_between_orders,
        MAX(DATEDIFF(day, prev_purchase_date, purchase_date)) AS max_days_between_orders
    FROM order_dates
    WHERE prev_purchase_date IS NOT NULL
    GROUP BY customer_unique_id
),

first_second AS (
    SELECT
        d1.customer_unique_id,
        DATEDIFF(day,
                 MAX(CASE WHEN d1.rn = 1 THEN d1.purchase_date END),
                 MAX(CASE WHEN d1.rn = 2 THEN d1.purchase_date END)
        ) AS first_to_second_order_days
    FROM order_dates d1
    GROUP BY d1.customer_unique_id
),

/* 6) Order items: revenue, freight, items, distinct products/sellers */
items_base AS (
    SELECT
        c.customer_unique_id,
        oi.order_id,
        oi.order_item_id,
        oi.product_id,
        oi.seller_id,
        oi.price,
        oi.freight_value
    FROM dbo.order_items oi
    INNER JOIN dbo.orders o
        ON o.order_id = oi.order_id
    INNER JOIN dbo.customers c
        ON c.customer_id = o.customer_id
),

items_agg AS (
    SELECT
        ib.customer_unique_id,

        SUM(CAST(ib.price AS float)) AS total_revenue,
        AVG(CAST(ib.price AS float)) AS avg_order_item_price,     -- not used directly; kept as helper
        MIN(CAST(ib.price AS float)) AS min_item_price,           -- helper
        MAX(CAST(ib.price AS float)) AS max_item_price,           -- helper

        SUM(CAST(ib.freight_value AS float)) AS total_freight_value,

        COUNT(*) AS total_items_purchased,
        COUNT(DISTINCT ib.product_id) AS distinct_products_purchased,
        COUNT(DISTINCT ib.seller_id) AS distinct_sellers_purchased
    FROM items_base ib
    GROUP BY ib.customer_unique_id
),

/* 7) Order-level monetary stats: avg/min/max order value */
order_value AS (
    SELECT
        c.customer_unique_id,
        oi.order_id,
        SUM(CAST(oi.price AS float)) AS order_value
    FROM dbo.order_items oi
    INNER JOIN dbo.orders o
        ON o.order_id = oi.order_id
    INNER JOIN dbo.customers c
        ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id, oi.order_id
),

order_value_agg AS (
    SELECT
        customer_unique_id,
        AVG(order_value) AS avg_order_value,
        MIN(order_value) AS min_order_value,
        MAX(order_value) AS max_order_value
    FROM order_value
    GROUP BY customer_unique_id
),

/* 8) Payments: totals + installment behavior + payment type rates + mode */
payments_base AS (
    SELECT
        c.customer_unique_id,
        p.order_id,
        p.payment_type,
        CAST(p.payment_value AS float) AS payment_value,
        CAST(p.payment_installments AS int) AS payment_installments
    FROM dbo.payments p
    INNER JOIN dbo.orders o
        ON o.order_id = p.order_id
    INNER JOIN dbo.customers c
        ON c.customer_id = o.customer_id
),

/* per-order installments (avoid double-counting if multiple payment rows) */
order_installments AS (
    SELECT
        customer_unique_id,
        order_id,
        MAX(payment_installments) AS installments_in_order
    FROM payments_base
    GROUP BY customer_unique_id, order_id
),

payments_agg AS (
    SELECT
        pb.customer_unique_id,

        SUM(pb.payment_value) AS total_payment_value,

        AVG(CAST(oi.installments_in_order AS float)) AS avg_installments_per_order,

        COUNT(DISTINCT pb.order_id) AS paid_orders,

        COUNT(DISTINCT CASE WHEN pb.payment_type = 'credit_card' THEN pb.order_id END) AS credit_card_orders,
        COUNT(DISTINCT CASE WHEN pb.payment_type = 'boleto'      THEN pb.order_id END) AS boleto_orders,
        COUNT(DISTINCT CASE WHEN pb.payment_type = 'voucher'     THEN pb.order_id END) AS voucher_orders,
        COUNT(DISTINCT CASE WHEN pb.payment_type = 'debit_card'  THEN pb.order_id END) AS debit_card_orders,

        COUNT(DISTINCT CASE WHEN oi.installments_in_order > 1 THEN pb.order_id END) AS installment_orders
    FROM payments_base pb
    LEFT JOIN order_installments oi
        ON oi.customer_unique_id = pb.customer_unique_id
       AND oi.order_id = pb.order_id
    GROUP BY pb.customer_unique_id
),

payment_type_mode AS (
    SELECT
        customer_unique_id,
        payment_type AS most_used_payment_type
    FROM (
        SELECT
            customer_unique_id,
            payment_type,
            COUNT(DISTINCT order_id) AS cnt_orders,
            ROW_NUMBER() OVER (
                PARTITION BY customer_unique_id
                ORDER BY COUNT(DISTINCT order_id) DESC, payment_type
            ) AS rn
        FROM payments_base
        GROUP BY customer_unique_id, payment_type
    ) x
    WHERE rn = 1
),

/* 9) Reviews */
reviews_base AS (
    SELECT
        c.customer_unique_id,
        r.order_id,
        r.review_score
    FROM dbo.order_reviews r
    INNER JOIN dbo.orders o
        ON o.order_id = r.order_id
    INNER JOIN dbo.customers c
        ON c.customer_id = o.customer_id
),

reviews_agg AS (
    SELECT
        rb.customer_unique_id,
        COUNT(*) AS total_reviews,
        AVG(CAST(rb.review_score AS float)) AS avg_review_score,
        MIN(rb.review_score) AS min_review_score,
        MAX(rb.review_score) AS max_review_score,
        AVG(CASE WHEN rb.review_score <= 2 THEN 1.0 ELSE 0.0 END) AS negative_review_rate,
        AVG(CASE WHEN rb.review_score >= 4 THEN 1.0 ELSE 0.0 END) AS positive_review_rate
    FROM reviews_base rb
    GROUP BY rb.customer_unique_id
),

/* 10) Assemble customer core */
customer_core AS (
    SELECT
        cg.customer_unique_id,
        cg.first_customer_id,
        cg.customer_city,
        cg.customer_state,
        cg.customer_zip_code_prefix,
        cg.customer_latitude,
        cg.customer_longitude,

        oa.first_purchase_date,
        YEAR(oa.first_purchase_date) AS first_purchase_year,
        MONTH(oa.first_purchase_date) AS first_purchase_month,
        oa.acquisition_cohort_month,

        oa.last_purchase_date,
        DATEDIFF(day, oa.first_purchase_date, oa.last_purchase_date) AS customer_lifetime_days,
        DATEDIFF(day, oa.last_purchase_date, p.as_of_date) AS days_since_last_purchase,

        CASE WHEN oa.total_orders >= 2 THEN 1 ELSE 0 END AS is_repeat_buyer_flag,

        /* churn */
        CASE WHEN DATEDIFF(day, oa.last_purchase_date, p.as_of_date) >= p.churn_days THEN 1 ELSE 0 END AS is_churned_flag,

        oa.total_orders,
        oa.delivered_orders,
        oa.canceled_orders,
        oa.undelivered_orders,

        ia.distinct_products_purchased,
        ia.distinct_sellers_purchased,

        CAST(ia.total_items_purchased AS float) / NULLIF(oa.total_orders, 0) AS avg_items_per_order,

        ia.total_revenue,
        ova.avg_order_value,
        ova.min_order_value,
        ova.max_order_value,

        ia.total_freight_value,
        ia.total_freight_value / NULLIF(oa.total_orders, 0) AS avg_freight_per_order,
        ia.total_freight_value / NULLIF(ia.total_revenue, 0) AS freight_to_revenue_ratio,

        pa.total_payment_value,
        pa.avg_installments_per_order,

        oa.active_months_count,
        CAST(oa.total_orders AS float) / NULLIF(oa.active_months_count, 0) AS purchase_frequency_per_month,

        g.avg_days_between_orders,
        fs.first_to_second_order_days,
        g.max_days_between_orders,

        oa.avg_delivery_days,
        dm.median_delivery_days,
        oa.on_time_deliveries,
        oa.late_deliveries,
        CAST(oa.on_time_deliveries AS float) / NULLIF(oa.delivered_orders, 0) AS on_time_delivery_rate,
        CAST(oa.late_deliveries AS float) / NULLIF(oa.delivered_orders, 0) AS late_delivery_rate,
        oa.avg_days_late,

        rv.total_reviews,
        CAST(rv.total_reviews AS float) / NULLIF(oa.delivered_orders, 0) AS review_participation_rate,
        rv.avg_review_score,
        rv.min_review_score,
        rv.max_review_score,
        rv.negative_review_rate,
        rv.positive_review_rate,

        pt.most_used_payment_type,
        CAST(pa.credit_card_orders AS float) / NULLIF(pa.paid_orders, 0) AS credit_card_usage_rate,
        CAST(pa.installment_orders  AS float) / NULLIF(pa.paid_orders, 0) AS installment_usage_rate,

        /* RFM base */
        DATEDIFF(day, oa.last_purchase_date, p.as_of_date) AS recency_days,
        oa.total_orders AS frequency_orders,
        ia.total_revenue AS monetary_value
    FROM cust_geo cg
    CROSS JOIN params p
    LEFT JOIN orders_agg oa  ON oa.customer_unique_id = cg.customer_unique_id
    LEFT JOIN items_agg ia   ON ia.customer_unique_id = cg.customer_unique_id
    LEFT JOIN order_value_agg ova ON ova.customer_unique_id = cg.customer_unique_id
    LEFT JOIN payments_agg pa ON pa.customer_unique_id = cg.customer_unique_id
    LEFT JOIN payment_type_mode pt ON pt.customer_unique_id = cg.customer_unique_id
    LEFT JOIN reviews_agg rv ON rv.customer_unique_id = cg.customer_unique_id
    LEFT JOIN delivery_median dm ON dm.customer_unique_id = cg.customer_unique_id
    LEFT JOIN gaps g ON g.customer_unique_id = cg.customer_unique_id
    LEFT JOIN first_second fs ON fs.customer_unique_id = cg.customer_unique_id
),

/* 11) RFM scores (relative across all customers in the view) */
rfm_scored AS (
    SELECT
        cc.*,

        /* Recency: smaller is better => higher score */
        (6 - NTILE(5) OVER (ORDER BY cc.recency_days ASC)) AS rfm_recency_score,

        /* Frequency: bigger is better => higher score */
        NTILE(5) OVER (ORDER BY cc.frequency_orders ASC) AS rfm_frequency_score,

        /* Monetary: bigger is better => higher score */
        NTILE(5) OVER (ORDER BY cc.monetary_value ASC) AS rfm_monetary_score
    FROM customer_core cc
)
SELECT
    /* 1) Identity & Location */
    customer_unique_id,
    first_customer_id,
    customer_city,
    customer_state,
    customer_zip_code_prefix,
    customer_latitude,
    customer_longitude,

    /* 2) Acquisition & Lifecycle */
    first_purchase_date,
    first_purchase_year,
    first_purchase_month,
    acquisition_cohort_month,
    last_purchase_date,
    customer_lifetime_days,
    days_since_last_purchase,
    is_churned_flag,

    /* 3) Order Behavior */
    total_orders,
    delivered_orders,
    canceled_orders,
    undelivered_orders,
    distinct_products_purchased,
    distinct_sellers_purchased,
    avg_items_per_order,
    is_repeat_buyer_flag,

    /* 4) Monetary Metrics */
    total_revenue,
    avg_order_value,
    min_order_value,
    max_order_value,
    total_freight_value,
    avg_freight_per_order,
    freight_to_revenue_ratio,
    total_payment_value,
    avg_installments_per_order,

    /* 5) Purchase Frequency */
    active_months_count,
    purchase_frequency_per_month,
    avg_days_between_orders,
    first_to_second_order_days,
    max_days_between_orders,

    /* 6) Delivery Performance */
    avg_delivery_days,
    median_delivery_days,
    on_time_deliveries,
    late_deliveries,
    on_time_delivery_rate,
    late_delivery_rate,
    avg_days_late,

    /* 7) Review & Satisfaction */
    total_reviews,
    review_participation_rate,
    avg_review_score,
    min_review_score,
    max_review_score,
    negative_review_rate,
    positive_review_rate,

    /* 8) Payment Behavior */
    most_used_payment_type,
    credit_card_usage_rate,
    installment_usage_rate,

    /* 9) Segmentation Layer */
    recency_days,
    frequency_orders,
    monetary_value,
    rfm_recency_score,
    rfm_frequency_score,
    rfm_monetary_score,

    CASE
        WHEN rfm_recency_score >= 4 AND rfm_frequency_score >= 4 AND rfm_monetary_score >= 4 THEN 'Champions'
        WHEN rfm_frequency_score >= 4 AND rfm_recency_score >= 3 THEN 'Loyal Customers'
        WHEN rfm_recency_score >= 4 AND rfm_frequency_score BETWEEN 2 AND 3 THEN 'Potential Loyalist'
        WHEN rfm_recency_score <= 2 AND rfm_frequency_score >= 3 THEN 'At Risk'
        WHEN rfm_recency_score <= 2 AND rfm_frequency_score <= 2 THEN 'Hibernating'
        ELSE 'Others'
    END AS rfm_segment_label
FROM rfm_scored;
GO
select * from customer_360;