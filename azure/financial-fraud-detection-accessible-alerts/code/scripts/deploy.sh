#!/bin/bash

# =============================================================================
# Azure Fraud Detection Deployment Script
# Recipe: Implementing Intelligent Financial Fraud Detection with Azure AI 
#         Metrics Advisor and Azure AI Immersive Reader
# =============================================================================

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deploy-config"

# Default values
DEFAULT_LOCATION="eastus"
DEFAULT_ENVIRONMENT="demo"

# =============================================================================
# Logging Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# =============================================================================
# Utility Functions
# =============================================================================

print_banner() {
    echo -e "${BLUE}"
    echo "=============================================================="
    echo "Azure Fraud Detection Deployment Script"
    echo "=============================================================="
    echo -e "${NC}"
}

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -l, --location LOCATION     Azure region (default: $DEFAULT_LOCATION)"
    echo "  -e, --environment ENV       Environment name (default: $DEFAULT_ENVIRONMENT)"
    echo "  -s, --suffix SUFFIX         Resource suffix (default: random)"
    echo "  -f, --force                 Force deployment (skip confirmations)"
    echo "  --dry-run                   Show what would be deployed without creating resources"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                          # Deploy with default settings"
    echo "  $0 -l westus2 -e prod      # Deploy to West US 2 for production"
    echo "  $0 --dry-run               # Preview deployment without creating resources"
}

generate_random_suffix() {
    openssl rand -hex 3 2>/dev/null || printf "%06x" $((RANDOM * RANDOM))
}

validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --output tsv --query '"azure-cli"')
    log_info "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if subscription is set
    local subscription_id=$(az account show --query id --output tsv)
    local subscription_name=$(az account show --query name --output tsv)
    log_info "Using subscription: $subscription_name ($subscription_id)"
    
    # Check if openssl is available for generating random values
    if ! command -v openssl &> /dev/null; then
        log_warning "openssl not found. Using alternative random generation."
    fi
    
    log_success "Prerequisites validated"
}

check_resource_providers() {
    log_info "Checking required resource providers..."
    
    local providers=("Microsoft.CognitiveServices" "Microsoft.Logic" "Microsoft.Storage" "Microsoft.Insights")
    
    for provider in "${providers[@]}"; do
        local state=$(az provider show --namespace "$provider" --query registrationState --output tsv)
        if [[ "$state" != "Registered" ]]; then
            log_info "Registering provider: $provider"
            az provider register --namespace "$provider"
        else
            log_info "Provider $provider is already registered"
        fi
    done
    
    log_success "Resource providers checked"
}

# =============================================================================
# Configuration Management
# =============================================================================

save_config() {
    cat > "$CONFIG_FILE" << EOF
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
ENVIRONMENT=$ENVIRONMENT
RANDOM_SUFFIX=$RANDOM_SUFFIX
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
METRICS_ADVISOR_NAME=$METRICS_ADVISOR_NAME
IMMERSIVE_READER_NAME=$IMMERSIVE_READER_NAME
LOGIC_APP_NAME=$LOGIC_APP_NAME
STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT_NAME
WORKSPACE_NAME=$WORKSPACE_NAME
DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    log_info "Configuration saved to $CONFIG_FILE"
}

# =============================================================================
# Resource Creation Functions
# =============================================================================

create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create resource group: $RESOURCE_GROUP in $LOCATION"
        return 0
    fi
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=fraud-detection environment="$ENVIRONMENT" \
            --output none
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

create_storage_account() {
    log_info "Creating storage account: $STORAGE_ACCOUNT_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create storage account: $STORAGE_ACCOUNT_NAME"
        return 0
    fi
    
    if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Storage account $STORAGE_ACCOUNT_NAME already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --https-only true \
            --min-tls-version TLS1_2 \
            --output none
        log_success "Storage account created: $STORAGE_ACCOUNT_NAME"
    fi
    
    # Create containers
    log_info "Creating storage containers..."
    local containers=("transaction-data" "fraud-alerts")
    
    for container in "${containers[@]}"; do
        if ! az storage container show --name "$container" --account-name "$STORAGE_ACCOUNT_NAME" &> /dev/null; then
            az storage container create \
                --name "$container" \
                --account-name "$STORAGE_ACCOUNT_NAME" \
                --public-access off \
                --output none
            log_success "Container created: $container"
        else
            log_warning "Container $container already exists"
        fi
    done
}

create_cognitive_services() {
    log_info "Creating Azure AI Metrics Advisor: $METRICS_ADVISOR_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Metrics Advisor: $METRICS_ADVISOR_NAME"
        log_info "[DRY RUN] Would create Immersive Reader: $IMMERSIVE_READER_NAME"
        return 0
    fi
    
    # Create Metrics Advisor
    if az cognitiveservices account show --name "$METRICS_ADVISOR_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Metrics Advisor $METRICS_ADVISOR_NAME already exists"
    else
        az cognitiveservices account create \
            --name "$METRICS_ADVISOR_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --kind MetricsAdvisor \
            --sku F0 \
            --custom-domain "$METRICS_ADVISOR_NAME" \
            --output none
        log_success "Metrics Advisor created: $METRICS_ADVISOR_NAME"
    fi
    
    # Create Immersive Reader
    log_info "Creating Azure AI Immersive Reader: $IMMERSIVE_READER_NAME"
    
    if az cognitiveservices account show --name "$IMMERSIVE_READER_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Immersive Reader $IMMERSIVE_READER_NAME already exists"
    else
        az cognitiveservices account create \
            --name "$IMMERSIVE_READER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --kind ImmersiveReader \
            --sku F0 \
            --custom-domain "$IMMERSIVE_READER_NAME" \
            --output none
        log_success "Immersive Reader created: $IMMERSIVE_READER_NAME"
    fi
}

create_logic_app() {
    log_info "Creating Logic App: $LOGIC_APP_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Logic App: $LOGIC_APP_NAME"
        return 0
    fi
    
    if az logic workflow show --name "$LOGIC_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Logic App $LOGIC_APP_NAME already exists"
    else
        # Create basic Logic App workflow
        local workflow_definition=$(cat << 'EOF'
{
  "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {},
  "triggers": {
    "manual": {
      "type": "Request",
      "kind": "Http",
      "inputs": {
        "schema": {
          "type": "object",
          "properties": {
            "alertId": {"type": "string"},
            "severity": {"type": "string"},
            "anomalyData": {"type": "object"}
          }
        }
      }
    }
  },
  "actions": {
    "Response": {
      "type": "Response",
      "inputs": {
        "statusCode": 200,
        "body": "Fraud alert processed successfully"
      }
    }
  }
}
EOF
)
        
        az logic workflow create \
            --name "$LOGIC_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --definition "$workflow_definition" \
            --output none
        log_success "Logic App created: $LOGIC_APP_NAME"
    fi
}

create_monitoring() {
    log_info "Creating Log Analytics workspace: $WORKSPACE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Log Analytics workspace: $WORKSPACE_NAME"
        return 0
    fi
    
    if az monitor log-analytics workspace show --workspace-name "$WORKSPACE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Log Analytics workspace $WORKSPACE_NAME already exists"
    else
        az monitor log-analytics workspace create \
            --workspace-name "$WORKSPACE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --output none
        log_success "Log Analytics workspace created: $WORKSPACE_NAME"
    fi
    
    # Create alert rule
    log_info "Creating alert rule for fraud detection failures..."
    
    if ! az monitor metrics alert show --name "fraud-detection-failures" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az monitor metrics alert create \
            --name "fraud-detection-failures" \
            --resource-group "$RESOURCE_GROUP" \
            --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.CognitiveServices/accounts/$METRICS_ADVISOR_NAME" \
            --condition "count static avg errors > 5 within 5m" \
            --description "Alert when fraud detection service experiences failures" \
            --evaluation-frequency 1m \
            --window-size 5m \
            --severity 2 \
            --output none
        log_success "Alert rule created: fraud-detection-failures"
    else
        log_warning "Alert rule fraud-detection-failures already exists"
    fi
}

create_sample_data() {
    log_info "Creating sample transaction data..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create sample transaction data"
        return 0
    fi
    
    # Create sample transaction data
    local sample_data=$(cat << 'EOF'
{
  "timestamp": "2025-07-12T10:00:00Z",
  "metrics": [
    {
      "name": "transaction_volume",
      "value": 1250,
      "dimensions": {
        "region": "north_america",
        "account_type": "premium"
      }
    },
    {
      "name": "average_transaction_amount",
      "value": 850.50,
      "dimensions": {
        "region": "north_america",
        "account_type": "premium"
      }
    }
  ]
}
EOF
)
    
    # Save to temporary file
    local temp_file=$(mktemp)
    echo "$sample_data" > "$temp_file"
    
    # Upload to storage
    az storage blob upload \
        --file "$temp_file" \
        --container-name "transaction-data" \
        --name "sample-transactions.json" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --output none
    
    # Clean up temp file
    rm -f "$temp_file"
    
    log_success "Sample transaction data uploaded"
}

create_processing_function() {
    log_info "Creating fraud alert processing function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create fraud alert processing function"
        return 0
    fi
    
    # Create processing function code
    local processing_code=$(cat << 'EOF'
import json
import requests
from datetime import datetime

def process_fraud_alert(anomaly_data):
    """
    Process fraud detection anomaly into accessible summary
    """
    # Extract key information from anomaly
    alert_summary = {
        "alert_id": anomaly_data.get("alertId", ""),
        "severity": anomaly_data.get("severity", "medium"),
        "detected_at": datetime.now().isoformat(),
        "affected_metrics": anomaly_data.get("affectedMetrics", []),
        "summary": f"Unusual transaction pattern detected: {anomaly_data.get('description', 'Unknown anomaly')}",
        "recommendation": "Immediate review required for potential fraud investigation",
        "confidence_score": anomaly_data.get("confidenceScore", 0.75)
    }
    
    # Create accessible text format
    accessible_text = f"""
    FRAUD ALERT SUMMARY
    
    Alert ID: {alert_summary['alert_id']}
    Severity: {alert_summary['severity'].upper()}
    Time Detected: {alert_summary['detected_at']}
    
    Description: {alert_summary['summary']}
    
    Recommendation: {alert_summary['recommendation']}
    
    Confidence Score: {alert_summary['confidence_score']}
    
    Please review the attached details and take appropriate action.
    """
    
    return {
        "structured_data": alert_summary,
        "accessible_text": accessible_text
    }

# Example usage
if __name__ == "__main__":
    sample_anomaly = {
        "alertId": "alert-001",
        "severity": "high",
        "description": "Transaction volume exceeded normal patterns by 300%",
        "affectedMetrics": ["transaction_volume", "average_amount"],
        "confidenceScore": 0.92
    }
    
    result = process_fraud_alert(sample_anomaly)
    print(json.dumps(result, indent=2))
EOF
)
    
    # Save to temporary file
    local temp_file=$(mktemp)
    echo "$processing_code" > "$temp_file"
    
    # Upload to storage
    az storage blob upload \
        --file "$temp_file" \
        --container-name "fraud-alerts" \
        --name "fraud-alert-processor.py" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --output none
    
    # Clean up temp file
    rm -f "$temp_file"
    
    log_success "Fraud alert processing function uploaded"
}

# =============================================================================
# Validation Functions
# =============================================================================

validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate deployment"
        return 0
    fi
    
    local validation_errors=0
    
    # Check resource group
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Resource group validation failed"
        ((validation_errors++))
    fi
    
    # Check storage account
    if ! az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Storage account validation failed"
        ((validation_errors++))
    fi
    
    # Check cognitive services
    if ! az cognitiveservices account show --name "$METRICS_ADVISOR_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Metrics Advisor validation failed"
        ((validation_errors++))
    fi
    
    if ! az cognitiveservices account show --name "$IMMERSIVE_READER_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Immersive Reader validation failed"
        ((validation_errors++))
    fi
    
    # Check Logic App
    if ! az logic workflow show --name "$LOGIC_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Logic App validation failed"
        ((validation_errors++))
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        log_success "All resources validated successfully"
        return 0
    else
        log_error "Validation failed with $validation_errors errors"
        return 1
    fi
}

# =============================================================================
# Main Functions
# =============================================================================

confirm_deployment() {
    if [[ "$FORCE_DEPLOYMENT" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "Deployment Summary:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  Environment: $ENVIRONMENT"
    echo "  Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "Resources to be created:"
    echo "  - Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "  - Metrics Advisor: $METRICS_ADVISOR_NAME"
    echo "  - Immersive Reader: $IMMERSIVE_READER_NAME"
    echo "  - Logic App: $LOGIC_APP_NAME"
    echo "  - Log Analytics Workspace: $WORKSPACE_NAME"
    echo ""
    
    read -p "Do you want to proceed with deployment? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

print_deployment_summary() {
    echo ""
    echo -e "${GREEN}=============================================================="
    echo "Deployment Summary"
    echo -e "==============================================================${NC}"
    echo ""
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo ""
    echo "Created Resources:"
    echo "  ✅ Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "  ✅ Metrics Advisor: $METRICS_ADVISOR_NAME"
    echo "  ✅ Immersive Reader: $IMMERSIVE_READER_NAME"
    echo "  ✅ Logic App: $LOGIC_APP_NAME"
    echo "  ✅ Log Analytics Workspace: $WORKSPACE_NAME"
    echo ""
    echo "Configuration saved to: $CONFIG_FILE"
    echo "Deployment log: $LOG_FILE"
    echo ""
    echo -e "${YELLOW}Important:${NC}"
    echo "  - Azure AI Metrics Advisor will be retired on October 1, 2026"
    echo "  - Plan migration to Azure AI Anomaly Detector for production use"
    echo "  - Remember to clean up resources when no longer needed"
    echo ""
    echo -e "${GREEN}Deployment completed successfully!${NC}"
}

main() {
    # Initialize logging
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
    print_banner
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -s|--suffix)
                RANDOM_SUFFIX="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_DEPLOYMENT="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Set default values
    LOCATION="${LOCATION:-$DEFAULT_LOCATION}"
    ENVIRONMENT="${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}"
    RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(generate_random_suffix)}"
    FORCE_DEPLOYMENT="${FORCE_DEPLOYMENT:-false}"
    DRY_RUN="${DRY_RUN:-false}"
    
    # Set resource names
    RESOURCE_GROUP="rg-fraud-detection-${RANDOM_SUFFIX}"
    METRICS_ADVISOR_NAME="ma-fraud-${RANDOM_SUFFIX}"
    IMMERSIVE_READER_NAME="ir-fraud-${RANDOM_SUFFIX}"
    LOGIC_APP_NAME="la-fraud-workflow-${RANDOM_SUFFIX}"
    STORAGE_ACCOUNT_NAME="stfraud${RANDOM_SUFFIX}"
    WORKSPACE_NAME="law-fraud-monitoring-${RANDOM_SUFFIX}"
    
    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in dry-run mode - no resources will be created"
    fi
    
    # Validate prerequisites
    validate_prerequisites
    check_resource_providers
    
    # Confirm deployment
    confirm_deployment
    
    # Execute deployment
    log_info "Starting deployment process..."
    
    create_resource_group
    create_storage_account
    create_cognitive_services
    create_logic_app
    create_monitoring
    create_sample_data
    create_processing_function
    
    if [[ "$DRY_RUN" != "true" ]]; then
        validate_deployment
        save_config
        print_deployment_summary
    else
        log_info "Dry-run completed - no resources were created"
    fi
}

# =============================================================================
# Error Handling
# =============================================================================

cleanup_on_error() {
    log_error "Deployment failed. Check $LOG_FILE for details."
    echo ""
    echo "To clean up any partially created resources, run:"
    echo "  $SCRIPT_DIR/destroy.sh"
    exit 1
}

trap cleanup_on_error ERR

# =============================================================================
# Script Execution
# =============================================================================

main "$@"