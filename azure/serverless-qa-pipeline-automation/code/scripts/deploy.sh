#!/bin/bash

# Deploy script for Automated Quality Assurance Pipelines with Azure Container Apps Jobs and Azure Load Testing
# This script deploys the complete infrastructure for the QA pipeline solution

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
VERBOSE=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "${LOG_FILE}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "${LOG_FILE}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "${LOG_FILE}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1" >> "${LOG_FILE}"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Container Apps Jobs and Azure Load Testing infrastructure for QA pipeline.

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -r, --region        Azure region (default: eastus)
    -s, --subscription  Azure subscription ID (optional)
    --dry-run          Show what would be deployed without actually deploying
    --force            Force deployment even if resources exist
    --skip-prereq      Skip prerequisite checks

EXAMPLES:
    $0                                    # Deploy with defaults
    $0 --region westus2 --verbose         # Deploy to West US 2 with verbose logging
    $0 --dry-run                          # Show deployment plan without executing
    $0 --force                            # Force deployment overwriting existing resources

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -r|--region)
                LOCATION="$2"
                shift 2
                ;;
            -s|--subscription)
                SUBSCRIPTION_ID="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --skip-prereq)
                SKIP_PREREQ=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

# Set default values
LOCATION="${LOCATION:-eastus}"
DRY_RUN="${DRY_RUN:-false}"
FORCE="${FORCE:-false}"
SKIP_PREREQ="${SKIP_PREREQ:-false}"

# Generate unique suffix for resources
RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")

# Set resource names
RESOURCE_GROUP="rg-qa-pipeline-${RANDOM_SUFFIX}"
CONTAINER_ENV_NAME="cae-qa-${RANDOM_SUFFIX}"
LOG_ANALYTICS_NAME="law-qa-${RANDOM_SUFFIX}"
STORAGE_ACCOUNT_NAME="stqa${RANDOM_SUFFIX}"
LOAD_TEST_NAME="lt-qa-${RANDOM_SUFFIX}"

# Prerequisites check
check_prerequisites() {
    if [[ "$SKIP_PREREQ" == "true" ]]; then
        warn "Skipping prerequisite checks"
        return 0
    fi

    info "Checking prerequisites..."

    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi

    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first"
    fi

    # Check Azure CLI version
    CLI_VERSION=$(az version --query '"azure-cli"' -o tsv)
    REQUIRED_VERSION="2.50.0"
    if [[ "$(printf '%s\n' "$REQUIRED_VERSION" "$CLI_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]]; then
        warn "Azure CLI version $CLI_VERSION is older than recommended version $REQUIRED_VERSION"
    fi

    # Set subscription if provided
    if [[ -n "$SUBSCRIPTION_ID" ]]; then
        info "Setting subscription to $SUBSCRIPTION_ID"
        az account set --subscription "$SUBSCRIPTION_ID"
    fi

    # Get current subscription
    CURRENT_SUBSCRIPTION=$(az account show --query id -o tsv)
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    info "Using subscription: $SUBSCRIPTION_NAME ($CURRENT_SUBSCRIPTION)"

    # Check if Container Apps extension is available
    if ! az extension show --name containerapp &> /dev/null; then
        info "Installing Container Apps extension..."
        az extension add --name containerapp --upgrade
    fi

    # Check if Load Testing extension is available
    if ! az extension show --name load &> /dev/null; then
        info "Installing Load Testing extension..."
        az extension add --name load --upgrade
    fi

    # Check required providers
    info "Checking required resource providers..."
    REQUIRED_PROVIDERS=(
        "Microsoft.App"
        "Microsoft.LoadTestService"
        "Microsoft.Storage"
        "Microsoft.OperationalInsights"
    )

    for provider in "${REQUIRED_PROVIDERS[@]}"; do
        STATE=$(az provider show --namespace "$provider" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
        if [[ "$STATE" != "Registered" ]]; then
            info "Registering provider: $provider"
            az provider register --namespace "$provider"
            
            # Wait for registration
            while [[ "$(az provider show --namespace "$provider" --query registrationState -o tsv)" != "Registered" ]]; do
                info "Waiting for provider $provider to register..."
                sleep 10
            done
        fi
    done

    log "Prerequisites check completed successfully"
}

# Check if resource group exists
check_resource_group() {
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        if [[ "$FORCE" == "true" ]]; then
            warn "Resource group $RESOURCE_GROUP already exists, continuing due to --force flag"
        else
            error "Resource group $RESOURCE_GROUP already exists. Use --force to overwrite or choose a different name"
        fi
    fi
}

# Create resource group
create_resource_group() {
    info "Creating resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create resource group: $RESOURCE_GROUP in $LOCATION"
        return 0
    fi

    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=qa-pipeline environment=demo created-by=azure-recipe \
        --output none

    log "✅ Resource group created: $RESOURCE_GROUP"
}

# Create Log Analytics workspace
create_log_analytics() {
    info "Creating Log Analytics workspace: $LOG_ANALYTICS_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create Log Analytics workspace: $LOG_ANALYTICS_NAME"
        return 0
    fi

    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_NAME" \
        --location "$LOCATION" \
        --sku PerGB2018 \
        --retention-time 30 \
        --output none

    # Get workspace ID and key
    LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_NAME" \
        --query customerId -o tsv)

    LOG_ANALYTICS_KEY=$(az monitor log-analytics workspace get-shared-keys \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_NAME" \
        --query primarySharedKey -o tsv)

    log "✅ Log Analytics workspace created: $LOG_ANALYTICS_NAME"
}

# Create storage account
create_storage_account() {
    info "Creating storage account: $STORAGE_ACCOUNT_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create storage account: $STORAGE_ACCOUNT_NAME"
        return 0
    fi

    az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --allow-blob-public-access false \
        --min-tls-version TLS1_2 \
        --output none

    # Create containers
    az storage container create \
        --name "load-test-scripts" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --public-access off \
        --output none

    az storage container create \
        --name "monitoring-templates" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --public-access off \
        --output none

    az storage container create \
        --name "test-results" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --public-access off \
        --output none

    log "✅ Storage account created: $STORAGE_ACCOUNT_NAME"
}

# Create Container Apps environment
create_container_apps_environment() {
    info "Creating Container Apps environment: $CONTAINER_ENV_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create Container Apps environment: $CONTAINER_ENV_NAME"
        return 0
    fi

    az containerapp env create \
        --name "$CONTAINER_ENV_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --logs-workspace-id "$LOG_ANALYTICS_ID" \
        --logs-workspace-key "$LOG_ANALYTICS_KEY" \
        --output none

    # Wait for environment to be ready
    info "Waiting for Container Apps environment to be ready..."
    while [[ "$(az containerapp env show --name "$CONTAINER_ENV_NAME" --resource-group "$RESOURCE_GROUP" --query provisioningState -o tsv)" != "Succeeded" ]]; do
        sleep 10
    done

    log "✅ Container Apps environment created: $CONTAINER_ENV_NAME"
}

# Create Container Apps jobs
create_container_jobs() {
    info "Creating Container Apps jobs..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create Container Apps jobs"
        return 0
    fi

    # Unit test job
    info "Creating unit test job..."
    az containerapp job create \
        --name "unit-test-job" \
        --resource-group "$RESOURCE_GROUP" \
        --environment "$CONTAINER_ENV_NAME" \
        --trigger-type Manual \
        --replica-timeout 1800 \
        --replica-retry-limit 3 \
        --parallelism 3 \
        --replica-completion-count 1 \
        --image mcr.microsoft.com/dotnet/sdk:7.0 \
        --cpu 1.0 \
        --memory 2Gi \
        --command "/bin/bash" \
        --args "-c" "echo 'Running unit tests...'; sleep 10; echo 'Unit tests completed successfully'" \
        --output none

    # Integration test job
    info "Creating integration test job..."
    az containerapp job create \
        --name "integration-test-job" \
        --resource-group "$RESOURCE_GROUP" \
        --environment "$CONTAINER_ENV_NAME" \
        --trigger-type Manual \
        --replica-timeout 3600 \
        --replica-retry-limit 2 \
        --parallelism 2 \
        --replica-completion-count 1 \
        --image mcr.microsoft.com/dotnet/sdk:7.0 \
        --cpu 1.5 \
        --memory 3Gi \
        --env-vars "TEST_TYPE=integration" "TIMEOUT=3600" \
        --command "/bin/bash" \
        --args "-c" "echo 'Running integration tests with timeout: \$TIMEOUT'; sleep 15; echo 'Integration tests completed'" \
        --output none

    # Performance test job
    info "Creating performance test job..."
    az containerapp job create \
        --name "performance-test-job" \
        --resource-group "$RESOURCE_GROUP" \
        --environment "$CONTAINER_ENV_NAME" \
        --trigger-type Manual \
        --replica-timeout 7200 \
        --replica-retry-limit 1 \
        --parallelism 1 \
        --replica-completion-count 1 \
        --image mcr.microsoft.com/azure-cli:latest \
        --cpu 0.5 \
        --memory 1Gi \
        --env-vars "LOAD_TEST_NAME=$LOAD_TEST_NAME" "RESOURCE_GROUP=$RESOURCE_GROUP" \
        --command "/bin/bash" \
        --args "-c" "echo 'Starting load test orchestration'; echo 'Load test: \$LOAD_TEST_NAME'; sleep 30; echo 'Performance test orchestration completed'" \
        --output none

    # Security test job
    info "Creating security test job..."
    az containerapp job create \
        --name "security-test-job" \
        --resource-group "$RESOURCE_GROUP" \
        --environment "$CONTAINER_ENV_NAME" \
        --trigger-type Manual \
        --replica-timeout 2400 \
        --replica-retry-limit 2 \
        --parallelism 1 \
        --replica-completion-count 1 \
        --image mcr.microsoft.com/dotnet/sdk:7.0 \
        --cpu 1.0 \
        --memory 2Gi \
        --env-vars "SECURITY_SCAN_TYPE=full" "REPORT_FORMAT=json" \
        --command "/bin/bash" \
        --args "-c" "echo 'Starting security scan: \$SECURITY_SCAN_TYPE'; sleep 20; echo 'Security scan completed - format: \$REPORT_FORMAT'" \
        --output none

    log "✅ Container Apps jobs created successfully"
}

# Create Azure Load Testing resource
create_load_testing() {
    info "Creating Azure Load Testing resource: $LOAD_TEST_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create Azure Load Testing resource: $LOAD_TEST_NAME"
        return 0
    fi

    az load create \
        --name "$LOAD_TEST_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=qa-pipeline environment=demo created-by=azure-recipe \
        --output none

    # Wait for load testing resource to be ready
    info "Waiting for Azure Load Testing resource to be ready..."
    while [[ "$(az load show --name "$LOAD_TEST_NAME" --resource-group "$RESOURCE_GROUP" --query provisioningState -o tsv)" != "Succeeded" ]]; do
        sleep 10
    done

    log "✅ Azure Load Testing resource created: $LOAD_TEST_NAME"
}

# Create monitoring templates
create_monitoring_templates() {
    info "Creating monitoring templates..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create monitoring templates"
        return 0
    fi

    # Create workbook template
    cat > "${SCRIPT_DIR}/qa-pipeline-workbook.json" << 'EOF'
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 1,
      "content": {
        "json": "# QA Pipeline Monitoring Dashboard\n\nThis dashboard provides real-time visibility into your automated quality assurance pipeline performance and results."
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "ContainerAppConsoleLogs_CL | where ContainerAppName_s contains 'test-job' | summarize count() by bin(TimeGenerated, 1h), ContainerAppName_s",
        "size": 1,
        "title": "Test Job Execution Frequency",
        "queryType": 0,
        "visualization": "timechart"
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "ContainerAppConsoleLogs_CL | where ContainerAppName_s contains 'test-job' | where Log_s contains 'completed' | summarize count() by ContainerAppName_s",
        "size": 1,
        "title": "Test Job Success Rate",
        "queryType": 0,
        "visualization": "piechart"
      }
    }
  ]
}
EOF

    # Upload workbook template
    az storage blob upload \
        --file "${SCRIPT_DIR}/qa-pipeline-workbook.json" \
        --name "qa-pipeline-workbook.json" \
        --container-name "monitoring-templates" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --overwrite \
        --output none

    # Create Azure DevOps pipeline template
    cat > "${SCRIPT_DIR}/azure-pipelines-qa.yml" << EOF
trigger:
  branches:
    include:
      - main
      - develop

pool:
  vmImage: 'ubuntu-latest'

variables:
  resourceGroup: '$RESOURCE_GROUP'
  containerEnv: '$CONTAINER_ENV_NAME'
  loadTestName: '$LOAD_TEST_NAME'

stages:
- stage: UnitTests
  displayName: 'Unit Tests'
  jobs:
  - job: RunUnitTests
    steps:
    - task: AzureCLI@2
      displayName: 'Execute Unit Test Job'
      inputs:
        azureSubscription: 'azure-service-connection'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          az containerapp job start \\
            --name unit-test-job \\
            --resource-group \$(resourceGroup)
          
          # Wait for completion and get results
          az containerapp job execution list \\
            --name unit-test-job \\
            --resource-group \$(resourceGroup) \\
            --query '[0].status' --output tsv

- stage: IntegrationTests
  displayName: 'Integration Tests'
  dependsOn: UnitTests
  condition: succeeded()
  jobs:
  - job: RunIntegrationTests
    steps:
    - task: AzureCLI@2
      displayName: 'Execute Integration Test Job'
      inputs:
        azureSubscription: 'azure-service-connection'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          az containerapp job start \\
            --name integration-test-job \\
            --resource-group \$(resourceGroup)

- stage: PerformanceTests
  displayName: 'Performance Tests'
  dependsOn: IntegrationTests
  condition: succeeded()
  jobs:
  - job: RunPerformanceTests
    steps:
    - task: AzureCLI@2
      displayName: 'Execute Performance Test Job'
      inputs:
        azureSubscription: 'azure-service-connection'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          az containerapp job start \\
            --name performance-test-job \\
            --resource-group \$(resourceGroup)

- stage: SecurityTests
  displayName: 'Security Tests'
  dependsOn: PerformanceTests
  condition: succeeded()
  jobs:
  - job: RunSecurityTests
    steps:
    - task: AzureCLI@2
      displayName: 'Execute Security Test Job'
      inputs:
        azureSubscription: 'azure-service-connection'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          az containerapp job start \\
            --name security-test-job \\
            --resource-group \$(resourceGroup)
EOF

    # Upload pipeline template
    az storage blob upload \
        --file "${SCRIPT_DIR}/azure-pipelines-qa.yml" \
        --name "azure-pipelines-qa.yml" \
        --container-name "monitoring-templates" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --overwrite \
        --output none

    # Clean up temporary files
    rm -f "${SCRIPT_DIR}/qa-pipeline-workbook.json" "${SCRIPT_DIR}/azure-pipelines-qa.yml"

    log "✅ Monitoring templates created and uploaded"
}

# Validate deployment
validate_deployment() {
    info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would validate deployment"
        return 0
    fi

    # Check Container Apps environment
    ENV_STATE=$(az containerapp env show --name "$CONTAINER_ENV_NAME" --resource-group "$RESOURCE_GROUP" --query provisioningState -o tsv)
    if [[ "$ENV_STATE" != "Succeeded" ]]; then
        error "Container Apps environment is not in Succeeded state: $ENV_STATE"
    fi

    # Check Container Apps jobs
    JOBS=("unit-test-job" "integration-test-job" "performance-test-job" "security-test-job")
    for job in "${JOBS[@]}"; do
        JOB_STATE=$(az containerapp job show --name "$job" --resource-group "$RESOURCE_GROUP" --query properties.provisioningState -o tsv)
        if [[ "$JOB_STATE" != "Succeeded" ]]; then
            error "Container Apps job $job is not in Succeeded state: $JOB_STATE"
        fi
    done

    # Check Load Testing resource
    LOAD_TEST_STATE=$(az load show --name "$LOAD_TEST_NAME" --resource-group "$RESOURCE_GROUP" --query provisioningState -o tsv)
    if [[ "$LOAD_TEST_STATE" != "Succeeded" ]]; then
        error "Azure Load Testing resource is not in Succeeded state: $LOAD_TEST_STATE"
    fi

    # Check Storage Account
    STORAGE_STATE=$(az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" --query provisioningState -o tsv)
    if [[ "$STORAGE_STATE" != "Succeeded" ]]; then
        error "Storage Account is not in Succeeded state: $STORAGE_STATE"
    fi

    log "✅ Deployment validation completed successfully"
}

# Print deployment summary
print_summary() {
    info "🎉 Deployment completed successfully!"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Container Apps Environment: $CONTAINER_ENV_NAME"
    echo "Log Analytics Workspace: $LOG_ANALYTICS_NAME"
    echo "Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "Load Testing Resource: $LOAD_TEST_NAME"
    echo
    echo "=== CREATED RESOURCES ==="
    echo "• Container Apps Jobs:"
    echo "  - unit-test-job"
    echo "  - integration-test-job"
    echo "  - performance-test-job"
    echo "  - security-test-job"
    echo "• Azure Load Testing resource"
    echo "• Storage Account with containers for scripts and results"
    echo "• Log Analytics workspace for monitoring"
    echo "• Azure Monitor workbook template"
    echo "• Azure DevOps pipeline template"
    echo
    echo "=== NEXT STEPS ==="
    echo "1. Configure your CI/CD pipeline using the uploaded template"
    echo "2. Test the Container Apps jobs manually:"
    echo "   az containerapp job start --name unit-test-job --resource-group $RESOURCE_GROUP"
    echo "3. View logs in Log Analytics workspace: $LOG_ANALYTICS_NAME"
    echo "4. Upload your load testing scripts to the storage account"
    echo "5. Run the cleanup script when no longer needed: ./destroy.sh"
    echo
    echo "=== ESTIMATED MONTHLY COST ==="
    echo "• Container Apps Jobs: ~\$20-40 (consumption-based)"
    echo "• Azure Load Testing: ~\$10-30 (usage-based)"
    echo "• Storage Account: ~\$5-10"
    echo "• Log Analytics: ~\$10-20"
    echo "Total estimated: \$50-100/month for development workloads"
    echo
    echo "For detailed cost information, visit: https://azure.microsoft.com/pricing/calculator/"
}

# Main execution function
main() {
    echo "=== Azure QA Pipeline Deployment Script ==="
    echo "Starting deployment at $(date)"
    echo

    # Initialize log file
    : > "$LOG_FILE"

    # Parse command line arguments
    parse_args "$@"

    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN MODE - No resources will be created"
        echo
    fi

    # Execute deployment steps
    check_prerequisites
    check_resource_group
    create_resource_group
    create_log_analytics
    create_storage_account
    create_container_apps_environment
    create_container_jobs
    create_load_testing
    create_monitoring_templates
    validate_deployment
    print_summary

    log "Deployment completed successfully at $(date)"
    echo "Deployment log saved to: $LOG_FILE"
}

# Execute main function with all arguments
main "$@"