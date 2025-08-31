# Infrastructure as Code for Community Knowledge Base with re:Post Private and SNS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Community Knowledge Base with re:Post Private and SNS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- AWS Enterprise Support or Enterprise On-Ramp Support plan (required for re:Post Private)
- Organization admin access to create and configure re:Post Private
- Email addresses for team members who will receive notifications
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)

### Required AWS Permissions

The deployment requires permissions for:
- SNS topic creation and management
- SNS subscription management
- re:Post Private access (via Enterprise Support)
- IAM role creation (for some implementations)

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name community-knowledge-base-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=TeamEmails,ParameterValue="developer1@company.com,developer2@company.com,teamlead@company.com" \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name community-knowledge-base-stack \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name community-knowledge-base-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to the CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Set team emails as context
cdk deploy --context teamEmails="developer1@company.com,developer2@company.com,teamlead@company.com"

# View stack outputs
cdk ls --long
```

### Using CDK Python

```bash
# Navigate to the CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Set environment variables for team emails
export TEAM_EMAILS="developer1@company.com,developer2@company.com,teamlead@company.com"

# Deploy the stack
cdk deploy

# View stack outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create a terraform.tfvars file with your configuration
cat > terraform.tfvars << 'EOF'
team_emails = [
  "developer1@company.com",
  "developer2@company.com",
  "teamlead@company.com"
]
organization_name = "Your Company Name"
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

# Set environment variables
export TEAM_EMAILS="developer1@company.com,developer2@company.com,teamlead@company.com"
export ORGANIZATION_NAME="Your Company Name"

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
aws sns list-topics | grep knowledge-notifications
```

## Post-Deployment Configuration

After deploying the infrastructure, complete these manual configuration steps:

### 1. Configure re:Post Private

1. Access re:Post Private console: https://console.aws.amazon.com/repost-private/
2. Sign in with IAM Identity Center credentials
3. Complete the initial configuration wizard:
   - Set organization title and welcome message
   - Upload company logo (max 2 MiB, 150x50px recommended)
   - Configure branding colors
   - Select relevant AWS service topics
   - Create custom tags for internal projects

### 2. Confirm Email Subscriptions

Team members will receive confirmation emails for SNS subscriptions. Each person must:
1. Check their email inbox for AWS SNS confirmation
2. Click the "Confirm subscription" link
3. Verify successful subscription in the AWS SNS console

### 3. Create Initial Content

Use the deployed infrastructure to create foundational knowledge base content:
- Welcome articles for team onboarding
- Common troubleshooting procedures
- Best practices documentation
- Discussion forums for ongoing collaboration

### 4. Test Notification System

Send a test notification to verify the system is working:

```bash
# Get the SNS topic ARN from outputs
TOPIC_ARN=$(aws cloudformation describe-stacks \
    --stack-name community-knowledge-base-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' \
    --output text)

# Send test notification
aws sns publish \
    --topic-arn ${TOPIC_ARN} \
    --subject "Knowledge Base Alert: Test Notification" \
    --message "Test notification from your enterprise knowledge base system."
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name community-knowledge-base-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name community-knowledge-base-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy
```

### Using CDK Python

```bash
cd cdk-python/
cdk destroy

# Deactivate virtual environment
deactivate
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify resources are deleted
aws sns list-topics | grep knowledge-notifications || echo "SNS topic deleted successfully"
```

### Manual Cleanup for re:Post Private

> **Important**: re:Post Private requires manual deactivation through AWS Support.

1. Export valuable discussions and content before deactivation
2. Save custom configurations and branding assets
3. Contact AWS Support to request re:Post Private deactivation
4. Document lessons learned and usage metrics for future reference

## Customization

### Environment Variables

All implementations support these customization options:

- **Team Emails**: List of email addresses for notifications
- **Organization Name**: Your company name for branding
- **AWS Region**: Deployment region (default: us-east-1)
- **Topic Name**: Custom SNS topic name (auto-generated with random suffix)

### CloudFormation Parameters

- `TeamEmails`: Comma-separated list of email addresses
- `OrganizationName`: Organization name for resource tagging
- `Environment`: Environment tag (default: production)

### CDK Context Values

- `teamEmails`: String with comma-separated email addresses
- `organizationName`: Organization name for resource naming
- `environment`: Deployment environment

### Terraform Variables

- `team_emails`: List of email addresses
- `organization_name`: Organization name
- `aws_region`: AWS region for deployment
- `environment`: Environment tag
- `tags`: Additional resource tags

## Architecture Components

This infrastructure deploys:

1. **SNS Topic**: Central hub for knowledge base notifications
2. **Email Subscriptions**: Individual subscriptions for each team member
3. **IAM Roles**: Service roles for SNS operations (where applicable)
4. **Resource Tags**: Consistent tagging for resource management

The infrastructure integrates with:
- **AWS re:Post Private**: Enterprise knowledge base platform (manual configuration required)
- **AWS Enterprise Support**: Required for re:Post Private access
- **Email Systems**: For notification delivery to team members

## Monitoring and Maintenance

### CloudWatch Metrics

Monitor these key metrics:
- SNS message delivery success/failure rates
- Number of confirmed vs. pending subscriptions
- re:Post Private engagement metrics (via console)

### Cost Optimization

- SNS email notifications: ~$0.50-$2.00/month (after free tier)
- re:Post Private: Included with Enterprise Support at no additional cost
- Consider subscription filters to reduce notification volume if needed

### Security Considerations

- Email subscriptions require explicit confirmation
- SNS topics use AWS managed encryption by default
- re:Post Private data remains within your AWS organization
- All resources follow least-privilege access principles

## Troubleshooting

### Common Issues

1. **re:Post Private Access Denied**
   - Verify Enterprise Support plan is active
   - Check IAM Identity Center permissions
   - Confirm organization admin access

2. **Email Subscriptions Not Confirmed**
   - Check team members' spam/junk folders
   - Verify email addresses are correct
   - Resend confirmation if needed

3. **SNS Notifications Not Received**
   - Verify subscriptions are confirmed
   - Check SNS topic permissions
   - Test with manual publish command

### Validation Commands

```bash
# Check Enterprise Support status
aws support describe-services --language en 2>/dev/null || \
    echo "Enterprise Support required for re:Post Private"

# Verify SNS topic configuration
aws sns get-topic-attributes --topic-arn ${TOPIC_ARN}

# List subscription status
aws sns list-subscriptions-by-topic --topic-arn ${TOPIC_ARN}
```

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check AWS documentation for service-specific guidance
3. Contact AWS Support for re:Post Private configuration assistance
4. Review CloudFormation/CDK/Terraform provider documentation for deployment issues

## Additional Resources

- [AWS re:Post Private User Guide](https://docs.aws.amazon.com/repostprivate/latest/userguide/what-is.html)
- [Amazon SNS Developer Guide](https://docs.aws.amazon.com/sns/latest/dg/)
- [AWS Enterprise Support](https://aws.amazon.com/premiumsupport/plans/enterprise/)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/)