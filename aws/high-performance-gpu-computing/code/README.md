# Infrastructure as Code for High-Performance GPU Computing Workloads

This directory contains Infrastructure as Code (IaC) implementations for the recipe "High-Performance GPU Computing Workloads".

## Overview

This infrastructure deploys GPU-accelerated computing resources using EC2 P4 instances (NVIDIA A100 GPUs) for machine learning training and G4 instances (NVIDIA T4 GPUs) for inference and graphics workloads. The solution includes automated GPU driver installation, comprehensive monitoring, cost optimization features, and spot fleet configurations for cost-effective GPU computing.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

- **EC2 P4 Instances**: High-performance ML training with NVIDIA A100 GPUs
- **EC2 G4 Instances**: Cost-effective inference with NVIDIA T4 GPUs
- **Spot Fleet**: Cost-optimized GPU instance management
- **CloudWatch Monitoring**: GPU performance metrics and dashboards
- **Systems Manager**: Secure instance management without SSH
- **SNS Notifications**: Automated alerts for performance and cost optimization
- **IAM Roles**: Secure access with least privilege principles
- **Security Groups**: Network security for GPU workloads

## Prerequisites

### General Requirements
- AWS CLI v2 installed and configured
- Appropriate AWS permissions for EC2, CloudWatch, Systems Manager, IAM, and SNS
- Understanding of GPU computing concepts and CUDA programming
- Knowledge of machine learning frameworks (PyTorch, TensorFlow) or HPC applications

### Estimated Costs
- **P4 instances**: $50-200 during testing (varies by region and usage)
- **G4 instances**: $5-20 during testing (varies by region and usage)
- **CloudWatch**: ~$1-5 for custom metrics and dashboards
- **Other services**: <$1 for SNS, IAM, and Security Groups

> **⚠️ Cost Warning**: GPU instances are significantly more expensive than standard instances. P4d.24xlarge can cost $32+ per hour. Always terminate resources when not in use.

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions
- Understanding of CloudFormation templates

#### CDK TypeScript
- Node.js 18.x or later
- AWS CDK CLI (`npm install -g aws-cdk`)
- TypeScript knowledge

#### CDK Python
- Python 3.8 or later
- AWS CDK CLI (`pip install aws-cdk-lib`)
- pip package manager

#### Terraform
- Terraform 1.0 or later
- AWS provider for Terraform
- Basic Terraform knowledge

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name gpu-workload-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=KeyPairName,ParameterValue=your-key-pair \
                 ParameterKey=NotificationEmail,ParameterValue=your-email@domain.com \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name gpu-workload-stack \
    --query "Stacks[0].StackStatus"

# Get outputs
aws cloudformation describe-stacks \
    --stack-name gpu-workload-stack \
    --query "Stacks[0].Outputs"
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --parameters notificationEmail=your-email@domain.com

# View outputs
cdk ls
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

# Deploy the infrastructure
cdk deploy --parameters notification-email=your-email@domain.com

# View outputs
cdk ls
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="notification_email=your-email@domain.com"

# Apply the configuration
terraform apply -var="notification_email=your-email@domain.com"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL="your-email@domain.com"
export AWS_REGION="us-east-1"  # or your preferred region

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for additional configuration options
```

## Post-Deployment Steps

### 1. Connect to GPU Instances
```bash
# Get instance details from outputs
P4_INSTANCE_ID=$(aws cloudformation describe-stacks \
    --stack-name gpu-workload-stack \
    --query "Stacks[0].Outputs[?OutputKey=='P4InstanceId'].OutputValue" \
    --output text)

P4_PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids $P4_INSTANCE_ID \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)

# SSH to P4 instance (use your key pair)
ssh -i your-key-pair.pem ubuntu@$P4_PUBLIC_IP
```

### 2. Verify GPU Setup
```bash
# Check GPU status
nvidia-smi

# Test CUDA availability in Python
python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"

# Run GPU test workload
python3 -c "
import torch
if torch.cuda.is_available():
    x = torch.randn(1000, 1000, device='cuda')
    y = torch.matmul(x, x)
    print(f'GPU computation successful. Result shape: {y.shape}')
"
```

### 3. Access Monitoring Dashboard
```bash
# Get CloudWatch dashboard URL from outputs
DASHBOARD_URL=$(aws cloudformation describe-stacks \
    --stack-name gpu-workload-stack \
    --query "Stacks[0].Outputs[?OutputKey=='MonitoringDashboard'].OutputValue" \
    --output text)

echo "View GPU monitoring at: $DASHBOARD_URL"
```

### 4. Confirm SNS Subscription
Check your email and confirm the SNS subscription to receive GPU monitoring alerts.

## Customization

### Key Parameters/Variables

| Parameter | Description | Default | CloudFormation | CDK | Terraform |
|-----------|-------------|---------|----------------|-----|-----------|
| Instance Types | GPU instance types to deploy | p4d.24xlarge, g4dn.xlarge | ✅ | ✅ | ✅ |
| Notification Email | Email for monitoring alerts | Required | ✅ | ✅ | ✅ |
| Spot Price | Maximum spot price for G4 instances | $0.50 | ✅ | ✅ | ✅ |
| Key Pair | EC2 key pair for SSH access | Required | ✅ | ✅ | ✅ |
| VPC/Subnet | Network configuration | Default VPC | ✅ | ✅ | ✅ |
| Monitoring Interval | CloudWatch metrics interval | 60 seconds | ✅ | ✅ | ✅ |

### Advanced Configuration

#### Enable Multi-AZ Deployment
```bash
# For Terraform
terraform apply -var="enable_multi_az=true" -var="availability_zones=[\"us-east-1a\",\"us-east-1b\"]"
```

#### Customize GPU Instance Counts
```bash
# For CDK
cdk deploy --parameters p4InstanceCount=2 --parameters g4InstanceCount=4
```

#### Enable Enhanced Monitoring
```bash
# For CloudFormation
aws cloudformation update-stack \
    --stack-name gpu-workload-stack \
    --use-previous-template \
    --parameters ParameterKey=EnableDetailedMonitoring,ParameterValue=true
```

## Monitoring and Operations

### GPU Performance Metrics
The deployment automatically configures CloudWatch monitoring for:
- GPU utilization percentage
- GPU memory utilization
- GPU temperature
- Power consumption
- Instance CPU and memory metrics

### Cost Optimization Features
- Automated low utilization detection
- Spot instance integration for G4 instances
- CloudWatch alarms for cost management
- Resource tagging for cost allocation

### Security Features
- Dedicated security groups with minimal required access
- IAM roles with least privilege principles
- Systems Manager integration for secure management
- VPC-based network isolation

## Troubleshooting

### Common Issues

#### 1. P4 Instance Launch Failure
```bash
# Check for capacity issues
aws ec2 describe-instance-type-offerings \
    --location-type availability-zone \
    --filters Name=instance-type,Values=p4d.24xlarge

# Try different instance types
terraform apply -var="p4_instance_type=p4d.xlarge"
```

#### 2. GPU Driver Installation Issues
```bash
# Check cloud-init logs
ssh -i your-key.pem ubuntu@instance-ip "sudo tail -f /var/log/cloud-init-output.log"

# Manually install drivers if needed
ssh -i your-key.pem ubuntu@instance-ip "sudo nvidia-smi"
```

#### 3. CloudWatch Metrics Not Appearing
```bash
# Check CloudWatch agent status
ssh -i your-key.pem ubuntu@instance-ip "sudo systemctl status amazon-cloudwatch-agent"

# Restart agent
ssh -i your-key.pem ubuntu@instance-ip "sudo systemctl restart amazon-cloudwatch-agent"
```

#### 4. Spot Instance Interruptions
```bash
# Check spot instance status
aws ec2 describe-spot-instance-requests

# Enable spot instance hibernation (if supported)
terraform apply -var="enable_hibernation=true"
```

### Log Locations
- **Cloud-init logs**: `/var/log/cloud-init-output.log`
- **CloudWatch agent logs**: `/opt/aws/amazon-cloudwatch-agent/logs/`
- **GPU driver logs**: `/var/log/nvidia-installer.log`
- **System logs**: `/var/log/syslog`

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name gpu-workload-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name gpu-workload-stack \
    --query "Stacks[0].StackStatus"
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy
```

### Using CDK Python
```bash
cd cdk-python/
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

### Manual Cleanup Verification
```bash
# Verify all EC2 instances are terminated
aws ec2 describe-instances \
    --filters "Name=tag:Purpose,Values=GPU-Workload" \
    --query "Reservations[*].Instances[*].[InstanceId,State.Name]"

# Check for any remaining spot fleet requests
aws ec2 describe-spot-fleet-requests \
    --query "SpotFleetConfigs[?SpotFleetRequestState!='cancelled_terminating' && SpotFleetRequestState!='cancelled_running']"

# Verify CloudWatch resources are cleaned up
aws cloudwatch list-dashboards \
    --dashboard-name-prefix "GPU-Workload"
```

## Performance Optimization

### GPU Workload Optimization
1. **Memory Management**: Monitor GPU memory utilization to optimize batch sizes
2. **Multi-GPU Training**: Utilize all 8 A100 GPUs on P4 instances for distributed training
3. **Mixed Precision**: Enable FP16 training to maximize performance
4. **Data Pipeline**: Optimize data loading to prevent GPU idle time

### Cost Optimization Strategies
1. **Spot Instances**: Use G4 spot instances for non-critical workloads
2. **Scheduled Scaling**: Implement time-based scaling for predictable workloads
3. **Hibernation**: Enable hibernation for development instances
4. **Reserved Instances**: Consider reserved instances for consistent long-term workloads

## Integration Examples

### SageMaker Integration
```python
# Example: Trigger training job on P4 instance
import boto3

ec2 = boto3.client('ec2')
instances = ec2.describe_instances(
    Filters=[{'Name': 'tag:Purpose', 'Values': ['GPU-Workload']}]
)
# Use instances for distributed training
```

### MLflow Integration
```python
# Example: Track experiments with GPU metrics
import mlflow
import torch

mlflow.log_param("gpu_count", torch.cuda.device_count())
mlflow.log_param("gpu_type", torch.cuda.get_device_name())
```

## Support and Additional Resources

### AWS Documentation
- [EC2 P4 Instances User Guide](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/accelerated-computing-instances.html)
- [EC2 G4 Instances User Guide](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/accelerated-computing-instances.html)
- [CloudWatch Custom Metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/publishingMetrics.html)

### Best Practices
- [AWS GPU Computing Best Practices](https://aws.amazon.com/ec2/instance-types/p4/)
- [Cost Optimization for GPU Workloads](https://aws.amazon.com/blogs/machine-learning/optimize-gpu-utilization-for-machine-learning-workloads/)
- [Security Best Practices for EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security.html)

### Community Resources
- [AWS Machine Learning Blog](https://aws.amazon.com/blogs/machine-learning/)
- [NVIDIA Deep Learning Documentation](https://docs.nvidia.com/deeplearning/)
- [PyTorch GPU Documentation](https://pytorch.org/docs/stable/cuda.html)

For issues with this infrastructure code, refer to the original recipe documentation or consult the AWS support resources above.