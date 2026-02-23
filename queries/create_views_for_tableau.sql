use [Olist-E-Commerce];
go

/*

1.Obtain the following KPI metrics from the data: total revenue,
total products sold, average order value, average review score, 
positive review rate, average shipping days, average shipping delay.
*/

/* Procedure:
1. Collect everything as order_id level
2. In the final select, apply aggregations for order level calculations
*/
create or alter view kpi_metrics as
with dataset_max_date as (
	select max(order_purchase_timestamp) as reference_day from orders
),

order_payments_agg as (
	select
		order_id,
		sum(payment_value) as total_order_payment
	from payments
	group by order_id 
),

order_items_agg as (
	select 
		order_id,
		count(product_id) as total_products
	from order_items
	group by order_id
)

select
	-- total revenue
	round(sum(case when ord.order_status not in ('canceled', 'unavailable') then 
				opa.total_order_payment else 0 end), 2) as total_revenue,
				
	-- total products sold
	sum(case when ord.order_status not in ('canceled', 'unavailable') then 
				oia.total_products else 0 end) as total_products_sold,

	-- average order value
    ROUND(
        SUM(CASE WHEN ord.order_status NOT IN ('canceled', 'unavailable') THEN opa.total_order_payment ELSE 0 END) / 
        NULLIF(COUNT(DISTINCT CASE WHEN ord.order_status NOT IN ('canceled', 'unavailable') THEN ord.order_id END), 0), 
    2) AS avg_order_value,

	-- average review score
    ROUND(AVG(CAST(r.review_score AS FLOAT)), 2) AS avg_review_score,

	-- positive review rate
    ROUND(
        100.0 * COUNT(CASE WHEN r.review_score >= 4 THEN 1 END) / 
        NULLIF(COUNT(r.review_id), 0), 
    2) AS positive_review_rate,

	-- average shipping days
    ROUND(AVG(
        CASE WHEN ord.order_status = 'delivered' AND ord.order_delivered_customer_date IS NOT NULL 
        THEN CAST(DATEDIFF(DAY, ord.order_purchase_timestamp, ord.order_delivered_customer_date) AS FLOAT)
        END
    ), 1) AS avg_shipping_days,

	-- average shipping delay
    ROUND(AVG(
        CASE WHEN ord.order_status = 'delivered' 
             AND ord.order_delivered_customer_date > ord.order_estimated_delivery_date 
        THEN CAST(DATEDIFF(DAY, ord.order_estimated_delivery_date, ord.order_delivered_customer_date) AS FLOAT)
        END
    ), 1) AS avg_shipping_delay_days
from orders ord
cross join dataset_max_date as dmd
join customers cus on cus.customer_id = ord.customer_id
left join order_payments_agg opa on opa.order_id = ord.order_id 
left join order_items_agg oia on oia.order_id = ord.order_id 
left join order_reviews r on r.order_id = ord.order_id;
go


/*
2. Categorize the customers into one-time buyer and repeat buyer. 
Find the number of customers for each category' */
create or alter view customer_category as 
WITH customer_order_counts AS (
    -- Step 1: Count total orders per unique customer identity
    SELECT 
        c.customer_unique_id,
        COUNT(o.order_id) as total_orders
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status not in ('canceled', 'unavailable') -- Excluding canceled orders for accurate behavior analysis
    GROUP BY c.customer_unique_id
),
customer_classification AS (
    -- Step 2: Categorize based on the business rule provided
    SELECT 
        customer_unique_id,
        total_orders,
        CASE 
            WHEN total_orders >= 2 THEN 'Repeat Buyer'
            ELSE 'One-Time Buyer'
        END AS customer_category
    FROM customer_order_counts
)
-- Step 3: Aggregate for Dashboard Summary
SELECT 
    customer_category,
    COUNT(customer_unique_id) AS customer_count,
    ROUND(100.0 * COUNT(customer_unique_id) / SUM(COUNT(customer_unique_id)) OVER(), 2) AS percentage_of_total
FROM customer_classification
GROUP BY customer_category;
go


/*
3. number of orders for each order status */ 
create or alter view order_category as 
select
    order_status, 
    count(order_id) as total_orders
from orders 
group by order_status;
go


/* 
4. number of orders for each review score*/
create or alter view order_cat_by_scores as
select
    isnull(cast(r.review_score as varchar(10)), 'No Score') as review_score,
    count(distinct o.order_id) as total_orders
from orders o
left join order_reviews r on r.order_id = o.order_id 
group by cast(r.review_score as varchar(10));

go
    

/*
5. number of sellers for each review score */
create or alter view sellers_categories as 
SELECT
    ISNULL(CAST(r.review_score AS VARCHAR(10)), 'No Score') AS review_score_label,
    -- Use COUNT DISTINCT so a seller is only counted once per score category
    COUNT(DISTINCT oi.seller_id) AS total_unique_sellers
FROM orders o 
JOIN order_items oi ON oi.order_id = o.order_id
LEFT JOIN order_reviews r ON o.order_id = r.order_id 
GROUP BY 
    ISNULL(CAST(r.review_score AS VARCHAR(10)), 'No Score')
go


/* 6. find number of orders for each payment type and avg review score */ 
create or alter view payment_type_categories as 
WITH unique_order_reviews AS (
    -- Step 1: Get exactly one average review score per order
    SELECT 
        order_id, 
        AVG(CAST(review_score AS FLOAT)) as avg_order_score
    FROM order_reviews
    GROUP BY order_id
)
SELECT 
    p.payment_type,
    -- Count of unique orders per payment type
    COUNT(DISTINCT p.order_id) AS total_orders,
    -- Average of the pre-aggregated scores
    ROUND(AVG(r.avg_order_score), 2) AS avg_review_score
FROM payments p
JOIN orders o ON p.order_id = o.order_id
LEFT JOIN unique_order_reviews r ON o.order_id = r.order_id
GROUP BY p.payment_type;
go


/* 
7. For each year-month pair (“yyyy-MM”) find the revenue (with MoM Growth % at some points),
number of new customers monthly,
number of successful orders and number of unsuccessful orders.*/

/* Monthly Performance Trends:
This query calculates monthly revenue, new customer acquisition, and order success rates.
It uses Window Functions to calculate Month-over-Month (MoM) Revenue growth.
*/
create or alter view year_monthly_metrics as
WITH monthly_metrics AS (
    -- Step 1: Aggregate core metrics by month
    SELECT 
        FORMAT(o.order_purchase_timestamp, 'yyyy-MM') AS year_month,
        -- Revenue from non-canceled orders
        SUM(CASE WHEN o.order_status NOT IN ('canceled', 'unavailable') THEN p.payment_value ELSE 0 END) AS monthly_revenue,
        -- Count of successful orders
        COUNT(DISTINCT CASE WHEN o.order_status NOT IN ('canceled', 'unavailable') THEN o.order_id END) AS successful_orders,
        -- Count of unsuccessful orders
        COUNT(DISTINCT CASE WHEN o.order_status IN ('canceled', 'unavailable') THEN o.order_id END) AS unsuccessful_orders
    FROM orders o
    LEFT JOIN (
        -- Pre-aggregating payments to avoid duplication
        SELECT order_id, SUM(payment_value) as payment_value 
        FROM payments 
        GROUP BY order_id
    ) p ON o.order_id = p.order_id
    GROUP BY FORMAT(o.order_purchase_timestamp, 'yyyy-MM')
),
customer_first_purchase AS (
    -- Step 2: Identify when each unique customer made their first purchase
    SELECT 
        c.customer_unique_id,
        MIN(FORMAT(o.order_purchase_timestamp, 'yyyy-MM')) AS first_purchase_month
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
),
new_customers_monthly AS (
    -- Step 3: Count new customers per month
    SELECT 
        first_purchase_month AS year_month,
        COUNT(customer_unique_id) AS new_customers
    FROM customer_first_purchase
    GROUP BY first_purchase_month
)
-- Step 4: Final Assembly with MoM Growth calculation
SELECT 
    m.year_month,
    ROUND(m.monthly_revenue, 2) AS revenue,
    -- MoM Growth %: ((Current - Previous) / Previous) * 100
    ROUND(
        100.0 * (m.monthly_revenue - LAG(m.monthly_revenue) OVER (ORDER BY m.year_month)) / 
        NULLIF(LAG(m.monthly_revenue) OVER (ORDER BY m.year_month), 0), 
    2) AS revenue_mom_growth_pct,
    ISNULL(n.new_customers, 0) AS new_customers,
    m.successful_orders,
    m.unsuccessful_orders
FROM monthly_metrics m
LEFT JOIN new_customers_monthly n ON m.year_month = n.year_month;
go


/*
8.  Sort the sellers by the revenue they got and categorize it by review scores. 
Visualize it with bar charts.
*/

/* Seller Performance Analysis by Region Code:
This query calculates the total product revenue, number of distinct sellers, 
and average review score grouped by a composite seller_code (State-City-Zip).
It also includes total orders, total reviews, and the requested review rate.
*/

create or alter view sellers_performance as
WITH order_reviews_agg AS (
    -- Step 1: Pre-aggregate reviews to the order level to prevent fan-out duplication
    SELECT 
        order_id,
        AVG(CAST(review_score AS FLOAT)) AS avg_order_score,
        COUNT(review_id) AS review_count -- Counting actual reviews per order
    FROM order_reviews
    GROUP BY order_id
)
SELECT 
    -- Create the composite seller_code (Using CONCAT to safely handle different data types)
    CONCAT(s.seller_state, '-', s.seller_city, '-', s.seller_zip_code_prefix) AS seller_code,
    
    -- Count how many distinct sellers fall into this specific code
    COUNT(DISTINCT s.seller_id) AS total_distinct_sellers,
    
    -- Total orders fulfilled by sellers in this code
    COUNT(DISTINCT oi.order_id) AS total_orders,
    
    -- Total number of reviews received for those orders
    ISNULL(SUM(r.review_count), 0) AS total_reviews,
    
    -- Review Rate (Calculated as reviews / total orders)
    -- The CAST to FLOAT must happen BEFORE the division to prevent Integer Division truncation
    ROUND(CAST(ISNULL(SUM(r.review_count), 0) AS FLOAT) / NULLIF(COUNT(DISTINCT oi.order_id), 0), 2) AS review_rate,
    
    -- Calculate regional revenue strictly from product price (excluding freight)
    ROUND(SUM(oi.price), 2) AS total_revenue,
    
    -- Average the review scores tied to the orders from this code
    ROUND(AVG(r.avg_order_score), 2) AS avg_review_score

FROM sellers s
JOIN order_items oi ON s.seller_id = oi.seller_id
JOIN orders o ON oi.order_id = o.order_id
LEFT JOIN order_reviews_agg r ON o.order_id = r.order_id
WHERE o.order_status NOT IN ('canceled', 'unavailable') -- Only count successful sales
GROUP BY 
    CONCAT(s.seller_state, '-', s.seller_city, '-', s.seller_zip_code_prefix);
go


/*
9. For each customer city and seller city pairs, find the average shipping days.  */

/* Average Shipping Days by City Pairs:
This query calculates the average time it takes for an order to travel 
from a seller's city to a customer's city. It is designed for a barbell/network chart.
*/

WITH unique_order_routes AS (
    -- Step 1: Identify unique routes per order to avoid duplicating 
    -- shipping times for orders with multiple items from the same seller.
    SELECT DISTINCT
        o.order_id,
        c.customer_city,
        s.seller_city,
        o.order_purchase_timestamp,
        o.order_delivered_customer_date
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN sellers s ON oi.seller_id = s.seller_id
    WHERE o.order_status = 'delivered' 
      AND o.order_delivered_customer_date IS NOT NULL
)
SELECT 
    seller_city,
    customer_city,
    -- Create a combined route name for easy labeling in Tableau
    CONCAT(seller_city, ' -> ', customer_city) AS route_name,
    
    -- Count the volume of orders on this specific route
    COUNT(order_id) AS total_deliveries,
    
    -- Calculate Average Shipping Days
    -- CAST to FLOAT prevents integer division truncation in SQL Server
    ROUND(AVG(CAST(DATEDIFF(DAY, order_purchase_timestamp, order_delivered_customer_date) AS FLOAT)), 1) AS avg_shipping_days

FROM unique_order_routes
GROUP BY 
    seller_city,
    customer_city;
go







