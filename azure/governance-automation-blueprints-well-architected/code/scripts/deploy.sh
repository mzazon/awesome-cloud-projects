#!/bin/bash

# Deploy script for Enterprise-Grade Governance Automation with Azure Blueprints
# This script deploys the complete governance solution including policies, blueprints, and monitoring

set -e
set -o pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
SCRIPT_NAME="deploy.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${message}"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${message}"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} ${message}"
            ;;
    esac
    
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log "ERROR" "Deployment failed with exit code ${exit_code}"
    log "ERROR" "Check ${LOG_FILE} for detailed error information"
    exit $exit_code
}

trap cleanup_on_error ERR

# Show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Enterprise-Grade Governance Automation with Azure Blueprints

OPTIONS:
    -h, --help              Show this help message
    -r, --resource-group    Resource group name (default: rg-governance-\$RANDOM)
    -l, --location          Azure region (default: eastus)
    -s, --subscription      Azure subscription ID (default: current)
    -b, --blueprint-name    Blueprint name (default: enterprise-governance-blueprint)
    -d, --dry-run           Show what would be deployed without executing
    -v, --verbose           Enable verbose logging
    --skip-prereqs          Skip prerequisite checks
    --force                 Force deployment even if resources exist

Examples:
    $0                                          # Deploy with defaults
    $0 -r my-governance-rg -l westus2          # Deploy to specific region
    $0 --dry-run                               # Show deployment plan
    $0 --verbose                               # Enable verbose logging

EOF
}

# Default values
RESOURCE_GROUP=""
LOCATION="eastus"
SUBSCRIPTION_ID=""
BLUEPRINT_NAME="enterprise-governance-blueprint"
DRY_RUN=false
VERBOSE=false
SKIP_PREREQS=false
FORCE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -r|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -s|--subscription)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        -b|--blueprint-name)
            BLUEPRINT_NAME="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --skip-prereqs)
            SKIP_PREREQS=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Initialize logging
log "INFO" "Starting deployment of Enterprise Governance Automation"
log "INFO" "Script: ${SCRIPT_NAME}"
log "INFO" "Log file: ${LOG_FILE}"

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log "ERROR" "Azure CLI is not installed. Please install Azure CLI v2.50.0 or later."
        exit 1
    fi
    
    # Check Azure CLI version
    local cli_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0.0.0")
    log "INFO" "Azure CLI version: ${cli_version}"
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        log "ERROR" "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check required commands
    local required_commands=("openssl" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log "ERROR" "Required command '$cmd' is not installed."
            exit 1
        fi
    done
    
    log "INFO" "Prerequisites check completed successfully"
}

# Set environment variables
setup_environment() {
    log "INFO" "Setting up environment variables..."
    
    # Generate random suffix if resource group not specified
    if [[ -z "$RESOURCE_GROUP" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
        RESOURCE_GROUP="rg-governance-${RANDOM_SUFFIX}"
    fi
    
    # Get subscription ID if not provided
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    fi
    
    # Set subscription context
    az account set --subscription "${SUBSCRIPTION_ID}"
    
    # Get management group ID
    MANAGEMENT_GROUP_ID=$(az account management-group list --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    # Set additional variables
    LOG_WORKSPACE_NAME="law-governance-${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"
    
    # Export variables for use in functions
    export RESOURCE_GROUP LOCATION SUBSCRIPTION_ID BLUEPRINT_NAME MANAGEMENT_GROUP_ID LOG_WORKSPACE_NAME
    
    log "INFO" "Environment setup completed"
    log "INFO" "Resource Group: ${RESOURCE_GROUP}"
    log "INFO" "Location: ${LOCATION}"
    log "INFO" "Subscription ID: ${SUBSCRIPTION_ID}"
    log "INFO" "Blueprint Name: ${BLUEPRINT_NAME}"
}

# Create resource group and foundational resources
create_foundation() {
    log "INFO" "Creating foundational resources..."
    
    if $DRY_RUN; then
        log "INFO" "[DRY RUN] Would create resource group: ${RESOURCE_GROUP}"
        log "INFO" "[DRY RUN] Would create Log Analytics workspace: ${LOG_WORKSPACE_NAME}"
        return 0
    fi
    
    # Create resource group
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log "INFO" "Creating resource group: ${RESOURCE_GROUP}"
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=governance environment=production framework=well-architected
        log "INFO" "Resource group created successfully"
    else
        log "WARN" "Resource group ${RESOURCE_GROUP} already exists"
        if ! $FORCE; then
            log "ERROR" "Use --force to proceed with existing resource group"
            exit 1
        fi
    fi
    
    # Create Log Analytics workspace
    if ! az monitor log-analytics workspace show --resource-group "${RESOURCE_GROUP}" --workspace-name "${LOG_WORKSPACE_NAME}" &> /dev/null; then
        log "INFO" "Creating Log Analytics workspace: ${LOG_WORKSPACE_NAME}"
        az monitor log-analytics workspace create \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${LOG_WORKSPACE_NAME}" \
            --location "${LOCATION}" \
            --sku Standard \
            --retention-in-days 30
        log "INFO" "Log Analytics workspace created successfully"
    else
        log "WARN" "Log Analytics workspace ${LOG_WORKSPACE_NAME} already exists"
    fi
}

# Create custom policy definitions
create_policies() {
    log "INFO" "Creating custom policy definitions..."
    
    if $DRY_RUN; then
        log "INFO" "[DRY RUN] Would create custom policy for required tags"
        log "INFO" "[DRY RUN] Would create security policy initiative"
        return 0
    fi
    
    # Create required tags policy
    local policy_file="${SCRIPT_DIR}/required-tags-policy.json"
    cat > "${policy_file}" << 'EOF'
{
  "mode": "All",
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.Resources/subscriptions/resourceGroups"
        },
        {
          "anyOf": [
            {
              "field": "tags['Environment']",
              "exists": "false"
            },
            {
              "field": "tags['CostCenter']",
              "exists": "false"
            },
            {
              "field": "tags['Owner']",
              "exists": "false"
            }
          ]
        }
      ]
    },
    "then": {
      "effect": "deny"
    }
  },
  "parameters": {}
}
EOF
    
    # Create policy definition
    if ! az policy definition show --name "require-resource-tags" --subscription "${SUBSCRIPTION_ID}" &> /dev/null; then
        log "INFO" "Creating policy definition: require-resource-tags"
        az policy definition create \
            --name "require-resource-tags" \
            --display-name "Require specific tags on resources" \
            --description "Enforces required tags for cost tracking and governance" \
            --rules "${policy_file}" \
            --mode All \
            --subscription "${SUBSCRIPTION_ID}"
        log "INFO" "Policy definition created successfully"
    else
        log "WARN" "Policy definition require-resource-tags already exists"
    fi
    
    # Create security initiative
    local initiative_file="${SCRIPT_DIR}/security-initiative.json"
    cat > "${initiative_file}" << EOF
{
  "properties": {
    "displayName": "Enterprise Security and Governance Initiative",
    "description": "Comprehensive security policies aligned with Well-Architected Framework",
    "policyDefinitions": [
      {
        "policyDefinitionId": "/providers/Microsoft.Authorization/policyDefinitions/404c3081-a854-4457-ae30-26a93ef643f9",
        "parameters": {}
      },
      {
        "policyDefinitionId": "/providers/Microsoft.Authorization/policyDefinitions/1e30110a-5ceb-460c-a204-c1c3969c6d62",
        "parameters": {}
      },
      {
        "policyDefinitionId": "/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Authorization/policyDefinitions/require-resource-tags",
        "parameters": {}
      }
    ]
  }
}
EOF
    
    # Create initiative
    if ! az policy set-definition show --name "enterprise-security-initiative" --subscription "${SUBSCRIPTION_ID}" &> /dev/null; then
        log "INFO" "Creating policy initiative: enterprise-security-initiative"
        az policy set-definition create \
            --name "enterprise-security-initiative" \
            --display-name "Enterprise Security and Governance Initiative" \
            --description "Comprehensive security policies for enterprise governance" \
            --definitions "${initiative_file}" \
            --subscription "${SUBSCRIPTION_ID}"
        log "INFO" "Policy initiative created successfully"
    else
        log "WARN" "Policy initiative enterprise-security-initiative already exists"
    fi
    
    # Clean up temporary files
    rm -f "${policy_file}" "${initiative_file}"
}

# Create ARM template for compliant resources
create_arm_template() {
    log "INFO" "Creating ARM template for compliant resources..."
    
    local template_file="${SCRIPT_DIR}/storage-template.json"
    cat > "${template_file}" << 'EOF'
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "storageAccountName": {
      "type": "string",
      "metadata": {
        "description": "Name of the storage account"
      }
    },
    "location": {
      "type": "string",
      "defaultValue": "[resourceGroup().location]",
      "metadata": {
        "description": "Location for the storage account"
      }
    }
  },
  "variables": {
    "storageAccountName": "[parameters('storageAccountName')]"
  },
  "resources": [
    {
      "type": "Microsoft.Storage/storageAccounts",
      "apiVersion": "2023-01-01",
      "name": "[variables('storageAccountName')]",
      "location": "[parameters('location')]",
      "tags": {
        "Environment": "Production",
        "CostCenter": "IT",
        "Owner": "CloudTeam",
        "Compliance": "Required"
      },
      "sku": {
        "name": "Standard_LRS"
      },
      "kind": "StorageV2",
      "properties": {
        "supportsHttpsTrafficOnly": true,
        "encryption": {
          "services": {
            "file": {
              "enabled": true
            },
            "blob": {
              "enabled": true
            }
          },
          "keySource": "Microsoft.Storage"
        },
        "accessTier": "Hot",
        "minimumTlsVersion": "TLS1_2"
      }
    }
  ],
  "outputs": {
    "storageAccountId": {
      "type": "string",
      "value": "[resourceId('Microsoft.Storage/storageAccounts', variables('storageAccountName'))]"
    }
  }
}
EOF
    
    log "INFO" "ARM template created: ${template_file}"
}

# Create and configure blueprint
create_blueprint() {
    log "INFO" "Creating and configuring Azure Blueprint..."
    
    if $DRY_RUN; then
        log "INFO" "[DRY RUN] Would create blueprint: ${BLUEPRINT_NAME}"
        log "INFO" "[DRY RUN] Would add policy and role assignment artifacts"
        return 0
    fi
    
    # Create blueprint definition
    if ! az blueprint show --name "${BLUEPRINT_NAME}" --subscription "${SUBSCRIPTION_ID}" &> /dev/null; then
        log "INFO" "Creating blueprint definition: ${BLUEPRINT_NAME}"
        az blueprint create \
            --name "${BLUEPRINT_NAME}" \
            --display-name "Enterprise Governance Blueprint" \
            --description "Comprehensive governance blueprint implementing Well-Architected Framework" \
            --target-scope subscription \
            --subscription "${SUBSCRIPTION_ID}"
        log "INFO" "Blueprint definition created successfully"
    else
        log "WARN" "Blueprint ${BLUEPRINT_NAME} already exists"
    fi
    
    # Add policy assignment artifact
    log "INFO" "Adding policy assignment artifact to blueprint"
    az blueprint artifact policy create \
        --blueprint-name "${BLUEPRINT_NAME}" \
        --artifact-name "security-policy-assignment" \
        --display-name "Security Policy Assignment" \
        --description "Assigns security policies for governance" \
        --policy-definition-id "/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Authorization/policySetDefinitions/enterprise-security-initiative" \
        --subscription "${SUBSCRIPTION_ID}" || log "WARN" "Policy artifact may already exist"
    
    # Add role assignment artifact
    log "INFO" "Adding role assignment artifact to blueprint"
    local user_id=$(az ad signed-in-user show --query id --output tsv 2>/dev/null || echo "")
    if [[ -n "$user_id" ]]; then
        az blueprint artifact role create \
            --blueprint-name "${BLUEPRINT_NAME}" \
            --artifact-name "governance-role-assignment" \
            --display-name "Governance Team Role Assignment" \
            --description "Assigns Policy Contributor role to governance team" \
            --role-definition-id "/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c" \
            --principal-ids "${user_id}" \
            --subscription "${SUBSCRIPTION_ID}" || log "WARN" "Role artifact may already exist"
    else
        log "WARN" "Could not get current user ID for role assignment"
    fi
}

# Publish and assign blueprint
publish_assign_blueprint() {
    log "INFO" "Publishing and assigning blueprint..."
    
    if $DRY_RUN; then
        log "INFO" "[DRY RUN] Would publish blueprint version 1.0"
        log "INFO" "[DRY RUN] Would assign blueprint to subscription"
        return 0
    fi
    
    # Publish blueprint version
    log "INFO" "Publishing blueprint version 1.0"
    az blueprint publish \
        --blueprint-name "${BLUEPRINT_NAME}" \
        --version "1.0" \
        --change-notes "Initial enterprise governance blueprint with Well-Architected Framework alignment" \
        --subscription "${SUBSCRIPTION_ID}"
    
    # Wait for publishing to complete
    sleep 10
    
    # Assign blueprint to subscription
    log "INFO" "Assigning blueprint to subscription"
    az blueprint assignment create \
        --name "enterprise-governance-assignment" \
        --blueprint-name "${BLUEPRINT_NAME}" \
        --blueprint-version "1.0" \
        --location "${LOCATION}" \
        --subscription "${SUBSCRIPTION_ID}" \
        --display-name "Enterprise Governance Assignment" \
        --description "Applies enterprise governance controls to subscription"
    
    log "INFO" "Blueprint assignment completed successfully"
}

# Configure Azure Advisor and monitoring
configure_monitoring() {
    log "INFO" "Configuring Azure Advisor and monitoring..."
    
    if $DRY_RUN; then
        log "INFO" "[DRY RUN] Would configure Advisor recommendations"
        log "INFO" "[DRY RUN] Would create action groups and alerts"
        return 0
    fi
    
    # Create action group for governance alerts
    log "INFO" "Creating action group for governance alerts"
    az monitor action-group create \
        --name "governance-alerts" \
        --resource-group "${RESOURCE_GROUP}" \
        --short-name "govAlert" \
        --email-receiver name="governance-team" email-address="governance@company.com" || log "WARN" "Action group may already exist"
    
    # Configure Advisor alerts
    log "INFO" "Configuring Advisor alerts for high-impact recommendations"
    az monitor activity-log alert create \
        --name "advisor-security-alert" \
        --resource-group "${RESOURCE_GROUP}" \
        --condition category=Recommendation \
        --action-group "governance-alerts" \
        --description "Alert for high-impact security recommendations" || log "WARN" "Alert may already exist"
    
    log "INFO" "Monitoring configuration completed successfully"
}

# Create governance dashboard
create_dashboard() {
    log "INFO" "Creating governance monitoring dashboard..."
    
    if $DRY_RUN; then
        log "INFO" "[DRY RUN] Would create governance dashboard"
        return 0
    fi
    
    local dashboard_file="${SCRIPT_DIR}/governance-dashboard.json"
    cat > "${dashboard_file}" << EOF
{
  "properties": {
    "lenses": {
      "0": {
        "order": 0,
        "parts": {
          "0": {
            "position": {
              "x": 0,
              "y": 0,
              "colSpan": 6,
              "rowSpan": 4
            },
            "metadata": {
              "inputs": [],
              "type": "Extension/HubsExtension/PartType/MonitorChartPart",
              "settings": {
                "content": {
                  "options": {
                    "chart": {
                      "metrics": [
                        {
                          "resourceMetadata": {
                            "id": "/subscriptions/${SUBSCRIPTION_ID}"
                          },
                          "name": "PolicyViolations",
                          "aggregationType": "Count",
                          "namespace": "Microsoft.PolicyInsights/policyStates"
                        }
                      ],
                      "title": "Policy Compliance Overview",
                      "titleKind": 1,
                      "visualization": {
                        "chartType": 3
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    },
    "metadata": {
      "model": {
        "timeRange": {
          "value": {
            "relative": {
              "duration": 24,
              "timeUnit": 1
            }
          },
          "type": "MsPortalFx.Composition.Configuration.ValueTypes.TimeRange"
        }
      }
    }
  },
  "name": "Enterprise Governance Dashboard",
  "type": "Microsoft.Portal/dashboards",
  "location": "${LOCATION}",
  "tags": {
    "hidden-title": "Enterprise Governance Dashboard"
  }
}
EOF
    
    # Deploy governance dashboard
    log "INFO" "Deploying governance dashboard"
    az portal dashboard create \
        --input-path "${dashboard_file}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name "enterprise-governance-dashboard" \
        --location "${LOCATION}" || log "WARN" "Dashboard may already exist"
    
    rm -f "${dashboard_file}"
    log "INFO" "Dashboard creation completed"
}

# Validate deployment
validate_deployment() {
    log "INFO" "Validating deployment..."
    
    if $DRY_RUN; then
        log "INFO" "[DRY RUN] Would validate blueprint assignment and policy compliance"
        return 0
    fi
    
    # Check blueprint assignment status
    log "INFO" "Checking blueprint assignment status..."
    local assignment_status=$(az blueprint assignment show \
        --name "enterprise-governance-assignment" \
        --subscription "${SUBSCRIPTION_ID}" \
        --query "properties.provisioningState" \
        --output tsv 2>/dev/null || echo "Unknown")
    
    if [[ "$assignment_status" == "Succeeded" ]]; then
        log "INFO" "Blueprint assignment completed successfully"
    else
        log "WARN" "Blueprint assignment status: ${assignment_status}"
    fi
    
    # Check policy assignments
    log "INFO" "Checking policy assignments..."
    local policy_count=$(az policy assignment list \
        --subscription "${SUBSCRIPTION_ID}" \
        --query "length(@)" \
        --output tsv 2>/dev/null || echo "0")
    
    log "INFO" "Found ${policy_count} policy assignments"
    
    # Check resource group
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log "INFO" "Resource group validation: PASSED"
    else
        log "ERROR" "Resource group validation: FAILED"
        return 1
    fi
    
    log "INFO" "Deployment validation completed"
}

# Main deployment function
main() {
    log "INFO" "Starting Enterprise Governance Automation deployment"
    
    # Check prerequisites unless skipped
    if ! $SKIP_PREREQS; then
        check_prerequisites
    fi
    
    # Setup environment
    setup_environment
    
    # Show deployment plan if dry run
    if $DRY_RUN; then
        log "INFO" "DRY RUN MODE - Showing deployment plan:"
        log "INFO" "Resource Group: ${RESOURCE_GROUP}"
        log "INFO" "Location: ${LOCATION}"
        log "INFO" "Blueprint Name: ${BLUEPRINT_NAME}"
        log "INFO" "Subscription ID: ${SUBSCRIPTION_ID}"
        log "INFO" "Components to deploy:"
        log "INFO" "  - Custom policy definitions"
        log "INFO" "  - Policy initiative"
        log "INFO" "  - Azure Blueprint"
        log "INFO" "  - Monitoring and alerts"
        log "INFO" "  - Governance dashboard"
        log "INFO" "DRY RUN MODE - No resources will be created"
    fi
    
    # Execute deployment steps
    create_foundation
    create_policies
    create_arm_template
    create_blueprint
    publish_assign_blueprint
    configure_monitoring
    create_dashboard
    
    # Validate deployment
    validate_deployment
    
    # Summary
    log "INFO" "Deployment completed successfully!"
    log "INFO" "Resources created:"
    log "INFO" "  - Resource Group: ${RESOURCE_GROUP}"
    log "INFO" "  - Log Analytics Workspace: ${LOG_WORKSPACE_NAME}"
    log "INFO" "  - Blueprint: ${BLUEPRINT_NAME}"
    log "INFO" "  - Policy Initiative: enterprise-security-initiative"
    log "INFO" "  - Governance Dashboard: enterprise-governance-dashboard"
    
    if ! $DRY_RUN; then
        log "INFO" "Access the Azure Portal to view your governance dashboard and policy compliance"
        log "INFO" "Monitor blueprint assignment status in the Azure Blueprints service"
    fi
    
    log "INFO" "Deployment log saved to: ${LOG_FILE}"
}

# Execute main function
main "$@"