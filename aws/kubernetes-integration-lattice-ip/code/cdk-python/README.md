# Kubernetes VPC Lattice Integration - CDK Python

This AWS CDK Python application deploys infrastructure for connecting self-managed Kubernetes clusters across VPCs using VPC Lattice as a service mesh layer with IP targets for direct pod communication.

## Architecture

The application creates:

- **Two VPCs** (10.0.0.0/16 and 10.1.0.0/16) for isolated Kubernetes clusters
- **VPC Lattice Service Network** for cross-VPC service mesh communication
- **EC2 Instances** configured as Kubernetes control planes (t3.medium)
- **Security Groups** with VPC Lattice integration for health checks
- **IP Target Groups** for direct pod IP registration
- **VPC Lattice Services** with HTTP listeners on port 80
- **CloudWatch Monitoring** with logs and dashboards
- **IAM Roles** with appropriate permissions

## Prerequisites

- Python 3.8 or later
- AWS CLI configured with appropriate credentials
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- SSH key pair in the target AWS region (optional)

## Installation

1. **Clone or download the CDK application files**

2. **Create a virtual environment** (recommended):
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Install CDK CLI** (if not already installed):
   ```bash
   npm install -g aws-cdk
   ```

## Configuration

### Environment Variables

Set the following environment variables:

```bash
export CDK_DEFAULT_ACCOUNT="123456789012"  # Your AWS account ID
export CDK_DEFAULT_REGION="us-east-1"     # Your preferred AWS region
```

### Context Variables

You can customize the deployment by setting context variables in `cdk.json` or via command line:

- `deployment_name`: Prefix for all resource names (default: "k8s-lattice")
- `ssh_key_name`: Name of EC2 key pair for SSH access (optional)

**Example with custom values**:
```bash
cdk deploy -c deployment_name="my-k8s-mesh" -c ssh_key_name="my-ssh-key"
```

## Deployment

1. **Bootstrap CDK** (first time only):
   ```bash
   cdk bootstrap
   ```

2. **Deploy the application**:
   ```bash
   cdk deploy
   ```

3. **View the deployment outputs**:
   The deployment will output important resource IDs including:
   - VPC IDs for both clusters
   - Service Network ID and domain name
   - Target Group IDs
   - Instance private IP addresses

## Usage

### Registering Pod IP Addresses

After deployment, you can register Kubernetes pod IP addresses with the target groups:

```bash
# Register frontend pod IPs with frontend target group
aws vpc-lattice register-targets \
    --target-group-identifier <FRONTEND_TARGET_GROUP_ID> \
    --targets id=<POD_IP_ADDRESS>,port=8080

# Register backend pod IPs with backend target group
aws vpc-lattice register-targets \
    --target-group-identifier <BACKEND_TARGET_GROUP_ID> \
    --targets id=<POD_IP_ADDRESS>,port=9090
```

### Service Discovery

Services are discoverable via the VPC Lattice service network domain:

```
frontend-service.<SERVICE_NETWORK_DOMAIN>
backend-service.<SERVICE_NETWORK_DOMAIN>
```

### Monitoring

Access the CloudWatch dashboard for VPC Lattice metrics:

1. Go to CloudWatch in the AWS Console
2. Navigate to Dashboards
3. Open the dashboard named: `{deployment_name}-vpc-lattice-monitoring`

## Customization

### Modifying Instance Types

To change the EC2 instance type, edit the `_create_kubernetes_instance` method in `app.py`:

```python
instance_type=ec2.InstanceType("t3.large"),  # Change from t3.medium
```

### Adding More Clusters

To add additional Kubernetes clusters, extend the stack by:

1. Creating additional VPCs using `_create_kubernetes_vpc`
2. Adding more instances with `_create_kubernetes_instance`
3. Creating additional target groups and services
4. Associating new VPCs with the service network

### Custom Security Group Rules

Modify the security group configuration in `_create_kubernetes_vpc` to add custom ingress/egress rules for your specific requirements.

## Cleanup

To remove all resources:

```bash
cdk destroy
```

**Note**: This will delete all resources created by the stack. Make sure to backup any important data first.

## Troubleshooting

### Common Issues

1. **VPC Lattice Managed Prefix List**: The application uses a hardcoded prefix list ID for VPC Lattice. If deployment fails, verify the correct prefix list ID for your region:
   ```bash
   aws ec2 describe-managed-prefix-lists \
       --filters "Name=prefix-list-name,Values=com.amazonaws.vpce.*vpc-lattice*"
   ```

2. **SSH Key Not Found**: If you specify an SSH key name that doesn't exist in the region, the deployment will fail. Either create the key pair or remove the `ssh_key_name` parameter.

3. **Instance Connect Issues**: Use AWS Systems Manager Session Manager if SSH access is not available.

### Validation Commands

After deployment, validate the infrastructure:

```bash
# Check service network status
aws vpc-lattice get-service-network --service-network-identifier <SERVICE_NETWORK_ID>

# List VPC associations
aws vpc-lattice list-service-network-vpc-associations --service-network-identifier <SERVICE_NETWORK_ID>

# Check target group health
aws vpc-lattice list-targets --target-group-identifier <TARGET_GROUP_ID>
```

## Security Considerations

- The security groups allow SSH access from anywhere (0.0.0.0/0). Consider restricting this to your IP range.
- EC2 instances have internet access for package downloads. Consider using private subnets with NAT gateways for production.
- VPC Lattice services use HTTP. For production, consider implementing authentication and authorization policies.

## Cost Optimization

- Use smaller instance types (t3.micro, t3.small) for development/testing
- Terminate resources when not in use
- Monitor VPC Lattice usage through AWS Cost Explorer

## Further Reading

- [AWS VPC Lattice Documentation](https://docs.aws.amazon.com/vpc-lattice/)
- [Kubernetes Networking Concepts](https://kubernetes.io/docs/concepts/services-networking/)
- [AWS CDK Python Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/work-with-cdk-python.html)