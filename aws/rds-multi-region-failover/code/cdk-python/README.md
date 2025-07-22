# Advanced RDS Multi-AZ with Cross-Region Failover - CDK Python

This CDK Python application implements an enterprise-grade RDS Multi-AZ deployment with cross-region disaster recovery capabilities. The architecture provides high availability through Multi-AZ deployment in the primary region and disaster recovery through cross-region read replicas with automated DNS failover.

## Architecture Overview

The solution deploys:

- **Primary Region (us-east-1)**:
  - Multi-AZ PostgreSQL RDS instance with synchronous replication
  - Custom parameter group optimized for high availability
  - CloudWatch monitoring and alarms
  - VPC with public and private subnets

- **Secondary Region (us-west-2)**:
  - Cross-region read replica
  - Enhanced monitoring and replica lag alarms
  - Dedicated VPC infrastructure

- **Global Services**:
  - Route 53 private hosted zone with health checks
  - DNS failover routing between regions
  - IAM roles for automated promotion

## Prerequisites

Before deploying this CDK application, ensure you have:

### Required Tools

1. **AWS CLI v2** installed and configured
   ```bash
   aws configure
   ```

2. **AWS CDK CLI** installed
   ```bash
   npm install -g aws-cdk
   ```

3. **Python 3.8+** with pip
   ```bash
   python --version
   pip --version
   ```

4. **Node.js** (for CDK CLI)
   ```bash
   node --version
   npm --version
   ```

### AWS Account Setup

1. **Bootstrap CDK** in both regions:
   ```bash
   # Bootstrap primary region
   cdk bootstrap aws://ACCOUNT-NUMBER/us-east-1
   
   # Bootstrap secondary region
   cdk bootstrap aws://ACCOUNT-NUMBER/us-west-2
   ```

2. **Set environment variables**:
   ```bash
   export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
   export AWS_DEFAULT_REGION=us-east-1
   ```

3. **Required IAM permissions** for deployment:
   - RDS full access
   - EC2 full access (for VPC and security groups)
   - Route 53 full access
   - CloudWatch full access
   - SNS full access
   - IAM role creation and policy attachment
   - Secrets Manager access

### Cost Considerations

- **Estimated monthly cost**: $800-1,200 for production-grade db.r5.xlarge instances
- **Storage costs**: Additional charges for 500GB GP3 storage and backups
- **Data transfer**: Cross-region replication and backup costs
- **Route 53**: Health check and hosted zone charges

> **Warning**: This configuration uses production-grade instance types and will incur significant costs. Consider using smaller instances (e.g., db.t3.medium) for testing.

## Installation and Deployment

### 1. Clone and Setup

```bash
# Navigate to the CDK Python directory
cd aws/advanced-rds-multi-az-cross-region-failover/code/cdk-python/

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### 2. Verify CDK Configuration

```bash
# List all stacks
cdk list

# Synthesize CloudFormation templates
cdk synth

# View differences (if updating existing deployment)
cdk diff
```

### 3. Deploy Infrastructure

Deploy stacks in the correct order due to dependencies:

```bash
# Deploy credentials and VPC stacks first
cdk deploy DatabaseCredentials PrimaryVpc SecondaryVpc

# Deploy primary RDS stack
cdk deploy AdvancedRdsMultiAzPrimary

# Deploy cross-region replica
cdk deploy CrossRegionReplica

# Deploy Route 53 failover
cdk deploy Route53Failover

# Deploy promotion automation
cdk deploy PromotionAutomation

# Or deploy all stacks at once
cdk deploy --all
```

### 4. Post-Deployment Configuration

After successful deployment:

1. **Configure SNS email notifications**:
   ```bash
   # Get SNS topic ARN from stack outputs
   TOPIC_ARN=$(aws cloudformation describe-stacks \
     --stack-name AdvancedRdsMultiAzPrimary \
     --query 'Stacks[0].Outputs[?OutputKey==`AlertTopicArn`].OutputValue' \
     --output text)
   
   # Subscribe email to topic
   aws sns subscribe \
     --topic-arn $TOPIC_ARN \
     --protocol email \
     --notification-endpoint your-email@example.com
   ```

2. **Verify database connectivity**:
   ```bash
   # Get database endpoint
   DB_ENDPOINT=$(aws cloudformation describe-stacks \
     --stack-name AdvancedRdsMultiAzPrimary \
     --query 'Stacks[0].Outputs[?OutputKey==`PrimaryInstanceEndpoint`].OutputValue' \
     --output text)
   
   echo "Primary database endpoint: $DB_ENDPOINT"
   ```

3. **Test DNS failover**:
   ```bash
   # Get DNS name for database
   DNS_NAME=$(aws cloudformation describe-stacks \
     --stack-name Route53Failover \
     --query 'Stacks[0].Outputs[?OutputKey==`DatabaseDnsName`].OutputValue' \
     --output text)
   
   echo "Database DNS name: $DNS_NAME"
   ```

## Stack Architecture

### Core Stacks

1. **DatabaseCredentials**: Manages database credentials in AWS Secrets Manager
2. **PrimaryVpc**: VPC infrastructure for primary region
3. **SecondaryVpc**: VPC infrastructure for secondary region
4. **AdvancedRdsMultiAzPrimary**: Primary Multi-AZ RDS instance and monitoring
5. **CrossRegionReplica**: Read replica in secondary region
6. **Route53Failover**: DNS failover configuration
7. **PromotionAutomation**: IAM roles for automated promotion

### Key Components

- **RDS Instance**: PostgreSQL 15.4 with Multi-AZ deployment
- **Security Groups**: Restrict database access to VPC CIDR
- **Parameter Groups**: Optimized for high availability workloads
- **CloudWatch Alarms**: Monitor connections, CPU, and replica lag
- **Route 53**: Private hosted zone with health checks
- **IAM Roles**: Enhanced monitoring and promotion automation

## Monitoring and Alerting

### CloudWatch Alarms

The application creates several alarms:

1. **Database Connections**: Alerts when connections exceed 80
2. **CPU Utilization**: Alerts when CPU exceeds 80% for 15 minutes
3. **Replica Lag**: Alerts when lag exceeds 5 minutes

### Accessing Metrics

```bash
# View RDS metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=financial-db-primary \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

## Testing Failover

### Multi-AZ Failover Test

```bash
# Force failover to test Multi-AZ capability
aws rds reboot-db-instance \
  --db-instance-identifier financial-db-primary \
  --force-failover

# Monitor failover completion
aws rds wait db-instance-available \
  --db-instance-identifier financial-db-primary
```

### Cross-Region Promotion Test

```bash
# Promote read replica (CAUTION: This breaks replication)
aws rds promote-read-replica \
  --db-instance-identifier financial-db-replica \
  --region us-west-2
```

## Security Best Practices

### Implemented Security Measures

1. **Encryption**: All storage encrypted at rest
2. **Network Security**: Database isolated in private subnets
3. **Access Control**: Security groups restrict database access
4. **Credentials**: Managed through AWS Secrets Manager
5. **Monitoring**: Enhanced monitoring enabled
6. **Backup Security**: Cross-region backup replication

### Additional Security Recommendations

1. **Enable VPC Flow Logs** for network monitoring
2. **Implement AWS Config** for compliance monitoring
3. **Use AWS GuardDuty** for threat detection
4. **Enable CloudTrail** for API logging
5. **Rotate database credentials** regularly

## Backup and Recovery

### Automated Backups

- **Retention Period**: 30 days
- **Backup Window**: 03:00-04:00 UTC (low traffic hours)
- **Cross-Region Replication**: 7-day retention in secondary region
- **Point-in-Time Recovery**: Available for full retention period

### Manual Snapshots

```bash
# Create manual snapshot
aws rds create-db-snapshot \
  --db-instance-identifier financial-db-primary \
  --db-snapshot-identifier financial-db-manual-$(date +%Y%m%d)

# Copy snapshot to another region
aws rds copy-db-snapshot \
  --source-db-snapshot-identifier financial-db-manual-$(date +%Y%m%d) \
  --target-db-snapshot-identifier financial-db-manual-$(date +%Y%m%d) \
  --source-region us-east-1 \
  --region us-west-2
```

## Cleanup

### Complete Infrastructure Removal

```bash
# Destroy all stacks (in reverse dependency order)
cdk destroy PromotionAutomation Route53Failover CrossRegionReplica AdvancedRdsMultiAzPrimary SecondaryVpc PrimaryVpc DatabaseCredentials

# Confirm each stack deletion when prompted
```

### Manual Cleanup (if needed)

```bash
# List any remaining snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier financial-db-primary

# Delete manual snapshots
aws rds delete-db-snapshot \
  --db-snapshot-identifier SNAPSHOT-ID

# Verify all resources are deleted
aws rds describe-db-instances
aws route53 list-hosted-zones
```

## Troubleshooting

### Common Issues

1. **Bootstrap Required**:
   ```bash
   Error: Need to perform AWS CDK bootstrap
   Solution: cdk bootstrap aws://ACCOUNT/REGION
   ```

2. **Permission Denied**:
   ```bash
   Error: User is not authorized to perform: rds:CreateDBInstance
   Solution: Ensure IAM user has required RDS permissions
   ```

3. **VPC Limits**:
   ```bash
   Error: VPC limit exceeded
   Solution: Delete unused VPCs or request limit increase
   ```

4. **Cross-Region Issues**:
   ```bash
   Error: Cross-region resource reference not supported
   Solution: Ensure proper stack dependencies are configured
   ```

### Debug Commands

```bash
# Check CDK version
cdk --version

# View detailed errors
cdk deploy --verbose

# Check CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name AdvancedRdsMultiAzPrimary

# Validate IAM permissions
aws iam simulate-principal-policy \
  --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
  --action-names rds:CreateDBInstance \
  --resource-arns "*"
```

## Support and Documentation

### Additional Resources

- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Amazon RDS Multi-AZ Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.html)
- [Route 53 Health Checks](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover.html)
- [RDS Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_BestPractices.html)

### Getting Help

For issues with this CDK application:

1. Check CloudFormation stack events for detailed error messages
2. Review CloudWatch logs for Lambda functions (if any)
3. Verify IAM permissions using the AWS IAM Policy Simulator
4. Consult AWS documentation for service-specific guidance

## Contributing

To contribute improvements to this CDK application:

1. Follow Python PEP 8 style guidelines
2. Add comprehensive type hints
3. Update documentation for any changes
4. Test deployments in development environment
5. Ensure all resources are properly tagged

## License

This CDK application is provided under the MIT license. See the original recipe documentation for complete terms and conditions.