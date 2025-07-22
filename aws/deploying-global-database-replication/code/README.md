# Infrastructure as Code for Deploying Global Database Replication with Aurora Global Database

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Deploying Global Database Replication with Aurora Global Database". This solution deploys a globally distributed Aurora database with write forwarding capabilities across multiple AWS regions.

## Architecture Overview

The infrastructure deploys an Aurora Global Database spanning three regions (us-east-1, eu-west-1, ap-southeast-1) with:

- **Primary Region (us-east-1)**: Primary Aurora cluster with writer and reader instances
- **Secondary Regions (eu-west-1, ap-southeast-1)**: Secondary Aurora clusters with write forwarding enabled
- **Global Database Infrastructure**: Cross-region replication with sub-second latency
- **CloudWatch Monitoring**: Performance monitoring and alerting across all regions

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code with AWS provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured (or AWS CloudShell)
- AWS account with appropriate permissions for Aurora, RDS, and Global Database operations
- Understanding of Aurora cluster architecture and database replication concepts
- Basic knowledge of MySQL/PostgreSQL and database connection management
- Familiarity with multi-region AWS architectures and networking
- Required IAM permissions:
  - `rds:CreateGlobalCluster`
  - `rds:CreateDBCluster`
  - `rds:CreateDBInstance`
  - `rds:DescribeGlobalClusters`
  - `rds:DescribeDBClusters`
  - `rds:DescribeDBInstances`
  - `rds:ModifyDBInstance`
  - `rds:DeleteDBInstance`
  - `rds:DeleteDBCluster`
  - `rds:DeleteGlobalCluster`
  - `cloudwatch:PutDashboard`
  - `cloudwatch:DeleteDashboards`
  - `secretsmanager:GetRandomPassword`
  - `sts:GetCallerIdentity`

> **Warning**: Aurora Global Database incurs significant costs ($500-800/month) with cross-region data transfer charges and requires multiple Aurora clusters running simultaneously across 3 regions with db.r5.large instances.

## Cost Considerations

- **Aurora Instances**: ~$400-600/month for 6 db.r5.large instances across 3 regions
- **Storage**: ~$0.10/GB per month for Aurora storage
- **Cross-Region Data Transfer**: ~$0.02/GB for data replication between regions
- **Backup Storage**: ~$0.021/GB per month for automated backups
- **Performance Insights**: ~$0.009/vCPU-hour for enhanced monitoring

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name aurora-global-db \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=MasterUsername,ParameterValue=globaladmin \
                 ParameterKey=MasterPassword,ParameterValue=YourSecurePassword123! \
                 ParameterKey=DBInstanceClass,ParameterValue=db.r5.large \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name aurora-global-db \
    --region us-east-1 \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Deploy the infrastructure
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=us-east-1

cdk bootstrap
cdk deploy --all \
    --parameters MasterUsername=globaladmin \
    --parameters MasterPassword=YourSecurePassword123! \
    --parameters DBInstanceClass=db.r5.large

# View outputs
cdk output
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Set up Python environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Deploy the infrastructure
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=us-east-1

cdk bootstrap
cdk deploy --all \
    --parameters MasterUsername=globaladmin \
    --parameters MasterPassword=YourSecurePassword123! \
    --parameters DBInstanceClass=db.r5.large

# View outputs
cdk output
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="master_username=globaladmin" \
    -var="master_password=YourSecurePassword123!" \
    -var="db_instance_class=db.r5.large"

# Deploy the infrastructure
terraform apply \
    -var="master_username=globaladmin" \
    -var="master_password=YourSecurePassword123!" \
    -var="db_instance_class=db.r5.large"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
cd scripts/

# Set environment variables
export MASTER_USERNAME="globaladmin"
export MASTER_PASSWORD="YourSecurePassword123!"
export DB_INSTANCE_CLASS="db.r5.large"

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy the infrastructure
./deploy.sh

# Verify deployment
aws rds describe-global-clusters \
    --query 'GlobalClusters[0].Status' \
    --output text
```

## Configuration Parameters

All implementations support the following customization parameters:

| Parameter | Description | Default Value | Valid Values |
|-----------|-------------|---------------|--------------|
| `MasterUsername` | Database master username | `globaladmin` | String (alphanumeric) |
| `MasterPassword` | Database master password | *Required* | String (16+ chars, complex) |
| `DBInstanceClass` | Aurora instance class | `db.r5.large` | `db.r5.large`, `db.r5.xlarge`, `db.r5.2xlarge` |
| `DBEngine` | Aurora database engine | `aurora-mysql` | `aurora-mysql`, `aurora-postgresql` |
| `EngineVersion` | Aurora engine version | `8.0.mysql_aurora.3.02.0` | Valid Aurora versions |
| `BackupRetentionPeriod` | Backup retention in days | `7` | `1-35` |
| `PrimaryRegion` | Primary cluster region | `us-east-1` | Valid AWS regions |
| `SecondaryRegion1` | First secondary region | `eu-west-1` | Valid AWS regions |
| `SecondaryRegion2` | Second secondary region | `ap-southeast-1` | Valid AWS regions |
| `EnableWriteForwarding` | Enable write forwarding | `true` | `true`, `false` |
| `EnablePerformanceInsights` | Enable Performance Insights | `true` | `true`, `false` |
| `EnableCloudWatchLogs` | Enable CloudWatch Logs | `true` | `true`, `false` |

## Deployed Resources

The infrastructure creates the following AWS resources:

### Global Database Components
- **Aurora Global Database**: Container for multi-region database clusters
- **Primary Aurora Cluster**: Writer cluster in primary region (us-east-1)
- **Secondary Aurora Clusters**: Read/write-forwarding clusters in secondary regions

### Database Instances
- **Primary Region**: 1 writer + 1 reader instance
- **Secondary Regions**: 1 writer + 1 reader instance each (6 total instances)

### Monitoring and Observability
- **CloudWatch Dashboard**: Global database monitoring dashboard
- **Performance Insights**: Enhanced database performance monitoring
- **CloudWatch Alarms**: Critical metric alerting (optional)

### Security
- **Database Subnet Groups**: Network isolation for each region
- **Security Groups**: Database access control
- **Parameter Groups**: Database configuration optimization

## Validation and Testing

After deployment, verify the infrastructure:

### 1. Check Global Database Status

```bash
# Verify global database is available
aws rds describe-global-clusters \
    --query 'GlobalClusters[0].{Status:Status,Regions:GlobalClusterMembers[].DBClusterArn}' \
    --output table
```

### 2. Test Database Connectivity

```bash
# Get database endpoints
PRIMARY_ENDPOINT=$(aws rds describe-db-clusters \
    --db-cluster-identifier primary-cluster-* \
    --query 'DBClusters[0].Endpoint' \
    --output text --region us-east-1)

# Test connection (replace with your credentials)
mysql -h $PRIMARY_ENDPOINT -u globaladmin -p \
    --execute "SELECT 'Connection successful' as status;"
```

### 3. Test Write Forwarding

```bash
# Get secondary region endpoint
EU_ENDPOINT=$(aws rds describe-db-clusters \
    --db-cluster-identifier secondary-eu-* \
    --query 'DBClusters[0].Endpoint' \
    --output text --region eu-west-1)

# Test write forwarding
mysql -h $EU_ENDPOINT -u globaladmin -p \
    --execute "
    CREATE DATABASE test_db;
    USE test_db;
    CREATE TABLE test_table (id INT, message VARCHAR(100));
    INSERT INTO test_table VALUES (1, 'Write forwarding works!');"
```

### 4. Verify Replication

```bash
# Check replication lag
aws rds describe-db-clusters \
    --db-cluster-identifier secondary-eu-* \
    --query 'DBClusters[0].GlobalWriteForwardingStatus' \
    --output text --region eu-west-1

# Should return "enabled"
```

### 5. Monitor Performance

```bash
# View CloudWatch dashboard
aws cloudwatch get-dashboard \
    --dashboard-name "Aurora-Global-Database-*" \
    --region us-east-1
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name aurora-global-db \
    --region us-east-1

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name aurora-global-db \
    --region us-east-1 \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Destroy all stacks
cdk destroy --all --force

# Clean up CDK bootstrap (optional)
# cdk bootstrap --destroy
```

### Using Terraform

```bash
cd terraform/

# Destroy the infrastructure
terraform destroy \
    -var="master_username=globaladmin" \
    -var="master_password=YourSecurePassword123!" \
    -var="db_instance_class=db.r5.large"

# Clean up Terraform state
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts

```bash
cd scripts/

# Run cleanup script
./destroy.sh

# Verify cleanup
aws rds describe-global-clusters \
    --query 'GlobalClusters[?Status==`available`]' \
    --output table
```

## Troubleshooting

### Common Issues

1. **Deployment Timeout**: Aurora Global Database creation can take 15-20 minutes
   ```bash
   # Check current status
   aws rds describe-global-clusters --query 'GlobalClusters[0].Status'
   ```

2. **Write Forwarding Not Working**: Verify secondary clusters have write forwarding enabled
   ```bash
   aws rds describe-db-clusters \
       --db-cluster-identifier secondary-* \
       --query 'DBClusters[0].GlobalWriteForwardingStatus'
   ```

3. **High Replication Lag**: Monitor the AuroraGlobalDBReplicationLag metric
   ```bash
   aws cloudwatch get-metric-statistics \
       --namespace AWS/RDS \
       --metric-name AuroraGlobalDBReplicationLag \
       --dimensions Name=DBClusterIdentifier,Value=secondary-eu-* \
       --start-time 2024-01-01T00:00:00Z \
       --end-time 2024-01-01T01:00:00Z \
       --period 300 \
       --statistics Average
   ```

4. **Connection Issues**: Check security group rules and subnet configurations
   ```bash
   # List security groups
   aws ec2 describe-security-groups \
       --filters Name=tag:Name,Values=aurora-global-db-* \
       --query 'SecurityGroups[*].{GroupId:GroupId,GroupName:GroupName}'
   ```

### Performance Optimization

1. **Monitor Key Metrics**:
   - `AuroraGlobalDBReplicationLag`: Keep under 1 second
   - `DatabaseConnections`: Monitor connection pooling
   - `ReadLatency`/`WriteLatency`: Optimize query performance

2. **Instance Sizing**:
   - Start with `db.r5.large` for development
   - Use `db.r5.xlarge` or larger for production workloads
   - Consider Aurora Serverless v2 for variable workloads

3. **Connection Management**:
   - Use connection pooling (RDS Proxy recommended)
   - Implement read/write splitting at application level
   - Use regional endpoints for optimal latency

## Security Considerations

- **Database Credentials**: Use AWS Secrets Manager for production deployments
- **Network Security**: Deploy in private subnets with VPC endpoints
- **Encryption**: Enable encryption at rest and in transit
- **IAM Authentication**: Consider using IAM database authentication
- **Audit Logging**: Enable CloudTrail for API auditing

## Advanced Configuration

### Multi-Region Networking

For production deployments, consider:

```bash
# Enable VPC peering between regions
aws ec2 create-vpc-peering-connection \
    --vpc-id vpc-12345678 \
    --peer-vpc-id vpc-87654321 \
    --peer-region eu-west-1

# Configure route tables for cross-region communication
aws ec2 create-route \
    --route-table-id rtb-12345678 \
    --destination-cidr-block 10.1.0.0/16 \
    --vpc-peering-connection-id pcx-12345678
```

### Automated Failover

Implement automated failover with AWS Lambda:

```bash
# Create Lambda function for failover automation
aws lambda create-function \
    --function-name aurora-global-failover \
    --runtime python3.9 \
    --role arn:aws:iam::123456789012:role/lambda-execution-role \
    --handler index.handler \
    --zip-file fileb://failover-function.zip
```

## Support and Documentation

- **AWS Aurora Global Database**: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html
- **Write Forwarding**: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-write-forwarding.html
- **Performance Insights**: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/USER_PerfInsights.html
- **CloudFormation RDS Resources**: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/AWS_RDS.html
- **Terraform AWS Provider**: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_global_cluster

For issues with this infrastructure code, refer to the original recipe documentation or contact your AWS support team.

## License

This infrastructure code is provided as-is under the MIT License. See the recipe documentation for full terms and conditions.