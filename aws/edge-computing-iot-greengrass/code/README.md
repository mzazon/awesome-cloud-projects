# Infrastructure as Code for Edge Computing with IoT Greengrass

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Edge Computing with IoT Greengrass".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - AWS IoT Core (Things, Certificates, Policies)
  - AWS IoT Greengrass V2
  - AWS Lambda
  - AWS IAM (Role creation and policy attachment)
  - AWS CloudWatch Logs
- Ubuntu 18.04+ or Amazon Linux 2 device for Greengrass Core installation
- Basic knowledge of IoT concepts and Lambda functions
- Estimated cost: $5-10 per month for testing environment

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name greengrass-edge-computing \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=CoreDeviceName,ParameterValue=my-greengrass-core \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name greengrass-edge-computing

# Get outputs
aws cloudformation describe-stacks \
    --stack-name greengrass-edge-computing \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters coreDeviceName=my-greengrass-core

# View outputs
cdk ls
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

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters core_device_name=my-greengrass-core

# View outputs
cdk ls
```

### Using Terraform
```bash
# Navigate to Terraform directory
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

# Follow prompts for device name and configuration
```

## Post-Deployment Steps

After deploying the infrastructure, you'll need to complete the Greengrass Core device setup:

### 1. Download Certificates and Keys
```bash
# Get certificate and key files from deployment outputs
# These will be provided as CloudFormation outputs or Terraform outputs

# Example for downloading from S3 (if stored there)
aws s3 cp s3://your-bucket/device.pem.crt /greengrass/v2/
aws s3 cp s3://your-bucket/private.pem.key /greengrass/v2/
```

### 2. Install Greengrass Core Software
```bash
# Download Greengrass Core V2
curl -s https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip \
    -o greengrass-nucleus-latest.zip

# Extract and install
unzip greengrass-nucleus-latest.zip -d GreengrassCore
cd GreengrassCore

# Run installer with your configuration
sudo -E java -Droot="/greengrass/v2" -Dlog.store=FILE \
    -jar ./lib/Greengrass.jar \
    --aws-region us-east-1 \
    --thing-name YourThingName \
    --thing-group-name YourThingGroupName \
    --tes-role-name YourTokenExchangeRole \
    --tes-role-alias-name YourRoleAlias \
    --component-default-user ggc_user:ggc_group \
    --provision true \
    --setup-system-service true
```

### 3. Verify Installation
```bash
# Check Greengrass service status
sudo systemctl status greengrass

# View Greengrass logs
sudo journalctl -u greengrass -f
```

## Configuration Options

### Environment Variables
Set these environment variables before deployment:

```bash
export AWS_REGION=us-east-1
export CORE_DEVICE_NAME=my-greengrass-core
export THING_GROUP_NAME=my-greengrass-group
export LAMBDA_FUNCTION_NAME=edge-processor
```

### Terraform Variables
Customize deployment by modifying `terraform/variables.tf` or creating `terraform.tfvars`:

```hcl
# terraform.tfvars
aws_region = "us-east-1"
core_device_name = "production-greengrass-core"
thing_group_name = "production-greengrass-group"
lambda_memory_size = 256
lambda_timeout = 60
environment = "production"
```

### CloudFormation Parameters
Customize deployment using CloudFormation parameters:

```bash
aws cloudformation create-stack \
    --stack-name greengrass-edge-computing \
    --template-body file://cloudformation.yaml \
    --parameters \
        ParameterKey=CoreDeviceName,ParameterValue=prod-greengrass-core \
        ParameterKey=Environment,ParameterValue=production \
        ParameterKey=LambdaMemorySize,ParameterValue=256 \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM
```

## Monitoring and Troubleshooting

### CloudWatch Logs
Monitor your Greengrass deployment:

```bash
# View Greengrass Core logs
aws logs describe-log-groups --log-group-name-prefix "/aws/greengrass"

# Stream logs
aws logs tail /aws/greengrass/GreengrassSystemComponents --follow
```

### Device Status
Check device connectivity:

```bash
# List core devices
aws greengrassv2 list-core-devices

# Get device status
aws greengrassv2 get-core-device \
    --core-device-thing-name your-thing-name
```

### Lambda Function Logs
Monitor edge Lambda execution:

```bash
# View Lambda logs (if logging to CloudWatch)
aws logs tail /aws/lambda/edge-processor --follow
```

## Security Considerations

### IAM Permissions
The IaC creates IAM roles with minimal required permissions:

- **Greengrass Core Role**: Allows access to IoT Core and required AWS services
- **Lambda Execution Role**: Provides necessary permissions for edge Lambda functions
- **Token Exchange Role**: Enables secure credential exchange for cloud services

### Certificate Management
- Device certificates are created with appropriate policies
- Certificates are automatically rotated based on AWS IoT policies
- Private keys are securely stored on the device

### Network Security
- All communication uses TLS encryption
- Device authentication through X.509 certificates
- Network traffic is restricted to required endpoints

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name greengrass-edge-computing

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name greengrass-edge-computing
```

### Using CDK
```bash
# Destroy the stack
cdk destroy

# Clean up local files
rm -rf node_modules/ cdk.out/
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Clean up state files (optional)
rm -rf .terraform/ terraform.tfstate*
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for resource deletion confirmation
```

### Manual Cleanup (if needed)
If automated cleanup fails, manually remove:

```bash
# Remove Greengrass service (on device)
sudo systemctl stop greengrass
sudo systemctl disable greengrass

# Remove IoT resources
aws iot list-things --query 'things[?contains(thingName, `greengrass`)].thingName' \
    --output text | xargs -I {} aws iot delete-thing --thing-name {}

# Remove Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `edge-processor`)].FunctionName' \
    --output text | xargs -I {} aws lambda delete-function --function-name {}
```

## Troubleshooting

### Common Issues

1. **Device Not Connecting**
   - Verify certificates are properly installed
   - Check network connectivity to AWS IoT endpoints
   - Verify IAM role permissions

2. **Lambda Function Not Executing**
   - Check component deployment status
   - Verify Lambda function permissions
   - Review Greengrass logs for errors

3. **Stream Manager Issues**
   - Verify Stream Manager component is deployed
   - Check stream configuration and permissions
   - Monitor CloudWatch logs for stream errors

### Debug Commands
```bash
# Check Greengrass status
sudo /greengrass/v2/bin/greengrass-cli component list

# View component logs
sudo /greengrass/v2/bin/greengrass-cli logs get --log-file greengrass.log

# Test device connectivity
aws iot test-connectivity --thing-name your-thing-name
```

## Customization

### Adding Custom Components
To add custom Greengrass components:

1. Create component recipe files
2. Update deployment configurations
3. Modify IAM permissions as needed
4. Update monitoring and logging configurations

### Scaling Considerations
For production deployments:

- Use Thing Groups for fleet management
- Implement automated device provisioning
- Configure appropriate resource limits
- Set up centralized logging and monitoring
- Implement device health checks

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review AWS IoT Greengrass V2 documentation
3. Consult AWS IoT Core troubleshooting guides
4. Review CloudWatch logs for error details

## Related Resources

- [AWS IoT Greengrass V2 Documentation](https://docs.aws.amazon.com/greengrass/v2/developerguide/)
- [AWS IoT Core Documentation](https://docs.aws.amazon.com/iot/latest/developerguide/)
- [AWS Lambda at the Edge](https://docs.aws.amazon.com/lambda/latest/dg/lambda-edge.html)
- [IoT Device Management](https://docs.aws.amazon.com/iot/latest/developerguide/device-management.html)