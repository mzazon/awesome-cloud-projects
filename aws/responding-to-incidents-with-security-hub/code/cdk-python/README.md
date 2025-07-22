# AWS CDK Python - Security Hub Incident Response

This directory contains an AWS CDK Python application that deploys a comprehensive security incident response system using AWS Security Hub, EventBridge, Lambda, and SNS.

## Architecture Overview

The application creates:

- **Security Hub Integration**: Central hub for security findings aggregation
- **EventBridge Rules**: Automated event processing for high-severity findings
- **Lambda Functions**: 
  - Incident processor for automated triage and notifications
  - Threat intelligence enrichment for context enhancement
- **SNS Topic**: Multi-channel notification delivery
- **SQS Queue**: Durable message buffering for external integrations
- **Custom Actions**: Manual escalation capabilities in Security Hub console
- **CloudWatch Dashboard**: Real-time monitoring and alerting
- **IAM Roles**: Least-privilege security permissions

## Prerequisites

- Python 3.8 or later
- AWS CLI v2 installed and configured
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Sufficient AWS permissions for:
  - Security Hub administration
  - Lambda function management
  - EventBridge rule creation
  - SNS/SQS resource management
  - IAM role and policy management
  - CloudWatch dashboard creation

## Installation

1. **Clone and navigate to the directory**:
   ```bash
   cd aws/security-incident-response-aws-security-hub/code/cdk-python/
   ```

2. **Create a Python virtual environment**:
   ```bash
   python -m venv .venv
   ```

3. **Activate the virtual environment**:
   
   On macOS/Linux:
   ```bash
   source .venv/bin/activate
   ```
   
   On Windows:
   ```bash
   .venv\Scripts\activate
   ```

4. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

5. **Verify CDK installation**:
   ```bash
   cdk --version
   ```

## Configuration

### Environment Variables

Set the following environment variables or CDK context:

```bash
export CDK_DEFAULT_ACCOUNT="123456789012"  # Your AWS account ID
export CDK_DEFAULT_REGION="us-east-1"     # Your preferred region
```

### CDK Context

Alternatively, you can set context in `cdk.json` or via command line:

```bash
cdk deploy -c account=123456789012 -c region=us-east-1
```

### Notification Email

To receive email notifications, set your email in the context:

```bash
cdk deploy -c notification-email=security-team@company.com
```

## Deployment

### Bootstrap CDK (First time only)

If you haven't used CDK in your account/region before:

```bash
cdk bootstrap
```

### Deploy the Stack

1. **Synthesize the CloudFormation template** (optional):
   ```bash
   cdk synth
   ```

2. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

3. **Confirm the deployment** when prompted.

### Post-Deployment Setup

1. **Enable Security Hub** (if not already enabled):
   ```bash
   aws securityhub enable-security-hub --enable-default-standards
   ```

2. **Subscribe to email notifications**:
   - Check your email for an SNS subscription confirmation
   - Click the confirmation link

3. **Configure Security Hub standards**:
   ```bash
   aws securityhub batch-enable-standards \
     --standards-subscription-requests '[
       {
         "StandardsArn": "arn:aws:securityhub:REGION::standards/cis-aws-foundations-benchmark/v/1.4.0"
       }
     ]'
   ```

## Usage

### Testing the System

1. **Create a test finding**:
   ```bash
   aws securityhub batch-import-findings \
     --findings '[{
       "AwsAccountId": "YOUR_ACCOUNT_ID",
       "CreatedAt": "2024-01-01T00:00:00.000Z",
       "Description": "Test high severity finding",
       "FindingProviderFields": {
         "Severity": {"Label": "HIGH", "Original": "8.0"},
         "Types": ["Software and Configuration Checks"]
       },
       "GeneratorId": "test-generator",
       "Id": "test-finding-001",
       "ProductArn": "arn:aws:securityhub:REGION:ACCOUNT:product/ACCOUNT/default",
       "Resources": [{"Id": "test-resource", "Type": "Other"}],
       "SchemaVersion": "2018-10-08",
       "Title": "Test Security Finding",
       "UpdatedAt": "2024-01-01T00:00:00.000Z",
       "Workflow": {"Status": "NEW"}
     }]'
   ```

2. **Monitor the processing**:
   - Check Lambda logs in CloudWatch
   - Verify SNS notifications
   - Review the CloudWatch dashboard

### Using Custom Actions

1. Navigate to the Security Hub console
2. Select findings
3. Use the "Escalate to SOC" custom action
4. Monitor automated escalation workflows

### Monitoring

Access the CloudWatch dashboard:
- Dashboard name: `SecurityHubIncidentResponse`
- Monitors Lambda invocations, errors, and SNS delivery metrics
- Includes alarms for processing failures

## Customization

### Lambda Function Configuration

Modify the Lambda functions by editing `security_incident_response_stack.py`:

- **Timeout**: Adjust `timeout` parameter (default: 60 seconds)
- **Memory**: Modify `memory_size` parameter (default: 256 MB)
- **Environment variables**: Add custom configuration

### Notification Channels

Add additional notification endpoints:

```python
# Add Slack webhook
topic.add_subscription(
    sns_subscriptions.UrlSubscription("https://hooks.slack.com/...")
)

# Add additional email addresses
topic.add_subscription(
    sns_subscriptions.EmailSubscription("additional-team@company.com")
)
```

### Event Filtering

Customize EventBridge rules to match your security requirements:

```python
# Add rule for specific finding types
rule = events.Rule(
    self,
    "CustomRule",
    event_pattern=events.EventPattern(
        source=["aws.securityhub"],
        detail={
            "findings": {
                "Types": [["Sensitive Data Identifications"]]
            }
        }
    )
)
```

### Threat Intelligence Integration

Extend the threat intelligence function to integrate with external feeds:

- VirusTotal API
- AlienVault OTX
- Custom threat feeds
- Commercial intelligence services

## Security Considerations

### IAM Permissions

The application follows least-privilege principles:

- Lambda execution role has minimal Security Hub and SNS permissions
- EventBridge rules are scoped to specific event patterns
- No cross-account access by default

### Data Protection

- All data in transit is encrypted using TLS
- Lambda logs are encrypted at rest
- SNS messages support optional encryption
- No sensitive data is logged in plain text

### Network Security

- Lambda functions run in AWS-managed VPCs by default
- Consider VPC deployment for additional network isolation
- Security groups and NACLs can be applied if using custom VPCs

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Required**:
   ```
   Error: Need to perform AWS CDK bootstrap
   ```
   Solution: Run `cdk bootstrap`

2. **Insufficient Permissions**:
   ```
   Error: User is not authorized to perform: iam:CreateRole
   ```
   Solution: Ensure your AWS user/role has appropriate permissions

3. **Lambda Function Errors**:
   - Check CloudWatch logs: `/aws/lambda/SecurityIncidentProcessor`
   - Verify IAM permissions
   - Check environment variables

4. **EventBridge Rules Not Triggering**:
   - Verify Security Hub is enabled
   - Check event pattern syntax
   - Review Lambda function permissions

5. **SNS Notifications Not Received**:
   - Confirm email subscription
   - Check SNS delivery metrics
   - Verify Lambda is publishing to correct topic

### Debug Mode

Enable detailed logging by setting environment variables:

```bash
export CDK_DEBUG=true
export AWS_CDK_DEBUG=true
cdk deploy
```

### Log Analysis

Monitor application logs:

```bash
# View Lambda logs
aws logs tail /aws/lambda/SecurityIncidentProcessor --follow

# View EventBridge metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Events \
  --metric-name MatchedEvents \
  --dimensions Name=RuleName,Value=security-hub-high-severity \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 3600 \
  --statistics Sum
```

## Cleanup

### Remove the Stack

```bash
cdk destroy
```

### Manual Cleanup (if needed)

Some resources may require manual deletion:

1. **Security Hub findings**: Resolve or suppress active findings
2. **CloudWatch logs**: May be retained based on retention policy
3. **SNS subscriptions**: Unsubscribe from email notifications

## Cost Estimation

Estimated monthly costs (assuming moderate usage):

- **Lambda**: $5-15 (based on invocations and duration)
- **SNS**: $1-5 (based on notification volume)
- **SQS**: $1-3 (based on message volume)
- **CloudWatch**: $2-8 (logs, metrics, dashboards)
- **EventBridge**: $1-5 (based on event volume)

**Total estimated cost**: $10-36/month

Costs may vary based on:
- Security finding volume
- Notification frequency
- Lambda execution duration
- Log retention settings

## Support and Contributing

### Documentation

- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [AWS Security Hub User Guide](https://docs.aws.amazon.com/securityhub/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)

### Getting Help

1. Review AWS CloudFormation events for deployment issues
2. Check CloudWatch logs for runtime errors
3. Consult AWS support for service-specific issues
4. Review the original recipe documentation

### Contributing

To contribute improvements:

1. Test changes in a development environment
2. Follow Python coding standards (PEP 8)
3. Add appropriate type hints and docstrings
4. Update tests and documentation
5. Submit changes following your organization's process

## License

This code is provided as an example implementation. Review and modify according to your organization's security and compliance requirements.