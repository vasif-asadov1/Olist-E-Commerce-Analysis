use [Olist-E-Commerce];
go


/* QUESTION 1: 
	"Can we segment the customer base into distinct clusters—specifically 'Champions', 'Loyalists', 
	'Hibernating', and 'At Risk'—by scoring each unique user based on the Recency of their last order, 
	the Frequency of their purchases, and their total Monetary contribution?"
*/

with dataset_max_date as (
	-- find the last order date in the dataset - reference date
	select
		max(order_purchase_timestamp) as max_date
	from 
		orders
),

customer_rfm_base as (
	-- calculate rfm values for each unique customer
	select
		customers.customer_unique_id,
		max(orders.order_purchase_timestamp) as last_order_date,
		count(distinct orders.order_id) as frequency_count,
		sum(payments.payment_value) as monetary_value,
		dmd.max_date
	from 
		orders 
	inner join 
		customers on customers.customer_id = orders.customer_id
	inner join 
		payments on orders.order_id = payments.order_id
	cross join 
		dataset_max_date dmd
	where 
		orders.order_status = 'delivered'
	group by
		customers.customer_unique_id, 
		dmd.max_date
),

rfm_scores as (
	-- assigning scores from 1 to 5 using ntile window function
	-- 5 is the best score, 1 is the worst
	select
		customer_unique_id,
		frequency_count, 
		monetary_value,
		DATEDIFF(day, last_order_date, max_date) as recency_days, 

		-- recency score: lower_days = better score (5)
		-- descending order -> larger days will get lower ntile
		ntile(5) over (order by DATEDIFF(day, last_order_date, max_date) desc) as r_score,

		-- frequency score: higher count = better score
		ntile(5) over (order by frequency_count asc)  as f_score,

		-- monetary score: higher value = better score
		ntile(5) over (order by monetary_value asc) as m_score

	from 
		customer_rfm_base
),

rfm_segments as (
	-- group the scores into segments
	select
		customer_unique_id,
		recency_days,
		frequency_count,
		monetary_value,
		r_score, 
		f_score,
		m_score, 
		case
			when r_score >= 4 and (f_score + m_score) / 2 >= 4 then 'Champions'
			when r_score >= 3 and (f_score + m_score) / 2 >= 3 then 'Loyal Customers'
			when r_score <= 2 and (f_score + m_score) / 2 >= 4 then 'At Risk'
			when r_score <= 2 and (f_score + m_score) / 2 <= 2 then 'Hibernating'
			else 'Potential Loyalist'
		end as customer_segment
	from 
		rfm_scores
)

select
	customer_segment, 
	count(customer_unique_id) as customer_count,
	cast(avg(r_score * 1.0) as decimal(5,2)) as avg_recency_score,
	cast(avg(f_score * 1.0) as decimal(5,2)) as avg_frequency_score, 
	cast(avg(m_score * 1.0) as decimal(5,2)) as avg_monetary_score, 
	cast(avg(recency_days * 1.0) as int) as avg_days_since_last_order,
	cast(avg(frequency_count * 1.0) as int) as avg_frequency_count,
    cast(avg(monetary_value) as decimal(10,2)) as avg_lifetime_spend
from 
	rfm_segments
group by 
	customer_segment
order by 
	customer_count desc;
go 


/* QUESTION 2:
	"How does customer retention evolve over time when users are grouped by their acquisition month? 
	Specifically, what percentage of customers acquired in a specific month (e.g., Jan 2017) 
	return to make a second purchase within months 1, 3, and 6?"


cohort retention analysis 
    objective: measure the percentage of customers who return for repeat purchases over a 6-month period
    granularity: acquisition_month (cohort) and month_index (time elapsed)
*/

with customer_first_purchase as (
    -- step 1: identify the acquisition month (birth month) for every unique customer
    select 
        c.customer_unique_id,
        min(datefromparts(year(o.order_purchase_timestamp), month(o.order_purchase_timestamp), 1)) as cohort_month
    from 
        orders o
    inner join 
        customers c on o.customer_id = c.customer_id
    where 
        o.order_status not in ('canceled', 'unavailable')
    group by 
        c.customer_unique_id
),

cohort_activities as (
    -- step 2: join all orders back to the birth month to see when they returned
    select 
        fp.customer_unique_id,
        fp.cohort_month,
        datediff(month, fp.cohort_month, datefromparts(year(o.order_purchase_timestamp), month(o.order_purchase_timestamp), 1)) as month_index
    from 
        orders o
    inner join 
        customers c on o.customer_id = c.customer_id
    inner join 
        customer_first_purchase fp on c.customer_unique_id = fp.customer_unique_id
    where 
        o.order_status not in ('canceled', 'unavailable')
),

cohort_sizes as (
    -- step 3: calculate the denominator (total customers acquired in each month)
    select 
        cohort_month,
        count(distinct customer_unique_id) as total_customers
    from 
        customer_first_purchase
    group by 
        cohort_month
),

retention_counts as (
    -- step 4: count how many unique customers shopped in month 1, 3, and 6
    select 
        cohort_month,
        count(distinct case when month_index = 1 then customer_unique_id end) as month_1_returnees,
        count(distinct case when month_index = 3 then customer_unique_id end) as month_3_returnees,
        count(distinct case when month_index = 6 then customer_unique_id end) as month_6_returnees
    from 
        cohort_activities
    group by 
        cohort_month
)

-- final output: calculate retention percentages
-- we filter for cohorts with > 10 customers to remove statistically insignificant beta testing months (late 2016)
select 
    r.cohort_month,
    s.total_customers as cohort_size,
    cast(100.0 * r.month_1_returnees / s.total_customers as decimal(5,2)) as month_1_retention_pct,
    cast(100.0 * r.month_3_returnees / s.total_customers as decimal(5,2)) as month_3_retention_pct,
    cast(100.0 * r.month_6_returnees / s.total_customers as decimal(5,2)) as month_6_retention_pct
from 
    retention_counts r
inner join 
    cohort_sizes s on r.cohort_month = s.cohort_month
where
    s.total_customers > 10
order by 
    r.cohort_month;
go 


/* QUESTION 3 

    "Does the customer base adhere to the '80/20 Rule' (Pareto Principle), 
    where the top 20% of unique customers contribute to 80% of the total revenue? If so, 
    what defines the profile of these top-tier customers?"

revenue concentration analysis (pareto principle)
    objective: determine if the top 20% of customers contribute 80% of revenue
    granularity: customer_unique_id
*/

with customer_revenue as (
    -- step 1: calculate total lifetime spend per unique customer
    select 
        c.customer_unique_id,
        sum(p.payment_value) as total_spend
    from 
        orders o
    inner join 
        customers c on o.customer_id = c.customer_id
    inner join 
        payments p on o.order_id = p.order_id
    where 
        o.order_status not in ('canceled', 'unavailable')
    group by 
        c.customer_unique_id
),

revenue_ranking as (
    -- step 2: rank customers by spend and calculate cumulative totals
    select 
        customer_unique_id,
        total_spend,
        -- using percent_rank to determine the top 20% percentile
        percent_rank() over (order by total_spend desc) as percentile_rank,
        -- running total of revenue
        sum(total_spend) over (order by total_spend desc) as cumulative_revenue,
        -- total revenue across all customers for percentage calculation
        sum(total_spend) over () as grand_total_revenue
    from 
        customer_revenue
),

pareto_summary as (
    -- step 3: identify the contribution of the top 20%
    select 
        case 
            when percentile_rank <= 0.20 then 'Top 20% (VIPs)'
            else 'Bottom 80% (Long Tail)'
        end as customer_tier,
        count(customer_unique_id) as customer_count,
        sum(total_spend) as tier_revenue,
        max(grand_total_revenue) as total_revenue
    from 
        revenue_ranking
    group by 
        case 
            when percentile_rank <= 0.20 then 'Top 20% (VIPs)'
            else 'Bottom 80% (Long Tail)'
        end
)

-- final output: calculating the percentage contribution per tier
select 
    customer_tier,
    customer_count,
    cast(tier_revenue as decimal(15,2)) as revenue_contribution,
    cast(100.0 * tier_revenue / total_revenue as decimal(5,2)) as revenue_pct
from 
    pareto_summary
order by 
    revenue_pct desc;
go

/*  QUESTION 4.
> "For the segment of customers with multiple purchases, what is the average time interval
(in days) between consecutive orders? How does this 'purchase latency' vary across 
different product categories?"


customer inter-purchase latency analysis
    objective: calculate the average days between consecutive orders for repeat customers
    granularity: customer_unique_id and product_category_name
*/

with purchase_sequences as (
    -- step 1: identify orders for repeat customers and find the previous order date
    -- we use lag() to get the prior purchase timestamp for each unique user
    select 
        c.customer_unique_id,
        o.order_purchase_timestamp,
        p.product_category_name,
        lag(o.order_purchase_timestamp) over (
            partition by c.customer_unique_id 
            order by o.order_purchase_timestamp
        ) as previous_order_timestamp
    from 
        orders o
    inner join 
        customers c on o.customer_id = c.customer_id
    inner join 
        order_items oi on o.order_id = oi.order_id
    inner join 
        products p on oi.product_id = p.product_id
    where 
        o.order_status not in ('canceled', 'unavailable')
),

latency_calculations as (
    -- step 2: calculate days between orders and filter only for the second+ purchases
    select 
        customer_unique_id,
        product_category_name,
        datediff(day, previous_order_timestamp, order_purchase_timestamp) as days_to_next_order
    from 
        purchase_sequences
    where 
        previous_order_timestamp is not null -- ensures we only look at repeat purchase events
)

-- final output: average latency per category to identify replenishment cycles
select 
    product_category_name,
    count(*) as repeat_purchase_events,
    avg(days_to_next_order) as avg_days_between_orders,
    min(days_to_next_order) as min_days,
    max(days_to_next_order) as max_days
from 
    latency_calculations
group by 
    product_category_name
having 
    count(*) >= 5 -- filtering for statistical significance in categories
order by 
    avg_days_between_orders asc;
GO


/* QUESTION 5.


Customer Churn Risk Analysis

**Analytical Question:**

> "Which customers have exceeded the average purchase cycle by more than 2 standard deviations 
without placing a new order? Can we flag these users as 'High Risk of Churn' based on their 
deviation from the typical repurchase behavior?"
*/

/* customer churn risk analysis
    objective: identify customers who have exceeded the platform's average purchase cycle by > 2 standard deviations
    logic: 
      1. calculate intervals between consecutive orders for repeat buyers.
      2. derive global average cycle and standard deviation.
      3. compare each customer's inactivity (days since last order) against the (avg + 2*stdev) threshold.
    granularity: customer_unique_id
*/

with dataset_max_date as (
    -- finding the last order date in the dataset to act as "today" for recency/churn calculation
    select max(order_purchase_timestamp) as max_date from orders
),

purchase_intervals as (
    -- step 1: use lag() to calculate the day-gap between consecutive orders for the same unique user
    select 
        c.customer_unique_id,
        o.order_purchase_timestamp,
        days_since_prior = datediff(day, lag(o.order_purchase_timestamp) over (
            partition by c.customer_unique_id 
            order by o.order_purchase_timestamp
        ), o.order_purchase_timestamp)
    from 
        orders o
    inner join 
        customers c on o.customer_id = c.customer_id
    where 
        o.order_status not in ('canceled', 'unavailable')
),

cycle_stats as (
    -- step 2: calculate global benchmarks for repurchase behavior
    -- stdev() helps define what is "statistically normal" vs "anomalous"
    select 
        avg_cycle = avg(days_since_prior * 1.0),
        std_dev_cycle = stdev(days_since_prior)
    from 
        purchase_intervals
    where 
        days_since_prior is not null -- only includes repeat purchase events
),

customer_last_purchase as (
    -- step 3: find the recency of the absolute last order for every customer
    select 
        c.customer_unique_id,
        max(o.order_purchase_timestamp) as last_order_date,
        days_since_last_order = datediff(day, max(o.order_purchase_timestamp), d.max_date)
    from 
        orders o
    inner join 
        customers c on o.customer_id = c.customer_id
    cross join 
        dataset_max_date d
    where 
        o.order_status not in ('canceled', 'unavailable')
    group by 
        c.customer_unique_id, d.max_date
)

-- final output: categorizing users based on statistical thresholds
select 
    lp.customer_unique_id,
    lp.days_since_last_order,
    cast(stats.avg_cycle as decimal(10,2)) as platform_avg_cycle,
    cast((stats.avg_cycle + (2 * stats.std_dev_cycle)) as decimal(10,2)) as churn_threshold,
    case 
        when lp.days_since_last_order > (stats.avg_cycle + (2 * stats.std_dev_cycle)) then 'High Risk of Churn'
        when lp.days_since_last_order > stats.avg_cycle then 'Above Average Latency'
        else 'Healthy / Within Normal Range'
    end as churn_risk_status
from 
    customer_last_purchase lp
cross join 
    cycle_stats stats
order by 
    lp.days_since_last_order desc;
go
