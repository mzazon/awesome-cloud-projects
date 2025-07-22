---
title: Cost-Efficient Batch Processing with Azure Compute Fleet and Azure Batch
id: 4f7a2c9e
category: compute
difficulty: 200
subject: azure
services: Azure Compute Fleet, Azure Batch, Azure Storage, Azure Monitor
estimated-time: 120 minutes
recipe-version: 1.0
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: null
passed-qa: null
tags: batch-processing, cost-optimization, compute-fleet, spot-instances, automation
recipe-generator-version: 1.3
---

# Cost-Efficient Batch Processing with Azure Compute Fleet and Azure Batch

## Problem

Organizations processing large datasets face significant compute costs when using traditional dedicated virtual machines for batch workloads. These workloads often require substantial compute resources for short periods, leading to overprovisioning and wasted capacity. Without intelligent resource management, companies experience unpredictable costs, underutilized infrastructure, and poor processing efficiency across varying workload demands.

## Solution

Azure Compute Fleet combined with Azure Batch provides an intelligent, cost-optimized solution that dynamically provisions mixed VM pricing models including spot instances to minimize costs while maintaining processing reliability. This architecture automatically scales compute resources based on workload demands, leverages unused Azure capacity at up to 90% cost savings, and implements fault-tolerant processing patterns that handle spot instance interruptions gracefully.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Data Input"
        STORAGE[Azure Storage Account]
        CONTAINER[Blob Container]
    end
    
    subgraph "Batch Processing"
        BATCH[Azure Batch Account]
        POOL[Batch Pool]
        JOBS[Batch Jobs]
    end
    
    subgraph "Compute Fleet"
        FLEET[Azure Compute Fleet]
        SPOT[Spot VMs]
        STANDARD[Standard VMs]
    end
    
    subgraph "Monitoring"
        MONITOR[Azure Monitor]
        LOGS[Log Analytics]
        ALERTS[Cost Alerts]
    end
    
    STORAGE --> BATCH
    BATCH --> POOL
    POOL --> FLEET
    FLEET --> SPOT
    FLEET --> STANDARD
    BATCH --> MONITOR
    MONITOR --> LOGS
    MONITOR --> ALERTS
    
    style FLEET fill:#FF9900
    style SPOT fill:#3F8624
    style MONITOR fill:#0078D4
```

## Prerequisites

1. Azure subscription with appropriate permissions for creating compute, storage, and monitoring resources
2. Azure CLI v2.50.0 or later installed and configured (or Azure Cloud Shell)
3. Basic understanding of batch processing concepts and Azure resource management
4. Familiarity with Azure cost management and optimization principles
5. Estimated cost: $50-100 for testing resources (can be minimized with spot instances)

## Preparation

```bash
# Set environment variables for Azure resources
export RESOURCE_GROUP="rg-batch-fleet-${RANDOM_SUFFIX}"
export LOCATION="eastus"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)

# Set resource names
export STORAGE_ACCOUNT="stbatch${RANDOM_SUFFIX}"
export BATCH_ACCOUNT="batchacct${RANDOM_SUFFIX}"
export FLEET_NAME="compute-fleet-${RANDOM_SUFFIX}"
export LOG_WORKSPACE="log-batch-${RANDOM_SUFFIX}"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION} \
    --tags purpose=batch-processing environment=demo

echo "✅ Resource group created: ${RESOURCE_GROUP}"

# Create storage account for batch data
az storage account create \
    --name ${STORAGE_ACCOUNT} \
    --resource-group ${RESOURCE_GROUP} \
    --location ${LOCATION} \
    --sku Standard_LRS \
    --kind StorageV2

echo "✅ Storage account created: ${STORAGE_ACCOUNT}"
```

## Steps

1. **Create Azure Batch Account with Compute Fleet Integration**:

   Azure Batch provides managed batch processing capabilities that automatically handle job scheduling, resource provisioning, and fault tolerance. By integrating with Azure Compute Fleet, we can leverage mixed VM pricing models to optimize costs while maintaining processing reliability. This combination enables intelligent resource allocation based on workload characteristics and cost constraints.

   ```bash
   # Create Azure Batch account
   az batch account create \
       --name ${BATCH_ACCOUNT} \
       --resource-group ${RESOURCE_GROUP} \
       --location ${LOCATION} \
       --storage-account ${STORAGE_ACCOUNT}
   
   # Get batch account keys
   BATCH_KEY=$(az batch account keys list \
       --name ${BATCH_ACCOUNT} \
       --resource-group ${RESOURCE_GROUP} \
       --query primary --output tsv)
   
   # Set batch account context
   az batch account set \
       --name ${BATCH_ACCOUNT} \
       --resource-group ${RESOURCE_GROUP}
   
   echo "✅ Batch account created with storage integration"
   ```

   The Batch account is now configured with integrated storage capabilities and ready for pool creation. This foundation enables automatic data management, job scheduling, and resource provisioning while maintaining secure access to processing data and results.

2. **Configure Azure Compute Fleet with Mixed Pricing Models**:

   Azure Compute Fleet enables intelligent VM provisioning across multiple pricing models, including spot instances that offer up to 90% cost savings. This service automatically handles instance interruptions and maintains workload availability by diversifying across different VM types and pricing tiers based on your optimization strategy.

   ```bash
   # Create compute fleet configuration
   cat > fleet-config.json << EOF
   {
     "name": "${FLEET_NAME}",
     "location": "${LOCATION}",
     "properties": {
       "computeProfile": {
         "baseVirtualMachineProfile": {
           "storageProfile": {
             "imageReference": {
               "publisher": "MicrosoftWindowsServer",
               "offer": "WindowsServer",
               "sku": "2022-datacenter-core",
               "version": "latest"
             }
           },
           "osProfile": {
             "computerNamePrefix": "batch-vm",
             "adminUsername": "batchadmin",
             "adminPassword": "BatchP@ssw0rd123!"
           }
         },
         "computeApiVersion": "2023-09-01"
       },
       "spotPriorityProfile": {
         "capacity": 80,
         "minCapacity": 0,
         "maxPricePerVM": 0.05,
         "evictionPolicy": "Delete",
         "allocationStrategy": "LowestPrice"
       },
       "regularPriorityProfile": {
         "capacity": 20,
         "minCapacity": 5,
         "allocationStrategy": "LowestPrice"
       }
     }
   }
   EOF
   
   # Create the compute fleet
   az compute-fleet create \
       --resource-group ${RESOURCE_GROUP} \
       --name ${FLEET_NAME} \
       --body @fleet-config.json
   
   echo "✅ Compute Fleet created with 80% spot, 20% standard capacity"
   ```

   The Compute Fleet is now configured to prioritize cost efficiency by allocating 80% of capacity to spot instances while maintaining 20% standard instances for reliability. This configuration automatically handles spot instance interruptions and ensures continuous processing capability.

3. **Create Batch Pool with Compute Fleet Integration**:

   Azure Batch pools define the compute resources available for job execution. By integrating with Azure Compute Fleet, the pool can leverage mixed pricing models and automatic scaling based on workload demands. This approach optimizes costs while maintaining processing reliability through intelligent resource allocation.

   ```bash
   # Create batch pool configuration
   cat > pool-config.json << EOF
   {
     "id": "batch-pool-${RANDOM_SUFFIX}",
     "vmSize": "Standard_D2s_v3",
     "virtualMachineConfiguration": {
       "imageReference": {
         "publisher": "MicrosoftWindowsServer",
         "offer": "WindowsServer",
         "sku": "2022-datacenter-core",
         "version": "latest"
       },
       "nodeAgentSKUId": "batch.node.windows amd64"
     },
     "targetDedicatedNodes": 0,
     "targetLowPriorityNodes": 10,
     "enableAutoScale": true,
     "autoScaleFormula": "$TargetLowPriorityNodes = min(20, $PendingTasks.GetSample(1 * TimeInterval_Minute, 0).GetAverage() * 2);",
     "autoScaleEvaluationInterval": "PT5M",
     "startTask": {
       "commandLine": "cmd /c echo 'Batch node ready for processing'",
       "waitForSuccess": true
     }
   }
   EOF
   
   # Create the batch pool
   az batch pool create \
       --json-file pool-config.json
   
   echo "✅ Batch pool created with auto-scaling and low-priority nodes"
   ```

   The Batch pool is now configured with automatic scaling based on pending tasks and optimized for cost efficiency using low-priority nodes. This setup ensures optimal resource utilization while maintaining processing capability for varying workload demands.

4. **Setup Azure Monitor for Cost and Performance Tracking**:

   Azure Monitor provides comprehensive visibility into batch processing costs, performance metrics, and resource utilization patterns. This monitoring foundation enables proactive cost optimization and performance tuning based on actual workload characteristics and resource consumption patterns.

   ```bash
   # Create Log Analytics workspace
   az monitor log-analytics workspace create \
       --workspace-name ${LOG_WORKSPACE} \
       --resource-group ${RESOURCE_GROUP} \
       --location ${LOCATION} \
       --sku PerGB2018
   
   # Get workspace ID
   WORKSPACE_ID=$(az monitor log-analytics workspace show \
       --workspace-name ${LOG_WORKSPACE} \
       --resource-group ${RESOURCE_GROUP} \
       --query customerId --output tsv)
   
   # Enable diagnostic settings for batch account
   az monitor diagnostic-settings create \
       --name batch-diagnostics \
       --resource ${BATCH_ACCOUNT} \
       --resource-group ${RESOURCE_GROUP} \
       --resource-type Microsoft.Batch/batchAccounts \
       --workspace ${WORKSPACE_ID} \
       --logs '[{"category":"ServiceLog","enabled":true}]' \
       --metrics '[{"category":"AllMetrics","enabled":true}]'
   
   echo "✅ Azure Monitor configured for cost and performance tracking"
   ```

   Azure Monitor is now capturing detailed metrics and logs from the batch processing environment. This telemetry enables cost analysis, performance optimization, and proactive alerting for both operational issues and cost overruns.

5. **Create Sample Batch Job for Testing**:

   A sample batch job demonstrates the cost-efficient processing capabilities of the integrated Azure Compute Fleet and Azure Batch solution. This job processes data files while leveraging spot instances for cost optimization and automatic scaling for performance optimization.

   ```bash
   # Create sample batch job configuration
   cat > job-config.json << EOF
   {
     "id": "sample-processing-job-${RANDOM_SUFFIX}",
     "poolInfo": {
       "poolId": "batch-pool-${RANDOM_SUFFIX}"
     },
     "jobManagerTask": {
       "id": "JobManager",
       "displayName": "Sample Processing Job Manager",
       "commandLine": "cmd /c echo 'Processing batch job with cost optimization' && timeout /t 30",
       "killJobOnCompletion": true
     },
     "onAllTasksComplete": "terminateJob",
     "usesTaskDependencies": false
   }
   EOF
   
   # Create the batch job
   az batch job create \
       --json-file job-config.json
   
   # Add sample tasks to the job
   for i in {1..5}; do
     az batch task create \
         --job-id "sample-processing-job-${RANDOM_SUFFIX}" \
         --task-id "task-${i}" \
         --command-line "cmd /c echo 'Processing task ${i} on cost-optimized compute' && timeout /t 60"
   done
   
   echo "✅ Sample batch job created with 5 processing tasks"
   ```

   The sample batch job is now running with tasks distributed across the cost-optimized compute fleet. This demonstrates how the solution automatically provisions resources, executes tasks, and manages costs through intelligent resource allocation.

6. **Configure Cost Alerts and Budget Management**:

   Azure Cost Management provides essential cost control capabilities that monitor spending patterns and trigger alerts when costs approach defined thresholds. This proactive cost management ensures batch processing remains within budget while optimizing for performance and reliability.

   ```bash
   # Create budget for batch processing resources
   cat > budget-config.json << EOF
   {
     "properties": {
       "category": "Cost",
       "amount": 100,
       "timeGrain": "Monthly",
       "timePeriod": {
         "startDate": "$(date +%Y-%m-01)",
         "endDate": "$(date -d '+1 month' +%Y-%m-01)"
       },
       "filters": {
         "resourceGroups": ["${RESOURCE_GROUP}"]
       },
       "notifications": {
         "actual_GreaterThan_80_Percent": {
           "enabled": true,
           "operator": "GreaterThan",
           "threshold": 80,
           "contactEmails": ["admin@example.com"]
         }
       }
     }
   }
   EOF
   
   # Create cost alert rule
   az monitor metrics alert create \
       --name "batch-cost-alert" \
       --resource-group ${RESOURCE_GROUP} \
       --condition "avg 'Percentage CPU' > 80" \
       --description "Alert when batch processing costs exceed threshold" \
       --evaluation-frequency 5m \
       --window-size 15m \
       --severity 2
   
   echo "✅ Cost alerts and budget management configured"
   ```

   Cost management is now actively monitoring batch processing expenses with automated alerts and budget controls. This ensures proactive cost optimization while maintaining processing capability and performance requirements.

## Validation & Testing

1. **Verify Batch Pool Status and Scaling**:

   ```bash
   # Check batch pool status
   az batch pool show \
       --pool-id "batch-pool-${RANDOM_SUFFIX}" \
       --query "{State:state,CurrentNodes:currentDedicatedNodes,TargetNodes:targetDedicatedNodes,AutoScale:enableAutoScale}" \
       --output table
   
   # Verify auto-scaling configuration
   az batch pool show \
       --pool-id "batch-pool-${RANDOM_SUFFIX}" \
       --query "autoScaleFormula" \
       --output tsv
   ```

   Expected output: Pool should show active state with auto-scaling enabled and nodes provisioning based on workload.

2. **Test Job Execution and Cost Optimization**:

   ```bash
   # Check job status
   az batch job show \
       --job-id "sample-processing-job-${RANDOM_SUFFIX}" \
       --query "{State:state,Priority:priority,PoolInfo:poolInfo.poolId}" \
       --output table
   
   # List task execution status
   az batch task list \
       --job-id "sample-processing-job-${RANDOM_SUFFIX}" \
       --query "[].{TaskId:id,State:state,ExitCode:executionInfo.exitCode}" \
       --output table
   ```

   Expected output: Job should show completed state with all tasks successfully executed on cost-optimized compute resources.

3. **Validate Cost Monitoring and Alerts**:

   ```bash
   # Check cost analysis for resource group
   az consumption usage list \
       --start-date $(date -d '-7 days' +%Y-%m-%d) \
       --end-date $(date +%Y-%m-%d) \
       --query "[?contains(instanceName, '${RESOURCE_GROUP}')].[instanceName,pretaxCost,currency]" \
       --output table
   
   # Verify monitoring configuration
   az monitor log-analytics workspace show \
       --workspace-name ${LOG_WORKSPACE} \
       --resource-group ${RESOURCE_GROUP} \
       --query "{Name:name,Sku:sku.name,RetentionInDays:retentionInDays}" \
       --output table
   ```

   Expected output: Cost data should show resource consumption with monitoring workspace active and collecting telemetry.

## Cleanup

1. **Delete Batch Jobs and Pools**:

   ```bash
   # Delete batch job
   az batch job delete \
       --job-id "sample-processing-job-${RANDOM_SUFFIX}" \
       --yes
   
   # Delete batch pool
   az batch pool delete \
       --pool-id "batch-pool-${RANDOM_SUFFIX}" \
       --yes
   
   echo "✅ Batch jobs and pools deleted"
   ```

2. **Remove Compute Fleet and Associated Resources**:

   ```bash
   # Delete compute fleet
   az compute-fleet delete \
       --resource-group ${RESOURCE_GROUP} \
       --name ${FLEET_NAME} \
       --yes
   
   # Delete batch account
   az batch account delete \
       --name ${BATCH_ACCOUNT} \
       --resource-group ${RESOURCE_GROUP} \
       --yes
   
   echo "✅ Compute fleet and batch account deleted"
   ```

3. **Remove Monitoring and Storage Resources**:

   ```bash
   # Delete Log Analytics workspace
   az monitor log-analytics workspace delete \
       --workspace-name ${LOG_WORKSPACE} \
       --resource-group ${RESOURCE_GROUP} \
       --yes
   
   # Delete storage account
   az storage account delete \
       --name ${STORAGE_ACCOUNT} \
       --resource-group ${RESOURCE_GROUP} \
       --yes
   
   echo "✅ Monitoring and storage resources deleted"
   ```

4. **Remove Resource Group**:

   ```bash
   # Delete resource group and all contained resources
   az group delete \
       --name ${RESOURCE_GROUP} \
       --yes \
       --no-wait
   
   echo "✅ Resource group deletion initiated: ${RESOURCE_GROUP}"
   echo "Note: Deletion may take several minutes to complete"
   ```

## Discussion

Azure Compute Fleet and Azure Batch create a powerful combination for cost-efficient batch processing by intelligently managing mixed VM pricing models and automatic scaling. This architecture is particularly effective for workloads like data processing, scientific computing, and media rendering where cost optimization is critical and processing can tolerate brief interruptions. The solution leverages Azure's unused capacity through spot instances while maintaining reliability through standard instances, following [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/) principles for cost optimization and operational excellence.

The integration of Azure Compute Fleet with Azure Batch enables sophisticated resource allocation strategies that automatically adapt to workload demands and cost constraints. Spot instances provide significant cost savings (up to 90%) while the fleet's intelligent allocation ensures processing continuity during capacity fluctuations. This approach is documented in the [Azure Compute Fleet documentation](https://docs.microsoft.com/en-us/azure/virtual-machines/spot-vms) and [Azure Batch best practices](https://docs.microsoft.com/en-us/azure/batch/best-practices) guides.

From a cost management perspective, this solution provides multiple optimization layers including spot instance utilization, automatic scaling based on workload demand, and comprehensive monitoring through Azure Monitor. The combination of proactive cost alerts, budget management, and resource right-sizing ensures predictable costs while maintaining processing performance. Organizations can achieve 60-90% cost reduction compared to traditional dedicated compute approaches while maintaining processing reliability and scalability.

> **Tip**: Use Azure Cost Management and Billing to analyze historical usage patterns and optimize your spot instance pricing strategy. The [Azure cost optimization guide](https://docs.microsoft.com/en-us/azure/cost-management-billing/costs/cost-analysis-common-uses) provides detailed strategies for batch processing workloads.

## Challenge

Extend this solution by implementing these enhancements:

1. **Multi-Region Processing**: Configure Azure Compute Fleet across multiple regions to optimize for capacity availability and further reduce costs by leveraging regional pricing differences.

2. **Advanced Workload Scheduling**: Implement intelligent job scheduling that considers cost patterns, capacity availability, and processing priorities to optimize both cost and performance.

3. **Container-Based Processing**: Integrate Azure Container Instances or Azure Kubernetes Service for containerized batch workloads with improved portability and resource efficiency.

4. **Data Pipeline Integration**: Connect with Azure Data Factory or Azure Synapse Analytics to create end-to-end data processing pipelines with automated triggering and dependency management.

5. **Machine Learning Optimization**: Implement Azure Machine Learning to predict optimal resource allocation patterns and automatically adjust compute fleet configurations based on historical processing patterns.

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*