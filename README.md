# Olist-E-Commerce-Analysis
Adcanced SQL Queries to analyze sales and delivery performance and improve marketplace health

Link to Kaggle Dataset: https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

`01_data_type_normalization.sql` - in this file raw data is imported to the SQL Server SSMS. All columns are assigned as varchar(100) to prevent any type mismatches during the data ingestion process. Afterward, the data type of each column was reviewed and converted to the appropriate format to ensure accuracy, consistency, and proper analytical processing. Also, <font color = "red">PRIMARY KEY CONSTRAINTS </font> and <font color = "green"> <b> FOREIGN KEY CONSTRAINTS </b> </font> are assigned to the features to build the relationships between the tables. 

`02_time_table_creation` - in this file new table - a table that covers the whole time range in the database - is created. Creating separate date table is essential step in time based analysis as it keeps all time-related calculations consistent and organized. It includes every date in a given range, even if there are no transactions on some days, which helps create accurate trend and time-series analysis. It also stores useful fields like year, month, quarter, and week, so you don’t have to calculate them repeatedly in queries. This makes analysis simpler, more reliable, and easier to maintain. To build the relationship between the date table (`Calendar`), 4 different foreign key columns are added to the `orders` table. These keys correspond to `order_purchase_datekey`, `order_approved_datekey` `delivered_customer_datekey`, `delivery_estimated_datekey`  columns in the orders table. 

To increase the performance of queries the indexes are created for the foreign keys in mostly used tables. You can find them in `01_data_type_normalization.sql`. 
After all regulations, the final database diagram with the established relationships is given below: 


img


sql_files/03_customer_behavior_and_retention.sql: this file answers the customer based questions which are given below:

1. "Can we segment the customer base into distinct clusters—specifically 'Champions', 'Loyalists', 'Hibernating', and 'At Risk'—by scoring each unique user based on the Recency of their last order, 	the Frequency of their purchases, and their total Monetary contribution?"

2. 	"How does customer retention evolve over time when users are grouped by their acquisition month?  Specifically, what percentage of customers acquired in a specific month (e.g., Jan 2017)	return to make a second purchase within months 1, 3, and 6?"

3. "Does the customer base adhere to the '80/20 Rule' (Pareto Principle), where the top 20% of unique customers contribute to 80% of the total revenue? If so, what defines the profile of these top-tier customers?"

4. "For the segment of customers with multiple purchases, what is the average time interval (in days) between consecutive orders? How does this 'purchase latency' vary across different product categories?"

5. "Which customers have exceeded the average purchase cycle by more than 2 standard deviations 
without placing a new order? Can we flag these users as 'High Risk of Churn' based on their 
deviation from the typical repurchase behavior?"





















