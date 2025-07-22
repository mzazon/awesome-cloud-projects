# Terraform Infrastructure for Custom Entity Recognition and Classification with Amazon Comprehend

This Terraform configuration deploys a comprehensive machine learning pipeline for training and deploying custom Amazon Comprehend models for entity recognition and document classification.

## Architecture Overview

The infrastructure creates:

- **Amazon S3**: Storage for training data, model artifacts, and processed documents
- **AWS Lambda**: Serverless functions for data preprocessing, model training orchestration, status checking, and real-time inference
- **AWS Step Functions**: Workflow orchestration for the complete training pipeline
- **Amazon Comprehend**: Custom entity recognition and document classification models
- **Amazon DynamoDB**: Storage for inference results and analytics
- **Amazon API Gateway**: REST API endpoints for real-time inference
- **Amazon CloudWatch**: Monitoring, logging, and dashboards
- **Amazon SNS**: Optional notifications for training completion

## Prerequisites

1. **AWS CLI**: Version 2.x installed and configured
2. **Terraform**: Version 1.0 or higher
3. **AWS Permissions**: IAM permissions for all services used in the configuration
4. **Training Data**: Custom training datasets for entity recognition and classification

### Required AWS IAM Permissions

Your AWS credentials must have permissions for:
- S3 (bucket creation, object management)
- Lambda (function creation and management)
- IAM (role and policy management)
- Step Functions (state machine creation)
- Comprehend (model training and inference)
- DynamoDB (table creation and management)
- API Gateway (API creation and management)
- CloudWatch (logs and metrics)
- SNS (topic creation, optional)

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd aws/custom-entity-recognition-comprehend-classification/code/terraform/
```

### 2. Configure Variables

Copy the example variables file and customize:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your specific configuration:

```hcl
project_name = "my-comprehend-project"
environment  = "dev"
aws_region   = "us-east-1"

# Enable notifications
enable_sns_notifications = true
notification_email       = "your-email@company.com"
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Start Training Pipeline

After deployment, start the training pipeline:

```bash
# Get the Step Functions ARN from Terraform output
STATE_MACHINE_ARN=$(terraform output -raw step_functions_state_machine_arn)

# Start training execution
aws stepfunctions start-execution \
    --state-machine-arn $STATE_MACHINE_ARN \
    --name "training-$(date +%Y%m%d-%H%M%S)" \
    --region $(terraform output -raw aws_region)
```

### 5. Monitor Training Progress

Monitor training in the AWS console:
- **Step Functions**: Track workflow execution
- **Comprehend**: Monitor model training jobs
- **CloudWatch**: View logs and metrics

Training typically takes 1-4 hours depending on data size.

### 6. Test Inference API

After training completes, test the inference API:

```bash
# Get the API endpoint
API_ENDPOINT=$(terraform output -raw api_gateway_inference_url)

# Test with sample text
curl -X POST $API_ENDPOINT \
    -H "Content-Type: application/json" \
    -d '{
        "text": "Goldman Sachs upgraded Tesla (TSLA) following strong quarterly earnings.",
        "entity_model_arn": "YOUR_ENTITY_MODEL_ARN",
        "classifier_model_arn": "YOUR_CLASSIFIER_MODEL_ARN"
    }'
```

## Configuration Options

### Core Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `project_name` | Project name prefix for resources | `"comprehend-custom"` |
| `environment` | Environment (dev/staging/prod) | `"dev"` |
| `aws_region` | AWS region for deployment | `"us-east-1"` |

### Lambda Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `lambda_timeout` | Lambda function timeout (seconds) | `300` |
| `lambda_memory_size` | Lambda memory allocation (MB) | `256` |

### Storage Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `s3_bucket_force_destroy` | Force destroy S3 bucket with objects | `false` |
| `enable_versioning` | Enable S3 bucket versioning | `true` |
| `enable_encryption` | Enable S3 bucket encryption | `true` |

### API Gateway Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `api_gateway_throttle_rate_limit` | Requests per second limit | `100` |
| `api_gateway_throttle_burst_limit` | Burst request limit | `200` |

### Monitoring Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_monitoring_dashboard` | Create CloudWatch dashboard | `true` |
| `cloudwatch_logs_retention_days` | Log retention period | `14` |
| `enable_sns_notifications` | Enable SNS notifications | `false` |

## Training Data Format

### Entity Recognition Data

CSV format with columns: `Text,File,Line,BeginOffset,EndOffset,Type`

```csv
Text,File,Line,BeginOffset,EndOffset,Type
"Apple Inc. (AAPL) reported earnings.",sample.txt,0,13,17,STOCK_SYMBOL
"The S&P 500 index rose 2.3%.",sample.txt,1,4,11,STOCK_INDEX
```

### Classification Data

CSV format with columns: `Text,Label`

```csv
Text,Label
"Quarterly earnings exceeded expectations.",EARNINGS_REPORT
"Fed announces interest rate decision.",MONETARY_POLICY
```

## Cost Estimation

Estimated monthly costs for moderate usage:

- **Comprehend Training**: $3-12 per model training job
- **Comprehend Inference**: $0.50-2.00 per 1M characters
- **Lambda**: ~$5-20 for processing functions
- **DynamoDB**: ~$5-15 for results storage
- **S3**: ~$5-10 for data storage
- **API Gateway**: ~$3-10 for API requests
- **CloudWatch**: ~$2-5 for logs and metrics

**Total estimated**: $25-75 per month for development workloads

## Security Considerations

The configuration implements several security best practices:

- **IAM Least Privilege**: Roles have minimal required permissions
- **S3 Security**: Public access blocked, encryption enabled
- **VPC Support**: Optional VPC configuration for Lambda functions
- **Encryption**: Data encrypted at rest and in transit
- **Access Logging**: Comprehensive CloudWatch logging

## Monitoring and Alerting

### CloudWatch Dashboards

Automatically created dashboard includes:
- Lambda function metrics (duration, errors, invocations)
- DynamoDB metrics (read/write capacity)
- API Gateway metrics (requests, latency, errors)

### CloudWatch Logs

Centralized logging for:
- Lambda function execution logs
- Step Functions workflow logs
- API Gateway access logs

### Optional SNS Notifications

Enable email notifications for:
- Training completion
- Training failures
- Critical errors

## Troubleshooting

### Common Issues

1. **Training Fails**: Check IAM permissions and data format
2. **API Timeouts**: Increase Lambda timeout or memory
3. **High Costs**: Monitor usage and adjust throttling
4. **Access Denied**: Verify IAM roles and policies

### Debugging Commands

```bash
# Check Lambda logs
aws logs tail /aws/lambda/$(terraform output -raw data_preprocessor_function_name) --follow

# Check Step Functions execution
aws stepfunctions describe-execution --execution-arn EXECUTION_ARN

# Test API Gateway locally
aws apigatewayv2 test-invoke-method --api-id API_ID --stage prod --route-key "POST /inference"
```

## Customization

### Adding Custom Entity Types

1. Update training data with new entity types
2. Ensure minimum 10 examples per entity type
3. Re-run training pipeline

### Modifying API Response Format

Edit `lambda_templates/inference_api.py.tpl` to customize response structure.

### Adding Validation Rules

Edit `lambda_templates/data_preprocessor.py.tpl` to add custom validation logic.

## Cleanup

To avoid ongoing charges, destroy the infrastructure:

```bash
# Destroy all resources
terraform destroy

# Confirm destruction
# Type 'yes' when prompted
```

**Note**: This will permanently delete all training data, models, and results.

## Support and Contributing

For issues or questions:

1. Check AWS Comprehend documentation
2. Review CloudWatch logs for error details
3. Consult Terraform AWS provider documentation
4. Open an issue in the project repository

## Version History

- **v1.0**: Initial implementation with basic training pipeline
- **v1.1**: Added monitoring dashboard and SNS notifications
- **v1.2**: Enhanced security and error handling
- **v1.3**: Current version with comprehensive documentation

## License

This infrastructure code is provided under the MIT License. See LICENSE file for details.