# EC2 Hibernation Cost Optimization - Terraform Infrastructure

This Terraform configuration implements the complete infrastructure for the EC2 hibernation cost optimization recipe, creating a production-ready solution that demonstrates how to use EC2 hibernation to reduce costs while maintaining application state.

## Architecture Overview

The infrastructure includes:
- **EC2 Instance**: Hibernation-enabled instance with encrypted EBS root volume
- **CloudWatch Monitoring**: CPU utilization and state change alarms
- **SNS Notifications**: Email alerts for hibernation events
- **IAM Roles**: Least-privilege access for EC2 and optional Lambda function
- **Security Groups**: Secure SSH access configuration
- **Optional Lambda**: Automated hibernation scheduling (dev environment only)

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for EC2, CloudWatch, SNS, and IAM
- Valid AWS account with hibernation-supported regions

## Quick Start

1. **Clone and Navigate**:
   ```bash
   cd aws/ec2-hibernate-cost-optimization/code/terraform/
   ```

2. **Configure Variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

3. **Initialize and Deploy**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Retrieve SSH Key**:
   ```bash
   # Get the private key from Systems Manager Parameter Store
   aws ssm get-parameter --name "/ec2/hibernation-demo/$(terraform output -raw key_pair_name)/private-key" --with-decryption --query 'Parameter.Value' --output text > hibernate-key.pem
   chmod 400 hibernate-key.pem
   ```

5. **Connect to Instance**:
   ```bash
   ssh -i hibernate-key.pem ec2-user@$(terraform output -raw instance_public_ip)
   ```

## Configuration Options

### Core Settings

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for resources | `us-east-1` | No |
| `environment` | Environment name | `dev` | No |
| `instance_type` | EC2 instance type | `m5.large` | No |
| `ebs_volume_size` | EBS volume size in GB | `30` | No |

### Monitoring Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_detailed_monitoring` | Enable detailed CloudWatch monitoring | `true` |
| `cpu_threshold` | CPU utilization threshold for alarms | `10` |
| `cpu_evaluation_periods` | Number of periods to evaluate | `6` |
| `cpu_alarm_period` | Period in seconds | `300` |

### Notification Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `notification_email` | Email for SNS notifications | `""` |
| `sns_topic_name` | SNS topic name | Auto-generated |

### Security Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `allowed_cidr_blocks` | CIDR blocks for SSH access | `["0.0.0.0/0"]` |
| `vpc_id` | VPC ID (uses default if empty) | `""` |
| `subnet_id` | Subnet ID (uses default if empty) | `""` |

## Hibernation Operations

### Manual Hibernation

```bash
# Hibernate the instance
aws ec2 stop-instances --instance-ids $(terraform output -raw instance_id) --hibernate

# Monitor hibernation progress
watch -n 5 'aws ec2 describe-instances --instance-ids $(terraform output -raw instance_id) --query "Reservations[0].Instances[0].State.Name"'
```

### Resume from Hibernation

```bash
# Resume the instance
aws ec2 start-instances --instance-ids $(terraform output -raw instance_id)

# Wait for instance to be running
aws ec2 wait instance-running --instance-ids $(terraform output -raw instance_id)
```

### Validation Commands

```bash
# Check hibernation support
aws ec2 describe-instances --instance-ids $(terraform output -raw instance_id) --query 'Reservations[0].Instances[0].HibernationOptions.Configured'

# Check CPU utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=$(terraform output -raw instance_id) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# Check alarm state
aws cloudwatch describe-alarms \
  --alarm-names $(terraform output -raw cloudwatch_alarm_low_cpu_name) \
  --query 'MetricAlarms[0].StateValue'
```

## Cost Optimization

### Hibernation Benefits

- **Compute Savings**: Stop paying for compute time during hibernation
- **State Preservation**: Maintain application state without lengthy startups
- **EBS Only Costs**: Pay only for EBS storage during hibernation (~$0.10/GB/month)

### Cost Calculation Example

For an `m5.large` instance (8 GB RAM, $0.096/hour):
- **Running 24/7**: $0.096 × 24 × 30 = $69.12/month
- **Running 8h/day**: $0.096 × 8 × 30 = $23.04/month
- **Hibernation savings**: ~67% cost reduction

### Monitoring Costs

```bash
# Check CloudWatch costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

## Automated Scheduling

The configuration includes an optional Lambda function for development environments that can automatically hibernate instances based on CPU utilization:

```bash
# Trigger hibernation via Lambda (dev environment only)
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_name) \
  --payload '{"action": "hibernate"}' \
  response.json
```

## Security Considerations

### Key Management

- Private keys are stored in AWS Systems Manager Parameter Store
- Keys are encrypted using AWS KMS
- Access is controlled via IAM policies

### Network Security

- Security groups restrict SSH access to specified CIDR blocks
- Consider using AWS Systems Manager Session Manager for bastion-free access
- Enable VPC Flow Logs for network monitoring

### IAM Permissions

The configuration follows least-privilege principles:
- EC2 instance role: CloudWatch metrics and SSM access only
- Lambda role: EC2 hibernation permissions only
- No unnecessary administrative permissions

## Troubleshooting

### Common Issues

1. **Hibernation Not Supported**:
   - Verify instance type supports hibernation
   - Check that EBS root volume is encrypted
   - Ensure sufficient EBS volume size (>= RAM)

2. **SSH Connection Issues**:
   - Verify security group allows SSH from your IP
   - Check that key pair is properly configured
   - Ensure instance is in running state

3. **CloudWatch Alarms Not Triggering**:
   - Verify detailed monitoring is enabled
   - Check that sufficient data points are available
   - Confirm alarm thresholds are appropriate

### Debug Commands

```bash
# Check instance configuration
aws ec2 describe-instances --instance-ids $(terraform output -raw instance_id)

# Check security group rules
aws ec2 describe-security-groups --group-ids $(terraform output -raw security_group_id)

# Check CloudWatch metrics
aws cloudwatch list-metrics --namespace AWS/EC2 --dimensions Name=InstanceId,Value=$(terraform output -raw instance_id)

# Check Lambda logs (if enabled)
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/$(terraform output -raw lambda_function_name)
```

## Advanced Configuration

### Custom AMI

To use a custom AMI that supports hibernation:

```hcl
# Add to terraform.tfvars
custom_ami_id = "ami-12345678"
```

### Multi-AZ Deployment

For high availability across multiple availability zones:

```hcl
# Add to terraform.tfvars
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
```

### Spot Instances

For additional cost savings with Spot Instances:

```hcl
# Add to terraform.tfvars
use_spot_instances = true
spot_price = "0.05"
```

## Cleanup

### Terraform Destroy

```bash
terraform destroy
```

### Manual Cleanup (if needed)

```bash
# Remove any remaining resources
aws ec2 terminate-instances --instance-ids $(terraform output -raw instance_id)
aws ec2 delete-key-pair --key-name $(terraform output -raw key_pair_name)
aws sns delete-topic --topic-arn $(terraform output -raw sns_topic_arn)
```

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS documentation for hibernation requirements
3. Verify your AWS account has appropriate permissions
4. Check Terraform and AWS CLI versions

## References

- [AWS EC2 Hibernation Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Hibernate.html)
- [AWS EC2 Instance Types](https://aws.amazon.com/ec2/instance-types/)
- [AWS CloudWatch Metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/aws-services-cloudwatch-metrics.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)