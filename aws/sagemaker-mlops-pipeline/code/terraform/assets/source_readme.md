# ML Model Deployment Pipeline Source Code

This directory contains the source code for the ${project_name} machine learning model deployment pipeline.

## Structure

- `train.py` - Model training script for fraud detection
- `buildspecs/` - CodeBuild configuration files
  - `buildspec-train.yml` - Configuration for model training stage
  - `buildspec-test.yml` - Configuration for model testing stage
- `requirements.txt` - Python dependencies
- `README.md` - This file

## Pipeline Stages

### 1. Source
Code changes in this repository trigger the pipeline execution.

### 2. Build (Training)
- Executes the training script using SageMaker
- Registers the trained model in SageMaker Model Registry
- Sets model approval status to "PendingManualApproval"

### 3. Test
- Deploys the model to a temporary test endpoint
- Performs validation tests on the model
- Automatically approves the model if tests pass
- Cleans up test resources

### 4. Deploy
- Deploys approved models to production endpoints
- Manages endpoint configurations and scaling
- Provides rollback capabilities

## Model Training

The training script (`train.py`) implements a Random Forest classifier for fraud detection using synthetic data. In a production environment, you would:

1. Replace synthetic data generation with real data loading from S3
2. Implement proper feature engineering and data preprocessing
3. Add model validation and hyperparameter tuning
4. Include proper error handling and logging

## Customization

To customize this pipeline for your use case:

1. **Update training script**: Modify `train.py` to use your data and model architecture
2. **Configure buildspecs**: Adjust environment variables and build commands in the buildspec files
3. **Add dependencies**: Update `requirements.txt` with any additional Python packages
4. **Modify testing**: Enhance the testing stage with your specific validation requirements

## Deployment

To deploy changes:

1. Commit your changes to this repository
2. Zip the source code: `zip -r ml-source-code.zip .`
3. Upload to S3: `aws s3 cp ml-source-code.zip s3://your-bucket/source/ml-source-code.zip`
4. The pipeline will automatically trigger and process the changes

## Monitoring

Monitor the pipeline execution through:

- AWS CodePipeline Console
- CloudWatch Logs for detailed build logs
- SageMaker Console for model registry and endpoints

## Support

For issues with this pipeline, refer to:
- AWS SageMaker documentation
- AWS CodePipeline documentation
- Project-specific documentation