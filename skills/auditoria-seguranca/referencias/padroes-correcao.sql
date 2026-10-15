-- =====================================================================================================
-- Padrões de correção (modelos de migration) — Supabase / Postgres
-- NÃO rode este arquivo inteiro. Copie o bloco que precisa para uma migration nova em supabase/migrations/,
-- troque os nomes, ensaie em transação desfeita e só então aplique (GUIA_COMPLETO.md, Parte 5).
-- Numeração citada no GUIA_COMPLETO.md.
-- =====================================================================================================


-- §0. Cabeçalho padrão de toda migration de segurança ------------------------------------------------
-- =====================================================
-- <Título curto> (<data>) — <achado da auditoria>
--
-- PROBLEMA: <o que acontecia, com a evidência: consulta + resultado>
-- CORREÇÃO: <o que muda>
-- QUEM USA: <telas/funções que dependem disto; o que foi conferido>
-- ORDEM DE PUBLICAÇÃO: <ex.: aplicar antes de publicar as funções X e Y>
-- REVERTER: <SQL que volta ao estado anterior>
-- =====================================================


-- §1. Fechar uma função (SECURITY DEFINER) -------------------------------------------------------------
-- Só o servidor usa (edge function com service_role, cron, outra função do banco):
revoke all on function public.minha_funcao(uuid) from public, anon, authenticated;
grant execute on function public.minha_funcao(uuid) to service_role;
-- ATENÇÃO: no Supabase, "from public" sozinho NÃO basta: anon e authenticated têm grant direto.

-- A equipe logada usa (mas com trava dentro, §2):
revoke all on function public.minha_funcao(uuid) from public, anon;
grant execute on function public.minha_funcao(uuid) to authenticated, service_role;

-- Página pública usa de propósito: deixe para anon, documente, e a função se autoriza sozinha
-- (parâmetro obrigatório, erro genérico, não enumerável, devolve só o necessário).

-- search_path fixo em toda SECURITY DEFINER:
alter function public.minha_funcao(uuid) set search_path = public, pg_temp;
-- Se usar extensão (pgcrypto): chame extensions.gen_random_bytes(...) ou use 'public, extensions, pg_temp'.


-- §2. Trava de chamador DENTRO da função ----------------------------------------------------------------
-- Copie a definição VIVA (select pg_get_functiondef('public.f(args)'::regprocedure)) e acrescente no início do corpo:
--   (a) logado precisa da permissão; servidor/cron (sem login) passam
--   if auth.uid() is not null and not coalesce(public.user_has_permission('financeiro_editar'), false) then
--     raise exception 'Sem permissão para esta ação.' using errcode = '42501';
--   end if;
--   (b) só servidor ou dono
--   if not (coalesce(auth.role(), 'service_role') = 'service_role' or public.is_dono()) then
--     raise exception 'Sem permissão.' using errcode = '42501';
--   end if;


-- §3. Policies de equipe (logado E ativo E com permissão) -----------------------------------------------
-- Função auxiliar (exemplo; adapte à sua tabela de permissões):
create or replace function public.is_equipe_ativa()
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.usuarios_permissoes
                 where user_id = auth.uid() and coalesce(ativo, true));
$$;
revoke all on function public.is_equipe_ativa() from public, anon;
grant execute on function public.is_equipe_ativa() to authenticated, service_role;

-- Leitura para a equipe ativa; gravação só com a caixa:
drop policy if exists "Authenticated full access" on public.minha_tabela;
create policy equipe_le on public.minha_tabela for select to authenticated
  using ((select public.is_equipe_ativa()));
create policy equipe_grava on public.minha_tabela for all to authenticated
  using ((select public.user_has_permission('minha_area_editar')))
  with check ((select public.user_has_permission('minha_area_editar')));
-- "(select fn())" faz a função ser avaliada uma vez por consulta, não por linha.
-- Use "to authenticated" (nunca auth.role() = 'authenticated', que é obsoleto).

-- Dono da linha (multi-usuário / multi-empresa): USING e WITH CHECK com o mesmo predicado
create policy dono_da_linha on public.pedidos for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- Dados só do servidor: RLS ligada e NENHUMA policy (a API não lê nem grava; service_role passa)
alter table public.tabela_interna enable row level security;
revoke all on public.tabela_interna from public, anon, authenticated;
grant all on public.tabela_interna to service_role;


-- §4. Grants de tabela (em ondas) e por coluna ----------------------------------------------------------
-- Onda 1: o que nem passa pela RLS
revoke truncate, references, trigger on all tables in schema public from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke truncate, references, trigger on tables from anon, authenticated;
-- Onda 2: visitante não apaga
revoke delete on all tables in schema public from anon;
alter default privileges for role postgres in schema public revoke delete on tables from anon;
-- Onda 3: visitante não grava (depois de inventariar os fluxos públicos que gravam)
-- revoke insert, update on all tables in schema public from anon;
-- grant insert (nome, telefone, cidade) on public.cadastro_publico to anon;   -- grant mínimo por fluxo
-- Funções novas não nascem abertas ao visitante:
alter default privileges for role postgres in schema public revoke execute on functions from public, anon;

-- Colunas públicas (a RLS filtra linha, não coluna):
revoke select on public.eventos from anon;
grant select (id, nome, data, local, imagem_url) on public.eventos to anon;
-- REVERTER: grant select on public.eventos to anon;
-- No front: nunca select('*') nesta tabela; lista de colunas num arquivo central. Publique o site ANTES.


-- §5. Storage -------------------------------------------------------------------------------------------
-- Bucket privado, com limite de tamanho e tipos
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('documentos-privados', 'documentos-privados', false, 10485760, array['image/jpeg','image/png','application/pdf'])
on conflict (id) do update set public = false,
  file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- Tornar privado um bucket existente
update storage.buckets set public = false where id in ('fotos-clientes');

-- Equipe ativa lê
create policy docs_equipe_le on storage.objects for select to authenticated
  using (bucket_id = 'documentos-privados' and (select public.is_equipe_ativa()));

-- Cada usuário só na própria pasta (<uid>/arquivo)
create policy envio_grava_propria_pasta on storage.objects for insert to authenticated
  with check (bucket_id = 'envios' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy envio_le_propria_pasta on storage.objects for select to authenticated
  using (bucket_id = 'envios' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Upload anônimo (só se necessário): nome rígido, sem listar nem ler de volta
create policy upload_publico_rigido on storage.objects for insert to anon
  with check (bucket_id = 'uploads-publicos'
              and name ~ '^cadastro/[0-9]{10,16}-[a-z0-9]{1,20}\.(jpg|jpeg|png|webp)$');
-- Apagar bucket: o banco não deixa por SQL; esvazie e apague pelo painel.


-- §6. Blocos DO de verificação (a migration falha e desfaz se a correção não pegou) --------------------
-- (a) bucket continua público
do $$ begin
  if exists (select 1 from storage.buckets where id in ('fotos-clientes') and public) then
    raise exception 'Bucket ainda público';
  end if;
end $$;

-- (b) função ainda executável por quem não devia
do $$ declare v text; begin
  foreach v in array array['public.minha_funcao(uuid)', 'public.outra_funcao(uuid, uuid)'] loop
    if has_function_privilege('anon', v, 'execute') or has_function_privilege('authenticated', v, 'execute') then
      raise exception '% ainda executável por anon/authenticated', v;
    end if;
  end loop;
end $$;

-- (c) função pública não pode voltar a entregar campo sensível (teste de regressão)
do $$ declare v_def text := pg_get_functiondef('public.buscar_documento_por_token(uuid)'::regprocedure); v text; begin
  foreach v in array array['conteudo_html','assinatura','selfie','ip_','cpf'] loop
    if position(v in v_def) > 0 then raise exception 'Função pública ainda referencia %', v; end if;
  end loop;
end $$;

-- (d) nenhuma policy que lê permissões sem conferir "ativo"
do $$ declare n int; begin
  select count(*) into n from pg_policies
   where schemaname in ('public','storage')
     and (coalesce(qual,'') || coalesce(with_check,'')) like '%usuarios_permissoes%'
     and (coalesce(qual,'') || coalesce(with_check,'')) not like '%ativo%';
  if n > 0 then raise exception '% policies ainda não conferem ativo', n; end if;
end $$;

-- (e) trava contra apagar dados por engano (ex.: ao remover um módulo)
do $$ begin
  if exists (select 1 from public.tabela_a_remover limit 1) then
    raise exception 'tabela_a_remover tem dados: abortando';
  end if;
end $$;


-- §7. Token por pessoa (link pessoal seguro) ------------------------------------------------------------
create table if not exists public.links_pessoais (
  id          uuid primary key default gen_random_uuid(),
  cliente_id  uuid not null unique references public.clientes(id) on delete cascade,
  token       text not null unique default encode(extensions.gen_random_bytes(32), 'hex'),   -- 256 bits
  criado_em   timestamptz not null default now(),
  revogado_em timestamptz
);
alter table public.links_pessoais enable row level security;   -- sem policy: só servidor e funções
revoke all on public.links_pessoais from public, anon, authenticated;
grant all on public.links_pessoais to service_role;
-- A equipe obtém/gera o link por função SECURITY DEFINER com trava de permissão (§2),
-- usando "insert ... on conflict (cliente_id) do update" para chamadas simultâneas.
-- A página pública valida o token numa EDGE FUNCTION (service_role), nunca por policy.


-- §8. View sem segredos para a equipe (tabela original fica só para a gestão) -------------------------
create or replace view public.integracoes_basicas with (security_invoker = true) as
  select id, nome, ativo, (configuracoes ->> 'phone_number') as telefone
  from public.integracoes;
revoke all on public.integracoes_basicas from public, anon;
grant select on public.integracoes_basicas to authenticated, service_role;
-- E na tabela original: policy de SELECT só para quem gerencia (ex.: pode_ler_segredos()).


-- §9. Constraint de esquema (o banco recusa mesmo se gravarem direto pela API) -------------------------
alter table public.reembolsos add constraint reembolsos_comprovante_https
  check (comprovante_url is null or comprovante_url ~* '^https://');
-- Limpar token gravado em log:
update public.logs_eventos set url = regexp_replace(url, '[?#].*$', '') where url ~ '[?#]';


-- §10. Bloqueio imediato --------------------------------------------------------------------------------
create or replace function public.encerrar_sessoes_usuario(p_user uuid)
returns void language plpgsql security definer set search_path = public, auth, pg_temp as $$
begin
  delete from auth.refresh_tokens where user_id = p_user::text;
  delete from auth.sessions where user_id = p_user;
end $$;
revoke all on function public.encerrar_sessoes_usuario(uuid) from public, anon, authenticated;
grant execute on function public.encerrar_sessoes_usuario(uuid) to service_role;
-- E: toda função/policy que lê o papel confere coalesce(ativo, true); o front desloga ao voltar o foco.


-- §11. Views que furam a RLS ----------------------------------------------------------------------------
alter view public.minha_view set (security_invoker = true);
-- View materializada não aceita: revoke select on public.minha_view_mat from anon, authenticated;


-- §12. Segredo interno lido pelo banco (cron chamando edge function) ---------------------------------
-- O segredo fica no Vault; uma função SECURITY DEFINER (só servidor) lê e o cron chama a edge com o header.
-- create or replace function public.cron_chamar_edge(p_function text) returns void
--   language sql security definer set search_path = public, pg_temp as $$
--   select net.http_post(
--     url := '<SUPABASE_URL>/functions/v1/' || p_function,
--     headers := jsonb_build_object('Content-Type','application/json',
--                                   'x-internal-secret', (select decrypted_secret from vault.decrypted_secrets
--                                                         where name = 'INTERNAL_TRIGGER_SECRET')));
-- $$;
-- revoke all on function public.cron_chamar_edge(text) from public, anon, authenticated;
