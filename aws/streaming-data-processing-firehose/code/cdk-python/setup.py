"""
Setup configuration for Real-Time Data Processing CDK Python Application

This setup.py file configures the Python package for the CDK application
that deploys a real-time data processing pipeline using Kinesis Data Firehose.
"""

from setuptools import setup, find_packages

# Read the contents of README file if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CDK Python application for real-time data processing with Kinesis Data Firehose"

# Read requirements from requirements.txt
def load_requirements():
    """Load requirements from requirements.txt file"""
    with open("requirements.txt", "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip() and not line.startswith("#")]

setup(
    name="realtime-data-processing-cdk",
    version="1.0.0",
    description="CDK Python application for real-time data processing with Kinesis Data Firehose",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Generator",
    author_email="developer@example.com",
    url="https://github.com/example/realtime-data-processing-cdk",
    packages=find_packages(),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Package dependencies
    install_requires=load_requirements(),
    
    # Optional development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "isort>=5.0.0",
            "mypy>=1.0.0",
            "boto3-stubs[essential]>=1.34.0",
        ],
        "powertools": [
            "aws-lambda-powertools>=2.0.0",
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    
    # Keywords for package discovery
    keywords="aws cdk kinesis firehose lambda s3 opensearch streaming data-processing",
    
    # Entry points for console scripts (if needed)
    entry_points={
        "console_scripts": [
            # Add any console scripts here if needed
            # "command-name=module:function",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/example/realtime-data-processing-cdk/issues",
        "Source": "https://github.com/example/realtime-data-processing-cdk",
        "Documentation": "https://github.com/example/realtime-data-processing-cdk/blob/main/README.md",
    },
    
    # License
    license="MIT",
    
    # Zip safe
    zip_safe=False,
)