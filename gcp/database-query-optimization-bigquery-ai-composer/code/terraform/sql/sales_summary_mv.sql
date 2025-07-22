-- Sales Summary Materialized View
-- Creates a materialized view for frequently accessed sales aggregations

SELECT 
  DATE(transaction_date) as transaction_date,
  channel,
  COUNT(*) as transaction_count,
  SUM(amount) as total_amount,
  AVG(amount) as avg_amount,
  MIN(amount) as min_amount,
  MAX(amount) as max_amount,
  COUNT(DISTINCT customer_id) as unique_customers,
  COUNT(DISTINCT product_id) as unique_products,
  -- Calculate percentiles for amount distribution
  APPROX_QUANTILES(amount, 100)[OFFSET(50)] as median_amount,
  APPROX_QUANTILES(amount, 100)[OFFSET(25)] as p25_amount,
  APPROX_QUANTILES(amount, 100)[OFFSET(75)] as p75_amount,
  -- Time-based aggregations
  EXTRACT(HOUR FROM transaction_date) as transaction_hour,
  EXTRACT(DAYOFWEEK FROM transaction_date) as day_of_week,
  -- Business metrics
  CASE 
    WHEN COUNT(*) > 1000 THEN 'HIGH_VOLUME'
    WHEN COUNT(*) > 100 THEN 'MEDIUM_VOLUME'
    ELSE 'LOW_VOLUME'
  END as volume_category
FROM `${project_id}.${dataset_id}.sales_transactions`
WHERE 
  transaction_date >= DATE_SUB(CURRENT_DATE(), INTERVAL ${partition_days} DAY)
  AND transaction_date <= CURRENT_DATE()
GROUP BY 
  DATE(transaction_date), 
  channel,
  EXTRACT(HOUR FROM transaction_date),
  EXTRACT(DAYOFWEEK FROM transaction_date)