# Infrastructure as Code for Real-Time Data Transformation with Amazon Kinesis Data Firehose

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Transforming Data with Kinesis Data Firehose".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a serverless real-time data processing pipeline that:

- Ingests streaming data through Amazon Kinesis Data Firehose
- Transforms data using AWS Lambda functions
- Delivers processed data to Amazon S3 with intelligent partitioning
- Provides backup of raw data for reprocessing capabilities
- Includes comprehensive monitoring and alerting via CloudWatch
- Supports error handling with dead-letter queues

## Prerequisites

- AWS CLI v2 installed and configured with appropriate permissions
- AWS account with permissions to create:
  - Kinesis Data Firehose delivery streams
  - Lambda functions
  - S3 buckets
  - IAM roles and policies
  - CloudWatch alarms and log groups
  - SNS topics
- Node.js 16.x or later (for CDK TypeScript)
- Python 3.8 or later (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Estimated cost: $0.035 per GB ingested + Lambda execution + S3 storage

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name firehose-data-transformation \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=DeliveryStreamName,ParameterValue=my-log-stream \
                 ParameterKey=NotificationEmail,ParameterValue=your-email@example.com

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name firehose-data-transformation \
    --query 'Stacks[0].StackStatus'

# Wait for completion
aws cloudformation wait stack-create-complete \
    --stack-name firehose-data-transformation
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
cdk outputs
```

### Using CDK Python

```bash
cd cdk-python/

# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
cdk outputs
```

### Using Terraform

```bash
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

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for configuration
```

## Testing Your Deployment

After deployment, test the data transformation pipeline:

```bash
# Set your delivery stream name (replace with actual name from outputs)
export DELIVERY_STREAM_NAME="your-stream-name"

# Create test data
cat > test_data.json << 'EOF'
{"timestamp": "2025-01-12T10:30:00Z", "level": "INFO", "service": "user-service", "message": "User login successful", "userId": "user123"}
{"timestamp": "2025-01-12T10:30:01Z", "level": "ERROR", "service": "payment-service", "message": "Payment failed", "userId": "user456"}
{"timestamp": "2025-01-12T10:30:02Z", "level": "DEBUG", "service": "db-service", "message": "Query executed", "duration": "45ms"}
{"timestamp": "2025-01-12T10:30:03Z", "level": "WARN", "service": "cache-service", "message": "Cache miss detected", "key": "user_profile_789"}
EOF

# Send test records to Firehose
while IFS= read -r line; do
    aws firehose put-record \
        --delivery-stream-name ${DELIVERY_STREAM_NAME} \
        --record Data="$(echo "$line" | base64)"
done < test_data.json

# Wait for processing (3-5 minutes)
echo "Waiting for data processing..."
sleep 300

# Check processed data (replace bucket name with actual from outputs)
aws s3 ls s3://your-processed-bucket/logs/ --recursive --human-readable
```

## Configuration Options

### CloudFormation Parameters

- `DeliveryStreamName`: Name for the Kinesis Data Firehose delivery stream
- `NotificationEmail`: Email address for CloudWatch alarm notifications
- `BufferSize`: Buffer size in MB (default: 5)
- `BufferInterval`: Buffer interval in seconds (default: 60)
- `CompressionFormat`: Compression format for S3 objects (default: GZIP)

### CDK Context Variables

Configure in `cdk.json` or pass via command line:

```bash
# Example: Custom buffer settings
cdk deploy -c bufferSize=3 -c bufferInterval=30
```

### Terraform Variables

Customize in `terraform.tfvars`:

```hcl
delivery_stream_name = "my-custom-stream"
notification_email   = "alerts@mycompany.com"
buffer_size_mb      = 5
buffer_interval_sec = 60
compression_format  = "GZIP"
```

## Monitoring and Troubleshooting

### CloudWatch Metrics

Key metrics to monitor:
- `DeliveryToS3.Success`: Successful deliveries to S3
- `DeliveryToS3.DataFreshness`: Time since last record delivery
- `DeliveryToS3.Records`: Number of records delivered
- `Lambda.Duration`: Transformation function execution time
- `Lambda.Errors`: Transformation function errors

### CloudWatch Logs

Check these log groups:
- `/aws/kinesisfirehose/[stream-name]`: Firehose delivery logs
- `/aws/lambda/[function-name]`: Lambda transformation logs

### Common Issues

1. **No data appearing in S3**: Check IAM permissions and buffer settings
2. **Lambda transformation errors**: Review CloudWatch logs for the Lambda function
3. **High data freshness**: Verify Firehose delivery stream status
4. **Missing records**: Check error bucket for failed transformations

## Security Considerations

This implementation includes:
- Least privilege IAM roles and policies
- S3 bucket encryption at rest (AES256)
- VPC endpoints for private communication (optional)
- CloudWatch logging for audit trails
- Secure parameter handling for sensitive data

## Cost Optimization

To optimize costs:
- Adjust buffer size and interval based on your latency requirements
- Use S3 lifecycle policies to transition old data to cheaper storage classes
- Monitor Lambda execution duration and memory usage
- Enable S3 Intelligent Tiering for automatic cost optimization

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name firehose-data-transformation

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name firehose-data-transformation
```

### Using CDK

```bash
# From the CDK directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

## Customization

### Extending the Lambda Function

To modify the transformation logic:

1. Update the Lambda function code in the respective IaC template
2. Modify the transformation rules in the Lambda handler
3. Add additional IAM permissions if accessing other AWS services
4. Redeploy the infrastructure

### Adding Additional Destinations

To add more destinations (e.g., Redshift, OpenSearch):

1. Modify the IaC template to include additional destination configurations
2. Update IAM roles with necessary permissions
3. Configure appropriate delivery stream destinations
4. Test the multi-destination delivery

### Custom Partitioning

To implement custom partitioning:

1. Modify the S3 destination prefix in the delivery stream configuration
2. Update Lambda function to add custom partition keys
3. Consider using dynamic partitioning for better performance

## Performance Tuning

### Buffer Configuration

- **Small buffers (1-3 MB, 60-300 seconds)**: Lower latency, higher costs
- **Large buffers (5-128 MB, 60-900 seconds)**: Higher latency, lower costs
- **Balanced approach**: 5 MB or 60 seconds for most use cases

### Lambda Optimization

- **Memory**: Start with 256 MB, adjust based on CloudWatch metrics
- **Timeout**: 60 seconds is usually sufficient for transformations
- **Concurrent executions**: Monitor and adjust based on throughput needs

## Support

For issues with this infrastructure code:
- Review the original recipe documentation
- Check AWS documentation for Kinesis Data Firehose
- Consult CloudWatch logs for troubleshooting
- Review IAM permissions for access issues

## Additional Resources

- [Amazon Kinesis Data Firehose Documentation](https://docs.aws.amazon.com/firehose/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [Amazon S3 Documentation](https://docs.aws.amazon.com/s3/)
- [AWS CloudWatch Documentation](https://docs.aws.amazon.com/cloudwatch/)
- [Firehose Data Transformation Guide](https://docs.aws.amazon.com/firehose/latest/dev/lambda-preprocessing.html)