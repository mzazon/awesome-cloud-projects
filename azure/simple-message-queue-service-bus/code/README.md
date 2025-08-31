# Infrastructure as Code for Simple Message Queue with Service Bus

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Message Queue with Service Bus".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.0.45 or later)
- Active Azure subscription with appropriate permissions to create:
  - Resource Groups
  - Service Bus namespaces and queues
  - Authorization rules
- For Terraform: Terraform installed (version 1.0 or later)
- For testing: Node.js installed (version 14 or later)

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
                 serviceBusNamespace=<unique-namespace-name> \
                 queueName=orders

# View deployment outputs
az deployment group show \
    --resource-group <your-resource-group> \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="resource_group_name=<your-resource-group>" \
    -var="location=eastus" \
    -var="servicebus_namespace=<unique-namespace-name>"

# Apply the configuration
terraform apply \
    -var="resource_group_name=<your-resource-group>" \
    -var="location=eastus" \
    -var="servicebus_namespace=<unique-namespace-name>"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set required environment variables
export RESOURCE_GROUP="<your-resource-group>"
export LOCATION="eastus"
export SERVICEBUS_NAMESPACE="<unique-namespace-name>"
export QUEUE_NAME="orders"

# Deploy infrastructure
./scripts/deploy.sh

# Optionally run the test application
./scripts/test-messaging.sh
```

## Configuration Options

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | `resourceGroup().location` | Azure region for resources |
| `serviceBusNamespace` | string | (required) | Unique name for Service Bus namespace |
| `queueName` | string | `orders` | Name of the message queue |
| `serviceBusSku` | string | `Standard` | Service Bus pricing tier (Basic/Standard/Premium) |
| `maxSizeInMegabytes` | int | `1024` | Maximum queue size in MB |
| `defaultMessageTimeToLive` | string | `P14D` | Default message TTL (ISO 8601 duration) |
| `enableDeadLettering` | bool | `true` | Enable dead letter queue for expired messages |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `resource_group_name` | string | (required) | Name of existing resource group |
| `location` | string | `"eastus"` | Azure region for resources |
| `servicebus_namespace` | string | (required) | Unique name for Service Bus namespace |
| `queue_name` | string | `"orders"` | Name of the message queue |
| `servicebus_sku` | string | `"Standard"` | Service Bus pricing tier |
| `max_size_in_megabytes` | number | `1024` | Maximum queue size in MB |
| `default_message_ttl` | string | `"P14D"` | Default message TTL |
| `enable_dead_lettering` | bool | `true` | Enable dead letter queue |

### Environment Variables (Bash Scripts)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `RESOURCE_GROUP` | Yes | - | Name of resource group to create/use |
| `LOCATION` | No | `eastus` | Azure region for deployment |
| `SERVICEBUS_NAMESPACE` | Yes | - | Unique name for Service Bus namespace |
| `QUEUE_NAME` | No | `orders` | Name of the message queue |

## Testing the Implementation

After deployment, you can test message sending and receiving:

### Using Azure CLI

```bash
# Get connection string
CONNECTION_STRING=$(az servicebus namespace authorization-rule keys list \
    --resource-group <your-resource-group> \
    --namespace-name <your-namespace> \
    --name RootManageSharedAccessKey \
    --query primaryConnectionString \
    --output tsv)

# Send a test message (requires Azure CLI extension)
az servicebus message send \
    --connection-string "$CONNECTION_STRING" \
    --queue-name orders \
    --body "Test message from CLI"

# Peek at messages in queue
az servicebus message peek \
    --connection-string "$CONNECTION_STRING" \
    --queue-name orders \
    --count 1
```

### Using Sample Application

If you deployed using the bash scripts, a Node.js test application is included:

```bash
# Install dependencies (if not already done)
cd test-app
npm install

# Set environment variables
export CONNECTION_STRING="<your-connection-string>"
export QUEUE_NAME="orders"

# Send test messages
node send-messages.js

# Receive messages
node receive-messages.js
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name <your-resource-group> \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy \
    -var="resource_group_name=<your-resource-group>" \
    -var="location=eastus" \
    -var="servicebus_namespace=<unique-namespace-name>"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Or manually delete resource group
az group delete \
    --name "$RESOURCE_GROUP" \
    --yes \
    --no-wait
```

## Architecture

This implementation creates:

1. **Azure Service Bus Namespace** - Container for messaging entities
2. **Service Bus Queue** - FIFO message queue with dead-letter handling
3. **Authorization Rules** - Shared access keys for authentication
4. **Resource Tagging** - Consistent tagging for resource management

## Security Considerations

- Uses Azure Service Bus managed identity where possible
- Implements least-privilege access with specific authorization rules
- Enables dead-letter queues for message recovery
- Follows Azure security best practices for messaging services

## Cost Optimization

- Uses Standard tier by default (upgrade to Premium only if needed)
- Configurable message TTL to prevent storage bloat
- Dead-letter queues for message recovery without loss
- Resource tagging for cost allocation and management

## Monitoring and Observability

The deployed infrastructure includes:

- Built-in Azure Monitor integration
- Service Bus metrics and logs
- Dead-letter queue monitoring
- Connection and throughput metrics

### Recommended Alerts

Set up alerts for:
- Queue depth exceeding thresholds
- Dead-letter queue message count
- Connection failures
- Processing latency

## Customization

### Adding Message Sessions

To enable message sessions for FIFO processing within groups:

**Bicep:**
```bicep
requiresSession: true
```

**Terraform:**
```hcl
requires_session = true
```

### Implementing Duplicate Detection

To enable automatic duplicate message detection:

**Bicep:**
```bicep
requiresDuplicateDetection: true
duplicateDetectionHistoryTimeWindow: 'PT10M'
```

**Terraform:**
```hcl
requires_duplicate_detection = true
duplicate_detection_history_time_window = "PT10M"
```

### Custom Authorization Rules

Create specific access policies for different application components:

**Bicep:**
```bicep
resource sendOnlyRule 'Microsoft.ServiceBus/namespaces/AuthorizationRules@2021-11-01' = {
  name: 'SendOnlyPolicy'
  parent: serviceBusNamespace
  properties: {
    rights: ['Send']
  }
}
```

## Troubleshooting

### Common Issues

1. **Namespace name conflicts**: Service Bus namespace names must be globally unique
2. **Insufficient permissions**: Ensure your account has Contributor or Service Bus Data Owner role
3. **Connection string issues**: Verify the connection string includes the correct endpoint and credentials
4. **Queue not found**: Ensure the queue name matches exactly (case-sensitive)

### Diagnostic Commands

```bash
# Check namespace status
az servicebus namespace show \
    --resource-group <resource-group> \
    --name <namespace> \
    --query '{name:name, status:status, tier:sku.tier}'

# Check queue properties
az servicebus queue show \
    --resource-group <resource-group> \
    --namespace-name <namespace> \
    --name <queue-name> \
    --query '{name:name, messageCount:messageCount, status:status}'

# List authorization rules
az servicebus namespace authorization-rule list \
    --resource-group <resource-group> \
    --namespace-name <namespace>
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure Service Bus documentation: https://docs.microsoft.com/en-us/azure/service-bus-messaging/
3. Validate resource naming and regional availability
4. Ensure proper authentication and permissions

## Next Steps

Consider extending this implementation with:

1. **Azure Functions integration** for serverless message processing
2. **Application Insights** for detailed telemetry and monitoring
3. **Azure Key Vault** for secure connection string management
4. **Multiple queues** for different message types or priorities
5. **Service Bus topics and subscriptions** for pub/sub messaging patterns