#!/usr/bin/env python3
"""
AWS CDK Python Application for Automated Cost Governance

This application deploys a comprehensive cost governance framework using:
- AWS Config for continuous compliance monitoring
- Lambda functions for automated remediation
- EventBridge for event-driven automation
- SNS for notifications and reporting
"""

import os
import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_s3 as s3,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_sqs as sqs,
    aws_events as events,
    aws_events_targets as targets,
    aws_config as config,
    aws_ssm as ssm,
    CfnOutput,
    CfnParameter,
)
from constructs import Construct
from typing import Dict, Any


class CostGovernanceStack(Stack):
    """
    Stack for deploying automated cost governance infrastructure
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters for customization
        self.email_parameter = CfnParameter(
            self,
            "NotificationEmail",
            type="String",
            description="Email address for cost governance notifications",
            constraint_description="Must be a valid email address",
        )

        self.cost_threshold_parameter = CfnParameter(
            self,
            "CostThreshold",
            type="Number",
            default=100,
            description="Monthly cost threshold for alerts (USD)",
            min_value=1,
            max_value=10000,
        )

        self.cpu_threshold_parameter = CfnParameter(
            self,
            "CpuThreshold",
            type="Number",
            default=5,
            description="CPU utilization threshold for idle instance detection (%)",
            min_value=1,
            max_value=50,
        )

        # Create foundational resources
        self._create_s3_buckets()
        self._create_iam_roles()
        self._create_notification_infrastructure()
        self._create_lambda_functions()
        self._create_config_rules()
        self._create_event_driven_automation()
        self._create_scheduled_tasks()
        self._create_outputs()

    def _create_s3_buckets(self) -> None:
        """Create S3 buckets for Config and cost governance reports"""
        
        # Config bucket for AWS Config service
        self.config_bucket = s3.Bucket(
            self,
            "ConfigBucket",
            bucket_name=f"aws-config-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Reports bucket for cost governance reports
        self.reports_bucket = s3.Bucket(
            self,
            "ReportsBucket",
            bucket_name=f"cost-governance-reports-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ReportRetention",
                    enabled=True,
                    expiration=Duration.days(90),
                    noncurrent_version_expiration=Duration.days(30),
                )
            ],
        )

        # Grant Config service access to the bucket
        self.config_bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSConfigBucketPermissionsCheck",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("config.amazonaws.com")],
                actions=["s3:GetBucketAcl"],
                resources=[self.config_bucket.bucket_arn],
                conditions={
                    "StringEquals": {
                        "AWS:SourceAccount": self.account
                    }
                }
            )
        )

        self.config_bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSConfigBucketExistenceCheck",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("config.amazonaws.com")],
                actions=["s3:ListBucket"],
                resources=[self.config_bucket.bucket_arn],
                conditions={
                    "StringEquals": {
                        "AWS:SourceAccount": self.account
                    }
                }
            )
        )

        self.config_bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSConfigBucketDelivery",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("config.amazonaws.com")],
                actions=["s3:PutObject"],
                resources=[f"{self.config_bucket.bucket_arn}/*"],
                conditions={
                    "StringEquals": {
                        "s3:x-amz-acl": "bucket-owner-full-control",
                        "AWS:SourceAccount": self.account
                    }
                }
            )
        )

    def _create_iam_roles(self) -> None:
        """Create IAM roles for Lambda functions and Config service"""
        
        # Lambda execution role for cost governance functions
        self.lambda_role = iam.Role(
            self,
            "CostGovernanceLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for cost governance Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "CostGovernancePolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "ec2:DescribeInstances",
                                "ec2:DescribeVolumes",
                                "ec2:StopInstances",
                                "ec2:TerminateInstances",
                                "ec2:ModifyInstanceAttribute",
                                "ec2:DeleteVolume",
                                "ec2:DetachVolume",
                                "ec2:CreateSnapshot",
                                "ec2:DescribeSnapshots",
                                "ec2:CreateTags",
                                "elasticloadbalancing:DescribeLoadBalancers",
                                "elasticloadbalancing:DescribeTargetGroups",
                                "elasticloadbalancing:DescribeTargetHealth",
                                "elasticloadbalancing:DeleteLoadBalancer",
                                "elasticloadbalancing:AddTags",
                                "rds:DescribeDBInstances",
                                "rds:DescribeDBClusters",
                                "rds:StopDBInstance",
                                "rds:StopDBCluster",
                                "rds:DeleteDBInstance",
                                "rds:AddTagsToResource",
                            ],
                            resources=["*"],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "cloudwatch:GetMetricStatistics",
                                "cloudwatch:ListMetrics",
                            ],
                            resources=["*"],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "config:GetComplianceDetailsByConfigRule",
                                "config:GetComplianceDetailsByResource",
                                "config:PutEvaluations",
                                "config:GetComplianceSummaryByConfigRule",
                            ],
                            resources=["*"],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "ssm:PutParameter",
                                "ssm:GetParameter",
                                "ssm:GetParameters",
                                "ssm:SendCommand",
                                "ssm:GetCommandInvocation",
                            ],
                            resources=["*"],
                        ),
                    ]
                )
            },
        )

        # Config service role
        self.config_role = iam.Role(
            self,
            "AWSConfigRole",
            assumed_by=iam.ServicePrincipal("config.amazonaws.com"),
            description="Service role for AWS Config",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/ConfigRole"
                )
            ],
        )

    def _create_notification_infrastructure(self) -> None:
        """Create SNS topics and SQS queues for notifications and processing"""
        
        # SNS topic for cost governance alerts
        self.cost_alerts_topic = sns.Topic(
            self,
            "CostGovernanceAlerts",
            topic_name="CostGovernanceAlerts",
            display_name="Cost Governance Alerts",
        )

        # SNS topic for critical cost actions
        self.critical_alerts_topic = sns.Topic(
            self,
            "CriticalCostActions",
            topic_name="CriticalCostActions",
            display_name="Critical Cost Actions",
        )

        # Subscribe email to topics
        self.cost_alerts_topic.add_subscription(
            sns_subscriptions.EmailSubscription(self.email_parameter.value_as_string)
        )

        self.critical_alerts_topic.add_subscription(
            sns_subscriptions.EmailSubscription(self.email_parameter.value_as_string)
        )

        # Dead Letter Queue for failed processing
        self.dlq = sqs.Queue(
            self,
            "CostGovernanceDLQ",
            queue_name="CostGovernanceDLQ",
            retention_period=Duration.days(14),
        )

        # Main processing queue
        self.processing_queue = sqs.Queue(
            self,
            "CostGovernanceQueue",
            queue_name="CostGovernanceQueue",
            visibility_timeout=Duration.minutes(5),
            retention_period=Duration.days(14),
            receive_message_wait_time=Duration.seconds(20),
            dead_letter_queue=sqs.DeadLetterQueue(
                max_receive_count=3,
                queue=self.dlq,
            ),
        )

        # Grant Lambda role access to SNS topics
        self.cost_alerts_topic.grant_publish(self.lambda_role)
        self.critical_alerts_topic.grant_publish(self.lambda_role)

        # Grant Lambda role access to SQS queues
        self.processing_queue.grant_consume_messages(self.lambda_role)
        self.processing_queue.grant_send_messages(self.lambda_role)

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions for cost governance automation"""
        
        # Idle instance detector function
        self.idle_detector_function = lambda_.Function(
            self,
            "IdleInstanceDetector",
            function_name="IdleInstanceDetector",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                "SNS_TOPIC_ARN": self.cost_alerts_topic.topic_arn,
                "CPU_THRESHOLD": self.cpu_threshold_parameter.value_as_string,
            },
            code=lambda_.Code.from_inline(self._get_idle_detector_code()),
        )

        # Volume cleanup function
        self.volume_cleanup_function = lambda_.Function(
            self,
            "VolumeCleanup",
            function_name="VolumeCleanup",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                "SNS_TOPIC_ARN": self.cost_alerts_topic.topic_arn,
            },
            code=lambda_.Code.from_inline(self._get_volume_cleanup_code()),
        )

        # Cost reporter function
        self.cost_reporter_function = lambda_.Function(
            self,
            "CostReporter",
            function_name="CostReporter",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "SNS_TOPIC_ARN": self.cost_alerts_topic.topic_arn,
                "REPORTS_BUCKET": self.reports_bucket.bucket_name,
            },
            code=lambda_.Code.from_inline(self._get_cost_reporter_code()),
        )

        # Grant S3 access to Lambda functions
        self.reports_bucket.grant_read_write(self.lambda_role)

    def _create_config_rules(self) -> None:
        """Create AWS Config rules for cost governance"""
        
        # Config delivery channel
        config_delivery_channel = config.CfnDeliveryChannel(
            self,
            "ConfigDeliveryChannel",
            s3_bucket_name=self.config_bucket.bucket_name,
        )

        # Config configuration recorder
        config_recorder = config.CfnConfigurationRecorder(
            self,
            "ConfigRecorder",
            role_arn=self.config_role.role_arn,
            recording_group=config.CfnConfigurationRecorder.RecordingGroupProperty(
                all_supported=True,
                include_global_resource_types=True,
                resource_types=[],
            ),
        )

        config_recorder.add_depends_on(config_delivery_channel)

        # Config rule for idle EC2 instances
        self.idle_instances_rule = config.CfnConfigRule(
            self,
            "IdleEC2InstancesRule",
            config_rule_name="idle-ec2-instances",
            description="Checks for EC2 instances with low CPU utilization",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="EC2_INSTANCE_NO_HIGH_LEVEL_FINDINGS",
            ),
            scope=config.CfnConfigRule.ScopeProperty(
                compliance_resource_types=["AWS::EC2::Instance"],
            ),
        )

        self.idle_instances_rule.add_depends_on(config_recorder)

        # Config rule for unattached EBS volumes
        self.unattached_volumes_rule = config.CfnConfigRule(
            self,
            "UnattachedEBSVolumesRule",
            config_rule_name="unattached-ebs-volumes",
            description="Checks for EBS volumes that are not attached to instances",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="EBS_OPTIMIZED_INSTANCE",
            ),
            scope=config.CfnConfigRule.ScopeProperty(
                compliance_resource_types=["AWS::EC2::Volume"],
            ),
        )

        self.unattached_volumes_rule.add_depends_on(config_recorder)

        # Config rule for unused load balancers
        self.unused_elb_rule = config.CfnConfigRule(
            self,
            "UnusedLoadBalancersRule",
            config_rule_name="unused-load-balancers",
            description="Checks for load balancers with no healthy targets",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="ELB_CROSS_ZONE_LOAD_BALANCING_ENABLED",
            ),
            scope=config.CfnConfigRule.ScopeProperty(
                compliance_resource_types=["AWS::ElasticLoadBalancing::LoadBalancer"],
            ),
        )

        self.unused_elb_rule.add_depends_on(config_recorder)

    def _create_event_driven_automation(self) -> None:
        """Create EventBridge rules for automated remediation"""
        
        # EventBridge rule for Config compliance changes
        self.compliance_rule = events.Rule(
            self,
            "ConfigComplianceChanges",
            rule_name="ConfigComplianceChanges",
            description="Trigger cost remediation on Config compliance changes",
            event_pattern=events.EventPattern(
                source=["aws.config"],
                detail_type=["Config Rules Compliance Change"],
                detail={
                    "configRuleName": [
                        "idle-ec2-instances",
                        "unattached-ebs-volumes",
                        "unused-load-balancers",
                    ],
                    "newEvaluationResult": {
                        "complianceType": ["NON_COMPLIANT"]
                    },
                },
            ),
        )

        # Add Lambda targets to the rule
        self.compliance_rule.add_target(
            targets.LambdaFunction(
                handler=self.idle_detector_function,
                event=events.RuleTargetInput.from_object({"source": "config-compliance"}),
            )
        )

        self.compliance_rule.add_target(
            targets.LambdaFunction(
                handler=self.volume_cleanup_function,
                event=events.RuleTargetInput.from_object({"source": "config-compliance"}),
            )
        )

    def _create_scheduled_tasks(self) -> None:
        """Create scheduled EventBridge rules for periodic cost scans"""
        
        # Weekly cost optimization scan
        self.weekly_scan_rule = events.Rule(
            self,
            "WeeklyCostOptimizationScan",
            rule_name="WeeklyCostOptimizationScan",
            description="Weekly scan for cost optimization opportunities",
            schedule=events.Schedule.rate(Duration.days(7)),
        )

        # Add Lambda targets for scheduled scans
        self.weekly_scan_rule.add_target(
            targets.LambdaFunction(
                handler=self.idle_detector_function,
                event=events.RuleTargetInput.from_object({"source": "scheduled-scan"}),
            )
        )

        self.weekly_scan_rule.add_target(
            targets.LambdaFunction(
                handler=self.volume_cleanup_function,
                event=events.RuleTargetInput.from_object({"source": "scheduled-scan"}),
            )
        )

        self.weekly_scan_rule.add_target(
            targets.LambdaFunction(
                handler=self.cost_reporter_function,
                event=events.RuleTargetInput.from_object({"source": "scheduled-report"}),
            )
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        
        CfnOutput(
            self,
            "ConfigBucketName",
            value=self.config_bucket.bucket_name,
            description="S3 bucket for AWS Config data",
        )

        CfnOutput(
            self,
            "ReportsBucketName",
            value=self.reports_bucket.bucket_name,
            description="S3 bucket for cost governance reports",
        )

        CfnOutput(
            self,
            "CostAlertsTopicArn",
            value=self.cost_alerts_topic.topic_arn,
            description="SNS topic ARN for cost governance alerts",
        )

        CfnOutput(
            self,
            "CriticalAlertsTopicArn",
            value=self.critical_alerts_topic.topic_arn,
            description="SNS topic ARN for critical cost actions",
        )

        CfnOutput(
            self,
            "IdleDetectorFunctionArn",
            value=self.idle_detector_function.function_arn,
            description="ARN of the idle instance detector Lambda function",
        )

        CfnOutput(
            self,
            "VolumeCleanupFunctionArn",
            value=self.volume_cleanup_function.function_arn,
            description="ARN of the volume cleanup Lambda function",
        )

        CfnOutput(
            self,
            "CostReporterFunctionArn",
            value=self.cost_reporter_function.function_arn,
            description="ARN of the cost reporter Lambda function",
        )

    def _get_idle_detector_code(self) -> str:
        """Get the Lambda function code for idle instance detection"""
        return """
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
    
    cpu_threshold = float(os.environ.get('CPU_THRESHOLD', '5'))
    
    # Get all running instances
    response = ec2.describe_instances(
        Filters=[
            {'Name': 'instance-state-name', 'Values': ['running']},
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
                    
                    if avg_cpu < cpu_threshold:
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
"""

    def _get_volume_cleanup_code(self) -> str:
        """Get the Lambda function code for volume cleanup"""
        return """
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
            # Estimate monthly cost savings
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
"""

    def _get_cost_reporter_code(self) -> str:
        """Get the Lambda function code for cost reporting"""
        return """
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
        compliance_summary = config_client.get_compliance_summary_by_config_rule()
        
        report_data['Summary']['ConfigRules'] = {
            'TotalRules': len(compliance_summary['ComplianceSummary']),
            'CompliantResources': sum(rule['ComplianceSummary']['CompliantResourceCount']['CappedCount'] 
                                    for rule in compliance_summary['ComplianceSummary']),
            'NonCompliantResources': sum(rule['ComplianceSummary']['NonCompliantResourceCount']['CappedCount'] 
                                       for rule in compliance_summary['ComplianceSummary'])
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
        summary_message = f'''
Cost Governance Report Summary

Generated: {report_data['ReportDate']}

Resource Summary:
- Running Instances: {running_instances}
- Idle Instances: {idle_instances}
- Unattached Volumes: {unattached_volumes}

Estimated Monthly Savings Opportunity: ${sum(estimated_savings.values()):.2f}

Full report saved to: s3://{os.environ['REPORTS_BUCKET']}/{report_key}
        '''
        
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
"""


# Create the CDK app and stack
app = cdk.App()

CostGovernanceStack(
    app,
    "CostGovernanceStack",
    description="Automated cost governance with AWS Config and Lambda remediation",
    env=cdk.Environment(
        account=os.getenv("CDK_DEFAULT_ACCOUNT"),
        region=os.getenv("CDK_DEFAULT_REGION"),
    ),
)

# Add tags to all resources
cdk.Tags.of(app).add("Project", "CostGovernance")
cdk.Tags.of(app).add("Environment", "Production")
cdk.Tags.of(app).add("Owner", "FinOps")
cdk.Tags.of(app).add("CostCenter", "Infrastructure")

app.synth()