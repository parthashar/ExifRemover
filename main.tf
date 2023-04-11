terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    klayers = {
      version = "~> 1.0.0"
      source  = "ldcorentin/klayer"
    }
  }
}

provider "aws" {
    region = "eu-west-1"
}

data "klayers_package_latest_version" "pillow" {
    name   = "pillow"
    region = "eu-west-1"
}

data "archive_file" "lambda_src_zip" {
    type  = "zip"
    source_dir = "src"
    output_path = "imageprocesser_lambda.zip"
}

resource "aws_s3_bucket" "bucket_a" {
    bucket    = "bucket-a"
    force_destroy = true
}

resource "aws_s3_bucket" "bucket_b" {
    bucket    = "bucket-b"
    force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "block_public_access_to_A" {
  bucket = aws_s3_bucket.bucket_a.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "block_public_access_to_B" {
  bucket = aws_s3_bucket.bucket_b.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_lambda_function" "exif_remover" {
    function_name   = "exif_remover"
    role            = aws_iam_role.lamdba_iam_role.arn
    handler         = "exif_remover.lambda_handler"
    runtime         = "python3.9"
    description     = "Removes Exif Metadata"
    filename        = "imageprocesser_lambda.zip"
    timeout         = 60
    memory_size         = 512
    source_code_hash = data.archive_file.lambda_src_zip.output_base64sha256

    layers = [
        data.klayers_package_latest_version.pillow.arn
    ]
}

resource "aws_lambda_permission" "allow_bucket_execute_lambda" {
    statement_id  = "AllowExecutionFromS3Bucket"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.exif_remover.arn
    principal     = "s3.amazonaws.com"
    source_arn    = aws_s3_bucket.bucket_a.arn
}


resource "aws_s3_bucket_notification" "bucket_notification" {
    bucket = aws_s3_bucket.bucket_a.id
    lambda_function {
    lambda_function_arn = aws_lambda_function.exif_remover.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".jpg"
    }
    depends_on = [aws_lambda_permission.allow_bucket_execute_lambda]
}

resource "aws_iam_role" "lamdba_iam_role" {
    name = "lambda-iam-role"
    assume_role_policy =  <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
} 

resource "aws_iam_policy" "s3_policy" {
    name = "s3-policy"
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": ["arn:aws:s3:::bucket-a/*"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject"
      ],
      "Resource": ["arn:aws:s3:::bucket-b/*"]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "s3_policy_attachment" {
    role = aws_iam_role.lamdba_iam_role.name
    policy_arn = aws_iam_policy.s3_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_exceution_policy" {
    role       = aws_iam_role.lamdba_iam_role.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

/* task 2:
To extend this further, we have two users User A and User B. Create IAM users with the following access:
• User A can Read/Write to Bucket A
• User B can Read from Bucket B
*/

resource "aws_iam_user" "A" {
    name = "user_A"
}

resource "aws_iam_user_policy" "bucket_A_rw_for_user_A" {
    name = "rw_bucket_a"
    user = aws_iam_user.A.name
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject"
      ],
      "Resource": ["arn:aws:s3:::bucket-a/*"]
    }
  ]
}
EOF
}

resource "aws_iam_user" "B" {
    name = "user_B"
}

resource "aws_iam_user_policy" "bucket_B_r_for_user_B" {
    name = "r_bucket_B"
    user = aws_iam_user.B.name
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": ["arn:aws:s3:::bucket-b/*"]
    }
  ]
}
EOF
}