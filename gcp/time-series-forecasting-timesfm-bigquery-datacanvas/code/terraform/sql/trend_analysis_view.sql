-- Trend Analysis View for Advanced Analytics
-- Provides moving averages, volatility metrics, and trend indicators

WITH price_metrics AS (
  SELECT 
    symbol,
    date,
    close_price,
    volume,
    market_cap,
    -- Moving averages
    AVG(close_price) OVER (
      PARTITION BY symbol 
      ORDER BY date 
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) as seven_day_avg,
    AVG(close_price) OVER (
      PARTITION BY symbol 
      ORDER BY date 
      ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
    ) as twenty_day_avg,
    AVG(close_price) OVER (
      PARTITION BY symbol 
      ORDER BY date 
      ROWS BETWEEN 49 PRECEDING AND CURRENT ROW
    ) as fifty_day_avg,
    -- Volatility measurements
    STDDEV(close_price) OVER (
      PARTITION BY symbol 
      ORDER BY date 
      ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
    ) as twenty_day_volatility,
    STDDEV(close_price) OVER (
      PARTITION BY symbol 
      ORDER BY date 
      ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) as thirty_day_volatility,
    -- Price changes
    LAG(close_price, 1) OVER (PARTITION BY symbol ORDER BY date) as prev_close,
    LAG(close_price, 7) OVER (PARTITION BY symbol ORDER BY date) as week_ago_close,
    LAG(close_price, 30) OVER (PARTITION BY symbol ORDER BY date) as month_ago_close,
    -- Volume metrics
    AVG(volume) OVER (
      PARTITION BY symbol 
      ORDER BY date 
      ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
    ) as avg_volume_20d
  FROM `${project_id}.${dataset_name}.stock_prices`
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 YEAR)
)

SELECT 
  symbol,
  date,
  close_price,
  volume,
  market_cap,
  seven_day_avg,
  twenty_day_avg,
  fifty_day_avg,
  twenty_day_volatility,
  thirty_day_volatility,
  prev_close,
  week_ago_close,
  month_ago_close,
  avg_volume_20d,
  -- Daily return calculations
  CASE 
    WHEN prev_close IS NOT NULL AND prev_close > 0 
    THEN (close_price - prev_close) / prev_close * 100
    ELSE NULL 
  END as daily_return,
  -- Weekly return
  CASE 
    WHEN week_ago_close IS NOT NULL AND week_ago_close > 0 
    THEN (close_price - week_ago_close) / week_ago_close * 100
    ELSE NULL 
  END as weekly_return,
  -- Monthly return
  CASE 
    WHEN month_ago_close IS NOT NULL AND month_ago_close > 0 
    THEN (close_price - month_ago_close) / month_ago_close * 100
    ELSE NULL 
  END as monthly_return,
  -- Technical indicators
  CASE 
    WHEN seven_day_avg > twenty_day_avg AND twenty_day_avg > fifty_day_avg 
    THEN 'Uptrend'
    WHEN seven_day_avg < twenty_day_avg AND twenty_day_avg < fifty_day_avg 
    THEN 'Downtrend'
    ELSE 'Sideways'
  END as trend_direction,
  -- Volatility classification
  CASE 
    WHEN twenty_day_volatility IS NULL THEN 'Unknown'
    WHEN twenty_day_volatility / close_price * 100 < 2 THEN 'Low Volatility'
    WHEN twenty_day_volatility / close_price * 100 < 5 THEN 'Medium Volatility'
    ELSE 'High Volatility'
  END as volatility_classification,
  -- Volume analysis
  CASE 
    WHEN avg_volume_20d IS NOT NULL AND volume > avg_volume_20d * 1.5 
    THEN 'High Volume'
    WHEN avg_volume_20d IS NOT NULL AND volume < avg_volume_20d * 0.5 
    THEN 'Low Volume'
    ELSE 'Normal Volume'
  END as volume_classification,
  -- Relative strength (vs 20-day average)
  CASE 
    WHEN twenty_day_avg IS NOT NULL AND twenty_day_avg > 0
    THEN (close_price - twenty_day_avg) / twenty_day_avg * 100
    ELSE NULL
  END as relative_strength_20d,
  -- Bollinger Band position (simplified)
  CASE 
    WHEN twenty_day_avg IS NOT NULL AND twenty_day_volatility IS NOT NULL
    THEN (close_price - twenty_day_avg) / (twenty_day_volatility * 2) * 100
    ELSE NULL
  END as bollinger_position
FROM price_metrics
ORDER BY symbol, date DESC