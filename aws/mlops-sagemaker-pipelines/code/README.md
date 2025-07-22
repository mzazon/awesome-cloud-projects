# Infrastructure as Code for End-to-End MLOps with SageMaker Pipelines

This directory contains Infrastructure as Code (IaC) implementations for the recipe "End-to-End MLOps with SageMaker Pipelines".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for SageMaker, S3, CodeCommit, and IAM
- Python 3.8+ (for CDK Python and SageMaker SDK)
- Node.js 18+ (for CDK TypeScript)
- Terraform 1.0+ (for Terraform implementation)
- Basic understanding of machine learning workflows
- Estimated cost: $15-25 for pipeline execution and endpoint hosting during testing

## Quick Start

### Using CloudFormation
```bash
# Create the infrastructure stack
aws cloudformation create-stack \
    --stack-name mlops-sagemaker-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=BucketPrefix,ParameterValue=mlops-$(date +%s)

# Monitor stack creation
aws cloudformation wait stack-create-complete \
    --stack-name mlops-sagemaker-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name mlops-sagemaker-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# Get outputs
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

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# Get outputs
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
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

# The script will create all necessary resources and provide
# environment variables for pipeline execution
```

## Infrastructure Components

This infrastructure creates the following AWS resources:

### Core Resources
- **S3 Bucket**: Stores training data, model artifacts, and pipeline outputs
- **IAM Execution Role**: Provides SageMaker with necessary permissions
- **CodeCommit Repository**: Version control for ML pipeline code
- **SageMaker Pipeline**: Orchestrates the end-to-end ML workflow

### Security & Access
- **IAM Policies**: Least privilege access for SageMaker operations
- **S3 Bucket Policies**: Secure access to training data and artifacts
- **VPC Endpoints**: (Optional) Private connectivity for enhanced security

### Monitoring & Logging
- **CloudWatch Log Groups**: Centralized logging for pipeline execution
- **CloudWatch Metrics**: Custom metrics for pipeline monitoring
- **EventBridge Rules**: (Optional) Automated pipeline triggering

## Post-Deployment Steps

After infrastructure deployment, follow these steps to execute your first ML pipeline:

### 1. Upload Training Data
```bash
# Set environment variables (from deployment outputs)
export BUCKET_NAME="your-bucket-name"
export PIPELINE_NAME="your-pipeline-name"

# Upload sample data
aws s3 cp sample-data/ s3://${BUCKET_NAME}/data/ --recursive
```

### 2. Execute Pipeline
```bash
# Create and run the ML pipeline
python execute_pipeline.py

# Monitor execution
aws sagemaker list-pipeline-executions \
    --pipeline-name ${PIPELINE_NAME}
```

### 3. Monitor Results
```bash
# Check pipeline status
aws sagemaker describe-pipeline-execution \
    --pipeline-execution-arn "your-execution-arn"

# View training job logs
aws logs describe-log-streams \
    --log-group-name /aws/sagemaker/TrainingJobs
```

## Customization

### Variables and Parameters

Each implementation supports customization through variables:

- **BucketPrefix**: Prefix for S3 bucket naming
- **PipelineName**: Name for the SageMaker pipeline
- **RoleName**: Name for the IAM execution role
- **RepositoryName**: Name for the CodeCommit repository
- **InstanceType**: EC2 instance type for training jobs
- **FrameworkVersion**: SageMaker framework version

### Environment-Specific Configuration

#### Development Environment
```bash
# Use smaller instance types for cost optimization
export INSTANCE_TYPE="ml.t3.medium"
export ENABLE_SPOT_INSTANCES="true"
```

#### Production Environment
```bash
# Use larger instances for performance
export INSTANCE_TYPE="ml.m5.2xlarge"
export ENABLE_MONITORING="true"
export ENABLE_MODEL_REGISTRY="true"
```

## Advanced Features

### Model Registry Integration
Enable automatic model registration by setting:
```bash
export ENABLE_MODEL_REGISTRY="true"
export MODEL_PACKAGE_GROUP_NAME="your-model-group"
```

### Data Quality Monitoring
Configure data drift detection:
```bash
export ENABLE_DATA_QUALITY="true"
export BASELINE_DATA_PATH="s3://your-bucket/baseline/"
```

### Multi-Environment Deployment
Configure pipeline for multiple environments:
```bash
export ENVIRONMENT="development"  # or staging, production
export APPROVAL_REQUIRED="true"   # for production deployments
```

## Monitoring and Troubleshooting

### Pipeline Monitoring
```bash
# View pipeline execution history
aws sagemaker list-pipeline-executions \
    --pipeline-name ${PIPELINE_NAME} \
    --sort-by CreationTime \
    --sort-order Descending

# Get detailed execution information
aws sagemaker describe-pipeline-execution \
    --pipeline-execution-arn "your-execution-arn"
```

### Training Job Logs
```bash
# List training jobs
aws sagemaker list-training-jobs \
    --sort-by CreationTime \
    --sort-order Descending

# View training job details
aws sagemaker describe-training-job \
    --training-job-name "your-training-job-name"
```

### Common Issues and Solutions

#### Issue: Pipeline execution fails
```bash
# Check pipeline definition
aws sagemaker describe-pipeline --pipeline-name ${PIPELINE_NAME}

# Review execution details
aws sagemaker list-pipeline-execution-steps \
    --pipeline-execution-arn "your-execution-arn"
```

#### Issue: Training job fails
```bash
# Check training job logs
aws logs filter-log-events \
    --log-group-name /aws/sagemaker/TrainingJobs \
    --filter-pattern "ERROR"
```

#### Issue: Insufficient permissions
```bash
# Verify IAM role permissions
aws iam list-attached-role-policies --role-name ${ROLE_NAME}
aws iam list-role-policies --role-name ${ROLE_NAME}
```

## Cost Optimization

### Training Cost Optimization
- Use Spot instances for non-critical training jobs
- Implement automatic model tuning with early stopping
- Use smaller instance types for development and testing

### Storage Cost Optimization
- Configure S3 lifecycle policies for model artifacts
- Use S3 Intelligent Tiering for training data
- Clean up intermediate outputs regularly

### Monitoring Costs
```bash
# Monitor SageMaker costs
aws ce get-cost-and-usage \
    --time-period Start=2025-01-01,End=2025-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Cleanup

### Using CloudFormation
```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name mlops-sagemaker-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name mlops-sagemaker-stack
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy --force
```

### Using CDK Python
```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy --force
```

### Using Terraform
```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm all resources are deleted
aws s3 ls | grep mlops
aws sagemaker list-pipelines --name-contains mlops
```

## Security Considerations

### IAM Best Practices
- Use least privilege access principles
- Regularly rotate access keys and tokens
- Enable CloudTrail for audit logging
- Use IAM roles instead of users for service access

### Data Security
- Enable S3 bucket encryption at rest
- Use VPC endpoints for private connectivity
- Implement data access logging and monitoring
- Follow data classification and handling policies

### Network Security
- Deploy in private subnets when possible
- Use security groups to restrict access
- Enable VPC Flow Logs for network monitoring
- Consider using AWS PrivateLink for service connectivity

## Performance Optimization

### Training Performance
- Use GPU instances for deep learning workloads
- Implement distributed training for large datasets
- Optimize data loading and preprocessing
- Use SageMaker Profiler for performance analysis

### Pipeline Performance
- Parallelize independent pipeline steps
- Use caching for expensive preprocessing steps
- Optimize data formats (Parquet vs CSV)
- Implement incremental data processing

## Integration Examples

### CI/CD Integration
```bash
# Example GitLab CI pipeline
script:
  - ./scripts/deploy.sh
  - python execute_pipeline.py
  - ./scripts/validate_model.sh
```

### Event-Driven Execution
```bash
# Configure S3 event trigger
aws events put-rule \
    --name MLPipelineTrigger \
    --event-pattern '{"source":["aws.s3"],"detail-type":["Object Created"]}'
```

## Support and Resources

### Documentation Links
- [SageMaker Pipelines User Guide](https://docs.aws.amazon.com/sagemaker/latest/dg/pipelines.html)
- [SageMaker Python SDK](https://sagemaker.readthedocs.io/)
- [MLOps Best Practices](https://docs.aws.amazon.com/sagemaker/latest/dg/mlops.html)

### Community Resources
- [SageMaker Examples Repository](https://github.com/aws/amazon-sagemaker-examples)
- [AWS Machine Learning Blog](https://aws.amazon.com/blogs/machine-learning/)
- [SageMaker Developer Forum](https://forums.aws.amazon.com/forum.jspa?forumID=285)

### Getting Help
For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS CloudTrail logs for permission issues
3. Consult the original recipe documentation
4. Refer to AWS SageMaker documentation
5. Contact AWS Support for service-specific issues

## Contributing

To improve this infrastructure code:
1. Test changes in a development environment
2. Follow AWS best practices and security guidelines
3. Update documentation for any configuration changes
4. Validate changes across all deployment methods
5. Submit improvements via pull request