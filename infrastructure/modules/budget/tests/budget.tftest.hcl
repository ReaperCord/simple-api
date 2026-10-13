mock_provider "aws" {}

variables {
  name                       = "test-budget"
  subscriber_email_addresses = ["alerta@example.invalid"]
}

run "creditos_excluidos_e_limite_45_usd" {
  command = plan

  assert {
    condition     = aws_budgets_budget.this.cost_types[0].include_credit == false
    error_message = "cost_types.include_credit deve ser false (com creditos o custo liquido zera e nenhum alerta dispara)."
  }

  assert {
    condition     = aws_budgets_budget.this.limit_amount == "45" && aws_budgets_budget.this.limit_unit == "USD"
    error_message = "O limite default deve ser 45 USD."
  }

  assert {
    condition     = aws_budgets_budget.this.budget_type == "COST" && aws_budgets_budget.this.time_unit == "MONTHLY"
    error_message = "O budget deve ser COST mensal."
  }
}

run "notificacoes_reais_5_usd_e_50_80_100_por_cento" {
  command = plan

  assert {
    condition     = length(aws_budgets_budget.this.notification) == 4
    error_message = "Devem existir 4 notificacoes."
  }

  assert {
    condition = toset([
      for n in aws_budgets_budget.this.notification : "${n.notification_type}/${n.threshold_type}/${n.threshold}"
      ]) == toset([
      "ACTUAL/ABSOLUTE_VALUE/5",
      "ACTUAL/PERCENTAGE/50",
      "ACTUAL/PERCENTAGE/80",
      "ACTUAL/PERCENTAGE/100",
    ])
    error_message = "As notificacoes devem ser de gasto REAL: ABSOLUTE_VALUE 5 e PERCENTAGE 50/80/100."
  }
}

run "sem_email_falha" {
  command = plan

  variables {
    subscriber_email_addresses = []
  }

  expect_failures = [var.subscriber_email_addresses]
}
