# Infrastructure as Code for Seamless Hybrid Cloud Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Seamless Hybrid Cloud Storage".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Storage Gateway operations
  - S3 bucket management
  - EC2 instance management
  - IAM role creation
  - CloudWatch configuration
  - KMS key management
- For CDK deployments: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Estimated cost: $20-50/month for gateway resources and S3 storage

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name hybrid-storage-gateway \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=GatewayName,ParameterValue=my-gateway \
                 ParameterKey=S3BucketName,ParameterValue=my-storage-bucket-$(date +%s)

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name hybrid-storage-gateway

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name hybrid-storage-gateway \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Configure environment (optional)
export GATEWAY_NAME="my-gateway"
export S3_BUCKET_NAME="my-storage-bucket-$(date +%s)"

# Deploy the stack
cdk deploy --require-approval never

# Get deployment outputs
cdk list --long
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment (optional)
export GATEWAY_NAME="my-gateway"
export S3_BUCKET_NAME="my-storage-bucket-$(date +%s)"

# Deploy the stack
cdk deploy --require-approval never

# Get deployment outputs
cdk list --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file (optional customization)
cat > terraform.tfvars << EOF
gateway_name = "my-gateway"
s3_bucket_name = "my-storage-bucket-$(date +%s)"
aws_region = "us-east-1"
cache_disk_size = 100
EOF

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for configuration values or use defaults
# Follow the script output for deployment progress

# View deployment results
./scripts/deploy.sh --status
```

## Configuration Options

### CloudFormation Parameters

- `GatewayName`: Name for the Storage Gateway (default: hybrid-gateway-random)
- `S3BucketName`: Name for the S3 bucket (must be globally unique)
- `InstanceType`: EC2 instance type for gateway (default: m5.large)
- `CacheDiskSize`: Size of cache disk in GB (default: 100)
- `AllowedCIDR`: CIDR block for NFS access (default: 10.0.0.0/8)

### CDK Configuration

Set environment variables before deployment:

```bash
export GATEWAY_NAME="your-gateway-name"
export S3_BUCKET_NAME="your-unique-bucket-name"
export AWS_REGION="your-preferred-region"
export CACHE_DISK_SIZE="100"
export ALLOWED_CIDR="10.0.0.0/8"
```

### Terraform Variables

Create `terraform.tfvars` file or set variables:

```hcl
gateway_name = "your-gateway-name"
s3_bucket_name = "your-unique-bucket-name"
aws_region = "us-east-1"
instance_type = "m5.large"
cache_disk_size = 100
allowed_cidr = "10.0.0.0/8"
nfs_file_mode = "0644"
nfs_directory_mode = "0755"
```

## Post-Deployment Steps

After successful deployment, complete these manual steps:

1. **Activate the Storage Gateway** (automated in IaC):
   - Gateway activation is handled automatically
   - Monitor CloudWatch logs for activation status

2. **Mount File Shares**:
   ```bash
   # Get gateway IP from deployment outputs
   GATEWAY_IP=$(terraform output -raw gateway_ip)  # For Terraform
   
   # Mount NFS share (Linux/macOS)
   sudo mkdir -p /mnt/storage-gateway
   sudo mount -t nfs ${GATEWAY_IP}:/your-bucket-name /mnt/storage-gateway
   
   # Mount SMB share (Windows)
   net use Z: \\${GATEWAY_IP}\your-bucket-name
   ```

3. **Test File Operations**:
   ```bash
   # Create test file
   echo "Hello from Storage Gateway" > /mnt/storage-gateway/test.txt
   
   # Verify file appears in S3
   aws s3 ls s3://your-bucket-name/
   ```

## Monitoring and Management

### CloudWatch Metrics

Key metrics to monitor:

- `CacheHitPercent`: Cache efficiency
- `CloudBytesUploaded`: Data uploaded to S3
- `CloudBytesDownloaded`: Data downloaded from S3
- `TotalCacheSize`: Current cache utilization

### Accessing Metrics

```bash
# View cache hit percentage
aws cloudwatch get-metric-statistics \
    --namespace AWS/StorageGateway \
    --metric-name CacheHitPercent \
    --dimensions Name=GatewayName,Value=your-gateway-name \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average
```

## Troubleshooting

### Common Issues

1. **Gateway Activation Fails**:
   - Verify Security Group allows ports 80/443
   - Check gateway instance is running and accessible
   - Ensure IAM permissions are correct

2. **File Share Mount Fails**:
   - Verify NFS ports (2049) are open in Security Group
   - Check client is in allowed CIDR range
   - Confirm gateway is fully activated

3. **Poor Performance**:
   - Monitor cache hit ratio in CloudWatch
   - Consider increasing cache disk size
   - Verify network bandwidth between gateway and AWS

### Debug Commands

```bash
# Check gateway status
aws storagegateway describe-gateway-information \
    --gateway-arn "your-gateway-arn"

# List file shares
aws storagegateway list-file-shares \
    --gateway-arn "your-gateway-arn"

# Check S3 bucket policy
aws s3api get-bucket-policy --bucket your-bucket-name
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name hybrid-storage-gateway

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name hybrid-storage-gateway
```

### Using CDK (AWS)

```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
cdk destroy --force
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

# Follow prompts to confirm resource deletion
```

## Security Considerations

- **Encryption**: All data is encrypted in transit and at rest using KMS
- **Access Control**: File shares use root squashing and CIDR restrictions
- **IAM Roles**: Least privilege access for Storage Gateway service
- **Network Security**: Security Groups restrict access to required ports only
- **Monitoring**: CloudWatch logs capture all gateway operations

## Cost Optimization

- **Storage Classes**: Configure S3 Intelligent Tiering for automatic cost optimization
- **Cache Sizing**: Monitor cache hit ratios to optimize local storage costs
- **Instance Sizing**: Use appropriate EC2 instance types based on throughput requirements
- **Data Transfer**: Consider AWS Direct Connect for large data transfers

## Customization

### Adding Additional File Shares

Modify the IaC templates to include additional file shares:

```bash
# For multiple departments or applications
# Each can have different S3 prefixes and access controls
```

### Integrating with Active Directory

For production SMB deployments:

```bash
# Update SMB file share configuration
# Configure domain authentication instead of guest access
```

### Multi-Region Setup

For disaster recovery:

```bash
# Deploy gateways in multiple regions
# Configure S3 cross-region replication
```

## Support

- **AWS Documentation**: [Storage Gateway User Guide](https://docs.aws.amazon.com/storagegateway/)
- **AWS Support**: Submit support cases through AWS Console
- **Community**: AWS Storage Gateway forum and Stack Overflow
- **Recipe Issues**: Refer to the original recipe documentation for detailed implementation guidance

## Version History

- v1.0: Initial implementation with basic file gateway support
- v1.1: Added SMB file share support and enhanced monitoring

For issues with this infrastructure code, refer to the original recipe documentation or the AWS Storage Gateway documentation.