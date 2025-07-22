# Infrastructure as Code for Fraud Detection with Amazon Fraud Detector

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Fraud Detection with Amazon Fraud Detector".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a comprehensive fraud detection system using:

- **Amazon Fraud Detector**: ML-powered fraud detection service
- **Amazon S3**: Training data storage
- **AWS IAM**: Service roles and permissions
- **AWS Lambda**: Fraud prediction processing
- **Custom ML Models**: Trained on your transaction data
- **Detection Rules**: Business logic for fraud decisions

## Prerequisites

- AWS CLI installed and configured with appropriate credentials
- Appropriate AWS permissions for:
  - Amazon Fraud Detector (full access)
  - Amazon S3 (bucket creation and management)
  - AWS IAM (role creation and policy attachment)
  - AWS Lambda (function creation and execution)
- Historical transaction data with fraud labels (minimum 10,000 events recommended)
- Basic understanding of fraud detection concepts

### Cost Considerations

- **Model Training**: $1-5 per hour (typically 45-60 minutes)
- **Predictions**: $7.50 per 1,000 requests
- **S3 Storage**: $0.023 per GB/month
- **Lambda**: $0.20 per 1M requests + compute time
- **Estimated Total**: $50-200 for initial setup and testing

## Quick Start

### Using CloudFormation

```bash
# Deploy the fraud detection infrastructure
aws cloudformation create-stack \
    --stack-name fraud-detection-system \
    --template-body file://cloudformation.yaml \
    --parameters \
        ParameterKey=ProjectName,ParameterValue=fraud-detection \
        ParameterKey=Environment,ParameterValue=dev \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name fraud-detection-system \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name fraud-detection-system \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy FraudDetectionStack

# View stack outputs
cdk ls --long
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

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy FraudDetectionStack

# View stack outputs
cdk ls --long
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

# Follow the interactive prompts for configuration
```

## Post-Deployment Setup

After infrastructure deployment, you'll need to:

1. **Upload Training Data**: Upload your historical transaction data to the created S3 bucket
2. **Train the Model**: The model training will start automatically and takes 45-60 minutes
3. **Activate the Detector**: Once training completes, the detector will be activated
4. **Test Predictions**: Use the provided Lambda function or direct API calls to test fraud detection

### Training Data Format

Your training data should be a CSV file with the following columns:

```csv
event_timestamp,customer_id,email_address,ip_address,customer_name,phone_number,billing_address,billing_city,billing_state,billing_zip,shipping_address,shipping_city,shipping_state,shipping_zip,payment_method,card_bin,order_price,product_category,EVENT_LABEL
```

The `EVENT_LABEL` column should contain either "fraud" or "legit" for supervised learning.

## Testing the System

### Real-time Fraud Detection Test

```bash
# Test with a legitimate transaction
aws frauddetector get-event-prediction \
    --detector-id $(terraform output -raw detector_name) \
    --event-id "test_$(date +%s)" \
    --event-type-name $(terraform output -raw event_type_name) \
    --entities '[{
        "entityType": "'$(terraform output -raw entity_type_name)'",
        "entityId": "test_customer_001"
    }]' \
    --event-timestamp $(date -u +"%Y-%m-%dT%H:%M:%SZ") \
    --event-variables '{
        "customer_id": "test_customer_001",
        "email_address": "legitimate@example.com",
        "ip_address": "192.168.1.100",
        "order_price": "99.99"
    }'

# Test with a suspicious transaction
aws frauddetector get-event-prediction \
    --detector-id $(terraform output -raw detector_name) \
    --event-id "test_fraud_$(date +%s)" \
    --event-type-name $(terraform output -raw event_type_name) \
    --entities '[{
        "entityType": "'$(terraform output -raw entity_type_name)'",
        "entityId": "test_customer_002"
    }]' \
    --event-timestamp $(date -u +"%Y-%m-%dT%H:%M:%SZ") \
    --event-variables '{
        "customer_id": "test_customer_002",
        "email_address": "suspicious@tempmail.com",
        "ip_address": "1.2.3.4",
        "order_price": "2999.99"
    }'
```

### Lambda Function Testing

```bash
# Invoke the fraud processing Lambda function
aws lambda invoke \
    --function-name $(terraform output -raw lambda_function_name) \
    --payload '{
        "transaction_id": "test_123",
        "detector_id": "'$(terraform output -raw detector_name)'",
        "event_type_name": "'$(terraform output -raw event_type_name)'",
        "entity_type_name": "'$(terraform output -raw entity_type_name)'",
        "transaction": {
            "customer_id": "test_customer_001",
            "email_address": "test@example.com",
            "ip_address": "192.168.1.1",
            "order_price": 150.00,
            "product_category": "electronics"
        }
    }' \
    response.json

# View the response
cat response.json
```

## Monitoring and Maintenance

### Model Performance Monitoring

```bash
# Check model training status
aws frauddetector describe-model-versions \
    --model-id $(terraform output -raw model_name) \
    --model-type ONLINE_FRAUD_INSIGHTS

# View detector status
aws frauddetector describe-detector \
    --detector-id $(terraform output -raw detector_name)
```

### CloudWatch Metrics

Monitor these key metrics in CloudWatch:
- Fraud Detector prediction latency
- Fraud Detector prediction volume
- Lambda function duration and error rates
- S3 bucket access patterns

## Customization

### Environment Variables

Each implementation supports customization through variables:

- **ProjectName**: Base name for all resources
- **Environment**: Deployment environment (dev, staging, prod)
- **ModelName**: Custom name for the ML model
- **DetectorName**: Custom name for the fraud detector
- **TrainingDataBucket**: S3 bucket name for training data

### Rule Customization

Modify fraud detection rules in the IaC templates:

1. **Low Risk Rule**: Transactions with fraud score ≤ 700
2. **High Risk Rule**: Transactions with fraud score > 700 or amount > $1000
3. **Obvious Fraud Rule**: Transactions with fraud score > 900

### Adding Custom Variables

To add new transaction variables:

1. Update the event type configuration
2. Modify the Lambda function to process new fields
3. Update your training data to include new columns
4. Retrain the model with enhanced data

## Security Best Practices

### IAM Permissions

The implementation follows least privilege principles:
- Fraud Detector service role has minimal required permissions
- Lambda execution role restricted to necessary actions
- S3 bucket access limited to specific prefixes

### Data Protection

- Training data encrypted at rest in S3
- All API communications use HTTPS/TLS
- Sensitive transaction data not logged in CloudWatch
- IAM roles prevent cross-account access

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name fraud-detection-system

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name fraud-detection-system \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy the CDK stack
cd cdk-typescript/  # or cdk-python/
cdk destroy FraudDetectionStack

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Destroy Terraform-managed resources
cd terraform/
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow interactive prompts to confirm deletion
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually delete:

1. **Fraud Detector Resources**:
   - Deactivate and delete detector versions
   - Delete detector, model, rules, and outcomes
   - Delete event types, entity types, and labels

2. **Supporting Resources**:
   - Empty and delete S3 bucket
   - Delete Lambda function
   - Delete IAM roles and policies

## Troubleshooting

### Common Issues

1. **Model Training Failure**:
   - Verify training data format and labels
   - Ensure sufficient data volume (>10,000 events)
   - Check IAM permissions for S3 access

2. **Prediction Errors**:
   - Verify detector is activated
   - Check event variable formats
   - Ensure entity types match configuration

3. **Permission Errors**:
   - Verify AWS CLI credentials
   - Check IAM policy attachments
   - Ensure service roles are properly configured

### Debugging Commands

```bash
# Check AWS CLI configuration
aws sts get-caller-identity

# Verify S3 bucket access
aws s3 ls s3://your-training-bucket/

# Test fraud detector API access
aws frauddetector list-detectors

# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"
```

## Support and Documentation

- [Amazon Fraud Detector Documentation](https://docs.aws.amazon.com/frauddetector/)
- [AWS CLI Reference](https://docs.aws.amazon.com/cli/latest/reference/frauddetector/)
- [CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support resources.

## Advanced Configuration

### Multi-Environment Deployment

Deploy to multiple environments using parameter overrides:

```bash
# Development environment
terraform apply -var="environment=dev" -var="model_name=fraud_model_dev"

# Production environment
terraform apply -var="environment=prod" -var="model_name=fraud_model_prod"
```

### Integration Patterns

1. **API Gateway Integration**: Expose fraud detection through REST API
2. **Event-Driven Processing**: Use EventBridge for asynchronous fraud scoring
3. **Batch Processing**: Schedule bulk fraud analysis using AWS Batch
4. **Real-time Streaming**: Integrate with Kinesis for continuous fraud monitoring

### Performance Optimization

- **Prediction Caching**: Implement Redis/ElastiCache for repeated predictions
- **Batch Predictions**: Use bulk prediction APIs for efficiency
- **Regional Deployment**: Deploy in multiple regions for low latency
- **Auto Scaling**: Configure Lambda concurrency based on traffic patterns