Below is a cleaner, recruiter-oriented version of your README. It focuses on business impact, technical rigor, and analytical depth rather than procedural details.

You can copy this directly into `README.md`.

---

# Olist E-Commerce Analysis

Advanced SQL-Based Marketplace Performance & Customer Intelligence Framework

Dataset: Brazilian E-Commerce Public Dataset by Olist
Source: [https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)

---

## Project Overview

This project transforms raw transactional e-commerce data into a structured analytical database and answers high-impact business questions using advanced SQL.

The objective is to:

* Evaluate marketplace revenue dynamics
* Measure delivery and operational performance
* Quantify customer lifetime value and retention
* Identify churn risks
* Validate Pareto concentration (80/20 rule)
* Support strategic decision-making through behavioral analytics

All analysis is implemented directly in SQL Server using optimized relational modeling and performance-aware design.

---

## Data Engineering & Modeling

### 1. Data Normalization & Relational Integrity

File: `01_data_type_normalization.sql`

* Raw data ingested using varchar staging to prevent type conflicts
* All columns converted to appropriate data types
* PRIMARY KEY constraints defined
* FOREIGN KEY constraints enforced to ensure referential integrity
* Indexes created on high-usage foreign keys to improve join and aggregation performance

Result:
A production-grade relational schema suitable for analytical workloads.

---

### 2. Time Dimension Modeling

File: `02_time_table_creation.sql`

A fully normalized `Calendar` dimension was created to support time-series analysis.

Why this matters:

* Ensures consistent temporal logic across all queries
* Enables reliable cohort, retention, and trend analysis
* Prevents repeated date calculations inside queries
* Includes precomputed attributes: year, month, quarter, week, etc.

Four foreign keys were added to the `orders` table:

* `order_purchase_datekey`
* `order_approved_datekey`
* `delivered_customer_datekey`
* `delivery_estimated_datekey`

This enables multi-event lifecycle analysis of each order.

---

## Customer Intelligence & Behavioral Analytics

File: `03_customer_behavior_and_retention.sql`

This section focuses on customer-level analytical modeling.

### 1. RFM Segmentation

Customers are scored based on:

* Recency (last purchase timing)
* Frequency (number of orders)
* Monetary (total revenue contribution)

Segments include:

* Champions
* Loyalists
* Hibernating
* At Risk

Business value:
Enables targeted retention campaigns and revenue concentration analysis.

---

### 2. Cohort-Based Retention Analysis

Customers grouped by acquisition month.

Measured:

* Month 1 retention
* Month 3 retention
* Month 6 retention

Business value:
Quantifies customer stickiness and marketplace health over time.

---

### 3. Pareto Principle (80/20 Rule)

Validated whether:

Top 20% of customers contribute ~80% of total revenue.

Additionally, profiled high-value customers to understand behavioral patterns.

Business value:
Identifies revenue concentration risk and strategic high-value segments.

---

### 4. Purchase Latency Analysis

For repeat customers:

* Calculated average days between consecutive purchases
* Compared latency across product categories

Business value:
Optimizes remarketing timing and category-level retention strategy.

---

### 5. Churn Risk Detection (Statistical Thresholding)

Identified customers who:

* Exceeded their expected purchase cycle
* Deviated more than 2 standard deviations from average behavior

Flagged as:

High Risk of Churn

Business value:
Enables proactive retention interventions.
