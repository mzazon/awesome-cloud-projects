# Outputs for GCP Dynamic Pricing Optimization Infrastructure
# This file defines outputs that provide important information about the created resources

# Project and Location Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming to ensure uniqueness"
  value       = random_id.suffix.hex
}

# BigQuery Resources
output "bigquery_dataset_id" {
  description = "ID of the BigQuery dataset for pricing optimization"
  value       = google_bigquery_dataset.pricing_optimization.dataset_id
}

output "bigquery_dataset_location" {
  description = "Location of the BigQuery dataset"
  value       = google_bigquery_dataset.pricing_optimization.location
}

output "sales_history_table_id" {
  description = "Full table ID for the sales history table"
  value       = "${var.project_id}.${google_bigquery_dataset.pricing_optimization.dataset_id}.${google_bigquery_table.sales_history.table_id}"
}

output "competitor_pricing_table_id" {
  description = "Full table ID for the competitor pricing table"
  value       = "${var.project_id}.${google_bigquery_dataset.pricing_optimization.dataset_id}.${google_bigquery_table.competitor_pricing.table_id}"
}

output "bigquery_console_url" {
  description = "URL to view the BigQuery dataset in the Google Cloud Console"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.pricing_optimization.dataset_id}"
}

# Cloud Storage Resources
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for data and model artifacts"
  value       = google_storage_bucket.pricing_data.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.pricing_data.url
}

output "storage_console_url" {
  description = "URL to view the Cloud Storage bucket in the Google Cloud Console"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.pricing_data.name}?project=${var.project_id}"
}

# Cloud Functions Resources
output "cloud_function_name" {
  description = "Name of the pricing optimization Cloud Function"
  value       = google_cloudfunctions2_function.pricing_optimizer.name
}

output "cloud_function_url" {
  description = "HTTPS URL of the pricing optimization Cloud Function"
  value       = google_cloudfunctions2_function.pricing_optimizer.service_config[0].uri
}

output "cloud_function_console_url" {
  description = "URL to view the Cloud Function in the Google Cloud Console"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.pricing_optimizer.name}?project=${var.project_id}"
}

# Service Account Information
output "service_account_email" {
  description = "Email address of the pricing optimizer service account"
  value       = google_service_account.pricing_optimizer.email
}

output "service_account_id" {
  description = "Full ID of the pricing optimizer service account"
  value       = google_service_account.pricing_optimizer.id
}

# Cloud Scheduler Information
output "scheduler_job_names" {
  description = "Names of the Cloud Scheduler jobs for automated pricing updates"
  value       = [for job in google_cloud_scheduler_job.pricing_optimization : job.name]
}

output "scheduler_job_urls" {
  description = "URLs to view the Cloud Scheduler jobs in the Google Cloud Console"
  value = [
    for job in google_cloud_scheduler_job.pricing_optimization :
    "https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
  ]
}

output "product_ids_scheduled" {
  description = "List of product IDs that have automated pricing optimization scheduled"
  value       = var.product_ids
}

output "scheduler_frequency" {
  description = "Cron expression for the pricing optimization schedule"
  value       = var.scheduler_frequency
}

# Monitoring Resources
output "monitoring_dashboard_url" {
  description = "URL to view the pricing optimization monitoring dashboard"
  value = var.enable_monitoring_dashboard ? (
    "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.pricing_optimization[0].id}?project=${var.project_id}"
  ) : "Monitoring dashboard not enabled"
}

output "monitoring_enabled" {
  description = "Whether monitoring dashboard was created"
  value       = var.enable_monitoring_dashboard
}

# Security and Access Information
output "public_access_enabled" {
  description = "Whether the Cloud Function allows public access"
  value       = var.enable_public_access
}

output "allowed_members" {
  description = "List of members allowed to invoke the Cloud Function (when public access is disabled)"
  value       = var.allowed_members
}

# Sample Data Information
output "sample_data_loaded" {
  description = "Whether sample data was loaded into BigQuery"
  value       = var.load_sample_data
}

output "sample_data_records" {
  description = "Number of sample records loaded (if sample data was enabled)"
  value       = var.load_sample_data ? 15 : 0
}

# Cost Information
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD (approximate, based on minimal usage)"
  value = {
    bigquery        = "5-20"
    cloud_functions = "0-10"
    cloud_storage   = "1-5"
    cloud_scheduler = "0-1"
    total_range     = "6-36"
    note           = "Costs depend on actual usage. BigQuery costs vary significantly with query volume and data size."
  }
}

# API Testing Information
output "api_testing_examples" {
  description = "Examples of how to test the pricing optimization API"
  value = {
    curl_example = "curl -X POST '${google_cloudfunctions2_function.pricing_optimizer.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"product_id\": \"PROD001\"}'"
    
    python_example = <<-EOF
import requests
import json

url = "${google_cloudfunctions2_function.pricing_optimizer.service_config[0].uri}"
payload = {"product_id": "PROD001"}
response = requests.post(url, json=payload)
print(json.dumps(response.json(), indent=2))
EOF
    
    sample_response = jsonencode({
      product_id            = "PROD001"
      current_price         = 29.99
      recommended_price     = 31.49
      competitor_price      = 31.99
      predicted_revenue     = 3149.0
      price_change_percent  = 5.0
      inventory_level       = 1200
      timestamp            = "2025-01-15T10:30:00.000Z"
      optimization_reason  = "inventory_level"
    })
  }
}

# BigQuery ML Model Commands
output "bigquery_ml_commands" {
  description = "Commands to create and use BigQuery ML models for pricing optimization"
  value = {
    create_model = <<-EOF
bq query --use_legacy_sql=false '
CREATE OR REPLACE MODEL `${var.project_id}.${var.dataset_name}.pricing_prediction_model`
OPTIONS(
  model_type="LINEAR_REG",
  input_label_cols=["revenue"],
  data_split_method="AUTO_SPLIT",
  data_split_eval_fraction=0.2
) AS
SELECT
  price,
  competitor_price,
  inventory_level,
  CASE 
    WHEN season = "winter" THEN 1
    WHEN season = "spring" THEN 2
    WHEN season = "summer" THEN 3
    ELSE 4
  END as season_numeric,
  CASE WHEN promotion THEN 1 ELSE 0 END as promotion_flag,
  revenue
FROM `${var.project_id}.${var.dataset_name}.sales_history`'
EOF
    
    evaluate_model = <<-EOF
bq query --use_legacy_sql=false '
SELECT
  mean_squared_error,
  r2_score,
  mean_absolute_error
FROM ML.EVALUATE(MODEL `${var.project_id}.${var.dataset_name}.pricing_prediction_model`)'
EOF
    
    predict_example = <<-EOF
bq query --use_legacy_sql=false '
SELECT 
  predicted_revenue
FROM ML.PREDICT(MODEL `${var.project_id}.${var.dataset_name}.pricing_prediction_model`,
  (SELECT 
    29.99 as price,
    31.99 as competitor_price,
    1200 as inventory_level,
    1 as season_numeric,
    0 as promotion_flag
  )
)'
EOF
  }
}

# Vertex AI Setup Commands
output "vertex_ai_setup_commands" {
  description = "Commands to set up Vertex AI training for advanced pricing models"
  value = {
    create_training_script = "# Upload your training script to gs://${google_storage_bucket.pricing_data.name}/vertex_ai_training/"
    
    submit_training_job = <<-EOF
gcloud ai custom-jobs create \
  --region=${var.region} \
  --display-name="pricing-optimization-training" \
  --worker-pool-spec=machine-type=${var.vertex_ai_machine_type},replica-count=${var.vertex_ai_replica_count},executor-image-uri=us-docker.pkg.dev/vertex-ai/training/scikit-learn-cpu.1-0:latest,local-package-path=vertex_ai_training,script=trainer.py
EOF
    
    list_training_jobs = "gcloud ai custom-jobs list --region=${var.region}"
  }
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

output "terraform_workspace" {
  description = "Terraform workspace used for this deployment"
  value       = terraform.workspace
}

# Security Recommendations
output "security_recommendations" {
  description = "Security recommendations for production deployment"
  value = {
    cloud_function = var.enable_public_access ? "⚠️  Public access is enabled. Consider disabling for production and using authentication." : "✅ Public access is disabled. Good for production security."
    
    iam_recommendations = [
      "Review and minimize IAM permissions based on actual usage",
      "Enable audit logging for BigQuery and Cloud Functions",
      "Consider using VPC Service Controls for additional network security",
      "Implement proper data encryption for sensitive pricing data"
    ]
    
    monitoring_recommendations = [
      "Set up alerting for unusual pricing recommendations",
      "Monitor BigQuery costs and set up budget alerts",
      "Implement data quality checks for incoming pricing data",
      "Set up log-based metrics for business KPIs"
    ]
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after infrastructure deployment"
  value = [
    "1. Test the Cloud Function with sample product IDs",
    "2. Create BigQuery ML models using the provided commands",
    "3. Load your actual historical pricing data into BigQuery",
    "4. Configure monitoring and alerting based on your business needs",
    "5. Set up Vertex AI training for advanced ML models",
    "6. Integrate the API with your e-commerce platform",
    "7. Implement A/B testing to validate pricing recommendations",
    "8. Set up automated data pipelines for real-time competitor pricing"
  ]
}