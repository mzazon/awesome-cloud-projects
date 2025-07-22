# Azure Orbital and AI Services Infrastructure for Satellite Data Analytics
# This Terraform configuration deploys a complete satellite data analytics platform
# using Azure Orbital, Synapse Analytics, AI Services, and supporting infrastructure

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and tagging
locals {
  # Resource naming convention: {project}-{resource_type}-{environment}-{suffix}
  resource_suffix = random_string.suffix.result
  
  # Common tags applied to all resources
  common_tags = merge({
    Environment     = var.environment
    Project         = var.project_name
    ManagedBy      = "Terraform"
    Purpose        = "Satellite Data Analytics"
    CreatedDate    = formatdate("YYYY-MM-DD", timestamp())
    CostCenter     = "Azure Orbital Analytics"
    DataClass      = "Satellite Imagery"
  }, var.additional_tags)
  
  # Resource names with consistent naming convention
  resource_group_name    = "rg-${var.project_name}-${var.environment}"
  storage_account_name   = "st${var.project_name}${var.environment}${local.resource_suffix}"
  synapse_workspace_name = "syn-${var.project_name}-${var.environment}-${local.resource_suffix}"
  eventhub_namespace_name = "eh-${var.project_name}-${var.environment}-${local.resource_suffix}"
  ai_services_name       = "ai-${var.project_name}-${var.environment}-${local.resource_suffix}"
  maps_account_name      = "maps-${var.project_name}-${var.environment}-${local.resource_suffix}"
  cosmos_account_name    = "cosmos-${var.project_name}-${var.environment}-${local.resource_suffix}"
  key_vault_name         = "kv-${var.project_name}-${var.environment}-${local.resource_suffix}"
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Resource Group - Central container for all orbital analytics resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Key Vault - Secure storage for connection strings, keys, and secrets
resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Enable purge protection for production environments
  purge_protection_enabled   = var.environment == "prod" ? true : false
  soft_delete_retention_days = 7

  # Network access configuration
  network_acls {
    default_action = var.enable_private_endpoints ? "Deny" : "Allow"
    bypass         = "AzureServices"
    ip_rules       = var.enable_private_endpoints ? [] : var.allowed_ip_ranges
  }

  tags = local.common_tags
}

# Key Vault Access Policy - Grant current user/service principal access
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"
  ]

  key_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Recover", "Backup", "Restore", "Purge"
  ]

  certificate_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Recover", "Backup", "Restore", "Purge"
  ]
}

# Data Lake Storage Gen2 - Foundational storage for satellite data
resource "azurerm_storage_account" "datalake" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type
  account_kind             = "StorageV2"
  access_tier              = var.storage_account_tier

  # Enable Data Lake Gen2 capabilities
  is_hns_enabled = true

  # Security configuration
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"

  # Network access rules
  network_rules {
    default_action = var.enable_private_endpoints ? "Deny" : "Allow"
    bypass         = ["AzureServices"]
    ip_rules       = var.enable_private_endpoints ? [] : var.allowed_ip_ranges
  }

  # Blob properties for optimized satellite data storage
  blob_properties {
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
    versioning_enabled = true
  }

  tags = local.common_tags
}

# Storage Containers for different data stages
resource "azurerm_storage_container" "raw_satellite_data" {
  name                  = "raw-satellite-data"
  storage_account_name  = azurerm_storage_account.datalake.name
  container_access_type = "private"

  metadata = {
    purpose = "Raw satellite imagery and telemetry data"
    stage   = "ingestion"
  }
}

resource "azurerm_storage_container" "processed_imagery" {
  name                  = "processed-imagery"
  storage_account_name  = azurerm_storage_account.datalake.name
  container_access_type = "private"

  metadata = {
    purpose = "Processed and normalized satellite imagery"
    stage   = "processing"
  }
}

resource "azurerm_storage_container" "ai_analysis_results" {
  name                  = "ai-analysis-results"
  storage_account_name  = azurerm_storage_account.datalake.name
  container_access_type = "private"

  metadata = {
    purpose = "AI analysis outputs and object detection results"
    stage   = "analysis"
  }
}

# Synapse File System for workspace integration
resource "azurerm_storage_data_lake_gen2_filesystem" "synapse" {
  name               = "synapse-fs"
  storage_account_id = azurerm_storage_account.datalake.id

  properties = {
    purpose = "Synapse Analytics workspace file system"
  }
}

# Event Hubs Namespace - High-throughput data streaming platform
resource "azurerm_eventhub_namespace" "main" {
  name                     = local.eventhub_namespace_name
  location                 = azurerm_resource_group.main.location
  resource_group_name      = azurerm_resource_group.main.name
  sku                      = "Standard"
  capacity                 = var.eventhub_throughput_units
  auto_inflate_enabled     = true
  maximum_throughput_units = var.eventhub_throughput_units

  # Network isolation configuration
  network_rulesets {
    default_action = var.enable_private_endpoints ? "Deny" : "Allow"
    trusted_service_access_enabled = true

    dynamic "ip_rule" {
      for_each = var.enable_private_endpoints ? [] : var.allowed_ip_ranges
      content {
        ip_mask = ip_rule.value
      }
    }
  }

  tags = local.common_tags
}

# Event Hub for satellite imagery streams
resource "azurerm_eventhub" "satellite_imagery" {
  name                = "satellite-imagery-stream"
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  partition_count     = var.eventhub_partition_count
  message_retention   = var.eventhub_message_retention

  capture_description {
    enabled  = true
    encoding = "Avro"
    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = azurerm_storage_container.raw_satellite_data.name
      storage_account_id  = azurerm_storage_account.datalake.id
    }
  }
}

# Event Hub for satellite telemetry data
resource "azurerm_eventhub" "satellite_telemetry" {
  name                = "satellite-telemetry-stream"
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.main.name
  partition_count     = 4
  message_retention   = 3

  capture_description {
    enabled  = true
    encoding = "Avro"
    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = azurerm_storage_container.raw_satellite_data.name
      storage_account_id  = azurerm_storage_account.datalake.id
    }
  }
}

# Synapse Analytics Workspace - Unified analytics platform
resource "azurerm_synapse_workspace" "main" {
  name                                 = local.synapse_workspace_name
  resource_group_name                  = azurerm_resource_group.main.name
  location                            = azurerm_resource_group.main.location
  storage_data_lake_gen2_filesystem_id = azurerm_storage_data_lake_gen2_filesystem.synapse.id

  # SQL Administrator credentials
  sql_administrator_login          = var.synapse_sql_admin_username
  sql_administrator_login_password = var.synapse_sql_admin_password

  # Security and networking configuration
  managed_virtual_network_enabled = true
  data_exfiltration_protection_enabled = var.environment == "prod" ? true : false

  # Azure AD authentication
  aad_admin {
    login     = "Synapse Administrator"
    object_id = data.azurerm_client_config.current.object_id
    tenant_id = data.azurerm_client_config.current.tenant_id
  }

  # Identity configuration for secure resource access
  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Synapse Spark Pool - Big data processing engine for satellite imagery
resource "azurerm_synapse_spark_pool" "main" {
  name                 = "sparkpool01"
  synapse_workspace_id = azurerm_synapse_workspace.main.id
  node_size_family     = "MemoryOptimized"
  node_size            = "Medium"
  cache_size           = 100

  # Auto-scaling configuration for variable workloads
  auto_scale {
    max_node_count = var.spark_pool_max_node_count
    min_node_count = var.spark_pool_min_node_count
  }

  # Auto-pause to reduce costs during inactive periods
  auto_pause {
    delay_in_minutes = var.enable_auto_pause ? var.auto_pause_delay_minutes : null
  }

  # Spark configuration optimized for image processing
  spark_config {
    content  = <<-EOT
spark.sql.adaptive.enabled=true
spark.sql.adaptive.coalescePartitions.enabled=true
spark.sql.adaptive.skewJoin.enabled=true
spark.serializer=org.apache.spark.serializer.KryoSerializer
spark.sql.execution.arrow.pyspark.enabled=true
spark.databricks.delta.preview.enabled=true
    EOT
    filename = "spark-config.conf"
  }

  tags = local.common_tags
}

# Synapse SQL Pool - Data warehousing for structured analytics
resource "azurerm_synapse_sql_pool" "main" {
  name                 = "sqlpool01"
  synapse_workspace_id = azurerm_synapse_workspace.main.id
  sku_name             = var.sql_pool_sku
  create_mode          = "Default"

  # Security configuration
  data_encrypted = true

  tags = local.common_tags
}

# Azure AI Services - Cognitive capabilities for image analysis
resource "azurerm_cognitive_account" "main" {
  name                = local.ai_services_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "CognitiveServices"
  sku_name            = var.cognitive_services_sku

  # Custom subdomain for API access
  custom_subdomain_name = local.ai_services_name

  # Network access configuration
  network_acls {
    default_action = var.enable_private_endpoints ? "Deny" : "Allow"

    dynamic "ip_rules" {
      for_each = var.enable_private_endpoints ? [] : var.allowed_ip_ranges
      content {
        ip_range = ip_rules.value
      }
    }
  }

  tags = local.common_tags
}

# Custom Vision Training Resource - Specialized satellite object detection
resource "azurerm_cognitive_account" "custom_vision_training" {
  name                = "cv-training-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "CustomVision.Training"
  sku_name            = var.custom_vision_training_sku

  tags = local.common_tags
}

# Azure Maps Account - Geospatial visualization platform
resource "azurerm_maps_account" "main" {
  name                = local.maps_account_name
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = var.maps_sku

  tags = local.common_tags
}

# Cosmos DB Account - Globally distributed database for metadata and results
resource "azurerm_cosmosdb_account" "main" {
  name                = local.cosmos_account_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  # Consistency and availability configuration
  consistency_policy {
    consistency_level       = var.cosmos_consistency_level
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }

  # Geographic distribution configuration
  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
    zone_redundant    = var.environment == "prod" ? true : false
  }

  # Backup and restore configuration
  backup {
    type                = "Periodic"
    interval_in_minutes = 240
    retention_in_hours  = 8
    storage_redundancy  = "Local"
  }

  # Network access configuration
  is_virtual_network_filter_enabled = var.enable_private_endpoints
  public_network_access_enabled     = !var.enable_private_endpoints

  tags = local.common_tags
}

# Cosmos DB Database for satellite analytics
resource "azurerm_cosmosdb_sql_database" "satellite_analytics" {
  name                = "SatelliteAnalytics"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name

  # Shared throughput configuration for cost optimization
  throughput = var.cosmos_throughput
}

# Cosmos DB Container for imagery metadata
resource "azurerm_cosmosdb_sql_container" "imagery_metadata" {
  name                = "ImageryMetadata"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.satellite_analytics.name
  partition_key_path  = "/satelliteId"

  # Indexing policy optimized for satellite data queries
  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/rawImageData/*"
    }

    composite_index {
      index {
        path  = "/satelliteId"
        order = "ascending"
      }
      index {
        path  = "/timestamp"
        order = "descending"
      }
    }
  }

  # Unique key constraints for data integrity
  unique_key {
    paths = ["/satelliteId", "/imageId"]
  }
}

# Cosmos DB Container for AI analysis results
resource "azurerm_cosmosdb_sql_container" "ai_analysis_results" {
  name                = "AIAnalysisResults"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.satellite_analytics.name
  partition_key_path  = "/imageId"

  # Time-to-live configuration for result archival
  default_ttl = 2592000 # 30 days in seconds

  # Indexing policy for analysis result queries
  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    composite_index {
      index {
        path  = "/imageId"
        order = "ascending"
      }
      index {
        path  = "/analysisTimestamp"
        order = "descending"
      }
    }

    composite_index {
      index {
        path  = "/detectionType"
        order = "ascending"
      }
      index {
        path  = "/confidence"
        order = "descending"
      }
    }
  }
}

# Cosmos DB Container for geospatial indexing
resource "azurerm_cosmosdb_sql_container" "geospatial_index" {
  name                = "GeospatialIndex"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.satellite_analytics.name
  partition_key_path  = "/gridCell"

  # Spatial indexing for geographic queries
  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    spatial_index {
      path = "/location/*"
    }

    composite_index {
      index {
        path  = "/gridCell"
        order = "ascending"
      }
      index {
        path  = "/timestamp"
        order = "descending"
      }
    }
  }
}

# Store sensitive configuration in Key Vault
resource "azurerm_key_vault_secret" "eventhub_connection" {
  name         = "EventHubConnection"
  value        = azurerm_eventhub_namespace.main.default_primary_connection_string
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.current_user]

  tags = local.common_tags
}

resource "azurerm_key_vault_secret" "ai_services_endpoint" {
  name         = "AIServicesEndpoint"
  value        = azurerm_cognitive_account.main.endpoint
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.current_user]

  tags = local.common_tags
}

resource "azurerm_key_vault_secret" "ai_services_key" {
  name         = "AIServicesKey"
  value        = azurerm_cognitive_account.main.primary_access_key
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.current_user]

  tags = local.common_tags
}

resource "azurerm_key_vault_secret" "maps_subscription_key" {
  name         = "MapsSubscriptionKey"
  value        = azurerm_maps_account.main.primary_access_key
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.current_user]

  tags = local.common_tags
}

resource "azurerm_key_vault_secret" "cosmos_endpoint" {
  name         = "CosmosEndpoint"
  value        = azurerm_cosmosdb_account.main.endpoint
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.current_user]

  tags = local.common_tags
}

resource "azurerm_key_vault_secret" "cosmos_key" {
  name         = "CosmosKey"
  value        = azurerm_cosmosdb_account.main.primary_key
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.current_user]

  tags = local.common_tags
}

# Role assignments for Synapse workspace to access storage and other resources
resource "azurerm_role_assignment" "synapse_storage_blob_data_contributor" {
  scope                = azurerm_storage_account.datalake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_synapse_workspace.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "synapse_eventhub_data_receiver" {
  scope                = azurerm_eventhub_namespace.main.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azurerm_synapse_workspace.main.identity[0].principal_id
}

# Log Analytics Workspace for monitoring and diagnostics
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_diagnostic_logs ? 1 : 0
  name                = "law-${var.project_name}-${var.environment}-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = local.common_tags
}

# Diagnostic settings for key resources
resource "azurerm_monitor_diagnostic_setting" "synapse_workspace" {
  count                          = var.enable_diagnostic_logs ? 1 : 0
  name                           = "diag-synapse-workspace"
  target_resource_id             = azurerm_synapse_workspace.main.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "SynapseRbacOperations"
  }

  enabled_log {
    category = "GatewayApiRequests"
  }

  enabled_log {
    category = "BuiltinSqlReqsEnded"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "eventhub_namespace" {
  count                          = var.enable_diagnostic_logs ? 1 : 0
  name                           = "diag-eventhub-namespace"
  target_resource_id             = azurerm_eventhub_namespace.main.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "ArchiveLogs"
  }

  enabled_log {
    category = "OperationalLogs"
  }

  enabled_log {
    category = "AutoScaleLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "cosmos_account" {
  count                          = var.enable_diagnostic_logs ? 1 : 0
  name                           = "diag-cosmos-account"
  target_resource_id             = azurerm_cosmosdb_account.main.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "DataPlaneRequests"
  }

  enabled_log {
    category = "QueryRuntimeStatistics"
  }

  enabled_log {
    category = "PartitionKeyStatistics"
  }

  metric {
    category = "Requests"
    enabled  = true
  }
}