# Infrastructure as Code for CodeCommit Git Workflows and Policies

This directory contains Infrastructure as Code (IaC) implementations for the recipe "CodeCommit Git Workflows and Policies".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This infrastructure deploys a comprehensive Git workflow automation system including:

- AWS CodeCommit repository with enterprise-grade configuration
- Lambda functions for pull request and quality gate automation
- SNS topics for multi-channel notifications
- EventBridge rules for event-driven workflow triggers
- IAM roles and policies with least-privilege access
- CloudWatch dashboards for workflow monitoring
- Approval rule templates for code review governance

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - CodeCommit (repository management, triggers, approval rules)
  - Lambda (function creation, execution)
  - IAM (role and policy management)
  - SNS (topic creation and management)
  - EventBridge (rule creation and management)
  - CloudWatch (dashboard and metrics)
- Git client configured with CodeCommit credentials
- Understanding of Git workflows and branching strategies

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name codecommit-git-workflows \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=RepositoryName,ParameterValue=my-enterprise-repo \
                ParameterKey=TeamLeadUser,ParameterValue=team-lead \
                ParameterKey=SeniorDevelopers,ParameterValue="senior-dev-1,senior-dev-2" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Wait for completion
aws cloudformation wait stack-create-complete \
    --stack-name codecommit-git-workflows

# Get outputs
aws cloudformation describe-stacks \
    --stack-name codecommit-git-workflows \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure deployment
export CDK_DEFAULT_REGION=us-east-1
export REPOSITORY_NAME=my-enterprise-repo
export TEAM_LEAD_USER=team-lead
export SENIOR_DEVELOPERS="senior-dev-1,senior-dev-2"

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

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

# Configure deployment
export CDK_DEFAULT_REGION=us-east-1
export REPOSITORY_NAME=my-enterprise-repo
export TEAM_LEAD_USER=team-lead
export SENIOR_DEVELOPERS="senior-dev-1,senior-dev-2"

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk output
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Create variables file
cat > terraform.tfvars << EOF
repository_name = "my-enterprise-repo"
repository_description = "Enterprise application with Git workflow automation"
team_lead_user = "team-lead"
senior_developers = ["senior-dev-1", "senior-dev-2"]
all_developers = ["dev-1", "dev-2", "dev-3", "senior-dev-1", "senior-dev-2"]
notification_email = "your-email@example.com"
EOF

# Plan deployment
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

# Configure environment
export REPOSITORY_NAME=my-enterprise-repo
export TEAM_LEAD_USER=team-lead
export SENIOR_DEVELOPERS="senior-dev-1,senior-dev-2"
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy infrastructure
./scripts/deploy.sh

# The script will output important resource ARNs and configuration details
```

## Configuration Options

### Repository Settings
- **Repository Name**: Customize the CodeCommit repository name
- **Repository Description**: Set descriptive text for the repository
- **Default Branch**: Configure the default branch (main/master)

### Team Configuration
- **Team Lead User**: IAM user for team leadership approval
- **Senior Developers**: List of senior developers for code review
- **All Developers**: Complete list of team developers for notifications

### Notification Settings
- **Email Notifications**: Configure email endpoints for SNS topics
- **Notification Types**: Customize which events trigger notifications
- **Message Formatting**: Adjust notification message templates

### Quality Gate Settings
- **Test Coverage Threshold**: Minimum required test coverage percentage
- **Security Scan Settings**: Configure vulnerability scanning parameters
- **Linting Rules**: Customize code style and quality rules

### Monitoring and Metrics
- **Dashboard Configuration**: Customize CloudWatch dashboard widgets
- **Metric Retention**: Configure metric data retention periods
- **Alert Thresholds**: Set up CloudWatch alarms for key metrics

## Post-Deployment Configuration

### 1. Configure Email Subscriptions
```bash
# Subscribe to pull request notifications
aws sns subscribe \
    --topic-arn $(terraform output -raw pull_request_topic_arn) \
    --protocol email \
    --notification-endpoint your-email@example.com

# Subscribe to quality gate alerts
aws sns subscribe \
    --topic-arn $(terraform output -raw quality_gate_topic_arn) \
    --protocol email \
    --notification-endpoint security-team@example.com
```

### 2. Clone and Initialize Repository
```bash
# Get repository clone URL
REPO_CLONE_URL=$(terraform output -raw repository_clone_url)

# Clone repository
git clone $REPO_CLONE_URL
cd $(terraform output -raw repository_name)

# Create initial structure (if not already present)
mkdir -p src tests docs .github/workflows scripts
echo "# Enterprise Application" > README.md
git add README.md
git commit -m "Initial commit"
git push origin main
```

### 3. Configure Git Credentials
```bash
# Configure Git credential helper for CodeCommit
git config --global credential.helper '!aws codecommit credential-helper $@'
git config --global credential.UseHttpPath true

# Verify connectivity
git ls-remote --heads $REPO_CLONE_URL
```

### 4. Test Workflow Automation
```bash
# Create test feature branch
git checkout -b feature/test-automation
echo "console.log('Hello World');" > src/app.js
git add .
git commit -m "Add test application file"
git push origin feature/test-automation

# Create test pull request
aws codecommit create-pull-request \
    --title "Test automation workflow" \
    --description "Testing automated quality gates and notifications" \
    --targets sourceReference=feature/test-automation,destinationReference=main \
    --repository-name $(terraform output -raw repository_name)
```

## Monitoring and Observability

### CloudWatch Dashboard
The deployment creates a comprehensive monitoring dashboard accessible at:
```
https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=Git-Workflow-{RepositoryName}
```

### Key Metrics Monitored
- Pull request creation and merge rates
- Quality gate success/failure rates
- Individual quality check results (linting, security, tests, dependencies)
- Lambda function execution metrics
- EventBridge rule processing statistics

### Log Analysis
```bash
# View Lambda function logs
aws logs tail "/aws/lambda/codecommit-automation-{suffix}-pull-request" --follow

# Check quality gate execution logs
aws logs tail "/aws/lambda/codecommit-automation-{suffix}-quality-gate" --follow

# Monitor EventBridge rule execution
aws logs describe-log-groups --log-group-name-prefix "/aws/events/rule"
```

## Troubleshooting

### Common Issues

#### 1. Lambda Functions Not Triggering
```bash
# Check EventBridge rule configuration
aws events describe-rule --name codecommit-pull-request-events-{suffix}

# Verify Lambda permissions
aws lambda get-policy --function-name codecommit-automation-{suffix}-pull-request

# Test Lambda function manually
aws lambda invoke \
    --function-name codecommit-automation-{suffix}-pull-request \
    --payload '{"source": "aws.codecommit", "detail-type": "CodeCommit Pull Request State Change"}' \
    response.json
```

#### 2. Quality Gates Failing
```bash
# Check repository triggers
aws codecommit get-repository-triggers --repository-name {repository-name}

# Verify trigger permissions
aws lambda get-policy --function-name codecommit-automation-{suffix}-quality-gate

# Review function logs for errors
aws logs filter-log-events \
    --log-group-name "/aws/lambda/codecommit-automation-{suffix}-quality-gate" \
    --filter-pattern "ERROR"
```

#### 3. Approval Rules Not Working
```bash
# Check approval rule template association
aws codecommit list-associated-approval-rule-templates-for-repository \
    --repository-name {repository-name}

# Verify approval rule template content
aws codecommit get-approval-rule-template \
    --approval-rule-template-name enterprise-approval-template
```

#### 4. Notifications Not Delivered
```bash
# Check SNS topic subscriptions
aws sns list-subscriptions-by-topic \
    --topic-arn {topic-arn}

# Verify SNS permissions
aws sns get-topic-attributes --topic-arn {topic-arn}

# Test notification delivery
aws sns publish \
    --topic-arn {topic-arn} \
    --message "Test notification" \
    --subject "Test Subject"
```

### Debug Commands
```bash
# Enable debug logging for Lambda functions
aws lambda update-function-configuration \
    --function-name codecommit-automation-{suffix}-pull-request \
    --environment Variables="{LOG_LEVEL=DEBUG}"

# Monitor real-time events
aws events put-rule \
    --name debug-codecommit-events \
    --event-pattern '{"source": ["aws.codecommit"]}'

# View EventBridge events
aws logs tail "/aws/events/debug-codecommit-events" --follow
```

## Security Considerations

### IAM Permissions
The infrastructure implements least-privilege access with role-based permissions:
- Lambda execution roles have minimal required permissions
- CodeCommit access is scoped to specific repositories
- SNS publishing permissions are limited to created topics

### Network Security
- All AWS services communicate over private AWS backbone
- Lambda functions execute in AWS-managed VPC
- EventBridge rules use IAM-based access control

### Data Protection
- CodeCommit repositories are encrypted at rest and in transit
- Lambda environment variables are encrypted using AWS KMS
- CloudWatch logs are encrypted using service-managed keys

### Compliance
- All actions are logged in CloudTrail for audit purposes
- IAM policies support compliance reporting
- Approval workflows maintain audit trails

## Customization

### Adding Custom Quality Checks
Modify the quality gate Lambda function to include additional checks:

```python
def run_custom_quality_check(repo_content):
    """Add your custom quality validation logic"""
    # Example: Check for specific file patterns
    # Example: Validate documentation completeness
    # Example: Check for security patterns
    pass
```

### Custom Notification Channels
Add additional notification endpoints:

```bash
# Add Slack webhook
aws sns subscribe \
    --topic-arn {topic-arn} \
    --protocol https \
    --notification-endpoint https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK

# Add Microsoft Teams webhook
aws sns subscribe \
    --topic-arn {topic-arn} \
    --protocol https \
    --notification-endpoint https://your-tenant.webhook.office.com/webhookb2/YOUR/TEAMS/WEBHOOK
```

### Branch Strategy Customization
Modify approval rules for different branch strategies:

```json
{
  "Version": "2018-11-08",
  "DestinationReferences": ["refs/heads/main", "refs/heads/release/*"],
  "Statements": [{
    "Type": "Approvers",
    "NumberOfApprovalsNeeded": 3,
    "ApprovalPoolMembers": ["arn:aws:iam::ACCOUNT:user/architect"]
  }]
}
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name codecommit-git-workflows

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name codecommit-git-workflows

# Verify deletion
aws cloudformation describe-stacks --stack-name codecommit-git-workflows
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy --force

# Verify resources are deleted
cdk list
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy -auto-approve

# Verify state is clean
terraform show
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

### Manual Cleanup (if needed)
```bash
# List and delete any remaining CodeCommit repositories
aws codecommit list-repositories
aws codecommit delete-repository --repository-name {repository-name}

# Clean up any remaining Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `codecommit-automation`)].FunctionName'

# Remove any remaining SNS topics
aws sns list-topics --query 'Topics[?contains(TopicArn, `codecommit-notifications`)].TopicArn'

# Delete CloudWatch dashboards
aws cloudwatch list-dashboards --query 'DashboardEntries[?contains(DashboardName, `Git-Workflow`)].DashboardName'
```

## Cost Optimization

### Resource Usage
- Lambda functions only execute on repository events (pay-per-execution)
- SNS charges apply per message delivery
- CloudWatch charges for custom metrics and dashboard widgets
- CodeCommit charges per active user and repository storage

### Estimated Monthly Costs
- Small team (5 developers): $10-20/month
- Medium team (20 developers): $30-50/month
- Large team (50+ developers): $75-150/month

### Cost Reduction Tips
```bash
# Monitor Lambda execution costs
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE

# Optimize CloudWatch log retention
aws logs put-retention-policy \
    --log-group-name "/aws/lambda/codecommit-automation-{suffix}-pull-request" \
    --retention-in-days 7

# Use CloudWatch Insights for efficient log analysis
aws logs start-query \
    --log-group-name "/aws/lambda/codecommit-automation-{suffix}-quality-gate" \
    --start-time $(date -d '7 days ago' +%s) \
    --end-time $(date +%s) \
    --query-string 'fields @timestamp, @message | filter @message like /ERROR/'
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file for implementation details
2. **AWS Documentation**: Consult [AWS CodeCommit User Guide](https://docs.aws.amazon.com/codecommit/latest/userguide/)
3. **Lambda Documentation**: Review [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
4. **EventBridge Documentation**: Check [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
5. **Terraform AWS Provider**: Reference [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

For advanced configuration questions, consider engaging with AWS support or consulting the AWS developer community forums.

## Version Information

- **Recipe Version**: 1.2
- **Last Updated**: 2025-07-12
- **CDK Version**: ^2.120.0 (TypeScript), ^2.120.0 (Python)
- **Terraform Version**: >= 1.0
- **AWS Provider Version**: >= 5.0
- **CloudFormation**: Latest API Version