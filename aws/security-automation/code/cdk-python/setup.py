"""
Setup configuration for Event-Driven Security Automation CDK Application

This setup file configures the Python package for the CDK application that
implements event-driven security automation using EventBridge and Lambda.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="event-driven-security-automation",
    version="1.0.0",
    author="Security Team",
    author_email="security@example.com",
    description="Event-driven security automation with EventBridge and Lambda",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/example/event-driven-security-automation",
    project_urls={
        "Bug Tracker": "https://github.com/example/event-driven-security-automation/issues",
        "Documentation": "https://github.com/example/event-driven-security-automation/wiki",
        "Source Code": "https://github.com/example/event-driven-security-automation",
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Security",
        "Topic :: System :: Monitoring",
        "Topic :: System :: Systems Administration",
    ],
    package_dir={"": "src"},
    packages=setuptools.find_packages(where="src"),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.111.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.28.0",
        "botocore>=1.31.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=0.991",
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
        "monitoring": [
            "cloudwatch-logs-insights>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-security-automation=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "security",
        "automation",
        "eventbridge",
        "lambda",
        "security-hub",
        "incident-response",
        "compliance",
        "monitoring",
    ],
    include_package_data=True,
    zip_safe=False,
)