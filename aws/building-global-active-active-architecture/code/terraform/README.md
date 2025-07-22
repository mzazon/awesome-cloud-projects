# Multi-Region Active-Active Application with AWS Global Accelerator - Terraform

This Terraform configuration deploys a globally distributed, active-active application architecture using AWS Global Accelerator, DynamoDB Global Tables, and Lambda functions across three regions (US East 1, EU West 1, and Asia Pacific Southeast 1).

## Architecture Overview

The solution provides:
- **Global Entry Point**: AWS Global Accelerator with static anycast IP addresses
- **Multi-Region Deployment**: Application Load Balancers and Lambda functions in three regions
- **Global Data Layer**: DynamoDB Global Tables with automatic cross-region replication
- **Automatic Failover**: Health-based traffic routing with instant failover
- **Low Latency**: Users automatically routed to nearest healthy region

## Prerequisites

1. **AWS CLI** installed and configured with appropriate permissions
2. **Terraform** >= 1.0 installed
3. **AWS Account** with permissions for:
   - Global Accelerator creation and management
   - DynamoDB Global Tables across multiple regions
   - Lambda functions, ALBs, and IAM roles
   - CloudWatch logs and S3 buckets
4. **Multi-Region Access** to us-east-1, eu-west-1, ap-southeast-1, and us-west-2

## Required AWS Permissions

Your AWS credentials need permissions for:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "globalaccelerator:*",
                "dynamodb:*",
                "lambda:*",
                "elasticloadbalancing:*",
                "iam:*",
                "logs:*",
                "s3:*",
                "ec2:Describe*",
                "ec2:CreateSecurityGroup",
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress"
            ],
            "Resource": "*"
        }
    ]
}
```

## Quick Start

### 1. Clone and Navigate
```bash
git clone <repository-url>
cd aws/multi-region-active-active-applications-with-global-accelerator/code/terraform/
```

### 2. Initialize Terraform
```bash
terraform init
```

### 3. Review and Customize Variables
```bash
# Create terraform.tfvars file with your customizations
cat > terraform.tfvars << EOF
project_name = "my-global-app"
environment = "prod"

# Optional: Customize regions
primary_region = "us-east-1"
secondary_region_eu = "eu-west-1"
secondary_region_asia = "ap-southeast-1"

# Optional: Enable detailed monitoring
enable_detailed_monitoring = true

# Optional: Customize Global Accelerator
accelerator_name = "my-app-accelerator"
EOF
```

### 4. Plan and Apply
```bash
# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply
```

### 5. Test the Deployment
```bash
# Get the Global Accelerator DNS name and static IPs
terraform output global_accelerator_dns_name
terraform output global_accelerator_static_ips

# Test health endpoints
curl -s http://$(terraform output -raw global_accelerator_dns_name)/health | jq .

# Create a test user
curl -X POST http://$(terraform output -raw global_accelerator_dns_name)/user \
  -H 'Content-Type: application/json' \
  -d '{"userId":"test-user-1","data":{"name":"Test User","email":"test@example.com"}}'

# List users
curl -s http://$(terraform output -raw global_accelerator_dns_name)/users | jq .
```

## Configuration Variables

### Core Configuration
| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_name` | Project name for resource naming | `"global-app"` | No |
| `environment` | Environment (dev/staging/prod) | `"dev"` | No |
| `primary_region` | Primary AWS region | `"us-east-1"` | No |
| `secondary_region_eu` | EU region | `"eu-west-1"` | No |
| `secondary_region_asia` | Asia region | `"ap-southeast-1"` | No |

### DynamoDB Configuration
| Variable | Description | Default |
|----------|-------------|---------|
| `dynamodb_table_name` | DynamoDB table name | `"GlobalUserData"` |
| `dynamodb_billing_mode` | Billing mode | `"PAY_PER_REQUEST"` |

### Lambda Configuration
| Variable | Description | Default |
|----------|-------------|---------|
| `lambda_runtime` | Runtime version | `"python3.11"` |
| `lambda_timeout` | Timeout in seconds | `30` |
| `lambda_memory_size` | Memory in MB | `256` |

### Global Accelerator Configuration
| Variable | Description | Default |
|----------|-------------|---------|
| `accelerator_name` | Accelerator name | `"global-app-accelerator"` |
| `accelerator_ip_address_type` | IP type (IPV4/DUAL_STACK) | `"IPV4"` |
| `health_check_interval_seconds` | Health check interval | `30` |
| `healthy_threshold_count` | Healthy threshold | `3` |
| `unhealthy_threshold_count` | Unhealthy threshold | `3` |

### Monitoring Configuration
| Variable | Description | Default |
|----------|-------------|---------|
| `enable_detailed_monitoring` | Enable CloudWatch monitoring | `true` |
| `log_retention_days` | Log retention period | `14` |

## API Endpoints

The deployed application provides the following REST API endpoints:

### Health Check
```bash
GET /health
```
Returns health status and region information.

### User Management
```bash
# Create user
POST /user
Content-Type: application/json
{
  "userId": "user123",
  "data": {
    "name": "John Doe",
    "email": "john@example.com"
  }
}

# Get user
GET /user/{userId}

# Update user  
PUT /user/{userId}
Content-Type: application/json
{
  "data": {
    "name": "John Smith",
    "email": "johnsmith@example.com"
  }
}

# List users
GET /users
```

## Testing Multi-Region Consistency

### 1. Create Test Script
```bash
cat > test_consistency.py << 'EOF'
import requests
import json
import time
import sys

def test_consistency(base_url):
    # Create user
    user_data = {
        "userId": f"test-{int(time.time())}",
        "data": {"name": "Test User", "email": "test@example.com"}
    }
    
    print(f"Creating user: {user_data['userId']}")
    response = requests.post(f"{base_url}/user", json=user_data)
    print(f"Create response: {response.status_code}")
    print(f"Response: {response.json()}")
    
    # Wait for replication
    print("Waiting for cross-region replication...")
    time.sleep(5)
    
    # Test read from multiple endpoints
    print("\nTesting read consistency:")
    response = requests.get(f"{base_url}/user/{user_data['userId']}")
    if response.status_code == 200:
        result = response.json()
        print(f"✅ User found, served from: {result.get('served_from_region')}")
    else:
        print(f"❌ User not found: {response.status_code}")

if __name__ == "__main__":
    base_url = sys.argv[1] if len(sys.argv) > 1 else "http://localhost"
    test_consistency(base_url)
EOF

# Run the test
python3 test_consistency.py http://$(terraform output -raw global_accelerator_dns_name)
```

### 2. Monitor Regional Endpoints
```bash
# Test individual regional endpoints
terraform output application_endpoints

# Monitor health across regions
watch -n 5 'echo "=== US Region ===" && curl -s http://$(terraform output -raw alb_us_dns_name)/health | jq .region && echo "=== EU Region ===" && curl -s http://$(terraform output -raw alb_eu_dns_name)/health | jq .region && echo "=== Asia Region ===" && curl -s http://$(terraform output -raw alb_asia_dns_name)/health | jq .region'
```

## Monitoring and Observability

### CloudWatch Dashboards
The deployment creates CloudWatch log groups for each Lambda function:
- `/aws/lambda/{project_name}-us-{suffix}`
- `/aws/lambda/{project_name}-eu-{suffix}`
- `/aws/lambda/{project_name}-asia-{suffix}`

### Global Accelerator Metrics
Monitor these CloudWatch metrics:
- `AWS/GlobalAccelerator/NewFlowCount`
- `AWS/GlobalAccelerator/ActiveFlowCount`
- `AWS/GlobalAccelerator/ProcessedBytesIn`

### DynamoDB Global Tables
Monitor replication lag and throttling:
- `AWS/DynamoDB/ReplicationLatency`
- `AWS/DynamoDB/UserErrors`

## Cost Optimization

### Estimated Monthly Costs (US East 1)
- **Global Accelerator**: $18.00 (fixed) + data transfer
- **ALB**: $16.20 per region (3 regions = $48.60)
- **Lambda**: $0.20 per 1M requests
- **DynamoDB**: $1.25 per GB + cross-region replication
- **CloudWatch Logs**: $0.50 per GB ingested

### Cost Reduction Strategies
1. **Use PAY_PER_REQUEST billing** for DynamoDB (default)
2. **Set Lambda reserved concurrency** to control costs
3. **Configure log retention** to manage storage costs
4. **Monitor data transfer** between regions

## Security Considerations

### IAM Least Privilege
The Lambda execution role includes only necessary permissions:
- DynamoDB read/write to Global Tables
- CloudWatch Logs creation and writing

### Network Security
- ALB security groups allow HTTP/HTTPS from internet
- Lambda functions run in AWS managed VPC
- DynamoDB encryption at rest enabled
- S3 bucket encryption for flow logs

### Data Protection
- Point-in-time recovery enabled for DynamoDB
- Server-side encryption for all data at rest
- VPC Flow Logs for network monitoring (optional)

## Troubleshooting

### Common Issues

1. **Global Accelerator Creation Fails**
   ```
   Error: Provider us-west-2 required for Global Accelerator
   ```
   Solution: Ensure AWS credentials work in us-west-2 region

2. **DynamoDB Global Tables Setup Fails**
   ```
   Error: Table already exists in region
   ```
   Solution: Choose unique table names or destroy existing tables

3. **Lambda Permission Errors**
   ```
   Error: Unable to invoke Lambda function
   ```
   Solution: Check IAM role policies and ALB target group registration

4. **Cross-Region Access Issues**
   ```
   Error: Access denied in region
   ```
   Solution: Verify AWS credentials have multi-region permissions

### Debug Commands
```bash
# Check resource status
terraform state list
terraform show

# Validate configuration
terraform validate
terraform plan

# Check AWS resources
aws globalaccelerator list-accelerators --region us-west-2
aws dynamodb list-global-tables --region us-east-1
aws lambda list-functions --region us-east-1
```

## Cleanup

### Destroy Resources
```bash
# Review what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy

# Confirm cleanup
aws globalaccelerator list-accelerators --region us-west-2
```

### Manual Cleanup (if needed)
If Terraform destroy fails, manually delete:
1. Global Accelerator (us-west-2)
2. DynamoDB Global Tables (all regions)
3. Lambda functions (all regions)
4. Application Load Balancers (all regions)
5. CloudWatch Log Groups (all regions)

## Advanced Configurations

### Custom Domain Setup
```hcl
# In terraform.tfvars
custom_domain_name = "api.yourdomain.com"
certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
```

### WAF Integration
```hcl
# In terraform.tfvars
enable_waf = true
```

### Enhanced Monitoring
```hcl
# In terraform.tfvars
enable_detailed_monitoring = true
log_retention_days = 30
```

## Support and Documentation

- [AWS Global Accelerator Documentation](https://docs.aws.amazon.com/global-accelerator/)
- [DynamoDB Global Tables Documentation](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GlobalTables.html)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Contributing

1. Fork the repository
2. Create feature branch
3. Test changes thoroughly
4. Submit pull request with detailed description

## License

This code is provided as-is for educational and production use. See LICENSE file for details.