# Prompt para Claude Code

## Com a skill instalada (o jeito mais fácil)

Abra o Claude Code na pasta do projeto e escreva:

```
Faça uma auditoria de segurança deste projeto usando a skill auditoria-seguranca.
Comece só lendo (não altere nada sem eu aprovar), me mostre a evidência de cada achado
e explique em linguagem simples. No fim, escreva o relatório e o plano em docs/.
```

Ela segue o roteiro da skill: preparar → inventário → banco → teste do visitante → teste por perfil →
edge functions → páginas públicas → front → segredos → varredura independente → relatório.

### Variações úteis

- **Só um diagnóstico rápido** (meia hora):
  ```
  Use a skill auditoria-seguranca e rode só as fases 2 e 3 (catálogo do banco e teste do visitante).
  Quero saber se algum dado de cliente está vazando para quem não tem login.
  ```
- **Só as páginas públicas:**
  ```
  Use a skill auditoria-seguranca, fase 6: para cada página pública com link, me diga o token, a validade,
  o limite de tentativas e o que a API entrega além do que a tela mostra. Teste só com tokens falsos.
  ```
- **Aplicar as correções (depois do plano aprovado):**
  ```
  Aplique a correção X do plano, seguindo a Parte 5 do guia (migration com cabeçalho e bloco DO,
  ensaio em transação desfeita, dry-run, tsc em cópia limpa). Pare antes de publicar e me mostre o que vai subir.
  ```
- **Levar as correções de um projeto para outro:**
  ```
  O projeto <A> já foi auditado e corrigido (veja docs/correcoes/ de lá). Use a skill auditoria-seguranca para
  auditar este projeto, compare com o que foi feito em <A> e monte o plano do que falta aqui. Só leitura.
  ```

## Com o plugin Claude Security (varredura independente)

```
/claude-security:claude-security
```
→ Scan codebase → escopo `supabase/` (servidor) → esforço `medium`. Para o front: escopo `src/`, esforço `low`.
Para revisar só o que mudou antes de publicar: `/security-review`.

## Sem a skill instalada

Anexe o `GUIA_COMPLETO.md` e use o prompt de `prompts/outras-ias.md`: funciona igual no Claude Code.

## Instalar a skill

```bash
npx skills add https://github.com/dmanske/auditoria-seguranca-supabase --skill auditoria-seguranca -g -y
# ou à mão:
git clone https://github.com/dmanske/auditoria-seguranca-supabase
cp -R auditoria-seguranca-supabase/skills/auditoria-seguranca ~/.claude/skills/
```

Skills complementares (recomendadas):
```bash
npx skills add https://github.com/supabase/agent-skills --skill supabase -g -y
npx skills add https://github.com/supabase/agent-skills --skill supabase-postgres-best-practices -g -y
npx skills add https://github.com/sickn33/agentic-awesome-skills --skill 007 -g -y
npx skills add https://github.com/sickn33/agentic-awesome-skills --skill find-bugs -g -y
```
