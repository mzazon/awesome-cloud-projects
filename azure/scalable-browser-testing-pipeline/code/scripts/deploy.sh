#!/bin/bash

# =============================================================================
# Azure Playwright Testing and Application Insights Deployment Script
# Recipe: Scalable Browser Testing Pipeline with Playwright Testing and Application Insights
# =============================================================================

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "${LOG_FILE}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "${LOG_FILE}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "${LOG_FILE}"
}

# Default values
DEFAULT_RESOURCE_GROUP="rg-playwright-testing"
DEFAULT_LOCATION="eastus"
DRY_RUN=false
SKIP_CONFIRMATION=false

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Playwright Testing and Application Insights infrastructure.

OPTIONS:
    -g, --resource-group NAME    Resource group name (default: ${DEFAULT_RESOURCE_GROUP})
    -l, --location LOCATION      Azure region (default: ${DEFAULT_LOCATION})
    -d, --dry-run               Show what would be deployed without executing
    -y, --yes                   Skip confirmation prompts
    -h, --help                  Show this help message

EXAMPLES:
    $0                          # Deploy with default settings
    $0 -g my-rg -l westus2      # Deploy to specific resource group and region
    $0 --dry-run                # Preview deployment without executing
    $0 -y                       # Deploy without confirmation prompts

EOF
}

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
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Set default values if not provided
RESOURCE_GROUP="${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}"
LOCATION="${LOCATION:-$DEFAULT_LOCATION}"

# Generate unique resource names
RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
KEYVAULT_NAME="kv-playwright-${RANDOM_SUFFIX}"
AI_NAME="ai-playwright-testing"
WORKSPACE_NAME="playwright-workspace-${RANDOM_SUFFIX}"
LAW_NAME="law-playwright-${RANDOM_SUFFIX}"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log "Azure CLI version: ${AZ_VERSION}"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if Node.js is available (for Playwright setup)
    if ! command -v node &> /dev/null; then
        warn "Node.js is not installed. This is required for Playwright test setup."
        warn "Please install Node.js 18.x or later from https://nodejs.org/"
    else
        NODE_VERSION=$(node --version)
        log "Node.js version: ${NODE_VERSION}"
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        warn "OpenSSL is not available. Using timestamp for unique suffixes."
    fi
    
    # Get current subscription info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    USER_NAME=$(az account show --query user.name --output tsv)
    
    log "Current Azure subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"
    log "Current user: ${USER_NAME}"
    
    # Check if the specified location is valid
    if ! az account list-locations --query "[?name=='${LOCATION}'].name" -o tsv | grep -q "${LOCATION}"; then
        error "Location '${LOCATION}' is not valid for your subscription."
        info "Available locations:"
        az account list-locations --query "[].name" -o tsv | sort
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to validate Azure Playwright Testing availability
check_playwright_testing_availability() {
    log "Checking Azure Playwright Testing availability..."
    
    # Note: Azure Playwright Testing is in preview and may not be available in all regions
    case "${LOCATION}" in
        "eastus"|"westus3"|"eastasia"|"westeurope")
            log "Azure Playwright Testing is supported in ${LOCATION}"
            ;;
        *)
            warn "Azure Playwright Testing may not be available in ${LOCATION}"
            warn "Supported regions: eastus, westus3, eastasia, westeurope"
            if [[ "${SKIP_CONFIRMATION}" == "false" ]]; then
                read -p "Continue anyway? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    info "Deployment cancelled by user"
                    exit 0
                fi
            fi
            ;;
    esac
}

# Function to show deployment plan
show_deployment_plan() {
    log "Deployment Plan:"
    echo "=================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "Key Vault: ${KEYVAULT_NAME}"
    echo "Application Insights: ${AI_NAME}"
    echo "Log Analytics Workspace: ${LAW_NAME}"
    echo "Playwright Workspace: ${WORKSPACE_NAME}"
    echo "=================="
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN MODE - No resources will be created"
        return 0
    fi
    
    if [[ "${SKIP_CONFIRMATION}" == "false" ]]; then
        read -p "Proceed with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Deployment cancelled by user"
            exit 0
        fi
    fi
}

# Function to create resource group
create_resource_group() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create resource group: ${RESOURCE_GROUP}"
        return 0
    fi
    
    log "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=e2e-testing environment=testing created-by=deploy-script
        
        log "✅ Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Function to create Log Analytics workspace
create_log_analytics_workspace() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create Log Analytics workspace: ${LAW_NAME}"
        return 0
    fi
    
    log "Creating Log Analytics workspace: ${LAW_NAME}"
    
    WORKSPACE_ID=$(az monitor log-analytics workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LAW_NAME}" \
        --location "${LOCATION}" \
        --query id --output tsv)
    
    if [[ -n "${WORKSPACE_ID}" ]]; then
        log "✅ Log Analytics workspace created: ${LAW_NAME}"
        echo "WORKSPACE_ID=${WORKSPACE_ID}" >> "${SCRIPT_DIR}/deployment.env"
    else
        error "Failed to create Log Analytics workspace"
        exit 1
    fi
}

# Function to create Application Insights
create_application_insights() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create Application Insights: ${AI_NAME}"
        return 0
    fi
    
    log "Creating Application Insights: ${AI_NAME}"
    
    # Get workspace ID from environment file or create it
    if [[ -f "${SCRIPT_DIR}/deployment.env" ]]; then
        source "${SCRIPT_DIR}/deployment.env"
    fi
    
    if [[ -z "${WORKSPACE_ID:-}" ]]; then
        error "Log Analytics workspace ID not found. Please ensure the workspace is created first."
        exit 1
    fi
    
    AI_CONNECTION_STRING=$(az monitor app-insights component create \
        --app "${AI_NAME}" \
        --location "${LOCATION}" \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace "${WORKSPACE_ID}" \
        --application-type web \
        --query connectionString --output tsv)
    
    if [[ -n "${AI_CONNECTION_STRING}" ]]; then
        log "✅ Application Insights created: ${AI_NAME}"
        echo "AI_CONNECTION_STRING=${AI_CONNECTION_STRING}" >> "${SCRIPT_DIR}/deployment.env"
    else
        error "Failed to create Application Insights"
        exit 1
    fi
}

# Function to create Key Vault
create_key_vault() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create Key Vault: ${KEYVAULT_NAME}"
        return 0
    fi
    
    log "Creating Key Vault: ${KEYVAULT_NAME}"
    
    az keyvault create \
        --name "${KEYVAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --enable-rbac-authorization true \
        --sku standard \
        --retention-days 7
    
    # Get current user's object ID for permissions
    USER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv)
    
    # Assign Key Vault Secrets Officer role to current user
    KEYVAULT_ID=$(az keyvault show --name "${KEYVAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" --query id --output tsv)
    
    az role assignment create \
        --role "Key Vault Secrets Officer" \
        --assignee "${USER_OBJECT_ID}" \
        --scope "${KEYVAULT_ID}"
    
    log "✅ Key Vault created: ${KEYVAULT_NAME}"
    echo "KEYVAULT_NAME=${KEYVAULT_NAME}" >> "${SCRIPT_DIR}/deployment.env"
    
    # Wait a moment for role assignment to propagate
    sleep 10
}

# Function to store secrets in Key Vault
store_secrets() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would store secrets in Key Vault"
        return 0
    fi
    
    log "Storing secrets in Key Vault"
    
    # Load environment variables
    if [[ -f "${SCRIPT_DIR}/deployment.env" ]]; then
        source "${SCRIPT_DIR}/deployment.env"
    fi
    
    if [[ -z "${AI_CONNECTION_STRING:-}" ]]; then
        error "Application Insights connection string not found"
        exit 1
    fi
    
    # Store Application Insights connection string
    az keyvault secret set \
        --vault-name "${KEYVAULT_NAME}" \
        --name "AppInsightsConnectionString" \
        --value "${AI_CONNECTION_STRING}" \
        --output none
    
    # Store test application URL (placeholder)
    az keyvault secret set \
        --vault-name "${KEYVAULT_NAME}" \
        --name "TestAppUrl" \
        --value "https://your-test-app.azurewebsites.net" \
        --output none
    
    # Store test user credentials
    az keyvault secret set \
        --vault-name "${KEYVAULT_NAME}" \
        --name "TestUsername" \
        --value "testuser@example.com" \
        --output none
    
    TEST_PASSWORD=$(openssl rand -base64 12 2>/dev/null || echo "TempPassword123!")
    az keyvault secret set \
        --vault-name "${KEYVAULT_NAME}" \
        --name "TestPassword" \
        --value "${TEST_PASSWORD}" \
        --output none
    
    log "✅ Test credentials stored securely in Key Vault"
}

# Function to create alert rules
create_monitoring_alerts() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create monitoring alerts"
        return 0
    fi
    
    log "Creating monitoring alerts"
    
    # Load environment variables
    if [[ -f "${SCRIPT_DIR}/deployment.env" ]]; then
        source "${SCRIPT_DIR}/deployment.env"
    fi
    
    # Get Application Insights resource ID
    AI_RESOURCE_ID=$(az monitor app-insights component show \
        --app "${AI_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
    
    # Create action group for notifications (email placeholder)
    ACTION_GROUP_NAME="ag-playwright-alerts"
    az monitor action-group create \
        --name "${ACTION_GROUP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --short-name "PlaywrightAG" \
        --output none || warn "Action group creation failed or already exists"
    
    # Note: Metric alert creation for custom metrics requires the metrics to exist first
    # This is a placeholder that would be activated once tests start running
    warn "Monitoring alerts will be fully configured after initial test runs generate metrics"
    
    log "✅ Monitoring infrastructure prepared"
}

# Function to create Playwright project template
create_playwright_project() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create Playwright project template"
        return 0
    fi
    
    log "Creating Playwright project template"
    
    PROJECT_DIR="${SCRIPT_DIR}/../playwright-tests"
    
    if [[ -d "${PROJECT_DIR}" ]]; then
        warn "Playwright project directory already exists: ${PROJECT_DIR}"
        return 0
    fi
    
    mkdir -p "${PROJECT_DIR}"
    cd "${PROJECT_DIR}"
    
    # Create package.json
    cat > package.json << EOF
{
  "name": "playwright-azure-tests",
  "version": "1.0.0",
  "description": "End-to-end browser tests with Azure Playwright Testing",
  "main": "index.js",
  "scripts": {
    "test": "playwright test",
    "test:azure": "source ../scripts/setup-test-env.sh && playwright test --config=playwright.service.config.ts",
    "test:local": "playwright test --config=playwright.config.ts",
    "test:debug": "playwright test --debug",
    "report": "playwright show-report"
  },
  "devDependencies": {
    "@playwright/test": "latest",
    "@azure/microsoft-playwright-testing": "latest",
    "@azure/keyvault-secrets": "latest",
    "@azure/identity": "latest",
    "applicationinsights": "latest"
  },
  "author": "Azure Recipe",
  "license": "MIT"
}
EOF
    
    # Create basic Playwright config
    cat > playwright.config.ts << 'EOF'
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  timeout: 60000,
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  
  use: {
    trace: 'on-first-retry',
    video: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
    },
  ],
  
  reporter: [
    ['html'],
    ['json', { outputFile: 'test-results.json' }],
  ],
});
EOF
    
    # Create tests directory structure
    mkdir -p tests/helpers
    
    # Create sample test
    cat > tests/sample.spec.ts << 'EOF'
import { test, expect } from '@playwright/test';

test.describe('Sample Browser Tests', () => {
  test('Basic navigation test', async ({ page }) => {
    // Navigate to a test page
    await page.goto('https://playwright.dev');
    
    // Verify page title
    await expect(page).toHaveTitle(/Playwright/);
    
    // Check for main heading
    const heading = page.locator('h1').first();
    await expect(heading).toBeVisible();
  });
});
EOF
    
    cd "${SCRIPT_DIR}"
    log "✅ Playwright project template created at: ${PROJECT_DIR}"
}

# Function to create setup script
create_setup_script() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create test environment setup script"
        return 0
    fi
    
    log "Creating test environment setup script"
    
    cat > "${SCRIPT_DIR}/setup-test-env.sh" << EOF
#!/bin/bash

# Azure Playwright Testing Environment Setup
# Source this script to set up environment variables for testing

# Load deployment environment
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "\${SCRIPT_DIR}/deployment.env" ]]; then
    source "\${SCRIPT_DIR}/deployment.env"
fi

# Azure Playwright Testing configuration
export PLAYWRIGHT_SERVICE_RUN_ID="\$(date +%Y%m%d-%H%M%S)"

# Azure Key Vault configuration
export KEYVAULT_NAME="${KEYVAULT_NAME}"

# Enable Azure authentication for local development
export AZURE_TENANT_ID=\$(az account show --query tenantId -o tsv 2>/dev/null || echo "")
export AZURE_CLIENT_ID=\$(az account show --query user.name -o tsv 2>/dev/null || echo "")

# Set service URL placeholder (to be updated after workspace creation)
export PLAYWRIGHT_SERVICE_URL="https://eastus.api.playwright.microsoft.com"

echo "✅ Test environment configured"
echo "Service URL: \${PLAYWRIGHT_SERVICE_URL}"
echo "Run ID: \${PLAYWRIGHT_SERVICE_RUN_ID}"
echo "Key Vault: \${KEYVAULT_NAME}"

# Reminder for manual workspace creation
echo ""
echo "⚠️  IMPORTANT: Azure Playwright Testing workspace must be created manually:"
echo "1. Navigate to: https://aka.ms/mpt/portal"
echo "2. Sign in with your Azure account"
echo "3. Click '+ New workspace'"
echo "4. Enter workspace name: ${WORKSPACE_NAME}"
echo "5. Select region: ${LOCATION}"
echo "6. Update PLAYWRIGHT_SERVICE_URL in this script with the service endpoint"
EOF
    
    chmod +x "${SCRIPT_DIR}/setup-test-env.sh"
    log "✅ Test environment setup script created"
}

# Function to save deployment information
save_deployment_info() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would save deployment information"
        return 0
    fi
    
    log "Saving deployment information"
    
    cat > "${SCRIPT_DIR}/deployment-summary.txt" << EOF
Azure Playwright Testing Deployment Summary
==========================================

Deployment Date: $(date)
Resource Group: ${RESOURCE_GROUP}
Location: ${LOCATION}

Resources Created:
- Key Vault: ${KEYVAULT_NAME}
- Application Insights: ${AI_NAME}
- Log Analytics Workspace: ${LAW_NAME}

Next Steps:
1. Create Azure Playwright Testing workspace manually:
   - Navigate to: https://aka.ms/mpt/portal
   - Create workspace: ${WORKSPACE_NAME}
   - Note the service endpoint URL

2. Set up Playwright tests:
   - cd ../playwright-tests
   - npm install
   - Update test configuration with your application URLs

3. Configure CI/CD pipeline:
   - Use the generated setup-test-env.sh script
   - Set Key Vault name: ${KEYVAULT_NAME}
   - Configure service authentication

4. Monitor test results:
   - Application Insights: ${AI_NAME}
   - View metrics and alerts in Azure Portal

Environment File: ${SCRIPT_DIR}/deployment.env
Setup Script: ${SCRIPT_DIR}/setup-test-env.sh
Cleanup Script: ${SCRIPT_DIR}/destroy.sh

EOF
    
    log "✅ Deployment information saved to deployment-summary.txt"
}

# Main deployment function
main() {
    log "Starting Azure Playwright Testing deployment"
    log "Script version: 1.0.0"
    
    # Initialize log file
    echo "Deployment started at $(date)" > "${LOG_FILE}"
    
    # Initialize environment file
    echo "# Azure Playwright Testing Deployment Environment" > "${SCRIPT_DIR}/deployment.env"
    echo "RESOURCE_GROUP=${RESOURCE_GROUP}" >> "${SCRIPT_DIR}/deployment.env"
    echo "LOCATION=${LOCATION}" >> "${SCRIPT_DIR}/deployment.env"
    
    # Run deployment steps
    check_prerequisites
    check_playwright_testing_availability
    show_deployment_plan
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        create_resource_group
        create_log_analytics_workspace
        create_application_insights
        create_key_vault
        store_secrets
        create_monitoring_alerts
        create_playwright_project
        create_setup_script
        save_deployment_info
        
        log "🎉 Deployment completed successfully!"
        log ""
        log "Next steps:"
        log "1. Review the deployment summary: ${SCRIPT_DIR}/deployment-summary.txt"
        log "2. Create the Playwright Testing workspace manually (see summary for details)"
        log "3. Set up your test project: cd ../playwright-tests && npm install"
        log "4. Configure your tests with actual application URLs"
        log ""
        warn "Remember: Azure Playwright Testing workspace creation requires manual steps in the Azure Portal"
    else
        log "Dry run completed. No resources were created."
    fi
}

# Trap to handle script interruption
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        error "Deployment failed. Check the log file: ${LOG_FILE}"
        error "You may need to run the cleanup script to remove partially created resources"
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"