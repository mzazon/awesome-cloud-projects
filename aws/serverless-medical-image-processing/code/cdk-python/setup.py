"""
Setup configuration for Medical Image Processing CDK Application

This setup.py file configures the Python package for the serverless medical image
processing pipeline using AWS CDK. It defines metadata, dependencies, and
package configuration for proper installation and deployment.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
README_PATH = Path(__file__).parent / "README.md"
long_description = README_PATH.read_text(encoding="utf-8") if README_PATH.exists() else ""

# Read requirements from requirements.txt
REQUIREMENTS_PATH = Path(__file__).parent / "requirements.txt"
if REQUIREMENTS_PATH.exists():
    with open(REQUIREMENTS_PATH, "r", encoding="utf-8") as f:
        requirements = [
            line.strip() 
            for line in f 
            if line.strip() and not line.startswith("#")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0"
    ]

setuptools.setup(
    name="medical-image-processing-cdk",
    version="1.0.0",
    
    description="CDK application for serverless medical image processing with AWS HealthImaging and Step Functions",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions",
    author_email="aws-solutions@amazon.com",
    
    url="https://github.com/aws-samples/medical-image-processing-cdk",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    install_requires=requirements,
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Healthcare Industry",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Scientific/Engineering :: Medical Science Apps.",
        "Topic :: System :: Distributed Computing",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "medical-imaging",
        "dicom",
        "healthcare",
        "serverless",
        "step-functions",
        "lambda",
        "healthimaging",
        "hipaa"
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/healthimaging/",
        "Source": "https://github.com/aws-samples/medical-image-processing-cdk",
        "Tracker": "https://github.com/aws-samples/medical-image-processing-cdk/issues",
    },
    
    # CDK specific configuration
    zip_safe=False,
    include_package_data=True,
    
    # Entry points for CDK commands
    entry_points={
        "console_scripts": [
            "medical-imaging-cdk=app:main",
        ],
    },
    
    # Additional metadata for healthcare compliance
    license="MIT",
    platforms=["any"],
    
    # Package data to include
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Exclude development files from distribution
    exclude_package_data={
        "": ["tests/*", "*.pyc", "__pycache__/*"],
    },
)