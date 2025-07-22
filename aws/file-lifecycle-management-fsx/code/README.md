# Infrastructure as Code for File Lifecycle Management with FSx

This directory contains Infrastructure as Code (IaC) implementations for the recipe "File Lifecycle Management with FSx".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for FSx, Lambda, CloudWatch, EventBridge, SNS, and S3 services
- Node.js 18+ and npm (for CDK TypeScript)
- Python 3.9+ and pip (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Bash shell environment (for script-based deployment)
- VPC with appropriate subnets and security groups for FSx deployment

## Architecture Overview

This solution deploys:

- **Amazon FSx for OpenZFS**: High-performance file system with intelligent tiering
- **Lambda Functions**: Automated lifecycle policy management, cost reporting, and alert handling
- **EventBridge Rules**: Scheduled triggers for automation functions
- **CloudWatch Alarms**: Performance and utilization monitoring
- **SNS Topic**: Notification system for alerts and reports
- **S3 Bucket**: Storage for cost optimization reports
- **IAM Roles**: Least-privilege security for Lambda execution
- **CloudWatch Dashboard**: Centralized monitoring and visualization

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name fsx-lifecycle-management \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=VpcId,ParameterValue=vpc-xxxxxxxxx \
                 ParameterKey=SubnetId,ParameterValue=subnet-xxxxxxxxx \
                 ParameterKey=NotificationEmail,ParameterValue=admin@company.com \
    --capabilities CAPABILITY_IAM

# Monitor stack creation
aws cloudformation wait stack-create-complete \
    --stack-name fsx-lifecycle-management

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name fsx-lifecycle-management \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure deployment parameters (edit cdk.json or use context)
npx cdk context --set vpcId=vpc-xxxxxxxxx
npx cdk context --set subnetId=subnet-xxxxxxxxx
npx cdk context --set notificationEmail=admin@company.com

# Deploy the infrastructure
npx cdk deploy --require-approval never

# View outputs
npx cdk list
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Install dependencies
pip install -r requirements.txt

# Set environment variables for configuration
export VPC_ID=vpc-xxxxxxxxx
export SUBNET_ID=subnet-xxxxxxxxx
export NOTIFICATION_EMAIL=admin@company.com

# Deploy the infrastructure
cdk deploy --require-approval never

# View stack information
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan deployment
terraform plan

# Apply configuration
terraform apply -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export VPC_ID=vpc-xxxxxxxxx
export SUBNET_ID=subnet-xxxxxxxxx
export NOTIFICATION_EMAIL=admin@company.com

# Deploy infrastructure
./scripts/deploy.sh

# Monitor deployment progress (follow script output)
```

## Configuration Parameters

### Required Parameters

- **VPC ID**: Existing VPC where FSx will be deployed
- **Subnet ID**: Subnet within the VPC for FSx deployment
- **Notification Email**: Email address for SNS notifications

### Optional Parameters

- **FSx Storage Capacity**: Default 64 GiB, minimum for OpenZFS
- **FSx Throughput Capacity**: Default 64 MBps, adjustable based on performance needs
- **Cache Size**: Default 128 GiB read cache size
- **Monitoring Schedule**: Default hourly for lifecycle analysis, daily for cost reports
- **Alarm Thresholds**: Configurable thresholds for performance alerts

## Post-Deployment Configuration

### 1. Test File System Access

```bash
# Get file system DNS name from outputs
FSX_DNS_NAME=$(aws cloudformation describe-stacks \
    --stack-name fsx-lifecycle-management \
    --query 'Stacks[0].Outputs[?OutputKey==`FileSystemDnsName`].OutputValue' \
    --output text)

# Mount the file system (from EC2 instance in same VPC)
sudo mkdir /mnt/fsx
sudo mount -t nfs ${FSX_DNS_NAME}:/ /mnt/fsx
```

### 2. Subscribe to SNS Notifications

```bash
# Get SNS topic ARN from outputs
SNS_TOPIC_ARN=$(aws cloudformation describe-stacks \
    --stack-name fsx-lifecycle-management \
    --query 'Stacks[0].Outputs[?OutputKey==`SnsTopicArn`].OutputValue' \
    --output text)

# Subscribe email to notifications
aws sns subscribe \
    --topic-arn ${SNS_TOPIC_ARN} \
    --protocol email \
    --notification-endpoint your-email@company.com
```

### 3. Access CloudWatch Dashboard

```bash
# Get dashboard URL from outputs or navigate to CloudWatch console
echo "https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:"
```

## Monitoring and Maintenance

### Key Metrics to Monitor

- **FileServerCacheHitRatio**: Should maintain >70% for optimal performance
- **StorageUtilization**: Monitor for capacity planning (alert at 85%)
- **NetworkThroughputUtilization**: Track for performance bottlenecks
- **Lambda Function Errors**: Monitor automation function health

### Cost Reports

Cost optimization reports are automatically generated daily and stored in S3:

```bash
# List generated reports
aws s3 ls s3://fsx-lifecycle-reports-${RANDOM_SUFFIX}/cost-reports/ --recursive

# Download latest report
aws s3 cp s3://fsx-lifecycle-reports-${RANDOM_SUFFIX}/cost-reports/latest-report.csv ./
```

### Manual Function Triggers

```bash
# Test lifecycle policy analysis
aws lambda invoke \
    --function-name fsx-lifecycle-policy \
    --payload '{}' \
    response.json

# Generate cost report on-demand
aws lambda invoke \
    --function-name fsx-cost-reporting \
    --payload '{}' \
    response.json
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack (this will remove all resources)
aws cloudformation delete-stack --stack-name fsx-lifecycle-management

# Wait for stack deletion to complete
aws cloudformation wait stack-delete-complete --stack-name fsx-lifecycle-management
```

### Using CDK (AWS)

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the infrastructure
cdk destroy --force

# Clean up CDK bootstrap (if no longer needed)
# cdk bootstrap --toolkit-stack-name CDKToolkit --destroy
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -auto-approve

# Remove state file if no longer needed
rm terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm all resources are removed
```

## Troubleshooting

### Common Issues

**FSx File System Creation Timeout**
- FSx creation typically takes 10-15 minutes
- Ensure VPC and subnet configuration is correct
- Verify security group allows NFS traffic (port 2049)

**Lambda Function Execution Errors**
- Check CloudWatch Logs for detailed error messages
- Verify IAM permissions for FSx, CloudWatch, and SNS access
- Ensure environment variables are properly configured

**CloudWatch Alarm False Positives**
- Initial metrics may be sparse after deployment
- Allow 1-2 hours for baseline metric collection
- Adjust alarm thresholds based on actual usage patterns

**SNS Notification Issues**
- Confirm email subscription and accept subscription confirmation
- Check spam folder for AWS notification emails
- Verify SNS topic permissions and Lambda integration

### Performance Optimization

**Cache Hit Ratio Below 70%**
- Consider increasing SSD read cache size
- Analyze client access patterns
- Review file system mount options and client configuration

**High Storage Utilization (>85%)**
- Review data retention policies
- Implement file archival processes
- Consider increasing storage capacity

**Network Throughput Bottlenecks**
- Monitor client connection patterns
- Consider increasing throughput capacity
- Implement client-side caching strategies

## Customization

### Environment-Specific Modifications

1. **Multi-AZ Deployment**: Modify subnet configuration for high availability
2. **Cross-Region Backup**: Add AWS Backup integration for disaster recovery
3. **Advanced Monitoring**: Integrate with existing monitoring solutions
4. **Compliance Integration**: Add AWS Config rules for compliance validation
5. **Cost Allocation**: Implement detailed cost allocation tags

### Security Enhancements

1. **VPC Endpoints**: Add VPC endpoints for AWS services to avoid internet traffic
2. **KMS Encryption**: Configure customer-managed KMS keys for encryption
3. **Network ACLs**: Implement additional network-level security controls
4. **IAM Policies**: Further restrict permissions based on principle of least privilege
5. **GuardDuty Integration**: Add threat detection for file system access

## Cost Estimation

**Monthly Cost Breakdown (Approximate)**

- FSx for OpenZFS (64 GiB, 64 MBps): ~$45/month
- Lambda Function Execution: ~$5-10/month
- CloudWatch Metrics and Alarms: ~$5/month
- SNS Notifications: ~$1/month
- S3 Storage (reports): ~$1/month

**Total Estimated Monthly Cost**: ~$57-62/month

*Costs vary by region and actual usage patterns. Use AWS Pricing Calculator for precise estimates.*

## Support

### Documentation References

- [Amazon FSx for OpenZFS User Guide](https://docs.aws.amazon.com/fsx/latest/OpenZFSGuide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon CloudWatch User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)

### Additional Resources

- Original recipe documentation for step-by-step implementation details
- AWS Well-Architected Framework for operational best practices
- FSx performance tuning guidelines for optimization strategies
- AWS cost optimization best practices for ongoing cost management

For issues with this infrastructure code, refer to the original recipe documentation, AWS support resources, or your organization's cloud infrastructure team.