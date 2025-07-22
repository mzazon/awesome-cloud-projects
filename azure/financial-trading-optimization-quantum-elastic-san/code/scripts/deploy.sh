#!/bin/bash
#
# Azure Quantum Trading Algorithm Deployment Script
# This script deploys the complete quantum-enhanced financial trading system
# including Azure Quantum, Azure Elastic SAN, and Azure Machine Learning
#
# Usage: ./deploy.sh [OPTIONS]
# Options:
#   -h, --help          Show this help message
#   -v, --verbose       Enable verbose output
#   -n, --no-confirm    Skip confirmation prompts
#   -s, --skip-quantum  Skip quantum workspace creation (for testing)
#   -t, --timeout       Set deployment timeout in minutes (default: 45)
#

set -euo pipefail

# Configuration defaults
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly DEPLOYMENT_TIMEOUT=45
readonly AZURE_REGIONS="eastus,westus2,southcentralus"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
VERBOSE=false
NO_CONFIRM=false
SKIP_QUANTUM=false
TIMEOUT=${DEPLOYMENT_TIMEOUT}

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${message}"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${message}"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}"
            ;;
        "DEBUG")
            if [[ "$VERBOSE" == true ]]; then
                echo -e "${BLUE}[DEBUG]${NC} ${message}"
            fi
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handler
error_handler() {
    local line_number="$1"
    local error_code="$2"
    local command="$3"
    
    log "ERROR" "Script failed at line $line_number with exit code $error_code"
    log "ERROR" "Failed command: $command"
    log "ERROR" "Check $LOG_FILE for detailed error information"
    
    # Offer cleanup option
    if [[ "$NO_CONFIRM" == false ]]; then
        echo -e "${YELLOW}Would you like to run cleanup? (y/N)${NC}"
        read -r cleanup_choice
        if [[ "$cleanup_choice" =~ ^[Yy]$ ]]; then
            log "INFO" "Running cleanup..."
            cleanup_resources
        fi
    fi
    
    exit "$error_code"
}

# Set up error handling
trap 'error_handler ${LINENO} $? "${BASH_COMMAND}"' ERR

# Usage function
usage() {
    cat << EOF
Azure Quantum Trading Algorithm Deployment Script

This script deploys a complete quantum-enhanced financial trading system using:
- Azure Quantum for portfolio optimization
- Azure Elastic SAN for ultra-high-performance storage
- Azure Machine Learning for hybrid algorithm orchestration
- Azure Monitor for comprehensive observability

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -n, --no-confirm    Skip confirmation prompts
    -s, --skip-quantum  Skip quantum workspace creation (for testing)
    -t, --timeout       Set deployment timeout in minutes (default: 45)

Examples:
    $0                  # Interactive deployment
    $0 -v -n            # Verbose, non-interactive deployment
    $0 -s               # Skip quantum workspace creation
    $0 -t 60            # Set 60-minute timeout

Requirements:
    - Azure CLI 2.50.0 or higher
    - Azure Quantum preview access
    - Contributor permissions on Azure subscription
    - Python 3.8+ with Azure SDK packages

Cost Estimate:
    - Daily operational cost: \$200-500
    - Storage: \$50-100/day (Elastic SAN)
    - Compute: \$100-300/day (ML and Quantum)
    - Networking: \$10-50/day

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -n|--no-confirm)
                NO_CONFIRM=true
                shift
                ;;
            -s|--skip-quantum)
                SKIP_QUANTUM=true
                shift
                ;;
            -t|--timeout)
                if [[ -n "${2:-}" ]]; then
                    TIMEOUT="$2"
                    shift 2
                else
                    log "ERROR" "Timeout value required"
                    exit 1
                fi
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking deployment prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log "ERROR" "Azure CLI not found. Please install Azure CLI 2.50.0 or higher"
        exit 1
    fi
    
    # Check Azure CLI version
    local cli_version
    cli_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0.0.0")
    log "DEBUG" "Azure CLI version: $cli_version"
    
    # Check login status
    if ! az account show &> /dev/null; then
        log "ERROR" "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    # Check subscription
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    local subscription_name
    subscription_name=$(az account show --query name --output tsv)
    log "INFO" "Using subscription: $subscription_name ($subscription_id)"
    
    # Check required extensions
    local required_extensions=("elastic-san" "quantum" "ml")
    for ext in "${required_extensions[@]}"; do
        if ! az extension show --name "$ext" &> /dev/null; then
            log "INFO" "Installing Azure CLI extension: $ext"
            az extension add --name "$ext" --yes
        fi
    done
    
    # Check for quantum preview access
    if [[ "$SKIP_QUANTUM" == false ]]; then
        log "INFO" "Checking Azure Quantum preview access..."
        if ! az provider show --namespace Microsoft.Quantum --query "registrationState" -o tsv | grep -q "Registered"; then
            log "WARN" "Azure Quantum provider not registered. This requires preview access."
            log "WARN" "Apply for preview access at: https://aka.ms/aq/preview"
            if [[ "$NO_CONFIRM" == false ]]; then
                echo -e "${YELLOW}Continue without quantum workspace? (y/N)${NC}"
                read -r skip_quantum
                if [[ "$skip_quantum" =~ ^[Yy]$ ]]; then
                    SKIP_QUANTUM=true
                else
                    log "ERROR" "Quantum preview access required for full deployment"
                    exit 1
                fi
            fi
        fi
    fi
    
    # Check available regions
    log "INFO" "Checking service availability in regions..."
    local available_regions
    available_regions=$(az account list-locations --query "[?metadata.regionType=='Physical'].name" -o tsv)
    log "DEBUG" "Available regions: $available_regions"
    
    log "INFO" "Prerequisites check completed successfully"
}

# Generate unique resource names
generate_resource_names() {
    log "INFO" "Generating unique resource names..."
    
    # Generate random suffix
    local random_suffix
    random_suffix=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Export environment variables for resource names
    export RESOURCE_GROUP="rg-quantum-trading-${random_suffix}"
    export LOCATION="eastus"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export ELASTIC_SAN_NAME="esan-trading-${random_suffix}"
    export ML_WORKSPACE_NAME="mlws-quantum-trading-${random_suffix}"
    export QUANTUM_WORKSPACE_NAME="quantum-trading-${random_suffix}"
    export STORAGE_ACCOUNT_NAME="stquantum${random_suffix}"
    export MONITOR_WORKSPACE_NAME="monitor-quantum-${random_suffix}"
    export EVENTHUB_NAMESPACE="eh-market-${random_suffix}"
    export DATAFACTORY_NAME="df-market-data-${random_suffix}"
    export STREAM_ANALYTICS_NAME="sa-quantum-trading-${random_suffix}"
    export APPLICATION_INSIGHTS_NAME="ai-quantum-trading-${random_suffix}"
    
    log "INFO" "Resource names generated with suffix: $random_suffix"
    log "DEBUG" "Resource group: $RESOURCE_GROUP"
    log "DEBUG" "Location: $LOCATION"
}

# Create resource group
create_resource_group() {
    log "INFO" "Creating resource group: $RESOURCE_GROUP"
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=quantum-trading environment=production deployment=automated \
        --output none
    
    log "INFO" "Resource group created successfully"
}

# Deploy Azure Elastic SAN
deploy_elastic_san() {
    log "INFO" "Deploying Azure Elastic SAN for ultra-high-performance storage..."
    
    # Create Elastic SAN
    az elastic-san create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ELASTIC_SAN_NAME" \
        --location "$LOCATION" \
        --base-size-tib 10 \
        --extended-capacity-size-tib 5 \
        --sku Premium_LRS \
        --tags workload=trading performance=ultra-high \
        --output none
    
    log "INFO" "Creating volume group for market data..."
    
    # Create volume group
    az elastic-san volume-group create \
        --resource-group "$RESOURCE_GROUP" \
        --elastic-san-name "$ELASTIC_SAN_NAME" \
        --name "vg-market-data" \
        --output none
    
    # Create volume for real-time data
    az elastic-san volume create \
        --resource-group "$RESOURCE_GROUP" \
        --elastic-san-name "$ELASTIC_SAN_NAME" \
        --volume-group-name "vg-market-data" \
        --name "vol-realtime-data" \
        --size-gib 1000 \
        --output none
    
    log "INFO" "Azure Elastic SAN deployed successfully"
}

# Deploy Azure Quantum workspace
deploy_quantum_workspace() {
    if [[ "$SKIP_QUANTUM" == true ]]; then
        log "INFO" "Skipping quantum workspace deployment as requested"
        return 0
    fi
    
    log "INFO" "Deploying Azure Quantum workspace..."
    
    # Create storage account for quantum workspace
    az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false \
        --output none
    
    # Create quantum workspace
    az quantum workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$QUANTUM_WORKSPACE_NAME" \
        --location "$LOCATION" \
        --storage-account "$STORAGE_ACCOUNT_NAME" \
        --output none
    
    log "INFO" "Adding quantum optimization providers..."
    
    # Add Microsoft quantum provider
    az quantum workspace provider add \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$QUANTUM_WORKSPACE_NAME" \
        --provider-id "microsoft" \
        --provider-sku "DZI" \
        --output none
    
    # Add IonQ provider (if available)
    if az quantum workspace provider add \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$QUANTUM_WORKSPACE_NAME" \
        --provider-id "ionq" \
        --provider-sku "pay-as-you-go-cred" \
        --output none 2>/dev/null; then
        log "INFO" "IonQ quantum provider added successfully"
    else
        log "WARN" "IonQ provider not available, using Microsoft provider only"
    fi
    
    log "INFO" "Azure Quantum workspace deployed successfully"
}

# Deploy Azure Machine Learning workspace
deploy_ml_workspace() {
    log "INFO" "Deploying Azure Machine Learning workspace..."
    
    # Create ML workspace
    az ml workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ML_WORKSPACE_NAME" \
        --location "$LOCATION" \
        --storage-account "$STORAGE_ACCOUNT_NAME" \
        --output none
    
    log "INFO" "Creating compute cluster for hybrid algorithms..."
    
    # Create compute cluster
    az ml compute create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$ML_WORKSPACE_NAME" \
        --name "quantum-compute-cluster" \
        --type AmlCompute \
        --min-instances 0 \
        --max-instances 10 \
        --size Standard_DS3_v2 \
        --output none
    
    log "INFO" "Azure Machine Learning workspace deployed successfully"
}

# Deploy real-time data processing pipeline
deploy_data_pipeline() {
    log "INFO" "Deploying real-time market data processing pipeline..."
    
    # Create Data Factory
    az datafactory create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DATAFACTORY_NAME" \
        --location "$LOCATION" \
        --output none
    
    # Create Event Hub namespace
    az eventhubs namespace create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$EVENTHUB_NAMESPACE" \
        --location "$LOCATION" \
        --sku Standard \
        --output none
    
    # Create Event Hub
    az eventhubs eventhub create \
        --resource-group "$RESOURCE_GROUP" \
        --namespace-name "$EVENTHUB_NAMESPACE" \
        --name "market-data-stream" \
        --partition-count 4 \
        --message-retention 7 \
        --output none
    
    # Create Stream Analytics job
    az stream-analytics job create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STREAM_ANALYTICS_NAME" \
        --location "$LOCATION" \
        --output none
    
    log "INFO" "Real-time data processing pipeline deployed successfully"
}

# Deploy monitoring and observability
deploy_monitoring() {
    log "INFO" "Deploying monitoring and observability components..."
    
    # Create Log Analytics workspace
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$MONITOR_WORKSPACE_NAME" \
        --location "$LOCATION" \
        --output none
    
    # Create Application Insights
    az monitor app-insights component create \
        --resource-group "$RESOURCE_GROUP" \
        --app "$APPLICATION_INSIGHTS_NAME" \
        --location "$LOCATION" \
        --kind web \
        --workspace "$MONITOR_WORKSPACE_NAME" \
        --output none
    
    # Create metrics alert for quantum optimization latency
    az monitor metrics alert create \
        --resource-group "$RESOURCE_GROUP" \
        --name "quantum-optimization-latency" \
        --description "Alert when quantum optimization exceeds latency threshold" \
        --condition "avg Platform.QuantumJobDuration > 5000" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --output none 2>/dev/null || log "WARN" "Quantum metrics alert creation skipped (requires active quantum jobs)"
    
    log "INFO" "Monitoring and observability deployed successfully"
}

# Validate deployment
validate_deployment() {
    log "INFO" "Validating deployment..."
    
    local validation_errors=0
    
    # Check resource group
    if ! az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null; then
        log "ERROR" "Resource group validation failed"
        ((validation_errors++))
    fi
    
    # Check Elastic SAN
    if ! az elastic-san show --resource-group "$RESOURCE_GROUP" --name "$ELASTIC_SAN_NAME" --output none 2>/dev/null; then
        log "ERROR" "Elastic SAN validation failed"
        ((validation_errors++))
    fi
    
    # Check ML workspace
    if ! az ml workspace show --resource-group "$RESOURCE_GROUP" --name "$ML_WORKSPACE_NAME" --output none 2>/dev/null; then
        log "ERROR" "Machine Learning workspace validation failed"
        ((validation_errors++))
    fi
    
    # Check quantum workspace (if not skipped)
    if [[ "$SKIP_QUANTUM" == false ]]; then
        if ! az quantum workspace show --resource-group "$RESOURCE_GROUP" --name "$QUANTUM_WORKSPACE_NAME" --output none 2>/dev/null; then
            log "ERROR" "Quantum workspace validation failed"
            ((validation_errors++))
        fi
    fi
    
    # Check Event Hub
    if ! az eventhubs namespace show --resource-group "$RESOURCE_GROUP" --name "$EVENTHUB_NAMESPACE" --output none 2>/dev/null; then
        log "ERROR" "Event Hub namespace validation failed"
        ((validation_errors++))
    fi
    
    # Check Application Insights
    if ! az monitor app-insights component show --resource-group "$RESOURCE_GROUP" --app "$APPLICATION_INSIGHTS_NAME" --output none 2>/dev/null; then
        log "ERROR" "Application Insights validation failed"
        ((validation_errors++))
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        log "INFO" "Deployment validation successful"
        return 0
    else
        log "ERROR" "Deployment validation failed with $validation_errors errors"
        return 1
    fi
}

# Show deployment summary
show_deployment_summary() {
    log "INFO" "Deployment Summary"
    echo "===================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Subscription ID: $SUBSCRIPTION_ID"
    echo ""
    echo "Deployed Resources:"
    echo "- Azure Elastic SAN: $ELASTIC_SAN_NAME"
    echo "- Machine Learning Workspace: $ML_WORKSPACE_NAME"
    if [[ "$SKIP_QUANTUM" == false ]]; then
        echo "- Quantum Workspace: $QUANTUM_WORKSPACE_NAME"
    fi
    echo "- Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "- Event Hub Namespace: $EVENTHUB_NAMESPACE"
    echo "- Data Factory: $DATAFACTORY_NAME"
    echo "- Stream Analytics: $STREAM_ANALYTICS_NAME"
    echo "- Application Insights: $APPLICATION_INSIGHTS_NAME"
    echo "- Log Analytics: $MONITOR_WORKSPACE_NAME"
    echo ""
    echo "Next Steps:"
    echo "1. Configure market data feeds in Event Hub"
    echo "2. Deploy quantum optimization algorithms to ML workspace"
    echo "3. Set up real-time dashboards in Application Insights"
    echo "4. Configure trading algorithm parameters"
    echo ""
    echo "Important:"
    echo "- Monitor costs closely - this solution can be expensive"
    echo "- Test quantum algorithms on simulators before using hardware"
    echo "- Review security settings before production deployment"
    echo ""
    echo "For cleanup, run: ./destroy.sh"
}

# Cleanup resources (for error handling)
cleanup_resources() {
    log "INFO" "Cleaning up resources..."
    
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait 2>/dev/null || true
        log "INFO" "Resource group deletion initiated: $RESOURCE_GROUP"
    fi
}

# Main deployment function
main() {
    log "INFO" "Starting Azure Quantum Trading Algorithm deployment"
    log "INFO" "Log file: $LOG_FILE"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Generate resource names
    generate_resource_names
    
    # Confirm deployment
    if [[ "$NO_CONFIRM" == false ]]; then
        echo -e "${YELLOW}This will deploy a quantum-enhanced trading system to Azure.${NC}"
        echo -e "${YELLOW}Estimated daily cost: \$200-500${NC}"
        echo -e "${YELLOW}Resource group: $RESOURCE_GROUP${NC}"
        echo -e "${YELLOW}Location: $LOCATION${NC}"
        echo ""
        echo -e "${YELLOW}Do you want to proceed? (y/N)${NC}"
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log "INFO" "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Start deployment timer
    local start_time=$(date +%s)
    
    # Deploy components
    create_resource_group
    deploy_elastic_san
    deploy_quantum_workspace
    deploy_ml_workspace
    deploy_data_pipeline
    deploy_monitoring
    
    # Validate deployment
    if ! validate_deployment; then
        log "ERROR" "Deployment validation failed"
        exit 1
    fi
    
    # Calculate deployment time
    local end_time=$(date +%s)
    local deployment_time=$((end_time - start_time))
    
    log "INFO" "Deployment completed successfully in ${deployment_time} seconds"
    
    # Show summary
    show_deployment_summary
    
    log "INFO" "Deployment script completed successfully"
}

# Run main function with all arguments
main "$@"