#!/usr/bin/env bash
# Classifica um plano do Terraform (saida de `terraform show -json tfplan`) para o gate do infra.yml.
# Uso: tools/plan-guard.sh <plan.json> <resumo.md>
#  - stdout: linhas chave=valor para o GITHUB_OUTPUT (create, update, delete, replace, forget, has_changes, destructive).
#  - <resumo.md>: tabela em Markdown com as contagens e a lista do que sera destruido ou substituido (so enderecos de
#    recurso, nunca valores: o resumo do run e publico neste repositorio).
# Destrutivo = algum recurso com acao delete (destroy) ou delete+create em qualquer ordem (replace).
# Saida: 0 = classificado; 2 = uso errado ou JSON invalido. Nao decide o gate: so informa (o workflow decide).
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "uso: $0 <plan.json> <resumo.md>" >&2
  exit 2
fi
plan="$1"
resumo="$2"

if ! jq -e '.format_version and (.resource_changes | type == "array" or . == null)' "$plan" >/dev/null 2>&1; then
  echo "erro: $plan nao e a saida de 'terraform show -json' de um plano" >&2
  exit 2
fi

# Uma linha por recurso com mudanca: "<tipo>\t<endereco>"; no-op e read nao contam.
classificado="$(jq -r '
  (.resource_changes // [])[]
  | (.change.actions | sort) as $a
  | (if   $a == ["create"]           then "create"
     elif $a == ["update"]           then "update"
     elif $a == ["delete"]           then "delete"
     elif $a == ["create", "delete"] then "replace"
     elif $a == ["forget"]           then "forget"
     else empty end) as $t
  | "\($t)\t\(.address)"
' "$plan")"

conta() { if [ -z "$classificado" ]; then echo 0; else grep -c "^$1"$'\t' <<<"$classificado" || true; fi; }
create="$(conta create)"
update="$(conta update)"
delete="$(conta delete)"
replace="$(conta replace)"
forget="$(conta forget)"

has_changes=false
[ $((create + update + delete + replace + forget)) -gt 0 ] && has_changes=true
destructive=false
[ $((delete + replace)) -gt 0 ] && destructive=true

printf 'create=%s\nupdate=%s\ndelete=%s\nreplace=%s\nforget=%s\nhas_changes=%s\ndestructive=%s\n' \
  "$create" "$update" "$delete" "$replace" "$forget" "$has_changes" "$destructive"

{
  echo "| Criar | Alterar | Destruir | Substituir | Esquecer (sai do state) |"
  echo "|---|---|---|---|---|"
  echo "| $create | $update | $delete | $replace | $forget |"
  echo
  if [ "$destructive" = true ]; then
    echo "**Mudanca destrutiva.** Recursos destruidos ou substituidos:"
    echo
    grep -E $'^(delete|replace)\t' <<<"$classificado" | head -100 | while IFS=$'\t' read -r tipo endereco; do
      echo "- \`${endereco}\` (${tipo})"
    done
    total=$((delete + replace))
    [ "$total" -le 100 ] || echo "- ... e mais $((total - 100))"
  elif [ "$has_changes" = true ]; then
    echo "Nenhum recurso destruido ou substituido."
  else
    echo "Sem mudancas: nada a aplicar."
  fi
} >"$resumo"
