# Distributed Data Processing Workflows with Cloud Dataproc and Cloud Scheduler
# This Terraform configuration creates the complete infrastructure for automated
# data processing pipelines using Google Cloud services

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Create a standardized suffix for resource naming
  resource_suffix = var.resource_suffix != "" ? var.resource_suffix : random_id.suffix.hex
  
  # Standardized resource naming
  data_bucket_name    = "dataproc-data-${local.resource_suffix}"
  staging_bucket_name = "dataproc-staging-${local.resource_suffix}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment   = var.environment
    resource-type = "dataproc-workflow"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(var.required_apis) : []
  
  project = var.project_id
  service = each.value
  
  # Prevent accidental deletion of critical APIs
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Cloud Storage bucket for input data
resource "google_storage_bucket" "data_bucket" {
  name     = local.data_bucket_name
  location = var.region
  
  # Storage configuration
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  force_destroy               = true
  
  # Enable versioning for data protection
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules_enabled ? [1] : []
    content {
      condition {
        age = 365
      }
      action {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
    }
  }
  
  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules_enabled ? [1] : []
    content {
      condition {
        age = 730
      }
      action {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for Dataproc staging
resource "google_storage_bucket" "staging_bucket" {
  name     = local.staging_bucket_name
  location = var.region
  
  # Storage configuration
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  force_destroy               = true
  
  # Enable versioning for operational safety
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management for temporary files
  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules_enabled ? [1] : []
    content {
      condition {
        age = 30
      }
      action {
        type = "Delete"
      }
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create sample data file for processing
resource "google_storage_bucket_object" "sample_data" {
  name   = "input/sales_data.csv"
  bucket = google_storage_bucket.data_bucket.name
  
  content = <<-EOT
    transaction_id,customer_id,product_id,product_name,category,quantity,unit_price,transaction_date,region
    T001,C001,P001,Laptop Pro,Electronics,2,1299.99,2024-01-15,North
    T002,C002,P002,Coffee Maker,Appliances,1,89.99,2024-01-15,South
    T003,C003,P003,Running Shoes,Sports,1,129.99,2024-01-16,East
    T004,C001,P004,Wireless Mouse,Electronics,3,29.99,2024-01-16,North
    T005,C004,P005,Yoga Mat,Sports,2,49.99,2024-01-17,West
    T006,C005,P001,Laptop Pro,Electronics,1,1299.99,2024-01-17,South
    T007,C002,P006,Blender,Appliances,1,199.99,2024-01-18,South
    T008,C006,P003,Running Shoes,Sports,2,129.99,2024-01-18,East
    T009,C007,P007,Gaming Chair,Furniture,1,399.99,2024-01-19,North
    T010,C003,P008,Desk Lamp,Furniture,1,79.99,2024-01-19,East
  EOT
  
  content_type = "text/csv"
  
  depends_on = [google_storage_bucket.data_bucket]
}

# Create PySpark processing script
resource "google_storage_bucket_object" "spark_script" {
  name   = "scripts/spark_sales_analysis.py"
  bucket = google_storage_bucket.staging_bucket.name
  
  content = <<-EOT
    from pyspark.sql import SparkSession
    from pyspark.sql.functions import col, sum as spark_sum, count, avg, current_timestamp
    import sys
    
    def main():
        # Initialize Spark session with BigQuery connector
        spark = SparkSession.builder \
            .appName("SalesAnalyticsWorkflow") \
            .config("spark.jars.packages", "com.google.cloud.spark:spark-bigquery-with-dependencies_2.12:0.28.0") \
            .getOrCreate()
        
        try:
            # Read input data from Cloud Storage
            input_path = sys.argv[1] if len(sys.argv) > 1 else "gs://*/input/sales_data.csv"
            output_path = sys.argv[2] if len(sys.argv) > 2 else "gs://*/output/"
            project_id = sys.argv[3] if len(sys.argv) > 3 else "default-project"
            
            print(f"Processing data from: {input_path}")
            
            # Load sales data
            df = spark.read.option("header", "true").option("inferSchema", "true").csv(input_path)
            
            # Perform analytics aggregations
            sales_summary = df.groupBy("region", "category") \
                .agg(
                    spark_sum(col("quantity") * col("unit_price")).alias("total_sales"),
                    count("transaction_id").alias("transaction_count"),
                    avg(col("quantity") * col("unit_price")).alias("avg_order_value")
                ) \
                .withColumn("processing_timestamp", current_timestamp())
            
            # Show sample results
            print("Sales Summary Results:")
            sales_summary.show()
            
            # Write results to Cloud Storage as Parquet
            sales_summary.write.mode("overwrite").parquet(f"{output_path}/sales_summary")
            
            # Write results to BigQuery
            sales_summary.write \
                .format("bigquery") \
                .option("table", f"{project_id}.analytics_results.sales_summary") \
                .option("writeMethod", "overwrite") \
                .save()
            
            print("✅ Processing completed successfully")
            
        except Exception as e:
            print(f"❌ Error during processing: {str(e)}")
            raise
        finally:
            spark.stop()
    
    if __name__ == "__main__":
        main()
  EOT
  
  content_type = "text/x-python"
  
  depends_on = [google_storage_bucket.staging_bucket]
}

# Create BigQuery dataset for analytics results
resource "google_bigquery_dataset" "analytics_dataset" {
  dataset_id  = var.bigquery_dataset_name
  project     = var.project_id
  location    = var.region
  description = var.bigquery_dataset_description
  
  # Access control settings
  delete_contents_on_destroy = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create BigQuery table for sales summary results
resource "google_bigquery_table" "sales_summary" {
  dataset_id          = google_bigquery_dataset.analytics_dataset.dataset_id
  table_id            = var.bigquery_table_name
  project             = var.project_id
  deletion_protection = false
  
  schema = jsonencode([
    {
      name = "region"
      type = "STRING"
      mode = "REQUIRED"
      description = "Geographic region for sales data"
    },
    {
      name = "category"
      type = "STRING"
      mode = "REQUIRED"
      description = "Product category"
    },
    {
      name = "total_sales"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Total sales amount for the region and category"
    },
    {
      name = "transaction_count"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Number of transactions"
    },
    {
      name = "avg_order_value"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Average order value"
    },
    {
      name = "processing_timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp when the data was processed"
    }
  ])
  
  labels = local.common_labels
}

# Create service account for Dataproc and Cloud Scheduler
resource "google_service_account" "dataproc_scheduler" {
  account_id   = var.service_account_name
  display_name = var.service_account_display_name
  description  = "Service account for scheduling and executing Dataproc workflows"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Grant necessary IAM roles to the service account
resource "google_project_iam_member" "dataproc_editor" {
  project = var.project_id
  role    = "roles/dataproc.editor"
  member  = "serviceAccount:${google_service_account.dataproc_scheduler.email}"
}

resource "google_project_iam_member" "storage_object_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.dataproc_scheduler.email}"
}

resource "google_project_iam_member" "bigquery_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.dataproc_scheduler.email}"
}

resource "google_project_iam_member" "bigquery_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dataproc_scheduler.email}"
}

# Grant service account access to Cloud Storage buckets
resource "google_storage_bucket_iam_member" "data_bucket_viewer" {
  bucket = google_storage_bucket.data_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.dataproc_scheduler.email}"
}

resource "google_storage_bucket_iam_member" "staging_bucket_admin" {
  bucket = google_storage_bucket.staging_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.dataproc_scheduler.email}"
}

# Create Dataproc workflow template
resource "google_dataproc_workflow_template" "sales_analytics" {
  name     = var.workflow_name
  location = var.region
  
  placement {
    managed_cluster {
      cluster_name = var.cluster_name
      config {
        gce_cluster_config {
          zone                = var.zone
          network             = var.network
          subnetwork          = var.subnetwork
          service_account     = google_service_account.dataproc_scheduler.email
          
          # Enable IP aliases for VPC-native networking
          dynamic "shielded_instance_config" {
            for_each = var.enable_ip_alias ? [1] : []
            content {
              enable_secure_boot = true
              enable_vtpm        = true
            }
          }
          
          metadata = {
            "enable-cloud-sql-hive-metastore" = "false"
          }
          
          tags = ["dataproc-cluster"]
        }
        
        master_config {
          num_instances    = 1
          machine_type     = var.master_machine_type
          min_cpu_platform = "Intel Skylake"
          
          disk_config {
            boot_disk_type    = "pd-standard"
            boot_disk_size_gb = var.master_disk_size
            num_local_ssds    = 0
          }
        }
        
        worker_config {
          num_instances    = var.worker_count
          machine_type     = var.worker_machine_type
          min_cpu_platform = "Intel Skylake"
          
          disk_config {
            boot_disk_type    = "pd-standard"
            boot_disk_size_gb = var.worker_disk_size
            num_local_ssds    = 0
          }
        }
        
        # Configure autoscaling if enabled
        dynamic "secondary_worker_config" {
          for_each = var.enable_autoscaling ? [1] : []
          content {
            num_instances   = 0
            machine_type    = var.worker_machine_type
            is_preemptible  = true
            
            disk_config {
              boot_disk_type    = "pd-standard"
              boot_disk_size_gb = var.worker_disk_size
              num_local_ssds    = 0
            }
          }
        }
        
        # Software configuration
        software_config {
          image_version = var.dataproc_image_version
          
          properties = {
            "dataproc:dataproc.allow.zero.workers" = "true"
            "spark:spark.sql.adaptive.enabled"     = "true"
            "spark:spark.sql.adaptive.coalescePartitions.enabled" = "true"
          }
        }
        
        # Autoscaling policy
        dynamic "autoscaling_config" {
          for_each = var.enable_autoscaling ? [1] : []
          content {
            max_workers               = var.max_workers
            secondary_worker_fraction = 0.0
          }
        }
        
        # Lifecycle configuration for cost optimization
        lifecycle_config {
          idle_delete_ttl = "600s"  # Delete cluster after 10 minutes of inactivity
        }
      }
    }
  }
  
  jobs {
    step_id = "sales-analytics-job"
    
    pyspark_job {
      main_python_file_uri = "gs://${google_storage_bucket.staging_bucket.name}/scripts/spark_sales_analysis.py"
      
      args = [
        "gs://${google_storage_bucket.data_bucket.name}/input/sales_data.csv",
        "gs://${google_storage_bucket.data_bucket.name}/output/",
        var.project_id
      ]
      
      properties = {
        "spark.submit.deployMode" = "cluster"
      }
      
      logging_config {
        driver_log_levels = {
          "root" = "INFO"
        }
      }
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_storage_bucket_object.spark_script,
    google_bigquery_table.sales_summary,
    google_project_iam_member.dataproc_editor
  ]
}

# Create Cloud Scheduler job for automated execution
resource "google_cloud_scheduler_job" "sales_analytics_daily" {
  name             = var.scheduler_job_name
  description      = var.scheduler_description
  schedule         = var.schedule_expression
  time_zone        = var.scheduler_timezone
  region           = var.region
  attempt_deadline = "320s"
  
  retry_config {
    retry_count = 3
  }
  
  http_target {
    http_method = "POST"
    uri         = "https://dataproc.googleapis.com/v1/projects/${var.project_id}/regions/${var.region}/workflowTemplates/${google_dataproc_workflow_template.sales_analytics.name}:instantiate"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      requestId = "scheduled-${formatdate("YYYY-MM-DD-hhmmss", timestamp())}"
    }))
    
    oauth_token {
      service_account_email = google_service_account.dataproc_scheduler.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
  
  depends_on = [
    google_dataproc_workflow_template.sales_analytics,
    google_project_service.required_apis
  ]
}