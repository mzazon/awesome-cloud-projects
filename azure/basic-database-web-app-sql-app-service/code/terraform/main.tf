# Main Terraform Configuration for Basic Database Web App
# This configuration deploys a complete web application infrastructure with
# Azure App Service and Azure SQL Database following security best practices

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Define local values for consistent naming and tagging
locals {
  # Generate unique suffix for resource names
  random_suffix = random_id.suffix.hex
  
  # Common resource naming convention
  resource_group_name  = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${local.random_suffix}"
  sql_server_name     = "sql-${var.project_name}-${var.environment}-${local.random_suffix}"
  app_service_plan_name = "asp-${var.project_name}-${var.environment}-${local.random_suffix}"
  web_app_name        = "app-${var.project_name}-${var.environment}-${local.random_suffix}"
  
  # Generate secure password if not provided
  sql_admin_password = var.sql_admin_password != null ? var.sql_admin_password : "${random_password.sql_password.result}"
  
  # Common tags applied to all resources
  common_tags = merge({
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Recipe      = "basic-database-web-app-sql-app-service"
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  }, var.additional_tags)
}

# Generate secure random password for SQL Database if not provided
resource "random_password" "sql_password" {
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
  
  # Ensure password meets Azure SQL requirements
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
  min_special = 1
}

# Create Resource Group to contain all infrastructure resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  
  tags = local.common_tags
}

# Create Azure SQL Database Server
# This provides the logical server container for SQL databases
resource "azurerm_mssql_server" "main" {
  name                         = local.sql_server_name
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = local.sql_admin_password
  
  # Security configurations
  minimum_tls_version               = "1.2"
  public_network_access_enabled     = true
  outbound_network_restriction_enabled = false
  
  # Azure AD authentication configuration (optional enhancement)
  azuread_administrator {
    login_username = var.sql_admin_username
    object_id     = data.azurerm_client_config.current.object_id
  }
  
  tags = local.common_tags
  
  lifecycle {
    ignore_changes = [
      # Ignore changes to password to prevent unnecessary updates
      administrator_login_password
    ]
  }
}

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Create SQL Database with Basic tier for cost optimization
resource "azurerm_mssql_database" "main" {
  name           = var.sql_database_name
  server_id      = azurerm_mssql_server.main.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  license_type   = "LicenseIncluded"
  sku_name       = var.sql_sku_name
  zone_redundant = false
  
  # Storage configuration for Basic tier
  max_size_gb    = 2
  storage_account_type = "Local"
  
  # Backup configuration
  short_term_retention_policy {
    retention_days = var.backup_retention_days
  }
  
  tags = local.common_tags
}

# Configure SQL Database firewall rule to allow Azure services
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  count            = var.allow_azure_services_access ? 1 : 0
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Create App Service Plan to host the web application
resource "azurerm_service_plan" "main" {
  name                = local.app_service_plan_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  os_type            = "Windows"
  sku_name           = var.app_service_sku_size
  
  tags = local.common_tags
}

# Create the Web App with system-assigned managed identity
resource "azurerm_windows_web_app" "main" {
  name                = local.web_app_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  service_plan_id    = azurerm_service_plan.main.id
  
  # Enable system-assigned managed identity for secure authentication
  identity {
    type = var.enable_system_assigned_identity ? "SystemAssigned" : null
  }
  
  # Application configuration
  site_config {
    # .NET Framework configuration
    application_stack {
      dotnet_version = "v${var.dotnet_version}"
    }
    
    # Security configurations
    always_on        = var.app_service_sku_tier != "Free" && var.app_service_sku_tier != "Shared"
    http2_enabled    = true
    minimum_tls_version = "1.2"
    
    # Default documents
    default_documents = [
      "Default.htm",
      "Default.html",
      "Default.asp",
      "index.htm",
      "index.html",
      "iisstart.htm",
      "default.aspx",
      "index.php"
    ]
  }
  
  # Database connection string configuration
  connection_string {
    name  = "DefaultConnection"
    type  = "SQLAzure"
    value = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.main.name};Persist Security Info=False;User ID=${var.sql_admin_username};Password=${local.sql_admin_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  }
  
  # Application settings for configuration
  app_settings = {
    "WEBSITE_RUN_FROM_PACKAGE" = "1"
    "ASPNETCORE_ENVIRONMENT"   = var.environment == "prod" ? "Production" : "Development"
  }
  
  tags = local.common_tags
  
  # Ensure database is created before web app
  depends_on = [
    azurerm_mssql_database.main,
    azurerm_mssql_firewall_rule.allow_azure_services
  ]
  
  lifecycle {
    ignore_changes = [
      # Ignore changes to connection strings to prevent drift
      connection_string
    ]
  }
}

# Create database schema and sample data using azurerm_mssql_database_extended_auditing_policy
# Note: This is a simplified approach. In production, use proper database migration tools
resource "null_resource" "database_setup" {
  # Trigger on database creation or schema changes
  triggers = {
    database_id = azurerm_mssql_database.main.id
    schema_hash = sha256(local.database_schema)
  }
  
  # Use Azure CLI to execute database setup
  provisioner "local-exec" {
    command = <<-EOT
      # Wait for database to be fully provisioned
      sleep 30
      
      # Install sqlcmd if not available (Linux/macOS)
      if ! command -v sqlcmd &> /dev/null; then
        echo "Installing sqlcmd..."
        # This requires manual installation on the deployment machine
        echo "Please install sqlcmd manually for database initialization"
        exit 0
      fi
      
      # Execute database schema creation
      sqlcmd -S "${azurerm_mssql_server.main.fully_qualified_domain_name}" \
             -d "${azurerm_mssql_database.main.name}" \
             -U "${var.sql_admin_username}" \
             -P "${local.sql_admin_password}" \
             -Q "${local.database_schema}"
    EOT
    
    environment = {
      SQLCMDPASSWORD = local.sql_admin_password
    }
  }
  
  depends_on = [
    azurerm_mssql_database.main,
    azurerm_mssql_firewall_rule.allow_azure_services
  ]
}

# Database schema and sample data
locals {
  database_schema = <<-EOT
    IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='Tasks' AND xtype='U')
    BEGIN
      CREATE TABLE Tasks (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        Title NVARCHAR(100) NOT NULL,
        Description NVARCHAR(500),
        IsCompleted BIT DEFAULT 0,
        CreatedDate DATETIME2 DEFAULT GETUTCDATE()
      );
      
      INSERT INTO Tasks (Title, Description) VALUES 
      ('Setup Database', 'Configure Azure SQL Database for the application'),
      ('Deploy Web App', 'Deploy the web application to Azure App Service'),
      ('Test Application', 'Verify database connectivity and functionality');
    END
  EOT
}

# Optional: Create Application Insights for monitoring (if enabled)
resource "azurerm_application_insights" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "appi-${var.project_name}-${var.environment}-${local.random_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  
  tags = local.common_tags
}

# Configure Application Insights connection (if enabled)
resource "azurerm_windows_web_app_slot" "staging" {
  count           = var.enable_monitoring ? 1 : 0
  name            = "staging"
  app_service_id  = azurerm_windows_web_app.main.id
  
  site_config {
    application_stack {
      dotnet_version = "v${var.dotnet_version}"
    }
  }
  
  app_settings = var.enable_monitoring ? {
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main[0].instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main[0].connection_string
  } : {}
  
  tags = local.common_tags
}