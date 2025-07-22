# Infrastructure Automation CDK Python Application

This AWS CDK Python application creates the infrastructure for automating infrastructure management using AWS CloudShell PowerShell scripts integrated with Systems Manager, Lambda, and CloudWatch monitoring.

## Architecture Overview

This CDK application deploys:

- **IAM Role**: Execution role for automation with necessary permissions
- **CloudWatch Log Group**: Centralized logging for automation execution
- **SNS Topic**: Notifications for automation alerts and failures  
- **Systems Manager Automation Document**: PowerShell-based infrastructure health checks
- **Lambda Function**: Orchestration layer for automation execution
- **EventBridge Rule**: Scheduled execution (daily at 6 AM UTC)
- **CloudWatch Monitoring**: Dashboards, alarms, and metrics for operational visibility

## Prerequisites

- AWS CLI configured with appropriate credentials
- Python 3.8 or later
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for creating IAM roles, Lambda functions, and other resources

## Installation

1. **Clone and navigate to the directory**:
   ```bash
   cd aws/automating-infrastructure-management-cloudshell-powershell/code/cdk-python/
   ```

2. **Create and activate a virtual environment**:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK (if first time using CDK in this account/region)**:
   ```bash
   cdk bootstrap
   ```

## Deployment

1. **Synthesize CloudFormation template** (optional, for validation):
   ```bash
   cdk synth
   ```

2. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

3. **Deploy with custom parameters**:
   ```bash
   cdk deploy --parameters EnvironmentSuffix=prod
   ```

## Configuration

### Parameters

- **EnvironmentSuffix**: Suffix added to resource names for uniqueness (default: "dev")

### Environment Variables

You can customize the deployment by setting CDK context variables:

```bash
# Deploy to specific account and region
cdk deploy -c account=123456789012 -c region=us-west-2
```

## Usage

### Manual Testing

After deployment, you can manually trigger the automation:

```bash
# Get the Lambda function name from outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
  --stack-name InfrastructureAutomationStack \
  --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionArn`].OutputValue' \
  --output text | cut -d':' -f7)

# Invoke the Lambda function
aws lambda invoke \
  --function-name $FUNCTION_NAME \
  --payload '{}' \
  response.json

cat response.json
```

### Monitoring

Access the CloudWatch dashboard created by this stack to monitor:
- Automation execution metrics
- Error rates and trends  
- Recent automation logs
- System health insights

### Scheduled Execution

The automation runs automatically every day at 6 AM UTC via EventBridge. You can modify the schedule by updating the `schedule` property in the `_create_schedule_rule` method.

## Security Considerations

This CDK application implements several security best practices:

- **Least Privilege IAM**: IAM roles with minimal required permissions
- **Encryption**: CloudWatch Logs encrypted by default
- **Resource Isolation**: Resources tagged and organized by environment
- **Secure Communications**: All AWS service communications use TLS

### Security Notes

- The IAM role includes managed policies for simplicity in this example
- For production use, replace managed policies with custom policies following least privilege
- Consider enabling AWS CloudTrail for audit logging
- Review and adjust resource-level permissions based on your specific requirements

## Customization

### Adding Resource Types

To extend the PowerShell health checks to additional AWS resource types:

1. Update the PowerShell script in `_create_automation_document` method
2. Add necessary IAM permissions to the custom policy in `_create_automation_role`
3. Test the updated automation document

### Modifying Schedule

To change the execution schedule:

1. Update the `schedule` parameter in `_create_schedule_rule` method
2. Use EventBridge cron expressions for complex scheduling needs

### Enhanced Monitoring

To add custom metrics or alarms:

1. Extend the `_create_monitoring` method
2. Add custom CloudWatch metrics in the Lambda function
3. Create additional alarms based on business requirements

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure your AWS credentials have sufficient permissions
2. **CDK Bootstrap**: Run `cdk bootstrap` if you encounter deployment errors
3. **Region Availability**: Some services may not be available in all regions

### Debugging

- Check CloudWatch Logs for automation execution details
- Use `cdk diff` to see changes before deployment
- Review Systems Manager automation execution history
- Monitor CloudWatch metrics for execution patterns

## Cleanup

To remove all resources created by this stack:

```bash
cdk destroy
```

**Warning**: This will delete all resources including CloudWatch logs and metrics data.

## Development

### Code Structure

- `app.py`: Main CDK application and stack definition
- `requirements.txt`: Python dependencies
- `cdk.json`: CDK configuration and feature flags
- `setup.py`: Python package configuration

### Best Practices

- Follow [CDK Best Practices](https://docs.aws.amazon.com/cdk/v2/guide/best-practices.html)
- Use CDK Nag for security compliance checking
- Implement proper error handling in Lambda functions
- Add comprehensive unit tests for production use

### Testing

```bash
# Install development dependencies
pip install -r requirements.txt

# Run tests (when implemented)
pytest

# Format code
black .

# Lint code
flake8

# Type checking
mypy .
```

## References

- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [AWS Systems Manager Automation](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-automation.html)
- [AWS CloudShell User Guide](https://docs.aws.amazon.com/cloudshell/latest/userguide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)

## Support

For issues with this CDK application:
1. Check the troubleshooting section above
2. Review AWS CloudFormation events in the AWS Console
3. Check CloudWatch Logs for detailed error messages
4. Refer to the original recipe documentation