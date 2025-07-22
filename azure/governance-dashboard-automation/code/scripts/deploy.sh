#!/bin/bash

# Deploy script for Azure Governance Dashboards with Resource Graph and Monitor Workbooks
# This script automates the deployment of governance monitoring infrastructure

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
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

# Function to check Azure CLI login status
check_azure_login() {
    log_info "Checking Azure CLI authentication..."
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged into Azure CLI. Please run 'az login' first."
        exit 1
    fi
    log_success "Azure CLI authentication verified"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local cli_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $cli_version"
    
    # Check if curl is available
    if ! command_exists curl; then
        log_error "curl is required but not installed."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command_exists openssl; then
        log_error "openssl is required but not installed."
        exit 1
    fi
    
    check_azure_login
    log_success "All prerequisites met"
}

# Function to set environment variables
set_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Default values (can be overridden by environment variables)
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-governance-dashboard}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export WORKBOOK_NAME="governance-dashboard-${RANDOM_SUFFIX}"
    export LOGIC_APP_NAME="governance-automation-${RANDOM_SUFFIX}"
    export WORKSPACE_NAME="governance-workspace-${RANDOM_SUFFIX}"
    export ACTION_GROUP_NAME="governance-alerts"
    export ALERT_NAME="governance-compliance-alert"
    export SCHEDULED_QUERY_NAME="governance-compliance-check"
    
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Subscription ID: $SUBSCRIPTION_ID"
    log_info "Workbook Name: $WORKBOOK_NAME"
    log_info "Logic App Name: $LOGIC_APP_NAME"
    log_info "Workspace Name: $WORKSPACE_NAME"
    
    log_success "Environment variables configured"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group..."
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=governance environment=production
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to register Azure providers
register_providers() {
    log_info "Registering required Azure providers..."
    
    local providers=("Microsoft.ResourceGraph" "Microsoft.Insights" "Microsoft.Logic" "Microsoft.OperationalInsights")
    
    for provider in "${providers[@]}"; do
        log_info "Registering provider: $provider"
        az provider register --namespace "$provider" --wait
        
        local state=$(az provider show --namespace "$provider" --query "registrationState" -o tsv)
        if [ "$state" = "Registered" ]; then
            log_success "Provider $provider registered successfully"
        else
            log_warning "Provider $provider state: $state"
        fi
    done
}

# Function to create governance queries file
create_governance_queries() {
    log_info "Creating governance queries file..."
    
    cat > governance-queries.kql << 'EOF'
// Query 1: Resources without required tags
resources
| where tags !has "Environment" or tags !has "Owner" or tags !has "CostCenter"
| project name, type, resourceGroup, subscriptionId, location, tags
| limit 1000

// Query 2: Non-compliant resource locations
resources
| where location !in ("eastus", "westus", "centralus")
| project name, type, resourceGroup, location, subscriptionId
| limit 1000

// Query 3: Resources by compliance state
policyresources
| where type == "microsoft.policyinsights/policystates"
| project resourceId, policyAssignmentName, policyDefinitionName, complianceState, timestamp
| summarize count() by complianceState

// Query 4: Security center recommendations
securityresources
| where type == "microsoft.security/assessments"
| project resourceId, displayName, status, severity
| summarize count() by status.code

// Query 5: Resource count by type and location
resources
| summarize count() by type, location
| order by count_ desc
EOF
    
    log_success "Governance queries file created"
}

# Function to test Resource Graph queries
test_resource_graph_queries() {
    log_info "Testing Resource Graph queries..."
    
    # Test basic resource query
    log_info "Testing basic resource count query..."
    az graph query \
        --graph-query "resources | summarize count() by type | top 10 by count_" \
        --subscriptions "$SUBSCRIPTION_ID" >/dev/null
    
    # Test policy compliance query (may return empty if no policies)
    log_info "Testing policy compliance query..."
    az graph query \
        --graph-query "policyresources | where type == 'microsoft.policyinsights/policystates' | summarize count() by complianceState" \
        --subscriptions "$SUBSCRIPTION_ID" >/dev/null || log_warning "Policy query returned no results (normal if no policies assigned)"
    
    # Test resources without required tags
    log_info "Testing tag compliance query..."
    az graph query \
        --graph-query "resources | where tags !has 'Environment' | project name, type, resourceGroup | limit 5" \
        --subscriptions "$SUBSCRIPTION_ID" >/dev/null
    
    log_success "Resource Graph queries tested successfully"
}

# Function to create workbook template
create_workbook_template() {
    log_info "Creating workbook template..."
    
    cat > governance-workbook-template.json << 'EOF'
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 1,
      "content": {
        "json": "# Azure Governance Dashboard\n\nThis dashboard provides comprehensive visibility into Azure resource governance, compliance, and security posture across your organization."
      },
      "name": "Dashboard Title"
    },
    {
      "type": 9,
      "content": {
        "version": "KqlParameterItem/1.0",
        "parameters": [
          {
            "id": "subscription-param",
            "version": "KqlParameterItem/1.0",
            "name": "Subscription",
            "type": 6,
            "description": "Select subscription(s) to monitor",
            "isRequired": true,
            "multiSelect": true,
            "quote": "'",
            "delimiter": ",",
            "value": []
          }
        ],
        "style": "pills",
        "queryType": 1,
        "resourceType": "microsoft.resourcegraph/resources"
      },
      "name": "Subscription Parameters"
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "resources | summarize ResourceCount=count() by Type=type | top 10 by ResourceCount desc",
        "size": 0,
        "title": "Top Resource Types",
        "queryType": 1,
        "resourceType": "microsoft.resourcegraph/resources",
        "visualization": "piechart"
      },
      "name": "Resource Types Chart"
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "resources | where tags !has 'Environment' or tags !has 'Owner' | summarize NonCompliantResources=count() by ResourceGroup=resourceGroup | top 10 by NonCompliantResources desc",
        "size": 0,
        "title": "Resources Missing Required Tags",
        "queryType": 1,
        "resourceType": "microsoft.resourcegraph/resources",
        "visualization": "table"
      },
      "name": "Compliance Table"
    }
  ],
  "fallbackResourceIds": [],
  "fromTemplateId": "governance-dashboard-template"
}
EOF
    
    log_success "Workbook template created"
}

# Function to deploy Azure Monitor Workbook
deploy_workbook() {
    log_info "Deploying Azure Monitor Workbook..."
    
    # Note: Azure CLI doesn't have direct workbook creation command
    # We'll use REST API through az rest command
    local workbook_id="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/workbooks/$WORKBOOK_NAME"
    
    # Create workbook using REST API
    az rest \
        --method PUT \
        --url "https://management.azure.com$workbook_id?api-version=2021-03-08" \
        --body "{
            \"kind\": \"user\",
            \"location\": \"$LOCATION\",
            \"properties\": {
                \"displayName\": \"Governance Dashboard\",
                \"description\": \"Automated governance and compliance dashboard\",
                \"category\": \"governance\",
                \"serializedData\": $(cat governance-workbook-template.json | jq -c .)
            }
        }" >/dev/null
    
    export WORKBOOK_ID="$workbook_id"
    log_success "Governance workbook deployed: $WORKBOOK_ID"
}

# Function to create Log Analytics workspace
create_log_analytics_workspace() {
    log_info "Creating Log Analytics workspace..."
    
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$WORKSPACE_NAME" \
        --location "$LOCATION" \
        --tags purpose=governance environment=production >/dev/null
    
    # Get workspace ID
    export WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$WORKSPACE_NAME" \
        --query customerId --output tsv)
    
    log_success "Log Analytics workspace created: $WORKSPACE_NAME"
    log_info "Workspace ID: $WORKSPACE_ID"
}

# Function to create Logic App
create_logic_app() {
    log_info "Creating Logic App for governance automation..."
    
    # Create Logic App with basic workflow
    az logic workflow create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP_NAME" \
        --location "$LOCATION" \
        --definition '{
          "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
          "contentVersion": "1.0.0.0",
          "parameters": {},
          "triggers": {
            "manual": {
              "type": "Request",
              "kind": "Http",
              "inputs": {
                "schema": {
                  "properties": {
                    "alertType": { "type": "string" },
                    "resourceId": { "type": "string" },
                    "severity": { "type": "string" }
                  },
                  "type": "object"
                }
              }
            }
          },
          "actions": {
            "Log_Alert": {
              "type": "Compose",
              "inputs": {
                "message": "Governance Alert Received",
                "alertType": "@triggerBody()?[\"alertType\"]",
                "resourceId": "@triggerBody()?[\"resourceId\"]",
                "severity": "@triggerBody()?[\"severity\"]",
                "timestamp": "@utcNow()"
              }
            }
          }
        }' >/dev/null
    
    # Get the Logic App trigger URL
    export LOGIC_APP_URL=$(az logic workflow show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP_NAME" \
        --query "accessEndpoint" --output tsv)
    
    log_success "Logic App created: $LOGIC_APP_NAME"
    log_info "Logic App URL: $LOGIC_APP_URL"
}

# Function to create action group
create_action_group() {
    log_info "Creating action group for governance alerts..."
    
    # Get Logic App callback URL for webhook
    local callback_url=$(az logic workflow trigger list-callback-url \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP_NAME" \
        --trigger-name "manual" \
        --query value --output tsv)
    
    az monitor action-group create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ACTION_GROUP_NAME" \
        --short-name "gov-alerts" \
        --action webhook governance-webhook "$callback_url" >/dev/null
    
    log_success "Action group created: $ACTION_GROUP_NAME"
}

# Function to create alert rules
create_alert_rules() {
    log_info "Creating governance alert rules..."
    
    # Create log search alert rule for governance violations
    az monitor scheduled-query create \
        --name "$SCHEDULED_QUERY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "/subscriptions/$SUBSCRIPTION_ID" \
        --condition "count 'Heartbeat | where TimeGenerated > ago(5m)' > 0" \
        --condition-query "Heartbeat | where TimeGenerated > ago(5m)" \
        --description "Scheduled governance compliance check" \
        --evaluation-frequency 15m \
        --window-size 15m \
        --severity 3 \
        --action-groups "$ACTION_GROUP_NAME" >/dev/null
    
    log_success "Governance alert rules created"
}

# Function to test end-to-end workflow
test_end_to_end_workflow() {
    log_info "Testing end-to-end governance workflow..."
    
    # Test Resource Graph connectivity
    log_info "Testing Resource Graph connectivity..."
    az graph query \
        --graph-query "resources | limit 1" \
        --subscriptions "$SUBSCRIPTION_ID" >/dev/null
    
    # Test Logic App trigger
    log_info "Testing Logic App trigger..."
    local callback_url=$(az logic workflow trigger list-callback-url \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP_NAME" \
        --trigger-name "manual" \
        --query value --output tsv)
    
    curl -X POST \
        -H "Content-Type: application/json" \
        -d '{"alertType": "test", "resourceId": "test-resource", "severity": "high"}' \
        "$callback_url" >/dev/null 2>&1 || log_warning "Logic App test call failed (may be expected)"
    
    log_success "End-to-end governance workflow tested"
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "=== Deployment Summary ==="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Subscription: $SUBSCRIPTION_ID"
    echo
    echo "=== Created Resources ==="
    echo "• Workbook: $WORKBOOK_NAME"
    echo "• Logic App: $LOGIC_APP_NAME"
    echo "• Log Analytics Workspace: $WORKSPACE_NAME"
    echo "• Action Group: $ACTION_GROUP_NAME"
    echo "• Alert Rule: $SCHEDULED_QUERY_NAME"
    echo
    echo "=== Access Information ==="
    echo "Governance Dashboard URL:"
    echo "https://portal.azure.com/#blade/Microsoft_Azure_Monitoring/WorkbooksMenuBlade/workbook$WORKBOOK_ID"
    echo
    echo "Logic App URL: $LOGIC_APP_URL"
    echo
    echo "=== Next Steps ==="
    echo "1. Access the governance dashboard through the Azure portal"
    echo "2. Customize the workbook queries based on your requirements"
    echo "3. Configure additional alert rules as needed"
    echo "4. Review the Logic App workflow and add custom actions"
    echo
    echo "To clean up all resources, run: ./destroy.sh"
}

# Function to save deployment state
save_deployment_state() {
    log_info "Saving deployment state..."
    
    cat > .deployment_state << EOF
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
WORKBOOK_NAME=$WORKBOOK_NAME
LOGIC_APP_NAME=$LOGIC_APP_NAME
WORKSPACE_NAME=$WORKSPACE_NAME
ACTION_GROUP_NAME=$ACTION_GROUP_NAME
ALERT_NAME=$ALERT_NAME
SCHEDULED_QUERY_NAME=$SCHEDULED_QUERY_NAME
WORKBOOK_ID=$WORKBOOK_ID
WORKSPACE_ID=$WORKSPACE_ID
LOGIC_APP_URL=$LOGIC_APP_URL
DEPLOYMENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    log_success "Deployment state saved to .deployment_state"
}

# Main deployment function
main() {
    log_info "Starting Azure Governance Dashboard deployment..."
    echo "========================================================"
    
    check_prerequisites
    set_environment_variables
    register_providers
    create_resource_group
    create_governance_queries
    test_resource_graph_queries
    create_workbook_template
    create_log_analytics_workspace
    deploy_workbook
    create_logic_app
    create_action_group
    create_alert_rules
    test_end_to_end_workflow
    save_deployment_state
    
    echo "========================================================"
    display_summary
    
    # Cleanup temporary files
    rm -f governance-queries.kql governance-workbook-template.json 2>/dev/null || true
}

# Error handling
trap 'log_error "Deployment failed on line $LINENO. Check the logs above for details."' ERR

# Run main function
main "$@"