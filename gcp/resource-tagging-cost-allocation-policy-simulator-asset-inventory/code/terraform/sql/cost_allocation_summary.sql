-- Cost allocation summary view
-- Aggregates billing data with resource metadata for cost allocation analysis

SELECT
  DATE(usage_start_time) as billing_date,
  project.id as project_id,
  service.description as service_name,
  sku.description as sku_description,
  SUM(cost) as total_cost,
  currency,
  location.location as region,
  -- Extract labels from billing export
  (SELECT value FROM UNNEST(labels) WHERE key = 'department') as department,
  (SELECT value FROM UNNEST(labels) WHERE key = 'cost_center') as cost_center,
  (SELECT value FROM UNNEST(labels) WHERE key = 'environment') as environment,
  (SELECT value FROM UNNEST(labels) WHERE key = 'project_code') as project_code,
  COUNT(*) as resource_count,
  -- Additional metrics
  MIN(cost) as min_cost,
  MAX(cost) as max_cost,
  AVG(cost) as avg_cost
FROM `${project_id}.${dataset_name}.gcp_billing_export_v1_*`
WHERE
  -- Filter to recent data (last 30 days)
  DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  -- Only include costs greater than zero
  AND cost > 0
GROUP BY
  billing_date, 
  project_id, 
  service_name, 
  sku_description,
  currency, 
  region,
  department, 
  cost_center, 
  environment,
  project_code
ORDER BY
  billing_date DESC, 
  total_cost DESC