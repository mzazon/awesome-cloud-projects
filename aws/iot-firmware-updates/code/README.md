# Infrastructure as Code for IoT Firmware Updates with Device Management Jobs

This directory contains Infrastructure as Code (IaC) implementations for the recipe "IoT Firmware Updates with Device Management Jobs".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - IoT Device Management (Jobs, Things, Thing Groups)
  - Lambda (function creation and execution)
  - S3 (bucket creation and object management)
  - AWS Signer (code signing profiles and jobs)
  - IAM (role and policy management)
  - CloudWatch (dashboard and metrics)
- Basic understanding of IoT device management and firmware update processes
- At least one IoT device or simulator for testing

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions

#### CDK TypeScript
- Node.js 16+ and npm
- AWS CDK CLI: `npm install -g aws-cdk`

#### CDK Python
- Python 3.8+ and pip
- AWS CDK CLI: `npm install -g aws-cdk`

#### Terraform
- Terraform 1.0+
- AWS provider for Terraform

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name iot-firmware-updates-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=FirmwareBucketName,ParameterValue=my-firmware-bucket-$(date +%s)

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name iot-firmware-updates-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name iot-firmware-updates-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk outputs
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk outputs
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
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

# The script will create all necessary resources and provide output values
```

## Architecture Components

This infrastructure deploys:

- **IoT Resources**: Thing, Thing Groups, and Job management roles
- **Storage**: S3 bucket for firmware distribution with versioning
- **Security**: AWS Signer profile for firmware code signing
- **Compute**: Lambda function for job orchestration and management
- **Monitoring**: CloudWatch dashboard for job tracking and metrics
- **IAM**: Least-privilege roles for IoT Jobs and Lambda execution

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| FirmwareBucketName | S3 bucket name for firmware storage | Generated | No |
| ThingName | IoT Thing name for testing | Generated | No |
| ThingGroupName | IoT Thing Group for job targeting | Generated | No |
| SigningProfileName | AWS Signer profile name | Generated | No |

### CDK Configuration

Modify the following variables in the CDK app files:
- `firmwareBucketName`: S3 bucket for firmware storage
- `thingName`: Test IoT device name
- `thingGroupName`: Device group for firmware updates
- `signingProfileName`: Code signing profile

### Terraform Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `firmware_bucket_name` | S3 bucket name | string | Generated |
| `thing_name` | IoT Thing name | string | Generated |
| `thing_group_name` | Thing Group name | string | Generated |
| `signing_profile_name` | Signer profile name | string | Generated |
| `region` | AWS region | string | Current region |

## Post-Deployment Setup

After deploying the infrastructure, complete these steps:

1. **Upload Sample Firmware**:
   ```bash
   # Create sample firmware
   echo "Sample firmware v1.0.0" > sample_firmware.bin
   
   # Upload to S3 bucket (replace with actual bucket name from outputs)
   aws s3 cp sample_firmware.bin s3://YOUR_FIRMWARE_BUCKET/firmware/
   ```

2. **Sign the Firmware**:
   ```bash
   # Start signing job (replace with actual values from outputs)
   aws signer start-signing-job \
       --source 's3={bucketName=YOUR_FIRMWARE_BUCKET,key=firmware/sample_firmware.bin}' \
       --destination 's3={bucketName=YOUR_FIRMWARE_BUCKET,prefix=signed-firmware/}' \
       --profile-name YOUR_SIGNING_PROFILE
   ```

3. **Create Firmware Update Job**:
   ```bash
   # Invoke Lambda function to create job (replace with actual values)
   aws lambda invoke \
       --function-name YOUR_LAMBDA_FUNCTION \
       --payload '{
         "action": "create_job",
         "firmware_version": "1.0.0",
         "thing_group": "YOUR_THING_GROUP",
         "s3_bucket": "YOUR_FIRMWARE_BUCKET",
         "s3_key": "signed-firmware/sample_firmware.bin"
       }' \
       response.json
   ```

4. **Monitor Job Progress**:
   ```bash
   # Check job status
   aws lambda invoke \
       --function-name YOUR_LAMBDA_FUNCTION \
       --payload '{
         "action": "check_job_status",
         "job_id": "YOUR_JOB_ID"
       }' \
       status.json
   ```

## Testing

### Device Simulator

The infrastructure includes a device simulator for testing firmware updates:

```bash
# Run the device simulator (outputs will provide the Python script)
python3 device_simulator.py YOUR_THING_NAME YOUR_AWS_REGION
```

### Verification Commands

```bash
# List IoT Jobs
aws iot list-jobs --target-selection SNAPSHOT

# Check Thing Group members
aws iot list-things-in-thing-group --thing-group-name YOUR_THING_GROUP

# View CloudWatch dashboard
aws cloudwatch get-dashboard --dashboard-name "IoT-Firmware-Updates"

# Check S3 bucket contents
aws s3 ls s3://YOUR_FIRMWARE_BUCKET --recursive
```

## Monitoring and Observability

### CloudWatch Metrics

The solution creates custom CloudWatch metrics:
- `JobsCompleted`: Number of successfully completed firmware updates
- `JobsFailed`: Number of failed firmware updates
- `JobsInProgress`: Current active firmware updates
- `JobsQueued`: Pending firmware updates

### CloudWatch Dashboard

Access the pre-built dashboard at:
```
https://console.aws.amazon.com/cloudwatch/home?region=YOUR_REGION#dashboards:name=IoT-Firmware-Updates
```

### Logs

Monitor Lambda function logs:
```bash
aws logs tail /aws/lambda/firmware-update-manager --follow
```

## Security Considerations

### IAM Roles and Policies

The infrastructure implements least-privilege access:
- **IoT Jobs Role**: Limited to S3 GetObject for firmware distribution
- **Lambda Execution Role**: Scoped permissions for IoT Jobs, S3, and Signer operations

### Code Signing

- All firmware must be signed using AWS Signer before deployment
- Devices verify signatures before installing updates
- Signing profiles include certificate-based authentication

### Network Security

- S3 bucket access is restricted to authorized roles only
- MQTT communication uses AWS IoT Core's built-in encryption
- Lambda functions execute in AWS's secure environment

## Troubleshooting

### Common Issues

1. **Job Creation Failures**:
   ```bash
   # Check IAM role permissions
   aws iam simulate-principal-policy \
       --policy-source-arn YOUR_LAMBDA_ROLE_ARN \
       --action-names iot:CreateJob \
       --resource-arns "*"
   ```

2. **Firmware Download Issues**:
   ```bash
   # Verify S3 object accessibility
   aws s3api head-object \
       --bucket YOUR_FIRMWARE_BUCKET \
       --key YOUR_FIRMWARE_KEY
   ```

3. **Signing Job Failures**:
   ```bash
   # Check signing job status
   aws signer describe-signing-job --job-id YOUR_SIGNING_JOB_ID
   ```

### Debug Mode

Enable debug logging in Lambda function:
```bash
aws lambda update-function-configuration \
    --function-name firmware-update-manager \
    --environment Variables='{LOG_LEVEL=DEBUG}'
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name iot-firmware-updates-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name iot-firmware-updates-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm when prompted for destructive actions
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually remove:

1. **Active IoT Jobs**:
   ```bash
   # List and cancel active jobs
   aws iot list-jobs --query 'jobs[?status==`IN_PROGRESS`].[jobId]' --output text | \
   xargs -I {} aws iot cancel-job --job-id {}
   ```

2. **S3 Bucket Contents**:
   ```bash
   # Empty bucket before deletion
   aws s3 rm s3://YOUR_FIRMWARE_BUCKET --recursive
   ```

3. **CloudWatch Resources**:
   ```bash
   # Delete custom dashboard
   aws cloudwatch delete-dashboards --dashboard-names "IoT-Firmware-Updates"
   ```

## Cost Estimation

Typical monthly costs for this solution (us-east-1 pricing):

| Service | Usage | Estimated Cost |
|---------|-------|----------------|
| IoT Device Management | 1,000 jobs/month | $0.50 |
| Lambda | 100 executions/month | $0.01 |
| S3 | 1 GB storage + transfers | $0.25 |
| AWS Signer | 10 signing jobs/month | $1.00 |
| CloudWatch | Custom metrics and dashboards | $1.00 |
| **Total** | | **~$2.76/month** |

*Costs may vary based on region, usage patterns, and current AWS pricing.*

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for detailed implementation guidance
2. **AWS Documentation**: 
   - [IoT Device Management Jobs](https://docs.aws.amazon.com/iot/latest/developerguide/iot-jobs.html)
   - [AWS Signer](https://docs.aws.amazon.com/signer/latest/developerguide/Welcome.html)
   - [Lambda Functions](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html)
3. **AWS Support**: Contact AWS Support for service-specific issues
4. **Community Forums**: AWS Developer Forums and Stack Overflow

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate all IaC templates before submission
3. Update documentation for any new features
4. Follow AWS security best practices
5. Ensure backward compatibility where possible