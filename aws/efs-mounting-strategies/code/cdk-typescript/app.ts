#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as efs from 'aws-cdk-lib/aws-efs';
import * as iam from 'aws-cdk-lib/aws-iam';

/**
 * Configuration interface for the EFS Mounting Strategies stack
 */
interface EfsMountingStrategiesStackProps extends cdk.StackProps {
  /**
   * The VPC to deploy resources into. If not provided, a new VPC will be created.
   */
  vpc?: ec2.IVpc;
  
  /**
   * The instance type for the demo EC2 instance
   * @default t3.micro
   */
  instanceType?: ec2.InstanceType;
  
  /**
   * The EFS performance mode
   * @default generalPurpose
   */
  performanceMode?: efs.PerformanceMode;
  
  /**
   * The EFS throughput mode
   * @default provisioned
   */
  throughputMode?: efs.ThroughputMode;
  
  /**
   * Provisioned throughput in MiBps (only used when throughputMode is provisioned)
   * @default 100
   */
  provisionedThroughputPerSecond?: cdk.Size;
  
  /**
   * Whether to create a demo EC2 instance
   * @default true
   */
  createDemoInstance?: boolean;
}

/**
 * CDK Stack for implementing EFS mounting strategies
 * 
 * This stack creates:
 * - An EFS file system with encryption at rest
 * - Mount targets in multiple availability zones
 * - Security groups for NFS access
 * - Access points for different use cases
 * - IAM roles for EC2 EFS access
 * - Optional demo EC2 instance with EFS utils
 */
class EfsMountingStrategiesStack extends cdk.Stack {
  /**
   * The VPC used for the deployment
   */
  public readonly vpc: ec2.IVpc;
  
  /**
   * The EFS file system
   */
  public readonly fileSystem: efs.FileSystem;
  
  /**
   * Security group for EFS access
   */
  public readonly efsSecurityGroup: ec2.SecurityGroup;
  
  /**
   * Access points for different use cases
   */
  public readonly accessPoints: { [key: string]: efs.AccessPoint };
  
  /**
   * IAM role for EC2 EFS access
   */
  public readonly ec2Role: iam.Role;
  
  /**
   * Demo EC2 instance (optional)
   */
  public readonly demoInstance?: ec2.Instance;

  constructor(scope: Construct, id: string, props: EfsMountingStrategiesStackProps = {}) {
    super(scope, id, props);

    // Use provided VPC or create a new one
    this.vpc = props.vpc ?? new ec2.Vpc(this, 'EfsVpc', {
      maxAzs: 3,
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
      ],
    });

    // Create security group for EFS access
    this.efsSecurityGroup = new ec2.SecurityGroup(this, 'EfsSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for EFS mount targets',
      allowAllOutbound: false,
    });

    // Allow NFS traffic from within the VPC
    this.efsSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(this.vpc.vpcCidrBlock),
      ec2.Port.tcp(2049),
      'Allow NFS traffic from VPC'
    );

    // Create EFS file system with encryption and optimal settings
    this.fileSystem = new efs.FileSystem(this, 'EfsFileSystem', {
      vpc: this.vpc,
      performanceMode: props.performanceMode ?? efs.PerformanceMode.GENERAL_PURPOSE,
      throughputMode: props.throughputMode ?? efs.ThroughputMode.PROVISIONED,
      provisionedThroughputPerSecond: props.provisionedThroughputPerSecond ?? cdk.Size.mebibytes(100),
      encrypted: true,
      lifecyclePolicy: efs.LifecyclePolicy.AFTER_30_DAYS,
      outOfInfrequentAccessPolicy: efs.OutOfInfrequentAccessPolicy.AFTER_1_ACCESS,
      securityGroup: this.efsSecurityGroup,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create access points for different use cases
    this.accessPoints = {
      appData: new efs.AccessPoint(this, 'AppDataAccessPoint', {
        fileSystem: this.fileSystem,
        path: '/app-data',
        posixUser: {
          uid: 1000,
          gid: 1000,
        },
        creationInfo: {
          ownerUid: 1000,
          ownerGid: 1000,
          permissions: '0755',
        },
      }),
      
      userData: new efs.AccessPoint(this, 'UserDataAccessPoint', {
        fileSystem: this.fileSystem,
        path: '/user-data',
        posixUser: {
          uid: 2000,
          gid: 2000,
        },
        creationInfo: {
          ownerUid: 2000,
          ownerGid: 2000,
          permissions: '0750',
        },
      }),
      
      logs: new efs.AccessPoint(this, 'LogsAccessPoint', {
        fileSystem: this.fileSystem,
        path: '/logs',
        posixUser: {
          uid: 3000,
          gid: 3000,
        },
        creationInfo: {
          ownerUid: 3000,
          ownerGid: 3000,
          permissions: '0755',
        },
      }),
    };

    // Create IAM role for EC2 EFS access
    this.ec2Role = new iam.Role(this, 'Ec2EfsRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for EC2 instances to access EFS',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    // Add EFS permissions to the role
    this.ec2Role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'elasticfilesystem:ClientMount',
        'elasticfilesystem:ClientWrite',
        'elasticfilesystem:ClientRootAccess',
      ],
      resources: [this.fileSystem.fileSystemArn],
    }));

    // Create demo EC2 instance if requested
    if (props.createDemoInstance !== false) {
      this.createDemoEc2Instance(props.instanceType);
    }

    // Add tags to resources
    this.addResourceTags();
    
    // Create outputs
    this.createOutputs();
  }

  /**
   * Creates a demo EC2 instance with EFS utils pre-installed
   */
  private createDemoEc2Instance(instanceType?: ec2.InstanceType): void {
    // Create security group for EC2 instance
    const instanceSecurityGroup = new ec2.SecurityGroup(this, 'InstanceSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for demo EC2 instance',
      allowAllOutbound: true,
    });

    // Allow SSH access (optional - can be removed for production)
    instanceSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access'
    );

    // User data script to install EFS utils and create mount points
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      '#!/bin/bash',
      'yum update -y',
      'yum install -y amazon-efs-utils',
      'mkdir -p /mnt/efs',
      'mkdir -p /mnt/efs-app',
      'mkdir -p /mnt/efs-user',
      'mkdir -p /mnt/efs-logs',
      '',
      '# Install CloudWatch agent for monitoring',
      'yum install -y amazon-cloudwatch-agent',
      '',
      '# Create performance testing script',
      'cat > /home/ec2-user/efs-performance-test.sh << "EOF"',
      '#!/bin/bash',
      'echo "Testing EFS performance..."',
      'echo "Write test:"',
      'time dd if=/dev/zero of=/mnt/efs/test-file bs=1M count=100',
      'echo "Read test:"',
      'time dd if=/mnt/efs/test-file of=/dev/null bs=1M',
      'echo "Cleanup:"',
      'rm -f /mnt/efs/test-file',
      'echo "Test complete!"',
      'EOF',
      '',
      'chmod +x /home/ec2-user/efs-performance-test.sh',
      'chown ec2-user:ec2-user /home/ec2-user/efs-performance-test.sh',
      '',
      '# Create mounting examples script',
      'cat > /home/ec2-user/mount-examples.sh << "EOF"',
      '#!/bin/bash',
      'echo "EFS Mounting Examples"',
      'echo "===================="',
      'echo ""',
      'echo "1. Standard NFS mount:"',
      `echo "sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,intr,timeo=600,retrans=2 ${this.fileSystem.fileSystemId}.efs.${this.region}.amazonaws.com:/ /mnt/efs"`,
      'echo ""',
      'echo "2. EFS utils mount with TLS:"',
      `echo "sudo mount -t efs -o tls ${this.fileSystem.fileSystemId}:/ /mnt/efs"`,
      'echo ""',
      'echo "3. EFS utils mount with access point:"',
      `echo "sudo mount -t efs -o tls,accesspoint=${this.accessPoints.appData.accessPointId} ${this.fileSystem.fileSystemId}:/ /mnt/efs-app"`,
      'echo ""',
      'echo "4. Add to fstab for automatic mounting:"',
      `echo "echo '${this.fileSystem.fileSystemId}.efs.${this.region}.amazonaws.com:/ /mnt/efs efs defaults,_netdev,tls' | sudo tee -a /etc/fstab"`,
      'echo ""',
      'echo "Current mounts:"',
      'df -h | grep efs',
      'EOF',
      '',
      'chmod +x /home/ec2-user/mount-examples.sh',
      'chown ec2-user:ec2-user /home/ec2-user/mount-examples.sh',
      '',
      '# Signal completion',
      'echo "EC2 instance setup complete!" > /home/ec2-user/setup-complete.txt',
      'chown ec2-user:ec2-user /home/ec2-user/setup-complete.txt'
    );

    // Create the demo instance
    this.demoInstance = new ec2.Instance(this, 'DemoInstance', {
      vpc: this.vpc,
      instanceType: instanceType ?? ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      machineImage: ec2.MachineImage.latestAmazonLinux2(),
      securityGroup: instanceSecurityGroup,
      role: this.ec2Role,
      userData: userData,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
      keyName: undefined, // Remove this line if you want to specify a key pair
    });

    // Allow the instance to access EFS
    this.efsSecurityGroup.addIngressRule(
      instanceSecurityGroup,
      ec2.Port.tcp(2049),
      'Allow NFS access from demo instance'
    );
  }

  /**
   * Adds comprehensive tags to all resources
   */
  private addResourceTags(): void {
    const tags = {
      'Project': 'EFS-Mounting-Strategies',
      'Environment': 'Demo',
      'Purpose': 'Recipe-Implementation',
      'ManagedBy': 'CDK',
    };

    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });
  }

  /**
   * Creates CloudFormation outputs for important resources
   */
  private createOutputs(): void {
    // VPC outputs
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for the EFS deployment',
    });

    // EFS outputs
    new cdk.CfnOutput(this, 'FileSystemId', {
      value: this.fileSystem.fileSystemId,
      description: 'EFS File System ID',
    });

    new cdk.CfnOutput(this, 'FileSystemArn', {
      value: this.fileSystem.fileSystemArn,
      description: 'EFS File System ARN',
    });

    // Access point outputs
    Object.entries(this.accessPoints).forEach(([name, accessPoint]) => {
      new cdk.CfnOutput(this, `AccessPoint${name.charAt(0).toUpperCase() + name.slice(1)}Id`, {
        value: accessPoint.accessPointId,
        description: `Access Point ID for ${name}`,
      });

      new cdk.CfnOutput(this, `AccessPoint${name.charAt(0).toUpperCase() + name.slice(1)}Arn`, {
        value: accessPoint.accessPointArn,
        description: `Access Point ARN for ${name}`,
      });
    });

    // Security group outputs
    new cdk.CfnOutput(this, 'EfsSecurityGroupId', {
      value: this.efsSecurityGroup.securityGroupId,
      description: 'Security Group ID for EFS access',
    });

    // IAM role outputs
    new cdk.CfnOutput(this, 'Ec2RoleArn', {
      value: this.ec2Role.roleArn,
      description: 'IAM Role ARN for EC2 EFS access',
    });

    // Demo instance outputs (if created)
    if (this.demoInstance) {
      new cdk.CfnOutput(this, 'DemoInstanceId', {
        value: this.demoInstance.instanceId,
        description: 'Demo EC2 Instance ID',
      });

      new cdk.CfnOutput(this, 'DemoInstancePublicIp', {
        value: this.demoInstance.instancePublicIp,
        description: 'Demo EC2 Instance Public IP',
      });
    }

    // Mounting command examples
    new cdk.CfnOutput(this, 'StandardNfsMount', {
      value: `sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,intr,timeo=600,retrans=2 ${this.fileSystem.fileSystemId}.efs.${this.region}.amazonaws.com:/ /mnt/efs`,
      description: 'Command for standard NFS mount',
    });

    new cdk.CfnOutput(this, 'EfsUtilsMount', {
      value: `sudo mount -t efs -o tls ${this.fileSystem.fileSystemId}:/ /mnt/efs`,
      description: 'Command for EFS utils mount with TLS',
    });

    new cdk.CfnOutput(this, 'AccessPointMount', {
      value: `sudo mount -t efs -o tls,accesspoint=${this.accessPoints.appData.accessPointId} ${this.fileSystem.fileSystemId}:/ /mnt/efs-app`,
      description: 'Command for mounting with access point',
    });
  }
}

// CDK App
const app = new cdk.App();

// Deploy the stack
new EfsMountingStrategiesStack(app, 'EfsMountingStrategiesStack', {
  description: 'EFS Mounting Strategies implementation using AWS CDK',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Add metadata to the app
app.node.setContext('@aws-cdk/core:enableStackNameDuplicates', false);
app.node.setContext('@aws-cdk/core:stackRelativeExports', true);