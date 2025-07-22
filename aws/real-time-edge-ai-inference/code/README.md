# Infrastructure as Code for Real-Time Edge AI Inference with SageMaker Edge

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Edge AI Inference with SageMaker Edge".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation deploys a complete edge AI inference solution including:

- **S3 Bucket**: For storing ML models and artifacts
- **IAM Roles**: Secure token exchange for IoT Greengrass devices
- **IoT Core Resources**: Things, policies, and device certificates
- **EventBridge**: Custom event bus for centralized monitoring
- **CloudWatch**: Log groups for event collection and monitoring
- **IoT Greengrass Components**: ONNX runtime, model components, and inference engine

## Prerequisites

- AWS CLI v2 installed and configured with appropriate permissions
- Administrative permissions for IoT, S3, IAM, EventBridge, and CloudWatch
- Edge device (Raspberry Pi 4, NVIDIA Jetson, or x86_64 Linux) with internet connectivity
- Python 3.8+ installed on edge device
- Estimated cost: $5-10/month for cloud resources + edge device hardware

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name edge-ai-inference-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=edge-ai-demo \
                 ParameterKey=EdgeDeviceName,ParameterValue=my-edge-device \
    --capabilities CAPABILITY_IAM \
    --region us-west-2

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name edge-ai-inference-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name edge-ai-inference-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy EdgeAiInferenceStack \
    --parameters projectName=edge-ai-demo \
    --parameters edgeDeviceName=my-edge-device

# View stack outputs
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

# Deploy the stack
cdk deploy EdgeAiInferenceStack \
    -c project_name=edge-ai-demo \
    -c edge_device_name=my-edge-device

# View stack outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="project_name=edge-ai-demo" \
    -var="edge_device_name=my-edge-device" \
    -var="aws_region=us-west-2"

# Apply the configuration
terraform apply \
    -var="project_name=edge-ai-demo" \
    -var="edge_device_name=my-edge-device" \
    -var="aws_region=us-west-2"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_NAME="edge-ai-demo"
export EDGE_DEVICE_NAME="my-edge-device"
export AWS_REGION="us-west-2"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
echo "Deployment complete. Check AWS console for resource status."
```

## Post-Deployment Configuration

After deploying the infrastructure, you'll need to configure your edge device:

### 1. Download IoT Greengrass Core Software

```bash
# On your edge device, download Greengrass
curl -s https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip -o greengrass-nucleus-latest.zip
unzip greengrass-nucleus-latest.zip -d GreengrassInstaller
```

### 2. Install Greengrass Core

```bash
# Install with automatic provisioning (replace with your stack outputs)
sudo -E java -Droot="/greengrass/v2" -Dlog.store=FILE \
    -jar ./GreengrassInstaller/lib/Greengrass.jar \
    --aws-region $AWS_REGION \
    --thing-name $EDGE_DEVICE_NAME \
    --thing-group-name EdgeAIDevices \
    --tes-role-name GreengrassV2TokenExchangeRole \
    --tes-role-alias-name GreengrassV2TokenExchangeRoleAlias \
    --component-default-user ggc_user:ggc_group \
    --provision true \
    --setup-system-service true
```

### 3. Deploy AI Components

```bash
# The deployment will be automatically triggered after device registration
# Monitor deployment status
sudo /greengrass/v2/bin/greengrass-cli deployment status
```

## Monitoring and Validation

### Check EventBridge Events

```bash
# Monitor inference events in CloudWatch Logs
aws logs tail /aws/events/edge-inference \
    --follow --format short \
    --region $AWS_REGION
```

### Verify IoT Device Status

```bash
# Check device connectivity
aws iot describe-thing \
    --thing-name $EDGE_DEVICE_NAME \
    --region $AWS_REGION
```

### View Component Status

```bash
# On the edge device, check component status
sudo /greengrass/v2/bin/greengrass-cli component list
```

## Customization

### Environment Variables

The following variables can be customized in each implementation:

- **Project Name**: Unique identifier for resource naming
- **Edge Device Name**: IoT Thing name for your edge device
- **AWS Region**: Deployment region for all resources
- **Event Bus Name**: Custom EventBridge bus name
- **Model Bucket Name**: S3 bucket for ML model storage

### CloudFormation Parameters

```yaml
Parameters:
  ProjectName:
    Type: String
    Default: edge-ai-inference
    Description: Project name for resource naming
  
  EdgeDeviceName:
    Type: String
    Default: edge-device-001
    Description: Name for the IoT Core thing
  
  ModelBucketName:
    Type: String
    Default: ""
    Description: S3 bucket name (auto-generated if empty)
```

### Terraform Variables

```hcl
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "edge-ai-inference"
}

variable "edge_device_name" {
  description = "Name for the IoT Core thing"
  type        = string
  default     = "edge-device-001"
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-west-2"
}
```

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name edge-ai-inference-stack \
    --region us-west-2

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name edge-ai-inference-stack
```

### Using CDK TypeScript

```bash
# Navigate to CDK directory
cd cdk-typescript/

# Destroy the stack
cdk destroy EdgeAiInferenceStack
```

### Using CDK Python

```bash
# Navigate to CDK directory and activate virtual environment
cd cdk-python/
source .venv/bin/activate

# Destroy the stack
cdk destroy EdgeAiInferenceStack
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="project_name=edge-ai-demo" \
    -var="edge_device_name=my-edge-device" \
    -var="aws_region=us-west-2"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm all resources are removed
echo "Cleanup complete. Verify in AWS console that all resources are deleted."
```

### Manual Edge Device Cleanup

```bash
# On the edge device, stop and remove Greengrass
sudo systemctl stop greengrass
sudo systemctl disable greengrass
sudo rm -rf /greengrass/
```

## Troubleshooting

### Common Issues

1. **Deployment Failures**
   - Verify AWS CLI is configured with appropriate permissions
   - Check that all prerequisite services are available in your region
   - Ensure unique naming if deploying multiple instances

2. **Edge Device Connection Issues**
   - Verify internet connectivity on edge device
   - Check IAM role permissions for token exchange
   - Validate IoT Core policies and certificates

3. **Component Deployment Failures**
   - Check Greengrass logs: `sudo tail -f /greengrass/v2/logs/greengrass.log`
   - Verify component dependencies are satisfied
   - Ensure sufficient disk space and memory on edge device

4. **Inference Not Working**
   - Check model artifacts are properly uploaded to S3
   - Verify ONNX runtime installation on edge device
   - Monitor EventBridge events for error messages

### Debug Commands

```bash
# Check Greengrass status
sudo systemctl status greengrass

# View component logs
sudo tail -f /greengrass/v2/logs/com.edge.InferenceEngine.log

# Test EventBridge connectivity
aws events put-events \
    --entries Source=test,DetailType=TestEvent,Detail='{"test":"value"}'

# Verify S3 bucket access
aws s3 ls s3://your-model-bucket-name/
```

## Security Considerations

- All IAM roles follow least privilege principle
- IoT device certificates are automatically rotated
- S3 bucket uses versioning and encryption
- EventBridge events are encrypted in transit
- Token exchange eliminates long-lived credentials on devices

## Cost Optimization

- S3 Intelligent Tiering reduces storage costs for infrequently accessed models
- EventBridge charges only for events published
- CloudWatch Logs retention can be adjusted based on requirements
- IoT Greengrass Core software is free; charges apply only for AWS service usage

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation for specific services
3. Verify edge device meets minimum requirements
4. Monitor CloudWatch Logs and EventBridge for error patterns

## Additional Resources

- [AWS IoT Greengrass v2 Documentation](https://docs.aws.amazon.com/greengrass/v2/developerguide/)
- [ONNX Runtime Documentation](https://onnxruntime.ai/docs/)
- [AWS EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [Edge AI Best Practices](https://docs.aws.amazon.com/iot/latest/developerguide/iot-edge-ml.html)