# Infrastructure as Code for Security Compliance Auditing with VPC Lattice and GuardDuty

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Security Compliance Auditing with VPC Lattice and GuardDuty".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- AWS account with permissions for:
  - GuardDuty (create/manage detectors)
  - VPC Lattice (create service networks, access log subscriptions)
  - Lambda (create functions, execution roles)
  - CloudWatch (create log groups, dashboards, metrics)
  - SNS (create topics, subscriptions)
  - S3 (create buckets, put/get objects)
  - IAM (create roles and policies)
- For CDK deployments: Node.js 18+ or Python 3.9+
- For Terraform: Terraform 1.0+
- Estimated cost: $15-25 per month for GuardDuty, $5-10 for Lambda executions, $2-5 for CloudWatch logs and metrics

> **Note**: GuardDuty pricing varies by region and data volume. The first 30 days include a free trial for new accounts.

## Architecture Overview

The solution creates an automated security compliance auditing system that:

- Enables GuardDuty threat detection across your AWS environment
- Configures VPC Lattice access logging to CloudWatch
- Deploys a Lambda function that processes access logs and correlates with GuardDuty findings
- Creates CloudWatch dashboards for security monitoring
- Sets up SNS notifications for security alerts
- Generates compliance reports stored in S3

## Quick Start

### Using CloudFormation (AWS)

```bash
aws cloudformation create-stack \
    --stack-name security-compliance-auditing \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=security-admin@yourcompany.com \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-east-1
```

Monitor deployment progress:

```bash
aws cloudformation wait stack-create-complete \
    --stack-name security-compliance-auditing
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/
npm install

# Bootstrap CDK (if not already done)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy --parameters notificationEmail=security-admin@yourcompany.com
```

### Using CDK Python (AWS)

```bash
cd cdk-python/
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters notificationEmail=security-admin@yourcompany.com
```

### Using Terraform

```bash
cd terraform/
terraform init

# Review the deployment plan
terraform plan -var="notification_email=security-admin@yourcompany.com"

# Apply the infrastructure
terraform apply -var="notification_email=security-admin@yourcompany.com"
```

### Using Bash Scripts

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

When prompted, enter your notification email address for security alerts.

## Post-Deployment Configuration

### 1. Confirm SNS Subscription

After deployment, check your email and confirm the SNS subscription to receive security alerts.

### 2. Configure VPC Lattice Logging

If you have existing VPC Lattice service networks, configure access logging:

```bash
# Get the CloudWatch log group ARN from stack outputs
LOG_GROUP_ARN=$(aws cloudformation describe-stacks \
    --stack-name security-compliance-auditing \
    --query 'Stacks[0].Outputs[?OutputKey==`LogGroupArn`].OutputValue' \
    --output text)

# Configure logging for your existing service network
aws vpc-lattice create-access-log-subscription \
    --resource-identifier YOUR_SERVICE_NETWORK_ID \
    --destination-arn ${LOG_GROUP_ARN}
```

### 3. Test the System

Generate test log entries to verify the system is working:

```bash
# Get Lambda function name from outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name security-compliance-auditing \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Invoke with test data
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload file://test-event.json \
    response.json
```

## Monitoring and Validation

### CloudWatch Dashboard

Access the security monitoring dashboard:

1. Go to CloudWatch Console > Dashboards
2. Open "SecurityComplianceDashboard"
3. Monitor VPC Lattice traffic patterns and security alerts

### GuardDuty Findings

Monitor threat detection:

```bash
# List recent GuardDuty findings
DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)
aws guardduty list-findings --detector-id ${DETECTOR_ID}
```

### Compliance Reports

Check generated compliance reports in S3:

```bash
# Get S3 bucket name from outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name security-compliance-auditing \
    --query 'Stacks[0].Outputs[?OutputKey==`ComplianceBucket`].OutputValue' \
    --output text)

# List compliance reports
aws s3 ls s3://${BUCKET_NAME}/compliance-reports/ --recursive
```

## Customization

### Parameters

Each implementation supports the following customizable parameters:

- **NotificationEmail**: Email address for security alerts (required)
- **LogRetentionDays**: CloudWatch log retention period (default: 30 days)
- **LambdaTimeout**: Lambda function timeout in seconds (default: 60)
- **DashboardName**: Name for the CloudWatch dashboard (default: SecurityComplianceDashboard)

### Environment Variables

The Lambda function supports these environment variables:

- **RISK_THRESHOLD**: Risk score threshold for triggering alerts (default: 25)
- **REPORT_FREQUENCY**: How often to generate compliance reports (default: hourly)
- **ENABLE_DEBUG**: Enable debug logging (default: false)

### Extending the Solution

To add custom security rules to the Lambda function:

1. Modify the `analyze_access_log` function in the Lambda code
2. Add new risk factors and scoring logic
3. Update the threshold values based on your security requirements
4. Redeploy the updated function

## Troubleshooting

### Common Issues

1. **GuardDuty Not Enabled**: Ensure GuardDuty is enabled in your target region
2. **SNS Subscription Not Confirmed**: Check email and confirm subscription
3. **Lambda Timeout**: Increase timeout if processing large log volumes
4. **Permission Errors**: Verify IAM roles have required permissions

### Debug Mode

Enable debug logging in the Lambda function:

```bash
aws lambda update-function-configuration \
    --function-name ${FUNCTION_NAME} \
    --environment Variables='{ENABLE_DEBUG=true}'
```

### Log Analysis

Check Lambda function logs for errors:

```bash
aws logs filter-log-events \
    --log-group-name /aws/lambda/${FUNCTION_NAME} \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Security Considerations

### Data Protection

- All S3 buckets are encrypted with AES-256
- CloudWatch logs are encrypted in transit
- Lambda function uses least privilege IAM permissions
- VPC Lattice access logs contain sensitive network information

### Access Control

- IAM roles follow principle of least privilege
- S3 bucket policies restrict access to authorized principals
- Lambda function can only access required resources
- GuardDuty findings are protected by AWS service permissions

### Compliance

- Solution supports SOC 2, PCI DSS, and GDPR compliance monitoring
- Audit trails are maintained in CloudTrail (not included in this recipe)
- Compliance reports include timestamps and integrity verification
- All security events are logged and searchable

## Cost Optimization

### Estimated Monthly Costs

- **GuardDuty**: $4.60 + $0.60 per GB analyzed
- **Lambda**: $0.20 per 1M requests + compute time
- **CloudWatch**: $0.50 per GB ingested + $0.03 per metric
- **S3**: $0.023 per GB storage + request costs
- **SNS**: $0.50 per 1M notifications

### Cost Reduction Tips

1. Adjust CloudWatch log retention periods
2. Use S3 Intelligent Tiering for compliance reports
3. Optimize Lambda memory allocation
4. Filter VPC Lattice logs to reduce volume
5. Use CloudWatch metric filters to reduce custom metrics

## Cleanup

### Using CloudFormation (AWS)

```bash
# Empty S3 bucket first (if it contains data)
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name security-compliance-auditing \
    --query 'Stacks[0].Outputs[?OutputKey==`ComplianceBucket`].OutputValue' \
    --output text)
aws s3 rm s3://${BUCKET_NAME} --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name security-compliance-auditing

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name security-compliance-auditing
```

### Using CDK (AWS)

```bash
# From the CDK project directory
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="notification_email=security-admin@yourcompany.com"
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Additional Resources

- [Recipe Documentation](../security-compliance-auditing-lattice-guardduty.md)
- [Amazon VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/)
- [Amazon GuardDuty User Guide](https://docs.aws.amazon.com/guardduty/latest/ug/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [AWS Well-Architected Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/)

## Support

For issues with this infrastructure code:

1. Review the troubleshooting section above
2. Check AWS service status in your region
3. Refer to the original recipe documentation
4. Consult AWS support for service-specific issues

## Contributing

To contribute improvements to this IaC implementation:

1. Test changes in a development environment
2. Ensure all security best practices are maintained
3. Update documentation for any new parameters or features
4. Validate against the original recipe requirements