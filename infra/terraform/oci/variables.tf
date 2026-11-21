variable "region" {
  description = "Oracle home region, fixed at sign-up (ADR 0004)."
  type        = string
  default     = "af-johannesburg-1"
}

variable "tenancy_ocid" {
  description = "Tenancy OCID, from ~/.oci/config."
  type        = string
}

variable "admin_cidr" {
  description = "The only address allowed to open Bastion sessions, such as Fiona's home IP with /32."
  type        = string
}

variable "ssh_public_key_path" {
  description = "Public key installed for the admin user and used for Bastion sessions."
  type        = string
  default     = "~/.ssh/northgate_oracle.pub"
}

variable "ocpus" {
  description = "Ampere A1 cores (Always Free allows a fixed total across all A1 VMs)."
  type        = number
  default     = 2
}

variable "memory_gbs" {
  description = "Ampere A1 memory in GB."
  type        = number
  default     = 12
}

variable "repository" {
  description = "Public repository the VM clones on first boot."
  type        = string
  default     = "https://github.com/FionaMich/northgate-dental.git"
}
