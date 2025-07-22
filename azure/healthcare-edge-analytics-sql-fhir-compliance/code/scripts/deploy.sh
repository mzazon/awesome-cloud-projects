#!/bin/bash

# Deploy script for Healthcare Edge Analytics with SQL Edge and FHIR Compliance
# This script deploys the complete infrastructure for healthcare edge analytics

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deployment.log"
readonly ERROR_LOG="${SCRIPT_DIR}/deployment_errors.log"

# Logging functions
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $*" | tee -a "${LOG_FILE}"
}

error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] ERROR: $*" | tee -a "${ERROR_LOG}" >&2
}

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${ERROR_LOG}")

log "=== Starting Healthcare Edge Analytics Deployment ==="

# Configuration variables with defaults
LOCATION="${LOCATION:-eastus}"
RESOURCE_GROUP_PREFIX="${RESOURCE_GROUP_PREFIX:-rg-healthcare-edge}"
IOT_HUB_PREFIX="${IOT_HUB_PREFIX:-iot-healthcare}"
EDGE_DEVICE_ID="${EDGE_DEVICE_ID:-medical-edge-device-01}"
WORKSPACE_PREFIX="${WORKSPACE_PREFIX:-ahds-workspace}"
FHIR_SERVICE_PREFIX="${FHIR_SERVICE_PREFIX:-fhir-service}"
FUNCTION_APP_PREFIX="${FUNCTION_APP_PREFIX:-func-health-alerts}"
STORAGE_ACCOUNT_PREFIX="${STORAGE_ACCOUNT_PREFIX:-sthealthdata}"
LOG_ANALYTICS_PREFIX="${LOG_ANALYTICS_PREFIX:-law-health}"

# Generate unique suffix for resource names
RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"

# Construct full resource names
RESOURCE_GROUP="${RESOURCE_GROUP_PREFIX}-${RANDOM_SUFFIX}"
IOT_HUB_NAME="${IOT_HUB_PREFIX}-${RANDOM_SUFFIX}"
WORKSPACE_NAME="${WORKSPACE_PREFIX}-${RANDOM_SUFFIX}"
FHIR_SERVICE_NAME="${FHIR_SERVICE_PREFIX}-${RANDOM_SUFFIX}"
FUNCTION_APP_NAME="${FUNCTION_APP_PREFIX}-${RANDOM_SUFFIX}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT_PREFIX}${RANDOM_SUFFIX}"
LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_PREFIX}-${RANDOM_SUFFIX}"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if required extensions are available
    log "Checking for required Azure CLI extensions..."
    
    # Check if healthcareapis extension is available
    if ! az extension list --query "[?name=='healthcareapis']" -o tsv &> /dev/null; then
        log "Installing healthcareapis extension..."
        az extension add --name healthcareapis || {
            error "Failed to install healthcareapis extension"
            exit 1
        }
    fi
    
    # Check if azure-iot extension is available
    if ! az extension list --query "[?name=='azure-iot']" -o tsv &> /dev/null; then
        log "Installing azure-iot extension..."
        az extension add --name azure-iot || {
            error "Failed to install azure-iot extension"
            exit 1
        }
    fi
    
    # Validate location
    if ! az account list-locations --query "[?name=='${LOCATION}']" -o tsv &> /dev/null; then
        error "Invalid location: ${LOCATION}"
        exit 1
    fi
    
    log "✅ Prerequisites check completed successfully"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log "Resource group ${RESOURCE_GROUP} already exists, skipping creation"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=healthcare-edge environment=demo deployment-script=true || {
            error "Failed to create resource group"
            exit 1
        }
        log "✅ Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account: ${STORAGE_ACCOUNT}"
    
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log "Storage account ${STORAGE_ACCOUNT} already exists, skipping creation"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --tags purpose=function-storage || {
            error "Failed to create storage account"
            exit 1
        }
        log "✅ Storage account created: ${STORAGE_ACCOUNT}"
    fi
}

# Function to create IoT Hub
create_iot_hub() {
    log "Creating IoT Hub: ${IOT_HUB_NAME}"
    
    if az iot hub show --name "${IOT_HUB_NAME}" &> /dev/null; then
        log "IoT Hub ${IOT_HUB_NAME} already exists, skipping creation"
    else
        az iot hub create \
            --name "${IOT_HUB_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku S1 \
            --partition-count 2 \
            --tags purpose=healthcare-edge || {
            error "Failed to create IoT Hub"
            exit 1
        }
        log "✅ IoT Hub created: ${IOT_HUB_NAME}"
    fi
    
    # Register IoT Edge device
    log "Registering IoT Edge device: ${EDGE_DEVICE_ID}"
    
    if az iot hub device-identity show --hub-name "${IOT_HUB_NAME}" --device-id "${EDGE_DEVICE_ID}" &> /dev/null; then
        log "Edge device ${EDGE_DEVICE_ID} already exists, skipping registration"
    else
        az iot hub device-identity create \
            --hub-name "${IOT_HUB_NAME}" \
            --device-id "${EDGE_DEVICE_ID}" \
            --edge-enabled \
            --auth-method shared_private_key || {
            error "Failed to register Edge device"
            exit 1
        }
        log "✅ IoT Edge device registered: ${EDGE_DEVICE_ID}"
    fi
    
    # Get and store connection string
    EDGE_CONNECTION_STRING=$(az iot hub device-identity connection-string show \
        --hub-name "${IOT_HUB_NAME}" \
        --device-id "${EDGE_DEVICE_ID}" \
        --query connectionString \
        --output tsv) || {
        error "Failed to get Edge device connection string"
        exit 1
    }
    
    log "Edge device connection string obtained (saved to edge_connection_string.txt)"
    echo "${EDGE_CONNECTION_STRING}" > "${SCRIPT_DIR}/edge_connection_string.txt"
}

# Function to create Health Data Services
create_health_data_services() {
    log "Creating Azure Health Data Services workspace: ${WORKSPACE_NAME}"
    
    if az healthcareapis workspace show --name "${WORKSPACE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log "Health Data Services workspace ${WORKSPACE_NAME} already exists, skipping creation"
    else
        az healthcareapis workspace create \
            --name "${WORKSPACE_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=healthcare-fhir || {
            error "Failed to create Health Data Services workspace"
            exit 1
        }
        log "✅ Health Data Services workspace created: ${WORKSPACE_NAME}"
    fi
    
    # Wait for workspace to be ready
    log "Waiting for workspace to be ready..."
    sleep 30
    
    # Create FHIR service
    log "Creating FHIR service: ${FHIR_SERVICE_NAME}"
    
    if az healthcareapis service fhir show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${WORKSPACE_NAME}" \
        --fhir-service-name "${FHIR_SERVICE_NAME}" &> /dev/null; then
        log "FHIR service ${FHIR_SERVICE_NAME} already exists, skipping creation"
    else
        az healthcareapis service fhir create \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${WORKSPACE_NAME}" \
            --fhir-service-name "${FHIR_SERVICE_NAME}" \
            --location "${LOCATION}" \
            --kind fhir-R4 \
            --identity-type SystemAssigned \
            --tags purpose=fhir-storage || {
            error "Failed to create FHIR service"
            exit 1
        }
        log "✅ FHIR service created: ${FHIR_SERVICE_NAME}"
    fi
    
    # Get FHIR service URL
    FHIR_URL=$(az healthcareapis service fhir show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${WORKSPACE_NAME}" \
        --fhir-service-name "${FHIR_SERVICE_NAME}" \
        --query properties.serviceUrl \
        --output tsv) || {
        error "Failed to get FHIR service URL"
        exit 1
    }
    
    log "FHIR Service URL: ${FHIR_URL}"
    echo "${FHIR_URL}" > "${SCRIPT_DIR}/fhir_service_url.txt"
}

# Function to create Log Analytics workspace
create_log_analytics() {
    log "Creating Log Analytics workspace: ${LOG_ANALYTICS_WORKSPACE}"
    
    if az monitor log-analytics workspace show \
        --name "${LOG_ANALYTICS_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log "Log Analytics workspace ${LOG_ANALYTICS_WORKSPACE} already exists, skipping creation"
    else
        az monitor log-analytics workspace create \
            --name "${LOG_ANALYTICS_WORKSPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=monitoring || {
            error "Failed to create Log Analytics workspace"
            exit 1
        }
        log "✅ Log Analytics workspace created: ${LOG_ANALYTICS_WORKSPACE}"
    fi
    
    # Wait for workspace to be ready
    log "Waiting for Log Analytics workspace to be ready..."
    sleep 15
    
    # Get workspace ID and key
    WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --name "${LOG_ANALYTICS_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query customerId \
        --output tsv) || {
        error "Failed to get workspace ID"
        exit 1
    }
    
    WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
        --name "${LOG_ANALYTICS_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query primarySharedKey \
        --output tsv) || {
        error "Failed to get workspace key"
        exit 1
    }
    
    # Enable IoT Hub diagnostics
    log "Enabling IoT Hub diagnostics..."
    
    IOT_HUB_RESOURCE_ID=$(az iot hub show \
        --name "${IOT_HUB_NAME}" \
        --query id \
        --output tsv) || {
        error "Failed to get IoT Hub resource ID"
        exit 1
    }
    
    az monitor diagnostic-settings create \
        --name "iot-diagnostics" \
        --resource "${IOT_HUB_RESOURCE_ID}" \
        --workspace "${LOG_ANALYTICS_WORKSPACE}" \
        --logs '[{"category": "Connections", "enabled": true},
                 {"category": "DeviceTelemetry", "enabled": true}]' \
        --metrics '[{"category": "AllMetrics", "enabled": true}]' || {
        log "Warning: Failed to configure IoT Hub diagnostics (may already exist)"
    }
    
    log "✅ Log Analytics workspace configured"
    echo "${WORKSPACE_ID}" > "${SCRIPT_DIR}/workspace_id.txt"
    echo "${WORKSPACE_KEY}" > "${SCRIPT_DIR}/workspace_key.txt"
}

# Function to create Azure Functions
create_azure_functions() {
    log "Creating Function App: ${FUNCTION_APP_NAME}"
    
    if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log "Function App ${FUNCTION_APP_NAME} already exists, skipping creation"
    else
        az functionapp create \
            --name "${FUNCTION_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_ACCOUNT}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime dotnet \
            --functions-version 4 \
            --tags purpose=alert-processing || {
            error "Failed to create Function App"
            exit 1
        }
        log "✅ Function App created: ${FUNCTION_APP_NAME}"
    fi
    
    # Get IoT Hub connection string
    IOT_HUB_CONNECTION=$(az iot hub connection-string show \
        --hub-name "${IOT_HUB_NAME}" \
        --policy-name iothubowner \
        --query connectionString \
        --output tsv) || {
        error "Failed to get IoT Hub connection string"
        exit 1
    }
    
    # Configure Function App settings
    log "Configuring Function App settings..."
    
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "FHIR_URL=${FHIR_URL}" \
                   "IOT_HUB_CONNECTION=${IOT_HUB_CONNECTION}" || {
        error "Failed to configure Function App settings"
        exit 1
    }
    
    # Enable Application Insights
    log "Enabling Application Insights..."
    
    if az monitor app-insights component show \
        --app "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log "Application Insights already exists for Function App"
    else
        az monitor app-insights component create \
            --app "${FUNCTION_APP_NAME}" \
            --location "${LOCATION}" \
            --resource-group "${RESOURCE_GROUP}" \
            --application-type web \
            --tags purpose=function-monitoring || {
            log "Warning: Failed to create Application Insights (may not be available in region)"
        }
    fi
    
    log "✅ Azure Functions configured"
}

# Function to create SQL Edge deployment manifest
create_sql_edge_deployment() {
    log "Creating SQL Edge deployment manifest..."
    
    cat > "${SCRIPT_DIR}/deployment.json" << EOF
{
  "modulesContent": {
    "\$edgeAgent": {
      "properties.desired": {
        "runtime": {
          "type": "docker",
          "settings": {
            "minDockerVersion": "v1.25"
          }
        },
        "systemModules": {
          "edgeAgent": {
            "type": "docker",
            "settings": {
              "image": "mcr.microsoft.com/azureiotedge-agent:1.4",
              "createOptions": {}
            }
          },
          "edgeHub": {
            "type": "docker",
            "status": "running",
            "restartPolicy": "always",
            "settings": {
              "image": "mcr.microsoft.com/azureiotedge-hub:1.4",
              "createOptions": {
                "HostConfig": {
                  "PortBindings": {
                    "5671/tcp": [{"HostPort": "5671"}],
                    "8883/tcp": [{"HostPort": "8883"}]
                  }
                }
              }
            }
          }
        },
        "modules": {
          "sqlEdge": {
            "version": "1.0",
            "type": "docker",
            "status": "running",
            "restartPolicy": "always",
            "settings": {
              "image": "mcr.microsoft.com/azure-sql-edge:latest",
              "createOptions": {
                "HostConfig": {
                  "PortBindings": {
                    "1433/tcp": [{"HostPort": "1433"}]
                  },
                  "Mounts": [
                    {
                      "Type": "volume",
                      "Source": "sqlvolume",
                      "Target": "/var/opt/mssql"
                    }
                  ]
                },
                "Env": [
                  "ACCEPT_EULA=Y",
                  "MSSQL_SA_PASSWORD=Strong!Passw0rd",
                  "MSSQL_LCID=1033",
                  "MSSQL_COLLATION=SQL_Latin1_General_CP1_CI_AS"
                ]
              }
            }
          }
        }
      }
    }
  }
}
EOF
    
    # Deploy to Edge device
    log "Deploying SQL Edge module to device..."
    
    az iot edge set-modules \
        --hub-name "${IOT_HUB_NAME}" \
        --device-id "${EDGE_DEVICE_ID}" \
        --content "${SCRIPT_DIR}/deployment.json" || {
        error "Failed to deploy SQL Edge module"
        exit 1
    }
    
    log "✅ Azure SQL Edge module deployed to edge device"
}

# Function to create analytics query
create_analytics_query() {
    log "Creating edge analytics query..."
    
    cat > "${SCRIPT_DIR}/edge-analytics-query.sql" << 'EOF'
WITH VitalSigns AS (
    SELECT
        DeviceId,
        PatientId,
        HeartRate,
        BloodPressureSystolic,
        BloodPressureDiastolic,
        OxygenSaturation,
        Temperature,
        EventEnqueuedUtcTime,
        CASE 
            WHEN HeartRate > 120 OR HeartRate < 50 THEN 'Critical'
            WHEN OxygenSaturation < 90 THEN 'Critical'
            WHEN BloodPressureSystolic > 180 THEN 'Critical'
            WHEN Temperature > 39.5 THEN 'Warning'
            ELSE 'Normal'
        END AS AlertLevel
    FROM
        Input TIMESTAMP BY EventEnqueuedUtcTime
)
SELECT
    *,
    System.Timestamp() AS WindowEnd
INTO
    Output
FROM
    VitalSigns
WHERE
    AlertLevel IN ('Critical', 'Warning')
EOF
    
    log "✅ Edge analytics query created"
}

# Function to create FHIR transformation code
create_fhir_transformation() {
    log "Creating FHIR transformation code..."
    
    cat > "${SCRIPT_DIR}/fhir-transform.cs" << 'EOF'
using System;
using System.Collections.Generic;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using Hl7.Fhir.Model;
using Hl7.Fhir.Serialization;

public static class FhirTransform
{
    [FunctionName("TransformToFHIR")]
    public static void Run(
        [EventHubTrigger("health-alerts", Connection = "IOT_HUB_CONNECTION")] string message,
        ILogger log)
    {
        try
        {
            dynamic data = JsonConvert.DeserializeObject(message);
            
            var observation = new Observation
            {
                Status = ObservationStatus.Final,
                Code = new CodeableConcept
                {
                    Coding = new List<Coding>
                    {
                        new Coding
                        {
                            System = "http://loinc.org",
                            Code = "8867-4",
                            Display = "Heart rate"
                        }
                    }
                },
                Subject = new ResourceReference($"Patient/{data.PatientId}"),
                Effective = new FhirDateTime(DateTime.UtcNow),
                Value = new Quantity
                {
                    Value = data.HeartRate,
                    Unit = "beats/minute",
                    System = "http://unitsofmeasure.org",
                    Code = "/min"
                }
            };
            
            // Send to FHIR service
            log.LogInformation($"Transformed observation for patient {data.PatientId}");
        }
        catch (Exception ex)
        {
            log.LogError($"Error transforming to FHIR: {ex.Message}");
            throw;
        }
    }
}
EOF
    
    log "✅ FHIR transformation code created"
}

# Function to save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    cat > "${SCRIPT_DIR}/deployment_info.txt" << EOF
Healthcare Edge Analytics Deployment Information
===============================================

Resource Group: ${RESOURCE_GROUP}
Location: ${LOCATION}
Deployment Time: $(date)

IoT Hub: ${IOT_HUB_NAME}
Edge Device ID: ${EDGE_DEVICE_ID}

Health Data Services:
- Workspace: ${WORKSPACE_NAME}
- FHIR Service: ${FHIR_SERVICE_NAME}
- FHIR URL: ${FHIR_URL}

Function App: ${FUNCTION_APP_NAME}
Storage Account: ${STORAGE_ACCOUNT}
Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE}

Connection Strings and URLs saved in separate files:
- edge_connection_string.txt
- fhir_service_url.txt
- workspace_id.txt
- workspace_key.txt

Configuration Files:
- deployment.json (SQL Edge deployment manifest)
- edge-analytics-query.sql (Stream Analytics query)
- fhir-transform.cs (FHIR transformation function)

Next Steps:
1. Configure IoT Edge runtime on your edge device using the connection string
2. Deploy the FHIR transformation function code to the Function App
3. Set up Stream Analytics job using the provided query
4. Test the solution with sample medical device data

Cleanup:
To remove all resources, run: ./destroy.sh
EOF
    
    log "✅ Deployment information saved to deployment_info.txt"
}

# Main deployment function
main() {
    log "Starting deployment with configuration:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Location: ${LOCATION}"
    log "  Random Suffix: ${RANDOM_SUFFIX}"
    
    # Check if running in non-interactive mode
    if [[ "${CI:-false}" == "true" ]] || [[ "${AUTOMATED:-false}" == "true" ]]; then
        log "Running in automated mode, skipping confirmations"
    else
        # Confirmation prompt
        echo
        echo "This script will deploy Azure resources for Healthcare Edge Analytics."
        echo "Resource Group: ${RESOURCE_GROUP}"
        echo "Location: ${LOCATION}"
        echo
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Execute deployment steps
    check_prerequisites
    create_resource_group
    create_storage_account
    create_iot_hub
    create_health_data_services
    create_log_analytics
    create_azure_functions
    create_sql_edge_deployment
    create_analytics_query
    create_fhir_transformation
    save_deployment_info
    
    log "=== Healthcare Edge Analytics Deployment Completed Successfully ==="
    log ""
    log "Important files created:"
    log "  - deployment_info.txt: Complete deployment summary"
    log "  - edge_connection_string.txt: For IoT Edge runtime configuration"
    log "  - fhir_service_url.txt: FHIR service endpoint"
    log "  - deployment.json: SQL Edge deployment manifest"
    log "  - edge-analytics-query.sql: Stream Analytics query"
    log "  - fhir-transform.cs: FHIR transformation function"
    log ""
    log "Next steps:"
    log "  1. Configure IoT Edge runtime on your edge device"
    log "  2. Deploy function code to the Function App"
    log "  3. Set up Stream Analytics job"
    log "  4. Test with sample medical device data"
    log ""
    log "To clean up all resources, run: ./destroy.sh"
}

# Handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Deployment failed with exit code: $exit_code"
        log "Check the error log for details: ${ERROR_LOG}"
    fi
}

trap cleanup_on_exit EXIT

# Execute main function
main "$@"