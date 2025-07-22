# Infrastructure as Code for SageMaker ML Workflows with Step Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "SageMaker ML Workflows with Step Functions".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for SageMaker, Step Functions, S3, IAM, and Lambda
- Basic knowledge of machine learning concepts and Python
- Understanding of containerization and Docker concepts
- Estimated cost: $50-100 for training jobs and endpoints during testing

> **Note**: This recipe uses SageMaker training instances and endpoints which incur charges. Ensure you complete the cleanup steps to avoid ongoing costs.

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name ml-pipeline-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=S3BucketName,ParameterValue=ml-pipeline-bucket-$(date +%s)
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
npm run build
cdk bootstrap  # Only needed first time
cdk deploy
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt
cdk bootstrap  # Only needed first time
cdk deploy
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Overview

The infrastructure deploys a complete ML pipeline with the following components:

- **S3 Bucket**: Storage for raw data, processed data, and model artifacts
- **IAM Roles**: Secure execution roles for SageMaker and Step Functions
- **Step Functions State Machine**: Orchestrates the ML workflow
- **Lambda Function**: Evaluates model performance for deployment decisions
- **SageMaker Resources**: Processing jobs, training jobs, model endpoints

## Deployment Details

### Resource Creation Order

1. **IAM Roles**: SageMaker execution role and Step Functions orchestration role
2. **S3 Bucket**: Storage for ML artifacts with proper folder structure
3. **Lambda Function**: Model evaluation function with necessary permissions
4. **Step Functions State Machine**: Workflow orchestration with integrated service calls
5. **Sample Data**: Upload training and test datasets

### Key Features

- **Automated Data Preprocessing**: SageMaker Processing Jobs handle data standardization
- **Model Training**: Managed training jobs with hyperparameter configuration
- **Quality Gates**: Conditional deployment based on model performance metrics
- **Error Handling**: Comprehensive retry logic and failure management
- **Monitoring**: CloudWatch integration for pipeline visibility

## Customization

### Key Variables/Parameters

- `S3BucketName`: Name for the ML pipeline bucket (must be globally unique)
- `ModelPerformanceThreshold`: R² score threshold for model deployment (default: 0.7)
- `TrainingInstanceType`: SageMaker training instance type (default: ml.m5.large)
- `EndpointInstanceType`: SageMaker endpoint instance type (default: ml.t2.medium)
- `Region`: AWS region for resource deployment

### Environment-Specific Configuration

Modify the following based on your requirements:

1. **Instance Types**: Adjust based on data size and performance needs
2. **Performance Thresholds**: Set model quality gates based on business requirements
3. **Retry Logic**: Configure retry attempts and backoff strategies
4. **Monitoring**: Add CloudWatch alarms for pipeline health monitoring

## Pipeline Execution

After deployment, execute the ML pipeline:

```bash
# Get the State Machine ARN from outputs
STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines \
    --query "stateMachines[?name=='ml-pipeline-*'].stateMachineArn" \
    --output text)

# Start pipeline execution
aws stepfunctions start-execution \
    --state-machine-arn $STATE_MACHINE_ARN \
    --name "execution-$(date +%s)" \
    --input '{
        "PreprocessingJobName": "preprocessing-'$(date +%s)'",
        "TrainingJobName": "training-'$(date +%s)'",
        "ModelName": "model-'$(date +%s)'",
        "EndpointConfigName": "endpoint-config-'$(date +%s)'",
        "EndpointName": "endpoint-'$(date +%s)'"
    }'
```

## Testing the Deployed Solution

### Model Endpoint Testing

```bash
# Test the deployed model endpoint
ENDPOINT_NAME=$(aws sagemaker list-endpoints \
    --query 'Endpoints[?EndpointStatus==`InService`].EndpointName' \
    --output text | head -1)

# Make a prediction
aws sagemaker-runtime invoke-endpoint \
    --endpoint-name $ENDPOINT_NAME \
    --content-type application/json \
    --body '{"instances": [[0.02729, 0.0, 7.07, 0, 0.469, 7.185, 61.1, 4.9671, 2, 242, 17.8, 392.83, 4.03]]}' \
    prediction-output.json

cat prediction-output.json
```

### Pipeline Monitoring

```bash
# Monitor pipeline execution
aws stepfunctions describe-execution \
    --execution-arn $EXECUTION_ARN \
    --query 'status' --output text

# View execution history
aws stepfunctions list-executions \
    --state-machine-arn $STATE_MACHINE_ARN \
    --query 'executions[*].[name,status,startDate]' \
    --output table
```

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name ml-pipeline-stack
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

## Cost Optimization

### Training Costs
- Use Spot instances for training jobs when possible
- Implement early stopping for training jobs
- Use smaller instance types for experimentation

### Endpoint Costs
- Use auto-scaling for production endpoints
- Consider serverless inference for sporadic usage
- Delete endpoints when not in use

### Storage Costs
- Implement S3 lifecycle policies for old artifacts
- Use appropriate storage classes for different data types
- Clean up failed job artifacts regularly

## Security Considerations

### IAM Best Practices
- Least privilege access for all roles
- Regular review of role permissions
- Use of condition statements for enhanced security

### Data Protection
- Encryption at rest for S3 buckets
- Encryption in transit for all communications
- VPC endpoints for private communication

### Monitoring and Auditing
- CloudTrail logging for all API calls
- CloudWatch monitoring for unusual activity
- Regular security assessments

## Troubleshooting

### Common Issues

1. **Training Job Failures**
   - Check CloudWatch logs for training jobs
   - Verify data format and preprocessing steps
   - Ensure sufficient instance resources

2. **Endpoint Deployment Failures**
   - Verify model artifacts exist in S3
   - Check inference script compatibility
   - Validate endpoint configuration

3. **Step Functions Execution Failures**
   - Review state machine execution history
   - Check IAM role permissions
   - Verify input parameter format

### Debugging Commands

```bash
# Check SageMaker job logs
aws logs describe-log-groups \
    --log-group-name-prefix /aws/sagemaker/

# View Step Functions execution details
aws stepfunctions describe-execution \
    --execution-arn $EXECUTION_ARN \
    --query 'error' --output text
```

## Advanced Features

### Model Registry Integration
Extend the pipeline to register models in SageMaker Model Registry:

```bash
# Register model in model registry
aws sagemaker create-model-package \
    --model-package-name "my-model-package" \
    --model-package-group-name "my-model-group"
```

### A/B Testing Support
Implement multi-variant endpoints for A/B testing:

```bash
# Create multi-variant endpoint
aws sagemaker create-endpoint-config \
    --endpoint-config-name "ab-test-config" \
    --production-variants VariantName=ModelA,ModelName=ModelA,InitialInstanceCount=1,InstanceType=ml.t2.medium,InitialVariantWeight=0.5 \
    --production-variants VariantName=ModelB,ModelName=ModelB,InitialInstanceCount=1,InstanceType=ml.t2.medium,InitialVariantWeight=0.5
```

## Extensions and Enhancements

1. **Hyperparameter Tuning**: Add SageMaker Hyperparameter Tuning Jobs
2. **Model Monitoring**: Implement data drift detection and model performance monitoring
3. **Multi-Environment Support**: Extend pipeline for dev/staging/prod environments
4. **Custom Algorithms**: Support for custom Docker containers and algorithms
5. **Batch Transform**: Add batch inference capabilities alongside real-time endpoints

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check AWS SageMaker documentation for service-specific issues
3. Review AWS Step Functions documentation for workflow problems
4. Consult AWS CloudFormation/CDK/Terraform documentation for deployment issues

## Contributing

When modifying this infrastructure:
1. Follow AWS best practices for security and cost optimization
2. Test changes in a development environment first
3. Update documentation to reflect changes
4. Ensure cleanup scripts remove all created resources