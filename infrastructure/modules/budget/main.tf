locals {
  # Somente gasto REAL (ACTUAL): alerta de previsao exige ~5 semanas de historico (02-finops-guardrails.md).
  notifications = [
    { threshold = 5, threshold_type = "ABSOLUTE_VALUE" },
    { threshold = 50, threshold_type = "PERCENTAGE" },
    { threshold = 80, threshold_type = "PERCENTAGE" },
    { threshold = 100, threshold_type = "PERCENTAGE" },
  ]
}

resource "aws_budgets_budget" "this" {
  name         = var.name
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = var.limit_amount
  limit_unit   = "USD"
  tags         = var.tags

  # O padrao do provider e include_credit = true: com creditos incluidos o custo liquido fica
  # zerado e nenhum alerta dispara.
  cost_types {
    include_credit = false
  }

  dynamic "notification" {
    for_each = local.notifications
    content {
      comparison_operator        = "GREATER_THAN"
      notification_type          = "ACTUAL"
      threshold                  = notification.value.threshold
      threshold_type             = notification.value.threshold_type
      subscriber_email_addresses = var.subscriber_email_addresses
    }
  }
}
