variable "aws_region" {
  description = "Region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "admin_ip_cidr" {
  description = "Administrator's IP in CIDR notation, e.g. 203.0.113.4/32. Never 0.0.0.0/0."
  type        = string
}

variable "bucket_name" {
  description = "Globally unique prefix for the platform's S3 buckets"
  type        = string
  default     = "securestudy-rahul-2026"
}

variable "alert_email" {
  description = "Email that receives SNS alarm notifications and budget alerts"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the HTTPS listener (TLS terminates at the load balancer)"
  type        = string
}

variable "app_instance_type" {
  description = "Instance type of the application tier"
  type        = string
  default     = "t3.micro"
}

variable "availability_zones" {
  description = "Two Availability Zones to spread each tier across (pinned, not looked up)"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Exactly two Availability Zones are expected."
  }
}
