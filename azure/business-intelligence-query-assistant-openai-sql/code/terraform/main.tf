# Business Intelligence Query Assistant with Azure OpenAI and SQL Database
# This Terraform configuration deploys a complete business intelligence solution
# that converts natural language queries to SQL using Azure OpenAI Service

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  # Generate unique resource names with suffix
  suffix = random_string.suffix.result
  
  # Resource naming convention: {service}-{project}-{environment}-{suffix}
  openai_service_name   = "openai-${var.project_name}-${var.environment}-${local.suffix}"
  sql_server_name       = "sql-${var.project_name}-${var.environment}-${local.suffix}"
  function_app_name     = "func-${var.project_name}-${var.environment}-${local.suffix}"
  storage_account_name  = "st${var.project_name}${var.environment}${local.suffix}"
  app_insights_name     = "appi-${var.project_name}-${var.environment}-${local.suffix}"
  
  # Common tags to apply to all resources
  common_tags = merge(var.tags, {
    Environment   = var.environment
    Project       = var.project_name
    ManagedBy     = "Terraform"
    CreationDate  = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # SQL Server password - generate if not provided
  sql_password = var.sql_admin_password != null ? var.sql_admin_password : random_password.sql_admin_password[0].result
}

# Generate secure random password for SQL Server if not provided
resource "random_password" "sql_admin_password" {
  count   = var.sql_admin_password == null ? 1 : 0
  length  = 16
  special = true
  
  # Ensure password meets Azure SQL requirements
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
  min_special = 1
}

# Create Resource Group for all resources
resource "azurerm_resource_group" "main" {
  name     = "${var.resource_group_name}-${var.environment}-${local.suffix}"
  location = var.location
  tags     = local.common_tags
}

# ================================
# Azure OpenAI Service Resources
# ================================

# Create Azure OpenAI Service (Cognitive Services Account)
resource "azurerm_cognitive_account" "openai" {
  name                = local.openai_service_name
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind               = "OpenAI"
  sku_name           = "S0"
  
  # Custom subdomain is required for OpenAI Service
  custom_subdomain_name = local.openai_service_name
  
  # Network access configuration
  public_network_access_enabled = true
  
  tags = local.common_tags
}

# Deploy GPT-4o model for natural language to SQL conversion
resource "azurerm_cognitive_deployment" "gpt_model" {
  name                 = var.openai_model_name
  cognitive_account_id = azurerm_cognitive_account.openai.id
  
  model {
    format  = "OpenAI"
    name    = var.openai_model_name
    version = var.openai_model_version
  }
  
  sku {
    name     = "Standard"
    capacity = var.openai_deployment_capacity
  }
  
  depends_on = [azurerm_cognitive_account.openai]
}

# ================================
# Azure SQL Database Resources
# ================================

# Create SQL Server
resource "azurerm_mssql_server" "main" {
  name                         = local.sql_server_name
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = local.sql_password
  
  # Security configuration
  minimum_tls_version = "1.2"
  
  # Azure AD authentication configuration
  azuread_administrator {
    login_username              = "AzureAD Admin"
    object_id                   = data.azurerm_client_config.current.object_id
    tenant_id                   = data.azurerm_client_config.current.tenant_id
    azuread_authentication_only = false
  }
  
  tags = local.common_tags
}

# Create SQL Database
resource "azurerm_mssql_database" "main" {
  name         = var.sql_database_name
  server_id    = azurerm_mssql_server.main.id
  sku_name     = var.sql_database_sku
  
  # Backup configuration
  short_term_retention_policy {
    retention_days = 7
  }
  
  tags = local.common_tags
}

# Configure SQL Server firewall to allow Azure services
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Create firewall rules for additional IP ranges if specified
resource "azurerm_mssql_firewall_rule" "allowed_ips" {
  count            = length(var.allowed_ip_ranges)
  name             = "AllowedRange${count.index + 1}"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = cidrhost(var.allowed_ip_ranges[count.index], 0)
  end_ip_address   = cidrhost(var.allowed_ip_ranges[count.index], -1)
}

# ================================
# Storage Account for Function App
# ================================

# Create Storage Account for Function App
resource "azurerm_storage_account" "function_storage" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Security configuration
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  # Network access configuration
  public_network_access_enabled = true
  
  tags = local.common_tags
}

# ================================
# Application Insights for Monitoring
# ================================

# Create Application Insights for Function App monitoring
resource "azurerm_application_insights" "main" {
  count               = var.enable_application_insights ? 1 : 0
  name                = local.app_insights_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  
  tags = local.common_tags
}

# ================================
# Service Plan for Function App
# ================================

# Create Service Plan for Function App (Consumption Plan)
resource "azurerm_service_plan" "function_plan" {
  name                = "plan-${var.project_name}-${var.environment}-${local.suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = "Y1"  # Consumption Plan
  
  tags = local.common_tags
}

# ================================
# Azure Function App
# ================================

# Create Function App for business intelligence query processing
resource "azurerm_linux_function_app" "main" {
  name                = local.function_app_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.function_plan.id
  
  # Storage account configuration
  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  
  # Function App configuration
  functions_extension_version = "~4"
  
  # Enable managed identity if specified
  dynamic "identity" {
    for_each = var.enable_managed_identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }
  
  # Site configuration
  site_config {
    # Runtime configuration
    application_stack {
      node_version = var.function_app_runtime == "node" ? var.function_app_runtime_version : null
    }
    
    # CORS configuration for web applications
    cors {
      allowed_origins = ["*"]
    }
    
    # Application Insights integration
    application_insights_key               = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
    application_insights_connection_string = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  }
  
  # Application settings for Function App
  app_settings = {
    # Azure OpenAI Service configuration
    "AZURE_OPENAI_ENDPOINT"     = azurerm_cognitive_account.openai.endpoint
    "AZURE_OPENAI_KEY"          = azurerm_cognitive_account.openai.primary_access_key
    "AZURE_OPENAI_DEPLOYMENT"   = azurerm_cognitive_deployment.gpt_model.name
    
    # SQL Database connection configuration
    "SQL_CONNECTION_STRING" = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.main.name};Persist Security Info=False;User ID=${var.sql_admin_username};Password=${local.sql_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    
    # Function App runtime configuration
    "FUNCTIONS_WORKER_RUNTIME"     = var.function_app_runtime
    "WEBSITE_NODE_DEFAULT_VERSION" = var.function_app_runtime == "node" ? "~${var.function_app_runtime_version}" : null
    
    # Enable detailed error logging
    "FUNCTIONS_ENABLE_LOGGING" = "true"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "false"
  }
  
  tags = local.common_tags
  
  depends_on = [
    azurerm_cognitive_deployment.gpt_model,
    azurerm_mssql_database.main,
    azurerm_storage_account.function_storage
  ]
}

# ================================
# Role Assignments for Managed Identity
# ================================

# Assign Cognitive Services User role to Function App managed identity
resource "azurerm_role_assignment" "openai_access" {
  count                = var.enable_managed_identity ? 1 : 0
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
  
  depends_on = [azurerm_linux_function_app.main]
}

# Assign SQL DB Contributor role to Function App managed identity for database access
resource "azurerm_role_assignment" "sql_access" {
  count                = var.enable_managed_identity ? 1 : 0
  scope                = azurerm_mssql_database.main.id
  role_definition_name = "SQL DB Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
  
  depends_on = [azurerm_linux_function_app.main]
}

# ================================
# Sample Business Data Setup
# ================================

# Create sample tables and insert business data using null_resource
resource "null_resource" "sample_data" {
  # Trigger recreation when database or server changes
  triggers = {
    database_id = azurerm_mssql_database.main.id
    server_id   = azurerm_mssql_server.main.id
  }
  
  # Use local-exec provisioner to create sample data
  provisioner "local-exec" {
    command = <<-EOT
      # Install sqlcmd if not present (Linux/macOS)
      which sqlcmd > /dev/null 2>&1 || {
        echo "sqlcmd not found. Please install SQL Server command line tools."
        echo "Visit: https://docs.microsoft.com/en-us/sql/tools/sqlcmd-utility"
        exit 1
      }
      
      # Create sample business data
      sqlcmd -S "${azurerm_mssql_server.main.fully_qualified_domain_name}" \
             -d "${azurerm_mssql_database.main.name}" \
             -U "${var.sql_admin_username}" \
             -P "${local.sql_password}" \
             -Q "
             -- Create Customers table
             IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='Customers' AND xtype='U')
             CREATE TABLE Customers (
                 CustomerID INT IDENTITY(1,1) PRIMARY KEY,
                 CompanyName NVARCHAR(100) NOT NULL,
                 ContactName NVARCHAR(50),
                 City NVARCHAR(50),
                 Country NVARCHAR(50),
                 Revenue DECIMAL(12,2)
             );
             
             -- Create Orders table
             IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='Orders' AND xtype='U')
             CREATE TABLE Orders (
                 OrderID INT IDENTITY(1,1) PRIMARY KEY,
                 CustomerID INT FOREIGN KEY REFERENCES Customers(CustomerID),
                 OrderDate DATE,
                 TotalAmount DECIMAL(10,2),
                 Status NVARCHAR(20)
             );
             
             -- Insert sample customers (only if table is empty)
             IF NOT EXISTS (SELECT 1 FROM Customers)
             BEGIN
                 INSERT INTO Customers (CompanyName, ContactName, City, Country, Revenue) VALUES 
                 ('Contoso Corp', 'John Smith', 'Seattle', 'USA', 250000.00),
                 ('Fabrikam Inc', 'Jane Doe', 'London', 'UK', 180000.00),
                 ('Adventure Works', 'Bob Johnson', 'Toronto', 'Canada', 320000.00),
                 ('Northwind Traders', 'Alice Brown', 'New York', 'USA', 450000.00),
                 ('Fourth Coffee', 'Charlie Wilson', 'Berlin', 'Germany', 280000.00);
             END
             
             -- Insert sample orders (only if table is empty)
             IF NOT EXISTS (SELECT 1 FROM Orders)
             BEGIN
                 INSERT INTO Orders (CustomerID, OrderDate, TotalAmount, Status) VALUES 
                 (1, '2024-01-15', 15000.00, 'Completed'),
                 (2, '2024-01-20', 8500.00, 'Pending'),
                 (3, '2024-01-25', 22000.00, 'Completed'),
                 (4, '2024-02-01', 35000.00, 'Completed'),
                 (5, '2024-02-05', 18500.00, 'Processing'),
                 (1, '2024-02-10', 12000.00, 'Completed'),
                 (2, '2024-02-15', 9800.00, 'Cancelled'),
                 (3, '2024-02-20', 27500.00, 'Completed');
             END
             
             PRINT 'Sample business data created successfully';
             "
    EOT
  }
  
  depends_on = [
    azurerm_mssql_database.main,
    azurerm_mssql_firewall_rule.allow_azure_services
  ]
}