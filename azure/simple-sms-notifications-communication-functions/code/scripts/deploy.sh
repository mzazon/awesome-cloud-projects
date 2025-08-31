#!/bin/bash

# =============================================================================
# Azure SMS Notifications Deployment Script
# 
# This script deploys a serverless SMS notification system using:
# - Azure Communication Services for SMS delivery
# - Azure Functions for event-driven processing
# - Azure Storage for function app requirements
#
# Prerequisites:
# - Azure CLI installed and configured
# - Azure Functions Core Tools v4 installed
# - Active Azure subscription with Communication Services permissions
# - Node.js 20+ for local function development
# =============================================================================

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Error handling function
cleanup_on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code: $exit_code"
    log_info "Cleaning up partial deployment..."
    
    # Attempt to clean up resources if they exist
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait 2>/dev/null || true
        log_info "Cleanup initiated for resource group: ${RESOURCE_GROUP}"
    fi
    
    exit $exit_code
}

# Set error trap
trap cleanup_on_error ERR

# Prerequisites checking function
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check Azure Functions Core Tools
    if ! command -v func &> /dev/null; then
        log_error "Azure Functions Core Tools not found. Please install from: https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local"
        exit 1
    fi
    
    local func_version
    func_version=$(func --version)
    log_info "Azure Functions Core Tools version: $func_version"
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed. Please install Node.js 20+ from: https://nodejs.org/"
        exit 1
    fi
    
    local node_version
    node_version=$(node --version)
    log_info "Node.js version: $node_version"
    
    # Check npm
    if ! command -v npm &> /dev/null; then
        log_error "npm is not installed. Please install Node.js which includes npm."
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

# Configuration validation function
validate_configuration() {
    log_info "Validating configuration..."
    
    # Validate location
    if ! az account list-locations --query "[?name=='${LOCATION}']" -o tsv | grep -q "${LOCATION}"; then
        log_error "Invalid Azure location: ${LOCATION}"
        log_info "Available locations: $(az account list-locations --query '[].name' -o tsv | tr '\n' ', ')"
        exit 1
    fi
    
    # Validate resource names (Azure naming requirements)
    if [[ ! "${ACS_RESOURCE_NAME}" =~ ^[a-zA-Z0-9-]{3,63}$ ]]; then
        log_error "Invalid Communication Services resource name: ${ACS_RESOURCE_NAME}"
        exit 1
    fi
    
    if [[ ! "${FUNCTION_APP_NAME}" =~ ^[a-zA-Z0-9-]{2,60}$ ]]; then
        log_error "Invalid Function App name: ${FUNCTION_APP_NAME}"
        exit 1
    fi
    
    if [[ ! "${STORAGE_ACCOUNT_NAME}" =~ ^[a-z0-9]{3,24}$ ]]; then
        log_error "Invalid Storage Account name: ${STORAGE_ACCOUNT_NAME}"
        exit 1
    fi
    
    log_success "Configuration validated"
}

# Generate unique suffix for resource names
generate_unique_suffix() {
    if command -v openssl &> /dev/null; then
        openssl rand -hex 3
    else
        # Fallback using date and random
        echo "$(date +%s | tail -c 4)$(shuf -i 100-999 -n 1)" | cut -c1-6
    fi
}

# Set default configuration
set_default_configuration() {
    log_info "Setting up default configuration..."
    
    # Set environment variables with defaults
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    local suffix
    suffix=$(generate_unique_suffix)
    
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-sms-notifications-${suffix}}"
    export ACS_RESOURCE_NAME="${ACS_RESOURCE_NAME:-acs-sms-${suffix}}"
    export FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-sms-${suffix}}"
    export STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-stsms${suffix}}"
    
    log_info "Configuration:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Location: ${LOCATION}"
    log_info "  Communication Services: ${ACS_RESOURCE_NAME}"
    log_info "  Function App: ${FUNCTION_APP_NAME}"
    log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists, skipping creation"
        return 0
    fi
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=recipe environment=demo \
        --output none
    
    log_success "Resource group created: ${RESOURCE_GROUP}"
}

# Create Communication Services resource
create_communication_services() {
    log_info "Creating Azure Communication Services resource: ${ACS_RESOURCE_NAME}"
    
    if az communication show --name "${ACS_RESOURCE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Communication Services resource already exists, skipping creation"
    else
        az communication create \
            --name "${ACS_RESOURCE_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "global" \
            --data-location "United States" \
            --output none
        
        log_success "Communication Services resource created"
    fi
    
    # Get connection string
    ACS_CONNECTION_STRING=$(az communication list-key \
        --name "${ACS_RESOURCE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "primaryConnectionString" \
        --output tsv)
    
    if [[ -z "${ACS_CONNECTION_STRING}" ]]; then
        log_error "Failed to retrieve Communication Services connection string"
        exit 1
    fi
    
    log_success "Communication Services connection string retrieved"
}

# Acquire phone number for SMS
acquire_phone_number() {
    log_info "Acquiring phone number for SMS..."
    
    # Check if phone number already exists
    local existing_numbers
    existing_numbers=$(az communication phonenumber list \
        --resource-group "${RESOURCE_GROUP}" \
        --communication-service "${ACS_RESOURCE_NAME}" \
        --query "phoneNumbers[0].phoneNumber" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${existing_numbers}" && "${existing_numbers}" != "null" ]]; then
        PHONE_NUMBER="${existing_numbers}"
        log_warning "Using existing phone number: ${PHONE_NUMBER}"
        return 0
    fi
    
    log_info "Searching for available toll-free numbers..."
    
    # Search for available numbers
    local available_numbers
    available_numbers=$(az communication phonenumber list-available \
        --resource-group "${RESOURCE_GROUP}" \
        --communication-service "${ACS_RESOURCE_NAME}" \
        --phone-number-type "tollFree" \
        --assignment-type "application" \
        --capabilities "sms" \
        --area-code "800" \
        --query "phoneNumbers[0].phoneNumber" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -z "${available_numbers}" || "${available_numbers}" == "null" ]]; then
        log_warning "No toll-free numbers available in area code 800, trying 888..."
        available_numbers=$(az communication phonenumber list-available \
            --resource-group "${RESOURCE_GROUP}" \
            --communication-service "${ACS_RESOURCE_NAME}" \
            --phone-number-type "tollFree" \
            --assignment-type "application" \
            --capabilities "sms" \
            --area-code "888" \
            --query "phoneNumbers[0].phoneNumber" \
            --output tsv 2>/dev/null || echo "")
    fi
    
    if [[ -z "${available_numbers}" || "${available_numbers}" == "null" ]]; then
        log_error "No toll-free numbers available for SMS. Please try again later or contact Azure support."
        exit 1
    fi
    
    log_info "Purchasing phone number: ${available_numbers}"
    log_warning "This will incur a monthly charge of approximately $2.00"
    
    # Purchase the number
    PHONE_NUMBER=$(az communication phonenumber purchase \
        --resource-group "${RESOURCE_GROUP}" \
        --communication-service "${ACS_RESOURCE_NAME}" \
        --phone-number-type "tollFree" \
        --assignment-type "application" \
        --capabilities "sms" \
        --area-code "800" \
        --quantity 1 \
        --query "phoneNumbers[0]" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -z "${PHONE_NUMBER}" ]]; then
        log_error "Failed to acquire phone number"
        exit 1
    fi
    
    log_success "Phone number acquired: ${PHONE_NUMBER}"
    log_warning "IMPORTANT: Toll-free numbers require verification before SMS can be sent."
    log_warning "Complete verification at: https://portal.azure.com/#@/resource/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Communication/CommunicationServices/${ACS_RESOURCE_NAME}/phoneNumbers"
}

# Create storage account
create_storage_account() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT_NAME}"
    
    if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Storage account already exists, skipping creation"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --output none
        
        log_success "Storage account created"
    fi
    
    # Get storage connection string
    STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "connectionString" \
        --output tsv)
    
    if [[ -z "${STORAGE_CONNECTION_STRING}" ]]; then
        log_error "Failed to retrieve storage connection string"
        exit 1
    fi
    
    log_success "Storage connection string retrieved"
}

# Create Function App
create_function_app() {
    log_info "Creating Function App: ${FUNCTION_APP_NAME}"
    
    if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Function App already exists, skipping creation"
    else
        az functionapp create \
            --name "${FUNCTION_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_ACCOUNT_NAME}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime node \
            --runtime-version 20 \
            --functions-version 4 \
            --os-type Linux \
            --output none
        
        log_success "Function App created"
    fi
    
    # Configure application settings
    log_info "Configuring Function App settings..."
    
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "ACS_CONNECTION_STRING=${ACS_CONNECTION_STRING}" \
                   "SMS_FROM_PHONE=${PHONE_NUMBER}" \
        --output none
    
    log_success "Function App configured with Communication Services settings"
}

# Create and deploy function code
create_and_deploy_function() {
    log_info "Creating local function project..."
    
    local temp_dir="/tmp/sms-function-${RANDOM}"
    mkdir -p "${temp_dir}"
    cd "${temp_dir}"
    
    # Initialize Functions project
    func init --javascript --model V4 --output none
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "sms-notification-function",
  "version": "1.0.0",
  "description": "SMS notification system using Azure Communication Services",
  "main": "src/index.js",
  "scripts": {
    "start": "func start"
  },
  "dependencies": {
    "@azure/communication-sms": "^1.1.0",
    "@azure/functions": "^4.0.0"
  }
}
EOF
    
    # Create function directory and code
    mkdir -p src
    
    cat > src/index.js << 'EOF'
const { app } = require('@azure/functions');
const { SmsClient } = require('@azure/communication-sms');

app.http('sendSMS', {
    methods: ['POST'],
    authLevel: 'function',
    handler: async (request, context) => {
        try {
            // Parse request body
            const requestBody = await request.json();
            const { to, message } = requestBody;
            
            // Validate required parameters
            if (!to || !message) {
                context.log('Missing required parameters: to, message');
                return {
                    status: 400,
                    jsonBody: {
                        error: 'Missing required parameters: to, message'
                    }
                };
            }
            
            // Validate phone number format
            if (!to.match(/^\+?[1-9]\d{1,14}$/)) {
                context.log(`Invalid phone number format: ${to}`);
                return {
                    status: 400,
                    jsonBody: {
                        error: 'Invalid phone number format. Use E.164 format (+1234567890)'
                    }
                };
            }
            
            // Initialize SMS client
            const connectionString = process.env.ACS_CONNECTION_STRING;
            const fromPhone = process.env.SMS_FROM_PHONE;
            
            if (!connectionString || !fromPhone) {
                context.error('Missing required environment variables');
                return {
                    status: 500,
                    jsonBody: {
                        error: 'Server configuration error'
                    }
                };
            }
            
            const smsClient = new SmsClient(connectionString);
            
            // Send SMS message
            const sendResults = await smsClient.send({
                from: fromPhone,
                to: [to],
                message: message
            });
            
            // Check if message was sent successfully
            const result = sendResults[0];
            if (result.successful) {
                context.log(`SMS sent successfully to ${to}, MessageId: ${result.messageId}`);
                return {
                    status: 200,
                    jsonBody: {
                        success: true,
                        messageId: result.messageId,
                        to: to,
                        message: 'SMS sent successfully'
                    }
                };
            } else {
                context.error(`Failed to send SMS: ${result.errorMessage}`);
                return {
                    status: 500,
                    jsonBody: {
                        success: false,
                        error: result.errorMessage
                    }
                };
            }
            
        } catch (error) {
            context.error(`Error sending SMS: ${error.message}`);
            return {
                status: 500,
                jsonBody: {
                    success: false,
                    error: 'Internal server error'
                }
            };
        }
    }
});
EOF
    
    log_info "Installing function dependencies..."
    npm install --silent
    
    log_info "Deploying function to Azure..."
    func azure functionapp publish "${FUNCTION_APP_NAME}" --output none
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "${temp_dir}"
    
    log_success "Function deployed successfully"
}

# Get function information for testing
get_function_info() {
    log_info "Retrieving function information..."
    
    # Get function URL
    FUNCTION_URL=$(az functionapp function show \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --function-name sendSMS \
        --query "invokeUrlTemplate" \
        --output tsv)
    
    # Get function key
    FUNCTION_KEY=$(az functionapp keys list \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "functionKeys.default" \
        --output tsv)
    
    if [[ -z "${FUNCTION_URL}" || -z "${FUNCTION_KEY}" ]]; then
        log_error "Failed to retrieve function information"
        exit 1
    fi
    
    log_success "Function information retrieved"
    
    # Save configuration to file for later use
    cat > "${PWD}/sms-function-config.env" << EOF
# SMS Function Configuration
# Generated on: $(date)
RESOURCE_GROUP="${RESOURCE_GROUP}"
LOCATION="${LOCATION}"
ACS_RESOURCE_NAME="${ACS_RESOURCE_NAME}"
FUNCTION_APP_NAME="${FUNCTION_APP_NAME}"
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME}"
PHONE_NUMBER="${PHONE_NUMBER}"
FUNCTION_URL="${FUNCTION_URL}"
FUNCTION_KEY="${FUNCTION_KEY}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID}"
EOF
    
    log_success "Configuration saved to: ${PWD}/sms-function-config.env"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check Function App status
    local app_state
    app_state=$(az functionapp show \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "state" \
        --output tsv)
    
    if [[ "${app_state}" != "Running" ]]; then
        log_error "Function App is not running. State: ${app_state}"
        exit 1
    fi
    
    log_success "Function App is running"
    
    # Test function availability (basic connectivity test)
    local http_status
    http_status=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${FUNCTION_URL}?code=${FUNCTION_KEY}" \
        -H "Content-Type: application/json" \
        -d '{"test": "connectivity"}' || echo "000")
    
    if [[ "${http_status}" == "400" ]]; then
        log_success "Function endpoint is accessible (returned expected 400 for test payload)"
    elif [[ "${http_status}" == "000" ]]; then
        log_warning "Function endpoint connectivity test failed (network issue or function not ready)"
    else
        log_info "Function endpoint returned HTTP ${http_status}"
    fi
}

# Display deployment summary
display_summary() {
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo ""
    log_info "Resource Summary:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Location: ${LOCATION}"
    log_info "  Communication Services: ${ACS_RESOURCE_NAME}"
    log_info "  Phone Number: ${PHONE_NUMBER}"
    log_info "  Function App: ${FUNCTION_APP_NAME}"
    log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo ""
    log_info "Function Endpoint:"
    log_info "  URL: ${FUNCTION_URL}?code=${FUNCTION_KEY}"
    echo ""
    log_warning "IMPORTANT NEXT STEPS:"
    log_warning "1. Complete toll-free verification in Azure portal before sending SMS"
    log_warning "2. Toll-free numbers incur monthly charges (~$2.00/month)"
    log_warning "3. SMS messages cost $0.0075-0.01 each"
    echo ""
    log_info "Test your function with:"
    echo 'curl -X POST "'${FUNCTION_URL}'?code='${FUNCTION_KEY}'" \'
    echo '     -H "Content-Type: application/json" \'
    echo '     -d '"'"'{"to": "+1234567890", "message": "Hello from Azure!"}'"'"
    echo ""
    log_info "Configuration saved to: ${PWD}/sms-function-config.env"
    log_info "Use the destroy.sh script to clean up resources when finished"
}

# Main deployment function
main() {
    log_info "Starting Azure SMS Notifications deployment..."
    log_info "Timestamp: $(date)"
    
    # Run deployment steps
    check_prerequisites
    set_default_configuration
    validate_configuration
    create_resource_group
    create_communication_services
    acquire_phone_number
    create_storage_account
    create_function_app
    create_and_deploy_function
    get_function_info
    validate_deployment
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Execute main function
main "$@"