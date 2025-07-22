# Infrastructure as Code for Event-Driven Security Automation

This directory contains Terraform Infrastructure as Code (IaC) for deploying the complete event-driven security automation solution using AWS EventBridge and Lambda.

## Architecture Overview

This solution creates an intelligent security automation framework that:

- **Captures security events** from AWS Security Hub, Inspector, GuardDuty, and CloudTrail
- **Automatically triages** security findings based on severity and type
- **Executes remediation actions** including instance isolation, network blocking, and forensic snapshots
- **Sends contextual notifications** to security teams with actionable information
- **Provides monitoring** and error handling for the automation infrastructure

## Resources Created

### Lambda Functions
- **Triage Function**: Analyzes security findings and determines appropriate response actions
- **Remediation Function**: Executes automated security response actions
- **Notification Function**: Sends rich security alerts to various endpoints
- **Error Handler Function**: Handles automation failures and system errors

### EventBridge Components
- **Security Hub Findings Rule**: Routes new security findings to automation
- **Remediation Actions Rule**: Triggers remediation based on triage decisions
- **Custom Actions Rule**: Handles manual triggers from Security Hub console
- **Error Handling Rule**: Captures and processes automation failures

### Security Hub Integration
- **Automation Rules**: Automatically update finding status based on severity
- **Custom Actions**: Provide manual controls for security analysts

### Monitoring and Notifications
- **SNS Topic**: Central notification hub for security alerts
- **SQS Dead Letter Queue**: Captures failed automation events
- **CloudWatch Alarms**: Monitor Lambda errors and EventBridge failures
- **CloudWatch Dashboard**: Operational visibility into automation performance

### Systems Manager
- **Automation Document**: Standardized instance isolation procedures

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Terraform** v1.0 or later installed
3. **AWS IAM permissions** for creating:
   - Lambda functions and IAM roles
   - EventBridge rules and targets
   - SNS topics and SQS queues
   - Security Hub automation rules and custom actions
   - CloudWatch alarms and dashboards
   - Systems Manager automation documents

4. **AWS Security Hub** enabled in your account with findings sources configured
5. **Estimated cost**: $15-25/month for Lambda executions, EventBridge rules, and SNS notifications

## Quick Start

### 1. Clone and Navigate
```bash
git clone <repository-url>
cd aws/event-driven-security-automation-eventbridge-lambda/code/terraform/
```

### 2. Initialize Terraform
```bash
terraform init
```

### 3. Review and Customize Variables
Copy the example variables file and customize for your environment:
```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your specific values:
```hcl
# AWS Configuration
aws_region = "us-east-1"
environment = "prod"

# Notification Configuration
notification_email = "security-team@example.com"

# Optional: Customize resource naming
automation_prefix = "security-automation"

# Optional: Enable/disable components
enable_automation_rules = true
enable_custom_actions = true
enable_cloudwatch_monitoring = true
```

### 4. Plan the Deployment
```bash
terraform plan
```

### 5. Deploy the Infrastructure
```bash
terraform apply
```

When prompted, type `yes` to confirm the deployment.

## Configuration Options

### Basic Configuration
```hcl
# terraform.tfvars
aws_region = "us-east-1"
environment = "prod"
notification_email = "security-team@example.com"
```

### Advanced Configuration
```hcl
# terraform.tfvars
aws_region = "us-east-1"
environment = "prod"
automation_prefix = "my-security-automation"

# Lambda Configuration
lambda_timeout = 300
lambda_memory_size = 512
lambda_runtime = "python3.9"

# Finding Processing
finding_severities = ["HIGH", "CRITICAL", "MEDIUM"]
event_rule_state = "ENABLED"

# Feature Toggles
enable_automation_rules = true
enable_custom_actions = true
enable_cloudwatch_monitoring = true
enable_ssm_automation = true

# SNS Configuration
sns_delivery_policy = {
  min_delay_target = 5
  max_delay_target = 300
  num_retries = 10
}

# Additional Tags
additional_tags = {
  Owner = "SecurityTeam"
  CostCenter = "IT-Security"
}
```

## Validation and Testing

### 1. Verify Resource Creation
```bash
# Check Lambda functions
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `security-automation`)].FunctionName'

# Check EventBridge rules
aws events list-rules --name-prefix security-automation

# Check SNS topic
aws sns list-topics --query 'Topics[?contains(TopicArn, `security-automation`)]'
```

### 2. Test Lambda Functions
```bash
# Test with sample event
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_names | jq -r .triage) \
  --payload file://test-event.json \
  response.json

cat response.json
```

### 3. Check Security Hub Integration
```bash
# List automation rules
aws securityhub list-automation-rules

# List custom actions
aws securityhub describe-action-targets
```

### 4. Monitor CloudWatch Logs
```bash
# Check Lambda logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/security-automation

# Get recent events
aws logs filter-log-events \
  --log-group-name /aws/lambda/security-automation-<suffix>-triage \
  --start-time $(date -d '1 hour ago' +%s)000
```

## Outputs

After successful deployment, Terraform provides these outputs:

- **lambda_function_arns**: ARNs of all created Lambda functions
- **sns_topic_arn**: ARN of the notification topic
- **eventbridge_rule_arns**: ARNs of all EventBridge rules
- **cloudwatch_dashboard_url**: URL to the monitoring dashboard
- **security_hub_automation_rule_arns**: ARNs of Security Hub automation rules

## Maintenance and Updates

### Update Lambda Function Code
```bash
# After modifying lambda_code/*.py files
terraform plan
terraform apply
```

### Update Configuration
```bash
# After modifying terraform.tfvars
terraform plan
terraform apply
```

### View Current State
```bash
terraform show
terraform output
```

## Troubleshooting

### Common Issues

1. **Lambda Function Errors**
   - Check CloudWatch logs: `/aws/lambda/security-automation-*`
   - Verify IAM permissions in the execution role
   - Ensure environment variables are set correctly

2. **EventBridge Rule Not Triggering**
   - Verify Security Hub is enabled and generating findings
   - Check event pattern matches your finding format
   - Confirm Lambda permissions for EventBridge invocation

3. **SNS Notifications Not Received**
   - Confirm email subscription to SNS topic
   - Check SNS topic policies and permissions
   - Verify email address in subscription

4. **Security Hub Integration Issues**
   - Ensure Security Hub is enabled in the region
   - Verify findings are being imported (not just generated)
   - Check automation rule criteria match your findings

### Debug Commands
```bash
# Check Lambda function configuration
aws lambda get-function --function-name <function-name>

# Check EventBridge rule targets
aws events list-targets-by-rule --rule <rule-name>

# Check SNS topic subscriptions
aws sns list-subscriptions-by-topic --topic-arn <topic-arn>

# Check CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/security-automation
```

## Security Considerations

1. **IAM Permissions**: The Lambda execution role follows least privilege principle
2. **Encryption**: SNS topic and SQS queue use default AWS encryption
3. **Network Security**: Lambda functions run in AWS managed VPC
4. **Audit Trail**: All automation actions are logged in CloudWatch
5. **Error Handling**: Failed events are captured in dead letter queue

## Cost Optimization

- Lambda functions use ARM-based Graviton2 processors where supported
- CloudWatch log retention is set to 14 days by default
- SNS topic includes retry policies to reduce failed delivery costs
- EventBridge rules are optimized to minimize unnecessary invocations

## Cleanup

To remove all resources created by this Terraform configuration:

```bash
terraform destroy
```

**Warning**: This will permanently delete all resources. Ensure you have backups of any important data or configurations.

## Support and Contributing

For issues with this infrastructure code:

1. Check the [original recipe documentation](../../event-driven-security-automation-eventbridge-lambda.md)
2. Review AWS service documentation for specific services
3. Check Terraform AWS provider documentation
4. Review CloudWatch logs for runtime errors

## License

This infrastructure code is provided as-is for educational and operational purposes. Please review and test thoroughly before deploying in production environments.