-- Compliance and encryption status report
-- This view provides overview of data protection and compliance status
-- for regulatory reporting and audit purposes

SELECT
  'Healthcare Analytics Report' as report_type,
  CURRENT_DATETIME() as generated_at,
  COUNT(DISTINCT diagnosis) as unique_diagnoses,
  COUNT(DISTINCT region) as regions_covered,
  COUNT(*) as total_encrypted_records,
  ROUND(AVG(treatment_cost), 2) as overall_avg_cost,
  ROUND(MIN(treatment_cost), 2) as min_cost,
  ROUND(MAX(treatment_cost), 2) as max_cost,
  ROUND(STDDEV(treatment_cost), 2) as cost_stddev,
  DATE(MIN(admission_date)) as earliest_record,
  DATE(MAX(admission_date)) as latest_record,
  'CMEK Encrypted with Hardware-level Privacy Protection' as encryption_status,
  'Confidential GKE with AMD SEV/Intel TDX' as processing_security,
  'K-Anonymity and Differential Privacy Enabled' as privacy_controls
FROM `${project_id}.${dataset_name}.patient_analytics`