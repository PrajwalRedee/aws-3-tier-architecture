variable "region" {
  default = "ap-south-1"
}

variable "ami_id" {
  description = "Amazon Linux 2023 AMI for ap-south-1 (Mumbai)"
  default     = "ami-0fd05997b4dff7aac"
}

variable "db_user" {
  description = "Database username"
  default     = "admin"
}

variable "db_pass" {
  description = "Database password"
  default     = "Password123!"
}
