# Infrastructure as Code for Feature Flags with CloudWatch Evidently

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Feature Flags with CloudWatch Evidently".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - CloudWatch Evidently (create projects, features, launches)
  - AWS Lambda (create functions, manage execution roles)
  - IAM (create roles, attach policies)
  - CloudWatch Logs (create log groups, write logs)
- For CDK: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+
- Estimated cost: $5-15/month for development usage

## Architecture Overview

This implementation deploys:
- CloudWatch Evidently project for feature flag management
- Feature flag with boolean variations (enabled/disabled)
- Launch configuration for gradual rollout (10% traffic split)
- Lambda function for feature evaluation
- IAM role with appropriate permissions
- CloudWatch Logs integration for evaluation tracking

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name evidently-feature-flags \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-feature-demo

# Monitor deployment
aws cloudformation describe-stacks \
    --stack-name evidently-feature-flags \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name evidently-feature-flags \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk list
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

# The script will prompt for project name and display progress
```

## Testing the Deployment

After deployment, test the feature flag functionality:

### Test Lambda Function
```bash
# Get the Lambda function name from outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name evidently-feature-flags \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Test feature evaluation
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload '{"userId": "test-user-123"}' \
    response.json

# View the result
cat response.json | jq '.'
```

### Monitor Feature Evaluations
```bash
# Check evaluation logs
aws logs describe-log-streams \
    --log-group-name "/aws/evidently/evaluations" \
    --order-by LastEventTime \
    --descending \
    --max-items 5
```

### Verify Launch Status
```bash
# Get project name from outputs
PROJECT_NAME=$(aws cloudformation describe-stacks \
    --stack-name evidently-feature-flags \
    --query 'Stacks[0].Outputs[?OutputKey==`ProjectName`].OutputValue' \
    --output text)

# Check launch status
aws evidently get-launch \
    --project ${PROJECT_NAME} \
    --launch "checkout-gradual-rollout" \
    --query 'status'
```

## Customization

### CloudFormation Parameters
- `ProjectName`: Name for the Evidently project (default: feature-demo-{random})
- `FeatureName`: Name for the feature flag (default: new-checkout-flow)
- `LaunchName`: Name for the launch configuration (default: checkout-gradual-rollout)
- `TreatmentPercentage`: Percentage of traffic for new feature (default: 10)

### CDK Configuration
Modify the configuration in the stack constructor:
```typescript
// TypeScript
const project = new evidently.CfnProject(this, 'EvidentlyProject', {
  name: props.projectName || 'feature-demo',
  description: 'Feature flag demonstration project'
});
```

```python
# Python
project = evidently.CfnProject(
    self, "EvidentlyProject",
    name=project_name or "feature-demo",
    description="Feature flag demonstration project"
)
```

### Terraform Variables
Edit `terraform.tfvars` or pass variables during apply:
```bash
terraform apply \
    -var="project_name=my-custom-project" \
    -var="feature_name=my-feature" \
    -var="treatment_percentage=20"
```

### Script Customization
The bash scripts support environment variables:
```bash
export PROJECT_NAME="my-feature-project"
export TREATMENT_PERCENTAGE=15
./scripts/deploy.sh
```

## Advanced Configuration

### Multi-Environment Setup
Deploy to different environments by customizing parameters:

```bash
# Development environment
aws cloudformation create-stack \
    --stack-name evidently-dev \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=feature-demo-dev \
                 ParameterKey=TreatmentPercentage,ParameterValue=5

# Production environment
aws cloudformation create-stack \
    --stack-name evidently-prod \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=feature-demo-prod \
                 ParameterKey=TreatmentPercentage,ParameterValue=1
```

### Additional Features
Extend the implementation by:
1. Adding custom metrics for launch optimization
2. Implementing audience targeting rules
3. Creating multiple feature flags with dependencies
4. Setting up automated rollback triggers
5. Integrating with CI/CD pipelines

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name evidently-feature-flags

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name evidently-feature-flags \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# From the CDK directory
cdk destroy

# Confirm when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

## Troubleshooting

### Common Issues

**Evidently Service Not Available**
CloudWatch Evidently is available in limited regions. Ensure you're deploying in a supported region:
- US East (N. Virginia)
- US East (Ohio)
- US West (Oregon)
- Europe (Ireland)
- Asia Pacific (Sydney)

**IAM Permission Errors**
Ensure your AWS credentials have the following permissions:
- `evidently:*`
- `lambda:*`
- `iam:CreateRole`, `iam:AttachRolePolicy`
- `logs:CreateLogGroup`, `logs:PutLogEvents`

**Lambda Function Timeout**
If feature evaluation fails, check:
- Network connectivity to Evidently service
- IAM role permissions
- CloudWatch Logs for error details

### Debug Commands
```bash
# Check stack events for errors
aws cloudformation describe-stack-events \
    --stack-name evidently-feature-flags

# View Lambda logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
    --start-time $(date -d '1 hour ago' +%s)000

# Test network connectivity
aws evidently list-projects --region ${AWS_REGION}
```

## Cost Optimization

- Evidently charges per feature evaluation (free tier: 1M evaluations/month)
- Lambda function costs scale with usage (free tier: 1M requests/month)
- CloudWatch Logs storage costs apply (first 5GB/month free)
- Consider using Evidently's caching mechanisms for high-traffic applications

## Security Considerations

- Lambda execution role follows least privilege principle
- Feature evaluation logs may contain user identifiers
- Consider data retention policies for CloudWatch Logs
- Implement proper authentication for Lambda API endpoints
- Review IAM policies regularly for unused permissions

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS CloudWatch Evidently documentation
3. Consult the original recipe documentation
4. Check AWS service health dashboard for regional issues

## Related Resources

- [AWS CloudWatch Evidently Documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Evidently.html)
- [Feature Flag Best Practices](https://docs.aws.amazon.com/wellarchitected/latest/management-and-governance-lens/feature-flags.html)
- [Lambda Function Configuration](https://docs.aws.amazon.com/lambda/latest/dg/configuration-function-common.html)
- [CDK Evidently Constructs](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_evidently-readme.html)