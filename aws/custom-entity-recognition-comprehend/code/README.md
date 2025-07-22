# Infrastructure as Code for Custom Entity Recognition with Comprehend

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Custom Entity Recognition with Comprehend".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a comprehensive custom NLP platform using Amazon Comprehend's custom entity recognition and classification capabilities. The infrastructure includes:

- **Data Storage**: S3 bucket for training data and model artifacts
- **Model Training Pipeline**: Step Functions workflow orchestrating training processes
- **Lambda Functions**: Data preprocessing, model training, status checking, and inference APIs
- **IAM Roles**: Secure access permissions for all services
- **Real-time Inference**: API Gateway integration for production workloads

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon Comprehend (custom model training and inference)
  - S3 (bucket creation and object management)
  - Lambda (function creation and execution)
  - Step Functions (state machine creation and execution)
  - IAM (role and policy management)
  - API Gateway (HTTP API creation)
- Training data with labeled entities and classified documents (minimum 100 examples per entity type)
- Understanding of machine learning model training concepts
- Estimated cost: $200-400 for model training and inference over several training cycles

> **Warning**: Comprehend custom model training can take 1-4 hours per model and incurs significant charges. Plan training cycles carefully and monitor costs closely.

## Quick Start

### Using CloudFormation
```bash
# Deploy the complete infrastructure
aws cloudformation create-stack \
    --stack-name comprehend-custom-nlp \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-nlp-project

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name comprehend-custom-nlp \
    --query 'Stacks[0].StackStatus'

# Get outputs after deployment
aws cloudformation describe-stacks \
    --stack-name comprehend-custom-nlp \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
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

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
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

# The script will:
# 1. Create S3 bucket for training data
# 2. Set up IAM roles and policies
# 3. Deploy Lambda functions
# 4. Create Step Functions workflow
# 5. Upload sample training data
```

## Post-Deployment Steps

After deploying the infrastructure, follow these steps to train and use your custom models:

### 1. Prepare Training Data
```bash
# Upload your custom training data to the S3 bucket
aws s3 cp your-entity-training.csv s3://your-bucket/training-data/entities.csv
aws s3 cp your-classification-training.csv s3://your-bucket/training-data/classification.csv
aws s3 cp your-training-text.txt s3://your-bucket/training-data/entities_sample.txt
```

### 2. Start Model Training
```bash
# Get the Step Functions ARN from outputs
STATE_MACHINE_ARN=$(aws cloudformation describe-stacks \
    --stack-name comprehend-custom-nlp \
    --query 'Stacks[0].Outputs[?OutputKey==`TrainingPipelineArn`].OutputValue' \
    --output text)

# Start the training pipeline
aws stepfunctions start-execution \
    --state-machine-arn $STATE_MACHINE_ARN \
    --name "training-$(date +%Y%m%d-%H%M%S)"
```

### 3. Monitor Training Progress
```bash
# Check execution status
aws stepfunctions list-executions \
    --state-machine-arn $STATE_MACHINE_ARN \
    --status-filter RUNNING

# Monitor Comprehend training jobs
aws comprehend list-entity-recognizers
aws comprehend list-document-classifiers
```

### 4. Test Inference (After Training Completes)
```bash
# Get trained model ARNs
ENTITY_MODEL_ARN=$(aws comprehend list-entity-recognizers \
    --query 'EntityRecognizerPropertiesList[0].EntityRecognizerArn' \
    --output text)

# Test entity recognition
aws comprehend detect-entities \
    --text "Apple Inc. (AAPL) and the S&P 500 showed strong performance." \
    --endpoint-arn $ENTITY_MODEL_ARN
```

## Configuration Options

### CloudFormation Parameters
- `ProjectName`: Unique name for your project (default: comprehend-custom)
- `BucketName`: S3 bucket name for training data (auto-generated if not specified)
- `TrainingDataPath`: S3 path for training data (default: training-data/)

### Terraform Variables
Edit `terraform/terraform.tfvars` to customize:
```hcl
project_name = "my-nlp-project"
aws_region = "us-east-1"
training_data_bucket = "my-training-data-bucket"
enable_api_gateway = true
```

### CDK Context Variables
Configure in `cdk.json` or pass as context:
```bash
cdk deploy -c projectName=my-nlp-project -c enableApiGateway=true
```

## Monitoring and Observability

The deployed infrastructure includes:

- **CloudWatch Logs**: Lambda function logs and Step Functions execution logs
- **CloudWatch Metrics**: Function duration, error rates, and custom metrics
- **Step Functions Console**: Visual workflow monitoring and debugging
- **Comprehend Console**: Model training progress and performance metrics

## Security Considerations

The infrastructure implements several security best practices:

- **Least Privilege IAM**: Roles have minimal required permissions
- **Resource-based Policies**: S3 bucket policies restrict access
- **Encryption**: S3 objects encrypted at rest
- **VPC Endpoints**: Optional VPC endpoints for private API access
- **API Authentication**: API Gateway can be configured with authentication

## Cost Optimization

To manage costs effectively:

- **Training Costs**: Custom model training is the primary cost driver ($10-50 per model)
- **Inference Costs**: Pay-per-request pricing for real-time inference
- **Storage Costs**: S3 storage for training data and model artifacts
- **Lambda Costs**: Minimal cost for preprocessing and orchestration functions

## Troubleshooting

### Common Issues

1. **Training Failures**:
   - Verify training data format matches Comprehend requirements
   - Ensure minimum 10 examples per entity type or classification label
   - Check IAM permissions for Comprehend service role

2. **Insufficient Permissions**:
   - Verify the deployment role has required permissions
   - Check CloudTrail logs for access denied errors

3. **Training Takes Too Long**:
   - Large datasets can take 3-4 hours to train
   - Monitor Step Functions execution for progress
   - Consider smaller datasets for initial testing

### Debug Commands
```bash
# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/

# View Step Functions execution details
aws stepfunctions describe-execution --execution-arn <execution-arn>

# Check Comprehend training job details
aws comprehend describe-entity-recognizer --entity-recognizer-arn <model-arn>
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack and all resources
aws cloudformation delete-stack --stack-name comprehend-custom-nlp

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name comprehend-custom-nlp \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# Destroy the infrastructure
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will safely remove:
# 1. Comprehend models and endpoints
# 2. Lambda functions
# 3. Step Functions workflow
# 4. S3 bucket and contents
# 5. IAM roles and policies
```

## Advanced Customization

### Adding Custom Entity Types
Modify the training data to include your domain-specific entities:
```csv
Text,File,Line,BeginOffset,EndOffset,Type
"Your custom text with CUSTOM_ENTITY highlighted.",sample.txt,0,24,37,CUSTOM_ENTITY
```

### Extending Classification Categories
Add your business-specific document categories:
```csv
Text,Label
"Document content for business classification.",BUSINESS_CATEGORY
```

### Multi-Language Support
Configure Comprehend for additional languages by modifying the language code in Lambda functions:
```python
training_config = {
    'LanguageCode': 'es'  # Spanish, French (fr), German (de), etc.
}
```

## Integration Examples

### REST API Integration
```bash
# Example API call after deployment
curl -X POST https://your-api-gateway-url/inference \
    -H "Content-Type: application/json" \
    -d '{
        "text": "Your text to analyze",
        "entity_model_arn": "arn:aws:comprehend:...",
        "classifier_model_arn": "arn:aws:comprehend:..."
    }'
```

### Batch Processing Integration
```python
import boto3

# Process multiple documents
comprehend = boto3.client('comprehend')
for document in documents:
    result = comprehend.detect_entities(
        Text=document,
        EndpointArn='your-model-arn'
    )
    process_results(result)
```

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS Comprehend documentation for model training requirements
3. Consult the AWS Lambda and Step Functions documentation for workflow issues
4. Monitor CloudWatch logs for detailed error information

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and adapt security configurations for production use.