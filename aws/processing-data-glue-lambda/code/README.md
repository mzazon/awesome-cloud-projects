# Infrastructure as Code for Processing Data with AWS Glue and Lambda

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Processing Data with AWS Glue and Lambda".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- Appropriate AWS permissions for creating:
  - IAM roles and policies
  - S3 buckets and objects
  - AWS Glue databases, crawlers, jobs, and workflows
  - Lambda functions
  - CloudWatch logs and metrics
- For CDK implementations: Node.js 16+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Estimated cost: $5-15 for data processing and storage during deployment

## Architecture Overview

This infrastructure deploys a complete serverless ETL pipeline including:

- **S3 Buckets**: Raw data storage, processed data output, scripts, and temporary files
- **IAM Roles**: Secure service roles for Glue and Lambda with least-privilege access
- **AWS Glue Components**:
  - Data Catalog database for metadata management
  - Crawler for automatic schema discovery
  - ETL job for data transformation using PySpark
  - Workflow for pipeline orchestration
- **Lambda Function**: Pipeline orchestrator for job triggering and monitoring
- **CloudWatch**: Logging and monitoring for all components

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name serverless-etl-pipeline \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=Environment,ParameterValue=dev \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name serverless-etl-pipeline \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name serverless-etl-pipeline \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in region)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy --require-approval never

# View stack outputs
npx cdk list --long
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in region)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View stack outputs
cdk list --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the configuration
terraform apply -auto-approve

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
echo "Deployment complete. Check AWS console for resources."
```

## Testing the Deployed Infrastructure

After successful deployment, test the ETL pipeline:

### 1. Upload Sample Data

```bash
# Get bucket name from outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name serverless-etl-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`DataBucketName`].OutputValue' \
    --output text)

# Create sample data
cat > sales_data.csv << 'EOF'
order_id,customer_id,product_id,quantity,price,order_date,region
1001,C001,P001,2,29.99,2024-01-15,North
1002,C002,P002,1,49.99,2024-01-15,South
1003,C003,P001,3,29.99,2024-01-16,East
EOF

# Upload to S3 (this should trigger the pipeline if event notifications are enabled)
aws s3 cp sales_data.csv "s3://${BUCKET_NAME}/raw-data/sales_data.csv"
```

### 2. Manually Trigger Pipeline

```bash
# Get Lambda function name from outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name serverless-etl-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Trigger the pipeline
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload '{"test": true}' \
    response.json

# Check response
cat response.json
```

### 3. Monitor Job Execution

```bash
# Check Glue job runs
aws glue get-job-runs \
    --job-name $(aws cloudformation describe-stacks \
        --stack-name serverless-etl-pipeline \
        --query 'Stacks[0].Outputs[?OutputKey==`GlueJobName`].OutputValue' \
        --output text) \
    --max-results 5

# Check processed data
aws s3 ls "s3://${BUCKET_NAME}/processed-data/" --recursive
```

## Customization

### Environment Variables

Customize the deployment by modifying these parameters:

- **Environment**: Set to `dev`, `staging`, or `prod`
- **BucketPrefix**: Customize S3 bucket naming
- **GlueWorkerType**: Adjust worker type (`G.1X`, `G.2X`, `G.4X`) based on data volume
- **NumberOfWorkers**: Scale Glue job workers (2-100)
- **LambdaMemorySize**: Adjust Lambda memory allocation (128-3008 MB)

### CloudFormation Parameters

```bash
aws cloudformation create-stack \
    --stack-name serverless-etl-pipeline \
    --template-body file://cloudformation.yaml \
    --parameters \
        ParameterKey=Environment,ParameterValue=prod \
        ParameterKey=GlueWorkerType,ParameterValue=G.2X \
        ParameterKey=NumberOfWorkers,ParameterValue=4 \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
environment         = "prod"
glue_worker_type   = "G.2X"
number_of_workers  = 4
lambda_memory_size = 512
enable_s3_notifications = true
```

### CDK Context

For CDK implementations, customize through `cdk.json` context:

```json
{
  "context": {
    "environment": "prod",
    "glueWorkerType": "G.2X",
    "numberOfWorkers": 4
  }
}
```

## Monitoring and Troubleshooting

### CloudWatch Logs

- **Glue Job Logs**: `/aws-glue/jobs/logs-v2`
- **Lambda Function Logs**: `/aws/lambda/{function-name}`
- **Glue Crawler Logs**: `/aws-glue/crawlers`

### Common Issues

1. **IAM Permissions**: Ensure roles have appropriate S3 and Glue permissions
2. **S3 Event Notifications**: Verify Lambda has permission to be invoked by S3
3. **Glue Job Failures**: Check CloudWatch logs for PySpark errors
4. **Data Format Issues**: Ensure input data matches expected schema

### Monitoring Commands

```bash
# Check recent Lambda invocations
aws logs filter-log-events \
    --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
    --start-time $(date -d '1 hour ago' +%s)000

# Monitor Glue job metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Glue \
    --metric-name glue.driver.aggregate.numCompletedTasks \
    --start-time $(date -d '1 hour ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 300 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name serverless-etl-pipeline

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name serverless-etl-pipeline \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Navigate to appropriate CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
npx cdk destroy  # or 'cdk destroy' for Python
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually delete resources in this order:

1. Empty and delete S3 buckets
2. Delete Lambda functions
3. Delete Glue jobs, crawlers, and workflows
4. Delete Glue databases
5. Delete IAM roles and policies
6. Delete CloudWatch log groups

## Cost Optimization

### Glue Job Optimization

- Use appropriate worker types for your data volume
- Enable job bookmarks for incremental processing
- Set appropriate timeout values to avoid runaway jobs
- Consider using Glue streaming for real-time requirements

### S3 Storage Optimization

- Implement S3 Lifecycle policies for processed data
- Use appropriate S3 storage classes (IA, Glacier)
- Enable S3 Transfer Acceleration if needed

### Lambda Optimization

- Right-size memory allocation based on actual usage
- Use provisioned concurrency only when necessary
- Monitor and optimize function duration

## Security Considerations

### IAM Best Practices

- All roles follow least-privilege principle
- Cross-service access is properly configured
- Resource-level permissions where applicable

### Data Security

- S3 buckets have encryption enabled by default
- Glue jobs encrypt data in transit and at rest
- CloudWatch logs are encrypted

### Network Security

- Consider VPC endpoints for enhanced security
- Implement S3 bucket policies for access control
- Use AWS PrivateLink for service communications

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for solution architecture details
2. Review AWS Glue documentation for job configuration
3. Consult AWS Lambda documentation for function optimization
4. Use AWS CloudFormation/CDK/Terraform documentation for IaC troubleshooting

## Additional Resources

- [AWS Glue Developer Guide](https://docs.aws.amazon.com/glue/latest/dg/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/latest/guide/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)