# Developer Environments with Cloud9 - CDK TypeScript

This CDK TypeScript application deploys a complete AWS Cloud9 development environment with team collaboration features, pre-configured development tools, and monitoring capabilities.

## Overview

This infrastructure creates:
- AWS Cloud9 environment with EC2 backend
- CodeCommit repository for team collaboration
- IAM roles and policies for development access
- CloudWatch dashboard for environment monitoring
- SSM Parameter Store for configuration management
- Project templates and development tools setup

## Architecture

The solution includes:
- **Cloud9 Environment**: Browser-based IDE with collaborative features
- **EC2 Instance**: Underlying compute for the development environment
- **CodeCommit Repository**: Git repository for version control
- **IAM Roles**: Secure access to AWS services for development
- **CloudWatch Monitoring**: Dashboard and metrics for environment usage
- **SSM Parameters**: Configuration and setup scripts storage

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ and npm installed
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for:
  - Cloud9 service
  - EC2 instances
  - IAM roles and policies
  - CodeCommit repositories
  - CloudWatch dashboards
  - SSM Parameter Store

## Installation

1. **Clone and navigate to the project**:
   ```bash
   cd aws/developer-environments-aws-cloud9/code/cdk-typescript/
   ```

2. **Install dependencies**:
   ```bash
   npm install
   ```

3. **Bootstrap CDK (if not done before)**:
   ```bash
   npx cdk bootstrap
   ```

## Configuration

You can customize the deployment by providing context values:

```bash
# Example with custom configuration
npx cdk deploy -c instanceType=t3.large -c environmentName=my-dev-env
```

Available configuration options:
- `instanceType`: EC2 instance type (default: t3.medium)
- `environmentName`: Name prefix for resources (default: dev-environment)
- `automaticStopTimeMinutes`: Auto-stop time in minutes (default: 60)
- `createCodeCommitRepo`: Whether to create CodeCommit repository (default: true)
- `teamMemberArns`: Array of user ARNs to add as environment members

## Deployment

1. **Review the changes**:
   ```bash
   npx cdk diff
   ```

2. **Deploy the stack**:
   ```bash
   npx cdk deploy
   ```

3. **Note the outputs**:
   After deployment, note the Cloud9 environment ID and other important outputs.

## Usage

### Accessing the Cloud9 Environment

1. Open the AWS Console
2. Navigate to Cloud9 service
3. Find your environment by name (includes unique suffix)
4. Click "Open IDE" to launch the browser-based development environment

### Setting Up the Development Environment

Once in Cloud9, run the setup script stored in SSM:

```bash
# Get and run the setup script
aws ssm get-parameter --name "/cloud9/XXXXXX/setup-script" --query 'Parameter.Value' --output text > setup.sh
chmod +x setup.sh
./setup.sh
```

### Loading Environment Configuration

```bash
# Get and load environment configuration
aws ssm get-parameter --name "/cloud9/XXXXXX/env-config-script" --query 'Parameter.Value' --output text >> ~/.bashrc
source ~/.bashrc
```

### Cloning the Team Repository

```bash
# Clone the CodeCommit repository (URL from stack outputs)
git clone https://git-codecommit.REGION.amazonaws.com/v1/repos/team-development-repo-XXXXXX
```

### Using Project Templates

```bash
# Navigate to projects directory
cd ~/projects

# Use the clone-template function
clone-template web-app my-new-project
cd my-new-project
```

## Development Commands

- `npm run build`: Compile TypeScript to JavaScript
- `npm run watch`: Watch for changes and compile
- `npm run test`: Run the Jest unit tests
- `npm run lint`: Run ESLint for code quality
- `npm run format`: Format code using Prettier
- `npx cdk deploy`: Deploy this stack to your default AWS account/region
- `npx cdk diff`: Compare deployed stack with current state
- `npx cdk synth`: Synthesize the CloudFormation template

## Monitoring

The deployment creates a CloudWatch dashboard to monitor:
- EC2 instance CPU utilization
- Network traffic (in/out)
- Instance status

Access the dashboard through the AWS Console using the URL provided in the stack outputs.

## Adding Team Members

To add team members to the environment:

1. **Get user ARNs** from IAM
2. **Redeploy with team member ARNs**:
   ```bash
   npx cdk deploy -c teamMemberArns='["arn:aws:iam::ACCOUNT:user/user1","arn:aws:iam::ACCOUNT:user/user2"]'
   ```

Or modify the stack code to include team member ARNs permanently.

## Security Considerations

- The environment uses IAM roles with least privilege access
- CodeCommit provides secure Git hosting with IAM integration
- Cloud9 environments use SSM Session Manager for secure access
- All resources are tagged for proper governance

## Cost Optimization

- Environment auto-stops after 60 minutes of inactivity (configurable)
- Use appropriate instance types for your team's needs
- Monitor usage through CloudWatch dashboard
- Consider using Spot instances for non-production environments

## Troubleshooting

### Environment Not Starting
- Check EC2 limits in your account
- Verify subnet has internet access
- Check IAM permissions for Cloud9 service

### Cannot Access CodeCommit
- Verify IAM permissions for CodeCommit
- Check AWS CLI configuration
- Ensure Git credentials are configured

### Setup Script Fails
- Check internet connectivity from Cloud9 environment
- Verify IAM permissions for SSM Parameter Store
- Check EC2 instance has appropriate role attached

## Cleanup

To remove all resources:

```bash
npx cdk destroy
```

This will delete:
- Cloud9 environment and associated EC2 instance
- CodeCommit repository (⚠️ **Warning**: This will delete all code)
- IAM roles and policies
- CloudWatch dashboard
- SSM parameters

**Note**: Make sure to backup any important code before destroying the stack.

## Customization

### Adding Development Tools

Modify the `createSetupScript()` method in the stack to include additional tools:

```typescript
// Add to setup script
sudo yum install -y docker
sudo systemctl start docker
sudo usermod -a -G docker ec2-user
```

### Custom IAM Permissions

Add additional policies to the `developmentPolicy` managed policy:

```typescript
new iam.PolicyStatement({
  effect: iam.Effect.ALLOW,
  actions: ['service:action'],
  resources: ['*']
})
```

### Environment Templates

Modify the project template creation in the setup script to include your organization's standard project structures.

## Support

For issues with this CDK application:
1. Check the AWS CDK documentation
2. Review AWS Cloud9 service documentation
3. Check CloudFormation events in the AWS Console
4. Review CloudWatch logs for the EC2 instance

## License

This code is provided under the MIT License. See LICENSE file for details.