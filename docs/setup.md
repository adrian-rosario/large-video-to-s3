# Setup — AWS test resources

You bring your own AWS account; this provisions a safe, throwaway place to test against.

## 1. Prerequisites

- An AWS account you control (**not** a production account).
- The AWS CLI installed and configured (`aws configure`, or an SSO profile).

## 2. Provision the bucket + policy (one command)

```sh
aws cloudformation deploy \
  --template-file infra/test-bucket.yaml \
  --stack-name lvs3-test \
  --parameter-overrides BucketName=<your-globally-unique-name> \
  --capabilities CAPABILITY_IAM
```

This creates a private, encrypted S3 bucket with a lifecycle rule that **auto-aborts incomplete
multipart uploads after 1 day** (so interrupted-transfer testing never quietly costs you storage),
plus a least-privilege managed IAM policy.

See the outputs (bucket name, region, policy ARN):

```sh
aws cloudformation describe-stacks --stack-name lvs3-test \
  --query "Stacks[0].Outputs" --output table
```

## 3. Grant access

The template creates a **managed policy** but no long-lived keys. Attach that policy
(`ManagedPolicyArn` from the outputs) to the IAM user or role you'll run the app under — or, for
quick local testing, just use a profile that already has access to the bucket.

## 4. Point the app at it

```sh
cp config.example.json config.local.json
# edit config.local.json: set "region" and "bucket" to the stack outputs
```

`config.local.json` is gitignored, so your bucket name never lands in the repo.

## 5. Tear it down

```sh
# empty the bucket first (CloudFormation won't delete a non-empty bucket)
aws s3 rm s3://<your-bucket-name> --recursive
aws cloudformation delete-stack --stack-name lvs3-test
```
