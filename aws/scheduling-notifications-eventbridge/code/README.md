# Infrastructure as Code for Scheduling Notifications with EventBridge and SNS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Scheduling Notifications with EventBridge and SNS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured (version 2.x recommended)
- Appropriate AWS permissions for creating:
  - EventBridge Scheduler schedules and schedule groups
  - SNS topics and subscriptions
  - IAM roles and policies
- Valid email address for receiving test notifications
- Basic understanding of cron expressions and JSON formatting

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions

#### CDK TypeScript
- Node.js (version 14.x or later)
- npm or yarn package manager
- AWS CDK CLI (`npm install -g aws-cdk`)

#### CDK Python
- Python 3.7 or later
- pip package manager
- AWS CDK CLI (`pip install aws-cdk-lib`)

#### Terraform
- Terraform CLI (version 1.0 or later)
- AWS provider for Terraform

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name simple-business-notifications \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name simple-business-notifications

# Get outputs
aws cloudformation describe-stacks \
    --stack-name simple-business-notifications \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters NotificationEmail=your-email@example.com

# View outputs
cdk ls --long
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters NotificationEmail=your-email@example.com

# View outputs
cdk ls --long
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your configuration
cat > terraform.tfvars << 'EOF'
notification_email = "your-email@example.com"
aws_region = "us-east-1"
project_name = "simple-business-notifications"
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
export NOTIFICATION_EMAIL="your-email@example.com"
export AWS_REGION="us-east-1"

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
echo "Deployment complete. Check your email for subscription confirmation."
```

## Post-Deployment Steps

1. **Confirm Email Subscription**: Check your email inbox and click the confirmation link sent by Amazon SNS to activate your subscription.

2. **Test the Notification System**: 
   ```bash
   # Send a test message using AWS CLI
   aws sns publish \
       --topic-arn $(aws sns list-topics --query 'Topics[0].TopicArn' --output text) \
       --subject "Test Business Notification" \
       --message "This is a test message to verify your notification system."
   ```

3. **Verify Schedule Configuration**:
   ```bash
   # List all created schedules
   aws scheduler list-schedules \
       --group-name $(aws scheduler list-schedule-groups --query 'ScheduleGroups[0].Name' --output text)
   ```

## Architecture Components

The deployed infrastructure includes:

- **SNS Topic**: Central hub for business notifications with email subscription
- **EventBridge Scheduler Schedules**:
  - Daily business report (weekdays at 9 AM EST)
  - Weekly summary (Mondays at 8 AM EST)  
  - Monthly reminder (1st of each month at 10 AM EST)
- **Schedule Group**: Logical organization for related schedules
- **IAM Role and Policy**: Secure access for EventBridge Scheduler to publish to SNS

## Customization

### Variables and Parameters

Each implementation supports customization through variables/parameters:

- `notification_email`: Email address for receiving notifications
- `aws_region`: AWS region for resource deployment
- `project_name`: Prefix for resource naming
- `schedule_timezone`: Timezone for schedule expressions (default: America/New_York)

### Modifying Schedules

To customize the notification schedules, update the cron expressions:

- **Daily Report**: `cron(0 9 ? * MON-FRI *)` (9 AM weekdays)
- **Weekly Summary**: `cron(0 8 ? * MON *)` (8 AM Mondays)
- **Monthly Reminder**: `cron(0 10 1 * ? *)` (10 AM first day of month)

### Message Customization

Modify the SNS message content in the respective IaC files to customize:
- Subject lines
- Message bodies
- Notification frequency
- Target audiences

## Monitoring and Troubleshooting

### Check Schedule Status
```bash
# View specific schedule details
aws scheduler get-schedule \
    --name daily-business-report \
    --group-name your-schedule-group-name

# Check schedule execution history
aws logs filter-log-events \
    --log-group-name /aws/events/scheduler \
    --start-time $(date -d '1 day ago' +%s)000
```

### Verify SNS Topic Health
```bash
# Check topic attributes
aws sns get-topic-attributes --topic-arn your-topic-arn

# List subscriptions
aws sns list-subscriptions-by-topic --topic-arn your-topic-arn
```

## Cleanup

### Using CloudFormation (AWS)
```bash
aws cloudformation delete-stack --stack-name simple-business-notifications

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name simple-business-notifications
```

### Using CDK (AWS)
```bash
# From the respective CDK directory
cdk destroy

# Confirm destruction when prompted
```

### Using Terraform
```bash
cd terraform/
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
./scripts/destroy.sh

# Confirm destruction when prompted
```

## Cost Considerations

This solution is designed to be cost-effective for business notifications:

- **EventBridge Scheduler**: $1.00 per million schedule invocations
- **SNS**: $0.50 per million email notifications
- **IAM**: No additional charges for roles and policies

Estimated monthly cost for typical business usage: $0.01 - $0.50

## Security Features

- **Least Privilege IAM**: Scheduler role can only publish to the specific SNS topic
- **Encrypted Communication**: SNS uses encryption in transit
- **Subscription Confirmation**: Email subscriptions require explicit confirmation
- **CloudTrail Integration**: All API calls are logged for audit purposes

## Support and Troubleshooting

### Common Issues

1. **Email Not Received**: Check spam folder and ensure subscription is confirmed
2. **Schedule Not Executing**: Verify IAM role permissions and schedule group exists
3. **Permission Errors**: Ensure AWS CLI has sufficient permissions for resource creation

### Additional Resources

- [Amazon EventBridge Scheduler User Guide](https://docs.aws.amazon.com/scheduler/latest/UserGuide/what-is-scheduler.html)
- [Amazon SNS Developer Guide](https://docs.aws.amazon.com/sns/latest/dg/welcome.html)
- [EventBridge Scheduler with SNS Integration](https://docs.aws.amazon.com/sns/latest/dg/using-eventbridge-scheduler.html)

For issues with this infrastructure code, refer to the original recipe documentation or consult the AWS documentation for the specific services involved.