-- CRAVA Admin V1 migration
-- Run this file once in Supabase SQL Editor AFTER supabase_setup_v8.sql.

create extension if not exists pgcrypto;

alter table public.boxes add column if not exists activation_code_hash text;
alter table public.boxes add column if not exists sold_at timestamptz;
alter table public.boxes add column if not exists activation_created_at timestamptz;

-- Useful indexes for the admin panel.
create index if not exists boxes_status_idx on public.boxes(status);
create index if not exists boxes_sold_at_idx on public.boxes(sold_at desc);
create index if not exists boxes_claimed_at_idx on public.boxes(claimed_at desc);
create index if not exists profiles_xp_idx on public.profiles(xp desc);
create index if not exists profiles_box_count_idx on public.profiles(box_count desc);

-- Marks one physical box as sold and creates a fresh one-time activation code.
create or replace function public.admin_sell_box(p_box_number integer)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  b public.boxes;
  raw_code text;
begin
  if not public.is_current_user_admin() then
    raise exception 'ACCESS DENIED';
  end if;

  select * into b from public.boxes where box_number=p_box_number for update;
  if not found then
    return jsonb_build_object('ok',false,'reason','BOX NOT FOUND');
  end if;
  if b.status='claimed' then
    return jsonb_build_object('ok',false,'reason','BOX ALREADY ACTIVATED BY A CUSTOMER');
  end if;
  if b.status='active' and b.activation_code_hash is not null then
    return jsonb_build_object('ok',false,'reason','BOX ALREADY SOLD');
  end if;

  raw_code := upper(substr(encode(gen_random_bytes(6),'hex'),1,4) || '-' || substr(encode(gen_random_bytes(6),'hex'),1,4));

  update public.boxes
     set status='active',
         activation_code_hash=crypt(raw_code,gen_salt('bf')),
         sold_at=now(),
         activated_at=now(),
         activation_created_at=now()
   where id=b.id;

  return jsonb_build_object(
    'ok',true,
    'box_number',p_box_number,
    'box_code','CRV' || lpad(p_box_number::text,6,'0'),
    'activation_code',raw_code,
    'status','sold_waiting_activation'
  );
end $$;

-- Customer claims a sold box by entering only the activation code.
create or replace function public.claim_crava_activation_code(p_activation_code text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  b public.boxes;
  p public.profiles;
  normalized text;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok',false,'reason','SIGN IN REQUIRED');
  end if;

  normalized := upper(trim(p_activation_code));
  if normalized !~ '^[A-F0-9]{4}-[A-F0-9]{4}$' then
    return jsonb_build_object('ok',false,'reason','INVALID ACTIVATION CODE');
  end if;

  select * into b
    from public.boxes
   where status='active'
     and activation_code_hash is not null
     and crypt(normalized,activation_code_hash)=activation_code_hash
   for update;

  if not found then
    return jsonb_build_object('ok',false,'reason','INVALID OR USED ACTIVATION CODE');
  end if;

  update public.boxes
     set status='claimed',
         claimed_by=auth.uid(),
         claimed_at=now(),
         activation_code_hash=null
   where id=b.id;

  update public.profiles
     set box_count=box_count+1,
         xp=xp+100
   where id=auth.uid()
   returning * into p;

  insert into public.user_badges(user_id,badge_key)
  values(auth.uid(),'first_box') on conflict do nothing;
  if p.box_count>=3 then insert into public.user_badges(user_id,badge_key) values(auth.uid(),'collector_3') on conflict do nothing; end if;
  if p.box_count>=10 then insert into public.user_badges(user_id,badge_key) values(auth.uid(),'collector_10') on conflict do nothing; end if;
  if p.box_count>=25 then insert into public.user_badges(user_id,badge_key) values(auth.uid(),'collector_25') on conflict do nothing; end if;
  if p.box_count>=50 then insert into public.user_badges(user_id,badge_key) values(auth.uid(),'collector_50') on conflict do nothing; end if;

  return jsonb_build_object(
    'ok',true,
    'box_id',b.id,
    'box_number',b.box_number,
    'box_code','CRV' || lpad(b.box_number::text,6,'0'),
    'box_count',p.box_count,
    'xp',p.xp,
    'points_awarded',100,
    'rarity',b.rarity
  );
end $$;

create or replace function public.admin_dashboard_v1()
returns jsonb
language sql
security definer
set search_path=public
as $$
select case when public.is_current_user_admin() then jsonb_build_object(
  'total_users',(select count(*) from public.profiles),
  'total_boxes',(select count(*) from public.boxes),
  'sold_boxes',(select count(*) from public.boxes where status in('active','claimed')),
  'unsold_boxes',(select count(*) from public.boxes where status='not_released'),
  'waiting_activation',(select count(*) from public.boxes where status='active'),
  'activated_boxes',(select count(*) from public.boxes where status='claimed'),
  'distributed_points',(select coalesce(sum(xp),0) from public.profiles)
) else null end
$$;

create or replace function public.admin_list_boxes_v1(p_search text default null,p_limit integer default 100)
returns table(
  box_number integer,
  box_code text,
  display_status text,
  sold_at timestamptz,
  claimed_at timestamptz,
  owner_name text
)
language sql
security definer
set search_path=public
as $$
  select b.box_number,
         'CRV' || lpad(b.box_number::text,6,'0') as box_code,
         case b.status when 'not_released' then 'unsold' when 'active' then 'sold_waiting_activation' else 'activated' end,
         b.sold_at,
         b.claimed_at,
         p.display_name
    from public.boxes b
    left join public.profiles p on p.id=b.claimed_by
   where public.is_current_user_admin()
     and (coalesce(trim(p_search),'')='' or b.box_number::text like '%' || regexp_replace(p_search,'\D','','g') || '%')
   order by b.box_number desc
   limit least(greatest(p_limit,1),500)
$$;

create or replace function public.admin_list_users_v1(p_limit integer default 100)
returns table(
  id uuid,
  display_name text,
  member_number bigint,
  points integer,
  owned_boxes integer,
  last_activation timestamptz,
  created_at timestamptz
)
language sql
security definer
set search_path=public
as $$
  select p.id,p.display_name,p.member_number,p.xp,p.box_count,
         max(b.claimed_at) as last_activation,p.created_at
    from public.profiles p
    left join public.boxes b on b.claimed_by=p.id
   where public.is_current_user_admin()
   group by p.id,p.display_name,p.member_number,p.xp,p.box_count,p.created_at
   order by p.xp desc,p.box_count desc,p.created_at desc
   limit least(greatest(p_limit,1),500)
$$;

grant execute on function public.admin_sell_box(integer) to authenticated;
grant execute on function public.claim_crava_activation_code(text) to authenticated;
grant execute on function public.admin_dashboard_v1() to authenticated;
grant execute on function public.admin_list_boxes_v1(text,integer) to authenticated;
grant execute on function public.admin_list_users_v1(integer) to authenticated;
