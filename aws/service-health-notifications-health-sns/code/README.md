# Infrastructure as Code for Service Health Notifications with Health and SNS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Service Health Notifications with Health and SNS". This solution automatically monitors AWS Personal Health Dashboard events and sends notifications via email using EventBridge and SNS.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

The solution deploys:
- SNS Topic for health notifications
- EventBridge Rule to capture AWS Health events
- IAM Role with permissions for EventBridge to publish to SNS
- Email subscription to the SNS topic
- Topic policy allowing EventBridge access

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- Appropriate AWS permissions for:
  - SNS (CreateTopic, Subscribe, SetTopicAttributes)
  - EventBridge (PutRule, PutTargets)
  - IAM (CreateRole, AttachRolePolicy)
  - AWS Health Dashboard access
- Valid email address for receiving notifications
- For CDK: Node.js 16+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name health-notifications \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name health-notifications \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name health-notifications \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure your email address
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the stack
npx cdk deploy HealthNotificationsStack

# Get stack outputs
npx cdk outputs
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment and install dependencies
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Configure your email address
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the stack
cdk deploy HealthNotificationsStack

# Get stack outputs
cdk outputs
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your email
echo 'notification_email = "your-email@example.com"' > terraform.tfvars

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

# Set your email address
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output resource information upon completion
```

## Post-Deployment Steps

After deploying with any method:

1. **Confirm Email Subscription**: Check your email inbox for a subscription confirmation message from AWS SNS and click the confirmation link.

2. **Test the System**: Send a test notification to verify the pipeline:
   ```bash
   # Get the SNS topic ARN from outputs
   TOPIC_ARN=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `health-notifications`)].TopicArn' --output text)
   
   # Send test message
   aws sns publish \
       --topic-arn ${TOPIC_ARN} \
       --subject "Test: AWS Health Notification" \
       --message "This is a test notification to verify your health monitoring system."
   ```

3. **Monitor Events**: The system will now automatically send notifications for AWS Health events affecting your account.

## Configuration Options

### CloudFormation Parameters

- `NotificationEmail`: Email address for receiving notifications (required)
- `TopicDisplayName`: Display name for the SNS topic (default: "AWS Health Notifications")

### CDK Configuration

Set environment variables before deployment:
- `NOTIFICATION_EMAIL`: Email address for notifications
- `AWS_REGION`: AWS region for deployment (uses default if not set)

### Terraform Variables

Configure in `terraform.tfvars`:
- `notification_email`: Email address for receiving notifications (required)
- `topic_display_name`: Display name for the SNS topic (optional)
- `aws_region`: AWS region for deployment (optional)

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name health-notifications

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name health-notifications
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy HealthNotificationsStack
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

## Customization

### Adding Multiple Email Recipients

For CloudFormation/CDK, modify the template to accept multiple emails:
```yaml
# CloudFormation example
AdditionalEmailSubscription:
  Type: AWS::SNS::Subscription
  Properties:
    Protocol: email
    TopicArn: !Ref HealthNotificationsTopic
    Endpoint: second-email@example.com
```

### Event Filtering

To filter specific types of health events, modify the EventBridge rule pattern:
```json
{
  "source": ["aws.health"],
  "detail-type": ["AWS Health Event"],
  "detail": {
    "eventTypeCategory": ["issue", "accountNotification"]
  }
}
```

### Additional Notification Channels

Add SMS notifications by creating additional SNS subscriptions:
```bash
aws sns subscribe \
    --topic-arn ${TOPIC_ARN} \
    --protocol sms \
    --notification-endpoint +1234567890
```

## Monitoring and Troubleshooting

### Verify EventBridge Rule

```bash
# Check rule status
aws events describe-rule --name aws-health-notifications-rule

# List rule targets
aws events list-targets-by-rule --rule aws-health-notifications-rule
```

### Monitor SNS Topic

```bash
# List topic subscriptions
aws sns list-subscriptions-by-topic --topic-arn ${TOPIC_ARN}

# Check topic attributes
aws sns get-topic-attributes --topic-arn ${TOPIC_ARN}
```

### CloudWatch Metrics

Monitor these CloudWatch metrics:
- `AWS/SNS/NumberOfMessagesPublished`: Messages sent to topic
- `AWS/SNS/NumberOfNotificationsFailed`: Failed notifications
- `AWS/Events/MatchedEvents`: Events matched by EventBridge rule

## Security Considerations

- The IAM role follows least privilege principles, only allowing SNS publish permissions
- SNS topic policy restricts access to EventBridge service
- Email subscription requires manual confirmation for security
- All resources are created with appropriate tags for governance

## Cost Optimization

- SNS charges $0.50 per million notifications
- EventBridge rules are free for AWS service events
- Typical monthly cost: Less than $1 for normal health event volumes
- No ongoing charges when no health events occur

## Troubleshooting

### Common Issues

1. **Email not received**: Check spam folder and ensure email confirmation is completed
2. **EventBridge rule not triggering**: Verify IAM permissions and topic policy
3. **Deployment failures**: Check IAM permissions for the deploying user/role

### Debug Commands

```bash
# Test SNS topic directly
aws sns publish --topic-arn ${TOPIC_ARN} --message "Test message"

# Check EventBridge rule metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Events \
    --metric-name MatchedEvents \
    --dimensions Name=RuleName,Value=aws-health-notifications-rule \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-02T00:00:00Z \
    --period 3600 \
    --statistics Sum
```

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS service documentation for [Personal Health Dashboard](https://docs.aws.amazon.com/health/), [EventBridge](https://docs.aws.amazon.com/eventbridge/), and [SNS](https://docs.aws.amazon.com/sns/)
3. Verify AWS CLI configuration and permissions
4. Check CloudWatch logs for detailed error information

## Related Resources

- [AWS Health User Guide](https://docs.aws.amazon.com/health/latest/ug/what-is-aws-health.html)
- [EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-what-is.html)
- [SNS Developer Guide](https://docs.aws.amazon.com/sns/latest/dg/welcome.html)
- [AWS Health EventBridge Integration](https://docs.aws.amazon.com/health/latest/ug/cloudwatch-events-health.html)