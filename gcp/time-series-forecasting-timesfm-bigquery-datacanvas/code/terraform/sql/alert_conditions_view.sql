-- Alert Conditions View for Monitoring
-- Identifies forecast accuracy issues and system alerts

WITH recent_metrics AS (
  SELECT 
    symbol,
    metric_date,
    avg_percentage_error,
    error_std_dev,
    forecast_count,
    accuracy_rate,
    calculated_at,
    -- Calculate rolling averages for trend detection
    AVG(avg_percentage_error) OVER (
      PARTITION BY symbol 
      ORDER BY metric_date 
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) as rolling_7d_error,
    AVG(accuracy_rate) OVER (
      PARTITION BY symbol 
      ORDER BY metric_date 
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) as rolling_7d_accuracy
  FROM `${project_id}.${dataset_name}.forecast_metrics`
  WHERE metric_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
    AND forecast_count > 0
)

SELECT 
  symbol,
  metric_date,
  avg_percentage_error,
  error_std_dev,
  forecast_count,
  accuracy_rate,
  rolling_7d_error,
  rolling_7d_accuracy,
  calculated_at,
  -- Primary alert conditions
  CASE 
    WHEN avg_percentage_error > 20 THEN 'HIGH_ERROR'
    WHEN accuracy_rate < 60 THEN 'LOW_ACCURACY'
    WHEN forecast_count < 3 THEN 'INSUFFICIENT_DATA'
    WHEN error_std_dev > 15 THEN 'HIGH_VARIANCE'
    WHEN rolling_7d_error > 15 THEN 'TRENDING_ERROR'
    WHEN rolling_7d_accuracy < 70 THEN 'TRENDING_LOW_ACCURACY'
    ELSE 'NORMAL'
  END as alert_level,
  -- Detailed alert messages
  CASE 
    WHEN avg_percentage_error > 20 
    THEN CONCAT('High forecast error: ', ROUND(avg_percentage_error, 2), '%')
    WHEN accuracy_rate < 60 
    THEN CONCAT('Low accuracy rate: ', ROUND(accuracy_rate, 2), '%')
    WHEN forecast_count < 3 
    THEN CONCAT('Insufficient forecasts: ', forecast_count, ' samples')
    WHEN error_std_dev > 15 
    THEN CONCAT('High error variance: ', ROUND(error_std_dev, 2), '%')
    WHEN rolling_7d_error > 15 
    THEN CONCAT('Increasing error trend: ', ROUND(rolling_7d_error, 2), '% (7-day avg)')
    WHEN rolling_7d_accuracy < 70 
    THEN CONCAT('Decreasing accuracy trend: ', ROUND(rolling_7d_accuracy, 2), '% (7-day avg)')
    ELSE 'Performance within normal parameters'
  END as alert_message,
  -- Alert priority
  CASE 
    WHEN avg_percentage_error > 25 OR accuracy_rate < 50 THEN 'CRITICAL'
    WHEN avg_percentage_error > 20 OR accuracy_rate < 60 OR rolling_7d_error > 15 THEN 'HIGH'
    WHEN avg_percentage_error > 15 OR accuracy_rate < 70 OR error_std_dev > 15 THEN 'MEDIUM'
    WHEN forecast_count < 3 THEN 'LOW'
    ELSE 'INFO'
  END as alert_priority,
  -- Recommendations
  CASE 
    WHEN avg_percentage_error > 20 AND error_std_dev > 15 
    THEN 'Consider model retraining or parameter adjustment'
    WHEN accuracy_rate < 60 
    THEN 'Review confidence interval settings'
    WHEN forecast_count < 3 
    THEN 'Increase data collection frequency'
    WHEN rolling_7d_error > rolling_7d_error * 1.2 
    THEN 'Investigate recent market conditions'
    ELSE 'Continue monitoring'
  END as recommendation,
  -- Business impact assessment
  CASE 
    WHEN avg_percentage_error > 20 THEN 'High financial risk'
    WHEN accuracy_rate < 60 THEN 'Low forecast reliability'
    WHEN rolling_7d_error > 15 THEN 'Declining model performance'
    ELSE 'Low impact'
  END as business_impact
FROM recent_metrics
WHERE metric_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
ORDER BY 
  CASE alert_priority
    WHEN 'CRITICAL' THEN 1
    WHEN 'HIGH' THEN 2
    WHEN 'MEDIUM' THEN 3
    WHEN 'LOW' THEN 4
    ELSE 5
  END,
  symbol,
  metric_date DESC