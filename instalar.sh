#!/usr/bin/env bash
# Instala a skill auditoria-seguranca e as skills complementares que usamos nas auditorias.
# Usa o instalador universal de skills (npx skills), que pergunta para qual assistente instalar
# (Claude Code, Kiro, Cursor, Gemini CLI…). -g = global (todos os projetos); -y = sem perguntas extras.
#
# Uso:
#   bash instalar.sh            # skill principal + complementares recomendadas
#   bash instalar.sh --minimo   # só a skill principal
#
# Precisa de Node.js 18+ (npx). Não instala nada além de pastas de skills (arquivos de texto e scripts).
set -e

REPO="https://github.com/dmanske/auditoria-seguranca-supabase"

echo "== 1/2 Skill principal: auditoria-seguranca"
npx -y skills add "$REPO" --skill auditoria-seguranca -g -y

if [[ "${1:-}" == "--minimo" ]]; then
  echo "Pronto (modo mínimo)."; exit 0
fi

echo
echo "== 2/2 Skills complementares"
# Supabase (oficiais): guia geral e boas práticas de Postgres/RLS
npx -y skills add https://github.com/supabase/agent-skills --skill supabase -g -y || echo "⚠️  supabase não instalou; siga sem ela ou instale à parte"
npx -y skills add https://github.com/supabase/agent-skills --skill supabase-postgres-best-practices -g -y || echo "⚠️  supabase-postgres-best-practices não instalou; siga sem ela ou instale à parte"
# 007: auditoria, modelagem de ameaças (STRIDE/PASTA), veredito de produção, resposta a incidente
npx -y skills add https://github.com/sickn33/agentic-awesome-skills --skill 007 -g -y || echo "⚠️  007 não instalou; siga sem ela ou instale à parte"
# find-bugs: revisa o diff da branch atrás de bugs e vulnerabilidades
npx -y skills add https://github.com/sickn33/agentic-awesome-skills --skill find-bugs -g -y || echo "⚠️  find-bugs não instalou; siga sem ela ou instale à parte"
# brainstorming: desenhar correções grandes antes de construir
npx -y skills add https://github.com/obra/superpowers --skill brainstorming -g -y || echo "⚠️  brainstorming não instalou; siga sem ela ou instale à parte"

cat <<'TXT'

Pronto. Linhas "✗ … PromptScript does not support global skill installation" são normais: esse
assistente não aceita instalação global; os outros (Claude Code incluso) receberam as skills.

Opcionais (instale à parte, se quiser):
- Plugin Claude Security (varredura com painel de 3 verificadores): no Claude Code, digite /plugin e procure
  "Claude Security". Se não aparecer na sua conta, use /security-review (já vem no Claude Code).
- Skills de teste da coleção comunitária (use SÓ no seu sistema): procure com
    npx skills find idor        npx skills find xss        npx skills find threat modeling
- Engenharia reversa / captura de tráfego de páginas: skill reverse-engineer-anything + servidor MCP rea.
- Ferramentas sem IA: Supabase CLI, Deno, gitleaks ou trufflehog, semgrep (ver referencias/ferramentas.md).

Como usar: abra o seu assistente na pasta do projeto e peça
  "Faça uma auditoria de segurança deste projeto usando a skill auditoria-seguranca. Só leitura primeiro."
TXT
