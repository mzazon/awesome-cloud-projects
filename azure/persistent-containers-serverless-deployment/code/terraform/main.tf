# Main Terraform configuration for deploying stateful container workloads
# with Azure Container Instances and Azure Files

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Create resource group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Create Log Analytics workspace for container monitoring
resource "azurerm_log_analytics_workspace" "main" {
  count               = var.enable_log_analytics ? 1 : 0
  name                = "log-${var.project_name}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

# Create storage account for Azure Files
resource "azurerm_storage_account" "main" {
  name                     = "${replace(var.project_name, "-", "")}storage${random_id.suffix.hex}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Enable large file shares for better performance
  large_file_share_enabled = true
  
  # Enable secure transfer and disable public access
  enable_https_traffic_only = true
  allow_nested_items_to_be_public = false
  
  tags = var.tags
}

# Create Azure Files file share
resource "azurerm_storage_share" "main" {
  name                 = var.file_share_name
  storage_account_name = azurerm_storage_account.main.name
  quota                = var.file_share_quota
  enabled_protocol     = "SMB"
  access_tier          = "Hot"
}

# Create directories in the file share for organized storage
resource "azurerm_storage_share_directory" "app_data" {
  name             = "app-data"
  share_name       = azurerm_storage_share.main.name
  storage_account_name = azurerm_storage_account.main.name
}

resource "azurerm_storage_share_directory" "database" {
  name             = "database"
  share_name       = azurerm_storage_share.main.name
  storage_account_name = azurerm_storage_account.main.name
}

resource "azurerm_storage_share_directory" "logs" {
  name             = "logs"
  share_name       = azurerm_storage_share.main.name
  storage_account_name = azurerm_storage_account.main.name
}

# Create Azure Container Registry for private container images
resource "azurerm_container_registry" "main" {
  name                = "${replace(var.project_name, "-", "")}registry${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.container_registry_sku
  admin_enabled       = true
  
  # Enable quarantine policy for security scanning
  quarantine_policy_enabled = var.container_registry_sku == "Premium" ? true : false
  
  tags = var.tags
}

# Deploy PostgreSQL container with persistent storage
resource "azurerm_container_group" "postgres" {
  name                = "${var.project_name}-postgres"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  ip_address_type     = "Private"
  os_type             = "Linux"
  restart_policy      = var.container_restart_policy
  
  # Configure Log Analytics for monitoring
  dynamic "diagnostics" {
    for_each = var.enable_log_analytics ? [1] : []
    content {
      log_analytics {
        workspace_id  = azurerm_log_analytics_workspace.main[0].workspace_id
        workspace_key = azurerm_log_analytics_workspace.main[0].primary_shared_key
      }
    }
  }
  
  container {
    name   = "postgres"
    image  = "postgres:13"
    cpu    = var.postgres_cpu_cores
    memory = var.postgres_memory_gb
    
    # Configure environment variables for PostgreSQL
    environment_variables = {
      POSTGRES_DB   = var.postgres_database
      PGDATA        = "/var/lib/postgresql/data/pgdata"
    }
    
    # Configure sensitive environment variables
    secure_environment_variables = {
      POSTGRES_PASSWORD = var.postgres_password
    }
    
    # Configure persistent storage volume
    volume {
      name                 = "postgres-data"
      mount_path           = "/var/lib/postgresql/data"
      storage_account_name = azurerm_storage_account.main.name
      storage_account_key  = azurerm_storage_account.main.primary_access_key
      share_name           = azurerm_storage_share.main.name
    }
    
    # Configure readiness probe for PostgreSQL
    readiness_probe {
      exec                = ["pg_isready", "-U", "postgres"]
      initial_delay_seconds = 30
      period_seconds       = 10
      failure_threshold    = 3
      success_threshold    = 1
      timeout_seconds      = 5
    }
    
    # Configure liveness probe for PostgreSQL
    liveness_probe {
      exec                = ["pg_isready", "-U", "postgres"]
      initial_delay_seconds = 60
      period_seconds       = 20
      failure_threshold    = 3
      success_threshold    = 1
      timeout_seconds      = 5
    }
  }
  
  tags = var.tags
}

# Deploy application container with shared storage
resource "azurerm_container_group" "app" {
  name                = "${var.project_name}-app"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  ip_address_type     = "Public"
  dns_name_label      = "${var.project_name}-app-${random_id.suffix.hex}"
  os_type             = "Linux"
  restart_policy      = var.container_restart_policy
  
  # Configure Log Analytics for monitoring
  dynamic "diagnostics" {
    for_each = var.enable_log_analytics ? [1] : []
    content {
      log_analytics {
        workspace_id  = azurerm_log_analytics_workspace.main[0].workspace_id
        workspace_key = azurerm_log_analytics_workspace.main[0].primary_shared_key
      }
    }
  }
  
  container {
    name   = "nginx-app"
    image  = "nginx:alpine"
    cpu    = var.app_cpu_cores
    memory = var.app_memory_gb
    
    # Configure port for web application
    ports {
      port     = 80
      protocol = "TCP"
    }
    
    # Configure shared storage volume
    volume {
      name                 = "app-data"
      mount_path           = "/usr/share/nginx/html"
      storage_account_name = azurerm_storage_account.main.name
      storage_account_key  = azurerm_storage_account.main.primary_access_key
      share_name           = azurerm_storage_share.main.name
    }
    
    # Configure readiness probe for Nginx
    readiness_probe {
      http_get {
        path   = "/"
        port   = 80
        scheme = "Http"
      }
      initial_delay_seconds = 10
      period_seconds       = 5
      failure_threshold    = 3
      success_threshold    = 1
      timeout_seconds      = 3
    }
    
    # Configure liveness probe for Nginx
    liveness_probe {
      http_get {
        path   = "/"
        port   = 80
        scheme = "Http"
      }
      initial_delay_seconds = 30
      period_seconds       = 10
      failure_threshold    = 3
      success_threshold    = 1
      timeout_seconds      = 5
    }
  }
  
  tags = var.tags
}

# Deploy worker container for background processing
resource "azurerm_container_group" "worker" {
  name                = "${var.project_name}-worker"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  ip_address_type     = "Private"
  os_type             = "Linux"
  restart_policy      = var.container_restart_policy
  
  # Configure Log Analytics for monitoring
  dynamic "diagnostics" {
    for_each = var.enable_log_analytics ? [1] : []
    content {
      log_analytics {
        workspace_id  = azurerm_log_analytics_workspace.main[0].workspace_id
        workspace_key = azurerm_log_analytics_workspace.main[0].primary_shared_key
      }
    }
  }
  
  container {
    name   = "worker"
    image  = "alpine:latest"
    cpu    = var.worker_cpu_cores
    memory = var.worker_memory_gb
    
    # Configure worker command for background processing
    commands = [
      "sh",
      "-c",
      "while true; do echo \"Worker processing at $(date)\" >> /shared/logs/worker.log; sleep 60; done"
    ]
    
    # Configure shared storage volume
    volume {
      name                 = "shared-data"
      mount_path           = "/shared"
      storage_account_name = azurerm_storage_account.main.name
      storage_account_key  = azurerm_storage_account.main.primary_access_key
      share_name           = azurerm_storage_share.main.name
    }
    
    # Configure liveness probe for worker
    liveness_probe {
      exec                = ["sh", "-c", "test -f /shared/logs/worker.log"]
      initial_delay_seconds = 120
      period_seconds       = 30
      failure_threshold    = 3
      success_threshold    = 1
      timeout_seconds      = 10
    }
  }
  
  tags = var.tags
}

# Deploy monitored application container with enhanced logging
resource "azurerm_container_group" "monitored_app" {
  name                = "${var.project_name}-monitored-app"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  ip_address_type     = "Public"
  dns_name_label      = "${var.project_name}-monitored-${random_id.suffix.hex}"
  os_type             = "Linux"
  restart_policy      = var.container_restart_policy
  
  # Configure Log Analytics for monitoring
  dynamic "diagnostics" {
    for_each = var.enable_log_analytics ? [1] : []
    content {
      log_analytics {
        workspace_id  = azurerm_log_analytics_workspace.main[0].workspace_id
        workspace_key = azurerm_log_analytics_workspace.main[0].primary_shared_key
      }
    }
  }
  
  container {
    name   = "monitored-nginx"
    image  = "nginx:alpine"
    cpu    = var.app_cpu_cores
    memory = var.app_memory_gb
    
    # Configure port for web application
    ports {
      port     = 80
      protocol = "TCP"
    }
    
    # Configure shared storage volume
    volume {
      name                 = "app-data"
      mount_path           = "/usr/share/nginx/html"
      storage_account_name = azurerm_storage_account.main.name
      storage_account_key  = azurerm_storage_account.main.primary_access_key
      share_name           = azurerm_storage_share.main.name
    }
    
    # Configure readiness probe for Nginx
    readiness_probe {
      http_get {
        path   = "/"
        port   = 80
        scheme = "Http"
      }
      initial_delay_seconds = 10
      period_seconds       = 5
      failure_threshold    = 3
      success_threshold    = 1
      timeout_seconds      = 3
    }
    
    # Configure liveness probe for Nginx
    liveness_probe {
      http_get {
        path   = "/"
        port   = 80
        scheme = "Http"
      }
      initial_delay_seconds = 30
      period_seconds       = 10
      failure_threshold    = 3
      success_threshold    = 1
      timeout_seconds      = 5
    }
  }
  
  tags = var.tags
}

# Create a sample HTML file in the Azure Files share for testing
resource "azurerm_storage_share_file" "index_html" {
  name             = "index.html"
  storage_share_id = azurerm_storage_share.main.id
  source           = "${path.module}/index.html"
  
  depends_on = [azurerm_storage_share_directory.app_data]
}

# Create the sample HTML file content
resource "local_file" "index_html" {
  filename = "${path.module}/index.html"
  content  = <<-EOT
<!DOCTYPE html>
<html>
<head>
    <title>Stateful Container Workloads</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
        .status { background-color: #e7f3ff; padding: 20px; border-radius: 5px; margin: 20px 0; }
        .success { color: #4caf50; }
        .info { color: #2196f3; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Stateful Container Workloads with Azure Container Instances</h1>
        <div class="status">
            <h2 class="success">✅ Deployment Successful!</h2>
            <p><strong>Project:</strong> ${var.project_name}</p>
            <p><strong>Environment:</strong> ${var.environment}</p>
            <p><strong>Storage Account:</strong> ${azurerm_storage_account.main.name}</p>
            <p><strong>File Share:</strong> ${var.file_share_name}</p>
            <p><strong>Container Registry:</strong> ${azurerm_container_registry.main.name}</p>
        </div>
        <div class="status">
            <h3 class="info">Container Instances</h3>
            <ul>
                <li>PostgreSQL Database - Persistent storage for application data</li>
                <li>Nginx Application - Web server with shared storage</li>
                <li>Background Worker - Processing tasks with log storage</li>
                <li>Monitored Application - Enhanced logging and monitoring</li>
            </ul>
        </div>
        <div class="status">
            <h3 class="info">Azure Files Integration</h3>
            <p>This application demonstrates how Azure Container Instances can use Azure Files for persistent storage, enabling stateful container workloads with data persistence across container restarts and deployments.</p>
        </div>
    </div>
</body>
</html>
EOT
}