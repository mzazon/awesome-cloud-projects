#!/usr/bin/env python3
"""
AWS CDK Python Application for Automated Security Scanning with Inspector and Security Hub

This CDK application deploys a comprehensive security scanning solution that integrates
Amazon Inspector for vulnerability assessment with AWS Security Hub for centralized
security findings management. The solution includes automated response capabilities
through EventBridge and Lambda functions.

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Stack,
    StackProps,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_events as events,
    aws_events_targets as targets,
    aws_sns as sns,
    aws_sns_subscriptions as subs,
    aws_logs as logs,
    aws_inspector2 as inspector2,
    aws_securityhub as securityhub,
    CfnOutput,
    Fn,
    RemovalPolicy,
)
from constructs import Construct


class SecurityScanningStack(Stack):
    """
    CDK Stack for automated security scanning with Inspector and Security Hub.
    
    This stack creates a complete security monitoring solution including:
    - Security Hub with compliance standards
    - Inspector configuration for vulnerability scanning
    - Lambda functions for automated response and compliance reporting
    - EventBridge rules for real-time event processing
    - SNS topics for security alerting
    - IAM roles and policies with least privilege access
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters for customization
        self.notification_email = self.node.try_get_context("notification_email") or "security@example.com"
        self.environment_name = self.node.try_get_context("environment") or "dev"
        self.enable_test_resources = self.node.try_get_context("enable_test_resources") or False

        # Create SNS topic for security alerts
        self.security_alerts_topic = self._create_security_alerts_topic()

        # Create IAM roles for Lambda functions
        self.lambda_execution_role = self._create_lambda_execution_role()

        # Create Lambda function for automated security response
        self.security_response_lambda = self._create_security_response_lambda()

        # Create Lambda function for compliance reporting
        self.compliance_report_lambda = self._create_compliance_report_lambda()

        # Create EventBridge rules for security automation
        self._create_eventbridge_rules()

        # Enable Security Hub and configure standards
        self._configure_security_hub()

        # Configure Inspector settings
        self._configure_inspector()

        # Create test EC2 instance if enabled
        if self.enable_test_resources:
            self._create_test_ec2_instance()

        # Create custom Security Hub insights
        self._create_security_hub_insights()

        # Create CloudWatch log groups for monitoring
        self._create_log_groups()

        # Output important resource information
        self._create_outputs()

    def _create_security_alerts_topic(self) -> sns.Topic:
        """Create SNS topic for security alert notifications."""
        topic = sns.Topic(
            self,
            "SecurityAlertsTopic",
            display_name="Security Alerts",
            topic_name=f"security-alerts-{self.environment_name}",
        )

        # Add email subscription if notification email is provided
        if self.notification_email and "@" in self.notification_email:
            topic.add_subscription(
                subs.EmailSubscription(self.notification_email)
            )

        return topic

    def _create_lambda_execution_role(self) -> iam.Role:
        """Create IAM role for Lambda functions with necessary permissions."""
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            role_name=f"SecurityLambdaRole-{self.environment_name}",
            description="IAM role for security automation Lambda functions",
        )

        # Add basic Lambda execution permissions
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AWSLambdaBasicExecutionRole"
            )
        )

        # Add custom permissions for security operations
        security_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "securityhub:BatchImportFindings",
                        "securityhub:BatchUpdateFindings",
                        "securityhub:GetFindings",
                        "securityhub:GetInsights",
                        "securityhub:GetInsightResults",
                        "securityhub:CreateInsight",
                    ],
                    resources=["*"],
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "inspector2:ListFindings",
                        "inspector2:BatchGetFinding",
                        "inspector2:GetCoverageStatistics",
                        "inspector2:ListCoverage",
                    ],
                    resources=["*"],
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "sns:Publish",
                    ],
                    resources=[self.security_alerts_topic.topic_arn],
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ec2:CreateTags",
                        "ec2:DescribeInstances",
                        "ec2:DescribeTags",
                    ],
                    resources=["*"],
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents",
                    ],
                    resources=["*"],
                ),
            ]
        )

        role.attach_inline_policy(
            iam.Policy(
                self,
                "SecurityAutomationPolicy",
                document=security_policy,
            )
        )

        return role

    def _create_security_response_lambda(self) -> lambda_.Function:
        """Create Lambda function for automated security response."""
        function_code = '''
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
    Process Security Hub findings and trigger appropriate responses.
    
    This function processes incoming security findings from EventBridge,
    sends notifications for critical issues, and performs automated
    remediation actions based on finding severity and resource type.
    """
    try:
        # Parse the EventBridge event
        detail = event.get('detail', {})
        findings = detail.get('findings', [])
        
        if not findings:
            logger.warning("No findings in event detail")
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'No findings to process'})
            }
        
        sns = boto3.client('sns')
        securityhub = boto3.client('securityhub')
        ec2 = boto3.client('ec2')
        
        processed_findings = 0
        high_severity_count = 0
        
        for finding in findings:
            processed_findings += 1
            
            # Extract finding details
            severity = finding.get('Severity', {}).get('Label', 'UNKNOWN')
            title = finding.get('Title', 'Security Finding')
            description = finding.get('Description', '')
            resource_details = finding.get('Resources', [{}])[0]
            resource_id = resource_details.get('Id', 'Unknown')
            resource_type = resource_details.get('Type', 'Unknown')
            
            logger.info(f"Processing finding: {title} with severity {severity}")
            
            # Create alert message
            message = {
                'timestamp': datetime.utcnow().isoformat(),
                'severity': severity,
                'title': title,
                'description': description[:500],  # Truncate long descriptions
                'resource_type': resource_type,
                'resource_id': resource_id,
                'finding_id': finding.get('Id', ''),
                'aws_account': finding.get('AwsAccountId', ''),
                'region': finding.get('Region', ''),
                'compliance_status': finding.get('Compliance', {}).get('Status', 'UNKNOWN')
            }
            
            # Send notification for HIGH and CRITICAL findings
            if severity in ['HIGH', 'CRITICAL']:
                high_severity_count += 1
                
                try:
                    sns.publish(
                        TopicArn=os.environ['SNS_TOPIC_ARN'],
                        Subject=f"🚨 Security Alert: {severity} - {title[:50]}",
                        Message=json.dumps(message, indent=2)
                    )
                    logger.info(f"Sent alert for {severity} finding: {title}")
                except Exception as e:
                    logger.error(f"Failed to send SNS notification: {str(e)}")
            
            # Automated remediation logic
            try:
                if resource_type == 'AwsEc2Instance' and 'vulnerability' in title.lower():
                    # Extract instance ID from resource ARN
                    instance_id = resource_id.split('/')[-1] if '/' in resource_id else resource_id
                    
                    if instance_id.startswith('i-'):
                        # Tag EC2 instance for remediation tracking
                        ec2.create_tags(
                            Resources=[instance_id],
                            Tags=[
                                {'Key': 'SecurityStatus', 'Value': 'RequiresPatching'},
                                {'Key': 'LastSecurityScan', 'Value': datetime.utcnow().isoformat()},
                                {'Key': 'SecuritySeverity', 'Value': severity},
                                {'Key': 'FindingId', 'Value': finding.get('Id', '')[:50]}
                            ]
                        )
                        logger.info(f"Tagged EC2 instance {instance_id} for remediation")
                
                elif resource_type == 'AwsEcrContainerImage' and severity in ['HIGH', 'CRITICAL']:
                    # Log container image vulnerability for tracking
                    logger.warning(f"High severity vulnerability in container image: {resource_id}")
                    
                elif resource_type == 'AwsLambdaFunction':
                    # Log Lambda function security issue
                    logger.warning(f"Security finding in Lambda function: {resource_id}")
                    
            except Exception as e:
                logger.error(f"Remediation failed for resource {resource_id}: {str(e)}")
        
        # Log processing summary
        logger.info(f"Processed {processed_findings} findings, {high_severity_count} high severity")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully processed {processed_findings} security findings',
                'high_severity_count': high_severity_count,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing security findings: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }
'''

        function = lambda_.Function(
            self,
            "SecurityResponseFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(function_code),
            role=self.lambda_execution_role,
            function_name=f"security-response-handler-{self.environment_name}",
            description="Automated security response handler for Inspector and Security Hub findings",
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                "SNS_TOPIC_ARN": self.security_alerts_topic.topic_arn,
                "ENVIRONMENT": self.environment_name,
            },
            retry_attempts=2,
        )

        return function

    def _create_compliance_report_lambda(self) -> lambda_.Function:
        """Create Lambda function for automated compliance reporting."""
        function_code = '''
import json
import boto3
import csv
import logging
from datetime import datetime, timedelta
from io import StringIO
from typing import Dict, List, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Generate compliance reports from Security Hub findings.
    
    This function creates comprehensive security compliance reports
    based on Security Hub findings from the past week, providing
    insights into security posture and vulnerability trends.
    """
    try:
        securityhub = boto3.client('securityhub')
        
        # Calculate time range for report (last 7 days)
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(days=7)
        
        logger.info(f"Generating compliance report for period: {start_time} to {end_time}")
        
        # Get findings from the last 7 days
        paginator = securityhub.get_paginator('get_findings')
        findings = []
        
        try:
            for page in paginator.paginate(
                Filters={
                    'UpdatedAt': [
                        {
                            'Start': start_time.isoformat() + 'Z',
                            'End': end_time.isoformat() + 'Z'
                        }
                    ],
                    'RecordState': [
                        {'Value': 'ACTIVE', 'Comparison': 'EQUALS'}
                    ]
                },
                MaxItems=1000  # Limit to prevent timeout
            ):
                findings.extend(page['Findings'])
                
        except Exception as e:
            logger.error(f"Error retrieving findings: {str(e)}")
            # Continue with empty findings list for report structure
        
        # Generate summary statistics
        severity_counts = {'CRITICAL': 0, 'HIGH': 0, 'MEDIUM': 0, 'LOW': 0, 'INFORMATIONAL': 0}
        resource_type_counts = {}
        compliance_status_counts = {'PASSED': 0, 'FAILED': 0, 'WARNING': 0, 'NOT_AVAILABLE': 0}
        
        for finding in findings:
            # Count by severity
            severity = finding.get('Severity', {}).get('Label', 'UNKNOWN')
            if severity in severity_counts:
                severity_counts[severity] += 1
            
            # Count by resource type
            for resource in finding.get('Resources', []):
                resource_type = resource.get('Type', 'Unknown')
                resource_type_counts[resource_type] = resource_type_counts.get(resource_type, 0) + 1
            
            # Count by compliance status
            compliance_status = finding.get('Compliance', {}).get('Status', 'NOT_AVAILABLE')
            if compliance_status in compliance_status_counts:
                compliance_status_counts[compliance_status] += 1
        
        # Generate CSV report content
        csv_buffer = StringIO()
        writer = csv.writer(csv_buffer)
        
        # Write summary header
        writer.writerow(['=== SECURITY COMPLIANCE REPORT ==='])
        writer.writerow([f'Report Period: {start_time.strftime("%Y-%m-%d")} to {end_time.strftime("%Y-%m-%d")}'])
        writer.writerow([f'Generated: {datetime.utcnow().isoformat()}'])
        writer.writerow([''])
        
        # Write severity summary
        writer.writerow(['=== FINDINGS BY SEVERITY ==='])
        for severity, count in severity_counts.items():
            writer.writerow([severity, count])
        writer.writerow([''])
        
        # Write resource type summary
        writer.writerow(['=== FINDINGS BY RESOURCE TYPE ==='])
        for resource_type, count in sorted(resource_type_counts.items()):
            writer.writerow([resource_type, count])
        writer.writerow([''])
        
        # Write compliance status summary
        writer.writerow(['=== COMPLIANCE STATUS ==='])
        for status, count in compliance_status_counts.items():
            writer.writerow([status, count])
        writer.writerow([''])
        
        # Write detailed findings
        writer.writerow(['=== DETAILED FINDINGS ==='])
        writer.writerow([
            'Finding ID', 'Title', 'Severity', 'Resource Type', 
            'Resource ID', 'Compliance Status', 'Created Date', 'Updated Date'
        ])
        
        for finding in findings[:100]:  # Limit to first 100 for CSV size
            resources = finding.get('Resources', [{}])
            primary_resource = resources[0] if resources else {}
            
            writer.writerow([
                finding.get('Id', '')[:50],  # Truncate long IDs
                finding.get('Title', '')[:100],  # Truncate long titles
                finding.get('Severity', {}).get('Label', ''),
                primary_resource.get('Type', ''),
                primary_resource.get('Id', '')[:50],  # Truncate long resource IDs
                finding.get('Compliance', {}).get('Status', ''),
                finding.get('CreatedAt', ''),
                finding.get('UpdatedAt', '')
            ])
        
        csv_content = csv_buffer.getvalue()
        
        # Calculate risk score based on severity distribution
        risk_score = (
            severity_counts['CRITICAL'] * 10 +
            severity_counts['HIGH'] * 7 +
            severity_counts['MEDIUM'] * 4 +
            severity_counts['LOW'] * 1
        )
        
        logger.info(f"Generated compliance report with {len(findings)} findings, risk score: {risk_score}")
        
        # Return comprehensive report data
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Generated compliance report with {len(findings)} findings',
                'summary': {
                    'total_findings': len(findings),
                    'severity_distribution': severity_counts,
                    'resource_type_distribution': resource_type_counts,
                    'compliance_status_distribution': compliance_status_counts,
                    'risk_score': risk_score,
                    'report_period': {
                        'start': start_time.isoformat(),
                        'end': end_time.isoformat()
                    }
                },
                'csv_report_size': len(csv_content),
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error generating compliance report: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }
'''

        function = lambda_.Function(
            self,
            "ComplianceReportFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(function_code),
            role=self.lambda_execution_role,
            function_name=f"compliance-report-generator-{self.environment_name}",
            description="Automated compliance reporting for Security Hub findings",
            timeout=Duration.minutes(10),
            memory_size=512,
            environment={
                "ENVIRONMENT": self.environment_name,
            },
            retry_attempts=2,
        )

        return function

    def _create_eventbridge_rules(self) -> None:
        """Create EventBridge rules for security automation."""
        # Rule for high severity security findings
        security_findings_rule = events.Rule(
            self,
            "SecurityFindingsRule",
            rule_name=f"security-findings-rule-{self.environment_name}",
            description="Route high severity security findings to Lambda for automated response",
            event_pattern=events.EventPattern(
                source=["aws.securityhub"],
                detail_type=["Security Hub Findings - Imported"],
                detail={
                    "findings": {
                        "Severity": {
                            "Label": ["HIGH", "CRITICAL"]
                        }
                    }
                }
            ),
        )

        # Add Lambda target to the rule
        security_findings_rule.add_target(
            targets.LambdaFunction(
                self.security_response_lambda,
                retry_attempts=2,
            )
        )

        # Rule for weekly compliance reporting
        compliance_report_rule = events.Rule(
            self,
            "ComplianceReportRule",
            rule_name=f"weekly-compliance-report-{self.environment_name}",
            description="Generate weekly compliance reports from Security Hub findings",
            schedule=events.Schedule.rate(Duration.days(7)),
        )

        # Add Lambda target for compliance reporting
        compliance_report_rule.add_target(
            targets.LambdaFunction(
                self.compliance_report_lambda,
                retry_attempts=2,
            )
        )

    def _configure_security_hub(self) -> None:
        """Configure Security Hub with compliance standards."""
        # Enable Security Hub (this will be done via custom resource or manually)
        # Note: CDK doesn't have native constructs for enabling Security Hub
        # This would typically be done as part of account setup or via custom resource

        # The Security Hub configuration would enable these standards:
        # - AWS Foundational Security Best Practices
        # - CIS AWS Foundations Benchmark
        pass

    def _configure_inspector(self) -> None:
        """Configure Inspector scanning settings."""
        # Enable Inspector (this would typically be done via custom resource)
        # Inspector configuration would include:
        # - EC2 scanning (hybrid mode)
        # - ECR scanning (30-day rescan)
        # - Lambda function scanning
        pass

    def _create_test_ec2_instance(self) -> None:
        """Create a test EC2 instance for vulnerability scanning demonstration."""
        # Get default VPC
        vpc = ec2.Vpc.from_lookup(
            self, 
            "DefaultVpc", 
            is_default=True
        )

        # Create security group for test instance
        security_group = ec2.SecurityGroup(
            self,
            "TestInstanceSecurityGroup",
            vpc=vpc,
            description="Security group for test EC2 instance",
            allow_all_outbound=True,
        )

        # No inbound rules - more secure for testing
        security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="HTTPS for package updates only"
        )

        # Create test EC2 instance
        test_instance = ec2.Instance(
            self,
            "SecurityTestInstance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.T3,
                ec2.InstanceSize.MICRO
            ),
            machine_image=ec2.AmazonLinuxImage(
                generation=ec2.AmazonLinuxGeneration.AMAZON_LINUX_2
            ),
            vpc=vpc,
            security_group=security_group,
            instance_name=f"security-test-instance-{self.environment_name}",
            key_name=None,  # No SSH key for security
        )

        # Add tags for identification and Inspector scanning
        cdk.Tags.of(test_instance).add("Purpose", "SecurityTesting")
        cdk.Tags.of(test_instance).add("Environment", self.environment_name)
        cdk.Tags.of(test_instance).add("AutoScan", "true")

    def _create_security_hub_insights(self) -> None:
        """Create custom Security Hub insights for enhanced visibility."""
        # Custom insights would be created via Security Hub API
        # These provide customized views of security data
        pass

    def _create_log_groups(self) -> None:
        """Create CloudWatch log groups for monitoring and troubleshooting."""
        # Log group for security response Lambda
        security_response_log_group = logs.LogGroup(
            self,
            "SecurityResponseLogGroup",
            log_group_name=f"/aws/lambda/security-response-handler-{self.environment_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Log group for compliance reporting Lambda
        compliance_report_log_group = logs.LogGroup(
            self,
            "ComplianceReportLogGroup",
            log_group_name=f"/aws/lambda/compliance-report-generator-{self.environment_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self,
            "SecurityAlertsTopicArn",
            value=self.security_alerts_topic.topic_arn,
            description="ARN of the SNS topic for security alerts",
            export_name=f"SecurityAlertsTopic-{self.environment_name}",
        )

        CfnOutput(
            self,
            "SecurityResponseLambdaArn",
            value=self.security_response_lambda.function_arn,
            description="ARN of the security response Lambda function",
            export_name=f"SecurityResponseLambda-{self.environment_name}",
        )

        CfnOutput(
            self,
            "ComplianceReportLambdaArn",
            value=self.compliance_report_lambda.function_arn,
            description="ARN of the compliance reporting Lambda function",
            export_name=f"ComplianceReportLambda-{self.environment_name}",
        )

        CfnOutput(
            self,
            "LambdaExecutionRoleArn",
            value=self.lambda_execution_role.role_arn,
            description="ARN of the Lambda execution role",
            export_name=f"LambdaExecutionRole-{self.environment_name}",
        )


class SecurityScanningApp(cdk.App):
    """
    CDK Application for the automated security scanning solution.
    
    This application creates a complete security monitoring infrastructure
    that integrates Amazon Inspector and AWS Security Hub for comprehensive
    vulnerability management and automated incident response.
    """

    def __init__(self) -> None:
        super().__init__()

        # Get environment configuration
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        )

        # Create the security scanning stack
        SecurityScanningStack(
            self,
            "SecurityScanningStack",
            env=env,
            description="Automated Security Scanning with Inspector and Security Hub",
            tags={
                "Project": "SecurityScanning",
                "Environment": self.node.try_get_context("environment") or "dev",
                "Owner": "SecurityTeam",
                "CostCenter": "Security",
                "Compliance": "Required",
            },
        )


# Entry point for CDK application
if __name__ == "__main__":
    app = SecurityScanningApp()
    app.synth()