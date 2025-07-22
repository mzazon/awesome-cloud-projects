#!/bin/bash

# ==============================================================================
# Azure IoT Edge Analytics Validation Script
# ==============================================================================
# This script validates the deployed IoT Edge Analytics solution
# ==============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
RESOURCE_GROUP=""
ENVIRONMENT="dev"
UNIQUE_SUFFIX=""
VERBOSE=false
SEND_TEST_DATA=false

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[HEADER]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate the deployed Azure IoT Edge Analytics solution.

OPTIONS:
    -g, --resource-group RG    Resource group name [required]
    -e, --environment ENV      Environment (dev, test, prod) [default: dev]
    -s, --suffix SUFFIX        Unique suffix for resources [required]
    -t, --test-data            Send test telemetry data
    -v, --verbose              Enable verbose output
    -h, --help                 Show this help message

EXAMPLES:
    # Validate development deployment
    $0 -g rg-iot-analytics-dev -s abc123

    # Validate with test data
    $0 -g rg-iot-analytics-dev -s abc123 -t

    # Validate production deployment
    $0 -g rg-iot-analytics-prod -e prod -s xyz789

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -s|--suffix)
            UNIQUE_SUFFIX="$2"
            shift 2
            ;;
        -t|--test-data)
            SEND_TEST_DATA=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
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

# Validate required parameters
if [[ -z "$RESOURCE_GROUP" ]]; then
    print_error "Resource group is required. Use -g or --resource-group"
    exit 1
fi

if [[ -z "$UNIQUE_SUFFIX" ]]; then
    print_error "Unique suffix is required. Use -s or --suffix"
    exit 1
fi

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it from https://aka.ms/azure-cli"
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    print_error "Not logged in to Azure. Please run 'az login' first"
    exit 1
fi

# Check if resource group exists
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    print_error "Resource group '$RESOURCE_GROUP' does not exist"
    exit 1
fi

# Resource names
IOT_HUB_NAME="iot-edge-${ENVIRONMENT}-${UNIQUE_SUFFIX}-hub"
STREAM_JOB_NAME="iot-edge-${ENVIRONMENT}-${UNIQUE_SUFFIX}-stream"
STORAGE_ACCOUNT_NAME="iotedge${ENVIRONMENT}${UNIQUE_SUFFIX}storage"
KEY_VAULT_NAME="iot-edge-${ENVIRONMENT}-${UNIQUE_SUFFIX}-kv"
LOG_WORKSPACE_NAME="iot-edge-${ENVIRONMENT}-${UNIQUE_SUFFIX}-logs"

VALIDATION_ERRORS=0

print_header "Azure IoT Edge Analytics Validation"
echo "Resource Group:  $RESOURCE_GROUP"
echo "Environment:     $ENVIRONMENT"
echo "Unique Suffix:   $UNIQUE_SUFFIX"
echo

# Validate IoT Hub
print_status "Validating IoT Hub..."
if az iot hub show --name "$IOT_HUB_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
    print_success "IoT Hub '$IOT_HUB_NAME' exists"
    
    # Check IoT Hub status
    IOT_HUB_STATE=$(az iot hub show --name "$IOT_HUB_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.state" --output tsv)
    if [[ "$IOT_HUB_STATE" == "Active" ]]; then
        print_success "IoT Hub is active"
    else
        print_error "IoT Hub state is '$IOT_HUB_STATE' (expected: Active)"
        ((VALIDATION_ERRORS++))
    fi
    
    # Check IoT Hub connectivity
    IOT_HUB_HOSTNAME=$(az iot hub show --name "$IOT_HUB_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.hostName" --output tsv)
    if [[ -n "$IOT_HUB_HOSTNAME" ]]; then
        print_success "IoT Hub hostname: $IOT_HUB_HOSTNAME"
    else
        print_error "Could not retrieve IoT Hub hostname"
        ((VALIDATION_ERRORS++))
    fi
else
    print_error "IoT Hub '$IOT_HUB_NAME' not found"
    ((VALIDATION_ERRORS++))
fi

# Validate Stream Analytics Job
print_status "Validating Stream Analytics Job..."
if az stream-analytics job show --name "$STREAM_JOB_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
    print_success "Stream Analytics Job '$STREAM_JOB_NAME' exists"
    
    # Check Stream Analytics job state
    STREAM_STATE=$(az stream-analytics job show --name "$STREAM_JOB_NAME" --resource-group "$RESOURCE_GROUP" --query "jobState" --output tsv)
    print_status "Stream Analytics job state: $STREAM_STATE"
    
    # Check inputs
    INPUTS=$(az stream-analytics input list --job-name "$STREAM_JOB_NAME" --resource-group "$RESOURCE_GROUP" --query "length(@)")
    if [[ "$INPUTS" -gt 0 ]]; then
        print_success "Stream Analytics job has $INPUTS input(s)"
    else
        print_error "Stream Analytics job has no inputs"
        ((VALIDATION_ERRORS++))
    fi
    
    # Check outputs
    OUTPUTS=$(az stream-analytics output list --job-name "$STREAM_JOB_NAME" --resource-group "$RESOURCE_GROUP" --query "length(@)")
    if [[ "$OUTPUTS" -gt 0 ]]; then
        print_success "Stream Analytics job has $OUTPUTS output(s)"
    else
        print_error "Stream Analytics job has no outputs"
        ((VALIDATION_ERRORS++))
    fi
else
    print_error "Stream Analytics Job '$STREAM_JOB_NAME' not found"
    ((VALIDATION_ERRORS++))
fi

# Validate Storage Account
print_status "Validating Storage Account..."
if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
    print_success "Storage Account '$STORAGE_ACCOUNT_NAME' exists"
    
    # Check if Data Lake is enabled
    HNS_ENABLED=$(az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" --query "isHnsEnabled" --output tsv)
    if [[ "$HNS_ENABLED" == "true" ]]; then
        print_success "Data Lake Gen2 is enabled"
    else
        print_error "Data Lake Gen2 is not enabled"
        ((VALIDATION_ERRORS++))
    fi
    
    # Check containers
    CONTAINERS=$(az storage container list --account-name "$STORAGE_ACCOUNT_NAME" --query "length(@)" --output tsv 2>/dev/null || echo "0")
    if [[ "$CONTAINERS" -gt 0 ]]; then
        print_success "Storage account has $CONTAINERS container(s)"
    else
        print_error "Storage account has no containers"
        ((VALIDATION_ERRORS++))
    fi
else
    print_error "Storage Account '$STORAGE_ACCOUNT_NAME' not found"
    ((VALIDATION_ERRORS++))
fi

# Validate Key Vault
print_status "Validating Key Vault..."
if az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
    print_success "Key Vault '$KEY_VAULT_NAME' exists"
    
    # Check Key Vault status
    KV_STATUS=$(az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.provisioningState" --output tsv)
    if [[ "$KV_STATUS" == "Succeeded" ]]; then
        print_success "Key Vault is provisioned successfully"
    else
        print_error "Key Vault status is '$KV_STATUS' (expected: Succeeded)"
        ((VALIDATION_ERRORS++))
    fi
else
    print_error "Key Vault '$KEY_VAULT_NAME' not found"
    ((VALIDATION_ERRORS++))
fi

# Validate Log Analytics Workspace
print_status "Validating Log Analytics Workspace..."
if az monitor log-analytics workspace show --workspace-name "$LOG_WORKSPACE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
    print_success "Log Analytics Workspace '$LOG_WORKSPACE_NAME' exists"
    
    # Check workspace status
    WORKSPACE_STATUS=$(az monitor log-analytics workspace show --workspace-name "$LOG_WORKSPACE_NAME" --resource-group "$RESOURCE_GROUP" --query "provisioningState" --output tsv)
    if [[ "$WORKSPACE_STATUS" == "Succeeded" ]]; then
        print_success "Log Analytics Workspace is provisioned successfully"
    else
        print_error "Log Analytics Workspace status is '$WORKSPACE_STATUS' (expected: Succeeded)"
        ((VALIDATION_ERRORS++))
    fi
else
    print_error "Log Analytics Workspace '$LOG_WORKSPACE_NAME' not found"
    ((VALIDATION_ERRORS++))
fi

# Validate Alert Rules
print_status "Validating Alert Rules..."
ALERT_RULES=$(az monitor metrics alert list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv)
if [[ "$ALERT_RULES" -gt 0 ]]; then
    print_success "Found $ALERT_RULES alert rule(s)"
else
    print_warning "No alert rules found"
fi

# Validate Action Groups
print_status "Validating Action Groups..."
ACTION_GROUPS=$(az monitor action-group list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv)
if [[ "$ACTION_GROUPS" -gt 0 ]]; then
    print_success "Found $ACTION_GROUPS action group(s)"
else
    print_warning "No action groups found"
fi

# Send test data if requested
if [[ "$SEND_TEST_DATA" == true ]]; then
    print_status "Sending test telemetry data..."
    
    # Create test device if it doesn't exist
    TEST_DEVICE_ID="test-device-validation"
    if ! az iot hub device-identity show --hub-name "$IOT_HUB_NAME" --device-id "$TEST_DEVICE_ID" &> /dev/null; then
        print_status "Creating test device..."
        az iot hub device-identity create --hub-name "$IOT_HUB_NAME" --device-id "$TEST_DEVICE_ID"
    fi
    
    # Send test message
    TEST_MESSAGE="{\"deviceId\":\"$TEST_DEVICE_ID\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"temperature\":25.5,\"humidity\":60.2,\"vibration\":0.1,\"messageType\":\"validation\"}"
    
    if az iot device send-d2c-message --hub-name "$IOT_HUB_NAME" --device-id "$TEST_DEVICE_ID" --data "$TEST_MESSAGE" &> /dev/null; then
        print_success "Test message sent successfully"
    else
        print_error "Failed to send test message"
        ((VALIDATION_ERRORS++))
    fi
    
    # Send anomaly test data
    ANOMALY_MESSAGE="{\"deviceId\":\"$TEST_DEVICE_ID\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"temperature\":95.5,\"humidity\":85.0,\"vibration\":5.2,\"messageType\":\"anomaly_test\"}"
    
    if az iot device send-d2c-message --hub-name "$IOT_HUB_NAME" --device-id "$TEST_DEVICE_ID" --data "$ANOMALY_MESSAGE" &> /dev/null; then
        print_success "Anomaly test message sent successfully"
    else
        print_error "Failed to send anomaly test message"
        ((VALIDATION_ERRORS++))
    fi
    
    print_status "Test data sent. Check Stream Analytics metrics in a few minutes."
fi

# Check connectivity to external services
print_status "Checking connectivity..."

# Test IoT Hub connectivity
if az iot hub show --name "$IOT_HUB_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.hostName" --output tsv &> /dev/null; then
    print_success "IoT Hub connectivity: OK"
else
    print_error "IoT Hub connectivity: FAILED"
    ((VALIDATION_ERRORS++))
fi

# Summary
print_header "Validation Summary"
if [[ $VALIDATION_ERRORS -eq 0 ]]; then
    print_success "✅ All validations passed!"
    echo
    print_status "Your IoT Edge Analytics solution is deployed correctly and ready to use."
    echo
    print_header "Connection Information"
    echo "IoT Hub Name: $IOT_HUB_NAME"
    echo "IoT Hub Hostname: $IOT_HUB_HOSTNAME"
    echo "Stream Analytics Job: $STREAM_JOB_NAME"
    echo "Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "Key Vault: $KEY_VAULT_NAME"
    echo
    print_header "Next Steps"
    echo "1. Configure your Azure Percept device"
    echo "2. Set up Azure Sphere device certificates"
    echo "3. Start the Stream Analytics job"
    echo "4. Monitor telemetry data and alerts"
    
    exit 0
else
    print_error "❌ Validation failed with $VALIDATION_ERRORS error(s)"
    print_error "Please check the errors above and fix them before using the solution."
    exit 1
fi