#!/usr/bin/env python3
"""
Setup configuration for Conversational AI CDK Python application.

This setup.py file configures the Python package for the conversational AI
infrastructure deployment using AWS CDK. It defines package metadata,
dependencies, and entry points for the application.
"""

from setuptools import setup, find_packages
import os

# Read the contents of README file
this_directory = os.path.abspath(os.path.dirname(__file__))
readme_path = os.path.join(this_directory, "README.md")

# Handle case where README.md might not exist yet
try:
    with open(readme_path, encoding="utf-8") as f:
        long_description = f.read()
except FileNotFoundError:
    long_description = """
    # Conversational AI CDK Python Application
    
    This package contains AWS CDK Python code for deploying a conversational AI
    application using Amazon Bedrock and Claude models.
    """

# Read requirements from requirements.txt
requirements_path = os.path.join(this_directory, "requirements.txt")
with open(requirements_path, encoding="utf-8") as f:
    requirements = []
    for line in f:
        line = line.strip()
        # Skip comments and empty lines
        if line and not line.startswith("#"):
            # Remove inline comments and version ranges for setuptools compatibility
            requirement = line.split("#")[0].strip()
            if requirement:
                requirements.append(requirement)

setup(
    # Package metadata
    name="conversational-ai-cdk",
    version="1.0.0",
    description="AWS CDK Python application for conversational AI using Amazon Bedrock and Claude",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS Solutions",
    author_email="aws-solutions@amazon.com",
    
    # Project URLs
    url="https://github.com/aws-samples/conversational-ai-bedrock-claude",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/bedrock/",
        "Source": "https://github.com/aws-samples/conversational-ai-bedrock-claude",
        "Tracker": "https://github.com/aws-samples/conversational-ai-bedrock-claude/issues",
    },
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Optional dependencies for different use cases
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "security": [
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "conversational-ai-deploy=app:main",
        ],
    },
    
    # Package classifiers for PyPI
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
    ],
    
    # Keywords for discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "bedrock",
        "claude",
        "ai",
        "conversational-ai",
        "chatbot",
        "lambda",
        "api-gateway",
        "dynamodb",
    ],
    
    # License
    license="Apache-2.0",
    
    # Platforms
    platforms=["any"],
)


def main():
    """
    Entry point for direct script execution.
    
    This function can be used when running the setup.py directly
    for deployment or development purposes.
    """
    import sys
    
    if len(sys.argv) > 1 and sys.argv[1] == "deploy":
        # Import and run the CDK app
        try:
            from app import app
            app.synth()
            print("✅ CDK synthesis completed successfully")
        except ImportError as e:
            print(f"❌ Error importing CDK app: {e}")
            sys.exit(1)
        except Exception as e:
            print(f"❌ Error during CDK synthesis: {e}")
            sys.exit(1)
    else:
        # Run normal setuptools setup
        print("📦 Installing conversational AI CDK package...")
        print("💡 Use 'python setup.py deploy' to synthesize CDK templates")


if __name__ == "__main__":
    main()