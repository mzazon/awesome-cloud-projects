"""
Setup configuration for Real-Time Video Analytics CDK Application

This setup.py file configures the Python package for the CDK application,
defining dependencies, metadata, and installation requirements for the
video analytics infrastructure deployment.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
this_directory = Path(__file__).parent
try:
    long_description = (this_directory / "README.md").read_text()
except FileNotFoundError:
    long_description = "Real-Time Video Analytics with Amazon Rekognition and Kinesis CDK Application"

# Read requirements from requirements.txt
def read_requirements(filename: str) -> list:
    """Read requirements from requirements.txt file"""
    try:
        with open(filename, 'r') as f:
            return [
                line.strip() 
                for line in f 
                if line.strip() and not line.startswith('#')
            ]
    except FileNotFoundError:
        return []

# Package metadata
setuptools.setup(
    name="video-analytics-cdk",
    version="1.0.0",
    
    description="Real-Time Video Analytics Platform using AWS CDK",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions",
    author_email="aws-solutions@amazon.com",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    install_requires=read_requirements("requirements.txt"),
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: JavaScript",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    keywords=[
        "aws", 
        "cdk", 
        "video-analytics", 
        "rekognition", 
        "kinesis", 
        "computer-vision",
        "machine-learning",
        "real-time",
        "streaming"
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/",
        "Tracker": "https://github.com/aws-samples/",
    },
    
    # Entry points for CLI commands (optional)
    entry_points={
        "console_scripts": [
            "video-analytics-deploy=app:main",
        ],
    },
    
    # Additional package data
    package_data={
        "": ["*.json", "*.yaml", "*.yml", "*.md"],
    },
    
    # Include additional files in distribution
    include_package_data=True,
    
    # Development dependencies (extras)
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "aws-cdk.assertions>=2.100.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    # Zip safe configuration
    zip_safe=False,
)

# Additional setup configuration for CDK applications
if __name__ == "__main__":
    print("Setting up Real-Time Video Analytics CDK Application...")
    print("This package provides infrastructure as code for deploying a")
    print("comprehensive video analytics platform using AWS services.")
    print("")
    print("Key features:")
    print("- Real-time video stream processing with Amazon Rekognition")
    print("- Scalable event processing with AWS Lambda")
    print("- Metadata storage with Amazon DynamoDB")
    print("- Alert notifications with Amazon SNS")
    print("- Query APIs with Amazon API Gateway")
    print("- Comprehensive monitoring with Amazon CloudWatch")
    print("")
    print("To deploy this infrastructure:")
    print("1. Install dependencies: pip install -r requirements.txt")
    print("2. Configure AWS credentials")
    print("3. Deploy with CDK: cdk deploy")
    print("")
    print("For more information, see the CDK documentation:")
    print("https://docs.aws.amazon.com/cdk/")