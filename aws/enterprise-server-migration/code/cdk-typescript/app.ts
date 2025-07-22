#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as mgn from 'aws-cdk-lib/aws-mgn';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Properties for the LargeScaleMigrationStack
 */
export interface LargeScaleMigrationStackProps extends cdk.StackProps {
  /**
   * The environment name for resource tagging
   * @default 'migration'
   */
  readonly environmentName?: string;
  
  /**
   * The replication server instance type
   * @default 't3.small'
   */
  readonly replicationServerInstanceType?: string;
  
  /**
   * The default staging disk type for replication
   * @default 'GP3'
   */
  readonly defaultStagingDiskType?: string;
  
  /**
   * Enable encryption for EBS volumes
   * @default true
   */
  readonly enableEbsEncryption?: boolean;
  
  /**
   * Bandwidth throttling for replication (0 = unlimited)
   * @default 0
   */
  readonly bandwidthThrottling?: number;
  
  /**
   * Use dedicated replication servers
   * @default false
   */
  readonly useDedicatedReplicationServer?: boolean;
  
  /**
   * Enable CloudWatch logging for MGN operations
   * @default true
   */
  readonly enableCloudWatchLogging?: boolean;
}

/**
 * AWS CDK Stack for Large-Scale Server Migration using AWS Application Migration Service (MGN)
 * 
 * This stack sets up the necessary infrastructure for migrating large numbers of servers
 * from on-premises environments to AWS using MGN. It includes IAM roles, replication
 * configuration templates, and optional CloudWatch logging.
 * 
 * Key Features:
 * - Automated MGN service initialization
 * - Replication configuration templates with best practices
 * - IAM roles with least privilege principles
 * - CloudWatch logging for migration monitoring
 * - Wave-based migration support
 * - Customizable instance types and storage options
 */
export class LargeScaleMigrationStack extends cdk.Stack {
  /**
   * The MGN service role for replication operations
   */
  public readonly mgnServiceRole: iam.Role;
  
  /**
   * The replication configuration template
   */
  public readonly replicationConfigTemplate: mgn.CfnReplicationConfigurationTemplate;
  
  /**
   * CloudWatch log group for MGN operations (if enabled)
   */
  public readonly mgnLogGroup?: logs.LogGroup;
  
  /**
   * VPC for migration infrastructure (if created)
   */
  public readonly migrationVpc?: ec2.Vpc;

  constructor(scope: Construct, id: string, props: LargeScaleMigrationStackProps = {}) {
    super(scope, id, props);

    // Default values
    const environmentName = props.environmentName ?? 'migration';
    const replicationServerInstanceType = props.replicationServerInstanceType ?? 't3.small';
    const defaultStagingDiskType = props.defaultStagingDiskType ?? 'GP3';
    const enableEbsEncryption = props.enableEbsEncryption ?? true;
    const bandwidthThrottling = props.bandwidthThrottling ?? 0;
    const useDedicatedReplicationServer = props.useDedicatedReplicationServer ?? false;
    const enableCloudWatchLogging = props.enableCloudWatchLogging ?? true;

    // Create MGN service role with minimal required permissions
    this.mgnServiceRole = new iam.Role(this, 'MGNServiceRole', {
      roleName: `MGNServiceRole-${cdk.Names.uniqueId(this).substring(0, 8)}`,
      assumedBy: new iam.ServicePrincipal('mgn.amazonaws.com'),
      description: 'Service role for AWS Application Migration Service operations',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSApplicationMigrationServiceRolePolicy')
      ],
      inlinePolicies: {
        'MGNAdditionalPermissions': new iam.PolicyDocument({
          statements: [
            // Additional permissions for enhanced monitoring and logging
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'cloudwatch:PutMetricData'
              ],
              resources: ['*']
            }),
            // Permissions for EBS encryption
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kms:Decrypt',
                'kms:DescribeKey',
                'kms:GenerateDataKey'
              ],
              resources: ['*'],
              conditions: {
                StringEquals: {
                  'kms:ViaService': `ec2.${this.region}.amazonaws.com`
                }
              }
            })
          ]
        })
      }
    });

    // Create CloudWatch log group for MGN operations if enabled
    if (enableCloudWatchLogging) {
      this.mgnLogGroup = new logs.LogGroup(this, 'MGNLogGroup', {
        logGroupName: `/aws/mgn/${environmentName}`,
        retention: logs.RetentionDays.ONE_MONTH,
        removalPolicy: cdk.RemovalPolicy.DESTROY
      });

      // Add log group ARN to SSM Parameter for easy reference
      new ssm.StringParameter(this, 'MGNLogGroupParameter', {
        parameterName: `/mgn/${environmentName}/log-group-arn`,
        stringValue: this.mgnLogGroup.logGroupArn,
        description: 'CloudWatch Log Group ARN for MGN operations'
      });
    }

    // Create VPC for migration infrastructure if not using existing VPC
    this.migrationVpc = new ec2.Vpc(this, 'MigrationVPC', {
      maxAzs: 2,
      cidr: '10.0.0.0/16',
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'MGN-Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS
        },
        {
          cidrMask: 24,
          name: 'MGN-Public',
          subnetType: ec2.SubnetType.PUBLIC
        }
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true
    });

    // Create security group for replication servers
    const replicationSecurityGroup = new ec2.SecurityGroup(this, 'ReplicationSecurityGroup', {
      vpc: this.migrationVpc,
      description: 'Security group for MGN replication servers',
      allowAllOutbound: true
    });

    // Allow inbound traffic from source servers for replication
    replicationSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'HTTPS traffic from source servers'
    );

    replicationSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcpRange(1500, 1600),
      'Replication traffic from source servers'
    );

    // Create replication configuration template
    this.replicationConfigTemplate = new mgn.CfnReplicationConfigurationTemplate(
      this,
      'ReplicationConfigTemplate',
      {
        associateDefaultSecurityGroup: true,
        bandwidthThrottling: bandwidthThrottling,
        createPublicIp: false,
        dataPlaneRouting: 'PRIVATE_IP',
        defaultLargeStagingDiskType: defaultStagingDiskType,
        ebsEncryption: enableEbsEncryption ? 'DEFAULT' : 'NONE',
        replicationServerInstanceType: replicationServerInstanceType,
        replicationServersSecurityGroupsIds: [replicationSecurityGroup.securityGroupId],
        stagingAreaSubnetId: this.migrationVpc.privateSubnets[0].subnetId,
        stagingAreaTags: {
          Environment: environmentName,
          Purpose: 'MGN-Staging',
          ManagedBy: 'CDK'
        },
        useDedicatedReplicationServer: useDedicatedReplicationServer,
        tags: [
          {
            key: 'Environment',
            value: environmentName
          },
          {
            key: 'Purpose',
            value: 'MGN-Replication'
          },
          {
            key: 'ManagedBy',
            value: 'CDK'
          }
        ]
      }
    );

    // Create IAM role for MGN agent installation
    const mgnAgentRole = new iam.Role(this, 'MGNAgentRole', {
      roleName: `MGNAgentRole-${cdk.Names.uniqueId(this).substring(0, 8)}`,
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for MGN agent installation on source servers',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore')
      ],
      inlinePolicies: {
        'MGNAgentPolicy': new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'mgn:SendAgentMetricsForSourceServer',
                'mgn:SendAgentLogsForSourceServer',
                'mgn:SendChannelCommandResultForSourceServer',
                'mgn:SendClientMetricsForSourceServer',
                'mgn:SendVolumeStatsForSourceServer',
                'mgn:GetChannelCommandsForSourceServer',
                'mgn:GetAgentInstallationAssetsForSourceServer',
                'mgn:GetAgentCommandForSourceServer',
                'mgn:GetAgentConfirmedResumeInfoForSourceServer',
                'mgn:GetAgentRuntimeConfigurationForSourceServer',
                'mgn:GetAgentReplicationInfoForSourceServer',
                'mgn:GetAgentSourceServerForSourceServer',
                'mgn:TagResource',
                'mgn:UntagResource',
                'mgn:ListTagsForResource'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // Create instance profile for MGN agent
    new iam.CfnInstanceProfile(this, 'MGNAgentInstanceProfile', {
      instanceProfileName: `MGNAgentInstanceProfile-${cdk.Names.uniqueId(this).substring(0, 8)}`,
      roles: [mgnAgentRole.roleName]
    });

    // Store configuration values in SSM Parameters for easy access
    new ssm.StringParameter(this, 'ReplicationTemplateIdParameter', {
      parameterName: `/mgn/${environmentName}/replication-template-id`,
      stringValue: this.replicationConfigTemplate.attrReplicationConfigurationTemplateId,
      description: 'MGN Replication Configuration Template ID'
    });

    new ssm.StringParameter(this, 'MGNServiceRoleArnParameter', {
      parameterName: `/mgn/${environmentName}/service-role-arn`,
      stringValue: this.mgnServiceRole.roleArn,
      description: 'MGN Service Role ARN'
    });

    new ssm.StringParameter(this, 'MigrationVpcIdParameter', {
      parameterName: `/mgn/${environmentName}/vpc-id`,
      stringValue: this.migrationVpc.vpcId,
      description: 'Migration VPC ID'
    });

    new ssm.StringParameter(this, 'ReplicationSecurityGroupIdParameter', {
      parameterName: `/mgn/${environmentName}/replication-security-group-id`,
      stringValue: replicationSecurityGroup.securityGroupId,
      description: 'Replication Security Group ID'
    });

    // Output important values
    new cdk.CfnOutput(this, 'MGNServiceRoleArn', {
      value: this.mgnServiceRole.roleArn,
      description: 'ARN of the MGN Service Role',
      exportName: `${this.stackName}-MGNServiceRoleArn`
    });

    new cdk.CfnOutput(this, 'ReplicationConfigTemplateId', {
      value: this.replicationConfigTemplate.attrReplicationConfigurationTemplateId,
      description: 'ID of the MGN Replication Configuration Template',
      exportName: `${this.stackName}-ReplicationConfigTemplateId`
    });

    new cdk.CfnOutput(this, 'MigrationVpcId', {
      value: this.migrationVpc.vpcId,
      description: 'ID of the Migration VPC',
      exportName: `${this.stackName}-MigrationVpcId`
    });

    new cdk.CfnOutput(this, 'ReplicationSecurityGroupId', {
      value: replicationSecurityGroup.securityGroupId,
      description: 'ID of the Replication Security Group',
      exportName: `${this.stackName}-ReplicationSecurityGroupId`
    });

    if (this.mgnLogGroup) {
      new cdk.CfnOutput(this, 'MGNLogGroupArn', {
        value: this.mgnLogGroup.logGroupArn,
        description: 'ARN of the MGN CloudWatch Log Group',
        exportName: `${this.stackName}-MGNLogGroupArn`
      });
    }

    // Add tags to all resources in the stack
    cdk.Tags.of(this).add('Environment', environmentName);
    cdk.Tags.of(this).add('Purpose', 'MGN-LargeScale-Migration');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }
}

/**
 * CDK Application for Large-Scale Server Migration
 */
const app = new cdk.App();

// Get context values from CDK context or environment variables
const environmentName = app.node.tryGetContext('environmentName') || process.env.ENVIRONMENT_NAME || 'migration';
const replicationServerInstanceType = app.node.tryGetContext('replicationServerInstanceType') || process.env.REPLICATION_SERVER_INSTANCE_TYPE || 't3.small';
const enableEbsEncryption = app.node.tryGetContext('enableEbsEncryption') === 'false' ? false : true;
const useDedicatedReplicationServer = app.node.tryGetContext('useDedicatedReplicationServer') === 'true' ? true : false;
const enableCloudWatchLogging = app.node.tryGetContext('enableCloudWatchLogging') === 'false' ? false : true;

// Create the stack
new LargeScaleMigrationStack(app, 'LargeScaleMigrationStack', {
  description: 'AWS CDK Stack for Large-Scale Server Migration using Application Migration Service (MGN)',
  environmentName: environmentName,
  replicationServerInstanceType: replicationServerInstanceType,
  enableEbsEncryption: enableEbsEncryption,
  useDedicatedReplicationServer: useDedicatedReplicationServer,
  enableCloudWatchLogging: enableCloudWatchLogging,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  }
});

// Synthesize the app
app.synth();