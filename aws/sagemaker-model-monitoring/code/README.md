# Infrastructure as Code for SageMaker Model Monitoring and Drift Detection

This directory contains Infrastructure as Code (IaC) implementations for the recipe "SageMaker Model Monitoring and Drift Detection".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a comprehensive ML model monitoring system using:

- **SageMaker Model Monitor**: Automated drift detection and data quality monitoring
- **SageMaker Endpoints**: Real-time model inference with data capture
- **CloudWatch**: Metrics, alarms, and dashboards for monitoring visualization
- **Lambda**: Automated response to monitoring alerts
- **SNS**: Real-time notification system for drift detection
- **S3**: Storage for captured data, baseline statistics, and monitoring results
- **IAM**: Secure role-based access control for all components

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - SageMaker (full access for model deployment and monitoring)
  - CloudWatch (metrics, alarms, and dashboards)
  - Lambda (function creation and execution)
  - S3 (bucket creation and object management)
  - SNS (topic creation and subscription management)
  - IAM (role and policy management)
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.5+ (for Terraform deployment)
- Estimated deployment time: 20-30 minutes
- Estimated cost: $50-100 for resources during testing

> **Note**: Ensure you have sufficient SageMaker service limits for endpoint deployment and processing jobs in your target region.

## Quick Start

### Using CloudFormation

```bash
# Deploy the complete monitoring infrastructure
aws cloudformation create-stack \
    --stack-name sagemaker-model-monitor \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=EmailAddress,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name sagemaker-model-monitor

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name sagemaker-model-monitor \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Install dependencies
cd cdk-typescript/
npm install

# Configure deployment parameters
export CDK_DEFAULT_REGION=us-east-1
export EMAIL_ADDRESS=your-email@example.com

# Deploy the infrastructure
cdk bootstrap
cdk deploy SageMakerModelMonitorStack

# View deployment outputs
cdk outputs
```

### Using CDK Python

```bash
# Set up Python environment
cd cdk-python/
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt

# Configure deployment parameters
export CDK_DEFAULT_REGION=us-east-1
export EMAIL_ADDRESS=your-email@example.com

# Deploy the infrastructure
cdk bootstrap
cdk deploy SageMakerModelMonitorStack

# View deployment outputs
cdk outputs
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your configuration

# Plan the deployment
terraform plan -var="email_address=your-email@example.com"

# Apply the infrastructure
terraform apply -var="email_address=your-email@example.com"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export AWS_REGION=us-east-1
export EMAIL_ADDRESS=your-email@example.com

# Deploy the complete solution
./scripts/deploy.sh

# Check deployment status
aws sagemaker describe-endpoint --endpoint-name $(cat endpoint-name.txt)
```

## Configuration Options

### Key Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `email_address` | Email for monitoring alerts | - | Yes |
| `aws_region` | AWS deployment region | us-east-1 | No |
| `environment` | Environment tag (dev/staging/prod) | dev | No |
| `monitoring_frequency` | Data quality monitoring frequency | hourly | No |
| `instance_type` | SageMaker endpoint instance type | ml.t2.medium | No |
| `enable_model_quality` | Enable model quality monitoring | true | No |

### CloudFormation Parameters

```yaml
Parameters:
  EmailAddress:
    Type: String
    Description: Email address for monitoring alerts
  Environment:
    Type: String
    Default: dev
    AllowedValues: [dev, staging, prod]
  MonitoringFrequency:
    Type: String
    Default: hourly
    AllowedValues: [hourly, daily]
```

### Terraform Variables

```hcl
variable "email_address" {
  description = "Email address for monitoring alerts"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "monitoring_frequency" {
  description = "Monitoring schedule frequency"
  type        = string
  default     = "hourly"
}
```

## Post-Deployment Steps

### 1. Confirm SNS Subscription

After deployment, check your email and confirm the SNS subscription to receive monitoring alerts.

### 2. Generate Sample Traffic

Use the provided test script to generate sample inference requests:

```bash
# Generate sample model traffic
python3 scripts/generate_traffic.py --endpoint-name <endpoint-name> --requests 100
```

### 3. Verify Monitoring

Check that monitoring schedules are active:

```bash
# List monitoring schedules
aws sagemaker list-monitoring-schedules

# Check schedule status
aws sagemaker describe-monitoring-schedule \
    --monitoring-schedule-name <schedule-name>
```

### 4. View Dashboard

Access the CloudWatch dashboard to monitor model performance:

```bash
# Open CloudWatch console and navigate to dashboards
aws cloudwatch list-dashboards
```

## Monitoring and Alerts

### CloudWatch Metrics

The solution creates custom metrics for:

- Constraint violations detected
- Monitoring job failures
- Data capture statistics
- Model quality metrics

### Automated Alerts

Alerts are triggered for:

- **Data Drift**: When input data distribution changes
- **Constraint Violations**: When data quality rules are violated
- **Job Failures**: When monitoring jobs fail to complete
- **Model Quality**: When prediction accuracy degrades (if enabled)

### Response Actions

Lambda functions automatically:

- Send detailed alert notifications
- Log monitoring events
- Can be extended to trigger retraining pipelines

## Troubleshooting

### Common Issues

1. **Endpoint Creation Fails**
   ```bash
   # Check service limits
   aws service-quotas get-service-quota \
       --service-code sagemaker \
       --quota-code L-1194F242
   ```

2. **Monitoring Jobs Fail**
   ```bash
   # Check IAM permissions
   aws iam simulate-principal-policy \
       --policy-source-arn <model-monitor-role-arn> \
       --action-names sagemaker:CreateProcessingJob
   ```

3. **No Data Captured**
   ```bash
   # Verify data capture configuration
   aws sagemaker describe-endpoint-config \
       --endpoint-config-name <config-name> \
       --query 'DataCaptureConfig'
   ```

### Log Analysis

Monitor CloudWatch logs for troubleshooting:

```bash
# View SageMaker processing job logs
aws logs describe-log-groups --log-group-name-prefix /aws/sagemaker/ProcessingJobs

# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/model-monitor
```

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name sagemaker-model-monitor

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name sagemaker-model-monitor
```

### Using CDK

```bash
# Destroy CDK stack
cd cdk-typescript/  # or cdk-python/
cdk destroy SageMakerModelMonitorStack

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Destroy Terraform infrastructure
cd terraform/
terraform destroy -var="email_address=your-email@example.com"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify all resources are deleted
aws sagemaker list-endpoints
aws s3 ls | grep model-monitor
```

### Manual Cleanup Verification

Ensure the following resources are removed:

- SageMaker endpoints and configurations
- S3 buckets and contents
- CloudWatch alarms and dashboards
- Lambda functions
- SNS topics and subscriptions
- IAM roles and policies

## Cost Optimization

### Resource Sizing

- **Endpoint Instance**: Start with `ml.t2.medium` for testing
- **Processing Jobs**: Use `ml.m5.xlarge` for standard workloads
- **Monitoring Frequency**: Consider daily vs hourly based on use case

### Cost Monitoring

```bash
# Estimate costs using AWS Cost Explorer API
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Security Considerations

### IAM Best Practices

- Roles follow principle of least privilege
- Cross-service access is explicitly defined
- Resource-level permissions where applicable

### Data Protection

- S3 buckets have default encryption enabled
- VPC endpoints can be configured for private communication
- CloudWatch logs are encrypted at rest

### Access Control

- All resources are tagged for cost tracking
- Environment-specific resource naming
- Cross-account access can be configured via role assumption

## Advanced Configuration

### Custom Monitoring Logic

Extend the Lambda function for custom response actions:

```python
# Example: Trigger automated retraining
def trigger_retraining_pipeline(model_name, drift_metrics):
    # Custom logic to start SageMaker training job
    pass
```

### Multi-Model Monitoring

Scale the solution for multiple models:

```bash
# Deploy additional monitoring schedules
for model in model1 model2 model3; do
    terraform apply -var="model_name=$model"
done
```

### Integration with MLOps Pipelines

Connect monitoring to CI/CD workflows:

```yaml
# Example GitHub Actions integration
- name: Check Model Drift
  run: |
    aws sagemaker describe-monitoring-schedule \
        --monitoring-schedule-name ${{ env.SCHEDULE_NAME }}
```

## Support and Documentation

- [Original Recipe Documentation](../model-monitoring-drift-detection-sagemaker-model-monitor.md)
- [AWS SageMaker Model Monitor Documentation](https://docs.aws.amazon.com/sagemaker/latest/dg/model-monitor.html)
- [CloudFormation SageMaker Reference](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/AWS_SageMaker.html)
- [CDK SageMaker Module Documentation](https://docs.aws.amazon.com/cdk/api/v2/python/aws_cdk.aws_sagemaker.html)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

For issues with this infrastructure code, refer to the troubleshooting section above or consult the AWS documentation for specific services.