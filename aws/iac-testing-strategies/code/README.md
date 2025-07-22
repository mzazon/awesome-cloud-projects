# Infrastructure as Code for Infrastructure Testing Strategies for IaC

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Infrastructure Testing Strategies for IaC".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a comprehensive automated testing pipeline for Infrastructure as Code that includes:

- **CodeCommit Repository**: Source control for infrastructure templates
- **CodeBuild Project**: Automated testing execution environment
- **CodePipeline**: CI/CD orchestration for testing workflows
- **S3 Bucket**: Artifact storage for pipeline outputs
- **IAM Roles**: Least-privilege permissions for pipeline execution
- **Testing Framework**: Unit tests, security scans, cost analysis, and integration tests

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - CodeCommit, CodeBuild, CodePipeline
  - S3, CloudFormation, IAM
  - CloudWatch Logs
- Node.js 18+ and npm (for CDK TypeScript)
- Python 3.9+ and pip (for CDK Python and testing frameworks)
- Terraform 1.0+ (for Terraform deployment)
- Git configured for CodeCommit authentication

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name iac-testing-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=my-iac-testing \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name iac-testing-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name iac-testing-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure CDK (first time only)
npm run cdk bootstrap

# Deploy the stack
npm run cdk deploy

# View stack outputs
npm run cdk deploy -- --outputs-file outputs.json
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
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

# Check deployment status
aws codepipeline get-pipeline-state --name $(cat .deployment-vars | grep PIPELINE_NAME | cut -d'=' -f2)
```

## Post-Deployment Setup

After deploying the infrastructure, follow these steps to set up the testing framework:

### 1. Clone the Repository

```bash
# Get repository URL from stack outputs
REPO_URL=$(aws cloudformation describe-stacks \
    --stack-name iac-testing-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`RepositoryCloneUrl`].OutputValue' \
    --output text)

# Clone the repository
git clone $REPO_URL iac-testing-project
cd iac-testing-project
```

### 2. Add Sample Infrastructure Code

```bash
# Create directory structure
mkdir -p templates tests scripts

# Add sample CloudFormation template
cat > templates/s3-bucket.yaml << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Sample S3 bucket for testing'

Parameters:
  BucketName:
    Type: String
    Description: Name of the S3 bucket
    Default: test-bucket

Resources:
  S3Bucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub '${BucketName}-${AWS::AccountId}-${AWS::Region}'
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: AES256
      VersioningConfiguration:
        Status: Enabled

Outputs:
  BucketName:
    Description: Name of the created S3 bucket
    Value: !Ref S3Bucket
    Export:
      Name: !Sub '${AWS::StackName}-BucketName'
EOF

# Add testing framework files (see original recipe for complete test files)
# This includes buildspec.yml, test files, and requirements.txt
```

### 3. Commit and Push Code

```bash
# Add buildspec.yml for CodeBuild
cat > buildspec.yml << 'EOF'
version: 0.2

phases:
  install:
    runtime-versions:
      python: 3.9
    commands:
      - echo "Installing dependencies..."
      - pip install -r tests/requirements.txt
      - pip install awscli

  pre_build:
    commands:
      - echo "Pre-build phase started on `date`"
      - aws sts get-caller-identity

  build:
    commands:
      - echo "Running unit tests..."
      - cd tests && python -m pytest test_s3_bucket.py -v
      - cd ..
      - echo "Running security tests..."
      - python tests/security_test.py
      - echo "Running cost analysis..."
      - python tests/cost_analysis.py
      - echo "Running integration tests..."
      - python tests/integration_test.py

  post_build:
    commands:
      - echo "All tests completed successfully!"

artifacts:
  files:
    - '**/*'
  base-directory: .
EOF

# Commit and push to trigger pipeline
git add .
git commit -m "Add infrastructure testing framework"
git push origin main
```

## Monitoring and Validation

### Check Pipeline Status

```bash
# Monitor pipeline execution
aws codepipeline get-pipeline-state \
    --name your-pipeline-name \
    --query 'stageStates[*].[stageName,latestExecution.status]' \
    --output table

# View build logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/codebuild/"
```

### View Test Results

```bash
# Get latest build ID
BUILD_ID=$(aws codebuild list-builds-for-project \
    --project-name your-project-name \
    --query 'ids[0]' --output text)

# Check build status
aws codebuild batch-get-builds \
    --ids $BUILD_ID \
    --query 'builds[0].[buildStatus,currentPhase]'
```

## Customization

### Parameters and Variables

Each implementation supports customization through parameters:

- **ProjectName**: Base name for all resources (default: iac-testing)
- **RepositoryName**: Name of the CodeCommit repository
- **BucketName**: Name of the S3 artifacts bucket
- **BuildComputeType**: CodeBuild compute type (BUILD_GENERAL1_SMALL, etc.)
- **EnableCloudWatchLogs**: Enable detailed logging (true/false)

### Testing Framework Customization

Modify the testing framework by updating:

- **buildspec.yml**: Add new testing phases or tools
- **tests/requirements.txt**: Include additional Python testing libraries
- **tests/**: Add custom test files for your infrastructure templates
- **templates/**: Include your actual infrastructure templates

### Security Configuration

The implementation follows AWS security best practices:

- IAM roles use least-privilege permissions
- S3 buckets have public access blocked
- CodeBuild projects run in isolated environments
- CloudWatch logging enabled for audit trails

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name iac-testing-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name iac-testing-stack
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npm run cdk destroy
```

### Using CDK Python

```bash
cd cdk-python/
source .venv/bin/activate  # If using virtual environment
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **CodeBuild Permission Errors**
   - Verify IAM roles have necessary permissions
   - Check resource-based policies on S3 and CodeCommit

2. **Pipeline Fails on First Run**
   - Ensure repository contains required buildspec.yml
   - Verify all test dependencies are listed in requirements.txt

3. **Integration Tests Fail**
   - Check CloudFormation template syntax
   - Verify AWS credentials in CodeBuild environment

4. **Cost Analysis Warnings**
   - Review resource configurations for cost optimization
   - Consider implementing lifecycle policies

### Debugging

Enable verbose logging by:

```bash
# For CloudFormation
aws cloudformation describe-stack-events --stack-name iac-testing-stack

# For CodeBuild
aws logs get-log-events \
    --log-group-name /aws/codebuild/your-project-name \
    --log-stream-name your-stream-name
```

## Best Practices

1. **Security Testing**: Always include security validation in your testing pipeline
2. **Cost Monitoring**: Implement cost analysis to prevent billing surprises
3. **Version Control**: Use semantic versioning for infrastructure templates
4. **Documentation**: Keep testing documentation up-to-date with infrastructure changes
5. **Compliance**: Regularly update compliance checks based on organizational requirements

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for detailed implementation guidance
2. Check AWS CloudFormation, CodeBuild, and CodePipeline documentation
3. Validate IAM permissions and resource configurations
4. Monitor CloudWatch logs for detailed error information

## Additional Resources

- [AWS CloudFormation Best Practices](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/best-practices.html)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [AWS CodePipeline User Guide](https://docs.aws.amazon.com/codepipeline/latest/userguide/)
- [Infrastructure Testing Strategies](https://aws.amazon.com/blogs/devops/testing-infrastructure-as-code-on-aws/)