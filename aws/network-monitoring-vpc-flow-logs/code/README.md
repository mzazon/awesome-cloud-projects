# Infrastructure as Code for Monitoring Network Traffic with VPC Flow Logs

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Monitoring Network Traffic with VPC Flow Logs".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for VPC, CloudWatch, S3, Athena, Lambda, IAM, and SNS
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.9+ (Python)
- For Terraform: Terraform v1.0+
- Estimated cost: $20-50/month for moderate traffic volumes

> **Note**: VPC Flow Logs incur charges for data ingestion to CloudWatch Logs and S3 storage. Monitor your usage to avoid unexpected costs.

## Architecture Overview

This solution implements comprehensive network monitoring using:

- **VPC Flow Logs**: Capture network traffic metadata with dual destinations
- **CloudWatch Logs**: Real-time ingestion and metric filtering
- **S3**: Cost-effective long-term storage with lifecycle policies
- **Athena**: Serverless analytics for historical data analysis
- **Lambda**: Advanced anomaly detection and custom analysis
- **CloudWatch Alarms**: Automated alerting for security events
- **SNS**: Multi-channel notification delivery

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name network-monitoring-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name network-monitoring-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Deploy the stack
cdk deploy \
    --parameters notificationEmail=your-email@example.com

# View outputs
cdk output
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment and install dependencies
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Deploy the stack
cdk deploy \
    --parameters notificationEmail=your-email@example.com

# View outputs
cdk output
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="notification_email=your-email@example.com"

# Apply the configuration
terraform apply \
    -var="notification_email=your-email@example.com"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set required environment variables
export NOTIFICATION_EMAIL="your-email@example.com"
export AWS_REGION="us-east-1"

# Make scripts executable and deploy
chmod +x scripts/deploy.sh
./scripts/deploy.sh

# Monitor deployment progress
tail -f deployment.log
```

## Post-Deployment Configuration

1. **Confirm SNS Subscription**: Check your email and confirm the SNS topic subscription
2. **Wait for Data**: VPC Flow Logs take 5-10 minutes to start appearing in CloudWatch and S3
3. **View Dashboard**: Access the CloudWatch dashboard named "VPC-Flow-Logs-Monitoring"
4. **Test Alarms**: Verify alarm notifications are working correctly

## Validation & Testing

### Verify Flow Logs Status

```bash
# List active flow logs
aws ec2 describe-flow-logs \
    --query 'FlowLogs[?FlowLogStatus==`ACTIVE`]'

# Check CloudWatch log streams
aws logs describe-log-streams \
    --log-group-name "/aws/vpc/flowlogs" \
    --order-by LastEventTime \
    --descending
```

### Test S3 Data Storage

```bash
# List S3 objects (replace with your bucket name)
aws s3 ls s3://vpc-flow-logs-ACCOUNT-SUFFIX/vpc-flow-logs/ --recursive
```

### Query Data with Athena

```bash
# Start a sample query
aws athena start-query-execution \
    --query-string "SELECT COUNT(*) FROM vpc_flow_logs WHERE action='REJECT'" \
    --work-group "vpc-flow-logs-workgroup"
```

### Test Alarm Notifications

```bash
# Trigger a test alarm
aws cloudwatch set-alarm-state \
    --alarm-name "VPC-High-Rejected-Connections" \
    --state-value ALARM \
    --state-reason "Testing alarm notification"
```

## Customization

### Key Configuration Options

- **VPC Selection**: Modify the VPC ID to monitor different VPCs
- **Flow Log Format**: Customize the log format to include additional fields
- **Retention Policies**: Adjust CloudWatch Logs and S3 lifecycle policies
- **Alarm Thresholds**: Tune CloudWatch alarm thresholds for your environment
- **Lambda Logic**: Enhance anomaly detection algorithms

### Environment-Specific Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `notification_email` | Email address for security alerts | N/A | Yes |
| `vpc_id` | VPC to monitor (auto-detected if not specified) | Default VPC | No |
| `log_retention_days` | CloudWatch Logs retention period | 30 | No |
| `alarm_threshold_rejected` | Rejected connections alarm threshold | 50 | No |
| `alarm_threshold_data_transfer` | High data transfer alarm threshold | 10 | No |
| `alarm_threshold_external` | External connections alarm threshold | 100 | No |

### Advanced Configuration

For production environments, consider:

1. **Multi-VPC Monitoring**: Deploy across multiple VPCs and regions
2. **Enhanced Security**: Enable S3 encryption and VPC endpoints
3. **Cost Optimization**: Implement intelligent flow log sampling
4. **Integration**: Connect with SIEM tools and security platforms
5. **Machine Learning**: Add anomaly detection using Amazon SageMaker

## Monitoring and Maintenance

### CloudWatch Dashboard

Access the "VPC-Flow-Logs-Monitoring" dashboard for:
- Real-time security metrics visualization
- Rejected connections trends
- Data transfer patterns
- External connection monitoring

### Log Analysis

Use CloudWatch Logs Insights for advanced queries:

```sql
fields @timestamp, @message
| filter @message like /REJECT/
| stats count() by bin(5m)
| sort @timestamp desc
```

### Cost Optimization

Monitor costs through:
- CloudWatch billing alerts
- S3 storage class transitions
- Athena query optimization
- Flow log filtering and sampling

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name network-monitoring-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name network-monitoring-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# From the CDK directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Make cleanup script executable and run
chmod +x scripts/destroy.sh
./scripts/destroy.sh

# Monitor cleanup progress
tail -f cleanup.log
```

## Troubleshooting

### Common Issues

1. **Flow Logs Not Appearing**: 
   - Wait 5-10 minutes for initial data
   - Check IAM role permissions
   - Verify VPC Flow Logs are active

2. **Athena Query Failures**:
   - Ensure S3 bucket permissions are correct
   - Verify table partitions are created
   - Check Athena workgroup configuration

3. **Alarm False Positives**:
   - Adjust alarm thresholds based on baseline traffic
   - Increase evaluation periods for stability
   - Review metric filter patterns

4. **High Costs**:
   - Review CloudWatch Logs retention settings
   - Implement S3 lifecycle policies
   - Consider flow log sampling for high-traffic environments

### Debug Commands

```bash
# Check IAM role trust relationship
aws iam get-role --role-name VPCFlowLogsRole-SUFFIX

# Verify S3 bucket policy
aws s3api get-bucket-policy --bucket vpc-flow-logs-ACCOUNT-SUFFIX

# Test CloudWatch metric filters
aws logs describe-metric-filters --log-group-name "/aws/vpc/flowlogs"

# Check Athena query history
aws athena list-query-executions --work-group "vpc-flow-logs-workgroup"
```

## Security Considerations

- All resources use least-privilege IAM policies
- S3 bucket blocks public access by default
- CloudWatch Logs are encrypted in transit and at rest
- SNS topics support encryption for sensitive alerts
- Lambda functions run with minimal required permissions

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS service-specific documentation
3. Verify IAM permissions and resource configurations
4. Monitor CloudWatch metrics and logs for error patterns

## Related Resources

- [AWS VPC Flow Logs Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html)
- [CloudWatch Logs User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/)
- [Amazon Athena User Guide](https://docs.aws.amazon.com/athena/latest/ug/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)