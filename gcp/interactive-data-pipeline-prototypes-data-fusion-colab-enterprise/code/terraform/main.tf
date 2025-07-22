# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming
  resource_suffix = random_id.suffix.hex
  name_prefix     = "${var.resource_prefix}-${var.environment}"
  
  # Data Fusion instance name
  data_fusion_name = "${local.name_prefix}-fusion-${local.resource_suffix}"
  
  # Storage bucket names
  data_bucket_name    = "${local.name_prefix}-data-${local.resource_suffix}"
  staging_bucket_name = "${local.name_prefix}-staging-${local.resource_suffix}"
  
  # BigQuery dataset name
  dataset_name = "${replace(local.name_prefix, "-", "_")}_analytics_${local.resource_suffix}"
  
  # Network configuration
  network_name = var.create_custom_network ? "${local.name_prefix}-network" : (var.network_name != "" ? var.network_name : "default")
  subnet_name  = var.create_custom_network ? "${local.name_prefix}-subnet" : (var.subnet_name != "" ? var.subnet_name : "default")
  
  # Service account names
  data_fusion_sa_name = "${local.name_prefix}-fusion-sa"
  notebook_sa_name    = "${local.name_prefix}-notebook-sa"
  
  # Location configuration
  bucket_location   = var.bucket_location != "" ? var.bucket_location : var.region
  bigquery_location = var.bigquery_location != "" ? var.bigquery_location : var.region
  
  # Common labels
  common_labels = merge(var.labels, {
    resource-suffix = local.resource_suffix
    created-by     = "terraform"
    recipe         = "interactive-data-pipeline-prototypes"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset(var.apis_to_enable)
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying this resource
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create custom VPC network if requested
resource "google_compute_network" "custom_network" {
  count = var.create_custom_network ? 1 : 0
  
  name                    = local.network_name
  auto_create_subnetworks = false
  description             = "Custom VPC network for data pipeline prototyping"
  
  depends_on = [google_project_service.apis]
}

# Create custom subnet if custom network is created
resource "google_compute_subnetwork" "custom_subnet" {
  count = var.create_custom_network ? 1 : 0
  
  name          = local.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.custom_network[0].id
  description   = "Subnet for data pipeline resources"
  
  # Enable private Google access for accessing Google APIs
  private_ip_google_access = true
}

# Service account for Cloud Data Fusion
resource "google_service_account" "data_fusion_sa" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = local.data_fusion_sa_name
  display_name = "Cloud Data Fusion Service Account"
  description  = "Service account for Cloud Data Fusion operations"
  
  depends_on = [google_project_service.apis]
}

# Service account for Colab Enterprise notebooks
resource "google_service_account" "notebook_sa" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = local.notebook_sa_name
  display_name = "Colab Enterprise Service Account"
  description  = "Service account for Colab Enterprise notebook operations"
  
  depends_on = [google_project_service.apis]
}

# IAM binding for Data Fusion service account - Data Fusion Admin
resource "google_project_iam_member" "data_fusion_admin" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/datafusion.admin"
  member  = "serviceAccount:${google_service_account.data_fusion_sa[0].email}"
}

# IAM binding for Data Fusion service account - BigQuery Data Editor
resource "google_project_iam_member" "data_fusion_bigquery_editor" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.data_fusion_sa[0].email}"
}

# IAM binding for Data Fusion service account - Storage Object Admin
resource "google_project_iam_member" "data_fusion_storage_admin" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.data_fusion_sa[0].email}"
}

# IAM binding for Notebook service account - BigQuery User
resource "google_project_iam_member" "notebook_bigquery_user" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:${google_service_account.notebook_sa[0].email}"
}

# IAM binding for Notebook service account - Storage Object Viewer
resource "google_project_iam_member" "notebook_storage_viewer" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.notebook_sa[0].email}"
}

# IAM binding for Notebook service account - Notebooks Admin
resource "google_project_iam_member" "notebook_admin" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/notebooks.admin"
  member  = "serviceAccount:${google_service_account.notebook_sa[0].email}"
}

# Cloud Storage bucket for raw and processed data
resource "google_storage_bucket" "data_bucket" {
  name          = local.data_bucket_name
  location      = local.bucket_location
  storage_class = var.storage_class
  
  # Prevent accidental deletion
  force_destroy = false
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Versioning configuration
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.enable_cost_optimization ? [1] : []
    content {
      condition {
        age                   = var.lifecycle_age_days
        with_state           = "ARCHIVED"
        matches_storage_class = []
      }
      action {
        type = "Delete"
      }
    }
  }
  
  # Labels for resource management
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Cloud Storage bucket for staging and pipeline artifacts
resource "google_storage_bucket" "staging_bucket" {
  name          = local.staging_bucket_name
  location      = local.bucket_location
  storage_class = var.storage_class
  
  # Allow destruction for staging bucket
  force_destroy = true
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Versioning configuration
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management for staging data
  dynamic "lifecycle_rule" {
    for_each = var.enable_cost_optimization ? [1] : []
    content {
      condition {
        age = 7  # Delete staging data after 7 days
      }
      action {
        type = "Delete"
      }
    }
  }
  
  # Labels for resource management
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# BigQuery dataset for analytics
resource "google_bigquery_dataset" "analytics_dataset" {
  dataset_id    = local.dataset_name
  friendly_name = "Pipeline Analytics Dataset"
  description   = "Dataset for storing processed pipeline data and analytics results"
  location      = local.bigquery_location
  
  # Dataset access configuration
  default_table_expiration_ms = var.bigquery_default_table_expiration_ms
  delete_contents_on_destroy  = var.bigquery_delete_contents_on_destroy
  
  # Labels for resource management
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Sample table for customer transactions
resource "google_bigquery_table" "customer_transactions" {
  dataset_id          = google_bigquery_dataset.analytics_dataset.dataset_id
  table_id            = "customer_transactions"
  description         = "Table for storing joined customer and transaction data"
  deletion_protection = false
  
  # Table schema definition
  schema = jsonencode([
    {
      name = "customer_id"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Unique customer identifier"
    },
    {
      name = "name"
      type = "STRING"
      mode = "NULLABLE"
      description = "Customer name"
    },
    {
      name = "email"
      type = "STRING"
      mode = "NULLABLE"
      description = "Customer email address"
    },
    {
      name = "signup_date"
      type = "STRING"
      mode = "NULLABLE"
      description = "Customer signup date"
    },
    {
      name = "region"
      type = "STRING"
      mode = "NULLABLE"
      description = "Customer region"
    },
    {
      name = "transaction_id"
      type = "STRING"
      mode = "NULLABLE"
      description = "Transaction identifier"
    },
    {
      name = "amount"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Transaction amount"
    },
    {
      name = "timestamp"
      type = "STRING"
      mode = "NULLABLE"
      description = "Transaction timestamp"
    },
    {
      name = "product"
      type = "STRING"
      mode = "NULLABLE"
      description = "Product purchased"
    }
  ])
  
  # Labels for resource management
  labels = local.common_labels
}

# Cloud Data Fusion instance
resource "google_data_fusion_instance" "pipeline_instance" {
  name                          = local.data_fusion_name
  description                   = "Cloud Data Fusion instance for interactive pipeline prototyping"
  region                        = var.region
  type                          = var.data_fusion_edition
  version                       = var.data_fusion_version
  enable_stackdriver_logging    = var.enable_stackdriver_logging
  enable_stackdriver_monitoring = var.enable_stackdriver_monitoring
  enable_rbac                   = var.enable_rbac
  
  # Network configuration
  dynamic "network_config" {
    for_each = var.create_custom_network ? [1] : []
    content {
      network         = google_compute_network.custom_network[0].id
      ip_allocation   = var.subnet_cidr
    }
  }
  
  # Accelerators configuration for performance (optional)
  accelerators {
    accelerator_type  = "CDC"
    state            = "ENABLED"
  }
  
  # Labels for resource management
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_service_account.data_fusion_sa,
    google_project_iam_member.data_fusion_admin,
    google_project_iam_member.data_fusion_bigquery_editor,
    google_project_iam_member.data_fusion_storage_admin
  ]
}

# Create sample data files in Cloud Storage
resource "google_storage_bucket_object" "customer_data" {
  name   = "raw/customer_data.csv"
  bucket = google_storage_bucket.data_bucket.name
  content = <<EOF
customer_id,name,email,signup_date,region
1001,John Smith,john.smith@email.com,2023-01-15,US-East
1002,Jane Doe,jane.doe@email.com,2023-02-20,US-West
1003,Bob Johnson,bob.johnson@email.com,2023-03-10,EU-Central
1004,Alice Brown,alice.brown@email.com,2023-04-05,US-East
1005,Charlie Davis,charlie.davis@email.com,2023-05-12,APAC
EOF
  
  content_type = "text/csv"
}

# Create sample transaction data in Cloud Storage
resource "google_storage_bucket_object" "transaction_data" {
  name   = "raw/transaction_data.json"
  bucket = google_storage_bucket.data_bucket.name
  content = <<EOF
{"transaction_id": "tx001", "customer_id": 1001, "amount": 125.50, "timestamp": "2023-06-01T10:30:00Z", "product": "Widget A"}
{"transaction_id": "tx002", "customer_id": 1002, "amount": 75.25, "timestamp": "2023-06-01T11:15:00Z", "product": "Widget B"}
{"transaction_id": "tx003", "customer_id": 1003, "amount": 200.00, "timestamp": "2023-06-01T14:20:00Z", "product": "Widget C"}
{"transaction_id": "tx004", "customer_id": 1001, "amount": 89.99, "timestamp": "2023-06-02T09:45:00Z", "product": "Widget A"}
{"transaction_id": "tx005", "customer_id": 1004, "amount": 150.75, "timestamp": "2023-06-02T16:30:00Z", "product": "Widget B"}
EOF
  
  content_type = "application/json"
}

# Create notebook template in Cloud Storage
resource "google_storage_bucket_object" "notebook_template" {
  name   = "notebooks/pipeline_prototype.ipynb"
  bucket = google_storage_bucket.data_bucket.name
  content = jsonencode({
    cells = [
      {
        cell_type = "markdown"
        metadata = {}
        source = [
          "# Pipeline Prototype: Customer Transaction Analysis\n",
          "This notebook demonstrates interactive pipeline development for Cloud Data Fusion"
        ]
      },
      {
        cell_type = "code"
        execution_count = null
        metadata = {}
        outputs = []
        source = [
          "import pandas as pd\n",
          "import json\n",
          "from google.cloud import bigquery, storage\n",
          "from datetime import datetime\n",
          "\n",
          "# Initialize clients\n",
          "bq_client = bigquery.Client()\n",
          "storage_client = storage.Client()\n",
          "\n",
          "PROJECT_ID = '${var.project_id}'\n",
          "BUCKET_NAME = '${local.data_bucket_name}'\n",
          "DATASET_NAME = '${local.dataset_name}'"
        ]
      },
      {
        cell_type = "code"
        execution_count = null
        metadata = {}
        outputs = []
        source = [
          "# Load customer data from Cloud Storage\n",
          "customer_df = pd.read_csv(f'gs://{BUCKET_NAME}/raw/customer_data.csv')\n",
          "print('Customer data shape:', customer_df.shape)\n",
          "customer_df.head()"
        ]
      },
      {
        cell_type = "code"
        execution_count = null
        metadata = {}
        outputs = []
        source = [
          "# Load transaction data from Cloud Storage\n",
          "import pandas as pd\n",
          "transaction_df = pd.read_json(f'gs://{BUCKET_NAME}/raw/transaction_data.json', lines=True)\n",
          "print('Transaction data shape:', transaction_df.shape)\n",
          "transaction_df.head()"
        ]
      }
    ]
    metadata = {
      kernelspec = {
        display_name = "Python 3"
        language = "python"
        name = "python3"
      }
      language_info = {
        name = "python"
        version = "3.8.0"
      }
    }
    nbformat = 4
    nbformat_minor = 4
  })
  
  content_type = "application/json"
}

# Create Data Fusion pipeline template
resource "google_storage_bucket_object" "pipeline_template" {
  name   = "pipelines/pipeline_template.json"
  bucket = google_storage_bucket.staging_bucket.name
  content = jsonencode({
    name = "customer-transaction-pipeline"
    description = "ETL pipeline for customer transaction analysis"
    artifact = {
      name = "cdap-data-pipeline"
      version = "6.7.0"
      scope = "SYSTEM"
    }
    config = {
      stages = [
        {
          name = "CustomerSource"
          plugin = {
            name = "GCSFile"
            type = "batchsource"
            properties = {
              path = "gs://${local.data_bucket_name}/raw/customer_data.csv"
              format = "csv"
              schema = jsonencode({
                type = "record"
                name = "etlSchemaBody"
                fields = [
                  { name = "customer_id", type = "long" },
                  { name = "name", type = "string" },
                  { name = "email", type = "string" },
                  { name = "signup_date", type = "string" },
                  { name = "region", type = "string" }
                ]
              })
            }
          }
        },
        {
          name = "TransactionSource"
          plugin = {
            name = "GCSFile"
            type = "batchsource"
            properties = {
              path = "gs://${local.data_bucket_name}/raw/transaction_data.json"
              format = "json"
            }
          }
        },
        {
          name = "JoinCustomerTransaction"
          plugin = {
            name = "Joiner"
            type = "batchjoiner"
            properties = {
              joinKeys = "CustomerSource.customer_id=TransactionSource.customer_id"
              requiredInputs = "CustomerSource,TransactionSource"
            }
          }
        },
        {
          name = "BigQuerySink"
          plugin = {
            name = "BigQueryTable"
            type = "batchsink"
            properties = {
              project = var.project_id
              dataset = local.dataset_name
              table = "customer_transactions"
            }
          }
        }
      ]
      connections = [
        { from = "CustomerSource", to = "JoinCustomerTransaction" },
        { from = "TransactionSource", to = "JoinCustomerTransaction" },
        { from = "JoinCustomerTransaction", to = "BigQuerySink" }
      ]
    }
  })
  
  content_type = "application/json"
}