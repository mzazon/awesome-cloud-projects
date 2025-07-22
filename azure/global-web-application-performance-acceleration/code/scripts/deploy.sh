#!/bin/bash

# Deployment script for Azure Web Application Performance Optimization
# Recipe: optimizing-web-application-performance-with-azure-cache-for-redis-and-azure-cdn
# This script deploys Azure resources for web application performance optimization
# using Azure Cache for Redis and Azure CDN

set -e  # Exit on any error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECIPE_NAME="optimizing-web-application-performance-with-azure-cache-for-redis-and-azure-cdn"
DEPLOYMENT_LOG_FILE="${SCRIPT_DIR}/deployment-$(date +%Y%m%d-%H%M%S).log"

# Default values
DEFAULT_RESOURCE_GROUP="rg-webapp-perf"
DEFAULT_LOCATION="eastus"
DEFAULT_ENVIRONMENT="dev"

# Configuration variables
RESOURCE_GROUP=${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}
LOCATION=${LOCATION:-$DEFAULT_LOCATION}
ENVIRONMENT=${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}
SUBSCRIPTION_ID=""
RANDOM_SUFFIX=""
DRY_RUN=${DRY_RUN:-false}
SKIP_PREREQS=${SKIP_PREREQS:-false}

# Resource names (will be set with random suffix)
APP_SERVICE_PLAN=""
WEB_APP=""
REDIS_CACHE=""
CDN_PROFILE=""
CDN_ENDPOINT=""
DB_SERVER=""
DB_NAME="ecommerce_db"
INSIGHTS_COMPONENT=""

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Web Application Performance Optimization infrastructure.

OPTIONS:
    -g, --resource-group <name>    Resource group name (default: $DEFAULT_RESOURCE_GROUP)
    -l, --location <location>      Azure location (default: $DEFAULT_LOCATION)
    -e, --environment <env>        Environment (dev/staging/prod) (default: $DEFAULT_ENVIRONMENT)
    -s, --subscription <id>        Azure subscription ID
    -r, --random-suffix <suffix>   Custom random suffix for resources
    -d, --dry-run                  Show what would be deployed without actually deploying
    --skip-prereqs                 Skip prerequisites check
    -h, --help                     Show this help message

EXAMPLES:
    $0                                    # Deploy with default settings
    $0 -g my-rg -l westus2               # Deploy to custom resource group and location
    $0 -e prod -s 12345678-1234-1234-1234-123456789012  # Deploy to production
    $0 --dry-run                          # Show deployment plan without executing
    
ENVIRONMENT VARIABLES:
    RESOURCE_GROUP          Resource group name
    LOCATION                Azure location
    ENVIRONMENT             Environment (dev/staging/prod)
    DRY_RUN                 Set to 'true' for dry run mode
    SKIP_PREREQS            Set to 'true' to skip prerequisites check

EOF
}

# Function to check prerequisites
check_prerequisites() {
    if [ "$SKIP_PREREQS" = "true" ]; then
        warn "Skipping prerequisites check"
        return 0
    fi
    
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI first."
        error "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random suffix generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is not installed. Please install openssl for random suffix generation."
        exit 1
    fi
    
    # Get subscription ID if not provided
    if [ -z "$SUBSCRIPTION_ID" ]; then
        SUBSCRIPTION_ID=$(az account show --query id --output tsv)
        if [ -z "$SUBSCRIPTION_ID" ]; then
            error "Could not determine subscription ID. Please specify with -s option."
            exit 1
        fi
    fi
    
    # Validate location
    if ! az account list-locations --query "[?name=='$LOCATION']" --output tsv | grep -q "$LOCATION"; then
        error "Invalid location: $LOCATION"
        info "Available locations: $(az account list-locations --query '[].name' --output tsv | tr '\n' ' ')"
        exit 1
    fi
    
    # Check resource providers
    local providers=("Microsoft.Web" "Microsoft.Cache" "Microsoft.Cdn" "Microsoft.DBforPostgreSQL" "Microsoft.Insights")
    for provider in "${providers[@]}"; do
        local state=$(az provider show --namespace "$provider" --query "registrationState" --output tsv)
        if [ "$state" != "Registered" ]; then
            warn "Provider $provider is not registered. Registering..."
            az provider register --namespace "$provider"
        fi
    done
    
    log "Prerequisites check completed successfully"
}

# Function to initialize configuration
initialize_config() {
    log "Initializing configuration..."
    
    # Generate random suffix if not provided
    if [ -z "$RANDOM_SUFFIX" ]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi
    
    # Set resource names with suffix
    APP_SERVICE_PLAN="asp-webapp-${RANDOM_SUFFIX}"
    WEB_APP="webapp-${RANDOM_SUFFIX}"
    REDIS_CACHE="cache-${RANDOM_SUFFIX}"
    CDN_PROFILE="cdn-profile-${RANDOM_SUFFIX}"
    CDN_ENDPOINT="cdn-${RANDOM_SUFFIX}"
    DB_SERVER="db-server-${RANDOM_SUFFIX}"
    INSIGHTS_COMPONENT="${WEB_APP}-insights"
    
    # Add environment suffix to resource group if not default
    if [ "$ENVIRONMENT" != "dev" ]; then
        RESOURCE_GROUP="${RESOURCE_GROUP}-${ENVIRONMENT}"
    fi
    
    # Add random suffix to resource group
    RESOURCE_GROUP="${RESOURCE_GROUP}-${RANDOM_SUFFIX}"
    
    info "Configuration initialized:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Location: $LOCATION"
    info "  Environment: $ENVIRONMENT"
    info "  Subscription: $SUBSCRIPTION_ID"
    info "  Random Suffix: $RANDOM_SUFFIX"
    info "  App Service Plan: $APP_SERVICE_PLAN"
    info "  Web App: $WEB_APP"
    info "  Redis Cache: $REDIS_CACHE"
    info "  CDN Profile: $CDN_PROFILE"
    info "  CDN Endpoint: $CDN_ENDPOINT"
    info "  DB Server: $DB_SERVER"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group: $RESOURCE_GROUP"
    
    if [ "$DRY_RUN" = "true" ]; then
        info "[DRY RUN] Would create resource group: $RESOURCE_GROUP in $LOCATION"
        return 0
    fi
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Resource group $RESOURCE_GROUP already exists"
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=performance-demo environment="$ENVIRONMENT" recipe="$RECIPE_NAME" \
        --output table
    
    if [ $? -eq 0 ]; then
        log "✅ Resource group created successfully: $RESOURCE_GROUP"
    else
        error "Failed to create resource group: $RESOURCE_GROUP"
        exit 1
    fi
}

# Function to create PostgreSQL database
create_postgresql_database() {
    log "Creating PostgreSQL database server: $DB_SERVER"
    
    if [ "$DRY_RUN" = "true" ]; then
        info "[DRY RUN] Would create PostgreSQL server: $DB_SERVER"
        return 0
    fi
    
    # Check if database server already exists
    if az postgres flexible-server show --resource-group "$RESOURCE_GROUP" --name "$DB_SERVER" &> /dev/null; then
        warn "PostgreSQL server $DB_SERVER already exists"
        return 0
    fi
    
    # Generate database password
    local db_password="P@ssw0rd123!$(openssl rand -hex 4)"
    
    az postgres flexible-server create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DB_SERVER" \
        --location "$LOCATION" \
        --admin-user dbadmin \
        --admin-password "$db_password" \
        --sku-name Standard_B1ms \
        --version 13 \
        --storage-size 32 \
        --public-access 0.0.0.0 \
        --tags purpose=performance-demo environment="$ENVIRONMENT" \
        --output table
    
    if [ $? -eq 0 ]; then
        log "✅ PostgreSQL server created successfully: $DB_SERVER"
        info "Database password: $db_password"
        info "⚠️  Please save this password securely!"
    else
        error "Failed to create PostgreSQL server: $DB_SERVER"
        exit 1
    fi
}

# Function to create Redis cache
create_redis_cache() {
    log "Creating Redis cache: $REDIS_CACHE"
    
    if [ "$DRY_RUN" = "true" ]; then
        info "[DRY RUN] Would create Redis cache: $REDIS_CACHE"
        return 0
    fi
    
    # Check if Redis cache already exists
    if az redis show --resource-group "$RESOURCE_GROUP" --name "$REDIS_CACHE" &> /dev/null; then
        warn "Redis cache $REDIS_CACHE already exists"
        return 0
    fi
    
    # Set Redis SKU based on environment
    local redis_sku="Standard"
    local redis_size="C1"
    
    if [ "$ENVIRONMENT" = "prod" ]; then
        redis_sku="Premium"
        redis_size="P1"
    fi
    
    az redis create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$REDIS_CACHE" \
        --location "$LOCATION" \
        --sku "$redis_sku" \
        --vm-size "$redis_size" \
        --enable-non-ssl-port false \
        --redis-configuration maxmemory-policy=allkeys-lru \
        --tags purpose=performance-demo environment="$ENVIRONMENT" \
        --output table
    
    if [ $? -eq 0 ]; then
        log "✅ Redis cache created successfully: $REDIS_CACHE"
        
        # Get Redis connection details
        local redis_hostname=$(az redis show \
            --resource-group "$RESOURCE_GROUP" \
            --name "$REDIS_CACHE" \
            --query hostName --output tsv)
        
        local redis_key=$(az redis list-keys \
            --resource-group "$RESOURCE_GROUP" \
            --name "$REDIS_CACHE" \
            --query primaryKey --output tsv)
        
        info "Redis hostname: $redis_hostname"
        info "Redis key: $redis_key"
        info "⚠️  Please save these credentials securely!"
    else
        error "Failed to create Redis cache: $REDIS_CACHE"
        exit 1
    fi
}

# Function to create App Service
create_app_service() {
    log "Creating App Service: $WEB_APP"
    
    if [ "$DRY_RUN" = "true" ]; then
        info "[DRY RUN] Would create App Service: $WEB_APP"
        return 0
    fi
    
    # Check if App Service Plan already exists
    if ! az appservice plan show --resource-group "$RESOURCE_GROUP" --name "$APP_SERVICE_PLAN" &> /dev/null; then
        log "Creating App Service Plan: $APP_SERVICE_PLAN"
        
        # Set App Service Plan SKU based on environment
        local app_plan_sku="S1"
        if [ "$ENVIRONMENT" = "prod" ]; then
            app_plan_sku="P1V2"
        fi
        
        az appservice plan create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$APP_SERVICE_PLAN" \
            --location "$LOCATION" \
            --sku "$app_plan_sku" \
            --is-linux \
            --tags purpose=performance-demo environment="$ENVIRONMENT" \
            --output table
        
        if [ $? -eq 0 ]; then
            log "✅ App Service Plan created successfully: $APP_SERVICE_PLAN"
        else
            error "Failed to create App Service Plan: $APP_SERVICE_PLAN"
            exit 1
        fi
    else
        warn "App Service Plan $APP_SERVICE_PLAN already exists"
    fi
    
    # Check if Web App already exists
    if az webapp show --resource-group "$RESOURCE_GROUP" --name "$WEB_APP" &> /dev/null; then
        warn "Web App $WEB_APP already exists"
        return 0
    fi
    
    # Create Web App
    az webapp create \
        --resource-group "$RESOURCE_GROUP" \
        --plan "$APP_SERVICE_PLAN" \
        --name "$WEB_APP" \
        --runtime "NODE|18-lts" \
        --tags purpose=performance-demo environment="$ENVIRONMENT" \
        --output table
    
    if [ $? -eq 0 ]; then
        log "✅ Web App created successfully: $WEB_APP"
        
        # Get Redis connection details for app settings
        local redis_hostname=$(az redis show \
            --resource-group "$RESOURCE_GROUP" \
            --name "$REDIS_CACHE" \
            --query hostName --output tsv)
        
        local redis_key=$(az redis list-keys \
            --resource-group "$RESOURCE_GROUP" \
            --name "$REDIS_CACHE" \
            --query primaryKey --output tsv)
        
        # Configure app settings
        az webapp config appsettings set \
            --resource-group "$RESOURCE_GROUP" \
            --name "$WEB_APP" \
            --settings \
            REDIS_HOSTNAME="$redis_hostname" \
            REDIS_KEY="$redis_key" \
            REDIS_PORT=6380 \
            REDIS_SSL=true \
            DATABASE_URL="postgresql://dbadmin:P@ssw0rd123!@${DB_SERVER}.postgres.database.azure.com:5432/${DB_NAME}" \
            NODE_ENV="$ENVIRONMENT" \
            --output table
        
        if [ $? -eq 0 ]; then
            log "✅ App settings configured successfully"
        else
            error "Failed to configure app settings"
            exit 1
        fi
    else
        error "Failed to create Web App: $WEB_APP"
        exit 1
    fi
}

# Function to create CDN
create_cdn() {
    log "Creating CDN profile: $CDN_PROFILE"
    
    if [ "$DRY_RUN" = "true" ]; then
        info "[DRY RUN] Would create CDN profile: $CDN_PROFILE"
        return 0
    fi
    
    # Check if CDN profile already exists
    if ! az cdn profile show --resource-group "$RESOURCE_GROUP" --name "$CDN_PROFILE" &> /dev/null; then
        az cdn profile create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$CDN_PROFILE" \
            --location "$LOCATION" \
            --sku Standard_Microsoft \
            --tags purpose=performance-demo environment="$ENVIRONMENT" \
            --output table
        
        if [ $? -eq 0 ]; then
            log "✅ CDN profile created successfully: $CDN_PROFILE"
        else
            error "Failed to create CDN profile: $CDN_PROFILE"
            exit 1
        fi
    else
        warn "CDN profile $CDN_PROFILE already exists"
    fi
    
    # Get web app hostname
    local web_app_hostname=$(az webapp show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WEB_APP" \
        --query defaultHostName --output tsv)
    
    # Check if CDN endpoint already exists
    if az cdn endpoint show --resource-group "$RESOURCE_GROUP" --profile-name "$CDN_PROFILE" --name "$CDN_ENDPOINT" &> /dev/null; then
        warn "CDN endpoint $CDN_ENDPOINT already exists"
        return 0
    fi
    
    # Create CDN endpoint
    az cdn endpoint create \
        --resource-group "$RESOURCE_GROUP" \
        --profile-name "$CDN_PROFILE" \
        --name "$CDN_ENDPOINT" \
        --origin "$web_app_hostname" \
        --origin-host-header "$web_app_hostname" \
        --location "$LOCATION" \
        --tags purpose=performance-demo environment="$ENVIRONMENT" \
        --output table
    
    if [ $? -eq 0 ]; then
        log "✅ CDN endpoint created successfully: $CDN_ENDPOINT"
        
        # Configure caching rules
        log "Configuring CDN caching rules..."
        
        # Static assets caching rule
        az cdn endpoint rule add \
            --resource-group "$RESOURCE_GROUP" \
            --profile-name "$CDN_PROFILE" \
            --endpoint-name "$CDN_ENDPOINT" \
            --order 1 \
            --rule-name "StaticAssets" \
            --match-variable RequestPath \
            --operator BeginsWith \
            --match-values "/static/" "/images/" "/css/" "/js/" \
            --action-name CacheExpiration \
            --cache-behavior Override \
            --cache-duration "30.00:00:00" \
            --output table
        
        # API endpoints caching rule
        az cdn endpoint rule add \
            --resource-group "$RESOURCE_GROUP" \
            --profile-name "$CDN_PROFILE" \
            --endpoint-name "$CDN_ENDPOINT" \
            --order 2 \
            --rule-name "ApiEndpoints" \
            --match-variable RequestPath \
            --operator BeginsWith \
            --match-values "/api/" \
            --action-name CacheExpiration \
            --cache-behavior Override \
            --cache-duration "0.00:05:00" \
            --output table
        
        # Enable compression
        az cdn endpoint update \
            --resource-group "$RESOURCE_GROUP" \
            --profile-name "$CDN_PROFILE" \
            --name "$CDN_ENDPOINT" \
            --enable-compression true \
            --query-string-caching-behavior IgnoreQueryString \
            --output table
        
        if [ $? -eq 0 ]; then
            log "✅ CDN caching rules configured successfully"
        else
            error "Failed to configure CDN caching rules"
            exit 1
        fi
    else
        error "Failed to create CDN endpoint: $CDN_ENDPOINT"
        exit 1
    fi
}

# Function to create Application Insights
create_application_insights() {
    log "Creating Application Insights: $INSIGHTS_COMPONENT"
    
    if [ "$DRY_RUN" = "true" ]; then
        info "[DRY RUN] Would create Application Insights: $INSIGHTS_COMPONENT"
        return 0
    fi
    
    # Check if Application Insights already exists
    if az monitor app-insights component show --resource-group "$RESOURCE_GROUP" --app "$INSIGHTS_COMPONENT" &> /dev/null; then
        warn "Application Insights $INSIGHTS_COMPONENT already exists"
        return 0
    fi
    
    az monitor app-insights component create \
        --resource-group "$RESOURCE_GROUP" \
        --app "$INSIGHTS_COMPONENT" \
        --location "$LOCATION" \
        --kind web \
        --tags purpose=performance-demo environment="$ENVIRONMENT" \
        --output table
    
    if [ $? -eq 0 ]; then
        log "✅ Application Insights created successfully: $INSIGHTS_COMPONENT"
        
        # Get instrumentation key
        local insights_key=$(az monitor app-insights component show \
            --resource-group "$RESOURCE_GROUP" \
            --app "$INSIGHTS_COMPONENT" \
            --query instrumentationKey --output tsv)
        
        # Configure web app with Application Insights
        az webapp config appsettings set \
            --resource-group "$RESOURCE_GROUP" \
            --name "$WEB_APP" \
            --settings \
            APPINSIGHTS_INSTRUMENTATIONKEY="$insights_key" \
            APPLICATIONINSIGHTS_CONNECTION_STRING="InstrumentationKey=$insights_key" \
            --output table
        
        if [ $? -eq 0 ]; then
            log "✅ Application Insights configured successfully"
        else
            error "Failed to configure Application Insights"
            exit 1
        fi
    else
        error "Failed to create Application Insights: $INSIGHTS_COMPONENT"
        exit 1
    fi
}

# Function to enable diagnostic logging
enable_diagnostic_logging() {
    log "Enabling diagnostic logging for Web App: $WEB_APP"
    
    if [ "$DRY_RUN" = "true" ]; then
        info "[DRY RUN] Would enable diagnostic logging for: $WEB_APP"
        return 0
    fi
    
    # Enable diagnostic logging
    az webapp log config \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WEB_APP" \
        --application-logging true \
        --level information \
        --web-server-logging filesystem \
        --output table
    
    # Configure additional logging settings
    az webapp log config \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WEB_APP" \
        --application-logging filesystem \
        --detailed-error-messages true \
        --failed-request-tracing true \
        --output table
    
    if [ $? -eq 0 ]; then
        log "✅ Diagnostic logging enabled successfully"
    else
        error "Failed to enable diagnostic logging"
        exit 1
    fi
}

# Function to display deployment summary
display_deployment_summary() {
    log "Deployment completed successfully!"
    
    local web_app_url="https://${WEB_APP}.azurewebsites.net"
    local cdn_url="https://${CDN_ENDPOINT}.azureedge.net"
    
    echo ""
    echo "=========================================="
    echo "         DEPLOYMENT SUMMARY"
    echo "=========================================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Environment: $ENVIRONMENT"
    echo ""
    echo "Created Resources:"
    echo "  • App Service Plan: $APP_SERVICE_PLAN"
    echo "  • Web App: $WEB_APP"
    echo "  • Redis Cache: $REDIS_CACHE"
    echo "  • CDN Profile: $CDN_PROFILE"
    echo "  • CDN Endpoint: $CDN_ENDPOINT"
    echo "  • Database Server: $DB_SERVER"
    echo "  • Application Insights: $INSIGHTS_COMPONENT"
    echo ""
    echo "URLs:"
    echo "  • Web App: $web_app_url"
    echo "  • CDN Endpoint: $cdn_url"
    echo ""
    echo "Next Steps:"
    echo "  1. Deploy your application code to the Web App"
    echo "  2. Configure custom domain for CDN (optional)"
    echo "  3. Monitor performance using Application Insights"
    echo "  4. Review Redis cache metrics for optimization"
    echo ""
    echo "⚠️  Important: Save the database and Redis credentials securely!"
    echo "=========================================="
}

# Function to handle cleanup on failure
cleanup_on_failure() {
    error "Deployment failed. Starting cleanup of partially created resources..."
    
    # This is a basic cleanup - you might want to implement more sophisticated logic
    if [ "$DRY_RUN" != "true" ]; then
        warn "To clean up resources, run: ./destroy.sh -g $RESOURCE_GROUP"
    fi
}

# Main function
main() {
    local start_time=$(date +%s)
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -s|--subscription)
                SUBSCRIPTION_ID="$2"
                shift 2
                ;;
            -r|--random-suffix)
                RANDOM_SUFFIX="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-prereqs)
                SKIP_PREREQS=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Start deployment
    log "Starting deployment of Azure Web Application Performance Optimization infrastructure"
    info "Recipe: $RECIPE_NAME"
    info "Deployment log: $DEPLOYMENT_LOG_FILE"
    
    # Setup error handling
    trap cleanup_on_failure ERR
    
    # Execute deployment steps
    check_prerequisites
    initialize_config
    
    if [ "$DRY_RUN" = "true" ]; then
        info "DRY RUN MODE - No resources will be created"
    fi
    
    create_resource_group
    create_postgresql_database
    create_redis_cache
    create_app_service
    create_cdn
    create_application_insights
    enable_diagnostic_logging
    
    # Calculate deployment time
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ "$DRY_RUN" = "true" ]; then
        log "Dry run completed in ${duration} seconds"
        info "No resources were created. Run without --dry-run to deploy."
    else
        display_deployment_summary
        log "Deployment completed in ${duration} seconds"
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@" 2>&1 | tee "$DEPLOYMENT_LOG_FILE"
fi