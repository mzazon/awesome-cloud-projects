# AWS CDK Python - Simple Website Hosting with Lightsail

This AWS CDK Python application deploys a complete WordPress hosting solution using AWS Lightsail. The solution includes a pre-configured WordPress instance with LAMP stack, static IP address, and optional DNS management.

## Architecture

The CDK application creates:

- **Lightsail WordPress Instance**: Pre-configured with WordPress, PHP 8, MySQL/MariaDB, and Apache
- **Static IP Address**: Ensures consistent access to your website
- **Firewall Configuration**: Opens HTTP (80), HTTPS (443), and SSH (22) ports
- **DNS Zone** (Optional): Manages custom domain records

## Prerequisites

- Python 3.8 or later
- AWS CLI installed and configured
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for Lightsail resource creation

## Installation

1. **Create a virtual environment**:
   ```bash
   python3 -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

2. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Bootstrap CDK (if not done previously)**:
   ```bash
   cdk bootstrap
   ```

## Deployment

### Basic Deployment (IP Address Only)

Deploy WordPress with static IP address:

```bash
# Deploy the WordPress stack
cdk deploy LightsailWordPressStack

# View outputs including static IP and URLs
cdk list --output json
```

### Advanced Deployment (Custom Domain)

Deploy with custom domain configuration:

```bash
# Set domain context and deploy both stacks
cdk deploy --context domain_name=yourdomain.com --context enable_dns=true
```

### Configuration Options

You can customize the deployment using CDK context:

```bash
# Deploy with different instance size
cdk deploy --context instance_bundle=micro_3_0

# Deploy with custom blueprint
cdk deploy --context blueprint=lamp_8_bitnami

# Deploy to specific region
cdk deploy --context region=us-west-2
```

## Post-Deployment Setup

1. **Get your website details**:
   ```bash
   # Get stack outputs
   aws cloudformation describe-stacks \
       --stack-name LightsailWordPressStack \
       --query 'Stacks[0].Outputs'
   ```

2. **Access your WordPress site**:
   - Website: `http://YOUR_STATIC_IP`
   - Admin: `http://YOUR_STATIC_IP/wp-admin`

3. **Get WordPress admin password**:
   ```bash
   # SSH into your instance (requires key pair)
   ssh -i ~/.ssh/your-key-pair.pem bitnami@YOUR_STATIC_IP
   
   # Get admin password
   sudo cat /home/bitnami/bitnami_application_password
   ```

4. **WordPress login credentials**:
   - Username: `user`
   - Password: Retrieved from SSH command above

## CDK Commands

- `cdk ls` - List all stacks
- `cdk synth` - Emit synthesized CloudFormation template
- `cdk deploy` - Deploy this stack to your AWS account
- `cdk diff` - Compare deployed stack with current state
- `cdk destroy` - Remove the stack from your AWS account

## Cost Optimization

- **nano_3_0**: $5/month - Suitable for development and low-traffic sites
- **micro_3_0**: $12/month - Better for production sites with moderate traffic
- **small_3_0**: $25/month - High-traffic production sites

The first 3 months are free with AWS Free Tier for new accounts.

## Security Considerations

1. **Change default passwords** immediately after deployment
2. **Update WordPress** and plugins regularly
3. **Enable HTTPS** using Let's Encrypt (via Lightsail console)
4. **Configure backups** through Lightsail snapshots
5. **Limit SSH access** to specific IP ranges if needed

## SSL Certificate Setup

To enable HTTPS:

1. Access the Lightsail console
2. Navigate to your instance
3. Go to "Networking" → "HTTPS"
4. Follow the wizard to set up Let's Encrypt SSL

## Backup Strategy

```bash
# Create manual snapshot
aws lightsail create-instance-snapshot \
    --instance-name wordpress-site-XXXXXX \
    --instance-snapshot-name wordpress-backup-$(date +%Y%m%d)

# Enable automatic snapshots via console
# Lightsail console → Instance → Snapshots → Enable automatic snapshots
```

## Monitoring

Monitor your WordPress site through:

- **Lightsail Console**: Built-in metrics and monitoring
- **CloudWatch**: Detailed metrics integration
- **WordPress Health Check**: Built-in WordPress site health tools

## Troubleshooting

### Common Issues

1. **Instance not responding**:
   ```bash
   # Check instance status
   aws lightsail get-instance --instance-name wordpress-site-XXXXXX
   
   # Restart instance if needed
   aws lightsail reboot-instance --instance-name wordpress-site-XXXXXX
   ```

2. **Can't access WordPress admin**:
   - Verify firewall rules allow HTTP/HTTPS traffic
   - Check instance is running
   - Verify static IP is attached

3. **Forgot admin password**:
   ```bash
   # SSH and retrieve password
   ssh -i ~/.ssh/your-key-pair.pem bitnami@YOUR_STATIC_IP
   sudo cat /home/bitnami/bitnami_application_password
   ```

## Cleanup

To remove all resources:

```bash
# Destroy the CDK stacks
cdk destroy --all

# Verify cleanup in AWS console
# Check Lightsail console for any remaining resources
```

## Extending the Solution

- **Add CDN**: Integrate with CloudFront for global content delivery
- **Database Migration**: Move to RDS for better scalability
- **Load Balancing**: Add Application Load Balancer for high availability
- **Auto Scaling**: Implement auto scaling based on traffic patterns

## Support

For issues with this CDK application:

1. Check the [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
2. Review [AWS Lightsail Documentation](https://docs.aws.amazon.com/lightsail/)
3. Check [CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)

## License

This project is licensed under the Apache License 2.0.