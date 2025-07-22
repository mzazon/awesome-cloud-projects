---
title: Proactive Resource Health Monitoring with Service Bus
id: f3a8d2c7
category: monitoring
difficulty: 200
subject: azure
services: Azure Resource Health, Azure Service Bus, Azure Logic Apps, Azure Monitor
estimated-time: 120 minutes
recipe-version: 1.0
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: null
passed-qa: null
tags: health monitoring, event-driven, messaging, proactive remediation, resource health, service bus
recipe-generator-version: 1.3
---

# Proactive Resource Health Monitoring with Service Bus

## Problem

Organizations struggle with reactive incident response when Azure resources experience health issues, leading to prolonged downtime and poor user experiences. Traditional monitoring solutions often miss critical resource health transitions, and manual remediation processes delay recovery times, resulting in SLA violations and decreased customer satisfaction.

## Solution

Build an intelligent proactive monitoring system that automatically detects Azure resource health changes using Azure Resource Health APIs and orchestrates automated remediation workflows through Azure Service Bus messaging patterns. This solution enables real-time health event processing, automated incident response, and seamless integration with existing microservices architectures for comprehensive application health management.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Azure Resources"
        VM[Virtual Machines]
        APP[App Services]
        SQL[SQL Databases]
        STORAGE[Storage Accounts]
    end
    
    subgraph "Health Monitoring"
        HEALTH[Azure Resource Health]
        MONITOR[Azure Monitor]
        ALERTS[Health Alerts]
    end
    
    subgraph "Event Processing"
        LOGIC[Logic Apps]
        SERVICEBUS[Service Bus]
        QUEUE[Health Events Queue]
        TOPIC[Remediation Topic]
    end
    
    subgraph "Remediation Services"
        HANDLER1[Auto-Scale Handler]
        HANDLER2[Restart Handler]
        HANDLER3[Failover Handler]
        WEBHOOK[Webhook Notifications]
    end
    
    VM --> HEALTH
    APP --> HEALTH
    SQL --> HEALTH
    STORAGE --> HEALTH
    
    HEALTH --> ALERTS
    ALERTS --> LOGIC
    MONITOR --> LOGIC
    
    LOGIC --> SERVICEBUS
    SERVICEBUS --> QUEUE
    SERVICEBUS --> TOPIC
    
    QUEUE --> HANDLER1
    TOPIC --> HANDLER2
    TOPIC --> HANDLER3
    TOPIC --> WEBHOOK
    
    style HEALTH fill:#FF6B6B
    style SERVICEBUS fill:#4ECDC4
    style LOGIC fill:#45B7D1
    style MONITOR fill:#96CEB4
```

## Prerequisites

1. Azure subscription with appropriate permissions for creating Resource Health alerts, Service Bus namespaces, and Logic Apps
2. Azure CLI v2.50.0 or higher installed and configured (or Azure CloudShell)
3. Understanding of Azure messaging patterns and event-driven architectures
4. Basic knowledge of Azure Resource Health concepts and service health monitoring
5. Estimated cost: $50-100/month for Service Bus, Logic Apps, and monitoring resources

> **Note**: This solution leverages Azure's native event-driven architecture patterns. Review the [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/) for additional guidance on building resilient monitoring systems.

## Preparation

```bash
# Set environment variables for Azure resources
export RESOURCE_GROUP="rg-health-monitoring-$(openssl rand -hex 3)"
export LOCATION="eastus"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)

# Service Bus configuration
export SERVICE_BUS_NAMESPACE="sb-health-monitoring-${RANDOM_SUFFIX}"
export HEALTH_QUEUE_NAME="health-events"
export REMEDIATION_TOPIC_NAME="remediation-actions"

# Logic Apps configuration
export LOGIC_APP_NAME="la-health-orchestrator-${RANDOM_SUFFIX}"
export CONSUMPTION_PLAN_NAME="plan-health-monitoring-${RANDOM_SUFFIX}"

# Monitoring configuration
export LOG_ANALYTICS_WORKSPACE="log-health-monitoring-${RANDOM_SUFFIX}"
export ACTION_GROUP_NAME="ag-health-alerts-${RANDOM_SUFFIX}"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION} \
    --tags purpose=health-monitoring environment=demo

echo "✅ Resource group created: ${RESOURCE_GROUP}"
```

## Steps

1. **Create Service Bus Namespace with Health Event Processing**:

   Azure Service Bus provides reliable, enterprise-grade messaging infrastructure that enables decoupled communication between health monitoring components and remediation services. The namespace serves as the central message broker for all health events, supporting both queue-based point-to-point messaging for specific handlers and topic-based publish-subscribe patterns for broadcast scenarios.

   ```bash
   # Create Service Bus namespace with premium tier for advanced features
   az servicebus namespace create \
       --name ${SERVICE_BUS_NAMESPACE} \
       --resource-group ${RESOURCE_GROUP} \
       --location ${LOCATION} \
       --sku Standard \
       --tags purpose=health-monitoring

   # Get Service Bus connection string for later use
   export SERVICE_BUS_CONNECTION=$(az servicebus namespace \
       authorization-rule keys list \
       --namespace-name ${SERVICE_BUS_NAMESPACE} \
       --resource-group ${RESOURCE_GROUP} \
       --name RootManageSharedAccessKey \
       --query primaryConnectionString --output tsv)

   echo "✅ Service Bus namespace created with connection string configured"
   ```

   The Service Bus namespace now provides the messaging backbone for your health monitoring system. This enterprise-grade messaging service ensures reliable delivery of health events even during high-load scenarios and supports advanced features like message deduplication, dead letter queues, and session-based processing.

2. **Configure Health Events Queue and Remediation Topic**:

   Message queues provide guaranteed delivery for critical health events, while topics enable fan-out messaging patterns for triggering multiple remediation actions simultaneously. This dual-pattern approach ensures both reliability and scalability for complex health monitoring scenarios.

   ```bash
   # Create queue for health events with duplicate detection
   az servicebus queue create \
       --namespace-name ${SERVICE_BUS_NAMESPACE} \
       --resource-group ${RESOURCE_GROUP} \
       --name ${HEALTH_QUEUE_NAME} \
       --max-size 2048 \
       --enable-duplicate-detection true \
       --duplicate-detection-history-time-window PT10M

   # Create topic for remediation actions
   az servicebus topic create \
       --namespace-name ${SERVICE_BUS_NAMESPACE} \
       --resource-group ${RESOURCE_GROUP} \
       --name ${REMEDIATION_TOPIC_NAME} \
       --max-size 2048 \
       --enable-duplicate-detection true

   # Create subscriptions for different remediation handlers
   az servicebus topic subscription create \
       --namespace-name ${SERVICE_BUS_NAMESPACE} \
       --resource-group ${RESOURCE_GROUP} \
       --topic-name ${REMEDIATION_TOPIC_NAME} \
       --name auto-scale-handler \
       --max-delivery-count 3

   az servicebus topic subscription create \
       --namespace-name ${SERVICE_BUS_NAMESPACE} \
       --resource-group ${RESOURCE_GROUP} \
       --topic-name ${REMEDIATION_TOPIC_NAME} \
       --name restart-handler \
       --max-delivery-count 3

   echo "✅ Service Bus messaging topology configured"
   ```

   The messaging topology is now established with dedicated pathways for health events and remediation actions. The duplicate detection feature prevents processing the same health event multiple times, while the subscription model enables specialized handlers to process only relevant remediation actions.

3. **Create Log Analytics Workspace for Monitoring**:

   Azure Monitor Log Analytics provides centralized logging and querying capabilities for health monitoring data. This workspace serves as the foundation for advanced analytics, alerting, and dashboard creation, enabling comprehensive visibility into resource health patterns and system performance.

   ```bash
   # Create Log Analytics workspace
   az monitor log-analytics workspace create \
       --workspace-name ${LOG_ANALYTICS_WORKSPACE} \
       --resource-group ${RESOURCE_GROUP} \
       --location ${LOCATION} \
       --tags purpose=health-monitoring

   # Get workspace ID for later configuration
   export WORKSPACE_ID=$(az monitor log-analytics workspace show \
       --workspace-name ${LOG_ANALYTICS_WORKSPACE} \
       --resource-group ${RESOURCE_GROUP} \
       --query customerId --output tsv)

   echo "✅ Log Analytics workspace created: ${LOG_ANALYTICS_WORKSPACE}"
   ```

   The Log Analytics workspace provides the analytics foundation for your health monitoring system, enabling complex queries, custom dashboards, and advanced correlation analysis across all health events and remediation actions.

4. **Deploy Logic Apps for Health Event Orchestration**:

   Azure Logic Apps serves as the orchestration engine that connects Resource Health events with Service Bus messaging patterns. This serverless workflow service automatically processes health alerts, enriches event data, and routes messages to appropriate remediation handlers based on configurable business rules.

   ```bash
   # Create Logic App with consumption plan
   az logic workflow create \
       --name ${LOGIC_APP_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --location ${LOCATION} \
       --definition '{
         "$schema": "https://schema.management.azure.com/schemas/2016-06-01/Microsoft.Logic.json",
         "contentVersion": "1.0.0.0",
         "triggers": {
           "When_a_resource_health_alert_is_fired": {
             "type": "request",
             "kind": "http",
             "inputs": {
               "schema": {
                 "type": "object",
                 "properties": {
                   "resourceId": {"type": "string"},
                   "status": {"type": "string"},
                   "eventTime": {"type": "string"},
                   "resourceType": {"type": "string"}
                 }
               }
             }
           }
         },
         "actions": {
           "Send_to_Health_Queue": {
             "type": "ServiceBusQueue",
             "inputs": {
               "host": {
                 "connection": {
                   "name": "@parameters($connections)[\"servicebus\"][\"connectionId\"]"
                 }
               },
               "method": "post",
               "path": "/@{encodeURIComponent(encodeURIComponent(\"'${HEALTH_QUEUE_NAME}'\"))}/messages",
               "body": {
                 "ContentData": "@base64(triggerBody())",
                 "ContentType": "application/json"
               }
             }
           },
           "Determine_Remediation_Action": {
             "type": "Switch",
             "expression": "@triggerBody()[\"status\"]",
             "cases": {
               "Unavailable": {
                 "case": "Unavailable",
                 "actions": {
                   "Send_to_Remediation_Topic": {
                     "type": "ServiceBusTopic",
                     "inputs": {
                       "host": {
                         "connection": {
                           "name": "@parameters($connections)[\"servicebus\"][\"connectionId\"]"
                         }
                       },
                       "method": "post",
                       "path": "/@{encodeURIComponent(encodeURIComponent(\"'${REMEDIATION_TOPIC_NAME}'\"))}/messages",
                       "body": {
                         "ContentData": "@base64(triggerBody())",
                         "ContentType": "application/json",
                         "Properties": {
                           "ActionType": "restart"
                         }
                       }
                     }
                   }
                 }
               },
               "Degraded": {
                 "case": "Degraded",
                 "actions": {
                   "Send_Scale_Action": {
                     "type": "ServiceBusTopic",
                     "inputs": {
                       "host": {
                         "connection": {
                           "name": "@parameters($connections)[\"servicebus\"][\"connectionId\"]"
                         }
                       },
                       "method": "post",
                       "path": "/@{encodeURIComponent(encodeURIComponent(\"'${REMEDIATION_TOPIC_NAME}'\"))}/messages",
                       "body": {
                         "ContentData": "@base64(triggerBody())",
                         "ContentType": "application/json",
                         "Properties": {
                           "ActionType": "scale"
                         }
                       }
                     }
                   }
                 }
               }
             }
           }
         }
       }'

   echo "✅ Logic Apps workflow created for health event orchestration"
   ```

   The Logic Apps workflow now provides intelligent event processing that automatically routes health events to appropriate remediation channels. This serverless orchestration ensures consistent processing of health events while maintaining flexibility for complex business rules and decision logic.

5. **Create Action Group for Resource Health Alerts**:

   Azure Action Groups provide the notification infrastructure that connects Resource Health events to your Logic Apps workflow. This component enables automated triggering of remediation workflows when resource health changes occur, ensuring immediate response to critical health events.

   ```bash
   # Create Action Group with Logic App webhook
   LOGIC_APP_TRIGGER_URL=$(az logic workflow show \
       --name ${LOGIC_APP_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --query "accessEndpoint" --output tsv)

   az monitor action-group create \
       --name ${ACTION_GROUP_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --short-name "HealthAlert" \
       --action webhook healthWebhook ${LOGIC_APP_TRIGGER_URL}

   echo "✅ Action Group created with Logic App integration"
   ```

   The Action Group establishes the critical link between Azure Resource Health events and your orchestration workflow, enabling automated response to health changes across your Azure environment.

6. **Configure Resource Health Alerts for Critical Resources**:

   Resource Health alerts provide proactive notification when Azure resources experience health issues. These alerts monitor specific resources or resource types and trigger automated remediation workflows through the configured Action Group, enabling immediate response to health degradation.

   ```bash
   # Create a sample VM to monitor (for demonstration)
   az vm create \
       --name "vm-health-demo-${RANDOM_SUFFIX}" \
       --resource-group ${RESOURCE_GROUP} \
       --image Ubuntu2204 \
       --admin-username azureuser \
       --generate-ssh-keys \
       --size Standard_B1s \
       --tags purpose=health-monitoring-demo

   # Get VM resource ID
   VM_RESOURCE_ID=$(az vm show \
       --name "vm-health-demo-${RANDOM_SUFFIX}" \
       --resource-group ${RESOURCE_GROUP} \
       --query id --output tsv)

   # Create Resource Health alert for the VM
   az monitor activity-log alert create \
       --name "vm-health-alert-${RANDOM_SUFFIX}" \
       --resource-group ${RESOURCE_GROUP} \
       --scopes ${VM_RESOURCE_ID} \
       --condition category=ResourceHealth \
       --action-groups ${ACTION_GROUP_NAME} \
       --description "Alert when VM health status changes"

   echo "✅ Resource Health alert configured for VM monitoring"
   ```

   The Resource Health alert system is now monitoring your critical resources and will automatically trigger remediation workflows when health issues are detected. This proactive approach ensures rapid response to resource health changes before they impact users.

7. **Deploy Sample Remediation Handlers**:

   Remediation handlers are specialized Logic Apps that process specific types of health events and execute appropriate recovery actions. These handlers subscribe to the remediation topic and implement business logic for different failure scenarios, such as auto-scaling, service restarts, or failover operations.

   ```bash
   # Create restart handler Logic App
   az logic workflow create \
       --name "la-restart-handler-${RANDOM_SUFFIX}" \
       --resource-group ${RESOURCE_GROUP} \
       --location ${LOCATION} \
       --definition '{
         "$schema": "https://schema.management.azure.com/schemas/2016-06-01/Microsoft.Logic.json",
         "contentVersion": "1.0.0.0",
         "triggers": {
           "When_a_restart_message_is_received": {
             "type": "ServiceBusSubscription",
             "inputs": {
               "host": {
                 "connection": {
                   "name": "@parameters($connections)[\"servicebus\"][\"connectionId\"]"
                 }
               },
               "method": "get",
               "path": "/@{encodeURIComponent(encodeURIComponent(\"'${REMEDIATION_TOPIC_NAME}'\"))}/subscriptions/@{encodeURIComponent(\"restart-handler\")}/messages/head",
               "queries": {
                 "subscriptionType": "Main"
               }
             }
           }
         },
         "actions": {
           "Log_Restart_Action": {
             "type": "Http",
             "inputs": {
               "method": "POST",
               "uri": "https://httpbin.org/post",
               "body": {
                 "action": "restart",
                 "resourceId": "@triggerBody()[\"resourceId\"]",
                 "timestamp": "@utcnow()"
               }
             }
           }
         }
       }'

   echo "✅ Restart handler Logic App deployed"
   ```

   The remediation handlers provide specialized processing for different types of health events, enabling targeted recovery actions based on the specific nature of each health issue. This modular approach ensures maintainable and scalable remediation logic.

8. **Create Monitoring Dashboard and Queries**:

   Azure Monitor dashboards provide comprehensive visibility into your health monitoring system's performance and effectiveness. Custom queries enable analysis of health event patterns, remediation success rates, and system performance metrics.

   ```bash
   # Create custom queries for health monitoring analytics
   cat > health_monitoring_queries.kql << 'EOF'
// Health Events Analysis
AzureActivity
| where CategoryValue == "ResourceHealth"
| summarize count() by ResourceId, Status, bin(TimeGenerated, 1h)
| order by TimeGenerated desc

// Remediation Actions Tracking
AzureActivity
| where OperationNameValue contains "Logic"
| where ResourceProvider == "Microsoft.Logic"
| summarize count() by bin(TimeGenerated, 1h), OperationNameValue
| order by TimeGenerated desc

// Service Bus Message Processing
ServiceBusLogs
| where Category == "OperationalLogs"
| summarize count() by bin(TimeGenerated, 15m), Status
| order by TimeGenerated desc
EOF

   echo "✅ Monitoring queries created for health analytics"
   ```

   The monitoring dashboard and queries provide essential visibility into your health monitoring system's operation, enabling performance optimization and troubleshooting of remediation workflows.

## Validation & Testing

1. **Verify Service Bus Infrastructure**:

   ```bash
   # Check Service Bus namespace status
   az servicebus namespace show \
       --name ${SERVICE_BUS_NAMESPACE} \
       --resource-group ${RESOURCE_GROUP} \
       --query "{Name:name,Status:status,Location:location}" \
       --output table
   
   # Verify queue and topic configuration
   az servicebus queue show \
       --namespace-name ${SERVICE_BUS_NAMESPACE} \
       --resource-group ${RESOURCE_GROUP} \
       --name ${HEALTH_QUEUE_NAME} \
       --query "{Name:name,Status:status,MessageCount:messageCount}" \
       --output table
   ```

   Expected output: Service Bus components should show "Active" status with proper configuration.

2. **Test Logic Apps Workflow Execution**:

   ```bash
   # Check Logic Apps workflow status
   az logic workflow show \
       --name ${LOGIC_APP_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --query "{Name:name,State:state,Location:location}" \
       --output table
   
   # Verify workflow run history
   az logic workflow run list \
       --workflow-name ${LOGIC_APP_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --query "[].{RunId:name,Status:status,StartTime:startTime}" \
       --output table
   ```

   Expected output: Logic Apps should show "Enabled" state with successful run history.

3. **Simulate Health Event Processing**:

   ```bash
   # Send test health event to Logic Apps trigger
   curl -X POST \
       "${LOGIC_APP_TRIGGER_URL}" \
       -H "Content-Type: application/json" \
       -d '{
         "resourceId": "/subscriptions/'${SUBSCRIPTION_ID}'/resourceGroups/'${RESOURCE_GROUP}'/providers/Microsoft.Compute/virtualMachines/test-vm",
         "status": "Unavailable",
         "eventTime": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'",
         "resourceType": "Microsoft.Compute/virtualMachines"
       }'
   
   echo "✅ Test health event sent to Logic Apps"
   ```

4. **Monitor Service Bus Message Processing**:

   ```bash
   # Check message counts in queue and topic
   az servicebus queue show \
       --namespace-name ${SERVICE_BUS_NAMESPACE} \
       --resource-group ${RESOURCE_GROUP} \
       --name ${HEALTH_QUEUE_NAME} \
       --query "messageCount"
   
   az servicebus topic show \
       --namespace-name ${SERVICE_BUS_NAMESPACE} \
       --resource-group ${RESOURCE_GROUP} \
       --name ${REMEDIATION_TOPIC_NAME} \
       --query "messageCount"
   ```

## Cleanup

1. **Remove Logic Apps and Workflows**:

   ```bash
   # Delete Logic Apps workflows
   az logic workflow delete \
       --name ${LOGIC_APP_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --yes
   
   az logic workflow delete \
       --name "la-restart-handler-${RANDOM_SUFFIX}" \
       --resource-group ${RESOURCE_GROUP} \
       --yes
   
   echo "✅ Logic Apps workflows deleted"
   ```

2. **Clean Up Service Bus Resources**:

   ```bash
   # Delete Service Bus namespace and all contained resources
   az servicebus namespace delete \
       --name ${SERVICE_BUS_NAMESPACE} \
       --resource-group ${RESOURCE_GROUP}
   
   echo "✅ Service Bus namespace deleted"
   ```

3. **Remove Monitoring and VM Resources**:

   ```bash
   # Delete VM created for demonstration
   az vm delete \
       --name "vm-health-demo-${RANDOM_SUFFIX}" \
       --resource-group ${RESOURCE_GROUP} \
       --yes
   
   # Delete Log Analytics workspace
   az monitor log-analytics workspace delete \
       --workspace-name ${LOG_ANALYTICS_WORKSPACE} \
       --resource-group ${RESOURCE_GROUP} \
       --yes
   
   echo "✅ Monitoring and VM resources deleted"
   ```

4. **Delete Resource Group**:

   ```bash
   # Delete resource group and all remaining resources
   az group delete \
       --name ${RESOURCE_GROUP} \
       --yes \
       --no-wait
   
   echo "✅ Resource group deletion initiated: ${RESOURCE_GROUP}"
   echo "Note: Deletion may take several minutes to complete"
   ```

## Discussion

This proactive health monitoring solution demonstrates the power of Azure's event-driven architecture for building resilient, self-healing systems. By combining Azure Resource Health with Service Bus messaging patterns, organizations can achieve sub-minute response times to resource health issues while maintaining loose coupling between monitoring and remediation components. The solution follows [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/) principles, particularly emphasizing reliability and operational excellence through automated incident response.

The Service Bus integration provides enterprise-grade messaging reliability with features like duplicate detection, dead letter queues, and guaranteed message delivery. This ensures that critical health events are never lost, even during high-load scenarios or temporary service disruptions. The topic-based publish-subscribe pattern enables flexible scaling of remediation handlers without requiring changes to the core orchestration logic. For comprehensive guidance on Service Bus messaging patterns, see the [Service Bus documentation](https://docs.microsoft.com/en-us/azure/service-bus-messaging/) and [messaging best practices](https://docs.microsoft.com/en-us/azure/service-bus-messaging/service-bus-performance-best-practices).

Logic Apps serves as the intelligent orchestration layer that bridges Resource Health events with business-specific remediation workflows. The serverless nature of Logic Apps eliminates infrastructure management overhead while providing rich integration capabilities with over 400 built-in connectors. This enables seamless integration with existing tools, notification systems, and automation platforms. The visual workflow designer simplifies maintenance and enables non-technical stakeholders to understand and modify remediation logic. For detailed Logic Apps guidance, review the [Logic Apps documentation](https://docs.microsoft.com/en-us/azure/logic-apps/) and [workflow best practices](https://docs.microsoft.com/en-us/azure/logic-apps/logic-apps-workflow-definition-language-functions-reference).

From a cost perspective, this solution leverages consumption-based pricing models that scale automatically with actual usage. Service Bus Standard tier provides sufficient capabilities for most scenarios while maintaining cost-effectiveness. Logic Apps consumption plans ensure you only pay for actual executions, making this solution financially viable for organizations of all sizes. The modular architecture enables incremental deployment and scaling based on specific business needs and resource criticality. For cost optimization strategies, see the [Azure cost management documentation](https://docs.microsoft.com/en-us/azure/cost-management-billing/) and [Service Bus pricing guidance](https://docs.microsoft.com/en-us/azure/service-bus-messaging/service-bus-pricing-billing).

> **Tip**: Enable Service Bus message sessions for scenarios requiring ordered processing of health events from the same resource. This ensures remediation actions are processed in the correct sequence and prevents conflicting operations. Configure appropriate message TTL values to prevent stale health events from triggering unnecessary remediation actions.

## Challenge

Extend this solution by implementing these enhancements:

1. **Multi-Region Health Monitoring**: Deploy the solution across multiple Azure regions with cross-region failover capabilities and centralized health event aggregation for global resource monitoring.

2. **ML-Powered Predictive Health Analytics**: Integrate Azure Machine Learning to analyze historical health patterns and predict potential resource failures before they occur, enabling proactive maintenance scheduling.

3. **Custom Remediation Action Library**: Build a comprehensive library of remediation handlers for different Azure services (AKS, App Services, SQL Database) with service-specific recovery logic and rollback capabilities.

4. **Integration with External Systems**: Connect the health monitoring system to external incident management platforms (ServiceNow, Jira) and communication tools (Teams, Slack) for comprehensive operational workflows.

5. **Advanced Analytics and Reporting**: Implement Power BI dashboards with custom KPIs for health monitoring effectiveness, MTTR analysis, and SLA compliance tracking with automated executive reporting.

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*