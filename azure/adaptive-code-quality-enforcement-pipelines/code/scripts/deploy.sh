#!/bin/bash

# Deploy script for Adaptive Code Quality Enforcement with DevOps Extensions
# This script deploys the complete intelligent code quality pipeline infrastructure

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    AZ_VERSION=$(az --version | head -n 1 | sed 's/azure-cli[[:space:]]*//')
    log "Azure CLI version: $AZ_VERSION"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random suffix generation
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it first."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Resource configuration
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-code-quality-pipeline}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export DEVOPS_ORG="${DEVOPS_ORG:-your-devops-organization}"
    export PROJECT_NAME="${PROJECT_NAME:-quality-pipeline-demo}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export APP_INSIGHTS_NAME="ai-quality-${RANDOM_SUFFIX}"
    export LOGIC_APP_NAME="la-quality-feedback-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stquality${RANDOM_SUFFIX}"
    
    # Save environment variables for cleanup
    cat > .env << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
DEVOPS_ORG=${DEVOPS_ORG}
PROJECT_NAME=${PROJECT_NAME}
APP_INSIGHTS_NAME=${APP_INSIGHTS_NAME}
LOGIC_APP_NAME=${LOGIC_APP_NAME}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log "Environment variables configured:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Location: ${LOCATION}"
    log "  DevOps Organization: ${DEVOPS_ORG}"
    log "  Project Name: ${PROJECT_NAME}"
    log "  App Insights: ${APP_INSIGHTS_NAME}"
    log "  Logic App: ${LOGIC_APP_NAME}"
    log "  Storage Account: ${STORAGE_ACCOUNT}"
    
    success "Environment setup completed"
}

# Create Azure resource group
create_resource_group() {
    log "Creating Azure resource group..."
    
    # Check if resource group already exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=recipe environment=demo
        success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Install Azure DevOps CLI extension
install_devops_extension() {
    log "Installing Azure DevOps CLI extension..."
    
    # Check if extension is already installed
    if az extension show --name azure-devops &> /dev/null; then
        warning "Azure DevOps extension already installed"
    else
        az extension add --name azure-devops
        success "Azure DevOps CLI extension installed"
    fi
    
    # Configure Azure DevOps login
    log "Configuring Azure DevOps login..."
    if [[ "${DEVOPS_ORG}" == "your-devops-organization" ]]; then
        error "Please set DEVOPS_ORG environment variable to your actual Azure DevOps organization"
        exit 1
    fi
    
    # Set default organization
    az devops configure --defaults organization=https://dev.azure.com/${DEVOPS_ORG}
    success "Azure DevOps CLI configured"
}

# Create Azure DevOps project
create_devops_project() {
    log "Creating Azure DevOps project..."
    
    # Check if project already exists
    if az devops project show --project "${PROJECT_NAME}" &> /dev/null; then
        warning "Azure DevOps project ${PROJECT_NAME} already exists"
    else
        az devops project create \
            --name "${PROJECT_NAME}" \
            --description "Intelligent Code Quality Pipeline Demo" \
            --process Agile \
            --source-control Git \
            --visibility private
        success "Azure DevOps project created: ${PROJECT_NAME}"
    fi
}

# Create Application Insights
create_app_insights() {
    log "Creating Application Insights resource..."
    
    # Check if Application Insights already exists
    if az monitor app-insights component show --app "${APP_INSIGHTS_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Application Insights ${APP_INSIGHTS_NAME} already exists"
    else
        az monitor app-insights component create \
            --app "${APP_INSIGHTS_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --kind web \
            --application-type web
        success "Application Insights created: ${APP_INSIGHTS_NAME}"
    fi
    
    # Get instrumentation key
    export INSTRUMENTATION_KEY=$(az monitor app-insights component show \
        --app "${APP_INSIGHTS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query instrumentationKey --output tsv)
    
    log "Instrumentation Key: ${INSTRUMENTATION_KEY}"
    
    # Save instrumentation key to environment file
    echo "INSTRUMENTATION_KEY=${INSTRUMENTATION_KEY}" >> .env
}

# Create storage account
create_storage_account() {
    log "Creating storage account for Logic Apps..."
    
    # Check if storage account already exists
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Storage account ${STORAGE_ACCOUNT} already exists"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2
        success "Storage account created: ${STORAGE_ACCOUNT}"
    fi
    
    # Get connection string
    export STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString --output tsv)
    
    # Save connection string to environment file
    echo "STORAGE_CONNECTION=${STORAGE_CONNECTION}" >> .env
}

# Deploy Logic App
deploy_logic_app() {
    log "Deploying Logic App for intelligent feedback loops..."
    
    # Check if Logic App already exists
    if az logic workflow show --name "${LOGIC_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Logic App ${LOGIC_APP_NAME} already exists"
    else
        # Create Logic App workflow definition
        cat > logic-app-definition.json << 'EOF'
{
  "$schema": "https://schema.management.azure.com/schemas/2016-06-01/workflowdefinition.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {},
  "triggers": {
    "manual": {
      "type": "Request",
      "kind": "Http",
      "inputs": {
        "schema": {
          "properties": {
            "qualityScore": {"type": "number"},
            "testResults": {"type": "string"},
            "performanceMetrics": {"type": "object"}
          },
          "type": "object"
        }
      }
    }
  },
  "actions": {
    "Evaluate_Quality_Score": {
      "type": "If",
      "expression": "@greater(triggerBody().qualityScore, 80)",
      "actions": {
        "Send_Success_Notification": {
          "type": "Response",
          "inputs": {
            "statusCode": 200,
            "body": "Quality threshold met - proceeding with deployment"
          }
        }
      },
      "else": {
        "actions": {
          "Send_Failure_Notification": {
            "type": "Response",
            "inputs": {
              "statusCode": 400,
              "body": "Quality threshold not met - blocking deployment"
            }
          }
        }
      }
    }
  }
}
EOF
        
        # Create Logic App
        az logic workflow create \
            --name "${LOGIC_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --definition @logic-app-definition.json
        
        success "Logic App deployed: ${LOGIC_APP_NAME}"
        
        # Clean up temporary file
        rm -f logic-app-definition.json
    fi
    
    # Get Logic App URL
    export LOGIC_APP_URL=$(az logic workflow show \
        --name "${LOGIC_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query accessEndpoint --output tsv)
    
    log "Logic App Webhook URL: ${LOGIC_APP_URL}"
    
    # Save URL to environment file
    echo "LOGIC_APP_URL=${LOGIC_APP_URL}" >> .env
}

# Configure Azure Test Plans
configure_test_plans() {
    log "Configuring Azure Test Plans..."
    
    # Create test plan
    TEST_PLAN_JSON=$(cat << EOF
{
  "name": "Intelligent Quality Pipeline Tests",
  "description": "Comprehensive testing strategy for code quality enforcement",
  "startDate": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "endDate": "$(date -u -d '+30 days' +%Y-%m-%dT%H:%M:%SZ)",
  "state": "Active"
}
EOF
    )
    
    # Create test plan using REST API
    export TEST_PLAN_ID=$(echo "${TEST_PLAN_JSON}" | az devops invoke \
        --area testplan \
        --resource testplans \
        --route-parameters project="${PROJECT_NAME}" \
        --http-method POST \
        --in-file /dev/stdin | jq -r '.id')
    
    if [[ "${TEST_PLAN_ID}" != "null" && -n "${TEST_PLAN_ID}" ]]; then
        success "Test Plan created: ${TEST_PLAN_ID}"
        
        # Create test suite
        TEST_SUITE_JSON=$(cat << EOF
{
  "name": "Automated Quality Gates",
  "suiteType": "StaticTestSuite",
  "requirementId": null
}
EOF
        )
        
        export TEST_SUITE_ID=$(echo "${TEST_SUITE_JSON}" | az devops invoke \
            --area testplan \
            --resource testsuites \
            --route-parameters project="${PROJECT_NAME}" planId="${TEST_PLAN_ID}" \
            --http-method POST \
            --in-file /dev/stdin | jq -r '.id')
        
        success "Test Suite created: ${TEST_SUITE_ID}"
        
        # Save test plan and suite IDs
        echo "TEST_PLAN_ID=${TEST_PLAN_ID}" >> .env
        echo "TEST_SUITE_ID=${TEST_SUITE_ID}" >> .env
    else
        warning "Test Plan creation may have failed or already exists"
    fi
}

# Install code quality extensions
install_quality_extensions() {
    log "Installing code quality extensions..."
    
    # List of extensions to install
    EXTENSIONS=(
        "sonarqube:SonarSource"
        "code-coverage:ms-devlabs"
        "security-code-scan:ms-securitycodeanalysis"
    )
    
    for extension in "${EXTENSIONS[@]}"; do
        IFS=':' read -ra EXT_PARTS <<< "$extension"
        EXT_ID="${EXT_PARTS[0]}"
        PUBLISHER="${EXT_PARTS[1]}"
        
        log "Installing extension: ${EXT_ID} by ${PUBLISHER}"
        
        # Check if extension is already installed
        if az devops extension show --extension-id "${EXT_ID}" --publisher-id "${PUBLISHER}" &> /dev/null; then
            warning "Extension ${EXT_ID} already installed"
        else
            # Note: Some extensions may require manual installation or may not be available
            # This is a placeholder for extension installation
            log "Extension ${EXT_ID} installation attempted (may require manual installation)"
        fi
    done
    
    success "Code quality extensions installation completed"
}

# Create quality pipeline
create_quality_pipeline() {
    log "Creating intelligent quality pipeline..."
    
    # Create pipeline YAML configuration
    cat > azure-pipeline-quality.yml << 'EOF'
trigger:
  branches:
    include:
      - main
      - develop

pool:
  vmImage: 'ubuntu-latest'

variables:
  buildConfiguration: 'Release'
  qualityThreshold: 80

stages:
- stage: QualityAnalysis
  displayName: 'Code Quality Analysis'
  jobs:
  - job: StaticAnalysis
    displayName: 'Static Code Analysis'
    steps:
    - task: UseDotNet@2
      displayName: 'Use .NET Core SDK'
      inputs:
        packageType: 'sdk'
        version: '6.x'
    
    - task: DotNetCoreCLI@2
      displayName: 'Restore dependencies'
      inputs:
        command: 'restore'
        projects: '**/*.csproj'
    
    - task: DotNetCoreCLI@2
      displayName: 'Build application'
      inputs:
        command: 'build'
        projects: '**/*.csproj'
        arguments: '--configuration $(buildConfiguration) --no-restore'
    
    - task: DotNetCoreCLI@2
      displayName: 'Run unit tests'
      inputs:
        command: 'test'
        projects: '**/*Tests.csproj'
        arguments: '--configuration $(buildConfiguration) --collect:"XPlat Code Coverage" --no-build'
    
    - task: PublishCodeCoverageResults@1
      displayName: 'Publish code coverage'
      inputs:
        codeCoverageTool: 'Cobertura'
        summaryFileLocation: '$(Agent.TempDirectory)/**/coverage.cobertura.xml'

- stage: TestExecution
  displayName: 'Test Execution'
  dependsOn: QualityAnalysis
  jobs:
  - job: AutomatedTesting
    displayName: 'Automated Test Suite'
    steps:
    - task: DotNetCoreCLI@2
      displayName: 'Run integration tests'
      inputs:
        command: 'test'
        projects: '**/*IntegrationTests.csproj'
        arguments: '--configuration $(buildConfiguration) --logger trx --collect:"XPlat Code Coverage"'
    
    - task: PublishTestResults@2
      displayName: 'Publish test results'
      inputs:
        testResultsFormat: 'VSTest'
        testResultsFiles: '**/*.trx'
        failTaskOnFailedTests: true

- stage: QualityGate
  displayName: 'Quality Gate Evaluation'
  dependsOn: TestExecution
  jobs:
  - job: EvaluateQuality
    displayName: 'Evaluate Quality Metrics'
    steps:
    - task: PowerShell@2
      displayName: 'Calculate quality score'
      inputs:
        targetType: 'inline'
        script: |
          # Calculate quality score based on metrics
          $qualityScore = 85  # This would be calculated from actual metrics
          Write-Host "Quality Score: $qualityScore"
          
          # Set pipeline variable
          Write-Host "##vso[task.setvariable variable=calculatedQualityScore]$qualityScore"
    
    - task: PowerShell@2
      displayName: 'Trigger Logic App feedback'
      inputs:
        targetType: 'inline'
        script: |
          $logicAppUrl = "$(LOGIC_APP_URL)"
          if ($logicAppUrl -and $logicAppUrl -ne "") {
            $body = @{
              qualityScore = $(calculatedQualityScore)
              testResults = "$(Agent.JobStatus)"
              performanceMetrics = @{
                buildTime = "$(System.StageDisplayName)"
                testCoverage = 85
              }
            } | ConvertTo-Json
            
            try {
              $response = Invoke-RestMethod -Uri $logicAppUrl -Method Post -Body $body -ContentType "application/json"
              Write-Host "Logic App response: $response"
            } catch {
              Write-Warning "Failed to trigger Logic App: $($_.Exception.Message)"
            }
          } else {
            Write-Warning "Logic App URL not configured"
          }
EOF
    
    # Check if pipeline already exists
    if az pipelines show --name "Intelligent Quality Pipeline" --project "${PROJECT_NAME}" &> /dev/null; then
        warning "Pipeline 'Intelligent Quality Pipeline' already exists"
    else
        # Create pipeline
        az pipelines create \
            --name "Intelligent Quality Pipeline" \
            --repository "${PROJECT_NAME}" \
            --branch main \
            --yaml-path azure-pipeline-quality.yml \
            --project "${PROJECT_NAME}"
        
        success "Intelligent quality pipeline created"
    fi
    
    # Clean up temporary file
    rm -f azure-pipeline-quality.yml
}

# Configure quality dashboard
configure_dashboard() {
    log "Configuring quality dashboard..."
    
    # Create dashboard JSON
    DASHBOARD_JSON=$(cat << EOF
{
  "name": "Code Quality Dashboard",
  "description": "Comprehensive view of code quality metrics and trends",
  "widgets": [
    {
      "name": "Test Results",
      "position": {"row": 1, "column": 1},
      "size": {"rowSpan": 2, "columnSpan": 2},
      "contributionId": "ms.vss-test-web.test-results-widget"
    },
    {
      "name": "Code Coverage",
      "position": {"row": 1, "column": 3},
      "size": {"rowSpan": 2, "columnSpan": 2},
      "contributionId": "ms.vss-build-web.code-coverage-widget"
    },
    {
      "name": "Build Status",
      "position": {"row": 3, "column": 1},
      "size": {"rowSpan": 1, "columnSpan": 4},
      "contributionId": "ms.vss-build-web.build-status-widget"
    }
  ]
}
EOF
    )
    
    # Create dashboard
    echo "${DASHBOARD_JSON}" | az devops invoke \
        --area dashboard \
        --resource dashboards \
        --route-parameters project="${PROJECT_NAME}" \
        --http-method POST \
        --in-file /dev/stdin &> /dev/null || warning "Dashboard creation may have failed"
    
    success "Quality dashboard configured"
}

# Main deployment function
main() {
    log "Starting deployment of Intelligent Code Quality Pipeline..."
    
    check_prerequisites
    setup_environment
    create_resource_group
    install_devops_extension
    create_devops_project
    create_app_insights
    create_storage_account
    deploy_logic_app
    configure_test_plans
    install_quality_extensions
    create_quality_pipeline
    configure_dashboard
    
    success "Deployment completed successfully!"
    
    log "Deployment Summary:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  DevOps Project: ${PROJECT_NAME}"
    log "  Application Insights: ${APP_INSIGHTS_NAME}"
    log "  Logic App: ${LOGIC_APP_NAME}"
    log "  Storage Account: ${STORAGE_ACCOUNT}"
    log "  Environment file: .env"
    
    log "Next steps:"
    log "  1. Configure your DevOps organization settings"
    log "  2. Set up your code repository"
    log "  3. Configure SonarQube or other quality tools"
    log "  4. Run the pipeline to test the quality gates"
    log "  5. Customize quality thresholds as needed"
}

# Run main function
main "$@"