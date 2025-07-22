# Infrastructure as Code for Monitoring Application Resilience with AWS Resilience Hub and EventBridge

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Monitoring Application Resilience with AWS Resilience Hub and EventBridge".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements proactive application resilience monitoring using:

- **AWS Resilience Hub**: Continuous resilience assessment and policy compliance
- **Amazon EventBridge**: Event-driven automation for resilience events
- **AWS Systems Manager**: Automated remediation workflows
- **Amazon CloudWatch**: Comprehensive monitoring, dashboards, and alerting
- **AWS Lambda**: Event processing and custom automation logic

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with administrative permissions for:
  - AWS Resilience Hub
  - Amazon EventBridge
  - AWS Systems Manager
  - Amazon CloudWatch
  - AWS Lambda
  - Amazon EC2
  - Amazon RDS
  - IAM (for role creation)
- Basic understanding of AWS Well-Architected Framework resilience principles
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python and Lambda functions)
- Terraform 1.5+ (for Terraform deployment)

## Cost Considerations

Estimated cost for 24-hour testing period: $15-25 USD

- EC2 t3.micro instances: ~$2-4
- RDS db.t3.micro: ~$8-12
- CloudWatch metrics and dashboards: ~$2-4
- EventBridge events: ~$1-2
- Lambda function executions: <$1
- AWS Resilience Hub assessments: ~$2-3

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name resilience-monitoring-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=Environment,ParameterValue=demo \
                 ParameterKey=AppName,ParameterValue=my-resilience-app

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name resilience-monitoring-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name resilience-monitoring-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Review what will be deployed
cdk diff

# Deploy the stack
cdk deploy --require-approval never

# Get stack outputs
cdk ls
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

# Review what will be deployed
cdk diff

# Deploy the stack
cdk deploy --require-approval never

# Get stack outputs
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
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

# The script will:
# 1. Validate prerequisites
# 2. Create unique resource identifiers
# 3. Deploy all infrastructure components
# 4. Configure monitoring and alerting
# 5. Run initial resilience assessment
```

## Post-Deployment Steps

After deploying the infrastructure, complete these steps:

1. **Verify Application Registration**:
   ```bash
   # Check application status in Resilience Hub
   aws resiliencehub list-apps --query 'apps[?contains(appName, `resilience-demo`)]'
   ```

2. **Monitor Initial Assessment**:
   ```bash
   # Check assessment progress
   aws resiliencehub list-app-assessments \
       --app-arn $(aws resiliencehub list-apps \
           --query 'apps[0].appArn' --output text)
   ```

3. **Access CloudWatch Dashboard**:
   - Navigate to CloudWatch console
   - Select "Dashboards" from left menu
   - Open "Application-Resilience-Monitoring" dashboard

4. **Test Event Processing**:
   ```bash
   # Monitor Lambda function logs
   aws logs tail /aws/lambda/resilience-processor-* --follow
   ```

## Configuration Options

### Environment Variables

All implementations support these configuration parameters:

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| Environment | Environment name (dev/test/prod) | demo | No |
| AppName | Application name prefix | resilience-demo-app | No |
| ResilienceThreshold | Critical resilience score threshold | 70 | No |
| WarningThreshold | Warning resilience score threshold | 80 | No |
| NotificationEmail | Email for SNS notifications | none | No |
| EnableMultiAZ | Enable Multi-AZ RDS deployment | true | No |

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
environment = "production"
app_name = "my-production-app"
resilience_threshold = 75
warning_threshold = 85
notification_email = "ops-team@company.com"
enable_multi_az = true
```

### CloudFormation Parameters

Override parameters during deployment:

```bash
aws cloudformation create-stack \
    --stack-name resilience-monitoring-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=Environment,ParameterValue=production \
                 ParameterKey=ResilienceThreshold,ParameterValue=75 \
                 ParameterKey=NotificationEmail,ParameterValue=ops@company.com
```

## Monitoring and Validation

### CloudWatch Metrics

The solution creates custom metrics in the `ResilienceHub/Monitoring` namespace:

- **ResilienceScore**: Application resilience score percentage
- **AssessmentEvents**: Count of assessment events by status
- **ProcessingErrors**: Count of event processing errors

### CloudWatch Alarms

Three types of alarms are configured:

1. **Critical-Low-Resilience-Score**: Triggers when score < 70%
2. **Warning-Low-Resilience-Score**: Triggers when score < 80%
3. **Resilience-Assessment-Failures**: Triggers on repeated assessment failures

### Dashboard Components

The CloudWatch dashboard includes:

- Resilience score trend with threshold annotations
- Assessment events and processing status
- Recent resilience events and processing logs

### Log Analysis

Monitor Lambda function execution:

```bash
# Real-time log monitoring
aws logs tail /aws/lambda/resilience-processor-* --follow --since 1h

# Search for specific events
aws logs filter-log-events \
    --log-group-name /aws/lambda/resilience-processor-* \
    --filter-pattern "resilience_score"
```

## Troubleshooting

### Common Issues

1. **Assessment Not Starting**:
   - Verify application is properly registered in Resilience Hub
   - Check IAM permissions for Resilience Hub service role
   - Ensure application components are correctly identified

2. **EventBridge Events Not Triggering**:
   - Verify EventBridge rule is enabled
   - Check Lambda function permissions
   - Review event pattern matching

3. **Lambda Function Errors**:
   - Check CloudWatch logs for error details
   - Verify IAM permissions for CloudWatch metrics
   - Ensure SNS topic exists and is accessible

4. **Missing Metrics**:
   - Verify Lambda function is processing events
   - Check CloudWatch namespace spelling
   - Ensure metrics are being published with correct dimensions

### Debug Commands

```bash
# Check Resilience Hub service status
aws resiliencehub list-apps

# Verify EventBridge rule configuration
aws events describe-rule --name "ResilienceHubAssessmentRule"

# Test Lambda function manually
aws lambda invoke \
    --function-name resilience-processor-* \
    --payload '{"test": "event"}' \
    response.json

# Check CloudWatch alarm states
aws cloudwatch describe-alarms \
    --alarm-names "Critical-Low-Resilience-Score"
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name resilience-monitoring-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name resilience-monitoring-stack
```

### Using CDK

```bash
# TypeScript
cd cdk-typescript/
cdk destroy

# Python
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
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Prompt for confirmation
# 2. Delete resources in proper order
# 3. Handle dependencies and wait times
# 4. Clean up local files
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually remove resources in this order:

1. CloudWatch alarms and dashboard
2. EventBridge rule and targets
3. Lambda function
4. SNS topic
5. Resilience Hub application and policy
6. EC2 instances and RDS databases
7. VPC and networking components
8. IAM roles and policies

## Security Considerations

### IAM Permissions

The solution creates IAM roles with least privilege access:

- **ResilienceAutomationRole**: Used by Lambda and Systems Manager
- **Instance Profile**: For EC2 instances to use Systems Manager

### Network Security

- VPC with public and private subnets
- Security groups with minimal required access
- RDS in private subnets only
- Encrypted RDS storage

### Data Protection

- RDS encryption at rest enabled
- CloudWatch logs encrypted
- SNS topics use server-side encryption
- No hardcoded credentials in code

## Extension Ideas

1. **Multi-Account Support**: Extend to monitor applications across multiple AWS accounts using Organizations
2. **Custom Remediation**: Add custom Systems Manager automation documents for specific remediation actions
3. **Integration with AWS FIS**: Automate chaos engineering experiments based on resilience assessments
4. **Cost-Aware Optimization**: Balance resilience improvements with cost considerations using Cost Explorer APIs
5. **Cross-Region Monitoring**: Monitor and coordinate resilience across multiple AWS regions

## Support

### Documentation References

- [AWS Resilience Hub User Guide](https://docs.aws.amazon.com/resilience-hub/latest/userguide/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [AWS Systems Manager User Guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/)
- [Amazon CloudWatch User Guide](https://docs.aws.amazon.com/cloudwatch/latest/monitoring/)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult AWS service documentation
4. Check AWS Support resources

### Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow AWS best practices
3. Update documentation as needed
4. Validate against the original recipe requirements

---

**Note**: This infrastructure code implements the complete solution described in the "Monitoring Application Resilience with AWS Resilience Hub and EventBridge" recipe. For detailed explanations of the architecture and implementation approach, refer to the original recipe documentation.