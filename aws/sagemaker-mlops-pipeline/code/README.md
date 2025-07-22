# Infrastructure as Code for SageMaker MLOps Pipeline with CodePipeline

This directory contains Infrastructure as Code (IaC) implementations for the recipe "SageMaker MLOps Pipeline with CodePipeline".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - Amazon SageMaker (training jobs, model registry, endpoints)
  - AWS CodePipeline and CodeBuild
  - Amazon S3 (bucket creation and object management)
  - AWS Lambda (function creation and execution)
  - IAM (role and policy management)
- Node.js 16+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)
- Estimated cost: $50-100 for training jobs, endpoints, and pipeline executions

## Architecture Overview

This infrastructure deploys a complete MLOps pipeline including:

- **SageMaker Model Registry** for model versioning and governance
- **CodePipeline** with four stages: Source → Build → Test → Deploy
- **CodeBuild projects** for model training and automated testing
- **S3 bucket** for artifacts, source code, and training data
- **Lambda function** for production model deployment
- **IAM roles and policies** with least privilege access

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name mlops-pipeline-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=my-mlops-project \
    --capabilities CAPABILITY_IAM
```

Monitor stack creation:
```bash
aws cloudformation describe-stacks \
    --stack-name mlops-pipeline-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
npm run build
cdk bootstrap  # If first time using CDK in this region
cdk deploy
```

### Using CDK Python
```bash
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt
cdk bootstrap  # If first time using CDK in this region
cdk deploy
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan -var="project_name=my-mlops-project"
terraform apply
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Configuration Parameters

### CloudFormation Parameters
- `ProjectName`: Unique identifier for the MLOps project (default: mlops-pipeline)
- `ModelPackageGroupName`: Name for the SageMaker Model Registry group (default: fraud-detection-models)
- `BucketName`: S3 bucket name for artifacts (auto-generated if not specified)

### CDK Parameters
Configure in `cdk.json` or pass as context:
```bash
cdk deploy -c projectName=my-mlops-project -c modelPackageGroupName=my-models
```

### Terraform Variables
Create `terraform.tfvars` file:
```hcl
project_name = "my-mlops-project"
model_package_group_name = "fraud-detection-models"
aws_region = "us-east-1"
```

### Bash Script Environment Variables
```bash
export PROJECT_NAME="my-mlops-project"
export MODEL_PACKAGE_GROUP_NAME="fraud-detection-models"
export AWS_REGION="us-east-1"
./scripts/deploy.sh
```

## Post-Deployment Steps

1. **Upload Training Code**: Deploy your model training script to the created S3 bucket
2. **Configure Source Repository**: Set up your source code repository integration
3. **Upload Training Data**: Place your training datasets in the S3 bucket
4. **Trigger Pipeline**: Push code changes or manually start the pipeline execution

## Pipeline Execution

After deployment, trigger the pipeline:

```bash
# Get pipeline name from stack outputs
PIPELINE_NAME=$(aws cloudformation describe-stacks \
    --stack-name mlops-pipeline-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`PipelineName`].OutputValue' \
    --output text)

# Start pipeline execution
aws codepipeline start-pipeline-execution \
    --name $PIPELINE_NAME
```

Monitor pipeline progress:
```bash
aws codepipeline get-pipeline-state --name $PIPELINE_NAME
```

## Monitoring and Validation

### Check SageMaker Model Registry
```bash
aws sagemaker list-model-package-groups
aws sagemaker list-model-packages \
    --model-package-group-name fraud-detection-models
```

### View CodeBuild Logs
```bash
# Get build project name from outputs
BUILD_PROJECT=$(aws cloudformation describe-stacks \
    --stack-name mlops-pipeline-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`TrainingProjectName`].OutputValue' \
    --output text)

# List recent builds
aws codebuild list-builds-for-project --project-name $BUILD_PROJECT
```

### Monitor Pipeline Metrics
Access CloudWatch metrics for:
- Pipeline execution success/failure rates
- Build duration and success rates
- Model training job metrics
- Endpoint performance metrics

## Cleanup

> **Warning**: This will delete all resources including trained models and data. Ensure you have backups if needed.

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name mlops-pipeline-stack
```

Monitor deletion:
```bash
aws cloudformation describe-stacks \
    --stack-name mlops-pipeline-stack \
    --query 'Stacks[0].StackStatus'
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

## Customization

### Training Job Configuration
Modify training job parameters in the infrastructure code:
- Instance types (ml.m5.large, ml.m5.xlarge, etc.)
- Framework versions
- Hyperparameters
- Training data paths

### Pipeline Stages
Add or modify pipeline stages:
- Additional testing stages
- Security scanning
- Model validation steps
- Multi-environment deployments

### Security Enhancements
- Enable VPC endpoints for SageMaker
- Add KMS encryption for S3 and SageMaker
- Implement fine-grained IAM policies
- Enable CloudTrail logging

### Cost Optimization
- Use Spot instances for training jobs
- Implement auto-scaling for endpoints
- Set up S3 lifecycle policies
- Configure resource tagging for cost allocation

## Troubleshooting

### Common Issues

**Pipeline Fails at Training Stage**:
- Check CodeBuild logs for training job errors
- Verify SageMaker execution role permissions
- Ensure training data is accessible in S3

**Model Registration Fails**:
- Verify Model Package Group exists
- Check SageMaker permissions for model registry
- Ensure training job completed successfully

**Deployment Stage Fails**:
- Check Lambda function logs
- Verify model package approval status
- Ensure endpoint configuration is valid

### Debug Commands

```bash
# Check CodeBuild project status
aws codebuild batch-get-projects --names $BUILD_PROJECT

# List SageMaker training jobs
aws sagemaker list-training-jobs --sort-by CreationTime --sort-order Descending

# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/

# View pipeline execution details
aws codepipeline get-pipeline-execution \
    --pipeline-name $PIPELINE_NAME \
    --pipeline-execution-id $EXECUTION_ID
```

## Best Practices

### Development Workflow
1. Test model training locally before pipeline deployment
2. Use staging environments for pipeline validation
3. Implement model performance monitoring
4. Set up automated rollback mechanisms

### Security
- Regularly rotate IAM credentials
- Use least privilege access principles
- Enable encryption at rest and in transit
- Implement model lineage tracking

### Monitoring
- Set up CloudWatch alarms for pipeline failures
- Monitor model performance metrics
- Track data drift and model degradation
- Implement automated retraining triggers

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS service documentation for latest API changes
3. Validate IAM permissions and resource limits
4. Review CloudWatch logs for detailed error messages

## Additional Resources

- [AWS SageMaker MLOps Documentation](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-projects.html)
- [CodePipeline User Guide](https://docs.aws.amazon.com/codepipeline/latest/userguide/)
- [SageMaker Model Registry](https://docs.aws.amazon.com/sagemaker/latest/dg/model-registry.html)
- [MLOps Best Practices](https://aws.amazon.com/sagemaker/mlops/)