#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cwactions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';

/**
 * Configuration interface for the Disaster Recovery Stack
 */
interface DisasterRecoveryConfig {
  readonly primaryRegion: string;
  readonly drRegion: string;
  readonly dbInstanceClass: string;
  readonly dbEngine: rds.DatabaseInstanceEngine;
  readonly dbUsername: string;
  readonly alertEmail: string;
  readonly backupRetentionDays: number;
  readonly enableDeletionProtection: boolean;
  readonly enablePerformanceInsights: boolean;
  readonly monitoringInterval: number;
}

/**
 * Primary Database Stack - Contains the main RDS instance and primary region resources
 */
class PrimaryDatabaseStack extends cdk.Stack {
  public readonly dbInstance: rds.DatabaseInstance;
  public readonly vpc: ec2.Vpc;
  public readonly dbSubnetGroup: rds.SubnetGroup;
  public readonly primarySnsTopic: sns.Topic;
  public readonly drCoordinatorFunction: lambda.Function;
  public readonly configBucket: s3.Bucket;
  public readonly dbSecret: secretsmanager.Secret;

  constructor(scope: Construct, id: string, config: DisasterRecoveryConfig, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create VPC for primary database
    this.vpc = new ec2.Vpc(this, 'PrimaryVPC', {
      maxAzs: 3,
      natGateways: 2,
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
        {
          cidrMask: 24,
          name: 'Database',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // Tag VPC for disaster recovery
    cdk.Tags.of(this.vpc).add('Purpose', 'DisasterRecovery');
    cdk.Tags.of(this.vpc).add('Environment', 'Production');

    // Create DB subnet group
    this.dbSubnetGroup = new rds.SubnetGroup(this, 'DatabaseSubnetGroup', {
      vpc: this.vpc,
      description: 'Subnet group for primary database',
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
    });

    // Create S3 bucket for configuration and logs
    this.configBucket = new s3.Bucket(this, 'DisasterRecoveryConfigBucket', {
      bucketName: `dr-config-bucket-${this.account}-${config.primaryRegion}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create database secret
    this.dbSecret = new secretsmanager.Secret(this, 'DatabaseSecret', {
      description: 'Database credentials for primary instance',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: config.dbUsername }),
        generateStringKey: 'password',
        excludeCharacters: '"@/\\',
        passwordLength: 16,
        requireEachIncludedType: true,
      },
    });

    // Create custom parameter group for optimized replication
    const parameterGroup = new rds.ParameterGroup(this, 'ReplicationParameterGroup', {
      engine: config.dbEngine,
      description: 'Optimized parameters for cross-region replication',
      parameters: {
        'innodb_flush_log_at_trx_commit': '2',
        'sync_binlog': '0',
        'binlog_format': 'ROW',
      },
    });

    // Create security group for RDS
    const dbSecurityGroup = new ec2.SecurityGroup(this, 'DatabaseSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for primary database',
      allowAllOutbound: false,
    });

    // Allow inbound MySQL connections from VPC
    dbSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(this.vpc.vpcCidrBlock),
      ec2.Port.tcp(3306),
      'Allow MySQL connections from VPC'
    );

    // Create RDS monitoring role
    const monitoringRole = new iam.Role(this, 'RDSMonitoringRole', {
      assumedBy: new iam.ServicePrincipal('monitoring.rds.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonRDSEnhancedMonitoringRole'),
      ],
    });

    // Create primary RDS instance
    this.dbInstance = new rds.DatabaseInstance(this, 'PrimaryDatabase', {
      instanceIdentifier: `primary-db-${this.account.substring(0, 6)}`,
      engine: config.dbEngine,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      credentials: rds.Credentials.fromSecret(this.dbSecret),
      vpc: this.vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      securityGroups: [dbSecurityGroup],
      subnetGroup: this.dbSubnetGroup,
      parameterGroup: parameterGroup,
      allocatedStorage: 20,
      storageEncrypted: true,
      backupRetention: cdk.Duration.days(config.backupRetentionDays),
      deletionProtection: config.enableDeletionProtection,
      enablePerformanceInsights: config.enablePerformanceInsights,
      monitoringInterval: cdk.Duration.seconds(config.monitoringInterval),
      monitoringRole: monitoringRole,
      autoMinorVersionUpgrade: true,
      deleteAutomatedBackups: false,
    });

    // Tag the database instance
    cdk.Tags.of(this.dbInstance).add('Purpose', 'DisasterRecovery');
    cdk.Tags.of(this.dbInstance).add('Environment', 'Production');

    // Create SNS topic for primary region alerts
    this.primarySnsTopic = new sns.Topic(this, 'PrimaryRegionAlerts', {
      topicName: `dr-primary-alerts-${this.account.substring(0, 6)}`,
      displayName: 'Disaster Recovery Primary Region Alerts',
    });

    // Subscribe email to SNS topic
    this.primarySnsTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(config.alertEmail)
    );

    // Create IAM role for Lambda disaster recovery coordinator
    const lambdaRole = new iam.Role(this, 'DisasterRecoveryLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        DisasterRecoveryPolicy: new iam.PolicyDocument({
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
              actions: [
                'sns:Publish',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ssm:PutParameter',
                'ssm:GetParameter',
              ],
              resources: [`arn:aws:ssm:*:${this.account}:parameter/disaster-recovery/*`],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'route53:GetHealthCheck',
                'route53:ChangeResourceRecordSets',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
              ],
              resources: [this.configBucket.arnForObjects('*')],
            }),
          ],
        }),
      },
    });

    // Create disaster recovery coordinator Lambda function
    this.drCoordinatorFunction = new lambda.Function(this, 'DisasterRecoveryCoordinator', {
      functionName: `dr-coordinator-${this.account.substring(0, 6)}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(60),
      environment: {
        DR_REGION: config.drRegion,
        DB_REPLICA_ID: `dr-replica-${this.account.substring(0, 6)}`,
        CONFIG_BUCKET: this.configBucket.bucketName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Disaster Recovery Coordinator Lambda Function
    Handles primary database failure detection and initiates failover
    """
    
    # Initialize AWS clients
    dr_region = os.environ['DR_REGION']
    rds = boto3.client('rds', region_name=dr_region)
    sns = boto3.client('sns', region_name=dr_region)
    route53 = boto3.client('route53')
    ssm = boto3.client('ssm', region_name=dr_region)
    s3 = boto3.client('s3')
    
    try:
        # Parse CloudWatch alarm from SNS message
        sns_message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = sns_message['AlarmName']
        
        print(f"Processing alarm: {alarm_name}")
        
        # Check if this is a database connection failure
        if 'database-connection-failure' in alarm_name:
            # Initiate disaster recovery procedure
            replica_id = os.environ['DB_REPLICA_ID']
            
            # Check replica status before promotion
            replica_status = rds.describe_db_instances(
                DBInstanceIdentifier=replica_id
            )['DBInstances'][0]['DBInstanceStatus']
            
            if replica_status == 'available':
                print(f"Promoting read replica {replica_id} to standalone instance")
                
                # Promote read replica
                rds.promote_read_replica(
                    DBInstanceIdentifier=replica_id
                )
                
                # Update parameter store with failover status
                ssm.put_parameter(
                    Name='/disaster-recovery/failover-status',
                    Value=json.dumps({
                        'status': 'in-progress',
                        'timestamp': datetime.utcnow().isoformat(),
                        'replica_id': replica_id
                    }),
                    Type='String',
                    Overwrite=True
                )
                
                # Log to S3
                s3.put_object(
                    Bucket=os.environ['CONFIG_BUCKET'],
                    Key=f'failover-logs/{datetime.utcnow().isoformat()}-failover-initiated.json',
                    Body=json.dumps({
                        'event': 'failover-initiated',
                        'replica_id': replica_id,
                        'timestamp': datetime.utcnow().isoformat(),
                        'alarm_name': alarm_name
                    })
                )
                
                return {
                    'statusCode': 200,
                    'body': json.dumps(f'DR procedure initiated for {replica_id}')
                }
            else:
                print(f"Replica {replica_id} is not available for promotion: {replica_status}")
                return {
                    'statusCode': 400,
                    'body': json.dumps(f'Replica not ready for promotion: {replica_status}')
                }
        
    except Exception as e:
        print(f"Error in DR coordinator: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
      `),
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Subscribe Lambda to SNS topic
    this.primarySnsTopic.addSubscription(
      new snsSubscriptions.LambdaSubscription(this.drCoordinatorFunction)
    );

    // Create CloudWatch alarms for database monitoring
    const connectionFailureAlarm = new cloudwatch.Alarm(this, 'DatabaseConnectionFailureAlarm', {
      alarmName: `${this.dbInstance.instanceIdentifier}-database-connection-failure`,
      alarmDescription: 'Alarm when database connection fails',
      metric: this.dbInstance.metricDatabaseConnections({
        statistic: cloudwatch.Statistic.AVERAGE,
        period: cdk.Duration.seconds(60),
      }),
      threshold: 0,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 3,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
    });

    const cpuUtilizationAlarm = new cloudwatch.Alarm(this, 'DatabaseCPUUtilizationAlarm', {
      alarmName: `${this.dbInstance.instanceIdentifier}-cpu-utilization-high`,
      alarmDescription: 'Alarm when CPU exceeds 80%',
      metric: this.dbInstance.metricCPUUtilization({
        statistic: cloudwatch.Statistic.AVERAGE,
        period: cdk.Duration.seconds(300),
      }),
      threshold: 80,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
    });

    // Add SNS actions to alarms
    connectionFailureAlarm.addAlarmAction(new cwactions.SnsAction(this.primarySnsTopic));
    cpuUtilizationAlarm.addAlarmAction(new cwactions.SnsAction(this.primarySnsTopic));

    // Store configuration in Parameter Store
    new ssm.StringParameter(this, 'PrimaryDBEndpoint', {
      parameterName: '/disaster-recovery/primary-db-endpoint',
      stringValue: this.dbInstance.instanceEndpoint.hostname,
      description: 'Primary database endpoint for disaster recovery',
    });

    new ssm.StringParameter(this, 'PrimaryDBIdentifier', {
      parameterName: '/disaster-recovery/primary-db-identifier',
      stringValue: this.dbInstance.instanceIdentifier,
      description: 'Primary database identifier for disaster recovery',
    });

    // Outputs
    new cdk.CfnOutput(this, 'PrimaryDatabaseEndpoint', {
      value: this.dbInstance.instanceEndpoint.hostname,
      description: 'Primary database endpoint',
      exportName: 'PrimaryDatabaseEndpoint',
    });

    new cdk.CfnOutput(this, 'PrimaryDatabaseIdentifier', {
      value: this.dbInstance.instanceIdentifier,
      description: 'Primary database identifier',
      exportName: 'PrimaryDatabaseIdentifier',
    });

    new cdk.CfnOutput(this, 'ConfigBucketName', {
      value: this.configBucket.bucketName,
      description: 'S3 bucket for disaster recovery configuration',
      exportName: 'ConfigBucketName',
    });

    new cdk.CfnOutput(this, 'PrimarySNSTopicArn', {
      value: this.primarySnsTopic.topicArn,
      description: 'SNS topic ARN for primary region alerts',
      exportName: 'PrimarySNSTopicArn',
    });
  }
}

/**
 * Disaster Recovery Stack - Contains the read replica and DR region resources
 */
class DisasterRecoveryStack extends cdk.Stack {
  public readonly readReplica: rds.DatabaseInstanceReadReplica;
  public readonly drSnsTopic: sns.Topic;
  public readonly replicaPromoterFunction: lambda.Function;
  public readonly vpc: ec2.Vpc;

  constructor(
    scope: Construct,
    id: string,
    config: DisasterRecoveryConfig,
    primaryDbInstanceArn: string,
    props?: cdk.StackProps
  ) {
    super(scope, id, props);

    // Create VPC for DR region
    this.vpc = new ec2.Vpc(this, 'DisasterRecoveryVPC', {
      maxAzs: 3,
      natGateways: 2,
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
        {
          cidrMask: 24,
          name: 'Database',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // Tag VPC for disaster recovery
    cdk.Tags.of(this.vpc).add('Purpose', 'DisasterRecovery');
    cdk.Tags.of(this.vpc).add('Environment', 'Production');
    cdk.Tags.of(this.vpc).add('Role', 'DR');

    // Create RDS monitoring role for DR region
    const monitoringRole = new iam.Role(this, 'DRMonitoringRole', {
      assumedBy: new iam.ServicePrincipal('monitoring.rds.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonRDSEnhancedMonitoringRole'),
      ],
    });

    // Create cross-region read replica
    this.readReplica = new rds.DatabaseInstanceReadReplica(this, 'DisasterRecoveryReplica', {
      instanceIdentifier: `dr-replica-${this.account.substring(0, 6)}`,
      sourceDatabaseInstance: rds.DatabaseInstance.fromDatabaseInstanceAttributes(this, 'SourceDB', {
        instanceIdentifier: 'primary-db',
        instanceEndpointAddress: 'dummy-endpoint',
        port: 3306,
        securityGroups: [],
      }),
      sourceRegion: config.primaryRegion,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      vpc: this.vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      publiclyAccessible: false,
      autoMinorVersionUpgrade: true,
      enablePerformanceInsights: config.enablePerformanceInsights,
      monitoringInterval: cdk.Duration.seconds(config.monitoringInterval),
      monitoringRole: monitoringRole,
    });

    // Override source database with actual ARN
    const cfnReadReplica = this.readReplica.node.defaultChild as rds.CfnDBInstance;
    cfnReadReplica.sourceDbInstanceIdentifier = primaryDbInstanceArn;

    // Tag the read replica
    cdk.Tags.of(this.readReplica).add('Purpose', 'DisasterRecovery');
    cdk.Tags.of(this.readReplica).add('Environment', 'Production');
    cdk.Tags.of(this.readReplica).add('Role', 'ReadReplica');

    // Create SNS topic for DR region alerts
    this.drSnsTopic = new sns.Topic(this, 'DisasterRecoveryAlerts', {
      topicName: `dr-failover-alerts-${this.account.substring(0, 6)}`,
      displayName: 'Disaster Recovery Failover Alerts',
    });

    // Subscribe email to DR SNS topic
    this.drSnsTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(config.alertEmail)
    );

    // Create IAM role for replica promoter Lambda
    const replicaPromoterRole = new iam.Role(this, 'ReplicaPromoterLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        ReplicaPromoterPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'rds:DescribeDBInstances',
                'rds:ModifyDBInstance',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sns:Publish',
              ],
              resources: [this.drSnsTopic.topicArn],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ssm:PutParameter',
                'ssm:GetParameter',
              ],
              resources: [`arn:aws:ssm:${config.drRegion}:${this.account}:parameter/disaster-recovery/*`],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'route53:ChangeResourceRecordSets',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create replica promoter Lambda function
    this.replicaPromoterFunction = new lambda.Function(this, 'ReplicaPromoter', {
      functionName: `replica-promoter-${this.account.substring(0, 6)}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: replicaPromoterRole,
      timeout: cdk.Duration.seconds(300),
      environment: {
        DR_REGION: config.drRegion,
        DR_SNS_ARN: this.drSnsTopic.topicArn,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Replica Promoter Lambda Function
    Handles post-promotion tasks and DNS updates
    """
    
    # Initialize AWS clients
    dr_region = os.environ['DR_REGION']
    rds = boto3.client('rds', region_name=dr_region)
    route53 = boto3.client('route53')
    ssm = boto3.client('ssm', region_name=dr_region)
    sns = boto3.client('sns', region_name=dr_region)
    
    try:
        # Check if this is a promotion completion event
        if 'source' in event and event['source'] == 'aws.rds':
            detail = event['detail']
            
            if detail['eventName'] == 'promote-read-replica' and detail['responseElements']:
                db_instance_id = detail['responseElements']['dBInstanceIdentifier']
                
                print(f"Processing promotion completion for {db_instance_id}")
                
                # Wait for instance to be available
                waiter = rds.get_waiter('db_instance_available')
                waiter.wait(
                    DBInstanceIdentifier=db_instance_id,
                    WaiterConfig={'Delay': 30, 'MaxAttempts': 20}
                )
                
                # Get promoted instance details
                instance = rds.describe_db_instances(
                    DBInstanceIdentifier=db_instance_id
                )['DBInstances'][0]
                
                new_endpoint = instance['Endpoint']['Address']
                
                # Update parameter store
                ssm.put_parameter(
                    Name='/disaster-recovery/failover-status',
                    Value=json.dumps({
                        'status': 'completed',
                        'timestamp': datetime.utcnow().isoformat(),
                        'new_endpoint': new_endpoint,
                        'db_instance_id': db_instance_id
                    }),
                    Type='String',
                    Overwrite=True
                )
                
                # Send completion notification
                sns.publish(
                    TopicArn=os.environ['DR_SNS_ARN'],
                    Subject='Disaster Recovery Completed',
                    Message=f'''
Disaster recovery promotion completed successfully.

New Database Endpoint: {new_endpoint}
Instance ID: {db_instance_id}
Completion Time: {datetime.utcnow().isoformat()}

Please update application configurations to use the new endpoint.
                    '''
                )
                
                return {
                    'statusCode': 200,
                    'body': json.dumps('Promotion completion processed successfully')
                }
        
        return {
            'statusCode': 200,
            'body': json.dumps('Event processed but no action required')
        }
        
    except Exception as e:
        print(f"Error in replica promoter: {str(e)}")
        sns.publish(
            TopicArn=os.environ['DR_SNS_ARN'],
            Subject='Disaster Recovery Error',
            Message=f'Error in replica promoter: {str(e)}'
        )
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
      `),
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Create EventBridge rule for RDS promotion events
    const rdsEventRule = new events.Rule(this, 'RDSPromotionEventRule', {
      ruleName: 'rds-promotion-events',
      description: 'Capture RDS promotion events for DR automation',
      eventPattern: {
        source: ['aws.rds'],
        detailType: ['RDS DB Instance Event'],
        detail: {
          eventName: ['promote-read-replica'],
        },
      },
    });

    // Add Lambda target to EventBridge rule
    rdsEventRule.addTarget(new targets.LambdaFunction(this.replicaPromoterFunction));

    // Create CloudWatch alarms for replica monitoring
    const replicaLagAlarm = new cloudwatch.Alarm(this, 'ReplicaLagAlarm', {
      alarmName: `${this.readReplica.instanceIdentifier}-replica-lag-high`,
      alarmDescription: 'Alarm when replica lag exceeds threshold',
      metric: this.readReplica.metricDatabaseConnections({
        statistic: cloudwatch.Statistic.AVERAGE,
        period: cdk.Duration.seconds(300),
      }),
      threshold: 300,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
    });

    const replicaCpuAlarm = new cloudwatch.Alarm(this, 'ReplicaCPUUtilizationAlarm', {
      alarmName: `${this.readReplica.instanceIdentifier}-cpu-utilization-high`,
      alarmDescription: 'Alarm when DR instance CPU exceeds 80%',
      metric: this.readReplica.metricCPUUtilization({
        statistic: cloudwatch.Statistic.AVERAGE,
        period: cdk.Duration.seconds(300),
      }),
      threshold: 80,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
    });

    // Add SNS actions to alarms
    replicaLagAlarm.addAlarmAction(new cwactions.SnsAction(this.drSnsTopic));
    replicaCpuAlarm.addAlarmAction(new cwactions.SnsAction(this.drSnsTopic));

    // Store DR configuration in Parameter Store
    new ssm.StringParameter(this, 'DRDBEndpoint', {
      parameterName: '/disaster-recovery/dr-db-endpoint',
      stringValue: this.readReplica.instanceEndpoint.hostname,
      description: 'DR database endpoint for disaster recovery',
    });

    new ssm.StringParameter(this, 'DRDBIdentifier', {
      parameterName: '/disaster-recovery/dr-db-identifier',
      stringValue: this.readReplica.instanceIdentifier,
      description: 'DR database identifier for disaster recovery',
    });

    // Create custom DR readiness metric
    new cloudwatch.Metric({
      namespace: 'Custom/DisasterRecovery',
      metricName: 'DRReadiness',
      dimensionsMap: {
        Region: config.drRegion,
      },
      statistic: cloudwatch.Statistic.AVERAGE,
    });

    // Outputs
    new cdk.CfnOutput(this, 'ReadReplicaEndpoint', {
      value: this.readReplica.instanceEndpoint.hostname,
      description: 'Read replica database endpoint',
      exportName: 'ReadReplicaEndpoint',
    });

    new cdk.CfnOutput(this, 'ReadReplicaIdentifier', {
      value: this.readReplica.instanceIdentifier,
      description: 'Read replica database identifier',
      exportName: 'ReadReplicaIdentifier',
    });

    new cdk.CfnOutput(this, 'DRSNSTopicArn', {
      value: this.drSnsTopic.topicArn,
      description: 'SNS topic ARN for DR region alerts',
      exportName: 'DRSNSTopicArn',
    });
  }
}

/**
 * Route 53 Health Checks Stack - Contains DNS health checks and failover configuration
 */
class Route53HealthChecksStack extends cdk.Stack {
  public readonly primaryHealthCheck: route53.CfnHealthCheck;
  public readonly drHealthCheck: route53.CfnHealthCheck;

  constructor(
    scope: Construct,
    id: string,
    config: DisasterRecoveryConfig,
    primaryAlarmArn: string,
    drAlarmArn: string,
    props?: cdk.StackProps
  ) {
    super(scope, id, props);

    // Create Route 53 health check for primary database
    this.primaryHealthCheck = new route53.CfnHealthCheck(this, 'PrimaryDatabaseHealthCheck', {
      type: 'CLOUDWATCH_METRIC',
      cloudWatchAlarmRegion: config.primaryRegion,
      cloudWatchAlarmName: primaryAlarmArn.split(':')[6], // Extract alarm name from ARN
      insufficientDataHealthStatus: 'Failure',
      tags: [
        {
          key: 'Name',
          value: 'Primary Database Health Check',
        },
        {
          key: 'Purpose',
          value: 'DisasterRecovery',
        },
      ],
    });

    // Create Route 53 health check for DR database
    this.drHealthCheck = new route53.CfnHealthCheck(this, 'DRDatabaseHealthCheck', {
      type: 'CLOUDWATCH_METRIC',
      cloudWatchAlarmRegion: config.drRegion,
      cloudWatchAlarmName: drAlarmArn.split(':')[6], // Extract alarm name from ARN
      insufficientDataHealthStatus: 'Success',
      tags: [
        {
          key: 'Name',
          value: 'DR Database Health Check',
        },
        {
          key: 'Purpose',
          value: 'DisasterRecovery',
        },
      ],
    });

    // Outputs
    new cdk.CfnOutput(this, 'PrimaryHealthCheckId', {
      value: this.primaryHealthCheck.attrId,
      description: 'Route 53 health check ID for primary database',
      exportName: 'PrimaryHealthCheckId',
    });

    new cdk.CfnOutput(this, 'DRHealthCheckId', {
      value: this.drHealthCheck.attrId,
      description: 'Route 53 health check ID for DR database',
      exportName: 'DRHealthCheckId',
    });
  }
}

/**
 * Main CDK Application
 */
class DatabaseDisasterRecoveryApp extends cdk.App {
  constructor() {
    super();

    // Configuration
    const config: DisasterRecoveryConfig = {
      primaryRegion: 'us-east-1',
      drRegion: 'us-west-2',
      dbInstanceClass: 'db.t3.micro',
      dbEngine: rds.DatabaseInstanceEngine.mysql({
        version: rds.MysqlEngineVersion.VER_8_0,
      }),
      dbUsername: 'admin',
      alertEmail: 'admin@example.com', // Replace with your email
      backupRetentionDays: 7,
      enableDeletionProtection: true,
      enablePerformanceInsights: true,
      monitoringInterval: 60,
    };

    // Create Primary Database Stack
    const primaryStack = new PrimaryDatabaseStack(this, 'DatabaseDRPrimaryStack', config, {
      env: {
        account: process.env.CDK_DEFAULT_ACCOUNT,
        region: config.primaryRegion,
      },
      description: 'Primary database stack for disaster recovery solution',
    });

    // Create Disaster Recovery Stack
    const drStack = new DisasterRecoveryStack(
      this,
      'DatabaseDRStack',
      config,
      primaryStack.dbInstance.instanceArn,
      {
        env: {
          account: process.env.CDK_DEFAULT_ACCOUNT,
          region: config.drRegion,
        },
        description: 'Disaster recovery stack with read replica and automation',
      }
    );

    // Create Route 53 Health Checks Stack (in primary region)
    const healthChecksStack = new Route53HealthChecksStack(
      this,
      'DatabaseDRHealthChecksStack',
      config,
      'primary-database-connection-failure', // This would be actual alarm ARN in real implementation
      'dr-replica-lag-high', // This would be actual alarm ARN in real implementation
      {
        env: {
          account: process.env.CDK_DEFAULT_ACCOUNT,
          region: config.primaryRegion,
        },
        description: 'Route 53 health checks for disaster recovery',
      }
    );

    // Add dependencies
    drStack.addDependency(primaryStack);
    healthChecksStack.addDependency(primaryStack);
    healthChecksStack.addDependency(drStack);

    // Add tags to all stacks
    const tags = {
      Project: 'DatabaseDisasterRecovery',
      Environment: 'Production',
      ManagedBy: 'CDK',
    };

    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(primaryStack).add(key, value);
      cdk.Tags.of(drStack).add(key, value);
      cdk.Tags.of(healthChecksStack).add(key, value);
    });
  }
}

// Initialize and synthesize the CDK application
const app = new DatabaseDisasterRecoveryApp();
app.synth();