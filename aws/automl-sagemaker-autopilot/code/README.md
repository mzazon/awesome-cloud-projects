# Infrastructure as Code for AutoML Solutions with SageMaker Autopilot

This directory contains Infrastructure as Code (IaC) implementations for the recipe "AutoML Solutions with SageMaker Autopilot".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon SageMaker (AutoML jobs, models, endpoints)
  - Amazon S3 (bucket creation, object management)
  - AWS IAM (role creation and policy attachment)
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name sagemaker-autopilot-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=autopilot-demo

# Monitor deployment
aws cloudformation describe-stack-events \
    --stack-name sagemaker-autopilot-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name sagemaker-autopilot-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy --parameters projectName=autopilot-demo

# View outputs
npx cdk ls --long
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters projectName=autopilot-demo

# View outputs
cdk ls --long
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_name=autopilot-demo"

# Apply configuration
terraform apply -var="project_name=autopilot-demo"

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

## Architecture Overview

The infrastructure deploys the following components:

- **S3 Bucket**: Stores training data, model artifacts, and generated notebooks
- **IAM Role**: Provides SageMaker Autopilot with necessary permissions
- **SageMaker Autopilot Job**: Automated machine learning pipeline
- **SageMaker Model**: Best candidate model from Autopilot
- **SageMaker Endpoint**: Real-time inference endpoint
- **SageMaker Endpoint Configuration**: Defines compute resources

## Configuration Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| ProjectName | Prefix for resource names | autopilot-demo | Yes |
| S3BucketName | Custom S3 bucket name | auto-generated | No |
| InstanceType | SageMaker endpoint instance type | ml.m5.large | No |
| MaxCandidates | Maximum model candidates to train | 10 | No |
| MaxRuntimeHours | Maximum training runtime (hours) | 4 | No |
| TargetAttribute | Target column for prediction | churn | No |

## Deployment Workflow

1. **Infrastructure Setup**: Creates S3 bucket and IAM role
2. **Data Preparation**: Uploads sample dataset to S3
3. **AutoML Job**: Launches SageMaker Autopilot job
4. **Model Training**: Automated feature engineering and model training
5. **Endpoint Deployment**: Deploys best model to real-time endpoint
6. **Validation**: Tests endpoint with sample predictions

## Usage Examples

### Testing the Deployed Endpoint

```bash
# Get endpoint name from outputs
ENDPOINT_NAME=$(aws cloudformation describe-stacks \
    --stack-name sagemaker-autopilot-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`EndpointName`].OutputValue' \
    --output text)

# Test with sample data
echo "42,12,65.30,783.60,Month-to-month,Electronic check" | \
aws sagemaker-runtime invoke-endpoint \
    --endpoint-name $ENDPOINT_NAME \
    --content-type text/csv \
    --body fileb:///dev/stdin \
    prediction_result.json

# View prediction
cat prediction_result.json
```

### Monitoring AutoML Job Progress

```bash
# Get job name from outputs
JOB_NAME=$(aws cloudformation describe-stacks \
    --stack-name sagemaker-autopilot-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`AutoMLJobName`].OutputValue' \
    --output text)

# Monitor job status
aws sagemaker describe-auto-ml-job-v2 \
    --auto-ml-job-name $JOB_NAME \
    --query 'AutoMLJobStatus'
```

### Accessing Generated Notebooks

```bash
# Get S3 bucket name
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name sagemaker-autopilot-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
    --output text)

# Download generated notebooks
aws s3 sync s3://$BUCKET_NAME/output/ ./autopilot-artifacts/ \
    --exclude "*" --include "*.ipynb"
```

## Cost Optimization

### Estimated Costs

- **S3 Storage**: $0.023 per GB per month
- **AutoML Job**: $0.45-$1.80 per hour (depends on dataset size)
- **Real-time Endpoint**: $0.048-$0.192 per hour (ml.m5.large)
- **Batch Transform**: $0.048-$0.192 per hour (when used)

### Cost Reduction Tips

1. **Use Smaller Instance Types**: Start with ml.t3.medium for testing
2. **Limit Training Time**: Set reasonable MaxRuntimeHours
3. **Use Batch Transform**: For bulk predictions instead of real-time endpoint
4. **Clean Up Resources**: Delete endpoints when not in use

## Security Considerations

### IAM Permissions

The deployed IAM role follows least privilege principles:
- SageMaker: Full access for AutoML operations
- S3: Access limited to the specific bucket
- CloudWatch: Logging permissions only

### Data Security

- S3 bucket uses server-side encryption (SSE-S3)
- VPC endpoints can be configured for private network access
- Model artifacts are encrypted at rest

### Network Security

```bash
# Optional: Deploy in VPC (add to parameters)
--parameters ParameterKey=VpcId,ParameterValue=vpc-12345678 \
            ParameterKey=SubnetIds,ParameterValue=subnet-12345678,subnet-87654321
```

## Troubleshooting

### Common Issues

1. **AutoML Job Fails**:
   - Check CloudWatch logs: `/aws/sagemaker/autopilot/{job-name}`
   - Verify data format and target column
   - Ensure sufficient IAM permissions

2. **Endpoint Deployment Fails**:
   - Check instance type availability in region
   - Verify service limits and quotas
   - Review CloudTrail for detailed error messages

3. **Permission Errors**:
   - Ensure CloudFormation has CAPABILITY_IAM
   - Verify AWS CLI credentials have sufficient permissions
   - Check IAM role trust relationships

### Debugging Commands

```bash
# Check AutoML job details
aws sagemaker describe-auto-ml-job-v2 \
    --auto-ml-job-name $JOB_NAME

# View CloudWatch logs
aws logs describe-log-groups \
    --log-group-name-prefix /aws/sagemaker/autopilot

# Check endpoint status
aws sagemaker describe-endpoint \
    --endpoint-name $ENDPOINT_NAME
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name sagemaker-autopilot-stack

# Monitor deletion
aws cloudformation describe-stack-events \
    --stack-name sagemaker-autopilot-stack
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npx cdk destroy
```

### Using CDK Python
```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy -var="project_name=autopilot-demo"
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Stop any running AutoML jobs
aws sagemaker stop-auto-ml-job \
    --auto-ml-job-name $JOB_NAME

# Delete endpoints
aws sagemaker delete-endpoint \
    --endpoint-name $ENDPOINT_NAME

# Empty and delete S3 bucket
aws s3 rm s3://$BUCKET_NAME --recursive
aws s3 rb s3://$BUCKET_NAME

# Delete IAM role
aws iam detach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess

aws iam delete-role --role-name $ROLE_NAME
```

## Customization

### Modifying Training Data

Replace the sample dataset by:
1. Uploading your CSV file to the S3 bucket
2. Updating the `TargetAttribute` parameter
3. Ensuring proper data format (CSV with headers)

### Changing Model Type

```bash
# For regression problems
--parameters ParameterKey=ProblemType,ParameterValue=Regression

# For multi-class classification
--parameters ParameterKey=ProblemType,ParameterValue=MulticlassClassification
```

### Scaling Configuration

```bash
# Increase endpoint instances
--parameters ParameterKey=InitialInstanceCount,ParameterValue=2

# Use larger instance type
--parameters ParameterKey=InstanceType,ParameterValue=ml.m5.xlarge
```

## Support

For issues with this infrastructure code:
1. Check the [original recipe documentation](../automl-solutions-amazon-sagemaker-autopilot.md)
2. Review [AWS SageMaker documentation](https://docs.aws.amazon.com/sagemaker/)
3. Consult [AWS CloudFormation documentation](https://docs.aws.amazon.com/cloudformation/)
4. Check [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
5. Review [Terraform AWS provider documentation](https://registry.terraform.io/providers/hashicorp/aws/)

## Additional Resources

- [SageMaker Autopilot User Guide](https://docs.aws.amazon.com/sagemaker/latest/dg/autopilot-automate-model-development.html)
- [SageMaker Pricing](https://aws.amazon.com/sagemaker/pricing/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [SageMaker Best Practices](https://docs.aws.amazon.com/sagemaker/latest/dg/best-practices.html)