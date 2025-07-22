# Advanced Cross-Account IAM Role Federation - CDK Python

This directory contains a comprehensive AWS CDK Python implementation for advanced cross-account IAM role federation with SAML integration, conditional access policies, and automated compliance validation.

## Architecture Overview

This CDK application implements a sophisticated cross-account access pattern that includes:

- **Master Cross-Account Role**: Central hub for federated access with SAML and MFA support
- **Environment-Specific Roles**: Production and development roles with tailored permissions
- **External ID Security**: Protection against confused deputy attacks
- **Session Tags**: Attribute-based access control (ABAC) implementation
- **Comprehensive Audit Trail**: CloudTrail logging with S3 storage and lifecycle management
- **Automated Validation**: Lambda function for continuous compliance monitoring
- **Secrets Management**: Secure storage of external IDs in AWS Secrets Manager

## Prerequisites

1. **AWS Accounts**: Minimum 3 AWS accounts (security, production, development)
2. **Python**: Python 3.8 or higher
3. **AWS CLI**: AWS CLI v2 configured with appropriate permissions
4. **CDK**: AWS CDK v2 installed (`npm install -g aws-cdk`)
5. **SAML Provider**: IAM SAML identity provider configured (optional for demo)

## Installation

1. **Clone and Navigate**:
   ```bash
   cd aws/advanced-cross-account-iam-role-federation/code/cdk-python/
   ```

2. **Create Virtual Environment**:
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install Dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK** (if not already done):
   ```bash
   cdk bootstrap
   ```

## Configuration

Configure your deployment using environment variables or CDK context:

### Environment Variables

```bash
export SECURITY_ACCOUNT_ID="111111111111"  # Your security/central account
export PROD_ACCOUNT_ID="222222222222"      # Your production account
export DEV_ACCOUNT_ID="333333333333"       # Your development account
export CDK_DEFAULT_REGION="us-east-1"      # Your preferred region
```

### CDK Context (Alternative)

You can also configure via `cdk.json` context:

```json
{
  "context": {
    "securityAccountId": "111111111111",
    "prodAccountId": "222222222222", 
    "devAccountId": "333333333333",
    "samlProviderName": "CorporateIdP",
    "allowedDepartments": ["Engineering", "Security", "DevOps"]
  }
}
```

## Deployment

1. **Review the Stack**:
   ```bash
   cdk diff
   ```

2. **Deploy the Stack**:
   ```bash
   cdk deploy
   ```

3. **Approve IAM Changes**:
   The deployment will prompt for approval of IAM changes due to the `requireApproval: broadening` setting.

## Usage

### Assuming Cross-Account Roles

After deployment, you can assume roles using the AWS CLI:

1. **Get External IDs** (from stack outputs or Secrets Manager):
   ```bash
   aws secretsmanager get-secret-value \
       --secret-id "ProdExternalIdSecret-XXX" \
       --query SecretString --output text
   ```

2. **Assume Production Role**:
   ```bash
   aws sts assume-role \
       --role-arn "arn:aws:iam::PROD_ACCOUNT:role/CrossAccount-ProductionAccess-XXX" \
       --role-session-name "ProductionSession" \
       --external-id "YOUR_PROD_EXTERNAL_ID" \
       --tags Key=Department,Value=Engineering Key=Project,Value=Demo \
       --transitive-tag-keys Department,Project
   ```

3. **Use Temporary Credentials**:
   ```bash
   export AWS_ACCESS_KEY_ID="ASIA..."
   export AWS_SECRET_ACCESS_KEY="..."
   export AWS_SESSION_TOKEN="..."
   ```

### Validating Role Compliance

Execute the role validator Lambda function:

```bash
aws lambda invoke \
    --function-name "CrossAccountRoleValidator-XXX" \
    --payload '{}' \
    response.json

cat response.json
```

### Monitoring Audit Logs

Check CloudTrail logs for role assumption activities:

```bash
aws logs filter-log-events \
    --log-group-name "/aws/cloudtrail/CrossAccountAuditTrail-XXX" \
    --filter-pattern '{ $.eventName = "AssumeRole" }' \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Security Features

### External ID Protection

- **Confused Deputy Prevention**: External IDs prevent unauthorized cross-account access
- **Unique Per Environment**: Separate external IDs for production and development
- **Secure Storage**: External IDs stored in AWS Secrets Manager

### Multi-Factor Authentication

- **Required for Master Role**: MFA must be present and recent (< 1 hour)
- **Session Duration Limits**: Production roles limited to 1 hour, development to 2 hours
- **Trust Policy Enforcement**: MFA conditions enforced at the trust policy level

### Session Tags and ABAC

- **Attribute-Based Access**: Session tags enable dynamic access control
- **Transitive Tags**: Tags flow through the entire assume role chain
- **Audit Trail**: All session tags logged for compliance tracking

### Conditional Access

- **IP Address Restrictions**: Development roles restricted to specific IP ranges
- **Region Restrictions**: Access limited to specified AWS regions
- **Time-Based Controls**: Session duration limits based on environment sensitivity

## Resource Outputs

The stack creates the following key outputs:

| Output | Description |
|--------|-------------|
| `MasterRoleArn` | ARN of the master cross-account role |
| `ProductionRoleArn` | ARN of the production access role |
| `DevelopmentRoleArn` | ARN of the development access role |
| `AuditBucketName` | S3 bucket name for audit logs |
| `ValidatorLambdaArn` | ARN of the role validation function |
| `ProductionExternalIdSecretArn` | Secrets Manager ARN for production external ID |
| `DevelopmentExternalIdSecretArn` | Secrets Manager ARN for development external ID |

## Compliance and Monitoring

### Automated Validation

The included Lambda function validates:

- **External ID Requirements**: Ensures all cross-account roles require external IDs
- **MFA Conditions**: Verifies MFA requirements in trust policies
- **Session Duration Limits**: Validates maximum session durations
- **IP Restrictions**: Checks for appropriate IP-based access controls

### Audit Logging

Comprehensive CloudTrail configuration captures:

- **All Management Events**: Including IAM and STS operations
- **Cross-Account Activities**: Detailed logging of role assumptions
- **Data Events**: S3 access patterns for audit buckets
- **Log File Validation**: Tamper-evident logging with file validation

### Cost Management

- **S3 Lifecycle Policies**: Automatic archival of old audit logs
- **Resource Tagging**: Comprehensive tagging for cost allocation
- **Retention Policies**: Configurable log retention periods

## Development

### Code Quality

Run code quality checks:

```bash
# Format code
black app.py

# Lint code
flake8 app.py

# Type checking
mypy app.py

# Security scanning
bandit -r .
```

### Testing

Run unit tests:

```bash
pytest tests/ -v --cov=.
```

### Documentation

Generate documentation:

```bash
sphinx-build -b html docs/ docs/_build/
```

## Troubleshooting

### Common Issues

1. **Bootstrap Required**:
   ```
   Error: This stack uses assets, so the toolkit stack must be deployed
   ```
   **Solution**: Run `cdk bootstrap` in each target account/region.

2. **IAM Permissions**:
   ```
   Error: User: arn:aws:iam::ACCOUNT:user/USER is not authorized to perform: iam:CreateRole
   ```
   **Solution**: Ensure your AWS credentials have sufficient IAM permissions.

3. **External ID Mismatch**:
   ```
   Error: AccessDenied when assuming role
   ```
   **Solution**: Verify external ID matches between assume role call and trust policy.

### Debugging

Enable CDK debug logging:

```bash
cdk deploy --debug
```

Check CloudFormation events:

```bash
aws cloudformation describe-stack-events \
    --stack-name CrossAccountIAMFederationStack
```

## Security Considerations

### Production Deployment

1. **External ID Rotation**: Implement regular rotation of external IDs
2. **Secret Access**: Restrict access to Secrets Manager containing external IDs
3. **Network Controls**: Implement VPC endpoints for API calls where appropriate
4. **Monitoring**: Set up CloudWatch alarms for unusual role assumption patterns

### Compliance

- **SOC 2**: Audit logging supports SOC 2 compliance requirements
- **PCI DSS**: Network controls and access logging support PCI DSS compliance
- **GDPR**: Session tags enable data subject tracking for GDPR compliance
- **HIPAA**: Encryption and access controls support HIPAA requirements

## Cleanup

To remove all resources:

```bash
cdk destroy
```

**Warning**: This will delete all resources including audit logs. Ensure you have backed up any required audit data before destroying the stack.

## Support

For issues with this CDK implementation:

1. Check the [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/latest/guide/)
2. Review [IAM Cross-Account Access Patterns](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies-cross-account-resource-access.html)
3. Consult [AWS Security Best Practices](https://docs.aws.amazon.com/security/)

## License

This code is provided under the MIT License. See the original recipe documentation for full details.