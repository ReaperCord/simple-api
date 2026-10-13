variable "name" {
  description = "Nome do budget"
  type        = string
}

variable "limit_amount" {
  description = "Limite mensal em USD (string, como exige o provider); 45 e a meta de 02-finops-guardrails.md"
  type        = string
  default     = "45"
}

variable "subscriber_email_addresses" {
  description = "E-mails que recebem os alertas; sem default para nao versionar PII"
  type        = list(string)
  sensitive   = true

  validation {
    condition     = length(var.subscriber_email_addresses) >= 1
    error_message = "Informe pelo menos um e-mail."
  }
}

variable "tags" {
  description = "Tags aplicadas ao budget"
  type        = map(string)
  default     = {}
}
