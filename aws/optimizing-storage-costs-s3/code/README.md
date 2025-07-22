# Infrastructure as Code for Optimizing Storage Costs with S3 Classes

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Optimizing Storage Costs with S3 Classes".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured
- Appropriate AWS permissions for:
  - S3 bucket creation and management
  - CloudWatch dashboard creation
  - AWS Budgets management
  - IAM role creation for analytics and monitoring
- For CDK implementations: Node.js 18+ and AWS CDK v2
- For Terraform: Terraform 1.0+
- Estimated cost: $5-15 for testing resources and monitoring

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name storage-cost-optimization-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BucketName,ParameterValue=my-optimization-bucket-$(date +%s)

# Monitor deployment
aws cloudformation describe-stacks \
    --stack-name storage-cost-optimization-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
# Install dependencies
cd cdk-typescript/
npm install

# Deploy the infrastructure
cdk deploy

# View outputs
cdk describe
```

### Using CDK Python

```bash
# Install dependencies
cd cdk-python/
pip install -r requirements.txt

# Deploy the infrastructure
cdk deploy

# View outputs
cdk describe
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

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

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
aws s3 ls | grep storage-optimization
```

## Infrastructure Components

This IaC deployment creates the following resources:

### Core Storage Resources
- **S3 Bucket**: Primary storage bucket with versioning enabled
- **Storage Class Analysis**: Configured to analyze access patterns
- **Intelligent Tiering**: Automatic cost optimization based on access patterns
- **Lifecycle Policies**: Custom rules for different data types

### Monitoring and Analytics
- **CloudWatch Dashboard**: Real-time storage metrics visualization
- **CloudWatch Metrics**: Custom metrics for storage cost tracking
- **AWS Budgets**: Cost alerting and budget management
- **Cost Analysis**: Automated reporting capabilities

### Security and Compliance
- **IAM Roles**: Least privilege access for services
- **Bucket Policies**: Secure access controls
- **Encryption**: Server-side encryption enabled by default

## Configuration Options

### Environment Variables

```bash
# Required variables
export AWS_REGION=us-east-1
export BUCKET_NAME=my-storage-optimization-bucket
export NOTIFICATION_EMAIL=admin@example.com

# Optional variables
export BUDGET_AMOUNT=50
export ANALYTICS_PREFIX=data/
export LIFECYCLE_TRANSITION_DAYS=30
```

### Terraform Variables

Key variables you can customize in `terraform/variables.tf`:

- `bucket_name`: Name of the S3 bucket (must be globally unique)
- `budget_amount`: Monthly budget threshold in USD
- `notification_email`: Email for budget alerts
- `analytics_prefix`: S3 prefix for storage analytics
- `enable_intelligent_tiering`: Enable/disable intelligent tiering
- `lifecycle_transition_days`: Days before transitioning to IA storage

### CloudFormation Parameters

Customize deployment via CloudFormation parameters:

- `BucketName`: S3 bucket name
- `BudgetAmount`: Monthly budget limit
- `NotificationEmail`: Alert email address
- `AnalyticsPrefix`: Storage analytics prefix
- `EnableIntelligentTiering`: Enable intelligent tiering (true/false)

## Validation

After deployment, validate the infrastructure:

```bash
# Check S3 bucket configuration
aws s3api get-bucket-analytics-configuration \
    --bucket <bucket-name> \
    --id storage-analytics

# Verify lifecycle policies
aws s3api get-bucket-lifecycle-configuration \
    --bucket <bucket-name>

# Check CloudWatch dashboard
aws cloudwatch list-dashboards \
    --dashboard-name-prefix "S3-Storage-Cost-Optimization"

# Verify budget creation
aws budgets describe-budget \
    --account-id <account-id> \
    --budget-name <budget-name>
```

## Cost Optimization Features

### Automatic Transitions
- **Day 1-30**: Objects remain in S3 Standard
- **Day 30+**: Transition to Standard-IA (40% cost reduction)
- **Day 90+**: Transition to Glacier (80% cost reduction)
- **Day 365+**: Transition to Deep Archive (95% cost reduction)

### Intelligent Tiering
- Automatically moves objects between access tiers
- No retrieval fees for frequently accessed data
- Optimizes costs based on actual access patterns

### Monitoring and Alerts
- Real-time cost tracking via CloudWatch
- Budget alerts at 80% of monthly threshold
- Storage analytics for access pattern insights

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name storage-cost-optimization-stack

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name storage-cost-optimization-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy the infrastructure
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm deletion
cdk list
```

### Using Terraform

```bash
# Destroy infrastructure
cd terraform/
terraform destroy

# Confirm cleanup
terraform show
```

### Using Bash Scripts

```bash
# Clean up all resources
./scripts/destroy.sh

# Verify cleanup
aws s3 ls | grep storage-optimization
```

## Troubleshooting

### Common Issues

1. **Bucket Name Conflicts**
   - S3 bucket names must be globally unique
   - Add a random suffix or timestamp to bucket names

2. **IAM Permissions**
   - Ensure your AWS credentials have sufficient permissions
   - Check CloudTrail logs for permission errors

3. **Budget Notifications**
   - Verify email address is correct and confirmed
   - Check spam folder for AWS budget notifications

4. **CloudWatch Metrics**
   - Metrics may take 24-48 hours to appear
   - Ensure proper IAM permissions for CloudWatch

### Debugging Commands

```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
    --stack-name storage-cost-optimization-stack

# View CDK synthesis output
cdk synth

# Debug Terraform with verbose logging
TF_LOG=DEBUG terraform apply

# Check S3 bucket policies
aws s3api get-bucket-policy --bucket <bucket-name>
```

## Customization

### Adding Custom Lifecycle Rules

Modify the lifecycle policies to match your data patterns:

```json
{
  "Rules": [
    {
      "ID": "CustomDataRule",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "custom-data/"
      },
      "Transitions": [
        {
          "Days": 7,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 30,
          "StorageClass": "GLACIER"
        }
      ]
    }
  ]
}
```

### Custom CloudWatch Metrics

Add additional metrics for specific use cases:

```bash
# Custom metric for application-specific storage
aws cloudwatch put-metric-data \
    --namespace "Custom/S3Storage" \
    --metric-data MetricName=ApplicationStorage,Value=1024,Unit=Bytes
```

### Integration with Other AWS Services

Extend the solution by integrating with:

- **AWS Lambda**: Automated cost optimization functions
- **AWS Step Functions**: Complex workflow orchestration
- **Amazon SNS**: Enhanced notification capabilities
- **AWS Config**: Compliance monitoring

## Best Practices

1. **Regular Monitoring**: Review storage analytics reports monthly
2. **Lifecycle Policy Testing**: Test with non-production data first
3. **Cost Alerting**: Set appropriate budget thresholds
4. **Access Pattern Analysis**: Use analytics data for optimization decisions
5. **Security Reviews**: Regularly audit IAM permissions and bucket policies

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review AWS documentation for specific services
3. Validate IAM permissions and resource configurations
4. Use AWS CloudTrail for debugging API calls
5. Consult AWS Support for service-specific issues

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment first
2. Update variable descriptions and validation rules
3. Ensure backward compatibility with existing deployments
4. Document any breaking changes
5. Update cost estimates based on resource changes