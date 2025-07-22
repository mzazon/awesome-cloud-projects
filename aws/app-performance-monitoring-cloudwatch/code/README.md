# Infrastructure as Code for Application Performance Monitoring Automation

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Application Performance Monitoring Automation".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured (minimum version 2.0)
- Appropriate AWS permissions for CloudWatch, EventBridge, Lambda, SNS, and IAM services
- An existing application running on AWS (EKS, EC2, or Lambda functions) for monitoring
- Basic knowledge of AWS monitoring services and event-driven architectures
- Estimated cost: $20-50/month for moderate monitoring workload (varies based on metrics volume and notification frequency)

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the monitoring infrastructure
aws cloudformation create-stack \
    --stack-name app-performance-monitoring \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stack-events \
    --stack-name app-performance-monitoring

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name app-performance-monitoring \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Review what will be deployed
cdk diff

# Deploy the monitoring infrastructure
cdk deploy --parameters NotificationEmail=your-email@example.com

# View outputs
cdk ls
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Review what will be deployed
cdk diff

# Deploy the monitoring infrastructure
cdk deploy --parameters NotificationEmail=your-email@example.com

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
aws_region = "us-west-2"
notification_email = "your-email@example.com"
application_name = "MyApplication"
environment = "production"
EOF

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export AWS_REGION=us-west-2
export NOTIFICATION_EMAIL=your-email@example.com
export APPLICATION_NAME=MyApplication

# Deploy the monitoring infrastructure
./scripts/deploy.sh

# Check deployment status
aws cloudwatch list-dashboards --query 'DashboardEntries[?contains(DashboardName, `ApplicationPerformanceMonitoring`)]'
```

## Configuration Options

### CloudFormation Parameters

- `NotificationEmail`: Email address for performance alerts (required)
- `ApplicationName`: Name of the application being monitored (default: MyApplication)
- `LatencyThreshold`: Maximum acceptable latency in milliseconds (default: 2000)
- `ErrorRateThreshold`: Maximum acceptable error rate percentage (default: 5)
- `ThroughputThreshold`: Minimum expected throughput per 5 minutes (default: 10)

### CDK Parameters

Both TypeScript and Python CDK implementations support the same parameters as CloudFormation through context variables:

```bash
# Using CDK context
cdk deploy \
    --context notificationEmail=your-email@example.com \
    --context applicationName=MyApplication \
    --context latencyThreshold=2000
```

### Terraform Variables

Key variables in `terraform.tfvars`:

```hcl
aws_region          = "us-west-2"
notification_email  = "your-email@example.com"
application_name    = "MyApplication"
environment         = "production"
latency_threshold   = 2000
error_rate_threshold = 5
throughput_threshold = 10

# Optional tags
tags = {
  Environment = "production"
  Owner       = "platform-team"
  Project     = "monitoring"
}
```

## Architecture Components

This IaC deployment creates the following AWS resources:

- **CloudWatch Application Signals**: Automatic application instrumentation and metrics collection
- **CloudWatch Alarms**: Monitor latency, error rates, and throughput thresholds
- **EventBridge Rules**: Route CloudWatch alarm state changes to processing functions
- **Lambda Function**: Intelligent event processing and automated remediation
- **SNS Topic**: Multi-channel notification delivery
- **CloudWatch Dashboard**: Real-time performance monitoring visualization
- **IAM Roles and Policies**: Secure permissions following least privilege principle

## Post-Deployment Configuration

### 1. Confirm Email Subscription

After deployment, you'll receive an email subscription confirmation. Click the confirmation link to receive alerts.

### 2. Verify Application Signals

```bash
# Check if Application Signals is collecting metrics
aws cloudwatch list-metrics \
    --namespace AWS/ApplicationSignals \
    --query 'Metrics[?MetricName==`Latency`]'
```

### 3. Access the Dashboard

Navigate to the CloudWatch console and find your dashboard named `ApplicationPerformanceMonitoring-{suffix}` to view real-time metrics.

### 4. Test Alarm Functionality

```bash
# Get the alarm name from outputs
ALARM_NAME=$(aws cloudformation describe-stacks \
    --stack-name app-performance-monitoring \
    --query 'Stacks[0].Outputs[?OutputKey==`HighLatencyAlarmName`].OutputValue' \
    --output text)

# Test alarm by setting it to ALARM state
aws cloudwatch set-alarm-state \
    --alarm-name $ALARM_NAME \
    --state-value ALARM \
    --state-reason "Manual test of monitoring system"
```

## Monitoring and Maintenance

### Health Checks

```bash
# Check EventBridge rule status
aws events describe-rule --name performance-anomaly-rule-*

# Check Lambda function health
aws lambda get-function --function-name performance-processor-*

# View recent Lambda invocations
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/performance-processor
```

### Updating Thresholds

To modify alarm thresholds after deployment, update the parameters and redeploy:

```bash
# CloudFormation
aws cloudformation update-stack \
    --stack-name app-performance-monitoring \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=LatencyThreshold,ParameterValue=3000 \
    --capabilities CAPABILITY_IAM

# Terraform
terraform apply -var="latency_threshold=3000"
```

## Troubleshooting

### Common Issues

1. **Application Signals not showing data**:
   - Ensure your application is properly instrumented
   - Verify the application is running and receiving traffic
   - Check that Application Signals is enabled in your AWS region

2. **Lambda function not processing events**:
   - Check EventBridge rule is enabled and properly configured
   - Verify Lambda function has correct IAM permissions
   - Review Lambda function logs in CloudWatch Logs

3. **Notifications not received**:
   - Confirm email subscription in SNS
   - Check SNS topic has correct permissions
   - Verify alarm actions are properly configured

### Debug Commands

```bash
# Check Lambda function logs
aws logs tail /aws/lambda/performance-processor-* --follow

# Verify EventBridge rule targets
aws events list-targets-by-rule --rule performance-anomaly-rule-*

# Check alarm history
aws cloudwatch describe-alarm-history --alarm-name AppSignals-HighLatency-*
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name app-performance-monitoring

# Monitor deletion progress
aws cloudformation describe-stack-events \
    --stack-name app-performance-monitoring
```

### Using CDK (AWS)

```bash
# TypeScript
cd cdk-typescript/
cdk destroy

# Python
cd cdk-python/
source .venv/bin/activate
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify all resources are deleted
aws cloudwatch list-dashboards --query 'DashboardEntries[?contains(DashboardName, `ApplicationPerformanceMonitoring`)]'
```

## Security Considerations

- All IAM roles follow the principle of least privilege
- Lambda function has minimal required permissions
- SNS topic access is restricted to the monitoring system
- CloudWatch data is encrypted at rest by default
- EventBridge rules use service-specific event patterns

## Cost Optimization

- Application Signals pricing is based on metrics ingested
- Lambda function uses ARM-based architecture for cost efficiency
- CloudWatch dashboard refresh rates are optimized for cost
- SNS notifications are batched to minimize charges
- Consider adjusting alarm evaluation periods to reduce alarm evaluations

## Support

For issues with this infrastructure code, refer to the original recipe documentation or consult the AWS documentation:

- [AWS CloudWatch Application Signals Documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Application-Monitoring-Sections.html)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)