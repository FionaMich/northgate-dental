output "public_ip" {
  description = "The load balancer's address; DNS name: <ip with dashes>.sslip.io"
  value       = [for ip in oci_network_load_balancer_network_load_balancer.nlb.ip_addresses : ip.ip_address if ip.is_public][0]
}

output "vm_private_ip" {
  value = oci_core_instance.vm.private_ip
}

output "bastion_id" {
  value = oci_bastion_bastion.admin.id
}

output "vm_id" {
  value = oci_core_instance.vm.id
}
