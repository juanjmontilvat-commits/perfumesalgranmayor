-- =====================================================================
-- MOTOSA PERFUMES · CAJAS AL POR MAYOR · 01 ESTRUCTURA
-- Pégalo completo en Supabase > SQL Editor > New query > Run.
-- Se puede ejecutar más de una vez sin dañar nada.
-- Todas las tablas empiezan con "box_" para no chocar con tu tienda MOTOSA PARFUM.
-- =====================================================================

-- ---------- TABLAS ----------
create table if not exists public.box_admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.box_tiers (
  id          text primary key,                       -- essence | signature | prestige
  name        text not null,
  qty         int  not null check (qty > 0),          -- perfumes por caja
  markup      numeric(6,2) not null check (markup >= 0),      -- ganancia bruta por perfume ($)
  seller_rate numeric(5,4) not null check (seller_rate >= 0 and seller_rate <= 1),  -- comisión del vendedor
  sort        int  not null default 0
);

create table if not exists public.box_products (
  code       text primary key,                        -- PE-ARB-0001
  brand      text not null,
  name       text not null,
  gender     text not null check (gender in ('Mujer','Hombre','Unisex')),
  category   text not null check (category in ('Árabe','Diseñador')),
  set_label  text,
  is_luxury  boolean not null default false,
  cost       numeric(8,2) not null check (cost >= 0), -- PRIVADO: costo del proveedor
  available  boolean not null default true,
  features   text,
  photo_url  text,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.box_sellers (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique check (slug ~ '^[a-z0-9-]{2,40}$'),   -- se usa en el enlace ?v=slug
  name       text not null,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.box_orders (
  id                bigint generated always as identity primary key,
  order_code        text unique,                      -- MP-0001
  created_at        timestamptz not null default now(),
  tier_id           text not null references public.box_tiers(id),
  customer_first    text not null,
  customer_last     text not null,
  customer_state    text not null,
  seller_id         uuid references public.box_sellers(id),
  seller_name       text,                             -- lo que escribió el cliente o el nombre del vendedor
  total             numeric(10,2) not null default 0,
  cost_total        numeric(10,2) not null default 0,
  commission_rate   numeric(5,4) not null default 0,
  seller_commission numeric(10,2) not null default 0, -- se llena cuando el pedido está pagado
  status            text not null default 'nuevo'
                    check (status in ('nuevo','pagado','enviado','entregado','cancelado')),
  paid_at           timestamptz,
  notes             text
);

create table if not exists public.box_order_items (
  order_id     bigint not null references public.box_orders(id) on delete cascade,
  product_code text   not null references public.box_products(code),
  qty          int    not null check (qty > 0),
  unit_price   numeric(8,2) not null,
  unit_cost    numeric(8,2) not null,
  primary key (order_id, product_code)
);

create table if not exists public.box_reservations (   -- "apartados" de perfumes agotados
  id           bigint generated always as identity primary key,
  order_id     bigint not null references public.box_orders(id) on delete cascade,
  product_code text   not null references public.box_products(code)
);

create index if not exists box_orders_created_idx on public.box_orders (created_at desc);
create index if not exists box_orders_seller_idx  on public.box_orders (seller_id);

-- ---------- NIVELES (puedes cambiar markup y seller_rate cuando quieras) ----------
insert into public.box_tiers (id, name, qty, markup, seller_rate, sort) values
  ('essence',   'ESSENCE',   8,  6.00, 0.0800, 1),
  ('signature', 'SIGNATURE', 12, 5.00, 0.0800, 2),
  ('prestige',  'PRESTIGE',  24, 3.00, 0.0500, 3)
on conflict (id) do nothing;

-- ---------- QUIÉN ES ADMINISTRADOR ----------
create or replace function public.is_box_admin()
returns boolean
language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.box_admins where user_id = auth.uid()) $$;

-- ---------- FUNCIONES PÚBLICAS (lo que ve el cliente, sin costos) ----------
create or replace function public.box_catalog()
returns table (
  code text, brand text, name text, gender text, category text, set_label text,
  is_luxury boolean, available boolean, features text, photo_url text,
  price_essence numeric, price_signature numeric, price_prestige numeric
)
language sql stable security definer set search_path = public
as $$
  select p.code, p.brand, p.name, p.gender, p.category, p.set_label,
         p.is_luxury, p.available, p.features, p.photo_url,
         round(p.cost + e.markup, 2), round(p.cost + s.markup, 2), round(p.cost + r.markup, 2)
  from public.box_products p
  join public.box_tiers e on e.id = 'essence'
  join public.box_tiers s on s.id = 'signature'
  join public.box_tiers r on r.id = 'prestige'
  where p.active
$$;

create or replace function public.box_seller_by_slug(p_slug text)
returns table (slug text, name text)
language sql stable security definer set search_path = public
as $$ select s.slug, s.name from public.box_sellers s where s.active and s.slug = lower(btrim(p_slug)) $$;

-- ---------- CREAR PEDIDO (el servidor recalcula todo; no confía en el navegador) ----------
create or replace function public.create_box_order(
  p_tier text, p_first text, p_last text, p_state text,
  p_seller_slug text, p_seller_name text,
  p_items jsonb, p_reservations jsonb default '[]'::jsonb
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_tier    public.box_tiers%rowtype;
  v_seller  public.box_sellers%rowtype;
  v_prod    public.box_products%rowtype;
  v_id      bigint;
  v_code    text;
  r         record;
  v_qty     int := 0;
  v_total   numeric(10,2) := 0;
  v_cost    numeric(10,2) := 0;
  v_unit    numeric(8,2);
  v_lines   jsonb := '[]'::jsonb;
  v_res     jsonb := '[]'::jsonb;
  rc        text;
begin
  select * into v_tier from public.box_tiers where id = p_tier;
  if not found then raise exception 'Nivel de caja no válido'; end if;

  if coalesce(length(btrim(p_first)),0) = 0 or length(p_first) > 60 then raise exception 'Nombre no válido'; end if;
  if coalesce(length(btrim(p_last)),0)  = 0 or length(p_last)  > 60 then raise exception 'Apellido no válido'; end if;
  if coalesce(length(btrim(p_state)),0) = 0 or length(p_state) > 40 then raise exception 'Estado no válido'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'La caja está vacía'; end if;

  if p_seller_slug is not null and btrim(p_seller_slug) <> '' then
    select * into v_seller from public.box_sellers where active and slug = lower(btrim(p_seller_slug));
  end if;

  -- validar cantidad exacta de la caja antes de guardar nada
  select coalesce(sum(q), 0) into v_qty
  from (select sum(x.qty) q from jsonb_to_recordset(p_items) as x(code text, qty int) group by x.code) t;
  if v_qty <> v_tier.qty then
    raise exception 'La caja % lleva % perfumes y tu pedido tiene %', v_tier.name, v_tier.qty, v_qty;
  end if;

  insert into public.box_orders (tier_id, customer_first, customer_last, customer_state,
                                 seller_id, seller_name, commission_rate)
  values (p_tier, btrim(p_first), btrim(p_last), btrim(p_state),
          v_seller.id, left(coalesce(v_seller.name, btrim(p_seller_name)), 80),
          case when v_seller.id is null then 0 else v_tier.seller_rate end)
  returning id into v_id;

  for r in
    select x.code, sum(x.qty)::int as qty
    from jsonb_to_recordset(p_items) as x(code text, qty int)
    group by x.code
  loop
    if r.qty is null or r.qty < 1 or r.qty > v_tier.qty then raise exception 'Cantidad no válida'; end if;
    select * into v_prod from public.box_products where code = r.code and active;
    if not found then raise exception 'El perfume % no existe', r.code; end if;
    if not v_prod.available then raise exception '% % ya no está disponible', v_prod.brand, v_prod.name; end if;
    v_unit := round(v_prod.cost + v_tier.markup, 2);
    insert into public.box_order_items (order_id, product_code, qty, unit_price, unit_cost)
    values (v_id, v_prod.code, r.qty, v_unit, v_prod.cost);
    v_total := v_total + v_unit * r.qty;
    v_cost  := v_cost  + v_prod.cost * r.qty;
    v_lines := v_lines || jsonb_build_object('code', v_prod.code, 'brand', v_prod.brand,
                          'name', v_prod.name, 'qty', r.qty, 'unit_price', v_unit);
  end loop;

  if p_reservations is not null and jsonb_typeof(p_reservations) = 'array' then
    for rc in select distinct jsonb_array_elements_text(p_reservations) loop
      select * into v_prod from public.box_products where code = rc and active;
      if found then
        insert into public.box_reservations (order_id, product_code) values (v_id, v_prod.code);
        v_res := v_res || jsonb_build_object('brand', v_prod.brand, 'name', v_prod.name);
      end if;
    end loop;
  end if;

  v_code := 'MP-' || lpad(v_id::text, 4, '0');
  update public.box_orders set total = v_total, cost_total = v_cost, order_code = v_code where id = v_id;

  return jsonb_build_object('order_id', v_id, 'order_code', v_code, 'tier', v_tier.name,
                            'qty', v_tier.qty, 'total', v_total, 'items', v_lines, 'reservations', v_res);
end $$;

-- ---------- COMISIÓN Y FECHA DE PAGO AUTOMÁTICAS ----------
create or replace function public.box_orders_before_update()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.seller_id is distinct from old.seller_id then
    new.commission_rate := case when new.seller_id is null then 0
                           else coalesce((select seller_rate from public.box_tiers where id = new.tier_id), 0) end;
  end if;
  if new.status = 'pagado' and old.status is distinct from 'pagado' then
    new.paid_at := now();
  end if;
  if new.status in ('pagado','enviado','entregado') then
    new.seller_commission := round(new.total * new.commission_rate, 2);   -- se gana cuando el cliente ya pagó
  else
    new.seller_commission := 0;
  end if;
  return new;
end $$;

drop trigger if exists box_orders_before_update on public.box_orders;
create trigger box_orders_before_update before update on public.box_orders
  for each row execute function public.box_orders_before_update();

-- ---------- SEGURIDAD ----------
alter table public.box_admins       enable row level security;   -- sin políticas: nadie la toca desde la web
alter table public.box_tiers        enable row level security;
alter table public.box_products     enable row level security;
alter table public.box_sellers      enable row level security;
alter table public.box_orders       enable row level security;
alter table public.box_order_items  enable row level security;
alter table public.box_reservations enable row level security;

revoke all on public.box_admins, public.box_tiers, public.box_products, public.box_sellers,
              public.box_orders, public.box_order_items, public.box_reservations from anon;
revoke all on public.box_admins from authenticated;

do $$
declare t text;
begin
  foreach t in array array['box_tiers','box_products','box_sellers','box_orders','box_order_items','box_reservations'] loop
    execute format('drop policy if exists "solo administradores" on public.%I', t);
    execute format('create policy "solo administradores" on public.%I for all to authenticated
                    using (public.is_box_admin()) with check (public.is_box_admin())', t);
  end loop;
end $$;

revoke all on function public.is_box_admin()                      from public;
revoke all on function public.box_catalog()                       from public;
revoke all on function public.box_seller_by_slug(text)            from public;
revoke all on function public.create_box_order(text,text,text,text,text,text,jsonb,jsonb) from public;
grant execute on function public.is_box_admin()                   to anon, authenticated;
grant execute on function public.box_catalog()                    to anon, authenticated;
grant execute on function public.box_seller_by_slug(text)         to anon, authenticated;
grant execute on function public.create_box_order(text,text,text,text,text,text,jsonb,jsonb) to anon, authenticated;

-- ---------- FOTOS (bucket público de lectura; solo administradores suben) ----------
insert into storage.buckets (id, name, public)
values ('perfume-photos', 'perfume-photos', true)
on conflict (id) do update set public = true;

drop policy if exists "box fotos ver"       on storage.objects;
drop policy if exists "box fotos subir"     on storage.objects;
drop policy if exists "box fotos cambiar"   on storage.objects;
drop policy if exists "box fotos borrar"    on storage.objects;
create policy "box fotos ver"     on storage.objects for select to authenticated
  using (bucket_id = 'perfume-photos' and public.is_box_admin());
create policy "box fotos subir"   on storage.objects for insert to authenticated
  with check (bucket_id = 'perfume-photos' and public.is_box_admin());
create policy "box fotos cambiar" on storage.objects for update to authenticated
  using (bucket_id = 'perfume-photos' and public.is_box_admin());
create policy "box fotos borrar"  on storage.objects for delete to authenticated
  using (bucket_id = 'perfume-photos' and public.is_box_admin());
