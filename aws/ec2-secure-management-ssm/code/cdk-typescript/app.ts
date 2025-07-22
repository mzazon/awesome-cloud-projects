#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as ssm from 'aws-cdk-lib/aws-ssm';

/**
 * Props for the SecureEC2Stack
 */
interface SecureEC2StackProps extends cdk.StackProps {
  /**
   * The instance type for the EC2 instance
   * @default t2.micro
   */
  readonly instanceType?: ec2.InstanceType;
  
  /**
   * The operating system for the EC2 instance
   * @default AMAZON_LINUX_2023
   */
  readonly operatingSystem?: ec2.OperatingSystemType;
  
  /**
   * Whether to create a CloudWatch log group for session logging
   * @default true
   */
  readonly enableSessionLogging?: boolean;
  
  /**
   * Whether to deploy a simple web application
   * @default true
   */
  readonly deployWebApp?: boolean;
}

/**
 * CDK Stack for securely managing EC2 instances using AWS Systems Manager
 * 
 * This stack creates:
 * - EC2 instance with Systems Manager permissions
 * - IAM role with minimal required permissions for Systems Manager
 * - Security group that blocks all inbound traffic
 * - CloudWatch log group for session logging
 * - Optional web application deployment via user data
 */
export class SecureEC2Stack extends cdk.Stack {
  /**
   * The EC2 instance
   */
  public readonly instance: ec2.Instance;
  
  /**
   * The security group for the EC2 instance
   */
  public readonly securityGroup: ec2.SecurityGroup;
  
  /**
   * The IAM role for the EC2 instance
   */
  public readonly instanceRole: iam.Role;
  
  /**
   * The CloudWatch log group for session logging (if enabled)
   */
  public readonly sessionLogGroup?: logs.LogGroup;

  constructor(scope: Construct, id: string, props: SecureEC2StackProps = {}) {
    super(scope, id, props);

    // Default values
    const instanceType = props.instanceType ?? ec2.InstanceType.of(ec2.InstanceClass.T2, ec2.InstanceSize.MICRO);
    const operatingSystem = props.operatingSystem ?? ec2.OperatingSystemType.LINUX;
    const enableSessionLogging = props.enableSessionLogging ?? true;
    const deployWebApp = props.deployWebApp ?? true;

    // Get default VPC or create one if it doesn't exist
    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVPC', {
      isDefault: true,
    });

    // Create IAM role for EC2 instance with Systems Manager permissions
    this.instanceRole = new iam.Role(this, 'SSMInstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for EC2 instance to use AWS Systems Manager',
      managedPolicies: [
        // Minimal policy required for Systems Manager core functionality
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    // Create security group that blocks all inbound traffic
    // This demonstrates the security improvement - no SSH ports needed
    this.securityGroup = new ec2.SecurityGroup(this, 'SSMSecurityGroup', {
      vpc,
      description: 'Security group for Systems Manager managed EC2 instance - no inbound access required',
      allowAllOutbound: true, // Systems Manager requires outbound HTTPS (port 443)
    });

    // Add tags to security group for identification
    cdk.Tags.of(this.securityGroup).add('Purpose', 'SystemsManagerAccess');
    cdk.Tags.of(this.securityGroup).add('SecurityProfile', 'NoInboundAccess');

    // Choose AMI based on operating system
    let machineImage: ec2.IMachineImage;
    let userData: ec2.UserData | undefined;

    if (operatingSystem === ec2.OperatingSystemType.LINUX) {
      // Use Amazon Linux 2023 which has SSM Agent pre-installed
      machineImage = ec2.MachineImage.latestAmazonLinux2023({
        generation: ec2.AmazonLinuxGeneration.AMAZON_LINUX_2023,
        cpuType: ec2.AmazonLinuxCpuType.X86_64,
      });

      // Create user data script for Linux
      if (deployWebApp) {
        userData = ec2.UserData.forLinux();
        userData.addCommands(
          '#!/bin/bash',
          '# Update system packages',
          'dnf update -y',
          '',
          '# Install and configure nginx web server',
          'dnf install -y nginx',
          'systemctl enable nginx',
          'systemctl start nginx',
          '',
          '# Create simple web page',
          'cat > /usr/share/nginx/html/index.html << EOF',
          '<html>',
          '<head><title>Systems Manager Managed Server</title></head>',
          '<body>',
          '<h1>Hello from AWS Systems Manager!</h1>',
          '<p>This server is managed securely without SSH access.</p>',
          '<p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>',
          '<p>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>',
          '<p>Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)</p>',
          '</body>',
          '</html>',
          'EOF',
          '',
          '# Restart nginx to ensure it\'s running',
          'systemctl restart nginx',
          '',
          '# Log successful deployment',
          'echo "Web server deployed successfully at $(date)" >> /var/log/deployment.log'
        );
      }
    } else {
      // Use Windows Server 2022 which has SSM Agent pre-installed
      machineImage = ec2.MachineImage.latestWindows(ec2.WindowsVersion.WINDOWS_SERVER_2022_ENGLISH_FULL_BASE);
      
      if (deployWebApp) {
        userData = ec2.UserData.forWindows();
        userData.addCommands(
          '# Install IIS web server',
          'Install-WindowsFeature -name Web-Server -IncludeManagementTools',
          '',
          '# Create simple web page',
          '$html = @"',
          '<html>',
          '<head><title>Systems Manager Managed Server</title></head>',
          '<body>',
          '<h1>Hello from AWS Systems Manager!</h1>',
          '<p>This Windows server is managed securely without RDP access.</p>',
          '</body>',
          '</html>',
          '"@',
          '',
          '$html | Out-File -FilePath C:\\inetpub\\wwwroot\\index.html -Encoding utf8',
          '',
          '# Log successful deployment',
          'Add-Content -Path C:\\deployment.log -Value "Web server deployed successfully at $(Get-Date)"'
        );
      }
    }

    // Create the EC2 instance
    this.instance = new ec2.Instance(this, 'SSMManagedInstance', {
      vpc,
      instanceType,
      machineImage,
      role: this.instanceRole,
      securityGroup: this.securityGroup,
      userData,
      // Use detailed monitoring for better observability
      detailedMonitoring: true,
      // Ensure instance can access Systems Manager service
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC, // Needed for internet access to reach Systems Manager endpoints
      },
    });

    // Add tags to the instance for identification and management
    cdk.Tags.of(this.instance).add('Name', 'SSM-Managed-Instance');
    cdk.Tags.of(this.instance).add('ManagedBy', 'SystemsManager');
    cdk.Tags.of(this.instance).add('Environment', 'Demo');
    cdk.Tags.of(this.instance).add('Project', 'SecureInstanceManagement');

    // Create CloudWatch log group for session logging if enabled
    if (enableSessionLogging) {
      this.sessionLogGroup = new logs.LogGroup(this, 'SessionLogGroup', {
        logGroupName: `/aws/ssm/sessions/${this.stackName}`,
        retention: logs.RetentionDays.ONE_WEEK,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      });

      // Create SSM document for session manager preferences
      new ssm.CfnDocument(this, 'SessionManagerPreferences', {
        documentType: 'Session',
        documentFormat: 'JSON',
        content: {
          schemaVersion: '1.0',
          description: 'Document to hold regional settings for Session Manager',
          sessionType: 'Standard_Stream',
          inputs: {
            s3BucketName: '',
            s3KeyPrefix: '',
            s3EncryptionEnabled: true,
            cloudWatchLogGroupName: this.sessionLogGroup.logGroupName,
            cloudWatchEncryptionEnabled: false,
            cloudWatchStreamingEnabled: true,
          },
        },
        name: 'SSM-SessionManagerRunShell',
      });

      // Grant permissions to write to CloudWatch Logs
      this.sessionLogGroup.grantWrite(this.instanceRole);
    }

    // Add explicit dependency to ensure proper resource creation order
    this.instance.node.addDependency(this.instanceRole);
    
    // Output important information
    new cdk.CfnOutput(this, 'InstanceId', {
      value: this.instance.instanceId,
      description: 'EC2 Instance ID for Systems Manager access',
    });

    new cdk.CfnOutput(this, 'InstancePrivateIp', {
      value: this.instance.instancePrivateIp,
      description: 'Private IP address of the EC2 instance',
    });

    new cdk.CfnOutput(this, 'SecurityGroupId', {
      value: this.securityGroup.securityGroupId,
      description: 'Security Group ID (configured for no inbound access)',
    });

    new cdk.CfnOutput(this, 'SessionManagerCommand', {
      value: `aws ssm start-session --target ${this.instance.instanceId}`,
      description: 'Command to start a Session Manager session to the instance',
    });

    new cdk.CfnOutput(this, 'ConsoleSessionManagerUrl', {
      value: `https://${this.region}.console.aws.amazon.com/systems-manager/session-manager/${this.instance.instanceId}`,
      description: 'Direct URL to Session Manager in AWS Console',
    });

    if (this.sessionLogGroup) {
      new cdk.CfnOutput(this, 'SessionLogGroupName', {
        value: this.sessionLogGroup.logGroupName,
        description: 'CloudWatch Log Group for session logging',
      });
    }

    if (deployWebApp && operatingSystem === ec2.OperatingSystemType.LINUX) {
      new cdk.CfnOutput(this, 'WebServerTestCommand', {
        value: `aws ssm send-command --document-name "AWS-RunShellScript" --targets "Key=InstanceIds,Values=${this.instance.instanceId}" --parameters 'commands=["curl -s http://localhost | grep Systems"]'`,
        description: 'Command to test the web server via Systems Manager Run Command',
      });
    }
  }
}

/**
 * CDK App for the Secure EC2 Systems Manager solution
 */
const app = new cdk.App();

// Get context values with defaults
const environment = app.node.tryGetContext('environment') || 'demo';
const instanceType = app.node.tryGetContext('instanceType') || 't2.micro';
const operatingSystem = app.node.tryGetContext('operatingSystem') || 'linux';
const enableSessionLogging = app.node.tryGetContext('enableSessionLogging') !== 'false';
const deployWebApp = app.node.tryGetContext('deployWebApp') !== 'false';

// Parse instance type
let parsedInstanceType: ec2.InstanceType;
try {
  const [instanceClass, instanceSize] = instanceType.split('.');
  parsedInstanceType = ec2.InstanceType.of(
    instanceClass as ec2.InstanceClass,
    instanceSize as ec2.InstanceSize
  );
} catch (error) {
  console.warn(`Invalid instance type '${instanceType}', using t2.micro as fallback`);
  parsedInstanceType = ec2.InstanceType.of(ec2.InstanceClass.T2, ec2.InstanceSize.MICRO);
}

// Parse operating system
const parsedOperatingSystem = operatingSystem.toLowerCase() === 'windows' 
  ? ec2.OperatingSystemType.WINDOWS 
  : ec2.OperatingSystemType.LINUX;

// Create the stack
new SecureEC2Stack(app, `SecureEC2SystemsManager-${environment}`, {
  instanceType: parsedInstanceType,
  operatingSystem: parsedOperatingSystem,
  enableSessionLogging,
  deployWebApp,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Secure EC2 instance management using AWS Systems Manager - eliminates need for SSH/RDP access',
  tags: {
    Project: 'SecureInstanceManagement',
    Environment: environment,
    ManagedBy: 'CDK',
    Purpose: 'SystemsManagerDemo',
  },
});

// Add global tags
cdk.Tags.of(app).add('Project', 'SecureInstanceManagement');
cdk.Tags.of(app).add('CreatedBy', 'CDK');
cdk.Tags.of(app).add('Repository', 'aws-recipes');