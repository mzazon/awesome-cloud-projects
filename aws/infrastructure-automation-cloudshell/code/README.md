# Infrastructure as Code for Infrastructure Automation with CloudShell PowerShell

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Infrastructure Automation with CloudShell PowerShell".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- AWS CLI installed and configured with appropriate permissions
- AWS account with CloudShell access enabled
- Permissions for the following AWS services:
  - IAM (roles and policies)
  - Lambda (function creation and management)
  - Systems Manager (automation documents)
  - CloudWatch (logs, metrics, alarms, dashboards)
  - EventBridge (rules and targets)
  - SNS (topic creation)

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2.0 or later
- CloudFormation stack creation permissions

#### CDK TypeScript
- Node.js 16.x or later
- npm or yarn package manager
- AWS CDK v2.x installed (`npm install -g aws-cdk`)

#### CDK Python
- Python 3.8 or later
- pip package manager
- AWS CDK v2.x installed (`pip install aws-cdk-lib`)

#### Terraform
- Terraform 1.0 or later
- AWS provider for Terraform

### Estimated Costs
- Lambda executions: $0.20 per 1M requests + $0.0000166667 per GB-second
- CloudWatch logs: $0.50 per GB ingested
- SNS notifications: $0.50 per 1M requests
- EventBridge: $1.00 per million events
- **Total estimated monthly cost: $5-15** for typical usage patterns

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name infrastructure-automation-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=prod

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name infrastructure-automation-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name infrastructure-automation-stack \
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
cdk deploy --require-approval never

# View stack outputs
cdk list
aws cloudformation describe-stacks \
    --stack-name InfrastructureAutomationStack \
    --query 'Stacks[0].Outputs'
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View stack outputs
cdk list
aws cloudformation describe-stacks \
    --stack-name InfrastructureAutomationStack \
    --query 'Stacks[0].Outputs'
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
aws cloudformation describe-stacks \
    --stack-name infrastructure-automation \
    --query 'Stacks[0].StackStatus'
```

## Post-Deployment Setup

### Configure PowerShell Scripts in CloudShell

After deploying the infrastructure, you'll need to set up the PowerShell automation scripts:

1. **Access CloudShell**:
   - Open the AWS Console
   - Navigate to CloudShell service
   - Start PowerShell: `pwsh`

2. **Create the Infrastructure Health Check Script**:
   ```powershell
   # Download or create the PowerShell script
   # The script should be placed in CloudShell's persistent storage
   # Example location: ~/infrastructure-health-check.ps1
   ```

3. **Test Manual Execution**:
   ```bash
   # Test the automation document
   aws ssm start-automation-execution \
       --document-name "InfrastructureHealthCheck-$(date +%s)" \
       --parameters "Region=$(aws configure get region)"
   ```

### Verify Scheduled Execution

```bash
# Check EventBridge rule status
aws events describe-rule \
    --name "$(terraform output -raw eventbridge_rule_name 2>/dev/null || echo 'InfrastructureHealthSchedule')"

# Verify Lambda function
aws lambda get-function \
    --function-name "$(terraform output -raw lambda_function_name 2>/dev/null || echo 'InfrastructureAutomation')"

# Check recent automation executions
aws ssm describe-automation-executions \
    --filters "Key=DocumentNamePrefix,Values=InfrastructureHealthCheck" \
    --query "AutomationExecutions[*].[ExecutionId,AutomationExecutionStatus,ExecutionStartTime]" \
    --output table
```

## Monitoring and Observability

### CloudWatch Dashboard

Access the created dashboard:
```bash
# Get dashboard URL
DASHBOARD_NAME=$(terraform output -raw cloudwatch_dashboard_name 2>/dev/null || echo 'InfrastructureAutomation')
echo "Dashboard URL: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
```

### Log Analysis

```bash
# View automation logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/automation"

# Get recent log events
aws logs filter-log-events \
    --log-group-name "/aws/automation/infrastructure-health" \
    --start-time $(date -d '1 hour ago' +%s)000
```

### Metrics and Alarms

```bash
# Check automation metrics
aws cloudwatch get-metric-statistics \
    --namespace "Infrastructure/Automation" \
    --metric-name "AutomationExecutions" \
    --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Sum

# List active alarms
aws cloudwatch describe-alarms \
    --alarm-name-prefix "InfrastructureAutomation"
```

## Customization

### Environment Variables

Key parameters that can be customized:

- **Environment**: Production, staging, or development
- **Schedule**: EventBridge cron expression for automation frequency
- **Notification Email**: SNS topic subscription for alerts
- **Log Retention**: CloudWatch log group retention period
- **Memory Size**: Lambda function memory allocation

### Terraform Variables

Edit `terraform/terraform.tfvars` or set environment variables:

```bash
export TF_VAR_environment="production"
export TF_VAR_schedule_expression="cron(0 6 * * ? *)"
export TF_VAR_notification_email="admin@example.com"
export TF_VAR_log_retention_days=30
export TF_VAR_lambda_memory_size=256
```

### CloudFormation Parameters

Override default parameters during deployment:

```bash
aws cloudformation create-stack \
    --stack-name infrastructure-automation-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=Environment,ParameterValue=production \
        ParameterKey=ScheduleExpression,ParameterValue="cron(0 6 * * ? *)" \
        ParameterKey=NotificationEmail,ParameterValue=admin@example.com
```

### CDK Context Values

Set context values in `cdk.json` or via command line:

```bash
# TypeScript
cdk deploy -c environment=production -c notificationEmail=admin@example.com

# Python
cdk deploy -c environment=production -c notificationEmail=admin@example.com
```

## Troubleshooting

### Common Issues

1. **IAM Permissions**: Ensure the deployment role has sufficient permissions for all AWS services
2. **CloudShell Access**: Verify CloudShell is available in your AWS region
3. **PowerShell Scripts**: Ensure scripts are properly formatted and stored in CloudShell persistent storage
4. **EventBridge Schedule**: Verify cron expressions are valid and timezone-appropriate

### Debug Commands

```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
    --stack-name infrastructure-automation-stack

# Review Lambda function logs
aws logs describe-log-streams \
    --log-group-name "/aws/lambda/InfrastructureAutomation" \
    --order-by LastEventTime --descending

# Test automation document syntax
aws ssm describe-document \
    --name "InfrastructureHealthCheck" \
    --query "Document.Status"
```

### Resource Validation

```bash
# Verify all resources exist
aws iam get-role --role-name InfraAutomationRole
aws lambda get-function --function-name InfrastructureAutomation
aws events describe-rule --name InfrastructureHealthSchedule
aws ssm describe-document --name InfrastructureHealthCheck
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name infrastructure-automation-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name infrastructure-automation-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# TypeScript
cd cdk-typescript/
cdk destroy --force

# Python
cd cdk-python/
cdk destroy --force
```

### Using Terraform

```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Remove CloudWatch log groups (optional - contains historical data)
aws logs delete-log-group \
    --log-group-name "/aws/automation/infrastructure-health"

aws logs delete-log-group \
    --log-group-name "/aws/lambda/InfrastructureAutomation"

# Remove SNS topic subscriptions
aws sns list-subscriptions-by-topic \
    --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:automation-alerts"
```

## Security Considerations

### IAM Best Practices

- The automation role follows least privilege principle
- PowerShell scripts run with limited permissions
- Lambda functions have minimal required permissions
- CloudWatch access is restricted to automation namespace

### Network Security

- All communications use AWS service endpoints
- No external network access required
- CloudShell provides secure, isolated execution environment

### Data Protection

- CloudWatch logs may contain infrastructure metadata
- Consider log encryption for sensitive environments
- Implement log retention policies based on compliance requirements

## Extensions and Integrations

### Multi-Account Setup

For enterprise environments, consider:
- AWS Organizations integration
- Cross-account automation roles
- Centralized logging and monitoring

### Advanced Monitoring

Enhance monitoring with:
- Custom CloudWatch metrics
- AWS X-Ray tracing for Lambda functions
- Integration with third-party monitoring tools

### Notification Enhancements

Extend alerting with:
- Slack/Teams webhook integration
- PagerDuty escalation
- Custom notification logic based on automation results

## Support

### Documentation References

- [AWS CloudShell User Guide](https://docs.aws.amazon.com/cloudshell/latest/userguide/welcome.html)
- [AWS Systems Manager Automation](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-automation.html)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html)
- [PowerShell on AWS](https://docs.aws.amazon.com/powershell/latest/userguide/pstools-welcome.html)

### Community Resources

- [AWS PowerShell GitHub Repository](https://github.com/aws/aws-tools-for-powershell)
- [AWS Systems Manager GitHub Repository](https://github.com/aws/aws-systems-manager)

For issues with this infrastructure code, refer to the original recipe documentation or open an issue in the repository.