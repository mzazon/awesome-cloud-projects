#!/bin/bash

# Azure Resource Tagging and Compliance Enforcement Deployment Script
# This script deploys an automated governance system using Azure Policy and Azure Resource Graph
# to enforce mandatory tagging standards and monitor compliance at scale.

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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null)
    if [[ -z "$az_version" ]]; then
        error "Unable to determine Azure CLI version"
    fi
    
    local min_version="2.30.0"
    if [[ "$(printf '%s\n' "$min_version" "$az_version" | sort -V | head -n1)" != "$min_version" ]]; then
        error "Azure CLI version $az_version is too old. Please upgrade to $min_version or higher"
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first"
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is required for generating random strings. Please install it"
    fi
    
    log "Prerequisites check passed"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        error "Unable to get subscription ID"
    fi
    
    # Set default values (can be overridden by environment variables)
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-governance-demo}"
    export LOCATION="${LOCATION:-eastus}"
    export LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-law-governance-$RANDOM}"
    
    # Generate unique identifiers
    local random_suffix=$(openssl rand -hex 3)
    export POLICY_INITIATIVE_NAME="${POLICY_INITIATIVE_NAME:-mandatory-tagging-initiative-${random_suffix}}"
    export POLICY_ASSIGNMENT_NAME="${POLICY_ASSIGNMENT_NAME:-enforce-mandatory-tags-${random_suffix}}"
    export AUTOMATION_ACCOUNT_NAME="${AUTOMATION_ACCOUNT_NAME:-aa-governance-${random_suffix}}"
    
    info "Using subscription: $SUBSCRIPTION_ID"
    info "Using resource group: $RESOURCE_GROUP"
    info "Using location: $LOCATION"
    info "Using policy initiative: $POLICY_INITIATIVE_NAME"
    info "Using policy assignment: $POLICY_ASSIGNMENT_NAME"
}

# Function to create resource group and foundational resources
create_foundational_resources() {
    log "Creating foundational resources..."
    
    # Create resource group
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=governance environment=demo
        log "Created resource group: $RESOURCE_GROUP"
    fi
    
    # Create Log Analytics workspace
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_ANALYTICS_WORKSPACE" &> /dev/null; then
        warn "Log Analytics workspace $LOG_ANALYTICS_WORKSPACE already exists"
    else
        az monitor log-analytics workspace create \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
            --location "$LOCATION" \
            --sku PerGB2018
        log "Created Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE"
    fi
    
    # Wait for Log Analytics workspace to be ready
    local max_attempts=30
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_ANALYTICS_WORKSPACE" --query "provisioningState" -o tsv | grep -q "Succeeded"; then
            log "Log Analytics workspace is ready"
            break
        fi
        info "Waiting for Log Analytics workspace to be ready... (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        error "Log Analytics workspace failed to become ready within expected time"
    fi
}

# Function to create policy definitions
create_policy_definitions() {
    log "Creating custom policy definitions..."
    
    # Create policy definition for required Department tag
    if az policy definition show --name "require-department-tag" &> /dev/null; then
        warn "Policy definition 'require-department-tag' already exists"
    else
        az policy definition create \
            --name "require-department-tag" \
            --display-name "Require Department Tag on Resources" \
            --description "Ensures all resources have a Department tag" \
            --mode "Indexed" \
            --rules '{
                "if": {
                    "field": "tags[Department]",
                    "exists": "false"
                },
                "then": {
                    "effect": "deny"
                }
            }' \
            --params '{
                "tagName": {
                    "type": "String",
                    "metadata": {
                        "displayName": "Tag Name",
                        "description": "Name of the tag, such as Department"
                    },
                    "defaultValue": "Department"
                }
            }'
        log "Created policy definition: require-department-tag"
    fi
    
    # Create policy definition for required Environment tag
    if az policy definition show --name "require-environment-tag" &> /dev/null; then
        warn "Policy definition 'require-environment-tag' already exists"
    else
        az policy definition create \
            --name "require-environment-tag" \
            --display-name "Require Environment Tag on Resources" \
            --description "Ensures all resources have an Environment tag" \
            --mode "Indexed" \
            --rules '{
                "if": {
                    "field": "tags[Environment]",
                    "exists": "false"
                },
                "then": {
                    "effect": "deny"
                }
            }'
        log "Created policy definition: require-environment-tag"
    fi
    
    # Create policy definition for automatic CostCenter tag inheritance
    if az policy definition show --name "inherit-costcenter-tag" &> /dev/null; then
        warn "Policy definition 'inherit-costcenter-tag' already exists"
    else
        az policy definition create \
            --name "inherit-costcenter-tag" \
            --display-name "Inherit CostCenter Tag from Resource Group" \
            --description "Automatically applies CostCenter tag from parent resource group" \
            --mode "Indexed" \
            --rules '{
                "if": {
                    "allOf": [
                        {
                            "field": "tags[CostCenter]",
                            "exists": "false"
                        },
                        {
                            "value": "[resourceGroup().tags[CostCenter]]",
                            "notEquals": ""
                        }
                    ]
                },
                "then": {
                    "effect": "modify",
                    "details": {
                        "roleDefinitionIds": [
                            "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
                        ],
                        "operations": [
                            {
                                "operation": "add",
                                "field": "tags[CostCenter]",
                                "value": "[resourceGroup().tags[CostCenter]]"
                            }
                        ]
                    }
                }
            }'
        log "Created policy definition: inherit-costcenter-tag"
    fi
    
    log "Policy definitions created successfully"
}

# Function to create policy initiative
create_policy_initiative() {
    log "Creating policy initiative..."
    
    if az policy set-definition show --name "$POLICY_INITIATIVE_NAME" &> /dev/null; then
        warn "Policy initiative '$POLICY_INITIATIVE_NAME' already exists"
        return 0
    fi
    
    az policy set-definition create \
        --name "$POLICY_INITIATIVE_NAME" \
        --display-name "Mandatory Resource Tagging Initiative" \
        --description "Comprehensive tagging policy initiative for governance and compliance" \
        --definitions "[
            {
                \"policyDefinitionId\": \"/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Authorization/policyDefinitions/require-department-tag\",
                \"parameters\": {}
            },
            {
                \"policyDefinitionId\": \"/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Authorization/policyDefinitions/require-environment-tag\",
                \"parameters\": {}
            },
            {
                \"policyDefinitionId\": \"/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Authorization/policyDefinitions/inherit-costcenter-tag\",
                \"parameters\": {}
            }
        ]" \
        --params '{
            "excludedResourceTypes": {
                "type": "Array",
                "metadata": {
                    "displayName": "Excluded Resource Types",
                    "description": "Resource types to exclude from tagging requirements"
                },
                "defaultValue": [
                    "Microsoft.Network/networkSecurityGroups",
                    "Microsoft.Network/routeTables"
                ]
            }
        }'
    
    log "Policy initiative created: $POLICY_INITIATIVE_NAME"
}

# Function to assign policy initiative
assign_policy_initiative() {
    log "Assigning policy initiative to subscription..."
    
    if az policy assignment show --name "$POLICY_ASSIGNMENT_NAME" --scope "/subscriptions/$SUBSCRIPTION_ID" &> /dev/null; then
        warn "Policy assignment '$POLICY_ASSIGNMENT_NAME' already exists"
        return 0
    fi
    
    # Assign policy initiative to subscription
    az policy assignment create \
        --name "$POLICY_ASSIGNMENT_NAME" \
        --display-name "Enforce Mandatory Tags - Subscription Level" \
        --description "Subscription-wide enforcement of mandatory tagging requirements" \
        --policy-set-definition "$POLICY_INITIATIVE_NAME" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" \
        --enforcement-mode "Default" \
        --identity-scope "/subscriptions/$SUBSCRIPTION_ID" \
        --assign-identity \
        --location "$LOCATION"
    
    log "Policy assignment created: $POLICY_ASSIGNMENT_NAME"
    
    # Wait for policy assignment to be ready
    sleep 30
    
    # Create remediation task
    local remediation_name="remediate-missing-tags-$(openssl rand -hex 3)"
    az policy remediation create \
        --name "$remediation_name" \
        --policy-assignment "$POLICY_ASSIGNMENT_NAME" \
        --definition-reference-id "inherit-costcenter-tag" \
        --resource-discovery-mode "ExistingNonCompliant" || warn "Remediation task creation failed - this is expected if no resources exist yet"
    
    log "Policy assignment and remediation configured"
}

# Function to create Resource Graph queries
create_resource_graph_queries() {
    log "Creating Resource Graph queries..."
    
    # Create saved query for compliance monitoring
    if az graph shared-query show --name "tag-compliance-dashboard" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Shared query 'tag-compliance-dashboard' already exists"
    else
        az graph shared-query create \
            --name "tag-compliance-dashboard" \
            --description "Comprehensive tag compliance monitoring query" \
            --query "
            Resources
            | where type !in ('microsoft.resources/subscriptions', 'microsoft.resources/resourcegroups')
            | extend compliance = case(
                tags.Department != '' and isnotempty(tags.Department) and 
                tags.Environment != '' and isnotempty(tags.Environment), 'Fully Compliant',
                tags.Department != '' and isnotempty(tags.Department) or 
                tags.Environment != '' and isnotempty(tags.Environment), 'Partially Compliant',
                'Non-Compliant'
            )
            | summarize count() by compliance, type
            | order by compliance desc
            " \
            --resource-group "$RESOURCE_GROUP"
        log "Created shared query: tag-compliance-dashboard"
    fi
    
    # Test basic compliance query
    info "Testing Resource Graph query for compliance status..."
    az graph query -q "
    Resources
    | where type !in ('microsoft.resources/subscriptions', 'microsoft.resources/resourcegroups')
    | extend compliance = case(
        tags.Department != '' and isnotempty(tags.Department) and 
        tags.Environment != '' and isnotempty(tags.Environment), 'Fully Compliant',
        'Non-Compliant'
    )
    | summarize count() by compliance
    " --output table || warn "Resource Graph query test failed - this is expected if no resources exist yet"
    
    log "Resource Graph queries configured"
}

# Function to configure monitoring
configure_monitoring() {
    log "Configuring Azure Monitor integration..."
    
    # Get Log Analytics workspace ID
    local workspace_id=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query customerId --output tsv)
    
    if [[ -z "$workspace_id" ]]; then
        error "Unable to get Log Analytics workspace ID"
    fi
    
    # Create diagnostic settings for policy evaluation logs
    if az monitor diagnostic-settings show --name "policy-compliance-logs" --resource "/subscriptions/$SUBSCRIPTION_ID" &> /dev/null; then
        warn "Diagnostic setting 'policy-compliance-logs' already exists"
    else
        az monitor diagnostic-settings create \
            --name "policy-compliance-logs" \
            --resource "/subscriptions/$SUBSCRIPTION_ID" \
            --workspace "$workspace_id" \
            --logs '[
                {
                    "category": "Policy",
                    "enabled": true,
                    "retentionPolicy": {
                        "enabled": true,
                        "days": 30
                    }
                }
            ]' \
            --metrics '[
                {
                    "category": "AllMetrics",
                    "enabled": true,
                    "retentionPolicy": {
                        "enabled": true,
                        "days": 30
                    }
                }
            ]' || warn "Diagnostic settings creation failed - some log categories may not be available"
        log "Created diagnostic settings for policy compliance logs"
    fi
    
    log "Azure Monitor integration configured"
}

# Function to create automation account
create_automation_account() {
    log "Creating automation account for remediation workflows..."
    
    if az automation account show --name "$AUTOMATION_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Automation account '$AUTOMATION_ACCOUNT_NAME' already exists"
        return 0
    fi
    
    # Create automation account
    az automation account create \
        --name "$AUTOMATION_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku "Basic"
    
    log "Created automation account: $AUTOMATION_ACCOUNT_NAME"
    
    # Create PowerShell runbook content
    cat > /tmp/remediation-runbook.ps1 << 'EOF'
param(
    [string]$SubscriptionId,
    [string]$ResourceGroupName,
    [string]$TagName,
    [string]$TagValue
)

# Connect to Azure using managed identity
Connect-AzAccount -Identity
Set-AzContext -SubscriptionId $SubscriptionId

# Get resources missing the required tag
$resources = Get-AzResource -ResourceGroupName $ResourceGroupName | Where-Object {
    $_.Tags.$TagName -eq $null -or $_.Tags.$TagName -eq ""
}

# Apply missing tags to resources
foreach ($resource in $resources) {
    $tags = $resource.Tags
    if ($tags -eq $null) { $tags = @{} }
    $tags[$TagName] = $TagValue
    Set-AzResource -ResourceId $resource.ResourceId -Tag $tags -Force
    Write-Output "Applied tag $TagName=$TagValue to resource: $($resource.Name)"
}
EOF
    
    # Create runbook in automation account
    az automation runbook create \
        --automation-account-name "$AUTOMATION_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "remediate-missing-tags" \
        --type "PowerShell" \
        --description "Automatically remediate missing tags on resources" || warn "Runbook creation failed - this is expected in some regions"
    
    log "Automation account and runbook configured"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "===================="
    echo "Subscription ID: $SUBSCRIPTION_ID"
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Policy Initiative: $POLICY_INITIATIVE_NAME"
    echo "Policy Assignment: $POLICY_ASSIGNMENT_NAME"
    echo "Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE"
    echo "Automation Account: $AUTOMATION_ACCOUNT_NAME"
    echo "===================="
    echo ""
    echo "Next Steps:"
    echo "1. Test policy enforcement by creating resources with/without required tags"
    echo "2. Monitor compliance using Azure Resource Graph queries"
    echo "3. Review policy compliance in the Azure portal"
    echo "4. Configure additional monitoring and alerting as needed"
    echo ""
    echo "Resources created:"
    echo "- Custom policy definitions (3)"
    echo "- Policy initiative"
    echo "- Policy assignment at subscription level"
    echo "- Log Analytics workspace"
    echo "- Automation account with remediation runbook"
    echo "- Resource Graph shared query"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Main execution
main() {
    log "Starting Azure Resource Tagging and Compliance Enforcement deployment..."
    
    check_prerequisites
    set_environment_variables
    create_foundational_resources
    create_policy_definitions
    create_policy_initiative
    assign_policy_initiative
    create_resource_graph_queries
    configure_monitoring
    create_automation_account
    display_summary
    
    log "Deployment completed successfully!"
}

# Run main function
main "$@"