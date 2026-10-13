output "subnet_id" {
  description = "A map of the subnet IDs, keyed by the original for_each key."
  value       = { for k, v in aws_subnet.this : k => v.id }
}

output "subnet_ids_ordered" {
  description = "Lista dos IDs das subnets na mesma ordem de subnet_name."
  value       = [for n in var.subnet_name : aws_subnet.this[n].id]
}

output "subnet_cidr_block" {
  description = "A map of the subnet CIDR blocks, keyed by the original for_each key."
  value       = { for k, v in aws_subnet.this : k => v.cidr_block }
}

output "subnet_availability_zone" {
  description = "A map of the subnet availability zones, keyed by the original for_each key."
  value       = { for k, v in aws_subnet.this : k => v.availability_zone }
}
