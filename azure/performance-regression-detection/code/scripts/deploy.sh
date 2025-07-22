#!/bin/bash

# Azure Performance Regression Detection - Deployment Script
# This script deploys the complete infrastructure for automated performance 
# regression detection using Azure Load Testing and Azure Monitor Workbooks

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default values
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/azure-perftest-deploy-$(date +%Y%m%d-%H%M%S).log"
readonly DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment-state"

# Configuration variables
RESOURCE_GROUP=""
LOCATION="eastus"
SUBSCRIPTION_ID=""
DRY_RUN=false
SKIP_CLEANUP_ON_ERROR=false
VERBOSE=false

# Resource names (will be set with random suffix)
LOAD_TEST_NAME=""
CONTAINER_APP_NAME=""
WORKSPACE_NAME=""
ENVIRONMENT_NAME=""
ACR_NAME=""
WORKBOOK_NAME=""
RANDOM_SUFFIX=""

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] ${message}${NC}" | tee -a "${LOG_FILE}"
}

print_info() { print_status "${BLUE}" "INFO: $1"; }
print_success() { print_status "${GREEN}" "SUCCESS: $1"; }
print_warning() { print_status "${YELLOW}" "WARNING: $1"; }
print_error() { print_status "${RED}" "ERROR: $1"; }

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version (minimum 2.60.0)
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    local min_version="2.60.0"
    if ! printf '%s\n%s\n' "$min_version" "$az_version" | sort -V | head -1 | grep -q "^$min_version$"; then
        print_error "Azure CLI version $az_version is too old. Minimum required: $min_version"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if subscription is set
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        print_error "No active Azure subscription found."
        exit 1
    fi
    
    # Check required extensions
    print_info "Checking Azure CLI extensions..."
    local required_extensions=("containerapp" "load")
    for ext in "${required_extensions[@]}"; do
        if ! az extension show --name "$ext" &> /dev/null; then
            print_info "Installing Azure CLI extension: $ext"
            az extension add --name "$ext" --yes
        fi
    done
    
    print_success "Prerequisites check completed"
}

# Function to validate required parameters
validate_parameters() {
    if [[ -z "$RESOURCE_GROUP" ]]; then
        print_error "Resource group name is required. Use --resource-group parameter."
        exit 1
    fi
    
    if [[ -z "$LOCATION" ]]; then
        print_error "Location is required. Use --location parameter."
        exit 1
    fi
    
    # Validate Azure location
    if ! az account list-locations --query "[?name=='$LOCATION']" --output tsv | grep -q "$LOCATION"; then
        print_error "Invalid Azure location: $LOCATION"
        print_info "Available locations: $(az account list-locations --query '[].name' --output tsv | tr '\n' ' ')"
        exit 1
    fi
}

# Function to generate unique resource names
generate_resource_names() {
    print_info "Generating unique resource names..."
    
    # Generate random suffix (6 characters)
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    LOAD_TEST_NAME="lt-perftest-${RANDOM_SUFFIX}"
    CONTAINER_APP_NAME="ca-demo-${RANDOM_SUFFIX}"
    WORKSPACE_NAME="law-perftest-${RANDOM_SUFFIX}"
    ENVIRONMENT_NAME="cae-perftest-${RANDOM_SUFFIX}"
    ACR_NAME="acrperftest${RANDOM_SUFFIX}"
    WORKBOOK_NAME="wb-perftest-${RANDOM_SUFFIX}"
    
    print_info "Resource names generated with suffix: $RANDOM_SUFFIX"
}

# Function to save deployment state
save_deployment_state() {
    cat > "$DEPLOYMENT_STATE_FILE" << EOF
RESOURCE_GROUP="$RESOURCE_GROUP"
LOCATION="$LOCATION"
SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
LOAD_TEST_NAME="$LOAD_TEST_NAME"
CONTAINER_APP_NAME="$CONTAINER_APP_NAME"
WORKSPACE_NAME="$WORKSPACE_NAME"
ENVIRONMENT_NAME="$ENVIRONMENT_NAME"
ACR_NAME="$ACR_NAME"
WORKBOOK_NAME="$WORKBOOK_NAME"
RANDOM_SUFFIX="$RANDOM_SUFFIX"
DEPLOYMENT_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    print_info "Deployment state saved to: $DEPLOYMENT_STATE_FILE"
}

# Function to create resource group
create_resource_group() {
    print_info "Creating resource group: $RESOURCE_GROUP"
    
    if $DRY_RUN; then
        print_info "[DRY RUN] Would create resource group: $RESOURCE_GROUP in $LOCATION"
        return
    fi
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=performance-testing environment=demo recipe=azure-load-testing-regression \
            --output none
        print_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create Log Analytics workspace
create_log_analytics_workspace() {
    print_info "Creating Log Analytics workspace: $WORKSPACE_NAME"
    
    if $DRY_RUN; then
        print_info "[DRY RUN] Would create Log Analytics workspace: $WORKSPACE_NAME"
        return
    fi
    
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$WORKSPACE_NAME" \
        --location "$LOCATION" \
        --retention-time 30 \
        --tags purpose=performance-monitoring \
        --output none
    
    print_success "Log Analytics workspace created: $WORKSPACE_NAME"
}

# Function to create Azure Load Testing resource
create_load_testing_resource() {
    print_info "Creating Azure Load Testing resource: $LOAD_TEST_NAME"
    
    if $DRY_RUN; then
        print_info "[DRY RUN] Would create Load Testing resource: $LOAD_TEST_NAME"
        return
    fi
    
    # Check if load testing is available in the region
    if ! az load test list-supported-locations --query "[?contains(name, '$LOCATION')]" --output tsv | grep -q "$LOCATION"; then
        print_warning "Azure Load Testing may not be available in $LOCATION. Continuing anyway..."
    fi
    
    az load create \
        --name "$LOAD_TEST_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=ci-cd-integration \
        --output none
    
    print_success "Load Testing resource created: $LOAD_TEST_NAME"
}

# Function to create Container Registry
create_container_registry() {
    print_info "Creating Azure Container Registry: $ACR_NAME"
    
    if $DRY_RUN; then
        print_info "[DRY RUN] Would create Container Registry: $ACR_NAME"
        return
    fi
    
    az acr create \
        --name "$ACR_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Basic \
        --admin-enabled true \
        --tags purpose=demo-app-hosting \
        --output none
    
    print_success "Container Registry created: $ACR_NAME"
}

# Function to create Container Apps Environment
create_container_apps_environment() {
    print_info "Creating Container Apps Environment: $ENVIRONMENT_NAME"
    
    if $DRY_RUN; then
        print_info "[DRY RUN] Would create Container Apps Environment: $ENVIRONMENT_NAME"
        return
    fi
    
    # Get workspace ID and key
    local workspace_id
    workspace_id=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$WORKSPACE_NAME" \
        --query id --output tsv)
    
    local workspace_key
    workspace_key=$(az monitor log-analytics workspace get-shared-keys \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$WORKSPACE_NAME" \
        --query primarySharedKey --output tsv)
    
    az containerapp env create \
        --name "$ENVIRONMENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --logs-workspace-id "$workspace_id" \
        --logs-workspace-key "$workspace_key" \
        --tags purpose=performance-testing \
        --output none
    
    print_success "Container Apps Environment created: $ENVIRONMENT_NAME"
}

# Function to build and deploy sample application
deploy_sample_application() {
    print_info "Building and deploying sample application"
    
    if $DRY_RUN; then
        print_info "[DRY RUN] Would build and deploy sample application"
        return
    fi
    
    # Build sample application in ACR
    print_info "Building sample application in ACR..."
    az acr build \
        --registry "$ACR_NAME" \
        --image demo-app:v1.0 \
        --source "https://github.com/Azure-Samples/nodejs-docs-hello-world.git" \
        --platform linux \
        --output none
    
    # Get ACR credentials
    local acr_password
    acr_password=$(az acr credential show \
        --name "$ACR_NAME" \
        --query passwords[0].value --output tsv)
    
    # Create Container App
    print_info "Creating Container App: $CONTAINER_APP_NAME"
    az containerapp create \
        --name "$CONTAINER_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --environment "$ENVIRONMENT_NAME" \
        --image "${ACR_NAME}.azurecr.io/demo-app:v1.0" \
        --registry-server "${ACR_NAME}.azurecr.io" \
        --registry-username "$ACR_NAME" \
        --registry-password "$acr_password" \
        --target-port 3000 \
        --ingress external \
        --cpu 0.5 \
        --memory 1.0Gi \
        --min-replicas 1 \
        --max-replicas 5 \
        --tags purpose=performance-testing \
        --output none
    
    print_success "Sample application deployed: $CONTAINER_APP_NAME"
}

# Function to create performance monitoring workbook
create_performance_workbook() {
    print_info "Creating Azure Monitor Workbook: $WORKBOOK_NAME"
    
    if $DRY_RUN; then
        print_info "[DRY RUN] Would create performance monitoring workbook"
        return
    fi
    
    # Get workspace ID
    local workspace_id
    workspace_id=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$WORKSPACE_NAME" \
        --query id --output tsv)
    
    # Create workbook template file
    local workbook_template="/tmp/performance-workbook-${RANDOM_SUFFIX}.json"
    cat > "$workbook_template" << 'EOF'
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 1,
      "content": {
        "json": "# Performance Regression Detection Dashboard\n\nMonitor application performance trends and detect regressions automatically."
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "ContainerAppConsoleLogs_CL\n| where TimeGenerated > ago(1h)\n| summarize ResponseTime = avg(todouble(Properties_s.duration)) by bin(TimeGenerated, 5m)\n| render timechart",
        "size": 0,
        "title": "Average Response Time Trend",
        "timeContext": {
          "durationMs": 3600000
        },
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces"
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "ContainerAppConsoleLogs_CL\n| where TimeGenerated > ago(1h)\n| summarize ErrorRate = countif(Properties_s.status >= 400) * 100.0 / count() by bin(TimeGenerated, 5m)\n| render timechart",
        "size": 0,
        "title": "Error Rate %",
        "timeContext": {
          "durationMs": 3600000
        },
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces"
      }
    }
  ]
}
EOF
    
    # Note: Azure CLI doesn't have direct workbook creation command
    # This would typically be done through ARM template or Azure Portal
    print_warning "Workbook creation requires manual setup in Azure Portal or ARM template deployment"
    print_info "Workbook template saved to: $workbook_template"
    
    print_success "Performance workbook template prepared"
}

# Function to create alert rules
create_alert_rules() {
    print_info "Creating performance regression alert rules"
    
    if $DRY_RUN; then
        print_info "[DRY RUN] Would create alert rules"
        return
    fi
    
    # Get workspace ID
    local workspace_id
    workspace_id=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$WORKSPACE_NAME" \
        --query id --output tsv)
    
    # Create action group for alerts
    print_info "Creating action group for alerts..."
    az monitor action-group create \
        --name "PerformanceAlerts" \
        --resource-group "$RESOURCE_GROUP" \
        --short-name "PerfAlerts" \
        --tags purpose=performance-monitoring \
        --output none
    
    # Note: Scheduled query rules for Log Analytics would be created here
    # This requires more complex configuration and is typically done via ARM templates
    print_warning "Alert rules require additional configuration through Azure Portal or ARM templates"
    
    print_success "Alert infrastructure prepared"
}

# Function to create configuration files
create_configuration_files() {
    print_info "Creating load test configuration files"
    
    if $DRY_RUN; then
        print_info "[DRY RUN] Would create configuration files"
        return
    fi
    
    # Get application URL
    local app_url
    app_url=$(az containerapp show \
        --name "$CONTAINER_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.configuration.ingress.fqdn --output tsv)
    
    # Create JMeter test script
    cat > "${SCRIPT_DIR}/loadtest.jmx" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<jmeterTestPlan version="1.2" properties="5.0">
  <hashTree>
    <TestPlan guiclass="TestPlanGui" testclass="TestPlan" testname="Performance Test">
      <elementProp name="TestPlan.user_defined_variables" elementType="Arguments"/>
      <stringProp name="TestPlan.user_define_classpath"></stringProp>
    </TestPlan>
    <hashTree>
      <ThreadGroup guiclass="ThreadGroupGui" testclass="ThreadGroup" testname="Users">
        <intProp name="ThreadGroup.num_threads">50</intProp>
        <intProp name="ThreadGroup.ramp_time">30</intProp>
        <intProp name="ThreadGroup.duration">180</intProp>
      </ThreadGroup>
      <hashTree>
        <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="Home Page">
          <stringProp name="HTTPSampler.domain">${__P(webapp_url)}</stringProp>
          <stringProp name="HTTPSampler.protocol">https</stringProp>
          <stringProp name="HTTPSampler.path">/</stringProp>
          <stringProp name="HTTPSampler.method">GET</stringProp>
        </HTTPSamplerProxy>
      </hashTree>
    </hashTree>
  </hashTree>
</jmeterTestPlan>
EOF
    
    # Create test configuration YAML
    cat > "${SCRIPT_DIR}/loadtest-config.yaml" << EOF
version: v0.1
testId: performance-baseline
displayName: Performance Regression Test
testPlan: loadtest.jmx
description: Automated performance regression detection test
engineInstances: 1
configurationFiles:
properties:
  webapp_url: ${app_url}
failureCriteria:
  - aggregate: avg
    clientMetric: response_time_ms
    condition: '>'
    value: 500
  - aggregate: percentage
    clientMetric: error
    condition: '>'
    value: 5
EOF
    
    # Create Azure DevOps pipeline template
    cat > "${SCRIPT_DIR}/azure-pipelines.yml" << EOF
trigger:
  - main

pool:
  vmImage: 'ubuntu-latest'

variables:
  loadTestResource: '${LOAD_TEST_NAME}'
  loadTestResourceGroup: '${RESOURCE_GROUP}'
  webAppUrl: 'https://${app_url}'

stages:
- stage: LoadTest
  displayName: 'Performance Testing'
  jobs:
  - job: RunLoadTest
    displayName: 'Run Load Test'
    steps:
    - task: AzureLoadTest@1
      displayName: 'Azure Load Testing'
      inputs:
        azureSubscription: 'LoadTestConnection'
        loadTestConfigFile: 'loadtest-config.yaml'
        loadTestResource: \$(loadTestResource)
        resourceGroup: \$(loadTestResourceGroup)
        secrets: |
          [
          ]
        env: |
          [
            {
              "name": "webapp_url",
              "value": "\$(webAppUrl)"
            }
          ]

    - task: PublishTestResults@2
      condition: succeededOrFailed()
      inputs:
        testResultsFormat: 'JUnit'
        testResultsFiles: '\$(System.DefaultWorkingDirectory)/loadtest/results.xml'
        testRunTitle: 'Load Test Results'

    - publish: \$(System.DefaultWorkingDirectory)/loadtest
      artifact: LoadTestResults
      condition: succeededOrFailed()
EOF
    
    print_success "Configuration files created in: $SCRIPT_DIR"
}

# Function to display deployment summary
display_deployment_summary() {
    print_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo ""
    print_info "Resource Group: $RESOURCE_GROUP"
    print_info "Location: $LOCATION"
    print_info "Subscription: $SUBSCRIPTION_ID"
    echo ""
    print_info "Created Resources:"
    print_info "  • Load Testing: $LOAD_TEST_NAME"
    print_info "  • Container App: $CONTAINER_APP_NAME"
    print_info "  • Log Analytics: $WORKSPACE_NAME"
    print_info "  • Container Env: $ENVIRONMENT_NAME"
    print_info "  • Container Registry: $ACR_NAME"
    echo ""
    
    if ! $DRY_RUN; then
        local app_url
        app_url=$(az containerapp show \
            --name "$CONTAINER_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query properties.configuration.ingress.fqdn --output tsv 2>/dev/null || echo "Not available")
        print_info "Application URL: https://$app_url"
    fi
    
    echo ""
    print_info "Next Steps:"
    print_info "  1. Configure Azure DevOps pipeline using: ${SCRIPT_DIR}/azure-pipelines.yml"
    print_info "  2. Upload load test files to your DevOps repository"
    print_info "  3. Create workbook manually in Azure Portal using template"
    print_info "  4. Set up alert rules for regression detection"
    echo ""
    print_info "Log file: $LOG_FILE"
    print_info "Deployment state: $DEPLOYMENT_STATE_FILE"
    
    if ! $SKIP_CLEANUP_ON_ERROR; then
        echo ""
        print_warning "To clean up resources, run: $SCRIPT_DIR/destroy.sh --resource-group $RESOURCE_GROUP"
    fi
}

# Function to handle errors
handle_error() {
    local exit_code=$1
    print_error "Deployment failed with exit code: $exit_code"
    print_error "Check the log file for details: $LOG_FILE"
    
    if ! $SKIP_CLEANUP_ON_ERROR && [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        print_warning "Consider running cleanup: $SCRIPT_DIR/destroy.sh --resource-group $RESOURCE_GROUP"
    fi
    
    exit $exit_code
}

# Function to show usage
show_usage() {
    cat << EOF
Azure Performance Regression Detection - Deployment Script

Usage: $0 [OPTIONS]

Required Options:
  --resource-group NAME    Name of the Azure resource group to create

Optional Options:
  --location LOCATION      Azure region (default: eastus)
  --dry-run               Show what would be done without making changes
  --skip-cleanup-on-error Don't suggest cleanup on deployment failure
  --verbose               Enable verbose logging
  --help                  Show this help message

Examples:
  $0 --resource-group rg-perftest-demo
  $0 --resource-group rg-perftest-prod --location westus2
  $0 --resource-group rg-perftest-test --dry-run

For more information, see the recipe documentation.
EOF
}

# Main execution function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --location)
                LOCATION="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-cleanup-on-error)
                SKIP_CLEANUP_ON_ERROR=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set up error handling
    trap 'handle_error $?' ERR
    
    # Enable verbose logging if requested
    if $VERBOSE; then
        set -x
    fi
    
    print_info "Starting Azure Performance Regression Detection deployment"
    print_info "Log file: $LOG_FILE"
    
    if $DRY_RUN; then
        print_warning "DRY RUN MODE: No resources will be created"
    fi
    
    # Execute deployment steps
    check_prerequisites
    validate_parameters
    generate_resource_names
    save_deployment_state
    
    create_resource_group
    create_log_analytics_workspace
    create_load_testing_resource
    create_container_registry
    create_container_apps_environment
    deploy_sample_application
    create_performance_workbook
    create_alert_rules
    create_configuration_files
    
    display_deployment_summary
    
    print_success "Deployment completed successfully!"
}

# Execute main function with all arguments
main "$@"