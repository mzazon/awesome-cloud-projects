# Infrastructure as Code for Establishing Database High Availability with Multi-AZ Deployments

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Establishing Database High Availability with Multi-AZ Deployments".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon RDS (create clusters, instances, parameter groups, subnet groups)
  - Amazon VPC (create security groups, describe VPCs and subnets)
  - AWS Systems Manager (Parameter Store access)
  - Amazon CloudWatch (create alarms and dashboards)
  - AWS IAM (enhanced monitoring role)
- Estimated cost: $200-400/month for Multi-AZ DB cluster (depends on instance size and storage)

## Architecture Overview

This IaC creates a highly available PostgreSQL database cluster with:

- Multi-AZ Aurora PostgreSQL cluster with semisynchronous replication
- Writer instance (primary) and two reader instances across different AZs
- VPC security group with proper database access controls
- DB subnet group spanning multiple Availability Zones
- Custom DB parameter group optimized for high availability
- CloudWatch monitoring with automated alarms
- Secure credential storage in Systems Manager Parameter Store
- Enhanced monitoring and Performance Insights enabled
- Automated backup configuration with point-in-time recovery

## Quick Start

### Using CloudFormation

```bash
# Create the stack
aws cloudformation create-stack \
    --stack-name multiaz-database-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DatabaseUsername,ParameterValue=dbadmin \
                 ParameterKey=DatabasePassword,ParameterValue=YourSecurePassword123! \
    --capabilities CAPABILITY_IAM

# Monitor stack creation
aws cloudformation wait stack-create-complete \
    --stack-name multiaz-database-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name multiaz-database-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure context (optional)
npx cdk context --set database:password "YourSecurePassword123!"

# Deploy the stack
npx cdk deploy

# View outputs
npx cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
database_username = "dbadmin"
database_password = "YourSecurePassword123!"
cluster_identifier = "multiaz-cluster"
enable_deletion_protection = false
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export DB_PASSWORD="YourSecurePassword123!"
export CLUSTER_NAME="multiaz-cluster"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/status.sh
```

## Configuration Options

### CloudFormation Parameters

- `ClusterIdentifier`: Name for the RDS cluster (default: multiaz-cluster)
- `DatabaseUsername`: Master username for the database (default: dbadmin)
- `DatabasePassword`: Master password (minimum 8 characters, required)
- `InstanceClass`: DB instance class (default: db.r6g.large)
- `EngineVersion`: PostgreSQL engine version (default: 15.4)
- `BackupRetentionPeriod`: Backup retention in days (default: 14)
- `EnableDeletionProtection`: Protect cluster from accidental deletion (default: true)

### CDK Configuration

Customize deployment by modifying context values in `cdk.json` or using CDK context commands:

```bash
# Set custom values
npx cdk context --set database:instanceClass "db.r6g.xlarge"
npx cdk context --set database:engineVersion "15.5"
npx cdk context --set cluster:backupRetention 30
```

### Terraform Variables

Key variables in `variables.tf`:

- `cluster_identifier`: RDS cluster name
- `database_username`: Master database username
- `database_password`: Master database password (sensitive)
- `instance_class`: DB instance class for all instances
- `engine_version`: PostgreSQL engine version
- `backup_retention_period`: Automated backup retention period
- `enable_deletion_protection`: Enable deletion protection
- `enable_enhanced_monitoring`: Enable enhanced monitoring
- `monitoring_interval`: Enhanced monitoring interval in seconds

## Validation & Testing

After deployment, validate the Multi-AZ cluster:

### Test Database Connectivity

```bash
# Get connection endpoints from outputs
WRITER_ENDPOINT=$(aws rds describe-db-clusters \
    --db-cluster-identifier your-cluster-name \
    --query 'DBClusters[0].Endpoint' --output text)

READER_ENDPOINT=$(aws rds describe-db-clusters \
    --db-cluster-identifier your-cluster-name \
    --query 'DBClusters[0].ReaderEndpoint' --output text)

# Test connection (requires PostgreSQL client)
psql -h $WRITER_ENDPOINT -U dbadmin -d postgres -c "SELECT version();"
```

### Verify Multi-AZ Configuration

```bash
# Check cluster configuration
aws rds describe-db-clusters \
    --db-cluster-identifier your-cluster-name \
    --query 'DBClusters[0].{
        Status:Status,
        MultiAZ:MultiAZ,
        AvailabilityZones:AvailabilityZones,
        Members:DBClusterMembers[*].{
            Instance:DBInstanceIdentifier,
            Role:IsClusterWriter,
            AZ:AvailabilityZone
        }
    }'
```

### Test Failover Capability

```bash
# Perform manual failover test
aws rds failover-db-cluster \
    --db-cluster-identifier your-cluster-name

# Monitor failover completion
aws rds wait db-cluster-available \
    --db-cluster-identifier your-cluster-name
```

## Monitoring & Maintenance

### CloudWatch Dashboard

Each implementation creates a CloudWatch dashboard with key metrics:

- CPU Utilization
- Database Connections
- Freeable Memory
- Read/Write IOPS
- Database Throughput

Access the dashboard in the AWS Console under CloudWatch > Dashboards.

### Performance Insights

Performance Insights is enabled for all instances. Access through:

1. AWS Console > RDS > Performance Insights
2. Select your cluster instances
3. Analyze query performance and resource utilization

### Automated Backups

- Automated backups enabled with 14-day retention (configurable)
- Backup window: 03:00-04:00 UTC (configurable)
- Point-in-time recovery available
- Manual snapshots can be created as needed

## Security Considerations

### Network Security

- Database instances deployed in private subnets
- Security group restricts access to VPC CIDR only
- No public accessibility enabled

### Encryption

- Encryption at rest enabled using AWS managed keys
- Encryption in transit enforced for all connections
- CloudWatch Logs encryption enabled

### Access Control

- Database credentials stored securely in Systems Manager Parameter Store
- Enhanced monitoring IAM role follows least privilege principle
- Deletion protection enabled by default

## Cost Optimization

### Instance Sizing

- Start with db.r6g.large instances (included in templates)
- Monitor CPU and memory utilization via CloudWatch
- Scale instance classes based on actual usage patterns

### Storage Optimization

- Aurora storage automatically scales based on usage
- No pre-provisioned storage required
- Storage optimization recommendations available in AWS Console

### Backup Costs

- Automated backups within retention period are free up to cluster storage size
- Extended retention and manual snapshots incur additional charges
- Cross-region backup replication available for disaster recovery

## Cleanup

### Using CloudFormation

```bash
# Disable deletion protection first (if enabled)
aws rds modify-db-cluster \
    --db-cluster-identifier your-cluster-name \
    --no-deletion-protection

# Delete the stack
aws cloudformation delete-stack \
    --stack-name multiaz-database-stack

# Monitor deletion
aws cloudformation wait stack-delete-complete \
    --stack-name multiaz-database-stack
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Disable deletion protection if enabled
aws rds modify-db-cluster \
    --db-cluster-identifier your-cluster-name \
    --no-deletion-protection

# Destroy the stack
npx cdk destroy  # or cdk destroy for Python
```

### Using Terraform

```bash
cd terraform/

# Disable deletion protection
terraform apply -var="enable_deletion_protection=false"

# Destroy infrastructure
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm all resources are deleted
./scripts/verify-cleanup.sh
```

## Troubleshooting

### Common Issues

**1. Insufficient Subnets**
- Error: "DB Subnet Group doesn't meet availability zone coverage requirement"
- Solution: Ensure your VPC has subnets in at least 3 different AZs

**2. IAM Role Missing**
- Error: "Enhanced monitoring requires a monitoring role"
- Solution: The templates create the required role, ensure IAM permissions are sufficient

**3. Password Requirements**
- Error: "MasterUserPassword failed to satisfy constraint"
- Solution: Password must be 8-128 characters, no quotes, @, /, or backslashes

**4. Instance Class Availability**
- Error: "The requested instance class is not available in the specified AZ"
- Solution: Choose an instance class available in all AZs in your region

### Monitoring Deployment

```bash
# Watch cluster creation progress
aws rds describe-db-clusters \
    --db-cluster-identifier your-cluster-name \
    --query 'DBClusters[0].Status'

# Monitor instance creation
aws rds describe-db-instances \
    --query 'DBInstances[?DBClusterIdentifier==`your-cluster-name`].{
        Instance:DBInstanceIdentifier,
        Status:DBInstanceStatus,
        AZ:AvailabilityZone
    }'
```

### Performance Tuning

**Connection Pooling**: Implement connection pooling in applications to manage database connections efficiently.

**Read Scaling**: Direct read-only queries to the reader endpoint to distribute load.

**Monitoring**: Use Performance Insights and CloudWatch metrics to identify optimization opportunities.

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for architecture details
2. Check AWS RDS documentation for service-specific guidance
3. Consult provider documentation for IaC tool-specific issues:
   - [CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
   - [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
   - [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Additional Resources

- [Amazon RDS Multi-AZ Deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.html)
- [Aurora Multi-AZ DB Clusters](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/multi-az-db-clusters-concepts.html)
- [RDS Performance Insights](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html)
- [AWS Well-Architected Framework - Reliability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/welcome.html)