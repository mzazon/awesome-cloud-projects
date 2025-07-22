"""
Setup configuration for Multi-Language Voice Processing Pipeline CDK Application

This setup.py file configures the Python package for the AWS CDK application
that deploys a comprehensive voice processing solution using Amazon Transcribe,
Amazon Translate, and Amazon Polly services.
"""

from setuptools import setup, find_packages
import os

# Read the contents of README file
def read_long_description():
    """Read the README file for the long description"""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "Multi-Language Voice Processing Pipeline using AWS CDK"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file"""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    requirements = []
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    requirements.append(line)
    return requirements

setup(
    name="multi-language-voice-processing-cdk",
    version="1.0.0",
    description="AWS CDK application for multi-language voice processing pipeline",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    author="AWS Solutions Architect",
    author_email="support@example.com",
    url="https://github.com/aws-samples/multi-language-voice-processing",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "isort>=5.12.0",
            "bandit>=1.7.5",
            "safety>=2.3.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",
            "localstack>=3.0.0",
            "boto3-stubs[transcribe,translate,polly,s3,dynamodb,stepfunctions]>=1.34.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
            "myst-parser>=2.0.0",
        ],
        "monitoring": [
            "structlog>=23.0.0",
            "python-json-logger>=2.0.0",
            "py-spy>=0.3.0",
            "memory-profiler>=0.60.0",
        ]
    },
    
    # Console scripts
    entry_points={
        "console_scripts": [
            "voice-pipeline-deploy=app:main",
        ],
    },
    
    # Package metadata
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Multimedia :: Sound/Audio :: Speech",
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
    ],
    
    # Keywords for PyPI
    keywords=[
        "aws", "cdk", "cloud", "infrastructure", "voice-processing", 
        "transcribe", "translate", "polly", "ai", "machine-learning",
        "speech-to-text", "text-to-speech", "translation", "multilingual",
        "serverless", "lambda", "step-functions", "s3", "dynamodb"
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/multi-language-voice-processing",
        "Tracker": "https://github.com/aws-samples/multi-language-voice-processing/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Transcribe": "https://aws.amazon.com/transcribe/",
        "AWS Translate": "https://aws.amazon.com/translate/",
        "AWS Polly": "https://aws.amazon.com/polly/",
    },
    
    # License information
    license="Apache-2.0",
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.yml", "*.yaml", "*.json"],
    },
    
    # Manifest template for additional files
    include_package_data=True,
    
    # Platform compatibility
    platforms=["any"],
    
    # Test suite configuration
    test_suite="tests",
    
    # Additional metadata
    maintainer="AWS Solutions Team",
    maintainer_email="aws-solutions@amazon.com",
    
    # Dependency links (if needed for private packages)
    dependency_links=[],
    
    # Namespace packages (if using)
    namespace_packages=[],
    
    # Data files to install
    data_files=[
        ("examples", ["examples/sample_audio.mp3"]) if os.path.exists("examples/sample_audio.mp3") else [],
        ("docs", ["docs/architecture.md"]) if os.path.exists("docs/architecture.md") else [],
        ("scripts", ["scripts/deploy.sh", "scripts/destroy.sh"]) if os.path.exists("scripts") else [],
    ],
    
    # Setup requires for build-time dependencies
    setup_requires=[
        "setuptools>=65.0.0",
        "wheel>=0.37.0",
    ],
    
    # Options for building wheels
    options={
        "bdist_wheel": {
            "universal": False,
        },
        "build_py": {
            "compile": True,
            "optimize": 2,
        },
        "install": {
            "compile": True,
            "optimize": 2,
        },
    },
    
    # CDK-specific configuration
    cdk_version="2.110.0",
    
    # Custom metadata for the voice processing pipeline
    voice_processing_config={
        "supported_languages": [
            "en", "es", "fr", "de", "it", "pt", "ja", "ko", 
            "zh", "ar", "hi", "ru", "nl", "sv"
        ],
        "default_target_languages": ["es", "fr", "de"],
        "max_audio_duration_minutes": 240,
        "supported_audio_formats": ["mp3", "wav", "flac", "ogg"],
        "neural_voices_available": [
            "Joanna", "Matthew", "Ivy", "Justin", "Kendra", 
            "Kimberly", "Salli", "Joey", "Lupe", "Lucia", 
            "Lea", "Vicki", "Bianca", "Camila", "Takumi", 
            "Zhiyu", "Ruth", "Stephen"
        ],
    },
    
    # Security configuration
    security_config={
        "encryption_at_rest": True,
        "encryption_in_transit": True,
        "iam_least_privilege": True,
        "vpc_endpoints": False,  # Optional for enhanced security
        "audit_logging": True,
    },
    
    # Performance configuration
    performance_config={
        "lambda_memory_sizes": {
            "language_detector": 512,
            "transcription_processor": 512,
            "translation_processor": 512,
            "speech_synthesizer": 512,
            "job_status_checker": 256,
        },
        "lambda_timeouts": {
            "language_detector": 300,
            "transcription_processor": 300,
            "translation_processor": 600,
            "speech_synthesizer": 600,
            "job_status_checker": 30,
        },
        "step_functions_timeout_hours": 2,
        "dynamodb_billing_mode": "PAY_PER_REQUEST",
    },
    
    # Cost optimization settings
    cost_optimization={
        "s3_lifecycle_rules": True,
        "cloudwatch_log_retention_days": 7,
        "lambda_reserved_concurrency": None,  # Use default
        "step_functions_express_workflows": False,  # Use standard for reliability
    },
)

# Additional setup for CDK context
def setup_cdk_context():
    """Setup CDK context configuration"""
    cdk_context = {
        "@aws-cdk/core:enableStackNameDuplicates": True,
        "@aws-cdk/core:stackRelativeExports": True,
        "@aws-cdk/aws-lambda:recognizeVersionProps": True,
        "@aws-cdk/aws-lambda:recognizeLayerVersion": True,
        "@aws-cdk/aws-cloudfront:defaultSecurityPolicyTLSv1.2_2021": True,
        "@aws-cdk/aws-s3:serverAccessLogsUseBucketPolicy": True,
        "@aws-cdk/aws-stepfunctions:useDelayedActivation": True,
        "@aws-cdk/aws-iam:minimizePolicies": True,
        "@aws-cdk/aws-lambda:coldStartWarning": True,
    }
    
    # Write CDK context to cdk.json if it doesn't exist
    import json
    cdk_json_path = os.path.join(os.path.dirname(__file__), "cdk.json")
    if not os.path.exists(cdk_json_path):
        cdk_config = {
            "app": "python app.py",
            "watch": {
                "include": [
                    "**"
                ],
                "exclude": [
                    "README.md",
                    "cdk*.json",
                    "requirements*.txt",
                    "source.bat",
                    "**/__pycache__",
                    "**/.venv",
                    "**/.env"
                ]
            },
            "context": cdk_context,
            "feature_flags": {
                "@aws-cdk/core:enableStackNameDuplicates": True,
                "@aws-cdk/core:stackRelativeExports": True,
            }
        }
        
        with open(cdk_json_path, "w") as f:
            json.dump(cdk_config, f, indent=2)

# Run CDK context setup
if __name__ == "__main__":
    setup_cdk_context()
    print("CDK Python setup completed successfully!")
    print("To deploy the voice processing pipeline:")
    print("1. Install dependencies: pip install -r requirements.txt")
    print("2. Bootstrap CDK: cdk bootstrap")
    print("3. Deploy stack: cdk deploy")