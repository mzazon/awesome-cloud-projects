# Infrastructure as Code for Graph-Based Recommendation Engine

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Graph-Based Recommendation Engine".

## Overview

This recipe demonstrates how to build sophisticated recommendation systems using Amazon Neptune's graph database capabilities. The infrastructure includes a Neptune cluster with read replicas, VPC networking, security groups, and an EC2 client instance for testing graph queries and recommendation algorithms.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture

The deployed infrastructure includes:

- VPC with public and private subnets across multiple AZs
- Neptune cluster with primary instance and read replicas
- Neptune subnet group for multi-AZ deployment
- Security groups with proper Neptune access controls
- EC2 instance for Gremlin client testing
- S3 bucket for sample data storage
- IAM roles and policies for Neptune access

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for creating:
  - Neptune clusters and instances
  - VPC resources (subnets, security groups, route tables)
  - EC2 instances and key pairs
  - S3 buckets
  - IAM roles and policies
- Basic understanding of graph databases and Gremlin query language
- **Estimated Cost**: $12-25/hour for Neptune cluster + $0.10/hour for EC2 instance

### Tool-Specific Prerequisites

#### For CloudFormation
- AWS CLI with CloudFormation permissions

#### For CDK TypeScript
- Node.js 18+ and npm installed
- AWS CDK CLI installed (`npm install -g aws-cdk`)

#### For CDK Python
- Python 3.8+ and pip installed
- AWS CDK CLI installed (`pip install aws-cdk-lib`)

#### For Terraform
- Terraform 1.0+ installed
- AWS provider configured

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name neptune-recommendations \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=KeyPairName,ParameterValue=my-keypair \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name neptune-recommendations

# Get outputs
aws cloudformation describe-stacks \
    --stack-name neptune-recommendations \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy NeptuneRecommendationsStack

# View outputs
cdk outputs
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy NeptuneRecommendationsStack

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

# The script will output connection details and next steps
```

## Post-Deployment Setup

After deploying the infrastructure, you'll need to:

1. **Connect to the EC2 instance** to load sample data and test recommendations:

```bash
# Get connection details from stack outputs
EC2_PUBLIC_IP=$(aws cloudformation describe-stacks \
    --stack-name neptune-recommendations \
    --query 'Stacks[0].Outputs[?OutputKey==`EC2PublicIP`].OutputValue' \
    --output text)

NEPTUNE_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name neptune-recommendations \
    --query 'Stacks[0].Outputs[?OutputKey==`NeptuneEndpoint`].OutputValue' \
    --output text)

# SSH to EC2 instance
ssh -i your-keypair.pem ec2-user@${EC2_PUBLIC_IP}
```

2. **Install Gremlin Python client** on the EC2 instance:

```bash
# On the EC2 instance
sudo yum update -y
sudo yum install -y python3 python3-pip
pip3 install gremlinpython
```

3. **Load sample e-commerce data** using the provided Gremlin scripts:

```bash
# Create sample data (users, products, purchases)
python3 load-sample-data.py --endpoint ${NEPTUNE_ENDPOINT}
```

4. **Test recommendation algorithms**:

```bash
# Test collaborative filtering
python3 test-recommendations.py --endpoint ${NEPTUNE_ENDPOINT} --algorithm collaborative

# Test content-based filtering
python3 test-recommendations.py --endpoint ${NEPTUNE_ENDPOINT} --algorithm content-based
```

## Customization

### Key Variables/Parameters

All implementations support these customization options:

- **Neptune Instance Class**: Default `db.r5.large`, can be changed to `db.r5.xlarge` or higher for better performance
- **Number of Read Replicas**: Default 2, can be adjusted based on read workload requirements
- **VPC CIDR Block**: Default `10.0.0.0/16`, can be customized for network integration
- **Backup Retention**: Default 7 days, can be extended for compliance requirements
- **EC2 Instance Type**: Default `t3.medium`, can be upgraded for development workloads

### Environment-Specific Configurations

#### Development Environment
- Single Neptune instance without read replicas
- Smaller instance types (db.t3.medium)
- Shorter backup retention (1 day)

#### Production Environment
- Multiple read replicas across AZs
- Larger instance types (db.r5.xlarge or higher)
- Extended backup retention (30 days)
- Enhanced monitoring and logging

### Security Customizations

- **Encryption**: All implementations enable storage encryption by default
- **Network Access**: Neptune is deployed in private subnets with no internet access
- **Security Groups**: Restrictive rules allowing only necessary traffic
- **IAM Policies**: Least-privilege access for Neptune operations

## Testing and Validation

### Connection Testing

```bash
# Test Neptune connectivity
python3 -c "
from gremlin_python.driver.driver_remote_connection import DriverRemoteConnection
from gremlin_python.structure.graph import Graph

connection = DriverRemoteConnection('wss://${NEPTUNE_ENDPOINT}:8182/gremlin', 'g')
g = Graph().traversal().withRemote(connection)

print('Vertices:', g.V().count().next())
print('Edges:', g.E().count().next())
connection.close()
print('✅ Connection successful')
"
```

### Sample Queries

```bash
# Find products purchased by similar users (collaborative filtering)
g.V().has('user', 'id', 'user1').out('purchased').in('purchased').where(neq(V().has('user', 'id', 'user1'))).values('name').dedup()

# Find products in same category (content-based filtering)
g.V().has('user', 'id', 'user1').out('purchased').values('category').dedup()

# Performance test
time g.V().hasLabel('user').out('purchased').hasLabel('product').where(values('category').is('Electronics')).count()
```

### Load Testing

For production readiness, test with realistic data volumes:

- Load 10,000+ user vertices
- Load 50,000+ product vertices  
- Load 500,000+ purchase relationships
- Measure query response times under concurrent load

## Monitoring and Troubleshooting

### Neptune Monitoring

Monitor these key metrics:

- **DatabaseConnections**: Track active connections
- **CPUUtilization**: Monitor compute usage
- **VolumeReadIOPs/VolumeWriteIOPs**: Track I/O performance
- **NetworkThroughput**: Monitor data transfer

### Common Issues

1. **Connection Timeouts**: Verify security group rules allow traffic on port 8182
2. **Slow Query Performance**: Consider adding read replicas or upgrading instance types
3. **High CPU Usage**: Optimize Gremlin queries or scale instance size
4. **Storage Growth**: Monitor data volume and implement data lifecycle policies

### Debugging

```bash
# Check Neptune cluster status
aws neptune describe-db-clusters --db-cluster-identifier your-cluster-id

# View Neptune logs
aws logs describe-log-streams --log-group-name /aws/neptune/your-cluster-id

# Test network connectivity from EC2
telnet ${NEPTUNE_ENDPOINT} 8182
```

## Performance Optimization

### Query Optimization
- Use indexes for frequently queried properties
- Minimize traversal depth in complex queries
- Implement query result caching for repeated patterns

### Infrastructure Optimization
- Use read replicas to distribute query load
- Configure appropriate instance types based on workload
- Implement connection pooling in application code

### Cost Optimization
- Use Reserved Instances for predictable workloads
- Monitor and optimize backup retention periods
- Consider Neptune Serverless for variable workloads

## Cleanup

### Using CloudFormation

```bash
# Delete the stack (this will remove all resources)
aws cloudformation delete-stack --stack-name neptune-recommendations

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name neptune-recommendations
```

### Using CDK

```bash
# From the CDK directory
cdk destroy NeptuneRecommendationsStack

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Verification

After automated cleanup, verify these resources are removed:

- Neptune cluster and instances
- VPC and associated networking resources
- EC2 instances and key pairs
- S3 buckets (may require manual deletion if not empty)
- CloudWatch log groups

## Security Considerations

### Data Protection
- All Neptune storage is encrypted at rest using AWS KMS
- Data in transit is encrypted using TLS
- VPC isolation prevents unauthorized network access

### Access Control
- IAM policies follow least-privilege principles
- Security groups restrict network access to necessary ports
- Neptune authentication uses IAM database authentication

### Compliance
- Backup retention supports compliance requirements
- Audit logging available through CloudTrail
- VPC Flow Logs available for network monitoring

## Support and Resources

### AWS Documentation
- [Amazon Neptune User Guide](https://docs.aws.amazon.com/neptune/latest/userguide/)
- [Gremlin Query Language Reference](https://tinkerpop.apache.org/docs/current/reference/)
- [Neptune Best Practices](https://docs.aws.amazon.com/neptune/latest/userguide/best-practices.html)

### Troubleshooting Resources
- [Neptune Troubleshooting Guide](https://docs.aws.amazon.com/neptune/latest/userguide/troubleshooting.html)
- [Performance Tuning](https://docs.aws.amazon.com/neptune/latest/userguide/performance.html)
- [Monitoring and Logging](https://docs.aws.amazon.com/neptune/latest/userguide/monitoring.html)

### Community Resources
- [AWS Neptune Forums](https://forums.aws.amazon.com/forum.jspa?forumID=307)
- [TinkerPop Community](https://tinkerpop.apache.org/community.html)
- [Graph Database Best Practices](https://neo4j.com/developer/graph-data-modeling/)

For issues with this infrastructure code, refer to the original recipe documentation or file an issue in the repository.