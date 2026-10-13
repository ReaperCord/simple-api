mock_provider "aws" {}

# Chave estatica (JSON) + ID do IGW desconhecido no plan: nao pode dar "Invalid for_each argument".
run "gateway_ref_com_id_desconhecido_planeja" {
  command = plan

  module {
    source = "./tests/setup"
  }

  assert {
    condition     = length(module.route.route_ids) == 1
    error_message = "Esperava 1 rota (default_igw) planejada."
  }

  assert {
    condition     = contains(keys(module.route.route_ids), "default_igw")
    error_message = "A chave do for_each deve vir do JSON (default_igw)."
  }
}
