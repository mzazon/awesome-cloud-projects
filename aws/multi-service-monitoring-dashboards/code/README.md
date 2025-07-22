# Infrastructure as Code for Multi-Service Monitoring Dashboards

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Service Monitoring Dashboards". This solution implements enterprise-grade monitoring dashboards that combine infrastructure metrics with custom business metrics, anomaly detection, and intelligent alerting.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

The solution deploys:

- **Lambda Functions**: Custom metrics collection for business metrics, infrastructure health, and cost monitoring
- **CloudWatch Dashboards**: Four specialized dashboards (Infrastructure, Business, Executive, Operations)
- **Anomaly Detection**: Machine learning-based anomaly detection for key metrics
- **Intelligent Alerting**: Tiered SNS topics with anomaly-based alarms
- **Scheduled Collection**: EventBridge rules for automated metric collection
- **IAM Roles**: Least privilege access for Lambda functions

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with permissions for:
  - CloudWatch (metrics, dashboards, alarms, anomaly detection)
  - Lambda (create functions, invoke permissions)
  - SNS (create topics, subscribe)
  - EventBridge (create rules, targets)
  - IAM (create roles, attach policies)
  - Cost Explorer (for cost monitoring)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.5+ (for Terraform implementation)

## Quick Start

### Using CloudFormation

```bash
# Deploy the monitoring infrastructure
aws cloudformation create-stack \
    --stack-name advanced-monitoring-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=my-monitoring \
                 ParameterKey=AlertEmail,ParameterValue=admin@example.com \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name advanced-monitoring-stack

# Get dashboard URLs
aws cloudformation describe-stacks \
    --stack-name advanced-monitoring-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`DashboardURLs`].OutputValue' \
    --output text
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Configure parameters
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk deploy --parameters projectName=my-monitoring \
           --parameters alertEmail=admin@example.com

# View dashboard URLs
cdk deploy --outputs-file outputs.json
cat outputs.json
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Set environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk deploy --parameters projectName=my-monitoring \
           --parameters alertEmail=admin@example.com

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
project_name = "my-monitoring"
alert_email = "admin@example.com"
aws_region = "us-east-1"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output dashboard_urls
terraform output sns_topic_arns
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_NAME="my-monitoring"
export ALERT_EMAIL="admin@example.com"
export AWS_REGION="us-east-1"

# Deploy the solution
./scripts/deploy.sh

# The script will output dashboard URLs and resource information
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| ProjectName | Unique project identifier | advanced-monitoring | Yes |
| AlertEmail | Email for critical alerts | - | Yes |
| MetricCollectionInterval | Business metrics collection interval (minutes) | 5 | No |
| InfraHealthCheckInterval | Infrastructure health check interval (minutes) | 10 | No |
| AnomalyDetectionBand | Anomaly detection band width (standard deviations) | 2 | No |

### CDK Configuration

Both CDK implementations support the same parameters through context variables:

```bash
# Set context variables
cdk deploy -c projectName=my-monitoring \
           -c alertEmail=admin@example.com \
           -c metricInterval=5 \
           -c healthCheckInterval=10
```

### Terraform Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| project_name | Unique project identifier | string | "advanced-monitoring" |
| alert_email | Email for critical alerts | string | - |
| aws_region | AWS region for deployment | string | "us-east-1" |
| metric_collection_interval | Business metrics collection interval | number | 5 |
| infra_health_check_interval | Infrastructure health check interval | number | 10 |
| anomaly_detection_band | Anomaly detection sensitivity | number | 2 |
| enable_cost_monitoring | Enable cost monitoring Lambda | bool | true |

## Post-Deployment Configuration

### 1. Email Subscription Confirmation

After deployment, check your email for SNS subscription confirmation messages and confirm them to receive alerts.

### 2. Dashboard Access

Access your dashboards through the AWS Console or use the URLs provided in the deployment outputs:

- **Infrastructure Dashboard**: Detailed infrastructure metrics and health scores
- **Business Dashboard**: Business KPIs and performance metrics
- **Executive Dashboard**: High-level business and technical summary
- **Operations Dashboard**: Troubleshooting and operational metrics

### 3. Customize Business Metrics

Update the business metrics Lambda function to collect your specific business KPIs:

```python
# Edit the business metrics collection logic
# Replace simulated metrics with your actual business data sources
```

### 4. Configure Alert Thresholds

Adjust alarm thresholds based on your SLAs and business requirements:

```bash
# Update alarm thresholds through AWS Console or CLI
aws cloudwatch put-metric-alarm \
    --alarm-name "custom-threshold-alarm" \
    --threshold 95 \
    --comparison-operator LessThanThreshold
```

## Monitoring and Maintenance

### Metric Collection Verification

```bash
# Check Lambda function execution
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/my-monitoring"

# View recent metrics
aws cloudwatch list-metrics \
    --namespace "Business/Metrics"
```

### Anomaly Detection Status

```bash
# Check anomaly detector status
aws cloudwatch describe-anomaly-detectors \
    --query 'AnomalyDetectors[*].{Namespace:Namespace,MetricName:MetricName,State:StateValue}'
```

### Cost Monitoring

Monitor the cost of your monitoring solution:

```bash
# View CloudWatch usage metrics
aws cloudwatch get-metric-statistics \
    --namespace "AWS/CloudWatch" \
    --metric-name "MetricCount" \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-02T00:00:00Z \
    --period 3600 \
    --statistics Sum
```

## Troubleshooting

### Common Issues

1. **Lambda Function Errors**
   ```bash
   # Check function logs
   aws logs filter-log-events \
       --log-group-name "/aws/lambda/my-monitoring-business-metrics" \
       --filter-pattern "ERROR"
   ```

2. **Missing Metrics**
   ```bash
   # Verify EventBridge rule execution
   aws events describe-rule --name "my-monitoring-business-metrics"
   ```

3. **Alarm Not Firing**
   ```bash
   # Check alarm state and history
   aws cloudwatch describe-alarms \
       --alarm-names "my-monitoring-revenue-anomaly"
   ```

### Performance Optimization

- Adjust Lambda memory allocation for better performance
- Modify metric collection intervals based on requirements
- Implement metric filtering to reduce CloudWatch costs
- Use composite metrics to reduce alarm complexity

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name advanced-monitoring-stack

# Wait for deletion to complete
aws cloudwatch wait stack-delete-complete \
    --stack-name advanced-monitoring-stack
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm destruction when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm cleanup when prompted
```

## Security Considerations

### IAM Permissions

The solution implements least privilege access:

- Lambda functions have read-only access to AWS services
- CloudWatch full access for metrics and alarms
- SNS publish permissions for alerting
- Cost Explorer read access for cost monitoring

### Data Security

- All metrics are stored in CloudWatch (encrypted at rest)
- SNS topics can be configured with server-side encryption
- Lambda functions use AWS managed keys for encryption

### Network Security

- Lambda functions run in AWS managed VPC
- No public internet access required
- All communications use AWS internal networks

## Cost Optimization

### Expected Costs

- **CloudWatch Custom Metrics**: ~$0.30 per metric per month
- **Lambda Invocations**: ~$0.20 per million invocations
- **SNS Notifications**: ~$0.50 per million notifications
- **Anomaly Detection**: ~$0.30 per metric per month

### Cost Reduction Strategies

1. **Optimize Metric Collection Frequency**
   - Reduce collection intervals for non-critical metrics
   - Use metric filters to reduce data points

2. **Implement Metric Lifecycle**
   - Archive old metrics to reduce storage costs
   - Use metric math to derive insights without storing raw data

3. **Alert Optimization**
   - Use composite alarms to reduce SNS costs
   - Implement alert suppression during maintenance windows

## Support and Documentation

### Additional Resources

- [AWS CloudWatch User Guide](https://docs.aws.amazon.com/cloudwatch/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)
- [CloudWatch Anomaly Detection](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Anomaly_Detection.html)
- [Original Recipe Documentation](../advanced-multi-service-monitoring-dashboards-custom-metrics.md)

### Getting Help

1. Check the original recipe documentation for detailed explanations
2. Review AWS service documentation for specific configuration options
3. Use AWS Support for infrastructure-related issues
4. Consult the troubleshooting section above for common problems

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Ensure you comply with your organization's policies and AWS service terms when deploying in production environments.