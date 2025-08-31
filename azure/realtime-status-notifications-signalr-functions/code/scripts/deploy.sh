#!/bin/bash

# Real-time Status Notifications with SignalR and Functions - Deployment Script
# This script deploys Azure SignalR Service and Azure Functions for real-time notifications

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to generate random suffix
generate_random_suffix() {
    if command_exists openssl; then
        openssl rand -hex 3
    elif command_exists date; then
        date +%s | tail -c 7
    else
        echo "$(shuf -i 100000-999999 -n 1)"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check Azure Functions Core Tools
    if ! command_exists func; then
        log_warning "Azure Functions Core Tools not found. Installing via npm..."
        if command_exists npm; then
            npm install -g azure-functions-core-tools@4 --unsafe-perm true
        else
            log_error "npm is not available. Please install Azure Functions Core Tools manually."
            log_error "Visit: https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local"
            exit 1
        fi
    fi
    
    # Check Node.js
    if ! command_exists node; then
        log_error "Node.js is not installed. Please install Node.js 18 or later."
        exit 1
    fi
    
    # Check Node.js version
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 18 ]; then
        log_error "Node.js version 18 or later is required. Current version: $(node --version)"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
set_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Set default values or use existing environment variables
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-recipe-$(generate_random_suffix)}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(generate_random_suffix)
    export SIGNALR_NAME="${SIGNALR_NAME:-signalr${RANDOM_SUFFIX}}"
    export FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func${RANDOM_SUFFIX}}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-storage${RANDOM_SUFFIX}}"
    
    # Validate resource name lengths and format
    if [ ${#SIGNALR_NAME} -gt 63 ]; then
        log_error "SignalR name too long: ${SIGNALR_NAME}"
        exit 1
    fi
    
    if [ ${#FUNCTION_APP_NAME} -gt 60 ]; then
        log_error "Function App name too long: ${FUNCTION_APP_NAME}"
        exit 1
    fi
    
    if [ ${#STORAGE_ACCOUNT} -gt 24 ]; then
        log_error "Storage account name too long: ${STORAGE_ACCOUNT}"
        exit 1
    fi
    
    # Save variables to file for cleanup script
    cat > .env << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
SIGNALR_NAME=${SIGNALR_NAME}
FUNCTION_APP_NAME=${FUNCTION_APP_NAME}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
EOF
    
    log_success "Environment variables configured"
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "SignalR Service: ${SIGNALR_NAME}"
    log_info "Function App: ${FUNCTION_APP_NAME}"
    log_info "Storage Account: ${STORAGE_ACCOUNT}"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}..."
    
    if az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=recipe environment=demo created_by=deploy_script
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Function to create SignalR Service
create_signalr_service() {
    log_info "Creating Azure SignalR Service: ${SIGNALR_NAME}..."
    
    if az signalr show --name "${SIGNALR_NAME}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "SignalR Service ${SIGNALR_NAME} already exists"
    else
        az signalr create \
            --name "${SIGNALR_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Free_F1 \
            --service-mode Serverless \
            --tags purpose=recipe created_by=deploy_script
        
        log_success "SignalR Service created: ${SIGNALR_NAME}"
    fi
    
    # Get connection string
    log_info "Retrieving SignalR connection string..."
    SIGNALR_CONNECTION=$(az signalr key list \
        --name "${SIGNALR_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query primaryConnectionString \
        --output tsv)
    
    if [ -z "$SIGNALR_CONNECTION" ]; then
        log_error "Failed to retrieve SignalR connection string"
        exit 1
    fi
    
    # Save connection string to environment file
    echo "SIGNALR_CONNECTION=${SIGNALR_CONNECTION}" >> .env
    
    log_success "SignalR connection string retrieved"
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT}..."
    
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Storage account ${STORAGE_ACCOUNT} already exists"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --tags purpose=recipe created_by=deploy_script
        
        log_success "Storage account created: ${STORAGE_ACCOUNT}"
    fi
}

# Function to create Function App
create_function_app() {
    log_info "Creating Function App: ${FUNCTION_APP_NAME}..."
    
    if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Function App ${FUNCTION_APP_NAME} already exists"
    else
        az functionapp create \
            --name "${FUNCTION_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --consumption-plan-location "${LOCATION}" \
            --storage-account "${STORAGE_ACCOUNT}" \
            --runtime node \
            --runtime-version 18 \
            --functions-version 4 \
            --tags purpose=recipe created_by=deploy_script
        
        log_success "Function App created: ${FUNCTION_APP_NAME}"
    fi
}

# Function to configure Function App settings
configure_function_app() {
    log_info "Configuring Function App settings..."
    
    # Set SignalR connection string
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "AzureSignalRConnectionString=${SIGNALR_CONNECTION}"
    
    # Enable CORS for web client access
    az functionapp cors add \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --allowed-origins "*"
    
    log_success "Function App configured with SignalR connection"
}

# Function to create and deploy Functions
create_and_deploy_functions() {
    log_info "Creating Functions project..."
    
    # Create temporary directory for Functions project
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Initialize Functions project
    func init signalr-functions --javascript --worker-runtime node --model V4
    cd signalr-functions
    
    # Install dependencies
    npm install @azure/functions
    
    # Create negotiate function
    log_info "Creating negotiate function..."
    mkdir -p src/functions
    cat > src/functions/negotiate.js << 'EOF'
const { app, input } = require('@azure/functions');

const inputSignalR = input.generic({
    type: 'signalRConnectionInfo',
    name: 'connectionInfo',
    hubName: 'notifications',
    connectionStringSetting: 'AzureSignalRConnectionString'
});

app.http('negotiate', {
    methods: ['GET', 'POST'],
    authLevel: 'anonymous',
    extraInputs: [inputSignalR],
    handler: async (context) => {
        return { 
            body: JSON.stringify(context.extraInputs.get('connectionInfo'))
        };
    }
});
EOF
    
    # Create broadcast function
    log_info "Creating broadcast function..."
    cat > src/functions/broadcast.js << 'EOF'
const { app, output } = require('@azure/functions');

const outputSignalR = output.generic({
    type: 'signalR',
    name: 'signalRMessages',
    hubName: 'notifications',
    connectionStringSetting: 'AzureSignalRConnectionString'
});

app.timer('broadcast', {
    schedule: '0 */30 * * * *', // Every 30 seconds for demo (consider longer intervals for production)
    extraOutputs: [outputSignalR],
    handler: async (myTimer, context) => {
        const statusMessage = {
            target: 'statusUpdate',
            arguments: [{
                timestamp: new Date().toISOString(),
                status: 'System operational',
                message: 'All services running normally',
                serverName: process.env.WEBSITE_SITE_NAME || 'unknown'
            }]
        };

        context.extraOutputs.set(outputSignalR, statusMessage);
        context.log('Status broadcast sent:', statusMessage);
    }
});
EOF
    
    # Deploy to Azure
    log_info "Deploying Functions to Azure..."
    func azure functionapp publish "${FUNCTION_APP_NAME}" --javascript
    
    # Get Function App URL
    FUNCTION_URL=$(az functionapp show \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query defaultHostName \
        --output tsv)
    
    # Save Function URL to environment file
    echo "FUNCTION_URL=${FUNCTION_URL}" >> "${OLDPWD}/.env"
    
    log_success "Functions deployed to: https://${FUNCTION_URL}"
    
    # Return to original directory
    cd "${OLDPWD}"
    
    # Clean up temporary directory
    rm -rf "${TEMP_DIR}"
}

# Function to create test client
create_test_client() {
    log_info "Creating test client..."
    
    # Load Function URL from environment
    if [ -f .env ]; then
        source .env
    fi
    
    cat > test-client.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>SignalR Real-time Status Notifications</title>
    <script src="https://unpkg.com/@microsoft/signalr@latest/dist/browser/signalr.min.js"></script>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            margin: 20px; 
            background-color: #f5f5f5;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 { color: #333; }
        #status { 
            padding: 10px; 
            margin: 10px 0; 
            border-radius: 4px;
            font-weight: bold;
        }
        .connected { background-color: #d4edda; color: #155724; }
        .connecting { background-color: #fff3cd; color: #856404; }
        .error { background-color: #f8d7da; color: #721c24; }
        #messages { 
            border: 1px solid #ddd; 
            padding: 15px; 
            min-height: 300px; 
            max-height: 400px;
            overflow-y: auto;
            border-radius: 4px;
            background: #fafafa;
        }
        .message { 
            margin: 8px 0; 
            padding: 8px 12px; 
            background: #e9ecef;
            border-left: 4px solid #007bff;
            border-radius: 4px;
        }
        .timestamp { color: #6c757d; font-size: 0.9em; }
        .clear-btn {
            background-color: #6c757d;
            color: white;
            border: none;
            padding: 8px 16px;
            border-radius: 4px;
            cursor: pointer;
            margin: 10px 0;
        }
        .clear-btn:hover { background-color: #5a6268; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔔 Real-time Status Notifications</h1>
        <div id="status" class="connecting">Connecting to SignalR...</div>
        <button class="clear-btn" onclick="clearMessages()">Clear Messages</button>
        <div id="messages"></div>
    </div>

    <script>
        const connection = new signalR.HubConnectionBuilder()
            .withUrl('https://${FUNCTION_URL}/api')
            .withAutomaticReconnect()
            .build();

        connection.on('statusUpdate', function (data) {
            console.log('Received status update:', data);
            const messages = document.getElementById('messages');
            const messageDiv = document.createElement('div');
            messageDiv.className = 'message';
            messageDiv.innerHTML = 
                '<div class="timestamp">' + data.timestamp + '</div>' +
                '<strong>Status:</strong> ' + data.status + '<br>' +
                '<strong>Message:</strong> ' + data.message +
                (data.serverName ? '<br><strong>Server:</strong> ' + data.serverName : '');
            messages.appendChild(messageDiv);
            messages.scrollTop = messages.scrollHeight;
        });

        connection.onreconnecting(() => {
            const status = document.getElementById('status');
            status.innerHTML = 'Reconnecting to SignalR...';
            status.className = 'connecting';
        });

        connection.onreconnected(() => {
            const status = document.getElementById('status');
            status.innerHTML = '✅ Reconnected to SignalR';
            status.className = 'connected';
        });

        connection.onclose(() => {
            const status = document.getElementById('status');
            status.innerHTML = '❌ Disconnected from SignalR';
            status.className = 'error';
        });

        function clearMessages() {
            document.getElementById('messages').innerHTML = '';
        }

        // Start connection
        connection.start().then(function () {
            const status = document.getElementById('status');
            status.innerHTML = '✅ Connected to SignalR - Waiting for status updates...';
            status.className = 'connected';
            console.log('Connected to SignalR');
        }).catch(function (err) {
            const status = document.getElementById('status');
            status.innerHTML = '❌ Connection failed: ' + err.message;
            status.className = 'error';
            console.error(err.toString());
        });
    </script>
</body>
</html>
EOF
    
    log_success "Test client created: test-client.html"
    log_info "Open test-client.html in your browser to test real-time notifications"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check SignalR Service status
    SIGNALR_STATUS=$(az signalr show \
        --name "${SIGNALR_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query provisioningState \
        --output tsv 2>/dev/null || echo "NotFound")
    
    if [ "$SIGNALR_STATUS" = "Succeeded" ]; then
        log_success "SignalR Service is running"
    else
        log_error "SignalR Service status: $SIGNALR_STATUS"
        return 1
    fi
    
    # Check Function App status
    FUNCTION_STATUS=$(az functionapp show \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query state \
        --output tsv 2>/dev/null || echo "NotFound")
    
    if [ "$FUNCTION_STATUS" = "Running" ]; then
        log_success "Function App is running"
    else
        log_error "Function App status: $FUNCTION_STATUS"
        return 1
    fi
    
    # Test negotiate endpoint
    log_info "Testing negotiate endpoint..."
    if [ -f .env ]; then
        source .env
    fi
    
    NEGOTIATE_RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null "https://${FUNCTION_URL}/api/negotiate" || echo "000")
    
    if [ "$NEGOTIATE_RESPONSE" = "200" ]; then
        log_success "Negotiate endpoint is responding"
    else
        log_warning "Negotiate endpoint returned HTTP $NEGOTIATE_RESPONSE (this is normal during initial deployment)"
    fi
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log_success "=== DEPLOYMENT COMPLETE ==="
    echo ""
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "SignalR Service: ${SIGNALR_NAME}"
    log_info "Function App: ${FUNCTION_APP_NAME}"
    log_info "Storage Account: ${STORAGE_ACCOUNT}"
    
    if [ -f .env ]; then
        source .env
        echo ""
        log_info "Function App URL: https://${FUNCTION_URL}"
        log_info "Negotiate Endpoint: https://${FUNCTION_URL}/api/negotiate"
    fi
    
    echo ""
    log_info "Next steps:"
    echo "  1. Open test-client.html in your browser"
    echo "  2. Watch for real-time status updates every 30 seconds"
    echo "  3. Check Azure portal for resource monitoring"
    echo ""
    log_info "To clean up resources, run: ./destroy.sh"
    echo ""
}

# Main deployment function
main() {
    log_info "Starting Azure SignalR and Functions deployment..."
    
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_signalr_service
    create_storage_account
    create_function_app
    configure_function_app
    create_and_deploy_functions
    create_test_client
    validate_deployment
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Handle script interruption
trap 'log_error "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"