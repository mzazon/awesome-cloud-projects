-- Forecast Analytics View for DataCanvas Integration
-- Compares actual vs forecast values for accuracy assessment

WITH actual_vs_forecast AS (
  SELECT 
    f.symbol,
    f.forecast_timestamp,
    f.forecast_value,
    f.prediction_interval_lower_bound,
    f.prediction_interval_upper_bound,
    f.confidence_level,
    f.forecast_created_at,
    a.close_price as actual_value,
    ABS(f.forecast_value - a.close_price) as absolute_error,
    CASE 
      WHEN a.close_price IS NOT NULL AND a.close_price > 0 
      THEN ABS(f.forecast_value - a.close_price) / a.close_price * 100
      ELSE NULL 
    END as percentage_error,
    CASE 
      WHEN a.close_price IS NOT NULL 
        AND a.close_price BETWEEN f.prediction_interval_lower_bound AND f.prediction_interval_upper_bound 
      THEN 'Within Confidence Interval' 
      WHEN a.close_price IS NOT NULL
      THEN 'Outside Confidence Interval'
      ELSE 'No Actual Data'
    END as accuracy_status
  FROM `${project_id}.${dataset_name}.timesfm_forecasts` f
  LEFT JOIN `${project_id}.${dataset_name}.stock_prices` a
    ON f.symbol = a.symbol 
    AND DATE(f.forecast_timestamp) = a.date
)

SELECT 
  symbol,
  DATE(forecast_timestamp) as forecast_date,
  forecast_timestamp,
  forecast_value,
  actual_value,
  absolute_error,
  percentage_error,
  accuracy_status,
  prediction_interval_lower_bound,
  prediction_interval_upper_bound,
  confidence_level,
  forecast_created_at,
  -- Additional analytics columns
  CASE 
    WHEN percentage_error IS NULL THEN 'N/A'
    WHEN percentage_error <= 5 THEN 'Excellent'
    WHEN percentage_error <= 10 THEN 'Good'
    WHEN percentage_error <= 20 THEN 'Fair'
    ELSE 'Poor'
  END as accuracy_grade,
  -- Forecast age in days
  DATE_DIFF(DATE(forecast_timestamp), DATE(forecast_created_at), DAY) as forecast_horizon_days,
  -- Market movement direction accuracy
  CASE 
    WHEN actual_value IS NOT NULL AND LAG(actual_value) OVER (PARTITION BY symbol ORDER BY forecast_timestamp) IS NOT NULL
    THEN CASE
      WHEN (forecast_value > LAG(forecast_value) OVER (PARTITION BY symbol ORDER BY forecast_timestamp)) 
           AND (actual_value > LAG(actual_value) OVER (PARTITION BY symbol ORDER BY forecast_timestamp))
      THEN 'Correct Direction'
      WHEN (forecast_value < LAG(forecast_value) OVER (PARTITION BY symbol ORDER BY forecast_timestamp)) 
           AND (actual_value < LAG(actual_value) OVER (PARTITION BY symbol ORDER BY forecast_timestamp))
      THEN 'Correct Direction'
      WHEN (forecast_value = LAG(forecast_value) OVER (PARTITION BY symbol ORDER BY forecast_timestamp)) 
           AND (actual_value = LAG(actual_value) OVER (PARTITION BY symbol ORDER BY forecast_timestamp))
      THEN 'Correct Direction'
      ELSE 'Wrong Direction'
    END
    ELSE 'N/A'
  END as direction_accuracy
FROM actual_vs_forecast
WHERE forecast_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
ORDER BY symbol, forecast_timestamp DESC