# Infrastructure as Code for Predictive Maintenance with IoT Digital Twins

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Predictive Maintenance with IoT Digital Twins".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI (v2.54.0 or later) installed and configured
- Azure subscription with Owner or Contributor access
- Sufficient Azure quota for:
  - Azure Digital Twins
  - Azure Data Explorer cluster
  - Azure Functions
  - Azure IoT Central
  - Azure Event Hubs
  - Azure Time Series Insights
- Basic understanding of IoT concepts, digital twins, and time-series data
- Familiarity with Kusto Query Language (KQL) for data analytics

## Cost Estimation

**Estimated monthly cost for demo workload**: ~$150-200/month

Main cost components:
- Azure Data Explorer cluster (Dev SKU): ~$100/month
- Azure Digital Twins: ~$20/month
- Azure IoT Central (ST2): ~$15/month
- Azure Functions (consumption): ~$5/month
- Azure Event Hubs (Standard): ~$10/month
- Azure Time Series Insights: ~$5/month

> **Warning**: Ensure proper cleanup after testing to avoid ongoing charges, especially for the Azure Data Explorer cluster.

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-iot-digital-twins \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters resourcePrefix=iot-demo

# Monitor deployment progress
az deployment group show \
    --resource-group rg-iot-digital-twins \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# Confirm deployment when prompted
# Type 'yes' to proceed
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for resource configuration
```

## Post-Deployment Configuration

After successful deployment, additional configuration is required:

### 1. Configure Digital Twin Models

```bash
# Set environment variables (replace with your values)
export ADT_NAME="your-digital-twins-instance"
export RESOURCE_GROUP="your-resource-group"

# Upload the equipment model
az dt model create \
    --dt-name ${ADT_NAME} \
    --models '{
        "@id": "dtmi:com:example:IndustrialEquipment;1",
        "@type": "Interface",
        "@context": "dtmi:dtdl:context;2",
        "displayName": "Industrial Equipment",
        "contents": [
            {
                "@type": "Property",
                "name": "temperature",
                "schema": "double"
            },
            {
                "@type": "Property",
                "name": "vibration",
                "schema": "double"
            },
            {
                "@type": "Property",
                "name": "operatingHours",
                "schema": "integer"
            },
            {
                "@type": "Property",
                "name": "maintenanceStatus",
                "schema": "string"
            }
        ]
    }'
```

### 2. Create Sample Digital Twins

```bash
# Create sample equipment instances
for i in {1..3}; do
    az dt twin create \
        --dt-name ${ADT_NAME} \
        --twin-id "equipment-${i}" \
        --twin-init '{
            "$metadata": {
                "$model": "dtmi:com:example:IndustrialEquipment;1"
            },
            "temperature": 25.0,
            "vibration": 5.0,
            "operatingHours": 100,
            "maintenanceStatus": "Normal"
        }'
done
```

### 3. Configure Data Explorer Analytics

```bash
# Set ADX variables
export ADX_CLUSTER="your-adx-cluster"
export ADX_DATABASE="iottelemetry"

# Create analytics functions
az kusto query \
    --cluster-name ${ADX_CLUSTER} \
    --database-name ${ADX_DATABASE} \
    --query "
    .create-or-alter function DetectAnomalies() {
        TelemetryData
        | where Timestamp > ago(1h)
        | make-series Temperature=avg(Temperature) default=0 on Timestamp step 1m by DeviceId
        | extend (anomalies, score, baseline) = series_decompose_anomalies(Temperature, 1.5, -1, 'linefit')
        | mv-expand Timestamp, Temperature, anomalies, score, baseline
        | where anomalies == 1
        | project DeviceId, Timestamp, Temperature, score, baseline
    }
    
    .create-or-alter function PredictMaintenance() {
        TelemetryData
        | where Timestamp > ago(7d)
        | summarize AvgVibration=avg(Vibration), MaxVibration=max(Vibration), OperatingHours=max(OperatingHours) by DeviceId
        | extend MaintenanceRisk = case(
            MaxVibration > 50 and OperatingHours > 1000, 'High',
            MaxVibration > 30 and OperatingHours > 500, 'Medium',
            'Low'
        )
        | project DeviceId, MaintenanceRisk, AvgVibration, OperatingHours
    }
    "
```

## Validation & Testing

### 1. Verify Azure Digital Twins

```bash
# Check ADT instance status
az dt show \
    --name ${ADT_NAME} \
    --query '{Name:name, Status:provisioningState}' \
    --output table

# List uploaded models
az dt model list \
    --dt-name ${ADT_NAME} \
    --query '[].{Model:id, DisplayName:displayName}' \
    --output table

# Query digital twins
az dt twin query \
    --dt-name ${ADT_NAME} \
    --query-command "SELECT * FROM digitaltwins"
```

### 2. Test Azure Data Explorer

```bash
# Check ADX cluster status
az kusto cluster show \
    --name ${ADX_CLUSTER} \
    --resource-group ${RESOURCE_GROUP} \
    --query '{Name:name, State:state, Uri:uri}' \
    --output table

# Test analytics functions
az kusto query \
    --cluster-name ${ADX_CLUSTER} \
    --database-name ${ADX_DATABASE} \
    --query "DetectAnomalies() | take 10"
```

### 3. Validate IoT Central

```bash
# Check IoT Central application
az iot central app show \
    --name ${IOTC_APP} \
    --resource-group ${RESOURCE_GROUP} \
    --query '{Name:name, State:state, Url:applicationUrl}' \
    --output table
```

## Accessing Services

After deployment, access your services through these URLs:

- **Azure Digital Twins Explorer**: `https://{your-adt-instance}.api.{region}.digitaltwins.azure.net/explorer`
- **IoT Central Dashboard**: `https://{your-iotc-app}.azureiotcentral.com`
- **Azure Data Explorer**: `https://{your-adx-cluster}.{region}.kusto.windows.net`
- **Time Series Insights**: Access through Azure Portal

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-iot-digital-twins \
    --yes \
    --no-wait

echo "Resource group deletion initiated"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
# Type 'yes' to proceed
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Verify Cleanup

```bash
# Check if resources are deleted
az group exists --name rg-iot-digital-twins

# Should return 'false' when deletion is complete
```

## Customization

### Bicep Parameters

Key parameters you can customize in the Bicep template:

- `location`: Azure region for resource deployment
- `resourcePrefix`: Prefix for resource names
- `adxSkuName`: Azure Data Explorer SKU (Dev, Standard, Premium)
- `adxSkuCapacity`: Number of ADX cluster instances
- `iotCentralSku`: IoT Central pricing tier
- `functionAppSku`: Function App hosting plan

### Terraform Variables

Customize deployment through `terraform.tfvars`:

```hcl
# terraform.tfvars
resource_group_name = "rg-iot-digital-twins"
location           = "eastus"
resource_prefix    = "iot-demo"
adx_sku_name      = "Dev(No SLA)_Standard_E2a_v4"
adx_sku_capacity  = 1
iotc_sku          = "ST2"
```

### Environment-Specific Configuration

For different environments (dev, staging, prod):

1. **Development**: Use Dev SKUs and minimal capacity
2. **Staging**: Use Standard SKUs with moderate capacity
3. **Production**: Use Premium SKUs with high availability

## Architecture Components

The infrastructure deploys these key components:

1. **Azure Digital Twins**: Digital representation of physical assets
2. **Azure Data Explorer**: Time-series analytics and anomaly detection
3. **Azure IoT Central**: Device management and telemetry collection
4. **Azure Functions**: Event processing and twin updates
5. **Azure Event Hubs**: Real-time data streaming
6. **Azure Time Series Insights**: IoT-specific analytics and visualization
7. **Azure Storage**: Function app storage and TSI warm storage

## Security Considerations

The infrastructure implements these security practices:

- **Managed Identity**: Function apps use managed identity for authentication
- **RBAC**: Role-based access control for Digital Twins and Data Explorer
- **Network Security**: Event Hubs and storage use Azure backbone networking
- **Encryption**: Data encrypted at rest and in transit
- **Least Privilege**: Minimal required permissions for each service

## Monitoring and Alerts

Consider implementing these monitoring practices:

- **Azure Monitor**: Track resource health and performance metrics
- **Application Insights**: Monitor Function app performance
- **ADX Dashboards**: Create operational dashboards for telemetry analysis
- **Alert Rules**: Set up alerts for anomaly detection results

## Troubleshooting

### Common Issues

1. **ADX Cluster Creation Fails**
   - Check regional availability and quota limits
   - Verify subscription has sufficient compute quota

2. **Function App Deployment Issues**
   - Ensure storage account is accessible
   - Check managed identity permissions

3. **Digital Twins Access Issues**
   - Verify RBAC role assignments
   - Check Azure AD permissions

4. **Data Flow Problems**
   - Validate Event Hub connection strings
   - Check Function app configuration settings

### Support Resources

- [Azure Digital Twins Documentation](https://docs.microsoft.com/en-us/azure/digital-twins/)
- [Azure Data Explorer Documentation](https://docs.microsoft.com/en-us/azure/data-explorer/)
- [Azure IoT Central Documentation](https://docs.microsoft.com/en-us/azure/iot-central/)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development environment
2. Update documentation for any parameter changes
3. Ensure compatibility with all deployment methods
4. Follow Azure naming conventions and best practices

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Refer to the original recipe documentation for usage guidelines.