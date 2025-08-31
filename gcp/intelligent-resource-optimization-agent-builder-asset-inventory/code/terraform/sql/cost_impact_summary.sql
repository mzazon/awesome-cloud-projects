-- BigQuery view for cost impact summary
-- This view aggregates optimization analysis data to provide high-level insights
-- into cost optimization opportunities by category

SELECT 
  optimization_category,
  COUNT(*) as resource_count,
  
  -- Calculate optimization statistics
  AVG(optimization_score) as avg_optimization_score,
  MIN(optimization_score) as min_optimization_score,
  MAX(optimization_score) as max_optimization_score,
  STDDEV(optimization_score) as optimization_score_stddev,
  
  -- Calculate total impact score (resources * average score)
  COUNT(*) * AVG(optimization_score) as total_impact_score,
  
  -- Resource age analysis
  AVG(age_days) as avg_age_days,
  MIN(age_days) as min_age_days,
  MAX(age_days) as max_age_days,
  
  -- Count resources by priority levels
  COUNTIF(optimization_score >= 80) as critical_priority_count,
  COUNTIF(optimization_score >= 60 AND optimization_score < 80) as high_priority_count,
  COUNTIF(optimization_score >= 40 AND optimization_score < 60) as medium_priority_count,
  COUNTIF(optimization_score < 40) as low_priority_count,
  
  -- Calculate percentage distributions
  ROUND(COUNTIF(optimization_score >= 80) * 100.0 / COUNT(*), 2) as critical_priority_percentage,
  ROUND(COUNTIF(optimization_score >= 60 AND optimization_score < 80) * 100.0 / COUNT(*), 2) as high_priority_percentage,
  ROUND(COUNTIF(optimization_score >= 40 AND optimization_score < 60) * 100.0 / COUNT(*), 2) as medium_priority_percentage,
  ROUND(COUNTIF(optimization_score < 40) * 100.0 / COUNT(*), 2) as low_priority_percentage,
  
  -- Location distribution
  COUNT(DISTINCT location) as unique_locations,
  STRING_AGG(DISTINCT location ORDER BY location) as locations,
  
  -- Asset type breakdown within category
  COUNT(DISTINCT asset_type) as unique_asset_types,
  STRING_AGG(DISTINCT asset_type ORDER BY asset_type) as asset_types,
  
  -- Time-based insights
  MIN(creation_timestamp) as oldest_resource_created,
  MAX(creation_timestamp) as newest_resource_created,
  
  -- Generate category-specific recommendations
  CASE optimization_category
    WHEN 'Idle Compute' THEN 'High priority: Delete or resize idle compute instances to reduce costs immediately'
    WHEN 'Stopped Compute' THEN 'Medium priority: Review stopped instances and delete if no longer needed'
    WHEN 'Unattached Storage' THEN 'High priority: Remove unattached disks to eliminate unnecessary storage costs'
    WHEN 'Storage Analysis Needed' THEN 'Medium priority: Implement lifecycle policies and optimize storage classes'
    WHEN 'Idle Cluster' THEN 'High priority: Scale down or delete idle clusters to reduce compute costs'
    WHEN 'Suspended Database' THEN 'Medium priority: Review suspended databases and delete if not needed'
    WHEN 'Active Resource' THEN 'Low priority: Monitor utilization and consider right-sizing opportunities'
    ELSE 'Review resource configuration and usage patterns'
  END as category_recommendation,
  
  -- Estimated potential impact
  CASE 
    WHEN optimization_category = 'Idle Compute' THEN 'High cost savings potential'
    WHEN optimization_category = 'Unattached Storage' THEN 'Medium cost savings potential'
    WHEN optimization_category = 'Idle Cluster' THEN 'High cost savings potential'
    WHEN optimization_category = 'Suspended Database' THEN 'Medium cost savings potential'
    WHEN optimization_category = 'Storage Analysis Needed' THEN 'Low to medium cost savings potential'
    ELSE 'Low cost savings potential'
  END as potential_savings_level

FROM `${project_id}.${dataset_name}.resource_optimization_analysis`
GROUP BY optimization_category
ORDER BY total_impact_score DESC