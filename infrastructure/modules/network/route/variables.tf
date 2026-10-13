variable "route_table_id" {
  description = "ID da route table alvo."
  type        = string
}

variable "routes_json" {
  description = "JSON com rotas (mapa nome_logico => objeto). Pode usar gateway_ref para apontar para uma chave de ref_ids."
  type        = string
}

variable "ref_ids" {
  description = "Mapa chave simbolica => ID (ex: { igw = <id do IGW> }) usado por gateway_ref. As CHAVES devem ser conhecidas no plan."
  type        = map(string)
  default     = {}
}
