# EC2 Fleet Management with Spot Instances - Terraform

This Terraform configuration deploys a comprehensive EC2 Fleet Management solution that demonstrates cost optimization through intelligent mixing of Spot and On-Demand instances across multiple Availability Zones and instance types.

## Architecture Overview

The solution creates:

- **EC2 Fleet**: Mixed instance deployment with Spot and On-Demand instances
- **Spot Fleet**: Dedicated Spot instance fleet for comparison
- **Launch Template**: Standardized instance configuration with user data
- **Security Groups**: Network access control for fleet instances
- **IAM Roles**: Service roles for fleet management and instance monitoring
- **CloudWatch Monitoring**: Dashboards, alarms, and log aggregation
- **Auto-scaling**: Intelligent capacity management and rebalancing

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for EC2, IAM, and CloudWatch resources
- SSH key pair for instance access (will be created automatically if not provided)

## Quick Start

1. **Clone and Navigate**:
   ```bash
   git clone <repository-url>
   cd aws/ec2-fleet-management-spot-fleet-on-demand-instances/code/terraform
   ```

2. **Configure Variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Plan Deployment**:
   ```bash
   terraform plan
   ```

5. **Deploy Infrastructure**:
   ```bash
   terraform apply
   ```

6. **Access Instances**:
   ```bash
   # SSH to instances using the generated key pair
   chmod 400 <key-name>.pem
   ssh -i <key-name>.pem ec2-user@<instance-public-ip>
   ```

## Configuration Options

### Basic Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region for deployment | `us-east-1` |
| `environment` | Environment name for tagging | `demo` |
| `project_name` | Project name for resource naming | `ec2-fleet-demo` |

### Network Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `use_default_vpc` | Use default VPC and subnets | `true` |
| `vpc_id` | Custom VPC ID (if not using default) | `null` |
| `subnet_ids` | Custom subnet IDs (if not using default) | `[]` |
| `allowed_cidr_blocks` | CIDR blocks for security group access | `["0.0.0.0/0"]` |

### Fleet Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `instance_types` | List of instance types for diversification | `["t3.micro", "t3.small", "t3.nano"]` |
| `ec2_fleet_target_capacity` | Total EC2 Fleet capacity | `6` |
| `ec2_fleet_on_demand_capacity` | On-Demand instances in EC2 Fleet | `2` |
| `ec2_fleet_spot_capacity` | Spot instances in EC2 Fleet | `4` |
| `spot_fleet_target_capacity` | Spot Fleet capacity | `3` |
| `spot_max_price` | Maximum Spot price per hour | `"0.10"` |

### Advanced Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `create_cloudwatch_dashboard` | Create monitoring dashboard | `true` |
| `enable_detailed_monitoring` | Enable detailed instance monitoring | `false` |
| `replace_unhealthy_instances` | Auto-replace unhealthy instances | `true` |
| `fleet_allocation_strategy` | Spot allocation strategy | `capacity-optimized` |

## Outputs

After deployment, Terraform provides comprehensive outputs including:

- **Fleet Information**: Fleet IDs, states, and configuration summaries
- **Network Details**: VPC, subnet, and security group information
- **Access Information**: SSH commands and key pair details
- **Monitoring**: CloudWatch dashboard URLs and alarm names
- **Management Commands**: AWS CLI commands for fleet operations

## Cost Optimization Features

This deployment includes several cost optimization features:

1. **Spot Instance Integration**: Up to 90% cost savings compared to On-Demand
2. **Capacity-Optimized Allocation**: Minimizes Spot interruptions
3. **Diversified Instance Types**: Maximizes available capacity pools
4. **Intelligent Rebalancing**: Automatic capacity redistribution
5. **Mixed Purchasing Options**: Balances cost and availability

## Monitoring and Observability

The solution includes comprehensive monitoring:

- **CloudWatch Dashboard**: Real-time fleet metrics and performance
- **Custom Metrics**: Instance-level CPU, memory, and disk usage
- **Log Aggregation**: Application and system logs in CloudWatch
- **Automated Alarms**: Notifications for high CPU and capacity issues
- **Health Checks**: Automated instance health monitoring

## Security Considerations

- **Security Groups**: Restrictive ingress rules with configurable CIDR blocks
- **IAM Roles**: Least privilege access for fleet operations
- **Key Pair Management**: Secure SSH access with generated key pairs
- **VPC Integration**: Deployment within existing or default VPC
- **Encryption**: EBS volumes encrypted by default

## Scaling and Management

### Modify Fleet Capacity

```bash
# Update EC2 Fleet capacity
terraform apply -var="ec2_fleet_target_capacity=10" -var="ec2_fleet_spot_capacity=7"

# Or modify terraform.tfvars and apply
terraform apply
```

### Monitor Fleet Status

```bash
# Check fleet status using output commands
terraform output fleet_management_commands

# Example commands:
aws ec2 describe-fleets --fleet-ids <fleet-id>
aws ec2 describe-fleet-instances --fleet-id <fleet-id>
```

### Access Instance Information

```bash
# View instance access information
terraform output instance_access_info

# SSH to instances
ssh -i <key-name>.pem ec2-user@<instance-ip>
```

## Troubleshooting

### Common Issues

1. **Insufficient Spot Capacity**: Increase instance type diversity or adjust max price
2. **Network Connectivity**: Verify security group rules and VPC configuration
3. **Key Pair Issues**: Ensure proper key pair creation and file permissions
4. **IAM Permissions**: Verify AWS credentials have required permissions

### Debug Commands

```bash
# View Terraform state
terraform show

# Check resource status
terraform state list
terraform state show <resource-name>

# Validate configuration
terraform validate

# Format configuration
terraform fmt
```

## Cleanup

To avoid ongoing costs, destroy the infrastructure when no longer needed:

```bash
# Destroy all resources
terraform destroy

# Confirm destruction
# Type 'yes' when prompted
```

## Advanced Usage

### Custom User Data

```hcl
# In terraform.tfvars
user_data_script = <<EOF
#!/bin/bash
yum update -y
yum install -y docker
systemctl start docker
systemctl enable docker
EOF
```

### Additional Security Rules

```hcl
# In terraform.tfvars
additional_security_group_rules = [
  {
    type        = "ingress"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
    description = "Custom application port"
  }
]
```

### Custom Resource Tags

```hcl
# In terraform.tfvars
resource_tags = {
  Owner       = "team-name"
  Department  = "engineering"
  CostCenter  = "12345"
  Environment = "production"
}
```

## Integration with Other Services

This Terraform configuration can be extended to integrate with:

- **Application Load Balancer**: Distribute traffic across fleet instances
- **Auto Scaling**: Dynamic capacity adjustment based on metrics
- **ECS/EKS**: Container orchestration with fleet-based capacity
- **Systems Manager**: Enhanced instance management and patching
- **AWS Config**: Compliance monitoring and configuration tracking

## Support and Documentation

- [AWS EC2 Fleet Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-fleet.html)
- [Spot Fleet Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-fleet.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Original Recipe](../../../ec2-fleet-management-spot-fleet-on-demand-instances.md)

## Contributing

To contribute improvements to this Terraform configuration:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This Terraform configuration is provided as-is for educational and demonstration purposes. Modify and adapt as needed for your specific requirements.