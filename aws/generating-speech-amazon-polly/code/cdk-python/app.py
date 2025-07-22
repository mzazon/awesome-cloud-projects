#!/usr/bin/env python3
"""
CDK Python Application for Text-to-Speech Applications with Amazon Polly

This application creates the infrastructure needed for building text-to-speech applications
using Amazon Polly, including S3 storage for audio output and IAM permissions for batch
synthesis operations.
"""

import os
from aws_cdk import (
    App,
    Stack,
    Environment,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_s3 as s3,
    aws_iam as iam,
    aws_polly as polly,
    Tags,
)
from constructs import Construct
from typing import Dict, Any


class TextToSpeechPollyStack(Stack):
    """
    CDK Stack for Amazon Polly Text-to-Speech Application Infrastructure
    
    This stack creates:
    - S3 bucket for audio output storage
    - IAM role for Polly batch synthesis operations
    - Custom pronunciation lexicon for technical terms
    - Outputs for integration with applications
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create S3 bucket for audio output
        self.audio_output_bucket = self._create_audio_output_bucket()
        
        # Create IAM role for Polly batch synthesis
        self.polly_service_role = self._create_polly_service_role()
        
        # Create custom pronunciation lexicon
        self.pronunciation_lexicon = self._create_pronunciation_lexicon()
        
        # Create outputs
        self._create_outputs()
        
        # Add tags to all resources
        self._add_tags()

    def _create_audio_output_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing synthesized audio files
        
        Returns:
            s3.Bucket: The created S3 bucket
        """
        bucket = s3.Bucket(
            self,
            "AudioOutputBucket",
            bucket_name=f"polly-audio-output-{self.account}-{self.region}",
            versioning=s3.BucketVersioning.ENABLED,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldAudioFiles",
                    enabled=True,
                    expiration=Duration.days(90),
                    abort_incomplete_multipart_upload_after=Duration.days(7),
                    noncurrent_version_expiration=Duration.days(30)
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )
        
        return bucket

    def _create_polly_service_role(self) -> iam.Role:
        """
        Create IAM role for Amazon Polly batch synthesis operations
        
        Returns:
            iam.Role: The created IAM role
        """
        # Create IAM role for Polly service
        role = iam.Role(
            self,
            "PollyServiceRole",
            role_name=f"PollyServiceRole-{self.stack_name}",
            assumed_by=iam.ServicePrincipal("polly.amazonaws.com"),
            description="IAM role for Amazon Polly batch synthesis operations",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonPollyServiceRole"
                )
            ]
        )
        
        # Add S3 permissions for batch synthesis
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:PutObject",
                    "s3:PutObjectAcl",
                    "s3:GetBucketLocation"
                ],
                resources=[
                    self.audio_output_bucket.bucket_arn,
                    f"{self.audio_output_bucket.bucket_arn}/*"
                ]
            )
        )
        
        return role

    def _create_pronunciation_lexicon(self) -> polly.CfnLexicon:
        """
        Create custom pronunciation lexicon for technical terms
        
        Returns:
            polly.CfnLexicon: The created pronunciation lexicon
        """
        # Define lexicon content with technical terms
        lexicon_content = '''<?xml version="1.0" encoding="UTF-8"?>
<lexicon version="1.0" 
    xmlns="http://www.w3.org/2005/01/pronunciation-lexicon"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
    xsi:schemaLocation="http://www.w3.org/2005/01/pronunciation-lexicon 
        http://www.w3.org/TR/2007/CR-pronunciation-lexicon-20071212/pls.xsd"
    alphabet="ipa" 
    xml:lang="en-US">
    <lexeme>
        <grapheme>AWS</grapheme>
        <alias>Amazon Web Services</alias>
    </lexeme>
    <lexeme>
        <grapheme>API</grapheme>
        <alias>Application Programming Interface</alias>
    </lexeme>
    <lexeme>
        <grapheme>CDK</grapheme>
        <alias>Cloud Development Kit</alias>
    </lexeme>
    <lexeme>
        <grapheme>S3</grapheme>
        <alias>Simple Storage Service</alias>
    </lexeme>
    <lexeme>
        <grapheme>IAM</grapheme>
        <alias>Identity and Access Management</alias>
    </lexeme>
    <lexeme>
        <grapheme>TTS</grapheme>
        <alias>Text To Speech</alias>
    </lexeme>
    <lexeme>
        <grapheme>SSML</grapheme>
        <alias>Speech Synthesis Markup Language</alias>
    </lexeme>
</lexicon>'''
        
        lexicon = polly.CfnLexicon(
            self,
            "TechTerminologyLexicon",
            name="tech-terminology",
            content=lexicon_content
        )
        
        return lexicon

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for application integration"""
        
        CfnOutput(
            self,
            "AudioOutputBucketName",
            value=self.audio_output_bucket.bucket_name,
            description="S3 bucket name for audio output storage",
            export_name=f"{self.stack_name}-AudioOutputBucketName"
        )
        
        CfnOutput(
            self,
            "AudioOutputBucketArn",
            value=self.audio_output_bucket.bucket_arn,
            description="S3 bucket ARN for audio output storage",
            export_name=f"{self.stack_name}-AudioOutputBucketArn"
        )
        
        CfnOutput(
            self,
            "PollyServiceRoleArn",
            value=self.polly_service_role.role_arn,
            description="IAM role ARN for Polly batch synthesis operations",
            export_name=f"{self.stack_name}-PollyServiceRoleArn"
        )
        
        CfnOutput(
            self,
            "PronunciationLexiconName",
            value=self.pronunciation_lexicon.name,
            description="Name of the custom pronunciation lexicon",
            export_name=f"{self.stack_name}-PronunciationLexiconName"
        )
        
        CfnOutput(
            self,
            "PollyEndpoint",
            value=f"https://polly.{self.region}.amazonaws.com",
            description="Amazon Polly service endpoint for the deployed region",
            export_name=f"{self.stack_name}-PollyEndpoint"
        )

    def _add_tags(self) -> None:
        """Add tags to all resources in the stack"""
        
        tags_to_add = {
            "Application": "TextToSpeechPolly",
            "Environment": "Development",
            "Owner": "DevOps",
            "CostCenter": "Engineering",
            "Purpose": "TextToSpeechDemo"
        }
        
        for key, value in tags_to_add.items():
            Tags.of(self).add(key, value)


class TextToSpeechPollyApp(App):
    """
    CDK Application for Text-to-Speech with Amazon Polly
    
    This application manages the deployment of infrastructure for building
    text-to-speech applications using Amazon Polly service.
    """

    def __init__(self) -> None:
        super().__init__()
        
        # Get environment configuration
        env = self._get_environment()
        
        # Create the main stack
        TextToSpeechPollyStack(
            self,
            "TextToSpeechPollyStack",
            env=env,
            description="Infrastructure for text-to-speech applications using Amazon Polly"
        )

    def _get_environment(self) -> Environment:
        """
        Get environment configuration for CDK deployment
        
        Returns:
            Environment: CDK environment configuration
        """
        return Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        )


# Application entry point
if __name__ == "__main__":
    app = TextToSpeechPollyApp()
    app.synth()