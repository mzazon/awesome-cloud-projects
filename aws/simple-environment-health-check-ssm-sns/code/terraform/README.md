# Terraform Infrastructure for Simple Environment Health Check

This directory contains Terraform Infrastructure as Code (IaC) for deploying the "Simple Environment Health Check with Systems Manager and SNS" solution on AWS.

## Solution Overview

This Terraform configuration deploys a complete environment health monitoring system that:

- 🔍 **Monitors EC2 instances** using AWS Systems Manager
- 📧 **Sends email notifications** when health issues are detected
- ⏰ **Runs automated health checks** every 5 minutes (configurable)
- 📊 **Tracks compliance status** using custom Systems Manager compliance types
- 🎯 **Responds to events** in real-time using EventBridge rules
- 📈 **Provides monitoring dashboard** with CloudWatch

## Architecture

The solution creates the following AWS resources:

- **SNS Topic**: For health alert notifications
- **Lambda Function**: Performs health checks and updates compliance
- **EventBridge Rules**: Schedule health checks and respond to compliance events
- **IAM Roles & Policies**: Secure access permissions
- **CloudWatch Dashboard**: Monitoring and visualization
- **CloudWatch Log Group**: Lambda function logs

## Prerequisites

### Required Tools

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate permissions
- AWS account with administrator access or the following permissions:
  - SNS: Full access
  - Lambda: Full access
  - EventBridge: Full access
  - Systems Manager: Full access
  - IAM: Role and policy management
  - CloudWatch: Dashboard and logs management

### AWS Resources

- At least one EC2 instance with SSM Agent installed and running
- Instances should be tagged with `SSMManaged=true` to be included in monitoring

### Estimated Costs

- **Monthly cost**: $3.50-$5.00 USD (us-east-1)
- **Free tier eligible**: Lambda executions, SNS notifications (up to limits)
- **Main costs**: CloudWatch Dashboard ($3/month), potential data transfer charges

## Configuration

### Required Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required: Your email address for notifications
notification_email = "your-email@example.com"

# Optional: AWS region (default: us-east-1)
aws_region = "us-east-1"

# Optional: Environment tag (default: dev)
environment = "prod"

# Optional: Health check frequency (default: rate(5 minutes))
health_check_schedule = "rate(5 minutes)"

# Optional: Project name for resource naming (default: environment-health-check)
project_name = "my-health-monitor"
```

### All Available Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `notification_email` | Email address for health notifications | - | Yes |
| `aws_region` | AWS region for deployment | `us-east-1` | No |
| `environment` | Environment tag (dev/staging/prod) | `dev` | No |
| `health_check_schedule` | EventBridge schedule expression | `rate(5 minutes)` | No |
| `lambda_timeout` | Lambda function timeout (seconds) | `60` | No |
| `lambda_memory_size` | Lambda memory allocation (MB) | `256` | No |
| `project_name` | Project name for resource naming | `environment-health-check` | No |
| `compliance_type` | Custom compliance type name | `Custom:EnvironmentHealth` | No |

## Deployment

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd aws/simple-environment-health-check-ssm-sns/code/terraform/
```

### 2. Configure Variables

```bash
# Create terraform.tfvars file
cat > terraform.tfvars << EOF
notification_email = "your-email@example.com"
aws_region = "us-east-1"
environment = "prod"
EOF
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Plan Deployment

```bash
terraform plan
```

### 5. Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted to confirm the deployment.

## Post-Deployment Steps

### 1. Confirm Email Subscription

1. Check your email for an SNS subscription confirmation
2. Click the confirmation link to activate notifications

### 2. Prepare EC2 Instances

```bash
# Tag your instances for monitoring (replace with your instance IDs)
aws ec2 create-tags \
    --resources i-1234567890abcdef0 \
    --tags Key=SSMManaged,Value=true

# Verify SSM Agent is running on your instances
aws ssm describe-instance-information \
    --query 'InstanceInformationList[*].[InstanceId,PingStatus,LastPingDateTime]' \
    --output table
```

### 3. Test the Solution

```bash
# Get Lambda function name from Terraform outputs
LAMBDA_NAME=$(terraform output -raw lambda_function_name)

# Manually invoke health check
aws lambda invoke \
    --function-name "$LAMBDA_NAME" \
    --payload '{"source":"manual-test"}' \
    response.json

# Check the response
cat response.json

# View Lambda logs
aws logs tail "/aws/lambda/$LAMBDA_NAME" --since 5m --follow
```

## Monitoring and Operations

### CloudWatch Dashboard

Access your monitoring dashboard:

```bash
# Get dashboard URL from Terraform outputs
terraform output cloudwatch_dashboard_url
```

### Useful Commands

```bash
# Check SNS topic status
SNS_TOPIC_ARN=$(terraform output -raw sns_topic_arn)
aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN"

# View compliance summary
aws ssm list-compliance-summaries \
    --filters Key=ComplianceType,Values="Custom:EnvironmentHealth"

# Send test notification
aws sns publish \
    --topic-arn "$SNS_TOPIC_ARN" \
    --subject "Test Health Alert" \
    --message "This is a test notification"

# View EventBridge rules
aws events list-rules --name-prefix "health-check-schedule"
aws events list-rules --name-prefix "compliance-health-alerts"
```

### Troubleshooting

#### No Email Notifications

1. Check if email subscription is confirmed:
   ```bash
   aws sns list-subscriptions-by-topic --topic-arn "$(terraform output -raw sns_topic_arn)"
   ```

2. Verify Lambda function is running:
   ```bash
   aws logs tail "/aws/lambda/$(terraform output -raw lambda_function_name)" --since 30m
   ```

#### No Health Check Data

1. Ensure instances have SSM Agent installed and running
2. Verify IAM permissions for Systems Manager
3. Check that instances are tagged with `SSMManaged=true`

#### Lambda Function Errors

1. Check CloudWatch logs for detailed error messages
2. Verify IAM permissions for Lambda role
3. Ensure SNS topic ARN is correctly configured

## Customization

### Modifying Health Check Logic

The Lambda function code is generated from a template. To customize:

1. Edit the `lambda_function.py.tpl` file created during deployment
2. Modify the health check logic as needed
3. Run `terraform apply` to update the function

### Adding More Notification Channels

You can extend the solution to include additional notification methods:

```hcl
# Add Slack webhook notification
resource "aws_sns_topic_subscription" "slack_notification" {
  topic_arn = aws_sns_topic.health_alerts.arn
  protocol  = "https"
  endpoint  = "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
}
```

### Modifying Check Frequency

Update the `health_check_schedule` variable to change how often health checks run:

```hcl
# Every minute
health_check_schedule = "rate(1 minute)"

# Every hour
health_check_schedule = "rate(1 hour)"

# Daily at 9 AM UTC
health_check_schedule = "cron(0 9 * * ? *)"
```

## Cleanup

To remove all resources created by this Terraform configuration:

```bash
terraform destroy
```

Type `yes` when prompted to confirm the destruction.

## Security Considerations

This configuration follows AWS security best practices:

- ✅ **Least Privilege**: IAM roles have minimal required permissions
- ✅ **Encryption**: SNS topics use AWS KMS encryption
- ✅ **Resource Isolation**: Resources are properly tagged and isolated
- ✅ **Network Security**: No public internet access required
- ✅ **Audit Trail**: CloudWatch logs provide complete audit trail

## Cost Optimization

- Uses AWS Free Tier eligible services where possible
- Lambda executions are typically within free tier limits
- CloudWatch Logs retention set to 14 days to minimize costs
- Consider reducing check frequency for cost savings in development environments

## Support

For issues with this Terraform configuration:

1. Check Terraform state: `terraform state list`
2. Review AWS CloudTrail logs for API errors
3. Validate AWS permissions and resource limits
4. Refer to the original recipe documentation

## Version History

- **v1.0**: Initial Terraform implementation
- **v1.1**: Added CloudWatch dashboard and enhanced monitoring
- **v1.2**: Improved error handling and documentation

---

**Note**: This Terraform configuration is designed to work with the complete "Simple Environment Health Check with Systems Manager and SNS" recipe. For the full context and step-by-step instructions, refer to the original recipe documentation.