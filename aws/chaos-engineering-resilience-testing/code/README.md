# Infrastructure as Code for Automated Chaos Engineering with Fault Injection Service

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Chaos Engineering with Fault Injection Service".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This infrastructure deploys a complete chaos engineering testing framework that includes:

- AWS Fault Injection Service (FIS) experiment templates
- EventBridge rules for experiment scheduling and notifications
- CloudWatch alarms for safety stop conditions
- SNS topics for notifications and alerting
- IAM roles with appropriate permissions
- CloudWatch dashboard for monitoring

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - IAM role creation and management
  - AWS FIS experiment template creation
  - EventBridge rule creation
  - CloudWatch alarm and dashboard creation
  - SNS topic creation and management
- Target resources tagged with `ChaosReady: true` for safe experimentation
- Valid email address for SNS notifications

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name chaos-engineering-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name chaos-engineering-stack \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name chaos-engineering-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure email for notifications
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy ChaosEngineeringStack

# View outputs
cdk ls
```

### Using CDK Python
```bash
cd cdk-python/

# Set up virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure email for notifications
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy ChaosEngineeringStack

# View outputs
cdk ls
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
notification_email = "your-email@example.com"
experiment_name = "my-chaos-experiment"
aws_region = "us-east-1"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL=your-email@example.com
export AWS_REGION=us-east-1

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
echo "Check your email to confirm SNS subscription"
```

## Configuration Options

### CloudFormation Parameters

- `NotificationEmail`: Email address for experiment notifications (required)
- `ExperimentName`: Name prefix for experiment resources (default: chaos-experiment)
- `Environment`: Environment tag for resources (default: Testing)

### CDK Environment Variables

- `NOTIFICATION_EMAIL`: Email address for experiment notifications (required)
- `CDK_DEFAULT_ACCOUNT`: AWS account ID (auto-detected)
- `CDK_DEFAULT_REGION`: AWS region (auto-detected)

### Terraform Variables

- `notification_email`: Email address for experiment notifications (required)
- `experiment_name`: Name prefix for experiment resources (default: chaos-experiment)
- `aws_region`: AWS region for deployment (default: us-east-1)
- `environment`: Environment tag for resources (default: Testing)

## Post-Deployment Steps

1. **Confirm SNS Subscription**: Check your email and confirm the SNS subscription
2. **Tag Target Resources**: Ensure EC2 instances have the `ChaosReady: true` tag
3. **Validate Permissions**: Verify FIS has permissions to access target resources
4. **Test Stop Conditions**: Confirm CloudWatch alarms are properly configured

## Running Your First Experiment

After deployment, you can run a chaos experiment:

```bash
# Get the experiment template ID from outputs
TEMPLATE_ID=$(aws cloudformation describe-stacks \
    --stack-name chaos-engineering-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ExperimentTemplateId`].OutputValue' \
    --output text)

# Start an experiment
EXPERIMENT_ID=$(aws fis start-experiment \
    --experiment-template-id $TEMPLATE_ID \
    --query experiment.id --output text)

# Monitor experiment progress
aws fis get-experiment --id $EXPERIMENT_ID
```

## Monitoring and Observability

### CloudWatch Dashboard

Access the generated CloudWatch dashboard to monitor:
- FIS experiment status and metrics
- Application health during experiments
- Target resource performance

### EventBridge Integration

The deployment creates EventBridge rules that:
- Capture FIS experiment state changes
- Send notifications via SNS
- Enable automated responses to experiment events

### Stop Conditions

CloudWatch alarms serve as safety mechanisms:
- High error rate alarm (>50 4XX errors in 2 minutes)
- High CPU utilization alarm (>90% average over 5 minutes)

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name chaos-engineering-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name chaos-engineering-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# Destroy the stack
cdk destroy ChaosEngineeringStack

# Confirm destruction
cdk ls
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
echo "All resources have been removed"
```

## Security Considerations

### IAM Permissions

The infrastructure creates IAM roles with least-privilege permissions:
- FIS execution role: Limited to experiment actions on tagged resources
- EventBridge role: SNS publish permissions only
- Scheduler role: FIS experiment start permissions only

### Resource Targeting

Experiments only target resources with the `ChaosReady: true` tag, providing an additional safety layer.

### Stop Conditions

CloudWatch alarms automatically halt experiments when safety thresholds are breached.

## Troubleshooting

### Common Issues

1. **SNS Subscription Not Confirmed**
   - Check your email spam folder
   - Manually confirm subscription in AWS Console

2. **No Target Resources Found**
   - Ensure EC2 instances have `ChaosReady: true` tag
   - Verify FIS role has permissions to describe EC2 instances

3. **Experiment Fails to Start**
   - Check FIS role permissions
   - Verify stop condition alarms exist
   - Ensure target resources are running

4. **Stop Conditions Not Triggering**
   - Verify CloudWatch alarm configuration
   - Check alarm state and history
   - Review metric data availability

### Debugging Commands

```bash
# Check FIS experiment status
aws fis list-experiments --query 'experiments[0]'

# Review CloudWatch alarm states
aws cloudwatch describe-alarms --alarm-names "FIS-HighErrorRate-*"

# Check EventBridge rule targets
aws events list-targets-by-rule --rule "FIS-ExperimentStateChanges-*"

# Verify SNS topic subscriptions
aws sns list-subscriptions-by-topic --topic-arn "arn:aws:sns:*:*:fis-alerts-*"
```

## Cost Optimization

### Resource Costs

- **AWS FIS**: $0.10 per action-minute
- **EventBridge**: $1.00 per million events
- **CloudWatch**: Standard alarm and dashboard pricing
- **SNS**: $0.50 per million notifications

### Cost Control

- Experiments only run when scheduled or manually triggered
- Stop conditions prevent runaway experiments
- Resources are tagged for cost allocation

## Best Practices

### Experiment Design

1. Start with read-only experiments before introducing destructive actions
2. Use gradual fault injection intensity
3. Run experiments during low-traffic periods initially
4. Maintain detailed experiment documentation

### Safety Measures

1. Always define appropriate stop conditions
2. Test stop conditions before production experiments
3. Monitor experiment impact in real-time
4. Have rollback procedures ready

### Automation

1. Schedule experiments during maintenance windows
2. Automate experiment result analysis
3. Integrate with incident response procedures
4. Use progressive automation as confidence grows

## Extension Ideas

1. **Multi-Region Experiments**: Extend templates for cross-region chaos testing
2. **Custom Actions**: Develop application-specific fault injection actions
3. **Automated Analysis**: Integrate with Amazon Bedrock for result analysis
4. **Game Day Automation**: Combine multiple experiment templates for comprehensive testing

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS FIS documentation: https://docs.aws.amazon.com/fis/
3. Consult AWS EventBridge documentation: https://docs.aws.amazon.com/eventbridge/
4. Review CloudFormation/CDK/Terraform provider documentation

## Contributing

When modifying this infrastructure:
1. Test changes in a development environment
2. Validate all IaC templates syntax
3. Update this README with any new requirements
4. Follow AWS security best practices