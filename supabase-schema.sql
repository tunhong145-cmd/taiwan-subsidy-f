-- F 项目独立订单表。此脚本可重复执行，不修改 subsidy_leads 或任何其他表。
begin;
create extension if not exists pgcrypto;

create table if not exists public.f_subsidy_leads (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  apply_type text not null,
  apply_amount text not null,
  name text not null,
  age text not null default '',
  residence text not null,
  line_id text not null,
  phone text not null,
  id_number text not null,
  payout_bank text not null,
  warning_account text not null default '',
  source_url text,
  user_agent text,
  status text not null default 'new' check (status in ('new','contacted','processing','approved','rejected','invalid')),
  notes text not null default ''
);

-- Existing F tables are migrated to accept any customer-entered age text.
alter table public.f_subsidy_leads drop constraint if exists f_subsidy_leads_age_check;
alter table public.f_subsidy_leads alter column age drop default;
alter table public.f_subsidy_leads alter column age type text using age::text;
alter table public.f_subsidy_leads alter column age set default '';
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'f_subsidy_leads'
      and column_name = 'warning_account'
      and data_type = 'boolean'
  ) then
    alter table public.f_subsidy_leads alter column warning_account drop default;
    alter table public.f_subsidy_leads alter column warning_account type text using (case when warning_account then 'yes' else 'no' end);
  end if;
  alter table public.f_subsidy_leads alter column warning_account set default '';
end;
$$;

create index if not exists f_subsidy_leads_created_at_idx on public.f_subsidy_leads (created_at desc);
create index if not exists f_subsidy_leads_status_idx on public.f_subsidy_leads (status);
create index if not exists f_subsidy_leads_phone_idx on public.f_subsidy_leads (phone);

create or replace function public.set_f_subsidy_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_f_subsidy_updated_at on public.f_subsidy_leads;
create trigger set_f_subsidy_updated_at
before update on public.f_subsidy_leads
for each row execute function public.set_f_subsidy_updated_at();

alter table public.f_subsidy_leads enable row level security;

drop policy if exists "f_public_can_submit" on public.f_subsidy_leads;
create policy "f_public_can_submit"
on public.f_subsidy_leads for insert
to anon
with check (
  status = 'new'
);

drop policy if exists "f_admin_can_read" on public.f_subsidy_leads;
create policy "f_admin_can_read"
on public.f_subsidy_leads for select
to authenticated
using ((auth.jwt() ->> 'email') = 'admin@taiwan-subsidy.com');

drop policy if exists "f_admin_can_update" on public.f_subsidy_leads;
create policy "f_admin_can_update"
on public.f_subsidy_leads for update
to authenticated
using ((auth.jwt() ->> 'email') = 'admin@taiwan-subsidy.com')
with check ((auth.jwt() ->> 'email') = 'admin@taiwan-subsidy.com');

revoke all on public.f_subsidy_leads from anon, authenticated;
grant insert on public.f_subsidy_leads to anon;
grant select, update on public.f_subsidy_leads to authenticated;

-- F 项目独立的落地页配置，不读取或修改 A、B 项目的 site_settings。
create table if not exists public.f_site_settings (
  id integer primary key default 1 check (id = 1),
  line_url text not null default 'https://lin.ee/591VM3X',
  line_id text not null default '',
  pixel_ids jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

insert into public.f_site_settings (id, line_url, line_id, pixel_ids)
values (1, 'https://lin.ee/591VM3X', '', '[]'::jsonb)
on conflict (id) do nothing;

alter table public.f_site_settings enable row level security;

drop policy if exists "f_public_can_read_settings" on public.f_site_settings;
create policy "f_public_can_read_settings"
on public.f_site_settings for select
to anon
using (id = 1);

drop policy if exists "f_admin_can_read_settings" on public.f_site_settings;
create policy "f_admin_can_read_settings"
on public.f_site_settings for select
to authenticated
using ((auth.jwt() ->> 'email') = 'admin@taiwan-subsidy.com');

drop policy if exists "f_admin_can_update_settings" on public.f_site_settings;
create policy "f_admin_can_update_settings"
on public.f_site_settings for update
to authenticated
using ((auth.jwt() ->> 'email') = 'admin@taiwan-subsidy.com')
with check ((auth.jwt() ->> 'email') = 'admin@taiwan-subsidy.com');

revoke all on public.f_site_settings from anon, authenticated;
grant select on public.f_site_settings to anon, authenticated;
grant update on public.f_site_settings to authenticated;

-- F 项目多人投放系统。只扩展 F 专用表，现有订单统一归入 main。
create table if not exists public.f_pages (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  operator_note text not null default '',
  line_url text not null default '',
  line_id text not null default '',
  pixel_ids jsonb not null default '[]'::jsonb,
  password_hash text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint f_pages_slug_check check (slug = 'main' or slug ~ '^page[1-9][0-9]*$')
);

insert into public.f_pages (slug, operator_note, line_url, line_id, pixel_ids, active)
select 'main', '默认页面', line_url, line_id, pixel_ids, true
from public.f_site_settings where id = 1
on conflict (slug) do nothing;

alter table public.f_subsidy_leads add column if not exists page_slug text not null default 'main';
alter table public.f_subsidy_leads add column if not exists page_id uuid references public.f_pages(id) on delete set null;
update public.f_subsidy_leads l
set page_id = p.id
from public.f_pages p
where p.slug = l.page_slug and l.page_id is null;

create index if not exists f_subsidy_leads_page_created_idx
on public.f_subsidy_leads (page_slug, created_at desc);

create or replace function public.set_f_page_updated_at()
returns trigger language plpgsql security invoker set search_path = public as $$
begin new.updated_at = now(); return new; end;
$$;
drop trigger if exists set_f_page_updated_at on public.f_pages;
create trigger set_f_page_updated_at before update on public.f_pages
for each row execute function public.set_f_page_updated_at();

create or replace function public.assign_f_lead_page()
returns trigger language plpgsql security definer set search_path = public as $$
declare target public.f_pages%rowtype;
begin
  new.page_slug := coalesce(nullif(btrim(new.page_slug), ''), 'main');
  select * into target from public.f_pages where slug = new.page_slug and active = true;
  if target.id is null then raise exception 'page unavailable'; end if;
  new.page_id := target.id;
  return new;
end;
$$;
drop trigger if exists assign_f_lead_page on public.f_subsidy_leads;
create trigger assign_f_lead_page before insert or update of page_slug on public.f_subsidy_leads
for each row execute function public.assign_f_lead_page();

create or replace function public.f_master_ok()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(auth.jwt() ->> 'email', '') = 'admin@taiwan-subsidy.com';
$$;

create or replace function public.get_f_page_config(target_slug text)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((
    select jsonb_build_object('id',id,'slug',slug,'line_url',line_url,'line_id',line_id,'pixel_ids',pixel_ids,'active',active)
    from public.f_pages where slug = coalesce(nullif(btrim(target_slug),''),'main') and active = true
  ), '{}'::jsonb);
$$;

create or replace function public.f_page_login(target_slug text, page_password text)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists(
    select 1 from public.f_pages
    where slug = target_slug and active = true and password_hash is not null
      and password_hash = crypt(coalesce(page_password,''), password_hash)
  );
$$;

create or replace function public.get_f_master_pages()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare result jsonb;
begin
  if not public.f_master_ok() then raise exception 'not authorized'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'slug',slug,'operator_note',operator_note,'line_url',line_url,'line_id',line_id,
    'pixel_ids',pixel_ids,'active',active,'password_set',password_hash is not null,
    'created_at',created_at,'updated_at',updated_at
  ) order by case when slug='main' then 0 else substring(slug from 5)::int end), '[]'::jsonb)
  into result from public.f_pages;
  return result;
end;
$$;

create or replace function public.create_f_page(
  p_operator_note text, p_line_url text, p_line_id text, p_pixel_ids jsonb, p_password text
)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare next_number integer; new_page public.f_pages%rowtype;
begin
  if not public.f_master_ok() then raise exception 'not authorized'; end if;
  if length(coalesce(p_password,'')) < 6 then raise exception 'password too short'; end if;
  lock table public.f_pages in share row exclusive mode;
  select coalesce(max(substring(slug from 5)::integer),0)+1 into next_number
  from public.f_pages where slug ~ '^page[1-9][0-9]*$';
  insert into public.f_pages(slug,operator_note,line_url,line_id,pixel_ids,password_hash)
  values('page'||next_number,coalesce(p_operator_note,''),coalesce(p_line_url,''),coalesce(p_line_id,''),coalesce(p_pixel_ids,'[]'::jsonb),crypt(p_password,gen_salt('bf')))
  returning * into new_page;
  return to_jsonb(new_page)-'password_hash';
end;
$$;

create or replace function public.update_f_page(
  target_slug text, p_operator_note text, p_line_url text, p_line_id text,
  p_pixel_ids jsonb, p_active boolean, p_password text default null
)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.f_master_ok() then raise exception 'not authorized'; end if;
  if target_slug = 'main' and p_active = false then raise exception 'main page cannot be disabled'; end if;
  if nullif(p_password,'') is not null and length(p_password)<6 then raise exception 'password too short'; end if;
  update public.f_pages set operator_note=coalesce(p_operator_note,''),line_url=coalesce(p_line_url,''),
    line_id=coalesce(p_line_id,''),pixel_ids=coalesce(p_pixel_ids,'[]'::jsonb),active=coalesce(p_active,true),
    password_hash=case when nullif(p_password,'') is null then password_hash
      when length(p_password)>=6 then crypt(p_password,gen_salt('bf')) else password_hash end
  where slug=target_slug;
  if not found then raise exception 'page not found'; end if;
  if target_slug='main' then
    update public.f_site_settings set line_url=coalesce(p_line_url,''),line_id=coalesce(p_line_id,''),pixel_ids=coalesce(p_pixel_ids,'[]'::jsonb),updated_at=now() where id=1;
  end if;
  return true;
end;
$$;

create or replace function public.get_f_page_leads_page(
  target_slug text, page_password text, p_page integer default 1, p_page_size integer default 100,
  p_search text default null, p_status text default null, p_from timestamptz default null,
  p_to timestamptz default null, p_today_from timestamptz default null, p_today_to timestamptz default null
)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare safe_page integer:=greatest(coalesce(p_page,1),1); safe_size integer:=least(greatest(coalesce(p_page_size,100),1),1000); result jsonb;
begin
  if not public.f_page_login(target_slug,page_password) then raise exception 'invalid password'; end if;
  with scope as (
    select l.* from public.f_subsidy_leads l where l.page_slug=target_slug
      and (p_from is null or l.created_at>=p_from) and (p_to is null or l.created_at<p_to)
      and (nullif(btrim(p_search),'') is null or concat_ws(' ',l.name,l.phone,l.line_id,l.id_number,l.payout_bank,l.residence,l.apply_type,l.apply_amount) ilike '%'||btrim(p_search)||'%')
  ), filtered as (select * from scope where nullif(btrim(p_status),'') is null or status=btrim(p_status)),
  page_rows as (select * from filtered order by created_at desc,id desc limit safe_size offset (safe_page-1)*safe_size)
  select jsonb_build_object(
    'rows',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id desc) from page_rows r),'[]'::jsonb),
    'total',(select count(*) from filtered),
    'stats',jsonb_build_object('filtered',(select count(*) from filtered),'today',(select count(*) from scope where p_today_from is not null and p_today_to is not null and created_at>=p_today_from and created_at<p_today_to),'new',(select count(*) from scope where status='new'),'contacted',(select count(*) from scope where status='contacted'),'processing',(select count(*) from scope where status='processing'),'approved',(select count(*) from scope where status='approved'),'rejected',(select count(*) from scope where status='rejected'),'invalid',(select count(*) from scope where status='invalid'))
  ) into result;
  return result;
end;
$$;

create or replace function public.update_f_page_lead(
  target_slug text, page_password text, lead_id uuid, new_status text default null, new_notes text default null
)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not public.f_page_login(target_slug,page_password) then raise exception 'invalid password'; end if;
  if new_status is not null and new_status not in ('new','contacted','processing','approved','rejected','invalid') then raise exception 'invalid status'; end if;
  update public.f_subsidy_leads set status=coalesce(new_status,status),notes=coalesce(new_notes,notes)
  where id=lead_id and page_slug=target_slug;
  if not found then raise exception 'lead not found'; end if;
  return true;
end;
$$;

alter table public.f_pages enable row level security;
revoke all on public.f_pages from anon, authenticated;

drop policy if exists "f_public_can_submit" on public.f_subsidy_leads;
create policy "f_public_can_submit" on public.f_subsidy_leads for insert to anon
with check (status='new');

revoke all on function public.get_f_page_config(text) from public;
grant execute on function public.get_f_page_config(text) to anon, authenticated;
revoke all on function public.f_page_login(text,text) from public;
grant execute on function public.f_page_login(text,text) to anon, authenticated;
revoke all on function public.get_f_master_pages() from public;
grant execute on function public.get_f_master_pages() to authenticated;
revoke all on function public.create_f_page(text,text,text,jsonb,text) from public;
grant execute on function public.create_f_page(text,text,text,jsonb,text) to authenticated;
revoke all on function public.update_f_page(text,text,text,text,jsonb,boolean,text) from public;
grant execute on function public.update_f_page(text,text,text,text,jsonb,boolean,text) to authenticated;
revoke all on function public.get_f_page_leads_page(text,text,integer,integer,text,text,timestamptz,timestamptz,timestamptz,timestamptz) from public;
grant execute on function public.get_f_page_leads_page(text,text,integer,integer,text,text,timestamptz,timestamptz,timestamptz,timestamptz) to anon, authenticated;
revoke all on function public.update_f_page_lead(text,text,uuid,text,text) from public;
grant execute on function public.update_f_page_lead(text,text,uuid,text,text) to anon, authenticated;
