#!/usr/bin/env bash
# Roda `deno check` em cada Edge Function (supabase/functions/<nome>/index.ts), sem gravar lockfile.
# Erro de tipo às vezes esconde bug real (ex.: função chamada com argumentos a menos).
# Uso:  bash deno-check-todas.sh [raiz-do-projeto] [pasta-de-logs]
# Precisa do Deno instalado (macOS: brew install deno; outros: https://deno.land).
set -u
RAIZ="${1:-.}"
SAIDA="${2:-/tmp/deno-check}"
mkdir -p "$SAIDA"
cd "$RAIZ" || exit 1
command -v deno >/dev/null || { echo "Deno não encontrado. Instale: brew install deno"; exit 1; }

ok=0; falhou=0
for dir in supabase/functions/*/; do
  nome=$(basename "$dir")
  [[ "$nome" == _* ]] && continue                      # _shared e afins não são funções
  [[ -f "$dir/index.ts" ]] || continue
  if [[ -f "$dir/deno.json" ]]; then cfg=(--config "$dir/deno.json"); else cfg=(--no-config); fi
  if deno check --no-lock "${cfg[@]}" "$dir/index.ts" > "$SAIDA/$nome.log" 2>&1; then
    ok=$((ok+1))
  else
    falhou=$((falhou+1))
    echo "FALHOU: $nome ($(grep -c 'TS[0-9]' "$SAIDA/$nome.log") erros) — veja $SAIDA/$nome.log"
  fi
done
echo "Resumo: $ok ok, $falhou com erro."
echo "Leia cada erro: muitos são só de tipagem (consultas viram 'never'), mas 'Expected 2 arguments, but got 1'"
echo "e 'Cannot find name' costumam ser bug de verdade."
