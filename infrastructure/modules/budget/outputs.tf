output "budget_name" {
  description = "Nome do budget"
  value       = aws_budgets_budget.this.name
}

output "budget_arn" {
  description = "ARN do budget"
  value       = aws_budgets_budget.this.arn
}
