# Infrastructure as Code for Sustainable Manufacturing Monitoring with IoT SiteWise

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Sustainable Manufacturing Monitoring with IoT SiteWise".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for creating IoT SiteWise, Lambda, CloudWatch, and QuickSight resources
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform v1.0+
- Basic understanding of IoT concepts and sustainability metrics
- Estimated cost: $50-100 per month for demo environment

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name sustainable-manufacturing-monitoring \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=demo

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name sustainable-manufacturing-monitoring \
    --query 'Stacks[0].StackStatus'
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
npx cdk deploy

# View outputs
npx cdk output
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk output
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
aws iotsitewise list-asset-models --query 'assetModelSummaries[?assetModelName==`SustainableManufacturingModel`]'
```

## Architecture Overview

The infrastructure creates:

- **IoT SiteWise Asset Model**: Defines the structure for manufacturing equipment data
- **IoT SiteWise Assets**: Represents individual manufacturing equipment
- **Lambda Function**: Processes IoT data and calculates carbon emissions
- **CloudWatch Alarms**: Monitors sustainability thresholds
- **EventBridge Rules**: Automates daily sustainability reporting
- **IAM Roles**: Provides secure access between services

## Configuration Options

### Environment Variables

All implementations support these environment variables:

```bash
export AWS_REGION=us-east-1                    # AWS region for deployment
export ENVIRONMENT=demo                        # Environment tag (demo/staging/prod)
export CARBON_INTENSITY_FACTOR=0.393          # Regional carbon intensity (kg CO2/kWh)
export ALARM_THRESHOLD_CARBON=50.0             # Carbon emissions alarm threshold
export ALARM_THRESHOLD_POWER=100.0             # Power consumption alarm threshold
```

### Customization Parameters

- **Asset Model Name**: Customize the manufacturing equipment model name
- **Equipment Names**: Modify the names of manufacturing equipment assets
- **Lambda Function Configuration**: Adjust memory size, timeout, and runtime
- **CloudWatch Alarm Settings**: Configure thresholds and evaluation periods
- **EventBridge Schedule**: Modify reporting frequency (default: daily at 8 AM UTC)

## Post-Deployment Steps

After successful deployment:

1. **Verify Asset Creation**:
   ```bash
   # List created asset models
   aws iotsitewise list-asset-models
   
   # Check asset status
   aws iotsitewise describe-asset --asset-id <ASSET_ID>
   ```

2. **Test Carbon Calculations**:
   ```bash
   # Invoke Lambda function with test data
   aws lambda invoke \
       --function-name manufacturing-carbon-calculator \
       --payload '{"asset_id":"<ASSET_ID>"}' \
       response.json
   ```

3. **Monitor CloudWatch Metrics**:
   ```bash
   # Check for sustainability metrics
   aws cloudwatch list-metrics \
       --namespace "Manufacturing/Sustainability"
   ```

4. **Configure QuickSight Dashboard** (Manual):
   - Access QuickSight console
   - Create new dashboard using CloudWatch metrics
   - Configure visualizations for carbon emissions and energy efficiency

## Testing and Validation

### Data Simulation

Use the provided simulation script to test the system:

```bash
# Generate and send test data
./scripts/simulate-manufacturing-data.sh

# Verify data ingestion
aws iotsitewise get-asset-property-value \
    --asset-id <ASSET_ID> \
    --property-id <POWER_PROPERTY_ID>
```

### Monitoring Validation

```bash
# Check alarm states
aws cloudwatch describe-alarms \
    --alarm-names "High-Carbon-Emissions" "Low-Energy-Efficiency"

# View CloudWatch logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/manufacturing-carbon-calculator"
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name sustainable-manufacturing-monitoring

# Verify deletion
aws cloudformation describe-stacks \
    --stack-name sustainable-manufacturing-monitoring
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
npx cdk destroy  # or cdk destroy for Python

# Confirm destruction
npx cdk ls  # Should show no stacks
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
aws iotsitewise list-asset-models \
    --query 'assetModelSummaries[?assetModelName==`SustainableManufacturingModel`]'
```

## Security Considerations

### IAM Permissions

The infrastructure creates IAM roles with minimal required permissions:

- **Lambda Execution Role**: 
  - Read access to IoT SiteWise assets
  - Write access to CloudWatch metrics
  - Basic Lambda execution permissions

- **EventBridge Role**:
  - Permission to invoke Lambda functions

### Data Protection

- All data in transit is encrypted using TLS
- CloudWatch metrics are encrypted at rest
- Lambda functions use environment variables for configuration
- No sensitive data is stored in function code

### Network Security

- Lambda functions run in AWS managed VPC
- IoT SiteWise assets use secure MQTT connections
- CloudWatch metrics access controlled by IAM

## Troubleshooting

### Common Issues

1. **Asset Creation Fails**:
   - Check IAM permissions for IoT SiteWise
   - Verify asset model is in ACTIVE state before creating assets

2. **Lambda Function Errors**:
   - Check CloudWatch logs for detailed error messages
   - Verify IAM role has required permissions
   - Ensure asset IDs are valid

3. **No Metrics in CloudWatch**:
   - Verify Lambda function is receiving data
   - Check CloudWatch namespace and metric names
   - Ensure proper permissions for metric publishing

4. **Alarm Not Triggering**:
   - Check alarm configuration and thresholds
   - Verify metric data is being published
   - Review evaluation periods and comparison operators

### Debug Commands

```bash
# Check Lambda function logs
aws logs tail /aws/lambda/manufacturing-carbon-calculator --follow

# Verify IoT SiteWise data ingestion
aws iotsitewise get-asset-property-value-history \
    --asset-id <ASSET_ID> \
    --property-id <PROPERTY_ID> \
    --start-date 2024-01-01T00:00:00Z \
    --end-date 2024-01-02T00:00:00Z

# Check EventBridge rule targets
aws events list-targets-by-rule \
    --rule daily-sustainability-report
```

## Cost Optimization

### Cost Factors

- **IoT SiteWise**: Charged per asset per month and data points ingested
- **Lambda**: Charged per invocation and execution duration
- **CloudWatch**: Charged per metric and alarm
- **EventBridge**: Minimal cost for rule executions

### Optimization Tips

1. **Data Retention**: Configure CloudWatch log retention periods
2. **Lambda Optimization**: Right-size memory allocation
3. **Metric Frequency**: Adjust data collection frequency based on needs
4. **Alarm Configuration**: Use appropriate evaluation periods

## Support and Documentation

### AWS Documentation

- [AWS IoT SiteWise User Guide](https://docs.aws.amazon.com/iot-sitewise/latest/userguide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon CloudWatch User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)

### Best Practices

- [AWS Well-Architected IoT Lens](https://docs.aws.amazon.com/wellarchitected/latest/iot-lens/)
- [AWS Sustainability Documentation](https://sustainability.aws/)
- [AWS Industrial IoT Solutions](https://aws.amazon.com/industrial/)

### Community Resources

- [AWS IoT SiteWise Samples](https://github.com/aws-samples/aws-iot-sitewise-samples)
- [AWS Sustainability Examples](https://github.com/aws-samples/aws-sustainability-examples)

For issues with this infrastructure code, refer to the original recipe documentation or open an issue in the repository.