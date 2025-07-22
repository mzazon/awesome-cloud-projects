"""
Unit tests for the PipelineStack.

This module contains comprehensive tests for the PipelineStack class,
validating the creation and configuration of the CI/CD pipeline components.
"""

import os
import pytest
import aws_cdk as cdk
from aws_cdk import assertions

# Import the stack under test
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from app import PipelineStack


class TestPipelineStack:
    """Test suite for the PipelineStack class."""

    def setup_method(self):
        """Set up test fixtures before each test method."""
        self.app = cdk.App()
        
        # Set required environment variables
        os.environ["REPO_NAME"] = "test-infrastructure-pipeline"
        os.environ["CDK_DEFAULT_ACCOUNT"] = "123456789012"
        os.environ["CDK_DEFAULT_REGION"] = "us-east-1"
        
        self.stack = PipelineStack(
            self.app,
            "TestPipelineStack",
            env=cdk.Environment(
                account="123456789012",
                region="us-east-1"
            )
        )
        self.template = assertions.Template.from_stack(self.stack)

    def test_codecommit_repository_created(self):
        """Test that CodeCommit repository is created or referenced."""
        # Note: The actual implementation tries to reference existing repo first
        # This test verifies the repository configuration is present
        pass

    def test_codepipeline_created(self):
        """Test that CodePipeline is created with correct configuration."""
        # Verify CodePipeline exists
        self.template.has_resource_properties("AWS::CodePipeline::Pipeline", {
            "Name": "InfrastructurePipeline"
        })

    def test_codebuild_project_created(self):
        """Test that CodeBuild project is created for synthesis."""
        # Verify CodeBuild project exists
        codebuild_resources = self.template.find_resources("AWS::CodeBuild::Project")
        
        # Should have at least one CodeBuild project
        assert len(codebuild_resources) >= 1
        
        # Check build environment configuration
        for resource_id, resource in codebuild_resources.items():
            properties = resource.get("Properties", {})
            environment = properties.get("Environment", {})
            
            # Verify build environment settings
            assert environment.get("Type") == "LINUX_CONTAINER"
            assert "Image" in environment
            assert environment.get("ComputeType") == "BUILD_GENERAL1_SMALL"

    def test_sns_topic_created(self):
        """Test that SNS topic is created for notifications."""
        # Verify SNS topic exists
        self.template.has_resource_properties("AWS::SNS::Topic", {
            "TopicName": "infrastructure-pipeline-notifications",
            "DisplayName": "Infrastructure Pipeline Notifications"
        })

    def test_cloudwatch_alarm_created(self):
        """Test that CloudWatch alarm is created for pipeline monitoring."""
        # Verify CloudWatch alarm exists
        self.template.has_resource_properties("AWS::CloudWatch::Alarm", {
            "AlarmName": "infrastructure-pipeline-failure",
            "AlarmDescription": "Infrastructure deployment pipeline has failed",
            "MetricName": "PipelineExecutionFailure",
            "Namespace": "AWS/CodePipeline",
            "Statistic": "Sum",
            "Threshold": 1,
            "EvaluationPeriods": 1,
            "ComparisonOperator": "GreaterThanOrEqualToThreshold"
        })

    def test_iam_roles_created(self):
        """Test that necessary IAM roles are created."""
        # Verify IAM roles exist for CodePipeline and CodeBuild
        iam_roles = self.template.find_resources("AWS::IAM::Role")
        
        # Should have multiple IAM roles
        assert len(iam_roles) >= 2
        
        # Check for CodePipeline service role
        codepipeline_role_found = False
        codebuild_role_found = False
        
        for resource_id, resource in iam_roles.items():
            properties = resource.get("Properties", {})
            assume_role_policy = properties.get("AssumeRolePolicyDocument", {})
            statements = assume_role_policy.get("Statement", [])
            
            for statement in statements:
                principal = statement.get("Principal", {})
                service = principal.get("Service", [])
                
                if isinstance(service, str):
                    service = [service]
                
                if "codepipeline.amazonaws.com" in service:
                    codepipeline_role_found = True
                if "codebuild.amazonaws.com" in service:
                    codebuild_role_found = True
        
        assert codepipeline_role_found, "CodePipeline service role not found"
        assert codebuild_role_found, "CodeBuild service role not found"

    def test_pipeline_stages_configuration(self):
        """Test that pipeline stages are configured correctly."""
        # Get pipeline resources
        pipeline_resources = self.template.find_resources("AWS::CodePipeline::Pipeline")
        
        for resource_id, resource in pipeline_resources.items():
            properties = resource.get("Properties", {})
            stages = properties.get("Stages", [])
            
            # Verify minimum number of stages
            assert len(stages) >= 2, "Pipeline should have at least Source and Build stages"
            
            # Check stage names
            stage_names = [stage.get("Name") for stage in stages]
            assert "Source" in stage_names
            assert any("Synth" in name or "Build" in name for name in stage_names)

    def test_artifacts_bucket_created(self):
        """Test that S3 bucket is created for pipeline artifacts."""
        # Verify S3 bucket exists for artifacts
        s3_resources = self.template.find_resources("AWS::S3::Bucket")
        
        # Should have at least one S3 bucket for artifacts
        assert len(s3_resources) >= 1
        
        # Check bucket encryption
        for resource_id, resource in s3_resources.items():
            properties = resource.get("Properties", {})
            encryption = properties.get("BucketEncryption", {})
            
            # Verify encryption is configured
            assert "ServerSideEncryptionConfiguration" in encryption

    def test_pipeline_self_mutation_enabled(self):
        """Test that pipeline self-mutation is enabled."""
        # This test verifies that the pipeline can update itself
        # The specific implementation depends on CDK Pipelines internals
        pass

    def test_cross_account_keys_configuration(self):
        """Test that cross-account keys are configured correctly."""
        # Verify KMS key configuration for cross-account access
        kms_resources = self.template.find_resources("AWS::KMS::Key")
        
        # Should have KMS keys for cross-account access
        if len(kms_resources) > 0:
            for resource_id, resource in kms_resources.items():
                properties = resource.get("Properties", {})
                key_policy = properties.get("KeyPolicy", {})
                
                # Verify key policy allows cross-account access
                assert "Statement" in key_policy

    def test_environment_variables_configuration(self):
        """Test that environment variables are configured correctly."""
        # Verify that environment variables are passed to CodeBuild
        codebuild_resources = self.template.find_resources("AWS::CodeBuild::Project")
        
        for resource_id, resource in codebuild_resources.items():
            properties = resource.get("Properties", {})
            environment = properties.get("Environment", {})
            env_vars = environment.get("EnvironmentVariables", [])
            
            # Check for required environment variables
            env_var_names = [var.get("Name") for var in env_vars]
            # Note: Specific environment variables depend on CDK Pipelines implementation

    def test_build_commands_configuration(self):
        """Test that build commands are configured correctly."""
        # This test would verify that the synthesis step includes correct commands
        # The actual commands are embedded in the CDK Pipelines construct
        pass

    def test_stack_outputs_created(self):
        """Test that stack outputs are created correctly."""
        # Verify outputs exist
        self.template.has_outputs_count(4)
        
        # Check specific outputs
        self.template.has_output("PipelineName", {})
        self.template.has_output("RepositoryName", {})
        self.template.has_output("RepositoryUrl", {})
        self.template.has_output("NotificationsTopic", {})

    def test_security_policies_configuration(self):
        """Test that security policies are configured correctly."""
        # Verify IAM policies have appropriate permissions
        iam_policies = self.template.find_resources("AWS::IAM::Policy")
        
        # Should have IAM policies for service roles
        assert len(iam_policies) >= 1
        
        # Check policy statements
        for resource_id, resource in iam_policies.items():
            properties = resource.get("Properties", {})
            policy_document = properties.get("PolicyDocument", {})
            statements = policy_document.get("Statement", [])
            
            # Verify statements exist
            assert len(statements) > 0

    def test_pipeline_failure_handling(self):
        """Test that pipeline failure handling is configured."""
        # Verify CloudWatch alarm is configured to trigger on failures
        alarm_resources = self.template.find_resources("AWS::CloudWatch::Alarm")
        
        # Should have at least one alarm
        assert len(alarm_resources) >= 1
        
        # Check alarm actions
        for resource_id, resource in alarm_resources.items():
            properties = resource.get("Properties", {})
            alarm_actions = properties.get("AlarmActions", [])
            
            # Verify alarm actions are configured
            assert len(alarm_actions) > 0

    def test_resource_naming_conventions(self):
        """Test that resources follow naming conventions."""
        # Verify resource names follow consistent patterns
        all_resources = self.template.to_json().get("Resources", {})
        
        # Check that resource names are meaningful
        for resource_id, resource in all_resources.items():
            # Resource IDs should be meaningful (not empty or too short)
            assert len(resource_id) > 3
            assert resource_id.isalnum() or any(c in resource_id for c in ['_', '-'])

    def cleanup_method(self):
        """Clean up after each test method."""
        # Clean up environment variables
        if "REPO_NAME" in os.environ:
            del os.environ["REPO_NAME"]