# Global Load Balancing with Route53 and CloudFront - Terraform

This directory contains Terraform Infrastructure as Code (IaC) for deploying a comprehensive global load balancing solution using AWS Route53, CloudFront, Application Load Balancers, and Auto Scaling Groups across multiple regions.

## Architecture Overview

The solution deploys:

- **Multi-Region Infrastructure**: VPCs, ALBs, and Auto Scaling Groups in 3 regions (us-east-1, eu-west-1, ap-southeast-1)
- **Route53 Health Checks**: Continuous monitoring of regional endpoints
- **DNS Routing Policies**: Weighted and geolocation-based routing
- **CloudFront Distribution**: Global edge network with origin failover
- **S3 Fallback**: Static content served when all origins fail
- **Monitoring & Alerting**: CloudWatch alarms and dashboards

## Prerequisites

### Required Tools
- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) v2 configured with appropriate credentials

### Required Permissions
Your AWS credentials need permissions for:
- EC2 (VPC, instances, security groups, load balancers)
- Route53 (hosted zones, health checks, DNS records)
- CloudFront (distributions, origin access control)
- S3 (buckets, objects, policies)
- IAM (roles, policies, instance profiles)
- CloudWatch (alarms, dashboards)
- SNS (topics, subscriptions)
- Auto Scaling (groups, launch templates)

### Cost Considerations
- **Estimated Monthly Cost**: $150-300 USD (varies by usage)
- **EC2 Instances**: ~$135/month (6 t3.micro instances across regions)
- **Load Balancers**: ~$60/month (3 ALBs)
- **Route53**: ~$45/month (health checks and hosted zone)
- **CloudFront**: ~$5-50/month (depends on traffic)

## Quick Start

### 1. Clone and Navigate
```bash
git clone <repository-url>
cd aws/global-load-balancing-route53-cloudfront/code/terraform/
```

### 2. Review and Customize Variables
Copy the example variables file:
```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` to customize your deployment:
```hcl
# Project Configuration
project_name = "my-global-lb"
environment  = "demo"

# Regional Configuration
primary_region   = "us-east-1"
secondary_region = "eu-west-1"
tertiary_region  = "ap-southeast-1"

# Domain Configuration (optional - will create demo domain if not specified)
domain_name         = "example.com"
create_hosted_zone  = true

# Instance Configuration
instance_type    = "t3.micro"
desired_capacity = 2
min_capacity     = 1
max_capacity     = 3

# Monitoring Configuration
enable_cloudwatch_alarms = true
sns_email_endpoint      = "your-email@example.com"
```

### 3. Initialize and Deploy
```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Verify Deployment
After deployment completes (15-20 minutes), test the infrastructure:

```bash
# Get CloudFront URL from outputs
terraform output cloudfront_url

# Test the CloudFront distribution
curl -I $(terraform output -raw cloudfront_url)

# Test weighted routing (if using custom domain)
nslookup app.$(terraform output -raw hosted_zone_name)

# Test geolocation routing (if using custom domain)
nslookup geo.$(terraform output -raw hosted_zone_name)
```

## Configuration Options

### Regional Configuration
Customize regions by modifying:
```hcl
primary_region   = "us-west-2"    # Primary region
secondary_region = "eu-central-1" # Secondary region
tertiary_region  = "ap-northeast-1" # Tertiary region
```

### Auto Scaling Configuration
Adjust capacity settings:
```hcl
instance_type    = "t3.small"  # Larger instance type
min_capacity     = 2           # Minimum instances per region
max_capacity     = 10          # Maximum instances per region
desired_capacity = 3           # Desired instances per region
```

### Health Check Configuration
Customize health check behavior:
```hcl
health_check_interval         = 30  # Check every 30 seconds
health_check_failure_threshold = 3   # 3 failures = unhealthy
health_check_path            = "/health"
```

### CloudFront Configuration
Optimize for cost or performance:
```hcl
cloudfront_price_class = "PriceClass_All"  # Global distribution
# or
cloudfront_price_class = "PriceClass_100"  # US/Europe only (cheaper)
```

### Monitoring Configuration
Configure alerting:
```hcl
enable_cloudwatch_alarms = true
sns_email_endpoint      = "ops-team@company.com"
```

## Module Structure

The Terraform code is organized using modules:

```
terraform/
├── main.tf                    # Main configuration
├── variables.tf               # Input variables
├── outputs.tf                 # Output values
├── versions.tf                # Provider requirements
├── terraform.tfvars.example  # Example variables
├── README.md                  # This file
└── modules/
    └── regional-infrastructure/
        ├── main.tf            # Regional VPC, ALB, ASG
        ├── variables.tf       # Module variables
        ├── outputs.tf         # Module outputs
        └── user-data.sh       # EC2 instance configuration
```

### Regional Infrastructure Module
The `regional-infrastructure` module creates:
- VPC with public subnets across AZs
- Internet Gateway and route tables
- Security groups for ALB and EC2
- Application Load Balancer with target group
- Launch template with user data
- Auto Scaling Group with ELB health checks
- IAM roles and instance profiles

## Testing Scenarios

### 1. Basic Functionality Test
```bash
# Test CloudFront distribution
curl https://$(terraform output -raw cloudfront_domain_name)

# Should return HTML from one of the regions
```

### 2. Regional Failover Test
```bash
# Get Auto Scaling Group name for primary region
ASG_NAME=$(terraform output -json primary_region_info | jq -r '.alb_arn' | cut -d'/' -f2)

# Simulate failure by scaling down primary region
aws autoscaling update-auto-scaling-group \
    --region $(terraform output -raw primary_region_info | jq -r '.region') \
    --auto-scaling-group-name $ASG_NAME \
    --desired-capacity 0

# Wait 5 minutes and test - traffic should route to other regions
sleep 300
curl https://$(terraform output -raw cloudfront_domain_name)

# Restore primary region
aws autoscaling update-auto-scaling-group \
    --region $(terraform output -raw primary_region_info | jq -r '.region') \
    --auto-scaling-group-name $ASG_NAME \
    --desired-capacity 2
```

### 3. Health Check Monitoring
```bash
# Check health check status
aws route53 get-health-check \
    --health-check-id $(terraform output -json health_checks | jq -r '.primary.id')
```

### 4. CloudWatch Monitoring
Access the CloudWatch dashboard:
```bash
# Get dashboard URL
terraform output -json monitoring_info | jq -r '.dashboard_url'
```

## Troubleshooting

### Common Issues

#### 1. CloudFront Distribution Deployment Slow
CloudFront distributions take 15-20 minutes to deploy globally.
```bash
# Check deployment status
aws cloudfront get-distribution --id $(terraform output -raw cloudfront_distribution_id)
```

#### 2. Health Checks Failing
Verify instances are healthy:
```bash
# Check target group health
aws elbv2 describe-target-health \
    --target-group-arn $(terraform output -json primary_region_info | jq -r '.target_group_arn')
```

#### 3. DNS Resolution Issues
If using a custom domain, ensure name servers are updated:
```bash
# Get name servers to configure in your domain registrar
terraform output route53_name_servers
```

#### 4. Permission Errors
Verify AWS credentials have required permissions:
```bash
# Test basic permissions
aws sts get-caller-identity
aws ec2 describe-regions
aws route53 list-hosted-zones
```

### Debugging Commands

#### Check Resource Status
```bash
# Terraform state
terraform show
terraform state list

# AWS resources
aws ec2 describe-instances --filters "Name=tag:Project,Values=$(terraform output -raw project_info | jq -r '.project_name')"
aws elbv2 describe-load-balancers
aws cloudfront list-distributions
```

#### Log Access
```bash
# CloudWatch logs (if configured)
aws logs describe-log-groups --log-group-name-prefix "/aws/ec2/global-lb"

# Instance logs via Systems Manager
aws ssm start-session --target <instance-id>
```

## Customization

### Adding Additional Regions
1. Add provider configuration in `versions.tf`
2. Add region variables in `variables.tf`
3. Create module instance in `main.tf`
4. Add Route53 health check and DNS records

### Custom Application Deployment
Modify `modules/regional-infrastructure/user-data.sh` to:
- Install your application
- Configure custom health checks
- Add application-specific monitoring

### SSL/TLS Certificates
For production use with custom domains:
```hcl
# In CloudFront configuration
viewer_certificate {
  acm_certificate_arn      = "arn:aws:acm:us-east-1:123456789012:certificate/example"
  ssl_support_method       = "sni-only"
  minimum_protocol_version = "TLSv1.2_2021"
}
```

## Cleanup

### Destroy Infrastructure
```bash
# Remove all resources
terraform destroy

# Confirm when prompted
# Note: This will delete ALL resources created by this Terraform configuration
```

### Partial Cleanup
To remove specific regions while keeping others:
```bash
# Disable specific module
terraform plan -target=module.vpc_tertiary -destroy
terraform destroy -target=module.vpc_tertiary
```

## Monitoring and Maintenance

### Regular Maintenance Tasks
1. **Monitor Costs**: Review AWS Cost Explorer monthly
2. **Update AMIs**: Regularly update to latest Amazon Linux 2 AMIs
3. **Security Updates**: Keep instance software updated
4. **Health Check Tuning**: Adjust thresholds based on actual performance
5. **Capacity Planning**: Monitor Auto Scaling metrics and adjust limits

### Performance Optimization
1. **Instance Right-Sizing**: Use CloudWatch metrics to optimize instance types
2. **CloudFront Optimization**: Tune cache behaviors and TTLs
3. **Health Check Optimization**: Balance frequency with cost
4. **Route53 Weight Adjustment**: Optimize traffic distribution based on performance data

## Support and Documentation

### AWS Documentation
- [Route53 Health Checks](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/health-checks-creating.html)
- [CloudFront Origin Groups](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/high_availability_origin_failover.html)
- [Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [Auto Scaling Groups](https://docs.aws.amazon.com/autoscaling/ec2/userguide/AutoScalingGroup.html)

### Terraform Documentation
- [AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Modules](https://www.terraform.io/docs/language/modules/index.html)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support.