# Infrastructure Automation with CloudShell PowerShell - CDK TypeScript

This CDK TypeScript application deploys a serverless infrastructure automation framework that integrates AWS CloudShell PowerShell environment with enterprise automation services.

## Architecture Overview

The solution creates:
- **AWS CloudShell Integration**: Pre-configured PowerShell environment for script development
- **Systems Manager Automation**: Enterprise-grade workflow orchestration with PowerShell Core 6.0
- **Lambda Orchestration**: Serverless function for automation scheduling and event handling
- **EventBridge Scheduling**: Cron-based scheduling for automated execution
- **CloudWatch Monitoring**: Comprehensive logging, metrics, and alerting
- **SNS Notifications**: Real-time alerts for automation events and errors

## Key Features

- ✅ **Zero Infrastructure Setup**: No local development environment required
- ✅ **Enterprise Security**: IAM roles with least-privilege permissions
- ✅ **Automated Scheduling**: Configurable cron-based execution
- ✅ **Comprehensive Monitoring**: CloudWatch dashboards and alarms
- ✅ **Error Handling**: Automatic error detection and notification
- ✅ **Scalable Design**: Serverless architecture with automatic scaling

## Prerequisites

- AWS CLI configured with appropriate permissions
- Node.js 18+ and npm installed
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for CDK deployment

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure AWS Environment

```bash
# Configure AWS CLI if not already done
aws configure

# Bootstrap CDK (first time only)
cdk bootstrap
```

### 3. Deploy the Stack

```bash
# Synthesize CloudFormation template (recommended first step)
cdk synth

# Deploy the infrastructure
cdk deploy

# Deploy with email notifications (optional)
cdk deploy --parameters notificationEmail=your-email@example.com
```

### 4. Access CloudShell for PowerShell Development

After deployment, use the CloudShell URL from the stack outputs to access the pre-configured PowerShell environment.

## Configuration Options

The stack supports several configuration options:

```typescript
new InfrastructureAutomationStack(app, 'InfrastructureAutomationStack', {
  // Optional email for alert notifications
  notificationEmail: 'admin@example.com',
  
  // Custom schedule (default: daily at 6 AM UTC)
  scheduleExpression: 'cron(0 6 * * ? *)',
  
  // Log retention period (default: 1 month)
  logRetention: logs.RetentionDays.ONE_MONTH,
});
```

## Usage

### Developing PowerShell Scripts

1. Access AWS CloudShell using the URL from stack outputs
2. Develop PowerShell automation scripts using the pre-installed AWS Tools
3. Test scripts interactively in the CloudShell environment
4. Scripts are automatically executed according to the configured schedule

### Monitoring Automation

- **CloudWatch Dashboard**: Monitor automation execution metrics and performance
- **CloudWatch Logs**: View detailed logs from PowerShell script execution
- **CloudWatch Alarms**: Automatic alerts for errors or failures
- **SNS Notifications**: Email alerts for critical events

### Customizing Automation

The Systems Manager Automation Document can be customized by modifying the PowerShell script in the stack. The current implementation includes:

- EC2 instance health assessment
- S3 bucket compliance checking
- Structured logging to CloudWatch
- Error handling and reporting

## Architecture Components

### IAM Role (`AutomationRole`)
- Permissions for Systems Manager, Lambda, EC2, S3, and CloudWatch
- Least-privilege access with resource-specific conditions
- Shared across Lambda and Systems Manager services

### Lambda Function (`OrchestrationFunction`)
- Orchestrates automation document execution
- Publishes CloudWatch metrics for monitoring
- Sends SNS notifications for errors
- 5-minute timeout with 256MB memory allocation

### Systems Manager Document (`InfrastructureHealthCheck`)
- PowerShell Core 6.0 runtime environment
- Parameterized execution with region and log group configuration
- Comprehensive health check and compliance assessment
- Structured JSON output for parsing and analysis

### EventBridge Rule
- Configurable cron-based scheduling
- Targets Lambda function for orchestration
- Default: Daily execution at 6 AM UTC

### CloudWatch Resources
- Log Group: `/aws/automation/infrastructure-health`
- Custom metrics namespace: `Infrastructure/Automation`
- Alarms for error detection and notification
- Dashboard for performance monitoring

## Monitoring and Alerting

### CloudWatch Metrics
- `AutomationExecutions`: Count of successful automation runs
- `AutomationErrors`: Count of failed automation runs
- Lambda function metrics (invocations, duration, errors)

### CloudWatch Alarms
- Automation error threshold (≥1 error in 5 minutes)
- Lambda function error threshold (≥1 error in 5 minutes)
- SNS notification for all alarm states

### Dashboard Widgets
- Automation execution trends over time
- Error rate monitoring
- Lambda function performance metrics
- Log stream analysis

## Security Considerations

- **Least Privilege IAM**: Minimal required permissions with resource conditions
- **Encryption**: CloudWatch Logs encrypted at rest
- **Network Security**: No public network access required
- **Secrets Management**: No hardcoded credentials or secrets
- **Audit Logging**: Comprehensive CloudTrail integration

## Cost Optimization

- **Serverless Architecture**: Pay only for execution time
- **Efficient Scheduling**: Configurable execution frequency
- **Log Retention**: Configurable retention period for cost control
- **Resource Tagging**: Cost allocation and tracking support

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   - Verify IAM permissions for deployment
   - Ensure CDK bootstrap has been completed
   - Check AWS CLI configuration

2. **PowerShell Module Import Failures**
   - Systems Manager automatically handles AWS Tools installation
   - Module import is included in the PowerShell script
   - CloudWatch Logs will show specific import errors

3. **Automation Document Execution Failures**
   - Check CloudWatch Logs for detailed error messages
   - Verify IAM role permissions for target resources
   - Review automation document parameters

### Debugging Steps

```bash
# View CloudFormation stack events
aws cloudformation describe-stack-events --stack-name InfrastructureAutomationStack

# Check automation execution status
aws ssm describe-automation-executions --filters "Key=DocumentNamePrefix,Values=InfrastructureHealthCheck"

# View Lambda function logs
aws logs tail /aws/lambda/infrastructure-automation-orchestrator --follow

# Check automation logs
aws logs tail /aws/automation/infrastructure-health --follow
```

## Cleanup

To remove all resources:

```bash
cdk destroy
```

This will delete:
- All AWS resources created by the stack
- CloudWatch Logs data (based on retention policy)
- SNS topic and subscriptions
- EventBridge rules and targets

**Note**: Some resources like CloudWatch Logs may have retention policies that preserve data beyond stack deletion.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes following TypeScript and CDK best practices
4. Test changes with `cdk synth` and `cdk deploy`
5. Submit a pull request

## License

This code is licensed under the MIT-0 License. See LICENSE file for details.

## Support

For issues and questions:
- Review CloudWatch Logs for detailed error information
- Check AWS documentation for service-specific guidance
- Submit issues via GitHub repository