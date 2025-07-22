# Infrastructure as Code for Microservices Choreography with Service Bus and Observability

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Microservices Choreography with Service Bus and Observability".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (Azure Resource Manager templates)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.60.0 or later)
- Azure subscription with appropriate permissions for resource creation
- Understanding of microservices architecture and event-driven design patterns
- Basic knowledge of Azure Container Apps, Azure Functions, and Azure Service Bus
- Estimated cost: $50-100 per month for development/testing environment

## Quick Start

### Using Bicep

```bash
# Navigate to the bicep directory
cd bicep/

# Create resource group
az group create --name rg-microservices-choreography --location eastus

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-microservices-choreography \
    --template-file main.bicep \
    --parameters parameters.json

# Get deployment outputs
az deployment group show \
    --resource-group rg-microservices-choreography \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your values
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts to configure environment variables
```

## Architecture Overview

This infrastructure deploys a complete microservices choreography solution featuring:

### Core Components

- **Azure Service Bus Premium**: High-performance messaging backbone with dedicated messaging units
- **Azure Container Apps**: Serverless container hosting for Order and Inventory services
- **Azure Functions**: Event-driven serverless compute for Payment and Shipping services
- **Application Insights**: Distributed tracing and performance monitoring
- **Azure Monitor Workbooks**: Custom dashboards for observability

### Event-Driven Architecture

The solution implements the choreography pattern where services communicate through events:

1. **Order Service** (Container App) - Initiates workflows by publishing order events
2. **Inventory Service** (Container App) - Responds to order events, publishes inventory events
3. **Payment Service** (Function App) - Processes payment events, publishes payment confirmations
4. **Shipping Service** (Function App) - Handles shipping after successful payment and inventory allocation

### Observability Features

- **Distributed Tracing**: End-to-end transaction correlation across all services
- **Performance Monitoring**: Real-time metrics and alerting
- **Custom Dashboards**: Azure Monitor Workbooks for visualizing choreography workflows
- **Message Filtering**: Advanced Service Bus filtering for complex routing patterns

## Configuration

### Environment Variables

The following environment variables are used across all deployment methods:

```bash
# Core Configuration
RESOURCE_GROUP="rg-microservices-choreography"
LOCATION="eastus"
ENVIRONMENT="dev"

# Service Bus Configuration
NAMESPACE_NAME="sb-choreography-${RANDOM_SUFFIX}"
SERVICE_BUS_SKU="Premium"
MESSAGING_UNITS="1"

# Container Apps Configuration
CONTAINER_ENV_NAME="cae-choreography-${RANDOM_SUFFIX}"
MIN_REPLICAS="1"
MAX_REPLICAS="10"

# Monitoring Configuration
WORKSPACE_NAME="log-choreography-${RANDOM_SUFFIX}"
APPINSIGHTS_NAME="ai-choreography-${RANDOM_SUFFIX}"
```

### Customization Options

#### Bicep Parameters

Edit `parameters.json` to customize:

```json
{
  "location": {
    "value": "eastus"
  },
  "environment": {
    "value": "dev"
  },
  "serviceBusSkuName": {
    "value": "Premium"
  },
  "containerAppsMaxReplicas": {
    "value": 10
  }
}
```

#### Terraform Variables

Edit `terraform.tfvars` to customize:

```hcl
location = "East US"
environment = "dev"
service_bus_sku = "Premium"
container_apps_max_replicas = 10
enable_monitoring = true
```

## Deployment Details

### Resource Groups

All resources are deployed into a single resource group for simplified management:

- **Primary Resource Group**: Contains all infrastructure components
- **Managed Resource Groups**: Automatically created by Container Apps Environment

### Networking

- **Container Apps Environment**: Provides internal networking for microservices
- **Service Bus Premium**: Dedicated messaging units with VNet integration capabilities
- **Function Apps**: Consumption plan with automatic scaling

### Security

- **Managed Identity**: All services use managed identity for authentication
- **Role-Based Access Control**: Least privilege access to Service Bus and monitoring resources
- **Network Security**: Internal communication through Container Apps Environment
- **Secret Management**: Connection strings managed through Azure Key Vault integration

## Monitoring and Observability

### Application Insights Integration

All services automatically send telemetry to Application Insights:

- **Request Tracing**: HTTP requests and responses
- **Dependency Tracking**: Service Bus message processing
- **Exception Monitoring**: Automatic error capture and alerting
- **Performance Counters**: System and application metrics

### Azure Monitor Workbooks

Custom workbooks provide:

- **Transaction Flow Visualization**: End-to-end choreography workflows
- **Performance Dashboards**: Service response times and throughput
- **Error Analysis**: Failed transactions and retry patterns
- **Capacity Planning**: Resource utilization and scaling metrics

### Distributed Tracing

Correlation IDs automatically track:

- **Cross-Service Transactions**: Complete business process flows
- **Message Processing**: Service Bus message correlation
- **Performance Bottlenecks**: Slow components in the choreography
- **Failure Analysis**: Error propagation across services

## Validation and Testing

### Health Checks

Each deployment includes health check endpoints:

```bash
# Test Order Service (Container App)
curl -X GET "https://${ORDER_SERVICE_URL}/api/health"

# Test Function Apps
az functionapp show --name payment-service-${RANDOM_SUFFIX} --resource-group ${RESOURCE_GROUP}
az functionapp show --name shipping-service-${RANDOM_SUFFIX} --resource-group ${RESOURCE_GROUP}
```

### Message Flow Testing

Test the choreography workflow:

```bash
# Send test order event
az servicebus topic message send \
    --topic-name order-events \
    --namespace-name ${NAMESPACE_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --body '{"orderId":"test-001","customerId":"customer-123","amount":99.99,"priority":"High"}'

# Monitor Application Insights for distributed traces
```

### Performance Validation

Verify system performance:

```bash
# Check Service Bus metrics
az monitor metrics list \
    --resource "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ServiceBus/namespaces/${NAMESPACE_NAME}" \
    --metric "IncomingMessages,OutgoingMessages"

# Check Container Apps scaling
az containerapp list --resource-group ${RESOURCE_GROUP} --query "[].{Name:name,Replicas:properties.template.scale}"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name rg-microservices-choreography --yes --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Remove Terraform state files
rm -rf .terraform/
rm terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run the destruction script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Troubleshooting

### Common Issues

1. **Service Bus Premium Quota**: Ensure your subscription has quota for Premium messaging units
2. **Container Apps Scaling**: Verify Container Apps Environment has sufficient capacity
3. **Function App Cold Start**: Consider using Premium plans for consistent performance
4. **Monitoring Data Delay**: Application Insights data may take 2-3 minutes to appear

### Diagnostic Commands

```bash
# Check deployment status
az deployment group show --resource-group ${RESOURCE_GROUP} --name main

# Verify Service Bus connectivity
az servicebus namespace authorization-rule keys list \
    --resource-group ${RESOURCE_GROUP} \
    --namespace-name ${NAMESPACE_NAME} \
    --name RootManageSharedAccessKey

# Monitor Application Insights
az monitor app-insights query \
    --app ${APPINSIGHTS_NAME} \
    --analytics-query "requests | where timestamp > ago(1h) | summarize count() by cloud_RoleName"
```

### Log Analysis

Access logs for troubleshooting:

```bash
# Container Apps logs
az containerapp logs show --name order-service --resource-group ${RESOURCE_GROUP}

# Function App logs
az functionapp logs tail --name payment-service-${RANDOM_SUFFIX} --resource-group ${RESOURCE_GROUP}

# Service Bus metrics
az monitor metrics list \
    --resource "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ServiceBus/namespaces/${NAMESPACE_NAME}" \
    --metric "ActiveMessages,DeadLetterMessages"
```

## Cost Optimization

### Resource Sizing

- **Service Bus Premium**: Start with 1 messaging unit, scale based on throughput requirements
- **Container Apps**: Configure appropriate min/max replicas based on expected load
- **Function Apps**: Use Consumption plan for event-driven workloads
- **Application Insights**: Configure sampling to manage ingestion costs

### Monitoring Costs

```bash
# Check current month costs
az consumption usage list \
    --start-date $(date -d "$(date +%Y-%m-01)" +%Y-%m-%d) \
    --end-date $(date +%Y-%m-%d) \
    --query "[?contains(instanceName, 'choreography')]"
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service documentation for the specific components
3. Verify Azure CLI and tool versions are current
4. Consult Azure support for service-specific issues

## Next Steps

After successful deployment, consider:

1. **Implementing the Saga Pattern**: Add compensating actions for long-running transactions
2. **Event Sourcing**: Store all events for audit trails and replay capabilities
3. **Advanced Monitoring**: Add custom metrics and automated alerting
4. **Security Hardening**: Implement VNet integration and private endpoints
5. **CI/CD Integration**: Automate deployments with Azure DevOps or GitHub Actions

## References

- [Azure Service Bus Premium Messaging](https://docs.microsoft.com/en-us/azure/service-bus-messaging/service-bus-premium-messaging)
- [Azure Container Apps Documentation](https://docs.microsoft.com/en-us/azure/container-apps/)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Application Insights Distributed Tracing](https://docs.microsoft.com/en-us/azure/azure-monitor/app/distributed-tracing)
- [Azure Monitor Workbooks](https://docs.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview)