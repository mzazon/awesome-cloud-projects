# Infrastructure as Code for Orchestrating Media Workflows with MediaConnect and Step Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Orchestrating Media Workflows with MediaConnect and Step Functions".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys an automated media workflow that includes:

- **AWS Elemental MediaConnect Flow**: Reliable video transport with redundant outputs
- **AWS Step Functions**: Orchestrates monitoring and alerting workflows
- **Lambda Functions**: Stream health monitoring and alert handling
- **CloudWatch**: Metrics collection, alarms, and dashboard visualization
- **SNS**: Real-time notifications for stream quality issues
- **EventBridge**: Event-driven workflow triggers
- **IAM Roles**: Secure service-to-service communication

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - MediaConnect (full access)
  - Step Functions (full access)
  - Lambda (full access)
  - CloudWatch (full access)
  - SNS (full access)
  - EventBridge (full access)
  - IAM (role creation and policy management)
  - S3 (bucket creation for Lambda code)
- For CDK deployments: Node.js 16+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+
- Live video source capable of streaming via RTP, Zixi, or SRT protocols

## Estimated Costs

- **MediaConnect Flow**: ~$20-40/month (varies by data transfer)
- **Lambda Executions**: ~$1-5/month (based on monitoring frequency)
- **Step Functions**: ~$1-3/month (Express workflows)
- **CloudWatch**: ~$5-15/month (metrics, alarms, dashboard)
- **SNS**: ~$1-3/month (notification delivery)
- **Total Estimated**: $30-70/month per monitored stream

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name media-workflow-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
                 ParameterKey=SourceWhitelistCidr,ParameterValue=0.0.0.0/0 \
                 ParameterKey=PrimaryOutputDestination,ParameterValue=10.0.0.100 \
                 ParameterKey=BackupOutputDestination,ParameterValue=10.0.0.101 \
    --capabilities CAPABILITY_IAM

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name media-workflow-stack

# Get the MediaConnect ingest endpoint
aws cloudformation describe-stacks \
    --stack-name media-workflow-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`MediaConnectIngestEndpoint`].OutputValue' \
    --output text
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set required context variables
npx cdk context --set notificationEmail=your-email@example.com
npx cdk context --set sourceWhitelistCidr=0.0.0.0/0
npx cdk context --set primaryOutputDestination=10.0.0.100
npx cdk context --set backupOutputDestination=10.0.0.101

# Deploy the stack
npx cdk deploy

# View outputs
npx cdk deploy --outputs-file outputs.json
```

### Using CDK Python
```bash
cd cdk-python/

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export NOTIFICATION_EMAIL=your-email@example.com
export SOURCE_WHITELIST_CIDR=0.0.0.0/0
export PRIMARY_OUTPUT_DESTINATION=10.0.0.100
export BACKUP_OUTPUT_DESTINATION=10.0.0.101

# Deploy the stack
cdk deploy

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
notification_email = "your-email@example.com"
source_whitelist_cidr = "0.0.0.0/0"
primary_output_destination = "10.0.0.100"
backup_output_destination = "10.0.0.101"
aws_region = "us-east-1"
EOF

# Plan the deployment
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

# Set required environment variables
export NOTIFICATION_EMAIL=your-email@example.com
export SOURCE_WHITELIST_CIDR=0.0.0.0/0
export PRIMARY_OUTPUT_DESTINATION=10.0.0.100
export BACKUP_OUTPUT_DESTINATION=10.0.0.101

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output the MediaConnect ingest endpoint
```

## Configuration Options

### Key Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `notification_email` | Email address for stream quality alerts | - | Yes |
| `source_whitelist_cidr` | CIDR block for source IP whitelist | `0.0.0.0/0` | Yes |
| `primary_output_destination` | IP address for primary stream output | `10.0.0.100` | Yes |
| `backup_output_destination` | IP address for backup stream output | `10.0.0.101` | Yes |
| `packet_loss_threshold` | Maximum acceptable packet loss (%) | `0.1` | No |
| `jitter_threshold` | Maximum acceptable jitter (ms) | `50` | No |
| `monitoring_frequency` | CloudWatch alarm evaluation period (seconds) | `300` | No |

### Security Considerations

- **Source IP Restriction**: Update `source_whitelist_cidr` to restrict access to your specific encoder IPs
- **Output Destinations**: Ensure output destination IPs are within your secure network
- **IAM Permissions**: All roles follow least-privilege principles
- **Encryption**: Consider enabling encryption for MediaConnect flows in production

## Post-Deployment Steps

### 1. Confirm SNS Subscription
After deployment, check your email and confirm the SNS subscription to receive alerts.

### 2. Configure Your Encoder
Point your video encoder to the MediaConnect ingest endpoint:
- **Protocol**: RTP, Zixi, or SRT
- **IP**: Output from deployment (MediaConnectIngestEndpoint)
- **Port**: 5000 (configurable in templates)

### 3. Monitor Stream Health
- View the CloudWatch dashboard for real-time metrics
- Test the alerting by temporarily stopping your stream
- Verify Step Functions executions in the AWS console

### 4. Customize Thresholds
Adjust packet loss and jitter thresholds based on your quality requirements:

**CloudFormation**: Update parameters and redeploy
```bash
aws cloudformation update-stack \
    --stack-name media-workflow-stack \
    --use-previous-template \
    --parameters ParameterKey=PacketLossThreshold,ParameterValue=0.05
```

**Terraform**: Update `terraform.tfvars` and apply
```bash
terraform apply -var="packet_loss_threshold=0.05"
```

## Monitoring and Troubleshooting

### CloudWatch Resources Created
- **Alarms**: Packet loss, jitter, and workflow triggers
- **Dashboard**: Real-time stream health visualization
- **Log Groups**: Lambda function execution logs

### Common Issues

1. **Stream Not Connecting**
   - Verify source IP is within whitelist CIDR
   - Check encoder configuration matches ingest endpoint
   - Review MediaConnect flow status in AWS console

2. **No Alerts Received**
   - Confirm SNS email subscription
   - Check CloudWatch alarm configurations
   - Verify Lambda function execution logs

3. **High False Positive Alerts**
   - Adjust packet loss and jitter thresholds
   - Increase alarm evaluation periods
   - Review source encoder stability

### Useful Commands

```bash
# Check MediaConnect flow status
aws mediaconnect describe-flow --flow-arn <FLOW_ARN>

# View recent Step Functions executions
aws stepfunctions list-executions --state-machine-arn <STATE_MACHINE_ARN>

# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/stream-monitor

# Test SNS topic
aws sns publish --topic-arn <SNS_TOPIC_ARN> --message "Test message"
```

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name media-workflow-stack
aws cloudformation wait stack-delete-complete --stack-name media-workflow-stack
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npx cdk destroy
```

### Using CDK Python
```bash
cd cdk-python/
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

## Customization Examples

### Adding Regional Redundancy
Extend the solution to multiple regions:

1. Deploy the infrastructure in multiple AWS regions
2. Use Route 53 health checks to monitor regional endpoints
3. Implement automatic failover between regions

### Integration with MediaLive
Connect to AWS Elemental MediaLive for transcoding:

1. Create MediaLive channels as MediaConnect outputs
2. Add transcoding profiles for multiple bitrates
3. Implement adaptive bitrate streaming

### Advanced Monitoring
Enhance monitoring capabilities:

1. Add custom CloudWatch metrics from your application
2. Implement machine learning-based anomaly detection
3. Create custom dashboards for different stakeholder groups

## Cost Optimization

- **Right-size Lambda**: Monitor execution times and adjust memory allocation
- **Optimize Flow Hours**: Stop MediaConnect flows when not actively streaming
- **SNS Filtering**: Use message filtering to reduce notification costs
- **CloudWatch Retention**: Set appropriate log retention periods

## Support and Documentation

- [AWS Elemental MediaConnect User Guide](https://docs.aws.amazon.com/mediaconnect/latest/ug/)
- [AWS Step Functions Developer Guide](https://docs.aws.amazon.com/step-functions/latest/dg/)
- [CloudFormation MediaConnect Resource Reference](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/AWS_MediaConnect.html)
- [Original Recipe Documentation](../orchestrating-real-time-media-workflows-with-aws-elemental-mediaconnect-and-step-functions.md)

For infrastructure-specific issues, consult the relevant tool documentation or AWS support channels.