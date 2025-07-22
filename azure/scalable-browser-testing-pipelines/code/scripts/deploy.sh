#!/bin/bash

# Azure Playwright Testing Pipeline Deployment Script
# This script deploys the complete Azure Playwright Testing solution
# including workspace, container registry, and DevOps pipeline

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Default values
DRY_RUN=false
SKIP_DEVOPS=false
SKIP_TESTS=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-devops)
            SKIP_DEVOPS=true
            shift
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run       Show what would be deployed without making changes"
            echo "  --skip-devops   Skip Azure DevOps project and pipeline creation"
            echo "  --skip-tests    Skip test suite creation"
            echo "  --help          Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/"
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check Node.js version
    if ! command -v node &> /dev/null; then
        error "Node.js is not installed. Please install Node.js 18.x or later."
    fi
    
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 18 ]; then
        error "Node.js version 18.x or later is required. Current version: $(node --version)"
    fi
    
    # Check if npm is available
    if ! command -v npm &> /dev/null; then
        error "npm is not installed. Please install npm."
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        error "curl is not installed. Please install curl."
    fi
    
    # Check if openssl is available
    if ! command -v openssl &> /dev/null; then
        error "openssl is not installed. Please install openssl."
    fi
    
    log "Prerequisites check passed"
}

# Set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Set default values if not provided
    export AZURE_REGION=${AZURE_REGION:-"eastus"}
    export RESOURCE_GROUP=${RESOURCE_GROUP:-"rg-playwright-testing"}
    export DEVOPS_ORG=${DEVOPS_ORG:-"your-devops-org"}
    export PROJECT_NAME=${PROJECT_NAME:-"playwright-testing-project"}
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export PLAYWRIGHT_WORKSPACE=${PLAYWRIGHT_WORKSPACE:-"pw-workspace-${RANDOM_SUFFIX}"}
    export ACR_NAME=${ACR_NAME:-"acr${RANDOM_SUFFIX}"}
    
    log "Environment variables set:"
    info "  AZURE_REGION: ${AZURE_REGION}"
    info "  RESOURCE_GROUP: ${RESOURCE_GROUP}"
    info "  PLAYWRIGHT_WORKSPACE: ${PLAYWRIGHT_WORKSPACE}"
    info "  ACR_NAME: ${ACR_NAME}"
    info "  SUBSCRIPTION_ID: ${SUBSCRIPTION_ID}"
    
    if [ "$SKIP_DEVOPS" = false ]; then
        info "  DEVOPS_ORG: ${DEVOPS_ORG}"
        info "  PROJECT_NAME: ${PROJECT_NAME}"
    fi
}

# Create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would create resource group ${RESOURCE_GROUP} in ${AZURE_REGION}"
        return
    fi
    
    # Check if resource group exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${AZURE_REGION}" \
            --tags purpose=browser-testing environment=production
        
        log "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Create Azure Playwright Testing workspace
create_playwright_workspace() {
    log "Creating Azure Playwright Testing workspace..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would create Playwright workspace ${PLAYWRIGHT_WORKSPACE}"
        return
    fi
    
    # Check if workspace exists
    if az playwright workspace show --name "${PLAYWRIGHT_WORKSPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Playwright workspace ${PLAYWRIGHT_WORKSPACE} already exists"
    else
        az playwright workspace create \
            --name "${PLAYWRIGHT_WORKSPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${AZURE_REGION}" \
            --tags project=browser-testing tier=production
        
        log "Playwright workspace created: ${PLAYWRIGHT_WORKSPACE}"
    fi
    
    # Get workspace details
    export PLAYWRIGHT_SERVICE_URL=$(az playwright workspace show \
        --name "${PLAYWRIGHT_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.serviceEndpoint \
        --output tsv)
    
    export PLAYWRIGHT_ACCESS_TOKEN=$(az playwright workspace show \
        --name "${PLAYWRIGHT_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.accessToken \
        --output tsv)
    
    log "Playwright service URL: ${PLAYWRIGHT_SERVICE_URL}"
}

# Create Azure Container Registry
create_container_registry() {
    log "Creating Azure Container Registry..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would create container registry ${ACR_NAME}"
        return
    fi
    
    # Check if ACR exists
    if az acr show --name "${ACR_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Container registry ${ACR_NAME} already exists"
    else
        az acr create \
            --name "${ACR_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${AZURE_REGION}" \
            --sku Basic \
            --admin-enabled true
        
        log "Container registry created: ${ACR_NAME}"
    fi
    
    # Get ACR login server
    export ACR_LOGIN_SERVER=$(az acr show \
        --name "${ACR_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query loginServer \
        --output tsv)
    
    log "Container registry login server: ${ACR_LOGIN_SERVER}"
}

# Create Azure DevOps project
create_devops_project() {
    if [ "$SKIP_DEVOPS" = true ]; then
        log "Skipping Azure DevOps project creation"
        return
    fi
    
    log "Creating Azure DevOps project..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would create DevOps project ${PROJECT_NAME}"
        return
    fi
    
    # Install Azure DevOps CLI extension
    if ! az extension show --name azure-devops &> /dev/null; then
        log "Installing Azure DevOps CLI extension..."
        az extension add --name azure-devops
    fi
    
    # Configure Azure DevOps defaults
    az devops configure --defaults organization=https://dev.azure.com/${DEVOPS_ORG}
    
    # Check if project exists
    if az devops project show --project "${PROJECT_NAME}" &> /dev/null; then
        warn "DevOps project ${PROJECT_NAME} already exists"
    else
        az devops project create \
            --name "${PROJECT_NAME}" \
            --description "Automated browser testing with Playwright" \
            --visibility private \
            --source-control git
        
        log "DevOps project created: ${PROJECT_NAME}"
    fi
    
    # Get project ID
    export PROJECT_ID=$(az devops project show \
        --project "${PROJECT_NAME}" \
        --query id \
        --output tsv)
    
    log "DevOps project ID: ${PROJECT_ID}"
}

# Configure service connections
configure_service_connections() {
    if [ "$SKIP_DEVOPS" = true ]; then
        log "Skipping service connections configuration"
        return
    fi
    
    log "Configuring service connections..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would configure service connections"
        return
    fi
    
    # Create service connection for Azure Resource Manager
    az devops service-endpoint azurerm create \
        --name "Azure-Playwright-Connection" \
        --azure-rm-subscription-id "${SUBSCRIPTION_ID}" \
        --azure-rm-subscription-name "$(az account show --query name -o tsv)" \
        --azure-rm-tenant-id $(az account show --query tenantId -o tsv) \
        --project "${PROJECT_NAME}" || warn "Azure service connection may already exist"
    
    # Get ACR credentials
    ACR_USERNAME=$(az acr credential show --name "${ACR_NAME}" --query username -o tsv)
    ACR_PASSWORD=$(az acr credential show --name "${ACR_NAME}" --query passwords[0].value -o tsv)
    
    # Create service connection for Azure Container Registry
    cat > /tmp/acr-service-connection.json << EOF
{
    "name": "ACR-Connection",
    "type": "dockerregistry",
    "url": "https://${ACR_LOGIN_SERVER}",
    "authorization": {
        "scheme": "UsernamePassword",
        "parameters": {
            "username": "${ACR_USERNAME}",
            "password": "${ACR_PASSWORD}"
        }
    }
}
EOF
    
    az devops service-endpoint create \
        --service-endpoint-configuration-file /tmp/acr-service-connection.json \
        --project "${PROJECT_NAME}" || warn "ACR service connection may already exist"
    
    # Clean up temporary file
    rm -f /tmp/acr-service-connection.json
    
    log "Service connections configured"
}

# Create test suite
create_test_suite() {
    if [ "$SKIP_TESTS" = true ]; then
        log "Skipping test suite creation"
        return
    fi
    
    log "Creating Playwright test suite..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would create test suite in playwright-tests directory"
        return
    fi
    
    # Create project structure
    mkdir -p playwright-tests/{tests,pages,fixtures,.azure-pipelines}
    cd playwright-tests
    
    # Initialize Node.js project if package.json doesn't exist
    if [ ! -f package.json ]; then
        npm init -y
    fi
    
    # Install Playwright and Azure testing package
    npm install --save-dev @playwright/test @azure/microsoft-playwright-testing
    
    # Create Playwright configuration
    cat > playwright.config.js << 'EOF'
const { defineConfig, devices } = require('@playwright/test');
const { getServiceConfig } = require('@azure/microsoft-playwright-testing');

module.exports = defineConfig({
  testDir: './tests',
  timeout: 30000,
  expect: {
    timeout: 5000
  },
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [
    ['html'],
    ['junit', { outputFile: 'test-results.xml' }],
    ['@azure/microsoft-playwright-testing/reporter']
  ],
  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure'
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] }
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] }
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] }
    }
  ],
  ...getServiceConfig()
});
EOF
    
    # Create page object model
    cat > pages/HomePage.js << 'EOF'
class HomePage {
  constructor(page) {
    this.page = page;
    this.title = page.locator('h1');
    this.navMenu = page.locator('nav');
    this.searchBox = page.locator('#search');
    this.loginButton = page.locator('#login');
  }

  async navigateTo() {
    await this.page.goto('/');
  }

  async getTitle() {
    return await this.title.textContent();
  }

  async searchFor(query) {
    await this.searchBox.fill(query);
    await this.searchBox.press('Enter');
  }

  async clickLogin() {
    await this.loginButton.click();
  }
}

module.exports = { HomePage };
EOF
    
    # Create test fixtures
    cat > fixtures/testData.json << 'EOF'
{
  "users": {
    "validUser": {
      "email": "test@example.com",
      "password": "testPassword123"
    },
    "invalidUser": {
      "email": "invalid@example.com",
      "password": "wrongPassword"
    }
  },
  "searchQueries": [
    "product search",
    "documentation",
    "support"
  ]
}
EOF
    
    # Create test suite
    cat > tests/homepage.spec.js << 'EOF'
const { test, expect } = require('@playwright/test');
const { HomePage } = require('../pages/HomePage');
const testData = require('../fixtures/testData.json');

test.describe('Homepage Tests', () => {
  let homePage;

  test.beforeEach(async ({ page }) => {
    homePage = new HomePage(page);
    await homePage.navigateTo();
  });

  test('should display homepage title', async ({ page }) => {
    await expect(homePage.title).toBeVisible();
    const title = await homePage.getTitle();
    expect(title).toContain('Welcome');
  });

  test('should perform search functionality', async ({ page }) => {
    await homePage.searchFor(testData.searchQueries[0]);
    await expect(page.locator('.search-results')).toBeVisible();
  });

  test('should navigate to login page', async ({ page }) => {
    await homePage.clickLogin();
    await expect(page).toHaveURL(/.*login.*/);
  });

  test('should be responsive on mobile', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 });
    await expect(homePage.navMenu).toBeVisible();
  });
});
EOF
    
    # Create Azure DevOps pipeline
    cat > .azure-pipelines/playwright-pipeline.yml << 'EOF'
trigger:
  branches:
    include:
      - main
      - develop
      - feature/*

pool:
  vmImage: 'ubuntu-latest'

variables:
  - name: PLAYWRIGHT_SERVICE_URL
    value: '$(PlaywrightServiceUrl)'
  - name: PLAYWRIGHT_SERVICE_ACCESS_TOKEN
    value: '$(PlaywrightServiceAccessToken)'
  - name: NODE_VERSION
    value: '18.x'

stages:
  - stage: Build
    displayName: 'Build and Test'
    jobs:
      - job: PlaywrightTests
        displayName: 'Run Playwright Tests'
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: '$(NODE_VERSION)'
            displayName: 'Install Node.js'

          - script: |
              npm ci
              npx playwright install --with-deps
            displayName: 'Install dependencies'

          - script: |
              npx playwright test --reporter=junit,html,@azure/microsoft-playwright-testing/reporter
            displayName: 'Run Playwright tests'
            env:
              PLAYWRIGHT_SERVICE_URL: $(PLAYWRIGHT_SERVICE_URL)
              PLAYWRIGHT_SERVICE_ACCESS_TOKEN: $(PLAYWRIGHT_SERVICE_ACCESS_TOKEN)
              CI: true

          - task: PublishTestResults@2
            inputs:
              testResultsFormat: 'JUnit'
              testResultsFiles: 'test-results.xml'
              failTaskOnFailedTests: true
            displayName: 'Publish test results'
            condition: always()

          - task: PublishHtmlReport@1
            inputs:
              reportDir: 'playwright-report'
              tabName: 'Playwright Report'
            displayName: 'Publish HTML report'
            condition: always()

          - task: PublishBuildArtifacts@1
            inputs:
              pathToPublish: 'test-results'
              artifactName: 'playwright-artifacts'
            displayName: 'Publish test artifacts'
            condition: always()

  - stage: Deploy
    displayName: 'Deploy to Staging'
    dependsOn: Build
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - job: DeployStaging
        displayName: 'Deploy to Staging Environment'
        steps:
          - script: echo "Deploying to staging environment"
            displayName: 'Deploy application'

          - script: |
              npx playwright test --grep="@smoke" --reporter=@azure/microsoft-playwright-testing/reporter
            displayName: 'Run smoke tests'
            env:
              PLAYWRIGHT_SERVICE_URL: $(PLAYWRIGHT_SERVICE_URL)
              PLAYWRIGHT_SERVICE_ACCESS_TOKEN: $(PLAYWRIGHT_SERVICE_ACCESS_TOKEN)
              BASE_URL: 'https://staging.example.com'
EOF
    
    cd ..
    
    log "Test suite created successfully"
}

# Configure pipeline variables
configure_pipeline_variables() {
    if [ "$SKIP_DEVOPS" = true ]; then
        log "Skipping pipeline variables configuration"
        return
    fi
    
    log "Configuring pipeline variables..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would configure pipeline variables"
        return
    fi
    
    # Create pipeline variables
    az pipelines variable create \
        --name PlaywrightServiceUrl \
        --value "${PLAYWRIGHT_SERVICE_URL}" \
        --project "${PROJECT_NAME}" || warn "Variable may already exist"
    
    az pipelines variable create \
        --name PlaywrightServiceAccessToken \
        --value "${PLAYWRIGHT_ACCESS_TOKEN}" \
        --secret true \
        --project "${PROJECT_NAME}" || warn "Variable may already exist"
    
    log "Pipeline variables configured"
}

# Create Azure DevOps pipeline
create_pipeline() {
    if [ "$SKIP_DEVOPS" = true ]; then
        log "Skipping Azure DevOps pipeline creation"
        return
    fi
    
    log "Creating Azure DevOps pipeline..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would create pipeline 'Playwright-Testing-Pipeline'"
        return
    fi
    
    # Create the pipeline
    az pipelines create \
        --name "Playwright-Testing-Pipeline" \
        --description "Automated browser testing with Azure Playwright Testing" \
        --repository "${PROJECT_NAME}" \
        --branch main \
        --yaml-path .azure-pipelines/playwright-pipeline.yml \
        --project "${PROJECT_NAME}" || warn "Pipeline may already exist"
    
    log "Pipeline created successfully"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would validate deployment"
        return
    fi
    
    # Check Playwright workspace
    workspace_status=$(az playwright workspace show \
        --name "${PLAYWRIGHT_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.provisioningState \
        --output tsv)
    
    if [ "$workspace_status" = "Succeeded" ]; then
        log "✅ Playwright workspace is operational"
    else
        warn "Playwright workspace status: $workspace_status"
    fi
    
    # Check service endpoint connectivity
    if curl -s -o /dev/null -w "%{http_code}" "${PLAYWRIGHT_SERVICE_URL}/health" | grep -q "200"; then
        log "✅ Playwright service endpoint is accessible"
    else
        warn "Playwright service endpoint may not be accessible"
    fi
    
    # Check ACR
    if az acr show --name "${ACR_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log "✅ Container registry is operational"
    else
        warn "Container registry validation failed"
    fi
    
    # Check DevOps project (if not skipped)
    if [ "$SKIP_DEVOPS" = false ]; then
        if az devops project show --project "${PROJECT_NAME}" &> /dev/null; then
            log "✅ DevOps project is operational"
        else
            warn "DevOps project validation failed"
        fi
    fi
    
    log "Deployment validation completed"
}

# Print summary
print_summary() {
    log "Deployment Summary:"
    echo "=================================="
    info "Resource Group: ${RESOURCE_GROUP}"
    info "Region: ${AZURE_REGION}"
    info "Playwright Workspace: ${PLAYWRIGHT_WORKSPACE}"
    info "Service URL: ${PLAYWRIGHT_SERVICE_URL}"
    info "Container Registry: ${ACR_NAME}"
    info "Login Server: ${ACR_LOGIN_SERVER}"
    
    if [ "$SKIP_DEVOPS" = false ]; then
        info "DevOps Organization: ${DEVOPS_ORG}"
        info "DevOps Project: ${PROJECT_NAME}"
        info "Project ID: ${PROJECT_ID}"
    fi
    
    echo "=================================="
    log "Next Steps:"
    echo "1. Configure your application for testing"
    echo "2. Update test cases in playwright-tests/tests/"
    echo "3. Commit code to trigger the pipeline"
    echo "4. Monitor tests in Azure DevOps dashboard"
    echo ""
    log "Deployment completed successfully!"
}

# Main execution
main() {
    log "Starting Azure Playwright Testing deployment..."
    
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_playwright_workspace
    create_container_registry
    create_devops_project
    configure_service_connections
    create_test_suite
    configure_pipeline_variables
    create_pipeline
    validate_deployment
    print_summary
}

# Execute main function
main "$@"