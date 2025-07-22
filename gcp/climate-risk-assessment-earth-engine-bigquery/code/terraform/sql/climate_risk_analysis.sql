-- Climate Risk Analysis View
-- This view combines multiple climate indicators into composite risk scores
-- and provides spatial analysis capabilities for climate risk assessment

WITH climate_stats AS (
  SELECT 
    location,
    AVG(avg_day_temp_c) as mean_temp,
    STDDEV(avg_day_temp_c) as temp_variability,
    SUM(total_precipitation_mm) as total_precip,
    AVG(avg_ndvi) as mean_vegetation_health,
    COUNT(*) as data_points,
    
    -- Temperature extremes (above 35°C or below -10°C)
    COUNTIF(avg_day_temp_c > 35) as extreme_heat_days,
    COUNTIF(avg_day_temp_c < -10) as extreme_cold_days,
    
    -- Drought indicator (low precipitation + low vegetation)
    COUNTIF(total_precipitation_mm < 10 AND avg_ndvi < 0.3) as drought_indicators,
    
    -- Calculate geographic centroid for regional analysis
    ST_CENTROID(ST_UNION_AGG(location)) as region_center
  FROM `${project_id}.${dataset_id}.climate_indicators`
  WHERE avg_day_temp_c IS NOT NULL 
    AND total_precipitation_mm IS NOT NULL
    AND avg_ndvi IS NOT NULL
  GROUP BY location
),

risk_scoring AS (
  SELECT *,
    -- Composite risk score (0-100 scale)
    LEAST(100, GREATEST(0, 
      (extreme_heat_days * 2.5) + 
      (drought_indicators * 3.0) + 
      (extreme_cold_days * 1.5) +
      (ABS(temp_variability - 10) * 2.0)
    )) as composite_risk_score,
    
    -- Risk categorization
    CASE 
      WHEN (extreme_heat_days + drought_indicators) > 20 THEN 'HIGH'
      WHEN (extreme_heat_days + drought_indicators) > 10 THEN 'MEDIUM'
      ELSE 'LOW'
    END as risk_category
  FROM climate_stats
)

SELECT 
  location,
  region_center,
  mean_temp,
  temp_variability,
  total_precip,
  mean_vegetation_health,
  extreme_heat_days,
  extreme_cold_days,
  drought_indicators,
  composite_risk_score,
  risk_category,
  
  -- Confidence based on data completeness
  ROUND((data_points / 1460.0) * 100, 1) as data_confidence_pct
FROM risk_scoring
ORDER BY composite_risk_score DESC