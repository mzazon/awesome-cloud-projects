# Neptune Graph Database Recommendation Engine - CDK Python

This CDK Python application deploys a complete Amazon Neptune graph database infrastructure for building recommendation engines. The solution demonstrates how to leverage graph databases for discovering complex relationships between users, products, and behaviors in e-commerce applications.

## Architecture Overview

The CDK application creates the following infrastructure:

- **VPC Infrastructure**: Multi-AZ VPC with public and private subnets
- **Neptune Cluster**: Primary and replica instances with encryption and automated backups
- **EC2 Client**: Gremlin client instance with pre-installed tools
- **S3 Storage**: Sample data bucket with e-commerce graph data
- **Security**: Least-privilege IAM roles and security groups

## Prerequisites

- AWS CLI v2 installed and configured
- Python 3.8 or higher
- Node.js 18.x or higher (for CDK CLI)
- AWS CDK v2 installed globally: `npm install -g aws-cdk`

## Quick Start

### 1. Install Dependencies

```bash
# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install Python dependencies
pip install -r requirements.txt
```

### 2. Configure AWS Environment

```bash
# Set your AWS account and region
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)
```

### 3. Bootstrap CDK (First Time Only)

```bash
cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/$CDK_DEFAULT_REGION
```

### 4. Deploy Infrastructure

```bash
# Deploy all stacks
cdk deploy --all --require-approval never

# Or deploy stacks individually
cdk deploy NeptuneNetworkingStack
cdk deploy NeptuneStorageStack
cdk deploy NeptuneClusterStack
cdk deploy NeptuneComputeStack
```

### 5. Access Neptune Cluster

After deployment, connect to the EC2 instance to interact with Neptune:

```bash
# Get connection details from stack outputs
INSTANCE_ID=$(aws cloudformation describe-stacks \
    --stack-name NeptuneComputeStack \
    --query 'Stacks[0].Outputs[?OutputKey==`EC2InstanceId`].OutputValue' \
    --output text)

# Connect using EC2 Instance Connect
aws ec2-instance-connect ssh --instance-id $INSTANCE_ID --os-user ec2-user
```

Once connected to the EC2 instance:

```bash
# Load environment variables
source ~/.neptune-env

# Test Neptune connection
python3 test-connection.py

# Download sample data
./download-sample-data.sh

# Start Gremlin console
cd /opt/gremlin-console
bin/gremlin.sh
```

## Sample Queries

### Load Sample Data

In the Gremlin console:

```groovy
// Connect to Neptune
:remote connect tinkerpop.server conf/neptune-remote.yaml
:remote console

// Load the sample data
:load ~/sample-data/load-data.groovy
```

### Collaborative Filtering Recommendations

```groovy
// Find users similar to user1
:load ~/sample-data/collaborative-filtering.groovy

// Get recommendations for a specific user
g.V().has('user', 'id', 'user1').
  out('purchased').
  in('purchased').
  where(neq(V().has('user', 'id', 'user1'))).
  out('purchased').
  where(not(__.in('purchased').has('user', 'id', 'user1'))).
  groupCount().
  order(local).by(values, desc).
  limit(local, 3)
```

### Content-Based Recommendations

```groovy
// Find products in similar categories
:load ~/sample-data/content-based.groovy

// Recommend products by category similarity
g.V().has('user', 'id', 'user2').
  out('purchased').
  values('category').
  dedup().
  as('categories').
  V().hasLabel('product').
  where(values('category').where(within('categories'))).
  where(not(__.in('purchased').has('user', 'id', 'user2'))).
  limit(5)
```

## Stack Architecture

### NetworkingStack
- VPC with CIDR 10.0.0.0/16
- 3 private subnets for Neptune (Multi-AZ)
- 1 public subnet for EC2 client
- Security groups for Neptune and EC2

### NeptuneStack
- Neptune cluster with encryption
- Primary instance (db.r5.large)
- 2 read replica instances
- Automated backups and maintenance windows

### StorageStack
- S3 bucket for sample data
- Pre-loaded CSV files and Gremlin scripts
- Secure bucket policies

### ComputeStack
- EC2 instance (t3.medium) in public subnet
- IAM role with Neptune and S3 permissions
- Pre-installed Gremlin client tools
- Connection testing scripts

## Configuration

### Customizing Instance Types

Edit the stack files to change instance types:

```python
# In neptune_stack.py
db_instance_class="db.r5.xlarge"  # Larger Neptune instances

# In compute_stack.py
instance_type=ec2.InstanceType.of(
    ec2.InstanceClass.T3, ec2.InstanceSize.LARGE  # Larger EC2 instance
)
```

### Security Configuration

For production environments:

1. Restrict SSH access in `compute_stack.py`:
   ```python
   # Replace with your IP
   peer=ec2.Peer.ipv4("YOUR-IP/32")
   ```

2. Enable deletion protection in `neptune_stack.py`:
   ```python
   deletion_protection=True
   ```

3. Increase backup retention:
   ```python
   backup_retention_period=30
   ```

## Cost Optimization

- **Development**: Use `db.t3.medium` instances
- **Production**: Use `db.r5.large` or larger
- **Auto-scaling**: Consider Aurora Serverless for variable workloads
- **Cleanup**: Always run `cdk destroy --all` after testing

## Monitoring and Logging

The deployment includes:

- CloudWatch audit logs for Neptune
- EC2 instance monitoring via SSM
- VPC Flow Logs (optional - uncomment in networking_stack.py)

## Troubleshooting

### Common Issues

1. **Connection timeout**: Check security group rules
2. **Permission denied**: Verify IAM roles and policies
3. **Instance not accessible**: Check VPC and subnet configuration

### Debug Commands

```bash
# Check Neptune cluster status
aws neptune describe-db-clusters --db-cluster-identifier neptune-recommendations-cluster

# Check EC2 instance status
aws ec2 describe-instances --instance-ids $INSTANCE_ID

# View CloudFormation events
aws cloudformation describe-stack-events --stack-name NeptuneClusterStack
```

## Cleanup

To avoid ongoing charges, destroy all resources:

```bash
cdk destroy --all
```

This will remove all created resources except:
- S3 bucket (if versioning is enabled)
- CloudWatch logs (retention period applies)

## Support

For issues with this CDK application:

1. Check the [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
2. Review [Amazon Neptune Documentation](https://docs.aws.amazon.com/neptune/)
3. Refer to the original recipe documentation

## Security Considerations

- All traffic between components stays within the VPC
- Neptune cluster is in private subnets only
- IAM roles follow principle of least privilege
- Encryption at rest enabled for Neptune storage
- S3 bucket uses server-side encryption

## Next Steps

1. Implement advanced recommendation algorithms
2. Add real-time data ingestion with Kinesis
3. Integrate with machine learning pipelines
4. Set up monitoring and alerting
5. Configure backup and disaster recovery