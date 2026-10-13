# ADR 0011: Recuperação de desastre por backups automáticos e PITR

## Contexto

- O desafio pede RPO e RTO e um plano para recriar o ambiente em outra região ou conta. [FATO: [`00-fonte-da-verdade.md`](../../.kiro/steering/00-fonte-da-verdade.md) seção "Requisitos obrigatórios do desafio", item 5]
- O RDS tem `backup_retention_period = 7`, o que liga os backups automáticos e o restore para um ponto no tempo (PITR). [FATO: [`modules/rds/main.tf`](../../infrastructure/modules/rds/main.tf) linha 32]
- A AWS envia os logs de transação do RDS ao S3 a cada cinco minutos. O restore para um ponto no tempo cria uma **nova** instância e não altera a original. [FATO: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIT.html, aberta em 13/10/2026]
- A replicação de backups automáticos para outra região copia snapshots e logs de transação. Há cobrança de transferência e de armazenamento no destino. [FATO: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReplicateBackups.html, aberta em 13/10/2026]
- Snapshot cifrado com a chave KMS padrão não pode ser compartilhado com outra conta. [FATO: [`00-fonte-da-verdade.md`](../../.kiro/steering/00-fonte-da-verdade.md) seção "Fatos de serviços AWS"]
- Conta aberta pelo cadastro novo não suporta recursos multi-região ou cross-região até a ativação dos recursos avançados. [FATO: [`00-fonte-da-verdade.md`](../../.kiro/steering/00-fonte-da-verdade.md) seção "Conta AWS e orçamento"]
- No `dev` o RDS tem `skip_final_snapshot = true` e `deletion_protection = false`. O módulo não define `delete_automated_backups`, e o padrão do provider na versão fixada é `true`. [FATO: [`dev.tfvars`](../../infrastructure/environments/dev.tfvars) linhas 87-88, [`modules/rds/main.tf`](../../infrastructure/modules/rds/main.tf) e a doc do `aws_db_instance` v6.68.0, https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/v6.68.0/website/docs/r/db_instance.html.markdown, argumento `delete_automated_backups`]

## Decisão

- Na mesma região: RPO alvo de até 5 minutos e RTO alvo de 30 a 60 minutos, por backups automáticos com retenção de 7 dias, restore PITR e `terraform apply`. O RTO é uma **meta a medir** num teste real. Não há medição.
- Em outra região ou conta: recriar a mesma stack, parametrizada por região, com state separado, e restaurar o banco a partir do que tiver sido copiado. O RPO entre regiões depende da cópia escolhida.
- Isto é **documentado e não implementado**. O procedimento está em [`docs/dr.md`](../dr.md).

## Alternativas consideradas

| Alternativa | RPO | Custo | Motivo |
|---|---|---|---|
| RDS Multi-AZ | **A verificar**. Cobre falha de AZ, não é DR entre regiões | **A verificar**; a steering diz que dobra o custo | Proibida sem pedido explícito. Alta disponibilidade não é o requisito |
| Replicação de backups automáticos entre regiões | Minutos (PITR no destino) | Transferência e armazenamento no destino, **a verificar** | Não suportada em conta aberta pelo cadastro novo sem recursos avançados. Não implementada |
| Cópia diária de snapshot entre regiões | Até 24 h | Armazenamento do snapshot copiado, **a verificar** | Mesma restrição de conta. Não implementada |
| Snapshot compartilhado com outra conta | Depende da frequência | Chave KMS gerenciada pelo cliente, cerca de US$ 1/mês, **a verificar** | A chave padrão não compartilha. Não implementada |
| Réplica de leitura entre regiões ou Aurora Global | **A verificar** | **A verificar** | Proibidos pela steering (réplicas, Aurora) |

## Consequências

- **Um `destroy` apaga os backups automáticos** com o padrão atual (`delete_automated_backups = true`) e não deixa snapshot final no `dev`. O PITR protege contra erro lógico ou corrupção enquanto a instância existe; não protege contra a destruição da própria instância. Mudar isso (`delete_automated_backups = false`, `skip_final_snapshot = false`, `deletion_protection = true`) é **[PROPOSTA]**, tem custo de armazenamento a verificar e contraria a decisão atual de evitar resíduo. Não foi feita.
- O restore cria uma instância nova, com endpoint novo. A aplicação lê `DB_HOST` da task definition, e o `ignore_changes` do service faz com que uma mudança de variável de ambiente pelo Terraform não chegue ao service sem um deploy. O passo a passo trata isso em [`docs/dr.md`](../dr.md).
- O módulo `rds` não tem entrada para restaurar de snapshot ou de PITR. O recurso `aws_db_instance` aceita `snapshot_identifier` e o bloco `restore_to_point_in_time`, mas usá-los exigiria alterar o módulo. [FATO: doc do `aws_db_instance` v6.68.0 citada acima]
- Nenhum teste de restore foi feito. RPO e RTO são metas, não resultados.

## Status

Aceito como plano documentado. **Não implementado e não testado.**
