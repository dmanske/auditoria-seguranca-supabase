#!/usr/bin/env bash
# Procura VALORES de segredos no código atual e no HISTÓRICO do git. Não imprime os valores: só arquivo,
# linha e tipo. Para JWT, diz o papel (anon = chave pública, normal; service_role = chave-mestra, problema).
# Uso:  bash procurar-segredos.sh [raiz-do-projeto]
# Para uma varredura mais completa, use também gitleaks ou trufflehog (ver referencias/ferramentas.md).
set -u
cd "${1:-.}" || exit 1

EXCLUIR=(--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build --exclude-dir='CLAUDE-SECURITY-*'
         --exclude=*.lock --exclude=package-lock.json --exclude=bun.lockb)
# Valores com formato de chave (não a palavra "service_role", que aparece em código e documentação legítimos)
PADRAO='(eyJ[A-Za-z0-9_-]{20,}\.eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}|sb_secret_[A-Za-z0-9_-]{10,}|APP_USR-[0-9]{6,}-[0-9]{6,}-[A-Za-z0-9]{10,}|sk_live_[A-Za-z0-9]{10,}|re_[A-Za-z0-9]{8,}_[A-Za-z0-9]{10,}|AIza[0-9A-Za-z_-]{30,}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|xox[baprs]-[A-Za-z0-9-]{10,})'

papel_jwt() {   # lê o "role" do payload do JWT, sem imprimir o token
  local meio pad
  meio=$(printf '%s' "$1" | cut -d. -f2 | tr '_-' '/+')
  pad=$(( (4 - ${#meio} % 4) % 4 )); meio="$meio$(printf '=%.0s' $(seq 1 $pad) 2>/dev/null)"
  printf '%s' "$meio" | base64 -d 2>/dev/null | grep -oE '"role":"[a-z_]+"' | cut -d'"' -f4
}

echo "== 1. Código atual (fora dos arquivos .env) =="
achou=0
while IFS= read -r linha; do
  arq=${linha%%:*}; resto=${linha#*:}; num=${resto%%:*}; valor=${resto#*:}
  case "$arq" in *.env|*.env.*) continue;; esac
  achou=1
  if [[ "$valor" == eyJ* ]]; then
    papel=$(papel_jwt "$valor")
    case "$papel" in
      anon) echo "  $arq:$num  JWT role=anon (chave pública: normal no front)";;
      service_role) echo "  $arq:$num  JWT role=service_role  <-- CHAVE-MESTRA: troque e remova";;
      *) echo "  $arq:$num  JWT role=${papel:-?}  <-- revisar";;
    esac
  else
    echo "  $arq:$num  tipo: ${valor:0:10}…  <-- revisar"
  fi
done < <(grep -rIonE "${EXCLUIR[@]}" "$PADRAO" . 2>/dev/null | sort -u | head -200)
[[ $achou -eq 0 ]] && echo "  (nada encontrado)"

echo
echo "== 2. Arquivos .env versionados no git (só .env.example deveria estar) =="
git ls-files 2>/dev/null | grep -E '(^|/)\.env' | grep -v '\.example$' || echo "  (nenhum)"

echo
echo "== 3. Histórico do git: commits que adicionaram algo com formato de chave =="
for termo in 'sb_secret_' 'APP_USR-' 'sk_live_' 'BEGIN PRIVATE KEY' 'AIza' 'ghp_' 'github_pat_'; do
  commits=$(git log --all --format='  %h %ad %s' --date=short -S"$termo" 2>/dev/null | head -5)
  [[ -n "$commits" ]] && { echo "-- $termo"; echo "$commits"; }
done
# JWT de service_role no histórico: procura tokens e lê o papel
git log --all -p -G'eyJ[A-Za-z0-9_-]{20,}\.eyJ' --format='COMMIT %h %ad %s' --date=short 2>/dev/null \
  | grep -oE '^COMMIT .*|eyJ[A-Za-z0-9_-]{20,}\.eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}' \
  | while IFS= read -r l; do
      if [[ "$l" == COMMIT* ]]; then commit="${l#COMMIT }"; continue; fi
      [[ "$(papel_jwt "$l")" == service_role ]] && echo "-- JWT service_role entra ou sai no commit: $commit  <-- se a chave ainda vale, TROQUE"
    done | sort -u | head -20

echo
echo "== 4. Valores de reserva em segredos (porta dos fundos) =="
grep -rInE "${EXCLUIR[@]}" "(Deno\.env\.get|process\.env|import\.meta\.env)[(.\[]['\"]?[A-Z_]*(SECRET|KEY|TOKEN|PASSWORD)[A-Z_]*['\"]?[)\]]?\s*(\|\||\?\?)\s*['\"][^'\"]+['\"]" . 2>/dev/null | head -50 \
  || echo "  (nada encontrado)"

echo
echo "== 5. Segredo em variável pública do front (vai para o navegador) =="
grep -rInE "${EXCLUIR[@]}" "(VITE_|NEXT_PUBLIC_)[A-Z_]*(SERVICE_ROLE|SECRET|PRIVATE)" . 2>/dev/null | head -20 || echo "  (nada encontrado)"

cat <<'TXT'

Como ler:
- JWT role=anon no front é normal (é a chave pública). role=service_role em qualquer arquivo do repositório é grave.
- O que aparece no HISTÓRICO continua válido para quem copiar o repositório: TROQUE a chave no painel do
  serviço (Supabase, gateway de pagamento, e-mail, WhatsApp). Apagar o arquivo não basta.
- Item 4: troque `env('X') || 'padrao'` por "sem segredo = recusa".
- Item 5: service_role e segredos nunca com prefixo VITE_ ou NEXT_PUBLIC_.
TXT
