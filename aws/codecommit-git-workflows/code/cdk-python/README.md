# CDK Python - CodeCommit Git Workflows with Branch Policies and Triggers

This directory contains a comprehensive CDK Python application that implements enterprise Git workflows with automated quality gates, branch protection policies, and event-driven automation for AWS CodeCommit repositories.

## Overview

The CDK application creates:

- **CodeCommit Repository** with structured Git workflow support
- **Lambda Functions** for pull request automation, quality gate enforcement, and branch protection
- **SNS Topics** for different notification types (pull requests, merges, quality gates, security alerts)
- **EventBridge Rules** for event-driven automation
- **CloudWatch Dashboard** for monitoring workflow metrics
- **IAM Roles and Policies** with least privilege access

## Architecture

The solution implements a comprehensive Git workflow automation system:

1. **Pull Request Automation**: Validates PR formatting, branch naming, and approval requirements
2. **Quality Gate Enforcement**: Runs automated code quality checks including linting, security scanning, and test coverage
3. **Branch Protection**: Ensures consistent protection policies across all protected branches
4. **Monitoring & Notifications**: Provides real-time visibility and alerts for all workflow activities

## Prerequisites

- Python 3.8 or higher
- AWS CLI v2 installed and configured
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for CodeCommit, Lambda, SNS, EventBridge, and CloudWatch

## Quick Start

1. **Install Dependencies**:
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   pip install -r requirements.txt
   ```

2. **Configure the Application**:
   ```bash
   # Set your AWS account and region
   export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
   export CDK_DEFAULT_REGION=$(aws configure get region)
   ```

3. **Customize Configuration** (Optional):
   ```bash
   # Create cdk.context.json for custom configuration
   cat > cdk.context.json << EOF
   {
     "repository_name": "my-enterprise-app",
     "repository_description": "My enterprise application with Git workflows",
     "team_lead_user": "john.smith",
     "senior_developers": ["alice.johnson", "bob.wilson"],
     "environment": "development",
     "notification_email": "team@example.com",
     "enable_email_notifications": "true"
   }
   EOF
   ```

4. **Deploy the Application**:
   ```bash
   # Bootstrap CDK (first time only)
   cdk bootstrap
   
   # Deploy the stack
   cdk deploy
   ```

## Configuration Options

The application supports various configuration options through CDK context:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `repository_name` | Name of the CodeCommit repository | "enterprise-app" |
| `repository_description` | Repository description | "Enterprise application with Git workflow automation" |
| `team_lead_user` | Username of team lead for approvals | "team-lead" |
| `senior_developers` | List of senior developer usernames | ["senior-dev-1", "senior-dev-2"] |
| `environment` | Environment name for tagging | "development" |
| `notification_email` | Email for notifications | None |
| `enable_monitoring` | Create CloudWatch dashboard | "true" |
| `enable_email_notifications` | Set up email subscriptions | "false" |

## Lambda Functions

### Pull Request Automation (`pull_request_automation.py`)

Handles CodeCommit pull request events:
- Validates branch naming conventions
- Checks pull request title formatting
- Ensures proper target branch selection
- Sends notifications for PR lifecycle events
- Records metrics for monitoring

### Quality Gate Automation (`quality_gate_automation.py`)

Implements comprehensive quality checks:
- Code linting and style validation
- Security vulnerability scanning
- Test coverage analysis
- Dependency vulnerability checking
- Automated notifications for quality gate results

### Branch Protection (`branch_protection.py`)

Enforces branch protection policies:
- Monitors approval rule template associations
- Validates branch protection settings
- Ensures compliance with enterprise policies
- Records compliance metrics

## Monitoring

The CloudWatch dashboard provides visibility into:

- **Pull Request Activity**: Creation, merge, and closure rates
- **Quality Gate Success Rates**: Overall and individual check results
- **Branch Protection Compliance**: Template associations and policy enforcement
- **Event Logs**: Detailed activity logs for troubleshooting

## Notifications

The system provides four types of notifications:

1. **Pull Request Notifications**: New PRs, updates, and status changes
2. **Merge Notifications**: Successful merge operations
3. **Quality Gate Alerts**: Failed quality checks and validation results
4. **Security Alerts**: Security vulnerabilities and compliance issues

## Usage Examples

### Basic Deployment

```bash
# Deploy with default configuration
cdk deploy
```

### Custom Configuration

```bash
# Deploy with custom repository name and team settings
cdk deploy \
  --context repository_name=my-project \
  --context team_lead_user=alice.smith \
  --context senior_developers='["bob.jones","carol.white"]'
```

### Enable Email Notifications

```bash
# Deploy with email notifications enabled
cdk deploy \
  --context notification_email=team@example.com \
  --context enable_email_notifications=true
```

## Development

### Running Tests

```bash
# Install development dependencies
pip install -e ".[dev]"

# Run tests
pytest tests/

# Run tests with coverage
pytest --cov=codecommit_git_workflows tests/
```

### Code Quality

```bash
# Format code
black codecommit_git_workflows/

# Lint code
pylint codecommit_git_workflows/

# Type checking
mypy codecommit_git_workflows/
```

### Local Development

```bash
# Synthesize CloudFormation template
cdk synth

# Compare deployed stack with current state
cdk diff

# Deploy specific stack
cdk deploy CodeCommitGitWorkflowsStack
```

## Troubleshooting

### Common Issues

1. **Lambda Function Permissions**: Ensure the execution role has proper permissions for CodeCommit, SNS, and CloudWatch
2. **Repository Access**: Verify that the repository exists and is accessible
3. **EventBridge Rules**: Check that EventBridge rules are properly configured and active
4. **SNS Subscriptions**: Confirm email subscriptions if notifications are not received

### Logs and Debugging

```bash
# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/CodeCommitGitWorkflowsStack"

# Get recent pull request events
aws logs filter-log-events \
  --log-group-name "/aws/lambda/CodeCommitGitWorkflowsStack-PullRequestAutomationFunction" \
  --filter-pattern "Pull request"
```

## Cleanup

To remove all resources:

```bash
# Delete the stack
cdk destroy

# Confirm deletion
# Type 'y' when prompted
```

## Security Considerations

- **IAM Policies**: All roles follow least privilege principle
- **Encryption**: SNS topics support encryption at rest
- **Access Control**: Repository access controlled through IAM and CodeCommit permissions
- **Audit Trail**: All actions logged to CloudWatch for compliance

## Cost Considerations

Estimated monthly costs for typical usage:

- **Lambda Execution**: $5-15 (based on event frequency)
- **SNS Messages**: $1-5 (based on notification volume)
- **CloudWatch Logs**: $2-8 (based on log retention)
- **EventBridge Events**: <$1 (minimal cost for events)

Total estimated cost: $8-29 per month for a typical development team.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## License

This project is licensed under the Apache 2.0 License - see the LICENSE file for details.

## Support

For issues and questions:

1. Check the troubleshooting section above
2. Review CloudWatch logs for detailed error information
3. Consult AWS CodeCommit documentation for service-specific issues
4. Open an issue in the project repository