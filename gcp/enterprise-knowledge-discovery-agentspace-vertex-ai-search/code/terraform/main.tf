# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming
locals {
  resource_prefix = "${var.application_name}-${var.environment}"
  unique_suffix   = random_string.suffix.result
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
  })
  
  # Service APIs to enable
  required_apis = [
    "discoveryengine.googleapis.com",
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "aiplatform.googleapis.com",
    "monitoring.googleapis.com",
    "iam.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Wait for APIs to be enabled before creating resources
resource "time_sleep" "api_enablement" {
  depends_on = [google_project_service.required_apis]
  
  create_duration = "60s"
}

#------------------------------------------------------------------------------
# Cloud Storage Resources
#------------------------------------------------------------------------------

# Cloud Storage bucket for enterprise documents
resource "google_storage_bucket" "document_repository" {
  name     = "${local.resource_prefix}-docs-${local.unique_suffix}"
  location = var.region
  
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = lifecycle_rule.value.action.storage_class
      }
      condition {
        age                   = lifecycle_rule.value.condition.age
        created_before        = lifecycle_rule.value.condition.created_before
        with_state           = lifecycle_rule.value.condition.with_state
        matches_storage_class = lifecycle_rule.value.condition.matches_storage_class
      }
    }
  }
  
  labels = local.common_labels
  
  depends_on = [time_sleep.api_enablement]
}

# Sample documents for testing (created as local files then uploaded)
resource "google_storage_bucket_object" "sample_documents" {
  for_each = var.create_sample_documents ? var.sample_documents : {}
  
  name   = each.value.path
  bucket = google_storage_bucket.document_repository.name
  content = each.value.content
  
  content_type = "text/plain"
}

#------------------------------------------------------------------------------
# BigQuery Resources
#------------------------------------------------------------------------------

# BigQuery dataset for search analytics
resource "google_bigquery_dataset" "knowledge_analytics" {
  dataset_id                 = replace("${local.resource_prefix}_analytics_${local.unique_suffix}", "-", "_")
  friendly_name              = "Enterprise Knowledge Discovery Analytics"
  description                = "Analytics data for enterprise knowledge discovery system"
  location                   = var.bigquery_location
  delete_contents_on_destroy = !var.bigquery_deletion_protection
  
  labels = local.common_labels
  
  depends_on = [time_sleep.api_enablement]
}

# BigQuery table for search queries
resource "google_bigquery_table" "search_queries" {
  dataset_id          = google_bigquery_dataset.knowledge_analytics.dataset_id
  table_id            = "search_queries"
  deletion_protection = var.bigquery_deletion_protection
  
  schema = jsonencode([
    {
      name = "query_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the search query"
    },
    {
      name = "user_id"
      type = "STRING"
      mode = "NULLABLE"
      description = "Identifier of the user who performed the search"
    },
    {
      name = "query_text"
      type = "STRING"
      mode = "REQUIRED"
      description = "The actual search query text"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "When the search was performed"
    },
    {
      name = "results_count"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Number of results returned"
    },
    {
      name = "click_through_rate"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Click-through rate for the search results"
    }
  ])
  
  labels = local.common_labels
}

# BigQuery table for document analytics
resource "google_bigquery_table" "document_analytics" {
  dataset_id          = google_bigquery_dataset.knowledge_analytics.dataset_id
  table_id            = "document_analytics"
  deletion_protection = var.bigquery_deletion_protection
  
  schema = jsonencode([
    {
      name = "document_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the document"
    },
    {
      name = "document_name"
      type = "STRING"
      mode = "REQUIRED"
      description = "Name of the document"
    },
    {
      name = "view_count"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Number of times the document was viewed"
    },
    {
      name = "last_accessed"
      type = "TIMESTAMP"
      mode = "NULLABLE"
      description = "Last time the document was accessed"
    },
    {
      name = "relevance_score"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Relevance score of the document for searches"
    }
  ])
  
  labels = local.common_labels
}

#------------------------------------------------------------------------------
# Discovery Engine Resources
#------------------------------------------------------------------------------

# Discovery Engine data store for enterprise search
resource "google_discovery_engine_data_store" "enterprise_search" {
  provider = google-beta
  
  location         = var.discovery_engine_location
  data_store_id    = "${local.resource_prefix}-search-${local.unique_suffix}"
  display_name     = "Enterprise Knowledge Search"
  industry_vertical = "GENERIC"
  solution_types   = ["SOLUTION_TYPE_SEARCH"]
  content_config   = "CONTENT_REQUIRED"
  
  depends_on = [time_sleep.api_enablement]
}

# Discovery Engine search engine
resource "google_discovery_engine_search_engine" "knowledge_engine" {
  provider = google-beta
  
  engine_id     = "${local.resource_prefix}-engine-${local.unique_suffix}"
  collection_id = "default_collection"
  location      = var.discovery_engine_location
  display_name  = "Enterprise Knowledge Engine"
  
  data_store_ids = [google_discovery_engine_data_store.enterprise_search.data_store_id]
  
  search_engine_config {
    search_tier = var.search_engine_config.search_tier
    search_add_ons = ["SEARCH_ADD_ON_LLM"]
  }
  
  common_config {
    company_name = var.application_name
  }
}

#------------------------------------------------------------------------------
# IAM Resources
#------------------------------------------------------------------------------

# Custom IAM role for knowledge discovery readers
resource "google_project_iam_custom_role" "knowledge_reader" {
  role_id     = "knowledgeDiscoveryReader"
  title       = "Knowledge Discovery Reader"
  description = "Can search and read enterprise knowledge"
  stage       = "GA"
  
  permissions = [
    "discoveryengine.engines.search",
    "discoveryengine.dataStores.get",
    "storage.objects.get",
    "bigquery.tables.get",
    "bigquery.tables.getData"
  ]
}

# Custom IAM role for knowledge discovery administrators
resource "google_project_iam_custom_role" "knowledge_admin" {
  role_id     = "knowledgeDiscoveryAdmin"
  title       = "Knowledge Discovery Administrator"
  description = "Can manage enterprise knowledge systems"
  stage       = "GA"
  
  permissions = [
    "discoveryengine.*",
    "storage.objects.*",
    "bigquery.datasets.*",
    "bigquery.tables.*"
  ]
}

# Service account for the knowledge discovery system
resource "google_service_account" "knowledge_discovery" {
  account_id   = "${local.resource_prefix}-sa-${local.unique_suffix}"
  display_name = "Knowledge Discovery Service Account"
  description  = "Service account for enterprise knowledge discovery system"
}

# Grant knowledge reader role to service account
resource "google_project_iam_member" "service_account_reader" {
  project = var.project_id
  role    = google_project_iam_custom_role.knowledge_reader.name
  member  = "serviceAccount:${google_service_account.knowledge_discovery.email}"
}

# Grant BigQuery Data Viewer to service account
resource "google_project_iam_member" "service_account_bigquery" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.knowledge_discovery.email}"
}

# Grant storage object viewer to service account
resource "google_project_iam_member" "service_account_storage" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.knowledge_discovery.email}"
}

# IAM bindings for knowledge readers
resource "google_project_iam_member" "knowledge_readers" {
  for_each = toset(var.knowledge_readers)
  
  project = var.project_id
  role    = google_project_iam_custom_role.knowledge_reader.name
  member  = each.value
}

# IAM bindings for knowledge administrators
resource "google_project_iam_member" "knowledge_admins" {
  for_each = toset(var.knowledge_admins)
  
  project = var.project_id
  role    = google_project_iam_custom_role.knowledge_admin.name
  member  = each.value
}

#------------------------------------------------------------------------------
# Monitoring Resources
#------------------------------------------------------------------------------

# Cloud Monitoring dashboard for knowledge discovery analytics
resource "google_monitoring_dashboard" "knowledge_discovery" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Enterprise Knowledge Discovery Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Search Query Volume"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  unitOverride = "1"
                  outputFullResourceType = false
                }
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Queries"
                scale = "LINEAR"
              }
            }
          }
        }
        {
          width  = 6
          height = 4
          widget = {
            title = "Document Access Patterns"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  unitOverride = "1"
                  outputFullResourceType = false
                }
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Access Count"
                scale = "LINEAR"
              }
            }
          }
        }
        {
          width  = 12
          height = 4
          widget = {
            title = "System Health Overview"
            scorecard = {
              timeSeriesQuery = {
                unitOverride = "1"
                outputFullResourceType = false
              }
              sparkChartView = {
                sparkChartType = "SPARK_LINE"
              }
            }
          }
        }
      ]
    }
  })
  
  depends_on = [time_sleep.api_enablement]
}

#------------------------------------------------------------------------------
# Sample Analytics Data
#------------------------------------------------------------------------------

# Insert sample search analytics data for testing
resource "google_bigquery_job" "sample_search_data" {
  count = var.create_sample_documents ? 1 : 0
  
  job_id = "sample-search-data-${local.unique_suffix}"
  
  query {
    query = <<-EOQ
      INSERT INTO `${var.project_id}.${google_bigquery_dataset.knowledge_analytics.dataset_id}.search_queries` VALUES
      ('q1', 'user1', 'remote work policy', CURRENT_TIMESTAMP(), 5, 0.8),
      ('q2', 'user2', 'API documentation customer service', CURRENT_TIMESTAMP(), 3, 0.6),
      ('q3', 'user3', 'quarterly financial results', CURRENT_TIMESTAMP(), 2, 1.0),
      ('q4', 'user1', 'employee handbook security', CURRENT_TIMESTAMP(), 4, 0.5)
    EOQ
    
    use_legacy_sql = false
  }
  
  depends_on = [google_bigquery_table.search_queries]
}

# Insert sample document analytics data
resource "google_bigquery_job" "sample_document_data" {
  count = var.create_sample_documents ? 1 : 0
  
  job_id = "sample-document-data-${local.unique_suffix}"
  
  query {
    query = <<-EOQ
      INSERT INTO `${var.project_id}.${google_bigquery_dataset.knowledge_analytics.dataset_id}.document_analytics` VALUES
      ('doc1', 'hr_policy.txt', 25, CURRENT_TIMESTAMP(), 0.85),
      ('doc2', 'api_documentation.txt', 18, CURRENT_TIMESTAMP(), 0.92),
      ('doc3', 'financial_report.txt', 12, CURRENT_TIMESTAMP(), 0.78)
    EOQ
    
    use_legacy_sql = false
  }
  
  depends_on = [google_bigquery_table.document_analytics]
}