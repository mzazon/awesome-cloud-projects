# Terraform Infrastructure for Resource Groups Automated Resource Management

This Terraform configuration deploys a complete automated resource management system using AWS Resource Groups, Systems Manager, CloudWatch, and SNS. It provides centralized visibility, automated compliance enforcement, and cost optimization through intelligent resource grouping and monitoring.

## Architecture Overview

The infrastructure includes:

- **Resource Groups**: Tag-based organization for AWS resources
- **Systems Manager**: Automation documents for maintenance and tagging
- **CloudWatch**: Monitoring dashboard and alarms
- **SNS**: Notification system for alerts
- **AWS Budgets**: Cost tracking and budget alerts
- **Cost Anomaly Detection**: Proactive cost monitoring
- **EventBridge**: Automated resource tagging workflows

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.5
- Appropriate AWS permissions for:
  - Resource Groups
  - Systems Manager
  - CloudWatch
  - SNS
  - IAM
  - AWS Budgets
  - Cost Explorer
  - EventBridge

## Quick Start

### 1. Initialize Terraform

```bash
cd terraform/
terraform init
```

### 2. Review and Customize Variables

Copy the example variables file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your specific values:

```hcl
# Basic Configuration
aws_region = "us-east-1"
environment = "production"
application = "web-app"
deployed_by = "your-name"

# Notification Configuration
notification_email = "admin@yourcompany.com"

# Monitoring Configuration
cpu_alarm_threshold = 80
monthly_budget_limit = 100

# Optional: Additional tags
additional_tags = {
  Team        = "DevOps"
  CostCenter  = "Engineering"
  Owner       = "platform-team"
}
```

### 3. Plan the Deployment

```bash
terraform plan
```

### 4. Deploy the Infrastructure

```bash
terraform apply
```

## Configuration Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for resources | `us-east-1` | No |
| `environment` | Environment name | `production` | No |
| `application` | Application name | `web-app` | No |
| `notification_email` | Email for notifications | `""` | No |
| `monthly_budget_limit` | Budget limit in USD | `100` | No |
| `cpu_alarm_threshold` | CPU alarm threshold % | `80` | No |
| `enable_automation_documents` | Enable SSM documents | `true` | No |
| `enable_cost_anomaly_detection` | Enable cost anomaly detection | `true` | No |

## Resource Organization

The solution organizes resources using these tags:
- `Environment`: Specified environment (e.g., production, staging)
- `Application`: Specified application name
- `Purpose`: Always set to "resource-management"
- `ManagedBy`: Always set to "terraform"

## Post-Deployment Setup

### 1. Confirm Email Subscription

Check your email for an SNS subscription confirmation and click the confirm link.

### 2. Tag Existing Resources

Tag your existing AWS resources with the appropriate Environment and Application tags:

```bash
# Example: Tag an EC2 instance
aws ec2 create-tags \
    --resources i-1234567890abcdef0 \
    --tags Key=Environment,Value=production Key=Application,Value=web-app

# Example: Tag an S3 bucket
aws s3api put-bucket-tagging \
    --bucket my-bucket \
    --tagging 'TagSet=[{Key=Environment,Value=production},{Key=Application,Value=web-app}]'
```

### 3. View the CloudWatch Dashboard

Access your dashboard using the URL provided in the Terraform outputs:

```bash
terraform output cloudwatch_dashboard_url
```

### 4. Test Automation

Test the Systems Manager automation:

```bash
# Get the document name from output
DOCUMENT_NAME=$(terraform output -raw maintenance_document_name)
RESOURCE_GROUP=$(terraform output -raw resource_group_name)

# Execute automation
aws ssm start-automation-execution \
    --document-name $DOCUMENT_NAME \
    --parameters "ResourceGroupName=$RESOURCE_GROUP"
```

## Monitoring and Alerts

### CloudWatch Alarms

The system includes two primary alarms:
1. **CPU Utilization**: Triggers when CPU exceeds threshold
2. **Health Check**: Triggers on EC2 status check failures

### Cost Monitoring

- **AWS Budget**: Monthly cost tracking with threshold alerts
- **Cost Anomaly Detection**: Automatic detection of unusual spending patterns

### Dashboard Metrics

The CloudWatch dashboard displays:
- Resource group CPU utilization
- Estimated monthly charges
- Systems Manager automation logs

## Automation Features

### Systems Manager Documents

1. **Resource Group Maintenance**: Performs maintenance tasks on grouped resources
2. **Automated Resource Tagging**: Applies consistent tags to resources

### EventBridge Integration

Automatically tags new resources when they're created in monitored services:
- EC2 instances
- S3 buckets
- RDS databases

## Cost Estimation

Expected monthly costs:
- SNS Topic: ~$0.50 (per 1M requests)
- CloudWatch Alarms: $0.40 (2 alarms × $0.20)
- CloudWatch Dashboard: $3.00
- CloudWatch Logs: ~$0.50 per GB
- AWS Budget: Free (first 2 budgets)
- Systems Manager: $0.0025 per automation step

**Total estimated monthly cost: $4.00-$6.00** (excluding data transfer and usage-based charges)

## Validation Commands

After deployment, validate the infrastructure:

```bash
# Check resource group
aws resource-groups get-group --group-name $(terraform output -raw resource_group_name)

# List resources in group
aws resource-groups list-group-resources --group-name $(terraform output -raw resource_group_name)

# Check alarm status
aws cloudwatch describe-alarms --alarm-names $(terraform output -raw cpu_alarm_name)

# View budget information
aws budgets describe-budget \
    --account-id $(aws sts get-caller-identity --query Account --output text) \
    --budget-name $(terraform output -raw budget_name)
```

## Troubleshooting

### Common Issues

1. **Email notifications not received**:
   - Check spam/junk folder
   - Verify email subscription confirmation
   - Check SNS topic permissions

2. **Resource group shows no resources**:
   - Ensure resources are tagged correctly
   - Wait 5-10 minutes for AWS to discover tagged resources
   - Verify resource types are supported

3. **Budget alerts not working**:
   - Confirm SNS topic policy allows budgets service
   - Check that cost allocation tags are properly applied
   - Allow 24-48 hours for cost data to appear

4. **Automation documents failing**:
   - Verify IAM role permissions
   - Check CloudWatch logs in `/aws/ssm/automation`
   - Ensure resources exist in the specified region

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete all monitoring, automation, and notification resources. Ensure you want to remove all infrastructure before proceeding.

## Security Considerations

- IAM roles use least-privilege principle
- SNS topics have restricted publish permissions
- All resources are tagged for proper governance
- Cost anomaly detection helps identify security incidents through unusual spending

## Support and Documentation

For more information, refer to:
- [AWS Resource Groups Documentation](https://docs.aws.amazon.com/ARG/latest/userguide/)
- [AWS Systems Manager Automation](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-automation.html)
- [CloudWatch Documentation](https://docs.aws.amazon.com/cloudwatch/)
- [AWS Budgets Documentation](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/budgets-managing-costs.html)