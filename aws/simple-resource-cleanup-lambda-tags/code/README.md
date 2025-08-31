# Infrastructure as Code for Resource Cleanup Automation with Lambda and Tags

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Resource Cleanup Automation with Lambda and Tags".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys an automated resource cleanup system that:
- Uses AWS Lambda to identify and terminate EC2 instances based on tags
- Sends notifications via SNS when cleanup actions are performed
- Includes proper IAM permissions and CloudWatch logging
- Provides cost-effective resource governance for organizations

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- Appropriate AWS permissions for:
  - Lambda (create functions, manage execution roles)
  - EC2 (describe instances, terminate instances, manage tags)
  - SNS (create topics, publish messages, manage subscriptions)
  - IAM (create roles, attach policies)
  - CloudWatch (create log groups, put log events)
- Email address for receiving cleanup notifications
- Basic understanding of AWS Lambda and EC2 tagging strategies

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name resource-cleanup-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name resource-cleanup-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name resource-cleanup-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set your notification email
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
```

### Using CDK Python
```bash
cd cdk-python/

# Install dependencies
pip install -r requirements.txt

# Set your notification email
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
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

# Set required environment variables
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment summary
cat deployment-summary.txt
```

## Configuration Options

### CloudFormation Parameters
- `NotificationEmail`: Email address for cleanup notifications (required)
- `FunctionName`: Name for the Lambda function (default: auto-generated)
- `ScheduleExpression`: CloudWatch Events schedule (default: rate(1 day))

### CDK Configuration
Set environment variables before deployment:
```bash
export NOTIFICATION_EMAIL=your-email@example.com
export FUNCTION_TIMEOUT=300  # Optional: Lambda timeout in seconds
export MEMORY_SIZE=256       # Optional: Lambda memory in MB
```

### Terraform Variables
Configure via `terraform.tfvars`:
```hcl
notification_email = "your-email@example.com"
function_name     = "resource-cleanup"
schedule_enabled  = true
tags = {
  Environment = "production"
  Owner      = "infrastructure-team"
}
```

## Testing the Solution

### 1. Confirm Email Subscription
After deployment, check your email and confirm the SNS subscription to receive notifications.

### 2. Create Test Instance
```bash
# Create a test EC2 instance with the AutoCleanup tag
aws ec2 run-instances \
    --image-id $(aws ssm get-parameter \
        --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
        --query 'Parameter.Value' --output text) \
    --instance-type t2.micro \
    --tag-specifications \
    'ResourceType=instance,Tags=[{Key=Name,Value=test-cleanup-instance},{Key=AutoCleanup,Value=true}]'
```

### 3. Manually Trigger Lambda
```bash
# Get function name from stack outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name resource-cleanup-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`FunctionName`].OutputValue' \
    --output text)

# Invoke the function
aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{}' \
    response.json

# Check the response
cat response.json
```

### 4. Monitor Execution
```bash
# View Lambda logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/$FUNCTION_NAME" \
    --start-time $(date -d '10 minutes ago' +%s)000
```

## Automated Scheduling

The solution includes CloudWatch Events rules to automatically run the cleanup function on a schedule:

- **Default Schedule**: Daily execution at 02:00 UTC
- **Customizable**: Modify the schedule expression in the IaC templates
- **Disable**: Set schedule parameters to false/null to disable automatic execution

## Security Features

- **Least Privilege IAM**: Lambda execution role has minimal required permissions
- **Resource Tagging**: Only instances with specific tags are affected
- **Audit Trail**: All actions logged to CloudWatch Logs
- **Notification System**: Immediate alerts for all cleanup actions
- **Error Handling**: Comprehensive error handling with failure notifications

## Cost Optimization

This solution provides significant cost savings:

- **Lambda Execution**: ~$0.50-$2.00/month for daily executions
- **SNS Notifications**: ~$0.01-$0.10/month for email notifications
- **CloudWatch Logs**: ~$0.50/month for log retention
- **Potential Savings**: $500-$5000+/month from automated cleanup of forgotten instances

## Customization

### Modify Cleanup Criteria
Edit the Lambda function code to change which instances are cleaned up:
- Different tag keys/values
- Instance age-based cleanup
- Instance type restrictions
- Environment-specific rules

### Add Additional Resources
Extend the solution to clean up other AWS resources:
- EBS volumes
- RDS instances
- Elastic Load Balancers
- Lambda functions

### Enhanced Notifications
Customize notification content:
- Add cost estimates
- Include resource metadata
- Format for different channels (Slack, Teams)

## Troubleshooting

### Common Issues

1. **Email notifications not received**
   - Check spam folder
   - Confirm SNS subscription
   - Verify email address in configuration

2. **Lambda function fails**
   - Check CloudWatch Logs for error messages
   - Verify IAM permissions
   - Ensure SNS topic ARN is correct

3. **No instances found for cleanup**
   - Verify EC2 instances have `AutoCleanup=true` tag
   - Check instance states (running/stopped)
   - Review tag key capitalization

### Debug Commands
```bash
# Check Lambda function configuration
aws lambda get-function --function-name $FUNCTION_NAME

# List SNS topics
aws sns list-topics

# Check IAM role permissions
aws iam get-role-policy \
    --role-name resource-cleanup-role \
    --policy-name ResourceCleanupPolicy
```

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name resource-cleanup-stack
aws cloudformation wait stack-delete-complete --stack-name resource-cleanup-stack
```

### Using CDK
```bash
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

## Monitoring and Maintenance

### CloudWatch Metrics
Monitor the following metrics:
- Lambda function duration and errors
- SNS message delivery success/failure
- EC2 instance termination counts

### Regular Reviews
- Review cleanup notifications for accuracy
- Audit tag usage across organization
- Update Lambda function for new requirements
- Review IAM permissions periodically

## Extension Ideas

1. **Time-Based Cleanup**: Implement instance age calculations
2. **Approval Workflows**: Add Step Functions for approval processes
3. **Multi-Region Support**: Deploy across multiple AWS regions
4. **Cost Reporting**: Add detailed cost analysis and reporting
5. **Slack Integration**: Replace/supplement email with Slack notifications

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review CloudWatch Logs for detailed error information
3. Refer to the original recipe documentation
4. Consult AWS documentation for service-specific issues

## License

This infrastructure code is provided as-is for educational and implementation purposes.