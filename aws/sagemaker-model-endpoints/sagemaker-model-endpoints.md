---
title: SageMaker Model Endpoints for ML Inference
id: d005ff94
category: machine-learning
difficulty: 300
subject: aws
services: sagemaker, ecr, cloudwatch, s3
estimated-time: 120 minutes
recipe-version: 1.2
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: 2025-07-23
passed-qa: null
tags: machine-learning, sagemaker, endpoints, containers, auto-scaling, cloudwatch, production-ml
recipe-generator-version: 1.3
---

# SageMaker Model Endpoints for ML Inference

## Problem

Your data science team has trained and validated machine learning models in development environments, but you need to deploy these models to production with reliable, scalable inference capabilities. You require endpoints that can handle variable traffic loads, provide low-latency predictions, and integrate seamlessly with your existing applications while maintaining security and monitoring best practices.

## Solution

Deploy machine learning models as scalable, managed endpoints using Amazon SageMaker real-time hosting services. SageMaker endpoints provide fully managed infrastructure with automatic scaling, built-in monitoring, and support for A/B testing. The solution includes model packaging in containers, endpoint configuration with auto-scaling policies, and comprehensive monitoring dashboards that follow AWS Well-Architected principles.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Development"
        MODEL[Trained ML Model]
        CONTAINER[Model Container]
        MODEL --> CONTAINER
    end
    
    subgraph "Amazon ECR"
        ECR_IMAGE[Container Image]
        CONTAINER --> ECR_IMAGE
    end
    
    subgraph "Amazon S3"
        MODEL_ARTIFACTS[Model Artifacts<br/>(.tar.gz)]
        MODEL --> MODEL_ARTIFACTS
    end
    
    subgraph "SageMaker Hosting"
        SM_MODEL[SageMaker Model]
        ENDPOINT_CONFIG[Endpoint Configuration]
        ENDPOINT[SageMaker Endpoint]
        
        MODEL_ARTIFACTS --> SM_MODEL
        ECR_IMAGE --> SM_MODEL
        SM_MODEL --> ENDPOINT_CONFIG
        ENDPOINT_CONFIG --> ENDPOINT
    end
    
    subgraph "Monitoring & Scaling"
        CW[CloudWatch Metrics]
        AS[Auto Scaling]
        ENDPOINT --> CW
        CW --> AS
        AS --> ENDPOINT
    end
    
    CLIENT[Client Application] --> ENDPOINT
    ENDPOINT --> CLIENT
    
    style SM_MODEL fill:#FF9900
    style ENDPOINT fill:#FF9900
    style ECR_IMAGE fill:#3F8624
```

## Prerequisites

1. AWS account with SageMaker, ECR, S3, and IAM permissions
2. Trained machine learning model (pickle, joblib, or framework-specific format)
3. Docker installed locally for containerization
4. Python 3.8+ with boto3 and sagemaker SDK installed
5. AWS CLI version 2 configured with appropriate credentials
6. Basic understanding of containerization and ML model deployment
7. Estimated cost: $5-20 per hour depending on instance type and traffic

> **Note**: This recipe follows [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html) principles for reliability, security, and cost optimization.

## Preparation

Set up the foundational infrastructure and prepare your model for deployment:

```bash
# Set AWS environment variables
export AWS_REGION=$(aws configure get region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

# Set resource names
MODEL_NAME="sklearn-iris-classifier-${RANDOM_SUFFIX}"
ENDPOINT_NAME="iris-prediction-endpoint-${RANDOM_SUFFIX}"
ECR_REPOSITORY_NAME="sagemaker-sklearn-inference-${RANDOM_SUFFIX}"
BUCKET_NAME="sagemaker-models-${RANDOM_SUFFIX}"

# Create ECR repository for our custom inference image
aws ecr create-repository \
    --repository-name $ECR_REPOSITORY_NAME \
    --image-scanning-configuration scanOnPush=true \
    --region $AWS_REGION

# Get ECR login credentials
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin \
    $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Create S3 bucket for model artifacts
aws s3 mb s3://$BUCKET_NAME --region $AWS_REGION

# Enable S3 bucket versioning and encryption
aws s3api put-bucket-versioning \
    --bucket $BUCKET_NAME \
    --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
    --bucket $BUCKET_NAME \
    --server-side-encryption-configuration \
    'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'

# Export variables for later steps
export AWS_REGION AWS_ACCOUNT_ID MODEL_NAME ENDPOINT_NAME
export ECR_REPOSITORY_NAME BUCKET_NAME RANDOM_SUFFIX

echo "✅ AWS environment configured"
```

Create the SageMaker execution role with least privilege access:

```bash
# Create trust policy for SageMaker
cat > sagemaker-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "sagemaker.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create SageMaker execution role
ROLE_NAME="SageMakerExecutionRole-${RANDOM_SUFFIX}"
aws iam create-role \
    --role-name $ROLE_NAME \
    --assume-role-policy-document file://sagemaker-trust-policy.json

# Create custom policy for minimal required permissions
cat > sagemaker-execution-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::sagemaker-*/*",
                "arn:aws:s3:::sagemaker-*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:DescribeLogStreams",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:log-group:/aws/sagemaker/*"
        }
    ]
}
EOF

# Create and attach custom policy
aws iam create-policy \
    --policy-name SageMakerExecutionPolicy-${RANDOM_SUFFIX} \
    --policy-document file://sagemaker-execution-policy.json

aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/SageMakerExecutionPolicy-${RANDOM_SUFFIX}

# Get role ARN
ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME \
    --query 'Role.Arn' --output text)

export ROLE_NAME ROLE_ARN

echo "✅ SageMaker execution role created with least privilege access"
```

## Steps

1. **Create and containerize your inference code with a sample scikit-learn model**:

   Amazon SageMaker enables you to deploy any machine learning model using custom containers, providing complete control over the inference pipeline. This approach demonstrates real-world ML deployment patterns including proper model serialization, validation, and production-ready error handling that scales across various ML frameworks and use cases.

   ```bash
   # Create model training script
   mkdir -p model-training
   cat > model-training/train_model.py << 'EOF'
   import pickle
   import numpy as np
   from sklearn.datasets import load_iris
   from sklearn.ensemble import RandomForestClassifier
   from sklearn.model_selection import train_test_split
   from sklearn.metrics import accuracy_score, classification_report
   
   # Load and prepare data
   iris = load_iris()
   X_train, X_test, y_train, y_test = train_test_split(
       iris.data, iris.target, test_size=0.2, random_state=42
   )
   
   # Train model
   model = RandomForestClassifier(n_estimators=100, random_state=42)
   model.fit(X_train, y_train)
   
   # Validate model
   predictions = model.predict(X_test)
   accuracy = accuracy_score(y_test, predictions)
   print(f"Model accuracy: {accuracy:.3f}")
   print("Classification Report:")
   print(classification_report(y_test, predictions, 
         target_names=iris.target_names))
   
   # Save model
   with open('model.pkl', 'wb') as f:
       pickle.dump(model, f)
   
   print("Model saved as model.pkl")
   EOF
   
   # Train and save the model
   cd model-training
   python train_model.py
   cd ..
   
   echo "✅ Model trained and validated successfully"
   ```

2. **Create the inference container with custom prediction logic**:

   Building a custom inference container gives you complete control over the prediction pipeline, including preprocessing, model loading, and response formatting. This approach enables integration with any ML framework while maintaining production-grade standards for error handling, logging, and monitoring that meet enterprise requirements.

   ```bash
   # Create container directory structure
   mkdir -p container/code
   
   # Create inference script
   cat > container/code/predictor.py << 'EOF'
   import pickle
   import json
   import numpy as np
   import os
   import logging
   import traceback
   from flask import Flask, request, jsonify
   
   # Configure logging
   logging.basicConfig(level=logging.INFO)
   logger = logging.getLogger(__name__)
   
   app = Flask(__name__)
   
   class ModelHandler:
       def __init__(self):
           self.model = None
           self.class_names = ['setosa', 'versicolor', 'virginica']
           self.feature_names = ['sepal_length', 'sepal_width', 
                               'petal_length', 'petal_width']
       
       def load_model(self):
           """Load the model from the model directory"""
           model_path = '/opt/ml/model/model.pkl'
           if os.path.exists(model_path):
               try:
                   with open(model_path, 'rb') as f:
                       self.model = pickle.load(f)
                   logger.info("Model loaded successfully")
               except Exception as e:
                   logger.error(f"Error loading model: {str(e)}")
                   raise
           else:
               raise FileNotFoundError(f"Model file not found at {model_path}")
       
       def validate_input(self, data):
           """Validate input data format and values"""
           if not isinstance(data, list):
               raise ValueError("Input must be a list of feature arrays")
           
           for idx, instance in enumerate(data):
               if not isinstance(instance, list) or len(instance) != 4:
                   raise ValueError(f"Instance {idx} must have exactly 4 features")
               
               if not all(isinstance(x, (int, float)) for x in instance):
                   raise ValueError(f"Instance {idx} contains non-numeric values")
       
       def predict(self, data):
           """Make predictions on input data"""
           if self.model is None:
               raise RuntimeError("Model not loaded")
           
           # Validate input
           self.validate_input(data)
           
           # Convert input to numpy array
           input_data = np.array(data).reshape(-1, 4)
           
           # Make predictions
           predictions = self.model.predict(input_data)
           probabilities = self.model.predict_proba(input_data)
           
           # Format results
           results = []
           for i, pred in enumerate(predictions):
               confidence = float(np.max(probabilities[i]))
               results.append({
                   'predicted_class': self.class_names[pred],
                   'predicted_class_index': int(pred),
                   'confidence': confidence,
                   'probabilities': {
                       self.class_names[j]: float(prob) 
                       for j, prob in enumerate(probabilities[i])
                   },
                   'input_features': {
                       self.feature_names[j]: float(data[i][j])
                       for j in range(4)
                   }
               })
           
           return results
   
   # Initialize model handler
   model_handler = ModelHandler()
   
   @app.route('/ping', methods=['GET'])
   def ping():
       """Health check endpoint"""
       try:
           status = 200 if model_handler.model is not None else 404
           return '', status
       except Exception as e:
           logger.error(f"Health check failed: {str(e)}")
           return '', 500
   
   @app.route('/invocations', methods=['POST'])
   def invocations():
       """Prediction endpoint"""
       try:
           # Parse input data
           content_type = request.content_type
           if content_type != 'application/json':
               return jsonify({
                   'error': f'Unsupported content type: {content_type}'
               }), 400
           
           input_data = request.get_json()
           
           if not input_data or 'instances' not in input_data:
               return jsonify({
                   'error': 'Input must contain "instances" key'
               }), 400
           
           # Make predictions
           predictions = model_handler.predict(input_data['instances'])
           
           logger.info(f"Processed {len(predictions)} predictions successfully")
           return jsonify({'predictions': predictions})
       
       except ValueError as e:
           logger.warning(f"Input validation error: {str(e)}")
           return jsonify({'error': f'Invalid input: {str(e)}'}), 400
       except Exception as e:
           logger.error(f"Prediction error: {str(e)}")
           logger.error(traceback.format_exc())
           return jsonify({'error': 'Internal server error'}), 500
   
   if __name__ == '__main__':
       try:
           # Load model at startup
           model_handler.load_model()
           logger.info("Starting Flask server on port 8080")
           
           # Start Flask server
           app.run(host='0.0.0.0', port=8080)
       except Exception as e:
           logger.error(f"Failed to start server: {str(e)}")
           raise
   EOF
   
   # Create Dockerfile with security best practices
   cat > container/Dockerfile << 'EOF'
   FROM python:3.9-slim
   
   # Create non-root user for security
   RUN useradd --create-home --shell /bin/bash sagemaker
   
   # Install system dependencies
   RUN apt-get update && apt-get install -y \
       build-essential \
       curl \
       && rm -rf /var/lib/apt/lists/* \
       && apt-get clean
   
   # Install Python dependencies
   RUN pip install --no-cache-dir --upgrade pip && \
       pip install --no-cache-dir \
       flask==2.3.3 \
       scikit-learn==1.3.2 \
       numpy==1.24.4 \
       gunicorn==21.2.0
   
   # Copy prediction code
   COPY code /opt/ml/code
   WORKDIR /opt/ml/code
   
   # Set permissions
   RUN chown -R sagemaker:sagemaker /opt/ml/code
   
   # Set environment variables
   ENV PYTHONUNBUFFERED=TRUE
   ENV PYTHONDONTWRITEBYTECODE=TRUE
   ENV PATH="/opt/ml/code:${PATH}"
   
   # Switch to non-root user
   USER sagemaker
   
   # Expose port
   EXPOSE 8080
   
   # Health check
   HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
       CMD curl -f http://localhost:8080/ping || exit 1
   
   # Define entrypoint
   ENTRYPOINT ["python", "predictor.py"]
   EOF
   
   echo "✅ Inference container code created with production-ready features"
   ```

   > **Note**: The inference container follows [SageMaker container specifications](https://docs.aws.amazon.com/sagemaker/latest/dg/your-algorithms-inference-code.html) with `/ping` for health checks and `/invocations` for predictions. The model is loaded from `/opt/ml/model/` where SageMaker automatically extracts your model artifacts.

3. **Build and push the container image to Amazon ECR**:

   Amazon ECR provides a secure, scalable container registry that integrates seamlessly with SageMaker. By storing your inference containers in ECR, you ensure they're available across your AWS environment with proper access controls and vulnerability scanning. This containerization approach enables consistent deployments across development, staging, and production environments while maintaining version control of your ML inference code.

   ```bash
   # Build the container image
   docker build -t $ECR_REPOSITORY_NAME container/
   
   # Tag for ECR
   ECR_IMAGE_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY_NAME:latest"
   docker tag $ECR_REPOSITORY_NAME:latest $ECR_IMAGE_URI
   
   # Push to ECR
   docker push $ECR_IMAGE_URI
   
   echo "✅ Container image pushed to: $ECR_IMAGE_URI"
   export ECR_IMAGE_URI
   ```

   The container image is now stored in ECR with automatic vulnerability scanning enabled. ECR provides immutable image tags and integrates with AWS security services, ensuring your production inference environment maintains the security and consistency standards required for enterprise ML deployments.

4. **Package and upload the trained model to S3**:

   Model artifacts must be packaged as tar.gz files for SageMaker deployment. This standardized format ensures consistent model loading across different runtime environments and enables version control of your trained models. S3 provides the durable, scalable storage required for production ML artifacts.

   ```bash
   # Create model archive
   cd model-training
   tar -czf model.tar.gz model.pkl
   
   # Upload to S3 with server-side encryption
   aws s3 cp model.tar.gz s3://$BUCKET_NAME/models/v1/model.tar.gz \
       --server-side-encryption AES256
   
   cd ..
   
   MODEL_DATA_URL="s3://$BUCKET_NAME/models/v1/model.tar.gz"
   echo "✅ Model uploaded to: $MODEL_DATA_URL"
   export MODEL_DATA_URL
   ```

5. **Create the SageMaker model**:

   The SageMaker model object combines your container image with your trained model artifacts, creating a deployable unit that can be used across multiple endpoint configurations. This separation enables flexible deployment strategies like A/B testing, blue-green deployments, and canary releases while maintaining consistency in your ML inference pipeline.

   ```bash
   aws sagemaker create-model \
       --model-name $MODEL_NAME \
       --primary-container Image=$ECR_IMAGE_URI,ModelDataUrl=$MODEL_DATA_URL \
       --execution-role-arn $ROLE_ARN \
       --tags Key=Environment,Value=Production \
             Key=Project,Value=IrisClassifier \
             Key=CostCenter,Value=MLOps \
       --region $AWS_REGION
   
   echo "✅ SageMaker model created: $MODEL_NAME"
   ```

6. **Create an endpoint configuration with optimized settings**:

   Endpoint configurations define the infrastructure specifications for your model hosting, including instance types, initial capacity, and traffic distribution. This separation between model definition and hosting configuration enables flexible deployment strategies like A/B testing, canary deployments, and blue-green rollouts. The configuration acts as a blueprint that can be reused across multiple endpoints, promoting consistency and operational efficiency in your ML deployment pipeline.

   ```bash
   ENDPOINT_CONFIG_NAME="${MODEL_NAME}-config"
   
   aws sagemaker create-endpoint-config \
       --endpoint-config-name $ENDPOINT_CONFIG_NAME \
       --production-variants \
       VariantName=primary,ModelName=$MODEL_NAME,InitialInstanceCount=1,InstanceType=ml.m5.large,InitialVariantWeight=1.0 \
       --tags Key=Environment,Value=Production \
             Key=Project,Value=IrisClassifier \
       --region $AWS_REGION
   
   echo "✅ Endpoint configuration created: $ENDPOINT_CONFIG_NAME"
   export ENDPOINT_CONFIG_NAME
   ```

   The endpoint configuration is now established with specifications for hosting your model on ml.m5.large instances, which provide balanced compute, memory, and networking performance suitable for most ML inference workloads. This configuration determines the compute resources, scaling behavior, and traffic allocation, providing the foundation for reliable, production-ready inference services.

   > **Warning**: Choose appropriate instance types based on your model's computational requirements. ml.m5.large is suitable for most ML models, but complex deep learning models may require compute-optimized instances like ml.c5.xlarge or GPU instances like ml.g4dn.xlarge for better performance.

7. **Deploy the endpoint**:

   Endpoint deployment typically takes 5-10 minutes as SageMaker provisions instances, downloads your container image, and performs health checks. During this time, SageMaker ensures your endpoint is ready to handle production traffic with proper load balancing and failover capabilities across multiple Availability Zones for high availability.

   ```bash
   aws sagemaker create-endpoint \
       --endpoint-name $ENDPOINT_NAME \
       --endpoint-config-name $ENDPOINT_CONFIG_NAME \
       --tags Key=Environment,Value=Production \
             Key=Project,Value=IrisClassifier \
       --region $AWS_REGION
   
   echo "Creating endpoint: $ENDPOINT_NAME"
   echo "This will take 5-10 minutes..."
   
   # Wait for endpoint to be in service
   aws sagemaker wait endpoint-in-service \
       --endpoint-name $ENDPOINT_NAME \
       --region $AWS_REGION
   
   echo "✅ Endpoint is now in service and ready for inference!"
   ```

8. **Configure auto-scaling for the endpoint**:

   Auto-scaling ensures your endpoints can handle traffic spikes while minimizing costs during low-usage periods. SageMaker uses CloudWatch metrics to automatically add or remove instances based on invocation patterns, maintaining consistent performance across varying workloads. This follows AWS cost optimization best practices by scaling resources based on actual demand.

   ```bash
   # Register scalable target
   aws application-autoscaling register-scalable-target \
       --service-namespace sagemaker \
       --resource-id endpoint/$ENDPOINT_NAME/variant/primary \
       --scalable-dimension sagemaker:variant:DesiredInstanceCount \
       --min-capacity 1 \
       --max-capacity 5 \
       --region $AWS_REGION
   
   # Create scaling policy based on invocations per instance
   aws application-autoscaling put-scaling-policy \
       --service-namespace sagemaker \
       --resource-id endpoint/$ENDPOINT_NAME/variant/primary \
       --scalable-dimension sagemaker:variant:DesiredInstanceCount \
       --policy-name iris-endpoint-scaling-policy \
       --policy-type TargetTrackingScaling \
       --target-tracking-scaling-policy-configuration \
       '{"TargetValue":70.0,"PredefinedMetricSpecification":{"PredefinedMetricType":"SageMakerVariantInvocationsPerInstance"}}' \
       --region $AWS_REGION
   
   echo "✅ Auto-scaling configured for endpoint"
   ```

   > **Tip**: Monitor your scaling events through CloudWatch to fine-tune scaling policies. Consider using custom CloudWatch metrics for more sophisticated scaling decisions based on application-specific metrics like request queue length or response time. Learn more about [SageMaker endpoint auto-scaling](https://docs.aws.amazon.com/sagemaker/latest/dg/endpoint-auto-scaling.html).

## Validation & Testing

Verify that your SageMaker endpoint is working correctly and performing as expected:

1. **Test the endpoint with sample predictions**:

   ```bash
   # Create test data representing different iris species
   cat > test_payload.json << 'EOF'
   {
     "instances": [
       [5.1, 3.5, 1.4, 0.2],
       [6.7, 3.1, 4.4, 1.4],
       [6.3, 3.3, 6.0, 2.5]
     ]
   }
   EOF
   
   # Test prediction via AWS CLI
   aws sagemaker-runtime invoke-endpoint \
       --endpoint-name $ENDPOINT_NAME \
       --content-type application/json \
       --body fileb://test_payload.json \
       --region $AWS_REGION \
       prediction_output.json
   
   # Display results
   echo "Prediction results:"
   cat prediction_output.json | python -m json.tool
   ```

   Expected output:
   ```json
   {
     "predictions": [
       {
         "predicted_class": "setosa",
         "predicted_class_index": 0,
         "confidence": 1.0,
         "probabilities": {
           "setosa": 1.0,
           "versicolor": 0.0,
           "virginica": 0.0
         },
         "input_features": {
           "sepal_length": 5.1,
           "sepal_width": 3.5,
           "petal_length": 1.4,
           "petal_width": 0.2
         }
       }
     ]
   }
   ```

2. **Verify endpoint metrics in CloudWatch**:

   ```bash
   # Check endpoint status
   aws sagemaker describe-endpoint \
       --endpoint-name $ENDPOINT_NAME \
       --query 'EndpointStatus' \
       --output text \
       --region $AWS_REGION
   
   # View recent invocations metric
   START_TIME=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)
   END_TIME=$(date -u +%Y-%m-%dT%H:%M:%S)
   
   aws cloudwatch get-metric-statistics \
       --namespace AWS/SageMaker \
       --metric-name Invocations \
       --dimensions Name=EndpointName,Value=$ENDPOINT_NAME \
                   Name=VariantName,Value=primary \
       --start-time $START_TIME \
       --end-time $END_TIME \
       --period 300 \
       --statistics Sum \
       --region $AWS_REGION
   
   echo "✅ Endpoint metrics verification completed"
   ```

3. **Test error handling and validation**:

   ```bash
   # Test with invalid input to verify error handling
   cat > invalid_payload.json << 'EOF'
   {
     "instances": [
       [1, 2, 3]
     ]
   }
   EOF
   
   aws sagemaker-runtime invoke-endpoint \
       --endpoint-name $ENDPOINT_NAME \
       --content-type application/json \
       --body fileb://invalid_payload.json \
       --region $AWS_REGION \
       error_output.json || echo "Expected error occurred"
   
   echo "Error handling test:"
   cat error_output.json | python -m json.tool
   ```

## Cleanup

Remove all created resources to avoid ongoing charges:

```bash
# Delete the endpoint (this stops billing for inference instances)
aws sagemaker delete-endpoint \
    --endpoint-name $ENDPOINT_NAME \
    --region $AWS_REGION

echo "Waiting for endpoint deletion..."
aws sagemaker wait endpoint-deleted \
    --endpoint-name $ENDPOINT_NAME \
    --region $AWS_REGION

# Delete auto-scaling configuration
aws application-autoscaling deregister-scalable-target \
    --service-namespace sagemaker \
    --resource-id endpoint/$ENDPOINT_NAME/variant/primary \
    --scalable-dimension sagemaker:variant:DesiredInstanceCount \
    --region $AWS_REGION

# Delete endpoint configuration
aws sagemaker delete-endpoint-config \
    --endpoint-config-name $ENDPOINT_CONFIG_NAME \
    --region $AWS_REGION

# Delete the model
aws sagemaker delete-model \
    --model-name $MODEL_NAME \
    --region $AWS_REGION

# Delete S3 bucket and contents
aws s3 rm s3://$BUCKET_NAME --recursive
aws s3 rb s3://$BUCKET_NAME

# Delete ECR repository
aws ecr delete-repository \
    --repository-name $ECR_REPOSITORY_NAME \
    --force \
    --region $AWS_REGION

# Delete IAM policy and role
aws iam detach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/SageMakerExecutionPolicy-${RANDOM_SUFFIX}

aws iam delete-policy \
    --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/SageMakerExecutionPolicy-${RANDOM_SUFFIX}

aws iam delete-role --role-name $ROLE_NAME

# Clean up local files
rm -rf container/ model-training/ *.json *.gz

echo "✅ All resources cleaned up successfully"
```

## Discussion

Amazon SageMaker provides a comprehensive platform for deploying machine learning models at scale without the operational overhead of managing underlying infrastructure. The managed endpoint service handles provisioning, scaling, patching, and monitoring of the compute instances that serve your models, following AWS Well-Architected principles for operational excellence. This abstraction allows data science teams to focus on model development and performance rather than infrastructure management while ensuring enterprise-grade reliability and security.

The containerization approach demonstrated in this recipe provides maximum flexibility for model deployment while maintaining security best practices. By creating custom inference containers with non-root users, health checks, and comprehensive error handling, you can control the entire prediction pipeline, implement complex pre-processing logic, and integrate with existing frameworks and libraries. SageMaker's support for custom containers means you're not limited to specific frameworks - you can deploy TensorFlow, PyTorch, scikit-learn, XGBoost, or even proprietary models using the same infrastructure patterns.

Auto-scaling capabilities ensure that your endpoints can handle variable traffic patterns cost-effectively, following AWS cost optimization best practices. SageMaker automatically adjusts the number of instances based on traffic patterns, which is crucial for production applications with unpredictable loads. The integration with CloudWatch provides comprehensive monitoring and alerting capabilities, enabling proactive response to performance issues. For organizations implementing MLOps practices, SageMaker endpoints integrate seamlessly with CI/CD pipelines, enabling automated model deployment, A/B testing workflows, and blue-green deployments that support continuous model improvement and deployment strategies.

Consider the cost implications of your instance choices and right-sizing strategies. While larger instances provide better performance, they also cost more. Monitor your endpoint metrics to optimize the balance between performance and cost. For variable workloads, consider implementing multiple endpoint configurations or using [SageMaker Serverless Inference](https://docs.aws.amazon.com/sagemaker/latest/dg/serverless-endpoints.html) for truly on-demand scaling. The security model implemented here follows AWS security best practices with least privilege IAM roles, encrypted data at rest and in transit, and comprehensive logging for audit compliance.

> **Warning**: Always implement proper error handling and input validation in your inference code. Malformed requests can cause endpoint failures that impact all traffic to that endpoint. Regular security updates and vulnerability scanning of your container images are essential for maintaining production security posture.

## Challenge

Extend this solution by implementing these enhancements:

1. **Multi-model endpoint**: Deploy multiple model versions simultaneously for A/B testing between different algorithms (Random Forest vs. Gradient Boosting) with traffic splitting capabilities.
2. **Advanced monitoring**: Add comprehensive logging and custom CloudWatch metrics to compare model performance, including latency, accuracy, and business metrics with automated alerting.
3. **Model explainability**: Integrate SHAP (SHapley Additive exPlanations) values into your prediction response to provide model interpretability and build trust with end users.
4. **CI/CD pipeline**: Create an automated deployment pipeline using AWS CodePipeline that includes model validation, security scanning, and staged rollouts.
5. **Edge deployment**: Extend the solution to support edge inference using AWS IoT Greengrass for local, low-latency predictions in IoT environments.

## Infrastructure Code

### Available Infrastructure as Code:

- [Infrastructure Code Overview](code/README.md) - Detailed description of all infrastructure components
- [AWS CDK (Python)](code/cdk-python/) - AWS CDK Python implementation
- [AWS CDK (TypeScript)](code/cdk-typescript/) - AWS CDK TypeScript implementation
- [CloudFormation](code/cloudformation.yaml) - AWS CloudFormation template
- [Bash CLI Scripts](code/scripts/) - Example bash scripts using AWS CLI commands to deploy infrastructure
- [Terraform](code/terraform/) - Terraform configuration files