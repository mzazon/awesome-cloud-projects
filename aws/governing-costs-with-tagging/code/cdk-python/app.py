#!/usr/bin/env python3
"""
AWS CDK Python Application for Resource Tagging Strategies and Cost Management

This CDK application implements a comprehensive resource tagging strategy using:
- AWS Config for tag compliance monitoring
- Lambda for automated tag remediation
- SNS for compliance notifications
- Sample resources demonstrating proper tagging

Author: AWS CDK Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Stack,
    aws_iam as iam,
    aws_s3 as s3,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_lambda as lambda_,
    aws_config as config,
    aws_resourcegroups as resourcegroups,
    aws_ec2 as ec2,
    RemovalPolicy,
    CfnOutput,
    Tags
)
from typing import Dict, List, Optional
from constructs import Construct


class ResourceTaggingStack(Stack):
    """
    Stack Governing Costs with Strategic Resource Tagging.
    
    This stack creates:
    - AWS Config for tag compliance monitoring
    - Config rules for required tag validation
    - Lambda function for automated tag remediation
    - SNS topic for compliance notifications
    - Sample resources with proper tagging
    - Resource groups for tag-based organization
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        notification_email: str,
        **kwargs
    ) -> None:
        """
        Initialize the Resource Tagging Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            notification_email: Email address for tag compliance notifications
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Define standard tag taxonomy for the organization
        self.tag_taxonomy = {
            "required_tags": {
                "CostCenter": ["Engineering", "Marketing", "Sales", "Finance", "Operations"],
                "Environment": ["Production", "Staging", "Development", "Testing"],
                "Project": "*",  # Any valid project name
                "Owner": "*"     # Valid email format
            },
            "optional_tags": {
                "Application": ["web", "api", "database", "cache", "queue"],
                "Backup": ["true", "false"]
            }
        }

        # Create S3 bucket for AWS Config
        self.config_bucket = self._create_config_bucket()
        
        # Create SNS topic for notifications
        self.notification_topic = self._create_notification_topic(notification_email)
        
        # Create IAM role for AWS Config
        self.config_role = self._create_config_service_role()
        
        # Create AWS Config configuration recorder and delivery channel
        self.config_recorder, self.delivery_channel = self._create_config_setup()
        
        # Create Config rules for tag compliance
        self.config_rules = self._create_config_rules()
        
        # Create Lambda function for tag remediation
        self.remediation_function = self._create_remediation_lambda()
        
        # Create sample resources with proper tagging
        self.sample_resources = self._create_sample_resources()
        
        # Create resource groups for tag-based organization
        self.resource_groups = self._create_resource_groups()
        
        # Apply standard tags to all resources
        self._apply_stack_tags()
        
        # Create outputs
        self._create_outputs()

    def _create_config_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for AWS Config storage with proper permissions.
        
        Returns:
            S3 bucket configured for AWS Config
        """
        # Create S3 bucket for Config
        bucket = s3.Bucket(
            self, "ConfigBucket",
            bucket_name=f"aws-config-{self.account}-{self.region}-{cdk.Aws.STACK_NAME.lower()}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ConfigLogRetention",
                    enabled=True,
                    expiration=Duration.days(365),
                    noncurrent_version_expiration=Duration.days(90)
                )
            ]
        )

        # Add bucket policy for AWS Config service
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSConfigBucketPermissionsCheck",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("config.amazonaws.com")],
                actions=["s3:GetBucketAcl", "s3:ListBucket"],
                resources=[bucket.bucket_arn],
                conditions={
                    "StringEquals": {
                        "AWS:SourceAccount": self.account
                    }
                }
            )
        )

        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSConfigBucketExistenceCheck",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("config.amazonaws.com")],
                actions=["s3:ListBucket"],
                resources=[bucket.bucket_arn],
                conditions={
                    "StringEquals": {
                        "AWS:SourceAccount": self.account
                    }
                }
            )
        )

        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSConfigBucketDelivery",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("config.amazonaws.com")],
                actions=["s3:PutObject"],
                resources=[f"{bucket.bucket_arn}/AWSLogs/{self.account}/Config/*"],
                conditions={
                    "StringEquals": {
                        "s3:x-amz-acl": "bucket-owner-full-control",
                        "AWS:SourceAccount": self.account
                    }
                }
            )
        )

        return bucket

    def _create_notification_topic(self, email: str) -> sns.Topic:
        """
        Create SNS topic for tag compliance notifications.
        
        Args:
            email: Email address for notifications
            
        Returns:
            SNS topic for notifications
        """
        topic = sns.Topic(
            self, "TagComplianceTopic",
            topic_name=f"tag-compliance-{cdk.Aws.STACK_NAME.lower()}",
            display_name="Tag Compliance Notifications"
        )

        # Add email subscription
        topic.add_subscription(
            sns_subscriptions.EmailSubscription(email)
        )

        return topic

    def _create_config_service_role(self) -> iam.Role:
        """
        Create IAM role for AWS Config service.
        
        Returns:
            IAM role for AWS Config
        """
        role = iam.Role(
            self, "ConfigServiceRole",
            role_name=f"aws-config-role-{cdk.Aws.STACK_NAME.lower()}",
            assumed_by=iam.ServicePrincipal("config.amazonaws.com"),
            description="Service role for AWS Config",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/ConfigRole")
            ]
        )

        # Add S3 permissions for the Config bucket
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetBucketAcl",
                    "s3:ListBucket",
                    "s3:PutObject",
                    "s3:GetBucketLocation"
                ],
                resources=[
                    self.config_bucket.bucket_arn,
                    f"{self.config_bucket.bucket_arn}/*"
                ]
            )
        )

        return role

    def _create_config_setup(self) -> tuple:
        """
        Create AWS Config configuration recorder and delivery channel.
        
        Returns:
            Tuple of (configuration_recorder, delivery_channel)
        """
        # Create delivery channel
        delivery_channel = config.CfnDeliveryChannel(
            self, "ConfigDeliveryChannel",
            name="default",
            s3_bucket_name=self.config_bucket.bucket_name
        )

        # Create configuration recorder
        configuration_recorder = config.CfnConfigurationRecorder(
            self, "ConfigRecorder",
            name="default",
            role_arn=self.config_role.role_arn,
            recording_group=config.CfnConfigurationRecorder.RecordingGroupProperty(
                all_supported=True,
                include_global_resource_types=True,
                recording_mode_overrides=[]
            )
        )

        # Ensure proper dependency order
        configuration_recorder.add_dependency(delivery_channel)

        return configuration_recorder, delivery_channel

    def _create_config_rules(self) -> List[config.CfnConfigRule]:
        """
        Create AWS Config rules for tag compliance monitoring.
        
        Returns:
            List of Config rules
        """
        rules = []

        # Rule for CostCenter tag
        cost_center_rule = config.CfnConfigRule(
            self, "RequiredTagCostCenter",
            config_rule_name="required-tag-costcenter",
            description="Checks if resources have required CostCenter tag with valid values",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="REQUIRED_TAGS"
            ),
            input_parameters='{"tag1Key":"CostCenter","tag1Value":"Engineering,Marketing,Sales,Finance,Operations"}'
        )
        cost_center_rule.add_dependency(self.config_recorder)
        rules.append(cost_center_rule)

        # Rule for Environment tag
        environment_rule = config.CfnConfigRule(
            self, "RequiredTagEnvironment",
            config_rule_name="required-tag-environment",
            description="Checks if resources have required Environment tag with valid values",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="REQUIRED_TAGS"
            ),
            input_parameters='{"tag1Key":"Environment","tag1Value":"Production,Staging,Development,Testing"}'
        )
        environment_rule.add_dependency(self.config_recorder)
        rules.append(environment_rule)

        # Rule for Project tag
        project_rule = config.CfnConfigRule(
            self, "RequiredTagProject",
            config_rule_name="required-tag-project",
            description="Checks if resources have required Project tag",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="REQUIRED_TAGS"
            ),
            input_parameters='{"tag1Key":"Project"}'
        )
        project_rule.add_dependency(self.config_recorder)
        rules.append(project_rule)

        # Rule for Owner tag
        owner_rule = config.CfnConfigRule(
            self, "RequiredTagOwner",
            config_rule_name="required-tag-owner",
            description="Checks if resources have required Owner tag",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="REQUIRED_TAGS"
            ),
            input_parameters='{"tag1Key":"Owner"}'
        )
        owner_rule.add_dependency(self.config_recorder)
        rules.append(owner_rule)

        return rules

    def _create_remediation_lambda(self) -> lambda_.Function:
        """
        Create Lambda function for automated tag remediation.
        
        Returns:
            Lambda function for tag remediation
        """
        # Create IAM role for Lambda
        lambda_role = iam.Role(
            self, "TagRemediationLambdaRole",
            role_name=f"tag-remediation-lambda-role-{cdk.Aws.STACK_NAME.lower()}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for tag remediation Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )

        # Add permissions for tag operations
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ec2:CreateTags",
                    "ec2:DescribeTags",
                    "s3:GetBucketTagging",
                    "s3:PutBucketTagging",
                    "rds:AddTagsToResource",
                    "rds:ListTagsForResource",
                    "lambda:TagResource",
                    "lambda:UntagResource",
                    "lambda:ListTags"
                ],
                resources=["*"]
            )
        )

        # Add SNS publish permissions
        self.notification_topic.grant_publish(lambda_role)

        # Lambda function code
        lambda_code = '''
import json
import boto3
import os
from datetime import datetime
from typing import Dict, List, Any

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Automated tag remediation function for AWS Config rule violations.
    
    Args:
        event: AWS Config rule evaluation event
        context: Lambda context object
        
    Returns:
        Response dictionary with status and message
    """
    print(f"Received event: {json.dumps(event, default=str)}")
    
    # Initialize AWS clients
    ec2 = boto3.client('ec2')
    s3 = boto3.client('s3')
    rds = boto3.client('rds')
    sns = boto3.client('sns')
    
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    try:
        # Parse Config rule evaluation result
        if 'configurationItem' in event:
            config_item = event['configurationItem']
            resource_type = config_item['resourceType']
            resource_id = config_item['resourceId']
            
            # Apply default tags based on resource type
            default_tags = get_default_tags(config_item)
            
            if resource_type == 'AWS::EC2::Instance':
                remediate_ec2_instance(ec2, resource_id, default_tags)
            elif resource_type == 'AWS::S3::Bucket':
                remediate_s3_bucket(s3, resource_id, default_tags)
            elif resource_type == 'AWS::RDS::DBInstance':
                remediate_rds_instance(rds, resource_id, default_tags)
            
            # Send notification
            send_notification(sns, sns_topic_arn, resource_type, resource_id, default_tags)
            
            return {
                'statusCode': 200,
                'body': json.dumps(f'Successfully processed {resource_type} {resource_id}')
            }
        else:
            return {
                'statusCode': 400,
                'body': json.dumps('Invalid event format - no configurationItem found')
            }
            
    except Exception as e:
        print(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def get_default_tags(config_item: Dict[str, Any]) -> List[Dict[str, str]]:
    """Generate default tags for non-compliant resources."""
    tags = []
    existing_tags = config_item.get('tags', {})
    
    # Add default CostCenter if missing
    if 'CostCenter' not in existing_tags:
        tags.append({'Key': 'CostCenter', 'Value': 'Unassigned'})
    
    # Add default Environment if missing
    if 'Environment' not in existing_tags:
        tags.append({'Key': 'Environment', 'Value': 'Development'})
    
    # Add default Project if missing
    if 'Project' not in existing_tags:
        tags.append({'Key': 'Project', 'Value': 'UntaggedResource'})
    
    # Add default Owner if missing
    if 'Owner' not in existing_tags:
        tags.append({'Key': 'Owner', 'Value': 'unknown@company.com'})
    
    # Add compliance tag
    tags.append({
        'Key': 'AutoTagged',
        'Value': f"true-{datetime.now().strftime('%Y%m%d')}"
    })
    
    return tags

def remediate_ec2_instance(ec2: Any, instance_id: str, tags: List[Dict[str, str]]) -> None:
    """Apply tags to EC2 instance."""
    if tags:
        ec2.create_tags(Resources=[instance_id], Tags=tags)
        print(f"Applied tags to EC2 instance {instance_id}")

def remediate_s3_bucket(s3: Any, bucket_name: str, tags: List[Dict[str, str]]) -> None:
    """Apply tags to S3 bucket."""
    if tags:
        tag_set = [{'Key': tag['Key'], 'Value': tag['Value']} for tag in tags]
        s3.put_bucket_tagging(
            Bucket=bucket_name,
            Tagging={'TagSet': tag_set}
        )
        print(f"Applied tags to S3 bucket {bucket_name}")

def remediate_rds_instance(rds: Any, db_instance_id: str, tags: List[Dict[str, str]]) -> None:
    """Apply tags to RDS instance."""
    if tags:
        # Get account and region for ARN construction
        sts = boto3.client('sts')
        account_id = sts.get_caller_identity()['Account']
        region = boto3.Session().region_name
        
        db_arn = f"arn:aws:rds:{region}:{account_id}:db:{db_instance_id}"
        rds.add_tags_to_resource(
            ResourceName=db_arn,
            Tags=tags
        )
        print(f"Applied tags to RDS instance {db_instance_id}")

def send_notification(sns: Any, topic_arn: str, resource_type: str, 
                     resource_id: str, tags: List[Dict[str, str]]) -> None:
    """Send SNS notification about tag remediation."""
    message = f"""
Tag Remediation Notification

Resource Type: {resource_type}
Resource ID: {resource_id}
Auto-Applied Tags: {json.dumps(tags, indent=2)}

Please review and update tags as needed in the AWS Console.
Timestamp: {datetime.now().isoformat()}
"""
    
    sns.publish(
        TopicArn=topic_arn,
        Subject=f'Auto-Tag Applied: {resource_type}',
        Message=message
    )
'''

        # Create Lambda function
        function = lambda_.Function(
            self, "TagRemediationFunction",
            function_name=f"tag-remediation-{cdk.Aws.STACK_NAME.lower()}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            description="Automated tag remediation for cost management compliance",
            environment={
                "SNS_TOPIC_ARN": self.notification_topic.topic_arn
            }
        )

        return function

    def _create_sample_resources(self) -> Dict[str, any]:
        """
        Create sample resources with proper tagging for demonstration.
        
        Returns:
            Dictionary of created sample resources
        """
        resources = {}

        # Create demo S3 bucket with comprehensive tagging
        demo_bucket = s3.Bucket(
            self, "DemoBucket",
            bucket_name=f"cost-mgmt-demo-{self.account}-{self.region}-{cdk.Aws.STACK_NAME.lower()}",
            versioned=False,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

        # Apply comprehensive tags to demo bucket
        Tags.of(demo_bucket).add("CostCenter", "Marketing")
        Tags.of(demo_bucket).add("Environment", "Production")
        Tags.of(demo_bucket).add("Project", "WebAssets")
        Tags.of(demo_bucket).add("Owner", "marketing@company.com")
        Tags.of(demo_bucket).add("Application", "web")
        Tags.of(demo_bucket).add("Backup", "true")

        resources["demo_bucket"] = demo_bucket

        return resources

    def _create_resource_groups(self) -> List[resourcegroups.CfnGroup]:
        """
        Create resource groups for tag-based organization.
        
        Returns:
            List of resource groups
        """
        groups = []

        # Resource group for Production environment
        production_group = resourcegroups.CfnGroup(
            self, "ProductionEnvironmentGroup",
            name=f"Production-Environment-{cdk.Aws.STACK_NAME}",
            description="Resources in Production environment",
            resource_query=resourcegroups.CfnGroup.ResourceQueryProperty(
                type="TAG_FILTERS_1_0",
                query={
                    "ResourceTypeFilters": ["AWS::AllSupported"],
                    "TagFilters": [
                        {
                            "Key": "Environment",
                            "Values": ["Production"]
                        }
                    ]
                }
            ),
            tags=[
                {
                    "key": "Environment",
                    "value": "Production"
                },
                {
                    "key": "Purpose",
                    "value": "CostAllocation"
                }
            ]
        )
        groups.append(production_group)

        # Resource group for Engineering cost center
        engineering_group = resourcegroups.CfnGroup(
            self, "EngineeringCostCenterGroup",
            name=f"Engineering-CostCenter-{cdk.Aws.STACK_NAME}",
            description="Resources for Engineering cost center",
            resource_query=resourcegroups.CfnGroup.ResourceQueryProperty(
                type="TAG_FILTERS_1_0",
                query={
                    "ResourceTypeFilters": ["AWS::AllSupported"],
                    "TagFilters": [
                        {
                            "Key": "CostCenter",
                            "Values": ["Engineering"]
                        }
                    ]
                }
            ),
            tags=[
                {
                    "key": "CostCenter",
                    "value": "Engineering"
                },
                {
                    "key": "Purpose",
                    "value": "CostAllocation"
                }
            ]
        )
        groups.append(engineering_group)

        return groups

    def _apply_stack_tags(self) -> None:
        """Apply standard tags to all resources in the stack."""
        Tags.of(self).add("CostCenter", "Engineering")
        Tags.of(self).add("Environment", "Development")
        Tags.of(self).add("Project", "TaggingStrategy")
        Tags.of(self).add("Owner", "devops@company.com")
        Tags.of(self).add("Application", "cost-management")
        Tags.of(self).add("StackName", cdk.Aws.STACK_NAME)
        Tags.of(self).add("CreatedBy", "AWS-CDK")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self, "ConfigBucketName",
            value=self.config_bucket.bucket_name,
            description="S3 bucket for AWS Config storage",
            export_name=f"{cdk.Aws.STACK_NAME}-ConfigBucket"
        )

        CfnOutput(
            self, "SNSTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS topic for tag compliance notifications",
            export_name=f"{cdk.Aws.STACK_NAME}-SNSTopic"
        )

        CfnOutput(
            self, "LambdaFunctionName",
            value=self.remediation_function.function_name,
            description="Lambda function for tag remediation",
            export_name=f"{cdk.Aws.STACK_NAME}-LambdaFunction"
        )

        CfnOutput(
            self, "ConfigRoleArn",
            value=self.config_role.role_arn,
            description="IAM role for AWS Config service",
            export_name=f"{cdk.Aws.STACK_NAME}-ConfigRole"
        )

        if hasattr(self, 'sample_resources') and 'demo_bucket' in self.sample_resources:
            CfnOutput(
                self, "DemoBucketName",
                value=self.sample_resources['demo_bucket'].bucket_name,
                description="Demo S3 bucket with proper tagging",
                export_name=f"{cdk.Aws.STACK_NAME}-DemoBucket"
            )


class ResourceTaggingApp(cdk.App):
    """CDK Application for Resource Tagging Strategy."""

    def __init__(self) -> None:
        super().__init__()

        # Get notification email from context or use default
        notification_email = self.node.try_get_context("notification_email")
        if not notification_email:
            notification_email = "admin@company.com"
            print(f"Warning: Using default email {notification_email}. Set with -c notification_email=your@email.com")

        # Create the main stack
        ResourceTaggingStack(
            self, "ResourceTaggingStack",
            notification_email=notification_email,
            description="AWS CDK stack for implementing resource tagging strategies and cost management",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION")
            )
        )


# Create the CDK app
import os
app = ResourceTaggingApp()
app.synth()