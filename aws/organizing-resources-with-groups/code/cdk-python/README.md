# AWS CDK Python - Resource Groups Automated Management

This directory contains the AWS CDK Python implementation for automated resource management using AWS Resource Groups, Systems Manager, CloudWatch, and SNS.

## Overview

This CDK application creates infrastructure to:
- Organize AWS resources using tag-based Resource Groups
- Automate resource management tasks with Systems Manager
- Monitor resource health and costs with CloudWatch
- Send notifications through SNS for alerts and budget thresholds
- Implement automated resource tagging workflows

## Architecture Components

- **Resource Groups**: Tag-based resource organization
- **Systems Manager**: Automation documents for maintenance tasks
- **CloudWatch**: Monitoring dashboards, alarms, and logging
- **SNS**: Notification system for alerts
- **IAM**: Roles and policies for automation
- **AWS Budgets**: Cost monitoring and alerting
- **EventBridge**: Automated resource tagging triggers

## Prerequisites

1. **AWS CLI**: Installed and configured with appropriate permissions
2. **AWS CDK**: Installed globally (`npm install -g aws-cdk`)
3. **Python**: Version 3.8 or higher
4. **pip**: Python package installer

### Required AWS Permissions

Your AWS credentials must have permissions for:
- Resource Groups (create, manage)
- Systems Manager (automation, documents)
- CloudWatch (dashboards, alarms, logs)
- SNS (topics, subscriptions)
- IAM (roles, policies)
- AWS Budgets (budget management)
- EventBridge (rules, targets)
- Cost Explorer (anomaly detection)

## Installation

1. **Clone or navigate to this directory**:
   ```bash
   cd aws/resource-groups-automated-resource-management/code/cdk-python/
   ```

2. **Create and activate a Python virtual environment**:
   ```bash
   # Create virtual environment
   python -m venv .venv
   
   # Activate virtual environment
   # On macOS/Linux:
   source .venv/bin/activate
   # On Windows:
   .venv\Scripts\activate
   ```

3. **Install Python dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK** (if not already done):
   ```bash
   cdk bootstrap
   ```

## Configuration

The application supports configuration through environment variables:

### Required Configuration
```bash
# Set your AWS account and region
export CDK_DEFAULT_ACCOUNT="123456789012"
export CDK_DEFAULT_REGION="us-east-1"
```

### Optional Configuration
```bash
# Environment name for resource tagging (default: production)
export ENVIRONMENT_NAME="production"

# Application name for resource tagging (default: web-app)
export APPLICATION_NAME="web-app"

# Email address for SNS notifications (highly recommended)
export NOTIFICATION_EMAIL="admin@example.com"

# Monthly budget limit in USD (default: 100.0)
export MONTHLY_BUDGET_LIMIT="100.0"
```

## Deployment

1. **Validate the CDK code** (optional but recommended):
   ```bash
   cdk synth
   ```

2. **Preview the deployment**:
   ```bash
   cdk diff
   ```

3. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

   The deployment will:
   - Create all necessary AWS resources
   - Apply security best practices with CDK Nag
   - Set up monitoring and alerting
   - Configure automated workflows

4. **Confirm email subscription** (if configured):
   - Check your email for SNS subscription confirmation
   - Click the confirmation link to receive notifications

## Usage

After deployment, the system will automatically:

1. **Organize Resources**: Any resources tagged with your Environment and Application values will be included in the Resource Group
2. **Monitor Performance**: CloudWatch dashboards and alarms will track resource health
3. **Track Costs**: Budgets and anomaly detection will monitor spending
4. **Send Alerts**: SNS will notify you of performance issues or budget concerns
5. **Automate Tagging**: New resources will be automatically tagged through EventBridge

### Viewing Resources

1. **Resource Group**: Visit the AWS Resource Groups console to view organized resources
2. **CloudWatch Dashboard**: View performance metrics and cost information
3. **Systems Manager**: Review automation execution history
4. **Budget Alerts**: Monitor spending in the AWS Budgets console

### Manual Operations

Execute Systems Manager automation manually:
```bash
# Get the automation document ARN from CloudFormation outputs
aws ssm start-automation-execution \
    --document-name "ResourceGroupMaintenance-production" \
    --parameters "ResourceGroupName=production-web-app-resources"
```

## Customization

### Modifying Resource Selection

Edit the `resource_query` in `_create_resource_group()` method to change which resources are included:

```python
resource_query = {
    "type": "TAG_FILTERS_1_0",
    "query": {
        "resourceTypeFilters": ["AWS::AllSupported"],  # Or specific types
        "tagFilters": [
            {
                "key": "Environment",
                "values": [self.environment_name]
            },
            # Add more tag filters as needed
        ]
    }
}
```

### Adding Custom Automation

Create additional Systems Manager documents in the `_create_ssm_automation()` method:

```python
custom_document = ssm.CfnDocument(
    self,
    "CustomAutomationDoc",
    document_type="Automation",
    document_format="YAML",
    name="CustomAutomation",
    content={
        "schemaVersion": "0.3",
        "description": "Custom automation task",
        # Add your automation steps here
    }
)
```

### Extending Monitoring

Add custom CloudWatch metrics and alarms in the `_create_cloudwatch_monitoring()` method.

## Security Features

This implementation includes several security best practices:

1. **IAM Least Privilege**: Roles have minimal required permissions
2. **Encryption**: SNS topics use AWS managed KMS keys
3. **Regional Scoping**: IAM policies are scoped to the current region
4. **CDK Nag Integration**: Automated security rule checking
5. **Resource Tagging**: All resources are tagged for governance

### CDK Nag Suppressions

Some CDK Nag warnings are suppressed with justification:
- Wildcard IAM permissions for resource group operations (region-scoped)
- AWS managed KMS keys for SNS encryption
- CloudWatch Logs encryption for development environments

## Troubleshooting

### Common Issues

1. **Email not receiving notifications**:
   - Check spam folder
   - Confirm SNS subscription in the AWS console
   - Verify email address in configuration

2. **CDK deployment fails**:
   - Ensure AWS credentials are properly configured
   - Check AWS account limits and quotas
   - Verify required permissions

3. **Resource Group appears empty**:
   - Ensure existing resources have the correct tags
   - Wait a few minutes for resource discovery
   - Check tag key/value spelling

### Debug Commands

```bash
# View CloudFormation events
aws cloudformation describe-stack-events --stack-name ResourceGroupManagement-production

# Check Systems Manager automation executions
aws ssm describe-automation-executions --filter Key=DocumentName,Values=ResourceGroupMaintenance-production

# View Resource Group resources
aws resource-groups list-group-resources --group-name production-web-app-resources
```

## Cleanup

To remove all created resources:

```bash
cdk destroy
```

This will:
- Delete all AWS resources created by the stack
- Remove CloudFormation stack
- Clean up associated resources

**Note**: Some resources like S3 buckets or RDS snapshots may require manual deletion if they contain data.

## Development

### Running Tests

```bash
# Install development dependencies
pip install -e .[dev]

# Run tests
pytest

# Run tests with coverage
pytest --cov=.

# Code formatting
black .

# Linting
flake8 .

# Type checking
mypy .
```

### Code Structure

```
cdk-python/
├── app.py                    # Main CDK application and stack definition
├── requirements.txt          # Python dependencies
├── setup.py                 # Package configuration
├── cdk.json                 # CDK configuration
├── README.md                # This documentation
└── .venv/                   # Virtual environment (created during setup)
```

## Cost Optimization

This solution includes several cost optimization features:

1. **Budget Alerts**: Proactive notifications when spending exceeds thresholds
2. **Cost Anomaly Detection**: Automatic detection of unusual spending patterns
3. **Resource Tagging**: Enable cost allocation and chargeback tracking
4. **Rightsizing Insights**: CloudWatch metrics to identify underutilized resources

Estimated monthly costs:
- CloudWatch dashboards: ~$3/month
- SNS notifications: <$1/month (typical usage)
- Systems Manager: Free tier covers most usage
- Resource Groups: Free
- **Total estimated cost**: $5-15/month depending on usage

## Support

For issues with this CDK implementation:

1. **CDK Issues**: Check the [AWS CDK GitHub repository](https://github.com/aws/aws-cdk)
2. **AWS Service Issues**: Refer to AWS documentation for specific services
3. **Recipe Questions**: Review the original recipe documentation

## Contributing

To contribute improvements:

1. Test changes thoroughly in a development environment
2. Follow Python and CDK best practices
3. Update documentation as needed
4. Ensure CDK Nag checks pass
5. Add appropriate unit tests

## License

This code is provided under the MIT License. See the LICENSE file for details.