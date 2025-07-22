# Infrastructure as Code for Organizing Resources with Groups and Automated Management

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Organizing Resources with Groups and Automated Management".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - AWS Resource Groups
  - AWS Systems Manager
  - Amazon CloudWatch
  - Amazon SNS
  - AWS IAM
  - AWS Budgets
  - AWS Cost Explorer
  - AWS EventBridge
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

## Architecture Overview

This infrastructure creates:

- **Resource Groups**: Tag-based resource organization system
- **Systems Manager**: Automation documents and IAM roles for resource management
- **CloudWatch**: Monitoring dashboards, alarms, and metrics
- **SNS**: Notification topics for alerts and monitoring
- **EventBridge**: Rules for automated resource tagging
- **Budgets**: Cost tracking and anomaly detection
- **IAM**: Roles and policies for service integration

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name resource-groups-automation \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name resource-groups-automation \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
# Navigate to CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters notificationEmail=your-email@example.com

# View outputs
cdk outputs
```

### Using CDK Python

```bash
# Navigate to CDK directory
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters notificationEmail=your-email@example.com

# View outputs
cdk outputs
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the plan
terraform plan -var="notification_email=your-email@example.com"

# Apply the configuration
terraform apply -var="notification_email=your-email@example.com"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL="your-email@example.com"
export AWS_REGION="us-east-1"  # or your preferred region

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/status.sh
```

## Configuration Parameters

### Required Parameters

- **NotificationEmail** / **notification_email**: Email address for SNS notifications and budget alerts
- **Environment**: Environment tag (default: "production")
- **Application**: Application tag (default: "web-app")

### Optional Parameters

- **BudgetAmount**: Monthly budget limit in USD (default: 100)
- **CPUThreshold**: CPU utilization alarm threshold percentage (default: 80)
- **ResourceGroupName**: Custom name for the resource group (auto-generated if not provided)

## Post-Deployment Setup

### 1. Confirm SNS Subscription

After deployment, check your email for SNS subscription confirmation and click the confirmation link.

### 2. Verify Resource Group Population

```bash
# List resources in the created resource group
aws resource-groups list-group-resources \
    --group-name $(aws resource-groups list-groups \
        --query 'GroupIdentifiers[0].GroupName' --output text)
```

### 3. Test Monitoring System

The deployment includes a test notification to verify the system is working correctly.

### 4. Create Sample Resources (Optional)

If you don't have existing resources with the required tags, create some test resources:

```bash
# Create test EC2 instance with proper tags
aws ec2 run-instances \
    --image-id ami-0abcdef1234567890 \
    --instance-type t2.micro \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Environment,Value=production},{Key=Application,Value=web-app}]'

# Create test S3 bucket with proper tags
aws s3 mb s3://test-bucket-$(date +%s) \
    --region us-east-1
aws s3api put-bucket-tagging \
    --bucket test-bucket-$(date +%s) \
    --tagging 'TagSet=[{Key=Environment,Value=production},{Key=Application,Value=web-app}]'
```

## Monitoring and Management

### CloudWatch Dashboard

Access your monitoring dashboard:

```bash
# Get dashboard URL
aws cloudwatch get-dashboard \
    --dashboard-name $(terraform output -raw dashboard_name) \
    --query 'DashboardArn'
```

### Systems Manager Automation

Execute maintenance tasks:

```bash
# Run resource group maintenance
aws ssm start-automation-execution \
    --document-name $(terraform output -raw automation_document_name) \
    --parameters "ResourceGroupName=$(terraform output -raw resource_group_name)"
```

### Cost Monitoring

View budget status:

```bash
# Check budget status
aws budgets describe-budget \
    --account-id $(aws sts get-caller-identity --query Account --output text) \
    --budget-name $(terraform output -raw budget_name)
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name resource-groups-automation

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name resource-groups-automation \
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
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="notification_email=your-email@example.com"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Customization

### Extending Resource Group Queries

Modify the resource group query to include additional resource types or tags:

```json
{
  "Type": "TAG_FILTERS_1_0",
  "Query": "{\"ResourceTypeFilters\":[\"AWS::AllSupported\"],\"TagFilters\":[{\"Key\":\"Environment\",\"Values\":[\"production\",\"staging\"]},{\"Key\":\"Application\",\"Values\":[\"web-app\",\"mobile-app\"]}]}"
}
```

### Adding Custom Automation Documents

Create additional Systems Manager automation documents for:
- Automated backup scheduling
- Security compliance checks
- Cost optimization recommendations
- Resource lifecycle management

### Enhanced Monitoring

Extend CloudWatch monitoring with:
- Custom business metrics
- Application-specific dashboards
- Advanced anomaly detection
- Integration with third-party tools

## Security Considerations

- **IAM Roles**: All roles follow least privilege principle
- **Encryption**: SNS topics and CloudWatch logs are encrypted
- **Access Control**: Resource groups respect existing IAM policies
- **Audit Trail**: All automation activities are logged in CloudTrail

## Troubleshooting

### Common Issues

1. **SNS Subscription Not Confirmed**
   - Check email spam folder
   - Ensure email address is correct
   - Re-confirm subscription manually

2. **Resource Group Empty**
   - Verify resources have required tags
   - Check tag key and value spelling
   - Ensure resources are in correct region

3. **Budget Alerts Not Working**
   - Verify SNS topic subscription
   - Check budget configuration
   - Ensure Cost Explorer is enabled

4. **Automation Execution Failures**
   - Check IAM role permissions
   - Verify resource group exists
   - Review CloudWatch logs

### Getting Help

- Review AWS CloudFormation/CDK documentation
- Check Systems Manager automation logs
- Verify IAM permissions and policies
- Consult AWS Resource Groups documentation

## Cost Estimates

Expected monthly costs (us-east-1 region):
- CloudWatch custom metrics: $0.30 per metric
- SNS notifications: $0.50 per million notifications
- Systems Manager automation: $0.0025 per execution
- AWS Budgets: $0.02 per budget
- **Total estimated cost**: $15-25/month

Costs may vary based on:
- Number of resources monitored
- Frequency of automation executions
- Number of notifications sent
- CloudWatch metric retention period

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS service documentation
3. Verify IAM permissions and service limits
4. Review CloudWatch logs for detailed error information