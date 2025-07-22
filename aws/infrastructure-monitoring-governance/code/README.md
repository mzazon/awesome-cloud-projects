# Infrastructure as Code for Implementing Infrastructure Monitoring with CloudTrail, Config, and Systems Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing Infrastructure Monitoring with CloudTrail, Config, and Systems Manager".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with administrative permissions for CloudTrail, Config, and Systems Manager
- At least 2-3 EC2 instances for Systems Manager demonstration
- Email address for SNS notifications
- Appropriate IAM permissions for resource creation

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions

#### CDK TypeScript
- Node.js (version 14 or later)
- npm or yarn package manager
- AWS CDK CLI installed (`npm install -g aws-cdk`)

#### CDK Python
- Python 3.7 or later
- pip package manager
- AWS CDK CLI installed (`pip install aws-cdk-lib`)

#### Terraform
- Terraform CLI (version 1.0 or later)
- AWS provider for Terraform

## Architecture Overview

This solution implements comprehensive infrastructure monitoring using:

- **AWS CloudTrail**: Audit logging for all API calls
- **AWS Config**: Configuration compliance monitoring
- **AWS Systems Manager**: Operational insights and automation
- **Amazon S3**: Centralized log storage
- **Amazon SNS**: Real-time notifications
- **Amazon CloudWatch**: Metrics and dashboard visualization

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name infrastructure-monitoring-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name infrastructure-monitoring-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name infrastructure-monitoring-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Set notification email
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy

# View stack outputs
cdk list
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Set notification email
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy

# View stack outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
# Required: notification_email = "your-email@example.com"
vim terraform.tfvars

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
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL=your-email@example.com
export AWS_REGION=us-east-1

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
# Script will provide status updates and resource ARNs
```

## Configuration Options

### Environment Variables

All implementations support these environment variables:

- `NOTIFICATION_EMAIL`: Email address for SNS notifications (required)
- `AWS_REGION`: AWS region for deployment (default: us-east-1)
- `RESOURCE_PREFIX`: Prefix for resource names (default: infra-monitoring)

### CloudFormation Parameters

- `NotificationEmail`: Email address for notifications
- `ResourcePrefix`: Prefix for all resource names
- `EnableDataEvents`: Enable CloudTrail data events (default: false)
- `ConfigRuleEvaluationPeriod`: Config rule evaluation frequency

### Terraform Variables

Key variables in `terraform.tfvars`:

```hcl
notification_email = "your-email@example.com"
resource_prefix = "infra-monitoring"
aws_region = "us-east-1"
enable_data_events = false
config_snapshot_delivery_interval = "TwentyFour_Hours"
```

## Post-Deployment Steps

1. **Confirm SNS Subscription**: Check your email and confirm the SNS subscription
2. **Verify Config Rules**: Allow 5-10 minutes for Config rules to initialize
3. **Access Dashboard**: Navigate to CloudWatch console to view the monitoring dashboard
4. **Test Notifications**: Make a configuration change to trigger alerts

## Monitoring and Validation

### Check CloudTrail Status

```bash
# Get trail status
aws cloudtrail get-trail-status --name $(terraform output -raw cloudtrail_name)

# View recent events
aws cloudtrail lookup-events --max-items 5
```

### Verify Config Compliance

```bash
# Check Config rules
aws configservice describe-config-rules

# Get compliance summary
aws configservice get-compliance-summary-by-config-rule
```

### Access CloudWatch Dashboard

```bash
# Get dashboard URL
echo "https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=InfrastructureMonitoring"
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name infrastructure-monitoring-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name infrastructure-monitoring-stack
```

### Using CDK (AWS)

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run destroy script
./scripts/destroy.sh

# Confirm deletion when prompted
# Script will remove resources in reverse order
```

## Cost Considerations

This solution incurs costs for:

- **CloudTrail**: API logging charges
- **Config**: Configuration recording and rule evaluations
- **S3**: Log storage (can be optimized with lifecycle policies)
- **SNS**: Notification delivery
- **CloudWatch**: Dashboard and custom metrics

Estimated monthly cost: $50-100 depending on:
- Number of API calls
- Amount of configuration data
- Retention periods
- Notification frequency

## Security Features

- IAM roles with least-privilege permissions
- S3 bucket encryption and access controls
- CloudTrail log file validation
- Config rule compliance monitoring
- Systems Manager secure session management

## Troubleshooting

### Common Issues

1. **Config Rules Not Active**: Wait 5-10 minutes after deployment for initialization
2. **SNS Notifications Not Received**: Verify email subscription confirmation
3. **CloudTrail Events Missing**: Check IAM permissions and trail status
4. **Dashboard Empty**: Allow time for metrics to populate (15-30 minutes)

### Support Commands

```bash
# Check IAM roles
aws iam list-roles --query 'Roles[?contains(RoleName, `Config`)]'

# Verify S3 bucket
aws s3 ls s3://$(terraform output -raw monitoring_bucket_name)

# Check SNS topic
aws sns list-subscriptions-by-topic \
    --topic-arn $(terraform output -raw sns_topic_arn)
```

## Customization

### Adding Custom Config Rules

Modify the appropriate IaC template to include additional Config rules:

```yaml
# CloudFormation example
CustomConfigRule:
  Type: AWS::Config::ConfigRule
  Properties:
    ConfigRuleName: your-custom-rule
    Source:
      Owner: AWS
      SourceIdentifier: YOUR_RULE_IDENTIFIER
```

### Extending Monitoring

- Add custom CloudWatch metrics
- Integrate with AWS Security Hub
- Set up automated remediation with Lambda
- Configure cross-account monitoring

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review AWS service documentation:
   - [CloudTrail User Guide](https://docs.aws.amazon.com/cloudtrail/)
   - [Config Developer Guide](https://docs.aws.amazon.com/config/)
   - [Systems Manager User Guide](https://docs.aws.amazon.com/systems-manager/)
3. Verify IAM permissions and service limits
4. Check AWS service health dashboard

## Version Information

- Recipe Version: 1.1
- Last Updated: 2025-07-12
- Compatible AWS CLI: v2.0+
- Compatible CDK: v2.0+
- Compatible Terraform: v1.0+