# Infrastructure as Code for Architecture Assessment with AWS Well-Architected Tool

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Architecture Assessment with AWS Well-Architected Tool".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS credentials with the following permissions:
  - `wellarchitected:*` (Well-Architected Tool access)
  - `cloudwatch:*` (CloudWatch monitoring)
  - `iam:GetUser` (Identity verification)
  - `sts:GetCallerIdentity` (Account verification)
- Basic understanding of cloud architecture concepts
- For CDK implementations: Node.js 16.x+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed

> **Note**: The AWS Well-Architected Tool assessments are free of charge. This implementation focuses on automating the assessment workflow and integrating with CloudWatch for monitoring.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name well-architected-assessment \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=WorkloadName,ParameterValue=my-workload \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name well-architected-assessment \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name well-architected-assessment \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy

# View stack outputs
npx cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
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
aws wellarchitected list-workloads --query 'WorkloadSummaries[].WorkloadName'
```

## Architecture Components

This implementation creates the following resources:

### Core Components
- **Well-Architected Workload**: Primary assessment entity
- **CloudWatch Dashboard**: Monitoring and metrics visualization
- **CloudWatch Log Group**: Assessment activity logging
- **IAM Role**: Automated assessment permissions

### Monitoring Integration
- **Custom Metrics**: Track assessment progress and completion
- **CloudWatch Alarms**: Alert on assessment milestones
- **Event Rules**: Automate assessment workflow triggers

## Configuration Options

### Environment Variables

```bash
# Set these before deployment
export AWS_REGION="us-east-1"
export WORKLOAD_NAME="my-application"
export ENVIRONMENT="PREPRODUCTION"  # or PRODUCTION
export INDUSTRY_TYPE="InfoTech"     # or other industry
```

### CloudFormation Parameters

- `WorkloadName`: Name for the Well-Architected workload
- `Environment`: Workload environment (PREPRODUCTION/PRODUCTION)
- `IndustryType`: Industry classification for the workload
- `ReviewOwner`: IAM ARN of the review owner (defaults to current user)

### CDK Context Variables

```json
{
  "workload-name": "my-workload",
  "environment": "PREPRODUCTION",
  "industry-type": "InfoTech",
  "enable-monitoring": true
}
```

### Terraform Variables

```hcl
# terraform.tfvars
workload_name = "my-application"
environment = "PREPRODUCTION"
industry_type = "InfoTech"
aws_region = "us-east-1"
enable_cloudwatch_integration = true
```

## Monitoring and Observability

### CloudWatch Integration

The implementation includes comprehensive monitoring:

```bash
# View assessment metrics
aws cloudwatch get-metric-statistics \
    --namespace "AWS/WellArchitected" \
    --metric-name "AssessmentProgress" \
    --start-time 2025-01-01T00:00:00Z \
    --end-time 2025-01-31T23:59:59Z \
    --period 3600 \
    --statistics Average

# Check dashboard
aws cloudwatch get-dashboard \
    --dashboard-name "WellArchitectedAssessment"
```

### Assessment Automation

```bash
# Trigger automated assessment workflow
aws events put-events \
    --entries Source=wellarchitected.assessment,DetailType="Assessment Started"

# Monitor assessment completion
aws logs filter-log-events \
    --log-group-name "/aws/wellarchitected/assessments" \
    --filter-pattern "COMPLETED"
```

## Validation and Testing

### Verify Deployment

```bash
# Check workload creation
aws wellarchitected list-workloads \
    --query 'WorkloadSummaries[].{Name:WorkloadName,Status:WorkloadArn}'

# Verify CloudWatch resources
aws cloudwatch list-dashboards \
    --dashboard-name-prefix "WellArchitected"

# Test lens review access
aws wellarchitected get-lens-review \
    --workload-id $(aws wellarchitected list-workloads --query 'WorkloadSummaries[0].WorkloadId' --output text) \
    --lens-alias "wellarchitected"
```

### Integration Testing

```bash
# Run assessment workflow test
./scripts/test-assessment.sh

# Validate monitoring integration
aws cloudwatch get-metric-data \
    --metric-data-queries file://test-metrics.json \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ)
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name well-architected-assessment

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name well-architected-assessment
```

### Using CDK

```bash
# Destroy TypeScript stack
cd cdk-typescript/
npx cdk destroy

# Destroy Python stack
cd cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
# Clean up all resources
./scripts/destroy.sh

# Verify cleanup
aws wellarchitected list-workloads --query 'length(WorkloadSummaries)'
```

### Manual Cleanup Verification

```bash
# Ensure no orphaned resources remain
aws wellarchitected list-workloads
aws cloudwatch list-dashboards
aws logs describe-log-groups --log-group-name-prefix "/aws/wellarchitected"
```

## Customization

### Advanced Configuration

#### Multi-Environment Setup

```bash
# Deploy to multiple environments
for env in dev staging prod; do
    aws cloudformation create-stack \
        --stack-name "well-architected-${env}" \
        --template-body file://cloudformation.yaml \
        --parameters ParameterKey=Environment,ParameterValue=${env}
done
```

#### Custom Lens Integration

```hcl
# terraform/custom-lens.tf
resource "aws_wellarchitected_lens" "custom" {
  lens_json = file("${path.module}/custom-lens.json")
  
  tags = {
    Environment = var.environment
    Purpose = "CustomAssessment"
  }
}
```

#### Assessment Automation

```python
# cdk-python/assessment_automation.py
from aws_cdk import aws_events as events
from aws_cdk import aws_lambda as lambda_

class AssessmentAutomation(Construct):
    def __init__(self, scope: Construct, construct_id: str):
        super().__init__(scope, construct_id)
        
        # Lambda function for automated assessments
        assessment_function = lambda_.Function(
            self, "AssessmentFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="assessment.handler",
            code=lambda_.Code.from_asset("lambda")
        )
        
        # EventBridge rule for scheduled assessments
        rule = events.Rule(
            self, "AssessmentSchedule",
            schedule=events.Schedule.rate(Duration.days(30))
        )
        
        rule.add_target(targets.LambdaFunction(assessment_function))
```

## Troubleshooting

### Common Issues

#### Workload Creation Fails

```bash
# Check IAM permissions
aws iam simulate-principal-policy \
    --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
    --action-names wellarchitected:CreateWorkload \
    --resource-arns "*"

# Verify region availability
aws wellarchitected list-lenses --region $AWS_REGION
```

#### CloudWatch Integration Issues

```bash
# Check CloudWatch permissions
aws logs describe-log-groups --log-group-name-prefix "/aws/wellarchitected"

# Verify metrics namespace
aws cloudwatch list-metrics --namespace "AWS/WellArchitected"
```

#### Assessment Access Problems

```bash
# Verify workload ownership
aws wellarchitected get-workload \
    --workload-id $WORKLOAD_ID \
    --query 'Workload.ReviewOwner'

# Check lens availability
aws wellarchitected list-lenses \
    --query 'LensSummaries[?LensAlias==`wellarchitected`]'
```

### Debug Commands

```bash
# Enable debug logging for CDK
export CDK_DEBUG=true
cdk deploy --verbose

# Terraform debug mode
export TF_LOG=DEBUG
terraform apply

# CloudFormation stack events
aws cloudformation describe-stack-events \
    --stack-name well-architected-assessment
```

## Security Considerations

### IAM Best Practices

- Use least privilege principle for Well-Architected Tool access
- Implement resource-based policies where applicable
- Enable CloudTrail logging for assessment activities
- Regular review of assessment permissions and access

### Data Protection

- Assessment data is encrypted at rest by default
- Use VPC endpoints for private API access when available
- Implement proper logging and monitoring for compliance

## Cost Optimization

### Resource Costs

- **Well-Architected Tool**: Free of charge
- **CloudWatch**: Pay for custom metrics and dashboard usage
- **Lambda**: Pay per assessment automation execution
- **CloudWatch Logs**: Pay for log ingestion and retention

### Cost Monitoring

```bash
# Monitor Well-Architected related costs
aws ce get-cost-and-usage \
    --time-period Start=2025-01-01,End=2025-02-01 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon CloudWatch","AWS Lambda"]}}'
```

## Support

For issues with this infrastructure code, refer to:

1. [Original recipe documentation](../architecture-assessment-well-architected-tool.md)
2. [AWS Well-Architected Tool User Guide](https://docs.aws.amazon.com/wellarchitected/latest/userguide/)
3. [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/)
4. [CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)
5. [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
6. [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)

## Contributing

When modifying this infrastructure code:

1. Test changes in a development environment first
2. Update documentation for any new parameters or outputs
3. Ensure compatibility across all IaC implementations
4. Follow AWS security best practices
5. Update cost estimates if resource usage changes