use [Olist-E-Commerce];
go

-- QUESTION 1.
/*
"What is the quantitative correlation between **Delivery Delay** (Actual Delivery Date - Estimated Delivery Date) 
and the **Average Review Score**? Specifically, at what 'delay threshold' (e.g., +1 day, +3 days)
does the average customer rating strictly drop below 3 stars?"*/

/* review score & delivery delay correlation analysis
    objective: quantify the impact of delivery delays on customer satisfaction scores
    logic:
        1. calculate delay days (actual vs estimated). 
        2. group orders by the number of delay days (negative = early, positive = late).
        3. calculate average review score for each bucket.
        4. identify the 'critical threshold' where average rating drops below 3.0 stars.
*/

with order_delays as (
    -- step 1: calculate delay in days for delivered orders
    select 
        o.order_id,
        o.order_estimated_delivery_date,
        o.order_delivered_customer_date,
        -- delay: positive means late, zero means on time, negative means early
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

delay_benchmarks as (
    -- step 2: aggregate ratings by delay day buckets
    select 
        delay_days,
        count(*) as order_count,
        avg(review_score * 1.0) as avg_review_score
    from 
        order_delays
    group by 
        delay_days
)

-- final output: identifying the correlation and the 'danger zone' threshold
select 
    delay_days,
    order_count,
    cast(avg_review_score as decimal(10,2)) as avg_rating,
    -- logical classification based on common customer sentiment patterns
    case 
        when delay_days < 0 then 'Early (Bonus Satisfaction)'
        when delay_days = 0 then 'On-Time (Expected)'
        when delay_days > 0 and avg_review_score >= 3.0 then 'Late (Tolerable)'
        when delay_days > 0 and avg_review_score < 3.0 then 'Late (Critical Threshold Passed)'
        else 'Outlier'
    end as sentiment_profile
from 
    delay_benchmarks
where 
    order_count > 10 -- ensures we only look at statistically significant delay buckets
order by 
    delay_days asc;
go



-- QUESTION 2.
/*
"Can we identify product categories that consistently have **Fast Delivery** (Top 25% speed) but **Low Review Scores**
(Bottom 25% rating)? Conversely, which categories have slow delivery but high scores?"
*/
/* PART 1: Review Score & Delivery Delay Correlation Analysis
    objective: quantify the impact of delivery delays on customer satisfaction scores
    logic:
        1. calculate delay days (actual vs estimated). 
        2. group orders by the number of delay days (negative = early, positive = late).
        3. identify the 'critical threshold' where average rating drops below 3.0 stars.
*/

with order_delays as (
    -- step 1: calculate delay in days for delivered orders
    select 
        o.order_id,
        o.order_estimated_delivery_date,
        o.order_delivered_customer_date,
        -- delay: positive means late, zero means on time, negative means early
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

delay_benchmarks as (
    -- step 2: aggregate ratings by delay day buckets
    select 
        delay_days,
        count(*) as order_count,
        avg(review_score * 1.0) as avg_review_score
    from 
        order_delays
    group by 
        delay_days
)

-- output 1: identifying the correlation and the 'danger zone' threshold
select 
    delay_days,
    order_count,
    cast(avg_review_score as decimal(10,2)) as avg_rating,
    case 
        when delay_days < 0 then 'Early (Bonus Satisfaction)'
        when delay_days = 0 then 'On-Time (Expected)'
        when delay_days > 0 and avg_review_score >= 3.0 then 'Late (Tolerable)'
        when delay_days > 0 and avg_review_score < 3.0 then 'Late (Critical Threshold Passed)'
        else 'Outlier'
    end as sentiment_profile
from 
    delay_benchmarks
where 
    order_count > 10 
order by 
    delay_days asc;


/* PART 2: Speed vs. Quality Paradox
    objective: identify categories with fast delivery (Top 25%) but poor review scores (Bottom 25%)
    logic:
        1. calculate avg lead time and avg review score per category.
        2. use percent_rank() to identify the top/bottom quartiles.
        3. isolate "Fast but Hated" categories where logistics is not the problem.
*/

with category_performance as (
    -- step 1: aggregate logistics and sentiment metrics per category
    select 
        p.product_category_name,
        count(distinct o.order_id) as total_orders,
        avg(datediff(day, o.order_purchase_timestamp, o.order_delivered_customer_date) * 1.0) as avg_lead_time_days,
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
        count(distinct o.order_id) > 50 -- filter for statistical significance
),

quartile_ranking as (
    -- step 2: rank categories using percentiles
    -- for lead time: 0.0 is fastest, 1.0 is slowest
    -- for review score: 0.0 is worst, 1.0 is best
    select 
        *,
        lead_time_percentile = percent_rank() over (order by avg_lead_time_days asc),
        review_percentile = percent_rank() over (order by avg_review_score asc)
    from 
        category_performance
)

-- output 2: identifying the "Logistics High / Quality Low" paradox
select 
    product_category_name,
    total_orders,
    cast(avg_lead_time_days as decimal(10,2)) as avg_delivery_speed,
    cast(avg_review_score as decimal(10,2)) as avg_rating,
    case 
        when lead_time_percentile <= 0.25 and review_percentile <= 0.25 then 'Paradox: Fast but Poorly Rated'
        when lead_time_percentile <= 0.25 and review_percentile >= 0.75 then 'Gold Standard: Fast & Loved'
        when lead_time_percentile >= 0.75 and review_percentile <= 0.25 then 'Operational Crisis: Slow & Hated'
        else 'Standard Performance'
    end as category_archetype
from 
    quartile_ranking
order by 
    lead_time_percentile asc;
go



-- QUESTION 3.
/*
> "Do reviews that include a written comment (`review_comment_message` IS NOT NULL) have a significantly 
lower average score than 'Rating-Only' reviews? What percentage of 1-star reviews contain detailed complaints versus 5-star reviews?"
*/
/* PART 1: Review Score & Delivery Delay Correlation Analysis
    objective: quantify the impact of delivery delays on customer satisfaction scores
    logic:
        1. calculate delay days (actual vs estimated). 
        2. group orders by the number of delay days (negative = early, positive = late).
        3. identify the 'critical threshold' where average rating drops below 3.0 stars.
*/

with order_delays as (
    -- step 1: calculate delay in days for delivered orders
    select 
        o.order_id,
        o.order_estimated_delivery_date,
        o.order_delivered_customer_date,
        -- delay: positive means late, zero means on time, negative means early
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

delay_benchmarks as (
    -- step 2: aggregate ratings by delay day buckets
    select 
        delay_days,
        count(*) as order_count,
        avg(review_score * 1.0) as avg_review_score
    from 
        order_delays
    group by 
        delay_days
)

-- output 1: identifying the correlation and the 'danger zone' threshold
select 
    delay_days,
    order_count,
    cast(avg_review_score as decimal(10,2)) as avg_rating,
    case 
        when delay_days < 0 then 'Early (Bonus Satisfaction)'
        when delay_days = 0 then 'On-Time (Expected)'
        when delay_days > 0 and avg_review_score >= 3.0 then 'Late (Tolerable)'
        when delay_days > 0 and avg_review_score < 3.0 then 'Late (Critical Threshold Passed)'
        else 'Outlier'
    end as sentiment_profile
from 
    delay_benchmarks
where 
    order_count > 10 
order by 
    delay_days asc;


/* PART 2: Speed vs. Quality Paradox
    objective: identify categories with fast delivery (Top 25%) but poor review scores (Bottom 25%)
    logic:
        1. calculate avg lead time and avg review score per category.
        2. use percent_rank() to identify the top/bottom quartiles.
        3. isolate "Fast but Hated" categories where logistics is not the problem.
*/

with category_performance as (
    -- step 1: aggregate logistics and sentiment metrics per category
    select 
        p.product_category_name,
        count(distinct o.order_id) as total_orders,
        avg(datediff(day, o.order_purchase_timestamp, o.order_delivered_customer_date) * 1.0) as avg_lead_time_days,
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
        count(distinct o.order_id) > 50 -- filter for statistical significance
),

quartile_ranking as (
    -- step 2: rank categories using percentiles
    select 
        *,
        lead_time_percentile = percent_rank() over (order by avg_lead_time_days asc),
        review_percentile = percent_rank() over (order by avg_review_score asc)
    from 
        category_performance
)

-- output 2: identifying the "Logistics High / Quality Low" paradox
select 
    product_category_name,
    total_orders,
    cast(avg_lead_time_days as decimal(10,2)) as avg_delivery_speed,
    cast(avg_review_score as decimal(10,2)) as avg_rating,
    case 
        when lead_time_percentile <= 0.25 and review_percentile <= 0.25 then 'Paradox: Fast but Poorly Rated'
        when lead_time_percentile <= 0.25 and review_percentile >= 0.75 then 'Gold Standard: Fast & Loved'
        when lead_time_percentile >= 0.75 and review_percentile <= 0.25 then 'Operational Crisis: Slow & Hated'
        else 'Standard Performance'
    end as category_archetype
from 
    quartile_ranking
order by 
    lead_time_percentile asc;


/* PART 3: Review Comment Sentiment Analysis
    objective: analyze the impact of written feedback on scores and compare "vocal" 1-star vs 5-star segments
    logic:
        1. categorize reviews as 'Written' (comment present) vs 'Rating-Only'.
        2. calculate average scores for each group.
        3. determine the "Comment Intensity" (percentage of users who write text) for extreme ratings.
*/

with review_feedback_stats as (
    -- step 1: identify presence of text in reviews
    select 
        review_score,
        case when review_comment_message is not null then 1 else 0 end as has_comment
    from 
        order_reviews
),

comment_impact as (
    -- step 2: compare average scores between commented and silent reviews
    select 
        case when has_comment = 1 then 'Written Feedback' else 'Rating-Only' end as feedback_type,
        count(*) as total_reviews,
        avg(review_score * 1.0) as avg_score
    from 
        review_feedback_stats
    group by 
        has_comment
),

rating_specific_comments as (
    -- step 3: calculate comment percentage for the polar ends of the rating scale
    select 
        review_score,
        count(*) as total_reviews,
        sum(has_comment) as comment_count,
        cast(100.0 * sum(has_comment) / count(*) as decimal(5,2)) as comment_rate_pct
    from 
        review_feedback_stats
    where 
        review_score in (1, 5)
    group by 
        review_score
)

-- output 3: summary of how "vocal" dissatisfied customers are compared to satisfied ones
select 
    ci.feedback_type,
    ci.total_reviews,
    cast(ci.avg_score as decimal(10,2)) as avg_score,
    -- referencing specific polar metrics
    (select comment_rate_pct from rating_specific_comments where review_score = 1) as one_star_comment_intensity,
    (select comment_rate_pct from rating_specific_comments where review_score = 5) as five_star_comment_intensity
from 
    comment_impact ci;
go





