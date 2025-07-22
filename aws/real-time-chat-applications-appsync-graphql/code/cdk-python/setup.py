"""
Setup configuration for Real-Time Chat Application CDK Python project.

This setup.py file defines the package configuration for the CDK application,
including dependencies, metadata, and entry points.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt") as f:
    requirements = [line.strip() for line in f if line.strip() and not line.startswith("#")]

setup(
    name="realtime-chat-cdk",
    version="1.0.0",
    description="AWS CDK Python application for real-time chat with AppSync and GraphQL",
    long_description="""
    A complete AWS CDK Python application that deploys a real-time chat solution using:
    - AWS AppSync for GraphQL API and real-time subscriptions
    - Amazon DynamoDB for scalable message and conversation storage
    - Amazon Cognito for secure user authentication
    - IAM roles and policies for secure access control
    
    This infrastructure supports features like:
    - Real-time message delivery via WebSocket subscriptions
    - User presence tracking and status updates
    - Conversation management and participant control
    - Secure authentication and authorization
    - Automatic scaling based on demand
    """,
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Recipe Generator",
    author_email="recipes@aws.example.com",
    
    # Project URLs
    url="https://github.com/aws-samples/realtime-chat-appsync",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/appsync/",
        "Source": "https://github.com/aws-samples/realtime-chat-appsync",
        "Tracker": "https://github.com/aws-samples/realtime-chat-appsync/issues",
    },
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    
    # Dependencies
    install_requires=requirements,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Package classifiers
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP :: WSGI :: Application",
        "Topic :: Communications :: Chat",
        "Framework :: AWS CDK",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "appsync", 
        "graphql",
        "realtime",
        "chat",
        "websocket",
        "dynamodb",
        "cognito",
        "serverless"
    ],
    
    # Entry points for CLI tools (if any)
    entry_points={
        "console_scripts": [
            "deploy-chat=app:main",
        ],
    },
    
    # Additional package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Development dependencies (optional)
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "mypy>=1.7.0",
            "flake8>=6.0.0",
            "isort>=5.12.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",  # For AWS service mocking
        ],
    },
    
    # Zip safety
    zip_safe=False,
)