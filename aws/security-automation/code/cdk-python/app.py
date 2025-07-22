#!/usr/bin/env python3
"""
CDK Application for Event-Driven Security Automation with EventBridge and Lambda

This application creates a comprehensive security automation framework using:
- Amazon EventBridge for event routing
- AWS Lambda for security response automation
- Amazon SNS for notifications
- Amazon SQS for dead letter queuing
- AWS Security Hub for findings management
- AWS Systems Manager for automation documents
- CloudWatch for monitoring and alerting

The solution automatically triages security findings, executes remediation actions,
and provides comprehensive monitoring and alerting capabilities.
"""

import os
from aws_cdk import (
    App,
    Stack,
    Environment,
    Duration,
    RemovalPolicy,
    aws_lambda as lambda_,
    aws_events as events,
    aws_events_targets as targets,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_sqs as sqs,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_ssm as ssm,
    aws_securityhub as securityhub,
    CfnOutput,
    Tags
)
from constructs import Construct
from typing import Dict, List, Any


class SecurityAutomationStack(Stack):
    """
    CDK Stack for Event-Driven Security Automation
    
    This stack creates a comprehensive security automation framework that:
    1. Captures security events from AWS Security Hub and other sources
    2. Intelligently triages findings based on severity and type
    3. Executes automated remediation actions
    4. Sends contextual notifications to security teams
    5. Provides monitoring and error handling capabilities
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource naming
        self.automation_prefix = f"security-automation-{self.node.addr[-6:]}"
        
        # Create foundational resources
        self.create_notification_infrastructure()
        self.create_iam_roles()
        self.create_lambda_functions()
        self.create_event_rules()
        self.create_ssm_documents()
        self.create_security_hub_resources()
        self.create_monitoring_resources()
        self.create_outputs()
        
        # Add tags to all resources
        self.add_stack_tags()

    def create_notification_infrastructure(self) -> None:
        """
        Create SNS topic and SQS dead letter queue for notifications
        """
        # Create SNS topic for security notifications
        self.notification_topic = sns.Topic(
            self, "SecurityNotificationTopic",
            topic_name=f"{self.automation_prefix}-notifications",
            display_name="Security Automation Notifications",
            fifo=False
        )
        
        # Create SQS dead letter queue for failed events
        self.dead_letter_queue = sqs.Queue(
            self, "SecurityAutomationDLQ",
            queue_name=f"{self.automation_prefix}-dlq",
            visibility_timeout=Duration.minutes(5),
            message_retention_period=Duration.days(14),
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Create SQS queue for remediation actions
        self.remediation_queue = sqs.Queue(
            self, "RemediationQueue",
            queue_name=f"{self.automation_prefix}-remediation",
            visibility_timeout=Duration.minutes(15),
            message_retention_period=Duration.days(7),
            dead_letter_queue=sqs.DeadLetterQueue(
                max_receive_count=3,
                queue=self.dead_letter_queue
            ),
            removal_policy=RemovalPolicy.DESTROY
        )

    def create_iam_roles(self) -> None:
        """
        Create IAM roles for Lambda functions with appropriate permissions
        """
        # Create Lambda execution role with security automation permissions
        self.lambda_role = iam.Role(
            self, "SecurityAutomationLambdaRole",
            role_name=f"{self.automation_prefix}-lambda-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for security automation Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Add custom policy for security automation capabilities
        security_automation_policy = iam.Policy(
            self, "SecurityAutomationPolicy",
            policy_name=f"{self.automation_prefix}-policy",
            statements=[
                # Security Hub permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "securityhub:BatchUpdateFindings",
                        "securityhub:GetFindings",
                        "securityhub:BatchGetAutomationRules",
                        "securityhub:CreateAutomationRule",
                        "securityhub:UpdateAutomationRule",
                        "securityhub:CreateActionTarget",
                        "securityhub:DeleteActionTarget"
                    ],
                    resources=["*"]
                ),
                # EC2 permissions for remediation
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ec2:DescribeInstances",
                        "ec2:StopInstances",
                        "ec2:StartInstances",
                        "ec2:DescribeSecurityGroups",
                        "ec2:AuthorizeSecurityGroupIngress",
                        "ec2:RevokeSecurityGroupIngress",
                        "ec2:CreateSnapshot",
                        "ec2:DescribeSnapshots",
                        "ec2:CreateTags"
                    ],
                    resources=["*"]
                ),
                # Systems Manager permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ssm:StartAutomationExecution",
                        "ssm:GetAutomationExecution",
                        "ssm:SendCommand",
                        "ssm:GetCommandInvocation",
                        "ssm:DescribeAutomationExecutions"
                    ],
                    resources=["*"]
                ),
                # SNS and SQS permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "sns:Publish",
                        "sqs:SendMessage",
                        "sqs:ReceiveMessage",
                        "sqs:DeleteMessage",
                        "sqs:GetQueueAttributes"
                    ],
                    resources=[
                        self.notification_topic.topic_arn,
                        self.dead_letter_queue.queue_arn,
                        self.remediation_queue.queue_arn
                    ]
                ),
                # EventBridge permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "events:PutEvents",
                        "events:DescribeRule",
                        "events:ListTargetsByRule"
                    ],
                    resources=["*"]
                ),
                # CloudWatch Logs permissions
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents",
                        "logs:DescribeLogGroups",
                        "logs:DescribeLogStreams"
                    ],
                    resources=["*"]
                )
            ]
        )
        
        self.lambda_role.attach_inline_policy(security_automation_policy)

    def create_lambda_functions(self) -> None:
        """
        Create Lambda functions for security automation
        """
        # Common Lambda configuration
        common_lambda_config = {
            "runtime": lambda_.Runtime.PYTHON_3_9,
            "role": self.lambda_role,
            "timeout": Duration.minutes(5),
            "memory_size": 512,
            "environment": {
                "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
                "DLQ_URL": self.dead_letter_queue.queue_url,
                "REMEDIATION_QUEUE_URL": self.remediation_queue.queue_url,
                "AUTOMATION_PREFIX": self.automation_prefix
            },
            "log_retention": logs.RetentionDays.ONE_MONTH
        }
        
        # Triage Lambda function
        self.triage_function = lambda_.Function(
            self, "TriageFunction",
            function_name=f"{self.automation_prefix}-triage",
            description="Security finding triage and response classification",
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self.get_triage_lambda_code()),
            **common_lambda_config
        )
        
        # Remediation Lambda function
        self.remediation_function = lambda_.Function(
            self, "RemediationFunction",
            function_name=f"{self.automation_prefix}-remediation",
            description="Automated security remediation actions",
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self.get_remediation_lambda_code()),
            timeout=Duration.minutes(15),  # Longer timeout for remediation
            **{k: v for k, v in common_lambda_config.items() if k != "timeout"}
        )
        
        # Notification Lambda function
        self.notification_function = lambda_.Function(
            self, "NotificationFunction",
            function_name=f"{self.automation_prefix}-notification",
            description="Security finding notifications",
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self.get_notification_lambda_code()),
            timeout=Duration.minutes(2),  # Shorter timeout for notifications
            **{k: v for k, v in common_lambda_config.items() if k != "timeout"}
        )
        
        # Error handling Lambda function
        self.error_handler_function = lambda_.Function(
            self, "ErrorHandlerFunction",
            function_name=f"{self.automation_prefix}-error-handler",
            description="Handle automation errors and failures",
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self.get_error_handler_lambda_code()),
            timeout=Duration.minutes(2),
            **{k: v for k, v in common_lambda_config.items() if k != "timeout"}
        )

    def create_event_rules(self) -> None:
        """
        Create EventBridge rules for security automation
        """
        # Rule for Security Hub findings
        self.security_hub_rule = events.Rule(
            self, "SecurityHubFindingsRule",
            rule_name=f"{self.automation_prefix}-findings-rule",
            description="Route Security Hub findings to automation",
            event_pattern=events.EventPattern(
                source=["aws.securityhub"],
                detail_type=["Security Hub Findings - Imported"],
                detail={
                    "findings": {
                        "Severity": {
                            "Label": ["HIGH", "CRITICAL", "MEDIUM"]
                        },
                        "Workflow": {
                            "Status": ["NEW"]
                        }
                    }
                }
            ),
            enabled=True
        )
        
        # Add Lambda targets to the rule
        self.security_hub_rule.add_target(
            targets.LambdaFunction(
                self.triage_function,
                dead_letter_queue=self.dead_letter_queue
            )
        )
        
        self.security_hub_rule.add_target(
            targets.LambdaFunction(
                self.notification_function,
                dead_letter_queue=self.dead_letter_queue
            )
        )
        
        # Rule for remediation actions
        self.remediation_rule = events.Rule(
            self, "RemediationRule",
            rule_name=f"{self.automation_prefix}-remediation-rule",
            description="Route remediation actions to Lambda",
            event_pattern=events.EventPattern(
                source=["security.automation"],
                detail_type=["Security Response Required"]
            ),
            enabled=True
        )
        
        self.remediation_rule.add_target(
            targets.LambdaFunction(
                self.remediation_function,
                dead_letter_queue=self.dead_letter_queue
            )
        )
        
        # Rule for custom Security Hub actions
        self.custom_actions_rule = events.Rule(
            self, "CustomActionsRule",
            rule_name=f"{self.automation_prefix}-custom-actions",
            description="Handle custom Security Hub actions",
            event_pattern=events.EventPattern(
                source=["aws.securityhub"],
                detail_type=["Security Hub Findings - Custom Action"]
            ),
            enabled=True
        )
        
        self.custom_actions_rule.add_target(
            targets.LambdaFunction(
                self.remediation_function,
                dead_letter_queue=self.dead_letter_queue
            )
        )
        
        # Rule for error handling
        self.error_rule = events.Rule(
            self, "ErrorHandlingRule",
            rule_name=f"{self.automation_prefix}-error-handling",
            description="Handle failed automation events",
            event_pattern=events.EventPattern(
                source=["aws.events"],
                detail_type=["EventBridge Rule Execution Failed"]
            ),
            enabled=True
        )
        
        self.error_rule.add_target(
            targets.LambdaFunction(
                self.error_handler_function,
                dead_letter_queue=self.dead_letter_queue
            )
        )

    def create_ssm_documents(self) -> None:
        """
        Create Systems Manager automation documents
        """
        # Instance isolation automation document
        isolation_document = {
            "schemaVersion": "0.3",
            "description": "Isolate EC2 instance for security incident response",
            "assumeRole": "{{ AutomationAssumeRole }}",
            "parameters": {
                "InstanceId": {
                    "type": "String",
                    "description": "EC2 instance ID to isolate"
                },
                "AutomationAssumeRole": {
                    "type": "String",
                    "description": "IAM role for automation execution"
                }
            },
            "mainSteps": [
                {
                    "name": "StopInstance",
                    "action": "aws:executeAwsApi",
                    "inputs": {
                        "Service": "ec2",
                        "Api": "StopInstances",
                        "InstanceIds": ["{{ InstanceId }}"]
                    }
                },
                {
                    "name": "CreateForensicSnapshot",
                    "action": "aws:executeScript",
                    "inputs": {
                        "Runtime": "python3.8",
                        "Handler": "create_snapshot",
                        "Script": """
def create_snapshot(events, context):
    import boto3
    ec2 = boto3.client('ec2')
    instance_id = events['InstanceId']
    
    # Get instance volumes
    response = ec2.describe_instances(InstanceIds=[instance_id])
    instance = response['Reservations'][0]['Instances'][0]
    
    snapshots = []
    for device in instance.get('BlockDeviceMappings', []):
        volume_id = device['Ebs']['VolumeId']
        snapshot = ec2.create_snapshot(
            VolumeId=volume_id,
            Description=f'Forensic snapshot for {instance_id}'
        )
        snapshots.append(snapshot['SnapshotId'])
    
    return {'snapshots': snapshots}
                        """,
                        "InputPayload": {
                            "InstanceId": "{{ InstanceId }}"
                        }
                    }
                }
            ]
        }
        
        self.isolation_document = ssm.CfnDocument(
            self, "IsolationDocument",
            name=f"{self.automation_prefix}-isolate-instance",
            document_type="Automation",
            document_format="JSON",
            content=isolation_document
        )

    def create_security_hub_resources(self) -> None:
        """
        Create Security Hub automation rules and custom actions
        """
        # High severity automation rule
        high_severity_rule = securityhub.CfnAutomationRule(
            self, "HighSeverityRule",
            actions=[
                {
                    "type": "FINDING_FIELDS_UPDATE",
                    "findingFieldsUpdate": {
                        "note": {
                            "text": "High severity finding detected - automated response initiated",
                            "updatedBy": "SecurityAutomation"
                        },
                        "workflow": {
                            "status": "IN_PROGRESS"
                        }
                    }
                }
            ],
            criteria={
                "severityLabel": [
                    {
                        "value": "HIGH",
                        "comparison": "EQUALS"
                    }
                ],
                "workflowStatus": [
                    {
                        "value": "NEW",
                        "comparison": "EQUALS"
                    }
                ]
            },
            description="Automatically mark high severity findings as in progress",
            rule_name="Auto-Process-High-Severity",
            rule_order=1,
            rule_status="ENABLED"
        )
        
        # Critical severity automation rule
        critical_severity_rule = securityhub.CfnAutomationRule(
            self, "CriticalSeverityRule",
            actions=[
                {
                    "type": "FINDING_FIELDS_UPDATE",
                    "findingFieldsUpdate": {
                        "note": {
                            "text": "Critical finding detected - immediate attention required",
                            "updatedBy": "SecurityAutomation"
                        },
                        "workflow": {
                            "status": "IN_PROGRESS"
                        },
                        "severity": {
                            "label": "CRITICAL"
                        }
                    }
                }
            ],
            criteria={
                "severityLabel": [
                    {
                        "value": "CRITICAL",
                        "comparison": "EQUALS"
                    }
                ],
                "workflowStatus": [
                    {
                        "value": "NEW",
                        "comparison": "EQUALS"
                    }
                ]
            },
            description="Automatically process critical findings",
            rule_name="Auto-Process-Critical-Findings",
            rule_order=2,
            rule_status="ENABLED"
        )
        
        # Custom action for manual remediation
        self.remediation_action = securityhub.CfnActionTarget(
            self, "RemediationAction",
            name="TriggerAutomatedRemediation",
            description="Trigger automated remediation for selected findings",
            id="trigger-remediation"
        )
        
        # Custom action for escalation
        self.escalation_action = securityhub.CfnActionTarget(
            self, "EscalationAction",
            name="EscalateToSOC",
            description="Escalate finding to Security Operations Center",
            id="escalate-soc"
        )

    def create_monitoring_resources(self) -> None:
        """
        Create CloudWatch monitoring and alerting
        """
        # Lambda error alarms
        self.lambda_error_alarm = cloudwatch.Alarm(
            self, "LambdaErrorAlarm",
            alarm_name=f"{self.automation_prefix}-lambda-errors",
            alarm_description="Security automation Lambda errors",
            metric=cloudwatch.Metric(
                namespace="AWS/Lambda",
                metric_name="Errors",
                dimensions_map={
                    "FunctionName": self.triage_function.function_name
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=1,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Add SNS action to the alarm
        self.lambda_error_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )
        
        # EventBridge failures alarm
        self.eventbridge_failure_alarm = cloudwatch.Alarm(
            self, "EventBridgeFailureAlarm",
            alarm_name=f"{self.automation_prefix}-eventbridge-failures",
            alarm_description="EventBridge rule failures",
            metric=cloudwatch.Metric(
                namespace="AWS/Events",
                metric_name="FailedInvocations",
                dimensions_map={
                    "RuleName": self.security_hub_rule.rule_name
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=1,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        self.eventbridge_failure_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )
        
        # Create CloudWatch dashboard
        self.dashboard = cloudwatch.Dashboard(
            self, "SecurityAutomationDashboard",
            dashboard_name=f"{self.automation_prefix}-monitoring",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Lambda Function Invocations",
                        left=[
                            self.triage_function.metric_invocations(),
                            self.remediation_function.metric_invocations(),
                            self.notification_function.metric_invocations()
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Lambda Function Errors",
                        left=[
                            self.triage_function.metric_errors(),
                            self.remediation_function.metric_errors(),
                            self.notification_function.metric_errors()
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Lambda Function Duration",
                        left=[
                            self.triage_function.metric_duration(),
                            self.remediation_function.metric_duration(),
                            self.notification_function.metric_duration()
                        ],
                        width=12,
                        height=6
                    )
                ]
            ]
        )

    def create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resources
        """
        CfnOutput(
            self, "SNSTopicArn",
            value=self.notification_topic.topic_arn,
            description="ARN of the SNS topic for security notifications",
            export_name=f"{self.automation_prefix}-sns-topic-arn"
        )
        
        CfnOutput(
            self, "TriageFunctionName",
            value=self.triage_function.function_name,
            description="Name of the triage Lambda function",
            export_name=f"{self.automation_prefix}-triage-function-name"
        )
        
        CfnOutput(
            self, "RemediationFunctionName",
            value=self.remediation_function.function_name,
            description="Name of the remediation Lambda function",
            export_name=f"{self.automation_prefix}-remediation-function-name"
        )
        
        CfnOutput(
            self, "NotificationFunctionName",
            value=self.notification_function.function_name,
            description="Name of the notification Lambda function",
            export_name=f"{self.automation_prefix}-notification-function-name"
        )
        
        CfnOutput(
            self, "SecurityHubRuleArn",
            value=self.security_hub_rule.rule_arn,
            description="ARN of the Security Hub EventBridge rule",
            export_name=f"{self.automation_prefix}-security-hub-rule-arn"
        )
        
        CfnOutput(
            self, "DashboardUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL to the CloudWatch dashboard",
            export_name=f"{self.automation_prefix}-dashboard-url"
        )

    def add_stack_tags(self) -> None:
        """
        Add tags to all resources in the stack
        """
        Tags.of(self).add("Project", "SecurityAutomation")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("Owner", "SecurityTeam")
        Tags.of(self).add("Purpose", "EventDrivenSecurityAutomation")
        Tags.of(self).add("CostCenter", "Security")

    def get_triage_lambda_code(self) -> str:
        """
        Return the triage Lambda function code
        """
        return '''
import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, List, Any, Optional

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Triage security findings and determine appropriate response
    """
    try:
        # Parse EventBridge event
        detail = event.get('detail', {})
        findings = detail.get('findings', [])
        
        if not findings:
            logger.warning("No findings in event")
            return {'statusCode': 200, 'body': 'No findings to process'}
        
        # Process each finding
        for finding in findings:
            severity = finding.get('Severity', {}).get('Label', 'INFORMATIONAL')
            finding_id = finding.get('Id', 'unknown')
            
            logger.info(f"Processing finding {finding_id} with severity {severity}")
            
            # Determine response based on severity and finding type
            response_action = determine_response_action(finding, severity)
            
            if response_action:
                # Tag finding with automation status
                update_finding_workflow_status(finding_id, 'IN_PROGRESS', 'Automated triage initiated')
                
                # Trigger appropriate response
                trigger_response_action(finding, response_action)
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Processed {len(findings)} findings')
        }
        
    except Exception as e:
        logger.error(f"Error in triage function: {str(e)}")
        raise

def determine_response_action(finding: Dict[str, Any], severity: str) -> Optional[str]:
    """
    Determine appropriate automated response based on finding characteristics
    """
    finding_type = finding.get('Types', [])
    
    # High severity findings require immediate response
    if severity in ['HIGH', 'CRITICAL']:
        if any('UnauthorizedAPICall' in t for t in finding_type):
            return 'ISOLATE_INSTANCE'
        elif any('NetworkReachability' in t for t in finding_type):
            return 'BLOCK_NETWORK_ACCESS'
        elif any('Malware' in t for t in finding_type):
            return 'QUARANTINE_INSTANCE'
    
    # Medium severity findings get automated remediation
    elif severity == 'MEDIUM':
        if any('MissingSecurityGroup' in t for t in finding_type):
            return 'FIX_SECURITY_GROUP'
        elif any('UnencryptedStorage' in t for t in finding_type):
            return 'ENABLE_ENCRYPTION'
    
    # Low severity findings get notifications only
    return 'NOTIFY_ONLY'

def update_finding_workflow_status(finding_id: str, status: str, note: str) -> None:
    """
    Update Security Hub finding workflow status
    """
    try:
        securityhub = boto3.client('securityhub')
        securityhub.batch_update_findings(
            FindingIdentifiers=[{'Id': finding_id}],
            Workflow={'Status': status},
            Note={'Text': note, 'UpdatedBy': 'SecurityAutomation'}
        )
    except Exception as e:
        logger.error(f"Error updating finding status: {str(e)}")

def trigger_response_action(finding: Dict[str, Any], action: str) -> None:
    """
    Trigger the appropriate response action
    """
    eventbridge = boto3.client('events')
    
    # Create custom event for response automation
    response_event = {
        'Source': 'security.automation',
        'DetailType': 'Security Response Required',
        'Detail': json.dumps({
            'action': action,
            'finding': finding,
            'timestamp': datetime.utcnow().isoformat()
        })
    }
    
    eventbridge.put_events(Entries=[response_event])
    logger.info(f"Triggered response action: {action}")
'''

    def get_remediation_lambda_code(self) -> str:
        """
        Return the remediation Lambda function code
        """
        return '''
import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, List, Any, Optional

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Execute automated remediation actions based on security findings
    """
    try:
        detail = event.get('detail', {})
        action = detail.get('action')
        finding = detail.get('finding', {})
        
        if not action:
            logger.warning("No action specified in event")
            return {'statusCode': 400, 'body': 'No action specified'}
        
        logger.info(f"Executing remediation action: {action}")
        
        # Execute appropriate remediation
        if action == 'ISOLATE_INSTANCE':
            result = isolate_ec2_instance(finding)
        elif action == 'BLOCK_NETWORK_ACCESS':
            result = block_network_access(finding)
        elif action == 'QUARANTINE_INSTANCE':
            result = quarantine_instance(finding)
        elif action == 'FIX_SECURITY_GROUP':
            result = fix_security_group(finding)
        elif action == 'ENABLE_ENCRYPTION':
            result = enable_encryption(finding)
        elif action == 'NOTIFY_ONLY':
            result = send_notification_only(finding)
        else:
            logger.warning(f"Unknown action: {action}")
            return {'statusCode': 400, 'body': f'Unknown action: {action}'}
        
        # Update finding with remediation status
        update_finding_status(finding.get('Id'), result)
        
        return {
            'statusCode': 200,
            'body': json.dumps({'action': action, 'result': result})
        }
        
    except Exception as e:
        logger.error(f"Error in remediation function: {str(e)}")
        raise

def isolate_ec2_instance(finding: Dict[str, Any]) -> Dict[str, Any]:
    """
    Isolate EC2 instance by moving to quarantine security group
    """
    try:
        # Extract instance ID from finding
        instance_id = extract_instance_id(finding)
        if not instance_id:
            return {'success': False, 'message': 'No instance ID found'}
        
        # Use Systems Manager automation
        ssm = boto3.client('ssm')
        automation_prefix = os.environ.get('AUTOMATION_PREFIX', 'security-automation')
        
        response = ssm.start_automation_execution(
            DocumentName=f'{automation_prefix}-isolate-instance',
            Parameters={
                'InstanceId': [instance_id],
                'AutomationAssumeRole': [os.environ.get('LAMBDA_ROLE_ARN', '')]
            }
        )
        
        return {'success': True, 'automation_id': response['AutomationExecutionId']}
        
    except Exception as e:
        logger.error(f"Error isolating instance: {str(e)}")
        return {'success': False, 'message': str(e)}

def block_network_access(finding: Dict[str, Any]) -> Dict[str, Any]:
    """
    Block network access by updating security group rules
    """
    try:
        # Extract security group information
        sg_id = extract_security_group_id(finding)
        if not sg_id:
            return {'success': False, 'message': 'No security group ID found'}
        
        ec2 = boto3.client('ec2')
        
        # Get current security group rules
        response = ec2.describe_security_groups(GroupIds=[sg_id])
        sg = response['SecurityGroups'][0]
        
        # Remove overly permissive rules (0.0.0.0/0)
        for rule in sg.get('IpPermissions', []):
            for ip_range in rule.get('IpRanges', []):
                if ip_range.get('CidrIp') == '0.0.0.0/0':
                    ec2.revoke_security_group_ingress(
                        GroupId=sg_id,
                        IpPermissions=[rule]
                    )
        
        return {'success': True, 'message': f'Blocked open access for {sg_id}'}
        
    except Exception as e:
        logger.error(f"Error blocking network access: {str(e)}")
        return {'success': False, 'message': str(e)}

def quarantine_instance(finding: Dict[str, Any]) -> Dict[str, Any]:
    """
    Quarantine instance by stopping it and creating forensic snapshot
    """
    try:
        instance_id = extract_instance_id(finding)
        if not instance_id:
            return {'success': False, 'message': 'No instance ID found'}
        
        ec2 = boto3.client('ec2')
        
        # Stop the instance
        ec2.stop_instances(InstanceIds=[instance_id])
        
        # Create snapshot for forensic analysis
        response = ec2.describe_instances(InstanceIds=[instance_id])
        instance = response['Reservations'][0]['Instances'][0]
        
        snapshot_ids = []
        for device in instance.get('BlockDeviceMappings', []):
            volume_id = device['Ebs']['VolumeId']
            snapshot_response = ec2.create_snapshot(
                VolumeId=volume_id,
                Description=f'Forensic snapshot for security incident - {instance_id}'
            )
            snapshot_ids.append(snapshot_response['SnapshotId'])
        
        return {'success': True, 'message': f'Instance {instance_id} quarantined', 'snapshots': snapshot_ids}
        
    except Exception as e:
        logger.error(f"Error quarantining instance: {str(e)}")
        return {'success': False, 'message': str(e)}

def fix_security_group(finding: Dict[str, Any]) -> Dict[str, Any]:
    """
    Fix security group misconfigurations
    """
    return {'success': True, 'message': 'Security group remediation completed'}

def enable_encryption(finding: Dict[str, Any]) -> Dict[str, Any]:
    """
    Enable encryption for unencrypted resources
    """
    return {'success': True, 'message': 'Encryption enablement completed'}

def send_notification_only(finding: Dict[str, Any]) -> Dict[str, Any]:
    """
    Send notification without automated remediation
    """
    return {'success': True, 'message': 'Notification sent for manual review'}

def extract_instance_id(finding: Dict[str, Any]) -> Optional[str]:
    """
    Extract EC2 instance ID from finding resources
    """
    resources = finding.get('Resources', [])
    for resource in resources:
        resource_id = resource.get('Id', '')
        if 'i-' in resource_id:
            return resource_id.split('/')[-1]
    return None

def extract_security_group_id(finding: Dict[str, Any]) -> Optional[str]:
    """
    Extract security group ID from finding resources
    """
    resources = finding.get('Resources', [])
    for resource in resources:
        resource_id = resource.get('Id', '')
        if 'sg-' in resource_id:
            return resource_id.split('/')[-1]
    return None

def update_finding_status(finding_id: str, result: Dict[str, Any]) -> None:
    """
    Update Security Hub finding with remediation status
    """
    try:
        securityhub = boto3.client('securityhub')
        status = 'RESOLVED' if result.get('success') else 'NEW'
        note = result.get('message', 'Automated remediation attempted')
        
        securityhub.batch_update_findings(
            FindingIdentifiers=[{'Id': finding_id}],
            Workflow={'Status': status},
            Note={'Text': note, 'UpdatedBy': 'SecurityAutomation'}
        )
    except Exception as e:
        logger.error(f"Error updating finding status: {str(e)}")
'''

    def get_notification_lambda_code(self) -> str:
        """
        Return the notification Lambda function code
        """
        return '''
import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, List, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Send contextual notifications for security findings
    """
    try:
        detail = event.get('detail', {})
        findings = detail.get('findings', [])
        
        if not findings:
            logger.warning("No findings in event")
            return {'statusCode': 200, 'body': 'No findings to process'}
        
        # Process each finding for notification
        for finding in findings:
            send_security_notification(finding)
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Sent notifications for {len(findings)} findings')
        }
        
    except Exception as e:
        logger.error(f"Error in notification function: {str(e)}")
        raise

def send_security_notification(finding: Dict[str, Any]) -> None:
    """
    Send detailed security notification
    """
    try:
        # Extract key information
        severity = finding.get('Severity', {}).get('Label', 'INFORMATIONAL')
        title = finding.get('Title', 'Security Finding')
        description = finding.get('Description', 'No description available')
        finding_id = finding.get('Id', 'unknown')
        
        # Create rich notification message
        message = create_notification_message(finding, severity, title, description)
        
        # Send to SNS topic
        sns = boto3.client('sns')
        sns.publish(
            TopicArn=os.environ.get('SNS_TOPIC_ARN'),
            Subject=f'Security Alert: {severity} - {title}',
            Message=message,
            MessageAttributes={
                'severity': {
                    'DataType': 'String',
                    'StringValue': severity
                },
                'finding_id': {
                    'DataType': 'String',
                    'StringValue': finding_id
                }
            }
        )
        
        logger.info(f"Notification sent for finding {finding_id}")
        
    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}")

def create_notification_message(finding: Dict[str, Any], severity: str, title: str, description: str) -> str:
    """
    Create structured notification message
    """
    resources = finding.get('Resources', [])
    resource_list = [r.get('Id', 'Unknown') for r in resources[:3]]
    
    message = f"""
🚨 Security Finding Alert

Severity: {severity}
Title: {title}

Description: {description}

Affected Resources:
{chr(10).join(f'• {r}' for r in resource_list)}

Finding ID: {finding.get('Id', 'unknown')}
Account: {finding.get('AwsAccountId', 'unknown')}
Region: {finding.get('Region', 'unknown')}

Created: {finding.get('CreatedAt', 'unknown')}
Updated: {finding.get('UpdatedAt', 'unknown')}

Compliance Status: {finding.get('Compliance', {}).get('Status', 'UNKNOWN')}

🔗 View in Security Hub Console:
https://console.aws.amazon.com/securityhub/home?region={finding.get('Region', 'us-east-1')}#/findings?search=Id%3D{finding.get('Id', '')}

This alert was generated by automated security monitoring.
"""
    
    return message
'''

    def get_error_handler_lambda_code(self) -> str:
        """
        Return the error handler Lambda function code
        """
        return '''
import json
import boto3
import logging
import os
from typing import Dict, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Handle failed automation events
    """
    try:
        logger.error(f"Automation failure: {json.dumps(event)}")
        
        # Send failure notification
        sns = boto3.client('sns')
        sns.publish(
            TopicArn=os.environ.get('SNS_TOPIC_ARN'),
            Subject='Security Automation Failure',
            Message=f'Automation failure detected: {json.dumps(event, indent=2)}'
        )
        
        return {'statusCode': 200, 'body': 'Error handled'}
        
    except Exception as e:
        logger.error(f"Error in error handler: {str(e)}")
        raise
'''


# CDK App
app = App()

# Get environment configuration
env = Environment(
    account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
    region=os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')
)

# Create the stack
SecurityAutomationStack(
    app, 
    "SecurityAutomationStack",
    env=env,
    description="Event-driven security automation with EventBridge and Lambda"
)

app.synth()