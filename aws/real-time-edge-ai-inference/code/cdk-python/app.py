#!/usr/bin/env python3
"""
AWS CDK Python Application for Real-Time Edge AI Inference
Implements SageMaker Edge Manager with IoT Greengrass v2 and EventBridge integration
"""

import os
from typing import Any, Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    CfnOutput,
    Duration,
    Environment,
    RemovalPolicy,
    Stack,
    StackProps,
    Tags,
)
from aws_cdk import aws_events as events
from aws_cdk import aws_events_targets as targets
from aws_cdk import aws_iam as iam
from aws_cdk import aws_iot as iot
from aws_cdk import aws_logs as logs
from aws_cdk import aws_s3 as s3
from constructs import Construct


class EdgeAIInferenceStack(Stack):
    """
    CDK Stack for Real-Time Edge AI Inference with IoT Greengrass v2
    
    This stack creates:
    - S3 bucket for ML model storage
    - IoT Greengrass v2 components (ONNX runtime, model, inference engine)
    - IAM roles for secure edge device access
    - EventBridge custom bus for centralized monitoring
    - CloudWatch logs for event storage
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        project_name: str = "edge-ai-inference",
        model_name: str = "defect-detection",
        **kwargs: Any
    ) -> None:
        """
        Initialize the Edge AI Inference stack
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            project_name: Project name for resource naming
            model_name: Name of the ML model for inference
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        self.project_name = project_name
        self.model_name = model_name

        # Generate unique suffix for resources
        self._create_unique_suffix()

        # Create S3 bucket for model storage
        self.model_bucket = self._create_model_bucket()

        # Create IAM roles for IoT Greengrass
        self.token_exchange_role = self._create_token_exchange_role()
        self.role_alias = self._create_role_alias()

        # Create EventBridge resources for monitoring
        self.event_bus = self._create_event_bus()
        self.log_group = self._create_log_group()
        self.monitoring_rule = self._create_monitoring_rule()

        # Create IoT Greengrass components
        self.onnx_component = self._create_onnx_runtime_component()
        self.model_component = self._create_model_component()
        self.inference_component = self._create_inference_component()

        # Create outputs for reference
        self._create_outputs()

        # Apply tags to all resources
        self._apply_tags()

    def _create_unique_suffix(self) -> None:
        """Generate a unique suffix for resource naming"""
        self.unique_suffix = cdk.Fn.select(
            2, cdk.Fn.split("-", cdk.Fn.select(2, cdk.Fn.split("/", self.stack_id)))
        )

    def _create_model_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing ML models with versioning enabled
        
        Returns:
            S3 bucket configured for model storage
        """
        bucket = s3.Bucket(
            self,
            "ModelBucket",
            bucket_name=f"edge-models-{self.unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ModelVersionCleanup",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30),
                    abort_incomplete_multipart_upload_after=Duration.days(1),
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Add CORS configuration for potential web access
        bucket.add_cors_rule(
            allowed_methods=[s3.HttpMethods.GET, s3.HttpMethods.HEAD],
            allowed_origins=["*"],
            allowed_headers=["*"],
            max_age=3000,
        )

        return bucket

    def _create_token_exchange_role(self) -> iam.Role:
        """
        Create IAM role for Greengrass Token Exchange Service
        
        Returns:
            IAM role for secure credential exchange
        """
        role = iam.Role(
            self,
            "GreengrassTokenExchangeRole",
            role_name=f"GreengrassV2TokenExchangeRole-{self.unique_suffix}",
            assumed_by=iam.ServicePrincipal("credentials.iot.amazonaws.com"),
            description="Token exchange role for IoT Greengrass v2 devices",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "GreengrassV2TokenExchangeRoleAccess"
                )
            ],
            inline_policies={
                "EdgeDevicePermissions": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:GetObjectVersion",
                            ],
                            resources=[f"{self.model_bucket.bucket_arn}/*"],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "events:PutEvents",
                            ],
                            resources=[
                                f"arn:aws:events:{self.region}:{self.account}:event-bus/{self.project_name}-monitoring-bus"
                            ],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                                "logs:DescribeLogStreams",
                            ],
                            resources=[
                                f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/greengrass/*"
                            ],
                        ),
                    ]
                )
            },
        )

        return role

    def _create_role_alias(self) -> iot.CfnRoleAlias:
        """
        Create IoT role alias for the token exchange role
        
        Returns:
            IoT role alias for credential management
        """
        role_alias = iot.CfnRoleAlias(
            self,
            "GreengrassRoleAlias",
            role_alias=f"GreengrassV2TokenExchangeRoleAlias-{self.unique_suffix}",
            role_arn=self.token_exchange_role.role_arn,
        )

        return role_alias

    def _create_event_bus(self) -> events.EventBus:
        """
        Create custom EventBridge bus for edge monitoring
        
        Returns:
            EventBridge custom event bus
        """
        event_bus = events.EventBus(
            self,
            "EdgeMonitoringBus",
            event_bus_name=f"{self.project_name}-monitoring-bus",
            description="Custom event bus for edge AI inference monitoring",
        )

        return event_bus

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch log group for EventBridge events
        
        Returns:
            CloudWatch log group for event storage
        """
        log_group = logs.LogGroup(
            self,
            "EdgeEventsLogGroup",
            log_group_name="/aws/events/edge-inference",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        return log_group

    def _create_monitoring_rule(self) -> events.Rule:
        """
        Create EventBridge rule for monitoring edge inference events
        
        Returns:
            EventBridge rule for event routing
        """
        rule = events.Rule(
            self,
            "EdgeInferenceMonitoringRule",
            rule_name="edge-inference-monitoring",
            event_bus=self.event_bus,
            description="Route edge inference events to CloudWatch Logs",
            event_pattern=events.EventPattern(
                source=["edge.ai.inference"],
                detail_type=["InferenceCompleted", "InferenceError", "ModelLoadError"],
            ),
        )

        # Add CloudWatch Logs target
        rule.add_target(
            targets.CloudWatchLogGroup(
                self.log_group,
                log_event=targets.LogGroupTargetInput.from_object({
                    "timestamp": events.EventField.from_path("$.time"),
                    "source": events.EventField.from_path("$.source"),
                    "detail-type": events.EventField.from_path("$.detail-type"),
                    "detail": events.EventField.from_path("$.detail"),
                }),
            )
        )

        return rule

    def _create_onnx_runtime_component(self) -> iot.CfnComponentVersion:
        """
        Create IoT Greengrass component for ONNX runtime
        
        Returns:
            IoT Greengrass component for ML runtime
        """
        recipe = {
            "RecipeFormatVersion": "2020-01-25",
            "ComponentName": "com.edge.OnnxRuntime",
            "ComponentVersion": "1.0.0",
            "ComponentDescription": "ONNX Runtime for edge inference with optimized dependencies",
            "ComponentPublisher": "EdgeAI",
            "Manifests": [
                {
                    "Platform": {"os": "linux"},
                    "Lifecycle": {
                        "Install": {
                            "Script": "pip3 install onnxruntime==1.16.0 numpy==1.24.0 opencv-python-headless==4.8.0 boto3",
                            "Timeout": 300,
                        }
                    },
                }
            ],
        }

        component = iot.CfnComponentVersion(
            self,
            "OnnxRuntimeComponent",
            inline_recipe=recipe,
        )

        return component

    def _create_model_component(self) -> iot.CfnComponentVersion:
        """
        Create IoT Greengrass component for ML model deployment
        
        Returns:
            IoT Greengrass component for model artifacts
        """
        recipe = {
            "RecipeFormatVersion": "2020-01-25",
            "ComponentName": "com.edge.DefectDetectionModel",
            "ComponentVersion": "1.0.0",
            "ComponentDescription": f"ML model for {self.model_name} inference",
            "ComponentPublisher": "EdgeAI",
            "ComponentConfiguration": {
                "DefaultConfiguration": {
                    "ModelPath": "/greengrass/v2/work/com.edge.DefectDetectionModel",
                    "ModelS3Uri": f"s3://{self.model_bucket.bucket_name}/models/v1.0.0/",
                }
            },
            "Manifests": [
                {
                    "Platform": {"os": "linux"},
                    "Artifacts": [
                        {
                            "URI": f"s3://{self.model_bucket.bucket_name}/models/v1.0.0/model.onnx",
                            "Unarchive": "NONE",
                        },
                        {
                            "URI": f"s3://{self.model_bucket.bucket_name}/models/v1.0.0/config.json",
                            "Unarchive": "NONE",
                        },
                    ],
                    "Lifecycle": {},
                }
            ],
        }

        component = iot.CfnComponentVersion(
            self,
            "ModelComponent",
            inline_recipe=recipe,
        )

        return component

    def _create_inference_component(self) -> iot.CfnComponentVersion:
        """
        Create IoT Greengrass component for inference engine
        
        Returns:
            IoT Greengrass component for inference processing
        """
        # Inference application code (embedded in component)
        inference_code = '''import json
import time
import boto3
import onnxruntime as ort
import numpy as np
from datetime import datetime
import cv2
import os
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class EdgeInferenceEngine:
    def __init__(self):
        self.model_path = os.environ.get('MODEL_PATH', 
            '/greengrass/v2/work/com.edge.DefectDetectionModel/model.onnx')
        self.eventbridge = boto3.client('events')
        self.device_id = os.environ.get('AWS_IOT_THING_NAME', 'unknown')
        self.event_bus_name = os.environ.get('EVENT_BUS_NAME', 'default')
        self.session = None
        self.load_model()
    
    def load_model(self):
        """Load ONNX model for inference"""
        try:
            if os.path.exists(self.model_path):
                self.session = ort.InferenceSession(self.model_path)
                logger.info(f"✅ Model loaded from {self.model_path}")
            else:
                logger.warning(f"Model file not found at {self.model_path}")
                self.publish_event('ModelLoadError', {'error': 'Model file not found'})
        except Exception as e:
            logger.error(f"❌ Model loading failed: {e}")
            self.publish_event('ModelLoadError', {'error': str(e)})
    
    def preprocess_image(self, image_path):
        """Preprocess image for model input"""
        try:
            image = cv2.imread(image_path)
            if image is None:
                raise ValueError(f"Could not load image from {image_path}")
            image = cv2.resize(image, (224, 224))
            image = image.astype(np.float32) / 255.0
            image = np.transpose(image, (2, 0, 1))
            return np.expand_dims(image, axis=0)
        except Exception as e:
            logger.error(f"Image preprocessing failed: {e}")
            return None
    
    def run_inference(self, image_path='/tmp/sample_image.jpg'):
        """Perform inference on image"""
        if not self.session:
            logger.warning("Model not loaded, skipping inference")
            return None
            
        try:
            start_time = time.time()
            input_data = self.preprocess_image(image_path)
            
            if input_data is None:
                return None
                
            outputs = self.session.run(None, 
                {self.session.get_inputs()[0].name: input_data})
            
            inference_time = (time.time() - start_time) * 1000
            
            # Process results (simplified for demo)
            predictions = outputs[0][0] if outputs and len(outputs[0]) > 0 else [0.5, 0.5]
            class_idx = np.argmax(predictions)
            confidence = float(predictions[class_idx])
            
            result = {
                'timestamp': datetime.utcnow().isoformat(),
                'device_id': self.device_id,
                'image_path': image_path,
                'prediction': 'defect' if class_idx == 1 else 'normal',
                'confidence': confidence,
                'inference_time_ms': round(inference_time, 2)
            }
            
            self.publish_event('InferenceCompleted', result)
            logger.info(f"Inference completed: {result}")
            return result
            
        except Exception as e:
            logger.error(f"❌ Inference failed: {e}")
            self.publish_event('InferenceError', {'error': str(e)})
            return None
    
    def publish_event(self, event_type, detail):
        """Publish inference events to EventBridge"""
        try:
            self.eventbridge.put_events(
                Entries=[{
                    'Source': 'edge.ai.inference',
                    'DetailType': event_type,
                    'Detail': json.dumps(detail),
                    'EventBusName': self.event_bus_name
                }]
            )
            logger.debug(f"Published event: {event_type}")
        except Exception as e:
            logger.error(f"Failed to publish event: {e}")
    
    def create_sample_image(self):
        """Create a sample image for demo purposes"""
        try:
            # Create a simple colored image for testing
            sample_image = np.random.randint(0, 255, (224, 224, 3), dtype=np.uint8)
            cv2.imwrite('/tmp/sample_image.jpg', sample_image)
            logger.info("Created sample image for inference")
        except Exception as e:
            logger.error(f"Failed to create sample image: {e}")
    
    def monitor_and_infer(self):
        """Main inference loop"""
        logger.info("Starting edge inference engine...")
        
        # Create sample image if it doesn't exist
        if not os.path.exists('/tmp/sample_image.jpg'):
            self.create_sample_image()
        
        while True:
            try:
                result = self.run_inference()
                if result:
                    logger.info(f"Inference result: {result['prediction']} "
                              f"(confidence: {result['confidence']:.2f})")
                time.sleep(10)  # Run every 10 seconds
            except KeyboardInterrupt:
                logger.info("Inference engine stopped")
                break
            except Exception as e:
                logger.error(f"Unexpected error in inference loop: {e}")
                time.sleep(5)

if __name__ == "__main__":
    engine = EdgeInferenceEngine()
    engine.monitor_and_infer()
'''

        recipe = {
            "RecipeFormatVersion": "2020-01-25",
            "ComponentName": "com.edge.InferenceEngine",
            "ComponentVersion": "1.0.0",
            "ComponentDescription": "Real-time inference engine with EventBridge integration",
            "ComponentPublisher": "EdgeAI",
            "ComponentDependencies": {
                "com.edge.OnnxRuntime": {"VersionRequirement": ">=1.0.0 <2.0.0"},
                "com.edge.DefectDetectionModel": {"VersionRequirement": ">=1.0.0 <2.0.0"},
            },
            "ComponentConfiguration": {
                "DefaultConfiguration": {
                    "EventBusName": f"{self.project_name}-monitoring-bus",
                    "InferenceInterval": 10,
                    "ConfidenceThreshold": 0.8,
                }
            },
            "Manifests": [
                {
                    "Platform": {"os": "linux"},
                    "Artifacts": [
                        {
                            "URI": f"data:text/plain;base64,{cdk.Fn.base64_encode(inference_code)}",
                            "Unarchive": "NONE",
                        }
                    ],
                    "Lifecycle": {
                        "Run": {
                            "Script": "python3 {artifacts:path}/inference_app.py",
                            "RequiresPrivilege": False,
                        }
                    },
                }
            ],
        }

        component = iot.CfnComponentVersion(
            self,
            "InferenceComponent",
            inline_recipe=recipe,
        )

        return component

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        CfnOutput(
            self,
            "ModelBucketName",
            value=self.model_bucket.bucket_name,
            description="S3 bucket for storing ML models",
            export_name=f"{self.stack_name}-ModelBucket",
        )

        CfnOutput(
            self,
            "EventBusName",
            value=self.event_bus.event_bus_name,
            description="EventBridge bus for monitoring edge inference",
            export_name=f"{self.stack_name}-EventBus",
        )

        CfnOutput(
            self,
            "TokenExchangeRoleArn",
            value=self.token_exchange_role.role_arn,
            description="IAM role ARN for Greengrass token exchange",
            export_name=f"{self.stack_name}-TokenExchangeRole",
        )

        CfnOutput(
            self,
            "RoleAliasName",
            value=self.role_alias.role_alias,
            description="IoT role alias for credential management",
            export_name=f"{self.stack_name}-RoleAlias",
        )

        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="CloudWatch log group for inference events",
            export_name=f"{self.stack_name}-LogGroup",
        )

    def _apply_tags(self) -> None:
        """Apply tags to all resources in the stack"""
        Tags.of(self).add("Project", self.project_name)
        Tags.of(self).add("Component", "EdgeAI")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("CostCenter", "MLOps")
        Tags.of(self).add("Owner", "DataScience")


def main() -> None:
    """
    Main function to create and deploy the CDK application
    """
    app = App()

    # Get configuration from environment variables or use defaults
    project_name = app.node.try_get_context("projectName") or "edge-ai-inference"
    model_name = app.node.try_get_context("modelName") or "defect-detection"
    
    # Create the stack
    EdgeAIInferenceStack(
        app,
        "EdgeAIInferenceStack",
        project_name=project_name,
        model_name=model_name,
        description="Real-time Edge AI Inference with SageMaker Edge Manager and IoT Greengrass",
        env=Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        ),
    )

    app.synth()


if __name__ == "__main__":
    main()