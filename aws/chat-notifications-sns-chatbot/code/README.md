# Infrastructure as Code for Chat Notifications with SNS and Chatbot

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Chat Notifications with SNS and Chatbot".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- AWS account with permissions for SNS, Chatbot, CloudWatch, and IAM services
- Active Slack workspace with admin permissions OR Microsoft Teams with appropriate permissions
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Basic understanding of pub/sub messaging patterns and chat platform integrations
- Estimated cost: $0.50-$2.00 per month for SNS messages and CloudWatch alarms (depends on message volume)

> **Important**: AWS Chatbot requires initial manual setup through the AWS Console to establish OAuth connections with chat platforms. The IaC implementations will create the necessary infrastructure, but you'll need to complete the chat platform integration manually.

## Architecture Overview

The deployed infrastructure includes:

- **SNS Topic**: Central messaging hub with optional KMS encryption
- **CloudWatch Alarm**: Demo alarm for testing notification delivery
- **IAM Role**: For AWS Chatbot with appropriate permissions
- **Resource Tags**: For cost allocation and resource management

## Outputs

All implementations provide these outputs:

- `SNSTopicArn`: ARN of the created SNS topic
- `SNSTopicName`: Name of the SNS topic
- `CloudWatchAlarmName`: Name of the demo alarm
- `ChatbotRoleArn`: ARN of the IAM role for Chatbot
- `ChatbotConfigurationName`: Suggested name for Chatbot configuration

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name chat-notifications-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationTopicName,ParameterValue=team-notifications \
                 ParameterKey=AlarmName,ParameterValue=demo-cpu-alarm \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name chat-notifications-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name chat-notifications-stack \
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
cdk output
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk output
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
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

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters
# and guide you through the deployment process
```

## Post-Deployment Configuration

After deploying the infrastructure with any method above, you'll need to complete the AWS Chatbot setup manually:

### Slack Integration

1. Navigate to the AWS Chatbot Console: https://console.aws.amazon.com/chatbot/
2. Choose "Slack" as your chat client
3. Click "Configure" and authorize AWS Chatbot in your Slack workspace
4. Select your Slack workspace from the dropdown
5. Click "Allow" to grant permissions
6. Configure a new channel:
   - Configuration name: Use the ChatbotConfigurationName from your deployment outputs
   - Slack channel: Choose your target channel
   - IAM role: Use the ChatbotRole ARN from your deployment outputs
   - Channel guardrail policies: ReadOnlyAccess (pre-configured)
   - SNS topics: Use the SNSTopicArn from your deployment outputs

### Microsoft Teams Integration

1. Navigate to the AWS Chatbot Console: https://console.aws.amazon.com/chatbot/
2. Choose "Microsoft Teams" as your chat client
3. Follow the OAuth authorization process
4. Configure the channel with the same parameters as above

## Testing the Setup

After completing the manual configuration:

```bash
# Get your SNS topic ARN from deployment outputs
export SNS_TOPIC_ARN=$(aws cloudformation describe-stacks \
    --stack-name chat-notifications-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' \
    --output text)

# Send a test notification
aws sns publish \
    --topic-arn $SNS_TOPIC_ARN \
    --subject "🚨 Test Alert: Infrastructure Notification" \
    --message "This is a test of the chat notification system. All teams should receive this message."

# Check your configured chat channel for the notification
```

## Customization

### CloudFormation Parameters

- `NotificationTopicName`: Name for the SNS topic (default: team-notifications)
- `AlarmName`: Name for the demo CloudWatch alarm (default: demo-cpu-alarm)
- `EnableEncryption`: Enable SNS topic encryption (default: true)

### CDK Configuration

Edit the configuration variables in the CDK app files:

**TypeScript**: Modify variables in `app.ts`
**Python**: Modify variables in `app.py`

### Terraform Variables

Edit `terraform/variables.tf` to customize default values, or create a `terraform.tfvars` file:

```hcl
notification_topic_name = "my-team-notifications"
alarm_name = "my-demo-alarm"
enable_encryption = true
environment = "production"
```

### Bash Script Configuration

Edit environment variables at the top of `scripts/deploy.sh`:

```bash
# Customize these variables
NOTIFICATION_TOPIC_NAME="team-notifications"
ALARM_NAME="demo-cpu-alarm"
ENABLE_ENCRYPTION="true"
```

## Validation and Testing

After deployment, verify the infrastructure:

1. **Check SNS Topic**:
   ```bash
   aws sns list-topics --query 'Topics[?contains(TopicArn, `team-notifications`)]'
   ```

2. **Verify CloudWatch Alarm**:
   ```bash
   aws cloudwatch describe-alarms --alarm-names demo-cpu-alarm
   ```

3. **Test Notification Flow**:
   ```bash
   # Replace with your actual topic ARN
   aws sns publish \
       --topic-arn arn:aws:sns:region:account:team-notifications \
       --subject "Infrastructure Test" \
       --message "Testing the complete notification pipeline"
   ```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name chat-notifications-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name chat-notifications-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy the stack
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

# Follow the prompts to confirm resource deletion
```

### Manual Cleanup (AWS Chatbot)

After destroying the infrastructure, manually clean up the Chatbot configuration:

1. Go to AWS Chatbot console: https://console.aws.amazon.com/chatbot/
2. Select your Slack workspace or Teams tenant
3. Delete the channel configuration you created
4. (Optional) Remove AWS Chatbot from your chat platform workspace

## Troubleshooting

### Common Issues

1. **ChatBot Permissions**: Ensure the IAM role has appropriate permissions for your use case
2. **SNS Topic Permissions**: Verify CloudWatch alarms can publish to the SNS topic
3. **Slack Integration**: Check that AWS Chatbot is properly authorized in your Slack workspace
4. **Region Consistency**: Ensure all resources are deployed in the same AWS region

### Debug Commands

```bash
# Check SNS topic attributes
aws sns get-topic-attributes --topic-arn <your-topic-arn>

# List SNS subscriptions
aws sns list-subscriptions-by-topic --topic-arn <your-topic-arn>

# Check CloudWatch alarm status
aws cloudwatch describe-alarms --alarm-names <your-alarm-name>

# Test SNS publishing
aws sns publish --topic-arn <your-topic-arn> --message "Debug test"
```

## Cost Considerations

- **SNS**: $0.50 per million messages
- **CloudWatch Alarms**: $0.10 per alarm per month
- **AWS Chatbot**: No additional charges
- **Data Transfer**: Standard AWS data transfer rates apply

Estimated monthly cost: $0.50-$2.00 (depending on message volume)

## Security Features

- SNS topic encryption using AWS KMS
- IAM role with least privilege permissions
- Resource-based policies for secure access
- CloudTrail integration for audit logging

## Version Compatibility

- **CloudFormation**: Compatible with all AWS regions that support Chatbot
- **CDK**: Requires CDK v2.x
- **Terraform**: Requires Terraform 1.0+ and AWS Provider 4.0+
- **AWS CLI**: Requires AWS CLI v2.x

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check AWS CloudFormation/CDK/Terraform documentation
3. Review AWS Chatbot setup guide: https://docs.aws.amazon.com/chatbot/latest/adminguide/
4. Consult AWS SNS documentation: https://docs.aws.amazon.com/sns/

## Additional Resources

- [AWS SNS Documentation](https://docs.aws.amazon.com/sns/)
- [AWS Chatbot Documentation](https://docs.aws.amazon.com/chatbot/)
- [CloudWatch Alarms Documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)
- [Slack Integration Guide](https://docs.aws.amazon.com/chatbot/latest/adminguide/slack-setup.html)
- [Microsoft Teams Integration Guide](https://docs.aws.amazon.com/chatbot/latest/adminguide/teams-setup.html)