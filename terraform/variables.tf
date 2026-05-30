variable "subscription_id" {
  description = "Azure Subscription ID to deploy resources into"
  type        = string
}

variable "project" {
  description = "Short project identifier used in resource names (lowercase, no hyphens)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.project))
    error_message = "project must be lowercase alphanumeric only (no hyphens — required for storage account naming)."
  }
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region for all resources (e.g. eastus)"
  type        = string
  default     = "eastus"
}

variable "location_short" {
  description = "Short region code used in resource names (e.g. eus for eastus)"
  type        = string
  default     = "eus"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}