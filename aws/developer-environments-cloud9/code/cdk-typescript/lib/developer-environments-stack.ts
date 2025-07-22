import * as cdk from 'aws-cdk-lib';
import * as cloud9 from 'aws-cdk-lib/aws-cloud9';
import * as codecommit from 'aws-cdk-lib/aws-codecommit';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import { Construct } from 'constructs';

export interface DeveloperEnvironmentsStackProps extends cdk.StackProps {
  /**
   * The instance type for the Cloud9 environment
   * @default 't3.medium'
   */
  readonly instanceType?: string;

  /**
   * The name prefix for resources
   * @default 'dev-environment'
   */
  readonly environmentName?: string;

  /**
   * Automatic stop time in minutes
   * @default 60
   */
  readonly automaticStopTimeMinutes?: number;

  /**
   * Whether to create a CodeCommit repository
   * @default true
   */
  readonly createCodeCommitRepo?: boolean;

  /**
   * List of user ARNs to add as environment members
   * @default []
   */
  readonly teamMemberArns?: string[];
}

export class DeveloperEnvironmentsStack extends cdk.Stack {
  public readonly cloud9Environment: cloud9.CfnEnvironmentEC2;
  public readonly codeCommitRepository?: codecommit.Repository;
  public readonly cloud9Role: iam.Role;
  public readonly developmentPolicy: iam.ManagedPolicy;
  public readonly monitoringDashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: DeveloperEnvironmentsStackProps = {}) {
    super(scope, id, props);

    // Extract configuration with defaults
    const instanceType = props.instanceType || 't3.medium';
    const environmentName = props.environmentName || 'dev-environment';
    const automaticStopTimeMinutes = props.automaticStopTimeMinutes || 60;
    const createCodeCommitRepo = props.createCodeCommitRepo ?? true;
    const teamMemberArns = props.teamMemberArns || [];

    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Names.uniqueId(this).slice(-6).toLowerCase();

    // Get default VPC
    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVpc', {
      isDefault: true
    });

    // Get first available subnet
    const subnet = vpc.publicSubnets[0];

    // Create IAM role for Cloud9 environment
    this.cloud9Role = new iam.Role(this, 'Cloud9Role', {
      roleName: `Cloud9-${uniqueSuffix}-Role`,
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for Cloud9 development environment',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSCloud9EnvironmentMember'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSCloud9User')
      ]
    });

    // Create custom development policy
    this.developmentPolicy = new iam.ManagedPolicy(this, 'DevelopmentPolicy', {
      managedPolicyName: `Cloud9-Development-Policy-${uniqueSuffix}`,
      description: 'Custom policy for Cloud9 development environment with AWS service access',
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            's3:GetObject',
            's3:PutObject',
            's3:DeleteObject',
            's3:ListBucket'
          ],
          resources: ['*'],
          sid: 'S3AccessForDevelopment'
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'dynamodb:GetItem',
            'dynamodb:PutItem',
            'dynamodb:UpdateItem',
            'dynamodb:DeleteItem',
            'dynamodb:Query',
            'dynamodb:Scan'
          ],
          resources: ['*'],
          sid: 'DynamoDBAccessForDevelopment'
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'lambda:InvokeFunction',
            'lambda:GetFunction',
            'lambda:CreateFunction',
            'lambda:UpdateFunctionCode'
          ],
          resources: ['*'],
          sid: 'LambdaAccessForDevelopment'
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'codecommit:GitPull',
            'codecommit:GitPush',
            'codecommit:GetRepository',
            'codecommit:ListRepositories',
            'codecommit:CreateRepository'
          ],
          resources: ['*'],
          sid: 'CodeCommitAccessForDevelopment'
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'logs:CreateLogGroup',
            'logs:CreateLogStream',
            'logs:PutLogEvents',
            'logs:DescribeLogGroups',
            'logs:DescribeLogStreams'
          ],
          resources: ['*'],
          sid: 'CloudWatchLogsAccess'
        })
      ]
    });

    // Attach custom policy to role
    this.cloud9Role.addManagedPolicy(this.developmentPolicy);

    // Create instance profile for the role
    const instanceProfile = new iam.CfnInstanceProfile(this, 'Cloud9InstanceProfile', {
      instanceProfileName: `Cloud9-${uniqueSuffix}-InstanceProfile`,
      roles: [this.cloud9Role.roleName]
    });

    // Create Cloud9 environment
    this.cloud9Environment = new cloud9.CfnEnvironmentEC2(this, 'Cloud9Environment', {
      name: `${environmentName}-${uniqueSuffix}`,
      description: 'Development environment with pre-configured tools and settings for team collaboration',
      instanceType: instanceType,
      imageId: 'amazonlinux-2023-x86_64',
      subnetId: subnet.subnetId,
      automaticStopTimeMinutes: automaticStopTimeMinutes,
      connectionType: 'CONNECT_SSM',
      tags: [
        {
          key: 'Name',
          value: `${environmentName}-${uniqueSuffix}`
        },
        {
          key: 'Environment',
          value: 'Development'
        },
        {
          key: 'Team',
          value: 'Shared'
        }
      ]
    });

    // Create CodeCommit repository if requested
    if (createCodeCommitRepo) {
      this.codeCommitRepository = new codecommit.Repository(this, 'TeamRepository', {
        repositoryName: `team-development-repo-${uniqueSuffix}`,
        description: 'Team development repository for Cloud9 environment collaboration',
        code: codecommit.Code.fromDirectory('assets/project-templates', 'main')
      });

      // Output repository clone URL
      new cdk.CfnOutput(this, 'CodeCommitCloneUrl', {
        value: this.codeCommitRepository.repositoryCloneUrlHttp,
        description: 'CodeCommit repository clone URL',
        exportName: `${this.stackName}-CodeCommitCloneUrl`
      });
    }

    // Add team members to environment if provided
    teamMemberArns.forEach((userArn, index) => {
      new cloud9.CfnEnvironmentMembership(this, `EnvironmentMember${index}`, {
        environmentId: this.cloud9Environment.ref,
        userArn: userArn,
        permissions: 'read-write'
      });
    });

    // Create CloudWatch dashboard for monitoring
    this.monitoringDashboard = new cloudwatch.Dashboard(this, 'Cloud9Dashboard', {
      dashboardName: `Cloud9-${uniqueSuffix}-Dashboard`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Cloud9 Environment Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/EC2',
                metricName: 'CPUUtilization',
                dimensionsMap: {
                  InstanceId: this.cloud9Environment.ref
                },
                statistic: 'Average'
              })
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/EC2',
                metricName: 'NetworkIn',
                dimensionsMap: {
                  InstanceId: this.cloud9Environment.ref
                },
                statistic: 'Sum'
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/EC2',
                metricName: 'NetworkOut',
                dimensionsMap: {
                  InstanceId: this.cloud9Environment.ref
                },
                statistic: 'Sum'
              })
            ],
            period: cdk.Duration.minutes(5),
            region: this.region
          })
        ]
      ]
    });

    // Store environment configuration in SSM Parameter Store
    new ssm.StringParameter(this, 'EnvironmentConfig', {
      parameterName: `/cloud9/${uniqueSuffix}/environment-id`,
      stringValue: this.cloud9Environment.ref,
      description: 'Cloud9 environment ID for reference'
    });

    // Store setup script in SSM Parameter Store
    const setupScript = this.createSetupScript();
    new ssm.StringParameter(this, 'SetupScript', {
      parameterName: `/cloud9/${uniqueSuffix}/setup-script`,
      stringValue: setupScript,
      description: 'Cloud9 environment setup script'
    });

    // Create environment configuration script
    const envConfigScript = this.createEnvironmentConfigScript();
    new ssm.StringParameter(this, 'EnvironmentConfigScript', {
      parameterName: `/cloud9/${uniqueSuffix}/env-config-script`,
      stringValue: envConfigScript,
      description: 'Cloud9 environment configuration script with aliases and variables'
    });

    // Outputs
    new cdk.CfnOutput(this, 'Cloud9EnvironmentId', {
      value: this.cloud9Environment.ref,
      description: 'Cloud9 environment ID',
      exportName: `${this.stackName}-Cloud9EnvironmentId`
    });

    new cdk.CfnOutput(this, 'Cloud9EnvironmentName', {
      value: `${environmentName}-${uniqueSuffix}`,
      description: 'Cloud9 environment name',
      exportName: `${this.stackName}-Cloud9EnvironmentName`
    });

    new cdk.CfnOutput(this, 'InstanceType', {
      value: instanceType,
      description: 'EC2 instance type used for Cloud9 environment'
    });

    new cdk.CfnOutput(this, 'CloudWatchDashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.monitoringDashboard.dashboardName}`,
      description: 'CloudWatch dashboard URL for monitoring'
    });

    new cdk.CfnOutput(this, 'IAMRoleArn', {
      value: this.cloud9Role.roleArn,
      description: 'IAM role ARN for Cloud9 environment'
    });
  }

  /**
   * Creates the setup script for Cloud9 environment
   */
  private createSetupScript(): string {
    return `#!/bin/bash
# Cloud9 Environment Setup Script
set -e

echo "Starting Cloud9 environment setup..."

# Update system packages
sudo yum update -y

# Install additional development tools
sudo yum install -y git htop tree jq curl wget unzip

# Install Node.js and npm (latest LTS)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \\. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \\. "$NVM_DIR/bash_completion"
nvm install --lts
nvm use --lts

# Install Python tools
pip3 install --user virtualenv pytest flake8 boto3 awscli

# Install AWS CDK
npm install -g aws-cdk

# Install Terraform
wget https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
unzip terraform_1.6.6_linux_amd64.zip
sudo mv terraform /usr/local/bin/
rm terraform_1.6.6_linux_amd64.zip

# Configure Git (users should set their own credentials)
git config --global init.defaultBranch main
git config --global pull.rebase false

# Create common project structure
mkdir -p ~/projects/{frontend,backend,scripts,infrastructure}
mkdir -p ~/projects/templates/{web-app,api-service,data-pipeline}

# Create project templates
cat > ~/projects/templates/web-app/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cloud9 Web App</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to Cloud9 Development</h1>
        <p>This is a template for web applications in Cloud9.</p>
    </div>
</body>
</html>
EOF

# Create Python API template
cat > ~/projects/templates/api-service/app.py << 'EOF'
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/')
def hello():
    return jsonify({"message": "Hello from Cloud9 API!"})

@app.route('/health')
def health():
    return jsonify({"status": "healthy"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)
EOF

# Create requirements file
cat > ~/projects/templates/api-service/requirements.txt << 'EOF'
Flask==2.3.3
requests==2.31.0
python-dotenv==1.0.0
boto3==1.34.0
EOF

echo "✅ Development environment setup complete!"
echo "🚀 Run 'source ~/.bashrc' to reload environment"
echo "📁 Project templates available in ~/projects/templates/"
echo "🔧 Tools installed: Node.js (LTS), Python tools, AWS CDK, Terraform"`;
  }

  /**
   * Creates the environment configuration script
   */
  private createEnvironmentConfigScript(): string {
    return `#!/bin/bash
# Cloud9 Environment Configuration
# Add this to ~/.bashrc or run manually

# Common environment variables
export NODE_ENV=development
export PYTHONPATH="$HOME/projects:$PYTHONPATH"
export PATH="$HOME/.local/bin:$PATH"
export CDK_NEW_BOOTSTRAP=1

# AWS specific environment variables
export AWS_DEFAULT_OUTPUT=json
export AWS_PAGER=""

# Helpful aliases
alias ll='ls -la'
alias la='ls -la'
alias proj='cd ~/projects'
alias templates='cd ~/projects/templates'

# Git shortcuts
alias gs='git status'
alias gp='git pull'
alias gc='git commit'
alias gco='git checkout'
alias gb='git branch'
alias gd='git diff'
alias ga='git add'

# AWS CLI shortcuts
alias awsprofile='aws configure list'
alias awsregion='aws configure get region'
alias awsaccount='aws sts get-caller-identity'

# Development shortcuts
alias serve='python3 -m http.server 8080'
alias venv='python3 -m venv'
alias activate='source venv/bin/activate'

# CDK shortcuts
alias cdkdiff='cdk diff'
alias cdkdeploy='cdk deploy'
alias cdkdestroy='cdk destroy'
alias cdksyn='cdk synth'

# Docker shortcuts (if Docker is installed)
alias dps='docker ps'
alias dpa='docker ps -a'
alias di='docker images'
alias dc='docker-compose'

# Terraform shortcuts
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'

# Custom functions
function mkproject() {
    if [ -z "$1" ]; then
        echo "Usage: mkproject <project-name>"
        return 1
    fi
    mkdir -p ~/projects/$1
    cd ~/projects/$1
    git init
    echo "# $1" > README.md
    echo "Project $1 created in ~/projects/$1"
}

function clone-template() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Usage: clone-template <template-name> <project-name>"
        echo "Available templates: web-app, api-service, data-pipeline"
        return 1
    fi
    if [ ! -d "~/projects/templates/$1" ]; then
        echo "Template $1 not found"
        return 1
    fi
    cp -r ~/projects/templates/$1 ~/projects/$2
    cd ~/projects/$2
    echo "Template $1 cloned to project $2"
}

echo "🔧 Cloud9 environment configuration loaded"
echo "📚 Available aliases: gs, gp, gc, proj, serve, venv, awsprofile"
echo "🛠️  Available functions: mkproject, clone-template"
echo "💡 Run 'alias' to see all available aliases"`;
  }
}