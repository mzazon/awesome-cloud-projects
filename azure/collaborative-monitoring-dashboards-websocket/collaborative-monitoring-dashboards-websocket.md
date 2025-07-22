---
title: Collaborative Monitoring Dashboards with WebSocket Synchronization
id: a7f3b9d2
category: analytics
difficulty: 200
subject: azure
services: Azure Web PubSub, Azure Monitor, Azure Static Web Apps
estimated-time: 90 minutes
recipe-version: 1.0
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: null
passed-qa: null
tags: real-time, websocket, monitoring, dashboards, collaboration
recipe-generator-version: 1.3
---

# Collaborative Monitoring Dashboards with WebSocket Synchronization

## Problem

Operations teams struggle to monitor critical system metrics collaboratively, with team members viewing dashboards in isolation and lacking real-time awareness of investigations or annotations made by colleagues. Traditional monitoring solutions require constant page refreshes and don't support simultaneous multi-user interaction, leading to delayed incident response and duplicated investigation efforts.

## Solution

Implement a real-time collaborative monitoring dashboard using Azure Web PubSub for WebSocket-based synchronization, Azure Monitor for metrics collection, and Azure Static Web Apps for hosting. This serverless architecture enables instant metric updates, shared cursor tracking, and collaborative annotations while automatically scaling to support hundreds of concurrent users.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Users"
        U1[User 1]
        U2[User 2]
        U3[User N]
    end
    
    subgraph "Frontend Hosting"
        SWA[Azure Static Web Apps]
    end
    
    subgraph "Real-Time Communication"
        WPS[Azure Web PubSub]
        subgraph "Channels"
            MC[Metrics Channel]
            CC[Collaboration Channel]
        end
    end
    
    subgraph "Monitoring Data"
        AM[Azure Monitor]
        AI[Application Insights]
        LA[Log Analytics]
    end
    
    subgraph "Backend Processing"
        FA[Function App]
        subgraph "Functions"
            MF[Metrics Function]
            CF[Connection Function]
            AF[Auth Function]
        end
    end
    
    U1 --> SWA
    U2 --> SWA
    U3 --> SWA
    
    SWA <--> WPS
    WPS --> MC
    WPS --> CC
    
    FA --> WPS
    MF --> AM
    MF --> AI
    MF --> LA
    CF --> WPS
    AF --> WPS
    
    AM --> MF
    AI --> MF
    LA --> MF
    
    style WPS fill:#FF6B6B
    style AM fill:#4ECDC4
    style SWA fill:#45B7D1
    style FA fill:#96CEB4
```

## Prerequisites

1. Azure subscription with contributor access
2. Azure CLI v2.50.0 or higher installed (or use Azure Cloud Shell)
3. Node.js 18.x or higher for local development
4. Basic knowledge of JavaScript and WebSocket concepts
5. Familiarity with Azure Monitor metrics and KQL queries
6. Estimated cost: ~$5-10/month for development workload

> **Note**: This recipe uses consumption-based pricing models for most services, keeping costs minimal during development and testing phases.

## Preparation

```bash
# Set Azure subscription (if you have multiple)
az account set --subscription "your-subscription-id"

# Set environment variables
export RESOURCE_GROUP="rg-collab-dashboard"
export LOCATION="eastus"
export RANDOM_SUFFIX=$(openssl rand -hex 3)
export WEBPUBSUB_NAME="wps-dashboard-${RANDOM_SUFFIX}"
export STATIC_APP_NAME="swa-dashboard-${RANDOM_SUFFIX}"
export FUNCTION_APP_NAME="func-dashboard-${RANDOM_SUFFIX}"
export STORAGE_NAME="stdashboard${RANDOM_SUFFIX}"
export APP_INSIGHTS_NAME="appi-dashboard-${RANDOM_SUFFIX}"
export LOG_ANALYTICS_NAME="log-dashboard-${RANDOM_SUFFIX}"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION} \
    --tags purpose=collab-dashboard environment=demo

echo "✅ Resource group created: ${RESOURCE_GROUP}"
```

## Steps

1. **Create Log Analytics Workspace for Centralized Monitoring**:

   Azure Log Analytics provides a centralized repository for all monitoring data, enabling powerful KQL queries across multiple data sources. This workspace will collect metrics, logs, and custom telemetry from our dashboard components, forming the foundation for real-time metric visualization and historical analysis.

   ```bash
   # Create Log Analytics workspace
   az monitor log-analytics workspace create \
       --name ${LOG_ANALYTICS_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --location ${LOCATION} \
       --retention-time 30

   # Store workspace ID for later use
   LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
       --name ${LOG_ANALYTICS_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --query id --output tsv)

   echo "✅ Log Analytics workspace created"
   ```

   The workspace is configured with 30-day retention, balancing cost with the need for historical data analysis. This retention period allows teams to investigate trends and patterns over a meaningful timeframe.

2. **Deploy Application Insights for Application Performance Monitoring**:

   Application Insights provides deep application performance monitoring and distributed tracing capabilities. By connecting it to our Log Analytics workspace, we create a unified monitoring solution that correlates infrastructure metrics with application behavior, essential for comprehensive dashboard visibility.

   ```bash
   # Create Application Insights connected to Log Analytics
   az monitor app-insights component create \
       --app ${APP_INSIGHTS_NAME} \
       --location ${LOCATION} \
       --resource-group ${RESOURCE_GROUP} \
       --workspace ${LOG_ANALYTICS_ID} \
       --application-type web

   # Get instrumentation key for application configuration
   INSTRUMENTATION_KEY=$(az monitor app-insights component show \
       --app ${APP_INSIGHTS_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --query instrumentationKey --output tsv)

   echo "✅ Application Insights created with key: ${INSTRUMENTATION_KEY}"
   ```

3. **Configure Azure Web PubSub for Real-Time Communication**:

   Azure Web PubSub enables serverless WebSocket connections at scale, handling the complexity of connection management, authentication, and message routing. The service automatically scales from zero to millions of concurrent connections, making it ideal for collaborative experiences where user count can vary dramatically.

   ```bash
   # Create Azure Web PubSub service
   az webpubsub create \
       --name ${WEBPUBSUB_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --location ${LOCATION} \
       --sku Free_F1 \
       --unit-count 1

   # Configure hub settings for dashboard communication
   az webpubsub hub create \
       --name dashboard \
       --resource-group ${RESOURCE_GROUP} \
       --webpubsub-name ${WEBPUBSUB_NAME} \
       --event-handler url-template="https://${FUNCTION_APP_NAME}.azurewebsites.net/api/eventhandler" \
       --event-handler user-event-pattern="*" \
       --event-handler system-event="connect,connected,disconnected"

   # Get connection string for backend configuration
   WEBPUBSUB_CONNECTION=$(az webpubsub key show \
       --name ${WEBPUBSUB_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --query primaryConnectionString --output tsv)

   echo "✅ Web PubSub service configured with dashboard hub"
   ```

   The dashboard hub configuration establishes event handlers for connection lifecycle and custom events, enabling the backend to track user presence and broadcast updates efficiently.

4. **Create Storage Account for Function App Backend**:

   Azure Storage provides durable state management for our serverless backend, storing function code, maintaining execution state, and enabling reliable message processing. The storage account's queue service will handle asynchronous metric processing, ensuring dashboard responsiveness even under heavy load.

   ```bash
   # Create storage account for Function App
   az storage account create \
       --name ${STORAGE_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --location ${LOCATION} \
       --sku Standard_LRS \
       --https-only true \
       --min-tls-version TLS1_2

   # Enable CORS for Static Web Apps integration
   az storage cors add \
       --services b \
       --methods GET POST PUT \
       --origins "*" \
       --allowed-headers "*" \
       --max-age 86400 \
       --account-name ${STORAGE_NAME}

   echo "✅ Storage account created with security hardening"
   ```

5. **Deploy Function App for Backend Processing**:

   Azure Functions provides the serverless compute layer for our dashboard, handling WebSocket authentication, metric aggregation, and real-time data broadcasting. The consumption plan ensures cost-effective scaling, spinning up instances only when needed to process incoming requests or metric updates.

   ```bash
   # Create Function App with Node.js runtime
   az functionapp create \
       --name ${FUNCTION_APP_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --storage-account ${STORAGE_NAME} \
       --consumption-plan-location ${LOCATION} \
       --runtime node \
       --runtime-version 18 \
       --functions-version 4

   # Configure application settings
   az functionapp config appsettings set \
       --name ${FUNCTION_APP_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --settings \
           "WEBPUBSUB_CONNECTION=${WEBPUBSUB_CONNECTION}" \
           "APPINSIGHTS_INSTRUMENTATIONKEY=${INSTRUMENTATION_KEY}" \
           "AzureWebJobsFeatureFlags=EnableWorkerIndexing"

   # Enable Application Insights integration
   az monitor app-insights component connect-webapp \
       --app ${APP_INSIGHTS_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --web-app ${FUNCTION_APP_NAME}

   echo "✅ Function App deployed and configured"
   ```

   The Function App configuration includes Application Insights integration for end-to-end tracing, helping identify performance bottlenecks and debug real-time communication issues.

6. **Implement Real-Time Metric Collection Functions**:

   Creating Azure Functions that query Azure Monitor and broadcast metrics through Web PubSub enables real-time dashboard updates. These functions run on a timer trigger, collecting metrics at regular intervals and pushing updates to all connected clients simultaneously.

   ```bash
   # Create local function project structure
   mkdir -p dashboard-functions/MetricsCollector
   cd dashboard-functions

   # Create host.json for function app configuration
   cat > host.json << 'EOF'
   {
     "version": "2.0",
     "logging": {
       "applicationInsights": {
         "samplingSettings": {
           "isEnabled": true,
           "maxTelemetryItemsPerSecond": 20
         }
       }
     },
     "extensions": {
       "http": {
         "routePrefix": "api",
         "maxConcurrentRequests": 100
       }
     }
   }
   EOF

   # Create metrics collector function
   cat > MetricsCollector/function.json << 'EOF'
   {
     "bindings": [
       {
         "name": "myTimer",
         "type": "timerTrigger",
         "direction": "in",
         "schedule": "*/10 * * * * *"
       },
       {
         "name": "webPubSubContext",
         "type": "webPubSub",
         "direction": "out",
         "hub": "dashboard",
         "connection": "WEBPUBSUB_CONNECTION"
       }
     ]
   }
   EOF

   # Create metrics collector implementation
   cat > MetricsCollector/index.js << 'EOF'
   const { DefaultAzureCredential } = require("@azure/identity");
   const { MetricsQueryClient } = require("@azure/monitor-query");

   module.exports = async function (context, myTimer) {
       const client = new MetricsQueryClient(new DefaultAzureCredential());
       
       // Query multiple metrics from Azure Monitor
       const metrics = await client.queryResource(
           process.env.RESOURCE_ID,
           ["Percentage CPU", "Available Memory Bytes"],
           {
               timespan: "PT5M",
               interval: "PT1M"
           }
       );

       // Broadcast metrics to all connected clients
       context.bindings.webPubSubContext = {
           actionName: "sendToAll",
           data: JSON.stringify({
               type: "metrics",
               timestamp: new Date().toISOString(),
               data: metrics
           })
       };

       context.log("Metrics broadcast completed");
   };
   EOF

   echo "✅ Function code created locally"
   ```

7. **Create WebSocket Connection Handler for Client Management**:

   The connection handler manages client lifecycle events, maintaining user presence information and handling authentication. This function ensures secure access to the dashboard while enabling real-time collaboration features like cursor tracking and user activity indicators.

   ```bash
   # Create connection handler function
   mkdir -p ConnectionHandler
   
   cat > ConnectionHandler/function.json << 'EOF'
   {
     "bindings": [
       {
         "name": "req",
         "type": "httpTrigger",
         "direction": "in",
         "methods": ["post"]
       },
       {
         "name": "res",
         "type": "http",
         "direction": "out"
       },
       {
         "name": "webPubSubContext",
         "type": "webPubSubTrigger",
         "direction": "in",
         "hub": "dashboard",
         "eventName": "connect",
         "connection": "WEBPUBSUB_CONNECTION"
       }
     ]
   }
   EOF

   cat > ConnectionHandler/index.js << 'EOF'
   module.exports = async function (context, req, webPubSubContext) {
       // Validate user authentication
       const userId = req.headers['x-user-id'];
       if (!userId) {
           context.res = {
               status: 401,
               body: "Unauthorized"
           };
           return;
       }

       // Accept connection and assign to groups
       context.res = {
           body: {
               userId: userId,
               groups: ["dashboard-users"],
               permissions: ["webpubsub.sendToGroup.dashboard-users"]
           }
       };

       context.log(`User ${userId} connected to dashboard`);
   };
   EOF

   # Deploy functions to Azure
   cd ..
   func azure functionapp publish ${FUNCTION_APP_NAME} --javascript

   echo "✅ Functions deployed to Azure"
   ```

8. **Deploy Static Web App for Dashboard Frontend**:

   Azure Static Web Apps provides global content distribution and automatic SSL for our dashboard frontend. The service integrates with GitHub Actions for continuous deployment, enabling rapid iteration on dashboard features while maintaining high availability and performance.

   ```bash
   # Create dashboard frontend structure
   mkdir -p dashboard-frontend/src
   cd dashboard-frontend

   # Create package.json
   cat > package.json << 'EOF'
   {
     "name": "collab-dashboard",
     "version": "1.0.0",
     "scripts": {
       "build": "webpack --mode production",
       "start": "webpack-dev-server --mode development"
     },
     "dependencies": {
       "@azure/web-pubsub-client": "^1.1.0",
       "chart.js": "^4.3.0"
     }
   }
   EOF

   # Create main dashboard HTML
   cat > src/index.html << 'EOF'
   <!DOCTYPE html>
   <html>
   <head>
       <title>Collaborative Monitoring Dashboard</title>
       <style>
           .dashboard { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
           .metric-card { border: 1px solid #ddd; padding: 20px; }
           .user-cursor { position: absolute; pointer-events: none; }
       </style>
   </head>
   <body>
       <h1>Real-Time Collaborative Dashboard</h1>
       <div id="active-users"></div>
       <div class="dashboard" id="dashboard"></div>
       <script src="bundle.js"></script>
   </body>
   </html>
   EOF

   # Create main JavaScript application
   cat > src/app.js << 'EOF'
   import { WebPubSubClient } from "@azure/web-pubsub-client";
   import Chart from "chart.js/auto";

   class CollaborativeDashboard {
       constructor() {
           this.charts = new Map();
           this.users = new Map();
           this.initWebSocket();
       }

       async initWebSocket() {
           const response = await fetch("/api/negotiate");
           const { url } = await response.json();
           
           this.client = new WebPubSubClient(url, {
               reconnectRetryOptions: {
                   maxRetries: 10,
                   retryDelayInMs: 5000
               }
           });

           this.client.on("message", (e) => this.handleMessage(e));
           await this.client.connect();
       }

       handleMessage(event) {
           const message = JSON.parse(event.data);
           
           switch(message.type) {
               case "metrics":
                   this.updateCharts(message.data);
                   break;
               case "cursor":
                   this.updateUserCursor(message.userId, message.position);
                   break;
               case "annotation":
                   this.addAnnotation(message.data);
                   break;
           }
       }

       updateCharts(metrics) {
           // Update real-time charts with new metric data
           metrics.forEach(metric => {
               if (!this.charts.has(metric.name)) {
                   this.createChart(metric.name);
               }
               this.charts.get(metric.name).update();
           });
       }
   }

   new CollaborativeDashboard();
   EOF

   # Create Static Web App
   az staticwebapp create \
       --name ${STATIC_APP_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --location ${LOCATION} \
       --sku Free

   echo "✅ Static Web App created"
   ```

   The frontend application establishes a resilient WebSocket connection with automatic reconnection, ensuring users maintain real-time synchronization even during network interruptions.

9. **Configure API Integration and Authentication**:

   Connecting the Static Web App to our Function App backend enables secure API calls while maintaining the benefits of global edge distribution. This configuration establishes the negotiate endpoint for WebSocket authentication and other API routes for dashboard operations.

   ```bash
   # Link backend API to Static Web App
   az staticwebapp backends link \
       --name ${STATIC_APP_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --backend-resource-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/sites/${FUNCTION_APP_NAME}"

   # Create negotiate function for WebSocket auth
   mkdir -p ../Negotiate
   
   cat > ../Negotiate/function.json << 'EOF'
   {
     "bindings": [
       {
         "authLevel": "anonymous",
         "type": "httpTrigger",
         "direction": "in",
         "name": "req",
         "methods": ["post"]
       },
       {
         "type": "http",
         "direction": "out",
         "name": "res"
       },
       {
         "type": "webPubSubConnection",
         "direction": "in",
         "name": "connection",
         "hub": "dashboard",
         "connection": "WEBPUBSUB_CONNECTION"
       }
     ]
   }
   EOF

   cat > ../Negotiate/index.js << 'EOF'
   module.exports = async function (context, req, connection) {
       context.res = {
           body: connection
       };
   };
   EOF

   # Deploy updated functions
   cd ..
   func azure functionapp publish ${FUNCTION_APP_NAME} --javascript

   echo "✅ API integration configured"
   ```

10. **Enable Advanced Monitoring Features**:

    Implementing custom metrics and alerts ensures the dashboard itself remains performant and reliable. These monitoring configurations track WebSocket connection health, message throughput, and system performance, enabling proactive issue resolution.

    ```bash
    # Create custom metric alerts
    az monitor metrics alert create \
        --name "high-websocket-connections" \
        --resource-group ${RESOURCE_GROUP} \
        --scopes "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.SignalRService/webPubSub/${WEBPUBSUB_NAME}" \
        --condition "total ConnectionCount > 1000" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --severity 2 \
        --description "Alert when WebSocket connections exceed 1000"

    # Configure diagnostic settings
    az monitor diagnostic-settings create \
        --name "dashboard-diagnostics" \
        --resource "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.SignalRService/webPubSub/${WEBPUBSUB_NAME}" \
        --workspace ${LOG_ANALYTICS_ID} \
        --logs '[{"category": "AllLogs", "enabled": true}]' \
        --metrics '[{"category": "AllMetrics", "enabled": true}]'

    # Create dashboard in Azure Portal
    az portal dashboard create \
        --name "CollaborativeDashboard" \
        --resource-group ${RESOURCE_GROUP} \
        --input-path dashboard-template.json

    echo "✅ Monitoring and alerts configured"
    ```

## Validation & Testing

1. Verify Web PubSub service is running:

   ```bash
   # Check Web PubSub health
   az webpubsub show \
       --name ${WEBPUBSUB_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --query "provisioningState" --output tsv
   ```

   Expected output: `Succeeded`

2. Test Function App endpoints:

   ```bash
   # Get Function App URL
   FUNCTION_URL=$(az functionapp show \
       --name ${FUNCTION_APP_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --query "defaultHostName" --output tsv)

   # Test negotiate endpoint
   curl -X POST "https://${FUNCTION_URL}/api/negotiate" \
       -H "Content-Type: application/json" \
       -H "x-user-id: test-user"
   ```

   Expected output: JSON containing WebSocket URL and access token

3. Verify Static Web App deployment:

   ```bash
   # Get Static Web App URL
   STATIC_URL=$(az staticwebapp show \
       --name ${STATIC_APP_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --query "defaultHostname" --output tsv)

   echo "Dashboard URL: https://${STATIC_URL}"
   
   # Check deployment status
   az staticwebapp environment list \
       --name ${STATIC_APP_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --output table
   ```

4. Test real-time collaboration features:

   ```bash
   # Open dashboard in multiple browser windows
   echo "Open https://${STATIC_URL} in multiple browsers"
   echo "Verify:"
   echo "  - Real-time metric updates appear simultaneously"
   echo "  - Mouse cursors from other users are visible"
   echo "  - Annotations sync across all connected clients"
   ```

> **Tip**: Use browser developer tools to monitor WebSocket frames and verify real-time message flow. The Network tab should show persistent WebSocket connections with regular heartbeat messages.

## Cleanup

1. Remove all dashboard resources:

   ```bash
   # Delete resource group and all contained resources
   az group delete \
       --name ${RESOURCE_GROUP} \
       --yes \
       --no-wait

   echo "✅ Resource deletion initiated"
   ```

2. Verify cleanup completion:

   ```bash
   # Check if resource group still exists
   az group exists --name ${RESOURCE_GROUP}
   ```

   Expected output: `false` (after deletion completes)

3. Clean up local development files:

   ```bash
   # Remove local project directories
   rm -rf dashboard-functions dashboard-frontend

   echo "✅ Local files cleaned up"
   ```

## Discussion

Azure Web PubSub revolutionizes real-time collaborative applications by abstracting WebSocket complexity while providing enterprise-scale capabilities. Unlike traditional SignalR implementations, Web PubSub offers a serverless approach that eliminates server management overhead and automatically scales to millions of concurrent connections. This architecture pattern is particularly effective for monitoring dashboards where multiple team members need synchronized views of system health. For detailed architectural guidance, see the [Azure Web PubSub documentation](https://docs.microsoft.com/en-us/azure/azure-web-pubsub/overview) and [real-time messaging patterns](https://docs.microsoft.com/en-us/azure/azure-web-pubsub/concept-service-internals).

The integration with Azure Monitor creates a powerful observability platform that goes beyond traditional dashboards. By leveraging Log Analytics and Application Insights, teams gain access to advanced analytics capabilities including anomaly detection, predictive alerts, and correlation analysis across multiple data sources. The [Azure Monitor best practices guide](https://docs.microsoft.com/en-us/azure/azure-monitor/best-practices) provides comprehensive strategies for optimizing metric collection and visualization. Additionally, the [KQL query language documentation](https://docs.microsoft.com/en-us/azure/data-explorer/kusto/query/) enables complex data transformations for sophisticated dashboard visualizations.

From a cost optimization perspective, the serverless architecture ensures you only pay for actual usage. Web PubSub's consumption-based pricing starts at $0 for the free tier, while Function Apps charge only for execution time. Static Web Apps provides free hosting for the frontend, making this solution extremely cost-effective for development and small production workloads. For high-scale deployments, review the [Azure pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/) and consider reserved capacity options. The [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/) provides additional guidance on balancing cost with performance and reliability requirements.

> **Warning**: WebSocket connections consume bandwidth continuously. Monitor your Web PubSub metrics to understand usage patterns and configure appropriate connection limits for your subscription tier.

## Challenge

Extend this solution by implementing these enhancements:

1. Add Azure Active Directory authentication with role-based access control to restrict dashboard access and enable user-specific metric views
2. Implement Redis Cache for metric data to reduce Azure Monitor API calls and improve dashboard loading performance
3. Create custom visualization widgets using D3.js and enable drag-and-drop dashboard customization with layout persistence
4. Integrate Azure Logic Apps to trigger automated responses when specific metric thresholds are exceeded collaboratively
5. Build a mobile companion app using React Native that maintains WebSocket synchronization for on-the-go monitoring

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*