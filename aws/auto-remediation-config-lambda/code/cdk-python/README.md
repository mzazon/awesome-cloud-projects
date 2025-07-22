# AWS Config Auto-Remediation CDK Python Application

This CDK Python application deploys a comprehensive auto-remediation solution using AWS Config and Lambda to automatically detect and remediate security and compliance violations across your AWS infrastructure.

## Architecture Overview

The solution creates a self-healing infrastructure that:

- **Monitors** AWS resources continuously using AWS Config
- **Detects** compliance violations against organizational policies
- **Remediates** violations automatically using Lambda functions and Systems Manager
- **Notifies** stakeholders of remediation actions via SNS
- **Provides** visibility through CloudWatch dashboards and monitoring

## Prerequisites

- **AWS CLI** v2 installed and configured
- **Python** 3.8 or later
- **AWS CDK** v2 installed (`npm install -g aws-cdk`)
- **AWS Account** with appropriate permissions
- **Node.js** 14.x or later (for CDK CLI)

## Installation

1. **Clone or download** this CDK application code
2. **Create a virtual environment**:
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK** (first time only):
   ```bash
   cdk bootstrap
   ```

## Configuration

### Environment Variables

Set the following environment variables to customize the deployment:

```bash
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)
export ENVIRONMENT=development  # or production, staging, etc.
export OWNER=aws-config-team
export COST_CENTER=security
```

### CDK Context

You can also configure the application using CDK context in `cdk.json`:

```json
{
  "context": {
    "environment": "production",
    "owner": "security-team",
    "cost_center": "infrastructure"
  }
}
```

## Deployment

### Quick Deployment

```bash
# Deploy the entire solution
cdk deploy

# Deploy with confirmation prompts
cdk deploy --require-approval broadening
```

### Step-by-Step Deployment

1. **Synthesize** the CloudFormation template:
   ```bash
   cdk synth
   ```

2. **Compare** with existing stack (if any):
   ```bash
   cdk diff
   ```

3. **Deploy** the stack:
   ```bash
   cdk deploy ConfigRemediationStack
   ```

### Deployment Outputs

After successful deployment, the stack provides these outputs:

- **ConfigBucketName**: S3 bucket name for Config data storage
- **SNSTopicArn**: ARN for compliance notification topic
- **LambdaFunctionArn**: ARN of the remediation Lambda function
- **DashboardURL**: CloudWatch dashboard for monitoring
- **ConfigRoleArn**: IAM role ARN used by AWS Config

## What Gets Deployed

### Core Infrastructure

1. **AWS Config Setup**:
   - Configuration recorder for continuous monitoring
   - Delivery channel for storing configuration data
   - S3 bucket with appropriate policies for Config

2. **IAM Roles and Policies**:
   - Config service role with minimal required permissions
   - Lambda execution role with remediation permissions
   - Least-privilege policies following AWS security best practices

3. **Remediation Functions**:
   - Lambda function for security group remediation
   - Custom remediation logic for removing unrestricted access
   - Error handling and logging capabilities

4. **Compliance Monitoring**:
   - Config rules for security group SSH restrictions
   - Config rules for S3 bucket public access monitoring
   - Auto-remediation configurations

5. **Notification System**:
   - SNS topic for compliance alerts
   - Integration with Lambda for notification publishing

6. **Monitoring and Visibility**:
   - CloudWatch dashboard for compliance metrics
   - Log groups with retention policies
   - Performance and error monitoring

### Security Features

- **Encryption**: All data encrypted at rest and in transit
- **Access Control**: Least-privilege IAM policies
- **Audit Trail**: Complete logging of all remediation actions
- **Network Security**: No public access to resources
- **Resource Tagging**: Comprehensive tagging for governance

## Configuration Rules

The solution deploys these Config rules:

1. **security-group-ssh-restricted**: Detects security groups allowing unrestricted SSH access (0.0.0.0/0:22)
2. **s3-bucket-public-access-prohibited**: Identifies S3 buckets with public access configurations

## Remediation Actions

### Automatic Remediation

- **Security Groups**: Removes unrestricted inbound rules
- **Resource Tagging**: Tags remediated resources with metadata
- **Notifications**: Sends alerts for all remediation actions

### Manual Escalation

Complex violations that cannot be automatically remediated trigger notifications for manual review.

## Monitoring and Alerting

### CloudWatch Dashboard

The solution creates a comprehensive dashboard showing:

- Config rule compliance status over time
- Remediation function invocation metrics
- Error rates and performance metrics
- Cost optimization opportunities

### SNS Notifications

Configure SNS subscriptions to receive alerts for:

- Compliance violations detected
- Successful remediation actions
- Remediation failures requiring manual intervention

```bash
# Subscribe email to SNS topic
aws sns subscribe \
    --topic-arn $(aws cloudformation describe-stacks \
        --stack-name ConfigRemediationStack \
        --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' \
        --output text) \
    --protocol email \
    --notification-endpoint your-email@example.com
```

## Testing the Solution

### Create Test Violations

```bash
# Create a security group with unrestricted SSH access
aws ec2 create-security-group \
    --group-name test-unrestricted-sg \
    --description "Test security group for Config remediation"

aws ec2 authorize-security-group-ingress \
    --group-name test-unrestricted-sg \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0
```

### Monitor Remediation

1. Check the CloudWatch dashboard for compliance status
2. Review CloudWatch logs for Lambda function execution
3. Verify SNS notifications are received
4. Confirm the security group rules were remediated

## Customization

### Adding New Remediation Rules

1. **Create new Config rule** in `_create_config_rules()` method
2. **Implement remediation logic** in a new Lambda function
3. **Configure auto-remediation** in `_create_remediation_configurations()`
4. **Update dashboard** to include new metrics

### Modifying Remediation Logic

Edit the Lambda function code in the `_create_security_group_remediation_lambda()` method to customize remediation behavior.

### Environment-Specific Configuration

Use CDK context or environment variables to deploy different configurations for development, staging, and production environments.

## Cost Optimization

### Cost Components

- **AWS Config**: Charges for configuration items and rule evaluations
- **Lambda**: Minimal charges for remediation function executions
- **S3**: Storage costs for Config data with lifecycle policies
- **CloudWatch**: Dashboard and log storage costs

### Cost Control

- Configure Config rules only for critical resource types
- Set appropriate log retention periods
- Use S3 lifecycle policies for cost-effective storage
- Monitor usage through Cost Explorer

## Troubleshooting

### Common Issues

1. **Deployment Failures**:
   - Verify AWS credentials and permissions
   - Check CDK version compatibility
   - Review CloudFormation events in AWS Console

2. **Config Setup Issues**:
   - Ensure Config service is enabled in the region
   - Verify S3 bucket permissions
   - Check IAM role permissions

3. **Remediation Not Working**:
   - Review Lambda function logs
   - Check Config rule evaluation status
   - Verify auto-remediation configuration

### Debug Commands

```bash
# Check stack status
cdk ls
cdk diff

# View CloudFormation events
aws cloudformation describe-stack-events \
    --stack-name ConfigRemediationStack

# Check Config status
aws configservice describe-configuration-recorders
aws configservice describe-delivery-channels

# View Lambda logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/SecurityGroupRemediation"
```

## Security Considerations

### IAM Permissions

The solution follows the principle of least privilege:

- Config role: Only permissions needed for configuration recording
- Lambda role: Minimal permissions for specific remediation actions
- No overly permissive wildcard policies

### Data Protection

- All data encrypted using AWS managed keys
- S3 bucket blocks all public access
- Lambda functions run in VPC when needed
- CloudTrail integration for audit trails

### Compliance

The solution helps maintain compliance with:

- AWS Security Best Practices
- CIS Benchmarks
- PCI DSS requirements
- SOC 2 controls
- GDPR data protection requirements

## Cleanup

### Remove All Resources

```bash
# Destroy the CDK stack
cdk destroy ConfigRemediationStack

# Clean up CDK bootstrap (optional)
# cdk bootstrap --show-template > bootstrap-template.yaml
# aws cloudformation delete-stack --stack-name CDKToolkit
```

### Manual Cleanup

Some resources may require manual cleanup:

1. **S3 Objects**: Delete remaining objects in Config bucket
2. **Log Groups**: Remove log groups if retention policy allows
3. **SNS Subscriptions**: Unsubscribe email endpoints

## Support

### Documentation

- [AWS Config Documentation](https://docs.aws.amazon.com/config/)
- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)

### Community Resources

- [AWS CDK Examples](https://github.com/aws-samples/aws-cdk-examples)
- [AWS Config Rules Repository](https://github.com/awslabs/aws-config-rules)
- [AWS Security Blog](https://aws.amazon.com/blogs/security/)

### Getting Help

For issues with this CDK application:

1. Check the troubleshooting section above
2. Review AWS CloudFormation events and logs
3. Consult AWS documentation for specific services
4. Contact your AWS support team for production issues

## License

This project is licensed under the Apache License 2.0. See the LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## Changelog

### Version 1.0.0

- Initial release with Config auto-remediation
- Security group SSH restriction remediation
- S3 public access monitoring
- CloudWatch dashboard and SNS notifications
- Comprehensive documentation and examples