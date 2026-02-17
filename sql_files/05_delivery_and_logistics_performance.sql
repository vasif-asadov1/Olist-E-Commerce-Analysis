use [Olist-E-Commerce];
go

-- QUESTION 1. 
/*"What is the overall 'On-Time Delivery Rate' (percentage of orders delivered before the 
`order_estimated_delivery_date`)? Furthermore, what is the average variance between the estimated 
and actual delivery dates across different states?" */
/* on-time delivery rate & relative accuracy analysis
    objective: measure logistics reliability using national benchmarks to find outliers
    logic: 
      1. calculate variance (estimate vs actual) for every delivered order.
      2. use a window function to find the national avg accuracy across all states.
      3. flag states that are significantly more conservative or aggressive than the norm.
*/

with delivery_data as (
    -- step 1: prepare variance data per order
    select 
        c.customer_state,
        o.order_id,
        o.order_estimated_delivery_date,
        o.order_delivered_customer_date,
        case 
            when o.order_delivered_customer_date <= o.order_estimated_delivery_date then 1 
            else 0 
        end as is_on_time,
        datediff(day, o.order_delivered_customer_date, o.order_estimated_delivery_date) as delivery_variance_days
    from 
        orders o
    inner join 
        customers c on o.customer_id = c.customer_id
    where 
        o.order_status = 'delivered'
        and o.order_delivered_customer_date is not null
        and o.order_estimated_delivery_date is not null
),

state_performance as (
    -- step 2: aggregate by state and calculate national benchmark
    select 
        customer_state,
        count(order_id) as total_delivered_orders,
        cast(100.0 * sum(is_on_time) / count(order_id) as decimal(5,2)) as on_time_rate,
        avg(delivery_variance_days * 1.0) as state_avg_accuracy,
        -- getting the national average across all states to use as a baseline
        avg(avg(delivery_variance_days * 1.0)) over () as national_avg_accuracy
    from 
        delivery_data
    group by 
        customer_state
)

-- final output: categorizing states relative to the national logistics standard
select 
    customer_state,
    total_delivered_orders,
    on_time_rate,
    cast(state_avg_accuracy as decimal(10,2)) as avg_accuracy_days,
    cast(national_avg_accuracy as decimal(10,2)) as national_benchmark,
    case 
        when state_avg_accuracy > national_avg_accuracy + 2 then 'Extremely Conservative (High Buffer)'
        when state_avg_accuracy < national_avg_accuracy - 2 then 'Relatively Aggressive (Lower Buffer)'
        else 'Standard (Aligned with National Avg)'
    end as relative_performance
from 
    state_performance
order by 
    avg_accuracy_days desc;
go




-- QUESTION 2. 
/*
"How does the average freight cost (`freight_value`) correlate with average delivery time across different states?
Can we identify regions that suffer from the 'Logistics Gap'—paying disproportionately high shipping fees 
for the slowest service?"
*/

/* logistics gap analysis
    objective: identify regions paying high freight costs for slow delivery service
    logic: 
      1. calculate total freight and delivery duration for every delivered order.
      2. aggregate by state to find averages.
      3. compare state metrics against national benchmarks using window functions.
    granularity: customer_state
*/

with order_metrics as (
    -- step 1: prepare freight and delivery time per order
    -- we sum freight_value per order first to handle cases with multiple items
    select 
        o.order_id,
        c.customer_state,
        sum(oi.freight_value) as total_order_freight,
        datediff(day, o.order_purchase_timestamp, o.order_delivered_customer_date) as delivery_time_days
    from 
        orders o
    inner join 
        customers c on o.customer_id = c.customer_id
    inner join 
        order_items oi on o.order_id = oi.order_id
    where 
        o.order_status = 'delivered'
        and o.order_delivered_customer_date is not null
    group by 
        o.order_id, c.customer_state, o.order_purchase_timestamp, o.order_delivered_customer_date
),

state_benchmarks as (
    -- step 2: calculate state averages and compare to national benchmarks
    select 
        customer_state,
        avg(total_order_freight) as avg_state_freight,
        avg(delivery_time_days * 1.0) as avg_state_delivery_time,
        -- national benchmarks using window functions
        avg(avg(total_order_freight)) over () as national_avg_freight,
        avg(avg(delivery_time_days * 1.0)) over () as national_avg_delivery_time
    from 
        order_metrics
    group by 
        customer_state
)

-- final output: classifying the logistics efficiency of each state
select 
    customer_state,
    cast(avg_state_freight as decimal(10,2)) as avg_freight,
    cast(avg_state_delivery_time as decimal(10,2)) as avg_delivery_days,
    case 
        when avg_state_freight > national_avg_freight and avg_state_delivery_time > national_avg_delivery_time then 'Logistics Gap (High Cost / Slow)'
        when avg_state_freight > national_avg_freight and avg_state_delivery_time <= national_avg_delivery_time then 'Premium Service (High Cost / Fast)'
        when avg_state_freight <= national_avg_freight and avg_state_delivery_time > national_avg_delivery_time then 'Budget / Inefficient (Low Cost / Slow)'
        else 'Optimized Logistics (Low Cost / Fast)'
    end as logistics_classification
from 
    state_benchmarks
order by 
    avg_state_freight desc, avg_state_delivery_time desc;
go




-- QUESTION 3. 
/*
"Can we decompose the total delivery timeline into three distinct stages: 'Approval Time' (Purchase to Approval), 
'Dispatch Time' (Approval to Carrier Handover), and 'Last-Mile Delivery' (Carrier to Customer)?
Which of these stages contributes the most to overall delays? */

/* delivery timeline decomposition analysis
    objective: identify which fulfillment stage (approval, dispatch, or last-mile) causes the most delay
    logic: 
      1. calculate duration in hours for each of the three supply chain segments.
      2. aggregate averages at a global level.
      3. calculate the percentage contribution of each stage to the total lead time.
    granularity: order_id
*/

with order_lifecycle as (
    -- step 1: extract time intervals for each stage of the fulfillment process
    -- using hours (3600.0 seconds) to maintain precision for fast stages like approval
    select 
        order_id,
        -- stage 1: approval time (internal processing)
        approval_hours = datediff(second, order_purchase_timestamp, order_approved_at) / 3600.0,
        
        -- stage 2: dispatch time (warehouse / seller preparation)
        dispatch_hours = datediff(second, order_approved_at, order_delivered_carrier_date) / 3600.0,
        
        -- stage 3: last-mile delivery (carrier performance)
        last_mile_hours = datediff(second, order_delivered_carrier_date, order_delivered_customer_date) / 3600.0,
        
        -- total lead time
        total_lead_time_hours = datediff(second, order_purchase_timestamp, order_delivered_customer_date) / 3600.0
    from 
        orders
    where 
        order_status = 'delivered'
        and order_approved_at is not null
        and order_delivered_carrier_date is not null
        and order_delivered_customer_date is not null
),

stage_averages as (
    -- step 2: calculate mean durations across all orders
    select 
        avg_approval_hrs = avg(approval_hours),
        avg_dispatch_hrs = avg(dispatch_hours),
        avg_last_mile_hrs = avg(last_mile_hours),
        avg_total_hrs = avg(total_lead_time_hours)
    from 
        order_lifecycle
    where 
        -- filtering out negative values (data entry errors) to ensure clean averages
        approval_hours >= 0 and dispatch_hours >= 0 and last_mile_hours >= 0
)

-- final output: showing the "weight" of each stage in the delivery process
select 
    cast(avg_approval_hrs / 24.0 as decimal(10,2)) as avg_approval_days,
    cast(avg_dispatch_hrs / 24.0 as decimal(10,2)) as avg_dispatch_days,
    cast(avg_last_mile_hrs / 24.0 as decimal(10,2)) as avg_last_mile_days,
    cast(avg_total_hrs / 24.0 as decimal(10,2)) as avg_total_lead_days,
    
    -- contribution percentages
    cast(100.0 * avg_approval_hrs / avg_total_hrs as decimal(5,2)) as approval_pct_contribution,
    cast(100.0 * avg_dispatch_hrs / avg_total_hrs as decimal(5,2)) as dispatch_pct_contribution,
    cast(100.0 * avg_last_mile_hrs / avg_total_hrs as decimal(5,2)) as last_mile_pct_contribution
from 
    stage_averages;
go



-- QUESTION 4. 
/* "How does logistics performance compare between 'Local Orders' (where `customer_state` matches `seller_state`) 
and 'Long-Haul Orders' (Cross-border)? Specifically, what is the 'Speed Premium'—the reduction in 
delivery days—achieved by fulfilling orders locally?" */
/* local vs long-haul logistics analysis
    objective: compare delivery performance between same-state and cross-state orders
    logic: 
      1. identify if an order is 'local' or 'long-haul' by comparing customer and seller states.
      2. calculate delivery duration and on-time rates for each group.
      3. calculate the "speed premium" (difference in days).
    granularity: shipment level (order_id + seller_id)
*/

with shipment_classification as (
    -- step 1: link customers and sellers to classify the fulfillment path
    -- we use distinct to handle multiple items from the same seller in one order
    select distinct
        o.order_id,
        c.customer_state,
        s.seller_state,
        o.order_purchase_timestamp,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        -- classification logic
        case 
            when c.customer_state = s.seller_state then 'Local' 
            else 'Long-Haul' 
        end as shipment_type
    from 
        orders o
    inner join 
        customers c on o.customer_id = c.customer_id
    inner join 
        order_items oi on o.order_id = oi.order_id
    inner join 
        sellers s on oi.seller_id = s.seller_id
    where 
        o.order_status = 'delivered'
        and o.order_delivered_customer_date is not null
),

performance_metrics as (
    -- step 2: calculate duration and on-time status for each shipment
    select 
        shipment_type,
        datediff(second, order_purchase_timestamp, order_delivered_customer_date) / 86400.0 as delivery_days,
        case when order_delivered_customer_date <= order_estimated_delivery_date then 1 else 0 end as is_on_time
    from 
        shipment_classification
),

summary_stats as (
    -- step 3: aggregate results by shipment type
    select 
        shipment_type,
        count(*) as shipment_count,
        avg(delivery_days) as avg_delivery_days,
        cast(100.0 * sum(is_on_time) / count(*) as decimal(5,2)) as on_time_rate_pct
    from 
        performance_metrics
    group by 
        shipment_type
)

-- final output: comparing the two groups and calculating the speed premium
select 
    shipment_type,
    shipment_count,
    cast(avg_delivery_days as decimal(10,2)) as avg_delivery_days,
    on_time_rate_pct,
    -- speed premium: calculating how much faster local is compared to long-haul
    -- we use a window function to find the difference between the two rows
    cast(
        lag(avg_delivery_days) over (order by avg_delivery_days desc) - avg_delivery_days 
    as decimal(10,2)) as speed_premium_days
from 
    summary_stats;
go


-- QUESTION 5.
/*
"What is the average 'Freight Ratio' (Freight Value / Product Price) across different product categories?
Can we identify categories where shipping costs are disproportionately high (\>20% of item value)
, leading to potential 'Cart Abandonment'?"*/

/* freight ratio analysis
    objective: identify categories where shipping costs are high relative to product price
    logic: 
      1. calculate the freight ratio (freight / price) at the item level.
      2. aggregate averages by product category.
      3. flag categories exceeding the 20% threshold for "abandonment risk".
    granularity: product_category_name
*/

with category_freight_stats as (
    -- step 1: aggregate total price and freight per category
    -- we use order_items directly as it contains both price and freight_value
    select 
        p.product_category_name,
        count(oi.order_item_id) as total_items_sold,
        avg(oi.price) as avg_product_price,
        avg(oi.freight_value) as avg_freight_cost,
        sum(oi.price) as total_category_revenue,
        sum(oi.freight_value) as total_category_freight
    from 
        order_items oi
    inner join 
        products p on oi.product_id = p.product_id
    where 
        p.product_category_name is not null
    group by 
        p.product_category_name
)

-- final output: calculating the ratio and risk levels
select 
    product_category_name,
    cast(avg_product_price as decimal(10,2)) as avg_price,
    cast(avg_freight_cost as decimal(10,2)) as avg_freight,
    -- freight ratio: what percentage of the product price is the shipping cost?
    cast(100.0 * total_category_freight / nullif(total_category_revenue, 0) as decimal(5,2)) as freight_ratio_pct,
    -- risk classification
    case 
        when (total_category_freight / nullif(total_category_revenue, 0)) > 0.20 then 'High Abandonment Risk (>20%)'
        when (total_category_freight / nullif(total_category_revenue, 0)) between 0.10 and 0.20 then 'Moderate Overhead'
        else 'Optimized / Low Shipping Impact'
    end as shipping_cost_impact
from 
    category_freight_stats
order by 
    freight_ratio_pct desc;
go