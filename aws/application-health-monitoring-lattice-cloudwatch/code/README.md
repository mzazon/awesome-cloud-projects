# Infrastructure as Code for Application Health Monitoring with VPC Lattice and CloudWatch

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Application Health Monitoring with VPC Lattice and CloudWatch".

## Overview

This solution creates an automated application health monitoring system using VPC Lattice service metrics, CloudWatch alarms, and Lambda functions to detect unhealthy services and trigger auto-remediation workflows. The infrastructure includes VPC Lattice service networks, target groups, CloudWatch monitoring, SNS notifications, and Lambda-based remediation functions.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

The infrastructure creates the following resources:

- **VPC Lattice Service Network**: Logical boundary for service-to-service communication
- **VPC Lattice Service**: Entry point for client requests with HTTP listener
- **Target Group**: Backend service configuration with health checks
- **CloudWatch Alarms**: Monitor 5XX errors, timeouts, and response times
- **Lambda Function**: Auto-remediation logic for health issues
- **SNS Topic**: Notification system for alerts and remediation
- **CloudWatch Dashboard**: Real-time monitoring visualization
- **IAM Roles and Policies**: Secure access controls

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - VPC Lattice (create service networks, services, target groups)
  - CloudWatch (create alarms, dashboards, metrics)
  - Lambda (create functions, manage execution roles)
  - SNS (create topics, manage subscriptions)
  - IAM (create roles and policies)
- Existing VPC with at least two subnets in different Availability Zones
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

## Cost Estimation

Expected monthly costs for this monitoring infrastructure:

- VPC Lattice Service Network: ~$5-10
- CloudWatch Alarms (3 alarms): ~$3
- Lambda Function: <$1 (with typical monitoring load)
- SNS Topic: <$1
- CloudWatch Dashboard: ~$3
- Total estimated cost: **$12-18/month**

> **Note**: Costs may vary based on traffic volume and alarm evaluation frequency.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name health-monitoring-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=VpcId,ParameterValue=vpc-xxxxxxxx \
                 ParameterKey=SubnetIds,ParameterValue="subnet-xxxxxxxx,subnet-yyyyyyyy" \
                 ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name health-monitoring-stack \
    --query "Stacks[0].StackStatus"

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name health-monitoring-stack \
    --query "Stacks[0].Outputs"
```

### Using CDK TypeScript

```bash
# Install dependencies
cd cdk-typescript/
npm install

# Configure environment
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk deploy \
    --parameters VpcId=vpc-xxxxxxxx \
    --parameters SubnetIds=subnet-xxxxxxxx,subnet-yyyyyyyy \
    --parameters NotificationEmail=your-email@example.com

# View deployment outputs
cdk output
```

### Using CDK Python

```bash
# Set up Python environment
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Configure environment
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk deploy \
    --parameters VpcId=vpc-xxxxxxxx \
    --parameters SubnetIds=subnet-xxxxxxxx,subnet-yyyyyyyy \
    --parameters NotificationEmail=your-email@example.com

# View deployment outputs
cdk output
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the deployment plan
terraform plan \
    -var="vpc_id=vpc-xxxxxxxx" \
    -var="subnet_ids=[\"subnet-xxxxxxxx\",\"subnet-yyyyyyyy\"]" \
    -var="notification_email=your-email@example.com"

# Deploy the infrastructure
terraform apply \
    -var="vpc_id=vpc-xxxxxxxx" \
    -var="subnet_ids=[\"subnet-xxxxxxxx\",\"subnet-yyyyyyyy\"]" \
    -var="notification_email=your-email@example.com"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Configure environment variables
export VPC_ID=vpc-xxxxxxxx
export SUBNET_IDS="subnet-xxxxxxxx subnet-yyyyyyyy"
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/deploy.sh --status
```

## Configuration Parameters

### Required Parameters

- **VpcId**: The VPC ID where VPC Lattice resources will be created
- **SubnetIds**: List of subnet IDs for target group configuration (minimum 2 subnets)
- **NotificationEmail**: Email address for health alert notifications

### Optional Parameters

- **EnvironmentName**: Environment identifier (default: "demo")
- **ErrorRateThreshold**: Threshold for 5XX error rate alarm (default: 10)
- **TimeoutThreshold**: Threshold for timeout alarm (default: 5)
- **ResponseTimeThreshold**: Response time threshold in milliseconds (default: 2000)
- **HealthCheckPath**: Path for target group health checks (default: "/health")
- **AlarmEvaluationPeriods**: Number of periods for alarm evaluation (default: 2)

## Post-Deployment Configuration

### 1. Confirm SNS Subscription

After deployment, check your email for an SNS subscription confirmation:

```bash
# List SNS subscriptions
aws sns list-subscriptions-by-topic \
    --topic-arn $(terraform output -raw sns_topic_arn)
```

### 2. Register Targets

Add EC2 instances or other targets to the target group:

```bash
# Example: Register EC2 instance
aws vpc-lattice register-targets \
    --target-group-identifier $(terraform output -raw target_group_id) \
    --targets "Id=i-1234567890abcdef0,Port=80"
```

### 3. Access CloudWatch Dashboard

Navigate to the CloudWatch console to view the monitoring dashboard:

```bash
echo "Dashboard URL: https://$(aws configure get region).console.aws.amazon.com/cloudwatch/home?region=$(aws configure get region)#dashboards:name=$(terraform output -raw dashboard_name)"
```

## Validation and Testing

### 1. Verify VPC Lattice Configuration

```bash
# Check service network status
aws vpc-lattice get-service-network \
    --service-network-identifier $(terraform output -raw service_network_id)

# Verify service configuration
aws vpc-lattice get-service \
    --service-identifier $(terraform output -raw service_id)
```

### 2. Test CloudWatch Alarms

```bash
# List created alarms
aws cloudwatch describe-alarms \
    --alarm-name-prefix "VPCLattice-"

# Test alarm by publishing custom metric
aws cloudwatch put-metric-data \
    --namespace "AWS/VpcLattice" \
    --metric-data MetricName=HTTPCode_5XX_Count,Value=15,Unit=Count,Dimensions=[{Name=Service,Value=$(terraform output -raw service_id)}]
```

### 3. Test Lambda Function

```bash
# Invoke Lambda function manually
aws lambda invoke \
    --function-name $(terraform output -raw lambda_function_name) \
    --payload '{"Records":[{"Sns":{"Message":"{\"AlarmName\":\"Test-Alarm\",\"NewStateValue\":\"ALARM\"}"}}]}' \
    response.json

# Check response
cat response.json
```

### 4. Verify SNS Notifications

```bash
# Send test notification
aws sns publish \
    --topic-arn $(terraform output -raw sns_topic_arn) \
    --subject "Health Monitoring Test" \
    --message "Testing health monitoring system"
```

## Monitoring and Operations

### Key Metrics to Monitor

1. **HTTP Error Rates**: 5XX responses indicating server errors
2. **Request Timeouts**: Requests exceeding configured timeout thresholds
3. **Response Times**: Average request processing times
4. **Target Health**: Number of healthy vs unhealthy targets

### Alarm Thresholds

- **5XX Error Rate**: >10 errors in 5 minutes (2 evaluation periods)
- **Request Timeouts**: >5 timeouts in 5 minutes (2 evaluation periods)
- **Response Time**: >2000ms average over 15 minutes (3 evaluation periods)

### Auto-Remediation Actions

The Lambda function implements these remediation patterns:

1. **Error Rate Issues**: Investigate unhealthy targets and trigger replacement
2. **Timeout Issues**: Check target capacity and scaling requirements
3. **Performance Issues**: Analyze response times and optimize resources

## Troubleshooting

### Common Issues

1. **VPC Lattice Service Not Accessible**
   - Verify VPC associations are active
   - Check security group configurations
   - Validate target registration

2. **CloudWatch Alarms Not Triggering**
   - Ensure targets are registered and receiving traffic
   - Verify alarm thresholds are appropriate
   - Check CloudWatch logs for Lambda errors

3. **SNS Notifications Not Received**
   - Confirm email subscription is confirmed
   - Check SNS topic permissions
   - Verify Lambda has SNS publish permissions

### Debug Commands

```bash
# Check VPC Lattice metrics
aws cloudwatch get-metric-statistics \
    --namespace "AWS/VpcLattice" \
    --metric-name "TotalRequestCount" \
    --dimensions "Name=Service,Value=$(terraform output -raw service_id)" \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum

# Check Lambda logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/$(terraform output -raw lambda_function_name)"

# View recent log events
aws logs filter-log-events \
    --log-group-name "/aws/lambda/$(terraform output -raw lambda_function_name)" \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name health-monitoring-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name health-monitoring-stack \
    --query "Stacks[0].StackStatus"
```

### Using CDK

```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm deletion
cdk list
```

### Using Terraform

```bash
# Destroy infrastructure
cd terraform/
terraform destroy \
    -var="vpc_id=vpc-xxxxxxxx" \
    -var="subnet_ids=[\"subnet-xxxxxxxx\",\"subnet-yyyyyyyy\"]" \
    -var="notification_email=your-email@example.com"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm all resources are deleted
./scripts/destroy.sh --verify
```

## Customization

### Extending Auto-Remediation

To add custom remediation logic, modify the Lambda function:

1. **CloudFormation**: Update the `LambdaCode` in the template
2. **CDK**: Modify the Lambda function code in the stack
3. **Terraform**: Update the `lambda_function.py` file
4. **Bash**: Edit the Lambda deployment section

### Adding Custom Alarms

Create additional CloudWatch alarms for specific use cases:

```bash
# Example: Add custom alarm for low request volume
aws cloudwatch put-metric-alarm \
    --alarm-name "VPCLattice-LowTraffic" \
    --alarm-description "Low request volume detected" \
    --metric-name "TotalRequestCount" \
    --namespace "AWS/VpcLattice" \
    --statistic "Sum" \
    --period 900 \
    --evaluation-periods 3 \
    --threshold 10 \
    --comparison-operator "LessThanThreshold" \
    --dimensions "Name=Service,Value=$(terraform output -raw service_id)" \
    --alarm-actions $(terraform output -raw sns_topic_arn)
```

### Integration with External Systems

The SNS topic can be extended to integrate with external monitoring systems:

- **PagerDuty**: Add webhook subscription
- **Slack**: Configure Slack webhook notifications
- **JIRA**: Automatic ticket creation for critical alarms

## Security Considerations

### IAM Permissions

The infrastructure follows least privilege principles:

- Lambda execution role has minimal required permissions
- VPC Lattice uses IAM authentication for service access
- CloudWatch alarms are scoped to specific metrics and resources

### Network Security

- VPC Lattice services use IAM-based authentication
- Target groups are configured within your VPC security boundaries
- No external internet access required for monitoring functions

### Data Protection

- CloudWatch metrics are encrypted at rest
- SNS topics support encryption for message privacy
- Lambda environment variables can use KMS encryption

## Support and Documentation

- [VPC Lattice Documentation](https://docs.aws.amazon.com/vpc-lattice/)
- [CloudWatch Monitoring](https://docs.aws.amazon.com/cloudwatch/)
- [Lambda Auto-Remediation Patterns](https://docs.aws.amazon.com/lambda/latest/dg/lambda-monitoring.html)
- [Original Recipe Documentation](../application-health-monitoring-lattice-cloudwatch.md)

For issues with this infrastructure code, refer to the original recipe documentation or the AWS service documentation linked above.