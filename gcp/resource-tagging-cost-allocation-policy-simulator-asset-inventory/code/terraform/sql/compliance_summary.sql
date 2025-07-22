-- Tag compliance summary view
-- Provides compliance metrics and trend analysis for resource tagging

SELECT
  DATE(timestamp) as compliance_date,
  resource_type,
  department,
  cost_center,
  environment,
  project_code,
  -- Compliance metrics
  COUNT(*) as total_resources,
  SUM(CASE WHEN compliant THEN 1 ELSE 0 END) as compliant_resources,
  SUM(CASE WHEN NOT compliant THEN 1 ELSE 0 END) as non_compliant_resources,
  ROUND(100.0 * SUM(CASE WHEN compliant THEN 1 ELSE 0 END) / COUNT(*), 2) as compliance_percentage,
  -- Trend analysis (compare to previous day)
  LAG(COUNT(*)) OVER (
    PARTITION BY resource_type, department 
    ORDER BY DATE(timestamp)
  ) as prev_day_total,
  LAG(SUM(CASE WHEN compliant THEN 1 ELSE 0 END)) OVER (
    PARTITION BY resource_type, department 
    ORDER BY DATE(timestamp)
  ) as prev_day_compliant,
  -- Compliance improvement calculation
  ROUND(
    100.0 * SUM(CASE WHEN compliant THEN 1 ELSE 0 END) / COUNT(*) -
    LAG(100.0 * SUM(CASE WHEN compliant THEN 1 ELSE 0 END) / COUNT(*)) OVER (
      PARTITION BY resource_type, department 
      ORDER BY DATE(timestamp)
    ), 2
  ) as compliance_change_pct
FROM `${project_id}.${dataset_name}.tag_compliance`
WHERE
  -- Filter to recent data (last 30 days)
  DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY
  compliance_date, 
  resource_type, 
  department, 
  cost_center, 
  environment,
  project_code
ORDER BY
  compliance_date DESC, 
  compliance_percentage ASC,
  total_resources DESC