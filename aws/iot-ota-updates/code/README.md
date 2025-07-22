# Infrastructure as Code for IoT Over-the-Air Updates with Device Management

This directory contains Infrastructure as Code (IaC) implementations for the recipe "IoT Over-the-Air Updates with Device Management".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - IoT Core (things, policies, certificates, jobs)
  - IoT Device Management (thing groups, fleet management)
  - S3 (bucket creation, object upload)
  - CloudWatch (logs and metrics)
  - IAM (role and policy creation)
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

## Architecture Overview

This infrastructure deploys:

- **IoT Core**: Device registry and MQTT messaging
- **IoT Device Management**: Thing groups and fleet organization
- **IoT Jobs**: Over-the-air update orchestration
- **S3 Bucket**: Firmware storage and distribution
- **IAM Policies**: Device authentication and authorization
- **CloudWatch**: Monitoring and logging

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name iot-fleet-management \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-iot-fleet \
                 ParameterKey=FirmwareVersion,ParameterValue=v2.1.0

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name iot-fleet-management \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View deployed resources
cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View deployed resources
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# View deployed resources
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
aws iot list-thing-groups
aws s3 ls | grep iot-firmware-updates
```

## Customization

### Environment Variables

Set these environment variables before deployment:

```bash
export AWS_REGION=us-east-1
export PROJECT_NAME=my-iot-fleet
export FIRMWARE_VERSION=v2.1.0
export DEVICE_COUNT=10
```

### Parameters

#### CloudFormation Parameters

- `ProjectName`: Name prefix for all resources (default: iot-fleet)
- `FirmwareVersion`: Initial firmware version (default: v2.1.0)
- `DeviceCount`: Number of devices to register (default: 3)
- `Environment`: Deployment environment (default: production)

#### CDK Context Values

```json
{
  "projectName": "my-iot-fleet",
  "firmwareVersion": "v2.1.0",
  "deviceCount": 3,
  "environment": "production"
}
```

#### Terraform Variables

```hcl
# terraform.tfvars
project_name = "my-iot-fleet"
firmware_version = "v2.1.0"
device_count = 3
environment = "production"
region = "us-east-1"
```

## Post-Deployment Tasks

### Upload Firmware Files

```bash
# Upload sample firmware to S3 bucket
echo "Firmware update package v2.1.0" > firmware-v2.1.0.bin
aws s3 cp firmware-v2.1.0.bin s3://iot-firmware-updates-<random-suffix>/firmware/
```

### Create and Deploy OTA Job

```bash
# Create job document
cat > firmware-update-job.json << EOF
{
  "operation": "firmwareUpdate",
  "firmwareVersion": "v2.1.0",
  "downloadUrl": "https://iot-firmware-updates-<bucket-suffix>.s3.amazonaws.com/firmware/firmware-v2.1.0.bin",
  "checksumAlgorithm": "SHA256",
  "installationSteps": [
    "Download firmware package",
    "Validate package integrity",
    "Install new firmware",
    "Restart and validate"
  ]
}
EOF

# Deploy OTA job to fleet
aws iot create-job \
    --job-id firmware-update-v2.1.0 \
    --targets "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:thinggroup/ProductionDevices" \
    --document file://firmware-update-job.json \
    --description "Deploy firmware version v2.1.0"
```

### Monitor Job Execution

```bash
# Check job status
aws iot describe-job --job-id firmware-update-v2.1.0

# Monitor device executions
aws iot list-job-executions-for-job \
    --job-id firmware-update-v2.1.0 \
    --output table
```

## Validation

### Verify Infrastructure

```bash
# Check IoT resources
aws iot list-things --output table
aws iot list-thing-groups --output table
aws iot list-policies --output table

# Verify S3 bucket
aws s3 ls s3://iot-firmware-updates-<random-suffix>/

# Check CloudWatch logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/iot" \
    --output table
```

### Test Device Communication

```bash
# Simulate device job processing
SAMPLE_THING=$(aws iot list-things --query 'things[0].thingName' --output text)
aws iot update-job-execution \
    --job-id firmware-update-v2.1.0 \
    --thing-name $SAMPLE_THING \
    --status IN_PROGRESS
```

## Monitoring and Troubleshooting

### CloudWatch Metrics

Key metrics to monitor:

- `AWS/IoT/JobsCompleted`: Number of completed jobs
- `AWS/IoT/JobsFailed`: Number of failed jobs
- `AWS/IoT/DeviceConnectivity`: Device connection status
- `AWS/IoT/MessageBroker.PublishIn`: Published messages

### CloudWatch Logs

Review logs in these log groups:

- `/aws/iot/jobs`: Job execution logs
- `/aws/iot/device-registry`: Device registration logs
- `/aws/iot/thing-groups`: Thing group operation logs

### Common Issues

1. **Job Execution Failures**
   - Check device certificates and policies
   - Verify thing group membership
   - Review job document syntax

2. **Device Registration Issues**
   - Validate IAM permissions
   - Check certificate status
   - Verify policy attachments

3. **Firmware Download Failures**
   - Check S3 bucket permissions
   - Verify firmware file existence
   - Validate download URLs

## Security Considerations

### IAM Policies

- Device policies follow least privilege principle
- Job execution requires specific permissions
- S3 access is restricted to firmware bucket

### Certificate Management

- Device certificates are created with proper lifecycle
- Certificates are deactivated before deletion
- Regular certificate rotation recommended

### Network Security

- All communication uses TLS encryption
- Device authentication via X.509 certificates
- MQTT topic access is restricted per device

## Cost Optimization

### Resource Costs

- IoT Core: $0.08 per million messages
- IoT Device Management: $0.0025 per remote action
- S3 Storage: $0.023 per GB per month
- CloudWatch Logs: $0.50 per GB ingested

### Optimization Tips

- Use device-side filtering to reduce message volume
- Implement batch job processing
- Set appropriate log retention periods
- Use S3 lifecycle policies for firmware archival

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name iot-fleet-management

# Verify deletion
aws cloudformation describe-stacks \
    --stack-name iot-fleet-management \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy the infrastructure
cdk destroy

# Confirm deletion
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
aws iot list-thing-groups
aws s3 ls | grep iot-firmware-updates
```

### Manual Cleanup (if needed)

```bash
# Clean up any remaining resources
aws iot cancel-job --job-id firmware-update-v2.1.0
aws iot delete-job --job-id firmware-update-v2.1.0
aws s3 rm s3://iot-firmware-updates-<suffix> --recursive
aws s3 rb s3://iot-firmware-updates-<suffix>
```

## Extensions

### Advanced Features

1. **Blue-Green Deployments**: Implement staged rollouts using multiple thing groups
2. **Automated Rollback**: Create CloudWatch alarms for automatic job cancellation
3. **Fleet Analytics**: Integrate with IoT Analytics for operational insights
4. **Compliance Reporting**: Add AWS Config rules for firmware version tracking

### Integration Options

- **Device Shadow**: Implement device state management
- **Rules Engine**: Add automated response to device events
- **Greengrass**: Enable edge computing capabilities
- **Device Defender**: Add security monitoring and anomaly detection

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS IoT Core documentation
3. Validate IAM permissions and policies
4. Review CloudWatch logs for error details
5. Ensure all prerequisites are met

## Additional Resources

- [AWS IoT Core Documentation](https://docs.aws.amazon.com/iot/)
- [AWS IoT Device Management Guide](https://docs.aws.amazon.com/iot/latest/developerguide/device-management.html)
- [AWS IoT Jobs Documentation](https://docs.aws.amazon.com/iot/latest/developerguide/iot-jobs.html)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)