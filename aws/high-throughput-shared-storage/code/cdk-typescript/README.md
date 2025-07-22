# High-Performance File Systems with Amazon FSx - CDK TypeScript

This AWS CDK TypeScript application deploys a comprehensive high-performance file system solution using Amazon FSx services, including Lustre, Windows File Server, and NetApp ONTAP file systems.

## Architecture Overview

The solution creates:

- **FSx for Lustre**: High-performance file system for HPC workloads with S3 data repository integration
- **FSx for Windows**: Fully managed Windows-based shared storage with SMB protocol support  
- **FSx for NetApp ONTAP**: Multi-protocol file system supporting NFS, SMB, and iSCSI (Multi-AZ deployment)
- **S3 Data Repository**: Integrated with Lustre for seamless data movement
- **CloudWatch Monitoring**: Comprehensive alarms and metrics for all file systems
- **Test EC2 Instance**: Linux instance configured with FSx client tools for testing

## Prerequisites

- AWS CLI installed and configured
- Node.js 18+ installed
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for FSx, EC2, S3, IAM, and CloudWatch
- Default VPC available in your target region

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure AWS Environment

```bash
# Set your AWS region and account
export CDK_DEFAULT_REGION=us-east-1
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
```

### 3. Bootstrap CDK (if not done before)

```bash
cdk bootstrap
```

### 4. Deploy the Stack

```bash
# Review the changes
cdk diff

# Deploy the infrastructure
cdk deploy
```

### 5. Access Your File Systems

After deployment, use the output values to access your file systems:

#### Lustre File System
```bash
# Connect to your EC2 instance via Session Manager
aws ssm start-session --target <InstanceId>

# Mount the Lustre file system (use output command)
sudo mount -t lustre <DNS-NAME>@tcp:/<MOUNT-NAME> /mnt/fsx

# Test performance
dd if=/dev/zero of=/mnt/fsx/testfile bs=1M count=1000
dd if=/mnt/fsx/testfile of=/dev/null bs=1M
```

#### Windows File System
```bash
# Access from Windows instance
net use Z: \\<DNS-NAME>\share
```

#### ONTAP File System (if deployed)
```bash
# Mount NFS volume
sudo mount -t nfs <SVM-ENDPOINT>:/nfs /mnt/nfs

# Access SMB share from Windows
net use Y: \\<SVM-ENDPOINT>\smb
```

## File System Configuration

### FSx for Lustre
- **Storage Capacity**: 1.2 TB
- **Deployment Type**: SCRATCH_2 (optimized for temporary, high-performance workloads)
- **Throughput**: 250 MB/s per TB
- **S3 Integration**: Automatic import/export with data repository

### FSx for Windows
- **Storage Capacity**: 32 GB (minimum)
- **Deployment Type**: Single-AZ
- **Throughput**: 8 MB/s (can be modified)
- **Features**: SMB protocol, Windows-based shared storage

### FSx for NetApp ONTAP
- **Storage Capacity**: 1 TB
- **Deployment Type**: Multi-AZ (high availability)
- **Throughput**: 256 MB/s
- **Features**: Multi-protocol access (NFS, SMB), storage efficiency

## Monitoring and Alarms

The stack creates CloudWatch alarms for:

- **Lustre Throughput Utilization**: Alerts when > 80% for 2 periods
- **Windows CPU Utilization**: Alerts when > 85% for 2 periods  
- **ONTAP Storage Utilization**: Alerts when > 90% for 1 period

View metrics in the CloudWatch console under the `AWS/FSx` namespace.

## Cost Optimization

### Development Environment
```bash
# Reduce costs by using smaller configurations
# Modify the stack to use:
# - Lustre: 1.2 TB (minimum for SCRATCH_2)
# - Windows: 32 GB (minimum)
# - ONTAP: 1 TB (minimum for Multi-AZ)
```

### Production Environment
```bash
# Scale up for production workloads:
# - Increase storage capacity based on requirements
# - Adjust throughput capacity for performance needs
# - Consider Persistent deployment for Lustre if data durability is needed
```

## Customization

### Environment Variables

Set these before deployment to customize the stack:

```bash
export CDK_DEFAULT_REGION=us-west-2  # Change region
export FSX_ENABLE_ONTAP=false        # Disable ONTAP if not needed
```

### Stack Parameters

Modify `lib/high-performance-file-systems-stack.ts` to customize:

- Storage capacities
- Throughput settings
- Security group rules
- Instance types
- Monitoring thresholds

## Useful CDK Commands

```bash
# Build TypeScript
npm run build

# Watch for changes and rebuild
npm run watch

# Run tests
npm run test

# Compare deployed stack with current state
cdk diff

# Synthesize CloudFormation template
cdk synth

# Deploy the stack
cdk deploy

# Destroy the stack
cdk destroy
```

## Testing Performance

### Lustre Performance Test
```bash
# On EC2 instance with mounted Lustre
# Sequential write test
dd if=/dev/zero of=/mnt/fsx/test_1gb bs=1M count=1024

# Sequential read test  
dd if=/mnt/fsx/test_1gb of=/dev/null bs=1M

# Parallel I/O test
for i in {1..4}; do
  dd if=/dev/zero of=/mnt/fsx/test_${i}gb bs=1M count=1024 &
done
wait
```

### Windows Performance Test
```bash
# From Windows client
# Copy large files to test throughput
robocopy C:\largefile \\<DNS-NAME>\share\ /MT:8
```

## Cleanup

To avoid ongoing charges, destroy the stack when done:

```bash
cdk destroy
```

This will remove:
- All FSx file systems
- S3 bucket and contents
- EC2 instances
- Security groups
- CloudWatch alarms
- IAM roles and policies

## Troubleshooting

### Common Issues

1. **Insufficient Subnets**: ONTAP Multi-AZ requires 2+ subnets in different AZs
2. **Security Group Rules**: Ensure proper ports are open (988 for Lustre, 445 for SMB, 2049 for NFS)
3. **Region Limitations**: Some FSx features may not be available in all regions
4. **Instance Type**: Ensure EC2 instance type supports enhanced networking for optimal performance

### Logs and Monitoring

- Check CloudWatch logs under `/aws/fsx/demo-*`
- Monitor CloudWatch alarms for performance issues
- Use AWS Systems Manager Session Manager to access EC2 instances

## Security Considerations

- All file systems use encryption at rest
- Security groups restrict access to private IP ranges
- IAM roles follow least privilege principle
- S3 bucket has public access blocked
- Consider enabling AWS Config for compliance monitoring

## Support

For issues with this CDK implementation:
1. Check the original recipe documentation
2. Review AWS FSx documentation
3. Check CloudFormation events in AWS Console
4. Review CloudWatch logs for detailed error messages

## License

This code is provided under the MIT License. See LICENSE file for details.