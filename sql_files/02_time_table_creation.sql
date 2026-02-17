USE [Olist-E-Commerce];
EXEC sp_changedbowner 'sa';
go 


/*
In this SQL file, the following operations will be done: 
	- creating the new dimension table - Calendar: for time-series analysis
	- dropping unnecessary columns in each table if exists any
	- creating new features for each suitable table using the existing 
*/


-- CREATE NEW TABLE - CALENDAR 
select
	table_name,
	column_name
from INFORMATION_SCHEMA.columns 

-- select the minimum date in the whole database
select min(shipping_limit_date) from order_items; -- 2016-09-19
select max(shipping_limit_date) from order_items; -- 2020-04-09


select 
	min(order_approved_at) as min_order_approved, 
	min(order_purchase_timestamp) as min_order_purchased, 

	max(order_estimated_delivery_date) as max_estimated_delivery, 
	max(order_delivered_customer_date) as max_delivered_customer
from orders;

-- max: 2018-11-12 00:00:00.0000000;  min: 2016-09-04 21:15:19.0000000


select
	min(review_creation_date),
	max(review_answer_timestamp)
from order_reviews;

-- max: 2018-10-29 12:27:35.000; min: 2016-10-02 00:00:00.000

-- so, min date :2016-01-01
-- max date: 2020-04-30



DECLARE @start_date date = '2016-01-01';
DECLARE @end_date date = '2020-04-30';



SET DATEFIRST 1; 

DROP TABLE IF EXISTS dbo.Calendar;

create table dbo.Calendar(
	datekey int not null primary key, 
	full_date datetime2 not null,
	[year] int not null,
	semester int not null, 
	[quarter] int not null,
	month_number int not null, 
	month_name varchar(10) not null,
	week_of_year int not null, 
	week_of_month int not null,
	day_name varchar(10) not  null, 
	day_of_week int not  null,
	day_of_month int not null, 
	day_of_year int not null,
	is_weekend bit not null
)


DECLARE @d date = @start_date; 
WHILE @d <= @end_date
BEGIN
	INSERT INTO dbo.Calendar(
		datekey, full_date, [year], semester, [quarter],
        month_number, month_name, week_of_year, week_of_month,
        day_name, day_of_week, day_of_month, day_of_year, is_weekend
    )
	VALUES (
		convert(int, format(@d, 'yyyyMMdd')),
		cast(@d as datetime2),
		year(@d),
		case when month(@d) <= 6 then 1 else 2 end, 
		datepart(quarter, @d),
		month(@d), 
		datename(month, @d), 
		datepart(week, @d), 
		datediff(week, DATEFROMPARTS(year(@d), month(@d), 1), @d) + 1, 
		datename(weekday, @d), 
		datepart(weekday, @d), 
		day(@d), 
		datepart(DAYOFYEAR, @d),
		case when DATEPART(weekday, @d) in (6,7) then 1 else 0 end
	);

	set @d = DATEADD(day, 1, @d);
END;

SELECT MIN(full_date) AS min_date,
       MAX(full_date) AS max_date,
       COUNT(*)       AS day_count
FROM dbo.Calendar;



-- BUILD RELATIONSHIP BETWEEN CALENDAR AND ORDERS

/* following foreign keys must be created to make relationships:
	- order_purchase_datekey
	- order_approved_datekey
	- delivered_carrier_datekey
	- delivered_customer_datekey
	- estimated_datekey
*/

alter table orders 
add 
	purchase_datekey int null,
	approved_datekey int null, 
	delivered_datekey int null, 
	estimated_datekey int null;
go 



update orders 
set 
	purchase_datekey = convert(int, format(order_purchase_timestamp, 'yyyyMMdd')), 
	approved_datekey = convert(int, format(order_approved_at, 'yyyyMMdd')), 
	delivered_datekey = convert(int, format(order_delivered_customer_date, 'yyyyMMdd')), 
	estimated_datekey = convert(int, format(order_estimated_delivery_date, 'yyyyMMdd'));
go


alter table orders add constraint FK_orders_calendar_purchase 
foreign key (purchase_datekey) 
references Calendar(datekey);
go



alter table orders add constraint FK_orders_calendar_approved
foreign key (approved_datekey) 
references Calendar(datekey);
go


alter table orders add constraint FK_orders_calendar_delivered
foreign key (delivered_datekey) 
references Calendar(datekey);
go



alter table orders add constraint FK_orders_calendar_estimated
foreign key (estimated_datekey) 
references Calendar(datekey);
go














