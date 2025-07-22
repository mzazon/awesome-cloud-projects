#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cwActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Interface for RDS Disaster Recovery Stack properties
 */
interface RdsDisasterRecoveryStackProps extends cdk.StackProps {
  readonly primaryRegion: string;
  readonly secondaryRegion: string;
  readonly sourceDbInstanceIdentifier: string;
  readonly notificationEmail?: string;
  readonly enableAutomatedFailover?: boolean;
}

/**
 * Primary Stack - Contains the main RDS instance and monitoring in primary region
 */
class RdsPrimaryStack extends cdk.Stack {
  public readonly primaryDatabase: rds.DatabaseInstance;
  public readonly primaryTopic: sns.Topic;
  public readonly drManagerFunction: lambda.Function;

  constructor(scope: Construct, id: string, props: RdsDisasterRecoveryStackProps) {
    super(scope, id, props);

    // Create VPC for RDS instance (if needed)
    const vpc = new ec2.Vpc(this, 'RdsVpc', {
      maxAzs: 2,
      natGateways: 0, // Cost optimization - no NAT gateways needed for this use case
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'rds-subnet',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
        {
          cidrMask: 24,
          name: 'public-subnet',
          subnetType: ec2.SubnetType.PUBLIC,
        }
      ],
    });

    // Security group for RDS
    const rdsSecurityGroup = new ec2.SecurityGroup(this, 'RdsSecurityGroup', {
      vpc,
      description: 'Security group for RDS database instance',
      allowAllOutbound: false,
    });

    // Add ingress rule for database access (adjust port based on your database engine)
    rdsSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(3306), // MySQL port - change to 5432 for PostgreSQL
      'Allow database access from VPC'
    );

    // Subnet group for RDS
    const subnetGroup = new rds.SubnetGroup(this, 'RdsSubnetGroup', {
      vpc,
      description: 'Subnet group for RDS database',
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
    });

    // Primary RDS Database Instance
    this.primaryDatabase = new rds.DatabaseInstance(this, 'PrimaryDatabase', {
      engine: rds.DatabaseInstanceEngine.mysql({
        version: rds.MysqlEngineVersion.VER_8_0_35,
      }),
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      vpc,
      subnetGroup,
      securityGroups: [rdsSecurityGroup],
      databaseName: 'primarydb',
      credentials: rds.Credentials.fromGeneratedSecret('admin', {
        secretName: `${props.sourceDbInstanceIdentifier}-credentials`,
      }),
      backupRetention: cdk.Duration.days(7),
      deletionProtection: true,
      multiAz: true, // Enable Multi-AZ for high availability
      storageEncrypted: true,
      monitoringInterval: cdk.Duration.seconds(60),
      enablePerformanceInsights: true,
      performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
      removalPolicy: cdk.RemovalPolicy.SNAPSHOT,
      tags: {
        Purpose: 'DisasterRecovery',
        Environment: 'Production',
      },
    });

    // SNS Topic for notifications in primary region
    this.primaryTopic = new sns.Topic(this, 'PrimaryNotificationTopic', {
      displayName: 'RDS Disaster Recovery Notifications',
      topicName: `rds-dr-notifications-${cdk.Names.uniqueId(this).slice(-6)}`,
    });

    // Add email subscription if provided
    if (props.notificationEmail) {
      this.primaryTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(props.notificationEmail)
      );
    }

    // Lambda execution role
    const lambdaRole = new iam.Role(this, 'DrLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for disaster recovery Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        DrLambdaPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'rds:DescribeDBInstances',
                'rds:PromoteReadReplica',
                'rds:ModifyDBInstance',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [this.primaryTopic.topicArn],
            }),
          ],
        }),
      },
    });

    // Lambda function for disaster recovery management
    this.drManagerFunction = new lambda.Function(this, 'DrManagerFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      code: lambda.Code.fromInline(`
import json
import boto3
import datetime
import os

def lambda_handler(event, context):
    """
    Disaster Recovery Manager for RDS
    Handles automated failover and notification logic
    """
    
    rds = boto3.client('rds')
    sns = boto3.client('sns')
    
    # Parse the CloudWatch alarm event
    message = json.loads(event['Records'][0]['Sns']['Message'])
    alarm_name = message['AlarmName']
    new_state = message['NewStateValue']
    reason = message['NewStateReason']
    
    # Determine the action based on alarm type
    if 'HighCPU' in alarm_name and new_state == 'ALARM':
        return handle_high_cpu_alert(alarm_name, reason, sns)
    elif 'ReplicaLag' in alarm_name and new_state == 'ALARM':
        return handle_replica_lag_alert(alarm_name, reason, sns)
    elif 'DatabaseConnections' in alarm_name and new_state == 'ALARM':
        return handle_connection_failure(alarm_name, reason, sns, rds)
    
    return {
        'statusCode': 200,
        'body': json.dumps('No action required')
    }

def handle_high_cpu_alert(alarm_name, reason, sns):
    """Handle high CPU utilization alerts"""
    message = f"HIGH CPU ALERT: {alarm_name}\\nReason: {reason}\\nRecommendation: Monitor performance and consider scaling."
    
    sns.publish(
        TopicArn=os.environ['SNS_TOPIC_ARN'],
        Subject='RDS Performance Alert',
        Message=message
    )
    
    return {'statusCode': 200, 'body': 'High CPU alert processed'}

def handle_replica_lag_alert(alarm_name, reason, sns):
    """Handle replica lag alerts"""
    message = f"REPLICA LAG ALERT: {alarm_name}\\nReason: {reason}\\nRecommendation: Check network connectivity and primary database load."
    
    sns.publish(
        TopicArn=os.environ['SNS_TOPIC_ARN'],
        Subject='RDS Replica Lag Alert',
        Message=message
    )
    
    return {'statusCode': 200, 'body': 'Replica lag alert processed'}

def handle_connection_failure(alarm_name, reason, sns, rds):
    """Handle database connection failures - potential failover scenario"""
    
    # Extract database identifier from alarm name
    db_identifier = alarm_name.split('-')[0]
    
    # Check database status
    try:
        response = rds.describe_db_instances(DBInstanceIdentifier=db_identifier)
        db_status = response['DBInstances'][0]['DBInstanceStatus']
        
        if db_status not in ['available']:
            message = f"CRITICAL DATABASE ALERT: {alarm_name}\\nDatabase Status: {db_status}\\nReason: {reason}\\n\\nThis may require manual intervention or failover to DR region."
            
            sns.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject='CRITICAL: RDS Database Alert - Action Required',
                Message=message
            )
            
    except Exception as e:
        error_message = f"ERROR: Could not check database status for {db_identifier}\\nError: {str(e)}\\nImmediate manual investigation required."
        
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject='CRITICAL: RDS Monitoring Error',
            Message=error_message
        )
    
    return {'statusCode': 200, 'body': 'Connection failure alert processed'}
      `),
      timeout: cdk.Duration.minutes(5),
      environment: {
        SNS_TOPIC_ARN: this.primaryTopic.topicArn,
      },
      logRetention: logs.RetentionDays.ONE_MONTH,
      description: 'Lambda function for RDS disaster recovery management',
    });

    // Subscribe Lambda function to SNS topic
    this.primaryTopic.addSubscription(
      new snsSubscriptions.LambdaSubscription(this.drManagerFunction)
    );

    // CloudWatch Alarms for primary database monitoring
    const cpuAlarm = new cloudwatch.Alarm(this, 'PrimaryDbHighCpuAlarm', {
      metric: this.primaryDatabase.metricCPUUtilization({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.AVERAGE,
      }),
      threshold: 80,
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      alarmDescription: 'Primary database high CPU utilization',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const connectionAlarm = new cloudwatch.Alarm(this, 'PrimaryDbConnectionAlarm', {
      metric: this.primaryDatabase.metricDatabaseConnections({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.AVERAGE,
      }),
      threshold: 0,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      alarmDescription: 'Primary database connection failures',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS actions to alarms
    cpuAlarm.addAlarmAction(new cwActions.SnsAction(this.primaryTopic));
    connectionAlarm.addAlarmAction(new cwActions.SnsAction(this.primaryTopic));

    // CloudWatch Dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'RdsDrDashboard', {
      dashboardName: `rds-dr-dashboard-${cdk.Names.uniqueId(this).slice(-6)}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Primary Database CPU Utilization',
            left: [this.primaryDatabase.metricCPUUtilization()],
            width: 12,
            height: 6,
          }),
          new cloudwatch.GraphWidget({
            title: 'Primary Database Connections',
            left: [this.primaryDatabase.metricDatabaseConnections()],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // Outputs
    new cdk.CfnOutput(this, 'PrimaryDatabaseEndpoint', {
      value: this.primaryDatabase.instanceEndpoint.hostname,
      description: 'Primary database endpoint',
      exportName: `${this.stackName}-primary-db-endpoint`,
    });

    new cdk.CfnOutput(this, 'PrimaryTopicArn', {
      value: this.primaryTopic.topicArn,
      description: 'Primary SNS topic ARN',
      exportName: `${this.stackName}-primary-topic-arn`,
    });

    new cdk.CfnOutput(this, 'PrimaryDatabaseArn', {
      value: this.primaryDatabase.instanceArn,
      description: 'Primary database ARN for cross-region replication',
      exportName: `${this.stackName}-primary-db-arn`,
    });
  }
}

/**
 * Secondary Stack - Contains read replica and monitoring in secondary region
 */
class RdsSecondaryStack extends cdk.Stack {
  public readonly readReplica: rds.DatabaseInstanceReadReplica;
  public readonly secondaryTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: RdsDisasterRecoveryStackProps & {
    primaryDatabaseArn: string;
  }) {
    super(scope, id, props);

    // SNS Topic for notifications in secondary region
    this.secondaryTopic = new sns.Topic(this, 'SecondaryNotificationTopic', {
      displayName: 'RDS DR Secondary Region Notifications',
      topicName: `rds-dr-secondary-notifications-${cdk.Names.uniqueId(this).slice(-6)}`,
    });

    // Add email subscription if provided
    if (props.notificationEmail) {
      this.secondaryTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(props.notificationEmail)
      );
    }

    // Create cross-region read replica
    this.readReplica = new rds.DatabaseInstanceReadReplica(this, 'ReadReplica', {
      sourceDatabaseInstance: rds.DatabaseInstance.fromDatabaseInstanceAttributes(this, 'SourceDatabase', {
        instanceIdentifier: props.sourceDbInstanceIdentifier,
        instanceEndpointAddress: 'placeholder', // This will be replaced during deployment
        port: 3306,
        securityGroups: [],
      }),
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      multiAz: true,
      storageEncrypted: true,
      monitoringInterval: cdk.Duration.seconds(60),
      enablePerformanceInsights: true,
      performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
      removalPolicy: cdk.RemovalPolicy.SNAPSHOT,
      tags: {
        Purpose: 'DisasterRecovery',
        Environment: 'Production',
        Role: 'ReadReplica',
      },
    });

    // CloudWatch Alarm for replica lag monitoring
    const replicaLagAlarm = new cloudwatch.Alarm(this, 'ReplicaLagAlarm', {
      metric: this.readReplica.metricReplicaLag({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.AVERAGE,
      }),
      threshold: 300, // 5 minutes
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      alarmDescription: 'Read replica lag monitoring',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS action to replica lag alarm
    replicaLagAlarm.addAlarmAction(new cwActions.SnsAction(this.secondaryTopic));

    // Outputs
    new cdk.CfnOutput(this, 'ReadReplicaEndpoint', {
      value: this.readReplica.instanceEndpoint.hostname,
      description: 'Read replica endpoint',
      exportName: `${this.stackName}-replica-endpoint`,
    });

    new cdk.CfnOutput(this, 'SecondaryTopicArn', {
      value: this.secondaryTopic.topicArn,
      description: 'Secondary SNS topic ARN',
      exportName: `${this.stackName}-secondary-topic-arn`,
    });
  }
}

/**
 * Main CDK Application
 */
class RdsDisasterRecoveryApp extends cdk.App {
  constructor() {
    super();

    // Get configuration from context or environment variables
    const primaryRegion = this.node.tryGetContext('primaryRegion') || process.env.PRIMARY_REGION || 'us-east-1';
    const secondaryRegion = this.node.tryGetContext('secondaryRegion') || process.env.SECONDARY_REGION || 'us-west-2';
    const sourceDbInstanceIdentifier = this.node.tryGetContext('sourceDbInstanceIdentifier') || process.env.SOURCE_DB_IDENTIFIER || 'primary-database';
    const notificationEmail = this.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;
    const enableAutomatedFailover = this.node.tryGetContext('enableAutomatedFailover') || process.env.ENABLE_AUTOMATED_FAILOVER === 'true';

    const stackProps: RdsDisasterRecoveryStackProps = {
      primaryRegion,
      secondaryRegion,
      sourceDbInstanceIdentifier,
      notificationEmail,
      enableAutomatedFailover,
      description: 'RDS Disaster Recovery Infrastructure',
    };

    // Deploy primary stack
    const primaryStack = new RdsPrimaryStack(this, 'RdsPrimaryStack', {
      ...stackProps,
      env: {
        region: primaryRegion,
        account: process.env.CDK_DEFAULT_ACCOUNT,
      },
    });

    // Deploy secondary stack with cross-region read replica
    const secondaryStack = new RdsSecondaryStack(this, 'RdsSecondaryStack', {
      ...stackProps,
      primaryDatabaseArn: primaryStack.primaryDatabase.instanceArn,
      env: {
        region: secondaryRegion,
        account: process.env.CDK_DEFAULT_ACCOUNT,
      },
    });

    // Add dependency to ensure primary stack deploys first
    secondaryStack.addDependency(primaryStack);

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'RdsDisasterRecovery');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }
}

// Create and synthesize the application
const app = new RdsDisasterRecoveryApp();
app.synth();