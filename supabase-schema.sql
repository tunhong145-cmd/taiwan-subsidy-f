-- F 项目独立订单表。此脚本可重复执行，不修改 subsidy_leads 或任何其他表。
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
