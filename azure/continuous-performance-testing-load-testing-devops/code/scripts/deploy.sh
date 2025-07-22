#!/bin/bash

# =============================================================================
# Azure Load Testing with Azure DevOps - Deployment Script
# =============================================================================
# This script deploys the complete infrastructure for automating performance
# testing with Azure Load Testing integrated into Azure DevOps CI/CD pipelines.
#
# Prerequisites:
# - Azure CLI installed and configured
# - Appropriate Azure subscription permissions
# - Azure DevOps organization (for service connection setup)
# =============================================================================

set -euo pipefail

# =============================================================================
# Script Configuration
# =============================================================================

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default configuration values
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/azure-loadtest-deploy-$(date +%Y%m%d-%H%M%S).log"

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC}  $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC}  $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

error_exit() {
    log ERROR "$1"
    log ERROR "Deployment failed. Check the log file: $LOG_FILE"
    exit 1
}

check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install Azure CLI and try again."
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' and try again."
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        log WARN "openssl not found. Using alternative method for random string generation."
        RANDOM_SUFFIX=$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 6)
    else
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi
    
    log INFO "Prerequisites check completed successfully"
}

validate_configuration() {
    log INFO "Validating configuration..."
    
    # Validate resource group name
    if [[ ! "$RESOURCE_GROUP" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        error_exit "Invalid resource group name: $RESOURCE_GROUP"
    fi
    
    # Validate location
    if ! az account list-locations --query "[?name=='$LOCATION'].name" -o tsv | grep -q "$LOCATION"; then
        error_exit "Invalid Azure location: $LOCATION"
    fi
    
    # Validate target app URL format if provided
    if [[ -n "$TARGET_APP_URL" && ! "$TARGET_APP_URL" =~ ^https?:// ]]; then
        error_exit "Invalid target application URL format: $TARGET_APP_URL"
    fi
    
    log INFO "Configuration validation completed successfully"
}

create_resource_group() {
    log INFO "Creating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Resource group $RESOURCE_GROUP already exists. Continuing with existing group."
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=performance-testing environment=demo deployment-script="$SCRIPT_NAME" \
            || error_exit "Failed to create resource group"
        
        log INFO "Resource group created successfully"
    fi
}

create_application_insights() {
    log INFO "Creating Application Insights: $APP_INSIGHTS_NAME"
    
    # Check if Application Insights already exists
    if az monitor app-insights component show --app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Application Insights $APP_INSIGHTS_NAME already exists. Skipping creation."
    else
        az monitor app-insights component create \
            --app "$APP_INSIGHTS_NAME" \
            --location "$LOCATION" \
            --resource-group "$RESOURCE_GROUP" \
            --application-type web \
            --tags purpose=performance-monitoring environment=demo \
            || error_exit "Failed to create Application Insights"
        
        log INFO "Application Insights created successfully"
    fi
    
    # Get connection string
    AI_CONNECTION_STRING=$(az monitor app-insights component show \
        --app "$APP_INSIGHTS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString \
        --output tsv) || error_exit "Failed to get Application Insights connection string"
    
    log INFO "Application Insights connection string retrieved"
}

create_load_testing_resource() {
    log INFO "Creating Azure Load Testing resource: $LOAD_TEST_NAME"
    
    # Check if Load Testing resource already exists
    if az load show --name "$LOAD_TEST_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Load Testing resource $LOAD_TEST_NAME already exists. Skipping creation."
    else
        az load create \
            --name "$LOAD_TEST_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags environment=demo purpose=cicd deployment-script="$SCRIPT_NAME" \
            || error_exit "Failed to create Azure Load Testing resource"
        
        log INFO "Azure Load Testing resource created successfully"
    fi
    
    # Get Load Testing resource ID
    LOAD_TEST_ID=$(az load show \
        --name "$LOAD_TEST_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query id \
        --output tsv) || error_exit "Failed to get Load Testing resource ID"
    
    log INFO "Load Testing resource ID: $LOAD_TEST_ID"
}

create_service_principal() {
    log INFO "Creating service principal for Azure DevOps integration"
    
    local sp_name="sp-loadtest-devops-${RANDOM_SUFFIX}"
    
    # Check if service principal already exists
    if az ad sp list --display-name "$sp_name" --query "[0].appId" -o tsv | grep -q "."; then
        log WARN "Service principal $sp_name already exists. Retrieving existing configuration."
        SP_APP_ID=$(az ad sp list --display-name "$sp_name" --query "[0].appId" -o tsv)
        log INFO "Existing service principal app ID: $SP_APP_ID"
        log WARN "Note: You'll need to create a new client secret in Azure Portal for Azure DevOps"
    else
        # Create service principal with Load Test Contributor role
        SP_OUTPUT=$(az ad sp create-for-rbac \
            --name "$sp_name" \
            --role "Load Test Contributor" \
            --scopes "$LOAD_TEST_ID" \
            --json-auth) || error_exit "Failed to create service principal"
        
        SP_APP_ID=$(echo "$SP_OUTPUT" | jq -r '.clientId')
        
        log INFO "Service principal created successfully"
        log INFO "Service principal app ID: $SP_APP_ID"
        
        # Save service connection details to file
        local sp_file="$SCRIPT_DIR/service-principal-config.json"
        echo "$SP_OUTPUT" > "$sp_file"
        log INFO "Service principal configuration saved to: $sp_file"
        log WARN "Keep this file secure and use it to configure Azure DevOps service connection"
    fi
}

create_action_group() {
    log INFO "Creating action group for performance alerts"
    
    local action_group_name="ag-perftest-alerts"
    
    # Check if action group already exists
    if az monitor action-group show --name "$action_group_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Action group $action_group_name already exists. Skipping creation."
    else
        # Use a placeholder email for demo purposes
        local demo_email="devops-team@example.com"
        
        az monitor action-group create \
            --name "$action_group_name" \
            --resource-group "$RESOURCE_GROUP" \
            --short-name "PerfAlerts" \
            --email-receiver \
                name="DevOpsTeam" \
                email="$demo_email" \
                use-common-alert-schema=true \
            || error_exit "Failed to create action group"
        
        log INFO "Action group created successfully"
        log WARN "Update the email address in action group '$action_group_name' with your actual team email"
    fi
}

create_performance_alerts() {
    log INFO "Creating performance monitoring alerts"
    
    local action_group_name="ag-perftest-alerts"
    
    # Create alert for high response time
    local response_time_alert="alert-high-response-time"
    if az monitor metrics alert show --name "$response_time_alert" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Response time alert already exists. Skipping creation."
    else
        az monitor metrics alert create \
            --name "$response_time_alert" \
            --resource-group "$RESOURCE_GROUP" \
            --scopes "$LOAD_TEST_ID" \
            --condition "avg response_time_ms > 1000" \
            --window-size 5m \
            --evaluation-frequency 1m \
            --action "$action_group_name" \
            --description "Alert when average response time exceeds 1 second" \
            || error_exit "Failed to create response time alert"
        
        log INFO "Response time alert created successfully"
    fi
    
    # Create alert for high error rate
    local error_rate_alert="alert-high-error-rate"
    if az monitor metrics alert show --name "$error_rate_alert" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Error rate alert already exists. Skipping creation."
    else
        az monitor metrics alert create \
            --name "$error_rate_alert" \
            --resource-group "$RESOURCE_GROUP" \
            --scopes "$LOAD_TEST_ID" \
            --condition "avg error_percentage > 5" \
            --window-size 5m \
            --evaluation-frequency 1m \
            --action "$action_group_name" \
            --description "Alert when error rate exceeds 5%" \
            || error_exit "Failed to create error rate alert"
        
        log INFO "Error rate alert created successfully"
    fi
}

create_test_scripts() {
    log INFO "Creating sample JMeter test scripts and configuration"
    
    local scripts_dir="$SCRIPT_DIR/../loadtest-scripts"
    mkdir -p "$scripts_dir"
    
    # Create JMeter test script
    cat > "$scripts_dir/performance-test.jmx" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<jmeterTestPlan version="1.2" properties="5.0">
  <hashTree>
    <TestPlan guiclass="TestPlanGui" testclass="TestPlan" testname="API Performance Test" enabled="true">
      <stringProp name="TestPlan.comments">Performance test for web application</stringProp>
      <boolProp name="TestPlan.functional_mode">false</boolProp>
      <boolProp name="TestPlan.tearDown_on_shutdown">true</boolProp>
      <boolProp name="TestPlan.serialize_threadgroups">false</boolProp>
      <elementProp name="TestPlan.user_defined_variables" elementType="Arguments" guiclass="ArgumentsPanel" testclass="Arguments" testname="User Defined Variables" enabled="true">
        <collectionProp name="Arguments.arguments">
          <elementProp name="HOST" elementType="Argument">
            <stringProp name="Argument.name">HOST</stringProp>
            <stringProp name="Argument.value">${__P(host,example.com)}</stringProp>
            <stringProp name="Argument.metadata">=</stringProp>
          </elementProp>
          <elementProp name="PROTOCOL" elementType="Argument">
            <stringProp name="Argument.name">PROTOCOL</stringProp>
            <stringProp name="Argument.value">${__P(protocol,https)}</stringProp>
            <stringProp name="Argument.metadata">=</stringProp>
          </elementProp>
        </collectionProp>
      </elementProp>
      <stringProp name="TestPlan.user_define_classpath"></stringProp>
    </TestPlan>
    <hashTree>
      <ThreadGroup guiclass="ThreadGroupGui" testclass="ThreadGroup" testname="Load Test Users" enabled="true">
        <stringProp name="ThreadGroup.on_sample_error">continue</stringProp>
        <elementProp name="ThreadGroup.main_controller" elementType="LoopController" guiclass="LoopControlGui" testclass="LoopController" testname="Loop Controller" enabled="true">
          <boolProp name="LoopController.continue_forever">false</boolProp>
          <stringProp name="LoopController.loops">1</stringProp>
        </elementProp>
        <stringProp name="ThreadGroup.num_threads">50</stringProp>
        <stringProp name="ThreadGroup.ramp_time">30</stringProp>
        <stringProp name="ThreadGroup.duration">180</stringProp>
        <stringProp name="ThreadGroup.delay"></stringProp>
        <boolProp name="ThreadGroup.scheduler">true</boolProp>
      </ThreadGroup>
      <hashTree>
        <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="GET Homepage" enabled="true">
          <elementProp name="HTTPsampler.Arguments" elementType="Arguments" guiclass="HTTPArgumentsPanel" testclass="Arguments" testname="User Defined Variables" enabled="true">
            <collectionProp name="Arguments.arguments"/>
          </elementProp>
          <stringProp name="HTTPSampler.domain">${HOST}</stringProp>
          <stringProp name="HTTPSampler.port"></stringProp>
          <stringProp name="HTTPSampler.protocol">${PROTOCOL}</stringProp>
          <stringProp name="HTTPSampler.contentEncoding"></stringProp>
          <stringProp name="HTTPSampler.path">/</stringProp>
          <stringProp name="HTTPSampler.method">GET</stringProp>
          <boolProp name="HTTPSampler.follow_redirects">true</boolProp>
          <boolProp name="HTTPSampler.auto_redirects">false</boolProp>
          <boolProp name="HTTPSampler.use_keepalive">true</boolProp>
          <boolProp name="HTTPSampler.DO_MULTIPART_POST">false</boolProp>
          <stringProp name="HTTPSampler.embedded_url_re"></stringProp>
          <stringProp name="HTTPSampler.connect_timeout"></stringProp>
          <stringProp name="HTTPSampler.response_timeout"></stringProp>
        </HTTPSamplerProxy>
        <hashTree>
          <ResponseAssertion guiclass="AssertionGui" testclass="ResponseAssertion" testname="Response Assertion" enabled="true">
            <collectionProp name="Asserion.test_strings">
              <stringProp name="1420792847">200</stringProp>
            </collectionProp>
            <stringProp name="Assertion.custom_message"></stringProp>
            <stringProp name="Assertion.test_field">Assertion.response_code</stringProp>
            <boolProp name="Assertion.assume_success">false</boolProp>
            <intProp name="Assertion.test_type">1</intProp>
          </ResponseAssertion>
          <hashTree/>
        </hashTree>
      </hashTree>
    </hashTree>
  </hashTree>
</jmeterTestPlan>
EOF
    
    # Create load test configuration
    cat > "$scripts_dir/loadtest-config.yaml" << EOF
version: v0.1
testId: performance-baseline
displayName: API Performance Baseline Test
testPlan: performance-test.jmx
description: Validates API performance meets SLA requirements
engineInstances: 1

configurationFiles:
- performance-test.jmx

failureCriteria:
- avg(response_time_ms) > 1000
- percentage(error) > 5
- avg(requests_per_sec) < 100

env:
- name: host
  value: ${TARGET_APP_URL:-example.com}
- name: protocol
  value: https

autoStop:
  errorPercentage: 90
  timeWindow: 60
EOF
    
    # Create Azure DevOps pipeline YAML
    cat > "$scripts_dir/azure-pipelines.yml" << 'EOF'
trigger:
- main

pool:
  vmImage: 'ubuntu-latest'

variables:
  loadTestResource: 'alt-perftest-demo'
  loadTestResourceGroup: 'rg-loadtest-devops'

stages:
- stage: Build
  jobs:
  - job: BuildApplication
    steps:
    - task: UseDotNet@2
      inputs:
        packageType: 'sdk'
        version: '8.x'
    
    - script: |
        echo "Building application..."
        # Add your build commands here
      displayName: 'Build Application'
    
    - publish: $(System.DefaultWorkingDirectory)
      artifact: drop

- stage: PerformanceTest
  dependsOn: Build
  jobs:
  - job: RunLoadTest
    steps:
    - checkout: self
    
    - task: AzureCLI@2
      displayName: 'Execute Load Test'
      inputs:
        azureSubscription: 'Azure-Service-Connection'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          # Create test run
          TEST_RUN_ID=$(az load test create \
              --test-id "performance-baseline" \
              --load-test-resource $(loadTestResource) \
              --resource-group $(loadTestResourceGroup) \
              --test-plan "./loadtest-scripts/performance-test.jmx" \
              --load-test-config-file "./loadtest-scripts/loadtest-config.yaml" \
              --display-name "Pipeline Run - $(Build.BuildId)" \
              --description "Automated test from pipeline" \
              --query testRunId \
              --output tsv)
          
          echo "Test run created: $TEST_RUN_ID"
          
          # Wait for test completion
          az load test-run wait \
              --test-run-id $TEST_RUN_ID \
              --load-test-resource $(loadTestResource) \
              --resource-group $(loadTestResourceGroup)
          
          # Get test results
          az load test-run metrics \
              --test-run-id $TEST_RUN_ID \
              --load-test-resource $(loadTestResource) \
              --resource-group $(loadTestResourceGroup) \
              --metric-namespace LoadTestRunMetrics

    - task: PublishTestResults@2
      displayName: 'Publish Load Test Results'
      inputs:
        testResultsFormat: 'JUnit'
        testResultsFiles: '**/loadtest-results.xml'
        failTaskOnFailedTests: true
EOF
    
    log INFO "Sample test scripts and configuration files created in: $scripts_dir"
    log INFO "Files created:"
    log INFO "  - performance-test.jmx (JMeter test script)"
    log INFO "  - loadtest-config.yaml (Load test configuration)"
    log INFO "  - azure-pipelines.yml (Azure DevOps pipeline template)"
}

display_deployment_summary() {
    log INFO "=== DEPLOYMENT SUMMARY ==="
    log INFO "Resource Group: $RESOURCE_GROUP"
    log INFO "Location: $LOCATION"
    log INFO "Load Testing Resource: $LOAD_TEST_NAME"
    log INFO "Application Insights: $APP_INSIGHTS_NAME"
    log INFO "Service Principal App ID: ${SP_APP_ID:-Not created}"
    log INFO ""
    log INFO "=== NEXT STEPS ==="
    log INFO "1. Configure Azure DevOps service connection using the service principal"
    log INFO "2. Update the action group email address for alert notifications"
    log INFO "3. Customize the JMeter test script for your application"
    log INFO "4. Update the target application URL in loadtest-config.yaml"
    log INFO "5. Import the Azure DevOps pipeline YAML into your project"
    log INFO ""
    log INFO "=== FILES CREATED ==="
    log INFO "- Service principal config: $SCRIPT_DIR/service-principal-config.json"
    log INFO "- Test scripts directory: $SCRIPT_DIR/../loadtest-scripts/"
    log INFO ""
    log INFO "Deployment completed successfully!"
    log INFO "Log file: $LOG_FILE"
}

show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Deploy Azure Load Testing with Azure DevOps integration infrastructure.

OPTIONS:
    -g, --resource-group NAME    Resource group name (default: rg-loadtest-devops)
    -l, --location LOCATION      Azure region (default: eastus)
    -n, --load-test-name NAME    Load testing resource name (default: alt-perftest-demo)
    -i, --app-insights NAME      Application Insights name (default: ai-perftest-demo)
    -u, --target-url URL         Target application URL for testing
    -h, --help                   Show this help message
    -v, --verbose                Enable verbose logging
    --dry-run                    Show what would be deployed without making changes

EXAMPLES:
    $SCRIPT_NAME
    $SCRIPT_NAME -g my-resource-group -l westus2
    $SCRIPT_NAME --target-url https://myapp.azurewebsites.net
    $SCRIPT_NAME --dry-run

EOF
}

# =============================================================================
# Main Script Execution
# =============================================================================

main() {
    # Default configuration
    RESOURCE_GROUP="rg-loadtest-devops"
    LOCATION="eastus"
    LOAD_TEST_NAME="alt-perftest-demo"
    APP_INSIGHTS_NAME="ai-perftest-demo"
    TARGET_APP_URL=""
    VERBOSE=false
    DRY_RUN=false
    
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
            -n|--load-test-name)
                LOAD_TEST_NAME="$2"
                shift 2
                ;;
            -i|--app-insights)
                APP_INSIGHTS_NAME="$2"
                shift 2
                ;;
            -u|--target-url)
                TARGET_APP_URL="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Start deployment
    log INFO "Starting Azure Load Testing deployment..."
    log INFO "Script: $SCRIPT_NAME"
    log INFO "Log file: $LOG_FILE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "DRY RUN MODE - No resources will be created"
        log INFO "Configuration:"
        log INFO "  Resource Group: $RESOURCE_GROUP"
        log INFO "  Location: $LOCATION"
        log INFO "  Load Test Name: $LOAD_TEST_NAME"
        log INFO "  App Insights: $APP_INSIGHTS_NAME"
        log INFO "  Target URL: ${TARGET_APP_URL:-Not specified}"
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    validate_configuration
    create_resource_group
    create_application_insights
    create_load_testing_resource
    create_service_principal
    create_action_group
    create_performance_alerts
    create_test_scripts
    display_deployment_summary
}

# Execute main function with all arguments
main "$@"