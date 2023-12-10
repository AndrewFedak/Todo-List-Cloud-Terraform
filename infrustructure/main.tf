locals {
  region = "eu-north-1"
}

provider "aws" {
  region = local.region
}

# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.2.0"

  name = "Terraform VPC"
  cidr = "10.0.0.0/16"

  azs             = ["${local.region}a", "${local.region}b", "${local.region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  create_igw = true
}

# S3
module "s3_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket                  = "todo-list-terraform"
  attach_public_policy    = false
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false

  attach_policy = true
  policy        = data.aws_iam_policy_document.allow_read_write.json

  versioning = {
    enabled = false
  }
}

data "aws_iam_policy_document" "allow_read_write" {
  statement {

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = [
      module.s3_bucket.s3_bucket_arn,
      "${module.s3_bucket.s3_bucket_arn}/*",
    ]
  }
}

# Application Load Balancer (ALB)
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "9.2.0"

  name               = "MainALB"
  internal           = true
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets
  load_balancer_type = "application"

  # Security Group
  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      description = "HTTP web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
    api_gateway_vpc_link = {
      from_port                    = 80
      to_port                      = 80
      ip_protocol                  = "tcp"
      description                  = "HTTP web traffic"
      referenced_security_group_id = module.api_gateway_security_group.security_group_id
    }
  }

  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "10.0.0.0/16"
    }
  }

  access_logs = {
    enabled = false
    bucket  = module.s3_bucket.s3_bucket_arn
    prefix  = "main-lb-access-logs"
  }

  listeners = {
    main = {
      port     = 80
      protocol = "HTTP"
      forward = {
        target_group_key = "main"
      }
    }
  }

  target_groups = {
    main = {
      name              = "MainTargetGroup"
      create_attachment = false
      protocol          = "HTTP"
      port              = 80
      health_check = {
        path                = "/health"
        protocol            = "HTTP"
        port                = 80
        healthy_threshold   = 3
        unhealthy_threshold = 3
        timeout             = 5
        interval            = 10
      }
    }
  }

  tags = {
    Environment = "Development"
    Project     = "Example"
  }
}
# resource "aws_lb" "main" {
#   depends_on = [
#     aws_s3_bucket_policy.allow_lb_logs
#   ]
# }


# Security Groups
resource "aws_security_group" "web_sg" {
  name        = "${local.tag_prefix}_Web_SG"
  description = "Allow Load Balancer inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [module.alb.security_group_id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${local.tag_prefix}_Web_SG"
  }
}

resource "aws_security_group" "data_sg" {
  name        = "${local.tag_prefix}_Data_SG"
  description = "Allow Web Instances inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  tags = {
    Name = "${local.tag_prefix}_Data_SG"
  }
}

# Launch template
resource "aws_launch_template" "main" {
  name            = "${local.tag_prefix}_Web_Server_Template"
  default_version = 1
  image_id        = "ami-0989fb15ce71ba39e" # Replace with your desired AMI ID
  instance_type   = "t3.micro"

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  key_name = "EC2 Tutorial"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_s3_rds_instance_profile.name
  }
  user_data = filebase64("${path.module}/instance-user-data.sh")

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.tag_prefix}_Web_Server_Template"
    }
  }
}

## IAM role for EC2 instance (RDS and S3 access)
resource "aws_iam_role" "ec2_s3_rds_role" {
  name = "ec2_role"
  ### Trust relationship policy
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

## EC2 Instance Profile
resource "aws_iam_instance_profile" "ec2_s3_rds_instance_profile" {
  name = "ec2_instance_profile"
  role = aws_iam_role.ec2_s3_rds_role.name
}
## Iam role policy attachement
resource "aws_iam_role_policy_attachment" "rds_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
  role       = aws_iam_role.ec2_s3_rds_role.name
}
resource "aws_iam_role_policy_attachment" "s3_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.ec2_s3_rds_role.name
}
##

# Auto Scaling Group
module "asg" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "7.3.1"

  # Autoscaling group
  name                      = "${local.tag_prefix}_Auto_Scaling_Group"
  min_size                  = 0
  max_size                  = 4
  desired_capacity          = 0
  health_check_type         = "EC2"
  health_check_grace_period = 300
  force_delete              = true
  vpc_zone_identifier = module.vpc.public_subnets

  # Launch template
  create_launch_template = false
  launch_template_id = aws_launch_template.main.id

  target_group_arns = [for k, v in module.alb.target_groups : v.arn]
}

# RDS
module "db" {
  source     = "terraform-aws-modules/rds/aws"
  version = "6.3.0"

  identifier = "myrdsinstance"

  allocated_storage = 20
  storage_type      = "gp2"

  db_name = "postgres"

  engine         = "postgres"
  engine_version = "15.3"
  instance_class = "db.t3.micro"

  username = "dbuser"
  password = "dbpassword"

  publicly_accessible = false
  skip_final_snapshot = true

  vpc_security_group_ids = [aws_security_group.data_sg.id]

  # DB subnet group
  create_db_subnet_group = true
  subnet_ids             = module.vpc.private_subnets

  # DB parameter group
  family = "postgres15.3"

  tags = {
    Name = "MyRDSInstance"
  }
}

# API Gateway
## Stages
resource "aws_apigatewayv2_stage" "dev" {
  api_id      = module.api_gateway.apigatewayv2_api_id
  name        = "dev"
  auto_deploy = true
}

resource "aws_apigatewayv2_stage" "test" {
  api_id      = module.api_gateway.apigatewayv2_api_id
  name        = "test"
  auto_deploy = true
}

module "api_gateway" {
  source  = "terraform-aws-modules/apigateway-v2/aws"
  version = "2.2.2"

  name          = "dev-http"
  description   = "My awesome HTTP API Gateway"
  protocol_type = "HTTP"

  cors_configuration = {
    allow_headers = ["content-type", "x-amz-date", "authorization", "x-api-key", "x-amz-security-token", "x-amz-user-agent"]
    allow_methods = ["*"]
    allow_origins = ["*"]
  }

  # Custom domain
  create_api_domain_name = false
  ## domain_name                 = "terraform-aws-modules.modules.tf"
  ## domain_name_certificate_arn = "arn:aws:acm:eu-west-1:052235179155:certificate/2b3a7ed9-05e1-4f9e-952b-27744ba06da6"

  # Access logs
  # default_stage_access_log_destination_arn = "arn:aws:logs:eu-west-1:835367859851:log-group:debug-apigateway"
  # default_stage_access_log_format          = "$context.identity.sourceIp - - [$context.requestTime] \"$context.httpMethod $context.routeKey $context.protocol\" $context.status $context.responseLength $context.requestId $context.integrationErrorMessage"

  # Routes and integrations
  integrations = {
    "ANY /api/{proxy+}" = {
      vpc_link           = "api_vpc_alb"
      connection_type    = "VPC_LINK"
      integration_uri    = module.alb.listeners["main"].arn
      integration_type   = "HTTP_PROXY"
      integration_method = "ANY"
      request_parameters = jsonencode({
        "overwrite:path" = "$request.path"
      })
    }

    "$default" = {
      lambda_arn = module.lambda_function.lambda_function_arn
    }
  }

  vpc_links = {
    api_vpc_alb = {
      name               = "example"
      security_group_ids = [module.api_gateway_security_group.security_group_id]
      subnet_ids         = module.vpc.public_subnets
    }
  }

  tags = {
    Name = "http-apigateway"
  }
}


module "api_gateway_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = "api-gateway-sg"
  description = "API Gateway group for example usage"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["http-80-tcp"]

  egress_rules = ["all-all"]
}

# Lambda (name=FrontEnd)
module "lambda_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "6.5.0"

  function_name = "my-lambda1"
  description   = "My awesome lambda function"
  handler       = "hello.handler"
  runtime       = "nodejs14.x"

  store_on_s3 = true
  s3_bucket   = module.s3_bucket.s3_bucket_id
  s3_prefix   = "/front-end"
  source_path = "../todo-list-front/src"

  ## IAM role
  role_name = "lambda_execution_role"
  policy    = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  ### Trust relationship policy
  trusted_entities = ["lambda.amazonaws.com"]

  ## Resource-based policy
  allowed_triggers = {
    APIGatewayAny = {
      statement_id = "AllowExecutionFromAPIGateway"
      service      = "apigateway"
      source_arn   = "${module.api_gateway.apigatewayv2_api_execution_arn}/*/*"
    }
  }

  tags = {
    Name = "my-lambda1"
  }
}

# TODO: Route53, Cloudfront?