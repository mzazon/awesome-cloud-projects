---
title: Predictive Maintenance with IoT Edge Analytics
id: 3f8e9b2c
category: iot
difficulty: 200
subject: azure
services: Azure IoT Edge, Azure Monitor, Azure Stream Analytics, Azure Storage
estimated-time: 90 minutes
recipe-version: 1.0
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: null
passed-qa: null
tags: iot, edge-computing, predictive-maintenance, real-time-analytics, anomaly-detection
recipe-generator-version: 1.3
---

# Predictive Maintenance with IoT Edge Analytics

## Problem

Manufacturing facilities often struggle with unexpected equipment failures that lead to costly production downtime, emergency repairs, and potential safety hazards. Traditional maintenance approaches rely on fixed schedules or reactive responses after failures occur, resulting in either unnecessary maintenance costs or catastrophic equipment breakdowns. Remote or bandwidth-constrained locations compound this challenge by limiting real-time cloud connectivity for immediate analysis and response to critical sensor data.

## Solution

Deploy Azure IoT Edge with Stream Analytics to process sensor data locally on industrial equipment, enabling real-time anomaly detection and predictive maintenance alerts without cloud dependency. This edge-based architecture combines Azure IoT Edge runtime for container orchestration, Stream Analytics for real-time data processing, Azure Monitor for alerting and diagnostics, and Azure Storage for historical telemetry archival, creating a resilient system that operates effectively even with intermittent connectivity.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Factory Floor"
        SENSOR[Industrial Sensors]
        EDGE[IoT Edge Device]
        EQUIP[Industrial Equipment]
    end
    
    subgraph "Edge Modules"
        TEMP[Temperature Sensor Module]
        SA[Stream Analytics Module]
        ALERT[Alert Handler Module]
    end
    
    subgraph "Azure Cloud"
        HUB[IoT Hub]
        MON[Azure Monitor]
        STOR[Azure Storage]
        LA[Log Analytics]
    end
    
    SENSOR -->|1. Telemetry| EDGE
    EDGE --> TEMP
    TEMP -->|2. Data Stream| SA
    SA -->|3. Anomaly Detection| ALERT
    ALERT -->|4. Local Alert| EQUIP
    ALERT -->|5. Cloud Alert| HUB
    HUB --> MON
    HUB --> STOR
    MON --> LA
    
    style EDGE fill:#FF9900
    style SA fill:#3F8624
    style MON fill:#0078D4
```

## Prerequisites

1. Azure account with Contributor access to create IoT Hub, Storage, and monitoring resources
2. Azure CLI v2.48.0 or later installed and configured (or use Azure Cloud Shell)
3. Physical IoT Edge device or Ubuntu VM (18.04 or later) with at least 2GB RAM
4. Docker installed on the edge device (automatically installed with IoT Edge runtime)
5. Basic understanding of IoT concepts and time-series data analysis
6. Estimated cost: ~$50/month (IoT Hub S1, Storage, minimal Stream Analytics usage)

> **Note**: This recipe uses a simulated temperature sensor for demonstration. In production, replace with actual industrial sensor modules compatible with your equipment.

## Preparation

```bash
# Set environment variables
export RESOURCE_GROUP="rg-predictive-maintenance"
export LOCATION="eastus"
export IOT_HUB_NAME="hub-pm-$(openssl rand -hex 4)"
export STORAGE_ACCOUNT="stpm$(openssl rand -hex 4)"
export DEVICE_ID="edge-device-01"
export SA_JOB_NAME="sa-edge-anomaly"
export LOG_ANALYTICS_WORKSPACE="law-pm-$(openssl rand -hex 4)"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION} \
    --tags purpose=predictive-maintenance environment=demo

# Create IoT Hub
az iot hub create \
    --name ${IOT_HUB_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --location ${LOCATION} \
    --sku S1

# Create Storage Account for Stream Analytics
az storage account create \
    --name ${STORAGE_ACCOUNT} \
    --resource-group ${RESOURCE_GROUP} \
    --location ${LOCATION} \
    --sku Standard_LRS \
    --kind StorageV2

# Create container for SA job storage
az storage container create \
    --name streamanalytics \
    --account-name ${STORAGE_ACCOUNT} \
    --auth-mode login

# Create Log Analytics Workspace
az monitor log-analytics workspace create \
    --resource-group ${RESOURCE_GROUP} \
    --workspace-name ${LOG_ANALYTICS_WORKSPACE} \
    --location ${LOCATION}

echo "✅ Foundation resources created successfully"
```

## Steps

1. **Register IoT Edge Device with IoT Hub**:

   Azure IoT Edge extends cloud intelligence to edge devices, enabling local data processing and decision-making. Registering an edge device creates a secure identity in IoT Hub that manages module deployment, configuration updates, and telemetry routing. This device identity uses symmetric keys or X.509 certificates for authentication, establishing the trust relationship necessary for secure edge-to-cloud communication.

   ```bash
   # Create edge device identity
   az iot hub device-identity create \
       --device-id ${DEVICE_ID} \
       --edge-enabled \
       --hub-name ${IOT_HUB_NAME} \
       --resource-group ${RESOURCE_GROUP}
   
   # Retrieve connection string for edge device
   CONNECTION_STRING=$(az iot hub device-identity connection-string show \
       --device-id ${DEVICE_ID} \
       --hub-name ${IOT_HUB_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --query connectionString \
       --output tsv)
   
   echo "✅ Edge device registered. Save this connection string:"
   echo "${CONNECTION_STRING}"
   ```

   The IoT Edge device is now registered with a unique identity in IoT Hub. This connection string will be used to configure the IoT Edge runtime on your physical device, enabling secure module deployment and management from the cloud.

2. **Create Stream Analytics Job for Edge Deployment**:

   Azure Stream Analytics on IoT Edge brings cloud-scale analytics to edge devices, processing streaming data with SQL-like queries while operating within resource constraints. Creating an edge-hosted job enables sub-millisecond latency for anomaly detection, crucial for preventing equipment damage. The job definition remains in the cloud for easy updates while execution happens locally, providing the perfect balance of manageability and performance.

   ```bash
   # Create Stream Analytics job configured for IoT Edge
   az stream-analytics job create \
       --name ${SA_JOB_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --location ${LOCATION} \
       --compatibility-level "1.2" \
       --sku Standard \
       --tags environment=edge purpose=anomaly-detection
   
   # Configure job to run on IoT Edge
   az stream-analytics job update \
       --name ${SA_JOB_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --job-type Edge
   
   echo "✅ Stream Analytics job created for edge deployment"
   ```

3. **Configure Stream Analytics Inputs and Outputs**:

   Stream Analytics jobs require properly defined inputs and outputs to create data processing pipelines. For edge scenarios, the Edge Hub serves as the message broker between modules, enabling seamless data flow from sensors through analytics to action modules. This configuration establishes the data contracts between modules, ensuring type safety and enabling the Stream Analytics engine to optimize query execution for edge constraints.

   ```bash
   # Create input from Edge Hub (receives sensor data)
   az stream-analytics input create \
       --resource-group ${RESOURCE_GROUP} \
       --job-name ${SA_JOB_NAME} \
       --name temperature-input \
       --type Stream \
       --datasource @- <<EOF
   {
     "type": "Microsoft.Devices/IotHubs",
     "properties": {
       "iotHubNamespace": "${IOT_HUB_NAME}",
       "sharedAccessPolicyName": "iothubowner",
       "endpoint": "messages/events",
       "consumerGroupName": "\$Default"
     }
   }
   EOF
   
   # Create output to Edge Hub (sends alerts)
   az stream-analytics output create \
       --resource-group ${RESOURCE_GROUP} \
       --job-name ${SA_JOB_NAME} \
       --name anomaly-output \
       --datasource @- <<EOF
   {
     "type": "Microsoft.Devices/IotHubs",
     "properties": {
       "iotHubNamespace": "${IOT_HUB_NAME}",
       "sharedAccessPolicyName": "iothubowner",
       "endpoint": "messages/events"
     }
   }
   EOF
   
   echo "✅ Input and output configured for Stream Analytics"
   ```

4. **Define Anomaly Detection Query**:

   The Stream Analytics query implements a sliding window algorithm to detect temperature anomalies that indicate potential equipment failure. By analyzing 30-second windows of sensor data, the query identifies sustained high temperatures that often precede mechanical failures. This predictive approach enables maintenance teams to intervene before catastrophic failure, reducing downtime by up to 75% compared to reactive maintenance strategies.

   ```bash
   # Create anomaly detection query
   QUERY="SELECT
       'maintenance_required' AS alertType,
       System.Timestamp() AS alertTime,
       AVG(temperature) AS avgTemperature,
       MAX(temperature) AS maxTemperature,
       COUNT(*) AS readingCount
   INTO
       [anomaly-output]
   FROM
       [temperature-input] TIMESTAMP BY timeCreated
   GROUP BY
       TumblingWindow(second, 30)
   HAVING
       AVG(temperature) > 75 OR MAX(temperature) > 85"
   
   # Update the Stream Analytics job with the query
   az stream-analytics transformation create \
       --resource-group ${RESOURCE_GROUP} \
       --job-name ${SA_JOB_NAME} \
       --name Transformation \
       --streaming-units 1 \
       --transformation-query "${QUERY}"
   
   echo "✅ Anomaly detection query configured"
   ```

   This query continuously monitors temperature readings and triggers alerts when average temperatures exceed 75°C or peak temperatures surpass 85°C within any 30-second window, providing early warning of potential equipment issues.

5. **Link Stream Analytics Job to Storage Account**:

   Edge-deployed Stream Analytics jobs require Azure Storage to host the job definition and configuration that edge devices download during deployment. This storage account serves as the distribution point for job artifacts, enabling version control and staged rollouts across your edge fleet. The secure connection ensures only authorized edge devices can access the job definition while maintaining audit trails of deployments.

   ```bash
   # Get storage account key
   STORAGE_KEY=$(az storage account keys list \
       --resource-group ${RESOURCE_GROUP} \
       --account-name ${STORAGE_ACCOUNT} \
       --query "[0].value" \
       --output tsv)
   
   # Link Stream Analytics job to storage
   az stream-analytics job update \
       --name ${SA_JOB_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --job-storage-account "{
           \"accountName\": \"${STORAGE_ACCOUNT}\",
           \"accountKey\": \"${STORAGE_KEY}\",
           \"authenticationMode\": \"Msi\"
       }"
   
   # Publish the job for edge deployment
   az stream-analytics job start \
       --name ${SA_JOB_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --output-start-mode JobStartTime
   
   echo "✅ Stream Analytics job linked to storage and published"
   ```

6. **Configure Azure Monitor Alerts**:

   Azure Monitor provides comprehensive observability for your predictive maintenance solution, transforming edge-generated alerts into actionable notifications. By creating metric-based alert rules, you ensure that maintenance teams receive immediate notification of anomalies through multiple channels. This proactive alerting system integrates with existing ITSM tools and can trigger automated workflows, reducing mean time to response (MTTR) for critical equipment issues.

   ```bash
   # Create action group for alerts
   az monitor action-group create \
       --name ag-maintenance-team \
       --resource-group ${RESOURCE_GROUP} \
       --short-name MaintTeam \
       --email-receiver name=Maintenance email=maint@example.com \
       --sms-receiver name=OnCall country-code=1 phone-number=5551234567
   
   # Create alert rule for device anomalies
   az monitor metrics alert create \
       --name alert-high-temperature \
       --resource-group ${RESOURCE_GROUP} \
       --scopes "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Devices/IotHubs/${IOT_HUB_NAME}" \
       --condition "avg messages.telemetry.allProtocol > 100" \
       --window-size 5m \
       --evaluation-frequency 1m \
       --action ag-maintenance-team \
       --description "Alert when high message volume indicates anomalies"
   
   echo "✅ Azure Monitor alerts configured"
   ```

   The monitoring configuration now actively watches for anomaly patterns and will notify your maintenance team within minutes of detection, enabling rapid response to prevent equipment failure.

7. **Deploy Edge Modules via IoT Hub**:

   IoT Hub's module deployment mechanism orchestrates containerized workloads across your edge fleet using deployment manifests. This declarative approach ensures consistent configuration across devices while supporting rolling updates and version control. The manifest defines module images, creation options, and message routing rules that establish the data flow pipeline from sensors through analytics to action handlers.

   ```bash
   # Create deployment manifest
   cat > deployment.json <<EOF
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
           "modules": {
             "SimulatedTemperatureSensor": {
               "type": "docker",
               "status": "running",
               "restartPolicy": "always",
               "settings": {
                 "image": "mcr.microsoft.com/azureiotedge-simulated-temperature-sensor:1.0",
                 "createOptions": "{}"
               }
             },
             "StreamAnalytics": {
               "type": "docker",
               "status": "running",
               "restartPolicy": "always",
               "settings": {
                 "image": "mcr.microsoft.com/azure-stream-analytics/azureiotedge:1.0.9-linux-amd64",
                 "createOptions": "{}"
               }
             }
           }
         }
       },
       "\$edgeHub": {
         "properties.desired": {
           "routes": {
             "sensorToAnalytics": "FROM /messages/modules/SimulatedTemperatureSensor/outputs/temperatureOutput INTO BrokeredEndpoint('/modules/StreamAnalytics/inputs/temperature-input')",
             "analyticsToHub": "FROM /messages/modules/StreamAnalytics/outputs/anomaly-output INTO \$upstream"
           }
         }
       }
     }
   }
   EOF
   
   # Deploy to edge device
   az iot edge deployment create \
       --deployment-id predictive-maintenance-v1 \
       --hub-name ${IOT_HUB_NAME} \
       --content deployment.json \
       --target-condition "deviceId='${DEVICE_ID}'" \
       --priority 10
   
   echo "✅ Edge modules deployed successfully"
   ```

   The deployment manifest is now active, instructing your IoT Edge device to download and run the specified modules with proper message routing for the complete predictive maintenance pipeline.

8. **Configure Historical Data Archival**:

   Long-term telemetry storage in Azure Storage enables trend analysis, machine learning model training, and compliance with industrial data retention requirements. By implementing automated routing from IoT Hub to blob storage, you create a cost-effective archive that scales to petabytes while maintaining quick access to recent data. This historical dataset becomes invaluable for improving predictive models and understanding equipment degradation patterns over time.

   ```bash
   # Create storage container for telemetry archive
   az storage container create \
       --name telemetry-archive \
       --account-name ${STORAGE_ACCOUNT} \
       --auth-mode login
   
   # Create IoT Hub route to storage
   az iot hub route create \
       --hub-name ${IOT_HUB_NAME} \
       --route-name telemetry-to-storage \
       --source DeviceMessages \
       --endpoint-name telemetry-storage \
       --condition true \
       --enabled true
   
   # Configure storage endpoint
   STORAGE_CONNECTION=$(az storage account show-connection-string \
       --name ${STORAGE_ACCOUNT} \
       --resource-group ${RESOURCE_GROUP} \
       --query connectionString \
       --output tsv)
   
   az iot hub routing-endpoint create \
       --hub-name ${IOT_HUB_NAME} \
       --endpoint-name telemetry-storage \
       --endpoint-type azurestoragecontainer \
       --endpoint-resource-group ${RESOURCE_GROUP} \
       --endpoint-subscription-id $(az account show --query id -o tsv) \
       --connection-string "${STORAGE_CONNECTION}" \
       --container-name telemetry-archive \
       --encoding json
   
   echo "✅ Historical data archival configured"
   ```

   Your predictive maintenance solution now automatically archives all sensor telemetry to Azure Storage, creating a valuable dataset for future analysis and model improvement while meeting compliance requirements.

## Validation & Testing

1. Verify edge device module deployment status:

   ```bash
   # Check deployment status
   az iot edge deployment show \
       --deployment-id predictive-maintenance-v1 \
       --hub-name ${IOT_HUB_NAME} \
       --query "systemMetrics.results"
   ```

   Expected output: Should show "appliedCount": 1 and "reportedSuccessfulCount": 1

2. Monitor incoming telemetry messages:

   ```bash
   # Monitor device-to-cloud messages
   az iot hub monitor-events \
       --hub-name ${IOT_HUB_NAME} \
       --device-id ${DEVICE_ID} \
       --timeout 30
   ```

   Expected output: JSON messages with temperature readings and anomaly alerts when thresholds are exceeded

3. Verify Stream Analytics job metrics:

   ```bash
   # Check Stream Analytics job status
   az stream-analytics job show \
       --name ${SA_JOB_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --query "jobState"
   ```

   Expected output: "Running"

4. Test alert notifications:

   ```bash
   # Simulate high temperature to trigger alert
   # This would be done on the edge device by modifying sensor module
   
   # Check alert history
   az monitor activity-log alert list \
       --resource-group ${RESOURCE_GROUP} \
       --output table
   ```

## Cleanup

1. Stop and delete Stream Analytics job:

   ```bash
   # Stop the job
   az stream-analytics job stop \
       --name ${SA_JOB_NAME} \
       --resource-group ${RESOURCE_GROUP}
   
   # Delete the job
   az stream-analytics job delete \
       --name ${SA_JOB_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --yes
   
   echo "✅ Stream Analytics job deleted"
   ```

2. Remove IoT Edge deployment:

   ```bash
   # Delete deployment
   az iot edge deployment delete \
       --deployment-id predictive-maintenance-v1 \
       --hub-name ${IOT_HUB_NAME}
   
   # Delete device identity
   az iot hub device-identity delete \
       --device-id ${DEVICE_ID} \
       --hub-name ${IOT_HUB_NAME}
   
   echo "✅ Edge deployment and device removed"
   ```

3. Delete Azure resources:

   ```bash
   # Delete resource group and all resources
   az group delete \
       --name ${RESOURCE_GROUP} \
       --yes \
       --no-wait
   
   echo "✅ Resource deletion initiated"
   echo "Note: Complete deletion may take 5-10 minutes"
   ```

## Discussion

Azure IoT Edge transforms traditional reactive maintenance into intelligent predictive maintenance by processing sensor data at the source, eliminating the latency and bandwidth constraints of cloud-only solutions. This edge-based architecture is particularly valuable in industrial settings where network connectivity may be unreliable or where sub-second response times are critical for preventing equipment damage. The [Azure IoT Edge documentation](https://docs.microsoft.com/en-us/azure/iot-edge/) provides comprehensive guidance on production deployments and security hardening.

The combination of Stream Analytics on IoT Edge with Azure Monitor creates a multi-layered alerting system that operates both locally and in the cloud. Local processing ensures immediate response to critical anomalies, while cloud integration enables sophisticated analytics, long-term trend analysis, and enterprise-wide visibility. This hybrid approach follows the [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/) principles of reliability and operational excellence. For detailed patterns, see the [IoT reference architecture](https://docs.microsoft.com/en-us/azure/architecture/reference-architectures/iot).

Cost optimization is achieved through edge processing, which reduces data transmission costs by up to 90% compared to streaming all raw telemetry to the cloud. Only aggregated results and anomalies are sent to Azure, while detailed sensor data is processed locally. The [Azure IoT Edge pricing guide](https://docs.microsoft.com/en-us/azure/iot-edge/support) and [Stream Analytics pricing](https://azure.microsoft.com/en-us/pricing/details/stream-analytics/) help estimate operational costs. Additionally, the [Azure Cost Management best practices](https://docs.microsoft.com/en-us/azure/cost-management-billing/costs/cost-mgt-best-practices) provide strategies for monitoring and optimizing IoT solution expenses.

> **Tip**: Use Azure IoT Edge's built-in metrics and prometheus endpoint to integrate with existing monitoring infrastructure. The [monitoring and troubleshooting guide](https://docs.microsoft.com/en-us/azure/iot-edge/troubleshoot) provides detailed instructions for production observability.

## Challenge

Extend this solution by implementing these enhancements:

1. Add Azure Machine Learning module to perform advanced anomaly detection using trained models for specific equipment types
2. Implement automatic work order creation in your CMMS system when maintenance is predicted using Logic Apps
3. Create a Power BI dashboard that visualizes equipment health scores and predicted failure timelines using streaming datasets
4. Deploy Azure Cognitive Services module for visual inspection of equipment using connected cameras
5. Implement multi-factor prediction by combining vibration, temperature, and pressure sensors with custom Stream Analytics queries

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*