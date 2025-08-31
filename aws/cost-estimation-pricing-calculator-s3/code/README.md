# Infrastructure as Code for Cost Estimation Planning with Pricing Calculator and S3

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cost Estimation Planning with Pricing Calculator and S3".

## Overview

This solution creates a centralized cost estimation planning system using AWS services to store, organize, and monitor cost estimates generated from AWS Pricing Calculator. The infrastructure includes S3 storage with lifecycle policies, SNS notifications for budget alerts, and AWS Budgets for proactive cost monitoring.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Infrastructure Components

- **S3 Bucket**: Centralized storage for cost estimates with versioning and encryption
- **S3 Lifecycle Policy**: Automatic cost optimization through storage class transitions
- **SNS Topic**: Notification system for budget alerts
- **AWS Budget**: Proactive cost monitoring with configurable thresholds
- **IAM Roles and Policies**: Secure access controls for cost management

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- Appropriate AWS permissions for:
  - S3 bucket creation and management
  - SNS topic creation and management
  - AWS Budgets creation and management
  - IAM role and policy creation
- For CDK deployments: Node.js 14+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Estimated cost: $0.50-$2.00/month for S3 storage and budget notifications

## Quick Start

### Using CloudFormation

```bash
# Create the stack
aws cloudformation create-stack \
    --stack-name cost-estimation-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=my-project \
                 ParameterKey=BudgetAmount,ParameterValue=50 \
    --capabilities CAPABILITY_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name cost-estimation-stack

# View stack outputs
aws cloudformation describe-stacks \
    --stack-name cost-estimation-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not done previously)
cdk bootstrap

# Deploy the stack
cdk deploy CostEstimationStack \
    --parameters projectName=my-project \
    --parameters budgetAmount=50

# View stack outputs
cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not done previously)
cdk bootstrap

# Deploy the stack
cdk deploy CostEstimationStack \
    -c project_name=my-project \
    -c budget_amount=50

# View stack outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="project_name=my-project" \
    -var="budget_amount=50"

# Apply the configuration
terraform apply \
    -var="project_name=my-project" \
    -var="budget_amount=50"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_NAME="my-project"
export BUDGET_AMOUNT="50"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment results
echo "S3 Bucket: $(cat /tmp/cost-estimation-outputs.txt | grep BUCKET_NAME)"
echo "SNS Topic: $(cat /tmp/cost-estimation-outputs.txt | grep TOPIC_ARN)"
```

## Configuration Parameters

### Required Parameters

- **Project Name**: Identifier for tagging and organizing resources
- **Budget Amount**: Monthly budget limit in USD for cost monitoring

### Optional Parameters

- **AWS Region**: Deployment region (defaults to current CLI region)
- **Notification Email**: Email address for budget alerts (if different from default)
- **Storage Class Transition Days**: Days before transitioning to different S3 storage classes
- **Budget Threshold**: Percentage threshold for budget alerts (default: 80%)

## Usage Instructions

### 1. Store Cost Estimates

After deploying the infrastructure, upload cost estimates from AWS Pricing Calculator:

```bash
# Get bucket name from stack outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name cost-estimation-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
    --output text)

# Upload estimate file with metadata
aws s3 cp my-estimate.csv \
    s3://${BUCKET_NAME}/projects/my-project/estimate-$(date +%Y%m%d).csv \
    --metadata "project=my-project,created-by=finance-team" \
    --tagging "Project=my-project&Department=Finance"
```

### 2. Organize Estimates

Use the predefined folder structure for better organization:

```bash
# Upload to quarterly folder
aws s3 cp quarterly-estimate.csv \
    s3://${BUCKET_NAME}/estimates/2025/Q1/quarterly-estimate.csv

# Upload project-specific estimates
aws s3 cp project-estimate.csv \
    s3://${BUCKET_NAME}/projects/web-migration/estimate.csv

# Archive old estimates
aws s3 cp old-estimate.csv \
    s3://${BUCKET_NAME}/archived/2024/old-estimate.csv
```

### 3. Monitor Costs

The deployed budget will automatically monitor spending and send alerts:

```bash
# View current budget status
aws budgets describe-budget \
    --account-id $(aws sts get-caller-identity --query Account --output text) \
    --budget-name my-project-budget

# Subscribe to budget notifications (if not done during deployment)
aws sns subscribe \
    --topic-arn $(aws cloudformation describe-stacks \
        --stack-name cost-estimation-stack \
        --query 'Stacks[0].Outputs[?OutputKey==`TopicArn`].OutputValue' \
        --output text) \
    --protocol email \
    --notification-endpoint your-email@example.com
```

## Cleanup

### Using CloudFormation

```bash
# Empty the S3 bucket first (required for deletion)
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name cost-estimation-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
    --output text)

aws s3 rm s3://${BUCKET_NAME} --recursive

# Delete all object versions
aws s3api delete-objects \
    --bucket ${BUCKET_NAME} \
    --delete "$(aws s3api list-object-versions \
        --bucket ${BUCKET_NAME} \
        --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || true

# Delete the stack
aws cloudformation delete-stack --stack-name cost-estimation-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name cost-estimation-stack
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy CostEstimationStack --force

# Clean up local dependencies (optional)
rm -rf node_modules/  # TypeScript
# or
rm -rf .venv/  # Python
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="project_name=my-project" \
    -var="budget_amount=50" \
    -auto-approve

# Clean up Terraform state (optional)
rm -rf .terraform/ terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Clean up temporary files
rm -f /tmp/cost-estimation-outputs.txt
```

## Customization

### Modifying Storage Lifecycle

To customize S3 storage class transitions, modify the lifecycle policy in your chosen IaC implementation:

- **Standard to Standard-IA**: Default 30 days
- **Standard-IA to Glacier**: Default 90 days
- **Glacier to Deep Archive**: Default 365 days

### Adding Custom Tags

Enhance cost allocation by adding custom tags to resources:

```yaml
# CloudFormation example
Tags:
  - Key: Environment
    Value: Production
  - Key: CostCenter
    Value: Finance
  - Key: Owner
    Value: FinanceTeam
```

### Custom Budget Thresholds

Configure multiple budget alerts at different thresholds:

- 50% - Early warning
- 80% - Standard alert (default)
- 100% - Critical alert
- 110% - Overspend alert

## Monitoring and Operations

### Health Checks

Verify the system is functioning correctly:

```bash
# Check S3 bucket accessibility
aws s3 ls s3://your-bucket-name/

# Verify lifecycle policy
aws s3api get-bucket-lifecycle-configuration --bucket your-bucket-name

# Check budget status
aws budgets describe-budget \
    --account-id $(aws sts get-caller-identity --query Account --output text) \
    --budget-name your-project-budget

# Test SNS notifications
aws sns publish \
    --topic-arn your-topic-arn \
    --message "Test budget notification"
```

### Cost Optimization

Monitor and optimize storage costs:

```bash
# Analyze storage class distribution
aws s3api list-objects-v2 \
    --bucket your-bucket-name \
    --query 'Contents[].{Key:Key,StorageClass:StorageClass,Size:Size}'

# Calculate current storage costs by class
aws ce get-cost-and-usage \
    --time-period Start=2025-01-01,End=2025-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Troubleshooting

### Common Issues

1. **Bucket Creation Failure**: Bucket names must be globally unique
   - Solution: The IaC includes random suffixes to ensure uniqueness

2. **Budget Creation Permissions**: Insufficient permissions for Budgets API
   - Solution: Ensure the deploying user has `budgets:CreateBudget` permission

3. **SNS Subscription Issues**: Email not receiving notifications
   - Solution: Check SNS subscription confirmation email and confirm subscription

4. **Lifecycle Policy Not Applied**: Objects not transitioning between storage classes
   - Solution: Verify policy syntax and ensure sufficient time has passed

### Debug Commands

```bash
# Check CloudFormation stack events for errors
aws cloudformation describe-stack-events --stack-name cost-estimation-stack

# Validate CloudFormation template
aws cloudformation validate-template --template-body file://cloudformation.yaml

# Check CDK diff before deployment
cdk diff

# Terraform plan with detailed logging
TF_LOG=DEBUG terraform plan
```

## Security Considerations

- **S3 Bucket Encryption**: All data encrypted at rest using AES-256
- **Access Controls**: Least privilege IAM policies for all resources
- **Versioning**: Enabled for data protection and compliance
- **Budget Notifications**: Secure SNS delivery to authorized recipients only

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for context
2. Check AWS service limits and quotas
3. Verify IAM permissions for all required services
4. Consult AWS documentation for service-specific guidance:
   - [S3 User Guide](https://docs.aws.amazon.com/s3/)
   - [AWS Budgets User Guide](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html)
   - [SNS Developer Guide](https://docs.aws.amazon.com/sns/)

## Related Resources

- [AWS Pricing Calculator](https://calculator.aws/)
- [AWS Cost Management Console](https://console.aws.amazon.com/cost-management/)
- [S3 Storage Classes Comparison](https://aws.amazon.com/s3/storage-classes/)
- [AWS Well-Architected Cost Optimization Pillar](https://docs.aws.amazon.com/wellarchitected/latest/cost-optimization-pillar/)