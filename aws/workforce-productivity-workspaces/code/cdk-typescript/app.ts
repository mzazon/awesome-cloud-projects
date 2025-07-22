#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ds from 'aws-cdk-lib/aws-directoryservice';
import * as workspaces from 'aws-cdk-lib/aws-workspaces';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as iam from 'aws-cdk-lib/aws-iam';

/**
 * Properties for the WorkSpaces stack
 */
interface WorkSpacesStackProps extends cdk.StackProps {
  /**
   * The VPC CIDR block for the WorkSpaces network
   * @default '10.0.0.0/16'
   */
  vpcCidr?: string;
  
  /**
   * The name of the Simple AD directory
   * @default 'workspaces.local'
   */
  directoryName?: string;
  
  /**
   * The password for the Simple AD directory administrator
   * Must be at least 8 characters with uppercase, lowercase, number, and special character
   */
  directoryPassword: string;
  
  /**
   * Whether to enable WorkDocs integration
   * @default true
   */
  enableWorkDocs?: boolean;
  
  /**
   * Whether to enable self-service capabilities for users
   * @default true
   */
  enableSelfService?: boolean;
  
  /**
   * The WorkSpace bundle type to use
   * @default 'wsb-bh8rsxt14' (Standard with Windows 10)
   */
  workSpaceBundleId?: string;
  
  /**
   * List of IP ranges allowed to access WorkSpaces
   * Use ['0.0.0.0/0'] for unrestricted access (not recommended for production)
   * @default ['0.0.0.0/0']
   */
  allowedIpRanges?: string[];
}

/**
 * AWS CDK Stack for WorkSpaces workforce productivity solution
 * 
 * This stack creates:
 * - VPC with public and private subnets
 * - NAT Gateway for internet access
 * - Simple AD directory for user authentication
 * - WorkSpaces configuration with security controls
 * - CloudWatch monitoring and logging
 */
export class WorkSpacesStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly directory: ds.CfnSimpleAD;
  public readonly ipAccessControlGroup: workspaces.CfnIpGroup;
  
  constructor(scope: Construct, id: string, props: WorkSpacesStackProps) {
    super(scope, id, props);
    
    // Generate unique suffix for resource naming
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().slice(-6);
    
    // Create VPC with public and private subnets across 2 AZs
    this.vpc = new ec2.Vpc(this, 'WorkSpacesVpc', {
      cidr: props.vpcCidr || '10.0.0.0/16',
      maxAzs: 2,
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
      natGateways: 1, // Single NAT Gateway for cost optimization
    });
    
    // Add tags to VPC
    cdk.Tags.of(this.vpc).add('Name', `workspaces-vpc-${uniqueSuffix}`);
    cdk.Tags.of(this.vpc).add('Purpose', 'WorkSpaces Infrastructure');
    
    // Get private subnets for directory service
    const privateSubnets = this.vpc.privateSubnets;
    if (privateSubnets.length < 2) {
      throw new Error('At least 2 private subnets are required for Simple AD');
    }
    
    // Create Simple AD directory
    this.directory = new ds.CfnSimpleAD(this, 'WorkSpacesDirectory', {
      name: props.directoryName || `workspaces-${uniqueSuffix}.local`,
      password: props.directoryPassword,
      size: 'Small',
      description: 'Simple AD directory for WorkSpaces authentication',
      vpcSettings: {
        vpcId: this.vpc.vpcId,
        subnetIds: [
          privateSubnets[0].subnetId,
          privateSubnets[1].subnetId,
        ],
      },
    });
    
    // Add tags to directory
    cdk.Tags.of(this.directory).add('Name', `workspaces-directory-${uniqueSuffix}`);
    cdk.Tags.of(this.directory).add('Purpose', 'WorkSpaces Authentication');
    
    // Create WorkSpaces directory configuration
    const workSpacesDirectory = new workspaces.CfnWorkspaceDirectory(this, 'WorkSpacesDirectoryConfig', {
      directoryId: this.directory.ref,
      subnetIds: [
        privateSubnets[0].subnetId,
        privateSubnets[1].subnetId,
      ],
      enableWorkDocs: props.enableWorkDocs ?? true,
      enableSelfService: props.enableSelfService ?? true,
      workspaceCreationProperties: {
        enableWorkDocs: props.enableWorkDocs ?? true,
        enableInternetAccess: true,
        defaultOu: 'CN=Computers,DC=' + (props.directoryName || `workspaces-${uniqueSuffix}`).split('.')[0] + ',DC=local',
        customSecurityGroupId: this.createWorkSpacesSecurityGroup().securityGroupId,
        userEnabledAsLocalAdministrator: false,
      },
    });
    
    // Ensure directory is created before WorkSpaces configuration
    workSpacesDirectory.addDependency(this.directory);
    
    // Create IP Access Control Group
    this.ipAccessControlGroup = new workspaces.CfnIpGroup(this, 'WorkSpacesIpGroup', {
      groupName: `workspaces-ip-group-${uniqueSuffix}`,
      groupDesc: 'IP access control for WorkSpaces',
      userRules: (props.allowedIpRanges || ['0.0.0.0/0']).map((ipRange, index) => ({
        ipRule: ipRange,
        ruleDesc: `Access rule ${index + 1}`,
      })),
    });
    
    // Associate IP group with directory
    new workspaces.CfnIpGroupAssociation(this, 'IpGroupAssociation', {
      directoryId: this.directory.ref,
      groupId: this.ipAccessControlGroup.ref,
    });
    
    // Create CloudWatch Log Group for WorkSpaces
    const logGroup = new logs.LogGroup(this, 'WorkSpacesLogGroup', {
      logGroupName: `/aws/workspaces/${this.directory.ref}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
    
    // Create CloudWatch alarm for connection failures
    new cloudwatch.Alarm(this, 'ConnectionFailuresAlarm', {
      alarmName: `WorkSpaces-Connection-Failures-${uniqueSuffix}`,
      alarmDescription: 'Monitor WorkSpace connection failures',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/WorkSpaces',
        metricName: 'ConnectionAttempt',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 5,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });
    
    // Create sample WorkSpace (commented out by default)
    /*
    new workspaces.CfnWorkspace(this, 'SampleWorkSpace', {
      directoryId: this.directory.ref,
      userName: 'testuser',
      bundleId: props.workSpaceBundleId || 'wsb-bh8rsxt14', // Standard Windows 10
      userVolumeEncryptionEnabled: true,
      rootVolumeEncryptionEnabled: true,
      workspaceProperties: {
        runningMode: 'AUTO_STOP',
        runningModeAutoStopTimeoutInMinutes: 60,
        rootVolumeSizeGib: 80,
        userVolumeSizeGib: 50,
        computeTypeName: 'STANDARD',
      },
    });
    */
    
    // Output important values
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for WorkSpaces infrastructure',
      exportName: `${this.stackName}-VpcId`,
    });
    
    new cdk.CfnOutput(this, 'DirectoryId', {
      value: this.directory.ref,
      description: 'Simple AD Directory ID for WorkSpaces',
      exportName: `${this.stackName}-DirectoryId`,
    });
    
    new cdk.CfnOutput(this, 'DirectoryName', {
      value: this.directory.name,
      description: 'Simple AD Directory Name',
      exportName: `${this.stackName}-DirectoryName`,
    });
    
    new cdk.CfnOutput(this, 'PrivateSubnetIds', {
      value: privateSubnets.map(subnet => subnet.subnetId).join(','),
      description: 'Private subnet IDs for WorkSpaces',
      exportName: `${this.stackName}-PrivateSubnetIds`,
    });
    
    new cdk.CfnOutput(this, 'IpAccessControlGroupId', {
      value: this.ipAccessControlGroup.ref,
      description: 'IP Access Control Group ID',
      exportName: `${this.stackName}-IpGroupId`,
    });
    
    new cdk.CfnOutput(this, 'LogGroupName', {
      value: logGroup.logGroupName,
      description: 'CloudWatch Log Group for WorkSpaces',
      exportName: `${this.stackName}-LogGroupName`,
    });
  }
  
  /**
   * Creates a security group for WorkSpaces with appropriate rules
   */
  private createWorkSpacesSecurityGroup(): ec2.SecurityGroup {
    const securityGroup = new ec2.SecurityGroup(this, 'WorkSpacesSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for WorkSpaces',
      allowAllOutbound: true, // WorkSpaces need internet access
    });
    
    // Allow WorkSpaces service communication
    securityGroup.addIngressRule(
      ec2.Peer.ipv4(this.vpc.vpcCidrBlock),
      ec2.Port.tcp(443),
      'HTTPS for WorkSpaces service communication'
    );
    
    securityGroup.addIngressRule(
      ec2.Peer.ipv4(this.vpc.vpcCidrBlock),
      ec2.Port.tcp(4172),
      'WorkSpaces streaming protocol'
    );
    
    // Add tags
    cdk.Tags.of(securityGroup).add('Name', 'WorkSpaces Security Group');
    cdk.Tags.of(securityGroup).add('Purpose', 'WorkSpaces Network Security');
    
    return securityGroup;
  }
}

/**
 * CDK App for WorkSpaces infrastructure
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const directoryPassword = app.node.tryGetContext('directoryPassword') || 
                         process.env.DIRECTORY_PASSWORD || 
                         'TempPassword123!';

const allowedIpRanges = app.node.tryGetContext('allowedIpRanges') || 
                       (process.env.ALLOWED_IP_RANGES ? process.env.ALLOWED_IP_RANGES.split(',') : ['0.0.0.0/0']);

new WorkSpacesStack(app, 'WorkSpacesStack', {
  description: 'AWS WorkSpaces infrastructure for workforce productivity',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  directoryPassword: directoryPassword,
  allowedIpRanges: allowedIpRanges,
  
  // Optional: Customize these values
  vpcCidr: app.node.tryGetContext('vpcCidr') || '10.0.0.0/16',
  directoryName: app.node.tryGetContext('directoryName'),
  enableWorkDocs: app.node.tryGetContext('enableWorkDocs') ?? true,
  enableSelfService: app.node.tryGetContext('enableSelfService') ?? true,
  workSpaceBundleId: app.node.tryGetContext('workSpaceBundleId'),
  
  // Add common tags
  tags: {
    Project: 'WorkSpaces-Workforce-Productivity',
    Environment: app.node.tryGetContext('environment') || 'development',
    ManagedBy: 'AWS-CDK',
  },
});

app.synth();