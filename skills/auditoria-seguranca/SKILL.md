---
name: auditoria-seguranca
description: Auditoria e endurecimento de segurança de projetos web com Supabase (Postgres + RLS + Storage + Edge Functions) e front React/Vite/Next na Vercel. Use quando o usuário pedir "auditoria de segurança", "ver se está vazando dado", "revisar segurança", "RLS", "policy", "página pública segura", "link com token", "proteger dados de clientes", "posso colocar em produção?", ou quiser aplicar as correções de segurança de um projeto em outro. Roteiro em fases (só leitura → evidência → plano → correção aprovada → verificação), com consultas SQL, scripts de teste como visitante, catálogo de ~40 classes de falha e o padrão de correção de cada uma.
---

# Auditoria de segurança (Supabase + front)

Você vai conduzir uma auditoria de segurança **com evidência**, no projeto aberto, seguindo este roteiro.
O material completo (explicado para leigos e com o detalhe técnico) está em `GUIA_COMPLETO.md`, nesta mesma
pasta. Leia as partes que a fase pedir; não precisa ler tudo de uma vez.

Arquivos desta skill:
- `GUIA_COMPLETO.md`: conceitos, roteiro detalhado, catálogo de falhas (com "como achar / como corrigir /
  como confirmar / armadilha"), publicação segura, padrões de desenho, incidentes reais, checklist final.
- `referencias/consultas.sql`: todas as consultas de diagnóstico (só leitura).
- `referencias/padroes-correcao.sql`: modelos de migration (revoke/grant, policies, travas, blocos de verificação).
- `referencias/pecas-de-codigo.md`: código pronto para Edge Functions e front (autorização, link assinado,
  CORS, IP e limite de tentativas, HTML seguro, storage privado, webhook, links seguros).
- `referencias/ferramentas.md`: as skills e ferramentas (Claude Security, /security-review, find-bugs, 007,
  supabase, rea, advisors) e os equivalentes para quem não usa Claude.
- `scripts/`: teste do visitante, conferência de endpoints com tokens falsos, `deno check` em todas as
  funções, busca de segredos.

## Regras que valem a auditoria inteira

1. **Primeiro só leitura.** Não altere banco, edge function, storage, segredos nem config sem aprovação
   explícita do usuário. Diagnóstico e plano vêm antes.
2. **Evidência sempre.** Todo achado traz `arquivo:linha` ou a consulta + o resultado. Achado grave é
   verificado no código e, quando possível, no banco ao vivo antes de ser reportado como fato.
3. **O banco ao vivo é a verdade.** Dumps, fotos de schema e migrations antigas podem não bater com produção.
   Consulte o catálogo (`pg_policies`, `pg_proc`, `has_function_privilege`, `storage.buckets`).
4. **Teste com papel errado.** Prove o que vaza chamando a API como visitante (só a chave pública), como
   funcionário sem permissão e como bloqueado. Distinga "protegido" (erro 42501/401/403) de "vazio" (`[]`
   numa tabela sem dados não prova nada).
5. **Nunca** rode `supabase config push` (aplica o `config.toml` inteiro sem perguntar e já derrubou o login de
   vários apps). Nunca teste envio em lote (WhatsApp, e-mail) contra produção. Nunca imprima o `.env`.
6. **Nada de dado real em testes:** use tokens falsos (`00000000-0000-4000-8000-000000000000`) e dados fictícios;
   ensaios de escrita em transação desfeita (`begin; ... rollback;`).
7. **Explique em linguagem simples.** Para cada correção: como está hoje, como fica, o que pode afetar no app,
   como reverter. O usuário pode ser leigo.
8. **Se outras sessões/agentes mexem no mesmo repositório:** não use `git stash`, `checkout -- .` nem `reset`;
   faça commit só dos seus arquivos; confira o número da migration contra a maior existente; rode o
   `--dry-run` e confira que só aparecem as suas.

## Roteiro (fases)

Siga a ordem. Ao fim de cada fase, resuma para o usuário o que achou (com evidência) antes de seguir.
Detalhes de cada fase: `GUIA_COMPLETO.md`, Parte 3.

0. **Preparar.** Descubra a stack (front, `supabase/`, `vercel.json`), qual projeto Supabase o site usa
   (`.env`, `supabase/config.toml` só para ler o `project_id`), se o CLI está ligado (`supabase projects list`,
   `supabase migration list --linked`). Se o MCP do Supabase negar permissão, use
   `supabase db query --linked "<SQL>"`. Pergunte ao usuário o que é público de propósito (páginas sem login,
   links enviados a clientes) e se há dados reais no banco.
1. **Inventário.** Liste: tabelas, views, funções, buckets, edge functions (com `verify_jwt` de
   `supabase/config.toml`), rotas públicas do front, webhooks, crons (`cron.job`), segredos usados
   (`Deno.env.get`, `import.meta.env`).
2. **Banco.** Rode `referencias/consultas.sql` (seções 1 a 8): RLS, policies abertas, grants, funções
   `SECURITY DEFINER` executáveis por `anon`/`authenticated`, `search_path`, views sem `security_invoker`,
   buckets e policies de storage, crons com chave escrita. Rode também `supabase db advisors --linked --type security`.
3. **Teste do visitante (empírico).** `scripts/teste-visitante.mjs`: com só a chave pública, tenta ler toda
   tabela/view, chama as funções estáveis sem argumento e lista os buckets. Marca respostas com CPF, e-mail,
   telefone e colunas sensíveis, sem imprimir valores.
4. **Teste por perfil.** Em transação desfeita, simule visitante, funcionário sem a permissão, funcionário
   com a permissão, bloqueado, dono e servidor (`set local role` + claims). Teste leitura E escrita, inclusive
   escrita cruzada (o próprio id num parâmetro e o id alheio em outro). Ver `GUIA_COMPLETO.md` 3.4.
5. **Edge functions.** Para cada uma: quem pode chamar? (`verify_jwt=true` não é "logado": a chave pública
   passa.) Procure: falta de checagem, decisão pelo corpo (`automatico: true`), id de usuário vindo do corpo,
   `service_role` usado antes de autorizar, segredo com valor de reserva, CORS `*`, IP do primeiro item de
   `x-forwarded-for`, limite que falha aberto, caminho de storage montado com dado do cliente, webhook sem
   assinatura. Rode `scripts/deno-check-todas.sh`.
6. **Páginas públicas e links com token.** Para cada rota pública: força do token (bits, gerador), validade,
   revogação, limite de tentativas, resposta igual para "não existe"/"errado", o que a API entrega a mais do
   que a tela mostra, `noindex`, token em log/URL/Referer. Confira com `scripts/conferir-endpoints.mjs` (tokens falsos).
7. **Front.** XSS (`dangerouslySetInnerHTML`, `document.write`, `innerHTML`, `<iframe src>`/`<a href>` com
   valor do banco), segredos no bundle (`VITE_`/`NEXT_PUBLIC_` com `service_role`), headers (`vercel.json`:
   CSP, HSTS, X-Frame-Options, Referrer-Policy), `npm audit`.
8. **Segredos e histórico.** `scripts/procurar-segredos.sh` (código + histórico do git). Chave que já esteve
   no git precisa ser **trocada**, não só apagada.
9. **Varredura independente (opcional, recomendada).** Se o plugin Claude Security estiver instalado:
   `/claude-security:claude-security` → Scan codebase, escopo no servidor (`supabase/`), esforço `medium`.
   Para um diff: `/security-review` ou `/find-bugs`. Ver `referencias/ferramentas.md`.
10. **Relatório e plano.** Escreva o relatório (achados por severidade, evidência, impacto em linguagem
    simples, correção proposta) e o plano em ordem de prioridade. Registre no `docs/` do projeto. Não aplique nada.

## Corrigindo (só depois da aprovação)

Siga `GUIA_COMPLETO.md`, Parte 5 (publicação segura). Resumo:
- Toda mudança de banco vira migration nova (número acima da maior existente), com cabeçalho
  PROBLEMA / CORREÇÃO / QUEM USA / ORDEM / COMO REVERTER e um bloco `DO` que falha se a correção não pegou.
- Ensaie em transação desfeita; `supabase db push --linked --dry-run`; só então aplique.
- Antes de restringir uma função/policy, procure quem usa (front, edge functions, outras policies, gatilhos).
- Ordem: o código novo não pode chamar o que ainda não existe; o banco novo não pode quebrar o código que
  está no ar. Em geral: banco → funções → site; para fechar um caminho antigo: caminho novo → telas →
  publicar → fechar o antigo.
- Antes do push: `tsc` com 0 erros numa cópia limpa do commit (o build da Vercel roda `tsc`; 1 erro derruba
  o site), testes, `deno check` nas funções alteradas.
- Depois de publicar: confira de fora com tokens falsos (`scripts/conferir-endpoints.mjs`) e no catálogo.
- Segredo exposto: troque (rotação) e confira por hash, sem exibir o valor.
- Diga ao usuário o que NÃO foi testado (ex.: fluxo real no celular, WhatsApp real) e o que mudou por conta própria.
