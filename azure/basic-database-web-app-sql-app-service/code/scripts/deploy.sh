#!/bin/bash

# ==============================================================================
# Azure Basic Database Web App Deployment Script
# This script deploys an Azure SQL Database and App Service web application
# ==============================================================================

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Configuration variables (can be overridden by environment variables)
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-webapp-demo-$(openssl rand -hex 3)}"
LOCATION="${LOCATION:-eastus}"
SQL_SERVER_NAME="${SQL_SERVER_NAME:-sql-server-$(openssl rand -hex 3)}"
SQL_DATABASE_NAME="${SQL_DATABASE_NAME:-TasksDB}"
APP_SERVICE_PLAN="${APP_SERVICE_PLAN:-asp-webapp-$(openssl rand -hex 3)}"
WEB_APP_NAME="${WEB_APP_NAME:-webapp-demo-$(openssl rand -hex 3)}"
SQL_ADMIN_USER="${SQL_ADMIN_USER:-sqladmin}"
SQL_ADMIN_PASSWORD="${SQL_ADMIN_PASSWORD:-SecurePass123!}"

# Cleanup function for script interruption
cleanup_on_exit() {
    log_warning "Script interrupted. Cleaning up temporary files..."
    rm -f index.html deployment.log
}

trap cleanup_on_exit EXIT

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0.0.0")
    log_info "Azure CLI version: $az_version"
    
    # Check if logged into Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login'"
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is required for generating random strings"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to validate resource names
validate_resource_names() {
    log_info "Validating resource names..."
    
    # Validate SQL Server name (3-63 chars, lowercase letters, numbers, hyphens)
    if [[ ! $SQL_SERVER_NAME =~ ^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$ ]]; then
        log_error "SQL Server name '$SQL_SERVER_NAME' is invalid. Must be 3-63 characters, lowercase letters, numbers, and hyphens only."
        exit 1
    fi
    
    # Validate Web App name (2-60 chars, alphanumeric and hyphens)
    if [[ ! $WEB_APP_NAME =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,58}[a-zA-Z0-9]$ ]]; then
        log_error "Web App name '$WEB_APP_NAME' is invalid. Must be 2-60 characters, alphanumeric and hyphens only."
        exit 1
    fi
    
    log_success "Resource names validated"
}

# Function to check if resource group exists
resource_group_exists() {
    az group show --name "$RESOURCE_GROUP" &> /dev/null
}

# Function to check if SQL server exists
sql_server_exists() {
    az sql server show --name "$SQL_SERVER_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null
}

# Function to check if database exists
database_exists() {
    az sql db show --name "$SQL_DATABASE_NAME" --server "$SQL_SERVER_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null
}

# Function to check if App Service plan exists
app_service_plan_exists() {
    az appservice plan show --name "$APP_SERVICE_PLAN" --resource-group "$RESOURCE_GROUP" &> /dev/null
}

# Function to check if web app exists
web_app_exists() {
    az webapp show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if resource_group_exists; then
        log_warning "Resource group '$RESOURCE_GROUP' already exists. Skipping creation."
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=recipe environment=demo created-by=deploy-script
    
    log_success "Resource group created: $RESOURCE_GROUP"
}

# Function to create SQL Server and Database
create_sql_resources() {
    log_info "Creating SQL Server and Database..."
    
    # Create SQL Server if it doesn't exist
    if ! sql_server_exists; then
        log_info "Creating SQL Server: $SQL_SERVER_NAME"
        az sql server create \
            --name "$SQL_SERVER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --admin-user "$SQL_ADMIN_USER" \
            --admin-password "$SQL_ADMIN_PASSWORD" \
            --enable-ad-only-auth false
        
        log_success "SQL Server created: $SQL_SERVER_NAME"
    else
        log_warning "SQL Server '$SQL_SERVER_NAME' already exists. Skipping creation."
    fi
    
    # Create database if it doesn't exist
    if ! database_exists; then
        log_info "Creating SQL Database: $SQL_DATABASE_NAME"
        az sql db create \
            --resource-group "$RESOURCE_GROUP" \
            --server "$SQL_SERVER_NAME" \
            --name "$SQL_DATABASE_NAME" \
            --service-objective Basic \
            --backup-storage-redundancy Local
        
        log_success "SQL Database created: $SQL_DATABASE_NAME"
    else
        log_warning "SQL Database '$SQL_DATABASE_NAME' already exists. Skipping creation."
    fi
}

# Function to configure database firewall
configure_database_firewall() {
    log_info "Configuring database firewall..."
    
    # Check if firewall rule already exists
    if az sql server firewall-rule show \
        --resource-group "$RESOURCE_GROUP" \
        --server "$SQL_SERVER_NAME" \
        --name "AllowAzureServices" &> /dev/null; then
        log_warning "Firewall rule 'AllowAzureServices' already exists. Skipping creation."
        return 0
    fi
    
    az sql server firewall-rule create \
        --resource-group "$RESOURCE_GROUP" \
        --server "$SQL_SERVER_NAME" \
        --name "AllowAzureServices" \
        --start-ip-address 0.0.0.0 \
        --end-ip-address 0.0.0.0
    
    log_success "Database firewall configured for Azure services"
}

# Function to create database schema and sample data
create_database_schema() {
    log_info "Creating database schema and sample data..."
    
    # Check if Tasks table already exists
    local table_exists=$(az sql query \
        --server "$SQL_SERVER_NAME" \
        --database "$SQL_DATABASE_NAME" \
        --auth-type SqlPassword \
        --username "$SQL_ADMIN_USER" \
        --password "$SQL_ADMIN_PASSWORD" \
        --query "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'Tasks'" \
        --output tsv 2>/dev/null || echo "0")
    
    if [[ "$table_exists" -gt 0 ]]; then
        log_warning "Tasks table already exists. Skipping schema creation."
        return 0
    fi
    
    az sql query \
        --server "$SQL_SERVER_NAME" \
        --database "$SQL_DATABASE_NAME" \
        --auth-type SqlPassword \
        --username "$SQL_ADMIN_USER" \
        --password "$SQL_ADMIN_PASSWORD" \
        --query "
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
        ('Test Application', 'Verify database connectivity and functionality');"
    
    log_success "Database schema created with sample data"
}

# Function to create App Service Plan
create_app_service_plan() {
    log_info "Creating App Service Plan: $APP_SERVICE_PLAN"
    
    if app_service_plan_exists; then
        log_warning "App Service Plan '$APP_SERVICE_PLAN' already exists. Skipping creation."
        return 0
    fi
    
    az appservice plan create \
        --name "$APP_SERVICE_PLAN" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku B1 \
        --is-linux false
    
    log_success "App Service Plan created: $APP_SERVICE_PLAN"
}

# Function to create web app
create_web_app() {
    log_info "Creating Web App: $WEB_APP_NAME"
    
    if web_app_exists; then
        log_warning "Web App '$WEB_APP_NAME' already exists. Skipping creation."
    else
        az webapp create \
            --name "$WEB_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --plan "$APP_SERVICE_PLAN" \
            --runtime "DOTNETCORE:8.0" \
            --assign-identity
        
        log_success "Web App created: $WEB_APP_NAME"
    fi
    
    # Get managed identity ID
    local managed_identity_id=$(az webapp identity show \
        --name "$WEB_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query principalId \
        --output tsv)
    
    log_info "Managed Identity ID: $managed_identity_id"
}

# Function to configure database connection
configure_database_connection() {
    log_info "Configuring database connection string..."
    
    local connection_string="Server=tcp:${SQL_SERVER_NAME}.database.windows.net,1433;Initial Catalog=${SQL_DATABASE_NAME};Persist Security Info=False;User ID=${SQL_ADMIN_USER};Password=${SQL_ADMIN_PASSWORD};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    
    az webapp config connection-string set \
        --name "$WEB_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --connection-string-type SQLAzure \
        --settings DefaultConnection="$connection_string"
    
    log_success "Database connection string configured"
}

# Function to create and deploy sample application
deploy_sample_application() {
    log_info "Creating and deploying sample application..."
    
    # Create sample HTML file
    cat > index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Task Manager - Azure Demo</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 40px; background-color: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #0078d4; text-align: center; margin-bottom: 30px; }
        .status { padding: 15px; margin: 15px 0; border-radius: 6px; text-align: center; }
        .success { background-color: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .info { background-color: #d1ecf1; color: #0c5460; border: 1px solid #bee5eb; }
        ul { line-height: 1.6; }
        .footer { margin-top: 30px; text-align: center; color: #666; font-size: 0.9em; }
        .resource-info { background-color: #f8f9fa; padding: 20px; border-radius: 6px; margin: 20px 0; }
        .resource-info h3 { margin-top: 0; color: #0078d4; }
        .resource-info p { margin: 5px 0; font-family: monospace; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Azure Web App Successfully Deployed!</h1>
        <div class="status success">
            <strong>✅ Deployment Status:</strong> Your web application is running on Azure App Service
        </div>
        <div class="status info">
            <strong>🔗 Database Connection:</strong> Ready to connect to Azure SQL Database
        </div>
        <div class="status info">
            <strong>🏗️ Architecture:</strong> This app demonstrates basic Azure App Service + SQL Database integration
        </div>
        
        <div class="resource-info">
            <h3>📋 Deployed Resources</h3>
            <p><strong>Resource Group:</strong> RESOURCE_GROUP_PLACEHOLDER</p>
            <p><strong>SQL Server:</strong> SQL_SERVER_PLACEHOLDER.database.windows.net</p>
            <p><strong>Database:</strong> SQL_DATABASE_PLACEHOLDER</p>
            <p><strong>Web App:</strong> WEB_APP_PLACEHOLDER.azurewebsites.net</p>
            <p><strong>App Service Plan:</strong> APP_SERVICE_PLAN_PLACEHOLDER</p>
        </div>
        
        <h2>Next Steps:</h2>
        <ul>
            <li>Add your application code to connect to the database using the configured connection string</li>
            <li>Configure managed identity for passwordless authentication to eliminate hardcoded credentials</li>
            <li>Enable Application Insights for monitoring and logging in Azure Monitor</li>
            <li>Set up CI/CD pipelines for automated deployments using Azure DevOps or GitHub Actions</li>
            <li>Configure custom domains and SSL certificates for production readiness</li>
            <li>Implement proper error handling and logging in your application</li>
        </ul>
        <div class="footer">
            <p>Built with Azure App Service and Azure SQL Database</p>
            <p>Deployed on: <script>document.write(new Date().toLocaleString());</script></p>
        </div>
    </div>
</body>
</html>
EOF
    
    # Replace placeholders with actual values
    sed -i.bak "s/RESOURCE_GROUP_PLACEHOLDER/$RESOURCE_GROUP/g" index.html
    sed -i.bak "s/SQL_SERVER_PLACEHOLDER/$SQL_SERVER_NAME/g" index.html
    sed -i.bak "s/SQL_DATABASE_PLACEHOLDER/$SQL_DATABASE_NAME/g" index.html
    sed -i.bak "s/WEB_APP_PLACEHOLDER/$WEB_APP_NAME/g" index.html
    sed -i.bak "s/APP_SERVICE_PLAN_PLACEHOLDER/$APP_SERVICE_PLAN/g" index.html
    rm -f index.html.bak
    
    # Deploy the HTML file
    az webapp deploy \
        --name "$WEB_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --src-path index.html \
        --type static
    
    log_success "Sample application deployed successfully"
}

# Function to display deployment summary
display_deployment_summary() {
    log_info "Deployment Summary"
    echo "=================================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "SQL Server: $SQL_SERVER_NAME.database.windows.net"
    echo "Database: $SQL_DATABASE_NAME"
    echo "App Service Plan: $APP_SERVICE_PLAN"
    echo "Web App: $WEB_APP_NAME"
    echo "=================================="
    
    local web_app_url=$(az webapp show \
        --name "$WEB_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query defaultHostName \
        --output tsv)
    
    local subscription_id=$(az account show --query id --output tsv)
    
    log_success "🌐 Web Application URL: https://$web_app_url"
    log_success "📊 Azure Portal: https://portal.azure.com/#@/resource/subscriptions/$subscription_id/resourceGroups/$RESOURCE_GROUP/overview"
    
    echo ""
    echo "Next steps:"
    echo "1. Visit your web application at: https://$web_app_url"
    echo "2. Review resources in the Azure Portal"
    echo "3. Test database connectivity using the Azure Portal Query Editor"
    echo "4. When finished testing, run './destroy.sh' to clean up resources"
}

# Function to run deployment validation
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check if all resources are accessible
    local validation_failed=false
    
    if ! resource_group_exists; then
        log_error "Resource group validation failed"
        validation_failed=true
    fi
    
    if ! sql_server_exists; then
        log_error "SQL Server validation failed"
        validation_failed=true
    fi
    
    if ! database_exists; then
        log_error "Database validation failed"
        validation_failed=true
    fi
    
    if ! app_service_plan_exists; then
        log_error "App Service Plan validation failed"
        validation_failed=true
    fi
    
    if ! web_app_exists; then
        log_error "Web App validation failed"
        validation_failed=true
    fi
    
    # Test database connectivity
    local task_count=$(az sql query \
        --server "$SQL_SERVER_NAME" \
        --database "$SQL_DATABASE_NAME" \
        --auth-type SqlPassword \
        --username "$SQL_ADMIN_USER" \
        --password "$SQL_ADMIN_PASSWORD" \
        --query "SELECT COUNT(*) as TaskCount FROM Tasks;" \
        --output tsv 2>/dev/null || echo "0")
    
    if [[ "$task_count" -ne 3 ]]; then
        log_error "Database connectivity validation failed. Expected 3 tasks, found $task_count"
        validation_failed=true
    fi
    
    if [[ "$validation_failed" == "true" ]]; then
        log_error "Validation failed. Please check the deployment and try again."
        exit 1
    fi
    
    log_success "Deployment validation completed successfully"
}

# Main deployment function
main() {
    log_info "Starting Azure Basic Database Web App deployment..."
    log_info "Timestamp: $(date)"
    
    # Store current directory and create log file
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local log_file="$script_dir/deployment.log"
    
    echo "Deployment started at $(date)" > "$log_file"
    
    # Display configuration
    log_info "Deployment Configuration:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  SQL Server: $SQL_SERVER_NAME"
    echo "  Database: $SQL_DATABASE_NAME"
    echo "  App Service Plan: $APP_SERVICE_PLAN"
    echo "  Web App: $WEB_APP_NAME"
    echo ""
    
    # Execute deployment steps
    check_prerequisites
    validate_resource_names
    create_resource_group
    create_sql_resources
    configure_database_firewall
    create_database_schema
    create_app_service_plan
    create_web_app
    configure_database_connection
    deploy_sample_application
    validate_deployment
    display_deployment_summary
    
    # Clean up temporary files
    rm -f index.html
    
    echo "Deployment completed at $(date)" >> "$log_file"
    log_success "Deployment completed successfully!"
    log_info "Deployment log saved to: $log_file"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi