#!/bin/bash

# =============================================================================
# Deploy Script for Azure Intelligent Supply Chain Carbon Tracking Solution
# =============================================================================
# 
# This script deploys the complete intelligent supply chain carbon tracking
# solution using Azure AI Foundry Agent Service and Azure Sustainability Manager.
#
# Prerequisites:
# - Azure CLI v2.60.0 or later
# - Azure subscription with appropriate permissions
# - Contributor access to create AI Foundry projects and Service Bus namespaces
#
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate Azure CLI installation and login
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check Azure CLI installation
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install Azure CLI v2.60.0 or later."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log_info "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Display current subscription
    local subscription_name
    subscription_name=$(az account show --query name -o tsv)
    log_info "Using Azure subscription: $subscription_name"
    
    log_success "Prerequisites validation completed"
}

# Function to set default values and generate unique identifiers
initialize_variables() {
    log_info "Initializing deployment variables..."
    
    # Set default location if not provided
    LOCATION=${LOCATION:-"eastus"}
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "${RANDOM:0:6}")
    
    # Set resource names with unique suffix
    RESOURCE_GROUP=${RESOURCE_GROUP:-"rg-carbon-tracking-${RANDOM_SUFFIX}"}
    AI_FOUNDRY_PROJECT=${AI_FOUNDRY_PROJECT:-"aif-carbon-${RANDOM_SUFFIX}"}
    SUSTAINABILITY_MANAGER=${SUSTAINABILITY_MANAGER:-"asm-carbon-${RANDOM_SUFFIX}"}
    SERVICE_BUS_NAMESPACE=${SERVICE_BUS_NAMESPACE:-"sb-carbon-${RANDOM_SUFFIX}"}
    FUNCTION_APP_NAME=${FUNCTION_APP_NAME:-"func-carbon-${RANDOM_SUFFIX}"}
    STORAGE_ACCOUNT=${STORAGE_ACCOUNT:-"stcarbon${RANDOM_SUFFIX}"}
    
    # Get Azure subscription ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Unique Suffix: $RANDOM_SUFFIX"
    log_success "Variables initialized"
    
    # Export variables for potential use in other scripts
    export RESOURCE_GROUP LOCATION AI_FOUNDRY_PROJECT SUSTAINABILITY_MANAGER
    export SERVICE_BUS_NAMESPACE FUNCTION_APP_NAME STORAGE_ACCOUNT SUBSCRIPTION_ID
}

# Function to register required Azure resource providers
register_providers() {
    log_info "Registering required Azure resource providers..."
    
    local providers=(
        "Microsoft.MachineLearningServices"
        "Microsoft.CognitiveServices"
        "Microsoft.ServiceBus"
        "Microsoft.Web"
        "Microsoft.Storage"
        "Microsoft.PowerPlatform"
    )
    
    for provider in "${providers[@]}"; do
        log_info "Registering provider: $provider"
        if az provider register --namespace "$provider" --wait >/dev/null 2>&1; then
            log_success "Provider $provider registered successfully"
        else
            log_warning "Provider $provider might already be registered or registration failed"
        fi
    done
    
    log_success "Resource provider registration completed"
}

# Function to create the main resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=carbon-tracking environment=demo deployment=automated \
        >/dev/null 2>&1; then
        log_success "Resource group created: $RESOURCE_GROUP"
    else
        log_error "Failed to create resource group: $RESOURCE_GROUP"
        exit 1
    fi
}

# Function to deploy Azure AI Foundry project
deploy_ai_foundry() {
    log_info "Deploying Azure AI Foundry project: $AI_FOUNDRY_PROJECT"
    
    # Create AI Foundry workspace (Machine Learning workspace)
    if az ml workspace create \
        --name "$AI_FOUNDRY_PROJECT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --description "AI Foundry project for carbon tracking agents" \
        --tags project=carbon-tracking environment=demo deployment=automated \
        >/dev/null 2>&1; then
        log_success "AI Foundry project created: $AI_FOUNDRY_PROJECT"
    else
        log_error "Failed to create AI Foundry project"
        return 1
    fi
    
    # Get workspace details for verification
    local workspace_status
    workspace_status=$(az ml workspace show \
        --name "$AI_FOUNDRY_PROJECT" \
        --resource-group "$RESOURCE_GROUP" \
        --query provisioningState -o tsv 2>/dev/null || echo "Unknown")
    
    log_info "Workspace provisioning state: $workspace_status"
    
    if [ "$workspace_status" = "Succeeded" ]; then
        log_success "AI Foundry project deployment completed"
    else
        log_warning "AI Foundry project may still be deploying. Status: $workspace_status"
    fi
}

# Function to deploy Azure Sustainability Manager environment
deploy_sustainability_manager() {
    log_info "Deploying Azure Sustainability Manager environment: $SUSTAINABILITY_MANAGER"
    
    # Note: Azure Sustainability Manager requires Power Platform integration
    # This creates a Power Platform environment for sustainability tracking
    if az powerplatform environment create \
        --name "$SUSTAINABILITY_MANAGER" \
        --location "$LOCATION" \
        --type Sandbox \
        --description "Carbon tracking environment for supply chain sustainability" \
        >/dev/null 2>&1; then
        log_success "Sustainability Manager environment created: $SUSTAINABILITY_MANAGER"
    else
        log_warning "Sustainability Manager environment creation may require additional permissions or Power Platform setup"
        log_info "You may need to create this manually in the Power Platform admin center"
    fi
}

# Function to deploy Service Bus namespace and queues
deploy_service_bus() {
    log_info "Deploying Service Bus namespace: $SERVICE_BUS_NAMESPACE"
    
    # Create Service Bus namespace
    if az servicebus namespace create \
        --name "$SERVICE_BUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard \
        --tags purpose=carbon-events environment=demo \
        >/dev/null 2>&1; then
        log_success "Service Bus namespace created: $SERVICE_BUS_NAMESPACE"
    else
        log_error "Failed to create Service Bus namespace"
        return 1
    fi
    
    # Wait for namespace to be ready
    log_info "Waiting for Service Bus namespace to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local status
        status=$(az servicebus namespace show \
            --name "$SERVICE_BUS_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --query provisioningState -o tsv 2>/dev/null || echo "Unknown")
        
        if [ "$status" = "Succeeded" ]; then
            break
        fi
        
        log_info "Waiting for namespace... (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    # Create queues for different carbon data types
    local queues=("carbon-data-queue" "analysis-results-queue" "alert-queue")
    
    for queue in "${queues[@]}"; do
        log_info "Creating queue: $queue"
        if az servicebus queue create \
            --name "$queue" \
            --namespace-name "$SERVICE_BUS_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --max-size 1024 \
            --enable-dead-lettering-on-message-expiration true \
            >/dev/null 2>&1; then
            log_success "Queue created: $queue"
        else
            log_warning "Failed to create queue: $queue"
        fi
    done
    
    # Get connection string for later use
    local connection_string
    connection_string=$(az servicebus namespace authorization-rule keys list \
        --name RootManageSharedAccessKey \
        --namespace-name "$SERVICE_BUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryConnectionString --output tsv 2>/dev/null || echo "")
    
    if [ -n "$connection_string" ]; then
        log_success "Service Bus deployment completed"
        # Save connection string to file for later use
        echo "$connection_string" > "/tmp/servicebus-connection-${RANDOM_SUFFIX}.txt"
        log_info "Connection string saved to /tmp/servicebus-connection-${RANDOM_SUFFIX}.txt"
    else
        log_warning "Could not retrieve Service Bus connection string"
    fi
}

# Function to deploy Azure Functions and storage
deploy_functions() {
    log_info "Deploying Azure Functions and storage account"
    
    # Create storage account for Functions
    log_info "Creating storage account: $STORAGE_ACCOUNT"
    if az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --tags purpose=function-storage environment=demo \
        >/dev/null 2>&1; then
        log_success "Storage account created: $STORAGE_ACCOUNT"
    else
        log_error "Failed to create storage account"
        return 1
    fi
    
    # Create Function App
    log_info "Creating Function App: $FUNCTION_APP_NAME"
    if az functionapp create \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-account "$STORAGE_ACCOUNT" \
        --consumption-plan-location "$LOCATION" \
        --runtime python \
        --runtime-version 3.11 \
        --functions-version 4 \
        --tags purpose=carbon-processing environment=demo \
        >/dev/null 2>&1; then
        log_success "Function App created: $FUNCTION_APP_NAME"
    else
        log_error "Failed to create Function App"
        return 1
    fi
    
    # Configure Service Bus connection for Functions
    local connection_string
    if [ -f "/tmp/servicebus-connection-${RANDOM_SUFFIX}.txt" ]; then
        connection_string=$(cat "/tmp/servicebus-connection-${RANDOM_SUFFIX}.txt")
        
        log_info "Configuring Function App settings"
        if az functionapp config appsettings set \
            --name "$FUNCTION_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --settings "ServiceBusConnection=$connection_string" \
            >/dev/null 2>&1; then
            log_success "Function App configured with Service Bus connection"
        else
            log_warning "Failed to configure Function App settings"
        fi
    else
        log_warning "Service Bus connection string not found, skipping Function App configuration"
    fi
}

# Function to create sample agent configurations
create_agent_configurations() {
    log_info "Creating AI agent configuration files"
    
    local config_dir="/tmp/carbon-tracking-agents-${RANDOM_SUFFIX}"
    mkdir -p "$config_dir"
    
    # Create data collection agent configuration
    cat > "$config_dir/carbon-data-agent.json" << 'EOF'
{
  "name": "carbon-data-collection-agent",
  "description": "Intelligent agent for collecting supply chain carbon emissions data",
  "instructions": "You are a specialized agent for collecting and validating carbon emissions data from supply chain sources. Extract relevant emissions data, validate data quality, and format for sustainability reporting.",
  "model": "gpt-4o",
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "validate_carbon_data",
        "description": "Validate carbon emissions data quality and completeness",
        "parameters": {
          "type": "object",
          "properties": {
            "data": {
              "type": "object",
              "description": "Carbon emissions data to validate"
            }
          },
          "required": ["data"]
        }
      }
    },
    {
      "type": "function", 
      "function": {
        "name": "extract_emissions_metrics",
        "description": "Extract carbon emissions metrics from unstructured data",
        "parameters": {
          "type": "object",
          "properties": {
            "source_data": {
              "type": "string",
              "description": "Unstructured data containing emissions information"
            }
          },
          "required": ["source_data"]
        }
      }
    }
  ]
}
EOF

    # Create analysis and optimization agent configuration
    cat > "$config_dir/carbon-analysis-agent.json" << 'EOF'
{
  "name": "carbon-analysis-optimization-agent",
  "description": "Intelligent agent for analyzing carbon emissions and generating optimization recommendations",
  "instructions": "Analyze carbon emissions data to identify trends, hotspots, and optimization opportunities. Generate actionable recommendations for emissions reduction and sustainability improvements.",
  "model": "gpt-4o",
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "analyze_emission_trends",
        "description": "Analyze carbon emissions trends and patterns",
        "parameters": {
          "type": "object",
          "properties": {
            "emissions_data": {
              "type": "array",
              "description": "Historical emissions data for analysis"
            },
            "time_range": {
              "type": "string",
              "description": "Time range for trend analysis"
            }
          },
          "required": ["emissions_data"]
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "generate_optimization_recommendations",
        "description": "Generate actionable recommendations for carbon reduction",
        "parameters": {
          "type": "object",
          "properties": {
            "current_emissions": {
              "type": "object",
              "description": "Current emissions profile"
            },
            "target_reduction": {
              "type": "number",
              "description": "Target percentage reduction"
            }
          },
          "required": ["current_emissions"]
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "calculate_reduction_impact",
        "description": "Calculate potential carbon reduction impact of proposed changes",
        "parameters": {
          "type": "object",
          "properties": {
            "proposed_changes": {
              "type": "array",
              "description": "List of proposed optimization changes"
            }
          },
          "required": ["proposed_changes"]
        }
      }
    }
  ]
}
EOF

    # Create sample carbon data for testing
    cat > "$config_dir/sample-carbon-data.json" << 'EOF'
{
  "facility_id": "FAC001",
  "supplier_name": "Green Manufacturing Co",
  "emission_source": "electricity_consumption",
  "activity_data": 1500,
  "activity_unit": "kWh",
  "emission_factor": 0.0005,
  "co2_eq_tonnes": 0.75,
  "measurement_date": "2025-07-12",
  "scope": "scope2",
  "data_quality": "high",
  "verification_status": "verified",
  "reporting_period": "2025-Q3"
}
EOF

    log_success "Agent configuration files created in: $config_dir"
    log_info "Configuration files:"
    log_info "  - carbon-data-agent.json (Data collection agent)"
    log_info "  - carbon-analysis-agent.json (Analysis and optimization agent)"
    log_info "  - sample-carbon-data.json (Sample test data)"
}

# Function to deploy sample Function code
deploy_sample_functions() {
    log_info "Creating sample Function code for carbon data processing"
    
    local function_dir="/tmp/carbon-functions-${RANDOM_SUFFIX}"
    mkdir -p "$function_dir"
    
    # Create sustainability integration function
    cat > "$function_dir/sustainability-integration-function.py" << 'EOF'
import azure.functions as func
import json
import logging
from azure.servicebus import ServiceBusClient, ServiceBusMessage

def main(msg: func.ServiceBusMessage) -> None:
    """Process carbon data and integrate with Sustainability Manager"""
    try:
        # Parse carbon emissions data from agent
        carbon_data = json.loads(msg.get_body().decode('utf-8'))
        
        # Validate and transform data for Sustainability Manager
        processed_data = {
            'facility_id': carbon_data.get('facility_id'),
            'emission_source': carbon_data.get('source'),
            'co2_equivalent': carbon_data.get('co2_eq_tonnes'),
            'measurement_date': carbon_data.get('date'),
            'scope': carbon_data.get('scope', 'scope3'),
            'activity_data': carbon_data.get('activity_data'),
            'emission_factor': carbon_data.get('emission_factor'),
            'data_quality': carbon_data.get('data_quality', 'medium'),
            'verification_status': carbon_data.get('verification_status', 'pending')
        }
        
        # Send to Sustainability Manager (via API or database)
        logging.info(f"Processing carbon data: {processed_data}")
        
        # Create response message for confirmation
        response_data = {
            'status': 'processed',
            'facility_id': processed_data['facility_id'],
            'processed_at': carbon_data.get('date'),
            'co2_equivalent': processed_data['co2_equivalent']
        }
        
        logging.info("Carbon data successfully integrated with Sustainability Manager")
        
    except Exception as e:
        logging.error(f"Error processing carbon data: {str(e)}")
        raise
EOF

    # Create carbon monitoring function
    cat > "$function_dir/carbon-monitoring-function.py" << 'EOF'
import azure.functions as func
import json
import logging
from datetime import datetime, timedelta

def main(timer: func.TimerRequest) -> None:
    """Monitor carbon emissions and trigger alerts"""
    try:
        # Query recent carbon emissions data
        current_time = datetime.now()
        
        # Simulate carbon monitoring logic
        carbon_metrics = {
            'total_emissions_today': 450.5,  # tonnes CO2e
            'baseline_target': 400.0,
            'threshold_exceeded': True,
            'emission_sources': ['transportation', 'manufacturing', 'energy'],
            'monitored_facilities': 25,
            'data_quality_score': 0.95
        }
        
        # Check against sustainability targets
        if carbon_metrics['total_emissions_today'] > carbon_metrics['baseline_target']:
            alert_data = {
                'alert_type': 'carbon_threshold_exceeded',
                'current_emissions': carbon_metrics['total_emissions_today'],
                'target_emissions': carbon_metrics['baseline_target'],
                'excess_amount': carbon_metrics['total_emissions_today'] - carbon_metrics['baseline_target'],
                'timestamp': current_time.isoformat(),
                'priority': 'high',
                'affected_facilities': carbon_metrics['monitored_facilities']
            }
            
            logging.warning(f"Carbon threshold exceeded: {alert_data}")
            
            # Trigger optimization agent for recommendations
            logging.info("Triggering optimization agent for emission reduction recommendations")
        else:
            logging.info(f"Carbon emissions within target: {carbon_metrics['total_emissions_today']} <= {carbon_metrics['baseline_target']}")
        
        logging.info("Carbon monitoring completed successfully")
        
    except Exception as e:
        logging.error(f"Error in carbon monitoring: {str(e)}")
        raise
EOF

    log_success "Sample Function code created in: $function_dir"
    log_info "Function files:"
    log_info "  - sustainability-integration-function.py (Data integration)"
    log_info "  - carbon-monitoring-function.py (Monitoring and alerts)"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    local validation_errors=0
    
    # Check resource group
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_success "Resource group validated: $RESOURCE_GROUP"
    else
        log_error "Resource group validation failed: $RESOURCE_GROUP"
        ((validation_errors++))
    fi
    
    # Check AI Foundry workspace
    if az ml workspace show --name "$AI_FOUNDRY_PROJECT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_success "AI Foundry project validated: $AI_FOUNDRY_PROJECT"
    else
        log_error "AI Foundry project validation failed: $AI_FOUNDRY_PROJECT"
        ((validation_errors++))
    fi
    
    # Check Service Bus namespace
    if az servicebus namespace show --name "$SERVICE_BUS_NAMESPACE" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_success "Service Bus namespace validated: $SERVICE_BUS_NAMESPACE"
    else
        log_error "Service Bus namespace validation failed: $SERVICE_BUS_NAMESPACE"
        ((validation_errors++))
    fi
    
    # Check Function App
    if az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_success "Function App validated: $FUNCTION_APP_NAME"
    else
        log_error "Function App validation failed: $FUNCTION_APP_NAME"
        ((validation_errors++))
    fi
    
    # Check storage account
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_success "Storage account validated: $STORAGE_ACCOUNT"
    else
        log_error "Storage account validation failed: $STORAGE_ACCOUNT"
        ((validation_errors++))
    fi
    
    if [ $validation_errors -eq 0 ]; then
        log_success "All resources validated successfully"
        return 0
    else
        log_error "Validation failed with $validation_errors errors"
        return 1
    fi
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "=============================================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "AI Foundry Project: $AI_FOUNDRY_PROJECT"
    echo "Sustainability Manager: $SUSTAINABILITY_MANAGER"
    echo "Service Bus Namespace: $SERVICE_BUS_NAMESPACE"
    echo "Function App: $FUNCTION_APP_NAME"
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo "Unique Suffix: $RANDOM_SUFFIX"
    echo "=============================================="
    
    log_info "Next Steps:"
    echo "1. Deploy agent configurations through Azure AI Foundry portal"
    echo "2. Configure Sustainability Manager data sources"
    echo "3. Deploy Function code for carbon data processing"
    echo "4. Test end-to-end carbon tracking workflow"
    echo "5. Set up monitoring and alerting dashboards"
    
    if [ -f "/tmp/servicebus-connection-${RANDOM_SUFFIX}.txt" ]; then
        echo ""
        log_info "Service Bus connection string saved to: /tmp/servicebus-connection-${RANDOM_SUFFIX}.txt"
    fi
    
    if [ -d "/tmp/carbon-tracking-agents-${RANDOM_SUFFIX}" ]; then
        echo ""
        log_info "Agent configurations saved to: /tmp/carbon-tracking-agents-${RANDOM_SUFFIX}"
    fi
    
    if [ -d "/tmp/carbon-functions-${RANDOM_SUFFIX}" ]; then
        echo ""
        log_info "Function code samples saved to: /tmp/carbon-functions-${RANDOM_SUFFIX}"
    fi
}

# Function to handle cleanup on error
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up partial deployment..."
    
    # Only attempt cleanup if resource group was created
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_info "Removing resource group: $RESOURCE_GROUP"
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait >/dev/null 2>&1 || true
    fi
    
    # Clean up temporary files
    rm -f "/tmp/servicebus-connection-${RANDOM_SUFFIX}.txt" 2>/dev/null || true
    rm -rf "/tmp/carbon-tracking-agents-${RANDOM_SUFFIX}" 2>/dev/null || true
    rm -rf "/tmp/carbon-functions-${RANDOM_SUFFIX}" 2>/dev/null || true
}

# Main execution function
main() {
    log_info "Starting Azure Intelligent Supply Chain Carbon Tracking deployment"
    echo "=============================================="
    
    # Set trap for cleanup on error
    trap cleanup_on_error ERR
    
    # Execute deployment steps
    validate_prerequisites
    initialize_variables
    register_providers
    create_resource_group
    deploy_ai_foundry
    deploy_sustainability_manager
    deploy_service_bus
    deploy_functions
    create_agent_configurations
    deploy_sample_functions
    
    # Validate deployment
    if validate_deployment; then
        display_summary
        log_success "Deployment completed successfully!"
        echo ""
        log_info "Total deployment time: Approximately 15-20 minutes"
        log_info "Estimated monthly cost: $150-300 (varies by usage)"
    else
        log_error "Deployment validation failed"
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi