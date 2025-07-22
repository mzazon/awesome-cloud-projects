# Real-Time Fraud Detection with Amazon Fraud Detector - Terraform Implementation

This Terraform implementation deploys a comprehensive real-time fraud detection system using Amazon Fraud Detector and supporting AWS services.

## Architecture Overview

The infrastructure creates a complete fraud detection pipeline that includes:

- **Amazon Fraud Detector** with Transaction Fraud Insights model
- **Amazon Kinesis Data Streams** for real-time transaction processing
- **AWS Lambda Functions** for event enrichment and fraud scoring
- **Amazon DynamoDB** for decision logging and audit trails
- **Amazon SNS** for fraud alerts and notifications
- **Amazon S3** for training data storage
- **CloudWatch** for monitoring and dashboards

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for creating:
  - IAM roles and policies
  - Lambda functions
  - Kinesis streams
  - DynamoDB tables
  - S3 buckets
  - SNS topics
  - CloudWatch resources

## Quick Start

### 1. Initialize Terraform

```bash
cd terraform/
terraform init
```

### 2. Review and Customize Variables

Create a `terraform.tfvars` file or modify the default values in `variables.tf`:

```hcl
# terraform.tfvars
aws_region = "us-east-1"
environment = "dev"
project_name = "fraud-detection"
alert_email = "your-email@example.com"
kinesis_shard_count = 3
dynamodb_read_capacity = 100
dynamodb_write_capacity = 100
```

### 3. Plan the Deployment

```bash
terraform plan
```

### 4. Deploy the Infrastructure

```bash
terraform apply
```

### 5. Complete Manual Setup

After Terraform deployment, you'll need to manually configure Amazon Fraud Detector components:

```bash
# Use the output values from Terraform
terraform output fraud_detector_config

# Create entity type
aws frauddetector create-entity-type \
    --name $(terraform output -raw fraud_detector_config | jq -r '.entity_type_name') \
    --description "Customer entity for fraud detection"

# Create event type (with event variables)
aws frauddetector create-event-type \
    --name $(terraform output -raw fraud_detector_config | jq -r '.event_type_name') \
    --description "Transaction event type for fraud detection" \
    --entity-types $(terraform output -raw fraud_detector_config | jq -r '.entity_type_name') \
    --event-variables '[
        {"name": "customer_id", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
        {"name": "email_address", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
        {"name": "ip_address", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
        {"name": "transaction_amount", "dataType": "FLOAT", "dataSource": "EVENT", "defaultValue": "0.0"},
        {"name": "payment_method", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"}
    ]'

# Create and train the model (requires training data in S3)
aws frauddetector create-model \
    --model-id $(terraform output -raw fraud_detector_config | jq -r '.model_name') \
    --model-type TRANSACTION_FRAUD_INSIGHTS \
    --event-type-name $(terraform output -raw fraud_detector_config | jq -r '.event_type_name') \
    --training-data-source '{
        "dataLocation": "s3://$(terraform output -raw s3_bucket_name)/training-data/enhanced_training_data.csv",
        "dataAccessRoleArn": "$(terraform output -raw fraud_detector_role_arn)"
    }'
```

## Configuration

### Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for deployment | `us-east-1` | No |
| `environment` | Environment name | `dev` | No |
| `project_name` | Project identifier | `fraud-detection` | No |
| `alert_email` | Email for fraud alerts | `fraud-alerts@example.com` | No |
| `kinesis_shard_count` | Number of Kinesis shards | `3` | No |
| `dynamodb_read_capacity` | DynamoDB read capacity | `100` | No |
| `dynamodb_write_capacity` | DynamoDB write capacity | `100` | No |
| `lambda_enrichment_memory` | Memory for enrichment Lambda | `256` | No |
| `lambda_processor_memory` | Memory for processor Lambda | `512` | No |
| `high_risk_score_threshold` | High risk score threshold | `900` | No |
| `medium_risk_score_threshold` | Medium risk score threshold | `600` | No |
| `low_risk_score_threshold` | Low risk score threshold | `400` | No |

### Outputs

After deployment, Terraform provides several useful outputs:

- `s3_bucket_name` - S3 bucket for training data
- `kinesis_stream_name` - Kinesis stream for transactions
- `fraud_detector_config` - Configuration for manual setup
- `next_steps` - Step-by-step setup instructions
- `aws_cli_commands` - Ready-to-use AWS CLI commands

## Usage

### 1. Upload Training Data

```bash
# Upload your training data to S3
aws s3 cp enhanced_training_data.csv s3://$(terraform output -raw s3_bucket_name)/training-data/
```

### 2. Test the Pipeline

```bash
# Send a test transaction to Kinesis
aws kinesis put-record \
    --stream-name $(terraform output -raw kinesis_stream_name) \
    --partition-key "test-transaction" \
    --data '{
        "transaction_id": "test-001",
        "customer_id": "cust-001",
        "email_address": "test@example.com",
        "ip_address": "192.168.1.100",
        "transaction_amount": 99.99,
        "payment_method": "credit_card"
    }'
```

### 3. Monitor Results

```bash
# Check DynamoDB for decision logs
aws dynamodb scan \
    --table-name $(terraform output -raw dynamodb_table_name) \
    --max-items 5

# View CloudWatch dashboard
echo "Dashboard URL: $(terraform output -raw cloudwatch_dashboard_url)"
```

## Architecture Details

### Lambda Functions

1. **Event Enrichment Lambda** (`event_enrichment_lambda.py`)
   - Processes Kinesis stream records
   - Enriches transactions with behavioral features
   - Calculates velocity, geographic, and email risk scores
   - Forwards enriched data to fraud processor

2. **Fraud Detection Processor** (`fraud_detection_processor.py`)
   - Receives enriched transaction data
   - Calls Amazon Fraud Detector for risk assessment
   - Processes decisions and determines risk levels
   - Logs decisions to DynamoDB
   - Sends alerts for high-risk transactions

### Security Features

- **IAM Least Privilege** - Separate roles with minimal required permissions
- **Encryption** - S3, DynamoDB, Kinesis, and SNS encryption enabled
- **VPC Security** - Optional VPC deployment (modify main.tf)
- **Access Logging** - CloudWatch logging for all components

### Monitoring

- **CloudWatch Dashboard** - Real-time metrics and visualizations
- **Lambda Metrics** - Invocation counts, duration, and error rates
- **Kinesis Metrics** - Throughput and record processing
- **DynamoDB Metrics** - Read/write capacity utilization

## Cost Optimization

### Tips for Cost Management

1. **Kinesis Shards** - Monitor utilization and adjust shard count
2. **DynamoDB Capacity** - Consider on-demand billing for variable workloads
3. **Lambda Memory** - Right-size memory allocation based on usage
4. **Log Retention** - Adjust CloudWatch log retention periods
5. **SNS Filtering** - Use message filtering to reduce costs

### Cost Estimation

Estimated monthly costs for moderate usage:
- Kinesis Data Streams: $15-50
- Lambda Functions: $5-20
- DynamoDB: $20-100
- Amazon Fraud Detector: $0.01 per prediction
- Supporting services: $10-30

## Troubleshooting

### Common Issues

1. **Lambda Function Errors**
   - Check CloudWatch logs for detailed error messages
   - Verify environment variables are set correctly
   - Ensure IAM permissions are properly configured

2. **Fraud Detector Setup**
   - Verify training data format and location
   - Check IAM role permissions for data access
   - Monitor model training progress

3. **Kinesis Processing**
   - Check shard count vs. throughput requirements
   - Verify Lambda event source mapping configuration
   - Monitor for throttling issues

### Debugging Commands

```bash
# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/fraud-detection"

# Test Lambda function directly
aws lambda invoke \
    --function-name $(terraform output -raw fraud_processor_lambda_function_name) \
    --payload '{"test": "data"}' \
    response.json

# Check Kinesis stream status
aws kinesis describe-stream \
    --stream-name $(terraform output -raw kinesis_stream_name)
```

## Maintenance

### Regular Tasks

1. **Monitor Model Performance** - Review fraud detection accuracy
2. **Update Training Data** - Refresh models with new fraud patterns
3. **Capacity Planning** - Adjust resources based on usage patterns
4. **Security Updates** - Keep Lambda runtimes and dependencies updated

### Backup and Recovery

- **DynamoDB** - Point-in-time recovery enabled
- **S3** - Versioning enabled for training data
- **Configuration** - Store Terraform state in S3 backend

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete all resources and data. Ensure you have backups of any important data before running destroy.

## Support

For issues specific to this Terraform implementation:

1. Check the AWS service documentation
2. Review CloudWatch logs for error details
3. Verify IAM permissions and resource configurations
4. Consult the original recipe documentation

## License

This infrastructure code is provided as-is for educational and reference purposes. Modify as needed for your specific requirements.