import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as fsx from 'aws-cdk-lib/aws-fsx';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import { Construct } from 'constructs';

/**
 * Configuration interface for FSx settings
 */
export interface FsxConfiguration {
  storageCapacity: number;
  throughputCapacity: number;
  cacheSize: number;
}

/**
 * Configuration interface for monitoring thresholds
 */
export interface MonitoringConfiguration {
  cacheHitRatioThreshold: number;
  storageUtilizationThreshold: number;
  networkUtilizationThreshold: number;
}

/**
 * Configuration interface for automation schedules
 */
export interface AutomationConfiguration {
  lifecyclePolicySchedule: string;
  costReportingSchedule: string;
}

/**
 * Properties for the Automated File Lifecycle Management Stack
 */
export interface AutomatedFileLifecycleManagementStackProps extends cdk.StackProps {
  fsxConfiguration: FsxConfiguration;
  monitoring: MonitoringConfiguration;
  automation: AutomationConfiguration;
  notificationEmail?: string;
  tags: { [key: string]: string };
}

/**
 * CDK Stack for Automated File Lifecycle Management with Amazon FSx and Lambda
 * 
 * This stack creates:
 * - Amazon FSx for OpenZFS file system with intelligent tiering capabilities
 * - Lambda functions for lifecycle policy management and cost reporting
 * - EventBridge rules for automated execution
 * - CloudWatch alarms for monitoring
 * - SNS notifications for alerts
 * - S3 bucket for cost reports
 * - CloudWatch dashboard for visualization
 */
export class AutomatedFileLifecycleManagementStack extends cdk.Stack {
  public readonly fsxFileSystem: fsx.CfnFileSystem;
  public readonly lifecyclePolicyFunction: lambda.Function;
  public readonly costReportingFunction: lambda.Function;
  public readonly alertHandlerFunction: lambda.Function;
  public readonly snsTopic: sns.Topic;
  public readonly reportsBucket: s3.Bucket;

  constructor(scope: Construct, id: string, props: AutomatedFileLifecycleManagementStackProps) {
    super(scope, id, props);

    // Apply tags to all resources in the stack
    for (const [key, value] of Object.entries(props.tags)) {
      cdk.Tags.of(this).add(key, value);
    }

    // Create VPC and networking components
    const { vpc, securityGroup } = this.createNetworking();

    // Create S3 bucket for cost reports
    this.reportsBucket = this.createReportsBucket();

    // Create SNS topic for notifications
    this.snsTopic = this.createNotificationTopic(props.notificationEmail);

    // Create IAM role for Lambda functions
    const lambdaRole = this.createLambdaExecutionRole();

    // Create FSx file system
    this.fsxFileSystem = this.createFsxFileSystem(vpc, securityGroup, props.fsxConfiguration);

    // Create Lambda functions
    this.lifecyclePolicyFunction = this.createLifecyclePolicyFunction(lambdaRole, this.snsTopic);
    this.costReportingFunction = this.createCostReportingFunction(lambdaRole, this.reportsBucket);
    this.alertHandlerFunction = this.createAlertHandlerFunction(lambdaRole, this.snsTopic, this.fsxFileSystem);

    // Create EventBridge rules for automation
    this.createEventBridgeRules(props.automation);

    // Create CloudWatch alarms
    this.createCloudWatchAlarms(props.monitoring, this.fsxFileSystem, this.snsTopic);

    // Create CloudWatch dashboard
    this.createCloudWatchDashboard(this.fsxFileSystem);

    // Output important resource information
    this.createOutputs();
  }

  /**
   * Creates VPC and security group for FSx
   */
  private createNetworking(): { vpc: ec2.IVpc; securityGroup: ec2.SecurityGroup } {
    // Use default VPC or create a new one
    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVpc', {
      isDefault: true,
    });

    // Create security group for FSx
    const securityGroup = new ec2.SecurityGroup(this, 'FsxSecurityGroup', {
      vpc: vpc,
      description: 'Security group for FSx file system',
      allowAllOutbound: true,
    });

    // Allow NFS traffic within the security group
    securityGroup.addIngressRule(
      securityGroup,
      ec2.Port.tcp(2049),
      'Allow NFS access within security group'
    );

    // Allow SSH for management (optional)
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access for management'
    );

    return { vpc, securityGroup };
  }

  /**
   * Creates S3 bucket for storing cost reports
   */
  private createReportsBucket(): s3.Bucket {
    return new s3.Bucket(this, 'CostReportsBucket', {
      bucketName: `fsx-lifecycle-reports-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
      versioned: true,
      lifecycleRules: [
        {
          id: 'DeleteOldReports',
          expiration: cdk.Duration.days(90),
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });
  }

  /**
   * Creates SNS topic for notifications
   */
  private createNotificationTopic(notificationEmail?: string): sns.Topic {
    const topic = new sns.Topic(this, 'FsxLifecycleAlerts', {
      topicName: `fsx-lifecycle-alerts-${this.stackName}`,
      displayName: 'FSx Lifecycle Management Alerts',
    });

    // Add email subscription if provided
    if (notificationEmail) {
      topic.addSubscription(new subscriptions.EmailSubscription(notificationEmail));
    }

    return topic;
  }

  /**
   * Creates IAM execution role for Lambda functions
   */
  private createLambdaExecutionRole(): iam.Role {
    const role = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add custom policy for FSx and other AWS services
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'fsx:DescribeFileSystems',
        'fsx:DescribeVolumes',
        'fsx:PutFileSystemPolicy',
        'cloudwatch:GetMetricStatistics',
        'cloudwatch:PutMetricData',
        'sns:Publish',
        's3:PutObject',
        's3:GetObject',
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
      ],
      resources: ['*'],
    }));

    return role;
  }

  /**
   * Creates Amazon FSx for OpenZFS file system
   */
  private createFsxFileSystem(
    vpc: ec2.IVpc,
    securityGroup: ec2.SecurityGroup,
    config: FsxConfiguration
  ): fsx.CfnFileSystem {
    const subnets = vpc.privateSubnets.length > 0 ? vpc.privateSubnets : vpc.publicSubnets;
    
    const fileSystem = new fsx.CfnFileSystem(this, 'FsxFileSystem', {
      fileSystemType: 'OpenZFS',
      storageCapacity: config.storageCapacity,
      storageType: 'SSD',
      subnetIds: [subnets[0].subnetId],
      securityGroupIds: [securityGroup.securityGroupId],
      openZfsConfiguration: {
        throughputCapacity: config.throughputCapacity,
        readCacheConfig: {
          sizeGiB: config.cacheSize,
        },
        deploymentType: 'SINGLE_AZ_1',
        automaticBackupRetentionDays: 7,
        dailyAutomaticBackupStartTime: '05:00',
        weeklyMaintenanceStartTime: '1:06:00',
      },
      tags: [
        {
          key: 'Name',
          value: `fsx-lifecycle-${this.stackName}`,
        },
      ],
    });

    return fileSystem;
  }

  /**
   * Creates Lambda function for lifecycle policy management
   */
  private createLifecyclePolicyFunction(role: iam.Role, topic: sns.Topic): lambda.Function {
    const functionCode = `
import json
import boto3
import datetime
from typing import Dict, List

def lambda_handler(event, context):
    """
    Monitor FSx metrics and adjust lifecycle policies based on access patterns
    """
    fsx_client = boto3.client('fsx')
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    try:
        # Get FSx file system information
        file_systems = fsx_client.describe_file_systems()
        
        for fs in file_systems['FileSystems']:
            if fs['FileSystemType'] == 'OpenZFS':
                fs_id = fs['FileSystemId']
                
                # Get cache hit ratio metric
                cache_metrics = get_cache_metrics(cloudwatch, fs_id)
                
                # Get storage utilization metrics
                storage_metrics = get_storage_metrics(cloudwatch, fs_id)
                
                # Analyze access patterns
                recommendations = analyze_access_patterns(cache_metrics, storage_metrics)
                
                # Send recommendations via SNS
                send_notifications(sns, fs_id, recommendations)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Lifecycle policy analysis completed')
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def get_cache_metrics(cloudwatch, file_system_id: str) -> Dict:
    """Get FSx cache hit ratio metrics"""
    end_time = datetime.datetime.utcnow()
    start_time = end_time - datetime.timedelta(hours=1)
    
    try:
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/FSx',
            MetricName='FileServerCacheHitRatio',
            Dimensions=[
                {
                    'Name': 'FileSystemId',
                    'Value': file_system_id
                }
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average']
        )
        return response['Datapoints']
    except Exception as e:
        print(f"Error getting cache metrics: {e}")
        return []

def get_storage_metrics(cloudwatch, file_system_id: str) -> Dict:
    """Get FSx storage utilization metrics"""
    end_time = datetime.datetime.utcnow()
    start_time = end_time - datetime.timedelta(hours=1)
    
    try:
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/FSx',
            MetricName='StorageUtilization',
            Dimensions=[
                {
                    'Name': 'FileSystemId',
                    'Value': file_system_id
                }
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average']
        )
        return response['Datapoints']
    except Exception as e:
        print(f"Error getting storage metrics: {e}")
        return []

def analyze_access_patterns(cache_metrics: List[Dict], storage_metrics: List[Dict]) -> Dict:
    """Analyze metrics to generate recommendations"""
    recommendations = {
        'cache_recommendation': 'No data available',
        'storage_recommendation': 'No data available',
        'actions': []
    }
    
    # Analyze cache hit ratio
    if cache_metrics:
        avg_cache_hit = sum(point['Average'] for point in cache_metrics) / len(cache_metrics)
        recommendations['cache_hit_ratio'] = avg_cache_hit
        
        if avg_cache_hit < 70:
            recommendations['cache_recommendation'] = 'Consider increasing SSD cache size'
            recommendations['actions'].append('scale_cache')
        elif avg_cache_hit > 95:
            recommendations['cache_recommendation'] = 'Cache size may be oversized'
            recommendations['actions'].append('optimize_cache')
        else:
            recommendations['cache_recommendation'] = 'Cache performance optimal'
            recommendations['actions'].append('maintain')
    
    # Analyze storage utilization
    if storage_metrics:
        avg_storage = sum(point['Average'] for point in storage_metrics) / len(storage_metrics)
        recommendations['storage_utilization'] = avg_storage
        
        if avg_storage > 85:
            recommendations['storage_recommendation'] = 'High storage utilization detected'
            recommendations['actions'].append('monitor_capacity')
        elif avg_storage < 30:
            recommendations['storage_recommendation'] = 'Low storage utilization - consider downsizing'
            recommendations['actions'].append('optimize_capacity')
        else:
            recommendations['storage_recommendation'] = 'Storage utilization optimal'
    
    return recommendations

def send_notifications(sns, file_system_id: str, recommendations: Dict):
    """Send recommendations via SNS"""
    import os
    
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    if topic_arn:
        message = f"""
        FSx File System: {file_system_id}
        
        Cache Recommendation: {recommendations['cache_recommendation']}
        Storage Recommendation: {recommendations['storage_recommendation']}
        
        Cache Hit Ratio: {recommendations.get('cache_hit_ratio', 'N/A')}%
        Storage Utilization: {recommendations.get('storage_utilization', 'N/A')}%
        
        Suggested Actions: {', '.join(recommendations.get('actions', []))}
        """
        
        sns.publish(
            TopicArn=topic_arn,
            Message=message,
            Subject='FSx Lifecycle Policy Recommendation'
        )
`;

    return new lambda.Function(this, 'LifecyclePolicyFunction', {
      functionName: `fsx-lifecycle-policy-${this.stackName}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      code: lambda.Code.fromInline(functionCode),
      handler: 'index.lambda_handler',
      role: role,
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      environment: {
        SNS_TOPIC_ARN: topic.topicArn,
      },
      description: 'Analyzes FSx metrics and provides lifecycle policy recommendations',
    });
  }

  /**
   * Creates Lambda function for cost reporting
   */
  private createCostReportingFunction(role: iam.Role, bucket: s3.Bucket): lambda.Function {
    const functionCode = `
import json
import boto3
import datetime
import csv
from io import StringIO

def lambda_handler(event, context):
    """
    Generate cost optimization reports for FSx file systems
    """
    fsx_client = boto3.client('fsx')
    cloudwatch = boto3.client('cloudwatch')
    s3 = boto3.client('s3')
    
    try:
        # Get FSx file systems
        file_systems = fsx_client.describe_file_systems()
        
        for fs in file_systems['FileSystems']:
            if fs['FileSystemType'] == 'OpenZFS':
                fs_id = fs['FileSystemId']
                
                # Collect usage metrics
                usage_data = collect_usage_metrics(cloudwatch, fs_id)
                
                # Generate cost report
                report = generate_cost_report(fs, usage_data)
                
                # Save report to S3
                save_report_to_s3(s3, fs_id, report)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Cost reports generated successfully')
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def collect_usage_metrics(cloudwatch, file_system_id: str) -> dict:
    """Collect various usage metrics for cost analysis"""
    end_time = datetime.datetime.utcnow()
    start_time = end_time - datetime.timedelta(days=7)
    
    metrics = {}
    
    # Storage capacity and utilization metrics
    for metric_name in ['StorageUtilization', 'FileServerCacheHitRatio']:
        try:
            response = cloudwatch.get_metric_statistics(
                Namespace='AWS/FSx',
                MetricName=metric_name,
                Dimensions=[
                    {
                        'Name': 'FileSystemId',
                        'Value': file_system_id
                    }
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=3600,
                Statistics=['Average']
            )
            metrics[metric_name] = response['Datapoints']
        except Exception as e:
            print(f"Error collecting {metric_name}: {e}")
            metrics[metric_name] = []
    
    return metrics

def generate_cost_report(file_system: dict, usage_data: dict) -> dict:
    """Generate comprehensive cost optimization report"""
    fs_id = file_system['FileSystemId']
    storage_capacity = file_system['StorageCapacity']
    throughput_capacity = file_system['OpenZFSConfiguration']['ThroughputCapacity']
    
    # Calculate estimated costs based on current pricing
    # Base throughput cost: approximately $0.30 per MBps/month
    base_throughput_cost = throughput_capacity * 0.30
    
    # Storage cost: approximately $0.15 per GiB/month for SSD
    storage_cost = storage_capacity * 0.15
    
    monthly_cost = base_throughput_cost + storage_cost
    
    # Storage efficiency analysis
    storage_metrics = usage_data.get('StorageUtilization', [])
    avg_utilization = 0
    if storage_metrics:
        avg_utilization = sum(point['Average'] for point in storage_metrics) / len(storage_metrics)
    
    # Cache performance analysis
    cache_metrics = usage_data.get('FileServerCacheHitRatio', [])
    avg_cache_hit = 0
    if cache_metrics:
        avg_cache_hit = sum(point['Average'] for point in cache_metrics) / len(cache_metrics)
    
    report = {
        'file_system_id': fs_id,
        'report_date': datetime.datetime.utcnow().isoformat(),
        'storage_capacity_gb': storage_capacity,
        'throughput_capacity_mbps': throughput_capacity,
        'estimated_monthly_cost': monthly_cost,
        'storage_efficiency': {
            'average_utilization': avg_utilization,
            'cache_hit_ratio': avg_cache_hit,
            'optimization_potential': max(0, 100 - avg_utilization)
        },
        'recommendations': []
    }
    
    # Generate recommendations
    if avg_utilization < 50:
        potential_savings = storage_capacity * 0.15 * 0.3  # 30% potential savings
        report['recommendations'].append({
            'type': 'storage_optimization',
            'description': 'Low storage utilization - consider reducing capacity',
            'potential_savings': f"${potential_savings:.2f}/month"
        })
    
    if avg_cache_hit < 70:
        report['recommendations'].append({
            'type': 'cache_optimization',
            'description': 'Low cache hit ratio - consider increasing cache size',
            'impact': 'Improved performance and reduced latency'
        })
    
    if avg_utilization > 90:
        report['recommendations'].append({
            'type': 'capacity_expansion',
            'description': 'High storage utilization - consider increasing capacity',
            'impact': 'Prevent capacity issues and maintain performance'
        })
    
    return report

def save_report_to_s3(s3, file_system_id: str, report: dict):
    """Save cost report to S3"""
    import os
    
    bucket_name = os.environ.get('S3_BUCKET_NAME')
    if not bucket_name:
        return
    
    # Create CSV report
    csv_buffer = StringIO()
    writer = csv.writer(csv_buffer)
    
    writer.writerow(['Metric', 'Value'])
    writer.writerow(['File System ID', report['file_system_id']])
    writer.writerow(['Report Date', report['report_date']])
    writer.writerow(['Storage Capacity (GB)', report['storage_capacity_gb']])
    writer.writerow(['Throughput Capacity (MBps)', report['throughput_capacity_mbps']])
    writer.writerow(['Estimated Monthly Cost', f"${report['estimated_monthly_cost']:.2f}"])
    writer.writerow(['Average Utilization (%)', f"{report['storage_efficiency']['average_utilization']:.1f}"])
    writer.writerow(['Cache Hit Ratio (%)', f"{report['storage_efficiency']['cache_hit_ratio']:.1f}"])
    
    # Add recommendations
    writer.writerow([])
    writer.writerow(['Recommendations'])
    for rec in report['recommendations']:
        writer.writerow([rec['type'], rec['description']])
    
    # Save to S3
    timestamp = datetime.datetime.utcnow().strftime('%Y%m%d_%H%M%S')
    key = f"cost-reports/{file_system_id}/report_{timestamp}.csv"
    
    s3.put_object(
        Bucket=bucket_name,
        Key=key,
        Body=csv_buffer.getvalue(),
        ContentType='text/csv'
    )
    
    print(f"Report saved to s3://{bucket_name}/{key}")
`;

    return new lambda.Function(this, 'CostReportingFunction', {
      functionName: `fsx-cost-reporting-${this.stackName}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      code: lambda.Code.fromInline(functionCode),
      handler: 'index.lambda_handler',
      role: role,
      timeout: cdk.Duration.seconds(120),
      memorySize: 512,
      environment: {
        S3_BUCKET_NAME: bucket.bucketName,
      },
      description: 'Generates cost optimization reports for FSx file systems',
    });
  }

  /**
   * Creates Lambda function for alert handling
   */
  private createAlertHandlerFunction(role: iam.Role, topic: sns.Topic, fileSystem: fsx.CfnFileSystem): lambda.Function {
    const functionCode = `
import json
import boto3
import urllib.parse

def lambda_handler(event, context):
    """
    Handle CloudWatch alarms and provide intelligent analysis
    """
    fsx_client = boto3.client('fsx')
    sns = boto3.client('sns')
    
    try:
        # Parse SNS message
        sns_message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = sns_message['AlarmName']
        new_state = sns_message['NewStateValue']
        
        if new_state == 'ALARM':
            if 'Low-Cache-Hit-Ratio' in alarm_name:
                handle_low_cache_hit_ratio(fsx_client, sns, alarm_name)
            elif 'High-Storage-Utilization' in alarm_name:
                handle_high_storage_utilization(fsx_client, sns, alarm_name)
            elif 'High-Network-Utilization' in alarm_name:
                handle_high_network_utilization(fsx_client, sns, alarm_name)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Alert processed successfully')
        }
        
    except Exception as e:
        print(f"Error processing alert: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def handle_low_cache_hit_ratio(fsx_client, sns, alarm_name):
    """Handle low cache hit ratio alarm"""
    fs_id = get_file_system_id()
    
    # Get current file system configuration
    response = fsx_client.describe_file_systems(FileSystemIds=[fs_id])
    fs = response['FileSystems'][0]
    
    # Get cache configuration
    cache_config = fs['OpenZFSConfiguration'].get('ReadCacheConfig', {})
    current_cache = cache_config.get('SizeGiB', 0)
    
    message = f"""
    Performance Alert: Low Cache Hit Ratio Detected
    
    File System: {fs_id}
    Current Cache Size: {current_cache} GiB
    
    Recommendations:
    1. Consider increasing SSD read cache size to improve performance
    2. Analyze workload patterns to optimize cache configuration
    3. Review client access patterns for optimization opportunities
    
    Impact: Low cache hit ratio may indicate increased latency and reduced throughput
    
    Next Steps: Review FSx performance metrics and consider cache optimization
    """
    
    send_notification(sns, message, 'FSx Cache Performance Alert')

def handle_high_storage_utilization(fsx_client, sns, alarm_name):
    """Handle high storage utilization alarm"""
    fs_id = get_file_system_id()
    
    # Get current file system configuration
    response = fsx_client.describe_file_systems(FileSystemIds=[fs_id])
    fs = response['FileSystems'][0]
    
    storage_capacity = fs['StorageCapacity']
    
    message = f"""
    Capacity Alert: High Storage Utilization Detected
    
    File System: {fs_id}
    Storage Capacity: {storage_capacity} GiB
    Utilization: Above 85% threshold
    
    Recommendations:
    1. Review data retention policies and archive old files
    2. Consider increasing storage capacity if needed
    3. Implement file lifecycle management policies
    4. Analyze storage usage patterns for optimization
    
    Impact: High utilization may affect performance and prevent new file creation
    
    Next Steps: Review storage usage and plan capacity expansion if needed
    """
    
    send_notification(sns, message, 'FSx Storage Capacity Alert')

def handle_high_network_utilization(fsx_client, sns, alarm_name):
    """Handle high network utilization alarm"""
    fs_id = get_file_system_id()
    
    # Get current file system configuration
    response = fsx_client.describe_file_systems(FileSystemIds=[fs_id])
    fs = response['FileSystems'][0]
    
    throughput_capacity = fs['OpenZFSConfiguration']['ThroughputCapacity']
    
    message = f"""
    Performance Alert: High Network Utilization Detected
    
    File System: {fs_id}
    Throughput Capacity: {throughput_capacity} MBps
    Utilization: Above 90% threshold
    
    Recommendations:
    1. Consider increasing throughput capacity for better performance
    2. Optimize client access patterns and connection pooling
    3. Review workload distribution across multiple clients
    4. Implement caching strategies at the client level
    
    Impact: High network utilization may cause performance bottlenecks
    
    Next Steps: Monitor performance trends and consider scaling throughput capacity
    """
    
    send_notification(sns, message, 'FSx Network Performance Alert')

def get_file_system_id():
    """Get file system ID from environment"""
    import os
    return os.environ.get('FSX_FILE_SYSTEM_ID', 'unknown')

def send_notification(sns, message, subject):
    """Send notification via SNS"""
    import os
    
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    if topic_arn:
        sns.publish(
            TopicArn=topic_arn,
            Message=message,
            Subject=subject
        )
`;

    const alertHandler = new lambda.Function(this, 'AlertHandlerFunction', {
      functionName: `fsx-alert-handler-${this.stackName}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      code: lambda.Code.fromInline(functionCode),
      handler: 'index.lambda_handler',
      role: role,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        SNS_TOPIC_ARN: topic.topicArn,
        FSX_FILE_SYSTEM_ID: fileSystem.ref,
      },
      description: 'Handles CloudWatch alarms and provides intelligent analysis',
    });

    // Subscribe the alert handler to SNS topic
    topic.addSubscription(new subscriptions.LambdaSubscription(alertHandler));

    return alertHandler;
  }

  /**
   * Creates EventBridge rules for automation
   */
  private createEventBridgeRules(config: AutomationConfiguration): void {
    // Rule for periodic lifecycle policy analysis
    const lifecyclePolicyRule = new events.Rule(this, 'LifecyclePolicySchedule', {
      schedule: events.Schedule.expression(config.lifecyclePolicySchedule),
      description: 'Trigger lifecycle policy analysis',
    });

    lifecyclePolicyRule.addTarget(new targets.LambdaFunction(this.lifecyclePolicyFunction));

    // Rule for daily cost reporting
    const costReportingRule = new events.Rule(this, 'CostReportingSchedule', {
      schedule: events.Schedule.expression(config.costReportingSchedule),
      description: 'Generate cost reports',
    });

    costReportingRule.addTarget(new targets.LambdaFunction(this.costReportingFunction));
  }

  /**
   * Creates CloudWatch alarms for FSx monitoring
   */
  private createCloudWatchAlarms(
    config: MonitoringConfiguration,
    fileSystem: fsx.CfnFileSystem,
    topic: sns.Topic
  ): void {
    // Alarm for low cache hit ratio
    const cacheHitRatioAlarm = new cloudwatch.Alarm(this, 'LowCacheHitRatioAlarm', {
      alarmName: `FSx-Low-Cache-Hit-Ratio-${this.stackName}`,
      alarmDescription: 'Alert when FSx cache hit ratio is below threshold',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/FSx',
        metricName: 'FileServerCacheHitRatio',
        dimensionsMap: {
          FileSystemId: fileSystem.ref,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: config.cacheHitRatioThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 2,
    });

    cacheHitRatioAlarm.addAlarmAction(new cloudwatchActions.SnsAction(topic));

    // Alarm for high storage utilization
    const storageUtilizationAlarm = new cloudwatch.Alarm(this, 'HighStorageUtilizationAlarm', {
      alarmName: `FSx-High-Storage-Utilization-${this.stackName}`,
      alarmDescription: 'Alert when FSx storage utilization exceeds threshold',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/FSx',
        metricName: 'StorageUtilization',
        dimensionsMap: {
          FileSystemId: fileSystem.ref,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: config.storageUtilizationThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
    });

    storageUtilizationAlarm.addAlarmAction(new cloudwatchActions.SnsAction(topic));

    // Alarm for high network utilization
    const networkUtilizationAlarm = new cloudwatch.Alarm(this, 'HighNetworkUtilizationAlarm', {
      alarmName: `FSx-High-Network-Utilization-${this.stackName}`,
      alarmDescription: 'Alert when FSx network utilization exceeds threshold',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/FSx',
        metricName: 'NetworkThroughputUtilization',
        dimensionsMap: {
          FileSystemId: fileSystem.ref,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: config.networkUtilizationThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
    });

    networkUtilizationAlarm.addAlarmAction(new cloudwatchActions.SnsAction(topic));
  }

  /**
   * Creates CloudWatch dashboard for visualization
   */
  private createCloudWatchDashboard(fileSystem: fsx.CfnFileSystem): void {
    const dashboard = new cloudwatch.Dashboard(this, 'FsxLifecycleDashboard', {
      dashboardName: `FSx-Lifecycle-Management-${this.stackName}`,
    });

    // Performance metrics widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'FSx Performance Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/FSx',
            metricName: 'FileServerCacheHitRatio',
            dimensionsMap: {
              FileSystemId: fileSystem.ref,
            },
            statistic: 'Average',
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/FSx',
            metricName: 'StorageUtilization',
            dimensionsMap: {
              FileSystemId: fileSystem.ref,
            },
            statistic: 'Average',
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/FSx',
            metricName: 'NetworkThroughputUtilization',
            dimensionsMap: {
              FileSystemId: fileSystem.ref,
            },
            statistic: 'Average',
          }),
        ],
        width: 12,
        height: 6,
      })
    );

    // Data transfer widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'FSx Data Transfer',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/FSx',
            metricName: 'DataReadBytes',
            dimensionsMap: {
              FileSystemId: fileSystem.ref,
            },
            statistic: 'Sum',
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/FSx',
            metricName: 'DataWriteBytes',
            dimensionsMap: {
              FileSystemId: fileSystem.ref,
            },
            statistic: 'Sum',
          }),
        ],
        width: 12,
        height: 6,
      })
    );

    // Latency metrics widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'FSx Latency Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/FSx',
            metricName: 'TotalReadTime',
            dimensionsMap: {
              FileSystemId: fileSystem.ref,
            },
            statistic: 'Average',
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/FSx',
            metricName: 'TotalWriteTime',
            dimensionsMap: {
              FileSystemId: fileSystem.ref,
            },
            statistic: 'Average',
          }),
        ],
        width: 24,
        height: 6,
      })
    );
  }

  /**
   * Creates CloudFormation outputs for important resources
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'FsxFileSystemId', {
      value: this.fsxFileSystem.ref,
      description: 'FSx File System ID',
      exportName: `${this.stackName}-FsxFileSystemId`,
    });

    new cdk.CfnOutput(this, 'FsxFileSystemDnsName', {
      value: this.fsxFileSystem.attrDnsName,
      description: 'FSx File System DNS Name',
      exportName: `${this.stackName}-FsxFileSystemDnsName`,
    });

    new cdk.CfnOutput(this, 'LifecyclePolicyFunctionArn', {
      value: this.lifecyclePolicyFunction.functionArn,
      description: 'Lifecycle Policy Lambda Function ARN',
      exportName: `${this.stackName}-LifecyclePolicyFunctionArn`,
    });

    new cdk.CfnOutput(this, 'CostReportingFunctionArn', {
      value: this.costReportingFunction.functionArn,
      description: 'Cost Reporting Lambda Function ARN',
      exportName: `${this.stackName}-CostReportingFunctionArn`,
    });

    new cdk.CfnOutput(this, 'AlertHandlerFunctionArn', {
      value: this.alertHandlerFunction.functionArn,
      description: 'Alert Handler Lambda Function ARN',
      exportName: `${this.stackName}-AlertHandlerFunctionArn`,
    });

    new cdk.CfnOutput(this, 'SnsTopicArn', {
      value: this.snsTopic.topicArn,
      description: 'SNS Topic ARN for notifications',
      exportName: `${this.stackName}-SnsTopicArn`,
    });

    new cdk.CfnOutput(this, 'ReportsBucketName', {
      value: this.reportsBucket.bucketName,
      description: 'S3 Bucket for cost reports',
      exportName: `${this.stackName}-ReportsBucketName`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=FSx-Lifecycle-Management-${this.stackName}`,
      description: 'CloudWatch Dashboard URL',
    });
  }
}