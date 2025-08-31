#!/bin/bash

# SMS Compliance Automation with Communication Services - Deployment Script
# This script deploys Azure Communication Services, Azure Functions, and Storage Account
# for automated SMS compliance management with opt-out processing capabilities.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if Azure Functions Core Tools is installed
    if ! command -v func &> /dev/null; then
        log_error "Azure Functions Core Tools is not installed. Please install it from https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local"
        exit 1
    fi
    
    # Check if OpenSSL is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not installed. Please install it for random suffix generation."
        exit 1
    fi
    
    # Check if user is logged into Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed successfully"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-sms-compliance-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Communication Services and Functions resource names
    export COMMUNICATION_SERVICE="sms-comm-${RANDOM_SUFFIX}"
    export FUNCTION_APP="sms-compliance-func-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="smsstorage${RANDOM_SUFFIX}"
    
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Communication Service: ${COMMUNICATION_SERVICE}"
    log_info "Function App: ${FUNCTION_APP}"
    log_info "Storage Account: ${STORAGE_ACCOUNT}"
    
    log_success "Environment variables configured"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=sms-compliance environment=demo \
        --output table
    
    if [ $? -eq 0 ]; then
        log_success "Resource group created: ${RESOURCE_GROUP}"
    else
        log_error "Failed to create resource group"
        exit 1
    fi
}

# Function to create Azure Communication Services resource
create_communication_services() {
    log_info "Creating Azure Communication Services resource: ${COMMUNICATION_SERVICE}"
    
    az communication create \
        --name "${COMMUNICATION_SERVICE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "global" \
        --data-location "United States" \
        --output table
    
    if [ $? -eq 0 ]; then
        log_success "Communication Services resource created with opt-out API access"
        
        # Get connection string for the Communication Services resource
        log_info "Retrieving Communication Services connection string..."
        export COMM_CONNECTION_STRING=$(az communication list-key \
            --name "${COMMUNICATION_SERVICE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query primaryConnectionString \
            --output tsv)
        
        if [ -n "${COMM_CONNECTION_STRING}" ]; then
            log_success "Communication Services connection string retrieved"
        else
            log_error "Failed to retrieve Communication Services connection string"
            exit 1
        fi
    else
        log_error "Failed to create Communication Services resource"
        exit 1
    fi
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account for Function App: ${STORAGE_ACCOUNT}"
    
    az storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --output table
    
    if [ $? -eq 0 ]; then
        log_success "Storage account created"
        
        # Create table for storing opt-out audit logs
        log_info "Creating audit table in storage account..."
        az storage table create \
            --name "optoutaudit" \
            --account-name "${STORAGE_ACCOUNT}" \
            --auth-mode login \
            --output table
        
        if [ $? -eq 0 ]; then
            log_success "Storage account created with audit table"
        else
            log_warning "Storage account created but audit table creation failed"
        fi
    else
        log_error "Failed to create storage account"
        exit 1
    fi
}

# Function to create Function App
create_function_app() {
    log_info "Creating Function App with consumption plan: ${FUNCTION_APP}"
    
    az functionapp create \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --storage-account "${STORAGE_ACCOUNT}" \
        --consumption-plan-location "${LOCATION}" \
        --runtime node \
        --runtime-version 20 \
        --functions-version 4 \
        --assign-identity \
        --output table
    
    if [ $? -eq 0 ]; then
        log_success "Function App created with managed identity"
        
        # Configure Communication Services connection string
        log_info "Configuring Function App settings..."
        az functionapp config appsettings set \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --settings "CommunicationServicesConnectionString=${COMM_CONNECTION_STRING}" \
            --output table
        
        if [ $? -eq 0 ]; then
            log_success "Function App configuration completed"
        else
            log_error "Failed to configure Function App settings"
            exit 1
        fi
    else
        log_error "Failed to create Function App"
        exit 1
    fi
}

# Function to create and deploy Azure Functions
create_functions() {
    log_info "Creating Azure Functions code..."
    
    # Create temporary directory for function code
    TEMP_FUNCTIONS_DIR="./sms-compliance-functions"
    mkdir -p "${TEMP_FUNCTIONS_DIR}/OptOutProcessor"
    mkdir -p "${TEMP_FUNCTIONS_DIR}/ComplianceMonitor"
    
    # Create HTTP trigger function configuration for opt-out processing
    cat > "${TEMP_FUNCTIONS_DIR}/OptOutProcessor/function.json" << 'EOF'
{
  "bindings": [
    {
      "authLevel": "function",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["post"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    }
  ]
}
EOF
    
    # Create opt-out processing logic
    cat > "${TEMP_FUNCTIONS_DIR}/OptOutProcessor/index.js" << 'EOF'
const { SmsClient } = require('@azure/communication-sms');
const { TableClient } = require('@azure/data-tables');

module.exports = async function (context, req) {
    context.log('SMS Compliance opt-out request received');
    
    try {
        // Validate required parameters
        const { phoneNumber, fromNumber, channel = 'sms' } = req.body;
        
        if (!phoneNumber || !fromNumber) {
            context.res = {
                status: 400,
                body: { error: 'phoneNumber and fromNumber are required' }
            };
            return;
        }
        
        // Initialize Communication Services client
        const connectionString = process.env.CommunicationServicesConnectionString;
        const smsClient = new SmsClient(connectionString);
        
        // Add phone number to opt-out list using new API
        const optOutResult = await smsClient.optOuts.add(fromNumber, [phoneNumber]);
        
        // Log compliance event for audit
        const auditRecord = {
            partitionKey: new Date().toISOString().split('T')[0],
            rowKey: `${phoneNumber}-${Date.now()}`,
            phoneNumber: phoneNumber,
            fromNumber: fromNumber,
            channel: channel,
            action: 'opt-out',
            timestamp: new Date().toISOString(),
            status: optOutResult.value[0].httpStatusCode === 200 ? 'success' : 'failed'
        };
        
        // Store audit record (simplified for demo)
        context.log('Audit record:', auditRecord);
        
        // Return success response
        context.res = {
            status: 200,
            body: {
                message: 'Opt-out processed successfully',
                phoneNumber: phoneNumber,
                status: 'opted-out',
                timestamp: new Date().toISOString()
            }
        };
        
    } catch (error) {
        context.log.error('Error processing opt-out:', error);
        context.res = {
            status: 500,
            body: { error: 'Failed to process opt-out request' }
        };
    }
};
EOF
    
    # Create timer trigger configuration for compliance monitoring (runs daily at 9 AM UTC)
    cat > "${TEMP_FUNCTIONS_DIR}/ComplianceMonitor/function.json" << 'EOF'
{
  "bindings": [
    {
      "name": "myTimer",
      "type": "timerTrigger",
      "direction": "in",
      "schedule": "0 0 9 * * *"
    }
  ]
}
EOF
    
    # Create compliance monitoring logic
    cat > "${TEMP_FUNCTIONS_DIR}/ComplianceMonitor/index.js" << 'EOF'
const { SmsClient } = require('@azure/communication-sms');

module.exports = async function (context, myTimer) {
    context.log('Starting compliance monitoring check');
    
    try {
        const connectionString = process.env.CommunicationServicesConnectionString;
        const smsClient = new SmsClient(connectionString);
        
        // Example: Check opt-out status for monitoring
        // In production, this would check against your customer database
        const sampleNumbers = ['+1234567890', '+1987654321']; // Example numbers
        
        for (const number of sampleNumbers) {
            try {
                const checkResult = await smsClient.optOuts.check('+18005551234', [number]);
                context.log(`Opt-out status for ${number}:`, checkResult.value[0].isOptedOut);
            } catch (error) {
                context.log.error(`Error checking ${number}:`, error.message);
            }
        }
        
        context.log('Compliance monitoring completed successfully');
        
    } catch (error) {
        context.log.error('Compliance monitoring failed:', error);
    }
};
EOF
    
    # Create package.json for dependencies
    cat > "${TEMP_FUNCTIONS_DIR}/package.json" << 'EOF'
{
  "name": "sms-compliance-functions",
  "version": "1.0.0",
  "description": "SMS compliance automation functions",
  "dependencies": {
    "@azure/communication-sms": "^1.1.0",
    "@azure/data-tables": "^13.2.2"
  }
}
EOF
    
    # Create host.json configuration
    cat > "${TEMP_FUNCTIONS_DIR}/host.json" << 'EOF'
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true
      }
    }
  },
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[2.*, 3.0.0)"
  }
}
EOF
    
    log_success "Function code created"
}

# Function to deploy functions to Azure
deploy_functions() {
    log_info "Deploying functions to Azure Function App..."
    
    # Change to functions directory
    cd "./sms-compliance-functions"
    
    # Deploy functions to Azure
    func azure functionapp publish "${FUNCTION_APP}" --javascript
    
    if [ $? -eq 0 ]; then
        log_success "Functions deployed with compliance automation"
        cd ..
        
        # Clean up temporary directory
        rm -rf "./sms-compliance-functions"
        log_info "Temporary function files cleaned up"
    else
        log_error "Failed to deploy functions"
        cd ..
        exit 1
    fi
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check Function App status and configuration
    log_info "Checking Function App status..."
    az functionapp show \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "{name:name,state:state,runtime:siteConfig.linuxFxVersion}" \
        --output table
    
    # Get function URLs for testing
    log_info "Retrieving function URLs..."
    FUNCTION_URL=$(az functionapp function show \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --function-name OptOutProcessor \
        --query "invokeUrlTemplate" \
        --output tsv 2>/dev/null || echo "URL retrieval failed")
    
    if [ "${FUNCTION_URL}" != "URL retrieval failed" ]; then
        log_success "Function URL: ${FUNCTION_URL}"
    else
        log_warning "Function URL could not be retrieved immediately. This is normal - functions may need a few minutes to fully initialize."
    fi
    
    # Verify Communication Services integration
    log_info "Verifying Communication Services integration..."
    az communication show \
        --name "${COMMUNICATION_SERVICE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "{name:name,location:location,dataLocation:dataLocation}" \
        --output table
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary:"
    echo "=================================================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "Communication Services: ${COMMUNICATION_SERVICE}"
    echo "Function App: ${FUNCTION_APP}"
    echo "Storage Account: ${STORAGE_ACCOUNT}"
    echo "=================================================="
    echo ""
    log_info "SMS Compliance Automation Solution deployed successfully!"
    echo ""
    log_info "Next Steps:"
    echo "1. Test the opt-out processing function using the Function URL"
    echo "2. Monitor compliance activities through Azure Portal"
    echo "3. Configure SMS phone numbers in Communication Services"
    echo "4. Set up Application Insights for monitoring and alerting"
    echo ""
    log_warning "Remember to run the destroy.sh script to clean up resources when testing is complete"
    echo ""
    log_info "For testing, you can use curl to send opt-out requests:"
    echo "curl -X POST \"<FUNCTION_URL>\" \\"
    echo "     -H \"Content-Type: application/json\" \\"
    echo "     -d '{\"phoneNumber\": \"+15551234567\", \"fromNumber\": \"+18005551234\", \"channel\": \"web\"}'"
}

# Main deployment function
main() {
    log_info "Starting SMS Compliance Automation deployment..."
    echo "=================================================="
    
    # Check prerequisites
    check_prerequisites
    
    # Setup environment
    setup_environment
    
    # Create Azure resources
    create_resource_group
    create_communication_services
    create_storage_account
    create_function_app
    
    # Create and deploy functions
    create_functions
    deploy_functions
    
    # Validate deployment
    validate_deployment
    
    # Display summary
    display_summary
    
    log_success "SMS Compliance Automation deployment completed successfully!"
}

# Handle script interruption
trap 'log_error "Script interrupted. Some resources may have been created. Run destroy.sh to clean up."; exit 1' INT TERM

# Check for dry-run mode
if [ "${1:-}" = "--dry-run" ]; then
    log_info "DRY RUN MODE - No resources will be created"
    check_prerequisites
    setup_environment
    log_info "Dry run completed. All checks passed."
    exit 0
fi

# Run main deployment
main "$@"