#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as redshift from 'aws-cdk-lib/aws-redshift';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as ec2 from 'aws-cdk-lib/aws-ec2';

/**
 * Properties for the RedshiftPerformanceStack
 */
export interface RedshiftPerformanceStackProps extends cdk.StackProps {
  /**
   * The identifier for the Redshift cluster
   * @default 'performance-optimized-cluster'
   */
  readonly clusterIdentifier?: string;

  /**
   * The master username for the Redshift cluster
   * @default 'admin'
   */
  readonly masterUsername?: string;

  /**
   * The database name for the Redshift cluster
   * @default 'mydb'
   */
  readonly databaseName?: string;

  /**
   * The node type for the Redshift cluster
   * @default 'dc2.large'
   */
  readonly nodeType?: string;

  /**
   * The number of compute nodes in the cluster
   * @default 2
   */
  readonly numberOfNodes?: number;

  /**
   * Email address for performance alerts
   */
  readonly alertEmail?: string;

  /**
   * Whether to enable enhanced VPC routing
   * @default true
   */
  readonly enhancedVpcRouting?: boolean;

  /**
   * Whether to enable encryption at rest
   * @default true
   */
  readonly encrypted?: boolean;
}

/**
 * CDK Stack for Redshift Performance Optimization
 * 
 * This stack creates:
 * - Amazon Redshift cluster with optimized configuration
 * - Performance monitoring with CloudWatch dashboards and alarms
 * - Automated maintenance Lambda function
 * - SNS topic for alerts
 * - EventBridge rule for scheduled maintenance
 */
export class RedshiftPerformanceStack extends cdk.Stack {
  public readonly cluster: redshift.Cluster;
  public readonly maintenanceFunction: lambda.Function;
  public readonly performanceDashboard: cloudwatch.Dashboard;
  public readonly alertTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: RedshiftPerformanceStackProps = {}) {
    super(scope, id, props);

    // Default values
    const clusterIdentifier = props.clusterIdentifier ?? 'performance-optimized-cluster';
    const masterUsername = props.masterUsername ?? 'admin';
    const databaseName = props.databaseName ?? 'mydb';
    const nodeType = props.nodeType ?? 'dc2.large';
    const numberOfNodes = props.numberOfNodes ?? 2;
    const enhancedVpcRouting = props.enhancedVpcRouting ?? true;
    const encrypted = props.encrypted ?? true;

    // Create VPC for Redshift cluster
    const vpc = new ec2.Vpc(this, 'RedshiftVpc', {
      maxAzs: 2,
      natGateways: 1,
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

    // Create subnet group for Redshift
    const subnetGroup = new redshift.ClusterSubnetGroup(this, 'RedshiftSubnetGroup', {
      description: 'Subnet group for Redshift performance optimization cluster',
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
    });

    // Create security group for Redshift
    const redshiftSecurityGroup = new ec2.SecurityGroup(this, 'RedshiftSecurityGroup', {
      vpc,
      description: 'Security group for Redshift cluster',
      allowAllOutbound: true,
    });

    // Allow inbound connections on Redshift port from within VPC
    redshiftSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(5439),
      'Allow Redshift connections from VPC'
    );

    // Create master user password secret
    const masterUserSecret = new secretsmanager.Secret(this, 'RedshiftMasterPassword', {
      description: 'Master password for Redshift cluster',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: masterUsername }),
        generateStringKey: 'password',
        excludeCharacters: '"@/\\\'',
        passwordLength: 32,
      },
    });

    // Create parameter group for workload management optimization
    const parameterGroup = new redshift.ClusterParameterGroup(this, 'OptimizedParameterGroup', {
      description: 'Optimized parameter group for Redshift performance',
      parameters: {
        // Enable automatic workload management
        wlm_json_configuration: JSON.stringify([
          {
            query_group: [],
            query_group_wild_card: 0,
            user_group: [],
            user_group_wild_card: 0,
            concurrency_scaling: 'auto',
          },
        ]),
        // Enable query monitoring rules
        query_group: 'default',
        // Enable enhanced VPC routing for better network performance
        enhanced_vpc_routing: enhancedVpcRouting.toString(),
        // Enable result caching
        enable_result_cache_for_session: 'true',
        // Set statement timeout to prevent runaway queries
        statement_timeout: '1800000', // 30 minutes
      },
    });

    // Create Redshift cluster with performance optimizations
    this.cluster = new redshift.Cluster(this, 'RedshiftCluster', {
      clusterName: clusterIdentifier,
      masterUser: {
        masterUsername,
        masterPassword: masterUserSecret.secretValue,
      },
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      securityGroups: [redshiftSecurityGroup],
      clusterType: numberOfNodes === 1 ? redshift.ClusterType.SINGLE_NODE : redshift.ClusterType.MULTI_NODE,
      numberOfNodes: numberOfNodes > 1 ? numberOfNodes : undefined,
      nodeType: redshift.NodeType.of(nodeType),
      defaultDatabaseName: databaseName,
      parameterGroup,
      subnetGroup,
      encrypted,
      // Enable logging for performance analysis
      loggingProperties: {
        loggingBucket: new cdk.aws_s3.Bucket(this, 'RedshiftLogsBucket', {
          bucketName: `redshift-logs-${cdk.Stack.of(this).account}-${cdk.Stack.of(this).region}`,
          encryption: cdk.aws_s3.BucketEncryption.S3_MANAGED,
          blockPublicAccess: cdk.aws_s3.BlockPublicAccess.BLOCK_ALL,
          removalPolicy: cdk.RemovalPolicy.RETAIN,
        }),
        loggingKeyPrefix: 'redshift-logs/',
      },
      // Enable backup with optimized retention
      automatedSnapshotRetentionPeriod: cdk.Duration.days(7),
      // Enable publicly accessible for demonstration (set to false in production)
      publiclyAccessible: false,
    });

    // Create SNS topic for performance alerts
    this.alertTopic = new sns.Topic(this, 'PerformanceAlertTopic', {
      displayName: 'Redshift Performance Alerts',
      topicName: 'redshift-performance-alerts',
    });

    // Add email subscription if provided
    if (props.alertEmail) {
      this.alertTopic.addSubscription(
        new cdk.aws_sns_subscriptions.EmailSubscription(props.alertEmail)
      );
    }

    // Create CloudWatch log group for custom metrics
    const performanceLogGroup = new logs.LogGroup(this, 'PerformanceMetricsLogGroup', {
      logGroupName: '/aws/redshift/performance-metrics',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create IAM role for maintenance Lambda function
    const maintenanceLambdaRole = new iam.Role(this, 'MaintenanceLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for Redshift maintenance Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        RedshiftMaintenancePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'redshift:DescribeClusters',
                'redshift:ModifyCluster',
                'redshift:DescribeClusterParameters',
              ],
              resources: [this.cluster.clusterArn],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'secretsmanager:GetSecretValue',
              ],
              resources: [masterUserSecret.secretArn],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: [performanceLogGroup.logGroupArn],
            }),
          ],
        }),
      },
    });

    // Create Lambda function for automated maintenance
    this.maintenanceFunction = new lambda.Function(this, 'MaintenanceFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'lambda_function.lambda_handler',
      role: maintenanceLambdaRole,
      timeout: cdk.Duration.minutes(5),
      description: 'Automated Redshift maintenance function for performance optimization',
      environment: {
        CLUSTER_IDENTIFIER: this.cluster.clusterName,
        SECRET_ARN: masterUserSecret.secretArn,
        DATABASE_NAME: databaseName,
        LOG_GROUP_NAME: performanceLogGroup.logGroupName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import psycopg2
import os
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Automated Redshift maintenance function
    Performs VACUUM and ANALYZE operations on tables that need maintenance
    """
    try:
        # Get environment variables
        cluster_identifier = os.environ['CLUSTER_IDENTIFIER']
        secret_arn = os.environ['SECRET_ARN']
        database_name = os.environ['DATABASE_NAME']
        
        # Get cluster endpoint
        redshift_client = boto3.client('redshift')
        cluster_response = redshift_client.describe_clusters(
            ClusterIdentifier=cluster_identifier
        )
        cluster_endpoint = cluster_response['Clusters'][0]['Endpoint']['Address']
        
        # Get database credentials from Secrets Manager
        secrets_client = boto3.client('secretsmanager')
        secret_response = secrets_client.get_secret_value(SecretId=secret_arn)
        credentials = json.loads(secret_response['SecretString'])
        
        # Connect to Redshift
        conn = psycopg2.connect(
            host=cluster_endpoint,
            database=database_name,
            user=credentials['username'],
            password=credentials['password'],
            port=5439
        )
        
        cur = conn.cursor()
        
        # Query for tables that need VACUUM
        cur.execute("""
            SELECT TRIM(name) as table_name,
                   unsorted/DECODE(rows,0,1,rows)::FLOAT * 100 as pct_unsorted,
                   rows
            FROM stv_tbl_perm
            WHERE unsorted > 0 AND rows > 1000
            ORDER BY pct_unsorted DESC
            LIMIT 10;
        """)
        
        tables_to_vacuum = cur.fetchall()
        maintenance_count = 0
        
        for table_name, pct_unsorted, row_count in tables_to_vacuum:
            if pct_unsorted > 10:  # Only VACUUM if >10% unsorted
                logger.info(f"Performing maintenance on table: {table_name} ({pct_unsorted:.2f}% unsorted, {row_count} rows)")
                
                try:
                    # VACUUM and ANALYZE the table
                    cur.execute(f"VACUUM {table_name};")
                    cur.execute(f"ANALYZE {table_name};")
                    maintenance_count += 1
                    
                    logger.info(f"Successfully maintained table: {table_name}")
                    
                except Exception as table_error:
                    logger.error(f"Error maintaining table {table_name}: {str(table_error)}")
                    continue
        
        conn.commit()
        cur.close()
        conn.close()
        
        result_message = f'Maintenance completed successfully on {maintenance_count} tables'
        logger.info(result_message)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': result_message,
                'tables_maintained': maintenance_count,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        error_message = f"Maintenance function error: {str(e)}"
        logger.error(error_message)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
`),
    });

    // Create EventBridge rule for nightly maintenance
    const maintenanceSchedule = new events.Rule(this, 'MaintenanceSchedule', {
      description: 'Schedule for nightly Redshift maintenance',
      schedule: events.Schedule.cron({
        minute: '0',
        hour: '2',
        day: '*',
        month: '*',
        year: '*',
      }),
    });

    // Add Lambda function as target for the scheduled rule
    maintenanceSchedule.addTarget(new targets.LambdaFunction(this.maintenanceFunction));

    // Create CloudWatch alarms for performance monitoring
    const cpuAlarm = new cloudwatch.Alarm(this, 'HighCpuAlarm', {
      alarmName: `Redshift-High-CPU-Usage-${clusterIdentifier}`,
      alarmDescription: 'Alert when Redshift CPU usage is high',
      metric: this.cluster.metricCPUUtilization({
        statistic: cloudwatch.Statistic.AVERAGE,
        period: cdk.Duration.minutes(5),
      }),
      threshold: 80,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const queueLengthAlarm = new cloudwatch.Alarm(this, 'HighQueueLengthAlarm', {
      alarmName: `Redshift-High-Queue-Length-${clusterIdentifier}`,
      alarmDescription: 'Alert when query queue length is high',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Redshift',
        metricName: 'QueueLength',
        dimensionsMap: {
          ClusterIdentifier: this.cluster.clusterName,
        },
        statistic: cloudwatch.Statistic.AVERAGE,
        period: cdk.Duration.minutes(5),
      }),
      threshold: 10,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const connectionCountAlarm = new cloudwatch.Alarm(this, 'HighConnectionCountAlarm', {
      alarmName: `Redshift-High-Connection-Count-${clusterIdentifier}`,
      alarmDescription: 'Alert when database connection count is high',
      metric: this.cluster.metricDatabaseConnections({
        statistic: cloudwatch.Statistic.AVERAGE,
        period: cdk.Duration.minutes(5),
      }),
      threshold: 450, // Alert when approaching max connections
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS actions to alarms
    const snsAction = new cloudwatchActions.SnsAction(this.alertTopic);
    cpuAlarm.addAlarmAction(snsAction);
    queueLengthAlarm.addAlarmAction(snsAction);
    connectionCountAlarm.addAlarmAction(snsAction);

    // Create comprehensive CloudWatch dashboard
    this.performanceDashboard = new cloudwatch.Dashboard(this, 'PerformanceDashboard', {
      dashboardName: `Redshift-Performance-Dashboard-${clusterIdentifier}`,
    });

    // Add widgets to dashboard
    this.performanceDashboard.addWidgets(
      // Row 1: Overview metrics
      new cloudwatch.GraphWidget({
        title: 'Cluster Overview',
        left: [
          this.cluster.metricCPUUtilization(),
          this.cluster.metricDatabaseConnections(),
        ],
        right: [
          new cloudwatch.Metric({
            namespace: 'AWS/Redshift',
            metricName: 'HealthStatus',
            dimensionsMap: {
              ClusterIdentifier: this.cluster.clusterName,
            },
          }),
        ],
        width: 12,
        height: 6,
      }),
      
      // Row 2: Query performance metrics
      new cloudwatch.GraphWidget({
        title: 'Query Performance',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Redshift',
            metricName: 'QueueLength',
            dimensionsMap: {
              ClusterIdentifier: this.cluster.clusterName,
            },
          }),
        ],
        right: [
          new cloudwatch.Metric({
            namespace: 'AWS/Redshift',
            metricName: 'WLMQueueLength',
            dimensionsMap: {
              ClusterIdentifier: this.cluster.clusterName,
            },
          }),
        ],
        width: 12,
        height: 6,
      }),
      
      // Row 3: Storage and I/O metrics
      new cloudwatch.GraphWidget({
        title: 'Storage and I/O',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Redshift',
            metricName: 'PercentageDiskSpaceUsed',
            dimensionsMap: {
              ClusterIdentifier: this.cluster.clusterName,
            },
          }),
        ],
        right: [
          new cloudwatch.Metric({
            namespace: 'AWS/Redshift',
            metricName: 'ReadIOPS',
            dimensionsMap: {
              ClusterIdentifier: this.cluster.clusterName,
            },
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/Redshift',
            metricName: 'WriteIOPS',
            dimensionsMap: {
              ClusterIdentifier: this.cluster.clusterName,
            },
          }),
        ],
        width: 12,
        height: 6,
      })
    );

    // Output important values
    new cdk.CfnOutput(this, 'ClusterIdentifier', {
      value: this.cluster.clusterName,
      description: 'Redshift cluster identifier',
    });

    new cdk.CfnOutput(this, 'ClusterEndpoint', {
      value: this.cluster.clusterEndpoint.hostname,
      description: 'Redshift cluster endpoint',
    });

    new cdk.CfnOutput(this, 'ClusterPort', {
      value: this.cluster.clusterEndpoint.port.toString(),
      description: 'Redshift cluster port',
    });

    new cdk.CfnOutput(this, 'MasterUserSecretArn', {
      value: masterUserSecret.secretArn,
      description: 'ARN of the secret containing master user credentials',
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.performanceDashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard',
    });

    new cdk.CfnOutput(this, 'MaintenanceFunctionName', {
      value: this.maintenanceFunction.functionName,
      description: 'Name of the maintenance Lambda function',
    });

    new cdk.CfnOutput(this, 'AlertTopicArn', {
      value: this.alertTopic.topicArn,
      description: 'ARN of the SNS topic for performance alerts',
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'RedshiftPerformanceOptimization');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('Owner', 'DataEngineering');
  }
}

// CDK App
const app = new cdk.App();

// Create the stack with default configuration
new RedshiftPerformanceStack(app, 'RedshiftPerformanceStack', {
  description: 'Stack for optimizing Amazon Redshift performance with monitoring and automation',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  // Example configuration - customize as needed
  clusterIdentifier: 'performance-optimized-cluster',
  masterUsername: 'admin',
  databaseName: 'mydb',
  nodeType: 'dc2.large',
  numberOfNodes: 2,
  // alertEmail: 'admin@example.com', // Uncomment and set your email
  enhancedVpcRouting: true,
  encrypted: true,
});

app.synth();