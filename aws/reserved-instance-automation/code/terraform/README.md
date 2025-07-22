# Reserved Instance Management Automation - Terraform

This Terraform configuration deploys a comprehensive Reserved Instance (RI) management automation system on AWS. The solution provides automated RI utilization monitoring, purchase recommendations, and expiration tracking to optimize AWS costs.

## Architecture Overview

The infrastructure includes:

- **Lambda Functions**: Three Python-based functions for RI analysis, recommendations, and monitoring
- **EventBridge Rules**: Automated scheduling for regular RI analysis
- **S3 Bucket**: Secure storage for RI reports and analysis data
- **DynamoDB Table**: Tracking of RI inventory and historical data
- **SNS Topic**: Notifications for alerts and recommendations
- **CloudWatch**: Logging and monitoring for the entire system
- **IAM Roles**: Least-privilege access for all components

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.0 installed
3. **AWS Account** with the following permissions:
   - Cost Explorer API access
   - Lambda, S3, DynamoDB, SNS, EventBridge, IAM permissions
   - EC2 and RDS read permissions for RI data
4. **Cost Explorer** enabled in your AWS account
5. **Reserved Instances** in your account (for meaningful analysis)

## Cost Considerations

Estimated monthly costs for this solution:

- Lambda executions: $2-5
- DynamoDB (pay-per-request): $1-3
- S3 storage: $1-5
- SNS notifications: $0.50-2
- CloudWatch logs: $0.50-2
- Cost Explorer API: $10-50 (first 1,000 requests free, then $0.01/request)

**Total estimated: $15-67 per month** (varies based on usage and data volume)

## Quick Start

1. **Clone and Navigate**:
   ```bash
   cd aws/reserved-instance-management-automation/code/terraform/
   ```

2. **Configure Variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Plan Deployment**:
   ```bash
   terraform plan
   ```

5. **Deploy Infrastructure**:
   ```bash
   terraform apply
   ```

6. **Confirm SNS Subscription**:
   - Check your email for SNS subscription confirmation
   - Click the confirmation link

## Configuration

### Required Variables

- `aws_region`: AWS region for deployment
- `notification_email`: Email for alerts and notifications

### Key Optional Variables

- `utilization_threshold`: RI utilization percentage threshold for alerts (default: 80%)
- `expiration_warning_days`: Days before expiration to send warnings (default: 90)
- `critical_expiration_days`: Days before expiration for critical alerts (default: 30)
- `slack_webhook_url`: Optional Slack webhook for notifications

### Scheduling Configuration

The system uses EventBridge cron expressions for scheduling:

- **Daily Analysis**: `cron(0 8 * * ? *)` - Daily at 8 AM UTC
- **Weekly Recommendations**: `cron(0 9 ? * MON *)` - Monday at 9 AM UTC
- **Weekly Monitoring**: `cron(0 10 ? * MON *)` - Monday at 10 AM UTC

Customize these in your `terraform.tfvars` file.

## Usage

### Testing Lambda Functions

After deployment, test the functions manually:

```bash
# Test utilization analysis
aws lambda invoke \
  --function-name $(terraform output -raw ri_utilization_function_name) \
  --payload '{}' response.json

# Test recommendations
aws lambda invoke \
  --function-name $(terraform output -raw ri_recommendations_function_name) \
  --payload '{}' response.json

# Test monitoring
aws lambda invoke \
  --function-name $(terraform output -raw ri_monitoring_function_name) \
  --payload '{}' response.json
```

### Viewing Reports

Access generated reports in S3:

```bash
# List reports
aws s3 ls s3://$(terraform output -raw s3_bucket_name)/ --recursive

# Download a report
aws s3 cp s3://$(terraform output -raw s3_bucket_name)/ri-utilization-reports/YYYY-MM-DD_analysis.json ./
```

### Monitoring RI Data

Check DynamoDB for RI tracking data:

```bash
aws dynamodb scan \
  --table-name $(terraform output -raw dynamodb_table_name) \
  --max-items 10
```

## Outputs

The Terraform configuration provides comprehensive outputs including:

- Resource names and ARNs
- Usage instructions and CLI commands
- Configuration summaries
- Cost estimates
- Security features implemented
- Recommended next steps

View all outputs:

```bash
terraform output
```

## Security Features

This solution implements AWS security best practices:

- **S3 Encryption**: AES256 server-side encryption
- **Public Access Blocked**: All S3 public access blocked
- **DynamoDB Encryption**: Server-side encryption enabled
- **SNS Encryption**: KMS encryption with AWS managed keys
- **IAM Least Privilege**: Minimal required permissions
- **VPC Endpoints**: Consider adding for enhanced security

## Customization

### Adjusting Thresholds

Modify thresholds in `terraform.tfvars`:

```hcl
utilization_threshold = 75      # Alert at 75% utilization
expiration_warning_days = 60    # 60-day warning
critical_expiration_days = 15   # 15-day critical alert
```

### Adding Services

To monitor additional AWS services:

1. Modify Lambda functions to include new services
2. Update IAM policies for additional permissions
3. Redeploy with `terraform apply`

### Slack Integration

Add Slack notifications by setting the webhook URL:

```hcl
slack_webhook_url = "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
```

## Troubleshooting

### Common Issues

1. **Cost Explorer API Errors**:
   - Ensure Cost Explorer is enabled in AWS Console
   - Verify billing permissions

2. **Lambda Timeout Errors**:
   - Increase `lambda_timeout` variable
   - Check CloudWatch logs for specific errors

3. **Missing RI Data**:
   - Ensure you have active Reserved Instances
   - Verify EC2/RDS permissions

4. **SNS Subscription Issues**:
   - Check email for confirmation message
   - Verify email address in configuration

### Debugging

Check CloudWatch logs:

```bash
# View recent logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/ri-management"

# Get specific log events
aws logs get-log-events \
  --log-group-name "/aws/lambda/$(terraform output -raw ri_utilization_function_name)" \
  --log-stream-name "$(aws logs describe-log-streams \
    --log-group-name "/aws/lambda/$(terraform output -raw ri_utilization_function_name)" \
    --order-by LastEventTime --descending --max-items 1 \
    --query 'logStreams[0].logStreamName' --output text)"
```

## Cleanup

To remove all resources:

```bash
terraform destroy
```

**Warning**: This will delete all RI tracking data and reports. Consider backing up important data before cleanup.

## Advanced Configuration

### Remote State Management

For production use, configure remote state:

```hcl
terraform {
  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "ri-management/terraform.tfstate"
    region = "us-east-1"
  }
}
```

### Multi-Account Setup

For multi-account RI management:

1. Deploy in a central account
2. Create cross-account IAM roles
3. Modify Lambda functions for cross-account access
4. Update permissions accordingly

### CI/CD Integration

For automated deployments:

1. Store `terraform.tfvars` in secure parameter store
2. Use GitHub Actions or similar for deployment
3. Implement proper state locking
4. Add approval workflows for production

## Support and Maintenance

### Regular Maintenance

- Review and update thresholds quarterly
- Monitor CloudWatch alarms and logs
- Update Lambda function code as needed
- Review Cost Explorer API usage and costs

### Updates

When AWS services change:

1. Update Lambda function code
2. Modify IAM permissions if needed
3. Test thoroughly in non-production
4. Apply changes with `terraform apply`

## Contributing

To contribute improvements:

1. Test changes thoroughly
2. Update documentation
3. Follow AWS security best practices
4. Validate with `terraform plan` and `terraform validate`

## License

This infrastructure code is provided as-is for the Reserved Instance Management Automation recipe. Refer to the original recipe documentation for complete context and usage guidance.