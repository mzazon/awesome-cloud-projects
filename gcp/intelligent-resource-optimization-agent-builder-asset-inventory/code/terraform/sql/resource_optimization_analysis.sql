-- BigQuery view for resource optimization analysis
-- This view analyzes Cloud Asset Inventory data to identify optimization opportunities
-- and assign optimization scores based on resource utilization patterns

SELECT 
  name,
  asset_type,
  JSON_EXTRACT_SCALAR(resource.data, '$.location') as location,
  JSON_EXTRACT_SCALAR(resource.data, '$.project') as project,
  DATE_DIFF(CURRENT_DATE(), DATE(update_time), DAY) as age_days,
  JSON_EXTRACT_SCALAR(resource.data, '$.status') as status,
  JSON_EXTRACT_SCALAR(resource.data, '$.machineType') as machine_type,
  
  -- Categorize resources based on optimization potential
  CASE 
    WHEN asset_type LIKE '%Instance%' AND JSON_EXTRACT_SCALAR(resource.data, '$.status') = 'TERMINATED' THEN 'Idle Compute'
    WHEN asset_type LIKE '%Instance%' AND JSON_EXTRACT_SCALAR(resource.data, '$.status') = 'STOPPED' THEN 'Stopped Compute'
    WHEN asset_type LIKE '%Disk%' AND JSON_EXTRACT_SCALAR(resource.data, '$.status') = 'READY' AND JSON_EXTRACT_SCALAR(resource.data, '$.users') IS NULL THEN 'Unattached Storage'
    WHEN asset_type LIKE '%Bucket%' THEN 'Storage Analysis Needed'
    WHEN asset_type LIKE '%Cluster%' AND JSON_EXTRACT_SCALAR(resource.data, '$.status') = 'STOPPED' THEN 'Idle Cluster'
    WHEN asset_type LIKE '%sqladmin%' AND JSON_EXTRACT_SCALAR(resource.data, '$.state') = 'SUSPENDED' THEN 'Suspended Database'
    ELSE 'Active Resource'
  END as optimization_category,
  
  -- Assign optimization scores based on potential cost savings
  CASE
    -- High priority: Resources idle for 30+ days
    WHEN DATE_DIFF(CURRENT_DATE(), DATE(update_time), DAY) > 30 AND JSON_EXTRACT_SCALAR(resource.data, '$.status') NOT IN ('RUNNING', 'ACTIVE') THEN 90
    
    -- Medium-high priority: Resources idle for 7+ days
    WHEN DATE_DIFF(CURRENT_DATE(), DATE(update_time), DAY) > 7 AND JSON_EXTRACT_SCALAR(resource.data, '$.status') IN ('TERMINATED', 'STOPPED', 'SUSPENDED') THEN 70
    
    -- Medium priority: Legacy machine types (n1 series)
    WHEN JSON_EXTRACT_SCALAR(resource.data, '$.machineType') LIKE '%n1-%' THEN 60
    
    -- Medium priority: Unattached persistent disks
    WHEN asset_type LIKE '%Disk%' AND JSON_EXTRACT_SCALAR(resource.data, '$.users') IS NULL THEN 65
    
    -- Low-medium priority: Oversized instances (high CPU/memory)
    WHEN JSON_EXTRACT_SCALAR(resource.data, '$.machineType') LIKE '%custom-%' OR JSON_EXTRACT_SCALAR(resource.data, '$.machineType') LIKE '%highmem-%' THEN 45
    
    -- Low priority: Storage buckets (need lifecycle analysis)
    WHEN asset_type LIKE '%Bucket%' THEN 30
    
    -- Minimal priority: Active resources
    ELSE 20
  END as optimization_score,
  
  -- Additional optimization metadata
  JSON_EXTRACT_SCALAR(resource.data, '$.creationTimestamp') as creation_timestamp,
  JSON_EXTRACT_SCALAR(resource.data, '$.zone') as zone,
  JSON_EXTRACT_SCALAR(resource.data, '$.description') as description,
  
  -- Extract cost-relevant metadata
  JSON_EXTRACT_SCALAR(resource.data, '$.disks[0].diskSizeGb') as disk_size_gb,
  JSON_EXTRACT_SCALAR(resource.data, '$.networkInterfaces[0].network') as network,
  
  -- Resource-specific optimization hints
  CASE 
    WHEN asset_type LIKE '%Instance%' AND JSON_EXTRACT_SCALAR(resource.data, '$.machineType') LIKE '%n1-%' THEN 'Consider upgrading to E2 or N2 machine types for better price-performance'
    WHEN asset_type LIKE '%Disk%' AND JSON_EXTRACT_SCALAR(resource.data, '$.users') IS NULL THEN 'Unattached disk - consider deletion if not needed'
    WHEN asset_type LIKE '%Instance%' AND JSON_EXTRACT_SCALAR(resource.data, '$.status') = 'TERMINATED' THEN 'Terminated instance - consider cleanup'
    WHEN asset_type LIKE '%Bucket%' THEN 'Review bucket lifecycle policies and storage class optimization'
    ELSE 'Review resource utilization and right-sizing opportunities'
  END as optimization_recommendation

FROM `${project_id}.${dataset_name}.asset_inventory`
WHERE 
  update_time IS NOT NULL
  AND asset_type IN (
    'compute.googleapis.com/Instance',
    'compute.googleapis.com/Disk',
    'storage.googleapis.com/Bucket',
    'container.googleapis.com/Cluster',
    'sqladmin.googleapis.com/Instance'
  )