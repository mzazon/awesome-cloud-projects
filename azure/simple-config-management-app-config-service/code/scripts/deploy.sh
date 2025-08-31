#!/bin/bash

# Azure Simple Configuration Management Deployment Script
# This script deploys Azure App Configuration and App Service with ASP.NET Core web application
# Recipe: Simple Configuration Management with App Configuration and App Service

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
Azure Simple Configuration Management Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -r, --resource-group    Resource group name (optional, will be generated if not provided)
    -l, --location          Azure region (default: eastus)
    -s, --suffix            Custom suffix for resource names (optional, will be generated if not provided)
    --dry-run               Show what would be deployed without actually deploying
    --skip-app              Skip application creation and deployment (deploy infrastructure only)

EXAMPLES:
    $0                                          # Deploy with default settings
    $0 -l "westus2"                            # Deploy to West US 2 region
    $0 -r "my-rg" -s "demo123"                # Deploy with custom resource group and suffix
    $0 --dry-run                               # Preview deployment without executing

DESCRIPTION:
    This script deploys a complete Azure configuration management solution including:
    - Azure Resource Group
    - Azure App Configuration store (Free tier)
    - ASP.NET Core web application with configuration integration
    - Azure App Service plan and web app (Free tier)
    - Managed identity and RBAC permissions
    - Sample configuration key-value pairs

    The deployment is idempotent and can be run multiple times safely.
EOF
}

# Default values
LOCATION="eastus"
RESOURCE_GROUP=""
CUSTOM_SUFFIX=""
DRY_RUN=false
SKIP_APP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -s|--suffix)
            CUSTOM_SUFFIX="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-app)
            SKIP_APP=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if .NET SDK is installed (only if not skipping app creation)
    if [[ "$SKIP_APP" == false ]]; then
        if ! command -v dotnet &> /dev/null; then
            log_error ".NET SDK is not installed. Please install .NET 8.0 SDK from: https://dotnet.microsoft.com/download"
            exit 1
        fi
        
        # Check .NET version
        local dotnet_version
        dotnet_version=$(dotnet --version | cut -d. -f1)
        if [[ "$dotnet_version" -lt 8 ]]; then
            log_warning ".NET version is $dotnet_version. This recipe requires .NET 8.0 or later."
        fi
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        log_error "zip command is not available. Please install zip utility."
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix if not provided
    if [[ -z "$CUSTOM_SUFFIX" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    else
        RANDOM_SUFFIX="$CUSTOM_SUFFIX"
    fi
    
    # Set resource group name if not provided
    if [[ -z "$RESOURCE_GROUP" ]]; then
        RESOURCE_GROUP="rg-config-demo-${RANDOM_SUFFIX}"
    fi
    
    # Set other environment variables
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export APP_CONFIG_NAME="appconfig-demo-${RANDOM_SUFFIX}"
    export APP_SERVICE_NAME="webapp-config-demo-${RANDOM_SUFFIX}"
    export APP_SERVICE_PLAN="plan-${APP_SERVICE_NAME}"
    
    log_info "Environment variables configured:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Location: $LOCATION"
    log_info "  App Config Name: $APP_CONFIG_NAME"
    log_info "  App Service Name: $APP_SERVICE_NAME"
    log_info "  Random Suffix: $RANDOM_SUFFIX"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create resource group: $RESOURCE_GROUP in $LOCATION"
        return
    fi
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=recipe environment=demo \
            --output none
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create App Configuration store
create_app_configuration() {
    log_info "Creating Azure App Configuration store: $APP_CONFIG_NAME"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create App Configuration store: $APP_CONFIG_NAME"
        return
    fi
    
    # Check if App Configuration already exists
    if az appconfig show --name "$APP_CONFIG_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "App Configuration $APP_CONFIG_NAME already exists"
    else
        az appconfig create \
            --name "$APP_CONFIG_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Free \
            --tags environment=demo purpose=recipe \
            --output none
        
        log_success "App Configuration created: $APP_CONFIG_NAME"
    fi
    
    # Get the App Configuration endpoint
    export APP_CONFIG_ENDPOINT=$(az appconfig show \
        --name "$APP_CONFIG_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query endpoint --output tsv)
    
    log_info "App Configuration endpoint: $APP_CONFIG_ENDPOINT"
}

# Function to add configuration key-values
add_configuration_values() {
    log_info "Adding configuration key-values to App Configuration"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would add configuration values to App Configuration"
        return
    fi
    
    # Configuration keys and values
    declare -A config_values=(
        ["DemoApp:Settings:Title"]="Configuration Management Demo"
        ["DemoApp:Settings:BackgroundColor"]="#2563eb"
        ["DemoApp:Settings:Message"]="Hello from Azure App Configuration!"
        ["DemoApp:Settings:RefreshInterval"]="30"
    )
    
    for key in "${!config_values[@]}"; do
        az appconfig kv set \
            --name "$APP_CONFIG_NAME" \
            --key "$key" \
            --value "${config_values[$key]}" \
            --content-type "text/plain" \
            --output none
        
        log_success "Added configuration: $key"
    done
}

# Function to create ASP.NET Core application
create_application() {
    if [[ "$SKIP_APP" == true ]]; then
        log_info "Skipping application creation (--skip-app flag provided)"
        return
    fi
    
    log_info "Creating ASP.NET Core web application"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create ASP.NET Core application"
        return
    fi
    
    # Create application directory and navigate to it
    local app_dir="config-demo-app-${RANDOM_SUFFIX}"
    
    if [[ -d "$app_dir" ]]; then
        log_warning "Application directory $app_dir already exists, removing it"
        rm -rf "$app_dir"
    fi
    
    mkdir "$app_dir" && cd "$app_dir"
    
    # Initialize the web application
    dotnet new webapp --framework net8.0 --name ConfigDemoApp --output ConfigDemoApp --force
    cd ConfigDemoApp
    
    # Add required NuGet packages
    dotnet add package Microsoft.Extensions.Configuration.AzureAppConfiguration --output table
    dotnet add package Azure.Identity --output table
    
    # Create Program.cs with App Configuration integration
    cat > Program.cs << 'EOF'
using Azure.Identity;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container
builder.Services.AddRazorPages();

// Configure Azure App Configuration with managed identity
builder.Configuration.AddAzureAppConfiguration(options =>
{
    var endpoint = Environment.GetEnvironmentVariable("APP_CONFIG_ENDPOINT");
    if (!string.IsNullOrEmpty(endpoint))
    {
        options.Connect(new Uri(endpoint), new DefaultAzureCredential())
               .Select("DemoApp:*", LabelFilter.Null)
               .ConfigureRefresh(refreshOptions =>
               {
                   refreshOptions.RegisterAll()
                               .SetRefreshInterval(TimeSpan.FromSeconds(30));
               });
    }
});

// Add Azure App Configuration middleware
builder.Services.AddAzureAppConfiguration();

var app = builder.Build();

// Configure the HTTP request pipeline
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();

// Use Azure App Configuration middleware for dynamic refresh
app.UseAzureAppConfiguration();

app.UseAuthorization();
app.MapRazorPages();

app.Run();
EOF
    
    # Create updated Index page
    cat > Pages/Index.cshtml << 'EOF'
@page
@model IndexModel
@{
    ViewData["Title"] = "Configuration Demo";
}

<div style="background-color: @Configuration["DemoApp:Settings:BackgroundColor"]; 
            color: white; padding: 40px; border-radius: 10px; text-align: center;">
    <h1>@Configuration["DemoApp:Settings:Title"]</h1>
    <p class="lead">@Configuration["DemoApp:Settings:Message"]</p>
    <hr style="border-color: white;">
    <p>Configuration loaded from Azure App Configuration</p>
    <p>Refresh Interval: @Configuration["DemoApp:Settings:RefreshInterval"] seconds</p>
    <p>Last Updated: @DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss UTC")</p>
</div>

<div style="margin-top: 20px; padding: 20px;">
    <h3>Dynamic Configuration Management</h3>
    <p>This application demonstrates how Azure App Configuration enables:</p>
    <ul>
        <li>Centralized configuration management across environments</li>
        <li>Dynamic updates without application restarts</li>
        <li>Secure access using managed identity</li>
        <li>Real-time configuration refresh capabilities</li>
    </ul>
</div>
EOF
    
    log_success "ASP.NET Core application created with App Configuration support"
}

# Function to create App Service and deploy application
create_app_service() {
    log_info "Creating Azure App Service and deploying application"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create App Service and deploy application"
        return
    fi
    
    # Create App Service plan
    if az appservice plan show --name "$APP_SERVICE_PLAN" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "App Service plan $APP_SERVICE_PLAN already exists"
    else
        az appservice plan create \
            --name "$APP_SERVICE_PLAN" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku FREE \
            --is-linux \
            --output none
        
        log_success "App Service plan created: $APP_SERVICE_PLAN"
    fi
    
    # Create Web App
    if az webapp show --name "$APP_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Web App $APP_SERVICE_NAME already exists"
    else
        az webapp create \
            --name "$APP_SERVICE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --plan "$APP_SERVICE_PLAN" \
            --runtime "DOTNET:8.0" \
            --tags environment=demo purpose=recipe \
            --output none
        
        log_success "Web App created: $APP_SERVICE_NAME"
    fi
    
    # Configure application settings
    az webapp config appsettings set \
        --name "$APP_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --settings APP_CONFIG_ENDPOINT="$APP_CONFIG_ENDPOINT" \
        --output none
    
    log_success "Application settings configured"
}

# Function to enable managed identity and grant permissions
setup_managed_identity() {
    log_info "Setting up managed identity and permissions"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would setup managed identity and grant permissions"
        return
    fi
    
    # Enable system-assigned managed identity
    az webapp identity assign \
        --name "$APP_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --output none
    
    # Get the managed identity principal ID
    local principal_id
    principal_id=$(az webapp identity show \
        --name "$APP_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query principalId --output tsv)
    
    # Wait a moment for the identity to propagate
    sleep 10
    
    # Grant App Configuration Data Reader role to the managed identity
    az role assignment create \
        --assignee "$principal_id" \
        --role "App Configuration Data Reader" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.AppConfiguration/configurationStores/${APP_CONFIG_NAME}" \
        --output none
    
    log_success "Managed identity enabled and permissions granted"
    log_info "Principal ID: $principal_id"
}

# Function to deploy application
deploy_application() {
    if [[ "$SKIP_APP" == true ]]; then
        log_info "Skipping application deployment (--skip-app flag provided)"
        return
    fi
    
    log_info "Building and deploying application to App Service"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would build and deploy application"
        return
    fi
    
    # Build and publish the application
    dotnet publish --configuration Release --output ./publish --verbosity quiet
    
    # Create deployment ZIP file
    cd publish
    zip -r ../deploy.zip . > /dev/null
    cd ..
    
    # Deploy to App Service using ZIP deployment
    az webapp deployment source config-zip \
        --name "$APP_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --src deploy.zip \
        --output none
    
    # Get the application URL
    export APP_URL="https://${APP_SERVICE_NAME}.azurewebsites.net"
    
    log_success "Application deployed successfully"
    log_success "Application URL: $APP_URL"
    
    # Clean up build artifacts
    rm -rf publish deploy.zip
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would validate deployment"
        return
    fi
    
    # Check App Service state
    local app_state
    app_state=$(az webapp show \
        --name "$APP_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "state" --output tsv)
    
    if [[ "$app_state" == "Running" ]]; then
        log_success "App Service is running"
    else
        log_warning "App Service state: $app_state"
    fi
    
    # Test HTTP connectivity (only if app was deployed)
    if [[ "$SKIP_APP" == false ]]; then
        local app_url="https://${APP_SERVICE_NAME}.azurewebsites.net"
        log_info "Testing HTTP connectivity to: $app_url"
        
        if curl -s -I "$app_url" | grep -q "200 OK"; then
            log_success "Application is accessible"
        else
            log_warning "Application may not be fully ready yet. Please check manually: $app_url"
        fi
    fi
    
    # List configuration values
    log_info "Listing configuration values:"
    az appconfig kv list \
        --name "$APP_CONFIG_NAME" \
        --query "[].{Key:key,Value:value}" \
        --output table
}

# Function to display deployment summary
show_summary() {
    log_info "Deployment Summary"
    echo "======================================"
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "App Configuration: $APP_CONFIG_NAME"
    echo "App Service: $APP_SERVICE_NAME"
    if [[ "$SKIP_APP" == false ]]; then
        echo "Application URL: https://${APP_SERVICE_NAME}.azurewebsites.net"
    fi
    echo "======================================"
    
    if [[ "$DRY_RUN" == false ]]; then
        log_success "Deployment completed successfully!"
        
        if [[ "$SKIP_APP" == false ]]; then
            echo ""
            log_info "Next steps:"
            echo "1. Visit the application URL to see the configuration management demo"
            echo "2. Try updating configuration values in the Azure portal"
            echo "3. Refresh the web page after 30 seconds to see changes"
            echo ""
            log_info "To update configuration values via CLI:"
            echo "az appconfig kv set --name $APP_CONFIG_NAME --key 'DemoApp:Settings:Message' --value 'Updated message'"
        fi
    else
        log_info "Dry run completed. No resources were created."
    fi
}

# Function to handle cleanup on script interruption
cleanup_on_interrupt() {
    log_warning "Script interrupted. Cleaning up temporary files..."
    if [[ -d "config-demo-app-${RANDOM_SUFFIX}" ]]; then
        cd .. 2>/dev/null || true
        rm -rf "config-demo-app-${RANDOM_SUFFIX}"
    fi
    exit 130
}

# Main execution function
main() {
    # Set up interrupt handler
    trap cleanup_on_interrupt INT TERM
    
    log_info "Starting Azure Simple Configuration Management deployment"
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_resource_group
    create_app_configuration
    add_configuration_values
    create_application
    create_app_service
    setup_managed_identity
    deploy_application
    validate_deployment
    show_summary
    
    # Return to original directory if we changed it
    if [[ "$SKIP_APP" == false && "$DRY_RUN" == false ]]; then
        cd ../..
    fi
}

# Execute main function
main "$@"