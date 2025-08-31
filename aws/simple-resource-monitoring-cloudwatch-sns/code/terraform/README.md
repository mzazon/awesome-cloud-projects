# Simple Resource Monitoring with CloudWatch and SNS - Terraform Implementation

This Terraform configuration creates a complete AWS monitoring solution that demonstrates basic CloudWatch alarms and SNS notifications for EC2 instances. It's designed for learning purposes and provides a foundation for more complex monitoring setups.

## Architecture Overview

The infrastructure includes:

- **EC2 Instance**: Amazon Linux 2023 instance with monitoring tools pre-installed
- **CloudWatch Alarms**: Multiple alarms for CPU utilization and status checks
- **SNS Topic**: Email notifications when alarms trigger
- **Security Group**: Controlled access with SSH and ICMP rules
- **IAM Roles**: Proper permissions for Systems Manager and CloudWatch
- **CloudWatch Logs**: Centralized logging with the CloudWatch agent
- **KMS Encryption**: Optional encryption for SNS messages

## Prerequisites

Before using this Terraform configuration, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Terraform** version 1.5 or later installed
3. **Sufficient AWS permissions** to create EC2, CloudWatch, SNS, IAM, and VPC resources
4. **Valid email address** for receiving alarm notifications

### Required AWS Permissions

Your AWS credentials need the following permissions:
- `ec2:*` (for EC2 instances, security groups, VPC resources)
- `cloudwatch:*` (for alarms and metrics)
- `sns:*` (for topics and subscriptions)
- `iam:*` (for roles and policies)
- `kms:*` (for encryption keys)
- `logs:*` (for CloudWatch Logs)

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd aws/simple-resource-monitoring-cloudwatch-sns/code/terraform
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Create Variables File

Create a `terraform.tfvars` file with your specific values:

```hcl
# Required Variables
email_address = "your-email@example.com"
aws_region    = "us-west-2"

# Optional Customizations
environment             = "dev"
instance_type          = "t2.micro"
cpu_alarm_threshold    = 70
resource_name_prefix   = "monitoring-demo"
enable_sns_encryption  = true
create_vpc            = false  # Use default VPC
create_key_pair       = false  # Set to true if you want SSH access
```

### 4. Plan Deployment

```bash
terraform plan
```

### 5. Deploy Infrastructure

```bash
terraform apply
```

When prompted, type `yes` to confirm the deployment.

### 6. Confirm Email Subscription

After deployment:
1. Check your email inbox for an SNS subscription confirmation
2. Click the "Confirm subscription" link in the email
3. You should see a confirmation page in your browser

## Configuration Options

### Core Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `email_address` | Email address for alarm notifications | - | Yes |
| `aws_region` | AWS region for resource deployment | `us-west-2` | No |
| `environment` | Environment tag (dev/staging/prod) | `dev` | No |
| `instance_type` | EC2 instance type | `t2.micro` | No |

### Monitoring Configuration

| Variable | Description | Default | Range |
|----------|-------------|---------|-------|
| `cpu_alarm_threshold` | CPU percentage that triggers alarm | `70` | 10-100 |
| `alarm_evaluation_periods` | Number of periods before alarm triggers | `2` | 1-10 |
| `metric_period` | Metric collection period in seconds | `300` | 60-3600 |
| `enable_detailed_monitoring` | Enable 1-minute metrics | `false` | boolean |

### Security and Access

| Variable | Description | Default |
|----------|-------------|---------|
| `create_key_pair` | Create SSH key pair | `false` |
| `public_key` | SSH public key (if creating key pair) | `""` |
| `allowed_cidr_blocks` | CIDR blocks for SSH access | `["0.0.0.0/0"]` |
| `enable_sns_encryption` | Encrypt SNS messages with KMS | `true` |

### Networking

| Variable | Description | Default |
|----------|-------------|---------|
| `create_vpc` | Create new VPC instead of using default | `false` |
| `vpc_cidr` | CIDR block for new VPC | `10.0.0.0/16` |

## Testing the Monitoring Setup

After deployment, you can test the monitoring system:

### 1. Connect to the Instance

**Using SSM Session Manager (Recommended):**
```bash
aws ssm start-session --target <instance-id> --region <region>
```

**Using SSH (if key pair was created):**
```bash
ssh -i ~/.ssh/<key-name> ec2-user@<public-ip>
```

### 2. Generate CPU Load

Run the pre-installed stress test script:
```bash
./cpu-stress-test.sh
```

This will generate high CPU usage for 10 minutes, triggering the CloudWatch alarm.

### 3. Monitor System Information

View current system metrics:
```bash
./system-info.sh
```

### 4. Check CloudWatch

- Navigate to the CloudWatch console
- View metrics under "AWS/EC2" namespace
- Monitor alarm states in the "Alarms" section

### 5. Verify Email Notifications

You should receive email notifications when:
- CPU utilization exceeds the threshold
- Alarms return to OK state
- Instance or system status checks fail

## Monitoring Components

### CloudWatch Alarms

The configuration creates three alarms:

1. **CPU Utilization Alarm**
   - Triggers when CPU > threshold (default 70%)
   - Evaluation period: 2 periods of 5 minutes
   - Sends email notifications

2. **Instance Status Check Alarm**
   - Monitors instance-level health
   - Triggers on failed instance status checks
   - Indicates instance-specific issues

3. **System Status Check Alarm**
   - Monitors AWS infrastructure health
   - Triggers on failed system status checks
   - Indicates AWS infrastructure issues

### CloudWatch Agent

The instance includes a pre-configured CloudWatch agent that collects:
- **CPU metrics**: Usage by type (user, system, idle, iowait)
- **Memory metrics**: Used and available percentages
- **Disk metrics**: Disk usage percentages
- **Network metrics**: Connection statistics
- **Log files**: System logs (/var/log/messages, /var/log/secure)

### SNS Integration

- **Topic**: Dedicated topic for monitoring alerts
- **Encryption**: Optional KMS encryption for messages
- **Delivery Policy**: Configured for reliable message delivery
- **Email Subscription**: Automatic email notifications

## Cost Optimization

### Free Tier Usage

This configuration is designed to stay within AWS Free Tier limits:
- **EC2**: t2.micro instance (750 hours/month free)
- **CloudWatch**: First 10 alarms free
- **SNS**: First 1,000 email notifications free
- **CloudWatch Logs**: 5GB ingestion free

### Estimated Monthly Costs (After Free Tier)

- EC2 t2.micro: ~$8.50/month (if running 24/7)
- CloudWatch Alarms: $0.30/month (3 alarms × $0.10)
- SNS Email: $0.00 (first 1,000 free)
- CloudWatch Logs: ~$0.50/month (varies by usage)

**Total**: ~$9.30/month

## Security Features

### Instance Security

- **Security Group**: Restricts access to SSH and ICMP only
- **IMDSv2**: Enforced for metadata service access
- **Encrypted Storage**: Root volume encrypted with default AWS key
- **IAM Role**: Least privilege access for Systems Manager

### Data Protection

- **SNS Encryption**: Optional KMS encryption for messages
- **CloudWatch Logs**: Encrypted at rest
- **Network Security**: Private subnets with controlled outbound access

### Access Control

- **SSH Access**: Optional, controlled by security group rules
- **Systems Manager**: Preferred method for instance access
- **IAM Policies**: Minimal required permissions only

## Troubleshooting

### Common Issues

**Email notifications not received:**
1. Check spam/junk folder
2. Verify subscription confirmation was clicked
3. Check SNS topic subscription status in AWS console

**Cannot connect to instance:**
1. Verify security group allows SSH on port 22
2. Check that instance has public IP (if using SSH)
3. Use Systems Manager Session Manager as alternative

**Alarms not triggering:**
1. Verify instance is running and passing status checks
2. Check that metrics are being published to CloudWatch
3. Ensure alarm threshold and evaluation period settings are appropriate

**CloudWatch agent not working:**
1. Check agent status: `sudo systemctl status amazon-cloudwatch-agent`
2. Review agent logs: `sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log`
3. Verify IAM permissions for CloudWatch

### Debug Commands

**Check instance metadata:**
```bash
curl -s http://169.254.169.254/latest/meta-data/instance-id
```

**Monitor CPU usage:**
```bash
htop
# or
top
```

**Check CloudWatch agent status:**
```bash
sudo systemctl status amazon-cloudwatch-agent
```

**View recent logs:**
```bash
sudo journalctl -u amazon-cloudwatch-agent -f
```

## Cleanup

To avoid ongoing charges, destroy the infrastructure when no longer needed:

```bash
terraform destroy
```

When prompted, type `yes` to confirm the destruction.

**Note**: This will delete all resources including the EC2 instance, alarms, and SNS topic. Make sure to backup any important data first.

## Extension Ideas

Consider these enhancements for production use:

### Enhanced Monitoring
- Add memory and disk utilization alarms
- Implement composite alarms for complex conditions
- Set up custom metrics for application-specific monitoring

### Automation
- Auto Scaling integration for automatic instance management
- Lambda functions for automated remediation
- Systems Manager Automation for common maintenance tasks

### Notifications
- Slack or Microsoft Teams integration
- SMS notifications for critical alerts
- Integration with incident management systems

### Security
- VPC Flow Logs for network monitoring
- AWS Config for compliance monitoring
- GuardDuty for threat detection

## Additional Resources

- [AWS CloudWatch Documentation](https://docs.aws.amazon.com/cloudwatch/)
- [Amazon SNS Documentation](https://docs.aws.amazon.com/sns/)
- [EC2 Instance Monitoring](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/monitoring_ec2.html)
- [CloudWatch Agent Configuration](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-Configuration-File-Details.html)
- [AWS Free Tier Details](https://aws.amazon.com/free/)

## Support

For issues with this Terraform configuration:
1. Check the troubleshooting section above
2. Review Terraform and AWS provider documentation
3. Consult AWS documentation for service-specific issues
4. Consider AWS Support if you have a support plan

## License

This Terraform configuration is provided as-is for educational purposes. Please review and test thoroughly before using in production environments.