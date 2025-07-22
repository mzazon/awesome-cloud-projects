# Infrastructure as Code for Responding to Incidents with Security Hub

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Responding to Incidents with Security Hub".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with administrator permissions for:
  - AWS Security Hub
  - Amazon EventBridge
  - AWS Lambda
  - Amazon SNS
  - Amazon SQS
  - AWS IAM
  - Amazon CloudWatch
- Basic knowledge of security incident response procedures
- Understanding of EventBridge event patterns and Lambda functions
- Estimated cost: $50-150/month depending on finding volume and Lambda execution frequency

> **Note**: This solution processes security findings that may contain sensitive information. Ensure proper access controls and encryption are in place.

## Quick Start

### Using CloudFormation

```bash
# Deploy the security incident response infrastructure
aws cloudformation create-stack \
    --stack-name security-incident-response \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name security-incident-response

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name security-incident-response \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not done previously)
cdk bootstrap

# Set notification email
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy SecurityHubIncidentResponseStack

# View outputs
cdk ls
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not done previously)
cdk bootstrap

# Set notification email
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy SecurityHubIncidentResponseStack

# View outputs
cdk ls
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
notification_email = "your-email@example.com"
aws_region = "us-east-1"
environment = "production"
EOF

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL=your-email@example.com
export AWS_REGION=us-east-1

# Deploy the infrastructure
./scripts/deploy.sh

# View deployed resources
aws securityhub describe-hub
aws events list-rules --name-prefix security-hub
```

## Architecture Overview

This infrastructure deploys a comprehensive security incident response system with the following components:

### Core Security Hub Infrastructure
- **AWS Security Hub**: Central security findings aggregation
- **Security Standards**: Enables CIS AWS Foundations Benchmark and default standards
- **Custom Actions**: Manual escalation capabilities for security analysts
- **Automation Rules**: Intelligent triage for automatic finding classification

### Event-Driven Processing
- **EventBridge Rules**: Automated triggers for high/critical severity findings
- **Lambda Functions**: Incident processing and threat intelligence enrichment
- **Step Functions**: Orchestrated response workflows (future enhancement)

### Notification and Integration
- **SNS Topics**: Multi-channel incident notifications
- **SQS Queues**: Durable message buffering for external system integration
- **CloudWatch**: Monitoring, alerting, and operational dashboards

### Security and Compliance
- **IAM Roles**: Least-privilege access for all components
- **Encryption**: Data encryption at rest and in transit
- **Audit Logging**: Complete audit trail of all security operations

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `NotificationEmail` | Email address for security incident notifications | - | Yes |
| `Environment` | Environment name (dev, staging, prod) | prod | No |
| `SecurityHubRegion` | AWS region for Security Hub deployment | us-east-1 | No |
| `EnableThreatIntelligence` | Enable threat intelligence enrichment | true | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `notification_email` | Email address for security incident notifications | - | Yes |
| `aws_region` | AWS region for deployment | us-east-1 | No |
| `environment` | Environment name | production | No |
| `enable_threat_intelligence` | Enable threat intelligence enrichment | true | No |
| `lambda_timeout` | Lambda function timeout in seconds | 60 | No |
| `lambda_memory_size` | Lambda function memory in MB | 256 | No |

### CDK Configuration

Both CDK implementations support the following environment variables:

- `NOTIFICATION_EMAIL`: Email address for notifications (required)
- `AWS_REGION`: Deployment region (optional, defaults to current region)
- `ENVIRONMENT`: Environment name (optional, defaults to "production")

## Post-Deployment Setup

### 1. Confirm Email Subscription

After deployment, check your email for an SNS subscription confirmation message and click the confirmation link.

### 2. Enable Security Hub Integrations

```bash
# Enable GuardDuty integration (if not already enabled)
aws guardduty create-detector --enable

# Enable Config integration (if not already enabled)
aws configservice put-configuration-recorder \
    --configuration-recorder name=default,roleARN=arn:aws:iam::ACCOUNT-ID:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig

# Enable Inspector integration (if not already enabled)
aws inspector2 enable --resource-types ECR,EC2
```

### 3. Test the Incident Response System

```bash
# Create a test high-severity finding
aws securityhub batch-import-findings \
    --findings '[{
        "AwsAccountId": "'$(aws sts get-caller-identity --query Account --output text)'",
        "CreatedAt": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'",
        "Description": "Test security finding for incident response validation",
        "FindingProviderFields": {
            "Severity": {
                "Label": "HIGH",
                "Original": "8.0"
            },
            "Types": ["Software and Configuration Checks/Vulnerabilities/CVE"]
        },
        "GeneratorId": "test-generator-incident-response",
        "Id": "test-finding-'$(date +%s)'",
        "ProductArn": "arn:aws:securityhub:'$AWS_REGION':'$(aws sts get-caller-identity --query Account --output text)':product/'$(aws sts get-caller-identity --query Account --output text)'/default",
        "Resources": [{
            "Id": "arn:aws:ec2:'$AWS_REGION':'$(aws sts get-caller-identity --query Account --output text)':instance/i-test123",
            "Partition": "aws",
            "Region": "'$AWS_REGION'",
            "Type": "AwsEc2Instance"
        }],
        "SchemaVersion": "2018-10-08",
        "Title": "Test Security Finding - Incident Response",
        "UpdatedAt": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'",
        "Workflow": {
            "Status": "NEW"
        }
    }]'

# Check if the incident was processed
aws logs filter-log-events \
    --log-group-name /aws/lambda/security-incident-processor-* \
    --start-time $(date -d '5 minutes ago' +%s)000
```

## Monitoring and Observability

### CloudWatch Dashboard

The deployment creates a CloudWatch dashboard called "SecurityHubIncidentResponse" with metrics for:

- Lambda function invocations, errors, and duration
- SNS message publishing and delivery failures
- EventBridge rule invocations
- Security Hub finding trends

### CloudWatch Alarms

Pre-configured alarms monitor:

- Security incident processing failures
- SNS notification delivery failures
- EventBridge rule processing errors
- Lambda function timeout errors

### Log Groups

Key log groups for troubleshooting:

- `/aws/lambda/security-incident-processor-*`: Incident processing logs
- `/aws/lambda/threat-intelligence-lookup-*`: Threat intelligence logs
- `/aws/events/rule/security-hub-*`: EventBridge execution logs

## Integration with External Systems

### JIRA Integration

The SNS messages include structured data for JIRA ticket creation:

```json
{
    "integration": {
        "jira_project": "SEC",
        "slack_channel": "#security-incidents",
        "pagerduty_service": "security-team"
    }
}
```

### ServiceNow Integration

Configure a ServiceNow webhook endpoint to consume SQS messages for automatic incident ticket creation.

### Slack Integration

Use AWS Chatbot to send SNS notifications to Slack channels for real-time security team collaboration.

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name security-incident-response

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name security-incident-response
```

### Using CDK

```bash
# Destroy the CDK stack
cdk destroy SecurityHubIncidentResponseStack

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy the infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm resource deletion when prompted
```

## Customization

### Adding Custom Response Actions

1. Modify the Lambda function code to include additional response logic
2. Update EventBridge rules to handle new event patterns
3. Add new SNS topics for specialized notification requirements

### Integrating Additional Threat Intelligence Feeds

1. Update the threat intelligence Lambda function
2. Add API keys and endpoints as environment variables
3. Configure appropriate IAM permissions for external API access

### Enhancing Automation Rules

1. Create additional Security Hub automation rules
2. Implement more sophisticated finding classification logic
3. Add business context-aware prioritization

## Troubleshooting

### Common Issues

1. **SNS Subscription Not Confirmed**
   - Check email for confirmation message
   - Verify email address in configuration
   - Check SNS topic policies

2. **Lambda Function Timeouts**
   - Increase Lambda timeout in configuration
   - Review function logs for performance bottlenecks
   - Consider increasing memory allocation

3. **EventBridge Rules Not Triggering**
   - Verify Security Hub is enabled and receiving findings
   - Check EventBridge rule patterns and permissions
   - Review Lambda function permissions

4. **No Test Findings Generated**
   - Ensure Security Hub is properly enabled
   - Verify account permissions for batch-import-findings
   - Check Security Hub standards are enabled

### Log Analysis

Use CloudWatch Insights to analyze incident processing patterns:

```sql
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100
```

## Security Considerations

- All Lambda functions follow least-privilege IAM principles
- SNS topics and SQS queues use encryption at rest
- Security Hub findings contain sensitive data - ensure proper access controls
- Regular review of IAM permissions and automation rules
- Monitor for unauthorized changes to incident response infrastructure

## Cost Optimization

- Lambda functions use ARM-based Graviton2 processors for cost efficiency
- CloudWatch log retention set to 14 days by default
- SQS queue configured with appropriate message retention periods
- Consider reserved capacity for high-volume environments

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation for Security Hub, EventBridge, and Lambda
3. Consult AWS Well-Architected Security Pillar guidelines
4. Review AWS Security Hub best practices documentation

## Additional Resources

- [AWS Security Hub User Guide](https://docs.aws.amazon.com/securityhub/latest/userguide/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [AWS Security Best Practices](https://aws.amazon.com/security/security-learning/)
- [AWS Well-Architected Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/)