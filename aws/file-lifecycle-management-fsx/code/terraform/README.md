# FSx Intelligent Tiering with Lambda Lifecycle Management - Terraform

This Terraform configuration deploys an automated file lifecycle management system using Amazon FSx for OpenZFS with Intelligent-Tiering, Lambda functions for monitoring and cost optimization, and comprehensive CloudWatch monitoring.

## Architecture Overview

The solution includes:

- **Amazon FSx for OpenZFS** with Intelligent-Tiering for automatic cost optimization
- **Lambda Functions** for lifecycle policy management, cost reporting, and alert handling
- **EventBridge Rules** for automated scheduling of lifecycle checks and reporting
- **CloudWatch Alarms** for monitoring storage utilization, cache performance, and system health
- **SNS Topics** for intelligent alerting and notifications
- **S3 Bucket** for storing cost optimization reports
- **KMS Keys** for encryption at rest across all services
- **CloudWatch Dashboard** for comprehensive monitoring and visualization

## Features

### Intelligent File Lifecycle Management
- Automated monitoring of FSx access patterns and performance metrics
- Intelligent recommendations for storage optimization
- Cost analysis and reporting with detailed recommendations
- Automated alerting with contextual analysis and remediation suggestions

### Cost Optimization
- FSx Intelligent-Tiering for automatic storage cost optimization (up to 85% savings)
- S3 Intelligent-Tiering for report storage optimization
- ARM64 Lambda functions for improved price-performance
- Comprehensive cost tracking and optimization recommendations

### Security & Compliance
- KMS encryption for all data at rest (FSx, S3, CloudWatch Logs, SNS)
- Least privilege IAM roles and policies
- VPC security groups with minimal required access
- Comprehensive audit logging and monitoring

### Monitoring & Alerting
- Real-time CloudWatch alarms for critical metrics
- Intelligent alert processing with contextual recommendations
- Automated cost reporting and trend analysis
- CloudWatch dashboard for centralized monitoring

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.5.0 installed
- Appropriate AWS permissions for creating:
  - FSx file systems
  - Lambda functions
  - IAM roles and policies
  - CloudWatch resources
  - S3 buckets
  - KMS keys
  - VPC security groups

## Quick Start

1. **Clone and Navigate**
   ```bash
   cd aws/automated-file-lifecycle-management-fsx-intelligent-tiering-lambda/code/terraform/
   ```

2. **Configure Variables**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

3. **Initialize and Deploy**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Verify Deployment**
   ```bash
   # Check FSx file system status
   aws fsx describe-file-systems --file-system-ids $(terraform output -raw fsx_file_system_id)
   
   # Test Lambda functions
   aws lambda invoke --function-name $(terraform output -raw lifecycle_policy_function_name) --payload '{}' response.json
   ```

## Configuration

### Required Variables

- `project_name`: Unique name for your project resources
- `environment`: Environment name (dev/staging/production)
- `aws_region`: AWS region for deployment

### Key Configuration Options

- `fsx_storage_capacity`: FSx storage size in GiB (minimum 64)
- `fsx_throughput_capacity`: FSx throughput in MBps (160, 320, 640, etc.)
- `enable_intelligent_tiering`: Enable FSx Intelligent-Tiering (recommended)
- `alert_email_addresses`: Email addresses for notifications
- `lambda_architecture`: ARM64 recommended for cost efficiency

### Networking

If you don't specify `vpc_id` and `subnet_id`, the configuration will use your default VPC and subnet. For production deployments, specify dedicated VPC and private subnets.

## Usage

### Mounting the FSx File System

Use the NFS mount command from the Terraform outputs:

```bash
# Get mount command
terraform output nfs_mount_command

# Example output:
# sudo mount -t nfs -o nfsvers=4.1 fs-01234567890abcdef.fsx.us-east-1.amazonaws.com:/ /mnt/fsx
```

### Monitoring and Alerts

1. **CloudWatch Dashboard**: Access via the URL in Terraform outputs
2. **Cost Reports**: Generated automatically and stored in S3
3. **Email Alerts**: Configure email addresses in `alert_email_addresses`

### Testing the Solution

```bash
# Test lifecycle policy function
aws lambda invoke \
  --function-name $(terraform output -raw lifecycle_policy_function_name) \
  --payload '{}' \
  response.json && cat response.json

# Test cost reporting function
aws lambda invoke \
  --function-name $(terraform output -raw cost_reporting_function_name) \
  --payload '{}' \
  response.json && cat response.json

# View generated reports
aws s3 ls s3://$(terraform output -raw s3_reports_bucket_name)/cost-reports/ --recursive
```

## Cost Estimation

### Monthly Cost Components

1. **FSx for OpenZFS**:
   - 64 GiB Intelligent-Tiering: ~$15-50/month
   - 160 MBps throughput: ~$48/month
   - Backups: ~$3-5/month (varies by retention)

2. **Lambda Functions**:
   - Execution costs: <$5/month (typical usage)
   - ARM64 architecture provides 20% cost savings

3. **Supporting Services**:
   - CloudWatch: ~$5-15/month (depends on retention)
   - S3: ~$1-5/month (for reports)
   - SNS/KMS: <$5/month

**Total Estimated Cost**: $75-130/month for typical usage

### Cost Optimization Features

- **Intelligent-Tiering**: Up to 85% storage cost savings
- **ARM64 Lambda**: 20% compute cost savings  
- **S3 Intelligent-Tiering**: Automatic storage class optimization
- **Automated Cost Reports**: Identify additional optimization opportunities

## Security Considerations

### Encryption
- All data encrypted at rest using KMS keys
- Separate KMS keys for each service (FSx, S3, CloudWatch, SNS)
- Automatic key rotation enabled

### Access Control
- Least privilege IAM roles and policies
- VPC security groups restrict network access
- SNS topic policies prevent unauthorized publishing

### Monitoring
- CloudTrail integration for API audit logging
- CloudWatch alarms for security-relevant metrics
- Comprehensive logging across all components

## Maintenance

### Regular Tasks
- Review cost optimization reports (generated daily)
- Monitor CloudWatch dashboard for performance trends
- Update Lambda runtime versions as needed
- Review and rotate KMS keys annually

### Scaling
- FSx storage and throughput can be modified after deployment
- Lambda functions automatically scale with demand
- CloudWatch log retention can be adjusted for cost optimization

## Troubleshooting

### Common Issues

1. **FSx Creation Timeout**
   - FSx deployment can take 10-15 minutes
   - Check VPC and subnet configuration
   - Verify security group rules

2. **Lambda Permission Errors**
   - Check IAM role policies
   - Verify KMS key permissions
   - Review VPC configuration for Lambda functions

3. **SNS Notification Issues**
   - Confirm email subscriptions
   - Check SNS topic policies
   - Verify CloudWatch alarm configurations

### Debugging Commands

```bash
# Check FSx status
aws fsx describe-file-systems --file-system-ids $(terraform output -raw fsx_file_system_id)

# View Lambda logs
aws logs tail /aws/lambda/$(terraform output -raw lifecycle_policy_function_name) --follow

# Check alarm states
aws cloudwatch describe-alarms --alarm-names $(terraform output -raw storage_utilization_alarm_name)
```

## Cleanup

To destroy all resources:

```bash
# Destroy infrastructure
terraform destroy

# Verify S3 bucket is empty (may need manual cleanup)
aws s3 ls s3://$(terraform output -raw s3_reports_bucket_name) --recursive
```

**Note**: Some resources may require manual cleanup:
- S3 bucket contents (if force_destroy = false)
- CloudWatch log streams
- SNS subscriptions (email confirmations)

## Support

For issues with this Terraform configuration:

1. Check the [AWS FSx documentation](https://docs.aws.amazon.com/fsx/)
2. Review [Terraform AWS provider documentation](https://registry.terraform.io/providers/hashicorp/aws/latest)
3. Check CloudWatch logs for detailed error information
4. Verify AWS service quotas and limits

## Advanced Configuration

### Multi-AZ Deployment
Currently configured for Single-AZ deployment with Intelligent-Tiering. For Multi-AZ requirements, modify the `deployment_type` variable (note: Intelligent-Tiering not available for Multi-AZ).

### Custom Monitoring
Additional CloudWatch metrics can be added by modifying the Lambda functions and dashboard configuration.

### Integration with Existing Infrastructure
The configuration can be adapted to use existing VPC, subnets, and KMS keys by modifying the data sources and variable configurations.