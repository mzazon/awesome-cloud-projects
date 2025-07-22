# Infrastructure as Code for Database Query Caching with ElastiCache

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Database Query Caching with ElastiCache".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - ElastiCache (create/modify clusters, parameter groups, subnet groups)
  - RDS (create/modify databases and subnet groups)
  - EC2 (create/modify instances and security groups)
  - VPC (describe VPCs and subnets)
- Node.js 18+ and npm (for CDK TypeScript)
- Python 3.8+ and pip (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Estimated cost: $50-100/month for test environment

> **Warning**: This infrastructure creates billable AWS resources. Clean up all resources after testing to avoid ongoing charges.

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name database-cache-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=CacheNodeType,ParameterValue=cache.t3.micro \
                 ParameterKey=DBInstanceClass,ParameterValue=db.t3.micro \
    --capabilities CAPABILITY_IAM

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name database-cache-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name database-cache-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
cdk outputs
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
cdk outputs
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/status.sh
```

## Architecture Overview

The deployed infrastructure includes:

- **ElastiCache Redis Cluster**: Multi-AZ replication group with automatic failover
- **RDS MySQL Database**: Primary database for caching demonstration
- **EC2 Instance**: Application server with Redis and MySQL clients
- **VPC Security Groups**: Network security controls
- **Subnet Groups**: Multi-AZ placement for high availability
- **Parameter Groups**: Custom Redis configuration for optimal caching

## Configuration Options

### Common Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| CacheNodeType | ElastiCache node instance type | cache.t3.micro |
| DBInstanceClass | RDS instance class | db.t3.micro |
| MultiAZ | Enable Multi-AZ deployment | true |
| CacheParameterGroupFamily | Redis parameter group family | redis7.x |
| BackupRetentionPeriod | Database backup retention | 0 (disabled) |

### Environment Variables (Scripts)

```bash
export AWS_REGION="us-east-1"                    # Target AWS region
export CACHE_NODE_TYPE="cache.t3.micro"          # Cache instance type
export DB_INSTANCE_CLASS="db.t3.micro"           # Database instance type
export ENABLE_MULTI_AZ="true"                    # Multi-AZ deployment
export CACHE_TTL="300"                            # Default cache TTL
```

## Testing the Cache Implementation

### Connect to the Application Server

```bash
# Get EC2 instance ID from outputs
INSTANCE_ID=$(aws cloudformation describe-stacks \
    --stack-name database-cache-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`EC2InstanceId`].OutputValue' \
    --output text)

# Connect via Session Manager (no SSH key required)
aws ssm start-session --target "${INSTANCE_ID}"
```

### Test Cache Operations

```bash
# Get Redis endpoint from outputs
REDIS_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name database-cache-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`RedisEndpoint`].OutputValue' \
    --output text)

# Test basic Redis operations
redis-cli -h "${REDIS_ENDPOINT}" ping

# Set and get cached data
redis-cli -h "${REDIS_ENDPOINT}" SET "test:key" "Hello Cache" EX 300
redis-cli -h "${REDIS_ENDPOINT}" GET "test:key"

# Monitor cache statistics
redis-cli -h "${REDIS_ENDPOINT}" INFO stats
```

### Performance Testing

```bash
# Run cache performance benchmarks
redis-cli -h "${REDIS_ENDPOINT}" --latency-history -i 1

# Test cache vs database performance
python3 /home/ec2-user/cache_demo.py
```

## Monitoring and Observability

### CloudWatch Metrics

The deployment automatically enables monitoring for:

- **ElastiCache Metrics**: Cache hits/misses, CPU utilization, memory usage
- **RDS Metrics**: Database connections, CPU utilization, read/write latency
- **EC2 Metrics**: Instance health and resource utilization

### Key Performance Indicators

```bash
# Monitor cache hit ratio
aws cloudwatch get-metric-statistics \
    --namespace AWS/ElastiCache \
    --metric-name CacheHitRate \
    --dimensions Name=CacheClusterId,Value=your-cache-cluster \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-01T23:59:59Z \
    --period 3600 \
    --statistics Average

# Monitor database connections
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --dimensions Name=DBInstanceIdentifier,Value=your-db-instance \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-01T23:59:59Z \
    --period 3600 \
    --statistics Average
```

## Security Considerations

### Network Security

- Security groups restrict Redis access to port 6379 within VPC only
- RDS access limited to application security groups
- No public access to cache or database endpoints
- EC2 instance uses Session Manager for secure access

### Data Protection

- Redis AUTH can be enabled via parameter groups
- RDS encryption at rest available (not enabled in test configuration)
- VPC provides network isolation
- Security groups implement least privilege access

## Troubleshooting

### Common Issues

1. **Cache Connection Timeouts**
   ```bash
   # Check security group rules
   aws ec2 describe-security-groups --group-ids sg-xxxxxxxxx
   
   # Verify cache cluster status
   aws elasticache describe-replication-groups \
       --replication-group-id your-cache-cluster
   ```

2. **Database Connection Issues**
   ```bash
   # Check RDS instance status
   aws rds describe-db-instances \
       --db-instance-identifier your-db-instance
   
   # Test connectivity from EC2
   mysql -h your-db-endpoint -u admin -p
   ```

3. **Performance Issues**
   ```bash
   # Monitor cache memory usage
   redis-cli -h "${REDIS_ENDPOINT}" INFO memory
   
   # Check eviction policy
   redis-cli -h "${REDIS_ENDPOINT}" CONFIG GET maxmemory-policy
   ```

### Log Analysis

```bash
# CloudWatch Logs for debugging
aws logs describe-log-groups
aws logs get-log-events --log-group-name /aws/elasticache/redis
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name database-cache-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name database-cache-stack
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy
```

### Using CDK Python
```bash
cd cdk-python/
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completed
./scripts/verify-cleanup.sh
```

## Customization

### Scaling Configuration

```yaml
# CloudFormation parameter example
CacheNodeType: cache.r6g.large        # Larger cache instances
NumCacheClusters: 3                   # More cache nodes
DBInstanceClass: db.r5.large          # Larger database instance
```

### Advanced Cache Configuration

```bash
# Custom parameter group settings
aws elasticache modify-cache-parameter-group \
    --cache-parameter-group-name custom-redis-params \
    --parameter-name-values \
    "ParameterName=maxmemory-policy,ParameterValue=allkeys-lru" \
    "ParameterName=timeout,ParameterValue=300"
```

### Multi-Region Deployment

For multi-region setups, consider:
- ElastiCache Global Datastore for cross-region replication
- RDS Cross-Region Read Replicas
- Application-level cache warming strategies

## Cost Optimization

### Right-Sizing Recommendations

- Start with t3.micro instances for development/testing
- Monitor memory utilization and scale up as needed
- Use Reserved Instances for production workloads
- Consider Spot Instances for non-critical workloads

### Cost Monitoring

```bash
# Estimate monthly costs
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Support

- **Recipe Documentation**: Refer to the original recipe markdown for detailed implementation guidance
- **AWS Documentation**: [ElastiCache User Guide](https://docs.aws.amazon.com/elasticache/)
- **Best Practices**: [Database Caching Strategies](https://docs.aws.amazon.com/whitepapers/latest/database-caching-strategies-using-redis/)
- **Community Support**: AWS Developer Forums and Stack Overflow

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow AWS Well-Architected Framework principles
3. Update documentation for any configuration changes
4. Consider cost and security implications of modifications

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and modify according to your organization's security and compliance requirements before production use.