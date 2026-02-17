
# Olist E-Commerce Marketplace Intelligence System

End-to-End SQL Analytics | Revenue Growth | Customer Retention | Operational Diagnostics

Dataset: Brazilian E-Commerce Public Dataset (Olist): https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

Database: Microsoft SQL Server

---

## Project Overview

This repository builds a production-style analytical database and marketplace intelligence system using advanced SQL.

The goal is not simple reporting.

The goal is to evaluate the structural health of a digital marketplace across:

* Revenue growth
* Product portfolio balance
* Customer retention & churn
* Seller ecosystem performance
* Delivery & logistics efficiency
* Payment risk structure
* Customer experience impact

All analysis is modularized into structured SQL files for clarity, maintainability, and scalability.

---

# Repository Structure & File Responsibilities

## 01_data_type_normalization.sql

Purpose: Data Engineering Foundation

What it does:

* Imports raw data
* Converts generic VARCHAR staging types into correct numeric/date types
* Defines PRIMARY KEY constraints
* Defines FOREIGN KEY constraints
* Creates indexes for performance optimization

Why it matters:

* Ensures referential integrity
* Prevents data inconsistency
* Improves join and aggregation speed
* Establishes production-grade relational structure

This file builds the backbone of the system.

---

## 02_time_table_creation.sql

Purpose: Time Dimension Modeling

What it does:

* Creates a dedicated Calendar table
* Generates full date coverage
* Adds year, month, quarter, week attributes
* Links Calendar to Orders table via:

  * purchase date
  * approval date
  * delivery date
  * estimated delivery date

Why it matters:

* Enables clean time-series analysis
* Supports cohort analysis
* Enables rolling averages
* Removes repetitive date logic from queries

This file enables advanced time intelligence.

---

## 03_customer_behavior_and_retention.sql

Purpose: Customer Intelligence

What it includes:

* RFM segmentation (Recency, Frequency, Monetary)
* Cohort retention analysis (1, 3, 6 month return rates)
* Pareto 80/20 validation
* Purchase latency calculation
* Statistical churn risk detection (mean + 2σ deviation logic)

Business value:

* Identifies high-value customers
* Detects churn risk
* Measures retention decay
* Supports CRM targeting strategy

---

## 04_orders_and_sales_performance.sql

Purpose: Core Revenue & Growth Diagnostics

What it includes:

* Monthly revenue aggregation
* Month-over-Month (MoM) growth
* Year-over-Year (YoY) growth
* Seasonal tagging (Black Friday, Holidays, New Year)
* 3-month rolling revenue smoothing
* Variance from long-term trend

Business value:

* Identifies structural growth vs seasonal spikes
* Detects abnormal revenue behavior
* Provides executive-level growth insights

---

## 05_delivery_and_logistics_performance.sql

Purpose: Operational Efficiency Analysis

What it includes:

* Delivery delay calculations
* Estimated vs actual delivery gap analysis
* On-time performance evaluation
* Logistics performance trends

Business value:

* Identifies operational bottlenecks
* Connects logistics performance to customer experience
* Detects fulfillment inefficiencies

---

## 06_seller_performance_and_marketplace_health.sql

Purpose: Seller Ecosystem Evaluation

What it includes:

* Seller-level revenue contribution
* Order volume performance
* Delivery reliability by seller
* Marketplace dependency concentration

Business value:

* Identifies top-performing sellers
* Detects risky or underperforming sellers
* Evaluates revenue concentration risk

---

## 07_payments_and_financial_risk.sql

Purpose: Financial Structure & Risk Analysis

What it includes:

* Payment type distribution
* Installment usage patterns
* Multi-payment order behavior
* Revenue exposure analysis

Business value:

* Assesses financial risk exposure
* Evaluates cash flow sensitivity
* Detects installment-heavy revenue dependency

---

## 08_customer_experience_and_reviews.sql

Purpose: Customer Satisfaction Analysis

What it includes:

* Review score distribution
* Delivery impact on review ratings
* Correlation between delays and negative reviews
* Experience-driven churn indicators

Business value:

* Quantifies operational impact on satisfaction
* Identifies drivers of negative feedback
* Links service quality to marketplace health

---

## 09_time_seasonality_and_growth.sql

Purpose: Advanced Time-Based Revenue Diagnostics

What it includes:

* Seasonal demand classification
* Revenue volatility smoothing
* Rolling average modeling
* Growth variance analysis

Business value:

* Identifies cyclical demand patterns
* Supports forecasting baseline creation
* Distinguishes noise from structural change

---

## 10_data_aggregation.sql

Purpose: Analytical Mart Construction

What it includes:

* Pre-aggregated analytical views
* Order-level financial correctness validation
* Duplicate prevention logic
* Basket size and AOV preparation

Business value:

* Ensures metric correctness
* Prevents revenue inflation
* Supports BI tool integration

---

# Analytical Themes Covered

Revenue Intelligence
Customer Lifecycle & Retention
Seller Ecosystem Stability
Operational Efficiency
Financial Risk Exposure
Product Portfolio Strategy
Regional Market Dynamics
Basket Economics

---

# Technical Competencies Demonstrated

Advanced SQL techniques:

* CTE-based modular architecture
* Window functions (LAG, RANK, PERCENT_RANK, rolling windows)
* Statistical threshold detection
* Cohort modeling
* Time-series smoothing
* Pre-aggregation strategies
* Referential integrity enforcement
* Performance indexing
* Duplicate-safe financial aggregation

---

# Why This Project Stands Out

This is not a collection of isolated SQL queries.

It is a structured marketplace intelligence framework.

It demonstrates:

* Data engineering discipline
* Analytical architecture design
* Business-first thinking
* Statistical reasoning inside SQL
* Financial metric integrity awareness
* Operational diagnostics capability

---

If you want, I can now:

* Make this even sharper and more minimal (Big Tech portfolio style)
* Add architecture diagram explanation section
* Add “How to Run the Project” section
* Add BI integration instructions (Tableau / Power BI)
* Convert this into a visually enhanced GitHub version with badges

Tell me the direction.
