# Main Terraform configuration for scientific workflow orchestration with Cloud Batch API and Vertex AI Workbench
# This infrastructure supports genomics research workflows with scalable data processing and ML analysis

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming with random suffix
  bucket_name     = "${var.resource_prefix}-data-${random_id.suffix.hex}"
  dataset_name    = "${var.resource_prefix}_analysis_${random_id.suffix.hex}"
  workbench_name  = "${var.resource_prefix}-workbench-${random_id.suffix.hex}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
    created-by  = "terraform"
    timestamp   = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "batch.googleapis.com",
    "notebooks.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "aiplatform.googleapis.com",
    "compute.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com"
  ])

  project                    = var.project_id
  service                    = each.key
  disable_dependent_services = true
  disable_on_destroy        = false
}

# Wait for APIs to be enabled
resource "time_sleep" "api_enablement" {
  depends_on      = [google_project_service.required_apis]
  create_duration = "60s"
}

# Cloud Storage bucket for genomic data storage
resource "google_storage_bucket" "genomics_data" {
  name                        = local.bucket_name
  location                    = var.region
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  force_destroy               = true

  # Enable versioning for data protection
  versioning {
    enabled = var.enable_versioning
  }

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.lifecycle_age_days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = var.lifecycle_age_days * 3
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  # CORS configuration for web access
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  labels = local.common_labels

  depends_on = [time_sleep.api_enablement]
}

# Create directory structure in the bucket
resource "google_storage_bucket_object" "directory_structure" {
  for_each = toset([
    "raw-data/",
    "processed-data/",
    "results/",
    "scripts/",
    "notebooks/"
  ])

  name    = "${each.key}.keep"
  content = "# This file maintains the directory structure"
  bucket  = google_storage_bucket.genomics_data.name
}

# Upload genomic processing script to bucket
resource "google_storage_bucket_object" "genomic_pipeline_script" {
  name   = "scripts/genomic_pipeline.py"
  bucket = google_storage_bucket.genomics_data.name
  source = "genomic_pipeline.py"

  # Create the script file locally if it doesn't exist
  content = templatefile("${path.module}/templates/genomic_pipeline.py.tpl", {
    dataset_name = local.dataset_name
    bucket_name  = local.bucket_name
    project_id   = var.project_id
  })
}

# Upload ML analysis notebook to bucket
resource "google_storage_bucket_object" "ml_notebook" {
  name   = "notebooks/genomic_ml_analysis.ipynb"
  bucket = google_storage_bucket.genomics_data.name
  
  content = templatefile("${path.module}/templates/genomic_ml_analysis.ipynb.tpl", {
    dataset_name = local.dataset_name
    project_id   = var.project_id
  })
}

# BigQuery dataset for genomic analytics
resource "google_bigquery_dataset" "genomics_dataset" {
  dataset_id                 = local.dataset_name
  friendly_name             = "Genomic Analysis Dataset"
  description               = "Dataset for storing genomic variant calls and analysis results"
  location                  = var.bigquery_location
  delete_contents_on_destroy = true
  
  # Enable deletion protection in production
  deletion_protection = var.bq_deletion_protection

  labels = local.common_labels

  # Access control
  access {
    role          = "OWNER"
    user_by_email = data.google_client_openid_userinfo.me.email
  }

  access {
    role   = "READER"
    domain = "google.com"
  }

  depends_on = [time_sleep.api_enablement]
}

# Get current user info for BigQuery access
data "google_client_openid_userinfo" "me" {}

# BigQuery table for variant calls
resource "google_bigquery_table" "variant_calls" {
  dataset_id          = google_bigquery_dataset.genomics_dataset.dataset_id
  table_id            = "variant_calls"
  deletion_protection = var.bq_deletion_protection

  description = "Table for storing genomic variant call data from processing pipelines"

  schema = jsonencode([
    {
      name = "chromosome"
      type = "STRING"
      mode = "REQUIRED"
      description = "Chromosome identifier (e.g., chr1, chr2, etc.)"
    },
    {
      name = "position"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Genomic position of the variant"
    },
    {
      name = "reference"
      type = "STRING"
      mode = "REQUIRED"
      description = "Reference allele sequence"
    },
    {
      name = "alternate"
      type = "STRING"
      mode = "REQUIRED"
      description = "Alternate allele sequence"
    },
    {
      name = "quality"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Quality score for the variant call"
    },
    {
      name = "filter"
      type = "STRING"
      mode = "NULLABLE"
      description = "Filter status (PASS, FAIL, etc.)"
    },
    {
      name = "info"
      type = "STRING"
      mode = "NULLABLE"
      description = "Additional variant information"
    },
    {
      name = "sample_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Sample identifier"
    },
    {
      name = "genotype"
      type = "STRING"
      mode = "NULLABLE"
      description = "Genotype call (e.g., 0/1, 1/1)"
    },
    {
      name = "depth"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Read depth at variant position"
    },
    {
      name = "allele_frequency"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Allele frequency in the sample"
    }
  ])

  labels = local.common_labels
}

# BigQuery table for analysis results
resource "google_bigquery_table" "analysis_results" {
  dataset_id          = google_bigquery_dataset.genomics_dataset.dataset_id
  table_id            = "analysis_results"
  deletion_protection = var.bq_deletion_protection

  description = "Table for storing ML analysis results and drug discovery insights"

  schema = jsonencode([
    {
      name = "sample_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Sample identifier"
    },
    {
      name = "variant_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique variant identifier"
    },
    {
      name = "gene"
      type = "STRING"
      mode = "NULLABLE"
      description = "Gene symbol associated with the variant"
    },
    {
      name = "effect"
      type = "STRING"
      mode = "NULLABLE"
      description = "Predicted effect of the variant"
    },
    {
      name = "clinical_significance"
      type = "STRING"
      mode = "NULLABLE"
      description = "Clinical significance classification"
    },
    {
      name = "drug_response"
      type = "STRING"
      mode = "NULLABLE"
      description = "Predicted drug response"
    },
    {
      name = "confidence_score"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Confidence score for the prediction"
    },
    {
      name = "analysis_timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp when analysis was performed"
    }
  ])

  labels = local.common_labels
}

# Service account for Vertex AI Workbench
resource "google_service_account" "workbench_sa" {
  account_id   = "${var.resource_prefix}-workbench-sa-${random_id.suffix.hex}"
  display_name = "Vertex AI Workbench Service Account"
  description  = "Service account for Vertex AI Workbench genomics research instance"
}

# IAM bindings for the workbench service account
resource "google_project_iam_member" "workbench_bigquery_user" {
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:${google_service_account.workbench_sa.email}"
}

resource "google_project_iam_member" "workbench_bigquery_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.workbench_sa.email}"
}

resource "google_project_iam_member" "workbench_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.workbench_sa.email}"
}

resource "google_project_iam_member" "workbench_ai_platform_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.workbench_sa.email}"
}

resource "google_project_iam_member" "workbench_batch_jobs_viewer" {
  project = var.project_id
  role    = "roles/batch.jobsViewer"
  member  = "serviceAccount:${google_service_account.workbench_sa.email}"
}

# Vertex AI Workbench instance for ML development
resource "google_notebooks_instance" "genomics_workbench" {
  name         = local.workbench_name
  location     = var.zone
  machine_type = var.workbench_machine_type

  # Container image for the notebook environment
  container_image {
    repository = "gcr.io/deeplearning-platform-release/tf2-cpu.2-11"
    tag        = "latest"
  }

  # Instance configuration
  install_gpu_driver = var.enable_gpu
  boot_disk_type     = "PD_STANDARD"
  boot_disk_size_gb  = var.workbench_boot_disk_size
  data_disk_type     = "PD_SSD"
  data_disk_size_gb  = var.workbench_data_disk_size

  # GPU configuration (if enabled)
  dynamic "accelerator_config" {
    for_each = var.enable_gpu ? [1] : []
    content {
      type       = var.gpu_type
      core_count = var.gpu_count
    }
  }

  # Network configuration
  network = var.network_name
  subnet  = var.subnet_name
  
  # Security and access configuration
  no_public_ip    = var.enable_private_ip
  no_proxy_access = false

  # Service account
  service_account = google_service_account.workbench_sa.email

  # Metadata for environment setup
  metadata = merge({
    "bigquery-dataset" = local.dataset_name
    "storage-bucket"   = local.bucket_name
    "enable-oslogin"   = var.enable_os_login ? "TRUE" : "FALSE"
    "startup-script" = templatefile("${path.module}/templates/workbench_startup.sh.tpl", {
      bucket_name  = local.bucket_name
      dataset_name = local.dataset_name
      project_id   = var.project_id
    })
  }, local.common_labels)

  labels = local.common_labels

  depends_on = [
    time_sleep.api_enablement,
    google_storage_bucket.genomics_data,
    google_bigquery_dataset.genomics_dataset
  ]
}

# Service account for Cloud Batch jobs
resource "google_service_account" "batch_sa" {
  account_id   = "${var.resource_prefix}-batch-sa-${random_id.suffix.hex}"
  display_name = "Cloud Batch Service Account"
  description  = "Service account for Cloud Batch genomics processing jobs"
}

# IAM bindings for the batch service account
resource "google_project_iam_member" "batch_bigquery_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.batch_sa.email}"
}

resource "google_project_iam_member" "batch_storage_object_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.batch_sa.email}"
}

resource "google_project_iam_member" "batch_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.batch_sa.email}"
}

resource "google_project_iam_member" "batch_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.batch_sa.email}"
}

# Cloud Batch job template for genomic processing
resource "google_batch_job" "genomic_processing" {
  name      = "${var.resource_prefix}-processing-${random_id.suffix.hex}"
  location  = var.region
  
  task_groups {
    task_count = var.batch_task_count
    parallelism = var.batch_job_parallelism
    
    task_spec {
      compute_resource {
        cpu_milli      = 2000  # 2 CPU cores
        memory_mib     = 4096  # 4GB RAM
        boot_disk_mib  = 10240 # 10GB boot disk
      }

      runnables {
        container {
          image_uri = "gcr.io/google.com/cloudsdktool/cloud-sdk:latest"
          
          commands = [
            "/bin/bash",
            "-c",
            "pip install google-cloud-bigquery google-cloud-storage pandas numpy && gsutil cp gs://${local.bucket_name}/scripts/genomic_pipeline.py . && python3 genomic_pipeline.py"
          ]
        }
      }

      environment {
        variables = {
          PROJECT_ID   = var.project_id
          DATASET_NAME = local.dataset_name
          BUCKET_NAME  = local.bucket_name
          REGION       = var.region
        }
      }

      max_retry_count = 2
      max_run_duration = "3600s"
    }
  }

  allocation_policy {
    instances {
      instance_template {
        machine_type = var.batch_machine_type
        
        provisioning_model = var.use_preemptible ? "PREEMPTIBLE" : "STANDARD"
        
        service_account {
          email = google_service_account.batch_sa.email
        }
      }
    }
    
    location {
      allowed_locations = [var.zone]
    }
  }

  logs_policy {
    destination = var.enable_logging ? "CLOUD_LOGGING" : "PATH"
  }

  labels = local.common_labels

  depends_on = [
    time_sleep.api_enablement,
    google_storage_bucket_object.genomic_pipeline_script,
    google_bigquery_table.variant_calls
  ]
}

# Create template files directory
resource "local_file" "genomic_pipeline_template" {
  filename = "${path.module}/templates/genomic_pipeline.py.tpl"
  content = templatefile("${path.root}/templates/genomic_pipeline.py", {
    dataset_name = "$${dataset_name}"
    bucket_name  = "$${bucket_name}"
    project_id   = "$${project_id}"
  })
}

resource "local_file" "ml_notebook_template" {
  filename = "${path.module}/templates/genomic_ml_analysis.ipynb.tpl"
  content = templatefile("${path.root}/templates/genomic_ml_analysis.ipynb", {
    dataset_name = "$${dataset_name}"
    project_id   = "$${project_id}"
  })
}

resource "local_file" "workbench_startup_template" {
  filename = "${path.module}/templates/workbench_startup.sh.tpl"
  content = templatefile("${path.root}/templates/workbench_startup.sh", {
    bucket_name  = "$${bucket_name}"
    dataset_name = "$${dataset_name}"
    project_id   = "$${project_id}"
  })
}