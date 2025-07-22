#!/usr/bin/env python3
"""
AWS CDK Python Application for DNS Security Monitoring

This CDK application implements automated DNS security monitoring using:
- Route 53 Resolver DNS Firewall for threat filtering
- CloudWatch for metrics analysis and alerting  
- Lambda for automated response actions
- SNS for security notifications

Author: AWS Recipes Team
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_route53resolver as resolver,
    aws_logs as logs,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cw_actions,
    aws_ec2 as ec2,
)
from constructs import Construct
from typing import Dict, List, Optional
import json


class DnsSecurityMonitoringStack(Stack):
    """
    CDK Stack for DNS Security Monitoring Solution
    
    This stack creates a comprehensive DNS security monitoring solution that:
    - Filters malicious DNS queries using Route 53 Resolver DNS Firewall
    - Monitors DNS activity with CloudWatch metrics and logs
    - Provides automated incident response through Lambda functions
    - Sends security alerts via SNS notifications
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        vpc_id: Optional[str] = None,
        notification_email: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the DNS Security Monitoring Stack
        
        Args:
            scope: CDK app or parent construct
            construct_id: Unique identifier for this stack
            vpc_id: Optional VPC ID to associate with DNS Firewall (uses default VPC if not provided)
            notification_email: Optional email address for security alerts
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Get VPC - use provided VPC ID or default VPC
        if vpc_id:
            vpc = ec2.Vpc.from_lookup(self, "ExistingVPC", vpc_id=vpc_id)
        else:
            vpc = ec2.Vpc.from_lookup(self, "DefaultVPC", is_default=True)

        # Create SNS topic for security alerts
        self.sns_topic = self._create_sns_topic(notification_email)
        
        # Create DNS Firewall domain list and rule group
        domain_list = self._create_dns_firewall_domain_list()
        rule_group = self._create_dns_firewall_rule_group(domain_list)
        
        # Associate DNS Firewall with VPC
        self._associate_dns_firewall_with_vpc(rule_group, vpc)
        
        # Create CloudWatch log group for DNS queries
        log_group = self._create_cloudwatch_log_group()
        
        # Create DNS query logging configuration
        self._create_dns_query_logging(log_group, vpc)
        
        # Create Lambda function for automated response
        lambda_function = self._create_security_response_lambda()
        
        # Configure CloudWatch alarms for threat detection
        self._create_cloudwatch_alarms(rule_group, vpc, lambda_function)
        
        # Output important resource information
        self._create_stack_outputs(rule_group, log_group, lambda_function)

    def _create_sns_topic(self, notification_email: Optional[str]) -> sns.Topic:
        """
        Create SNS topic for DNS security alerts
        
        Args:
            notification_email: Optional email address to subscribe to alerts
            
        Returns:
            SNS Topic for security notifications
        """
        topic = sns.Topic(
            self,
            "DnsSecurityAlerts",
            topic_name="dns-security-alerts",
            display_name="DNS Security Monitoring Alerts",
            description="SNS topic for DNS security monitoring alerts and notifications"
        )
        
        # Subscribe email if provided
        if notification_email:
            topic.add_subscription(
                subscriptions.EmailSubscription(notification_email)
            )
        
        # Add tags for resource management
        cdk.Tags.of(topic).add("Purpose", "DNS-Security-Monitoring")
        cdk.Tags.of(topic).add("Component", "Notification")
        
        return topic

    def _create_dns_firewall_domain_list(self) -> resolver.CfnFirewallDomainList:
        """
        Create DNS Firewall domain list with malicious domains
        
        Returns:
            DNS Firewall domain list resource
        """
        # Sample malicious domains for demonstration
        # In production, populate with threat intelligence feeds
        malicious_domains = [
            "malware.example",
            "suspicious.tk", 
            "phishing.com",
            "badactor.ru",
            "cryptominer.xyz",
            "botnet.info"
        ]
        
        domain_list = resolver.CfnFirewallDomainList(
            self,
            "MaliciousDomainList",
            name="malicious-domains-list",
            domains=malicious_domains,
            tags=[
                cdk.CfnTag(key="Purpose", value="DNS-Security-Monitoring"),
                cdk.CfnTag(key="Component", value="DomainList")
            ]
        )
        
        return domain_list

    def _create_dns_firewall_rule_group(
        self, 
        domain_list: resolver.CfnFirewallDomainList
    ) -> resolver.CfnFirewallRuleGroup:
        """
        Create DNS Firewall rule group with security rules
        
        Args:
            domain_list: Domain list containing malicious domains
            
        Returns:
            DNS Firewall rule group
        """
        # Create firewall rule for blocking malicious domains
        firewall_rules = [
            resolver.CfnFirewallRuleGroup.FirewallRuleProperty(
                action="BLOCK",
                block_response="NXDOMAIN",
                firewall_domain_list_id=domain_list.attr_id,
                name="block-malicious-domains",
                priority=100
            )
        ]
        
        rule_group = resolver.CfnFirewallRuleGroup(
            self,
            "DnsSecurityRuleGroup",
            name="dns-security-rules",
            firewall_rules=firewall_rules,
            tags=[
                cdk.CfnTag(key="Purpose", value="DNS-Security-Monitoring"),
                cdk.CfnTag(key="Component", value="RuleGroup")
            ]
        )
        
        return rule_group

    def _associate_dns_firewall_with_vpc(
        self, 
        rule_group: resolver.CfnFirewallRuleGroup, 
        vpc: ec2.IVpc
    ) -> resolver.CfnFirewallRuleGroupAssociation:
        """
        Associate DNS Firewall rule group with VPC
        
        Args:
            rule_group: DNS Firewall rule group to associate
            vpc: VPC to protect with DNS Firewall
            
        Returns:
            Firewall rule group association
        """
        association = resolver.CfnFirewallRuleGroupAssociation(
            self,
            "DnsFirewallAssociation",
            firewall_rule_group_id=rule_group.attr_id,
            name="vpc-dns-security-association",
            priority=101,
            vpc_id=vpc.vpc_id,
            tags=[
                cdk.CfnTag(key="Purpose", value="DNS-Security-Monitoring"),
                cdk.CfnTag(key="Component", value="Association")
            ]
        )
        
        return association

    def _create_cloudwatch_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch log group for DNS query analysis
        
        Returns:
            CloudWatch log group for DNS queries
        """
        log_group = logs.LogGroup(
            self,
            "DnsSecurityLogGroup",
            log_group_name="/aws/route53resolver/dns-security",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Add tags for resource management
        cdk.Tags.of(log_group).add("Purpose", "DNS-Security-Monitoring")
        cdk.Tags.of(log_group).add("Component", "Logging")
        
        return log_group

    def _create_dns_query_logging(
        self, 
        log_group: logs.LogGroup, 
        vpc: ec2.IVpc
    ) -> resolver.CfnResolverQueryLoggingConfig:
        """
        Create DNS query logging configuration
        
        Args:
            log_group: CloudWatch log group for DNS queries
            vpc: VPC to enable query logging for
            
        Returns:
            DNS query logging configuration
        """
        # Create query logging configuration
        query_log_config = resolver.CfnResolverQueryLoggingConfig(
            self,
            "DnsQueryLoggingConfig",
            destination_arn=log_group.log_group_arn,
            name="dns-security-query-logging"
        )
        
        # Associate query logging with VPC
        resolver.CfnResolverQueryLoggingConfigAssociation(
            self,
            "QueryLoggingAssociation",
            resolver_query_log_config_id=query_log_config.attr_id,
            resource_id=vpc.vpc_id
        )
        
        return query_log_config

    def _create_security_response_lambda(self) -> lambda_.Function:
        """
        Create Lambda function for automated DNS security response
        
        Returns:
            Lambda function for security response automation
        """
        # Create IAM role for Lambda execution
        lambda_role = iam.Role(
            self,
            "DnsSecurityLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "CloudWatchMetricsPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "cloudwatch:GetMetricStatistics",
                                "cloudwatch:ListMetrics"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )
        
        # Lambda function code for security response
        lambda_code = '''
import json
import boto3
import logging
from datetime import datetime
from typing import Dict, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process DNS security alerts and execute automated response actions
    
    Args:
        event: CloudWatch alarm event data
        context: Lambda execution context
        
    Returns:
        Response indicating processing status
    """
    try:
        # Parse CloudWatch alarm data from SNS message
        message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = message['AlarmName']
        alarm_description = message.get('AlarmDescription', 'No description')
        metric_name = message['Trigger']['MetricName']
        
        # Log security event for audit trail
        logger.info(f"Processing DNS security event: {alarm_name}")
        logger.info(f"Metric: {metric_name}")
        logger.info(f"Description: {alarm_description}")
        
        # Create detailed alert context
        alert_context = {
            'alarm_name': alarm_name,
            'alarm_description': alarm_description,
            'metric_name': metric_name,
            'timestamp': datetime.now().isoformat(),
            'account_id': context.invoked_function_arn.split(':')[4],
            'region': context.invoked_function_arn.split(':')[3]
        }
        
        # Execute security response actions based on alarm type
        if "Block-Rate" in alarm_name:
            response = handle_high_block_rate_alert(alert_context)
        elif "Volume" in alarm_name:
            response = handle_unusual_volume_alert(alert_context)
        else:
            response = handle_generic_security_alert(alert_context)
        
        logger.info(f"Security response completed: {response}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'DNS security alert processed successfully',
                'alarm': alarm_name,
                'response': response
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing DNS security alert: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def handle_high_block_rate_alert(context: Dict[str, str]) -> str:
    """Handle high DNS block rate alerts indicating potential attacks"""
    logger.warning(f"High DNS block rate detected in {context['region']}")
    # In production, implement additional response actions:
    # - Update Security Groups
    # - Create incident tickets
    # - Trigger additional monitoring
    return "High block rate response executed"

def handle_unusual_volume_alert(context: Dict[str, str]) -> str:
    """Handle unusual DNS query volume alerts"""
    logger.warning(f"Unusual DNS query volume detected in {context['region']}")
    # In production, implement volume-specific responses:
    # - Rate limiting
    # - Traffic analysis
    # - DDoS mitigation
    return "Unusual volume response executed"

def handle_generic_security_alert(context: Dict[str, str]) -> str:
    """Handle generic DNS security alerts"""
    logger.info(f"Generic DNS security alert processed for {context['alarm_name']}")
    return "Generic security response executed"
'''
        
        # Create Lambda function
        lambda_function = lambda_.Function(
            self,
            "DnsSecurityResponseFunction",
            function_name="dns-security-response",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=lambda_role,
            timeout=Duration.minutes(1),
            memory_size=256,
            description="Automated DNS security incident response function",
            environment={
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn
            }
        )
        
        # Grant SNS permission to invoke Lambda
        lambda_function.add_permission(
            "AllowSnsInvoke",
            principal=iam.ServicePrincipal("sns.amazonaws.com"),
            action="lambda:InvokeFunction",
            source_arn=self.sns_topic.topic_arn
        )
        
        # Subscribe Lambda to SNS topic
        self.sns_topic.add_subscription(
            subscriptions.LambdaSubscription(lambda_function)
        )
        
        # Add tags for resource management
        cdk.Tags.of(lambda_function).add("Purpose", "DNS-Security-Monitoring")
        cdk.Tags.of(lambda_function).add("Component", "AutomatedResponse")
        
        return lambda_function

    def _create_cloudwatch_alarms(
        self, 
        rule_group: resolver.CfnFirewallRuleGroup,
        vpc: ec2.IVpc,
        lambda_function: lambda_.Function
    ) -> List[cloudwatch.Alarm]:
        """
        Create CloudWatch alarms for DNS threat detection
        
        Args:
            rule_group: DNS Firewall rule group to monitor
            vpc: VPC to monitor DNS activity for
            lambda_function: Lambda function to trigger on alarms
            
        Returns:
            List of CloudWatch alarms for DNS monitoring
        """
        alarms = []
        
        # Alarm for high DNS block rate (potential attacks)
        block_rate_alarm = cloudwatch.Alarm(
            self,
            "DnsHighBlockRateAlarm",
            alarm_name="DNS-High-Block-Rate",
            alarm_description="High rate of blocked DNS queries detected - potential security threat",
            metric=cloudwatch.Metric(
                namespace="AWS/Route53Resolver",
                metric_name="QueryCount",
                dimensions_map={
                    "FirewallRuleGroupId": rule_group.attr_id
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=50,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Add SNS action to alarm
        block_rate_alarm.add_alarm_action(
            cw_actions.SnsAction(self.sns_topic)
        )
        
        alarms.append(block_rate_alarm)
        
        # Alarm for unusual DNS query volume
        volume_alarm = cloudwatch.Alarm(
            self,
            "DnsUnusualVolumeAlarm", 
            alarm_name="DNS-Unusual-Volume",
            alarm_description="Unusual DNS query volume detected - potential DDoS or scanning activity",
            metric=cloudwatch.Metric(
                namespace="AWS/Route53Resolver",
                metric_name="QueryCount",
                dimensions_map={
                    "VpcId": vpc.vpc_id
                },
                statistic="Sum",
                period=Duration.minutes(15)
            ),
            threshold=1000,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Add SNS action to alarm
        volume_alarm.add_alarm_action(
            cw_actions.SnsAction(self.sns_topic)
        )
        
        alarms.append(volume_alarm)
        
        # Add tags to alarms
        for alarm in alarms:
            cdk.Tags.of(alarm).add("Purpose", "DNS-Security-Monitoring")
            cdk.Tags.of(alarm).add("Component", "Alerting")
        
        return alarms

    def _create_stack_outputs(
        self,
        rule_group: resolver.CfnFirewallRuleGroup,
        log_group: logs.LogGroup,
        lambda_function: lambda_.Function
    ) -> None:
        """
        Create CloudFormation outputs for important resources
        
        Args:
            rule_group: DNS Firewall rule group
            log_group: CloudWatch log group for DNS queries
            lambda_function: Security response Lambda function
        """
        cdk.CfnOutput(
            self,
            "DnsFirewallRuleGroupId",
            value=rule_group.attr_id,
            description="DNS Firewall Rule Group ID",
            export_name=f"{self.stack_name}-DnsFirewallRuleGroupId"
        )
        
        cdk.CfnOutput(
            self,
            "DnsSecurityLogGroupName",
            value=log_group.log_group_name,
            description="CloudWatch Log Group for DNS Security Monitoring",
            export_name=f"{self.stack_name}-DnsSecurityLogGroupName"
        )
        
        cdk.CfnOutput(
            self,
            "SecurityResponseFunctionArn",
            value=lambda_function.function_arn,
            description="DNS Security Response Lambda Function ARN",
            export_name=f"{self.stack_name}-SecurityResponseFunctionArn"
        )
        
        cdk.CfnOutput(
            self,
            "SnsTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS Topic ARN for DNS Security Alerts",
            export_name=f"{self.stack_name}-SnsTopicArn"
        )


def main() -> None:
    """
    Main function to create and deploy the CDK application
    """
    app = cdk.App()
    
    # Get configuration from CDK context or environment variables
    vpc_id = app.node.try_get_context("vpc_id")
    notification_email = app.node.try_get_context("notification_email")
    
    # Create the DNS Security Monitoring stack
    DnsSecurityMonitoringStack(
        app, 
        "DnsSecurityMonitoringStack",
        vpc_id=vpc_id,
        notification_email=notification_email,
        description="Automated DNS Security Monitoring with Route 53 Resolver DNS Firewall and CloudWatch",
        env=cdk.Environment(
            account=app.account,
            region=app.region
        )
    )
    
    app.synth()


if __name__ == "__main__":
    main()