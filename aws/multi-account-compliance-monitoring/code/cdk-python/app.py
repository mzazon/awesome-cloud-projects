#!/usr/bin/env python3
"""
CDK Python application for implementing cross-account compliance monitoring
with AWS Systems Manager and Security Hub.

This application creates the infrastructure for centralized compliance monitoring
across multiple AWS accounts using Security Hub as the central aggregation point.
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
    aws_cloudtrail as cloudtrail,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_s3 as s3,
    aws_securityhub as securityhub,
    aws_ssm as ssm,
)
from constructs import Construct


class ComplianceMonitoringStack(Stack):
    """
    CDK Stack for cross-account compliance monitoring infrastructure.
    
    This stack creates:
    - Security Hub configuration as organization administrator
    - Cross-account IAM roles for compliance data access
    - Lambda function for automated compliance processing
    - EventBridge rules for event-driven automation
    - CloudTrail for compliance auditing
    - Systems Manager documents for custom compliance checks
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        security_account_id: str,
        member_account_ids: List[str],
        enable_custom_compliance: bool = True,
        compliance_retention_days: int = 90,
        **kwargs
    ) -> None:
        """
        Initialize the Compliance Monitoring Stack.
        
        Args:
            scope: The parent construct
            construct_id: The construct identifier
            security_account_id: The AWS account ID that will serve as Security Hub administrator
            member_account_ids: List of member account IDs to monitor
            enable_custom_compliance: Whether to create custom compliance rules
            compliance_retention_days: Number of days to retain compliance data
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        self.security_account_id = security_account_id
        self.member_account_ids = member_account_ids
        self.enable_custom_compliance = enable_custom_compliance
        self.compliance_retention_days = compliance_retention_days

        # Create unique suffix for resource naming
        self.resource_suffix = cdk.Fn.select(
            2, cdk.Fn.split("/", self.stack_id)
        )

        # Create S3 bucket for CloudTrail logs
        self.cloudtrail_bucket = self._create_cloudtrail_bucket()

        # Create CloudTrail for compliance auditing
        self.cloudtrail = self._create_cloudtrail()

        # Create Lambda execution role
        self.lambda_role = self._create_lambda_execution_role()

        # Create Lambda function for compliance processing
        self.compliance_lambda = self._create_compliance_lambda()

        # Create EventBridge rules for automation
        self.eventbridge_rules = self._create_eventbridge_rules()

        # Create cross-account IAM role template
        self.cross_account_role_template = self._create_cross_account_role_template()

        # Create Systems Manager documents for custom compliance
        if self.enable_custom_compliance:
            self.ssm_documents = self._create_ssm_documents()

        # Create Security Hub configuration
        self.security_hub = self._create_security_hub_config()

        # Output important resource ARNs and configurations
        self._create_outputs()

    def _create_cloudtrail_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for CloudTrail logs with appropriate policies.
        
        Returns:
            S3 bucket configured for CloudTrail logging
        """
        bucket = s3.Bucket(
            self,
            "ComplianceAuditTrailBucket",
            bucket_name=f"compliance-audit-trail-{self.resource_suffix}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            public_write_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ComplianceLogRetention",
                    enabled=True,
                    expiration=Duration.days(self.compliance_retention_days),
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(60),
                        ),
                    ],
                )
            ],
        )

        # Add bucket policy for CloudTrail
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSCloudTrailAclCheck",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("cloudtrail.amazonaws.com")],
                actions=["s3:GetBucketAcl"],
                resources=[bucket.bucket_arn],
            )
        )

        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSCloudTrailWrite",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("cloudtrail.amazonaws.com")],
                actions=["s3:PutObject"],
                resources=[f"{bucket.bucket_arn}/*"],
                conditions={
                    "StringEquals": {"s3:x-amz-acl": "bucket-owner-full-control"}
                },
            )
        )

        return bucket

    def _create_cloudtrail(self) -> cloudtrail.Trail:
        """
        Create CloudTrail for compliance auditing.
        
        Returns:
            CloudTrail configured for multi-region compliance monitoring
        """
        trail = cloudtrail.Trail(
            self,
            "ComplianceAuditTrail",
            trail_name=f"ComplianceAuditTrail-{self.resource_suffix}",
            bucket=self.cloudtrail_bucket,
            include_global_service_events=True,
            is_multi_region_trail=True,
            enable_file_validation=True,
            send_to_cloud_watch_logs=True,
            cloud_watch_logs_retention=logs.RetentionDays.ONE_MONTH,
            event_selectors=[
                cloudtrail.EventSelector(
                    read_write_type=cloudtrail.ReadWriteType.ALL,
                    include_management_events=True,
                    data_events=[
                        cloudtrail.DataEvent(
                            s3_bucket=self.cloudtrail_bucket,
                            s3_object_prefix="compliance/",
                        )
                    ],
                )
            ],
        )

        cdk.Tags.of(trail).add("Purpose", "ComplianceAuditing")
        cdk.Tags.of(trail).add("Environment", "Production")

        return trail

    def _create_lambda_execution_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function execution.
        
        Returns:
            IAM role with necessary permissions for compliance processing
        """
        role = iam.Role(
            self,
            "ComplianceProcessingRole",
            role_name=f"ComplianceProcessingRole-{self.resource_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for compliance processing Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "ComplianceProcessingPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "sts:AssumeRole",
                                "securityhub:BatchImportFindings",
                                "securityhub:BatchUpdateFindings",
                                "ssm:ListComplianceItems",
                                "ssm:GetComplianceSummary",
                                "ssm:ListResourceComplianceSummaries",
                                "ssm:DescribeInstanceInformation",
                            ],
                            resources=["*"],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["sts:AssumeRole"],
                            resources=[
                                f"arn:aws:iam::{account_id}:role/SecurityHubComplianceRole-*"
                                for account_id in self.member_account_ids
                            ],
                        ),
                    ]
                )
            },
        )

        cdk.Tags.of(role).add("Purpose", "ComplianceMonitoring")

        return role

    def _create_compliance_lambda(self) -> lambda_.Function:
        """
        Create Lambda function for automated compliance processing.
        
        Returns:
            Lambda function configured to process compliance events
        """
        function = lambda_.Function(
            self,
            "ComplianceProcessingFunction",
            function_name=f"ComplianceAutomation-{self.resource_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            description="Automated compliance processing for Security Hub",
            environment={
                "SECURITY_ACCOUNT_ID": self.security_account_id,
                "MEMBER_ACCOUNTS": ",".join(self.member_account_ids),
                "CROSS_ACCOUNT_ROLE_NAME": f"SecurityHubComplianceRole-{self.resource_suffix}",
                "EXTERNAL_ID": f"ComplianceMonitoring-{self.resource_suffix}",
            },
            code=lambda_.Code.from_inline("""
import json
import boto3
import uuid
import os
from datetime import datetime
from typing import Dict, List, Any

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    \"\"\"
    Process Systems Manager compliance events and create Security Hub findings.
    
    Args:
        event: EventBridge event containing compliance information
        context: Lambda context object
        
    Returns:
        Response dictionary with processing status
    \"\"\"
    
    # Initialize AWS clients
    sts = boto3.client('sts')
    securityhub = boto3.client('securityhub')
    
    # Parse the EventBridge event
    detail = event.get('detail', {})
    account_id = event.get('account', os.environ.get('SECURITY_ACCOUNT_ID'))
    region = event.get('region', 'us-east-1')
    
    print(f"Processing compliance event for account: {account_id}")
    
    try:
        # Process compliance change event
        if detail.get('eventName') in ['PutComplianceItems', 'DeleteComplianceItems']:
            findings = []
            
            # Determine compliance status and severity
            compliance_status = 'FAILED' if 'NON_COMPLIANT' in str(detail) else 'PASSED'
            severity = 'HIGH' if 'CRITICAL' in str(detail).upper() else 'MEDIUM'
            
            # Create Security Hub finding for compliance event
            finding = {
                'SchemaVersion': '2018-10-08',
                'Id': f"compliance-{account_id}-{str(uuid.uuid4())}",
                'ProductArn': f"arn:aws:securityhub:{region}::product/aws/systems-manager",
                'GeneratorId': 'ComplianceMonitoring',
                'AwsAccountId': account_id,
                'Types': ['Software and Configuration Checks/Vulnerabilities/CVE'],
                'CreatedAt': datetime.utcnow().isoformat() + 'Z',
                'UpdatedAt': datetime.utcnow().isoformat() + 'Z',
                'Severity': {
                    'Label': severity
                },
                'Title': 'Systems Manager Compliance Event Detected',
                'Description': f"Compliance event detected in account {account_id}: {detail.get('eventName', 'Unknown')}",
                'Resources': [
                    {
                        'Type': 'AwsAccount',
                        'Id': f"AWS::::Account:{account_id}",
                        'Region': region
                    }
                ],
                'Compliance': {
                    'Status': compliance_status
                },
                'WorkflowState': 'NEW',
                'RecordState': 'ACTIVE'
            }
            
            # Add resource-specific information if available
            if 'responseElements' in detail:
                response_elements = detail['responseElements']
                if 'resourceId' in response_elements:
                    finding['Resources'].append({
                        'Type': 'AwsEc2Instance',
                        'Id': f"arn:aws:ec2:{region}:{account_id}:instance/{response_elements['resourceId']}",
                        'Region': region
                    })
            
            findings.append(finding)
            
            # Import findings into Security Hub
            if findings:
                response = securityhub.batch_import_findings(
                    Findings=findings
                )
                print(f"Imported {len(findings)} findings to Security Hub")
                print(f"Failed imports: {response.get('FailedCount', 0)}")
                
                if response.get('FailedFindings'):
                    for failed in response['FailedFindings']:
                        print(f"Failed to import finding: {failed}")
        
        # Process Security Hub findings events
        elif event.get('source') == 'aws.securityhub':
            print("Processing Security Hub findings event")
            findings = detail.get('findings', [])
            
            for finding in findings:
                if finding.get('Compliance', {}).get('Status') == 'FAILED':
                    print(f"Processing failed compliance finding: {finding.get('Id')}")
                    # Here you could trigger additional automation or notifications
                    # For example, send to SNS topic, trigger remediation workflow, etc.
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Compliance event processed successfully',
                'eventType': detail.get('eventName', 'Unknown'),
                'accountId': account_id
            })
        }
        
    except Exception as e:
        print(f"Error processing compliance event: {str(e)}")
        import traceback
        traceback.print_exc()
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Error processing compliance event',
                'error': str(e)
            })
        }
"""),
            dead_letter_queue_enabled=True,
            retry_attempts=2,
        )

        cdk.Tags.of(function).add("Purpose", "ComplianceMonitoring")

        return function

    def _create_eventbridge_rules(self) -> List[events.Rule]:
        """
        Create EventBridge rules for compliance automation.
        
        Returns:
            List of EventBridge rules for compliance event processing
        """
        rules = []

        # Rule for Systems Manager compliance events
        ssm_rule = events.Rule(
            self,
            "ComplianceMonitoringRule",
            rule_name=f"ComplianceMonitoringRule-{self.resource_suffix}",
            description="Trigger compliance processing on SSM compliance changes",
            event_pattern=events.EventPattern(
                source=["aws.ssm"],
                detail_type=["AWS API Call via CloudTrail"],
                detail={
                    "eventName": ["PutComplianceItems", "DeleteComplianceItems"]
                },
            ),
            enabled=True,
        )

        ssm_rule.add_target(targets.LambdaFunction(self.compliance_lambda))
        rules.append(ssm_rule)

        # Rule for Security Hub findings
        securityhub_rule = events.Rule(
            self,
            "SecurityHubFindingsRule",
            rule_name=f"SecurityHubFindingsRule-{self.resource_suffix}",
            description="Process Security Hub compliance findings",
            event_pattern=events.EventPattern(
                source=["aws.securityhub"],
                detail_type=["Security Hub Findings - Imported"],
                detail={
                    "findings": {
                        "ProductArn": [{"prefix": "arn:aws:securityhub"}],
                        "Compliance": {"Status": ["FAILED"]},
                    }
                },
            ),
            enabled=True,
        )

        securityhub_rule.add_target(targets.LambdaFunction(self.compliance_lambda))
        rules.append(securityhub_rule)

        return rules

    def _create_cross_account_role_template(self) -> iam.CfnRole:
        """
        Create cross-account IAM role template for member accounts.
        
        Returns:
            CloudFormation IAM role template for deployment in member accounts
        """
        role = iam.CfnRole(
            self,
            "CrossAccountRoleTemplate",
            role_name=f"SecurityHubComplianceRole-{self.resource_suffix}",
            assume_role_policy_document={
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {"AWS": f"arn:aws:iam::{self.security_account_id}:root"},
                        "Action": "sts:AssumeRole",
                        "Condition": {
                            "StringEquals": {
                                "sts:ExternalId": f"ComplianceMonitoring-{self.resource_suffix}"
                            }
                        },
                    }
                ],
            },
            policies=[
                iam.CfnRole.PolicyProperty(
                    policy_name="ComplianceAccessPolicy",
                    policy_document={
                        "Version": "2012-10-17",
                        "Statement": [
                            {
                                "Effect": "Allow",
                                "Action": [
                                    "ssm:ListComplianceItems",
                                    "ssm:ListResourceComplianceSummaries",
                                    "ssm:GetComplianceSummary",
                                    "ssm:DescribeInstanceInformation",
                                    "ssm:DescribeInstanceAssociations",
                                    "securityhub:BatchImportFindings",
                                    "securityhub:BatchUpdateFindings",
                                ],
                                "Resource": "*",
                            }
                        ],
                    },
                )
            ],
            description="Cross-account role for Security Hub compliance monitoring",
            tags=[
                cdk.CfnTag(key="Purpose", value="ComplianceMonitoring"),
                cdk.CfnTag(key="Environment", value="Production"),
            ],
        )

        return role

    def _create_ssm_documents(self) -> List[ssm.CfnDocument]:
        """
        Create Systems Manager documents for custom compliance checks.
        
        Returns:
            List of SSM documents for custom compliance monitoring
        """
        documents = []

        # Custom compliance check document
        compliance_doc = ssm.CfnDocument(
            self,
            "CustomComplianceDocument",
            name=f"CustomComplianceCheck-{self.resource_suffix}",
            document_type="Command",
            document_format="YAML",
            content={
                "schemaVersion": "2.2",
                "description": "Custom compliance check for organizational policies",
                "parameters": {
                    "complianceType": {
                        "type": "String",
                        "description": "Type of compliance check to perform",
                        "default": "Custom:OrganizationalPolicy",
                    }
                },
                "mainSteps": [
                    {
                        "action": "aws:runShellScript",
                        "name": "runComplianceCheck",
                        "inputs": {
                            "runCommand": [
                                "#!/bin/bash",
                                "# Custom compliance check implementation",
                                "INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)",
                                "COMPLIANCE_TYPE='{{ complianceType }}'",
                                "",
                                "# Check for required tags",
                                "REQUIRED_TAGS=('Environment' 'Owner' 'Project')",
                                "COMPLIANCE_STATUS='COMPLIANT'",
                                "COMPLIANCE_DETAILS=''",
                                "",
                                "for tag in \"${REQUIRED_TAGS[@]}\"; do",
                                "    TAG_VALUE=$(aws ec2 describe-tags \\",
                                "        --filters \"Name=resource-id,Values=${INSTANCE_ID}\" \"Name=key,Values=${tag}\" \\",
                                "        --query \"Tags[0].Value\" --output text)",
                                "    ",
                                "    if [ \"$TAG_VALUE\" = \"None\" ]; then",
                                "        COMPLIANCE_STATUS='NON_COMPLIANT'",
                                "        COMPLIANCE_DETAILS=\"${COMPLIANCE_DETAILS}Missing required tag: ${tag}; \"",
                                "    fi",
                                "done",
                                "",
                                "# Report compliance status to Systems Manager",
                                "aws ssm put-compliance-items \\",
                                "    --resource-id ${INSTANCE_ID} \\",
                                "    --resource-type 'ManagedInstance' \\",
                                "    --compliance-type ${COMPLIANCE_TYPE} \\",
                                "    --execution-summary \"ExecutionTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)\" \\",
                                "    --items \"Id=TagCompliance,Title=Required Tags Check,Severity=HIGH,Status=${COMPLIANCE_STATUS},Details={\\\"Details\\\":\\\"${COMPLIANCE_DETAILS}\\\"}\"",
                                "",
                                "echo \"Custom compliance check completed: ${COMPLIANCE_STATUS}\"",
                            ]
                        },
                    }
                ],
            },
            tags=[
                cdk.CfnTag(key="Purpose", value="ComplianceMonitoring"),
                cdk.CfnTag(key="Type", value="CustomCompliance"),
            ],
        )

        documents.append(compliance_doc)

        return documents

    def _create_security_hub_config(self) -> Dict[str, Any]:
        """
        Create Security Hub configuration resources.
        
        Returns:
            Dictionary containing Security Hub configuration details
        """
        # Note: Security Hub enablement and organization configuration
        # should be done via CLI or separate administrative process
        # as CDK doesn't fully support all Security Hub organization features
        
        config = {
            "security_account_id": self.security_account_id,
            "member_accounts": self.member_account_ids,
            "cross_account_role_name": f"SecurityHubComplianceRole-{self.resource_suffix}",
            "external_id": f"ComplianceMonitoring-{self.resource_suffix}",
        }

        return config

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        
        # CloudTrail bucket
        cdk.CfnOutput(
            self,
            "CloudTrailBucketName",
            value=self.cloudtrail_bucket.bucket_name,
            description="S3 bucket name for CloudTrail compliance logs",
        )

        # Lambda function ARN
        cdk.CfnOutput(
            self,
            "ComplianceLambdaArn",
            value=self.compliance_lambda.function_arn,
            description="ARN of the compliance processing Lambda function",
        )

        # Cross-account role information
        cdk.CfnOutput(
            self,
            "CrossAccountRoleName",
            value=f"SecurityHubComplianceRole-{self.resource_suffix}",
            description="Name of the cross-account role to deploy in member accounts",
        )

        cdk.CfnOutput(
            self,
            "ExternalId",
            value=f"ComplianceMonitoring-{self.resource_suffix}",
            description="External ID for cross-account role assumption",
        )

        # Security Hub configuration
        cdk.CfnOutput(
            self,
            "SecurityAccountId",
            value=self.security_account_id,
            description="AWS account ID configured as Security Hub administrator",
        )

        # EventBridge rules
        for i, rule in enumerate(self.eventbridge_rules):
            cdk.CfnOutput(
                self,
                f"EventBridgeRule{i+1}",
                value=rule.rule_arn,
                description=f"ARN of EventBridge rule {i+1} for compliance automation",
            )


class ComplianceMonitoringApp(cdk.App):
    """
    CDK Application for cross-account compliance monitoring.
    
    This application creates the complete infrastructure needed for
    centralized compliance monitoring across multiple AWS accounts.
    """

    def __init__(self) -> None:
        super().__init__()

        # Get configuration from environment variables or context
        security_account_id = self.node.try_get_context("securityAccountId") or os.environ.get(
            "SECURITY_ACCOUNT_ID", "123456789012"
        )
        
        member_account_ids = self.node.try_get_context("memberAccountIds") or os.environ.get(
            "MEMBER_ACCOUNT_IDS", "123456789013,123456789014"
        ).split(",")
        
        aws_region = self.node.try_get_context("region") or os.environ.get(
            "CDK_DEFAULT_REGION", "us-east-1"
        )
        
        enable_custom_compliance = self.node.try_get_context("enableCustomCompliance") or os.environ.get(
            "ENABLE_CUSTOM_COMPLIANCE", "true"
        ).lower() == "true"

        # Create the compliance monitoring stack
        compliance_stack = ComplianceMonitoringStack(
            self,
            "ComplianceMonitoringStack",
            security_account_id=security_account_id,
            member_account_ids=member_account_ids,
            enable_custom_compliance=enable_custom_compliance,
            compliance_retention_days=90,
            env=cdk.Environment(
                account=security_account_id,
                region=aws_region,
            ),
            description="Cross-account compliance monitoring with Systems Manager and Security Hub",
        )

        # Add stack-level tags
        cdk.Tags.of(compliance_stack).add("Project", "ComplianceMonitoring")
        cdk.Tags.of(compliance_stack).add("Environment", "Production")
        cdk.Tags.of(compliance_stack).add("ManagedBy", "CDK")


# Main application entry point
if __name__ == "__main__":
    app = ComplianceMonitoringApp()
    app.synth()