# Security Compliance Auditing with VPC Lattice and GuardDuty - CDK TypeScript

This CDK TypeScript application deploys a comprehensive security compliance auditing system that continuously monitors VPC Lattice access logs, integrates with GuardDuty threat intelligence, and generates real-time compliance reports.

## Architecture

The solution creates the following AWS resources:

- **GuardDuty Detector**: Provides intelligent threat detection using machine learning and threat intelligence
- **S3 Bucket**: Stores compliance reports with encryption and lifecycle policies
- **CloudWatch Log Group**: Collects VPC Lattice access logs
- **Lambda Function**: Processes security logs, correlates with GuardDuty findings, and generates alerts
- **SNS Topic**: Sends real-time security alerts via email
- **CloudWatch Dashboard**: Provides security monitoring visualization
- **VPC Lattice Service Network**: Demo configuration for testing (optional)
- **Log Subscription Filter**: Triggers real-time processing of access logs

## Prerequisites

- AWS CLI installed and configured
- Node.js 18.x or later
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for deploying the stack resources

## Installation

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK (if not already done)**:
   ```bash
   cdk bootstrap
   ```

3. **Configure email for alerts** (optional):
   ```bash
   # Set your email in cdk.json context or use CLI parameter
   cdk deploy -c emailForAlerts=your-email@company.com
   ```

## Deployment

### Quick Deploy

```bash
# Deploy with default settings
npm run deploy
```

### Custom Configuration

```bash
# Deploy with custom email and disable demo VPC Lattice
cdk deploy \
  -c emailForAlerts=security-team@yourcompany.com \
  -c enableVpcLatticeDemo=false \
  -c environment=production
```

### Environment-Specific Deployment

```bash
# Development environment
cdk deploy -c environment=dev

# Production environment
cdk deploy -c environment=prod -c emailForAlerts=security-ops@company.com
```

## Configuration

The stack accepts the following context parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `emailForAlerts` | `security-admin@yourcompany.com` | Email address for security alerts |
| `enableVpcLatticeDemo` | `true` | Create demo VPC Lattice service network |
| `environment` | `demo` | Environment tag for resources |

### Setting Configuration

1. **Via cdk.json**:
   ```json
   {
     "context": {
       "emailForAlerts": "your-email@company.com",
       "enableVpcLatticeDemo": true,
       "environment": "production"
     }
   }
   ```

2. **Via command line**:
   ```bash
   cdk deploy -c emailForAlerts=your-email@company.com
   ```

3. **Via environment variables**:
   ```bash
   export CDK_DEFAULT_REGION=us-west-2
   export CDK_DEFAULT_ACCOUNT=123456789012
   cdk deploy
   ```

## Usage

### Monitoring Security Events

1. **CloudWatch Dashboard**: Access the security dashboard via the output URL
2. **S3 Compliance Reports**: Review detailed reports in the S3 bucket
3. **SNS Alerts**: Receive real-time notifications via email
4. **Lambda Logs**: Monitor processing details in CloudWatch Logs

### Testing the System

1. **Generate sample VPC Lattice logs** (if demo network is enabled)
2. **Simulate security events** by creating test traffic patterns
3. **Verify alert generation** through SNS notifications
4. **Review compliance reports** in S3

### Customizing Security Rules

Modify the Lambda function code in `lib/lambda/security-processor/security_processor.py` to:

- Add custom threat detection rules
- Adjust risk scoring algorithms
- Implement additional correlation logic
- Integrate with external security tools

## Available Scripts

- `npm run build`: Compile TypeScript to JavaScript
- `npm run watch`: Watch for changes and recompile
- `npm run test`: Run unit tests
- `npm run deploy`: Deploy the stack
- `npm run destroy`: Destroy the stack
- `npm run diff`: Show deployment differences
- `npm run synth`: Synthesize CloudFormation template

## Stack Outputs

After deployment, the stack provides the following outputs:

- **GuardDutyDetectorId**: GuardDuty detector ID for threat detection
- **ComplianceReportsBucketName**: S3 bucket for compliance reports
- **SecurityAlertsTopicArn**: SNS topic for security alerts
- **SecurityProcessorFunctionName**: Lambda function for log processing
- **VpcLatticeLogGroupName**: CloudWatch log group for VPC Lattice logs
- **SecurityDashboardUrl**: Direct link to CloudWatch dashboard

## Security Features

### Threat Detection

- **VPC Lattice Log Analysis**: Monitors network traffic patterns
- **GuardDuty Integration**: Correlates with ML-powered threat intelligence
- **Risk Scoring**: Assigns risk scores to suspicious activities
- **Real-time Alerts**: Immediate notifications for security violations

### Compliance Reporting

- **Automated Reports**: Generated hourly with compliance status
- **Audit Trail**: Timestamped reports stored in S3
- **Risk Assessment**: Overall risk level calculation
- **Security Recommendations**: Actionable security guidance

### Data Protection

- **Encryption**: S3 server-side encryption for compliance reports
- **Access Control**: IAM roles with least privilege principles
- **Secure Logging**: CloudWatch log group with retention policies
- **Network Security**: VPC Lattice secure service communication

## Cost Optimization

- **S3 Lifecycle Policies**: Automatic transition to cheaper storage classes
- **Log Retention**: CloudWatch logs expire after 30 days
- **Resource Tagging**: Proper cost allocation and tracking
- **Auto-deletion**: Resources are deleted when stack is destroyed

## Troubleshooting

### Common Issues

1. **Lambda Function Timeout**:
   - Increase timeout in stack configuration
   - Optimize log processing logic

2. **Missing GuardDuty Findings**:
   - Verify GuardDuty is enabled in your region
   - Check IAM permissions for GuardDuty access

3. **No Email Alerts**:
   - Confirm email subscription in SNS topic
   - Check spam/junk folders for notifications

4. **VPC Lattice Access Logs Not Appearing**:
   - Ensure VPC Lattice service network has traffic
   - Verify access log configuration

### Debug Mode

Enable debug logging:

```bash
# Set debug level in Lambda environment
aws lambda update-function-configuration \
  --function-name security-compliance-processor \
  --environment "Variables={DEBUG=true}"
```

## Cleanup

To remove all resources:

```bash
npm run destroy
```

**Warning**: This will delete all compliance reports and security data. Ensure you have backups if needed.

## Security Considerations

1. **IAM Permissions**: Review and customize IAM policies for your environment
2. **Network Access**: Ensure VPC Lattice services are properly secured
3. **Data Retention**: Adjust S3 lifecycle policies based on compliance requirements
4. **Alert Sensitivity**: Tune detection rules to minimize false positives
5. **Key Management**: Consider using AWS KMS for additional encryption

## Integration with Existing Systems

### Security Information and Event Management (SIEM)

Integrate with existing SIEM systems by:

- Configuring SNS to forward alerts to SIEM endpoints
- Using S3 compliance reports as SIEM data sources
- Implementing custom Lambda logic for SIEM-specific formats

### Incident Response Systems

Connect to incident response platforms:

- SNS integration with PagerDuty, Slack, or Microsoft Teams
- Webhook notifications for custom incident management systems
- AWS Systems Manager integration for automated response

## Contributing

To contribute improvements:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

This code is licensed under the MIT License. See LICENSE file for details.

## Support

For issues and questions:

1. Check the troubleshooting section above
2. Review AWS documentation for the services used
3. Create an issue in the repository
4. Contact your AWS support team for infrastructure issues

## Related Resources

- [Amazon VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/)
- [Amazon GuardDuty User Guide](https://docs.aws.amazon.com/guardduty/latest/ug/)
- [AWS CDK TypeScript Reference](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib-readme.html)
- [AWS Well-Architected Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)