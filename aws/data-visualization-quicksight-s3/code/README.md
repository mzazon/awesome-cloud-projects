# Infrastructure as Code for Data Visualization Pipelines with QuickSight

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Visualization Pipelines with QuickSight".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a complete data visualization pipeline including:

- **S3 Buckets**: Raw data storage, processed data storage, and Athena query results
- **AWS Glue**: Data catalog, crawlers, and ETL jobs for data transformation
- **Amazon Athena**: Serverless SQL query engine for data analysis
- **Lambda Functions**: Automation triggers for pipeline processing
- **IAM Roles**: Secure access permissions for all services
- **EventBridge**: Event-driven automation for new data processing

The pipeline automatically processes data files uploaded to S3, catalogs schemas, transforms data into optimized formats, and prepares datasets for QuickSight visualization.

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - S3 (CreateBucket, PutObject, GetObject, DeleteObject)
  - AWS Glue (CreateDatabase, CreateCrawler, CreateJob)
  - Amazon Athena (CreateWorkGroup, StartQueryExecution)
  - AWS Lambda (CreateFunction, AddPermission)
  - IAM (CreateRole, AttachRolePolicy, PutRolePolicy)
  - EventBridge (PutRule, PutTargets)
- QuickSight account activated (Standard or Enterprise edition)
- Basic understanding of data analytics and SQL
- Estimated cost: $50-100/month for moderate usage

> **Note**: QuickSight setup requires manual configuration through the AWS Console after infrastructure deployment.

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name data-viz-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-data-pipeline

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name data-viz-pipeline \
    --query 'Stacks[0].StackStatus'

# Get output values
aws cloudformation describe-stacks \
    --stack-name data-viz-pipeline \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters projectName=my-data-pipeline

# Get stack outputs
cdk list
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Deploy the stack
cdk deploy --parameters projectName=my-data-pipeline

# Get stack outputs
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_name=my-data-pipeline"

# Apply the configuration
terraform apply -var="project_name=my-data-pipeline"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for configuration values
# and deploy all necessary resources
```

## Post-Deployment Steps

After infrastructure deployment, complete these manual steps:

### 1. Upload Sample Data
```bash
# Set your project name (use same as deployment)
export PROJECT_NAME="my-data-pipeline"
export RAW_BUCKET="${PROJECT_NAME}-raw-data-$(date +%s)"

# Create sample data files
mkdir sample-data
cat > sample-data/sales_2024_q1.csv << 'EOF'
order_id,customer_id,product_category,product_name,quantity,unit_price,order_date,region,sales_rep
1001,C001,Electronics,Laptop,1,1200.00,2024-01-15,North,John Smith
1002,C002,Clothing,T-Shirt,3,25.00,2024-01-16,South,Jane Doe
1003,C003,Electronics,Smartphone,2,800.00,2024-01-17,East,Bob Johnson
EOF

# Upload to S3
aws s3 cp sample-data/ s3://${RAW_BUCKET}/sales-data/ --recursive
```

### 2. Configure QuickSight Data Source
1. Open the AWS Console and navigate to QuickSight
2. Create a new data source with type "Athena"
3. Select the workgroup created by the deployment
4. Choose the database and tables from the Glue catalog
5. Create your first analysis and dashboard

### 3. Test the Pipeline
```bash
# Trigger crawler to catalog data
export CRAWLER_NAME="${PROJECT_NAME}-raw-crawler"
aws glue start-crawler --name ${CRAWLER_NAME}

# Wait for crawler completion, then run ETL job
export ETL_JOB="${PROJECT_NAME}-etl-job"
aws glue start-job-run --job-name ${ETL_JOB}
```

## Configuration Options

### Environment Variables
All implementations support these configuration options:

- `PROJECT_NAME`: Unique identifier for all resources (default: auto-generated)
- `AWS_REGION`: AWS region for deployment (default: us-east-1)
- `ENABLE_AUTOMATION`: Enable Lambda triggers for automatic processing (default: true)
- `ATHENA_WORKGROUP_NAME`: Custom name for Athena workgroup
- `GLUE_DATABASE_NAME`: Custom name for Glue database

### CloudFormation Parameters
```yaml
Parameters:
  ProjectName:
    Type: String
    Default: data-viz-pipeline
  EnableAutomation:
    Type: String
    Default: "true"
    AllowedValues: ["true", "false"]
```

### Terraform Variables
```hcl
variable "project_name" {
  description = "Unique identifier for all resources"
  type        = string
  default     = "data-viz-pipeline"
}

variable "enable_automation" {
  description = "Enable Lambda automation triggers"
  type        = bool
  default     = true
}
```

## Validation and Testing

### Verify Infrastructure Deployment
```bash
# Check S3 buckets
aws s3 ls | grep ${PROJECT_NAME}

# Verify Glue database
aws glue get-database --name ${PROJECT_NAME}-database

# Check Athena workgroup
aws athena get-work-group --work-group ${PROJECT_NAME}-workgroup

# Test Lambda function
aws lambda invoke \
    --function-name ${PROJECT_NAME}-automation \
    --payload '{"test": true}' \
    response.json
```

### Test Data Processing
```bash
# Upload test data
aws s3 cp sample-data/sales_2024_q1.csv s3://${RAW_BUCKET}/sales-data/

# Monitor crawler execution
aws glue get-crawler --name ${PROJECT_NAME}-raw-crawler

# Check processed data
aws s3 ls s3://${PROJECT_NAME}-processed-data/ --recursive
```

### Query Data with Athena
```bash
# Execute sample query
QUERY_ID=$(aws athena start-query-execution \
    --query-string "SELECT COUNT(*) FROM \"${PROJECT_NAME}-database\".\"enriched_sales\"" \
    --work-group ${PROJECT_NAME}-workgroup \
    --query 'QueryExecutionId' --output text)

# Get results
aws athena get-query-results --query-execution-id ${QUERY_ID}
```

## Monitoring and Troubleshooting

### CloudWatch Logs
Monitor these log groups for troubleshooting:
- `/aws/lambda/${PROJECT_NAME}-automation`
- `/aws/glue/crawlers/${PROJECT_NAME}-raw-crawler`
- `/aws/glue/jobs/${PROJECT_NAME}-etl-job`

### Common Issues

**Issue**: Glue crawler fails to run
```bash
# Check crawler status
aws glue get-crawler --name ${PROJECT_NAME}-raw-crawler

# Verify IAM permissions
aws iam get-role-policy --role-name GlueDataVizRole-* --policy-name S3AccessPolicy
```

**Issue**: ETL job fails
```bash
# Check job run status
aws glue get-job-runs --job-name ${PROJECT_NAME}-etl-job

# View job logs in CloudWatch
```

**Issue**: QuickSight cannot access data
- Verify Athena workgroup configuration
- Check QuickSight service permissions
- Ensure tables exist in Glue catalog

## Cleanup

### Using CloudFormation
```bash
# Empty S3 buckets first (required)
aws s3 rm s3://${PROJECT_NAME}-raw-data --recursive
aws s3 rm s3://${PROJECT_NAME}-processed-data --recursive
aws s3 rm s3://${PROJECT_NAME}-athena-results --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name data-viz-pipeline

# Verify deletion
aws cloudformation describe-stacks --stack-name data-viz-pipeline
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/

# Empty S3 buckets
cdk destroy --force

# For manual bucket cleanup if needed
aws s3 rm s3://${PROJECT_NAME}-raw-data --recursive
aws s3 rb s3://${PROJECT_NAME}-raw-data
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_name=my-data-pipeline"

# Confirm with 'yes' when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

### Manual QuickSight Cleanup
1. Delete any dashboards and analyses created
2. Remove the Athena data source
3. Cancel QuickSight subscription if no longer needed

## Cost Optimization

### Storage Costs
- Use S3 Intelligent-Tiering for automatic cost optimization
- Implement lifecycle policies to move old data to cheaper storage classes
- Delete processed data after QuickSight import if using SPICE

### Compute Costs
- Use Athena partition projection to reduce query costs
- Optimize Glue ETL jobs for better performance
- Schedule ETL jobs during off-peak hours if applicable

### QuickSight Costs
- Monitor user count and access patterns
- Use Standard edition if Enterprise features aren't needed
- Implement row-level security to share dashboards efficiently

## Security Considerations

### IAM Best Practices
- All roles follow least privilege principle
- S3 bucket policies restrict access to specific resources
- Lambda functions have minimal required permissions

### Data Protection
- S3 buckets can be configured with encryption at rest
- Athena query results are stored in encrypted S3 location
- VPC endpoints can be added for private connectivity

### Access Control
- QuickSight integrates with AWS IAM and SSO
- Row-level security available for multi-tenant scenarios
- API access can be restricted using resource-based policies

## Support and Documentation

### AWS Service Documentation
- [AWS Glue Developer Guide](https://docs.aws.amazon.com/glue/)
- [Amazon Athena User Guide](https://docs.aws.amazon.com/athena/)
- [Amazon QuickSight User Guide](https://docs.aws.amazon.com/quicksight/)
- [AWS S3 Developer Guide](https://docs.aws.amazon.com/s3/)

### Troubleshooting Resources
- [AWS Glue Troubleshooting](https://docs.aws.amazon.com/glue/latest/dg/troubleshooting.html)
- [Athena Troubleshooting](https://docs.aws.amazon.com/athena/latest/ug/troubleshooting-athena.html)
- [QuickSight Troubleshooting](https://docs.aws.amazon.com/quicksight/latest/user/troubleshoot.html)

For issues with this infrastructure code, refer to the original recipe documentation or the specific provider's documentation.