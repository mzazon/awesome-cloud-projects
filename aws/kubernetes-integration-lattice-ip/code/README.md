# Infrastructure as Code for Self-Managed Kubernetes Integration with VPC Lattice IP Targets

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Self-Managed Kubernetes Integration with VPC Lattice IP Targets".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - VPC Lattice service management
  - EC2 instance and networking operations
  - CloudWatch logs and metrics
  - IAM role creation (for some implementations)
- Docker installed (for building container images)
- For CDK implementations: Node.js 18+ or Python 3.8+
- For Terraform: Terraform 1.0+
- Estimated cost: $20-40 for 45 minutes of testing

> **Note**: This recipe creates resources across multiple VPCs and requires careful network configuration. Ensure you understand VPC Lattice pricing before proceeding.

## Architecture Overview

This implementation creates:
- Two separate VPCs with Kubernetes clusters
- VPC Lattice service network for cross-VPC communication
- IP target groups for pod-level routing
- CloudWatch monitoring and logging
- Security groups configured for VPC Lattice integration

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name kubernetes-lattice-integration \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=KeyPairName,ParameterValue=your-key-pair \
    --capabilities CAPABILITY_IAM

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name kubernetes-lattice-integration

# Get outputs
aws cloudformation describe-stacks \
    --stack-name kubernetes-lattice-integration \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters keyPairName=your-key-pair

# View outputs
cdk outputs
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters keyPairName=your-key-pair

# View outputs
cdk outputs
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="key_pair_name=your-key-pair"

# Apply the configuration
terraform apply -var="key_pair_name=your-key-pair"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters
# and guide you through the deployment process
```

## Post-Deployment Configuration

After deploying the infrastructure, you'll need to:

1. **SSH into EC2 instances** to complete Kubernetes setup:
   ```bash
   # Connect to cluster A instance
   ssh -i your-key-pair.pem ec2-user@<INSTANCE_A_PUBLIC_IP>
   
   # Initialize Kubernetes cluster
   sudo kubeadm init --pod-network-cidr=192.168.0.0/16
   ```

2. **Register actual pod IPs** with VPC Lattice target groups:
   ```bash
   # Get pod IPs from Kubernetes
   kubectl get pods -o wide
   
   # Register pod IPs with VPC Lattice
   aws vpc-lattice register-targets \
       --target-group-identifier <TARGET_GROUP_ID> \
       --targets id=<POD_IP>,port=8080
   ```

3. **Deploy sample applications** to test cross-cluster communication:
   ```bash
   # Deploy frontend service to cluster A
   kubectl apply -f sample-apps/frontend-deployment.yaml
   
   # Deploy backend service to cluster B  
   kubectl apply -f sample-apps/backend-deployment.yaml
   ```

## Validation & Testing

1. **Verify VPC Lattice Service Network**:
   ```bash
   # Check service network status
   aws vpc-lattice get-service-network \
       --service-network-identifier <SERVICE_NETWORK_ID>
   ```

2. **Test Cross-VPC Communication**:
   ```bash
   # From cluster A, test connectivity to cluster B service
   curl http://<BACKEND_SERVICE_NAME>.<SERVICE_NETWORK_DOMAIN>/health
   ```

3. **Monitor Service Mesh Metrics**:
   ```bash
   # View CloudWatch metrics
   aws cloudwatch get-metric-statistics \
       --namespace AWS/VPCLattice \
       --metric-name ActiveConnectionCount \
       --dimensions Name=ServiceNetwork,Value=<SERVICE_NETWORK_ID> \
       --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
       --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
       --period 300 \
       --statistics Sum
   ```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name kubernetes-lattice-integration

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name kubernetes-lattice-integration
```

### Using CDK (AWS)

```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="key_pair_name=your-key-pair"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Customization

### Key Parameters

- **KeyPairName**: EC2 key pair for SSH access to Kubernetes nodes
- **InstanceType**: EC2 instance size for Kubernetes control planes (default: t3.medium)
- **VpcCidrA/VpcCidrB**: CIDR blocks for the two VPCs (default: 10.0.0.0/16, 10.1.0.0/16)
- **ServiceNetworkName**: Name for the VPC Lattice service network
- **EnableDetailedMonitoring**: Enable/disable detailed CloudWatch monitoring

### Advanced Configuration

1. **Custom Security Groups**: Modify security group rules in the IaC templates to match your network requirements
2. **Multi-AZ Deployment**: Extend the templates to deploy across multiple Availability Zones
3. **Custom CNI**: Configure alternative Container Network Interface plugins for Kubernetes
4. **Load Balancer Integration**: Add Application or Network Load Balancers for external traffic

## Troubleshooting

### Common Issues

1. **Target Health Check Failures**:
   - Verify security group rules allow VPC Lattice health checks
   - Ensure application pods are listening on configured ports
   - Check target group health check configuration

2. **Cross-VPC Communication Issues**:
   - Verify service network VPC associations
   - Check DNS resolution for VPC Lattice service domains
   - Validate target group registrations

3. **Kubernetes Cluster Issues**:
   - Check EC2 instance user data execution logs: `/var/log/cloud-init-output.log`
   - Verify Docker and kubelet service status
   - Review Kubernetes cluster initialization logs

### Monitoring and Logs

- **VPC Lattice Access Logs**: `/aws/vpc-lattice/<service-network-name>`
- **EC2 Instance Logs**: CloudWatch Logs agent (if configured)
- **CloudWatch Metrics**: `AWS/VPCLattice` namespace
- **Custom Dashboard**: VPC Lattice service mesh monitoring dashboard

## Security Considerations

- All resources are deployed with least-privilege security groups
- VPC Lattice uses AWS managed encryption for data in transit
- EC2 instances use IMDSv2 for enhanced metadata security
- CloudWatch logs are encrypted at rest

## Cost Optimization

- Use Spot instances for non-production environments
- Configure VPC Lattice target group health check intervals appropriately
- Monitor CloudWatch usage and adjust log retention periods
- Consider using smaller instance types for testing scenarios

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation for implementation details
2. Check AWS VPC Lattice documentation for service-specific guidance
3. Consult Kubernetes documentation for cluster-related issues
4. Reference provider documentation for IaC tool-specific problems

## Additional Resources

- [AWS VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)