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

variable "shape" {
  description = "VM shape. VM.Standard.A1.Flex (Arm) and VM.Standard.E2.1.Micro (AMD, 1 core, 1 GB) are Always Free."
  type        = string
  # shortcut: E2.1.Micro because Johannesburg had no A1 capacity on 2026-11-21; switch to A1 when it frees up.
  default = "VM.Standard.E2.1.Micro"
}

variable "ocpus" {
  description = "Cores, for flexible shapes only (Always Free allows a fixed A1 total)."
  type        = number
  default     = 2
}

variable "memory_gbs" {
  description = "Memory in GB, for flexible shapes only."
  type        = number
  default     = 12
}

variable "repository" {
  description = "Public repository the VM clones on first boot."
  type        = string
  default     = "https://github.com/FionaMich/northgate-dental.git"
}
