#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as events from 'aws-cdk-lib/aws-events';
import * as eventsTargets from 'aws-cdk-lib/aws-events-targets';
import * as budgets from 'aws-cdk-lib/aws-budgets';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as mgn from 'aws-cdk-lib/aws-mgn';
import * as dx from 'aws-cdk-lib/aws-directconnect';
import * as ce from 'aws-cdk-lib/aws-ce';

/**
 * Properties for the VMware Cloud Migration Stack
 */
export interface VmwareCloudMigrationStackProps extends cdk.StackProps {
  /**
   * The name of the SDDC to be created
   */
  readonly sddcName?: string;
  
  /**
   * The management subnet CIDR for the SDDC
   */
  readonly managementSubnet?: string;
  
  /**
   * Email address for notifications
   */
  readonly notificationEmail?: string;
  
  /**
   * Monthly budget limit for VMware Cloud on AWS
   */
  readonly monthlyBudgetLimit?: number;
  
  /**
   * Whether to create Direct Connect resources
   */
  readonly enableDirectConnect?: boolean;
  
  /**
   * Existing Direct Connect connection ID (optional)
   */
  readonly directConnectConnectionId?: string;
}

/**
 * VMware Cloud Migration Stack
 * 
 * This stack creates the necessary AWS infrastructure to support VMware Cloud on AWS
 * migration, including networking, monitoring, backup, and migration services.
 */
export class VmwareCloudMigrationStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly backupBucket: s3.Bucket;
  public readonly migrationTable: dynamodb.Table;
  public readonly snsTopicArn: string;

  constructor(scope: Construct, id: string, props: VmwareCloudMigrationStackProps = {}) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Names.uniqueId(this).slice(-6).toLowerCase();
    
    // Default values
    const sddcName = props.sddcName ?? `vmware-migration-${uniqueSuffix}`;
    const managementSubnet = props.managementSubnet ?? '10.0.0.0/16';
    const notificationEmail = props.notificationEmail ?? 'admin@company.com';
    const monthlyBudgetLimit = props.monthlyBudgetLimit ?? 15000;

    // Create VPC for VMware Cloud on AWS connectivity
    this.vpc = new ec2.Vpc(this, 'VmwareMigrationVpc', {
      cidr: '10.1.0.0/16',
      enableDnsHostnames: true,
      enableDnsSupport: true,
      maxAzs: 2,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'VMware-Migration-Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'VMware-Migration-Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
      ],
    });

    // Tag the VPC for identification
    cdk.Tags.of(this.vpc).add('Name', 'vmware-migration-vpc');
    cdk.Tags.of(this.vpc).add('Purpose', 'VMware Cloud on AWS Migration');

    // Create security group for HCX traffic
    const hcxSecurityGroup = new ec2.SecurityGroup(this, 'HcxSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for VMware HCX traffic',
      allowAllOutbound: true,
    });

    // HCX required ports
    hcxSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'HTTPS traffic for HCX management'
    );
    hcxSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(9443),
      'HCX Cloud Manager'
    );
    hcxSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(8043),
      'HCX authentication service'
    );
    hcxSecurityGroup.addIngressRule(
      ec2.Peer.ipv4('192.168.0.0/16'),
      ec2.Port.tcp(902),
      'HCX mobility traffic'
    );

    // Create IAM role for VMware Cloud on AWS
    const vmwareServiceRole = new iam.Role(this, 'VmwareCloudServiceRole', {
      roleName: 'VMwareCloudOnAWS-ServiceRole',
      assumedBy: new iam.AccountPrincipal('063048924651'), // VMware Cloud on AWS service account
      externalIds: [this.account],
      description: 'Service role for VMware Cloud on AWS operations',
    });

    // Attach the managed policy for VMware Cloud on AWS
    vmwareServiceRole.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('VMwareCloudOnAWSServiceRolePolicy')
    );

    // Create S3 bucket for VMware backups
    this.backupBucket = new s3.Bucket(this, 'VmwareBackupBucket', {
      bucketName: `vmware-backup-${uniqueSuffix}-${this.account}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'VMwareBackupLifecycle',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.STANDARD_INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
        },
      ],
    });

    // Create CloudWatch log group for VMware operations
    const vmwareLogGroup = new logs.LogGroup(this, 'VmwareLogGroup', {
      logGroupName: '/aws/vmware/migration',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create SNS topic for alerts
    const alertsTopic = new sns.Topic(this, 'VmwareAlertsTopic', {
      topicName: 'VMware-Migration-Alerts',
      displayName: 'VMware Migration Alerts',
    });

    // Subscribe email to SNS topic
    alertsTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(notificationEmail)
    );

    this.snsTopicArn = alertsTopic.topicArn;

    // Create CloudWatch alarms for SDDC health
    const sddcHealthAlarm = new cloudwatch.Alarm(this, 'SddcHealthAlarm', {
      alarmName: 'VMware-SDDC-HostHealth',
      alarmDescription: 'Monitor VMware SDDC host health',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/VMwareCloudOnAWS',
        metricName: 'HostHealth',
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 2,
    });

    sddcHealthAlarm.addAlarmAction(
      new cloudwatch.SnsAction(alertsTopic)
    );

    // Create CloudWatch dashboard
    const migrationDashboard = new cloudwatch.Dashboard(this, 'MigrationDashboard', {
      dashboardName: 'VMware-Migration-Dashboard',
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'VMware Migration Status',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/VMwareCloudOnAWS',
                metricName: 'HostHealth',
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'VMware/Migration',
                metricName: 'MigrationProgress',
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/ApplicationMigrationService',
                metricName: 'ReplicationProgress',
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
          }),
        ],
      ],
    });

    // Create EventBridge rule for SDDC events
    const sddcEventRule = new events.Rule(this, 'SddcEventRule', {
      ruleName: 'VMware-SDDC-StateChange',
      eventPattern: {
        source: ['aws.vmware'],
        detailType: ['VMware Cloud on AWS SDDC State Change'],
      },
    });

    sddcEventRule.addTarget(
      new eventsTargets.SnsTopic(alertsTopic)
    );

    // Create DynamoDB table for migration tracking
    this.migrationTable = new dynamodb.Table(this, 'MigrationTrackingTable', {
      tableName: 'VMwareMigrationTracking',
      partitionKey: {
        name: 'VMName',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'MigrationWave',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PROVISIONED,
      readCapacity: 5,
      writeCapacity: 5,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Lambda function for migration orchestration
    const migrationOrchestratorRole = new iam.Role(this, 'MigrationOrchestratorRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Grant permissions to Lambda role
    this.backupBucket.grantReadWrite(migrationOrchestratorRole);
    this.migrationTable.grantReadWriteData(migrationOrchestratorRole);
    alertsTopic.grantPublish(migrationOrchestratorRole);

    // Grant CloudWatch permissions
    migrationOrchestratorRole.addToPolicy(
      new iam.PolicyStatement({
        actions: [
          'cloudwatch:PutMetricData',
          'logs:CreateLogGroup',
          'logs:CreateLogStream',
          'logs:PutLogEvents',
        ],
        resources: ['*'],
      })
    );

    const migrationOrchestrator = new lambda.Function(this, 'MigrationOrchestrator', {
      functionName: 'VMware-Migration-Orchestrator',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Lambda function to orchestrate VMware migration waves
    """
    try:
        # Initialize AWS clients
        cloudwatch = boto3.client('cloudwatch')
        sns = boto3.client('sns')
        dynamodb = boto3.resource('dynamodb')
        
        # Get environment variables
        backup_bucket = os.environ.get('BACKUP_BUCKET')
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        table_name = os.environ.get('MIGRATION_TABLE')
        
        # Get migration wave from event
        migration_wave = event.get('wave', 1)
        
        # Update migration progress metric
        cloudwatch.put_metric_data(
            Namespace='VMware/Migration',
            MetricData=[
                {
                    'MetricName': 'CurrentWave',
                    'Value': migration_wave,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
        # Send notification
        message = f"Migration wave {migration_wave} initiated successfully"
        sns.publish(
            TopicArn=sns_topic_arn,
            Message=message,
            Subject=f"VMware Migration Wave {migration_wave} Started"
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': message,
                'wave': migration_wave,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        error_message = f"Error in migration orchestrator: {str(e)}"
        print(error_message)
        
        # Send error notification
        if 'sns_topic_arn' in locals():
            sns.publish(
                TopicArn=sns_topic_arn,
                Message=error_message,
                Subject="VMware Migration Error"
            )
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
      `),
      role: migrationOrchestratorRole,
      timeout: cdk.Duration.minutes(5),
      environment: {
        BACKUP_BUCKET: this.backupBucket.bucketName,
        SNS_TOPIC_ARN: alertsTopic.topicArn,
        MIGRATION_TABLE: this.migrationTable.tableName,
      },
    });

    // Initialize AWS Application Migration Service
    const mgnServiceRole = new iam.Role(this, 'MgnServiceRole', {
      assumedBy: new iam.ServicePrincipal('mgn.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSApplicationMigrationServiceRolePolicy'),
      ],
    });

    // Create budget for cost monitoring
    const vmwareBudget = new budgets.CfnBudget(this, 'VmwareBudget', {
      budget: {
        budgetName: 'VMware-Cloud-Budget',
        budgetLimit: {
          amount: monthlyBudgetLimit,
          unit: 'USD',
        },
        timeUnit: 'MONTHLY',
        budgetType: 'COST',
        costFilters: {
          Service: ['VMware Cloud on AWS'],
        },
      },
      notificationsWithSubscribers: [
        {
          notification: {
            notificationType: 'ACTUAL',
            comparisonOperator: 'GREATER_THAN',
            threshold: 80,
            thresholdType: 'PERCENTAGE',
          },
          subscribers: [
            {
              subscriptionType: 'EMAIL',
              address: notificationEmail,
            },
          ],
        },
      ],
    });

    // Create Direct Connect Gateway if enabled
    if (props.enableDirectConnect) {
      const directConnectGateway = new dx.CfnDirectConnectGateway(this, 'DirectConnectGateway', {
        name: 'vmware-migration-dx-gateway',
        amazonSideAsn: 64512,
      });

      // Create virtual interface if connection ID is provided
      if (props.directConnectConnectionId) {
        new dx.CfnVirtualInterface(this, 'VmwareVirtualInterface', {
          connectionId: props.directConnectConnectionId,
          vlan: 100,
          asn: 65000,
          mtu: 1500,
          interfaceType: 'private',
          addressFamily: 'ipv4',
          customerAddress: '192.168.1.1/30',
          amazonAddress: '192.168.1.2/30',
          directConnectGatewayId: directConnectGateway.ref,
        });
      }

      // Output Direct Connect Gateway ID
      new cdk.CfnOutput(this, 'DirectConnectGatewayId', {
        value: directConnectGateway.ref,
        description: 'Direct Connect Gateway ID for VMware connectivity',
      });
    }

    // Create cost anomaly detection
    const costAnomalyDetector = new ce.CfnAnomalyDetector(this, 'CostAnomalyDetector', {
      anomalyDetector: {
        detectorName: 'VMware-Cost-Anomaly-Detector',
        monitorType: 'DIMENSIONAL',
        monitorSpecification: {
          dimensionKey: 'SERVICE',
          matchOptions: ['EQUALS'],
          values: ['VMware Cloud on AWS'],
        },
      },
    });

    // Stack outputs
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for VMware Cloud on AWS connectivity',
    });

    new cdk.CfnOutput(this, 'BackupBucketName', {
      value: this.backupBucket.bucketName,
      description: 'S3 bucket for VMware backups',
    });

    new cdk.CfnOutput(this, 'MigrationTableName', {
      value: this.migrationTable.tableName,
      description: 'DynamoDB table for migration tracking',
    });

    new cdk.CfnOutput(this, 'SnsTopicArn', {
      value: alertsTopic.topicArn,
      description: 'SNS topic ARN for migration alerts',
    });

    new cdk.CfnOutput(this, 'HcxSecurityGroupId', {
      value: hcxSecurityGroup.securityGroupId,
      description: 'Security group ID for HCX traffic',
    });

    new cdk.CfnOutput(this, 'VmwareServiceRoleArn', {
      value: vmwareServiceRole.roleArn,
      description: 'IAM role ARN for VMware Cloud on AWS service',
    });

    new cdk.CfnOutput(this, 'MigrationOrchestratorArn', {
      value: migrationOrchestrator.functionArn,
      description: 'Lambda function ARN for migration orchestration',
    });

    new cdk.CfnOutput(this, 'SddcName', {
      value: sddcName,
      description: 'Name for the VMware SDDC (use in VMware Cloud Console)',
    });

    new cdk.CfnOutput(this, 'ManagementSubnet', {
      value: managementSubnet,
      description: 'Management subnet CIDR for SDDC (use in VMware Cloud Console)',
    });
  }
}

// CDK App
const app = new cdk.App();

// Get context values or use defaults
const sddcName = app.node.tryGetContext('sddcName');
const managementSubnet = app.node.tryGetContext('managementSubnet');
const notificationEmail = app.node.tryGetContext('notificationEmail');
const monthlyBudgetLimit = app.node.tryGetContext('monthlyBudgetLimit');
const enableDirectConnect = app.node.tryGetContext('enableDirectConnect') === 'true';
const directConnectConnectionId = app.node.tryGetContext('directConnectConnectionId');

// Create the stack
new VmwareCloudMigrationStack(app, 'VmwareCloudMigrationStack', {
  sddcName,
  managementSubnet,
  notificationEmail,
  monthlyBudgetLimit: monthlyBudgetLimit ? parseInt(monthlyBudgetLimit) : undefined,
  enableDirectConnect,
  directConnectConnectionId,
  
  // Stack configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Add stack-level tags
  tags: {
    Project: 'VMware-Cloud-Migration',
    Environment: 'Migration',
    Owner: 'Infrastructure-Team',
  },
  
  description: 'VMware Cloud Migration infrastructure stack with networking, monitoring, and backup services',
});

// Synthesize the app
app.synth();