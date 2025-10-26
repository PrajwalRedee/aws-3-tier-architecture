variable "region" {
  description = "AWS region for deployment"
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Name of the project for tagging and identification"
  type        = string
  default     = "aws-3tier-architecture"
}

variable "ami_id" {
  description = "Amazon Linux 2023 AMI for ap-south-1"
  default     = "ami-0fd05997b4dff7aac"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t3.micro"
}

variable "key_pair_name" {
  description = "AWS Key Pair name for SSH access"
  type        = string
}

variable "db_user" {
  description = "Database username"
  default     = "admin"
}

variable "db_pass" {
  description = "Database password"
  default     = "Password123!"
}

variable "multi_az" {
  description = "Enable Multi-AZ for RDS"
  default     = true
}
