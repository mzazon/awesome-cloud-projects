# Infrastructure as Code for Security Incident Response Automation

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Security Incident Response Automation".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements an automated security incident response system that:

- Centralizes security findings through AWS Security Hub
- Automatically classifies and prioritizes security incidents
- Performs intelligent automated remediation actions
- Sends contextual notifications to security teams
- Provides audit trails and compliance reporting

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Security Hub administration
  - EventBridge rule management
  - Lambda function creation and execution
  - IAM role and policy management
  - SNS topic management
- Understanding of AWS security services (GuardDuty, Config, Inspector)
- Email address for security notifications

### Required AWS Permissions

The deploying user/role needs permissions for:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "securityhub:*",
                "events:*",
                "lambda:*",
                "iam:*",
                "sns:*",
                "logs:*"
            ],
            "Resource": "*"
        }
    ]
}
```

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name security-incident-response \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=SecurityTeamEmail,ParameterValue=your-team@company.com \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-east-1

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name security-incident-response

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name security-incident-response \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Set required environment variables
export SECURITY_TEAM_EMAIL="your-team@company.com"

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy SecurityIncidentResponseStack

# View outputs
cdk ls
```

### Using CDK Python

```bash
# Navigate to CDK directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Set required environment variables
export SECURITY_TEAM_EMAIL="your-team@company.com"

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy SecurityIncidentResponseStack

# View outputs
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="security_team_email=your-team@company.com"

# Apply the configuration
terraform apply -var="security_team_email=your-team@company.com"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export SECURITY_TEAM_EMAIL="your-team@company.com"

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment status
echo "Check AWS Console for Security Hub, Lambda functions, and EventBridge rules"
```

## Post-Deployment Configuration

### 1. Confirm Email Subscription

After deployment, check your email for an SNS subscription confirmation and click the confirmation link.

### 2. Enable Additional Security Services

To maximize the effectiveness of your incident response system, enable these AWS security services:

```bash
# Enable GuardDuty
aws guardduty create-detector --enable

# Enable Config (requires S3 bucket and SNS topic)
aws configservice put-configuration-recorder \
    --configuration-recorder name=default,roleARN=arn:aws:iam::ACCOUNT:role/aws-config-role \
    --recording-group allSupported=true,includeGlobalResourceTypes=true

# Enable Inspector V2
aws inspector2 enable --resource-types ECR,EC2
```

### 3. Test the System

Create a test security finding to validate the automated response:

```bash
# Import a test finding
aws securityhub batch-import-findings \
    --findings '[{
        "SchemaVersion": "2018-10-08",
        "Id": "test-finding-'$(date +%s)'",
        "ProductArn": "arn:aws:securityhub:'$AWS_REGION':'$AWS_ACCOUNT_ID':product/'$AWS_ACCOUNT_ID'/default",
        "GeneratorId": "TestGenerator",
        "AwsAccountId": "'$AWS_ACCOUNT_ID'",
        "Types": ["Software and Configuration Checks/Vulnerabilities"],
        "FirstObservedAt": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'",
        "LastObservedAt": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'",
        "CreatedAt": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'",
        "UpdatedAt": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'",
        "Severity": {"Label": "HIGH", "Normalized": 70},
        "Title": "Test Security Group Open to Internet",
        "Description": "Test finding to validate automated incident response",
        "Resources": [{
            "Type": "AwsEc2SecurityGroup",
            "Id": "arn:aws:ec2:'$AWS_REGION':'$AWS_ACCOUNT_ID':security-group/sg-test123",
            "Partition": "aws",
            "Region": "'$AWS_REGION'"
        }],
        "WorkflowState": "NEW",
        "RecordState": "ACTIVE"
    }]'
```

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor Lambda function execution:

```bash
# View classification function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/security-classification

# View remediation function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/security-remediation

# View notification function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/security-notification
```

### Security Hub Insights

Access pre-configured insights for incident tracking:

```bash
# List available insights
aws securityhub get-insights

# Get critical findings insight
aws securityhub get-insight-results --insight-arn <CRITICAL_INSIGHT_ARN>
```

### EventBridge Rule Metrics

Monitor rule execution in CloudWatch:

- Go to CloudWatch → Metrics → Events
- View rule invocation counts and success rates
- Set up alarms for failed rule executions

## Customization

### Modifying Classification Logic

Edit the classification function to customize incident categorization:

1. Update the `classify_finding()` function in Lambda code
2. Add custom classification categories
3. Modify escalation criteria based on your organization's needs

### Adding Remediation Actions

Extend automated remediation capabilities:

1. Add new remediation functions to the remediation Lambda
2. Update IAM policies to grant necessary permissions
3. Test remediation actions in a non-production environment

### Notification Customization

Customize notification content and channels:

1. Modify the `create_notification_message()` function
2. Add additional SNS subscriptions (Slack, PagerDuty, etc.)
3. Implement severity-based notification routing

### Security Standards Configuration

Customize Security Hub standards and controls:

```bash
# Enable additional security standards
aws securityhub batch-enable-standards \
    --standards-subscription-requests StandardsArn=arn:aws:securityhub:::ruleset/finding-format/aws-foundational-security-standard/v/1.0.0

# Disable specific controls
aws securityhub update-standards-control \
    --standards-control-arn <CONTROL_ARN> \
    --control-status DISABLED \
    --disabled-reason "Not applicable to our environment"
```

## Cost Optimization

### Estimated Monthly Costs

- Security Hub: $0.0010 per finding ingested
- Lambda: $0.20 per 1M requests + compute time
- EventBridge: $1.00 per million events
- SNS: $0.50 per million notifications

**Total estimated cost: $20-50/month** (varies based on finding volume)

### Cost Optimization Tips

1. **Filter EventBridge Rules**: Use precise event patterns to reduce Lambda invocations
2. **Optimize Lambda Memory**: Right-size memory allocation based on execution metrics
3. **Archive Old Findings**: Set up automatic archiving of resolved findings
4. **Use Reserved Capacity**: Consider Lambda provisioned concurrency for high-volume environments

## Security Considerations

### Least Privilege Access

The solution implements least privilege IAM policies. Review and adjust permissions based on your security requirements:

- Lambda execution roles have minimal required permissions
- EventBridge rules are scoped to specific finding types
- SNS topics restrict publishing to authorized roles

### Data Protection

- All communications use TLS encryption in transit
- Lambda environment variables are encrypted with AWS KMS
- Security Hub findings contain sensitive information - ensure proper access controls

### Compliance

This solution supports compliance with:

- SOC 2 Type II (automated monitoring and response)
- PCI DSS (incident response requirements)
- HIPAA (security incident management)
- ISO 27001 (information security management)

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name security-incident-response

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name security-incident-response
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy SecurityIncidentResponseStack
```

### Using CDK Python

```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy SecurityIncidentResponseStack
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="security_team_email=your-team@company.com"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm resource deletion
echo "Verify all resources are deleted in AWS Console"
```

### Manual Cleanup Steps

If automated cleanup fails, manually delete these resources:

1. Security Hub custom actions and insights
2. EventBridge rules and targets
3. Lambda functions and associated logs
4. IAM roles and policies
5. SNS topics and subscriptions

## Troubleshooting

### Common Issues

#### Lambda Function Timeouts

**Symptom**: CloudWatch logs show function timeouts
**Solution**: Increase function timeout or optimize code

```bash
aws lambda update-function-configuration \
    --function-name <function-name> \
    --timeout 300
```

#### EventBridge Rules Not Triggering

**Symptom**: Security findings not triggering automated response
**Solution**: Check event pattern matching

```bash
# Test event pattern
aws events test-event-pattern \
    --event-pattern file://event-pattern.json \
    --event file://test-event.json
```

#### SNS Delivery Failures

**Symptom**: Notifications not received
**Solution**: Check SNS subscription status and email filtering

```bash
# Check subscription status
aws sns get-subscription-attributes \
    --subscription-arn <subscription-arn>
```

#### IAM Permission Errors

**Symptom**: Lambda functions fail with access denied errors
**Solution**: Review and update IAM policies

```bash
# Test IAM policy simulation
aws iam simulate-principal-policy \
    --policy-source-arn <role-arn> \
    --action-names <action> \
    --resource-arns <resource-arn>
```

### Debug Mode

Enable debug logging for detailed troubleshooting:

```bash
# Set Lambda environment variable for debug logging
aws lambda update-function-configuration \
    --function-name <function-name> \
    --environment Variables='{LOG_LEVEL=DEBUG}'
```

## Support and Resources

### Documentation

- [AWS Security Hub User Guide](https://docs.aws.amazon.com/securityhub/latest/userguide/)
- [EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)

### Best Practices

- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)
- [Incident Response Best Practices](https://docs.aws.amazon.com/whitepapers/latest/aws-security-incident-response-guide/)
- [Security Hub Best Practices](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-standards.html)

### Community

- [AWS Security Blog](https://aws.amazon.com/blogs/security/)
- [AWS re:Post Security Community](https://repost.aws/tags/TAF4Zqx6vDSmCugdoRwdNzfA/security)

## Contributing

For issues with this infrastructure code, refer to the original recipe documentation or submit issues through the appropriate channels.

---

**Note**: This infrastructure code implements the complete automated security incident response solution described in the recipe. Customize the configuration variables and notification settings according to your organization's requirements.