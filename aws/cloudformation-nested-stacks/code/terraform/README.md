# Terraform Infrastructure for CloudFormation Nested Stacks Demo

This Terraform configuration recreates the CloudFormation nested stacks architecture from the recipe using Terraform's modular approach. It demonstrates the same layered architecture and separation of concerns while leveraging Terraform's features for infrastructure management.

## Architecture Overview

The infrastructure consists of multiple layers that mirror the CloudFormation nested stacks pattern:

### 🌐 Network Layer
- **VPC** with customizable CIDR block
- **Public Subnets** (2) across multiple Availability Zones
- **Private Subnets** (2) across multiple Availability Zones
- **Internet Gateway** for public internet access
- **NAT Gateways** (2) for private subnet outbound connectivity
- **Route Tables** with appropriate routing rules

### 🔒 Security Layer
- **Security Groups** for each tier (ALB, Application, Database, Bastion)
- **IAM Roles** for EC2 instances with least-privilege policies
- **IAM Instance Profile** for EC2 service access
- **RDS Monitoring Role** for enhanced database monitoring

### 🚀 Application Layer
- **Application Load Balancer** for traffic distribution
- **Auto Scaling Group** with environment-specific sizing
- **Launch Template** with user data configuration
- **Target Group** with health checks

### 🗄️ Database Layer
- **RDS MySQL** instance with encryption
- **Database Subnet Group** for multi-AZ placement
- **Secrets Manager** for credential management
- **Enhanced Monitoring** and Performance Insights

### 📊 Monitoring Layer
- **CloudWatch Log Groups** for application logging
- **CloudWatch Agent** configuration for metrics and logs
- **Custom health monitoring** scripts

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.5.0 installed
3. **AWS Account** with necessary permissions for:
   - VPC and networking resources
   - EC2 instances and Auto Scaling
   - RDS database instances
   - IAM roles and policies
   - CloudWatch logs and monitoring
   - Secrets Manager

## Quick Start

### 1. Clone and Navigate
```bash
cd terraform/
```

### 2. Configure Variables
```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your specific configuration
nano terraform.tfvars
```

### 3. Initialize Terraform
```bash
terraform init
```

### 4. Plan Deployment
```bash
terraform plan
```

### 5. Deploy Infrastructure
```bash
terraform apply
```

### 6. Access Application
After deployment, get the application URL:
```bash
terraform output application_url
```

## Configuration Options

### Environment-Specific Defaults

The configuration automatically adjusts resources based on the environment:

| Setting | Development | Staging | Production |
|---------|-------------|---------|------------|
| Instance Type | t3.micro | t3.small | t3.medium |
| Min/Max/Desired | 1/2/1 | 2/4/2 | 2/6/3 |
| DB Instance | db.t3.micro | db.t3.small | db.t3.medium |
| DB Storage (GB) | 20 | 50 | 100 |
| Multi-AZ DB | false | false | true |
| Deletion Protection | false | false | true |

### Key Variables

```hcl
# Basic Configuration
aws_region     = "us-west-2"
environment    = "development"
project_name   = "webapp"
vpc_cidr       = "10.0.0.0/16"

# Cost Optimization
enable_nat_gateway = true  # Set to false for development

# Security
allowed_cidr_blocks = ["0.0.0.0/0"]  # Restrict for production

# Database
database_backup_retention_period = 7
enable_performance_insights = true
```

## Cost Optimization

### Development Environment
```hcl
environment = "development"
enable_nat_gateway = false              # Saves ~$45/month per NAT Gateway
database_backup_retention_period = 0    # No backup costs
enable_database_multi_az = false        # Single AZ deployment
cloudwatch_log_retention_days = 3       # Shorter log retention
```

### Production Environment
```hcl
environment = "production"
enable_nat_gateway = true
enable_database_multi_az = true
database_backup_retention_period = 30
load_balancer_deletion_protection = true
database_deletion_protection = true
```

## Security Best Practices

### Network Security
- All database traffic restricted to application security group
- Application instances in private subnets
- Load balancer in public subnets only
- NAT Gateways for secure outbound connectivity

### IAM Security
- Instance roles with minimal required permissions
- No hardcoded credentials in code
- Secrets Manager for database credentials
- AWS managed policies where appropriate

### Data Security
- RDS encryption at rest enabled
- VPC provides network isolation
- Security groups implement least privilege access
- Regular automated backups

## Monitoring and Observability

### CloudWatch Integration
- Application logs: `/aws/ec2/{project}-{environment}/httpd/access`
- Error logs: `/aws/ec2/{project}-{environment}/httpd/error`
- System logs: `/aws/ec2/{project}-{environment}/system/user-data`

### Health Checks
- Load balancer health checks at `/health`
- Application status endpoint at `/status`
- Automated health monitoring script

### Metrics Collection
- EC2 instance metrics (CPU, memory, disk)
- Application Load Balancer metrics
- RDS Performance Insights
- Custom application metrics

## Deployment Validation

### 1. Infrastructure Verification
```bash
# Check all resources were created
terraform show

# Verify outputs
terraform output

# Test connectivity
curl $(terraform output -raw application_url)
```

### 2. Application Health
```bash
# Check health endpoint
curl $(terraform output -raw application_url)/health

# Check detailed status
curl $(terraform output -raw application_url)/status
```

### 3. Database Connectivity
```bash
# Get database connection info
terraform output connection_info
```

## Disaster Recovery

### Backup Strategy
- **RDS Automated Backups**: 7-30 days retention
- **Point-in-time Recovery**: Available for RDS
- **Multi-AZ Deployment**: Automatic failover (production)

### Recovery Procedures
1. **Application Recovery**: Auto Scaling Group automatically replaces failed instances
2. **Database Recovery**: RDS handles failover in Multi-AZ setup
3. **Infrastructure Recovery**: Terraform state enables full infrastructure recreation

## Troubleshooting

### Common Issues

#### 1. Insufficient Permissions
```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify required permissions are attached to user/role
```

#### 2. Resource Limits
```bash
# Check VPC limits
aws ec2 describe-account-attributes

# Check RDS limits
aws rds describe-account-attributes
```

#### 3. Application Not Accessible
```bash
# Check Auto Scaling Group
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $(terraform output -raw auto_scaling_group_name)

# Check Load Balancer targets
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw target_group_arn)
```

### Log Analysis
```bash
# View CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix "/aws/ec2/$(terraform output -raw project_name)"

# Get recent log events
aws logs get-log-events --log-group-name "/aws/ec2/webapp-development/httpd/access" --log-stream-name "i-1234567890abcdef0"
```

## Cleanup

### Destroy Infrastructure
```bash
# Review what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy
```

### Manual Cleanup (if needed)
Some resources may require manual cleanup:
- CloudWatch Log Groups (if retention is set)
- Secrets Manager secrets (if recovery window is configured)
- EBS snapshots from terminated instances

## Comparison with CloudFormation Nested Stacks

| Aspect | CloudFormation Nested Stacks | Terraform Modules |
|--------|-------------------------------|-------------------|
| **Modularity** | Separate template files | Single configuration with logical separation |
| **Dependencies** | Explicit DependsOn and cross-stack references | Implicit dependency resolution |
| **State Management** | AWS manages stack state | Terraform state file |
| **Parameter Passing** | Stack parameters and exports | Variables and outputs |
| **Rollback** | Automatic rollback on failure | Manual rollback with state |
| **Drift Detection** | Built-in drift detection | terraform plan shows differences |

## Advanced Configurations

### Backend Configuration
For production use, configure remote backend:

```hcl
# versions.tf
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "nested-stacks-demo/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-state-locks"
  }
}
```

### Workspace Usage
```bash
# Create environment-specific workspaces
terraform workspace new development
terraform workspace new staging
terraform workspace new production

# Switch between environments
terraform workspace select development
```

### Module Integration
This configuration can be converted to a reusable module:

```hcl
# main.tf
module "webapp_infrastructure" {
  source = "./modules/webapp"
  
  environment    = "development"
  project_name   = "webapp"
  vpc_cidr       = "10.0.0.0/16"
}
```

## Support

For issues related to this infrastructure code:

1. **Check Terraform Documentation**: [terraform.io](https://terraform.io)
2. **Review AWS Provider Documentation**: [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
3. **Consult the original recipe**: Refer to the CloudFormation nested stacks recipe for architectural context
4. **AWS Support**: For AWS-specific service issues

## Contributing

When modifying this infrastructure:

1. **Test Changes**: Always test in development environment first
2. **Update Documentation**: Keep README and variable descriptions current
3. **Follow Conventions**: Maintain consistent naming and tagging
4. **Validate Security**: Review IAM policies and security group rules
5. **Performance Testing**: Verify changes don't impact application performance