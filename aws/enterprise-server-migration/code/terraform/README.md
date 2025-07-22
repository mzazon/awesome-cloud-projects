# Terraform Infrastructure for AWS Application Migration Service

This Terraform configuration creates a complete infrastructure for large-scale server migration using AWS Application Migration Service (MGN). It provides automated setup of all necessary components including IAM roles, security groups, replication templates, migration waves, and monitoring resources.

## Architecture Overview

The infrastructure includes:
- **MGN Replication Configuration Template** - Defines how source servers are replicated to AWS
- **Migration Waves** - Organizes servers into logical groups for coordinated migration
- **IAM Roles and Policies** - Provides necessary permissions for MGN operations
- **Security Groups** - Controls network access for replication servers and migrated instances
- **S3 Bucket** - Stores migration logs and artifacts
- **CloudWatch Resources** - Monitors replication progress and performance (optional)
- **Launch Templates** - Defines post-launch actions for migrated instances

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Terraform** v1.0 or later installed
3. **AWS Account** with necessary permissions for:
   - IAM role and policy management
   - EC2 instance and security group management
   - S3 bucket operations
   - CloudWatch logs and metrics
   - Application Migration Service operations

## Required AWS Permissions

Your AWS credentials need the following permissions:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "mgn:*",
                "iam:CreateRole",
                "iam:AttachRolePolicy",
                "iam:CreateInstanceProfile",
                "iam:AddRoleToInstanceProfile",
                "ec2:*",
                "s3:*",
                "logs:*",
                "cloudwatch:*"
            ],
            "Resource": "*"
        }
    ]
}
```

## Quick Start

### 1. Initialize and Deploy

```bash
# Clone or navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Deploy the infrastructure
terraform apply
```

### 2. Customize Configuration

Create a `terraform.tfvars` file to customize the deployment:

```hcl
# terraform.tfvars
aws_region     = "us-west-2"
environment    = "production"
project_name   = "enterprise-migration"

# MGN Configuration
mgn_replication_server_instance_type = "t3.medium"
mgn_staging_disk_type               = "gp3"
mgn_bandwidth_throttling            = 1000
mgn_data_plane_routing              = "PRIVATE_IP"

# Migration Waves
migration_waves = [
  {
    name        = "Wave-1-WebTier"
    description = "Web tier servers - first wave"
    servers     = []
  },
  {
    name        = "Wave-2-AppTier"
    description = "Application tier servers - second wave"
    servers     = []
  },
  {
    name        = "Wave-3-DatabaseTier"
    description = "Database tier servers - final wave"
    servers     = []
  }
]

# Security and Monitoring
enable_cloudwatch_monitoring = true
kms_key_id                   = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"

# Additional Tags
additional_tags = {
  CostCenter = "IT-Migration"
  Owner      = "Platform-Team"
}
```

### 3. Initialize MGN Service

After Terraform deployment, initialize the MGN service:

```bash
# Initialize MGN service (one-time per region)
aws mgn initialize-service --region $(terraform output -raw resource_identifiers | jq -r '.aws_region')
```

## Configuration Options

### MGN Replication Settings

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `mgn_replication_server_instance_type` | EC2 instance type for replication servers | `t3.small` | Any valid EC2 instance type |
| `mgn_staging_disk_type` | EBS volume type for staging areas | `gp3` | `gp2`, `gp3`, `io1`, `io2` |
| `mgn_bandwidth_throttling` | Bandwidth limit in Mbps (0 = unlimited) | `0` | 0-10000 |
| `mgn_data_plane_routing` | Network routing for replication traffic | `PRIVATE_IP` | `PRIVATE_IP`, `PUBLIC_IP` |

### Launch Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `target_instance_type_right_sizing_method` | Instance sizing method | `BASIC` |
| `launch_disposition` | Instance state after launch | `STARTED` |
| `copy_private_ip` | Copy source server private IPs | `false` |
| `copy_tags` | Copy source server tags | `true` |
| `licensing_os_byol` | Use BYOL licensing | `true` |

### Migration Waves

Migration waves organize servers into logical groups for coordinated migration:

```hcl
migration_waves = [
  {
    name        = "Wave-1-WebServers"
    description = "Public-facing web servers"
    servers     = []  # Server IDs added during migration
  },
  {
    name        = "Wave-2-AppServers"
    description = "Application tier servers"
    servers     = []
  }
]
```

## Post-Deployment Steps

### 1. Verify Infrastructure

```bash
# Check all resources were created
terraform output

# Verify MGN replication template
aws mgn describe-replication-configuration-templates \
    --region $(terraform output -raw resource_identifiers | jq -r '.aws_region')

# List migration waves
aws mgn list-waves \
    --region $(terraform output -raw resource_identifiers | jq -r '.aws_region')
```

### 2. Install MGN Agents

Download and install MGN agents on source servers:

```bash
# Get agent download URLs
terraform output agent_installation_info

# For Linux servers
curl -o aws-replication-installer-init.py \
    "$(terraform output -raw agent_installation_info | jq -r '.agent_download_url_linux')"

# Run installation (on source server)
sudo python3 aws-replication-installer-init.py \
    --region $(terraform output -raw resource_identifiers | jq -r '.aws_region') \
    --aws-access-key-id YOUR_ACCESS_KEY \
    --aws-secret-access-key YOUR_SECRET_KEY \
    --no-prompt
```

### 3. Configure Launch Templates

For each source server, configure launch settings:

```bash
# Example launch configuration
aws mgn put-launch-configuration \
    --source-server-id s-1234567890abcdef0 \
    --launch-configuration '{
        "bootMode": "BIOS",
        "copyPrivateIp": false,
        "copyTags": true,
        "enableMapAutoTagging": true,
        "launchDisposition": "STARTED",
        "licensing": {"osByol": true},
        "name": "MyServer-Launch-Config",
        "targetInstanceTypeRightSizingMethod": "BASIC"
    }'
```

## Monitoring and Alerting

### CloudWatch Integration

When `enable_cloudwatch_monitoring` is true, the following monitoring resources are created:

- **Log Group**: `/aws/mgn/{project_name}-{environment}`
- **Metric Alarm**: Monitors replication lag
- **Dashboard**: (Optional) Custom dashboard for migration metrics

### S3 Logging

All MGN logs and artifacts are stored in the created S3 bucket:
- Bucket: `{project_name}-{environment}-mgn-logs-{random_suffix}`
- Prefix: `mgn-logs/`

## Migration Workflow

### 1. Server Registration and Replication

```bash
# Monitor source server registration
aws mgn describe-source-servers \
    --region $(terraform output -raw resource_identifiers | jq -r '.aws_region') \
    --query 'items[*].{ServerID:sourceServerID,Hostname:sourceProperties.identificationHints.hostname,Status:dataReplicationInfo.dataReplicationState}'

# Wait for continuous replication
while true; do
    PENDING=$(aws mgn describe-source-servers \
        --region $(terraform output -raw resource_identifiers | jq -r '.aws_region') \
        --query 'length(items[?dataReplicationInfo.dataReplicationState!=`CONTINUOUS`])')
    if [ "$PENDING" -eq 0 ]; then
        echo "All servers reached continuous replication"
        break
    fi
    echo "Waiting for $PENDING servers to reach continuous replication..."
    sleep 30
done
```

### 2. Test Migration

```bash
# Launch test instances
aws mgn start-test \
    --source-server-ids s-1234567890abcdef0 \
    --region $(terraform output -raw resource_identifiers | jq -r '.aws_region')

# Monitor test status
aws mgn describe-source-servers \
    --source-server-ids s-1234567890abcdef0 \
    --region $(terraform output -raw resource_identifiers | jq -r '.aws_region') \
    --query 'items[0].lifeCycle.state'
```

### 3. Production Cutover

```bash
# Execute cutover
aws mgn start-cutover \
    --source-server-ids s-1234567890abcdef0 \
    --region $(terraform output -raw resource_identifiers | jq -r '.aws_region')

# Finalize migration
aws mgn finalize-cutover \
    --source-server-id s-1234567890abcdef0 \
    --region $(terraform output -raw resource_identifiers | jq -r '.aws_region')
```

## Wave-Based Migration

### Associate Servers with Waves

```bash
# Get wave ID
WAVE_ID=$(aws mgn list-waves \
    --region $(terraform output -raw resource_identifiers | jq -r '.aws_region') \
    --query 'items[?name==`Wave-1-WebServers`].waveID' \
    --output text)

# Associate servers with wave
aws mgn associate-source-servers \
    --wave-id $WAVE_ID \
    --source-server-ids s-1234567890abcdef0 s-1234567890abcdef1 \
    --region $(terraform output -raw resource_identifiers | jq -r '.aws_region')
```

### Execute Wave Migration

```bash
# Start wave cutover
aws mgn start-cutover \
    --wave-id $WAVE_ID \
    --region $(terraform output -raw resource_identifiers | jq -r '.aws_region')

# Monitor wave progress
aws mgn describe-source-servers \
    --region $(terraform output -raw resource_identifiers | jq -r '.aws_region') \
    --query 'items[?contains(waveID, `'$WAVE_ID'`)].{ServerID:sourceServerID,Status:lifeCycle.state}'
```

## Security Considerations

### Network Security

The infrastructure creates security groups with minimal required access:

- **Replication Servers**: Allow inbound port 1500 from private networks
- **Migrated Instances**: Allow SSH (22) and RDP (3389) from private networks

### IAM Security

IAM roles follow the principle of least privilege:
- **MGN Service Role**: Only permissions required for MGN operations
- **Replication Server Role**: EC2 and logging permissions only

### Encryption

- **S3 Bucket**: Server-side encryption enabled
- **EBS Volumes**: Encryption enabled for staging and migrated instances
- **CloudWatch Logs**: KMS encryption supported (optional)

## Troubleshooting

### Common Issues

1. **MGN Service Not Initialized**
   ```bash
   aws mgn initialize-service --region $(terraform output -raw resource_identifiers | jq -r '.aws_region')
   ```

2. **Replication Servers Not Starting**
   - Check VPC subnets have available IP addresses
   - Verify security group rules allow required traffic
   - Review CloudWatch logs for detailed error messages

3. **Agent Installation Fails**
   - Ensure source servers have outbound HTTPS (443) access
   - Verify AWS credentials have MGN permissions
   - Check agent compatibility with source OS

### Logs and Debugging

- **CloudWatch Logs**: `/aws/mgn/{project_name}-{environment}`
- **S3 Logs**: `{bucket_name}/mgn-logs/`
- **Instance Logs**: `/var/log/mgn-post-launch.log`

## Cleanup

To avoid ongoing costs, clean up resources after migration:

```bash
# Remove all source servers from MGN
aws mgn describe-source-servers \
    --region $(terraform output -raw resource_identifiers | jq -r '.aws_region') \
    --query 'items[*].sourceServerID' \
    --output text | xargs -I {} aws mgn disconnect-from-service \
    --source-server-id {} \
    --region $(terraform output -raw resource_identifiers | jq -r '.aws_region')

# Destroy Terraform infrastructure
terraform destroy
```

## Cost Optimization

### Replication Costs

- Use smaller instance types for replication servers during off-peak hours
- Implement lifecycle policies for S3 staging data
- Monitor and optimize bandwidth throttling settings

### Storage Costs

- Configure S3 lifecycle policies to transition logs to cheaper storage classes
- Use GP3 volumes instead of GP2 for better cost-performance ratio
- Clean up test instances promptly after validation

## Support

For issues with this infrastructure:
1. Check the original recipe documentation
2. Review AWS MGN documentation
3. Consult AWS support for service-specific issues
4. Review Terraform state for resource configuration details

## Version History

- **v1.0**: Initial release with basic MGN infrastructure
- **v1.1**: Added wave-based migration and enhanced monitoring
- **v1.2**: Improved security configurations and post-launch actions