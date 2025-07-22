# Infrastructure as Code for Real-Time Fraud Detection with Amazon Fraud Detector

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Detecting Fraud with Amazon Fraud Detector".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a comprehensive real-time fraud detection system using:

- **Amazon Fraud Detector**: Transaction Fraud Insights model with advanced ML capabilities
- **Amazon Kinesis Data Streams**: Real-time transaction data ingestion
- **AWS Lambda**: Event processing and fraud scoring functions
- **Amazon DynamoDB**: Decision logging and audit trails
- **Amazon SNS**: Fraud alert notifications
- **Amazon S3**: Training data storage and model artifacts
- **Amazon CloudWatch**: Performance monitoring and dashboards

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - Amazon Fraud Detector (full access)
  - Amazon Kinesis Data Streams
  - AWS Lambda
  - Amazon DynamoDB
  - Amazon SNS
  - Amazon S3
  - Amazon CloudWatch
  - IAM role management
- Python 3.9+ for Lambda development
- Node.js 18+ (for CDK TypeScript)
- Terraform 1.0+ (for Terraform deployment)
- Historical transaction data with fraud labels (minimum 50,000 events with 5% fraud rate)

## Quick Start

### Using CloudFormation

```bash
# Deploy the complete fraud detection system
aws cloudformation create-stack \
    --stack-name fraud-detection-platform \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=TrainingDataBucket,ParameterValue=your-training-data-bucket \
                 ParameterKey=AlertEmail,ParameterValue=your-email@example.com

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name fraud-detection-platform \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npm install

# Configure deployment parameters
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk deploy --parameters alertEmail=your-email@example.com

# View outputs
cdk outputs
```

### Using CDK Python

```bash
cd cdk-python/
pip install -r requirements.txt

# Configure deployment parameters
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk deploy --parameters alertEmail=your-email@example.com

# View outputs
cdk outputs
```

### Using Terraform

```bash
cd terraform/
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
aws_region = "us-east-1"
alert_email = "your-email@example.com"
training_data_bucket = "your-training-data-bucket"
environment = "production"
EOF

# Plan and apply
terraform plan
terraform apply
```

### Using Bash Scripts

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh

# Follow the prompts to configure:
# - AWS region
# - Alert email address
# - Training data bucket name
# - Environment name
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `TrainingDataBucket` | S3 bucket for training data | - | Yes |
| `AlertEmail` | Email for fraud alerts | - | Yes |
| `Environment` | Environment name | `production` | No |
| `KinesisShardCount` | Number of Kinesis shards | `3` | No |
| `DynamoDBReadCapacity` | DynamoDB read capacity | `100` | No |
| `DynamoDBWriteCapacity` | DynamoDB write capacity | `100` | No |

### CDK Configuration

Both CDK implementations support these context variables:

```bash
# Set in cdk.context.json or via command line
cdk deploy --context alertEmail=your-email@example.com \
           --context environment=production \
           --context kinesisShardCount=3
```

### Terraform Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `aws_region` | AWS region | `string` | `"us-east-1"` |
| `alert_email` | Email for fraud alerts | `string` | - |
| `training_data_bucket` | S3 bucket name | `string` | - |
| `environment` | Environment name | `string` | `"production"` |
| `kinesis_shard_count` | Kinesis shard count | `number` | `3` |
| `dynamodb_read_capacity` | DynamoDB read capacity | `number` | `100` |
| `dynamodb_write_capacity` | DynamoDB write capacity | `number` | `100` |

## Post-Deployment Steps

### 1. Upload Training Data

```bash
# Upload your training data to S3
aws s3 cp your-training-data.csv s3://your-training-data-bucket/training-data/
```

### 2. Monitor Model Training

```bash
# Check model training status
aws frauddetector describe-model-versions \
    --model-id $(terraform output -raw model_name) \
    --model-type TRANSACTION_FRAUD_INSIGHTS \
    --query 'modelVersionDetails[0].status'
```

### 3. Test Fraud Detection

```bash
# Test with sample transaction
aws frauddetector get-event-prediction \
    --detector-id $(terraform output -raw detector_name) \
    --event-id "test-$(date +%s)" \
    --event-type-name $(terraform output -raw event_type_name) \
    --entities '[{"entityType":"customer","entityId":"test-customer"}]' \
    --event-timestamp $(date -u +"%Y-%m-%dT%H:%M:%SZ") \
    --event-variables '{
        "customer_id": "test-customer",
        "order_price": "99.99",
        "transaction_amount": "99.99"
    }'
```

### 4. Configure Monitoring

Access the CloudWatch dashboard to monitor:
- Lambda function performance
- Kinesis stream metrics
- DynamoDB capacity utilization
- Fraud detection accuracy

## Performance Optimization

### Scaling Considerations

- **Kinesis Shards**: Increase shard count for higher throughput
- **Lambda Concurrency**: Configure reserved concurrency for consistent performance
- **DynamoDB Capacity**: Use auto-scaling for variable workloads
- **Model Performance**: Monitor prediction latency and accuracy

### Cost Optimization

- **Fraud Detector**: Pay-per-prediction model scales with usage
- **Kinesis**: Right-size shard count based on data volume
- **DynamoDB**: Use on-demand billing for unpredictable workloads
- **Lambda**: Optimize memory allocation based on performance metrics

## Security Considerations

### IAM Permissions

The infrastructure implements least-privilege access:
- Fraud Detector service role with minimal S3 and DynamoDB permissions
- Lambda execution roles with specific resource access
- Cross-service permissions limited to required operations

### Data Protection

- **Encryption**: All data encrypted at rest and in transit
- **Access Logging**: Comprehensive audit trails for all operations
- **Network Security**: VPC endpoints for internal service communication
- **Secrets Management**: Sensitive configuration stored in AWS Secrets Manager

## Monitoring and Alerting

### CloudWatch Metrics

Monitor these key metrics:
- Fraud detection accuracy and false positive rates
- Lambda function duration and error rates
- Kinesis stream utilization and throttling
- DynamoDB capacity and throttling

### Alerts

Configure alerts for:
- High fraud detection rates
- Lambda function errors
- Kinesis stream throttling
- DynamoDB capacity exceeded

## Troubleshooting

### Common Issues

1. **Model Training Failures**:
   - Verify training data format and quality
   - Check IAM permissions for S3 access
   - Ensure minimum data requirements are met

2. **Lambda Timeouts**:
   - Increase function timeout values
   - Optimize function memory allocation
   - Review function code for performance bottlenecks

3. **Kinesis Throttling**:
   - Increase shard count
   - Implement exponential backoff in producers
   - Monitor shard utilization metrics

### Debugging Steps

```bash
# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/fraud-detection"

# Monitor Kinesis stream health
aws kinesis describe-stream --stream-name $(terraform output -raw kinesis_stream_name)

# Check DynamoDB table metrics
aws dynamodb describe-table --table-name $(terraform output -raw decisions_table_name)
```

## Cleanup

### Using CloudFormation

```bash
aws cloudformation delete-stack --stack-name fraud-detection-platform
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
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Integration Examples

### API Gateway Integration

```bash
# Create API Gateway for transaction processing
aws apigateway create-rest-api --name fraud-detection-api

# Configure Lambda integration for real-time scoring
aws apigateway put-integration \
    --rest-api-id your-api-id \
    --resource-id your-resource-id \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:region:lambda:path/2015-03-31/functions/arn:aws:lambda:region:account:function:fraud-detection-processor/invocations"
```

### Event-Driven Architecture

```bash
# Configure additional event sources
aws lambda create-event-source-mapping \
    --event-source-arn arn:aws:sqs:region:account:transaction-queue \
    --function-name fraud-detection-processor
```

## Advanced Features

### A/B Testing

Deploy multiple detector versions to compare performance:

```bash
# Create new detector version
aws frauddetector create-detector-version \
    --detector-id your-detector-id \
    --description "Updated rules for A/B testing"

# Route traffic percentage to new version
aws frauddetector update-detector-version-metadata \
    --detector-id your-detector-id \
    --detector-version-id "2" \
    --description "50% traffic routing"
```

### Model Retraining

Implement automated retraining pipelines:

```bash
# Schedule periodic retraining with EventBridge
aws events put-rule \
    --name fraud-model-retrain \
    --schedule-expression "rate(7 days)"
```

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../real-time-fraud-detection-amazon-fraud-detector.md)
2. Review AWS service documentation:
   - [Amazon Fraud Detector](https://docs.aws.amazon.com/frauddetector/)
   - [Amazon Kinesis Data Streams](https://docs.aws.amazon.com/kinesis/)
   - [AWS Lambda](https://docs.aws.amazon.com/lambda/)
3. Check AWS service health and region availability
4. Review CloudWatch logs for specific error messages

## Contributing

To improve this infrastructure code:

1. Test deployments in multiple AWS regions
2. Validate security configurations
3. Optimize performance and cost
4. Update documentation with new features
5. Add integration examples for common use cases

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and modify according to your organization's security and compliance requirements.