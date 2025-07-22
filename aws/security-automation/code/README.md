# Infrastructure as Code for Automated Security Response with EventBridge

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Security Response with EventBridge".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation deploys a comprehensive event-driven security automation framework that:

- Captures security events from AWS Security Hub, Inspector, GuardDuty, and CloudTrail
- Automatically triages security findings based on severity and type
- Executes automated remediation actions including instance isolation and network blocking
- Sends contextual notifications to security teams
- Provides monitoring and error handling capabilities
- Integrates with Systems Manager for complex automation workflows

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - EventBridge
  - Lambda
  - Security Hub
  - Systems Manager
  - SNS/SQS
  - CloudWatch
  - IAM
- Security Hub enabled with findings configured
- Basic understanding of event-driven architectures and security automation

## Quick Start

### Using CloudFormation

```bash
# Deploy the security automation stack
aws cloudformation create-stack \
    --stack-name security-automation-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=NotificationEmail,ParameterValue=security-team@company.com
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
cdk deploy SecurityAutomationStack
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy SecurityAutomationStack
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh
```

## Configuration

### Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| NotificationEmail | Email address for security notifications | None | Yes |
| Environment | Environment name (dev/staging/prod) | dev | No |
| AutomationPrefix | Prefix for all resource names | security-automation | No |
| EnableHighSeverityAutomation | Enable automated remediation for high severity findings | true | No |
| EnableCriticalSeverityAutomation | Enable automated remediation for critical severity findings | false | No |

### Terraform Variables

Create a `terraform.tfvars` file with your specific values:

```hcl
notification_email = "security-team@company.com"
environment = "prod"
automation_prefix = "security-automation"
enable_high_severity_automation = true
enable_critical_severity_automation = false
```

## Post-Deployment Configuration

### 1. Configure SNS Email Subscription

After deployment, check your email for the SNS subscription confirmation and click the confirmation link.

### 2. Test the Automation

```bash
# Send a test notification
aws sns publish \
    --topic-arn $(aws cloudformation describe-stacks \
        --stack-name security-automation-stack \
        --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' \
        --output text) \
    --subject "Test Security Alert" \
    --message "This is a test security automation notification"
```

### 3. Configure Security Hub

Ensure Security Hub is enabled and configured to generate findings:

```bash
# Enable Security Hub (if not already enabled)
aws securityhub enable-security-hub

# Enable AWS Config findings
aws securityhub enable-import-findings-for-product \
    --product-arn arn:aws:securityhub:us-east-1::product/aws/config
```

### 4. Create Custom Security Hub Actions

The deployment automatically creates custom actions in Security Hub:
- "TriggerAutomatedRemediation" - Manually trigger remediation
- "EscalateToSOC" - Escalate to Security Operations Center

## Monitoring and Observability

### CloudWatch Dashboard

The deployment creates a CloudWatch dashboard to monitor:
- Lambda function invocations and errors
- EventBridge rule execution metrics
- Security Hub finding processing rates
- Dead letter queue message counts

### CloudWatch Alarms

Automatic alarms are configured for:
- Lambda function errors
- EventBridge rule failures
- High numbers of security findings
- Dead letter queue message accumulation

### Logs

Monitor the following CloudWatch Log Groups:
- `/aws/lambda/security-automation-triage`
- `/aws/lambda/security-automation-remediation`
- `/aws/lambda/security-automation-notification`
- `/aws/lambda/security-automation-error-handler`

## Security Considerations

### IAM Permissions

The automation uses least-privilege IAM policies that allow:
- Reading Security Hub findings
- Updating finding workflow status
- Executing Systems Manager automation
- Managing EC2 security groups (for remediation)
- Publishing SNS notifications
- Writing CloudWatch logs

### Automated Remediation Controls

- **High Severity**: Automated isolation and containment actions
- **Critical Severity**: Manual approval required (configurable)
- **Medium/Low Severity**: Notification-only by default

### Audit Trail

All automation actions are logged to CloudWatch Logs and include:
- Original security finding details
- Remediation actions taken
- Results of automation execution
- Timestamps and execution context

## Troubleshooting

### Common Issues

1. **Lambda Function Timeouts**
   - Check CloudWatch Logs for specific error messages
   - Verify IAM permissions for target resources
   - Ensure network connectivity for external integrations

2. **EventBridge Rules Not Triggering**
   - Verify Security Hub is generating findings
   - Check EventBridge rule event patterns
   - Ensure Lambda function permissions are correct

3. **Remediation Actions Failing**
   - Check IAM permissions for remediation actions
   - Verify target resources exist and are accessible
   - Review Systems Manager automation execution logs

### Debug Mode

Enable debug logging by setting the `DEBUG` environment variable:

```bash
aws lambda update-function-configuration \
    --function-name security-automation-triage \
    --environment Variables="{DEBUG=true}"
```

## Cleanup

### Using CloudFormation

```bash
aws cloudformation delete-stack --stack-name security-automation-stack
```

### Using CDK

```bash
# From the CDK directory
cdk destroy SecurityAutomationStack
```

### Using Terraform

```bash
# From the terraform directory
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Customization

### Adding New Remediation Actions

1. Extend the remediation Lambda function with new action types
2. Update the triage function to classify findings for new actions
3. Add appropriate IAM permissions for new actions
4. Test thoroughly in non-production environments

### Integrating with External Systems

1. Modify the notification function to send alerts to SIEM/SOAR platforms
2. Add webhook endpoints for ticketing systems
3. Integrate with Slack or Microsoft Teams for real-time notifications
4. Connect to third-party threat intelligence feeds

### Custom EventBridge Rules

Add custom rules for specific security scenarios:

```bash
aws events put-rule \
    --name custom-security-rule \
    --event-pattern '{
        "source": ["aws.securityhub"],
        "detail-type": ["Security Hub Findings - Imported"],
        "detail": {
            "findings": {
                "Types": [{"prefix": "Sensitive Data"}]
            }
        }
    }'
```

## Cost Optimization

### Estimated Monthly Costs

- Lambda executions: $5-15 (depends on finding volume)
- EventBridge rules: $1-3
- SNS notifications: $1-2
- CloudWatch logs and metrics: $2-5
- **Total estimated cost: $10-25/month**

### Cost Reduction Tips

1. Use EventBridge filtering to reduce Lambda invocations
2. Implement Lambda function warming for consistent performance
3. Use SNS message filtering to reduce notification costs
4. Archive old CloudWatch logs to reduce storage costs

## Security Best Practices

1. **Regular Reviews**: Review and update automation rules monthly
2. **Testing**: Test all remediation actions in non-production environments
3. **Monitoring**: Monitor automation effectiveness and adjust thresholds
4. **Documentation**: Maintain runbooks for manual intervention scenarios
5. **Compliance**: Ensure automation aligns with compliance requirements

## Support

For issues with this infrastructure code:
1. Check CloudWatch Logs for specific error messages
2. Review the original recipe documentation
3. Consult AWS documentation for specific services
4. Test automation in isolated environments before production deployment

## Contributing

When extending this automation framework:
1. Follow AWS security best practices
2. Include comprehensive error handling
3. Add appropriate monitoring and alerting
4. Document all changes thoroughly
5. Test in multiple environments before production use