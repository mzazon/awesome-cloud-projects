# Infrastructure as Code for Streaming ETL with Kinesis Data Firehose

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Streaming ETL with Kinesis Data Firehose".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon Kinesis Data Firehose
  - AWS Lambda
  - Amazon S3
  - Amazon CloudWatch
  - AWS IAM (roles and policies)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

## Architecture Overview

This solution creates a streaming ETL pipeline that:
- Ingests real-time data through Kinesis Data Firehose
- Transforms data using Lambda functions
- Stores processed data in S3 as Parquet files
- Provides monitoring through CloudWatch

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name streaming-etl-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BucketName,ParameterValue=my-streaming-etl-bucket-$(date +%s)

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name streaming-etl-pipeline \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk output
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk output
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
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

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters
# and display progress throughout deployment
```

## Testing the Deployment

After deployment, test the streaming ETL pipeline:

```bash
# Get the Firehose delivery stream name from outputs
STREAM_NAME=$(aws cloudformation describe-stacks \
    --stack-name streaming-etl-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`FirehoseStreamName`].OutputValue' \
    --output text)

# Send test data
aws firehose put-record \
    --delivery-stream-name $STREAM_NAME \
    --record '{"Data":"eyJldmVudF90eXBlIjoicGFnZV92aWV3IiwidXNlcl9pZCI6InVzZXIxMjMiLCJzZXNzaW9uX2lkIjoic2Vzc2lvbjQ1NiIsInBhZ2VfdXJsIjoiaHR0cHM6Ly9leGFtcGxlLmNvbS9wcm9kdWN0cyJ9"}'

# Check S3 bucket for processed data (after 5-10 minutes)
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name streaming-etl-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
    --output text)

aws s3 ls s3://$BUCKET_NAME/processed-data/ --recursive
```

## Customization

### Key Parameters

Each implementation supports the following customizable parameters:

- **BucketName**: S3 bucket name for data storage (must be globally unique)
- **LambdaFunctionName**: Name for the Lambda transformation function
- **FirehoseStreamName**: Name for the Kinesis Data Firehose delivery stream
- **BufferSize**: Firehose buffer size in MB (default: 5)
- **BufferInterval**: Firehose buffer interval in seconds (default: 300)
- **CompressionFormat**: Data compression format (default: GZIP)

### Environment-Specific Configuration

For production environments, consider adjusting:

```bash
# Terraform example
terraform apply \
    -var="buffer_size=64" \
    -var="buffer_interval=60" \
    -var="lambda_memory=256"
```

### Lambda Transformation Logic

The Lambda function can be customized to handle different data transformation requirements. The default implementation:
- Adds timestamps to incoming records
- Enriches data with processing metadata
- Handles error scenarios gracefully
- Converts data to appropriate format for Parquet conversion

## Monitoring and Troubleshooting

### CloudWatch Metrics

Monitor the following key metrics:
- `DeliveryToS3.Success` - Successful deliveries to S3
- `DeliveryToS3.DataFreshness` - Age of oldest record in Firehose
- `KinesisFirehose.DeliveryToS3.Records` - Number of records delivered

### CloudWatch Logs

Check these log groups for troubleshooting:
- `/aws/lambda/[FunctionName]` - Lambda transformation logs
- `/aws/kinesisfirehose/[StreamName]` - Firehose delivery logs

### Common Issues

1. **Data not appearing in S3**: Check buffer size and interval settings
2. **Lambda errors**: Review CloudWatch logs for transformation function
3. **Permission issues**: Verify IAM roles have required permissions
4. **Parquet conversion errors**: Ensure data schema consistency

## Cleanup

### Using CloudFormation

```bash
# Delete the stack and all resources
aws cloudformation delete-stack --stack-name streaming-etl-pipeline

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name streaming-etl-pipeline \
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
source .venv/bin/activate  # If not already activated
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

## Cost Optimization

To minimize costs during testing and development:

1. **Use smaller buffer sizes** to process data more frequently
2. **Set up lifecycle policies** on S3 bucket for automatic data archival
3. **Monitor Lambda execution time** and optimize memory allocation
4. **Use CloudWatch cost allocation tags** to track spending by component

## Security Considerations

This implementation follows AWS security best practices:

- **IAM roles** use least privilege principle
- **S3 bucket** has default encryption enabled
- **Lambda function** runs with minimal required permissions
- **CloudWatch logs** are encrypted at rest
- **VPC endpoints** can be configured for private connectivity (advanced configuration)

## Performance Tuning

For high-throughput scenarios:

1. **Adjust buffer settings** based on data volume and latency requirements
2. **Optimize Lambda function** memory and timeout settings
3. **Consider partitioning strategy** for S3 data organization
4. **Use appropriate S3 storage class** based on access patterns

## Integration Examples

### With Amazon Athena

Query processed data directly from S3:

```sql
CREATE EXTERNAL TABLE streaming_etl_data (
    timestamp string,
    event_type string,
    user_id string,
    session_id string,
    page_url string,
    referrer string,
    user_agent string,
    ip_address string,
    processed_by string
)
STORED AS PARQUET
LOCATION 's3://your-bucket-name/processed-data/'
```

### With Amazon QuickSight

1. Create a dataset pointing to the S3 location
2. Use Athena as the data source
3. Build dashboards with real-time insights

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **AWS Documentation**: Check [Amazon Data Firehose documentation](https://docs.aws.amazon.com/firehose/)
3. **CloudFormation Reference**: See [AWS CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
4. **CDK Documentation**: Visit [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
5. **Terraform Documentation**: Check [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)

## Version Information

- **Recipe Version**: 1.2
- **Last Updated**: 2025-07-12
- **Tested AWS Regions**: us-east-1, us-west-2, eu-west-1
- **Minimum AWS CLI Version**: 2.0
- **CDK Version**: 2.x
- **Terraform Version**: 1.0+