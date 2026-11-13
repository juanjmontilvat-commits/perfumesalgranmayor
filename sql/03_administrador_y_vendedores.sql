-- =====================================================================
-- MOTOSA PERFUMES · CAJAS AL POR MAYOR · 03 ADMINISTRADORES Y VENDEDORES
-- 1) Primero crea tu usuario en Supabase > Authentication > Users > Add user
--    (correo + contraseña, marca "Auto Confirm User").
-- 2) Cambia los correos de abajo por los tuyos y ejecuta.
-- =====================================================================

-- Dar permiso de administrador (pon el correo con el que creaste el usuario)
insert into public.box_admins (user_id)
select id from auth.users
where lower(email) in (
  'CAMBIA-ESTE-CORREO@ejemplo.com'
  -- , 'otro-socio@ejemplo.com'
)
on conflict do nothing;

select u.email, 'administrador' as permiso
from public.box_admins a join auth.users u on u.id = a.user_id;

-- Vendedores de ejemplo (cambia nombre y slug; el enlace será  tudominio.com/?v=slug)
insert into public.box_sellers (slug, name) values
  ('wuile',    'Wuile'),
  ('gardimar', 'Gardimar')
on conflict (slug) do nothing;
