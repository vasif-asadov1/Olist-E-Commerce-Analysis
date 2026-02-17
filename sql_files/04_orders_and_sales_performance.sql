use [Olist-E-Commerce];
go



-- Question 1. 

with monthly_sales as (
    -- step 1: aggregate core metrics by month
    -- we use the calendar table to ensure clean date grouping
    select 
        c.year,
        c.month_number,
        c.month_name,
        count(distinct o.order_id) as total_orders,
        sum(p.payment_value) as total_revenue
    from 
        orders o
    inner join 
        payments p on o.order_id = p.order_id
    inner join 
        Calendar c on o.purchase_datekey = c.datekey
    where 
        o.order_status not in ('canceled', 'unavailable')
    group by 
        c.year, c.month_number, c.month_name
),

growth_metrics as (
    -- step 2: use lag() to fetch values from the previous month and previous year
    select 
        *,
        -- previous month values
        prev_month_orders = lag(total_orders) over (order by year, month_number),
        prev_month_revenue = lag(total_revenue) over (order by year, month_number),
        
        -- previous year values (offset of 12 rows)
        prev_year_orders = lag(total_orders, 12) over (order by year, month_number),
        prev_year_revenue = lag(total_revenue, 12) over (order by year, month_number)
    from 
        monthly_sales
)

-- final output: calculating percentage growth
select 
    year,
    month_name,
    total_orders,
    total_revenue,
    
    -- month-over-month (mom) growth
    mom_revenue_growth_pct = cast(100.0 * (total_revenue - prev_month_revenue) / nullif(prev_month_revenue, 0) as decimal(10,2)),
    
    -- year-over-year (yoy) growth
    yoy_revenue_growth_pct = cast(100.0 * (total_revenue - prev_year_revenue) / nullif(prev_year_revenue, 0) as decimal(10,2)),
    
    -- identifying seasonal spikes
    case 
        when month_number = 11 then 'Black Friday Period'
        when month_number = 12 then 'Holiday Season'
        when month_number = 1 then 'New Year Peak'
        else 'Standard Period'
    end as seasonality_tag
from 
    growth_metrics
order by 
    year, month_number;
go


-- Question 2. 

/*> "Which product categories constitute the top 20% of sales volume, and do they align with 
the top 20% of revenue generators? Can we identify 'High Volume / Low Value' categories versus
'Low Volume / High Value' (Niche/Luxury) categories?" */

/* 
objective: identify top 20% categories by revenue vs volume and classify business niches
logic: 
    1. aggregate revenue and quantity 
    2. use percent_rank() to find the top 20% percentile for both metrics
    3. cross-analyze metrics to find high-volumne vs high-value categories
*/

with category_metrics as  (
    select 
        products.product_category_name,
        count(order_items.order_item_id) as  total_volume,
        sum(order_items.price) as total_revenue       
    from 
        order_items
    inner join 
        products on products.product_id = order_items.product_id
    inner join 
        orders on orders.order_id = order_items.order_id
    where
        orders.order_status not in ('canceled', 'unavailable')
            and products.product_category_name is not null 
    group by 
        products.product_category_name
), 

category_rankings as (
    select
        *,
        percent_rank() over (order by total_volume desc) as volume_percentile,
        percent_rank() over (order by total_revenue desc) as revenue_percentile
    from  
        category_metrics
)

select
    product_category_name,
    total_volume,
    total_revenue,
    cast( total_revenue / total_volume as decimal(10,2)) as avg_unit_price,
    case
        when volume_percentile <= 0.20 and revenue_percentile <= 0.20 then 'High Vol / High Rev'
        when volume_percentile <= 0.20 and revenue_percentile > 0.20 then 'High Vol / Low Rev'
        when volume_percentile > 0.20 and revenue_percentile <= 0.20 then 'Low Vol / High Rev'
        else 'Standard'
    end as category_segmentation
from 
    category_rankings
order by 
    total_revenue desc;
go 


-- QUESTION 3 
/*"Can we calculate the 3-month rolling average for total revenue to smooth out daily and weekly volatility?
How does this long-term trendline compare to the raw sales data in identifying the true direction of business growth?"*/

/* 3 month rolling revenue analysis
objective: smooth out noise to identify underlying business growth trends
logic: 
    1. aggregate total revenue by month
    2. use window function with rows_between to calculate 3-month moving average
    3. compare raw revenue vs the smoothed trendline
*/

with monthly_revenue as (
    select
        Calendar.year, 
        Calendar.month_number,
        Calendar.month_name,
        sum(payments.payment_value) as raw_monthly_revenue
    from 
        orders 
    inner join 
        payments on payments.order_id = orders.order_id 
    inner join 
        Calendar on Calendar.datekey = orders.purchase_datekey
    where 
        orders.order_status not in ('canceled', 'unavailable')
    group by 
        Calendar.year, calendar.month_number, Calendar.month_name
)

select 
    [year], 
    month_number,
    month_name,
    raw_monthly_revenue,

    -- average the current month and 2 preceding (last) months
    cast (avg(raw_monthly_revenue) over (order by [year], month_number 
            rows between 2 preceding and current row) as decimal(10,3)) as rolling_avg_3m,

    -- calculate deviation from the trend = (current_month - rolling_avg_3m) / current_month * 100.0 = var_dev %
    cast(100.0 * (raw_monthly_revenue - avg(raw_monthly_revenue) over (order by [year], month_number 
            rows between 2 preceding and current row)) / nullif(raw_monthly_revenue,0) as decimal (10,2)) as variance_from_trend
from 
    monthly_revenue
group by 
    [year], 
    month_number, 
    month_name,
    raw_monthly_revenue
order by
    [year], month_number;
go

-- QUESTION 4.
/*
> "How is revenue distributed across different states (`customer_state`) and cities? specifically, identifying the top 5 regions 
with the highest sales density per capita versus regions with high order volume but low total revenue?" */

with region_performance as (
    SELECT
        customers.customer_state,
        customers.customer_city,
        count(distinct orders.order_id) as total_orders,
        sum(payments.payment_value) as total_revenue,
        -- avg order value -> revenue density
        sum(payments.payment_value) / count(distinct orders.order_id) as avg_order_value
    FROM 
        orders
    join   
        customers on customers.customer_id = orders.customer_id
    join 
        payments on payments.order_id = orders.order_id
    where 
        orders.order_status not in ('canceled', 'unavailable')
    group by 
        customers.customer_state,
        customers.customer_city
), 

region_rankings as (
    select 
        *,
        rank() over (order by total_revenue desc) as revenue_rank, 
        rank() over ( order by total_orders desc) as volume_rank
    from 
        region_performance
)

select 
    customer_state,
    customer_city,
    total_orders,
    total_revenue,
    cast(avg_order_value as decimal(10,2)) as avg_order_value,
    case 
        when revenue_rank <= 10 and volume_rank <= 10 then 'Major Economic Hub (High Vol / High Rev)'
        when revenue_rank <= 20 and volume_rank > 50 then 'Affluent Niche (Low Vol / High Rev)'
        when revenue_rank <= 10 and volume_rank <= 10 then 'Mass Market (High Vol / Low Rev)'
        else 'Standard Market'
    end as regional_profile
from 
    region_rankings
order by 
    total_revenue desc;
go



-- QUESTION 5.

/* aov and basket size correlation analysis
    objective: analyze the relationship between total spend and items per order over time
    logic: 
      1. aggregate items and prices at the order level first (to prevent join duplication).
      2. join with payments to get the true total value.
      3. aggregate by month to calculate aov and average basket size.
    granularity: year_month
*/

with order_item_totals as (
    -- step 1: calculate total items and total price per order
    -- this prevents duplication before joining with payments
    select 
        order_id,
        count(order_item_id) as items_in_basket,
        sum(price) as total_items_price
    from 
        order_items
    group by 
        order_id
),

order_payment_totals as (
    -- step 2: calculate total payment value per order 
    -- (accounts for multi-payment methods/installments)
    select 
        order_id,
        sum(payment_value) as total_order_payment
    from 
        payments
    group by 
        order_id
),

monthly_metrics as (
    -- step 3: aggregate metrics by month
    select 
        c.year,
        c.month_number,
        c.month_name,
        count(o.order_id) as total_orders,
        sum(p.total_order_payment) as monthly_revenue,
        sum(i.items_in_basket) as monthly_items_count
    from 
        orders o
    inner join 
        Calendar c on o.purchase_datekey = c.datekey
    inner join 
        order_item_totals i on o.order_id = i.order_id
    inner join 
        order_payment_totals p on o.order_id = p.order_id
    where 
        o.order_status not in ('canceled', 'unavailable')
    group by 
        c.year, c.month_number, c.month_name
)

-- final output: calculating aov and avg basket size trends
select 
    year,
    month_name,
    total_orders,
    -- aov: total revenue / total orders
    cast(monthly_revenue / total_orders as decimal(10,2)) as aov,
    -- avg basket size: total items / total orders
    cast(monthly_items_count * 1.0 / total_orders as decimal(10,2)) as avg_basket_size,
    -- item value proxy: aov / avg basket size (average price per item)
    cast((monthly_revenue / total_orders) / (monthly_items_count * 1.0 / total_orders) as decimal(10,2)) as avg_price_per_item
from 
    monthly_metrics
order by 
    year, month_number;
GO 

