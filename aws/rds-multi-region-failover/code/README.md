# Infrastructure as Code for Advanced RDS Multi-AZ Deployments with Cross-Region Failover

This directory contains Infrastructure as Code (IaC) implementations for the recipe "RDS Multi-Region Failover Strategy".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - RDS (create instances, parameter groups, subnet groups, snapshots)
  - Route 53 (create hosted zones, health checks, DNS records)
  - CloudWatch (create alarms, metrics)
  - IAM (create roles and policies)
  - VPC (access to subnets and security groups)
- VPC setup in both primary (us-east-1) and secondary (us-west-2) regions
- Estimated cost: $800-1,200/month for db.r5.xlarge instances

## Architecture Overview

This implementation creates:

- Multi-AZ PostgreSQL RDS instance in primary region (us-east-1)
- Cross-region read replica in secondary region (us-west-2)
- Custom DB parameter group optimized for high availability
- CloudWatch alarms for database monitoring
- Route 53 health checks and DNS failover
- Cross-region automated backup replication
- IAM roles for automated promotion capabilities

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name advanced-rds-multi-az \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DBMasterPassword,ParameterValue=YourSecurePassword123! \
                 ParameterKey=PrimaryVPCSubnet1,ParameterValue=subnet-12345678 \
                 ParameterKey=PrimaryVPCSubnet2,ParameterValue=subnet-87654321 \
                 ParameterKey=SecondaryVPCSubnet1,ParameterValue=subnet-abcd1234 \
                 ParameterKey=SecondaryVPCSubnet2,ParameterValue=subnet-4321dcba \
                 ParameterKey=DatabaseSecurityGroup,ParameterValue=sg-financial-db \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name advanced-rds-multi-az \
    --region us-east-1
```

### Using CDK TypeScript

```bash
# Install dependencies
cd cdk-typescript/
npm install

# Configure environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=us-east-1

# Deploy the infrastructure
cdk deploy AdvancedRdsMultiAzStack \
    --parameters dbMasterPassword=YourSecurePassword123! \
    --parameters primaryVpcSubnet1=subnet-12345678 \
    --parameters primaryVpcSubnet2=subnet-87654321 \
    --parameters secondaryVpcSubnet1=subnet-abcd1234 \
    --parameters secondaryVpcSubnet2=subnet-4321dcba \
    --parameters databaseSecurityGroup=sg-financial-db
```

### Using CDK Python

```bash
# Install dependencies
cd cdk-python/
pip install -r requirements.txt

# Configure environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=us-east-1

# Deploy the infrastructure
cdk deploy AdvancedRdsMultiAzStack \
    --parameters dbMasterPassword=YourSecurePassword123! \
    --parameters primaryVpcSubnet1=subnet-12345678 \
    --parameters primaryVpcSubnet2=subnet-87654321 \
    --parameters secondaryVpcSubnet1=subnet-abcd1234 \
    --parameters secondaryVpcSubnet2=subnet-4321dcba \
    --parameters databaseSecurityGroup=sg-financial-db
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the deployment plan
terraform plan \
    -var="db_master_password=YourSecurePassword123!" \
    -var="primary_vpc_subnet_1=subnet-12345678" \
    -var="primary_vpc_subnet_2=subnet-87654321" \
    -var="secondary_vpc_subnet_1=subnet-abcd1234" \
    -var="secondary_vpc_subnet_2=subnet-4321dcba" \
    -var="database_security_group=sg-financial-db"

# Apply the configuration
terraform apply \
    -var="db_master_password=YourSecurePassword123!" \
    -var="primary_vpc_subnet_1=subnet-12345678" \
    -var="primary_vpc_subnet_2=subnet-87654321" \
    -var="secondary_vpc_subnet_1=subnet-abcd1234" \
    -var="secondary_vpc_subnet_2=subnet-4321dcba" \
    -var="database_security_group=sg-financial-db"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export DB_MASTER_PASSWORD="YourSecurePassword123!"
export PRIMARY_VPC_SUBNET_1="subnet-12345678"
export PRIMARY_VPC_SUBNET_2="subnet-87654321"
export SECONDARY_VPC_SUBNET_1="subnet-abcd1234"
export SECONDARY_VPC_SUBNET_2="subnet-4321dcba"
export DATABASE_SECURITY_GROUP="sg-financial-db"

# Deploy the infrastructure
./scripts/deploy.sh
```

## Configuration Parameters

### Required Parameters

- **DB Master Password**: Strong password for database administrator account (minimum 8 characters)
- **VPC Subnets**: Subnet IDs for primary and secondary regions (2 subnets each for Multi-AZ)
- **Security Group**: Security group ID for database access

### Optional Parameters

- **DB Instance Class**: RDS instance type (default: db.r5.xlarge)
- **Allocated Storage**: Database storage in GB (default: 500)
- **Backup Retention**: Backup retention period in days (default: 30)
- **Environment**: Environment name for resource tagging (default: production)

## Post-Deployment Verification

### 1. Verify Multi-AZ Configuration

```bash
# Check Multi-AZ status
aws rds describe-db-instances \
    --db-instance-identifier financial-db-xxxxx \
    --region us-east-1 \
    --query 'DBInstances[0].[MultiAZ,AvailabilityZone,SecondaryAvailabilityZone]' \
    --output table
```

### 2. Test Cross-Region Replication

```bash
# Check replica lag
aws cloudwatch get-metric-statistics \
    --region us-west-2 \
    --namespace AWS/RDS \
    --metric-name ReplicaLag \
    --dimensions Name=DBInstanceIdentifier,Value=financial-db-replica-xxxxx \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average
```

### 3. Test DNS Failover

```bash
# Test DNS resolution
nslookup db.financial-db.internal

# Test with dig for detailed information
dig @8.8.8.8 db.financial-db.internal CNAME
```

### 4. Verify CloudWatch Alarms

```bash
# List CloudWatch alarms
aws cloudwatch describe-alarms \
    --alarm-name-prefix "financial-db" \
    --region us-east-1
```

## Testing Failover

### Multi-AZ Failover Test

```bash
# Test automatic failover (primary region)
aws rds reboot-db-instance \
    --db-instance-identifier financial-db-xxxxx \
    --force-failover \
    --region us-east-1

# Monitor failover completion
aws rds wait db-instance-available \
    --db-instance-identifier financial-db-xxxxx \
    --region us-east-1
```

### Cross-Region Failover Simulation

```bash
# Promote read replica to standalone database (disaster recovery scenario)
aws rds promote-read-replica \
    --db-instance-identifier financial-db-replica-xxxxx \
    --region us-west-2

# Update DNS to point to promoted replica (manual step)
# This would typically be automated in a production environment
```

## Monitoring and Alerts

### Key Metrics to Monitor

- **DatabaseConnections**: Monitor connection usage
- **ReplicaLag**: Track cross-region replication delay
- **CPUUtilization**: Database performance monitoring
- **FreeableMemory**: Memory utilization tracking
- **DatabaseConnections**: Connection pool monitoring

### CloudWatch Dashboards

The implementation creates CloudWatch alarms for:

- High connection count (threshold: 80 connections)
- Excessive replica lag (threshold: 300 seconds)
- Database CPU utilization
- Free memory monitoring

## Security Considerations

### Database Security

- Encryption at rest enabled for all instances
- Encryption in transit enforced
- Master password stored securely (consider AWS Secrets Manager)
- Database subnet groups restrict network access
- Security groups limit connection sources

### IAM Security

- Least privilege IAM roles for automation
- Cross-region permissions for disaster recovery
- Monitoring role for CloudWatch integration

### Network Security

- Private subnets for database instances
- Security group rules for controlled access
- VPC isolation between regions

## Cost Optimization

### Cost Factors

- **RDS Instances**: db.r5.xlarge instances in two regions
- **Storage**: 500GB GP3 storage with backup retention
- **Data Transfer**: Cross-region replication charges
- **Route 53**: Health checks and DNS queries
- **CloudWatch**: Alarm monitoring and metrics

### Cost Reduction Strategies

- Use smaller instance types for development/testing
- Implement automated start/stop for non-production environments
- Optimize backup retention periods
- Monitor data transfer costs for cross-region replication

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name advanced-rds-multi-az \
    --region us-east-1

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name advanced-rds-multi-az \
    --region us-east-1
```

### Using CDK

```bash
# Destroy CDK stack
cd cdk-typescript/  # or cdk-python/
cdk destroy AdvancedRdsMultiAzStack
```

### Using Terraform

```bash
# Destroy Terraform-managed infrastructure
cd terraform/
terraform destroy \
    -var="db_master_password=YourSecurePassword123!" \
    -var="primary_vpc_subnet_1=subnet-12345678" \
    -var="primary_vpc_subnet_2=subnet-87654321" \
    -var="secondary_vpc_subnet_1=subnet-abcd1234" \
    -var="secondary_vpc_subnet_2=subnet-4321dcba" \
    -var="database_security_group=sg-financial-db"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Subnet Group Creation Fails**
   - Verify subnet IDs exist in correct regions
   - Ensure subnets are in different Availability Zones

2. **Cross-Region Replica Creation Fails**
   - Check source database is in available state
   - Verify cross-region permissions
   - Ensure target region has required subnet group

3. **Route 53 Health Checks Fail**
   - Verify database endpoints are accessible
   - Check security group rules for health check sources
   - Ensure DNS configuration is correct

4. **High Replication Lag**
   - Monitor network connectivity between regions
   - Check source database performance
   - Review parameter group settings

### Support Resources

- [Amazon RDS User Guide](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/)
- [Amazon Route 53 Developer Guide](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/)
- [RDS Multi-AZ Deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZSingleStandby.html)

## Customization

### Environment-Specific Configurations

Modify the variable definitions in each implementation to customize:

- Instance types and storage configurations
- Backup retention and maintenance windows
- Monitoring thresholds and alert destinations
- Network configurations and security groups
- Region selection for primary and secondary deployments

### Advanced Configurations

Consider implementing these enhancements:

- Automated promotion using Lambda functions
- Blue-Green deployment capabilities
- Enhanced monitoring with custom metrics
- Cross-region VPC peering for private connectivity
- Automated backup testing and validation

## Support

For issues with this infrastructure code, refer to:

1. The original recipe documentation
2. AWS provider documentation for your chosen IaC tool
3. AWS support resources and community forums
4. Provider-specific troubleshooting guides

---

**Note**: This infrastructure creates production-grade resources that incur significant costs. Always review the estimated costs and clean up resources when no longer needed.