-- Privacy-preserving analytics view with k-anonymity protection
-- This view ensures individual privacy by only showing aggregated results
-- with sufficient sample sizes (k-anonymity with k=10)

SELECT
  diagnosis,
  region,
  -- Use aggregation functions that preserve privacy
  COUNT(*) as patient_count,
  APPROX_QUANTILES(age, 4)[OFFSET(2)] as median_age,
  ROUND(STDDEV(treatment_cost), 2) as cost_variance,
  -- Only show results with sufficient sample size for privacy (k=10)
  CASE 
    WHEN COUNT(*) >= 10 THEN ROUND(AVG(treatment_cost), 2)
    ELSE NULL 
  END as avg_treatment_cost,
  -- Add time-based privacy protection
  DATE_TRUNC(MIN(admission_date), MONTH) as earliest_admission_month
FROM `${project_id}.${dataset_name}.patient_analytics`
GROUP BY diagnosis, region
HAVING COUNT(*) >= 10  -- Ensure k-anonymity with k=10
ORDER BY patient_count DESC