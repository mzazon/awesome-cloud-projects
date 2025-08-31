#!/bin/bash

# =============================================================================
# Azure Service Bus Message Queue Deployment Script
# =============================================================================
# Description: Deploys Azure Service Bus namespace and queue for message 
#              processing with proper error handling and logging
# Recipe: Simple Message Queue with Service Bus
# Services: Azure Service Bus, Azure CLI
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# =============================================================================
# CONFIGURATION
# =============================================================================

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy-$(date +%Y%m%d-%H%M%S).log"

# Default values (can be overridden by environment variables)
LOCATION="${LOCATION:-eastus}"
QUEUE_NAME="${QUEUE_NAME:-orders}"
RESOURCE_GROUP_PREFIX="${RESOURCE_GROUP_PREFIX:-rg-servicebus-recipe}"
SERVICEBUS_NAMESPACE_PREFIX="${SERVICEBUS_NAMESPACE_PREFIX:-sbns-demo}"
ENABLE_TESTING="${ENABLE_TESTING:-true}"

# =============================================================================
# LOGGING AND UTILITY FUNCTIONS
# =============================================================================

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2
}

log_warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] ✅ $*" | tee -a "${LOG_FILE}"
}

cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log_info "Initiating cleanup of resource group: ${RESOURCE_GROUP}"
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait 2>/dev/null || true
        log_warn "Cleanup initiated. Resources may take several minutes to delete completely."
    fi
}

# Set trap for cleanup on script exit due to error
trap cleanup_on_error ERR

show_usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Deploy Azure Service Bus message queue infrastructure.

OPTIONS:
    -h, --help              Show this help message
    -l, --location          Azure region (default: ${LOCATION})
    -q, --queue-name        Queue name (default: ${QUEUE_NAME})
    -g, --resource-group    Resource group name (auto-generated if not provided)
    -n, --namespace         Service Bus namespace name (auto-generated if not provided)
    --skip-test            Skip test application setup
    --dry-run              Show what would be deployed without creating resources

ENVIRONMENT VARIABLES:
    LOCATION                Azure region
    QUEUE_NAME              Queue name
    RESOURCE_GROUP_PREFIX   Prefix for resource group name
    SERVICEBUS_NAMESPACE_PREFIX  Prefix for Service Bus namespace name
    ENABLE_TESTING          Enable test application setup (true/false)

EXAMPLES:
    ${SCRIPT_NAME}                          # Deploy with defaults
    ${SCRIPT_NAME} --location westus2        # Deploy to specific region
    ${SCRIPT_NAME} --skip-test              # Deploy without test setup
    ${SCRIPT_NAME} --dry-run                # Preview deployment

EOF
}

# =============================================================================
# PREREQUISITE CHECKS
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI first."
        log_error "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' --output tsv 2>/dev/null || echo "unknown")
    log_info "Azure CLI version: ${az_version}"
    
    # Check if logged in to Azure
    local account_check
    if ! account_check=$(az account show --query name --output tsv 2>/dev/null); then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    log_info "Logged in to Azure account: ${account_check}"
    
    # Get subscription information
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    log_info "Using subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"
    
    # Check if Node.js is available for testing (if testing is enabled)
    if [[ "${ENABLE_TESTING}" == "true" ]]; then
        if ! command -v node &> /dev/null; then
            log_warn "Node.js not found. Test application setup will be skipped."
            ENABLE_TESTING="false"
        else
            local node_version
            node_version=$(node --version 2>/dev/null || echo "unknown")
            log_info "Node.js version: ${node_version}"
        fi
        
        if ! command -v npm &> /dev/null; then
            log_warn "npm not found. Test application setup will be skipped."
            ENABLE_TESTING="false"
        fi
    fi
    
    log_success "Prerequisites check completed"
}

# =============================================================================
# RESOURCE DEPLOYMENT FUNCTIONS
# =============================================================================

generate_unique_names() {
    log_info "Generating unique resource names..."
    
    # Generate random suffix for unique naming
    local random_suffix
    random_suffix=$(openssl rand -hex 3)
    
    # Set resource names
    RESOURCE_GROUP="${RESOURCE_GROUP_PREFIX}-${random_suffix}"
    SERVICEBUS_NAMESPACE="${SERVICEBUS_NAMESPACE_PREFIX}-${random_suffix}"
    
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Service Bus Namespace: ${SERVICEBUS_NAMESPACE}"
    log_info "Queue Name: ${QUEUE_NAME}"
    log_info "Location: ${LOCATION}"
}

create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
        log_warn "Resource group ${RESOURCE_GROUP} already exists. Continuing..."
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=recipe environment=demo deployment=automated \
            --output none
        
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

create_servicebus_namespace() {
    log_info "Creating Service Bus namespace: ${SERVICEBUS_NAMESPACE}"
    
    # Check if namespace already exists
    if az servicebus namespace show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${SERVICEBUS_NAMESPACE}" &>/dev/null; then
        log_warn "Service Bus namespace ${SERVICEBUS_NAMESPACE} already exists. Continuing..."
    else
        # Create Service Bus namespace with Standard tier
        az servicebus namespace create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${SERVICEBUS_NAMESPACE}" \
            --location "${LOCATION}" \
            --sku Standard \
            --tags environment=demo purpose=recipe deployment=automated \
            --output none
        
        # Wait for namespace to be provisioned
        log_info "Waiting for Service Bus namespace to be provisioned..."
        local max_attempts=30
        local attempt=1
        
        while (( attempt <= max_attempts )); do
            local status
            status=$(az servicebus namespace show \
                --resource-group "${RESOURCE_GROUP}" \
                --name "${SERVICEBUS_NAMESPACE}" \
                --query status \
                --output tsv 2>/dev/null || echo "Unknown")
            
            if [[ "${status}" == "Active" ]]; then
                log_success "Service Bus namespace is active: ${SERVICEBUS_NAMESPACE}"
                break
            fi
            
            log_info "Namespace status: ${status}. Waiting... (${attempt}/${max_attempts})"
            sleep 10
            (( attempt++ ))
        done
        
        if (( attempt > max_attempts )); then
            log_error "Timeout waiting for Service Bus namespace to become active"
            exit 1
        fi
    fi
}

create_servicebus_queue() {
    log_info "Creating Service Bus queue: ${QUEUE_NAME}"
    
    # Check if queue already exists
    if az servicebus queue show \
        --resource-group "${RESOURCE_GROUP}" \
        --namespace-name "${SERVICEBUS_NAMESPACE}" \
        --name "${QUEUE_NAME}" &>/dev/null; then
        log_warn "Service Bus queue ${QUEUE_NAME} already exists. Continuing..."
    else
        # Create Service Bus queue with enhanced configuration
        az servicebus queue create \
            --resource-group "${RESOURCE_GROUP}" \
            --namespace-name "${SERVICEBUS_NAMESPACE}" \
            --name "${QUEUE_NAME}" \
            --max-size 1024 \
            --default-message-time-to-live P14D \
            --enable-dead-lettering-on-message-expiration true \
            --enable-duplicate-detection false \
            --duplicate-detection-history-time-window PT10M \
            --output none
        
        log_success "Service Bus queue created: ${QUEUE_NAME}"
    fi
}

retrieve_connection_string() {
    log_info "Retrieving Service Bus connection string..."
    
    CONNECTION_STRING=$(az servicebus namespace authorization-rule keys list \
        --resource-group "${RESOURCE_GROUP}" \
        --namespace-name "${SERVICEBUS_NAMESPACE}" \
        --name RootManageSharedAccessKey \
        --query primaryConnectionString \
        --output tsv)
    
    if [[ -z "${CONNECTION_STRING}" ]]; then
        log_error "Failed to retrieve connection string"
        exit 1
    fi
    
    log_success "Connection string retrieved successfully"
    
    # Export for use in testing
    export CONNECTION_STRING
    export QUEUE_NAME
}

# =============================================================================
# TESTING FUNCTIONS
# =============================================================================

setup_test_application() {
    if [[ "${ENABLE_TESTING}" != "true" ]]; then
        log_info "Test application setup skipped"
        return 0
    fi
    
    log_info "Setting up test application..."
    
    # Create test directory
    local test_dir="${SCRIPT_DIR}/servicebus-test"
    
    if [[ -d "${test_dir}" ]]; then
        log_warn "Test directory already exists. Cleaning up..."
        rm -rf "${test_dir}"
    fi
    
    mkdir -p "${test_dir}"
    cd "${test_dir}"
    
    # Initialize Node.js project
    log_info "Initializing Node.js project..."
    npm init -y &>/dev/null
    
    # Install Azure Service Bus SDK
    log_info "Installing Azure Service Bus SDK..."
    npm install @azure/service-bus &>/dev/null
    
    # Create sender script
    log_info "Creating message sender script..."
    cat > send-messages.js << 'EOF'
const { ServiceBusClient } = require("@azure/service-bus");

async function sendMessages() {
    const connectionString = process.env.CONNECTION_STRING;
    const queueName = process.env.QUEUE_NAME;
    
    if (!connectionString || !queueName) {
        console.error("❌ CONNECTION_STRING and QUEUE_NAME environment variables are required");
        process.exit(1);
    }
    
    const sbClient = new ServiceBusClient(connectionString);
    const sender = sbClient.createSender(queueName);
    
    try {
        const messages = [];
        const timestamp = new Date().toISOString();
        
        for (let i = 1; i <= 5; i++) {
            messages.push({
                body: `Order message #${i} - ${timestamp}`,
                subject: `Order ${i}`,
                applicationProperties: { 
                    orderId: i, 
                    priority: "normal",
                    timestamp: timestamp,
                    source: "deployment-test"
                }
            });
        }
        
        await sender.sendMessages(messages);
        console.log(`✅ Successfully sent ${messages.length} messages to queue '${queueName}'`);
        
        // Log message details
        messages.forEach((msg, index) => {
            console.log(`   Message ${index + 1}: ${msg.subject} - ${msg.applicationProperties.orderId}`);
        });
        
    } catch (error) {
        console.error("❌ Error sending messages:", error.message);
        process.exit(1);
    } finally {
        await sender.close();
        await sbClient.close();
    }
}

sendMessages().catch(error => {
    console.error("❌ Unhandled error:", error.message);
    process.exit(1);
});
EOF
    
    # Create receiver script
    log_info "Creating message receiver script..."
    cat > receive-messages.js << 'EOF'
const { ServiceBusClient } = require("@azure/service-bus");

async function receiveMessages() {
    const connectionString = process.env.CONNECTION_STRING;
    const queueName = process.env.QUEUE_NAME;
    
    if (!connectionString || !queueName) {
        console.error("❌ CONNECTION_STRING and QUEUE_NAME environment variables are required");
        process.exit(1);
    }
    
    const sbClient = new ServiceBusClient(connectionString);
    const receiver = sbClient.createReceiver(queueName);
    
    try {
        console.log(`📥 Waiting to receive messages from queue '${queueName}'...`);
        const messages = await receiver.receiveMessages(10, { maxWaitTimeInMs: 10000 });
        
        if (messages.length === 0) {
            console.log("📭 No messages received within timeout period");
            return;
        }
        
        console.log(`📨 Received ${messages.length} messages:`);
        
        for (let i = 0; i < messages.length; i++) {
            const message = messages[i];
            console.log(`\n--- Message ${i + 1} ---`);
            console.log(`Body: ${message.body}`);
            console.log(`Subject: ${message.subject || 'N/A'}`);
            console.log(`Message ID: ${message.messageId || 'N/A'}`);
            console.log(`Properties: ${JSON.stringify(message.applicationProperties || {})}`);
            
            // Complete the message to remove it from the queue
            await receiver.completeMessage(message);
            console.log(`✅ Message ${i + 1} processed and completed`);
        }
        
        console.log(`\n🎉 Successfully processed ${messages.length} messages`);
        
    } catch (error) {
        console.error("❌ Error receiving messages:", error.message);
        process.exit(1);
    } finally {
        await receiver.close();
        await sbClient.close();
    }
}

receiveMessages().catch(error => {
    console.error("❌ Unhandled error:", error.message);
    process.exit(1);
});
EOF
    
    # Create test runner script
    cat > test-messaging.sh << 'EOF'
#!/bin/bash
set -e

echo "🧪 Running Service Bus messaging tests..."

# Send messages
echo "📤 Sending test messages..."
node send-messages.js

# Wait a moment for messages to be available
echo "⏳ Waiting for messages to be available..."
sleep 2

# Receive messages
echo "📥 Receiving messages..."
node receive-messages.js

echo "✅ Messaging test completed successfully!"
EOF
    
    chmod +x test-messaging.sh
    
    cd "${SCRIPT_DIR}"
    log_success "Test application setup completed"
}

run_validation_tests() {
    if [[ "${ENABLE_TESTING}" != "true" ]]; then
        log_info "Validation tests skipped"
        return 0
    fi
    
    log_info "Running validation tests..."
    
    # Verify namespace and queue creation
    log_info "Verifying Service Bus resources..."
    
    local namespace_info
    namespace_info=$(az servicebus namespace show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${SERVICEBUS_NAMESPACE}" \
        --query '{name:name, status:status, tier:sku.tier, location:location}' \
        --output json)
    
    log_info "Namespace details: ${namespace_info}"
    
    local queue_info
    queue_info=$(az servicebus queue show \
        --resource-group "${RESOURCE_GROUP}" \
        --namespace-name "${SERVICEBUS_NAMESPACE}" \
        --name "${QUEUE_NAME}" \
        --query '{name:name, status:status, messageCount:messageCount, sizeInBytes:sizeInBytes}' \
        --output json)
    
    log_info "Queue details: ${queue_info}"
    
    # Run messaging tests
    local test_dir="${SCRIPT_DIR}/servicebus-test"
    if [[ -d "${test_dir}" ]]; then
        log_info "Running messaging tests..."
        cd "${test_dir}"
        
        # Export environment variables for the test
        export CONNECTION_STRING
        export QUEUE_NAME
        
        # Run the test
        if ./test-messaging.sh; then
            log_success "All validation tests passed!"
        else
            log_error "Validation tests failed"
            return 1
        fi
        
        cd "${SCRIPT_DIR}"
    else
        log_warn "Test directory not found. Skipping messaging tests."
    fi
}

# =============================================================================
# MAIN DEPLOYMENT FUNCTION
# =============================================================================

deploy_infrastructure() {
    log_info "Starting Azure Service Bus deployment..."
    log_info "Log file: ${LOG_FILE}"
    
    # Check prerequisites
    check_prerequisites
    
    # Generate unique names
    generate_unique_names
    
    # Create Azure resources
    create_resource_group
    create_servicebus_namespace
    create_servicebus_queue
    retrieve_connection_string
    
    # Setup testing environment
    setup_test_application
    
    # Run validation tests
    run_validation_tests
    
    log_success "Deployment completed successfully!"
    
    # Display deployment summary
    echo ""
    echo "======================================================================"
    echo "DEPLOYMENT SUMMARY"
    echo "======================================================================"
    echo "Resource Group:       ${RESOURCE_GROUP}"
    echo "Service Bus Namespace: ${SERVICEBUS_NAMESPACE}"
    echo "Queue Name:           ${QUEUE_NAME}"
    echo "Location:             ${LOCATION}"
    echo "Subscription:         ${SUBSCRIPTION_NAME}"
    echo ""
    echo "Connection String:"
    echo "${CONNECTION_STRING}"
    echo ""
    echo "Next Steps:"
    echo "1. Use the connection string to connect your applications"
    echo "2. Configure your applications to send/receive messages"
    echo "3. Monitor queue metrics in the Azure portal"
    echo "4. Run 'destroy.sh' when you want to clean up resources"
    echo ""
    echo "Cost Management:"
    echo "- Standard tier charges: ~\$0.05 per million operations"
    echo "- Base messaging unit charges apply"
    echo "- Monitor usage in Azure Cost Management"
    echo "======================================================================"
}

# =============================================================================
# COMMAND LINE ARGUMENT PARSING
# =============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -q|--queue-name)
                QUEUE_NAME="$2"
                shift 2
                ;;
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -n|--namespace)
                SERVICEBUS_NAMESPACE="$2"
                shift 2
                ;;
            --skip-test)
                ENABLE_TESTING="false"
                shift
                ;;
            --dry-run)
                log_info "DRY RUN MODE - No resources will be created"
                log_info "Would deploy Service Bus namespace with queue to ${LOCATION}"
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log_info "Azure Service Bus Deployment Script Starting..."
    log_info "Script: ${SCRIPT_NAME}"
    log_info "Version: 1.0"
    log_info "Date: $(date)"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Run deployment
    deploy_infrastructure
    
    log_success "Script execution completed successfully!"
}

# Execute main function with all arguments
main "$@"