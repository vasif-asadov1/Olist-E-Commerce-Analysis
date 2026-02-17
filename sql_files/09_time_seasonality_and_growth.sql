use [Olist-E-Commerce];
go

-- QUESTION 1.
/*
"What is the Month-over-Month (MoM) growth rate for total revenue across the entire dataset? 
Can we identify specific months where the business experienced 'Hyper-Growth' (\>20% increase) 
versus months of stagnation or contraction?"*/

/* growth and seasonality analysis
    objective: calculate mom and yoy growth rates for revenue and order volume
    logic: 
      1. aggregate revenue and order counts by month.
      2. use lag() window function to compare current month vs prior month and prior year.
      3. calculate percentage growth rates and classify performance tiers.
    granularity: year_month
*/

with monthly_sales as (
    -- step 1: aggregate core metrics by month
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
),

final_calculations as (
    -- step 3: calculate percentage growth
    select 
        *,
        mom_revenue_growth_pct = cast(100.0 * (total_revenue - prev_month_revenue) / nullif(prev_month_revenue, 0) as decimal(10,2)),
        yoy_revenue_growth_pct = cast(100.0 * (total_revenue - prev_year_revenue) / nullif(prev_year_revenue, 0) as decimal(10,2))
    from 
        growth_metrics
)

-- final output: categorizing growth performance levels and seasonality
select 
    year,
    month_name,
    total_orders,
    total_revenue,
    mom_revenue_growth_pct,
    
    -- identifying growth tiers as requested
    case 
        when mom_revenue_growth_pct > 20 then 'Hyper-Growth (>20%)'
        when mom_revenue_growth_pct > 0 then 'Positive Growth'
        when mom_revenue_growth_pct <= 0 then 'Stagnation / Contraction'
        else 'Baseline (No Prior Month)'
    end as growth_performance_tag,
    
    -- identifying seasonal spikes
    case 
        when month_number = 11 then 'Black Friday Period'
        when month_number = 12 then 'Holiday Season'
        when month_number = 1 then 'New Year Peak'
        else 'Standard Period'
    end as seasonality_tag
from 
    final_calculations
order by 
    year, month_number;
go


-- QUESTION 2.
/*
"How does the revenue of specific months compare across different years (e.g., Jan 2017 vs. Jan 2018)? 
Can we observe a consistent 'Seasonality Effect' where certain months (like November) consistently
outperform others regardless of the year?"
*/
/* growth and seasonality analysis
    objective: 
        1. compare specific months across years (e.g., Jan 2017 vs Jan 2018).
        2. calculate a 'seasonality index' to identify recurring monthly trends.
    logic: 
      - aggregate revenue by year and month.
      - use window functions to compare same-month performance across years.
      - calculate the deviation of each month from its year's average to find the 'seasonal push'.
*/

with monthly_revenue_base as (
    -- step 1: aggregate total revenue by year and month
    select 
        c.year,
        c.month_number,
        c.month_name,
        sum(p.payment_value) as monthly_revenue
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

seasonal_indexing as (
    -- step 2: calculate year-over-year same-month comparisons and yearly averages
    select 
        *,
        -- direct comparison: revenue of the same month in the previous year
        prev_year_same_month_rev = lag(monthly_revenue) over (
            partition by month_number 
            order by year
        ),
        -- average monthly revenue for that specific year (benchmark)
        yearly_avg_monthly_rev = avg(monthly_revenue) over (
            partition by year
        )
    from 
        monthly_revenue_base
)

-- final output: quantifying the seasonality effect
select 
    year,
    month_name,
    cast(monthly_revenue as decimal(15,2)) as current_month_revenue,
    
    -- yoy comparison for the specific month
    cast(100.0 * (monthly_revenue - prev_year_same_month_rev) / nullif(prev_year_same_month_rev, 0) as decimal(10,2)) as month_specific_yoy_growth_pct,
    
    -- seasonality index: revenue / yearly average
    -- index > 1.0 means the month outperforms the year's average
    cast(monthly_revenue / nullif(yearly_avg_monthly_rev, 0) as decimal(10,2)) as seasonality_index,
    
    -- classification of the month's role in the business cycle
    case 
        when (monthly_revenue / yearly_avg_monthly_rev) >= 1.2 then 'Peak Month (Strong Seasonality)'
        when (monthly_revenue / yearly_avg_monthly_rev) between 0.9 and 1.2 then 'Standard Performance'
        when (monthly_revenue / yearly_avg_monthly_rev) < 0.9 then 'Low Season / Slack Period'
        else 'Baseline'
    end as seasonal_classification
from 
    seasonal_indexing
order by 
    year, month_number;
go


-- QUESTION 3.
/*"What is the distribution of order volume across different **Days of the Week** and **Hours of the Day**?
Specifically, do we see a 'Lunchtime Spike' (12 PM - 2 PM) or an 'Evening Spike' (8 PM - 10 PM)?"	
*/

/* growth and seasonality analysis
    objective: 
        1. compare specific months across years (e.g., Jan 2017 vs Jan 2018).
        2. calculate a 'seasonality index' to identify recurring monthly trends.
        3. analyze order distribution by Day of the Week and Hour of Day.
    logic: 
      - aggregate revenue by year and month for high-level trends.
      - use window functions for year-over-year same-month comparisons.
      - extract time-of-day and day-of-week metrics to find peak engagement windows.
*/

with monthly_revenue_base as (
    -- step 1: aggregate total revenue by year and month
    select 
        c.year,
        c.month_number,
        c.month_name,
        sum(p.payment_value) as monthly_revenue
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

seasonal_indexing as (
    -- step 2: calculate year-over-year same-month comparisons and yearly averages
    select 
        *,
        -- direct comparison: revenue of the same month in the previous year
        prev_year_same_month_rev = lag(monthly_revenue) over (
            partition by month_number 
            order by year
        ),
        -- average monthly revenue for that specific year (benchmark)
        yearly_avg_monthly_rev = avg(monthly_revenue) over (
            partition by year
        )
    from 
        monthly_revenue_base
),

-- step 3: analyzing hourly and weekly volume distribution
time_of_day_stats as (
    select 
        datename(dw, order_purchase_timestamp) as day_of_week,
        datepart(dw, order_purchase_timestamp) as day_num, -- used for sorting
        datepart(hour, order_purchase_timestamp) as hour_of_day,
        count(order_id) as total_orders
    from 
        orders
    where 
        order_status not in ('canceled', 'unavailable')
    group by 
        datename(dw, order_purchase_timestamp),
        datepart(dw, order_purchase_timestamp),
        datepart(hour, order_purchase_timestamp)
)

-- final output: combining the original seasonality analysis with the new time-of-day insights
-- part 1: monthly seasonality (existing)
select 
    year,
    month_name,
    cast(monthly_revenue as decimal(15,2)) as current_month_revenue,
    
    -- yoy comparison for the specific month
    cast(100.0 * (monthly_revenue - prev_year_same_month_rev) / nullif(prev_year_same_month_rev, 0) as decimal(10,2)) as month_specific_yoy_growth_pct,
    
    -- seasonality index
    cast(monthly_revenue / nullif(yearly_avg_monthly_rev, 0) as decimal(10,2)) as seasonality_index,
    
    case 
        when (monthly_revenue / yearly_avg_monthly_rev) >= 1.2 then 'Peak Month (Strong Seasonality)'
        when (monthly_revenue / yearly_avg_monthly_rev) between 0.9 and 1.2 then 'Standard Performance'
        when (monthly_revenue / yearly_avg_monthly_rev) < 0.9 then 'Low Season / Slack Period'
        else 'Baseline'
    end as seasonal_classification
from 
    seasonal_indexing

union all

-- part 2: placeholder/separator row for clear data interpretation if exported
select 
    null, '--- INTRA-DAY ANALYSIS ---', null, null, null, null

union all

-- part 3: day/hour distribution
select 
    day_num as year, -- repurposing columns for the union's schema
    concat(day_of_week, ' at ', hour_of_day, ':00') as month_name,
    total_orders as current_month_revenue,
    null as month_specific_yoy_growth_pct,
    null as seasonality_index,
    case 
        when hour_of_day between 12 and 14 then 'Lunchtime Spike Window'
        when hour_of_day between 20 and 22 then 'Evening Spike Window'
        else 'Standard Time'
    end as seasonal_classification
from 
    time_of_day_stats
order by 
    year, month_name;
go




-- QUESTION 4.
/*
"What is the cumulative revenue generated over time since the inception of the platform? 
By plotting the running total of sales, can we visually confirm the business's transition from 'Linear Growth
' to 'Exponential Growth' (The Hockey Stick Curve)?"
*/

/* growth and seasonality analysis
    objective: 
        1. compare specific months across years (e.g., Jan 2017 vs Jan 2018).
        2. calculate a 'seasonality index' to identify recurring monthly trends.
        3. analyze order distribution by Day of the Week and Hour of Day.
        4. calculate cumulative revenue to track "The Hockey Stick" growth curve.
    logic: 
      - aggregate revenue by year and month for high-level trends.
      - use window functions for year-over-year and running total calculations.
      - extract time-of-day and day-of-week metrics to find peak engagement windows.
*/

with monthly_revenue_base as (
    -- step 1: aggregate total revenue by year and month
    select 
        c.year,
        c.month_number,
        c.month_name,
        sum(p.payment_value) as monthly_revenue
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

seasonal_indexing as (
    -- step 2: calculate YoY comparisons, yearly averages, and cumulative running total
    select 
        *,
        -- direct comparison: revenue of the same month in the previous year
        prev_year_same_month_rev = lag(monthly_revenue) over (
            partition by month_number 
            order by year
        ),
        -- average monthly revenue for that specific year (benchmark)
        yearly_avg_monthly_rev = avg(monthly_revenue) over (
            partition by year
        ),
        -- cumulative revenue: running total since the platform inception
        running_total_revenue = sum(monthly_revenue) over (
            order by year, month_number
        )
    from 
        monthly_revenue_base
),

-- step 3: analyzing hourly and weekly volume distribution
time_of_day_stats as (
    select 
        datename(dw, order_purchase_timestamp) as day_of_week,
        datepart(dw, order_purchase_timestamp) as day_num, -- used for sorting
        datepart(hour, order_purchase_timestamp) as hour_of_day,
        count(order_id) as total_orders
    from 
        orders
    where 
        order_status not in ('canceled', 'unavailable')
    group by 
        datename(dw, order_purchase_timestamp),
        datepart(dw, order_purchase_timestamp),
        datepart(hour, order_purchase_timestamp)
)

-- final output: combining the original seasonality analysis with the new running total and time-of-day insights
-- part 1: monthly seasonality and cumulative growth
select 
    year,
    month_name,
    cast(monthly_revenue as decimal(15,2)) as current_month_revenue,
    cast(running_total_revenue as decimal(15,2)) as cumulative_revenue,
    
    -- yoy comparison for the specific month
    cast(100.0 * (monthly_revenue - prev_year_same_month_rev) / nullif(prev_year_same_month_rev, 0) as decimal(10,2)) as month_specific_yoy_growth_pct,
    
    -- seasonality index
    cast(monthly_revenue / nullif(yearly_avg_monthly_rev, 0) as decimal(10,2)) as seasonality_index,
    
    case 
        when (monthly_revenue / yearly_avg_monthly_rev) >= 1.2 then 'Peak Month (Strong Seasonality)'
        when (monthly_revenue / yearly_avg_monthly_rev) between 0.9 and 1.2 then 'Standard Performance'
        when (monthly_revenue / yearly_avg_monthly_rev) < 0.9 then 'Low Season / Slack Period'
        else 'Baseline'
    end as seasonal_classification
from 
    seasonal_indexing

union all

-- part 2: placeholder/separator row
select 
    null, '--- INTRA-DAY ANALYSIS ---', null, null, null, null, null

union all

-- part 3: day/hour distribution
select 
    day_num as year,
    concat(day_of_week, ' at ', hour_of_day, ':00') as month_name,
    total_orders as current_month_revenue,
    null as cumulative_revenue,
    null as month_specific_yoy_growth_pct,
    null as seasonality_index,
    case 
        when hour_of_day between 12 and 14 then 'Lunchtime Spike Window'
        when hour_of_day between 20 and 22 then 'Evening Spike Window'
        else 'Standard Time'
    end as seasonal_classification
from 
    time_of_day_stats
order by 
    year, month_name;
go

