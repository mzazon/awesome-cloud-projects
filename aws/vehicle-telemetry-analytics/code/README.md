# Infrastructure as Code for Vehicle Telemetry Analytics with IoT FleetWise

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Vehicle Telemetry Analytics with IoT FleetWise".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This infrastructure deploys a complete vehicle telemetry analytics system including:

- AWS IoT FleetWise signal catalog, vehicle models, and decoder manifests
- Amazon Timestream database and table for time-series data storage
- Amazon Managed Grafana workspace for visualization
- S3 bucket for data archival
- IAM roles and policies for secure service integration
- Data collection campaigns for real-time telemetry

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - AWS IoT FleetWise
  - Amazon Timestream
  - Amazon Managed Grafana
  - Amazon S3
  - AWS IAM
  - AWS IoT Core
- Python 3.9+ (for CDK Python implementation)
- Node.js 18+ (for CDK TypeScript implementation)
- Terraform 1.0+ (for Terraform implementation)
- Estimated cost: $50-100/month for small fleet (10 vehicles)

> **Note**: AWS IoT FleetWise is currently available in US East (N. Virginia) and Europe (Frankfurt) regions only.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name vehicle-telemetry-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=FleetName,ParameterValue=my-vehicle-fleet \
                 ParameterKey=Environment,ParameterValue=dev \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stack-events \
    --stack-name vehicle-telemetry-stack \
    --query 'StackEvents[?ResourceStatus==`CREATE_COMPLETE`]'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name vehicle-telemetry-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy --parameters fleetName=my-vehicle-fleet

# View outputs
npx cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters fleet-name=my-vehicle-fleet

# View outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="fleet_name=my-vehicle-fleet" \
               -var="environment=dev"

# Deploy infrastructure
terraform apply -var="fleet_name=my-vehicle-fleet" \
                -var="environment=dev" \
                -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export FLEET_NAME="my-vehicle-fleet"
export AWS_REGION="us-east-1"
export ENVIRONMENT="dev"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Post-Deployment Configuration

After successful deployment, complete these manual configuration steps:

### 1. Vehicle Registration

```bash
# Get the fleet ID from outputs
FLEET_ID=$(aws cloudformation describe-stacks \
    --stack-name vehicle-telemetry-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`FleetId`].OutputValue' \
    --output text)

# Register a test vehicle
aws iotfleetwise create-vehicle \
    --vehicle-name "test-vehicle-001" \
    --model-manifest-arn $(aws cloudformation describe-stacks \
        --stack-name vehicle-telemetry-stack \
        --query 'Stacks[0].Outputs[?OutputKey==`ModelManifestArn`].OutputValue' \
        --output text) \
    --decoder-manifest-arn $(aws cloudformation describe-stacks \
        --stack-name vehicle-telemetry-stack \
        --query 'Stacks[0].Outputs[?OutputKey==`DecoderManifestArn`].OutputValue' \
        --output text)

# Associate vehicle with fleet
aws iotfleetwise associate-vehicle-fleet \
    --vehicle-name "test-vehicle-001" \
    --fleet-id ${FLEET_ID}
```

### 2. Grafana Configuration

```bash
# Get Grafana workspace URL
GRAFANA_URL=$(aws cloudformation describe-stacks \
    --stack-name vehicle-telemetry-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`GrafanaWorkspaceUrl`].OutputValue' \
    --output text)

echo "Access Grafana at: ${GRAFANA_URL}"
echo "Configure Timestream data source with:"
echo "  Database: $(aws cloudformation describe-stacks \
    --stack-name vehicle-telemetry-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`TimestreamDatabase`].OutputValue' \
    --output text)"
echo "  Table: $(aws cloudformation describe-stacks \
    --stack-name vehicle-telemetry-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`TimestreamTable`].OutputValue' \
    --output text)"
```

### 3. Start Data Collection Campaign

```bash
# Get campaign name from outputs
CAMPAIGN_NAME=$(aws cloudformation describe-stacks \
    --stack-name vehicle-telemetry-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`CampaignName`].OutputValue' \
    --output text)

# Approve and start campaign
aws iotfleetwise update-campaign \
    --name ${CAMPAIGN_NAME} \
    --action APPROVE

sleep 5

aws iotfleetwise update-campaign \
    --name ${CAMPAIGN_NAME} \
    --action RESUME

echo "Campaign started successfully"
```

## Validation

### Verify Infrastructure Deployment

```bash
# Check IoT FleetWise resources
aws iotfleetwise list-signal-catalogs
aws iotfleetwise list-model-manifests
aws iotfleetwise list-fleets

# Check Timestream database
aws timestream-write describe-database \
    --database-name $(terraform output -raw timestream_database_name)

# Check Grafana workspace
aws grafana list-workspaces
```

### Test Data Collection

```bash
# Query recent telemetry data (if any)
aws timestream-query query \
    --query-string "SELECT * FROM telemetry_db.vehicle_metrics ORDER BY time DESC LIMIT 5"

# Check campaign status
aws iotfleetwise get-campaign --name ${CAMPAIGN_NAME}
```

## Monitoring and Troubleshooting

### View CloudWatch Logs

```bash
# View FleetWise logs
aws logs describe-log-groups --log-group-name-prefix "/aws/iotfleetwise"

# View Timestream metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Timestream \
    --metric-name UserRecords \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

### Common Issues

1. **Campaign not collecting data**: Ensure vehicles are properly registered and Edge Agent is deployed
2. **Timestream write errors**: Verify IAM permissions for FleetWise service role
3. **Grafana access issues**: Check workspace status and authentication configuration

## Customization

### Configuration Variables

The following variables can be customized for your environment:

#### CloudFormation Parameters
- `FleetName`: Name for the vehicle fleet (default: vehicle-fleet)
- `Environment`: Environment tag (default: dev)
- `DataRetentionDays`: Timestream data retention (default: 30)
- `CollectionIntervalMs`: Data collection interval (default: 10000)

#### Terraform Variables
- `fleet_name`: Name for the vehicle fleet
- `environment`: Environment tag
- `aws_region`: AWS region for deployment
- `timestream_memory_retention_hours`: Memory store retention (default: 24)
- `timestream_magnetic_retention_days`: Magnetic store retention (default: 30)

#### CDK Parameters
- `fleet_name`: Name for the vehicle fleet
- `environment`: Environment tag
- `collection_interval`: Data collection interval in milliseconds

### Adding Custom Signals

To add custom vehicle signals, modify the signal catalog configuration in your chosen IaC implementation:

```yaml
# CloudFormation example
VehicleSpeed:
  Type: AWS::IoTFleetWise::SignalCatalog
  Properties:
    Nodes:
      - Sensor:
          FullyQualifiedName: "Vehicle.CustomSignal"
          DataType: "DOUBLE"
          Unit: "custom_unit"
          Min: 0
          Max: 1000
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name vehicle-telemetry-stack

# Monitor deletion progress
aws cloudformation describe-stack-events \
    --stack-name vehicle-telemetry-stack \
    --query 'StackEvents[?ResourceStatus==`DELETE_COMPLETE`]'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npx cdk destroy --force
```

### Using CDK Python

```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy --force
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="fleet_name=my-vehicle-fleet" \
                  -var="environment=dev" \
                  -auto-approve
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm cleanup
./scripts/destroy.sh --verify
```

### Manual Cleanup (if needed)

```bash
# Remove any remaining FleetWise resources
aws iotfleetwise list-campaigns --query 'summaries[].name' --output text | \
  xargs -I {} aws iotfleetwise delete-campaign --name {}

# Empty S3 bucket before deletion
aws s3 rm s3://your-bucket-name --recursive
```

## Cost Optimization

### Reduce Costs

1. **Adjust collection frequency**: Increase `CollectionIntervalMs` to reduce data points
2. **Optimize Timestream retention**: Reduce retention periods for non-critical data
3. **Use S3 lifecycle policies**: Archive old data to cheaper storage classes
4. **Pause campaigns**: Suspend data collection when not needed

### Monitor Costs

```bash
# Check current month charges
aws ce get-cost-and-usage \
    --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Security Considerations

### IAM Best Practices

- All IAM roles follow least privilege principle
- Cross-service permissions are explicitly defined
- Service-linked roles are used where available

### Data Encryption

- Timestream data encrypted at rest with AWS managed keys
- S3 bucket uses server-side encryption
- Data in transit encrypted using TLS

### Network Security

- VPC endpoints can be configured for private connectivity
- Security groups restrict access to necessary ports only

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation:
   - [AWS IoT FleetWise Developer Guide](https://docs.aws.amazon.com/iot-fleetwise/)
   - [Amazon Timestream Developer Guide](https://docs.aws.amazon.com/timestream/)
   - [Amazon Managed Grafana User Guide](https://docs.aws.amazon.com/grafana/)
3. Verify AWS service limits and quotas
4. Check CloudWatch logs for error details

## Additional Resources

- [AWS IoT FleetWise Pricing](https://aws.amazon.com/iot-fleetwise/pricing/)
- [Amazon Timestream Pricing](https://aws.amazon.com/timestream/pricing/)
- [Amazon Managed Grafana Pricing](https://aws.amazon.com/grafana/pricing/)
- [AWS Well-Architected IoT Lens](https://docs.aws.amazon.com/wellarchitected/latest/iot-lens/)