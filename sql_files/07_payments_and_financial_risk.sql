use [Olist-E-Commerce];
go

-- QUESTION 1.
/*
"What is the distribution of total revenue across different payment methods (Credit Card, Boleto, Voucher, Debit Card)? 
Specifically, does the 'Average Transaction Value' differ significantly between Credit Card users and Boleto users?"
*/

/* payment method & transaction value analysis
    objective: 
        1. analyze the distribution of revenue across payment types.
        2. compare average transaction value (atv) between credit card and boleto users.
    logic:
        - aggregate payments by type to find revenue contribution.
        - calculate atv as total payment value divided by transaction count.
        - calculate percentage shares to identify dominant payment methods.
*/

with payment_distribution as (
    -- step 1: aggregate metrics at the payment type level
    select 
        payment_type,
        count(*) as transaction_count,
        sum(payment_value) as total_revenue,
        avg(payment_value) as avg_transaction_value
    from 
        payments
    group by 
        payment_type
),

global_metrics as (
    -- step 2: get platform-wide totals for percentage calculations
    select 
        sum(total_revenue) as grand_total_revenue
    from 
        payment_distribution
)

-- final output: comparing payment methods and identifying value differences
select 
    pd.payment_type,
    pd.transaction_count,
    cast(pd.total_revenue as decimal(15,2)) as revenue_contribution,
    -- revenue share percentage
    cast(100.0 * pd.total_revenue / gm.grand_total_revenue as decimal(5,2)) as revenue_share_pct,
    -- average transaction value (atv)
    cast(pd.avg_transaction_value as decimal(10,2)) as atv,
    -- comparison logic specifically for credit card vs boleto
    case 
        when pd.payment_type = 'credit_card' then 'High Convenience / Installment Potential'
        when pd.payment_type = 'boleto' then 'Cash-based / Single Payment'
        else 'Alternative Method'
    end as payment_profile
from 
    payment_distribution pd
cross join 
    global_metrics gm
order by 
    revenue_contribution desc;
go



-- QUESTION 2.
/*
 "Is there a positive correlation between the number of installments chosen (`payment_installments`) and 
 the total order value? Specifically, what percentage of high-ticket orders (\>R\$500) are purchased using 5+ installments?"
*/
/* PART 1: Payment Method & Transaction Value Analysis
    Objective: 
        1. Analyze the distribution of revenue across payment types.
        2. Compare average transaction value (atv) between credit card and boleto users.
*/

with payment_distribution as (
    -- step 1: aggregate metrics at the payment type level
    select 
        payment_type,
        count(*) as transaction_count,
        sum(payment_value) as total_revenue,
        avg(payment_value) as avg_transaction_value
    from 
        payments
    group by 
        payment_type
),

global_metrics as (
    -- step 2: get platform-wide totals for percentage calculations
    select 
        sum(total_revenue) as grand_total_revenue
    from 
        payment_distribution
)

-- output 1: comparing payment methods and identifying value differences
select 
    pd.payment_type,
    pd.transaction_count,
    cast(pd.total_revenue as decimal(15,2)) as revenue_contribution,
    cast(100.0 * pd.total_revenue / gm.grand_total_revenue as decimal(5,2)) as revenue_share_pct,
    cast(pd.avg_transaction_value as decimal(10,2)) as atv
from 
    payment_distribution pd
cross join 
    global_metrics gm
order by 
    revenue_contribution desc;


/* PART 2: Installment Correlation & High-Ticket Analysis
    Objective: 
        1. Analyze if higher installment counts correlate with higher order values.
        2. Calculate the % of high-ticket orders (>R$500) using 5+ installments.
*/

with installment_stats as (
    -- step 1: calculate average value per installment count
    select 
        payment_installments,
        count(*) as order_count,
        avg(payment_value) as avg_payment_value
    from 
        payments
    where 
        payment_type = 'credit_card' -- installments primarily apply to credit cards
        and payment_installments > 0
    group by 
        payment_installments
),

high_ticket_segment as (
    -- step 2: isolate high-ticket orders and check installment counts
    select 
        count(*) as total_high_ticket_orders,
        sum(case when payment_installments >= 5 then 1 else 0 end) as high_installment_count
    from 
        payments
    where 
        payment_value > 500
        and payment_type = 'credit_card'
)

-- output 2: identifying the "financing" behavior of high-value customers
select 
    h.total_high_ticket_orders,
    h.high_installment_count,
    -- percentage of high-ticket users who "finance" via 5+ installments
    cast(100.0 * h.high_installment_count / h.total_high_ticket_orders as decimal(5,2)) as high_ticket_financing_pct,
    -- referencing the average value for 1 installment vs 10 installments for context
    (select cast(avg_payment_value as decimal(10,2)) from installment_stats where payment_installments = 1) as avg_val_1_inst,
    (select cast(avg_payment_value as decimal(10,2)) from installment_stats where payment_installments = 10) as avg_val_10_inst
from 
    high_ticket_segment h;
go




-- QUESTION 3.
/*"How does payment preference vary by region (`customer_state`)? Are there specific states where 
"Boleto' usage is disproportionately high compared to the national average, 
indicating a lower penetration of credit cards?"*/

/* PART 1: Payment Method & Transaction Value Analysis
    Objective: 
        1. Analyze the distribution of revenue across payment types.
        2. Compare average transaction value (atv) between credit card and boleto users.
*/

with payment_distribution as (
    -- step 1: aggregate metrics at the payment type level
    select 
        payment_type,
        count(*) as transaction_count,
        sum(payment_value) as total_revenue,
        avg(payment_value) as avg_transaction_value
    from 
        payments
    group by 
        payment_type
),

global_metrics as (
    -- step 2: get platform-wide totals for percentage calculations
    select 
        sum(total_revenue) as grand_total_revenue
    from 
        payment_distribution
)

-- output 1: comparing payment methods and identifying value differences
select 
    pd.payment_type,
    pd.transaction_count,
    cast(pd.total_revenue as decimal(15,2)) as revenue_contribution,
    cast(100.0 * pd.total_revenue / gm.grand_total_revenue as decimal(5,2)) as revenue_share_pct,
    cast(pd.avg_transaction_value as decimal(10,2)) as atv
from 
    payment_distribution pd
cross join 
    global_metrics gm
order by 
    revenue_contribution desc;


/* PART 2: Installment Correlation & High-Ticket Analysis
    Objective: 
        1. Analyze if higher installment counts correlate with higher order values.
        2. Calculate the % of high-ticket orders (>R$500) using 5+ installments.
*/

with installment_stats as (
    -- step 1: calculate average value per installment count
    select 
        payment_installments,
        count(*) as order_count,
        avg(payment_value) as avg_payment_value
    from 
        payments
    where 
        payment_type = 'credit_card' -- installments primarily apply to credit cards
        and payment_installments > 0
    group by 
        payment_installments
),

high_ticket_segment as (
    -- step 2: isolate high-ticket orders and check installment counts
    select 
        count(*) as total_high_ticket_orders,
        sum(case when payment_installments >= 5 then 1 else 0 end) as high_installment_count
    from 
        payments
    where 
        payment_value > 500
        and payment_type = 'credit_card'
)

-- output 2: identifying the "financing" behavior of high-value customers
select 
    h.total_high_ticket_orders,
    h.high_installment_count,
    -- percentage of high-ticket users who "finance" via 5+ installments
    cast(100.0 * h.high_installment_count / h.total_high_ticket_orders as decimal(5,2)) as high_ticket_financing_pct,
    -- referencing the average value for 1 installment vs 10 installments for context
    (select cast(avg_payment_value as decimal(10,2)) from installment_stats where payment_installments = 1) as avg_val_1_inst,
    (select cast(avg_payment_value as decimal(10,2)) from installment_stats where payment_installments = 10) as avg_val_10_inst
from 
    high_ticket_segment h;


/* PART 3: Regional Payment Preferences & Boleto Penetration
    Objective: 
        1. Determine how payment preferences vary by customer state.
        2. Identify states where Boleto usage is significantly higher than the national average.
*/

with state_payment_counts as (
    -- step 1: count payment types per state
    select 
        c.customer_state,
        count(p.payment_type) as total_payments,
        sum(case when p.payment_type = 'boleto' then 1 else 0 end) as boleto_count,
        sum(case when p.payment_type = 'credit_card' then 1 else 0 end) as credit_card_count
    from 
        payments p
    inner join 
        orders o on p.order_id = o.order_id
    inner join 
        customers c on o.customer_id = c.customer_id
    group by 
        c.customer_state
),

state_boleto_share as (
    -- step 2: calculate state-level boleto share and the national benchmark
    select 
        customer_state,
        total_payments,
        cast(100.0 * boleto_count / total_payments as decimal(5,2)) as state_boleto_pct,
        -- national benchmark using window function
        avg(100.0 * boleto_count / total_payments) over () as national_avg_boleto_pct
    from 
        state_payment_counts
)

-- output 3: identifying regional outliers in payment behavior
select 
    customer_state,
    total_payments,
    state_boleto_pct,
    cast(national_avg_boleto_pct as decimal(5,2)) as national_avg_pct,
    -- deviation from national norm
    cast(state_boleto_pct - national_avg_boleto_pct as decimal(5,2)) as percentage_point_diff,
    case 
        when state_boleto_pct > national_avg_boleto_pct + 5 then 'High Boleto Usage (Low Credit Penetration)'
        when state_boleto_pct < national_avg_boleto_pct - 5 then 'High Credit Usage (Digital/Banked Hub)'
        else 'Standard Regional Mix'
    end as regional_payment_profile
from 
    state_boleto_share
order by 
    state_boleto_pct desc;
go


