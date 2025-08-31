# Infrastructure as Code for Centralized Alert Management with User Notifications and CloudWatch

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Centralized Alert Management with User Notifications and CloudWatch".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates a centralized notification management system that:
- Creates an S3 bucket with CloudWatch metrics enabled
- Sets up CloudWatch alarms for bucket size monitoring
- Configures AWS User Notifications for centralized alert management
- Establishes email notifications for alarm state changes
- Provides a unified notification dashboard experience

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- AWS account with Administrator access for:
  - Amazon S3
  - Amazon CloudWatch
  - AWS User Notifications
  - AWS User Notifications Contacts
- Valid email address for notification testing
- Required tools for your chosen deployment method:
  - **CloudFormation**: No additional tools required
  - **CDK**: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
  - **Terraform**: Terraform 1.5+ installed
  - **Scripts**: Bash shell environment

## Cost Considerations

- **S3 Storage**: ~$0.023 per GB per month for Standard storage
- **CloudWatch Alarms**: $0.10 per alarm per month
- **CloudWatch Metrics**: Daily storage metrics included, request metrics $0.01 per 1,000 requests
- **User Notifications**: No additional charges for basic notification delivery
- **Estimated Monthly Cost**: $0.10 - $0.50 for typical usage

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name centralized-alerts-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name centralized-alerts-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name centralized-alerts-stack \
    --query "Stacks[0].Outputs"
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Configure email for notifications
export NOTIFICATION_EMAIL=your-email@example.com

# Bootstrap CDK (if first time using CDK in the account/region)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View stack outputs
cdk output
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure email for notifications
export NOTIFICATION_EMAIL=your-email@example.com

# Bootstrap CDK (if first time using CDK in the account/region)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View stack outputs
cdk output
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your email
echo 'notification_email = "your-email@example.com"' > terraform.tfvars

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export NOTIFICATION_EMAIL=your-email@example.com
export AWS_REGION=us-east-1

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment summary
echo "Deployment completed. Check your email for activation instructions."
```

## Post-Deployment Steps

### Email Contact Activation

1. **Check your email** for an activation message from AWS User Notifications
2. **Click the activation link** in the email to verify your contact
3. **Confirm activation** in the AWS Console under User Notifications

### Testing the Solution

1. **Upload test files** to the S3 bucket to generate metrics:
   ```bash
   # Get bucket name from stack outputs
   BUCKET_NAME=$(aws cloudformation describe-stacks \
       --stack-name centralized-alerts-stack \
       --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" \
       --output text)
   
   # Upload test files
   echo "Test file content" > test-file.txt
   aws s3 cp test-file.txt s3://${BUCKET_NAME}/
   ```

2. **Manually trigger alarm** for testing:
   ```bash
   # Get alarm name from stack outputs
   ALARM_NAME=$(aws cloudformation describe-stacks \
       --stack-name centralized-alerts-stack \
       --query "Stacks[0].Outputs[?OutputKey=='AlarmName'].OutputValue" \
       --output text)
   
   # Trigger alarm state change
   aws cloudwatch set-alarm-state \
       --alarm-name ${ALARM_NAME} \
       --state-value ALARM \
       --state-reason "Manual test of notification system"
   ```

3. **Check notifications**:
   - Monitor your email for alert notifications
   - Check the AWS Console User Notifications Center
   - Verify notification delivery and formatting

### Accessing the Notification Center

1. **Open AWS Console** and navigate to "User Notifications"
2. **View notification history** in the Notifications Center
3. **Manage preferences** for different notification types
4. **Configure additional contacts** or delivery channels as needed

## Customization Options

### Environment Variables

- `NOTIFICATION_EMAIL`: Email address for notifications (required)
- `AWS_REGION`: Target AWS region (default: us-east-1)
- `BUCKET_NAME_SUFFIX`: Custom suffix for bucket naming
- `ALARM_THRESHOLD`: S3 bucket size threshold in bytes (default: 5000000)

### Parameter Customization

Each implementation supports customization through parameters:

- **Notification Email**: Email address for alert delivery
- **Alarm Threshold**: CloudWatch alarm threshold for bucket size
- **Aggregation Duration**: Notification aggregation window
- **Metric Evaluation Period**: CloudWatch alarm evaluation period

### Advanced Configuration

For advanced scenarios, consider modifying:

1. **Multiple Notification Channels**: Add SMS, mobile push, or webhook endpoints
2. **Complex Event Filtering**: Customize EventBridge rules for specific alarm types
3. **Multi-Service Monitoring**: Extend alarms to cover additional AWS services
4. **Escalation Policies**: Integrate with external incident management systems

## Monitoring and Troubleshooting

### Health Checks

```bash
# Check notification hub status
aws notifications list-notification-hubs \
    --query "notificationHubs[*].{Region:notificationHubRegion,Status:status}"

# Verify email contact status
aws notificationscontacts list-email-contacts \
    --query "emailContacts[*].{Name:name,Status:status,Email:emailAddress}"

# Check CloudWatch alarm state
aws cloudwatch describe-alarms \
    --query "MetricAlarms[?AlarmName=='s3-bucket-size-alarm'].{Name:AlarmName,State:StateValue}"
```

### Common Issues

1. **Email Not Activated**: Check spam folder and activate email contact
2. **No Notifications Received**: Verify notification hub registration and email association
3. **Alarm Not Triggering**: Ensure S3 metrics are enabled and alarm threshold is appropriate
4. **Permission Errors**: Verify IAM permissions for all required services

### Logging and Monitoring

- **CloudWatch Logs**: Monitor User Notifications service logs
- **CloudTrail**: Track API calls for troubleshooting
- **AWS Config**: Monitor configuration changes
- **Cost Explorer**: Track notification-related costs

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name centralized-alerts-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name centralized-alerts-stack

# Verify stack deletion
aws cloudformation describe-stacks \
    --stack-name centralized-alerts-stack 2>/dev/null || echo "Stack deleted successfully"
```

### Using CDK

```bash
# Navigate to your CDK directory (TypeScript or Python)
cd cdk-typescript/  # or cd cdk-python/

# Destroy the stack
cdk destroy --force

# Clean up CDK bootstrap (optional, affects all CDK usage in account/region)
# cdk bootstrap --toolkit-stack-name CDKToolkit --destroy
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy -auto-approve

# Clean up state files (optional)
rm -f terraform.tfstate*
rm -rf .terraform/
```

### Using Bash Scripts

```bash
# Execute cleanup script
./scripts/destroy.sh

# Confirm all resources are removed
echo "Cleanup completed. Verify in AWS Console that all resources are removed."
```

### Manual Cleanup Verification

After automated cleanup, verify these resources are removed:

1. **S3 Bucket**: Check that bucket and all objects are deleted
2. **CloudWatch Alarms**: Confirm alarm deletion
3. **User Notifications Hub**: Verify deregistration
4. **Email Contacts**: Confirm contact deletion
5. **Event Rules**: Check EventBridge rules are removed

## Security Considerations

### IAM Permissions

The infrastructure creates IAM roles and policies with least privilege access:

- **CloudWatch Service Role**: Permissions for alarm state changes
- **User Notifications Role**: Permissions for notification processing
- **S3 Service Role**: Permissions for metrics publishing

### Data Privacy

- **Email Addresses**: Stored securely in AWS User Notifications Contacts
- **Notification Content**: Transmitted over encrypted channels
- **S3 Objects**: Encrypted at rest using S3 default encryption

### Network Security

- **API Calls**: All service communications use HTTPS/TLS
- **Event Processing**: EventBridge provides secure event routing
- **Email Delivery**: Uses AWS SES with DKIM signing

## Support and Documentation

### AWS Service Documentation

- [AWS User Notifications User Guide](https://docs.aws.amazon.com/notifications/latest/userguide/)
- [Amazon CloudWatch User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/)
- [Amazon S3 User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/)
- [AWS User Notifications Contacts API Reference](https://docs.aws.amazon.com/notifications-contacts/latest/APIReference/)

### IaC Tool Documentation

- [AWS CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/)

### Troubleshooting Resources

- **AWS Support**: Contact AWS Support for service-specific issues
- **Community Forums**: AWS Developer Forums and Stack Overflow
- **GitHub Issues**: Report infrastructure code issues to the recipe repository

For issues with this infrastructure code, refer to the original recipe documentation or the AWS service documentation linked above.