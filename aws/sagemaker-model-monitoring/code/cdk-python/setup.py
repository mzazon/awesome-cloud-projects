"""
Setup configuration for SageMaker Model Monitoring CDK Application

This setup.py file configures the Python package for the CDK application
that deploys SageMaker Model Monitor infrastructure for drift detection.
"""

import setuptools
from pathlib import Path

# Read the long description from README if it exists
long_description = ""
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()

# Read requirements from requirements.txt
requirements = []
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        requirements = [
            line.strip()
            for line in fh.readlines()
            if line.strip() and not line.startswith("#")
        ]

setuptools.setup(
    name="sagemaker-model-monitoring-cdk",
    version="1.0.0",
    
    description="AWS CDK application for SageMaker Model Monitoring and Drift Detection",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Generator",
    author_email="cdk-generator@example.com",
    
    url="https://github.com/aws-samples/sagemaker-model-monitoring-cdk",
    
    packages=setuptools.find_packages(),
    
    install_requires=requirements,
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "sagemaker",
        "machine-learning",
        "model-monitoring",
        "drift-detection",
        "mlops",
        "infrastructure-as-code",
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/sagemaker-model-monitoring-cdk/issues",
        "Source": "https://github.com/aws-samples/sagemaker-model-monitoring-cdk",
        "Documentation": "https://docs.aws.amazon.com/sagemaker/latest/dg/model-monitor.html",
    },
    
    entry_points={
        "console_scripts": [
            "deploy-model-monitoring=app:main",
        ],
    },
    
    include_package_data=True,
    
    zip_safe=False,
    
    # Optional: Specify additional metadata
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=22.0.0",
            "flake8>=4.0.0",
            "mypy>=0.950",
        ],
        "test": [
            "pytest>=7.0.0",
            "moto>=4.0.0",
            "boto3-stubs[essential]>=1.34.0",
        ],
    },
)