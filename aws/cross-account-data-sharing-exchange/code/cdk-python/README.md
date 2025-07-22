# AWS CDK Python - Cross-Account Data Sharing with Data Exchange

This CDK Python application creates the infrastructure for securely sharing data assets across AWS accounts using AWS Data Exchange, S3, IAM roles, and Lambda functions for automation.

## Architecture

The solution creates:

- **S3 Bucket**: Secure storage for data assets with versioning and lifecycle policies
- **IAM Role**: Service role for AWS Data Exchange operations with least privilege access
- **Lambda Functions**: 
  - Notification handler for Data Exchange events
  - Automated data update function for scheduled revisions
- **EventBridge Rules**: Event-driven automation for notifications and scheduled updates
- **CloudWatch Monitoring**: Log groups, metrics, and alarms for operational visibility

## Prerequisites

- Python 3.8 or later
- AWS CLI v2 configured with appropriate permissions
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Docker installed (for Lambda function packaging)

### Required AWS Permissions

The deploying user/role needs permissions for:
- IAM role and policy management
- S3 bucket creation and management
- Lambda function deployment
- EventBridge rule creation
- CloudWatch log group and alarm management
- Data Exchange operations (for testing)

## Installation

1. **Clone and navigate to the directory**:
   ```bash
   cd aws/cross-account-data-sharing-aws-data-exchange/code/cdk-python/
   ```

2. **Create virtual environment**:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

## Configuration

### Context Parameters

Configure the deployment by setting context parameters in `cdk.json` or via command line:

```bash
# Set subscriber account ID
cdk deploy -c subscriber_account_id=123456789012

# Set environment name
cdk deploy -c environment=prod

# Set SNS topic ARN for notifications (optional)
cdk deploy -c sns_topic_arn=arn:aws:sns:us-east-1:123456789012:notifications
```

### Environment Variables

You can also set these environment variables:

```bash
export CDK_DEFAULT_ACCOUNT=123456789012
export CDK_DEFAULT_REGION=us-east-1
```

## Deployment

1. **Bootstrap CDK** (first time only):
   ```bash
   cdk bootstrap
   ```

2. **Synthesize CloudFormation template**:
   ```bash
   cdk synth
   ```

3. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

   Or with specific configuration:
   ```bash
   cdk deploy -c subscriber_account_id=123456789012 -c environment=prod
   ```

4. **View outputs**:
   ```bash
   cdk deploy --outputs-file outputs.json
   ```

## Usage

### Creating Data Sets and Grants

After deployment, use the AWS CLI or Console to:

1. **Create a Data Set**:
   ```bash
   aws dataexchange create-data-set \
       --asset-type S3_SNAPSHOT \
       --description "Enterprise analytics data" \
       --name "enterprise-analytics-data"
   ```

2. **Upload sample data** to the created S3 bucket
3. **Create revisions and import assets**
4. **Create data grants** for cross-account sharing

### Monitoring

- **CloudWatch Logs**: Check `/aws/dataexchange/operations` for operational logs
- **Lambda Logs**: Monitor function execution in CloudWatch
- **Alarms**: Receive notifications for Lambda errors

### Automated Updates

The solution includes automated daily data updates via EventBridge and Lambda. To trigger manual updates:

```bash
aws lambda invoke \
    --function-name DataExchangeAutoUpdate \
    --payload '{"bucket_name":"your-bucket","dataset_id":"your-dataset-id"}' \
    response.json
```

## Customization

### Lambda Functions

Modify the Lambda function code in `stacks/data_exchange_stack.py`:

- `_get_notification_lambda_code()`: Customize notification logic
- `_get_update_lambda_code()`: Modify data generation and update logic

### S3 Lifecycle Policies

Adjust lifecycle rules in the `_create_data_bucket()` method:

```python
lifecycle_rules=[
    s3.LifecycleRule(
        id="CustomTransition",
        enabled=True,
        transitions=[
            s3.Transition(
                storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                transition_after=Duration.days(30)
            )
        ]
    )
]
```

### EventBridge Schedules

Modify the schedule in `_create_event_rules()`:

```python
schedule=events.Schedule.rate(Duration.hours(12))  # Every 12 hours
```

## Security Considerations

### IAM Roles and Policies

- The Data Exchange role uses AWS managed policies with additional inline policies
- Lambda functions have minimal required permissions
- S3 bucket enforces SSL and blocks public access

### Data Encryption

- S3 bucket uses server-side encryption (S3-managed keys)
- Consider using AWS KMS for additional encryption control
- Lambda environment variables are encrypted at rest

### Network Security

- All resources use AWS service endpoints
- Consider VPC endpoints for enhanced security
- S3 bucket policies can restrict access by IP or VPC

## Testing

### Unit Tests

Run unit tests with pytest:

```bash
pytest tests/ -v
```

### Integration Tests

Test the deployed infrastructure:

```bash
# Test Lambda functions
aws lambda invoke \
    --function-name DataExchangeNotificationHandler \
    --payload '{"test": true}' \
    response.json

# Verify S3 bucket
aws s3 ls s3://your-data-bucket-name

# Check IAM role
aws iam get-role --role-name DataExchangeProviderRole
```

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Required**:
   ```bash
   cdk bootstrap aws://ACCOUNT-NUMBER/REGION
   ```

2. **Permission Errors**:
   - Ensure deploying user has required permissions
   - Check CloudTrail logs for detailed error messages

3. **Lambda Function Errors**:
   - Check CloudWatch Logs for function execution logs
   - Verify environment variables are set correctly

4. **S3 Bucket Name Conflicts**:
   - Bucket names are globally unique
   - The stack creates buckets with account/region suffixes

### Debugging

Enable CDK debug mode:

```bash
cdk deploy --debug
```

Check CloudFormation events:

```bash
aws cloudformation describe-stack-events --stack-name DataExchangeStack
```

## Cost Optimization

### Resource Costs

- S3 storage with lifecycle policies to transition to cheaper storage classes
- Lambda functions with right-sized memory allocation
- CloudWatch log retention set to 30 days

### Monitoring Costs

- Use AWS Cost Explorer to monitor Data Exchange costs
- Set up billing alarms for unexpected charges
- Review S3 storage class transitions regularly

## Cleanup

Remove all resources:

```bash
cdk destroy
```

This will delete:
- All Lambda functions
- EventBridge rules
- CloudWatch resources
- IAM roles and policies
- S3 bucket (if empty)

**Note**: You may need to manually delete S3 objects before destroying the stack if the bucket is not empty.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and add tests
4. Run tests and linting
5. Submit a pull request

### Development Setup

```bash
# Install development dependencies
pip install -r requirements.txt

# Run linting
flake8 .
black .
mypy .

# Run tests
pytest tests/ -v --cov=stacks
```

## Support

For issues and questions:

- Check AWS Data Exchange documentation
- Review CloudWatch logs for error details
- Create issues in the repository
- Contact AWS Support for service-specific questions

## License

This project is licensed under the MIT License - see the LICENSE file for details.