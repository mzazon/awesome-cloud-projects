"""
Security Incident Response Stack for AWS Security Hub
This stack creates a comprehensive incident response system with automated triage and notifications.
"""

from typing import Dict, Any
from aws_cdk import (
    Stack,
    Duration,
    CfnOutput,
    aws_iam as iam,
    aws_lambda as _lambda,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_sqs as sqs,
    aws_events as events,
    aws_events_targets as targets,
    aws_securityhub as securityhub,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cloudwatch_actions,
    aws_logs as logs
)
from constructs import Construct


class SecurityIncidentResponseStack(Stack):
    """CDK Stack for Security Hub Incident Response System"""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create SNS topic for incident notifications
        self.incident_topic = self._create_incident_topic()
        
        # Create SQS queue for external integrations
        self.incident_queue = self._create_incident_queue()
        
        # Create IAM roles for Lambda functions
        self.lambda_role = self._create_lambda_execution_role()
        
        # Create Lambda functions
        self.incident_processor = self._create_incident_processor_function()
        self.threat_intelligence = self._create_threat_intelligence_function()
        
        # Create EventBridge rules for automated response
        self._create_eventbridge_rules()
        
        # Create Security Hub custom actions
        self._create_security_hub_custom_actions()
        
        # Create CloudWatch monitoring
        self._create_monitoring_dashboard()
        
        # Create outputs
        self._create_outputs()

    def _create_incident_topic(self) -> sns.Topic:
        """Create SNS topic for security incident notifications"""
        topic = sns.Topic(
            self,
            "SecurityIncidentTopic",
            display_name="Security Incident Alerts",
            topic_name="security-incident-alerts"
        )
        
        # Add dead letter queue for failed deliveries
        dlq = sqs.Queue(
            self,
            "IncidentNotificationDLQ",
            queue_name="security-incident-notifications-dlq",
            retention_period=Duration.days(14)
        )
        
        return topic

    def _create_incident_queue(self) -> sqs.Queue:
        """Create SQS queue for external system integration"""
        # Create dead letter queue
        dlq = sqs.Queue(
            self,
            "IncidentQueueDLQ",
            queue_name="security-incident-queue-dlq",
            retention_period=Duration.days(14)
        )
        
        # Create main queue
        queue = sqs.Queue(
            self,
            "SecurityIncidentQueue",
            queue_name="security-incident-queue",
            visibility_timeout=Duration.minutes(5),
            retention_period=Duration.days(14),
            receive_message_wait_time=Duration.seconds(20),
            dead_letter_queue=sqs.DeadLetterQueue(
                max_receive_count=3,
                queue=dlq
            )
        )
        
        # Subscribe queue to SNS topic
        self.incident_topic.add_subscription(
            sns_subscriptions.SqsSubscription(queue)
        )
        
        return queue

    def _create_lambda_execution_role(self) -> iam.Role:
        """Create IAM role for Lambda functions with security permissions"""
        role = iam.Role(
            self,
            "SecurityHubLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for Security Hub incident processing Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )
        
        # Add custom policy for Security Hub and SNS access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "securityhub:BatchUpdateFindings",
                    "securityhub:GetFindings",
                    "securityhub:BatchImportFindings"
                ],
                resources=["*"]
            )
        )
        
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "sns:Publish"
                ],
                resources=[self.incident_topic.topic_arn]
            )
        )
        
        # Add CloudWatch Logs permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                resources=[
                    f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/lambda/*"
                ]
            )
        )
        
        return role

    def _create_incident_processor_function(self) -> _lambda.Function:
        """Create Lambda function for processing security incidents"""
        # Create the Lambda function code
        function_code = '''
import json
import boto3
import os
from datetime import datetime
from typing import Dict, Any

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Process Security Hub findings and create incident notifications"""
    
    # Initialize AWS clients
    sns = boto3.client('sns')
    securityhub = boto3.client('securityhub')
    
    try:
        # Extract finding from event
        finding = event['detail']['findings'][0]
        
        # Extract key information
        severity = finding.get('Severity', {}).get('Label', 'UNKNOWN')
        title = finding.get('Title', 'Unknown Security Finding')
        description = finding.get('Description', 'No description available')
        account_id = finding.get('AwsAccountId', 'Unknown')
        region = finding.get('Region', 'Unknown')
        finding_id = finding.get('Id', 'Unknown')
        
        # Determine response action based on severity
        response_action = determine_response_action(severity)
        
        # Create incident payload
        incident_payload = {
            'finding_id': finding_id,
            'severity': severity,
            'title': title,
            'description': description,
            'account_id': account_id,
            'region': region,
            'timestamp': datetime.utcnow().isoformat(),
            'response_action': response_action,
            'source': 'AWS Security Hub'
        }
        
        # Create notification message
        message = create_incident_message(incident_payload)
        
        # Send notification to SNS
        response = sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=json.dumps(message, indent=2),
            Subject=f"Security Incident: {severity} - {title[:50]}",
            MessageAttributes={
                'severity': {
                    'DataType': 'String',
                    'StringValue': severity
                },
                'account_id': {
                    'DataType': 'String',
                    'StringValue': account_id
                }
            }
        )
        
        # Update finding workflow status
        update_finding_workflow(securityhub, finding_id, response_action)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Incident processed successfully',
                'finding_id': finding_id,
                'severity': severity,
                'response_action': response_action,
                'sns_message_id': response['MessageId']
            })
        }
        
    except Exception as e:
        print(f"Error processing incident: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'finding_id': finding.get('Id', 'Unknown') if 'finding' in locals() else 'Unknown'
            })
        }

def determine_response_action(severity: str) -> str:
    """Determine appropriate response action based on severity"""
    severity_actions = {
        'CRITICAL': 'immediate_response',
        'HIGH': 'escalated_response',
        'MEDIUM': 'standard_response',
        'LOW': 'low_priority_response',
        'INFORMATIONAL': 'informational_only'
    }
    return severity_actions.get(severity, 'standard_response')

def create_incident_message(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Create formatted incident message for notifications"""
    return {
        'incident_details': {
            'id': payload['finding_id'],
            'severity': payload['severity'],
            'title': payload['title'],
            'description': payload['description'],
            'account': payload['account_id'],
            'region': payload['region'],
            'timestamp': payload['timestamp']
        },
        'response_plan': {
            'action': payload['response_action'],
            'priority': get_priority_level(payload['severity']),
            'sla_minutes': get_sla_minutes(payload['severity'])
        },
        'integration': {
            'jira_project': 'SEC',
            'slack_channel': '#security-incidents',
            'pagerduty_service': 'security-team'
        }
    }

def get_priority_level(severity: str) -> str:
    """Map severity to priority level"""
    priority_map = {
        'CRITICAL': 'P1',
        'HIGH': 'P2',
        'MEDIUM': 'P3',
        'LOW': 'P4',
        'INFORMATIONAL': 'P5'
    }
    return priority_map.get(severity, 'P4')

def get_sla_minutes(severity: str) -> int:
    """Get SLA response time in minutes"""
    sla_map = {
        'CRITICAL': 15,
        'HIGH': 60,
        'MEDIUM': 240,
        'LOW': 1440,
        'INFORMATIONAL': 2880
    }
    return sla_map.get(severity, 1440)

def update_finding_workflow(securityhub, finding_id: str, response_action: str) -> None:
    """Update finding workflow status in Security Hub"""
    try:
        securityhub.batch_update_findings(
            FindingIdentifiers=[{
                'Id': finding_id,
                'ProductArn': f'arn:aws:securityhub:{os.environ["AWS_REGION"]}::product/aws/securityhub'
            }],
            Note={
                'Text': f'Automated incident response initiated: {response_action}',
                'UpdatedBy': 'SecurityHubAutomation'
            },
            Workflow={
                'Status': 'NOTIFIED'
            }
        )
    except Exception as e:
        print(f"Error updating finding workflow: {str(e)}")
'''
        
        function = _lambda.Function(
            self,
            "SecurityIncidentProcessor",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(function_code),
            role=self.lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            environment={
                "SNS_TOPIC_ARN": self.incident_topic.topic_arn,
                "AWS_REGION": self.region
            },
            description="Processes Security Hub findings and creates incident notifications"
        )
        
        # Create log group with retention
        logs.LogGroup(
            self,
            "IncidentProcessorLogGroup",
            log_group_name=f"/aws/lambda/{function.function_name}",
            retention=logs.RetentionDays.ONE_MONTH
        )
        
        return function

    def _create_threat_intelligence_function(self) -> _lambda.Function:
        """Create Lambda function for threat intelligence enrichment"""
        function_code = '''
import json
import boto3
import os
import re
from typing import Dict, Any, List

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Enrich Security Hub findings with threat intelligence data"""
    
    securityhub = boto3.client('securityhub')
    
    try:
        finding = event['detail']['findings'][0]
        
        # Extract threat indicators from resources
        resources = finding.get('Resources', [])
        threat_indicators = extract_threat_indicators(resources)
        
        # Calculate threat score based on indicators
        threat_score = calculate_threat_score(threat_indicators)
        
        # Update finding with threat intelligence
        securityhub.batch_update_findings(
            FindingIdentifiers=[{
                'Id': finding['Id'],
                'ProductArn': finding['ProductArn']
            }],
            Note={
                'Text': f'Threat Intelligence Score: {threat_score}/100. Indicators found: {len(threat_indicators)}',
                'UpdatedBy': 'ThreatIntelligence'
            },
            UserDefinedFields={
                'ThreatScore': str(threat_score),
                'ThreatIndicators': str(len(threat_indicators)),
                'IndicatorTypes': ','.join(set(ind['type'] for ind in threat_indicators))
            }
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'threat_score': threat_score,
                'indicators_found': len(threat_indicators),
                'finding_id': finding['Id']
            })
        }
        
    except Exception as e:
        print(f"Error enriching finding with threat intelligence: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def extract_threat_indicators(resources: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Extract threat indicators from Security Hub finding resources"""
    indicators = []
    
    for resource in resources:
        resource_id = resource.get('Id', '')
        resource_type = resource.get('Type', '')
        
        # Extract IP addresses
        ip_pattern = r'\\b(?:[0-9]{1,3}\\.){3}[0-9]{1,3}\\b'
        ips = re.findall(ip_pattern, resource_id)
        for ip in ips:
            indicators.append({'value': ip, 'type': 'ip', 'source': resource_type})
        
        # Extract domain names
        domain_pattern = r'\\b[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}\\b'
        domains = re.findall(domain_pattern, resource_id)
        for domain in domains:
            if not domain.endswith('.amazonaws.com'):  # Exclude AWS domains
                indicators.append({'value': domain, 'type': 'domain', 'source': resource_type})
        
        # Extract file hashes (MD5, SHA1, SHA256)
        hash_patterns = {
            'md5': r'\\b[a-fA-F0-9]{32}\\b',
            'sha1': r'\\b[a-fA-F0-9]{40}\\b',
            'sha256': r'\\b[a-fA-F0-9]{64}\\b'
        }
        
        for hash_type, pattern in hash_patterns.items():
            hashes = re.findall(pattern, resource_id)
            for hash_val in hashes:
                indicators.append({'value': hash_val, 'type': hash_type, 'source': resource_type})
    
    return indicators

def calculate_threat_score(indicators: List[Dict[str, Any]]) -> int:
    """Calculate threat score based on indicators found"""
    # Base score for any finding
    base_score = 10
    
    # Score modifiers based on indicator types
    score_modifiers = {
        'ip': 15,
        'domain': 10,
        'md5': 20,
        'sha1': 20,
        'sha256': 25
    }
    
    # Calculate score based on indicators
    indicator_score = 0
    for indicator in indicators:
        indicator_score += score_modifiers.get(indicator['type'], 5)
    
    # Cap at 100
    total_score = min(base_score + indicator_score, 100)
    
    return total_score
'''
        
        function = _lambda.Function(
            self,
            "ThreatIntelligenceLookup",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(function_code),
            role=self.lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            description="Enriches Security Hub findings with threat intelligence data"
        )
        
        # Create log group with retention
        logs.LogGroup(
            self,
            "ThreatIntelligenceLogGroup",
            log_group_name=f"/aws/lambda/{function.function_name}",
            retention=logs.RetentionDays.ONE_MONTH
        )
        
        return function

    def _create_eventbridge_rules(self) -> None:
        """Create EventBridge rules for automated incident response"""
        
        # Rule for high severity findings
        high_severity_rule = events.Rule(
            self,
            "SecurityHubHighSeverityRule",
            rule_name="security-hub-high-severity",
            description="Process high and critical severity Security Hub findings",
            event_pattern=events.EventPattern(
                source=["aws.securityhub"],
                detail_type=["Security Hub Findings - Imported"],
                detail={
                    "findings": {
                        "Severity": {
                            "Label": ["HIGH", "CRITICAL"]
                        },
                        "Workflow": {
                            "Status": ["NEW"]
                        }
                    }
                }
            )
        )
        
        # Add Lambda target to high severity rule
        high_severity_rule.add_target(
            targets.LambdaFunction(self.incident_processor)
        )
        
        # Rule for custom actions
        custom_action_rule = events.Rule(
            self,
            "SecurityHubCustomActionRule",
            rule_name="security-hub-custom-escalation",
            description="Process manual escalation from Security Hub",
            event_pattern=events.EventPattern(
                source=["aws.securityhub"],
                detail_type=["Security Hub Findings - Custom Action"],
                detail={
                    "actionName": ["Escalate to SOC"],
                    "actionDescription": ["Escalate this finding to the Security Operations Center"]
                }
            )
        )
        
        # Add Lambda target to custom action rule
        custom_action_rule.add_target(
            targets.LambdaFunction(self.incident_processor)
        )
        
        # Rule for threat intelligence enrichment
        threat_intel_rule = events.Rule(
            self,
            "SecurityHubThreatIntelRule",
            rule_name="security-hub-threat-intelligence",
            description="Enrich findings with threat intelligence",
            event_pattern=events.EventPattern(
                source=["aws.securityhub"],
                detail_type=["Security Hub Findings - Imported"],
                detail={
                    "findings": {
                        "Severity": {
                            "Label": ["MEDIUM", "HIGH", "CRITICAL"]
                        }
                    }
                }
            )
        )
        
        # Add Lambda target to threat intelligence rule
        threat_intel_rule.add_target(
            targets.LambdaFunction(self.threat_intelligence)
        )

    def _create_security_hub_custom_actions(self) -> None:
        """Create Security Hub custom actions for manual escalation"""
        
        # Custom action for SOC escalation
        soc_escalation_action = securityhub.CfnActionTarget(
            self,
            "SOCEscalationAction",
            name="Escalate to SOC",
            description="Escalate this finding to the Security Operations Center",
            id="escalate-to-soc"
        )

    def _create_monitoring_dashboard(self) -> None:
        """Create CloudWatch dashboard for monitoring incident response"""
        
        dashboard = cloudwatch.Dashboard(
            self,
            "SecurityIncidentResponseDashboard",
            dashboard_name="SecurityHubIncidentResponse"
        )
        
        # Lambda metrics widget
        lambda_metrics_widget = cloudwatch.GraphWidget(
            title="Security Incident Processing Metrics",
            left=[
                self.incident_processor.metric_invocations(period=Duration.minutes(5)),
                self.incident_processor.metric_errors(period=Duration.minutes(5)),
                self.incident_processor.metric_duration(period=Duration.minutes(5))
            ],
            width=12,
            height=6
        )
        
        # SNS metrics widget
        sns_metrics_widget = cloudwatch.GraphWidget(
            title="Notification Delivery Metrics",
            left=[
                self.incident_topic.metric_number_of_messages_published(period=Duration.minutes(5)),
                self.incident_topic.metric_number_of_notifications_failed(period=Duration.minutes(5))
            ],
            width=12,
            height=6
        )
        
        # Add widgets to dashboard
        dashboard.add_widgets(lambda_metrics_widget)
        dashboard.add_widgets(sns_metrics_widget)
        
        # Create CloudWatch alarm for failed incident processing
        incident_processing_alarm = cloudwatch.Alarm(
            self,
            "IncidentProcessingFailureAlarm",
            alarm_name="SecurityHubIncidentProcessingFailures",
            alarm_description="Alert when Security Hub incident processing fails",
            metric=self.incident_processor.metric_errors(period=Duration.minutes(5)),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
        )
        
        # Add SNS action to alarm
        incident_processing_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.incident_topic)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs"""
        
        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.incident_topic.topic_arn,
            description="ARN of the SNS topic for security incident notifications"
        )
        
        CfnOutput(
            self,
            "SQSQueueUrl",
            value=self.incident_queue.queue_url,
            description="URL of the SQS queue for external system integration"
        )
        
        CfnOutput(
            self,
            "IncidentProcessorFunctionName",
            value=self.incident_processor.function_name,
            description="Name of the Lambda function that processes security incidents"
        )
        
        CfnOutput(
            self,
            "ThreatIntelligenceFunctionName",
            value=self.threat_intelligence.function_name,
            description="Name of the Lambda function that enriches findings with threat intelligence"
        )
        
        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name=SecurityHubIncidentResponse",
            description="URL to the CloudWatch dashboard for monitoring incident response"
        )