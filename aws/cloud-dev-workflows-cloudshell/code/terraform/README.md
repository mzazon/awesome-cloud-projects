# Terraform Infrastructure for Cloud-Based Development Workflows

This Terraform configuration deploys infrastructure for cloud-based development workflows using AWS CloudShell and CodeCommit. It creates a complete development environment that supports team collaboration, version control, and secure access management.

## Architecture Overview

The infrastructure includes:

- **CodeCommit Repository**: Secure Git repository for source code
- **IAM Resources**: Groups, policies, and optional users for access control
- **CloudWatch Logging**: Development activity monitoring
- **Systems Manager Parameters**: Configuration storage
- **Lambda Function**: Repository initialization automation

## Prerequisites

- AWS CLI installed and configured with appropriate credentials
- Terraform >= 1.0 installed
- IAM permissions for:
  - CodeCommit (repository management)
  - IAM (user/group/policy management)
  - CloudWatch (log group management)
  - Systems Manager (parameter management)
  - Lambda (function deployment)

## Quick Start

1. **Clone and Navigate**:
   ```bash
   git clone <repository-url>
   cd aws/cloud-based-development-workflows-cloudshell-codecommit/code/terraform/
   ```

2. **Configure Variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your desired configuration
   ```

3. **Initialize and Deploy**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Access CloudShell**:
   - Open AWS Management Console
   - Click CloudShell icon in the top navigation
   - Run the setup commands from terraform outputs

## Configuration

### Required Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `aws_region` | AWS region for deployment | `us-east-1` | `us-west-2` |
| `environment` | Environment name | `dev` | `staging` |
| `project_name` | Project name for resources | `dev-workflow` | `myapp` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `repository_name` | CodeCommit repository name | Auto-generated |
| `repository_description` | Repository description | Pre-defined |
| `create_iam_user` | Create test IAM user | `false` |
| `iam_user_name` | IAM user name | Auto-generated |
| `cloudshell_timeout` | CloudShell timeout (minutes) | `20` |
| `team_size` | Expected team size | `5` |
| `enable_versioning` | Enable versioning | `true` |
| `additional_tags` | Additional resource tags | `{}` |

### Example Configurations

#### Development Environment
```hcl
aws_region = "us-east-1"
environment = "dev"
project_name = "myapp-dev"
create_iam_user = true
team_size = 3
additional_tags = {
  Owner = "dev-team"
  CostCenter = "engineering"
}
```

#### Production Environment
```hcl
aws_region = "us-west-2"
environment = "prod"
project_name = "myapp-prod"
create_iam_user = false
team_size = 10
cloudshell_timeout = 30
```

## Outputs

After deployment, Terraform provides these outputs:

### Repository Information
- `repository_name`: CodeCommit repository name
- `repository_clone_url_http`: HTTPS clone URL
- `repository_arn`: Repository ARN

### IAM Resources
- `iam_group_name`: Developer group name
- `codecommit_policy_arn`: CodeCommit access policy ARN
- `cloudshell_policy_arn`: CloudShell access policy ARN

### Setup Instructions
- `cloudshell_setup_commands`: Commands to configure CloudShell
- `next_steps`: Recommended actions after deployment

### Cost and Security Information
- `estimated_monthly_cost`: Cost breakdown
- `security_considerations`: Security features

## Usage Instructions

### 1. Access CloudShell

1. Sign in to AWS Management Console
2. Click the CloudShell icon (>_) in the top navigation bar
3. Wait for the environment to initialize (30-60 seconds)

### 2. Configure Git

Run the setup commands provided in the Terraform output:

```bash
# Configure Git credentials
git config --global credential.helper '!aws codecommit credential-helper $@'
git config --global credential.UseHttpPath true
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

### 3. Clone Repository

```bash
# Clone the repository (URL from Terraform output)
git clone <repository-clone-url>
cd <repository-name>
```

### 4. Start Development

```bash
# Create feature branch
git checkout -b feature/my-feature

# Make changes
echo "# My Feature" > feature.md

# Commit and push
git add .
git commit -m "Add my feature"
git push origin feature/my-feature
```

## Team Management

### Adding Team Members

1. **Add users to IAM group**:
   ```bash
   aws iam add-user-to-group \
     --group-name <group-name-from-output> \
     --user-name <username>
   ```

2. **Provide setup instructions**:
   - Share CloudShell access instructions
   - Provide repository clone URL
   - Share Git configuration commands

### Access Management

The infrastructure creates:

- **IAM Group**: `<project>-<environment>-developers`
- **IAM Policies**: 
  - CodeCommit access (read/write)
  - CloudShell access (full)
- **Optional IAM User**: For testing and demonstration

## Security Features

- **Encryption**: All data encrypted in transit and at rest
- **IAM Integration**: Uses AWS IAM for authentication
- **Least Privilege**: Minimal required permissions
- **Audit Trail**: CloudTrail logs all API calls
- **Network Security**: HTTPS/TLS for all communications

## Monitoring and Logging

- **CloudWatch Logs**: Development activity logging
- **Systems Manager**: Configuration parameter storage
- **AWS CloudTrail**: API call auditing
- **Lambda Logs**: Repository initialization logs

## Cost Management

### Free Tier Benefits
- **CodeCommit**: 5 active users, 50GB storage, 10k requests/month
- **CloudShell**: 10 hours/month
- **Lambda**: 1M requests, 400k GB-seconds/month
- **CloudWatch**: 5GB logs, basic monitoring

### Estimated Costs (Beyond Free Tier)
- **CodeCommit**: $1/user/month, $0.06/GB storage
- **CloudShell**: $0.10/hour
- **Lambda**: $0.20/1M requests
- **CloudWatch Logs**: $0.50/GB ingestion, $0.03/GB storage

## Maintenance

### Updates
```bash
# Update Terraform configuration
terraform plan
terraform apply

# Update repository initialization
terraform taint aws_lambda_function.repo_initializer
terraform apply
```

### Backup
- CodeCommit repositories are automatically backed up
- Export important configurations:
  ```bash
  terraform output > infrastructure-outputs.json
  ```

## Troubleshooting

### Common Issues

1. **CloudShell Access Denied**:
   - Verify IAM permissions
   - Check CloudShell service availability in region

2. **Git Authentication Failed**:
   - Reconfigure credential helper
   - Verify IAM CodeCommit permissions

3. **Repository Not Found**:
   - Check repository name in outputs
   - Verify region matches deployment

### Debug Commands

```bash
# Check repository status
aws codecommit get-repository --repository-name <repo-name>

# Verify IAM group membership
aws iam get-group --group-name <group-name>

# Test CloudShell access
aws sts get-caller-identity
```

## Cleanup

To remove all resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete:
- CodeCommit repository and all code
- IAM groups, policies, and users
- CloudWatch logs
- All other created resources

## Support

- [AWS CloudShell Documentation](https://docs.aws.amazon.com/cloudshell/)
- [AWS CodeCommit Documentation](https://docs.aws.amazon.com/codecommit/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

## Contributing

1. Fork the repository
2. Create feature branch
3. Make changes
4. Test thoroughly
5. Submit pull request

## License

This infrastructure code is provided as-is for educational and demonstration purposes.