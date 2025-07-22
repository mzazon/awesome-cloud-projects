"""
Setup configuration for CodeCommit Git Workflows CDK Python application.

This setup.py file defines the package configuration for the CDK application,
including dependencies, metadata, and development requirements.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="codecommit-git-workflows",
    version="1.0.0",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="CDK Python application for CodeCommit Git workflows with automation",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/example/codecommit-git-workflows",
    project_urls={
        "Bug Tracker": "https://github.com/example/codecommit-git-workflows/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source Code": "https://github.com/example/codecommit-git-workflows",
    },
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
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    packages=setuptools.find_packages(),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=22.0.0",
            "pylint>=2.15.0",
            "mypy>=0.991",
            "boto3-stubs[codecommit,lambda,sns,events,cloudwatch]",
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "cdk-deploy=app:main",
        ],
    },
    include_package_data=True,
    package_data={
        "codecommit_git_workflows": [
            "lambda/**/*.py",
            "assets/**/*",
        ],
    },
    zip_safe=False,
)