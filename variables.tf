variable "cloud_id" {
  type        = string
  description = "The ID of the cloud"
}

variable "folder_id" {
  type        = string
  description = "The ID of the folder"
}

variable "servacc_id" {
  type        = string
  description = "The ID of the service account"
}

variable "my_ip" {
  type        = string
  description = "The public IP of the administrator"
}

variable "vm_preemptible" {
  description = "If true, all VMs will be preemptible (cheaper but can be shut down)"
  type        = bool
  default     = true # Set to true by default to save money
}