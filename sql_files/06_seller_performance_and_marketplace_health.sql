use [Olist-E-Commerce];
go

-- QUESTION 1.
/*
"What is the average time gap between `order_approved_at` and `order_delivered_carrier_date` for each seller? 
Who are the 'Bottom 10%' of sellers who consistently take the longest to hand over packaged orders to 
the logistics partner?"
*/
/* seller dispatch efficiency analysis
    objective: identify sellers with the longest gap between order approval and carrier handover
    logic: 
      1. calculate the 'dispatch lag' in hours for every order item.
      2. aggregate to find the average dispatch time per seller.
      3. use ntile(10) to identify the bottom 10% (slowest performers).
    granularity: seller_id
*/

with seller_lead_times as (
    -- step 1: calculate hours between approval and carrier handover
    -- we use hours to capture precision for high-performing sellers
    select 
        oi.seller_id,
        o.order_id,
        dispatch_hours = datediff(second, o.order_approved_at, o.order_delivered_carrier_date) / 3600.0
    from 
        orders o
    inner join 
        order_items oi on o.order_id = oi.order_id
    where 
        o.order_status not in ('canceled', 'unavailable')
        and o.order_approved_at is not null
        and o.order_delivered_carrier_date is not null
),

seller_performance_summary as (
    -- step 2: aggregate averages per seller
    select 
        seller_id,
        count(distinct order_id) as total_orders_fulfilled,
        avg(dispatch_hours) as avg_dispatch_hours
    from 
        seller_lead_times
    where 
        dispatch_hours >= 0 -- filtering out potential data entry errors
    group by 
        seller_id
    having 
        count(distinct order_id) >= 5 -- filtering for sellers with enough history to be statistically relevant
),

seller_efficiency_ranks as (
    -- step 3: segment sellers into deciles based on speed
    -- ntile(10) with order by desc puts the slowest 10% into bucket 1
    select 
        *,
        efficiency_decile = ntile(10) over (order by avg_dispatch_hours desc)
    from 
        seller_performance_summary
)

-- final output: isolating the "bottom 10%" slowest sellers
select 
    seller_id,
    total_orders_fulfilled,
    cast(avg_dispatch_hours as decimal(10,2)) as avg_dispatch_hours,
    cast(avg_dispatch_hours / 24.0 as decimal(10,2)) as avg_dispatch_days
from 
    seller_efficiency_ranks
where 
    efficiency_decile = 1 -- selecting the slowest decile
order by 
    avg_dispatch_hours desc;
go



-- QUESTION 2.
/*
"Do the top 10% of sellers generate more than 50% of the platform's total revenue? Furthermore, 
which product categories are dominated by a single 'Monopoly Seller' vs. categories with a healthy, 
competitive mix of multiple vendors??4
*/

/* seller revenue concentration & category monopoly analysis
    objective: 
        1. verify the 10/50 rule (do top 10% sellers drive >50% revenue?).
        2. identify category health (monopolies vs competitive markets).
    logic: 
        - calculate revenue per seller globally.
        - calculate revenue per seller per category.
        - use window functions to determine market share and percentile rankings.
*/

with seller_global_revenue as (
    -- step 1: calculate total revenue for every seller across the platform
    select 
        oi.seller_id,
        sum(p.payment_value) as total_seller_revenue
    from 
        order_items oi
    inner join 
        payments p on oi.order_id = p.order_id
    inner join 
        orders o on oi.order_id = o.order_id
    where 
        o.order_status not in ('canceled', 'unavailable')
    group by 
        oi.seller_id
),

global_pareto as (
    -- step 2: rank sellers into deciles to check platform-wide concentration
    select 
        seller_id,
        total_seller_revenue,
        ntile(10) over (order by total_seller_revenue desc) as seller_decile,
        sum(total_seller_revenue) over () as platform_total_revenue
    from 
        seller_global_revenue
),

category_seller_share as (
    -- step 3: calculate revenue share for each seller within their specific category
    select 
        prod.product_category_name,
        oi.seller_id,
        sum(p.payment_value) as seller_category_revenue,
        sum(sum(p.payment_value)) over (partition by prod.product_category_name) as total_category_revenue
    from 
        order_items oi
    inner join 
        products prod on oi.product_id = prod.product_id
    inner join 
        payments p on oi.order_id = p.order_id
    inner join 
        orders o on oi.order_id = o.order_id
    where 
        o.order_status not in ('canceled', 'unavailable')
        and prod.product_category_name is not null
    group by 
        prod.product_category_name, oi.seller_id
),

category_dominance as (
    -- step 4: identify the share of the 'top seller' in each category
    select 
        product_category_name,
        count(distinct seller_id) as total_vendors,
        max(seller_category_revenue) as top_seller_revenue,
        total_category_revenue,
        -- market share of the leading seller
        cast(100.0 * max(seller_category_revenue) / total_category_revenue as decimal(5,2)) as leader_market_share_pct
    from 
        category_seller_share
    group by 
        product_category_name, total_category_revenue
)

-- final output: categorizing product categories by competitive health
select 
    product_category_name,
    total_vendors,
    leader_market_share_pct,
    case 
        when leader_market_share_pct >= 50 and total_vendors < 5 then 'Monopoly / Highly Concentrated'
        when leader_market_share_pct >= 30 then 'Dominant Leader'
        when leader_market_share_pct < 15 and total_vendors > 20 then 'Healthy / Fragmented Competition'
        else 'Moderate Competition'
    end as market_health_status
from 
    category_dominance
order by 
    leader_market_share_pct desc;
go



-- QUESTION 3.
/*
"What is the churn rate of sellers on the platform? Specifically, how many sellers who made a sale in 2017
became inactive (zero sales) in 2018? Is there a correlation between high 'Order Cancellation Rates' 
and subsequent seller churn?
*/

/* seller churn & cancellation correlation analysis
    objective: 
        1. identify sellers active in 2017 who became inactive in 2018 (churn).
        2. calculate the 'cancellation rate' for these sellers to see if it correlates with churn.
    logic:
        - segment sellers by their last year of activity.
        - calculate the ratio of canceled orders to total orders.
        - compare cancellation benchmarks between 'retained' and 'churned' sellers.
*/

with seller_activity as (
    -- step 1: identify activity years and cancellation counts for every seller
    select 
        oi.seller_id,
        year(o.order_purchase_timestamp) as activity_year,
        count(distinct o.order_id) as total_orders,
        sum(case when o.order_status = 'canceled' then 1 else 0 end) as canceled_orders
    from 
        orders o
    inner join 
        order_items oi on o.order_id = oi.order_id
    group by 
        oi.seller_id, year(o.order_purchase_timestamp)
),

seller_cohort_2017 as (
    -- step 2: isolate sellers who were active in 2017 and track their 2018 status
    select 
        s17.seller_id,
        s17.total_orders as orders_2017,
        cast(100.0 * s17.canceled_orders / s17.total_orders as decimal(5,2)) as cancellation_rate_2017,
        case 
            when s18.seller_id is null then 'Churned (Inactive in 2018)'
            else 'Retained (Active in 2018)'
        end as churn_status
    from 
        seller_activity s17
    left join 
        seller_activity s18 on s17.seller_id = s18.seller_id and s18.activity_year = 2018
    where 
        s17.activity_year = 2017
)

-- final output: comparing cancellation rates across churned vs retained sellers
select 
    churn_status,
    count(seller_id) as seller_count,
    -- average cancellation rate to identify the correlation
    cast(avg(cancellation_rate_2017) as decimal(5,2)) as avg_cancellation_rate_pct,
    -- average volume to see if smaller or larger sellers churn more
    cast(avg(orders_2017 * 1.0) as decimal(10,2)) as avg_2017_order_volume
from 
    seller_cohort_2017
group by 
    churn_status;
go


-- QUESTION 4.
/*
"Which sellers have a high sales volume (\>50 orders) but a consistently low average review score (\<3 stars)?
Can we identify specific sellers who are responsible for a disproportionate number of the platform's 1-star reviews?"
*/

/* PART 1: Seller Churn & Cancellation Correlation Analysis
    Objective: 
        1. Identify sellers active in 2017 who became inactive in 2018 (churn).
        2. Calculate the 'cancellation rate' for these sellers to see if it correlates with churn.
*/

with seller_activity as (
    -- step 1: identify activity years and cancellation counts for every seller
    select 
        oi.seller_id,
        year(o.order_purchase_timestamp) as activity_year,
        count(distinct o.order_id) as total_orders,
        sum(case when o.order_status = 'canceled' then 1 else 0 end) as canceled_orders
    from 
        orders o
    inner join 
        order_items oi on o.order_id = oi.order_id
    group by 
        oi.seller_id, year(o.order_purchase_timestamp)
),

seller_cohort_2017 as (
    -- step 2: isolate sellers who were active in 2017 and track their 2018 status
    select 
        s17.seller_id,
        s17.total_orders as orders_2017,
        cast(100.0 * s17.canceled_orders / s17.total_orders as decimal(5,2)) as cancellation_rate_2017,
        case 
            when s18.seller_id is null then 'Churned (Inactive in 2018)'
            else 'Retained (Active in 2018)'
        end as churn_status
    from 
        seller_activity s17
    left join 
        seller_activity s18 on s17.seller_id = s18.seller_id and s18.activity_year = 2018
    where 
        s17.activity_year = 2017
)

-- output 1: comparing cancellation rates across churned vs retained sellers
select 
    churn_status,
    count(seller_id) as seller_count,
    cast(avg(cancellation_rate_2017) as decimal(5,2)) as avg_cancellation_rate_pct,
    cast(avg(orders_2017 * 1.0) as decimal(10,2)) as avg_2017_order_volume
from 
    seller_cohort_2017
group by 
    churn_status;


/* PART 2: Seller Review Performance & 1-Star Concentration
    Objective: 
        1. Identify high-volume sellers (>50 orders) with poor ratings (<3 stars).
        2. Calculate their contribution to the platform's total 1-star reviews.
*/

with seller_review_stats as (
    -- step 1: aggregate review scores and total 1-stars per seller
    select 
        oi.seller_id,
        count(distinct o.order_id) as total_orders,
        avg(orv.review_score * 1.0) as avg_review_score,
        sum(case when orv.review_score = 1 then 1 else 0 end) as one_star_count
    from 
        order_items oi
    inner join 
        orders o on oi.order_id = o.order_id
    inner join 
        order_reviews orv on o.order_id = orv.order_id
    group by 
        oi.seller_id
),

platform_total_one_stars as (
    -- step 2: get the total number of 1-star reviews across the whole platform
    select sum(case when review_score = 1 then 1 else 0 end) as grand_total_one_stars
    from order_reviews
)

-- output 2: flagging high-risk sellers based on volume and negative sentiment
select 
    s.seller_id,
    s.total_orders,
    cast(s.avg_review_score as decimal(3,2)) as avg_review_score,
    s.one_star_count,
    -- concentration: what % of the entire platform's 1-star reviews come from this one seller?
    cast(100.0 * s.one_star_count / p.grand_total_one_stars as decimal(5,2)) as pct_of_platform_one_stars
from 
    seller_review_stats s
cross join 
    platform_total_one_stars p
where 
    s.total_orders > 50 
    and s.avg_review_score < 3
order by 
    s.one_star_count desc;
go



