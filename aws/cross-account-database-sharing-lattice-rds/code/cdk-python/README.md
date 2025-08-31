# Cross-Account Database Sharing with VPC Lattice and RDS - CDK Python

This directory contains an AWS CDK Python application that implements secure cross-account database sharing using VPC Lattice resource configurations and Amazon RDS. The solution provides governed access to databases without complex networking requirements, following AWS security best practices.

## Architecture Overview

The CDK application creates:

- **VPC Infrastructure**: Multi-AZ VPC with public, private, and isolated subnets
- **RDS Database**: Encrypted MySQL database with security groups and subnet groups
- **VPC Lattice Components**: Resource gateway, service network, and resource configuration
- **Cross-Account Access**: IAM roles and policies for secure cross-account authentication
- **Resource Sharing**: AWS RAM integration for sharing VPC Lattice configurations
- **Monitoring**: CloudWatch dashboards and logging for observability
- **Security**: Secrets Manager for database credentials and comprehensive security groups

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI v2** installed and configured with appropriate credentials
2. **Python 3.8+** installed on your system
3. **AWS CDK v2.120.0+** installed globally:
   ```bash
   npm install -g aws-cdk@latest
   ```
4. **Two AWS accounts** with administrative access:
   - Account A (Database Owner): Where this stack will be deployed
   - Account B (Database Consumer): Account that will access the shared database
5. **Appropriate IAM permissions** for:
   - VPC and networking resources
   - RDS database creation
   - VPC Lattice service management
   - IAM role and policy creation
   - AWS RAM resource sharing
   - CloudWatch monitoring

## Quick Start

### 1. Environment Setup

```bash
# Clone or navigate to the CDK application directory
cd ./aws/cross-account-database-sharing-lattice-rds/code/cdk-python/

# Create and activate a Python virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Verify CDK installation
cdk --version
```

### 2. Bootstrap CDK (First Time Only)

```bash
# Bootstrap CDK in your account/region
cdk bootstrap aws://ACCOUNT-ID/REGION

# Example:
cdk bootstrap aws://123456789012/us-east-1
```

### 3. Deploy the Stack

```bash
# Deploy with required consumer account ID
cdk deploy -c consumer_account_id=CONSUMER_ACCOUNT_ID

# Example:
cdk deploy -c consumer_account_id=987654321098

# Optional: Specify additional parameters
cdk deploy \
    -c consumer_account_id=987654321098 \
    -c external_id=my-unique-external-id \
    -c db_instance_class=db.t3.small \
    -c db_allocated_storage=50
```

## Configuration Parameters

The CDK application accepts the following context parameters:

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `consumer_account_id` | Yes | None | AWS account ID that will consume the shared database |
| `external_id` | No | `unique-external-id-12345` | External ID for cross-account role assumption security |
| `db_instance_class` | No | `db.t3.micro` | RDS instance class for the database |
| `db_allocated_storage` | No | `20` | Storage allocation for the database in GB |
| `aws_account_id` | No | Current account | AWS account ID for deployment |
| `aws_region` | No | `us-east-1` | AWS region for deployment |

### Example with All Parameters

```bash
cdk deploy \
    -c consumer_account_id=987654321098 \
    -c external_id=prod-external-id-2024 \
    -c db_instance_class=db.t3.medium \
    -c db_allocated_storage=100 \
    -c aws_region=us-west-2
```

## Stack Outputs

After successful deployment, the stack provides these outputs:

- **VpcId**: VPC ID for the database owner account
- **DatabaseEndpoint**: RDS database endpoint hostname
- **DatabasePort**: RDS database port (3306 for MySQL)
- **ResourceGatewayId**: VPC Lattice resource gateway identifier
- **ServiceNetworkId**: VPC Lattice service network identifier
- **ResourceConfigurationId**: VPC Lattice resource configuration identifier
- **CrossAccountRoleArn**: ARN of the cross-account access role
- **ResourceShareArn**: ARN of the AWS RAM resource share
- **DatabaseSecretArn**: ARN of the database credentials secret

## Accessing Outputs

```bash
# View all stack outputs
aws cloudformation describe-stacks \
    --stack-name DatabaseSharingStack \
    --query 'Stacks[0].Outputs'

# Get specific output value
aws cloudformation describe-stacks \
    --stack-name DatabaseSharingStack \
    --query 'Stacks[0].Outputs[?OutputKey==`DatabaseEndpoint`].OutputValue' \
    --output text
```

## Consumer Account Setup

After deploying this stack, the consumer account needs to:

### 1. Accept the Resource Share

```bash
# In consumer account, list received invitations
aws ram get-resource-share-invitations \
    --resource-share-arns RESOURCE_SHARE_ARN

# Accept the invitation
aws ram accept-resource-share-invitation \
    --resource-share-invitation-arn INVITATION_ARN
```

### 2. Create VPC and Service Network Association

The consumer account needs to create their own VPC and associate it with the shared service network.

### 3. Assume Cross-Account Role

```bash
# Assume the cross-account role for database access
aws sts assume-role \
    --role-arn CROSS_ACCOUNT_ROLE_ARN \
    --role-session-name database-access-session \
    --external-id EXTERNAL_ID
```

## Database Connection

### Retrieving Database Credentials

```bash
# Get database credentials from Secrets Manager
aws secretsmanager get-secret-value \
    --secret-id DATABASE_SECRET_ARN \
    --query 'SecretString' \
    --output text | jq -r '.password'
```

### Connecting to the Database

```bash
# Using MySQL client (replace with actual values)
mysql -h DATABASE_ENDPOINT \
      -P 3306 \
      -u admin \
      -p DATABASE_NAME
```

## Monitoring and Observability

### CloudWatch Dashboard

The stack creates a CloudWatch dashboard named "DatabaseSharingMonitoring" with:

- VPC Lattice request metrics
- RDS database performance metrics
- Connection and latency monitoring

### VPC Flow Logs

VPC Flow Logs are automatically enabled for network traffic monitoring and security analysis.

### Log Groups

- VPC Lattice logs: `/aws/vpc-lattice/servicenetwork/{SERVICE_NETWORK_ID}`
- VPC Flow Logs: Auto-created log group

## Security Considerations

### Database Security

- Database is encrypted at rest using AWS managed keys
- Credentials stored securely in AWS Secrets Manager
- Network isolation through VPC and security groups
- Performance Insights enabled for monitoring

### Cross-Account Access

- IAM roles with least privilege principles
- External ID requirement for role assumption
- VPC Lattice authentication policies
- AWS RAM for secure resource sharing

### Network Security

- Private subnets for database placement
- Isolated subnets for VPC Lattice components
- Security groups with minimal required access
- VPC Flow Logs for traffic monitoring

## Cost Optimization

### Estimated Monthly Costs (us-east-1)

- RDS db.t3.micro: ~$12-15/month
- VPC Lattice service network: ~$5-10/month
- CloudWatch monitoring: ~$2-5/month
- **Total estimated**: ~$19-30/month

### Cost Optimization Tips

1. Use appropriate RDS instance sizing
2. Enable RDS storage autoscaling
3. Set up CloudWatch billing alarms
4. Use Reserved Instances for production workloads
5. Monitor and optimize VPC Lattice usage

## Development and Testing

### Running Tests

```bash
# Install development dependencies
pip install -e ".[dev]"

# Run unit tests
pytest tests/

# Run with coverage
pytest --cov=app tests/

# Type checking
mypy app.py

# Code formatting
black app.py

# Security scanning
bandit -r app.py
```

### Code Quality

```bash
# Lint the code
flake8 app.py

# Check for security issues
safety check

# Format code
black app.py setup.py
```

## Troubleshooting

### Common Issues

1. **Bootstrap Required**: Ensure CDK is bootstrapped in your account/region
2. **VPC Lattice Quotas**: Check service quotas for VPC Lattice resources
3. **Cross-Account Permissions**: Verify RAM sharing is enabled
4. **Database Connectivity**: Check security group rules and network ACLs

### Debug Commands

```bash
# Synthesize CloudFormation template
cdk synth

# Compare deployed stack with current code
cdk diff

# View CDK context values
cdk context

# Debug deployment
cdk deploy --debug
```

### Log Analysis

```bash
# Check VPC Lattice logs
aws logs filter-log-events \
    --log-group-name /aws/vpc-lattice/servicenetwork/SERVICE_NETWORK_ID \
    --start-time $(date -d '1 hour ago' +%s)000

# Check RDS logs
aws rds describe-db-log-files \
    --db-instance-identifier DATABASE_ID
```

## Cleanup

To avoid ongoing charges, clean up resources when no longer needed:

```bash
# Destroy the stack
cdk destroy

# Confirm deletion
# Type 'y' when prompted
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually delete:

1. AWS RAM resource shares
2. VPC Lattice associations
3. RDS database (if deletion protection enabled)
4. CloudWatch dashboards
5. Secrets Manager secrets

## Advanced Configuration

### Custom VPC Configuration

To use an existing VPC, modify the `_create_vpc()` method in `app.py`:

```python
# Import existing VPC
vpc = ec2.Vpc.from_lookup(
    self, "ExistingVpc",
    vpc_id="vpc-xxxxxxxx"
)
```

### Multi-Region Deployment

Deploy to multiple regions by specifying different environments:

```bash
# Deploy to us-west-2
cdk deploy -c aws_region=us-west-2

# Deploy to eu-west-1
cdk deploy -c aws_region=eu-west-1
```

### Production Hardening

For production deployments:

1. Enable RDS deletion protection
2. Use Aurora for high availability
3. Implement backup strategies
4. Set up cross-region replication
5. Enable AWS Config for compliance
6. Implement AWS WAF for API protection

## Support and Contributing

### Getting Help

- Review the original recipe documentation
- Check AWS VPC Lattice documentation
- Use AWS Support for service-specific issues
- Check CloudFormation events for deployment issues

### Contributing

To contribute improvements:

1. Follow AWS CDK best practices
2. Include comprehensive type hints
3. Add unit tests for new functionality
4. Update documentation
5. Follow Python PEP 8 style guidelines

## License

This code is provided under the MIT License. See LICENSE file for details.

## Related Resources

- [AWS VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/)
- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [AWS RDS User Guide](https://docs.aws.amazon.com/rds/latest/userguide/)
- [AWS RAM User Guide](https://docs.aws.amazon.com/ram/latest/userguide/)
- [Cross-Account Database Sharing Recipe](../cross-account-database-sharing-lattice-rds.md)