#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as athena from 'aws-cdk-lib/aws-athena';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as logsDestination from 'aws-cdk-lib/aws-logs-destinations';
import { Construct } from 'constructs';

/**
 * Properties for the NetworkMonitoringStack
 */
interface NetworkMonitoringStackProps extends cdk.StackProps {
  /**
   * The VPC ID to monitor. If not provided, will use the default VPC.
   */
  readonly vpcId?: string;
  
  /**
   * Email address for alert notifications
   */
  readonly alertEmail?: string;
  
  /**
   * Environment name for resource tagging
   */
  readonly environment?: string;
  
  /**
   * Enable comprehensive flow logs format with additional fields
   * @default true
   */
  readonly enableComprehensiveFormat?: boolean;
  
  /**
   * Flow logs aggregation interval in seconds (60 or 600)
   * @default 60
   */
  readonly aggregationInterval?: number;
  
  /**
   * CloudWatch Logs retention period in days
   * @default 30
   */
  readonly logRetentionDays?: number;
}

/**
 * AWS CDK Stack for comprehensive VPC Flow Logs network monitoring
 * 
 * This stack implements a complete network monitoring solution using VPC Flow Logs
 * integrated with CloudWatch for real-time alerting, S3 for cost-effective storage,
 * and Athena for advanced analytics capabilities.
 * 
 * Key Features:
 * - Dual destination flow logs (CloudWatch + S3)
 * - Real-time anomaly detection via CloudWatch metrics and alarms
 * - Advanced analytics with Athena and Glue Data Catalog
 * - Serverless anomaly detection with Lambda
 * - Comprehensive alerting via SNS
 * - Cost-optimized S3 lifecycle policies
 */
export class NetworkMonitoringStack extends cdk.Stack {
  public readonly flowLogsBucket: s3.Bucket;
  public readonly cloudWatchLogGroup: logs.LogGroup;
  public readonly snsAlertTopic: sns.Topic;
  public readonly anomalyDetectorLambda: lambda.Function;
  public readonly athenaWorkGroup: athena.CfnWorkGroup;
  public readonly glueDatabase: glue.CfnDatabase;

  constructor(scope: Construct, id: string, props: NetworkMonitoringStackProps = {}) {
    super(scope, id, props);

    // Extract configuration with defaults
    const environment = props.environment || 'production';
    const enableComprehensiveFormat = props.enableComprehensiveFormat ?? true;
    const aggregationInterval = props.aggregationInterval || 60;
    const logRetentionDays = props.logRetentionDays || 30;

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.substring(0, 8);

    // Get or create VPC reference
    const vpc = props.vpcId 
      ? ec2.Vpc.fromLookup(this, 'MonitoredVpc', { vpcId: props.vpcId })
      : ec2.Vpc.fromLookup(this, 'DefaultVpc', { isDefault: true });

    // Create S3 bucket for flow logs storage with security best practices
    this.flowLogsBucket = new s3.Bucket(this, 'FlowLogsBucket', {
      bucketName: `vpc-flow-logs-${this.account}-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'FlowLogsLifecycle',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
            {
              storageClass: s3.StorageClass.DEEP_ARCHIVE,
              transitionAfter: cdk.Duration.days(365),
            },
          ],
          expiration: cdk.Duration.days(2557), // 7 years for compliance
        },
      ],
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // Create CloudWatch Log Group for real-time monitoring
    this.cloudWatchLogGroup = new logs.LogGroup(this, 'FlowLogsGroup', {
      logGroupName: '/aws/vpc/flowlogs',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create IAM role for VPC Flow Logs with least privilege permissions
    const flowLogsRole = new iam.Role(this, 'FlowLogsRole', {
      roleName: `VPCFlowLogsRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('vpc-flow-logs.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/VPCFlowLogsDeliveryRolePolicy'),
      ],
    });

    // Create SNS topic for alerting with encryption
    this.snsAlertTopic = new sns.Topic(this, 'NetworkAlertsTopic', {
      topicName: `network-monitoring-alerts-${uniqueSuffix}`,
      displayName: 'Network Monitoring Alerts',
      kmsMasterKey: undefined, // Use AWS managed key for simplicity
    });

    // Add email subscription if provided
    if (props.alertEmail) {
      this.snsAlertTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(props.alertEmail)
      );
    }

    // Define comprehensive flow logs format for enhanced analysis
    const comprehensiveFormat = enableComprehensiveFormat 
      ? '${version} ${account-id} ${interface-id} ${srcaddr} ${dstaddr} ${srcport} ${dstport} ${protocol} ${packets} ${bytes} ${start} ${end} ${action} ${log-status} ${vpc-id} ${subnet-id} ${instance-id} ${tcp-flags} ${type} ${pkt-srcaddr} ${pkt-dstaddr}'
      : undefined;

    // Create VPC Flow Logs for CloudWatch (real-time monitoring)
    const cloudWatchFlowLogs = new ec2.CfnFlowLog(this, 'CloudWatchFlowLog', {
      resourceType: 'VPC',
      resourceIds: [vpc.vpcId],
      trafficType: 'ALL',
      logDestinationType: 'cloud-watch-logs',
      logGroupName: this.cloudWatchLogGroup.logGroupName,
      deliverLogsPermissionArn: flowLogsRole.roleArn,
      maxAggregationInterval: aggregationInterval,
      tags: [
        { key: 'Name', value: 'VPC-FlowLogs-CloudWatch' },
        { key: 'Environment', value: environment },
        { key: 'Purpose', value: 'NetworkMonitoring' },
      ],
    });

    // Create VPC Flow Logs for S3 (long-term storage and analytics)
    const s3FlowLogs = new ec2.CfnFlowLog(this, 'S3FlowLog', {
      resourceType: 'VPC',
      resourceIds: [vpc.vpcId],
      trafficType: 'ALL',
      logDestinationType: 's3',
      logDestination: `${this.flowLogsBucket.bucketArn}/vpc-flow-logs/`,
      logFormat: comprehensiveFormat,
      maxAggregationInterval: aggregationInterval,
      tags: [
        { key: 'Name', value: 'VPC-FlowLogs-S3' },
        { key: 'Environment', value: environment },
        { key: 'Purpose', value: 'NetworkAnalytics' },
      ],
    });

    // Create custom CloudWatch metrics from flow logs
    this.createCustomMetrics();

    // Create CloudWatch alarms for network security monitoring
    this.createSecurityAlarms();

    // Create Lambda function for advanced anomaly detection
    this.anomalyDetectorLambda = this.createAnomalyDetectorLambda(uniqueSuffix);

    // Create Glue database for Athena analytics
    this.glueDatabase = new glue.CfnDatabase(this, 'FlowLogsDatabase', {
      catalogId: this.account,
      databaseInput: {
        name: `vpc_flow_logs_db_${uniqueSuffix}`,
        description: 'Database for VPC Flow Logs analytics with Athena',
      },
    });

    // Create Athena workgroup for flow logs analysis
    this.athenaWorkGroup = new athena.CfnWorkGroup(this, 'FlowLogsWorkGroup', {
      name: `vpc-flow-logs-workgroup-${uniqueSuffix}`,
      description: 'Workgroup for VPC Flow Logs analysis',
      workGroupConfiguration: {
        resultConfiguration: {
          outputLocation: `s3://${this.flowLogsBucket.bucketName}/athena-results/`,
          encryptionConfiguration: {
            encryptionOption: 'SSE_S3',
          },
        },
        enforceWorkGroupConfiguration: true,
        publishCloudWatchMetrics: true,
      },
    });

    // Create Glue table for Athena queries
    this.createGlueTable();

    // Create CloudWatch dashboard for monitoring
    this.createMonitoringDashboard();

    // Add resource dependencies
    s3FlowLogs.addDependency(cloudWatchFlowLogs);
    
    // Output important resource information
    new cdk.CfnOutput(this, 'FlowLogsBucketName', {
      value: this.flowLogsBucket.bucketName,
      description: 'S3 bucket for VPC Flow Logs storage',
      exportName: `${this.stackName}-FlowLogsBucket`,
    });

    new cdk.CfnOutput(this, 'CloudWatchLogGroupName', {
      value: this.cloudWatchLogGroup.logGroupName,
      description: 'CloudWatch Log Group for VPC Flow Logs',
      exportName: `${this.stackName}-LogGroup`,
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.snsAlertTopic.topicArn,
      description: 'SNS topic for network monitoring alerts',
      exportName: `${this.stackName}-AlertTopic`,
    });

    new cdk.CfnOutput(this, 'AthenaWorkGroupName', {
      value: this.athenaWorkGroup.name!,
      description: 'Athena workgroup for flow logs analysis',
      exportName: `${this.stackName}-AthenaWorkGroup`,
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=VPC-Flow-Logs-Monitoring`,
      description: 'CloudWatch Dashboard URL for network monitoring',
    });
  }

  /**
   * Creates custom CloudWatch metrics from VPC Flow Logs
   */
  private createCustomMetrics(): void {
    // Metric filter for rejected connections
    new logs.MetricFilter(this, 'RejectedConnectionsFilter', {
      logGroup: this.cloudWatchLogGroup,
      metricNamespace: 'VPC/FlowLogs',
      metricName: 'RejectedConnections',
      metricValue: '1',
      filterPattern: logs.FilterPattern.spaceDelimited(
        'version', 'account', 'eni', 'source', 'destination', 'srcport', 
        'destport', 'protocol', 'packets', 'bytes', 'windowstart', 
        'windowend', 'action', 'flowlogstatus'
      ).whereString('action', '=', 'REJECT'),
    });

    // Metric filter for high data transfer (>10MB)
    new logs.MetricFilter(this, 'HighDataTransferFilter', {
      logGroup: this.cloudWatchLogGroup,
      metricNamespace: 'VPC/FlowLogs',
      metricName: 'HighDataTransfer',
      metricValue: '1',
      filterPattern: logs.FilterPattern.spaceDelimited(
        'version', 'account', 'eni', 'source', 'destination', 'srcport', 
        'destport', 'protocol', 'packets', 'bytes', 'windowstart', 
        'windowend', 'action', 'flowlogstatus'
      ).whereNumber('bytes', '>', 10000000),
    });

    // Metric filter for external connections (non-RFC1918 addresses)
    new logs.MetricFilter(this, 'ExternalConnectionsFilter', {
      logGroup: this.cloudWatchLogGroup,
      metricNamespace: 'VPC/FlowLogs',
      metricName: 'ExternalConnections',
      metricValue: '1',
      filterPattern: logs.FilterPattern.literal(
        '[version, account, eni, source!="10.*" && source!="172.16.*" && source!="192.168.*", destination, srcport, destport, protocol, packets, bytes, windowstart, windowend, action, flowlogstatus]'
      ),
    });
  }

  /**
   * Creates CloudWatch alarms for network security monitoring
   */
  private createSecurityAlarms(): void {
    // Alarm for excessive rejected connections
    const rejectedConnectionsAlarm = new cloudwatch.Alarm(this, 'HighRejectedConnectionsAlarm', {
      alarmName: 'VPC-High-Rejected-Connections',
      alarmDescription: 'Alert when rejected connections exceed threshold indicating potential attacks',
      metric: new cloudwatch.Metric({
        namespace: 'VPC/FlowLogs',
        metricName: 'RejectedConnections',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 50,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    rejectedConnectionsAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.snsAlertTopic));

    // Alarm for high data transfer
    const highDataTransferAlarm = new cloudwatch.Alarm(this, 'HighDataTransferAlarm', {
      alarmName: 'VPC-High-Data-Transfer',
      alarmDescription: 'Alert when high data transfer detected indicating potential data exfiltration',
      metric: new cloudwatch.Metric({
        namespace: 'VPC/FlowLogs',
        metricName: 'HighDataTransfer',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 10,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    highDataTransferAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.snsAlertTopic));

    // Alarm for external connections
    const externalConnectionsAlarm = new cloudwatch.Alarm(this, 'ExternalConnectionsAlarm', {
      alarmName: 'VPC-External-Connections',
      alarmDescription: 'Alert when external connections exceed threshold',
      metric: new cloudwatch.Metric({
        namespace: 'VPC/FlowLogs',
        metricName: 'ExternalConnections',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 100,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    externalConnectionsAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.snsAlertTopic));
  }

  /**
   * Creates Lambda function for advanced anomaly detection
   */
  private createAnomalyDetectorLambda(uniqueSuffix: string): lambda.Function {
    // Create Lambda execution role with necessary permissions
    const lambdaRole = new iam.Role(this, 'AnomalyDetectorRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        SNSPublishPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [this.snsAlertTopic.topicArn],
            }),
          ],
        }),
      },
    });

    // Lambda function code for anomaly detection
    const lambdaFunction = new lambda.Function(this, 'AnomalyDetectorFunction', {
      functionName: `network-anomaly-detector-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      environment: {
        SNS_TOPIC_ARN: this.snsAlertTopic.topicArn,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import gzip
import base64
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Advanced anomaly detection for VPC Flow Logs
    Analyzes traffic patterns and detects suspicious activities
    """
    
    # Decode and decompress CloudWatch Logs data
    try:
        compressed_payload = base64.b64decode(event['awslogs']['data'])
        uncompressed_payload = gzip.decompress(compressed_payload)
        log_data = json.loads(uncompressed_payload)
    except Exception as e:
        print(f"Error processing log data: {str(e)}")
        return {'statusCode': 400, 'body': 'Error processing log data'}
    
    anomalies = []
    sns_client = boto3.client('sns')
    
    # Process each log event
    for log_event in log_data['logEvents']:
        try:
            message = log_event['message']
            fields = message.split(' ')
            
            # Ensure we have enough fields
            if len(fields) < 14:
                continue
                
            # Extract relevant fields
            srcaddr = fields[3]
            dstaddr = fields[4]
            srcport = int(fields[5]) if fields[5].isdigit() else 0
            dstport = int(fields[6]) if fields[6].isdigit() else 0
            protocol = fields[7]
            bytes_transferred = int(fields[9]) if fields[9].isdigit() else 0
            action = fields[12]
            
            # Anomaly detection rules
            
            # 1. Detect very high data transfer (>50MB)
            if bytes_transferred > 50000000:
                anomalies.append({
                    'type': 'high_data_transfer',
                    'source': srcaddr,
                    'destination': dstaddr,
                    'bytes': bytes_transferred,
                    'timestamp': log_event['timestamp'],
                    'severity': 'HIGH'
                })
            
            # 2. Detect TCP connection rejections on common ports
            if action == 'REJECT' and protocol == '6':  # TCP protocol
                if dstport in [22, 80, 443, 3389, 1433, 3306]:  # Common service ports
                    anomalies.append({
                        'type': 'rejected_service_connection',
                        'source': srcaddr,
                        'destination': dstaddr,
                        'port': dstport,
                        'timestamp': log_event['timestamp'],
                        'severity': 'MEDIUM'
                    })
            
            # 3. Detect potential port scanning (multiple rejected connections from same source)
            if action == 'REJECT':
                # This is simplified - in production, you'd maintain state across invocations
                anomalies.append({
                    'type': 'potential_port_scan',
                    'source': srcaddr,
                    'destination': dstaddr,
                    'port': dstport,
                    'timestamp': log_event['timestamp'],
                    'severity': 'MEDIUM'
                })
            
            # 4. Detect suspicious protocols or unusual port combinations
            if protocol in ['1']:  # ICMP
                if bytes_transferred > 1000:  # Large ICMP packets
                    anomalies.append({
                        'type': 'large_icmp_packet',
                        'source': srcaddr,
                        'destination': dstaddr,
                        'bytes': bytes_transferred,
                        'timestamp': log_event['timestamp'],
                        'severity': 'LOW'
                    })
                    
        except Exception as e:
            print(f"Error processing log event: {str(e)}")
            continue
    
    # Send notifications for high-severity anomalies
    high_severity_anomalies = [a for a in anomalies if a.get('severity') == 'HIGH']
    
    if high_severity_anomalies:
        message = {
            'alert_type': 'Network Security Anomaly',
            'timestamp': datetime.utcnow().isoformat(),
            'anomalies_detected': len(high_severity_anomalies),
            'total_anomalies': len(anomalies),
            'high_severity_details': high_severity_anomalies[:5],  # Limit to first 5
            'summary': f"Detected {len(high_severity_anomalies)} high-severity network anomalies"
        }
        
        try:
            sns_client.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Message=json.dumps(message, indent=2),
                Subject=f'🚨 Network Security Alert: {len(high_severity_anomalies)} High-Severity Anomalies Detected'
            )
        except Exception as e:
            print(f"Error sending SNS notification: {str(e)}")
    
    # Log summary for monitoring
    print(f"Processed {len(log_data['logEvents'])} log events")
    print(f"Detected {len(anomalies)} total anomalies ({len(high_severity_anomalies)} high-severity)")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'events_processed': len(log_data['logEvents']),
            'anomalies_detected': len(anomalies),
            'high_severity_anomalies': len(high_severity_anomalies)
        })
    }
`),
    });

    // Create subscription filter to trigger Lambda on specific log patterns
    new logs.SubscriptionFilter(this, 'AnomalyDetectionSubscription', {
      logGroup: this.cloudWatchLogGroup,
      destination: new logsDestination.LambdaDestination(lambdaFunction),
      filterPattern: logs.FilterPattern.anyTerm('REJECT', 'ACCEPT'),
    });

    return lambdaFunction;
  }

  /**
   * Creates Glue table for Athena analytics
   */
  private createGlueTable(): void {
    new glue.CfnTable(this, 'FlowLogsTable', {
      catalogId: this.account,
      databaseName: this.glueDatabase.ref,
      tableInput: {
        name: 'vpc_flow_logs',
        description: 'VPC Flow Logs table for Athena analytics',
        tableType: 'EXTERNAL_TABLE',
        parameters: {
          'projection.enabled': 'true',
          'projection.year.type': 'integer',
          'projection.year.range': '2020,2030',
          'projection.month.type': 'integer',
          'projection.month.range': '01,12',
          'projection.month.digits': '2',
          'projection.day.type': 'integer',
          'projection.day.range': '01,31',
          'projection.day.digits': '2',
          'projection.hour.type': 'integer',
          'projection.hour.range': '00,23',
          'projection.hour.digits': '2',
          'storage.location.template': `s3://${this.flowLogsBucket.bucketName}/vpc-flow-logs/AWSLogs/${this.account}/vpcflowlogs/${this.region}/\${year}/\${month}/\${day}/\${hour}`,
        },
        partitionKeys: [
          { name: 'year', type: 'string' },
          { name: 'month', type: 'string' },
          { name: 'day', type: 'string' },
          { name: 'hour', type: 'string' },
        ],
        storageDescriptor: {
          columns: [
            { name: 'version', type: 'int' },
            { name: 'account_id', type: 'string' },
            { name: 'interface_id', type: 'string' },
            { name: 'srcaddr', type: 'string' },
            { name: 'dstaddr', type: 'string' },
            { name: 'srcport', type: 'int' },
            { name: 'dstport', type: 'int' },
            { name: 'protocol', type: 'bigint' },
            { name: 'packets', type: 'bigint' },
            { name: 'bytes', type: 'bigint' },
            { name: 'windowstart', type: 'bigint' },
            { name: 'windowend', type: 'bigint' },
            { name: 'action', type: 'string' },
            { name: 'flowlogstatus', type: 'string' },
            { name: 'vpc_id', type: 'string' },
            { name: 'subnet_id', type: 'string' },
            { name: 'instance_id', type: 'string' },
            { name: 'tcp_flags', type: 'int' },
            { name: 'type', type: 'string' },
            { name: 'pkt_srcaddr', type: 'string' },
            { name: 'pkt_dstaddr', type: 'string' },
          ],
          location: `s3://${this.flowLogsBucket.bucketName}/vpc-flow-logs/AWSLogs/${this.account}/vpcflowlogs/${this.region}/`,
          inputFormat: 'org.apache.hadoop.mapred.TextInputFormat',
          outputFormat: 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat',
          serdeInfo: {
            serializationLibrary: 'org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe',
            parameters: {
              'field.delim': ' ',
              'skip.header.line.count': '0',
            },
          },
        },
      },
    });
  }

  /**
   * Creates CloudWatch dashboard for network monitoring visualization
   */
  private createMonitoringDashboard(): void {
    const dashboard = new cloudwatch.Dashboard(this, 'NetworkMonitoringDashboard', {
      dashboardName: 'VPC-Flow-Logs-Monitoring',
    });

    // Create metrics widgets
    const networkMetricsWidget = new cloudwatch.GraphWidget({
      title: 'Network Security Metrics',
      left: [
        new cloudwatch.Metric({
          namespace: 'VPC/FlowLogs',
          metricName: 'RejectedConnections',
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        new cloudwatch.Metric({
          namespace: 'VPC/FlowLogs',
          metricName: 'HighDataTransfer',
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        new cloudwatch.Metric({
          namespace: 'VPC/FlowLogs',
          metricName: 'ExternalConnections',
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
      ],
      width: 12,
      height: 6,
    });

    // Create log insights widget for rejected connections
    const rejectedConnectionsWidget = new cloudwatch.LogQueryWidget({
      title: 'Rejected Connections Over Time',
      logGroups: [this.cloudWatchLogGroup],
      queryLines: [
        'fields @timestamp, @message',
        'filter @message like /REJECT/',
        'stats count() by bin(5m)',
      ],
      width: 12,
      height: 6,
    });

    // Create Lambda metrics widget
    const lambdaMetricsWidget = new cloudwatch.GraphWidget({
      title: 'Anomaly Detector Lambda Metrics',
      left: [
        this.anomalyDetectorLambda.metricInvocations({
          period: cdk.Duration.minutes(5),
        }),
        this.anomalyDetectorLambda.metricErrors({
          period: cdk.Duration.minutes(5),
        }),
        this.anomalyDetectorLambda.metricDuration({
          period: cdk.Duration.minutes(5),
        }),
      ],
      width: 12,
      height: 6,
    });

    // Add widgets to dashboard
    dashboard.addWidgets(networkMetricsWidget);
    dashboard.addWidgets(rejectedConnectionsWidget);
    dashboard.addWidgets(lambdaMetricsWidget);
  }
}

/**
 * Main CDK application entry point
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const vpcId = app.node.tryGetContext('vpcId') || process.env.VPC_ID;
const alertEmail = app.node.tryGetContext('alertEmail') || process.env.ALERT_EMAIL;
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'production';

// Create the network monitoring stack
new NetworkMonitoringStack(app, 'NetworkMonitoringStack', {
  vpcId,
  alertEmail,
  environment,
  description: 'Comprehensive VPC Flow Logs network monitoring solution with real-time alerting and analytics',
  tags: {
    Project: 'NetworkMonitoring',
    Environment: environment,
    Owner: 'SecurityTeam',
    CostCenter: 'Infrastructure',
  },
});

app.synth();