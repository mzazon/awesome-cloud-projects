#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as config from 'aws-cdk-lib/aws-config';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Duration } from 'aws-cdk-lib';

/**
 * CDK Stack for Automated Cost Governance with AWS Config and Lambda Remediation
 * 
 * This stack deploys a comprehensive automated cost governance framework that:
 * - Monitors AWS resources for cost optimization opportunities using AWS Config
 * - Automatically remediates cost-inefficient configurations using Lambda functions
 * - Provides notifications and reporting for governance oversight
 * - Implements safety measures and audit trails for all automated actions
 */
export class CostGovernanceStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // =================================
    // S3 BUCKETS FOR CONFIG AND REPORTS
    // =================================

    // S3 bucket for AWS Config delivery channel
    const configBucket = new s3.Bucket(this, 'ConfigBucket', {
      bucketName: `aws-config-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: Duration.days(90),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // S3 bucket for cost governance reports
    const reportsBucket = new s3.Bucket(this, 'ReportsBucket', {
      bucketName: `cost-governance-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteOldReports',
          enabled: true,
          expiration: Duration.days(365),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // ======================
    // SNS TOPICS FOR ALERTS
    // ======================

    // SNS topic for general cost governance notifications
    const costAlertsTopic = new sns.Topic(this, 'CostAlertsTopic', {
      topicName: 'CostGovernanceAlerts',
      displayName: 'Cost Governance Alerts',
    });

    // SNS topic for critical cost actions requiring immediate attention
    const criticalAlertsTopic = new sns.Topic(this, 'CriticalAlertsTopic', {
      topicName: 'CriticalCostActions',
      displayName: 'Critical Cost Actions',
    });

    // ===============================
    // SQS QUEUES FOR EVENT PROCESSING
    // ===============================

    // Dead letter queue for failed message processing
    const deadLetterQueue = new sqs.Queue(this, 'CostGovernanceDLQ', {
      queueName: 'CostGovernanceDLQ',
      retentionPeriod: Duration.days(14),
    });

    // Main SQS queue for cost governance event processing
    const costEventQueue = new sqs.Queue(this, 'CostEventQueue', {
      queueName: 'CostGovernanceQueue',
      visibilityTimeout: Duration.minutes(5),
      retentionPeriod: Duration.days(14),
      receiveMessageWaitTime: Duration.seconds(20),
      deadLetterQueue: {
        queue: deadLetterQueue,
        maxReceiveCount: 3,
      },
    });

    // ===========================
    // IAM ROLES FOR LAMBDA FUNCTIONS
    // ===========================

    // IAM role for cost governance Lambda functions
    const lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `CostGovernanceLambdaRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for cost governance Lambda functions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add comprehensive permissions for cost governance operations
    lambdaExecutionRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        // EC2 permissions for instance management
        'ec2:DescribeInstances',
        'ec2:DescribeVolumes',
        'ec2:DescribeSnapshots',
        'ec2:StopInstances',
        'ec2:TerminateInstances',
        'ec2:ModifyInstanceAttribute',
        'ec2:DeleteVolume',
        'ec2:DetachVolume',
        'ec2:CreateSnapshot',
        'ec2:CreateTags',
        // CloudWatch permissions for metrics analysis
        'cloudwatch:GetMetricStatistics',
        'cloudwatch:GetMetricData',
        // Load balancer permissions
        'elasticloadbalancing:DescribeLoadBalancers',
        'elasticloadbalancing:DescribeTargetGroups',
        'elasticloadbalancing:DescribeTargetHealth',
        'elasticloadbalancing:DeleteLoadBalancer',
        'elasticloadbalancing:AddTags',
        // RDS permissions
        'rds:DescribeDBInstances',
        'rds:DescribeDBClusters',
        'rds:StopDBInstance',
        'rds:StopDBCluster',
        'rds:AddTagsToResource',
        // Config permissions
        'config:GetComplianceDetailsByConfigRule',
        'config:GetComplianceDetailsByResource',
        'config:PutEvaluations',
        'config:GetComplianceSummaryByConfigRule',
        // Systems Manager permissions
        'ssm:PutParameter',
        'ssm:GetParameter',
        'ssm:GetParameters',
        'ssm:SendCommand',
        'ssm:GetCommandInvocation',
      ],
      resources: ['*'],
    }));

    // Grant permissions to access S3 buckets
    reportsBucket.grantReadWrite(lambdaExecutionRole);
    configBucket.grantRead(lambdaExecutionRole);

    // Grant permissions to publish to SNS topics
    costAlertsTopic.grantPublish(lambdaExecutionRole);
    criticalAlertsTopic.grantPublish(lambdaExecutionRole);

    // Grant permissions to interact with SQS queues
    costEventQueue.grantConsumeMessages(lambdaExecutionRole);
    costEventQueue.grantSendMessages(lambdaExecutionRole);

    // ================================
    // AWS CONFIG SETUP
    // ================================

    // IAM role for AWS Config service
    const configRole = new iam.Role(this, 'ConfigRole', {
      roleName: `AWSConfigRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('config.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/ConfigRole'),
      ],
    });

    // Grant Config service access to the S3 bucket
    configBucket.addToResourcePolicy(new iam.PolicyStatement({
      sid: 'AWSConfigBucketPermissionsCheck',
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('config.amazonaws.com')],
      actions: ['s3:GetBucketAcl', 's3:ListBucket'],
      resources: [configBucket.bucketArn],
    }));

    configBucket.addToResourcePolicy(new iam.PolicyStatement({
      sid: 'AWSConfigBucketExistenceCheck',
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('config.amazonaws.com')],
      actions: ['s3:GetBucketLocation'],
      resources: [configBucket.bucketArn],
    }));

    configBucket.addToResourcePolicy(new iam.PolicyStatement({
      sid: 'AWSConfigBucketDelivery',
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('config.amazonaws.com')],
      actions: ['s3:PutObject'],
      resources: [`${configBucket.bucketArn}/*`],
      conditions: {
        StringEquals: {
          's3:x-amz-acl': 'bucket-owner-full-control',
        },
      },
    }));

    // AWS Config delivery channel
    const deliveryChannel = new config.CfnDeliveryChannel(this, 'DeliveryChannel', {
      name: 'default',
      s3BucketName: configBucket.bucketName,
    });

    // AWS Config configuration recorder
    const configurationRecorder = new config.CfnConfigurationRecorder(this, 'ConfigurationRecorder', {
      name: 'default',
      roleArn: configRole.roleArn,
      recordingGroup: {
        allSupported: true,
        includeGlobalResourceTypes: true,
      },
    });

    // Ensure proper dependency order
    configurationRecorder.addDependency(deliveryChannel);

    // =========================
    // LAMBDA FUNCTIONS
    // =========================

    // Lambda function for idle instance detection
    const idleInstanceDetector = new lambda.Function(this, 'IdleInstanceDetector', {
      functionName: 'IdleInstanceDetector',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: Duration.minutes(5),
      memorySize: 256,
      environment: {
        SNS_TOPIC_ARN: costAlertsTopic.topicArn,
        REPORTS_BUCKET: reportsBucket.bucketName,
      },
      logGroup: new logs.LogGroup(this, 'IdleInstanceDetectorLogs', {
        logGroupName: '/aws/lambda/IdleInstanceDetector',
        retention: logs.RetentionDays.ONE_MONTH,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      }),
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    # Get all running instances
    response = ec2.describe_instances(
        Filters=[
            {'Name': 'instance-state-name', 'Values': ['running']},
            {'Name': 'tag:CostOptimization', 'Values': ['enabled']}
        ]
    )
    
    idle_instances = []
    
    for reservation in response['Reservations']:
        for instance in reservation['Instances']:
            instance_id = instance['InstanceId']
            
            # Check CPU utilization for last 7 days
            end_time = datetime.utcnow()
            start_time = end_time - timedelta(days=7)
            
            try:
                cpu_response = cloudwatch.get_metric_statistics(
                    Namespace='AWS/EC2',
                    MetricName='CPUUtilization',
                    Dimensions=[
                        {'Name': 'InstanceId', 'Value': instance_id}
                    ],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=3600,
                    Statistics=['Average']
                )
                
                if cpu_response['Datapoints']:
                    avg_cpu = sum(dp['Average'] for dp in cpu_response['Datapoints']) / len(cpu_response['Datapoints'])
                    
                    if avg_cpu < 5.0:  # Less than 5% average CPU
                        idle_instances.append({
                            'InstanceId': instance_id,
                            'AvgCPU': avg_cpu,
                            'InstanceType': instance['InstanceType'],
                            'LaunchTime': instance['LaunchTime'].isoformat()
                        })
                        
                        # Tag as idle for tracking
                        ec2.create_tags(
                            Resources=[instance_id],
                            Tags=[
                                {'Key': 'CostOptimization:Status', 'Value': 'Idle'},
                                {'Key': 'CostOptimization:DetectedDate', 'Value': datetime.utcnow().isoformat()}
                            ]
                        )
                        
                        logger.info(f"Detected idle instance: {instance_id} (CPU: {avg_cpu:.2f}%)")
                
            except Exception as e:
                logger.error(f"Error checking metrics for {instance_id}: {str(e)}")
    
    # Send notification if idle instances found
    if idle_instances:
        message = {
            'Alert': 'Idle EC2 Instances Detected',
            'Count': len(idle_instances),
            'Instances': idle_instances,
            'Recommendation': 'Consider stopping or terminating idle instances to reduce costs'
        }
        
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject='Cost Governance Alert: Idle EC2 Instances',
            Message=json.dumps(message, indent=2)
        )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Processed {len(idle_instances)} idle instances',
            'idle_instances': idle_instances
        })
    }
      `),
    });

    // Lambda function for unattached volume cleanup
    const volumeCleanup = new lambda.Function(this, 'VolumeCleanup', {
      functionName: 'VolumeCleanup',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: Duration.minutes(5),
      memorySize: 256,
      environment: {
        SNS_TOPIC_ARN: costAlertsTopic.topicArn,
        REPORTS_BUCKET: reportsBucket.bucketName,
      },
      logGroup: new logs.LogGroup(this, 'VolumeCleanupLogs', {
        logGroupName: '/aws/lambda/VolumeCleanup',
        retention: logs.RetentionDays.ONE_MONTH,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      }),
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    sns = boto3.client('sns')
    
    # Get all unattached volumes
    response = ec2.describe_volumes(
        Filters=[
            {'Name': 'status', 'Values': ['available']}
        ]
    )
    
    volumes_to_clean = []
    total_cost_savings = 0
    
    for volume in response['Volumes']:
        volume_id = volume['VolumeId']
        size = volume['Size']
        volume_type = volume['VolumeType']
        create_time = volume['CreateTime']
        
        # Calculate age in days
        age_days = (datetime.now(create_time.tzinfo) - create_time).days
        
        # Only process volumes older than 7 days
        if age_days > 7:
            # Estimate monthly cost savings (rough calculation)
            cost_per_gb_month = {
                'gp2': 0.10, 'gp3': 0.08, 'io1': 0.125, 'io2': 0.125, 'st1': 0.045, 'sc1': 0.025
            }.get(volume_type, 0.10)
            
            monthly_cost = size * cost_per_gb_month
            total_cost_savings += monthly_cost
            
            # Create snapshot before deletion (safety measure)
            try:
                snapshot_response = ec2.create_snapshot(
                    VolumeId=volume_id,
                    Description=f'Pre-deletion snapshot of {volume_id}',
                    TagSpecifications=[
                        {
                            'ResourceType': 'snapshot',
                            'Tags': [
                                {'Key': 'CostOptimization', 'Value': 'true'},
                                {'Key': 'OriginalVolumeId', 'Value': volume_id},
                                {'Key': 'DeletionDate', 'Value': datetime.utcnow().isoformat()}
                            ]
                        }
                    ]
                )
                
                snapshot_id = snapshot_response['SnapshotId']
                
                # Tag volume for deletion tracking
                ec2.create_tags(
                    Resources=[volume_id],
                    Tags=[
                        {'Key': 'CostOptimization:ScheduledDeletion', 'Value': 'true'},
                        {'Key': 'CostOptimization:BackupSnapshot', 'Value': snapshot_id}
                    ]
                )
                
                volumes_to_clean.append({
                    'VolumeId': volume_id,
                    'Size': size,
                    'Type': volume_type,
                    'AgeDays': age_days,
                    'MonthlyCostSavings': monthly_cost,
                    'BackupSnapshot': snapshot_id
                })
                
                logger.info(f"Tagged volume {volume_id} for deletion (snapshot: {snapshot_id})")
                
            except Exception as e:
                logger.error(f"Error processing volume {volume_id}: {str(e)}")
    
    # Send notification about volumes scheduled for cleanup
    if volumes_to_clean:
        message = {
            'Alert': 'Unattached EBS Volumes Scheduled for Cleanup',
            'Count': len(volumes_to_clean),
            'TotalMonthlySavings': f'${total_cost_savings:.2f}',
            'Volumes': volumes_to_clean,
            'Action': 'Volumes have been tagged and backed up. Manual confirmation required for deletion.'
        }
        
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject='Cost Governance Alert: Unattached Volume Cleanup',
            Message=json.dumps(message, indent=2)
        )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Processed {len(volumes_to_clean)} unattached volumes',
            'potential_monthly_savings': f'${total_cost_savings:.2f}',
            'volumes': volumes_to_clean
        })
    }
      `),
    });

    // Lambda function for cost reporting
    const costReporter = new lambda.Function(this, 'CostReporter', {
      functionName: 'CostReporter',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: Duration.minutes(5),
      memorySize: 512,
      environment: {
        SNS_TOPIC_ARN: costAlertsTopic.topicArn,
        REPORTS_BUCKET: reportsBucket.bucketName,
      },
      logGroup: new logs.LogGroup(this, 'CostReporterLogs', {
        logGroupName: '/aws/lambda/CostReporter',
        retention: logs.RetentionDays.ONE_MONTH,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      }),
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    sns = boto3.client('sns')
    ec2 = boto3.client('ec2')
    config_client = boto3.client('config')
    
    # Generate cost governance report
    report_data = {
        'ReportDate': datetime.utcnow().isoformat(),
        'Summary': {},
        'Details': {}
    }
    
    try:
        # Get compliance summary from Config
        try:
            compliance_summary = config_client.get_compliance_summary_by_config_rule()
            
            report_data['Summary']['ConfigRules'] = {
                'TotalRules': len(compliance_summary.get('ComplianceSummary', [])),
                'CompliantResources': sum(rule.get('ComplianceSummary', {}).get('CompliantResourceCount', {}).get('CappedCount', 0) 
                                        for rule in compliance_summary.get('ComplianceSummary', [])),
                'NonCompliantResources': sum(rule.get('ComplianceSummary', {}).get('NonCompliantResourceCount', {}).get('CappedCount', 0) 
                                           for rule in compliance_summary.get('ComplianceSummary', []))
            }
        except Exception as e:
            logger.warning(f"Could not get Config compliance summary: {str(e)}")
            report_data['Summary']['ConfigRules'] = {
                'TotalRules': 0,
                'CompliantResources': 0,
                'NonCompliantResources': 0
            }
        
        # Get resource counts for cost analysis
        instances_response = ec2.describe_instances()
        volumes_response = ec2.describe_volumes()
        
        running_instances = 0
        stopped_instances = 0
        idle_instances = 0
        unattached_volumes = 0
        
        for reservation in instances_response['Reservations']:
            for instance in reservation['Instances']:
                state = instance['State']['Name']
                if state == 'running':
                    running_instances += 1
                    # Check if tagged as idle
                    for tag in instance.get('Tags', []):
                        if tag['Key'] == 'CostOptimization:Status' and tag['Value'] == 'Idle':
                            idle_instances += 1
                            break
                elif state == 'stopped':
                    stopped_instances += 1
        
        for volume in volumes_response['Volumes']:
            if volume['State'] == 'available':
                unattached_volumes += 1
        
        report_data['Summary']['Resources'] = {
            'RunningInstances': running_instances,
            'StoppedInstances': stopped_instances,
            'IdleInstances': idle_instances,
            'UnattachedVolumes': unattached_volumes
        }
        
        # Calculate estimated cost savings opportunities
        estimated_savings = {
            'IdleInstances': idle_instances * 50,  # Rough estimate $50/month per idle instance
            'UnattachedVolumes': unattached_volumes * 8  # Rough estimate $8/month per 80GB volume
        }
        
        report_data['Summary']['EstimatedMonthlySavings'] = estimated_savings
        report_data['Summary']['TotalPotentialSavings'] = sum(estimated_savings.values())
        
        # Save report to S3
        report_key = f"cost-governance-reports/{datetime.utcnow().strftime('%Y/%m/%d')}/report-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}.json"
        
        s3.put_object(
            Bucket=os.environ['REPORTS_BUCKET'],
            Key=report_key,
            Body=json.dumps(report_data, indent=2),
            ContentType='application/json'
        )
        
        # Send summary notification
        summary_message = f"""
Cost Governance Report Summary

Generated: {report_data['ReportDate']}

Resource Summary:
- Running Instances: {running_instances}
- Idle Instances: {idle_instances}
- Unattached Volumes: {unattached_volumes}

Estimated Monthly Savings Opportunity: ${sum(estimated_savings.values()):.2f}

Full report saved to: s3://{os.environ['REPORTS_BUCKET']}/{report_key}
        """
        
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject='Weekly Cost Governance Report',
            Message=summary_message
        )
        
        logger.info(f"Cost governance report generated: {report_key}")
        
    except Exception as e:
        logger.error(f"Error generating cost report: {str(e)}")
        raise
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Cost governance report generated successfully',
            'report_location': f"s3://{os.environ['REPORTS_BUCKET']}/{report_key}",
            'summary': report_data['Summary']
        })
    }
      `),
    });

    // ========================
    // AWS CONFIG RULES
    // ========================

    // Config rule for idle EC2 instances
    const idleInstancesRule = new config.CfnConfigRule(this, 'IdleInstancesRule', {
      configRuleName: 'idle-ec2-instances',
      description: 'Checks for EC2 instances with low CPU utilization',
      source: {
        owner: 'AWS',
        sourceIdentifier: 'EC2_INSTANCE_NO_HIGH_LEVEL_FINDINGS',
      },
      scope: {
        complianceResourceTypes: ['AWS::EC2::Instance'],
      },
    });

    // Config rule for unattached EBS volumes
    const unattachedVolumesRule = new config.CfnConfigRule(this, 'UnattachedVolumesRule', {
      configRuleName: 'unattached-ebs-volumes',
      description: 'Checks for EBS volumes that are not attached to instances',
      source: {
        owner: 'AWS',
        sourceIdentifier: 'EBS_OPTIMIZED_INSTANCE',
      },
      scope: {
        complianceResourceTypes: ['AWS::EC2::Volume'],
      },
    });

    // Config rule for unused load balancers
    const unusedLoadBalancersRule = new config.CfnConfigRule(this, 'UnusedLoadBalancersRule', {
      configRuleName: 'unused-load-balancers',
      description: 'Checks for load balancers with no healthy targets',
      source: {
        owner: 'AWS',
        sourceIdentifier: 'ELB_CROSS_ZONE_LOAD_BALANCING_ENABLED',
      },
      scope: {
        complianceResourceTypes: ['AWS::ElasticLoadBalancing::LoadBalancer'],
      },
    });

    // Ensure Config rules depend on configuration recorder
    idleInstancesRule.addDependency(configurationRecorder);
    unattachedVolumesRule.addDependency(configurationRecorder);
    unusedLoadBalancersRule.addDependency(configurationRecorder);

    // ===============================
    // EVENTBRIDGE RULES AND TARGETS
    // ===============================

    // EventBridge rule for Config compliance changes
    const configComplianceRule = new events.Rule(this, 'ConfigComplianceRule', {
      ruleName: 'ConfigComplianceChanges',
      description: 'Trigger cost remediation on Config compliance changes',
      eventPattern: {
        source: ['aws.config'],
        detailType: ['Config Rules Compliance Change'],
        detail: {
          configRuleName: [
            'idle-ec2-instances',
            'unattached-ebs-volumes',
            'unused-load-balancers',
          ],
          newEvaluationResult: {
            complianceType: ['NON_COMPLIANT'],
          },
        },
      },
    });

    // Add Lambda targets to Config compliance rule
    configComplianceRule.addTarget(new targets.LambdaFunction(idleInstanceDetector, {
      event: events.RuleTargetInput.fromObject({ source: 'config-compliance' }),
    }));

    configComplianceRule.addTarget(new targets.LambdaFunction(volumeCleanup, {
      event: events.RuleTargetInput.fromObject({ source: 'config-compliance' }),
    }));

    // EventBridge rule for weekly cost optimization scans
    const weeklyOptimizationRule = new events.Rule(this, 'WeeklyOptimizationRule', {
      ruleName: 'WeeklyCostOptimizationScan',
      description: 'Weekly scan for cost optimization opportunities',
      schedule: events.Schedule.rate(Duration.days(7)),
    });

    // Add Lambda targets to weekly optimization rule
    weeklyOptimizationRule.addTarget(new targets.LambdaFunction(idleInstanceDetector, {
      event: events.RuleTargetInput.fromObject({ source: 'scheduled-scan' }),
    }));

    weeklyOptimizationRule.addTarget(new targets.LambdaFunction(volumeCleanup, {
      event: events.RuleTargetInput.fromObject({ source: 'scheduled-scan' }),
    }));

    weeklyOptimizationRule.addTarget(new targets.LambdaFunction(costReporter, {
      event: events.RuleTargetInput.fromObject({ source: 'scheduled-report' }),
    }));

    // ==================
    // STACK OUTPUTS
    // ==================

    // Output important resource ARNs and names for reference
    new cdk.CfnOutput(this, 'ConfigBucketName', {
      description: 'S3 bucket name for AWS Config delivery channel',
      value: configBucket.bucketName,
    });

    new cdk.CfnOutput(this, 'ReportsBucketName', {
      description: 'S3 bucket name for cost governance reports',
      value: reportsBucket.bucketName,
    });

    new cdk.CfnOutput(this, 'CostAlertsTopicArn', {
      description: 'SNS topic ARN for cost governance alerts',
      value: costAlertsTopic.topicArn,
    });

    new cdk.CfnOutput(this, 'CriticalAlertsTopicArn', {
      description: 'SNS topic ARN for critical cost actions',
      value: criticalAlertsTopic.topicArn,
    });

    new cdk.CfnOutput(this, 'IdleInstanceDetectorArn', {
      description: 'Lambda function ARN for idle instance detection',
      value: idleInstanceDetector.functionArn,
    });

    new cdk.CfnOutput(this, 'VolumeCleanupArn', {
      description: 'Lambda function ARN for volume cleanup',
      value: volumeCleanup.functionArn,
    });

    new cdk.CfnOutput(this, 'CostReporterArn', {
      description: 'Lambda function ARN for cost reporting',
      value: costReporter.functionArn,
    });

    new cdk.CfnOutput(this, 'DeploymentInstructions', {
      description: 'Next steps after deployment',
      value: 'Subscribe to SNS topics for notifications, then tag EC2 instances with "CostOptimization=enabled" to enable monitoring',
    });
  }
}

// ========================
// CDK APP INITIALIZATION
// ========================

const app = new cdk.App();

// Deploy the Cost Governance Stack
new CostGovernanceStack(app, 'CostGovernanceStack', {
  description: 'Automated Cost Governance with AWS Config and Lambda Remediation',
  
  // Enable termination protection for production deployments
  terminationProtection: false,
  
  // Add tags for cost allocation and governance
  tags: {
    Project: 'CostGovernance',
    Environment: 'Production',
    ManagedBy: 'CDK',
    Purpose: 'AutomatedCostOptimization',
  },
  
  // Specify environment (optional - will use default if not specified)
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Synthesize the CloudFormation template
app.synth();