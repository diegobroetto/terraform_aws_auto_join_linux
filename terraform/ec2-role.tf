resource "aws_iam_role" "ec2_ssm_role" {
  name = "ec2-ssm-domain-join-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "ssm_parameter_access" {
  name        = "EC2SSMParameterAccessPolicy"
  description = "Allows EC2 to read parameters from the SSM Parameter Store and decrypt using KMS"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid: "AllowSSMParameterRead",
        Effect: "Allow",
        Action: [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ],
        Resource: "*"
      },
      {
        Sid: "AllowKMSDecrypt",
        Effect: "Allow",
        Action: [
          "kms:Decrypt"
        ],
        Resource: "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_parameter_access" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = aws_iam_policy.ssm_parameter_access.arn
}