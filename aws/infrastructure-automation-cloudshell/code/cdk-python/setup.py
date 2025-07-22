"""
Setup configuration for Infrastructure Automation CDK application
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="infrastructure-automation-cdk",
    version="1.0.0",
    author="AWS CDK",
    author_email="aws-cdk@example.com",
    description="CDK application for Infrastructure Automation with CloudShell PowerShell",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Bug Tracker": "https://github.com/aws/aws-cdk/issues",
    },
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
    packages=setuptools.find_packages(),
    install_requires=[
        "aws-cdk-lib>=2.171.1,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=6.2.0",
            "black>=21.0.0",
            "flake8>=3.9.0",
            "mypy>=0.910",
            "cdk-nag>=2.0.0",
        ],
        "lambda": [
            "aws-lambda-powertools>=2.0.0",
        ]
    },
    python_requires=">=3.8",
    entry_points={
        "console_scripts": [
            "infrastructure-automation=app:main",
        ],
    },
)