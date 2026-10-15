# Auditoria de segurança para projetos Supabase

Um roteiro completo, testado num sistema real, para descobrir **se o seu projeto está vazando dados** e
**como corrigir sem quebrar nada**. Pensado para projetos com:

- front em React/Vite ou Next.js (Vercel ou similar);
- **Supabase**: banco Postgres com RLS, Storage, Edge Functions e Auth;
- páginas públicas para clientes (links com token), painel administrativo, pagamentos e integrações.

Funciona com **Claude Code** (como skill), com **outras IAs** (Cursor, Kiro, ChatGPT/Codex, Gemini, Copilot)
e também **sem IA**, seguindo o guia à mão.

> ⚠️ Use só em projetos seus ou que você tem autorização para testar.

## O que tem aqui

```
skills/auditoria-seguranca/
├── SKILL.md                     ← roteiro que a IA segue (Claude Code, Kiro, Gemini CLI…)
├── GUIA_COMPLETO.md             ← o guia: conceitos, roteiro, ~45 falhas com correção, publicação segura
├── referencias/
│   ├── consultas.sql            ← consultas de diagnóstico (só leitura)
│   ├── padroes-correcao.sql     ← modelos de migration (fechar função, policies, storage, travas)
│   ├── pecas-de-codigo.md       ← código pronto (autorização, link assinado, CORS, limites, HTML seguro…)
│   └── ferramentas.md           ← todas as skills e ferramentas, quando usar e como instalar
└── scripts/
    ├── teste-visitante.mjs      ← tenta ler tudo só com a chave pública e aponta vazamentos
    ├── alvos-visitante.sql      ← lista o que o visitante alcança (entrada do script acima)
    ├── conferir-endpoints.mjs   ← confere endpoints com tokens falsos (antes e depois de publicar)
    ├── deno-check-todas.sh      ← erros de tipo em todas as Edge Functions
    └── procurar-segredos.sh     ← chaves no código e no histórico do git
prompts/
├── claude-code.md               ← como pedir no Claude Code
└── outras-ias.md                ← prompt pronto para qualquer outra IA
```

## Comece por aqui: escolha o seu caminho

### 1. Uso Claude Code
```bash
npx skills add https://github.com/dmanske/auditoria-seguranca-supabase --skill auditoria-seguranca -g -y
```
Depois, na pasta do seu projeto:
```
Faça uma auditoria de segurança deste projeto usando a skill auditoria-seguranca. Só leitura primeiro.
```
Mais opções em [prompts/claude-code.md](prompts/claude-code.md).

### 2. Uso outra IA (Cursor, Kiro, ChatGPT, Gemini, Copilot…)
Abra a IA na pasta do projeto, anexe o [GUIA_COMPLETO.md](skills/auditoria-seguranca/GUIA_COMPLETO.md) e cole o
prompt de [prompts/outras-ias.md](prompts/outras-ias.md). No Kiro, copie a pasta da skill para `~/.kiro/skills/`
e use `@auditoria-seguranca`.

### 3. Não uso IA
Siga o [GUIA_COMPLETO.md](skills/auditoria-seguranca/GUIA_COMPLETO.md), Parte 3. Rode as consultas de
[consultas.sql](skills/auditoria-seguranca/referencias/consultas.sql) no **SQL Editor** do Supabase e os scripts
no terminal:

```bash
# o que um estranho consegue ler com a chave pública do seu site?
supabase db query --linked -f skills/auditoria-seguranca/scripts/alvos-visitante.sql > alvos.json
node skills/auditoria-seguranca/scripts/teste-visitante.mjs caminho/do/projeto/.env alvos.json

# chaves esquecidas no código ou no histórico do git
bash skills/auditoria-seguranca/scripts/procurar-segredos.sh caminho/do/projeto
```

## Os 5 problemas mais comuns (e mais graves)

1. **Policy "todo mundo vê tudo"** (`USING (true)`) numa tabela de clientes: qualquer pessoa com a chave pública
   do site (que está no próprio site) lê CPF, telefone e e-mail.
2. **Função do banco com poder de dono aberta para qualquer um** (`SECURITY DEFINER` executável por `anon` ou
   por qualquer logado): já vimos uma que entregava o segredo do servidor e, com ele, o banco inteiro.
3. **Edge Function sem checar quem chama:** `verify_jwt = true` não significa "logado".
4. **Link de cliente com token fraco, igual para todos ou que nunca vence**, e uma API que entrega mais do que a tela mostra.
5. **Segredo no histórico do git:** apagar o arquivo não basta, é preciso trocar a chave.

O guia explica cada um em linguagem simples, mostra como achar, como corrigir e como confirmar.

## Requisitos

- [Supabase CLI](https://supabase.com/docs/guides/cli) (`supabase login` + `supabase link`)
- Node.js 18+ (scripts)
- Opcional: [Deno](https://deno.land) (checar Edge Functions), `gitleaks` ou `trufflehog`, `semgrep`

## Licença

MIT. Use, adapte e compartilhe.
