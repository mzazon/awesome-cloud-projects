# Fine-Grained Access Control with IAM Policies and Conditions - CDK Python

This CDK Python application demonstrates advanced IAM policy patterns using conditions, resource-based policies, and context-aware access controls. It implements the complete infrastructure from the "Fine-Grained Access Control with IAM" recipe.

## Architecture

The application creates:

- **S3 Bucket**: Test bucket with versioning, encryption, and SSL enforcement
- **CloudWatch Log Group**: For testing log-based access controls
- **IAM Policies**: Five advanced policies demonstrating different condition patterns:
  - Time-based access control (business hours only)
  - IP address restrictions
  - Tag-based access control (ABAC)
  - MFA requirements for sensitive operations
  - Session-based access controls
- **IAM Principals**: Test user and role with appropriate tags and trust relationships
- **Resource-Based Policies**: S3 bucket policy with encryption and metadata requirements

## Prerequisites

- AWS CLI v2 installed and configured
- Python 3.8+ installed
- Node.js 18+ (required for CDK)
- AWS CDK v2 installed globally: `npm install -g aws-cdk`
- Appropriate AWS permissions for IAM, S3, and CloudWatch operations

## Installation

1. **Clone or navigate to the CDK Python directory**:
   ```bash
   cd aws/fine-grained-access-control-iam-policies-conditions/code/cdk-python/
   ```

2. **Create a Python virtual environment**:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat
   ```

3. **Install Python dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Install CDK dependencies and bootstrap (if not done previously)**:
   ```bash
   cdk bootstrap
   ```

## Configuration

The application uses CDK context values for configuration. You can customize the deployment by modifying `cdk.json` or providing context values via command line:

### Available Context Parameters

- `project_name`: Base name for all resources (default: "finegrained-access")
- `environment`: Environment tag (default: "test")
- `department`: Department tag for testing ABAC (default: "Engineering")
- `allowed_ip_ranges`: IP ranges for testing IP-based restrictions
- `business_hours`: Time window for business hours policy
- `mfa_max_age_seconds`: Maximum age for MFA authentication (default: 3600)
- `session_max_duration_seconds`: Maximum session duration (default: 3600)

### Custom Configuration Examples

```bash
# Deploy with custom project name
cdk deploy -c project_name="my-access-control-test"

# Deploy with custom environment
cdk deploy -c environment="development" -c department="Marketing"

# Deploy with custom IP ranges
cdk deploy -c allowed_ip_ranges='["10.0.0.0/8","172.16.0.0/12"]'
```

## Deployment

1. **Validate the CDK application**:
   ```bash
   cdk synth
   ```

2. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

   The deployment will create all resources and output important ARNs and names for testing.

3. **View the generated CloudFormation template** (optional):
   ```bash
   cdk synth > cloudformation-template.yaml
   ```

## Testing the Access Controls

After deployment, use the AWS CLI or IAM Policy Simulator to test the various access control patterns:

### 1. Test Business Hours Policy

```bash
# Get the test role ARN from CDK output
TEST_ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name FineGrainedAccessControlStack \
    --query 'Stacks[0].Outputs[?OutputKey==`TestRoleArn`].OutputValue' \
    --output text)

# Test during business hours (adjust time as needed)
aws iam simulate-principal-policy \
    --policy-source-arn $TEST_ROLE_ARN \
    --action-names "s3:GetObject" \
    --resource-arns "arn:aws:s3:::your-bucket-name/test-file.txt" \
    --context-entries ContextKeyName=aws:CurrentTime,ContextKeyValues="14:00:00Z",ContextKeyType=date
```

### 2. Test IP-Based Restrictions

```bash
# Test with allowed IP address
aws iam simulate-principal-policy \
    --policy-source-arn "arn:aws:iam::ACCOUNT:policy/finegrained-access-ip-restriction-policy" \
    --action-names "logs:PutLogEvents" \
    --resource-arns "arn:aws:logs:REGION:ACCOUNT:log-group:/aws/lambda/finegrained-access" \
    --context-entries ContextKeyName=aws:SourceIp,ContextKeyValues="203.0.113.100",ContextKeyType=ip
```

### 3. Test Tag-Based Access Control

```bash
# Test with matching department tags
aws iam simulate-principal-policy \
    --policy-source-arn "arn:aws:iam::ACCOUNT:policy/finegrained-access-tag-based-policy" \
    --action-names "s3:GetObject" \
    --resource-arns "arn:aws:s3:::your-bucket-name/Engineering/test-file.txt" \
    --context-entries ContextKeyName=aws:PrincipalTag/Department,ContextKeyValues="Engineering",ContextKeyType=string \
                      ContextKeyName=s3:ExistingObjectTag/Department,ContextKeyValues="Engineering",ContextKeyType=string
```

### 4. Test MFA Requirements

```bash
# Test MFA policy without MFA (should deny write operations)
aws iam simulate-principal-policy \
    --policy-source-arn "arn:aws:iam::ACCOUNT:policy/finegrained-access-mfa-required-policy" \
    --action-names "s3:PutObject" \
    --resource-arns "arn:aws:s3:::your-bucket-name/test-file.txt" \
    --context-entries ContextKeyName=aws:MultiFactorAuthPresent,ContextKeyValues="false",ContextKeyType=boolean
```

## Outputs

The stack provides the following outputs for testing and integration:

- `TestBucketName`: Name of the S3 bucket for testing
- `TestBucketArn`: ARN of the S3 bucket
- `LogGroupName`: CloudWatch log group name
- `TestUserArn`: ARN of the test user
- `TestRoleArn`: ARN of the test role
- `BusinessHoursPolicyArn`: ARN of the business hours policy
- `TagBasedPolicyArn`: ARN of the tag-based policy
- `MfaRequiredPolicyArn`: ARN of the MFA-required policy

## Cost Considerations

This application creates the following billable resources:

- **S3 Bucket**: Standard storage charges apply for any objects created
- **CloudWatch Log Group**: Charges for log ingestion and storage (minimal for testing)
- **IAM Resources**: No charges for IAM users, roles, and policies

Estimated cost for testing: **Under $1/month** with minimal usage.

## Security Best Practices

The CDK application implements several security best practices:

1. **Least Privilege**: All policies grant minimal required permissions
2. **Defense in Depth**: Combines identity-based and resource-based policies
3. **Encryption**: S3 bucket uses server-side encryption
4. **Secure Transport**: S3 bucket policy denies non-HTTPS requests
5. **Auto-Cleanup**: Resources configured for easy deletion

## Customization

### Adding New Condition Types

To add additional condition patterns, extend the stack class with new policy methods:

```python
def _create_custom_policy(self) -> iam.ManagedPolicy:
    """Create a custom policy with specific conditions."""
    policy_document = iam.PolicyDocument(
        statements=[
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["your:actions"],
                resources=["your:resources"],
                conditions={
                    "YourConditionOperator": {
                        "your:condition:key": "your-condition-value"
                    }
                }
            )
        ]
    )
    
    return iam.ManagedPolicy(
        self, "CustomPolicy",
        managed_policy_name=f"{self.project_name}-custom-policy",
        description="Custom policy description",
        document=policy_document,
    )
```

### Modifying IP Ranges

Update the `allowed_ip_ranges` context value in `cdk.json` or provide via command line:

```bash
cdk deploy -c allowed_ip_ranges='["your.ip.range/24","another.range/24"]'
```

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Required**: Ensure your account/region is bootstrapped for CDK
   ```bash
   cdk bootstrap aws://ACCOUNT-NUMBER/REGION
   ```

2. **Permission Errors**: Verify your AWS credentials have necessary permissions for IAM, S3, and CloudWatch

3. **Resource Name Conflicts**: The application generates unique names using account ID, but conflicts may occur in some regions

4. **Policy Validation Errors**: Use the IAM Policy Simulator to validate policies before testing in production

### Debug Mode

Enable verbose CDK output for troubleshooting:

```bash
cdk deploy --verbose
```

## Cleanup

To remove all resources created by this application:

```bash
cdk destroy
```

This will delete all IAM policies, users, roles, S3 bucket, and CloudWatch log group created by the stack.

## Development

### Code Style

The project follows Python best practices:

- **Type Hints**: All functions include type annotations
- **Docstrings**: Comprehensive documentation for all classes and methods
- **Comments**: Inline comments explain complex IAM policy logic
- **PEP 8**: Code formatted according to Python style guidelines

### Testing

Run tests using pytest (install dev dependencies first):

```bash
pip install -e ".[dev]"
pytest
```

### Code Formatting

Format code using black:

```bash
black app.py
```

Check code quality:

```bash
flake8 app.py
mypy app.py
```

## Additional Resources

- [AWS IAM Policy Reference](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies.html)
- [IAM JSON Policy Elements: Condition](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_condition.html)
- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [AWS IAM Policy Simulator](https://policysim.aws.amazon.com/)
- [AWS IAM Access Analyzer](https://docs.aws.amazon.com/IAM/latest/UserGuide/what-is-access-analyzer.html)

## Support

For issues with this CDK application:

1. Check the [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
2. Review [IAM troubleshooting guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/troubleshoot.html)
3. Use AWS IAM Policy Simulator for policy validation
4. Refer to the original recipe documentation for conceptual guidance