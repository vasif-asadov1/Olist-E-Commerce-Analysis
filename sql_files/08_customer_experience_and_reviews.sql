use [Olist-E-Commerce]
go



-- QUESTION 1

/* "What is the quantitative correlation between **Delivery Delay** (Actual Delivery Date - Estimated Delivery Date) and the **Average Review Score**? Specifically,
at what 'delay threshold' (e.g., +1 day, +3 days) does the average customer rating strictly drop below 3 stars?" */

/* delivery satisfaction threshold analysis
    objective: identify the "cliff" where delivery delays result in failing satisfaction scores (< 3 stars)
    logic: 
      1. calculate 'delay_days' as the delta between actual and estimated delivery.
      2. aggregate average review scores for every day of delay.
      3. identify the first day where the average rating strictly falls below 3.0.
    granularity: delay_days
*/

with order_delay_metrics as (
    -- step 1: calculate the delay for every delivered order with a review
    select 
        o.order_id,
        -- delay: positive = late, 0 = on time, negative = early
        datediff(day, o.order_estimated_delivery_date, o.order_delivered_customer_date) as delay_days,
        r.review_score
    from 
        orders o
    inner join 
        order_reviews r on o.order_id = r.order_id
    where 
        o.order_status = 'delivered'
        and o.order_delivered_customer_date is not null
        and o.order_estimated_delivery_date is not null
),

aggregated_scores as (
    -- step 2: find average score and volume per delay day
    select 
        delay_days,
        count(order_id) as volume,
        avg(review_score * 1.0) as avg_review_score
    from 
        order_delay_metrics
    group by 
        delay_days
)

-- final output: categorizing the impact of delays on sentiment
select 
    delay_days,
    volume as order_volume,
    cast(avg_review_score as decimal(10,2)) as avg_rating,
    
    -- identifying the threshold status
    case 
        when delay_days < 0 then 'Early (Bonus Rating)'
        when delay_days = 0 then 'On-Time (High Satisfaction)'
        when delay_days > 0 and avg_review_score >= 3.0 then 'Late (Tolerable)'
        when delay_days > 0 and avg_review_score < 3.0 then 'Critical Delay (Satisfaction Cliff)'
        else 'Standard'
    end as satisfaction_tier,
    
    -- calculating the percentage drop from the "On-Time" benchmark
    cast(100.0 * (avg_review_score - (select avg_review_score from aggregated_scores where delay_days = 0)) 
        / (select avg_review_score from aggregated_scores where delay_days = 0) as decimal(10,2)) as pct_drop_from_ontime
from 
    aggregated_scores
where 
    volume > 5 -- filter for statistical relevance
    and delay_days between -10 and 30 -- focusing on the most relevant window
order by 
    delay_days asc;
go

-- QUESTION 2.
 /*"Can we identify product categories that consistently have **Fast Delivery** (Top 25% speed) but **Low Review Scores** (Bottom 25% rating)? 
 Conversely, which categories have slow delivery but high scores?" */

 /* quality vs. logistics matrix analysis
    objective: segment categories to identify if low scores are caused by product quality or delivery speed
    logic: 
      1. calculate average lead time (purchase to delivery) and average review score per category.
      2. use percent_rank() to identify categories in the top/bottom 25th percentiles.
      3. categorize into the 4 quadrants of the quality/logistics matrix.
    granularity: product_category_name
*/

with category_metrics as (
    -- step 1: aggregate logistics and satisfaction metrics at the category level
    select 
        p.product_category_name,
        count(o.order_id) as total_orders,
        -- lead time speed (days)
        avg(datediff(day, o.order_purchase_timestamp, o.order_delivered_customer_date) * 1.0) as avg_delivery_lead_time,
        -- customer satisfaction
        avg(r.review_score * 1.0) as avg_review_score
    from 
        orders o
    inner join 
        order_items oi on o.order_id = oi.order_id
    inner join 
        products p on oi.product_id = p.product_id
    inner join 
        order_reviews r on o.order_id = r.order_id
    where 
        o.order_status = 'delivered'
        and o.order_delivered_customer_date is not null
        and p.product_category_name is not null
    group by 
        p.product_category_name
    having 
        count(o.order_id) > 30 -- filter for statistical significance
),

category_percentiles as (
    -- step 2: assign percentile ranks (0.0 to 1.0)
    select 
        *,
        -- speed: 0.0 is fastest, 1.0 is slowest
        speed_rank = percent_rank() over (order by avg_delivery_lead_time asc),
        -- rating: 0.0 is lowest, 1.0 is highest
        rating_rank = percent_rank() over (order by avg_review_score asc)
    from 
        category_metrics
)

-- final output: matrix segmentation
select 
    product_category_name,
    total_orders,
    cast(avg_delivery_lead_time as decimal(10,2)) as avg_lead_time_days,
    cast(avg_review_score as decimal(10,2)) as avg_rating,
    
    -- step 3: segmenting into the quality/logistics quadrants
    case 
        -- fast delivery (top 25%) + low score (bottom 25%)
        when speed_rank <= 0.25 and rating_rank <= 0.25 then 'Product/Catalog Issue (Fast but Hated)'
        
        -- slow delivery (bottom 25%) + high score (top 25%)
        when speed_rank >= 0.75 and rating_rank >= 0.75 then 'Logistics Bottleneck (Slow but Loved)'
        
        -- fast delivery + high score
        when speed_rank <= 0.25 and rating_rank >= 0.75 then 'Gold Standard (Fast & Loved)'
        
        -- slow delivery + low score
        when speed_rank >= 0.75 and rating_rank <= 0.25 then 'Systemic Failure (Slow & Hated)'
        
        else 'Standard Performance'
    end as matrix_segment
from 
    category_percentiles
order by 
    avg_rating asc;
GO



 -- QUESTION 3.
/*
 "Do reviews that include a written comment (`review_comment_message` IS NOT NULL) have a significantly lower average score than 'Rating-Only' reviews? 
 What percentage of 1-star reviews contain detailed complaints versus 5-star reviews?"*/

 /* PART 1: Quality vs. Logistics Matrix Analysis
    objective: segment categories to identify if low scores are caused by product quality or delivery speed
    logic: 
      1. calculate average lead time (purchase to delivery) and average review score per category.
      2. use percent_rank() to identify categories in the top/bottom 25th percentiles.
      3. categorize into the 4 quadrants of the quality/logistics matrix.
*/

with category_metrics as (
    -- step 1: aggregate logistics and satisfaction metrics at the category level
    select 
        p.product_category_name,
        count(o.order_id) as total_orders,
        -- lead time speed (days)
        avg(datediff(day, o.order_purchase_timestamp, o.order_delivered_customer_date) * 1.0) as avg_delivery_lead_time,
        -- customer satisfaction
        avg(r.review_score * 1.0) as avg_review_score
    from 
        orders o
    inner join 
        order_items oi on o.order_id = oi.order_id
    inner join 
        products p on oi.product_id = p.product_id
    inner join 
        order_reviews r on o.order_id = r.order_id
    where 
        o.order_status = 'delivered'
        and o.order_delivered_customer_date is not null
        and p.product_category_name is not null
    group by 
        p.product_category_name
    having 
        count(o.order_id) > 30 -- filter for statistical significance
),

category_percentiles as (
    -- step 2: assign percentile ranks (0.0 to 1.0)
    select 
        *,
        -- speed: 0.0 is fastest, 1.0 is slowest
        speed_rank = percent_rank() over (order by avg_delivery_lead_time asc),
        -- rating: 0.0 is lowest, 1.0 is highest
        rating_rank = percent_rank() over (order by avg_review_score asc)
    from 
        category_metrics
)

-- Output 1: Matrix Segmentation
select 
    product_category_name,
    total_orders,
    cast(avg_delivery_lead_time as decimal(10,2)) as avg_lead_time_days,
    cast(avg_review_score as decimal(10,2)) as avg_rating,
    
    case 
        when speed_rank <= 0.25 and rating_rank <= 0.25 then 'Product/Catalog Issue (Fast but Hated)'
        when speed_rank >= 0.75 and rating_rank >= 0.75 then 'Logistics Bottleneck (Slow but Loved)'
        when speed_rank <= 0.25 and rating_rank >= 0.75 then 'Gold Standard (Fast & Loved)'
        when speed_rank >= 0.75 and rating_rank <= 0.25 then 'Systemic Failure (Slow & Hated)'
        else 'Standard Performance'
    end as matrix_segment
from 
    category_percentiles;


/* PART 2: The "Vocal Minority" Analysis (Comment Sentiment)
    objective: determine if written feedback correlates with stronger negative sentiment 
    logic: 
      1. flag reviews as 'vocal' (written message) vs 'silent' (rating-only).
      2. compare average review scores for both groups.
      3. calculate the percentage of written complaints for 1-star vs 5-star reviews.
*/

with review_segments as (
    -- step 1: flag reviews that contain text
    select 
        review_id,
        review_score,
        case when review_comment_message is not null then 1 else 0 end as has_text
    from 
        order_reviews
),

vocal_comparison as (
    -- step 2: compare average scores for written vs silent reviews
    select 
        case when has_text = 1 then 'Vocal (Written Comment)' else 'Silent (Rating Only)' end as review_type,
        count(*) as review_count,
        avg(review_score * 1.0) as avg_score
    from 
        review_segments
    group by 
        has_text
),

polarity_intensity as (
    -- step 3: calculate the % of reviews with text for the extreme ends of the scale
    select 
        review_score,
        count(*) as total_reviews,
        sum(has_text) as reviews_with_text,
        cast(100.0 * sum(has_text) / count(*) as decimal(10,2)) as text_intensity_pct
    from 
        review_segments
    where 
        review_score in (1, 5)
    group by 
        review_score
)

-- Output 2: Vocal Minority Distribution
select 
    vc.review_type,
    vc.review_count,
    cast(vc.avg_score as decimal(10,2)) as avg_score,
    -- referencing polarity stats for business context
    (select text_intensity_pct from polarity_intensity where review_score = 1) as one_star_comment_pct,
    (select text_intensity_pct from polarity_intensity where review_score = 5) as five_star_comment_pct
from 
    vocal_comparison vc;
go

