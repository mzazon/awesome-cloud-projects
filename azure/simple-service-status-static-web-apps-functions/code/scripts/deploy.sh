#!/bin/bash

# Azure Service Status Page Deployment Script
# Recipe: Simple Service Status Page with Static Web Apps and Functions
# Version: 1.1
# Last Updated: 2025-07-12

set -euo pipefail
IFS=$'\n\t'

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log_info "Checking if resource group exists for cleanup..."
        if az group show --name "${RESOURCE_GROUP}" --output none 2>/dev/null; then
            log_warning "Deleting resource group: ${RESOURCE_GROUP}"
            az group delete --name "${RESOURCE_GROUP}" --yes --no-wait || true
        fi
    fi
    
    if [[ -d "${PROJECT_DIR:-}" ]]; then
        log_info "Cleaning up temporary project directory..."
        rm -rf "${PROJECT_DIR}" || true
    fi
    
    exit 1
}

trap cleanup_on_error ERR

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        log_info "Install guide: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version (minimum 2.29.0)
    local az_version
    az_version=$(az version --query '"azure-cli"' --output tsv)
    local required_version="2.29.0"
    
    if ! printf '%s\n' "${required_version}" "${az_version}" | sort -V -C; then
        log_error "Azure CLI version ${az_version} is too old. Minimum required: ${required_version}"
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show --output none 2>/dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if Node.js is installed (required for Static Web Apps CLI)
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed. Please install Node.js v18+ first."
        log_info "Download from: https://nodejs.org/"
        exit 1
    fi
    
    # Check Node.js version (minimum v18)
    local node_version
    node_version=$(node --version | sed 's/v//')
    local required_node_version="18.0.0"
    
    if ! printf '%s\n' "${required_node_version}" "${node_version}" | sort -V -C; then
        log_error "Node.js version ${node_version} is too old. Minimum required: v${required_node_version}"
        exit 1
    fi
    
    # Check if npm is available
    if ! command -v npm &> /dev/null; then
        log_error "npm is not installed. Please install npm first."
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Required for generating unique resource names."
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Configuration
set_configuration() {
    log_info "Setting up configuration..."
    
    # Generate unique suffix for resource names
    readonly RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables
    export RESOURCE_GROUP="rg-recipe-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export STATIC_WEB_APP_NAME="status-page-${RANDOM_SUFFIX}"
    export PROJECT_NAME="status-page"
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Create project directory in temp location
    export PROJECT_DIR="/tmp/${PROJECT_NAME}-${RANDOM_SUFFIX}"
    
    log_info "Configuration set:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Location: ${LOCATION}"
    log_info "  Static Web App: ${STATIC_WEB_APP_NAME}"
    log_info "  Subscription ID: ${SUBSCRIPTION_ID}"
    log_info "  Project Directory: ${PROJECT_DIR}"
}

# Create Azure resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=recipe environment=demo \
        --output none
    
    log_success "Resource group created: ${RESOURCE_GROUP}"
}

# Create project structure
create_project_structure() {
    log_info "Creating project directory structure..."
    
    mkdir -p "${PROJECT_DIR}"/{public,api}
    cd "${PROJECT_DIR}"
    
    # Initialize the API with Functions v4 configuration
    cd api
    npm init -y --silent
    npm install @azure/functions --silent
    
    log_success "Project structure created at: ${PROJECT_DIR}"
    cd ..
}

# Create frontend status page
create_frontend() {
    log_info "Creating frontend status page..."
    
    cat > public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Service Status Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { text-align: center; margin-bottom: 30px; }
        .service { display: flex; justify-content: space-between; align-items: center; padding: 15px; margin: 10px 0; border-radius: 5px; background: #f8f9fa; }
        .status { padding: 5px 15px; border-radius: 20px; color: white; font-weight: bold; }
        .operational { background: #28a745; }
        .degraded { background: #ffc107; color: #212529; }
        .outage { background: #dc3545; }
        .loading { background: #6c757d; }
        .last-updated { text-align: center; margin-top: 20px; color: #6c757d; font-size: 14px; }
        .refresh-btn { background: #0078d4; color: white; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer; margin: 10px auto; display: block; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Service Status Dashboard</h1>
            <p>Real-time monitoring of our service infrastructure</p>
        </div>
        <div id="services">
            <p>Loading service status...</p>
        </div>
        <button class="refresh-btn" onclick="loadStatus()">Refresh Status</button>
        <div class="last-updated" id="lastUpdated"></div>
    </div>

    <script>
        async function loadStatus() {
            try {
                const response = await fetch('/api/status');
                const data = await response.json();
                displayServices(data.services);
                document.getElementById('lastUpdated').textContent = 
                    `Last updated: ${new Date(data.timestamp).toLocaleString()}`;
            } catch (error) {
                document.getElementById('services').innerHTML = 
                    '<p style="color: red;">Failed to load service status</p>';
            }
        }

        function displayServices(services) {
            const servicesDiv = document.getElementById('services');
            servicesDiv.innerHTML = services.map(service => `
                <div class="service">
                    <div>
                        <strong>${service.name}</strong>
                        <br><small>${service.url}</small>
                    </div>
                    <span class="status ${service.status.toLowerCase()}">${service.status}</span>
                </div>
            `).join('');
        }

        // Load status on page load and refresh every 30 seconds
        loadStatus();
        setInterval(loadStatus, 30000);
    </script>
</body>
</html>
EOF
    
    log_success "Frontend status page created"
}

# Create Azure Functions API
create_functions_api() {
    log_info "Creating Azure Functions v4 API endpoint..."
    
    # Create Functions v4 host configuration
    cat > api/host.json << 'EOF'
{
  "version": "2.0",
  "functionTimeout": "00:05:00",
  "extensions": {
    "http": {
      "routePrefix": "api"
    }
  }
}
EOF

    # Create package.json with v4 configuration
    cat > api/package.json << 'EOF'
{
  "name": "status-api",
  "version": "1.0.0",
  "description": "Service status monitoring API",
  "main": "src/functions/*.js",
  "scripts": {
    "start": "func start",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "dependencies": {
    "@azure/functions": "^4.0.0"
  },
  "devDependencies": {
    "azure-functions-core-tools": "^4.x"
  }
}
EOF

    # Create the status function using v4 model
    mkdir -p api/src/functions
    cat > api/src/functions/status.js << 'EOF'
const { app } = require('@azure/functions');
const https = require('https');
const http = require('http');

// Configure HTTP agent for connection reuse
const httpAgent = new http.Agent({ keepAlive: true, maxSockets: 10 });
const httpsAgent = new https.Agent({ keepAlive: true, maxSockets: 10 });

// Services to monitor
const SERVICES = [
    { name: 'GitHub API', url: 'https://api.github.com/status' },
    { name: 'JSONPlaceholder', url: 'https://jsonplaceholder.typicode.com/posts/1' },
    { name: 'HTTPBin', url: 'https://httpbin.org/status/200' }
];

async function checkServiceHealth(service) {
    return new Promise((resolve) => {
        const startTime = Date.now();
        const url = new URL(service.url);
        const options = {
            hostname: url.hostname,
            port: url.port || (url.protocol === 'https:' ? 443 : 80),
            path: url.pathname + url.search,
            method: 'GET',
            agent: url.protocol === 'https:' ? httpsAgent : httpAgent,
            timeout: 5000,
            headers: {
                'User-Agent': 'Azure-Functions-Status-Monitor/1.0'
            }
        };

        const client = url.protocol === 'https:' ? https : http;
        const req = client.request(options, (res) => {
            const responseTime = Date.now() - startTime;
            let status = 'OUTAGE';
            
            if (res.statusCode >= 200 && res.statusCode < 300) {
                status = 'OPERATIONAL';
            } else if (res.statusCode >= 300 && res.statusCode < 500) {
                status = 'DEGRADED';
            }

            resolve({
                name: service.name,
                url: service.url,
                status: status,
                responseTime: responseTime,
                httpCode: res.statusCode
            });
        });

        req.on('timeout', () => {
            req.destroy();
            resolve({
                name: service.name,
                url: service.url,
                status: 'OUTAGE',
                responseTime: 5000,
                httpCode: null,
                error: 'Timeout'
            });
        });

        req.on('error', (error) => {
            resolve({
                name: service.name,
                url: service.url,
                status: 'OUTAGE',
                responseTime: Date.now() - startTime,
                httpCode: null,
                error: error.message
            });
        });

        req.end();
    });
}

app.http('status', {
    methods: ['GET'],
    authLevel: 'anonymous',
    handler: async (request, context) => {
        context.log('Service status check initiated');

        try {
            // Check all services in parallel
            const serviceChecks = SERVICES.map(service => checkServiceHealth(service));
            const results = await Promise.all(serviceChecks);

            // Calculate overall status
            const operationalCount = results.filter(r => r.status === 'OPERATIONAL').length;
            const totalCount = results.length;
            let overallStatus = 'OPERATIONAL';
            
            if (operationalCount === 0) {
                overallStatus = 'OUTAGE';
            } else if (operationalCount < totalCount) {
                overallStatus = 'DEGRADED';
            }

            const response = {
                overall: overallStatus,
                services: results,
                timestamp: new Date().toISOString(),
                totalServices: totalCount,
                operationalServices: operationalCount
            };

            context.log(`Status check completed: ${operationalCount}/${totalCount} services operational`);

            return {
                status: 200,
                headers: {
                    'Content-Type': 'application/json',
                    'Cache-Control': 'no-cache'
                },
                jsonBody: response
            };
        } catch (error) {
            context.log.error('Error during status check:', error);
            
            return {
                status: 500,
                headers: { 'Content-Type': 'application/json' },
                jsonBody: {
                    error: 'Failed to check service status',
                    timestamp: new Date().toISOString()
                }
            };
        }
    }
});
EOF
    
    log_success "Azure Functions v4 API endpoint created"
}

# Create Static Web Apps configuration
create_swa_config() {
    log_info "Creating Static Web Apps configuration..."
    
    cat > public/staticwebapp.config.json << 'EOF'
{
  "routes": [
    {
      "route": "/api/*",
      "allowedRoles": ["anonymous"]
    },
    {
      "route": "/*",
      "serve": "/index.html",
      "statusCode": 200
    }
  ],
  "responseOverrides": {
    "404": {
      "serve": "/index.html"
    }
  },
  "platform": {
    "apiRuntime": "node:18"
  }
}
EOF
    
    log_success "Static Web Apps configuration created"
}

# Deploy Static Web App
deploy_static_web_app() {
    log_info "Creating Static Web App: ${STATIC_WEB_APP_NAME}"
    
    az staticwebapp create \
        --name "${STATIC_WEB_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --app-location "public" \
        --api-location "api" \
        --output none
    
    log_success "Static Web App created: ${STATIC_WEB_APP_NAME}"
}

# Deploy application code
deploy_application_code() {
    log_info "Installing Static Web Apps CLI..."
    
    # Check if SWA CLI is already installed globally
    if ! command -v swa &> /dev/null; then
        npm install -g @azure/static-web-apps-cli@2.0.2 --silent
        log_success "Static Web Apps CLI installed"
    else
        log_info "Static Web Apps CLI already installed"
    fi
    
    log_info "Getting deployment token..."
    local deployment_token
    deployment_token=$(az staticwebapp secrets list \
        --name "${STATIC_WEB_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "properties.apiKey" --output tsv)
    
    if [[ -z "${deployment_token}" ]]; then
        log_error "Failed to retrieve deployment token"
        exit 1
    fi
    
    log_info "Deploying application code..."
    swa deploy ./public \
        --api-location ./api \
        --deployment-token "${deployment_token}" \
        --verbose=false
    
    log_success "Application deployed successfully"
}

# Get deployment information
get_deployment_info() {
    log_info "Retrieving deployment information..."
    
    local app_url
    app_url=$(az staticwebapp show \
        --name "${STATIC_WEB_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "defaultHostname" --output tsv)
    
    if [[ -z "${app_url}" ]]; then
        log_error "Failed to retrieve application URL"
        exit 1
    fi
    
    # Save deployment info to file for destroy script
    cat > "${PROJECT_DIR}/deployment_info.txt" << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
STATIC_WEB_APP_NAME=${STATIC_WEB_APP_NAME}
LOCATION=${LOCATION}
APP_URL=https://${app_url}
PROJECT_DIR=${PROJECT_DIR}
DEPLOYMENT_DATE=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
EOF
    
    echo
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo
    log_info "📋 Deployment Summary:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Static Web App: ${STATIC_WEB_APP_NAME}"
    log_info "  Location: ${LOCATION}"
    echo
    log_info "🌐 Application URLs:"
    log_info "  Status Page: https://${app_url}"
    log_info "  API Endpoint: https://${app_url}/api/status"
    echo
    log_info "📁 Deployment Info Saved: ${PROJECT_DIR}/deployment_info.txt"
    echo
    log_warning "💡 Next Steps:"
    log_info "  1. Open the status page URL in your browser"
    log_info "  2. Verify the service status indicators are working"
    log_info "  3. Test the API endpoint directly"
    log_info "  4. Use destroy.sh script to clean up when finished"
    echo
}

# Test deployment
test_deployment() {
    log_info "Testing deployment..."
    
    local app_url
    app_url=$(az staticwebapp show \
        --name "${STATIC_WEB_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "defaultHostname" --output tsv)
    
    # Wait for deployment to be ready
    log_info "Waiting for deployment to be ready (this may take a few minutes)..."
    local retries=0
    local max_retries=30
    
    while [[ ${retries} -lt ${max_retries} ]]; do
        if curl -s -f "https://${app_url}/api/status" > /dev/null 2>&1; then
            log_success "API endpoint is responding"
            break
        fi
        
        retries=$((retries + 1))
        log_info "Waiting for API to be ready... (attempt ${retries}/${max_retries})"
        sleep 10
    done
    
    if [[ ${retries} -eq ${max_retries} ]]; then
        log_warning "API endpoint did not respond within expected time. This is normal for initial deployments."
        log_info "Please wait a few more minutes and try accessing the URL manually."
    fi
}

# Main deployment function
main() {
    echo
    log_info "🚀 Starting Azure Service Status Page deployment..."
    echo
    
    check_prerequisites
    set_configuration
    create_resource_group
    create_project_structure
    create_frontend
    create_functions_api
    create_swa_config
    deploy_static_web_app
    deploy_application_code
    get_deployment_info
    test_deployment
    
    echo
    log_success "🎉 Deployment completed successfully!"
    echo
}

# Dry run option
if [[ "${1:-}" == "--dry-run" ]]; then
    log_info "DRY RUN MODE - No resources will be created"
    log_info "Would execute:"
    log_info "  - Prerequisites check"
    log_info "  - Configuration setup"
    log_info "  - Resource group creation"
    log_info "  - Project structure creation"
    log_info "  - Frontend and API code generation"
    log_info "  - Static Web App deployment"
    log_info "  - Application code deployment"
    exit 0
fi

# Help option
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Azure Service Status Page Deployment Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --dry-run    Show what would be deployed without creating resources"
    echo "  --help, -h   Show this help message"
    echo
    echo "Environment Variables:"
    echo "  AZURE_LOCATION    Azure region for deployment (default: eastus)"
    echo
    echo "Examples:"
    echo "  $0                           # Deploy with default settings"
    echo "  AZURE_LOCATION=westus2 $0    # Deploy to West US 2 region"
    echo "  $0 --dry-run                 # Show deployment plan"
    echo
    exit 0
fi

# Execute main function
main "$@"