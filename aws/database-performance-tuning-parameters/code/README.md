# Infrastructure as Code for Database Performance Tuning with Parameters

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Database Performance Tuning with Parameters".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with RDS, CloudWatch, Performance Insights, and EC2 permissions
- Basic understanding of PostgreSQL performance tuning concepts
- Appropriate IAM permissions for:
  - RDS instance creation and management
  - Parameter group creation and modification
  - VPC, subnet, and security group management
  - CloudWatch dashboard and alarm creation
  - Performance Insights access
- Estimated cost: $50-100 for testing resources

## Quick Start

### Using CloudFormation (AWS)

```bash
# Create the stack with optimized PostgreSQL configuration
aws cloudformation create-stack \
    --stack-name database-performance-tuning \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DBInstanceClass,ParameterValue=db.t3.medium \
                 ParameterKey=Environment,ParameterValue=testing \
    --capabilities CAPABILITY_IAM

# Monitor stack creation progress
aws cloudformation wait stack-create-complete \
    --stack-name database-performance-tuning

# Get database endpoint
aws cloudformation describe-stacks \
    --stack-name database-performance-tuning \
    --query 'Stacks[0].Outputs[?OutputKey==`DatabaseEndpoint`].OutputValue' \
    --output text
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --parameters dbInstanceClass=db.t3.medium

# View deployment outputs
cdk list
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --parameters db-instance-class=db.t3.medium

# View outputs
cdk ls
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned infrastructure
terraform plan -var="db_instance_class=db.t3.medium" \
               -var="environment=testing"

# Apply the configuration
terraform apply -var="db_instance_class=db.t3.medium" \
                -var="environment=testing"

# View important outputs
terraform output database_endpoint
terraform output parameter_group_name
terraform output cloudwatch_dashboard_url
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure with default settings
./scripts/deploy.sh

# Or deploy with custom parameters
DB_INSTANCE_CLASS=db.t3.medium ENVIRONMENT=testing ./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Architecture Overview

This IaC deployment creates:

- **VPC and Networking**: Isolated network environment with subnets across multiple AZs
- **Security Groups**: Properly configured database access controls
- **Custom Parameter Group**: Optimized PostgreSQL configuration for performance
- **RDS Instance**: PostgreSQL database with Performance Insights enabled
- **Read Replica**: Optional read scaling with same optimized parameters
- **CloudWatch Dashboard**: Real-time performance monitoring
- **CloudWatch Alarms**: Automated alerting for performance thresholds
- **Sample Data**: Test dataset for performance validation

## Key Performance Optimizations

The parameter group includes optimizations for:

- **Memory Management**: Optimized shared_buffers, work_mem, and effective_cache_size
- **Query Planning**: Tuned cost parameters for SSD storage
- **Connection Handling**: Increased max_connections for high concurrency
- **I/O Optimization**: Enhanced checkpoint and WAL configurations
- **Parallel Processing**: Configured parallel workers for analytical queries
- **Autovacuum**: Optimized maintenance operations

## Customization Options

### Database Configuration

```bash
# Instance class options
DB_INSTANCE_CLASS=db.t3.medium    # Default
DB_INSTANCE_CLASS=db.t3.large     # Higher performance
DB_INSTANCE_CLASS=db.r5.xlarge    # Memory optimized

# Storage configuration
ALLOCATED_STORAGE=100              # Default (GB)
STORAGE_TYPE=gp3                   # Default
MAX_ALLOCATED_STORAGE=1000         # Auto-scaling limit
```

### Performance Tuning Parameters

Key parameters that can be customized:

- `shared_buffers`: Memory for caching (default: 1024MB)
- `work_mem`: Memory per query operation (default: 16MB)
- `max_connections`: Concurrent connections (default: 200)
- `effective_cache_size`: Query planner cache estimate (default: 3GB)

### Monitoring Configuration

```bash
# Performance Insights retention
PERFORMANCE_INSIGHTS_RETENTION=7   # Days (7-731)

# Enhanced monitoring interval
MONITORING_INTERVAL=60             # Seconds (1, 5, 10, 15, 30, 60)

# CloudWatch alarm thresholds
CPU_THRESHOLD=80                   # Percent
CONNECTION_THRESHOLD=150           # Count
LATENCY_THRESHOLD=0.1             # Seconds
```

## Testing and Validation

### Performance Baseline Testing

```bash
# Connect to database (replace with actual endpoint)
DB_ENDPOINT=$(terraform output -raw database_endpoint)
psql -h $DB_ENDPOINT -U dbadmin -d postgres

# Run performance test queries
\timing on
SELECT COUNT(*) FROM users WHERE created_at >= CURRENT_DATE - INTERVAL '7 days';
```

### Load Testing

```bash
# Use pgbench for load testing
pgbench -h $DB_ENDPOINT -U dbadmin -d postgres \
        -c 10 -j 2 -T 300 \
        --initialize --scale=10

# Monitor Performance Insights during load test
aws pi get-resource-metrics \
    --service-type RDS \
    --identifier <dbi-resource-id> \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period-in-seconds 300
```

### CloudWatch Monitoring

Access the created dashboard:

```bash
# Get dashboard URL
echo "https://console.aws.amazon.com/cloudwatch/home?region=$(aws configure get region)#dashboards:name=Database-Performance-Tuning"

# View real-time metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name CPUUtilization \
    --dimensions Name=DBInstanceIdentifier,Value=<instance-id> \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average,Maximum
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name database-performance-tuning

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name database-performance-tuning
```

### Using CDK (AWS)

```bash
# Destroy the infrastructure
cdk destroy

# Confirm when prompted
# Clean up bootstrap resources if no longer needed
# cdk destroy CDKToolkit
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="db_instance_class=db.t3.medium" \
                  -var="environment=testing"

# Confirm when prompted
# Clean up state files if desired
# rm -rf .terraform* terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm resource deletion when prompted
# Script will verify all resources are removed
```

## Troubleshooting

### Common Issues

1. **Parameter Group Conflicts**
   ```bash
   # Check parameter group status
   aws rds describe-db-parameter-groups \
       --db-parameter-group-name <parameter-group-name>
   
   # Verify parameter application status
   aws rds describe-db-instances \
       --db-instance-identifier <instance-id> \
       --query 'DBInstances[0].DBParameterGroups'
   ```

2. **Performance Insights Access**
   ```bash
   # Verify Performance Insights is enabled
   aws rds describe-db-instances \
       --db-instance-identifier <instance-id> \
       --query 'DBInstances[0].PerformanceInsightsEnabled'
   ```

3. **CloudWatch Permissions**
   ```bash
   # Test CloudWatch access
   aws cloudwatch list-dashboards
   aws cloudwatch describe-alarms
   ```

### Log Analysis

```bash
# Check RDS events
aws rds describe-events \
    --source-identifier <instance-id> \
    --source-type db-instance

# View CloudWatch logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/rds/instance"
```

## Cost Optimization

### Resource Sizing

- Start with `db.t3.medium` for testing
- Monitor CloudWatch metrics to determine if scaling is needed
- Consider Reserved Instances for production workloads
- Use Savings Plans for flexible cost reduction

### Storage Optimization

- GP3 storage provides better price-performance than GP2
- Monitor storage utilization and adjust auto-scaling settings
- Consider cold storage archival for backup retention

### Monitoring Costs

```bash
# Monitor RDS costs
aws ce get-cost-and-usage \
    --time-period Start=2025-01-01,End=2025-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Security Considerations

- Database instances are deployed in private subnets
- Security groups restrict access to necessary ports only
- Encryption at rest is enabled by default
- Enhanced monitoring logs are encrypted
- Parameter group modifications are logged
- IAM roles follow least privilege principle

## Performance Monitoring

### Key Metrics to Monitor

- **CPU Utilization**: Should remain below 80% under normal load
- **Database Connections**: Monitor against max_connections setting
- **Read/Write Latency**: Baseline and track improvements
- **Buffer Cache Hit Ratio**: Higher ratios indicate better memory utilization
- **Query Performance**: Use Performance Insights for slow query analysis

### Alerting Thresholds

The deployment includes CloudWatch alarms for:
- CPU utilization > 80%
- Database connections > 150 (75% of max_connections)
- Read latency > 0.1 seconds
- Write latency > 0.2 seconds

## Advanced Configuration

### Multi-AZ Deployment

```bash
# Enable Multi-AZ for production
MULTI_AZ=true ./scripts/deploy.sh
```

### Read Replica Scaling

```bash
# Deploy with read replica
ENABLE_READ_REPLICA=true ./scripts/deploy.sh
```

### Enhanced Monitoring

```bash
# Increase monitoring frequency
MONITORING_INTERVAL=15 ./scripts/deploy.sh
```

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review AWS RDS documentation for parameter group limitations
3. Consult PostgreSQL performance tuning guides
4. Monitor CloudWatch logs and Performance Insights for detailed diagnostics
5. Refer to the original recipe documentation for implementation details

## Additional Resources

- [Amazon RDS Performance Insights](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html)
- [PostgreSQL Parameter Groups](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithParamGroups.html)
- [RDS CloudWatch Metrics](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/monitoring-cloudwatch.html)
- [PostgreSQL Performance Tuning](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Tuning.html)