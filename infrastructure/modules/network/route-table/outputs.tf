output "route_table_ids" {
  description = "IDs das route tables"
  value       = aws_route_table.this[*].id
}
