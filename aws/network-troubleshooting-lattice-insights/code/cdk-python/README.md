# Network Troubleshooting VPC Lattice with Network Insights - CDK Python

This CDK Python application deploys a comprehensive network troubleshooting platform that combines VPC Lattice service mesh monitoring with automated path analysis and proactive alerting.

## Architecture Overview

The solution creates:

- **VPC Lattice Service Network**: Application-level networking for service-to-service communication
- **Test EC2 Infrastructure**: Test instances and security groups for connectivity analysis
- **CloudWatch Monitoring**: Dashboard, alarms, and logging for real-time visibility
- **SNS Alerting**: Topic for network alerts and notifications
- **Lambda Automation**: Function for automated response to network issues
- **Systems Manager Automation**: Document for VPC Reachability Analyzer integration
- **IAM Roles**: Secure permissions for automation and troubleshooting workflows

## Prerequisites

- AWS CLI v2 installed and configured
- Python 3.9 or later
- Node.js 14.x or later (for CDK CLI)
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for all services used

## Quick Start

### 1. Install Dependencies

```bash
# Install Python dependencies
pip install -r requirements.txt

# Verify CDK installation
cdk version
```

### 2. Bootstrap CDK (if not done previously)

```bash
cdk bootstrap
```

### 3. Deploy the Stack

```bash
# Deploy with default settings
cdk deploy

# Deploy with custom stack name
cdk deploy --context stack_name=MyNetworkTroubleshooting

# Deploy with specific account/region
cdk deploy --context account=123456789012 --context region=us-west-2
```

### 4. Verify Deployment

After deployment, you can verify the resources using the AWS CLI:

```bash
# Check VPC Lattice service network
aws vpc-lattice list-service-networks

# Check CloudWatch dashboard
aws cloudwatch list-dashboards

# Check Systems Manager automation document
aws ssm list-documents --filters "Key=Name,Values=NetworkReachabilityAnalysis*"
```

## Usage

### Testing Network Connectivity

1. **Manual Testing**: Use the Systems Manager automation document to manually trigger network analysis
2. **Automated Response**: CloudWatch alarms will automatically trigger troubleshooting when network issues are detected
3. **Dashboard Monitoring**: View real-time metrics and performance data in the CloudWatch dashboard

### Customization

The application can be customized through CDK context values:

```bash
# Deploy with custom values
cdk deploy \
  --context stack_name=CustomNetworkStack \
  --context account=123456789012 \
  --context region=us-east-1
```

### Environment Variables

The Lambda function uses these environment variables (automatically configured):

- `AUTOMATION_ROLE_ARN`: IAM role for Systems Manager automation
- `DEFAULT_INSTANCE_ID`: Test EC2 instance ID for connectivity testing
- `DOCUMENT_NAME`: Systems Manager automation document name

## Stack Outputs

The stack provides these outputs for integration:

- `ServiceNetworkId`: VPC Lattice Service Network ID
- `ServiceNetworkArn`: VPC Lattice Service Network ARN
- `TestInstanceId`: Test EC2 Instance ID
- `SecurityGroupId`: Test Security Group ID
- `SNSTopicArn`: SNS Topic ARN for alerts
- `DashboardName`: CloudWatch Dashboard name
- `LambdaFunctionName`: Troubleshooting Lambda function name
- `AutomationDocumentName`: Systems Manager automation document name
- `AutomationRoleArn`: IAM role ARN for automation
- `LogGroupName`: CloudWatch log group for VPC Lattice logs

## Development

### Running Tests

```bash
# Install development dependencies
pip install -e .[dev]

# Run tests (when available)
pytest tests/

# Type checking
mypy app.py

# Code formatting
black app.py

# Linting
flake8 app.py
```

### CDK Commands

- `cdk ls`: List all stacks in the app
- `cdk synth`: Emit the synthesized CloudFormation template
- `cdk deploy`: Deploy this stack to your default AWS account/region
- `cdk diff`: Compare deployed stack with current state
- `cdk destroy`: Destroy the deployed stack

## Cost Considerations

The deployed resources incur costs for:

- EC2 t3.micro instance (eligible for free tier)
- VPC Lattice service network usage
- CloudWatch dashboard, alarms, and log storage
- Lambda function invocations
- Systems Manager automation executions

Estimated monthly cost: $10-30 depending on usage patterns.

## Security

The application follows AWS security best practices:

- **Least Privilege IAM**: Roles have minimal necessary permissions
- **Encryption**: CloudWatch logs encrypted at rest
- **Network Security**: Security groups restrict access to necessary ports
- **Secure Defaults**: All services configured with secure default settings

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Error**: Ensure your AWS account is bootstrapped for CDK
2. **Permission Denied**: Verify your AWS credentials have sufficient permissions
3. **Resource Limits**: Check AWS service quotas if deployment fails
4. **VPC Lattice Availability**: Ensure VPC Lattice is available in your region

### Logs and Monitoring

- Lambda function logs: CloudWatch Logs group `/aws/lambda/network-troubleshooting-*`
- VPC Lattice logs: CloudWatch Logs group `/aws/vpclattice/servicenetwork/*`
- Automation execution logs: Systems Manager console

## Cleanup

To remove all resources and avoid ongoing charges:

```bash
cdk destroy
```

This will remove all AWS resources created by the stack.

## Support

For issues with this CDK application:

1. Check the [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
2. Review [VPC Lattice documentation](https://docs.aws.amazon.com/vpc-lattice/)
3. Consult the original recipe documentation
4. Check AWS service status for any ongoing issues

## Contributing

To contribute to this CDK application:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.