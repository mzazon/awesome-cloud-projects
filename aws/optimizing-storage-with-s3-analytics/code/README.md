# Infrastructure as Code for Optimizing Storage with S3 Analytics and Reporting

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Optimizing Storage with S3 Analytics and Reporting".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with IAM permissions for S3, Athena, Glue, CloudWatch, QuickSight, Lambda, EventBridge, and IAM
- Basic understanding of S3 storage classes and lifecycle policies
- Node.js 16+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Appropriate permissions for resource creation:
  - S3 bucket creation and configuration
  - IAM role and policy management
  - Lambda function deployment
  - Athena database and table creation
  - CloudWatch dashboard creation
  - EventBridge rule configuration

## Estimated Costs

- S3 Inventory: $0.0025 per million objects listed
- Athena queries: $5 per TB of data scanned
- Lambda execution: Minimal cost for scheduled analytics
- CloudWatch dashboards: $3 per dashboard per month
- S3 storage for reports: Standard S3 pricing
- Total estimated cost: $5-15 per month for small to medium datasets

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name s3-inventory-analytics \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=SourceBucketName,ParameterValue=your-source-bucket \
                 ParameterKey=DestinationBucketName,ParameterValue=your-reports-bucket

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name s3-inventory-analytics \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls
```

### Using CDK Python
```bash
cd cdk-python/

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack information
cdk ls
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
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
aws s3 ls | grep storage-analytics
aws lambda list-functions --query 'Functions[?contains(FunctionName, `StorageAnalytics`)]'
```

## Configuration Options

### CloudFormation Parameters
- `SourceBucketName`: Name of the S3 bucket to analyze
- `DestinationBucketName`: Name of the bucket for inventory reports
- `InventoryFrequency`: Daily or Weekly inventory generation
- `AnalyticsPrefix`: Prefix filter for storage class analysis
- `ReportingSchedule`: EventBridge schedule expression for automated reports

### CDK Configuration
Modify the configuration in the CDK app files:
- Bucket names and regions
- Inventory and analytics configurations
- Lambda function settings
- EventBridge schedule expressions

### Terraform Variables
Edit `terraform/variables.tf` or create a `terraform.tfvars` file:
```hcl
source_bucket_name = "my-source-bucket"
destination_bucket_name = "my-reports-bucket"
aws_region = "us-east-1"
inventory_frequency = "Daily"
analytics_prefix = "data/"
```

## Post-Deployment Setup

### 1. Upload Sample Data (if needed)
```bash
# Create sample data structure
echo "Sample data for analysis" > sample-file.txt
aws s3 cp sample-file.txt s3://your-source-bucket/data/
aws s3 cp sample-file.txt s3://your-source-bucket/logs/
aws s3 cp sample-file.txt s3://your-source-bucket/archive/
```

### 2. Wait for First Inventory Report
S3 Inventory reports are generated within 24-48 hours of configuration. Monitor the destination bucket:
```bash
aws s3 ls s3://your-reports-bucket/inventory-reports/ --recursive
```

### 3. Create Athena Table (after first report)
```bash
# Execute the table creation query in Athena
aws athena start-query-execution \
    --query-string "CREATE EXTERNAL TABLE s3_inventory_db.inventory_table ..." \
    --result-configuration OutputLocation=s3://your-reports-bucket/athena-results/
```

### 4. Test Analytics Queries
```bash
# Execute sample analytics query
aws athena start-query-execution \
    --query-string "SELECT storage_class, COUNT(*) as object_count FROM s3_inventory_db.inventory_table GROUP BY storage_class" \
    --result-configuration OutputLocation=s3://your-reports-bucket/athena-results/
```

## Monitoring and Validation

### Check Inventory Configuration
```bash
aws s3api list-bucket-inventory-configurations --bucket your-source-bucket
```

### Monitor Storage Analytics
```bash
aws s3api list-bucket-analytics-configurations --bucket your-source-bucket
```

### View CloudWatch Dashboard
```bash
aws cloudwatch list-dashboards --dashboard-name-prefix "S3-Storage-Analytics"
```

### Test Lambda Function
```bash
aws lambda invoke \
    --function-name StorageAnalyticsFunction \
    --payload '{}' \
    response.json
```

### Check EventBridge Schedule
```bash
aws events list-rules --name-prefix "StorageAnalyticsSchedule"
```

## Troubleshooting

### Common Issues

1. **Inventory reports not appearing**
   - Verify bucket policy allows S3 service to write reports
   - Check that inventory configuration is enabled
   - Allow 24-48 hours for first report generation

2. **Athena queries failing**
   - Ensure Athena database and table are created
   - Verify S3 permissions for Athena service
   - Check query result location configuration

3. **Lambda function errors**
   - Review CloudWatch logs for the function
   - Verify IAM permissions for Athena and S3 access
   - Check environment variables are set correctly

4. **EventBridge not triggering Lambda**
   - Verify EventBridge rule is enabled
   - Check Lambda function permissions for EventBridge
   - Review rule target configuration

### Debug Commands
```bash
# Check S3 bucket policies
aws s3api get-bucket-policy --bucket your-destination-bucket

# Review Lambda logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/StorageAnalytics"

# List Athena query executions
aws athena list-query-executions --max-results 10

# Check EventBridge rule details
aws events describe-rule --name StorageAnalyticsSchedule
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name s3-inventory-analytics

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name s3-inventory-analytics \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)
```bash
# Remove S3 bucket contents and buckets
aws s3 rm s3://your-source-bucket --recursive
aws s3 rb s3://your-source-bucket
aws s3 rm s3://your-destination-bucket --recursive
aws s3 rb s3://your-destination-bucket

# Delete Athena database
aws athena start-query-execution \
    --query-string "DROP DATABASE IF EXISTS s3_inventory_db CASCADE" \
    --result-configuration OutputLocation=s3://aws-athena-query-results-account-region/
```

## Architecture Overview

This implementation creates:

- **S3 Inventory Configuration**: Automated daily reports of object metadata
- **Storage Class Analysis**: 30-day observation for optimization recommendations
- **Athena Database and Queries**: SQL-based analytics on inventory data
- **Lambda Function**: Automated report generation and analysis
- **EventBridge Schedule**: Daily trigger for automated analytics
- **CloudWatch Dashboard**: Real-time storage metrics monitoring
- **IAM Roles and Policies**: Secure service-to-service permissions

## Security Considerations

- IAM roles follow least privilege principle
- S3 bucket policies restrict access to authorized services only
- Lambda function has minimal required permissions
- All resources are tagged for governance and cost tracking
- Encryption at rest enabled for S3 buckets and Lambda environment variables

## Cost Optimization

- S3 Inventory reports use CSV format for efficient storage
- Athena queries are optimized to scan minimal data
- Lambda function uses appropriate memory allocation
- CloudWatch dashboards use efficient metric aggregation
- EventBridge scheduling minimizes unnecessary executions

## Extension Ideas

1. **Multi-Account Setup**: Configure cross-account inventory reporting
2. **Advanced Analytics**: Add machine learning models for predictive analysis
3. **Automated Actions**: Implement lifecycle policy automation based on insights
4. **Cost Integration**: Connect with AWS Cost Explorer for financial analysis
5. **Alerting**: Add CloudWatch alarms for storage anomalies

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS service documentation for specific services
3. Verify IAM permissions and resource configurations
4. Review CloudWatch logs for detailed error information

## Additional Resources

- [AWS S3 Inventory Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-inventory.html)
- [AWS S3 Storage Class Analysis](https://docs.aws.amazon.com/AmazonS3/latest/userguide/analytics-storage-class.html)
- [Amazon Athena User Guide](https://docs.aws.amazon.com/athena/latest/ug/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)