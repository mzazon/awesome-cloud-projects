# Infrastructure as Code for Simple Website Hosting with Lightsail

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Website Hosting with Lightsail".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured
- Appropriate AWS permissions for Lightsail resource creation
- For CDK implementations: Node.js (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform CLI version 1.0+
- Domain name (optional - can use public IP initially)

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name lightsail-wordpress-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=InstanceName,ParameterValue=my-wordpress-site \
                 ParameterKey=StaticIpName,ParameterValue=my-wordpress-ip \
    --capabilities CAPABILITY_IAM
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
cdk bootstrap  # Run once per AWS account/region
cdk deploy
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt
cdk bootstrap  # Run once per AWS account/region
cdk deploy
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Overview

This infrastructure deploys:

- AWS Lightsail instance with WordPress blueprint
- Static IP address for consistent access
- Firewall rules for HTTP, HTTPS, and SSH traffic
- Optional DNS zone configuration for custom domains

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| InstanceName | Name for the Lightsail instance | `wordpress-site` |
| StaticIpName | Name for the static IP address | `wordpress-ip` |
| BundleId | Lightsail bundle size | `nano_3_0` |
| BlueprintId | Application blueprint | `wordpress` |

### CDK Configuration

Modify the stack configuration in the CDK app files to customize:
- Instance bundle size
- Availability zone
- Resource tags
- Blueprint selection

### Terraform Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| instance_name | Name for the Lightsail instance | string | `wordpress-site` |
| static_ip_name | Name for the static IP | string | `wordpress-ip` |
| bundle_id | Lightsail bundle size | string | `nano_3_0` |
| availability_zone | AWS availability zone | string | `us-east-1a` |

## Post-Deployment Steps

After successful deployment:

1. **Access Your WordPress Site**:
   - Navigate to the static IP address shown in the outputs
   - Access WordPress admin at `http://<static-ip>/wp-admin`

2. **Retrieve WordPress Credentials**:
   ```bash
   # Connect via SSH using Lightsail console or:
   ssh -i ~/.ssh/your-key-pair.pem bitnami@<static-ip>
   
   # Get the admin password
   sudo cat /home/bitnami/bitnami_application_password
   ```

3. **Configure SSL (Optional)**:
   - Use Lightsail console to configure Let's Encrypt SSL
   - Requires a custom domain name

4. **Set Up Custom Domain (Optional)**:
   - Configure DNS records in your domain registrar
   - Point A record to the static IP address

## Monitoring and Maintenance

- Monitor instance metrics through Lightsail console
- Set up automatic backups via snapshots
- Keep WordPress and plugins updated
- Monitor security through AWS Security Hub integration

## Cost Considerations

- Lightsail pricing starts at $5 USD/month for nano instances
- Includes compute, storage, and data transfer allowances
- Static IP addresses are free when attached to running instances
- Additional data transfer charges may apply for high-traffic sites

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name lightsail-wordpress-stack
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Instance Not Accessible**: 
   - Verify firewall rules allow HTTP/HTTPS traffic
   - Check static IP attachment
   - Ensure instance is in running state

2. **WordPress Admin Access**:
   - Verify admin password from bitnami_application_password file
   - Default username is 'user'
   - Clear browser cache if login issues persist

3. **SSL Certificate Issues**:
   - Ensure domain DNS is properly configured
   - Allow 24-48 hours for DNS propagation
   - Check Let's Encrypt rate limits

### Support Resources

- [AWS Lightsail Documentation](https://docs.aws.amazon.com/lightsail/)
- [WordPress on Bitnami Documentation](https://docs.bitnami.com/aws/apps/wordpress/)
- [AWS Support](https://aws.amazon.com/support/)

## Security Best Practices

- Regularly update WordPress core and plugins
- Use strong passwords for WordPress admin accounts
- Enable automatic backups
- Configure SSL/TLS certificates for production use
- Monitor access logs for suspicious activity
- Consider enabling AWS CloudTrail for audit logging

## Scaling Considerations

As your site grows, consider:
- Upgrading to larger Lightsail bundles
- Implementing CDN with Lightsail distributions
- Separating database to Lightsail managed database
- Adding load balancing for high availability
- Migrating to full AWS architecture (EC2, RDS, etc.)

## Customization

Refer to the variable definitions in each implementation to customize the deployment for your environment. Common customizations include:

- Instance size and specifications
- Availability zone selection
- Custom resource naming
- Additional firewall rules
- Backup scheduling
- Domain configuration

## Support

For issues with this infrastructure code, refer to:
- The original recipe documentation
- AWS Lightsail documentation
- Provider-specific documentation for each IaC tool
- AWS Support for account-specific issues