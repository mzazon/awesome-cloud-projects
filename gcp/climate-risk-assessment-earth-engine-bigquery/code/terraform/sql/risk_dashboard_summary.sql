-- Risk Dashboard Summary View
-- This view provides both temporal and spatial perspectives on climate risk
-- for comprehensive risk visualization and dashboard creation

WITH temporal_trends AS (
  SELECT 
    DATE_TRUNC(DATE(analysis_date), MONTH) as analysis_month,
    AVG(avg_day_temp_c) as monthly_avg_temp,
    SUM(total_precipitation_mm) as monthly_total_precip,
    AVG(avg_ndvi) as monthly_avg_vegetation,
    COUNT(*) as monthly_observations
  FROM `${project_id}.${dataset_id}.climate_indicators`
  WHERE analysis_date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 3 YEAR)
  GROUP BY analysis_month
),

spatial_risk_summary AS (
  SELECT 
    risk_category,
    COUNT(*) as location_count,
    AVG(composite_risk_score) as avg_risk_score,
    MIN(composite_risk_score) as min_risk_score,
    MAX(composite_risk_score) as max_risk_score,
    
    -- Create geographic bounds for each risk category
    ST_ENVELOPE(ST_UNION_AGG(location)) as risk_region_bounds
  FROM `${project_id}.${dataset_id}.climate_risk_analysis`
  GROUP BY risk_category
)

SELECT 
  'TEMPORAL_TRENDS' as summary_type,
  analysis_month as period,
  monthly_avg_temp as temperature_c,
  monthly_total_precip as precipitation_mm,
  monthly_avg_vegetation as vegetation_index,
  monthly_observations as data_points,
  NULL as risk_category,
  NULL as location_count,
  NULL as risk_bounds
FROM temporal_trends

UNION ALL

SELECT 
  'SPATIAL_RISK' as summary_type,
  NULL as period,
  NULL as temperature_c,
  NULL as precipitation_mm,
  NULL as vegetation_index,
  NULL as data_points,
  risk_category,
  location_count,
  ST_ASGEOJSON(risk_region_bounds) as risk_bounds
FROM spatial_risk_summary
ORDER BY summary_type, period DESC, avg_risk_score DESC