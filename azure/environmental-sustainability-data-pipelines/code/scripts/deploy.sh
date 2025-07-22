#!/bin/bash

# Deploy script for Orchestrating Automated Environmental Data Pipelines
# Recipe: orchestrating-automated-environmental-data-pipelines-with-azure-data-factory-and-azure-sustainability-manager
# Generated: 2025-01-16

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random suffixes. Please install it."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Set default values that can be overridden
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-env-data-pipeline}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    local RANDOM_SUFFIX=$(openssl rand -hex 3)
    export DATA_FACTORY_NAME="${DATA_FACTORY_NAME:-adf-env-pipeline-${RANDOM_SUFFIX}}"
    export STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-stenvdata${RANDOM_SUFFIX}}"
    export FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-env-transform-${RANDOM_SUFFIX}}"
    export LOG_ANALYTICS_NAME="${LOG_ANALYTICS_NAME:-log-env-monitor-${RANDOM_SUFFIX}}"
    
    # Validate storage account name length (must be 3-24 characters)
    if [ ${#STORAGE_ACCOUNT_NAME} -gt 24 ]; then
        log_error "Storage account name too long: ${STORAGE_ACCOUNT_NAME}"
        exit 1
    fi
    
    log "Environment variables set:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Location: $LOCATION"
    log "  Subscription ID: $SUBSCRIPTION_ID"
    log "  Data Factory Name: $DATA_FACTORY_NAME"
    log "  Storage Account Name: $STORAGE_ACCOUNT_NAME"
    log "  Function App Name: $FUNCTION_APP_NAME"
    log "  Log Analytics Name: $LOG_ANALYTICS_NAME"
    
    log_success "Environment variables configured"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=environmental-data environment=demo
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account with Data Lake Gen2 capabilities..."
    
    # Check if storage account already exists
    if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Storage account '$STORAGE_ACCOUNT_NAME' already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --hierarchical-namespace true
        
        log_success "Storage account created with Data Lake Gen2 capabilities: $STORAGE_ACCOUNT_NAME"
    fi
}

# Function to create Data Factory
create_data_factory() {
    log "Creating Azure Data Factory instance..."
    
    # Check if Data Factory already exists
    if az datafactory show --resource-group "$RESOURCE_GROUP" --name "$DATA_FACTORY_NAME" &> /dev/null; then
        log_warning "Data Factory '$DATA_FACTORY_NAME' already exists"
    else
        az datafactory create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$DATA_FACTORY_NAME" \
            --location "$LOCATION"
        
        log_success "Data Factory created: $DATA_FACTORY_NAME"
    fi
    
    # Store Data Factory resource ID for later use
    export ADF_RESOURCE_ID=$(az datafactory show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DATA_FACTORY_NAME" \
        --query id --output tsv)
    
    log "Data Factory resource ID: $ADF_RESOURCE_ID"
}

# Function to create Log Analytics workspace
create_log_analytics() {
    log "Creating Log Analytics workspace..."
    
    # Check if Log Analytics workspace already exists
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_ANALYTICS_NAME" &> /dev/null; then
        log_warning "Log Analytics workspace '$LOG_ANALYTICS_NAME' already exists"
    else
        az monitor log-analytics workspace create \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_NAME" \
            --location "$LOCATION" \
            --sku pergb2018
        
        log_success "Log Analytics workspace created: $LOG_ANALYTICS_NAME"
    fi
    
    # Get workspace ID and key for Data Factory integration
    export WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_NAME" \
        --query customerId --output tsv)
    
    export WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_NAME" \
        --query primarySharedKey --output tsv)
    
    log "Log Analytics workspace ID: $WORKSPACE_ID"
}

# Function to create Function App
create_function_app() {
    log "Creating Azure Function App for data transformation..."
    
    # Check if Function App already exists
    if az functionapp show --resource-group "$RESOURCE_GROUP" --name "$FUNCTION_APP_NAME" &> /dev/null; then
        log_warning "Function App '$FUNCTION_APP_NAME' already exists"
    else
        az functionapp create \
            --resource-group "$RESOURCE_GROUP" \
            --consumption-plan-location "$LOCATION" \
            --runtime python \
            --functions-version 4 \
            --name "$FUNCTION_APP_NAME" \
            --storage-account "$STORAGE_ACCOUNT_NAME" \
            --os-type Linux
        
        log_success "Function App created: $FUNCTION_APP_NAME"
    fi
    
    # Get storage connection string
    local STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STORAGE_ACCOUNT_NAME" \
        --query connectionString --output tsv)
    
    # Configure Function App settings
    log "Configuring Function App settings..."
    az functionapp config appsettings set \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FUNCTION_APP_NAME" \
        --settings "APPINSIGHTS_INSTRUMENTATIONKEY=$WORKSPACE_ID" \
                   "FUNCTIONS_WORKER_RUNTIME=python" \
                   "STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION_STRING"
    
    log_success "Function App configuration completed"
}

# Function to create Data Factory components
create_data_factory_components() {
    log "Creating Data Factory linked services, datasets, and pipelines..."
    
    # Get storage connection string
    local STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STORAGE_ACCOUNT_NAME" \
        --query connectionString --output tsv)
    
    # Create linked service for storage account
    log "Creating storage linked service..."
    az datafactory linked-service create \
        --resource-group "$RESOURCE_GROUP" \
        --factory-name "$DATA_FACTORY_NAME" \
        --linked-service-name "StorageLinkedService" \
        --properties "{
            \"type\": \"AzureBlobStorage\",
            \"typeProperties\": {
                \"connectionString\": {
                    \"type\": \"SecureString\",
                    \"value\": \"$STORAGE_CONNECTION_STRING\"
                }
            }
        }" || log_warning "Storage linked service may already exist"
    
    # Create dataset for environmental data
    log "Creating environmental data dataset..."
    az datafactory dataset create \
        --resource-group "$RESOURCE_GROUP" \
        --factory-name "$DATA_FACTORY_NAME" \
        --dataset-name "EnvironmentalDataSet" \
        --properties "{
            \"type\": \"DelimitedText\",
            \"linkedServiceName\": {
                \"referenceName\": \"StorageLinkedService\",
                \"type\": \"LinkedServiceReference\"
            },
            \"typeProperties\": {
                \"location\": {
                    \"type\": \"AzureBlobStorageLocation\",
                    \"container\": \"environmental-data\",
                    \"fileName\": \"*.csv\"
                },
                \"columnDelimiter\": \",\",
                \"firstRowAsHeader\": true
            }
        }" || log_warning "Environmental data dataset may already exist"
    
    # Create the main data processing pipeline
    log "Creating environmental data processing pipeline..."
    az datafactory pipeline create \
        --resource-group "$RESOURCE_GROUP" \
        --factory-name "$DATA_FACTORY_NAME" \
        --pipeline-name "EnvironmentalDataPipeline" \
        --properties "{
            \"activities\": [
                {
                    \"name\": \"CopyEnvironmentalData\",
                    \"type\": \"Copy\",
                    \"inputs\": [
                        {
                            \"referenceName\": \"EnvironmentalDataSet\",
                            \"type\": \"DatasetReference\"
                        }
                    ],
                    \"outputs\": [
                        {
                            \"referenceName\": \"EnvironmentalDataSet\",
                            \"type\": \"DatasetReference\"
                        }
                    ],
                    \"typeProperties\": {
                        \"source\": {
                            \"type\": \"DelimitedTextSource\"
                        },
                        \"sink\": {
                            \"type\": \"DelimitedTextSink\"
                        }
                    }
                }
            ]
        }" || log_warning "Environmental data pipeline may already exist"
    
    log_success "Data Factory components created successfully"
}

# Function to create pipeline triggers
create_pipeline_triggers() {
    log "Creating pipeline triggers for automation..."
    
    # Get current UTC time for trigger start time
    local START_TIME=$(date -u +%Y-%m-%dT06:00:00Z)
    
    # Create schedule trigger for daily data processing
    az datafactory trigger create \
        --resource-group "$RESOURCE_GROUP" \
        --factory-name "$DATA_FACTORY_NAME" \
        --trigger-name "DailyEnvironmentalDataTrigger" \
        --properties "{
            \"type\": \"ScheduleTrigger\",
            \"typeProperties\": {
                \"recurrence\": {
                    \"frequency\": \"Day\",
                    \"interval\": 1,
                    \"startTime\": \"$START_TIME\",
                    \"timeZone\": \"UTC\"
                }
            },
            \"pipelines\": [
                {
                    \"pipelineReference\": {
                        \"referenceName\": \"EnvironmentalDataPipeline\",
                        \"type\": \"PipelineReference\"
                    }
                }
            ]
        }" || log_warning "Daily trigger may already exist"
    
    # Start the trigger
    log "Starting the daily trigger..."
    az datafactory trigger start \
        --resource-group "$RESOURCE_GROUP" \
        --factory-name "$DATA_FACTORY_NAME" \
        --trigger-name "DailyEnvironmentalDataTrigger" || log_warning "Trigger may already be running"
    
    log_success "Daily trigger configured and started"
}

# Function to create monitoring alerts
create_monitoring_alerts() {
    log "Creating Azure Monitor alerts for compliance thresholds..."
    
    # Create action group for alert notifications
    log "Creating action group for notifications..."
    az monitor action-group create \
        --resource-group "$RESOURCE_GROUP" \
        --name "EnvironmentalAlerts" \
        --short-name "EnvAlerts" \
        --email-receivers name=admin email=admin@company.com || log_warning "Action group may already exist"
    
    # Create alert rule for pipeline failures
    log "Creating alert for pipeline failures..."
    az monitor metrics alert create \
        --resource-group "$RESOURCE_GROUP" \
        --name "EnvironmentalPipelineFailures" \
        --description "Alert when environmental data pipeline fails" \
        --scopes "$ADF_RESOURCE_ID" \
        --condition "count PipelineFailedRuns > 0" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --severity 2 \
        --action-groups "EnvironmentalAlerts" || log_warning "Pipeline failure alert may already exist"
    
    # Create alert for data processing delays
    log "Creating alert for processing delays..."
    az monitor metrics alert create \
        --resource-group "$RESOURCE_GROUP" \
        --name "EnvironmentalDataProcessingDelay" \
        --description "Alert when environmental data processing is delayed" \
        --scopes "$ADF_RESOURCE_ID" \
        --condition "average PipelineRunDuration > 1800" \
        --window-size 15m \
        --evaluation-frequency 5m \
        --severity 3 \
        --action-groups "EnvironmentalAlerts" || log_warning "Processing delay alert may already exist"
    
    log_success "Environmental monitoring alerts configured"
}

# Function to configure diagnostic settings
configure_diagnostic_settings() {
    log "Configuring diagnostic settings for comprehensive monitoring..."
    
    # Enable diagnostic settings for Data Factory
    az monitor diagnostic-settings create \
        --resource "$ADF_RESOURCE_ID" \
        --name "EnvironmentalDataFactoryDiagnostics" \
        --workspace "$WORKSPACE_ID" \
        --logs '[
            {
                "category": "PipelineRuns",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 90
                }
            },
            {
                "category": "ActivityRuns",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 90
                }
            },
            {
                "category": "TriggerRuns",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 90
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
        ]' || log_warning "Diagnostic settings may already exist"
    
    log_success "Comprehensive diagnostic settings configured"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check Data Factory status
    local df_status=$(az datafactory show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DATA_FACTORY_NAME" \
        --query "provisioningState" --output tsv)
    
    if [ "$df_status" == "Succeeded" ]; then
        log_success "Data Factory deployment validated: $DATA_FACTORY_NAME"
    else
        log_error "Data Factory deployment failed or incomplete"
        return 1
    fi
    
    # Check if pipeline exists
    local pipeline_count=$(az datafactory pipeline list \
        --resource-group "$RESOURCE_GROUP" \
        --factory-name "$DATA_FACTORY_NAME" \
        --query "length(@)" --output tsv)
    
    if [ "$pipeline_count" -gt 0 ]; then
        log_success "Pipeline validation passed: $pipeline_count pipeline(s) created"
    else
        log_error "No pipelines found in Data Factory"
        return 1
    fi
    
    # Check Log Analytics workspace
    local la_status=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_NAME" \
        --query "provisioningState" --output tsv)
    
    if [ "$la_status" == "Succeeded" ]; then
        log_success "Log Analytics workspace validated: $LOG_ANALYTICS_NAME"
    else
        log_error "Log Analytics workspace deployment failed"
        return 1
    fi
    
    log_success "Deployment validation completed successfully"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "===================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Data Factory: $DATA_FACTORY_NAME"
    echo "Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "Function App: $FUNCTION_APP_NAME"
    echo "Log Analytics: $LOG_ANALYTICS_NAME"
    echo "===================="
    echo ""
    echo "Next Steps:"
    echo "1. Upload sample environmental data to the storage account"
    echo "2. Configure additional data sources as needed"
    echo "3. Customize the Function App with your data transformation logic"
    echo "4. Set up Azure Sustainability Manager integration"
    echo "5. Configure notification email addresses in the action group"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log "Starting Azure Environmental Data Pipeline deployment..."
    
    # Run deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_storage_account
    create_data_factory
    create_log_analytics
    create_function_app
    create_data_factory_components
    create_pipeline_triggers
    create_monitoring_alerts
    configure_diagnostic_settings
    validate_deployment
    display_summary
    
    log_success "Deployment completed successfully!"
    log "Total deployment time: $SECONDS seconds"
}

# Error handling
trap 'log_error "Deployment failed at line $LINENO. Exit code: $?"' ERR

# Execute main function
main "$@"