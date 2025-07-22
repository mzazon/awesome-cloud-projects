# Infrastructure as Code for Intelligent Cloud Threat Detection

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent Cloud Threat Detection".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon GuardDuty (create detector, manage findings)
  - Amazon SNS (create topics, manage subscriptions)
  - Amazon EventBridge (create rules, manage targets)
  - Amazon CloudWatch (create dashboards)
  - Amazon S3 (create buckets, manage objects)
  - IAM (create roles and policies)
- Valid email address for threat notifications
- Estimated cost: $3-10 per month (30-day free trial available)

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions

#### CDK TypeScript
- Node.js 18.x or later
- npm or yarn package manager
- AWS CDK CLI: `npm install -g aws-cdk`

#### CDK Python
- Python 3.8 or later
- pip package manager
- AWS CDK CLI: `pip install aws-cdk-lib`

#### Terraform
- Terraform 1.0 or later
- AWS provider for Terraform

## Quick Start

### Using CloudFormation
```bash
# Deploy the GuardDuty threat detection stack
aws cloudformation create-stack \
    --stack-name guardduty-threat-detection \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name guardduty-threat-detection

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name guardduty-threat-detection \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set your notification email
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set your notification email
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
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
EOF

# Plan the deployment
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

# Set your notification email
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment outputs
cat deployment-outputs.txt
```

## Post-Deployment Steps

1. **Confirm Email Subscription**: Check your email and confirm the SNS subscription to receive GuardDuty alerts.

2. **Verify GuardDuty**: Navigate to the GuardDuty console to confirm the detector is enabled and monitoring.

3. **Test Notifications**: Use the GuardDuty console to generate sample findings and verify alert delivery.

4. **Review Dashboard**: Access the CloudWatch dashboard to monitor security metrics.

## Configuration Options

### Email Notifications
All implementations support configuring the email address for threat notifications:

- **CloudFormation**: Set `NotificationEmail` parameter
- **CDK**: Set `NOTIFICATION_EMAIL` environment variable
- **Terraform**: Set `notification_email` variable
- **Bash**: Set `NOTIFICATION_EMAIL` environment variable

### Finding Export
The S3 bucket for GuardDuty findings export is automatically created with:
- Versioning enabled
- Server-side encryption
- Public access blocked
- Lifecycle policies for cost optimization

### EventBridge Rules
The implementation creates EventBridge rules to capture:
- All GuardDuty findings (for immediate alerts)
- High and critical severity findings (for enhanced monitoring)

## Monitoring and Alerting

### CloudWatch Dashboard
The deployment creates a comprehensive security monitoring dashboard including:
- GuardDuty findings count over time
- Findings by severity level
- Findings by type
- Regional threat distribution

### SNS Notifications
Real-time email alerts are sent for:
- All GuardDuty findings
- Formatted with finding details and recommended actions
- Includes direct links to AWS console for investigation

### S3 Export
GuardDuty findings are automatically exported to S3 for:
- Long-term retention and compliance
- Advanced analytics and reporting
- Integration with external SIEM tools

## Security Considerations

### IAM Permissions
All implementations follow the principle of least privilege:
- Service-specific roles with minimal required permissions
- Cross-service trust relationships properly configured
- No hardcoded credentials or overly permissive policies

### Data Protection
- GuardDuty findings contain sensitive security information
- S3 bucket access is restricted to authorized personnel only
- SNS topic access is limited to the EventBridge service
- All data in transit and at rest is encrypted

### Cost Management
- GuardDuty pricing is based on log volume analyzed
- S3 lifecycle policies automatically transition old findings to cheaper storage classes
- CloudWatch dashboard uses efficient metric queries to minimize costs

## Cleanup

### Using CloudFormation
```bash
# Delete the stack and all resources
aws cloudformation delete-stack \
    --stack-name guardduty-threat-detection

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name guardduty-threat-detection
```

### Using CDK
```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Troubleshooting

### Common Issues

1. **Email Subscription Pending**: 
   - Check spam folder for confirmation email
   - Resend confirmation from SNS console if needed

2. **GuardDuty Not Generating Findings**:
   - GuardDuty requires 7-14 days to establish baseline behavior
   - Use "Generate sample findings" in console for immediate testing

3. **S3 Bucket Access Denied**:
   - Verify IAM permissions for GuardDuty service role
   - Check bucket policy allows GuardDuty to write objects

4. **EventBridge Rule Not Triggering**:
   - Verify rule pattern matches GuardDuty event format
   - Check SNS topic permissions allow EventBridge to publish

### Validation Steps

```bash
# Check GuardDuty detector status
aws guardduty list-detectors

# Verify SNS topic and subscription
aws sns list-topics | grep guardduty
aws sns list-subscriptions

# Test EventBridge rule
aws events test-event-pattern \
    --event-pattern file://test-pattern.json \
    --event file://test-event.json

# Check CloudWatch dashboard
aws cloudwatch list-dashboards | grep GuardDuty
```

## Customization

### Adding Custom Threat Intelligence
Extend the implementation to include custom threat intelligence feeds:

```bash
# Example: Add custom IP threat list
aws guardduty create-threat-intel-set \
    --detector-id <detector-id> \
    --name "Custom-Threat-IPs" \
    --format TXT \
    --location s3://your-bucket/threat-ips.txt
```

### Enhanced Alerting
Modify EventBridge rules to filter findings by:
- Severity level (HIGH, MEDIUM, LOW)
- Finding type (specific threat categories)
- Resource tags (production vs development)

### Integration with SOAR
Extend SNS notifications to trigger Security Orchestration and Response platforms:
- Add Lambda function as SNS target
- Parse GuardDuty findings and format for SOAR APIs
- Implement automated response playbooks

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS GuardDuty documentation
3. Verify AWS service limits and quotas
4. Contact AWS Support for service-specific issues

## Additional Resources

- [Amazon GuardDuty User Guide](https://docs.aws.amazon.com/guardduty/latest/ug/)
- [GuardDuty Finding Types](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_finding-types-active.html)
- [GuardDuty Pricing](https://aws.amazon.com/guardduty/pricing/)
- [EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [SNS User Guide](https://docs.aws.amazon.com/sns/latest/dg/)