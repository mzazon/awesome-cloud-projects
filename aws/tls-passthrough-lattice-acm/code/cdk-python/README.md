# TLS Passthrough VPC Lattice CDK Python Application

This AWS CDK Python application implements end-to-end encryption using VPC Lattice TLS passthrough, AWS Certificate Manager, and Route 53 for DNS resolution. The architecture ensures complete end-to-end encryption while simplifying service discovery and load balancing across microservices architectures.

## Architecture Overview

The application creates:

- **VPC Infrastructure**: VPC with public/private subnets and security groups
- **EC2 Target Instances**: Two instances with self-signed TLS certificates serving HTTPS content
- **VPC Lattice Service Network**: Service mesh for secure service-to-service communication
- **TLS Passthrough Configuration**: Ensures encrypted traffic flows directly to targets
- **AWS Certificate Manager**: Managed certificates for custom domains
- **Route 53 DNS**: Domain resolution pointing to VPC Lattice service

## Prerequisites

Before deploying this application, ensure you have:

1. **AWS CLI** configured with appropriate permissions
2. **AWS CDK** installed (`npm install -g aws-cdk`)
3. **Python 3.8+** with pip
4. **A registered domain name** that you can configure DNS records for
5. **Route 53 Hosted Zone** for your domain

### Required AWS Permissions

Your AWS credentials need permissions for:
- VPC Lattice (create service networks, services, listeners, target groups)
- EC2 (create instances, VPCs, security groups, subnets)
- Certificate Manager (request and manage certificates)
- Route 53 (create DNS records)
- IAM (create roles for EC2 instances)
- CloudWatch Logs (for VPC Flow Logs)

## Installation

1. **Clone or navigate to the CDK application directory**:
   ```bash
   cd aws/tls-passthrough-lattice-acm/code/cdk-python/
   ```

2. **Create a Python virtual environment**:
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Configure your domain settings** (choose one method):

   **Method A: Update cdk.json context**:
   ```json
   {
     "context": {
       "custom_domain": "api-service.yourdomain.com",
       "certificate_domain": "*.yourdomain.com", 
       "hosted_zone_name": "yourdomain.com"
     }
   }
   ```

   **Method B: Use CDK context parameters**:
   ```bash
   cdk deploy --context custom_domain=api-service.yourdomain.com \
              --context certificate_domain="*.yourdomain.com" \
              --context hosted_zone_name=yourdomain.com
   ```

## Deployment

1. **Bootstrap CDK** (one-time setup per AWS account/region):
   ```bash
   cdk bootstrap
   ```

2. **Review the CloudFormation template**:
   ```bash
   cdk synth
   ```

3. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

   The deployment will:
   - Create VPC infrastructure and EC2 instances
   - Request an ACM certificate (requires DNS validation)
   - Create VPC Lattice service network and components
   - Configure Route 53 DNS records

4. **Complete certificate validation**:
   - Go to the AWS Certificate Manager console
   - Find your requested certificate
   - Add the CNAME validation records to your DNS
   - Wait for validation to complete (usually 5-10 minutes)

## Validation and Testing

After deployment, validate the TLS passthrough functionality:

1. **Check stack outputs**:
   ```bash
   aws cloudformation describe-stacks \
     --stack-name TlsPassthroughLatticeStack \
     --query 'Stacks[0].Outputs'
   ```

2. **Test HTTPS connectivity**:
   ```bash
   # Test with certificate verification disabled (self-signed target certs)
   curl -k -v https://api-service.yourdomain.com
   
   # Verify TLS handshake details
   openssl s_client -connect api-service.yourdomain.com:443 \
     -servername api-service.yourdomain.com </dev/null
   ```

3. **Test load balancing**:
   ```bash
   # Multiple requests should show different instance IDs
   for i in {1..5}; do
     echo "Request $i:"
     curl -k -s https://api-service.yourdomain.com | grep "Instance ID"
     sleep 2
   done
   ```

## Configuration Options

### Environment Variables

Set environment variables before deployment:

```bash
export CDK_DEFAULT_ACCOUNT=123456789012
export CDK_DEFAULT_REGION=us-east-1
```

### Custom Configuration

Modify the following in `app.py` for custom configurations:

- **Instance Types**: Change `ec2.InstanceType.of()` for different instance sizes
- **Health Check Settings**: Modify target group health check parameters
- **Security Groups**: Adjust ingress rules for your security requirements
- **Certificate Domains**: Update domain validation for your specific needs

## Security Considerations

This application implements several security best practices:

- **End-to-End Encryption**: TLS traffic flows directly to targets without intermediate decryption
- **Least Privilege IAM**: EC2 instances have minimal required permissions
- **VPC Isolation**: Private subnets for target instances
- **Security Groups**: Restrictive ingress rules for HTTPS traffic only
- **VPC Flow Logs**: Network traffic monitoring for security analysis

### Compliance Features

- **PCI DSS**: Supports requirement 4.1 for encrypted transmission of cardholder data
- **HIPAA**: Technical safeguards for data transmission security
- **Zero-Trust**: No intermediate decryption points in the communication path

## Cost Optimization

Estimated monthly costs (us-east-1):
- VPC Lattice Service: ~$15-25/month
- EC2 t3.micro instances (2): ~$15-20/month
- ACM Certificate: Free
- Route 53 Hosted Zone: ~$0.50/month
- Total: ~$30-45/month

### Cost Reduction Tips

1. **Use Spot Instances**: For non-production workloads
2. **Right-size Instances**: Monitor CPU/memory usage and adjust
3. **Implement Auto Scaling**: Scale instances based on demand
4. **Use Reserved Instances**: For predictable workloads

## Monitoring and Observability

The application includes:

- **VPC Flow Logs**: Network traffic analysis
- **CloudWatch Integration**: Instance and service metrics
- **Health Checks**: Target group health monitoring
- **X-Ray Tracing**: (Can be added for distributed tracing)

View logs and metrics:
```bash
# VPC Flow Logs
aws logs describe-log-groups --log-group-name-prefix "/aws/vpc/flowlogs"

# EC2 Instance metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=i-1234567890abcdef0 \
  --start-time 2023-01-01T00:00:00Z \
  --end-time 2023-01-01T01:00:00Z \
  --period 3600 \
  --statistics Average
```

## Troubleshooting

### Common Issues

1. **Certificate Validation Fails**:
   - Verify DNS records are created correctly
   - Check that the domain is publicly resolvable
   - Ensure Route 53 hosted zone is properly configured

2. **Target Instances Unhealthy**:
   - Check security group rules allow port 443
   - Verify Apache is running: `systemctl status httpd`
   - Check instance system logs in EC2 console

3. **DNS Resolution Issues**:
   - Verify CNAME record points to VPC Lattice service DNS
   - Check TTL settings for DNS propagation
   - Use `dig` or `nslookup` to test resolution

4. **TLS Handshake Failures**:
   - Ensure target instances have valid certificates
   - Check certificate expiration dates
   - Verify TLS protocol versions match

### Debug Commands

```bash
# Check VPC Lattice service status
aws vpc-lattice get-service --service-identifier <service-id>

# Verify target group health
aws vpc-lattice list-targets --target-group-identifier <target-group-id>

# Test network connectivity
telnet api-service.yourdomain.com 443

# Check certificate details
openssl s_client -connect api-service.yourdomain.com:443 -showcerts
```

## Cleanup

To avoid ongoing charges, destroy the stack when testing is complete:

```bash
cdk destroy
```

This will remove all resources except:
- Route 53 Hosted Zone (if it existed before deployment)
- ACM Certificate (optional deletion)

## Extension Ideas

1. **Multi-Region Deployment**: Deploy across multiple AWS regions for high availability
2. **Auto Scaling**: Add auto scaling groups for target instances
3. **Application Load Balancer**: Combine with ALB for additional routing capabilities
4. **Certificate Automation**: Automate certificate rotation for target instances
5. **Service Mesh Integration**: Integrate with AWS App Mesh for advanced traffic management

## Support

For issues with this CDK application:

1. Check the [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
2. Review [VPC Lattice documentation](https://docs.aws.amazon.com/vpc-lattice/)
3. Consult the [AWS Certificate Manager guide](https://docs.aws.amazon.com/acm/)
4. Reference the original recipe documentation

## License

This code is provided under the Apache 2.0 License. See the LICENSE file for details.