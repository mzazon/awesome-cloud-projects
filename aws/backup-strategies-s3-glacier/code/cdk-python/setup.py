import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="backup-strategies-s3-glacier",
    version="1.0.0",
    author="AWS CDK Generator",
    author_email="example@example.com",
    description="AWS CDK Python application for backup strategies with S3 and Glacier",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3 :: Only",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    packages=setuptools.find_packages(),
    install_requires=[
        "aws-cdk-lib==2.177.0",
        "constructs>=10.0.0,<11.0.0",
    ],
    python_requires=">=3.8",
)