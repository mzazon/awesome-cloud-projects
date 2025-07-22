# Infrastructure as Code for AWS Cost Optimization Hub and Budgets

This directory contains Terraform Infrastructure as Code (IaC) for implementing automated cost optimization workflows using AWS Cost Optimization Hub, AWS Budgets, Cost Anomaly Detection, and Lambda-based automation.

## Architecture Overview

This solution deploys:

- **Cost Optimization Hub**: Centralized cost optimization recommendations
- **AWS Budgets**: Monthly cost, EC2 usage, and RI utilization budgets
- **Cost Anomaly Detection**: ML-powered anomaly detection for monitored services
- **SNS Notifications**: Real-time alerts for budget and anomaly events
- **Lambda Automation**: Automated processing of cost optimization recommendations
- **IAM Roles and Policies**: Secure access controls for all components

## Prerequisites

1. **AWS CLI**: Installed and configured with appropriate credentials
2. **Terraform**: Version >= 1.0
3. **AWS Account**: With sufficient permissions for:
   - Cost Management and Billing services
   - IAM roles and policies
   - Lambda functions
   - SNS topics and subscriptions
   - CloudWatch logs
4. **Email Address**: Valid email for receiving budget notifications

## Required Permissions

Your AWS credentials must have permissions for:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "budgets:*",
        "ce:*",
        "cost-optimization-hub:*",
        "sns:*",
        "lambda:*",
        "iam:*",
        "logs:*"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Start

### 1. Clone and Navigate

```bash
cd aws/automated-cost-optimization-workflows-cost-optimization-hub-budgets/code/terraform/
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Configure Variables

Copy the example variables file and customize it:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your specific values:

```hcl
# Required Variables
notification_email = "your-email@example.com"
aws_region        = "us-east-1"
environment       = "prod"

# Optional Customizations
monthly_budget_amount     = 1500
monthly_budget_threshold  = 85
ec2_usage_budget_hours   = 3000
anomaly_detection_threshold = 150
```

### 4. Plan Deployment

Review the planned infrastructure:

```bash
terraform plan
```

### 5. Deploy Infrastructure

Apply the Terraform configuration:

```bash
terraform apply
```

### 6. Confirm Email Subscription

After deployment, check your email and confirm the SNS subscription to receive notifications.

## Configuration Variables

### Required Variables

| Variable | Description | Type | Example |
|----------|-------------|------|---------|
| `notification_email` | Email for budget and anomaly alerts | string | `"admin@company.com"` |

### Optional Variables

| Variable | Description | Default | Type |
|----------|-------------|---------|------|
| `aws_region` | AWS region for deployment | `"us-east-1"` | string |
| `environment` | Environment name | `"dev"` | string |
| `monthly_budget_amount` | Monthly budget in USD | `1000` | number |
| `monthly_budget_threshold` | Budget alert threshold % | `80` | number |
| `ec2_usage_budget_hours` | Monthly EC2 hours budget | `2000` | number |
| `ri_utilization_threshold` | RI utilization threshold % | `80` | number |
| `anomaly_detection_threshold` | Anomaly threshold in USD | `100` | number |
| `enable_budget_actions` | Enable automated budget actions | `false` | bool |
| `monitored_services` | Services for anomaly detection | `["EC2-Instance", "RDS", "S3", "Lambda"]` | list(string) |

## Advanced Configuration

### Enable Budget Actions

To enable automated resource restrictions when budgets are exceeded:

```hcl
enable_budget_actions = true
```

**Warning**: This will automatically restrict EC2 and RDS resource provisioning when budget thresholds are exceeded.

### Customize Monitored Services

Modify the services monitored for cost anomalies:

```hcl
monitored_services = [
  "EC2-Instance",
  "RDS",
  "S3",
  "Lambda",
  "CloudFront",
  "EBS"
]
```

### Lambda Function Tuning

Adjust Lambda function performance:

```hcl
lambda_timeout     = 120  # seconds
lambda_memory_size = 512  # MB
```

## Outputs

After deployment, Terraform provides important information:

```bash
# View all outputs
terraform output

# View specific output
terraform output sns_topic_arn
terraform output lambda_function_name
terraform output cost_optimization_hub_url
```

Key outputs include:
- SNS Topic ARN for notifications
- Lambda function name and ARN
- Budget names and configuration
- Console URLs for cost management services
- Next steps for configuration

## Monitoring and Maintenance

### CloudWatch Logs

Monitor Lambda function execution:

```bash
# View recent logs
aws logs describe-log-groups --log-group-name-prefix '/aws/lambda/cost-optimization'

# Stream logs in real-time
aws logs tail /aws/lambda/cost-optimization-handler-<suffix> --follow
```

### Test Lambda Function

Manually trigger the Lambda function:

```bash
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_name) \
  --payload '{"test": "manual trigger"}' \
  /tmp/lambda_response.json

cat /tmp/lambda_response.json
```

### Budget Status

Check budget status:

```bash
aws budgets describe-budgets --account-id $(aws sts get-caller-identity --query Account --output text)
```

## Customization

### Lambda Function Logic

To customize the Lambda function behavior:

1. Edit `lambda_function.py`
2. Modify the processing logic as needed
3. Apply changes with `terraform apply`

### Additional Budgets

To add more budgets, extend the Terraform configuration:

```hcl
resource "aws_budgets_budget" "custom_service_budget" {
  name         = "${local.name_prefix}-custom-budget-${local.resource_suffix}"
  budget_type  = "COST"
  limit_amount = "500"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  
  cost_filter {
    name = "Service"
    values = ["Amazon Simple Storage Service"]
  }
  
  notification {
    comparison_operator         = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }
}
```

## Troubleshooting

### Common Issues

1. **Cost Optimization Hub not available**: Some regions may not support Cost Optimization Hub. Use a supported region like `us-east-1`.

2. **Budget permissions**: Ensure your AWS credentials have proper budgets permissions.

3. **Email notifications not received**: Check spam folder and confirm SNS subscription.

4. **Lambda function errors**: Check CloudWatch logs for detailed error messages.

### Debug Commands

```bash
# Check AWS credentials
aws sts get-caller-identity

# Validate Terraform configuration
terraform validate

# Show current state
terraform show

# Refresh state
terraform refresh
```

## Cost Considerations

This solution incurs minimal costs:

- **AWS Budgets**: $0.02/day per budget (after first 2 free budgets)
- **SNS**: $0.50 per million notifications
- **Lambda**: Pay per execution (usually < $1/month)
- **CloudWatch Logs**: ~$0.50/GB ingested
- **Cost Optimization Hub**: Free
- **Cost Anomaly Detection**: Free

**Estimated monthly cost**: $5-15 depending on usage.

## Cleanup

To remove all resources:

```bash
terraform destroy
```

**Warning**: This will delete all budgets, notifications, and automation. Cost data in Cost Explorer and Cost Optimization Hub will remain.

## Support and Documentation

- [AWS Cost Optimization Hub Documentation](https://docs.aws.amazon.com/cost-management/latest/userguide/cost-optimization-hub.html)
- [AWS Budgets User Guide](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/budgets-managing-costs.html)
- [AWS Cost Anomaly Detection](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/manage-ad.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Contributing

To contribute improvements:

1. Test changes thoroughly in a development environment
2. Update documentation for any new variables or outputs
3. Follow Terraform best practices for resource naming and tagging
4. Validate with `terraform fmt` and `terraform validate`

## License

This infrastructure code is provided as part of the AWS Cost Optimization Hub and Budgets recipe and follows the same licensing terms.