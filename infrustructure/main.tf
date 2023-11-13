terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-north-1"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.tag_prefix}_MainVPC"
  }
}

# Public subnet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.tag_prefix}_InternetGateway"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }

  route {
    cidr_block = "0.0.0.0/16"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.tag_prefix}_Web_Route_Table"
  }
}

resource "aws_subnet" "public" {
  count = 3

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 3}.0/24"
  availability_zone       = element(["eu-north-1a", "eu-north-1b", "eu-north-1c"], count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.tag_prefix}_Web_${element(["a", "b", "c"], count.index)}"
  }
}

resource "aws_route_table_association" "web" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Subnets
resource "aws_subnet" "private" {
  count = 3

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = element(["eu-north-1a", "eu-north-1b", "eu-north-1c"], count.index)
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.tag_prefix}_Data_${element(["a", "b", "c"], count.index)}"
  }
}


# Security Groups
resource "aws_security_group" "web_lb_sg" {
  name        = "${local.tag_prefix}_Web_LB_SG"
  description = "Allow Internet inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.tag_prefix}_Web_LB_SG"
  }
}

resource "aws_security_group" "web_sg" {
  name        = "${local.tag_prefix}_Web_SG"
  description = "Allow Load Balancer inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.web_lb_sg.id]
  }

  tags = {
    Name = "${local.tag_prefix}_Web_SG"
  }
}

resource "aws_security_group" "data_sg" {
  name        = "${local.tag_prefix}_Data_SG"
  description = "Allow Web Instances inbound traffic"
  vpc_id      = aws_vpc.main.id

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

# Application Load Balancer (ALB)
resource "aws_lb" "main" {
  name               = "MainALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_lb_sg.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false
}

# Target Group
resource "aws_lb_target_group" "main" {
  name     = "MainTargetGroup"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  health_check {
    path                = "/health"
    protocol            = "HTTP"
    port                = 80
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 10
  }
}

# Listeners and rules (Application Load Balancer (ALB) -> Target Group)
resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# resource "aws_key_pair" "deployer" {
#   key_name   = "deployer-key"
#   public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD3F6tyPEFEzV0LX3X8BsXdMsQz1x2cEikKDEY0aIj41qgxMCP/iteneqXSIFZBp5vizPvaoIR3Um9xK7PGoW8giupGn+EPuxIA4cDM4vzOqOkiMPhz5XK0whEjkVzTo4+S0puvDZuwIsdiW9mxhJc7tgBNL0cYlWSYVkz4G/fslNfRPW5mYAM49f4fhtxPb5ok4Q2Lg9dPKVHO/Bgeu5woMc7RY0p1ej6D4CKFE6lymSDJpW0YHX/wqE9+cfEauh7xZcG0q9t2ta6F6fmX0agvpFyZo8aFbXeUBr7osSCJNgvavWbM/06niWrOvYX2xwWdhXmXSrbX8ZbabVohBK41 email@example.com"
# }

# Launch Template
resource "aws_launch_template" "main" {
  name            = "${local.tag_prefix}_Web_Server_Template"
  default_version = 1
  image_id        = "ami-0989fb15ce71ba39e" # Replace with your desired AMI ID
  instance_type   = "t3.micro"

  vpc_security_group_ids = [aws_security_group.web_sg.id]
  # key_name = ""

  user_data = filebase64("${path.module}/instance-user-data.sh")
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.tag_prefix}_Web_Server_Template"
    }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "main" {
  name                      = "${local.tag_prefix}_Auto_Scaling_Group"
  desired_capacity          = 0
  min_size                  = 0
  max_size                  = 4
  health_check_type         = "EC2"
  health_check_grace_period = 300
  force_delete              = true
  vpc_zone_identifier       = aws_subnet.public[*].id

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.main.arn]
  depends_on        = [aws_lb.main]
}


# TODO: RDS, S3, APIGW, Lambda, Cloudfront?