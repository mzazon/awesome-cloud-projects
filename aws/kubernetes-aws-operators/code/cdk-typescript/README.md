# Kubernetes Operators for AWS Resources - CDK TypeScript

This CDK TypeScript application deploys infrastructure for creating Kubernetes operators that manage AWS resources using AWS Controllers for Kubernetes (ACK). The solution demonstrates how to build custom operators that extend ACK capabilities for organization-specific resource management patterns.

## Architecture Overview

The CDK application provisions:

- **EKS Cluster**: Managed Kubernetes cluster with OIDC provider for IRSA
- **VPC Infrastructure**: Multi-AZ VPC with public and private subnets
- **IAM Roles**: Properly configured roles for ACK controllers with least privilege
- **S3 Bucket**: Application storage with security best practices
- **Lambda Function**: Serverless processing for operator integration
- **Networking**: VPC Flow Logs and security groups for monitoring

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ and npm 9+ installed
- AWS CDK v2 installed globally: `npm install -g aws-cdk`
- Docker installed (for building container images)
- kubectl installed for cluster management
- Helm 3.8+ for ACK controller installation

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (if not done before)

```bash
npm run bootstrap
# or
cdk bootstrap
```

### 3. Review and Customize Configuration

Edit `cdk.json` to customize the deployment:

```json
{
  "context": {
    "clusterName": "ack-operators-cluster",
    "resourceSuffix": "demo",
    "enableLogging": true,
    "nodeGroupInstanceTypes": ["t3.medium"],
    "nodeGroupDesiredSize": 2,
    "nodeGroupMinSize": 1,
    "nodeGroupMaxSize": 4,
    "environment": "development",
    "owner": "platform-team",
    "costCenter": "engineering"
  }
}
```

### 4. Deploy the Stack

```bash
npm run deploy
# or
cdk deploy
```

### 5. Configure kubectl

After deployment, update your kubectl configuration:

```bash
aws eks update-kubeconfig --region <region> --name ack-operators-cluster
```

### 6. Install ACK Controllers

Use the Helm commands provided in the stack outputs:

```bash
# Add ACK Helm repository
helm repo add aws-controllers-k8s https://aws-controllers-k8s.github.io/charts
helm repo update

# Install S3 controller
helm install ack-s3-controller oci://public.ecr.aws/aws-controllers-k8s/s3-chart \
    --namespace ack-system \
    --set aws.region=<region> \
    --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="<ack-role-arn>"

# Install IAM controller
helm install ack-iam-controller oci://public.ecr.aws/aws-controllers-k8s/iam-chart \
    --namespace ack-system \
    --set aws.region=<region> \
    --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="<ack-role-arn>"

# Install Lambda controller
helm install ack-lambda-controller oci://public.ecr.aws/aws-controllers-k8s/lambda-chart \
    --namespace ack-system \
    --set aws.region=<region> \
    --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="<ack-role-arn>"
```

## Available Commands

```bash
# Build TypeScript
npm run build

# Run in watch mode
npm run watch

# Run tests
npm run test

# Run tests in watch mode
npm run test:watch

# Lint code
npm run lint

# Fix linting issues
npm run lint:fix

# Format code
npm run format

# Generate documentation
npm run docs

# CDK commands
npm run synth    # Synthesize CloudFormation template
npm run deploy   # Deploy stack
npm run diff     # Show differences
npm run destroy  # Destroy stack
```

## Project Structure

```
├── app.ts                           # CDK application entry point
├── lib/
│   └── kubernetes-operators-stack.ts # Main stack definition
├── test/                            # Unit tests
├── package.json                     # Dependencies and scripts
├── tsconfig.json                    # TypeScript configuration
├── cdk.json                         # CDK configuration
└── README.md                        # This file
```

## Key Components

### EKS Cluster

- Kubernetes version 1.28
- Managed node groups with configurable instance types
- OIDC provider for IRSA (IAM Roles for Service Accounts)
- Comprehensive logging (API, audit, authenticator, etc.)
- Security-hardened configuration

### IAM Roles

- **ACK Controller Role**: Permissions for S3, IAM, and Lambda ACK controllers
- **Sample Application Role**: Example role for demo applications
- **EKS Cluster Role**: Service role for EKS cluster management
- **Node Group Role**: Worker node permissions

### VPC Configuration

- Multi-AZ setup across 3 availability zones
- Public subnets for load balancers and NAT gateways
- Private subnets for worker nodes and applications
- VPC Flow Logs for network monitoring
- Security groups with least privilege access

### S3 Bucket

- Encrypted with S3-managed keys
- Versioning enabled for data protection
- Block public access for security
- Lifecycle rules for cost optimization
- SSL-only access policy

### Lambda Function

- Python 3.9 runtime
- Integrated with S3 bucket for processing
- CloudWatch logging enabled
- Environment variables for configuration
- IAM role with minimal required permissions

## Customization Options

### Node Group Configuration

Modify the node group settings in `cdk.json`:

```json
{
  "nodeGroupInstanceTypes": ["t3.medium", "t3.large"],
  "nodeGroupDesiredSize": 3,
  "nodeGroupMinSize": 1,
  "nodeGroupMaxSize": 6
}
```

### Environment-specific Deployments

Use CDK context for environment-specific configurations:

```bash
# Development environment
cdk deploy --context environment=development

# Production environment
cdk deploy --context environment=production --context enableLogging=true
```

### Security Hardening

The stack implements several security best practices:

- IRSA for pod-level AWS permissions
- Encrypted S3 storage with SSL enforcement
- VPC with private subnets for worker nodes
- Security groups with minimal required access
- CloudWatch logging for audit trails

## Testing Custom Operators

After deploying the infrastructure and installing ACK controllers, you can test custom operator functionality:

### 1. Deploy Application CRD

```bash
kubectl apply -f - <<EOF
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: applications.platform.example.com
spec:
  group: platform.example.com
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              name:
                type: string
              environment:
                type: string
                enum: ["dev", "staging", "prod"]
          status:
            type: object
            properties:
              phase:
                type: string
              bucketName:
                type: string
  scope: Namespaced
  names:
    plural: applications
    singular: application
    kind: Application
EOF
```

### 2. Create Test Application

```bash
kubectl apply -f - <<EOF
apiVersion: platform.example.com/v1
kind: Application
metadata:
  name: sample-app
  namespace: default
spec:
  name: sample-app
  environment: dev
EOF
```

### 3. Verify Resources

```bash
# Check application status
kubectl get applications

# Verify AWS resources were created through ACK
kubectl get buckets
kubectl get roles
kubectl get functions
```

## Monitoring and Observability

The stack includes comprehensive monitoring capabilities:

### CloudWatch Logs

- EKS cluster logs (API, audit, authenticator, controller manager, scheduler)
- VPC Flow Logs for network monitoring
- Lambda function execution logs
- ACK controller logs (when controllers are installed)

### Metrics and Alarms

Consider adding CloudWatch alarms for:

- EKS cluster health
- Node group capacity utilization
- Lambda function errors and duration
- S3 bucket access patterns

## Cost Optimization

### Resource Sizing

- Use appropriate instance types for your workload
- Configure auto-scaling for node groups
- Consider Spot instances for non-critical workloads
- Implement S3 lifecycle policies for data archival

### Monitoring Costs

- Enable AWS Cost Explorer for cost tracking
- Tag resources consistently for cost allocation
- Monitor EKS cluster costs with container insights
- Set up billing alerts for cost control

## Troubleshooting

### Common Issues

1. **OIDC Provider Issues**
   ```bash
   # Verify OIDC provider configuration
   aws eks describe-cluster --name ack-operators-cluster --query cluster.identity.oidc.issuer
   ```

2. **ACK Controller Permission Issues**
   ```bash
   # Check service account annotations
   kubectl describe sa ack-controller -n ack-system
   ```

3. **Node Group Issues**
   ```bash
   # Check node group status
   kubectl get nodes
   kubectl describe nodes
   ```

### Debugging Commands

```bash
# Check CDK synthesis
npm run synth

# View differences before deployment
npm run diff

# Check CloudFormation events
aws cloudformation describe-stack-events --stack-name KubernetesOperatorsStack
```

## Security Considerations

### IAM Permissions

- ACK controllers use IRSA for secure AWS API access
- Roles follow principle of least privilege
- Service accounts are properly configured with role annotations

### Network Security

- Worker nodes run in private subnets
- Security groups restrict unnecessary traffic
- VPC Flow Logs provide network monitoring

### Data Security

- S3 bucket encryption enabled
- SSL-only access policies
- Private bucket configuration with no public access

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and add tests
4. Run linting and tests: `npm run lint && npm run test`
5. Submit a pull request

## Cleanup

To avoid ongoing charges, destroy the stack when no longer needed:

```bash
# Remove ACK controllers first
helm uninstall ack-s3-controller -n ack-system
helm uninstall ack-iam-controller -n ack-system
helm uninstall ack-lambda-controller -n ack-system

# Destroy the CDK stack
npm run destroy
# or
cdk destroy
```

## Support

For issues with this CDK application:

1. Check the [CDK documentation](https://docs.aws.amazon.com/cdk/)
2. Review [EKS best practices](https://aws.github.io/aws-eks-best-practices/)
3. Consult [ACK documentation](https://aws-controllers-k8s.github.io/community/)
4. Open an issue in the repository

## License

This code is licensed under the MIT-0 License. See the LICENSE file for details.