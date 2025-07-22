#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as cr from 'aws-cdk-lib/custom-resources';

/**
 * Stack for automated application migration workflows using AWS Application Migration Service
 * and Migration Hub Orchestrator. This stack creates the necessary infrastructure for
 * lift-and-shift migrations including VPC, security groups, IAM roles, and monitoring.
 */
class MigrationWorkflowStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = new secretsmanager.Secret(this, 'UniqueId', {
      description: 'Unique identifier for migration resources',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ suffix: '' }),
        generateStringKey: 'suffix',
        excludePunctuation: true,
        excludeUppercase: true,
        passwordLength: 8,
        requireEachIncludedType: true,
      },
    });

    // Create VPC for migration target environment
    const migrationVpc = new ec2.Vpc(this, 'MigrationVPC', {
      vpcName: `migration-vpc-${cdk.Token.asString(uniqueSuffix.secretValueFromJson('suffix'))}`,
      ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
      enableDnsHostnames: true,
      enableDnsSupport: true,
      maxAzs: 2,
      subnetConfiguration: [
        {
          name: 'Migration-Public',
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 24,
        },
        {
          name: 'Migration-Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
          cidrMask: 24,
        },
      ],
    });

    // Create security group for migrated instances
    const migrationSecurityGroup = new ec2.SecurityGroup(this, 'MigrationSecurityGroup', {
      vpc: migrationVpc,
      securityGroupName: `migration-sg-${cdk.Token.asString(uniqueSuffix.secretValueFromJson('suffix'))}`,
      description: 'Security group for migrated instances',
      allowAllOutbound: true,
    });

    // Configure security group rules based on application requirements
    migrationSecurityGroup.addIngressRule(
      ec2.Peer.ipv4('10.0.0.0/16'),
      ec2.Port.tcp(22),
      'Allow SSH access from within VPC'
    );

    migrationSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP access from anywhere'
    );

    migrationSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS access from anywhere'
    );

    // Create IAM role for MGN service operations
    const mgnServiceRole = new iam.Role(this, 'MGNServiceRole', {
      roleName: `MGNServiceRole-${cdk.Token.asString(uniqueSuffix.secretValueFromJson('suffix'))}`,
      assumedBy: new iam.ServicePrincipal('mgn.amazonaws.com'),
      description: 'Service role for AWS Application Migration Service operations',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSApplicationMigrationServiceRolePolicy'),
      ],
    });

    // Create IAM role for Migration Hub Orchestrator
    const orchestratorRole = new iam.Role(this, 'MigrationOrchestratorRole', {
      roleName: `MigrationOrchestratorRole-${cdk.Token.asString(uniqueSuffix.secretValueFromJson('suffix'))}`,
      assumedBy: new iam.ServicePrincipal('migrationhub-orchestrator.amazonaws.com'),
      description: 'Service role for Migration Hub Orchestrator workflow execution',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSMigrationHubOrchestratorServiceRolePolicy'),
      ],
    });

    // Create IAM role for Systems Manager automation
    const ssmAutomationRole = new iam.Role(this, 'SSMAutomationRole', {
      roleName: `SSMAutomationRole-${cdk.Token.asString(uniqueSuffix.secretValueFromJson('suffix'))}`,
      assumedBy: new iam.ServicePrincipal('ssm.amazonaws.com'),
      description: 'Service role for Systems Manager automation execution',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMAutomationRole'),
      ],
    });

    // Add additional permissions for post-migration automation
    ssmAutomationRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'ec2:DescribeInstances',
        'ec2:DescribeInstanceStatus',
        'ssm:SendCommand',
        'ssm:GetCommandInvocation',
        'ssm:DescribeInstanceInformation',
        'cloudwatch:PutMetricData',
      ],
      resources: ['*'],
    }));

    // Initialize MGN service using custom resource
    const mgnInitialization = new cr.AwsCustomResource(this, 'MGNInitialization', {
      onCreate: {
        service: 'MGN',
        action: 'initializeService',
        parameters: {},
        physicalResourceId: cr.PhysicalResourceId.of('mgn-initialization'),
      },
      policy: cr.AwsCustomResourcePolicy.fromSdkCalls({
        resources: cr.AwsCustomResourcePolicy.ANY_RESOURCE,
      }),
    });

    // Create Systems Manager document for post-migration automation
    const postMigrationAutomation = new ssm.CfnDocument(this, 'PostMigrationAutomation', {
      documentType: 'Automation',
      documentFormat: 'JSON',
      name: `PostMigrationAutomation-${cdk.Token.asString(uniqueSuffix.secretValueFromJson('suffix'))}`,
      content: {
        schemaVersion: '0.3',
        description: 'Post-migration automation tasks for migrated instances',
        assumeRole: ssmAutomationRole.roleArn,
        parameters: {
          InstanceId: {
            type: 'String',
            description: 'EC2 Instance ID for post-migration tasks',
          },
          AutomationAssumeRole: {
            type: 'String',
            description: 'IAM role for automation execution',
            default: ssmAutomationRole.roleArn,
          },
        },
        mainSteps: [
          {
            name: 'WaitForInstanceReady',
            action: 'aws:waitForAwsResourceProperty',
            inputs: {
              Service: 'ec2',
              Api: 'DescribeInstanceStatus',
              InstanceIds: ['{{ InstanceId }}'],
              PropertySelector: '$.InstanceStatuses[0].InstanceStatus.Status',
              DesiredValues: ['ok'],
            },
            onFailure: 'Abort',
          },
          {
            name: 'ConfigureCloudWatchAgent',
            action: 'aws:runCommand',
            inputs: {
              DocumentName: 'AWS-ConfigureAWSPackage',
              InstanceIds: ['{{ InstanceId }}'],
              Parameters: {
                action: 'Install',
                name: 'AmazonCloudWatchAgent',
              },
            },
            onFailure: 'Continue',
          },
          {
            name: 'ValidateServices',
            action: 'aws:runCommand',
            inputs: {
              DocumentName: 'AWS-RunShellScript',
              InstanceIds: ['{{ InstanceId }}'],
              Parameters: {
                commands: [
                  '#!/bin/bash',
                  'systemctl status sshd',
                  'curl -f http://localhost/health || echo "Application health check failed"',
                  'echo "Post-migration validation completed"',
                ],
              },
            },
            onFailure: 'Continue',
          },
        ],
      },
    });

    // Create CloudWatch dashboard for migration monitoring
    const migrationDashboard = new cloudwatch.Dashboard(this, 'MigrationDashboard', {
      dashboardName: `Migration-Dashboard-${cdk.Token.asString(uniqueSuffix.secretValueFromJson('suffix'))}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'MGN Migration Status',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/MGN',
                metricName: 'TotalSourceServers',
                statistic: 'Average',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/MGN',
                metricName: 'HealthySourceServers',
                statistic: 'Average',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/MGN',
                metricName: 'ReplicationProgress',
                statistic: 'Average',
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.LogQueryWidget({
            title: 'Migration Errors',
            logGroups: [
              '/aws/migrationhub-orchestrator',
              '/aws/ssm/automation',
            ],
            queryLines: [
              'fields @timestamp, @message',
              'filter @message like /ERROR/',
              'sort @timestamp desc',
              'limit 20',
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // Create CloudWatch alarms for migration monitoring
    const replicationHealthAlarm = new cloudwatch.Alarm(this, 'ReplicationHealthAlarm', {
      alarmName: `MGN-Replication-Health-${cdk.Token.asString(uniqueSuffix.secretValueFromJson('suffix'))}`,
      alarmDescription: 'Alert when MGN replication encounters issues',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/MGN',
        metricName: 'HealthySourceServers',
        statistic: 'Average',
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
    });

    // Create custom resource for MGN replication configuration template update
    const mgnConfigUpdate = new cr.AwsCustomResource(this, 'MGNConfigUpdate', {
      onCreate: {
        service: 'MGN',
        action: 'updateReplicationConfigurationTemplate',
        parameters: {
          replicationConfigurationTemplateID: mgnInitialization.getResponseField('replicationConfigurationTemplateID'),
          replicationServersSecurityGroupsIDs: [migrationSecurityGroup.securityGroupId],
          stagingAreaSubnetId: migrationVpc.privateSubnets[0].subnetId,
          stagingAreaTags: {
            Name: 'MGN-Staging-Area',
            Environment: 'Migration',
          },
        },
        physicalResourceId: cr.PhysicalResourceId.of('mgn-config-update'),
      },
      policy: cr.AwsCustomResourcePolicy.fromSdkCalls({
        resources: cr.AwsCustomResourcePolicy.ANY_RESOURCE,
      }),
    });

    // Ensure MGN is initialized before updating configuration
    mgnConfigUpdate.node.addDependency(mgnInitialization);

    // Create outputs for important resource identifiers
    new cdk.CfnOutput(this, 'MigrationVpcId', {
      value: migrationVpc.vpcId,
      description: 'VPC ID for migration target environment',
      exportName: `${this.stackName}-MigrationVpcId`,
    });

    new cdk.CfnOutput(this, 'MigrationSecurityGroupId', {
      value: migrationSecurityGroup.securityGroupId,
      description: 'Security Group ID for migrated instances',
      exportName: `${this.stackName}-MigrationSecurityGroupId`,
    });

    new cdk.CfnOutput(this, 'PrivateSubnetId', {
      value: migrationVpc.privateSubnets[0].subnetId,
      description: 'Private subnet ID for migration staging area',
      exportName: `${this.stackName}-PrivateSubnetId`,
    });

    new cdk.CfnOutput(this, 'PublicSubnetId', {
      value: migrationVpc.publicSubnets[0].subnetId,
      description: 'Public subnet ID for migration targets',
      exportName: `${this.stackName}-PublicSubnetId`,
    });

    new cdk.CfnOutput(this, 'MGNServiceRoleArn', {
      value: mgnServiceRole.roleArn,
      description: 'IAM role ARN for MGN service operations',
      exportName: `${this.stackName}-MGNServiceRoleArn`,
    });

    new cdk.CfnOutput(this, 'OrchestratorRoleArn', {
      value: orchestratorRole.roleArn,
      description: 'IAM role ARN for Migration Hub Orchestrator',
      exportName: `${this.stackName}-OrchestratorRoleArn`,
    });

    new cdk.CfnOutput(this, 'SSMAutomationRoleArn', {
      value: ssmAutomationRole.roleArn,
      description: 'IAM role ARN for Systems Manager automation',
      exportName: `${this.stackName}-SSMAutomationRoleArn`,
    });

    new cdk.CfnOutput(this, 'PostMigrationAutomationDocument', {
      value: postMigrationAutomation.ref,
      description: 'Systems Manager document for post-migration automation',
      exportName: `${this.stackName}-PostMigrationAutomationDocument`,
    });

    new cdk.CfnOutput(this, 'MigrationDashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${migrationDashboard.dashboardName}`,
      description: 'URL to CloudWatch dashboard for migration monitoring',
    });

    // Add tags to all resources for better organization and cost tracking
    cdk.Tags.of(this).add('Project', 'Migration-Workflow');
    cdk.Tags.of(this).add('Environment', 'Migration');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    cdk.Tags.of(this).add('Purpose', 'Application-Migration');
  }
}

/**
 * CDK App for automated application migration workflows
 */
const app = new cdk.App();

// Create the migration workflow stack
new MigrationWorkflowStack(app, 'MigrationWorkflowStack', {
  description: 'Infrastructure for automated application migration workflows using AWS Application Migration Service and Migration Hub Orchestrator',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  terminationProtection: true, // Protect against accidental deletion
});

// Synthesize the CloudFormation template
app.synth();