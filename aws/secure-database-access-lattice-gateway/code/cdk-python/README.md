# Secure Database Access with VPC Lattice Resource Gateway - CDK Python

This CDK Python application deploys a complete infrastructure solution for secure cross-account database access using AWS VPC Lattice Resource Gateway. The solution enables organizations to share RDS databases across AWS accounts without internet exposure while maintaining strict security controls.

## Architecture Overview

The solution creates:

- **RDS MySQL Database**: Encrypted database in private subnets with enterprise security
- **VPC Lattice Service Network**: Secure application networking layer for cross-account communication
- **Resource Gateway**: Managed ingress point for database traffic abstraction
- **Resource Configuration**: Mapping of database endpoints to VPC Lattice networking
- **Security Groups**: Least privilege network access controls
- **IAM Policies**: Cross-account authentication and authorization controls
- **AWS RAM Share**: Secure resource sharing across AWS accounts

## Prerequisites

- **AWS Account**: Two AWS accounts (database owner and consumer)
- **AWS CLI**: Version 2.x installed and configured with administrative access
- **Python**: Python 3.8 or higher
- **Node.js**: Node.js 14.x or higher (for AWS CDK)
- **AWS CDK**: Version 2.100.0 or higher

### Permission Requirements

The deployment account needs permissions for:
- VPC and networking resources (EC2, VPC)
- RDS database creation and management
- VPC Lattice service network and resource gateway operations
- IAM role and policy management
- AWS RAM resource sharing
- CloudWatch logging and monitoring

## Installation

1. **Clone and navigate to the project**:
   ```bash
   cd aws/secure-database-access-lattice-gateway/code/cdk-python/
   ```

2. **Create and activate Python virtual environment**:
   ```bash
   python -m venv venv
   
   # On macOS/Linux:
   source venv/bin/activate
   
   # On Windows:
   venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Install AWS CDK globally** (if not already installed):
   ```bash
   npm install -g aws-cdk
   ```

5. **Bootstrap CDK** (if not already done in your account/region):
   ```bash
   cdk bootstrap
   ```

## Configuration

### Required Configuration

1. **Update Consumer Account ID** in `cdk.json`:
   ```json
   {
     "context": {
       "consumer_account_id": "123456789012"  // Replace with actual consumer account ID
     }
   }
   ```

2. **Configure Environment** (optional):
   ```bash
   export CDK_DEFAULT_ACCOUNT=123456789012
   export CDK_DEFAULT_REGION=us-east-1
   ```

### Optional Configuration Parameters

Edit `cdk.json` to customize the deployment:

```json
{
  "context": {
    "consumer_account_id": "123456789012",
    "environment": "development",
    "cost_center": "engineering",
    "enable_deletion_protection": false,
    "database_backup_retention_days": 7,
    "database_instance_class": "db.t3.micro",
    "database_allocated_storage": 20,
    "enable_performance_insights": false,
    "enable_enhanced_monitoring": false,
    "create_read_replica": false,
    "multi_az_deployment": false,
    "vpc_cidr": "10.0.0.0/16",
    "create_new_vpc": true,
    "enable_vpc_flow_logs": true,
    "enable_cloudtrail_logging": true
  }
}
```

## Deployment

### 1. Synthesize CloudFormation Template

```bash
cdk synth
```

### 2. Deploy the Stack

```bash
cdk deploy
```

The deployment will create:
- VPC with public, private, and isolated subnets
- RDS MySQL database with encryption and security groups
- VPC Lattice Service Network and Resource Gateway
- Resource Configuration mapping database to VPC Lattice
- IAM policies for cross-account access
- AWS RAM resource share for the consumer account

### 3. Accept RAM Invitation (Consumer Account)

After deployment, the consumer account will receive an AWS RAM invitation:

```bash
# Switch to consumer account credentials
aws configure --profile consumer-account

# List pending invitations
aws ram get-resource-share-invitations --query 'resourceShareInvitations[0].resourceShareInvitationArn' --output text

# Accept the invitation
aws ram accept-resource-share-invitation --resource-share-invitation-arn <invitation-arn>
```

### 4. Configure Consumer VPC Association

```bash
# Associate consumer VPC with shared service network
aws vpc-lattice create-service-network-vpc-association \
    --service-network-identifier <service-network-arn> \
    --vpc-identifier <consumer-vpc-id>
```

## Testing and Validation

### 1. Verify Deployment

```bash
# Check stack status
cdk ls
aws cloudformation describe-stacks --stack-name SecureDatabaseAccessStack

# Verify RDS database
aws rds describe-db-instances --db-instance-identifier <db-instance-id>

# Check VPC Lattice resources
aws vpc-lattice list-service-networks
aws vpc-lattice list-resource-gateways
```

### 2. Test Database Connectivity

From an EC2 instance in the consumer account:

```bash
# Get VPC Lattice DNS name for database access
LATTICE_DNS_NAME=$(aws vpc-lattice get-resource-configuration \
    --resource-configuration-identifier <resource-config-arn> \
    --query 'dnsEntry.domainName' --output text)

# Test connectivity using MySQL client
mysql -h ${LATTICE_DNS_NAME} -P 3306 -u admin -p
```

### 3. Monitor Access Logs

```bash
# Check VPC Flow Logs
aws logs describe-log-groups --log-group-name-prefix "/aws/vpc/flowlogs/"

# Monitor VPC Lattice access logs
aws logs describe-log-groups --log-group-name-prefix "/aws/vpc-lattice/"

# Check RDS logs
aws rds describe-db-log-files --db-instance-identifier <db-instance-id>
```

## Cost Optimization

### Estimated Costs (US East 1)

- **RDS db.t3.micro**: ~$15-20/month
- **VPC Lattice Service Network**: ~$0.025/hour (~$18/month)
- **Resource Gateway**: ~$0.025/hour (~$18/month)  
- **NAT Gateway**: ~$45/month
- **Data Processing**: Variable based on traffic

### Cost Reduction Strategies

1. **Use Smaller Instance Types** for development:
   ```json
   "database_instance_class": "db.t3.micro"
   ```

2. **Reduce Backup Retention**:
   ```json
   "database_backup_retention_days": 1
   ```

3. **Disable Enhanced Monitoring** for development:
   ```json
   "enable_enhanced_monitoring": false,
   "enable_performance_insights": false
   ```

## Security Considerations

### Network Security

- Database deployed in private subnets only
- Security Groups with least privilege access
- VPC Flow Logs enabled for traffic monitoring
- No internet-facing database endpoints

### Data Security

- Encryption at rest enabled for RDS
- Database credentials stored in AWS Secrets Manager
- TLS/SSL encryption for data in transit
- Automated backups with encryption

### Access Control

- IAM policies for cross-account authentication
- VPC Lattice auth policies for service access
- AWS RAM for controlled resource sharing
- CloudTrail logging for audit trails

## Troubleshooting

### Common Issues

1. **VPC Lattice Resources Not Available**:
   - Ensure you're in a supported AWS region
   - Check if VPC Lattice is available in your region
   - Verify IAM permissions for VPC Lattice operations

2. **Database Connection Issues**:
   - Verify security group rules allow MySQL traffic (port 3306)
   - Check Resource Gateway and Resource Configuration status
   - Ensure VPC association is active in consumer account

3. **RAM Share Not Visible**:
   - Verify consumer account ID is correct
   - Check if invitation was sent and needs acceptance
   - Ensure cross-account sharing is enabled

4. **CDK Deployment Failures**:
   - Check AWS CLI credentials and permissions
   - Verify CDK bootstrap was completed
   - Review CloudFormation events for specific errors

### Debug Commands

```bash
# Check CDK context and configuration
cdk context

# Validate CloudFormation template
cdk synth > template.yaml
aws cloudformation validate-template --template-body file://template.yaml

# Check resource dependencies
cdk ls --long

# Get detailed error information
aws cloudformation describe-stack-events --stack-name SecureDatabaseAccessStack
```

## Cleanup

### Delete All Resources

```bash
# Destroy the CDK stack
cdk destroy

# Confirm deletion
# Type 'y' when prompted
```

### Manual Cleanup (if needed)

If automatic cleanup fails, manually delete:

1. **VPC Lattice Resources**:
   ```bash
   # Delete resource configuration associations
   aws vpc-lattice delete-resource-configuration-association --resource-configuration-association-identifier <id>
   
   # Delete resource configurations
   aws vpc-lattice delete-resource-configuration --resource-configuration-identifier <id>
   
   # Delete resource gateways
   aws vpc-lattice delete-resource-gateway --resource-gateway-identifier <id>
   
   # Delete service network VPC associations
   aws vpc-lattice delete-service-network-vpc-association --service-network-vpc-association-identifier <id>
   
   # Delete service networks
   aws vpc-lattice delete-service-network --service-network-identifier <id>
   ```

2. **RAM Resource Shares**:
   ```bash
   aws ram delete-resource-share --resource-share-arn <arn>
   ```

3. **RDS Resources**:
   ```bash
   aws rds delete-db-instance --db-instance-identifier <id> --skip-final-snapshot
   ```

## Development

### Code Structure

```
cdk-python/
├── app.py                          # CDK application entry point
├── requirements.txt                # Python dependencies
├── setup.py                       # Package configuration
├── cdk.json                       # CDK configuration
├── stacks/
│   ├── __init__.py
│   └── secure_database_access_stack.py  # Main stack implementation
└── README.md                      # This file
```

### Running Tests

```bash
# Install development dependencies
pip install -e ".[dev]"

# Run unit tests
pytest tests/

# Run type checking
mypy stacks/

# Format code
black stacks/ app.py

# Lint code
flake8 stacks/ app.py
```

### Adding Features

1. **Additional Database Engines**: Modify the RDS configuration in `secure_database_access_stack.py`
2. **Multi-Region Support**: Add cross-region VPC Lattice configuration
3. **Enhanced Monitoring**: Add CloudWatch dashboards and alarms
4. **Automated Failover**: Implement RDS Proxy integration

## Additional Resources

- [AWS VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/what-is-vpc-lattice.html)
- [VPC Lattice Resource Gateway Documentation](https://docs.aws.amazon.com/vpc-lattice/latest/ug/resource-gateway.html)
- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [RDS Security Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.html)
- [AWS RAM User Guide](https://docs.aws.amazon.com/ram/latest/userguide/what-is.html)

## Support

For issues with this CDK application:

1. Check the troubleshooting section above
2. Review AWS CloudFormation events for deployment issues
3. Consult AWS documentation for service-specific guidance
4. Open an issue in the project repository

## License

This project is licensed under the Apache 2.0 License. See the LICENSE file for details.