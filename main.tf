terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.region
}

#####################
# VPC + Networking
#####################
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "3tier-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "3tier-igw" }
}

# Public subnets
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true
  tags                    = { Name = "public-subnet-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = true
  tags                    = { Name = "public-subnet-b" }
}

# Private subnets for DB
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.region}a"
  tags              = { Name = "private-subnet-a" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "${var.region}b"
  tags              = { Name = "private-subnet-b" }
}

# Route table for public subnets
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "public-rt" }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_rt.id
}

#####################
# Security Groups
#####################
resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.main.id
  name   = "alb-sg"

  ingress {
    description = "Allow HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "alb-sg" }
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id
  name   = "web-sg"

  ingress {
    description     = "Allow HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    description = "Allow SSH (for debugging)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "web-sg" }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.main.id
  name   = "db-sg"

  ingress {
    description     = "Allow MySQL from Web Tier"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "db-sg" }
}

#####################
# Load Balancer
#####################
resource "aws_lb" "alb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

resource "aws_lb_target_group" "tg" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

#####################
# EC2 + Auto Scaling
#####################
resource "aws_launch_template" "web_template" {
  name_prefix            = "web-template-"
  image_id               = var.ami_id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    exec > >(tee /var/log/user-data.log) 2>&1
    set -x

    # Install Apache (Amazon Linux 2023 uses dnf)
    dnf update -y
    dnf install -y httpd

    # Enable and start Apache
    systemctl enable httpd
    systemctl start httpd

    # Get metadata
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

    # Create web page
    cat <<EOF2 > /var/www/html/index.html
    <html>
    <head><title>3-Tier Architecture</title></head>
    <body style="font-family: Arial; background: #f2f2f2; text-align: center;">
    <h1>🚀 3-Tier Architecture - Web Tier</h1>
    <h2>Hello from Instance: $INSTANCE_ID</h2>
    <p><strong>Availability Zone:</strong> $AZ</p>
    <p><strong>Region:</strong> ${var.region}</p>
    <hr>
    <p>✅ Apache running successfully on Amazon Linux 2023!</p>
    </body>
    </html>
    EOF2

    systemctl restart httpd
    echo "User data completed successfully on $(date)" >> /var/log/user-data.log
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "web-asg-instance"
    }
  }
}

resource "aws_autoscaling_group" "web_asg" {
  name_prefix               = "web-asg-"
  vpc_zone_identifier       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  desired_capacity          = 2
  max_size                  = 3
  min_size                  = 1
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.web_template.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.tg.arn]

  tag {
    key                 = "Name"
    value               = "web-asg-instance"
    propagate_at_launch = true
  }

  depends_on = [aws_lb_target_group.tg]
}

#####################
# RDS Database (Multi-AZ)
#####################
resource "aws_db_subnet_group" "db_subnets" {
  name       = "db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  tags       = { Name = "db-subnet-group" }
}

resource "aws_db_instance" "db" {
  identifier              = "notes-db"
  engine                  = "mysql"
  instance_class          = "db.t3.micro"
  username                = var.db_user
  password                = var.db_pass
  allocated_storage       = 20
  multi_az                = true
  db_subnet_group_name    = aws_db_subnet_group.db_subnets.name
  vpc_security_group_ids  = [aws_security_group.db_sg.id]
  skip_final_snapshot     = true
  publicly_accessible     = false
  storage_type            = "gp2"
  backup_retention_period = 1
}

#####################
# Outputs
#####################
output "alb_dns_name" {
  description = "Application Load Balancer URL"
  value       = aws_lb.alb.dns_name
}

output "rds_endpoint" {
  description = "RDS Database Endpoint"
  value       = aws_db_instance.db.endpoint
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}
