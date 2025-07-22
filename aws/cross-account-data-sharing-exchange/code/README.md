# Infrastructure as Code for Cross-Account Data Sharing with Data Exchange

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cross-Account Data Sharing with Data Exchange".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Two AWS accounts (provider and subscriber) with appropriate Data Exchange permissions
- IAM permissions for creating roles, policies, S3 buckets, Lambda functions, and EventBridge rules
- Understanding of cross-account access patterns and Data Exchange concepts
- Estimated cost: $50-100/month for data transfer and storage (varies by data volume)

## Architecture Overview

This implementation deploys:

- **S3 Buckets**: Provider and subscriber data storage
- **IAM Roles**: Data Exchange service permissions and cross-account access
- **Data Exchange Resources**: Data sets, revisions, and data grants
- **Lambda Functions**: Automated notifications and data updates
- **EventBridge Rules**: Event-driven automation and monitoring
- **CloudWatch Resources**: Logging, monitoring, and alerting

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure stack
aws cloudformation create-stack \
    --stack-name data-exchange-provider-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=SubscriberAccountId,ParameterValue=123456789012 \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name data-exchange-provider-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name data-exchange-provider-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set subscriber account ID
export SUBSCRIBER_ACCOUNT_ID=123456789012

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy DataExchangeProviderStack

# View outputs
cdk ls --long
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Set subscriber account ID
export SUBSCRIBER_ACCOUNT_ID=123456789012

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy DataExchangeProviderStack

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
subscriber_account_id = "123456789012"
aws_region = "us-east-1"
environment = "dev"
project_name = "data-exchange-demo"
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

# Set required environment variables
export SUBSCRIBER_ACCOUNT_ID=123456789012
export AWS_REGION=us-east-1

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output resource IDs and configuration details
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| SubscriberAccountId | AWS Account ID for data subscriber | - | Yes |
| Environment | Environment name (dev/staging/prod) | dev | No |
| ProjectName | Project name for resource naming | data-exchange | No |
| DataRetentionDays | CloudWatch log retention period | 30 | No |

### CDK Context Variables

```json
{
  "subscriber-account-id": "123456789012",
  "environment": "dev",
  "project-name": "data-exchange-demo",
  "enable-automated-updates": true,
  "data-retention-days": 30
}
```

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| subscriber_account_id | AWS Account ID for data subscriber | string | - | Yes |
| aws_region | AWS region for resources | string | us-east-1 | No |
| environment | Environment name | string | dev | No |
| project_name | Project name for resource naming | string | data-exchange | No |
| enable_automated_updates | Enable automated data updates | bool | true | No |
| data_retention_days | CloudWatch log retention period | number | 30 | No |

## Post-Deployment Steps

### 1. Upload Initial Data
```bash
# Get provider bucket name from outputs
PROVIDER_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name data-exchange-provider-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ProviderBucketName`].OutputValue' \
    --output text)

# Create sample data
mkdir -p sample-data
cat > sample-data/customer-analytics.csv << 'EOF'
customer_id,purchase_date,amount,category,region
C001,2024-01-15,150.50,electronics,us-east
C002,2024-01-16,89.99,books,us-west
C003,2024-01-17,299.99,clothing,eu-central
EOF

# Upload to S3
aws s3 cp sample-data/ s3://$PROVIDER_BUCKET/analytics-data/ --recursive
```

### 2. Create Data Grant
```bash
# Get data set ID from outputs
DATASET_ID=$(aws cloudformation describe-stacks \
    --stack-name data-exchange-provider-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`DataSetId`].OutputValue' \
    --output text)

# Create data grant
aws dataexchange create-data-grant \
    --name "Analytics Data Grant" \
    --description "Cross-account data sharing grant" \
    --dataset-id $DATASET_ID \
    --recipient-account-id 123456789012 \
    --ends-at "2024-12-31T23:59:59Z"
```

### 3. Subscriber Access (Run in Subscriber Account)
```bash
# Accept data grant (run this in subscriber account)
aws dataexchange accept-data-grant --data-grant-id <GRANT_ID>

# Create subscriber bucket
aws s3 mb s3://data-exchange-subscriber-bucket

# Export entitled data
aws dataexchange create-job \
    --type EXPORT_ASSETS_TO_S3 \
    --details '{
        "ExportAssetsToS3JobDetails": {
            "DataSetId": "<ENTITLED_DATASET_ID>",
            "AssetDestinations": [{
                "AssetId": "*",
                "Bucket": "data-exchange-subscriber-bucket",
                "Key": "imported-data/"
            }]
        }
    }'
```

## Monitoring and Validation

### CloudWatch Metrics
```bash
# View Data Exchange metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/DataExchange \
    --metric-name DataGrantsActive \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-31T23:59:59Z \
    --period 86400 \
    --statistics Sum
```

### Lambda Function Logs
```bash
# View notification Lambda logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/DataExchangeNotificationHandler \
    --start-time $(date -d '1 hour ago' +%s)000

# View update Lambda logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/DataExchangeAutoUpdate \
    --start-time $(date -d '1 hour ago' +%s)000
```

### EventBridge Rule Status
```bash
# Check EventBridge rules
aws events list-rules --name-prefix DataExchange

# View rule targets
aws events list-targets-by-rule --rule DataExchangeEventRule
```

## Troubleshooting

### Common Issues

1. **Data Grant Creation Fails**
   - Verify subscriber account ID is correct
   - Check IAM permissions for Data Exchange operations
   - Ensure data set has finalized revisions

2. **Lambda Function Errors**
   - Check CloudWatch logs for detailed error messages
   - Verify IAM role permissions
   - Ensure environment variables are set correctly

3. **EventBridge Integration Issues**
   - Verify EventBridge rules are enabled
   - Check Lambda function permissions
   - Review event patterns for accuracy

### Debug Commands
```bash
# Test Lambda function locally
aws lambda invoke \
    --function-name DataExchangeAutoUpdate \
    --payload '{"dataset_id":"<DATASET_ID>","bucket_name":"<BUCKET_NAME>"}' \
    response.json

# Check IAM role trust relationships
aws iam get-role --role-name DataExchangeProviderRole

# Verify S3 bucket policies
aws s3api get-bucket-policy --bucket <BUCKET_NAME>
```

## Cleanup

### Using CloudFormation
```bash
# Empty S3 buckets first (if needed)
aws s3 rm s3://$(aws cloudformation describe-stacks \
    --stack-name data-exchange-provider-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ProviderBucketName`].OutputValue' \
    --output text) --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name data-exchange-provider-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name data-exchange-provider-stack
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy DataExchangeProviderStack

# Clean up local files
npm run clean  # TypeScript only
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Clean up state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

## Security Considerations

### IAM Best Practices
- All IAM roles follow least privilege principle
- Cross-account access is restricted to specific operations
- Data Exchange service roles have minimal required permissions

### Data Protection
- S3 buckets use server-side encryption by default
- Data in transit is encrypted using HTTPS
- Access logging is enabled for audit purposes

### Network Security
- Resources are deployed in default VPC with appropriate security groups
- Lambda functions run in AWS managed environment
- EventBridge rules are scoped to specific event patterns

## Cost Optimization

### Resource Pricing
- **Data Exchange**: Pay per data grant and data transfer
- **S3 Storage**: Standard storage class with lifecycle policies
- **Lambda**: Pay per execution and compute time
- **EventBridge**: Pay per event processed
- **CloudWatch**: Pay for log storage and metric queries

### Cost Management Tips
1. Use S3 Intelligent Tiering for long-term data storage
2. Set appropriate CloudWatch log retention periods
3. Monitor Data Exchange usage through AWS Cost Explorer
4. Consider reserved capacity for predictable workloads

## Customization

### Adding New Data Sources
1. Modify S3 bucket structure in IaC templates
2. Update Lambda functions to handle new data formats
3. Adjust EventBridge rules for additional event types
4. Update Data Exchange asset configurations

### Integrating with CI/CD
1. Use AWS CodePipeline for automated deployments
2. Implement AWS CodeBuild for infrastructure validation
3. Add AWS Config rules for compliance monitoring
4. Integrate with AWS Systems Manager for parameter management

## Support

For issues with this infrastructure code, refer to:
- [AWS Data Exchange Documentation](https://docs.aws.amazon.com/data-exchange/)
- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/)
- Original recipe documentation for implementation details

## Contributing

When modifying this infrastructure code:
1. Test changes in a development environment
2. Update documentation for any new parameters or outputs
3. Follow provider-specific best practices and naming conventions
4. Validate infrastructure security and compliance requirements