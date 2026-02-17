USE [Olist-E-Commerce];
EXEC sp_changedbowner 'sa';
go 



/*
In this sql file, following operations will be done: 
	- data import (using the Tasks -> Import Flat Data) 
	- initially, all columns will be imported as varchar(100) (some long ones are varchar(1000))
	- data type conversions for each table
	- setting the primary keys for each table (if there is a convenient column in the table) 
	- setting the foreign keys for each table = building relationships
	- creating the Database Diagram
	- indexes: for fast / optimized sql queries later.
*/


-- MAKE DATA TYPE CONVERSIONS BEFORE STARTING ANALYSIS


-- ----------------CUSTOMERS TABLE--------------------

-- 1. CHECK THE CURRENT DATA TYPES OF EACH COLUMN

SELECT 
	COLUMN_NAME,
	DATA_TYPE, 
	CHARACTER_MAXIMUM_LENGTH, 
	IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'customers' 
	AND TABLE_SCHEMA = 'dbo';
go	

/* 
Conversions must be done: 
- customer_id (nvarchar(50), is_nullable) -> customer_id (varchar(50), not_nullable) 
- varchar is aSCII (english alphabet) so 1 byte,  but nvarchar is unicode so 2 byte. For IDs, use varchar, 
- customer_unique_id (nvarchar(50)) -> varchar(50)
- set customer_id as primary key
*/

alter table customers alter column customer_id varchar(100) not null; 
alter table customers alter column customer_unique_id varchar(100) not null;


-- MAKE customer_unique_id PRIMARY KEY
alter table customers add constraint PK_customers primary key (customer_id); 




-- ------------GEOLOCATION TABLE----------------------------
SELECT 
	COLUMN_NAME,
	DATA_TYPE, 
	CHARACTER_MAXIMUM_LENGTH, 
	IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'geolocation' 
	AND TABLE_SCHEMA = 'dbo';
go	

/* Do the following changes: 

- geolocatino_zip_code_prefix -> int 
- geolocation_lat -> decimal(9,6)
- geolocatino_lng -> decimal(9,6)

*/

alter table geolocation alter column geolocation_zip_code_prefix int; 
alter table geolocation alter column geolocation_lat decimal(9,6); 
alter table geolocation alter column geolocation_lng decimal(9,6); 




-- ------------ORDER ITEMS TABLE----------------------------
SELECT 
	COLUMN_NAME,
	DATA_TYPE, 
	CHARACTER_MAXIMUM_LENGTH, 
	IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'order_items' 
	AND TABLE_SCHEMA = 'dbo';
go	

select top 10 * from order_items;


/*
shipping_limit_date -> datetime
price -> decimal(20,3)
freigh_value -> decimal(20,3)
*/

alter table order_items alter column order_item_id int not null;
alter table order_items alter column shipping_limit_date DATETIME2 not null;
alter table order_items alter column price decimal(20,3); 
alter table order_items alter column freight_value decimal(20,3); 




-- ------------ORDER REVIEWS TABLE----------------------------
SELECT 
	COLUMN_NAME,
	DATA_TYPE, 
	CHARACTER_MAXIMUM_LENGTH, 
	IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'order_reviews' 
	AND TABLE_SCHEMA = 'dbo';
go	

select top 10 * from order_reviews;


alter table order_reviews alter column review_id varchar(100) not null;
alter table order_reviews alter column review_score int; 
alter table order_reviews alter column review_creation_date datetime; 
alter table order_reviews alter column review_answer_timestamp datetime;


-- primary key 
-- alter table order_reviews add constraint PK_reviews primary key (review_id); 

-- that command above returned error, because there are multiple duplicated review_ids. 
-- therefore, we can use surrogate key instead of this.

alter table order_reviews add review_sk bigint identity(1,1) not null; 

ALTER TABLE order_reviews
ADD CONSTRAINT PK_order_reviews PRIMARY KEY (review_sk);




-- ------------ORDERS TABLE----------------------------
SELECT 
	COLUMN_NAME,
	DATA_TYPE, 
	CHARACTER_MAXIMUM_LENGTH, 
	IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'orders' 
	AND TABLE_SCHEMA = 'dbo';
go	

select top 10 * from orders;


/*
order_id -> primary key
*/
alter table orders alter column order_id varchar(100) not null;
alter table orders add constraint PK_orders primary key (order_id); 
go




-- ------------PAYMENTS TABLE----------------------------
SELECT 
	COLUMN_NAME,
	DATA_TYPE, 
	CHARACTER_MAXIMUM_LENGTH, 
	IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'payments' 
	AND TABLE_SCHEMA = 'dbo';
go	

select top 10 * from payments;


/* 
payment_sequential -> int
payment_installments -> int
payment_value -> decimal(20,3)
*/
alter table payments alter column payment_sequential int;
alter table payments alter column payment_installments int;
alter table payments alter column payment_value decimal(20,3);




-- ------------PRODUCTS TABLE----------------------------
SELECT 
	COLUMN_NAME,
	DATA_TYPE, 
	CHARACTER_MAXIMUM_LENGTH, 
	IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'products' 
	AND TABLE_SCHEMA = 'dbo';
go	

select top 10 * from products;



alter table products alter column product_id varchar(100) not null; 
alter table products alter column product_photos_qty int;
alter table products alter column product_weight_g int;
alter table products alter column product_length_cm int;
alter table products alter column product_height_cm int;
alter table products alter column product_width_cm int;

-- product_id primary key
alter table products add constraint PK_products primary key (product_id);
go


-- ------------SELLERS TABLE----------------------------
SELECT 
	COLUMN_NAME,
	DATA_TYPE, 
	CHARACTER_MAXIMUM_LENGTH, 
	IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'sellers' 
	AND TABLE_SCHEMA = 'dbo';
go	

select top 10 * from sellers;


alter table sellers alter column seller_id varchar(100) not null; 
alter table sellers alter column seller_zip_code_prefix int; 
go 

-- add primary key
alter table sellers add constraint PK_sellers primary key (seller_id);
go




-- BUILD RELATIONSHIPS AMONG TABLES

-- --------ORDERS AND CUSTOMERS-----------------------
alter table orders add constraint FK_orders_customers
foreign key (customer_id) 
references customers(customer_id);


-- --------ORDER ITEMS AND ORDERS-----------------------

select top 5 * from order_items;

alter table order_items add constraint FK_orderitems_orders 
foreign key (order_id)
references orders(order_id);



-- --------ORDER ITEMS AND PRODUCTS-----------------------

alter table order_items add constraint FK_orderitems_products 
foreign key (product_id)
references products(product_id);




-- --------ORDER ITEMS AND SELLERS-----------------------
select top 5 * from order_items;

alter table order_items add constraint FK_orderitems_sellers 
foreign key (seller_id)
references sellers(seller_id);





-- --------ORDER REVIEWS AND ORDERS-----------------------
select top 5 * from order_reviews;

alter table order_reviews add constraint FK_reviews_orders
foreign key (order_id)
references orders(order_id); 
go


-- --------ORDER PAYMENTS AND ORDERS-----------------------
select top 5 * from payments;

alter table payments add constraint FK_payments_orders
foreign key (order_id)
references orders(order_id); 
go




-- VALIDITY CHECK
SELECT
    fk.name                AS foreign_key_name,
    OBJECT_SCHEMA_NAME(fk.parent_object_id) AS child_schema,
    OBJECT_NAME(fk.parent_object_id)        AS child_table,
    c1.name                AS child_column,
    OBJECT_SCHEMA_NAME(fk.referenced_object_id) AS parent_schema,
    OBJECT_NAME(fk.referenced_object_id)        AS parent_table,
    c2.name                AS parent_column
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc
  ON fk.object_id = fkc.constraint_object_id
JOIN sys.columns c1
  ON c1.object_id = fkc.parent_object_id
 AND c1.column_id = fkc.parent_column_id
JOIN sys.columns c2
  ON c2.object_id = fkc.referenced_object_id
 AND c2.column_id = fkc.referenced_column_id
ORDER BY
    child_table, foreign_key_name;
go


-- CREATE INDEXES TO INCREASE THE SEARCH PERFORMANCE

-- index on orders(customer_id)
create index IX_orders_customer_id on orders(customer_id); 
go 


-- index on order_items(order_id)
create index IX_order_items_order_id on order_items(order_id); 
go 


-- index on order_items(product_id)
create index IX_order_items_product_id on order_items(product_id); 
go 



-- index on order_items(seller_id)
create index IX_order_items_seller_id on order_items(seller_id); 
go 


-- index on payments(order_id)
create index IX_payments_order_id on payments(order_id); 
go 


-- index on order_reviews(order_id)
create index IX_order_reviews_order_id on order_reviews(order_id); 
go 
