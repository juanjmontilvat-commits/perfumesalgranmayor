# MOTOSA Cajas: paso a paso para publicar y ponerlo a rodar

Tiempo estimado: 45 a 60 minutos la primera vez. No necesitas instalar nada ni usar la terminal.

## Qué trae el paquete

```
MOTOSA_Cajas_Deploy/
├─ PASO_A_PASO.md                       ← esta guía
├─ sql/
│  ├─ 01_estructura.sql                 ← tablas, seguridad, funciones, bucket de fotos
│  ├─ 02_catalogo_77.sql                ← los 77 perfumes con su costo
│  └─ 03_administrador_y_vendedores.sql ← te da permiso de admin y crea vendedores
└─ web/
   ├─ index.html                        ← la tienda que ve el cliente
   ├─ admin.html                        ← tu panel (pedidos, catálogo, vendedores, precios)
   ├─ config.js                         ← aquí pegas los datos de Supabase (3 líneas)
   └─ logo.png
```

Cómo encaja todo: **Supabase** guarda el catálogo, las fotos y los pedidos. **GitHub** guarda los archivos de la web. **Cloudflare Pages** publica la web (gratis, reemplaza a Netlify). El cliente solo ve `index.html`; tú entras a `admin.html`.

Lo que el cliente **nunca** puede ver: tus costos, las comisiones ni los pedidos de otros. El servidor recalcula cada pedido por su cuenta, así que nadie puede cambiar precios desde el navegador.

---

## PARTE 1 · Supabase (base de datos y fotos)

### Paso 1. Crear el proyecto
Puedes usar el mismo proyecto de Supabase que ya tienes para MOTOSA PARFUM (las tablas de esta app empiezan con `box_` y no chocan con las tuyas). Si prefieres uno nuevo:
1. Entra a supabase.com e inicia sesión.
2. **New project**. Nombre: `motosa-cajas`. Escribe una contraseña de base de datos y guárdala.
3. Región: **East US (North Virginia)** o **South America (São Paulo)**. Espera 1 o 2 minutos a que cargue.

### Paso 2. Ejecutar el SQL (3 archivos, en orden)
1. En el menú izquierdo abre **SQL Editor**.
2. Pulsa **New query**.
3. Abre `sql/01_estructura.sql` con el Bloc de notas, copia **todo** y pégalo. Pulsa **Run**. Debe decir "Success. No rows returned".
4. Repite con `sql/02_catalogo_77.sql`. Al final muestra `perfumes_cargados: 77`.
5. **No ejecutes todavía el 03.** Primero el Paso 3.

Si algo sale mal, puedes volver a ejecutar el 01 y el 02 sin problema: no duplican nada.

### Paso 3. Crear tu usuario administrador
1. Menú izquierdo: **Authentication → Users → Add user → Create new user**.
2. Escribe tu correo y una contraseña fuerte. Marca **Auto Confirm User**. Crea el usuario.
3. Si tu socio George también debe entrar, crea otro usuario igual.
4. Vuelve a **SQL Editor → New query** y abre `sql/03_administrador_y_vendedores.sql`.
5. Cambia `CAMBIA-ESTE-CORREO@ejemplo.com` por el correo del usuario que creaste (puedes quitar el `--` de la línea de abajo para agregar al segundo).
6. Pulsa **Run**. Debe mostrar tu correo con el permiso "administrador".
7. Ese mismo archivo crea dos vendedores de ejemplo (Wuile y Gardimar). Cámbialos si quieres; luego los administras desde el panel.

### Paso 4. Copiar los dos datos de conexión
1. **Project Settings** (engranaje, abajo a la izquierda) → **API** (puede llamarse "API Keys" o "Data API").
2. Copia:
   - **Project URL**, parecida a `https://abcdefgh.supabase.co`.
   - La clave **anon public** (empieza con `eyJ...`).
3. **Nunca uses ni pegues la clave `service_role`.** Esa es secreta y da acceso total.

La clave `anon` sí puede ser pública: con las reglas de seguridad del SQL solo permite ver el catálogo sin costos y crear pedidos.

---

## PARTE 2 · Preparar los archivos de la web

### Paso 5. Pegar los datos en `config.js`
Abre `web/config.js` con el Bloc de notas y reemplaza:

```js
window.MOTOSA_CONFIG = {
  SUPABASE_URL: 'https://abcdefgh.supabase.co',
  SUPABASE_ANON_KEY: 'eyJ...tu clave anon...',
  WHATSAPP: '584241735215'
};
```
Guarda. El número de WhatsApp va con código de país, sin `+` ni espacios.

### Paso 6. Probar en tu computadora (opcional, 2 minutos)
Haz doble clic en `web/index.html`. Debe abrir la tienda con los 77 perfumes. Si ves arriba un aviso que dice "Modo demostración" o "No pudimos cargar el catálogo en línea", revisa el Paso 5.

---

## PARTE 3 · Publicar en internet

### Paso 7. Subir los archivos a GitHub
1. Entra a github.com → **New repository**. Nombre: `motosa-cajas`. Privado o público, como prefieras. Crea el repositorio.
2. En la página del repositorio vacío pulsa **uploading an existing file**.
3. Arrastra **el contenido de la carpeta `web`** (los 4 archivos: `index.html`, `admin.html`, `config.js`, `logo.png`). Deben quedar en la raíz del repositorio, no dentro de una carpeta.
4. Pulsa **Commit changes**.

(Los archivos de la carpeta `sql` no hace falta subirlos; guárdalos como respaldo.)

### Paso 8. Publicar con Cloudflare Pages
1. Crea una cuenta gratis en cloudflare.com.
2. Menú: **Workers & Pages → Create application → Pages → Connect to Git**. Autoriza GitHub y elige `motosa-cajas`.
3. Configuración:
   - Framework preset: **None**
   - Build command: **déjalo vacío**
   - Build output directory: **/** (o déjalo vacío)
4. Pulsa **Save and Deploy**. En un minuto te da una dirección como `motosa-cajas.pages.dev`.

Si no quieres usar GitHub: en Pages elige **Upload assets** (subir archivos) y arrastra la carpeta `web`.

Alternativas que funcionan igual con estos archivos: Vercel, o GitHub Pages (Settings → Pages). Netlify también cuando tengas crédito.

### Paso 9. Dominio propio
1. En el proyecto de Pages: **Custom domains → Set up a domain**.
2. Escribe el dominio o subdominio (por ejemplo `cajas.tudominio.com`) y sigue las instrucciones de DNS que muestra. Si el dominio lo compraste en otro lugar, solo debes agregar el registro `CNAME` que Cloudflare te indica.
3. Espera unos minutos y abre la dirección.

---

## PARTE 4 · Ponerlo a rodar

### Paso 10. Entrar al panel y cargar las fotos
1. Abre `https://tudominio.com/admin.html` e inicia sesión con el correo y la contraseña del Paso 3.
2. **Catálogo → Subir fotos en lote.** Cada archivo debe llamarse como el código del perfume, por ejemplo `PE-ARB-0001.jpg`. La lista de códigos está en el Catálogo del panel y en el CSV. Las fotos se ajustan solas a un cuadro blanco de estudio. Cuanto más limpia esté la foto con fondo blanco, mejor se ve.
3. También puedes tocar el cuadro de foto de un perfume para subir solo esa.
4. En el mismo Catálogo revisa el **género** de cada perfume (algunos se dedujeron del nombre), escribe las **características** (notas, tamaño) y marca **Disponible** o no.

### Paso 11. Crear tus vendedores y sus enlaces
1. Pestaña **Vendedores**: escribe el nombre y se genera el código del enlace.
2. Cada vendedor comparte **su** enlace, por ejemplo `https://cajas.tudominio.com/?v=wuile`.
3. Quien entre por ese enlace queda asignado a ese vendedor, no puede cambiarlo y la comisión se calcula bien. Quien entre sin enlace puede escribir el nombre del vendedor; esos pedidos aparecen "sin enlazar" y tú eliges el vendedor correcto en el panel.

### Paso 12. Hacer un pedido de prueba completo
1. Abre la tienda desde un celular, arma una caja Essence con 8 perfumes y envía el pedido.
2. Debe aparecer "Pedido MP-0001 guardado" y el botón para abrir WhatsApp.
3. En el panel, pestaña **Pedidos**: verás el pedido como **nuevo**.
4. Cámbialo a **pagado**: la comisión del vendedor aparece sola y las tarjetas de arriba (ventas cobradas, comisiones, ganancia neta) se actualizan.
5. Para borrar el pedido de prueba: en Supabase, **Table Editor → box_orders**, selecciona la fila y bórrala.

### Paso 13. Cómo funciona el día a día
- **Cliente** arma la caja y envía; el pedido se guarda con su número (MP-0001, MP-0002…) y llega por WhatsApp al número configurado.
- **Tú** confirmas el pago y pasas el pedido por los estados: nuevo → pagado → enviado → entregado. Puedes anotar notas (guía de envío, referencia de pago).
- **Comisión:** se calcula sola cuando el pedido pasa a **pagado** (8% en Essence y Signature, 5% en Prestige). Si lo devuelves a "nuevo" o lo cancelas, vuelve a 0. La pestaña Pedidos suma lo que debes pagar a cada vendedor.
- **Agotados:** desmarca "Disponible" en el Catálogo. El cliente verá el perfume en gris con el botón "Apartar".
- **Cambiar precios o comisiones:** pestaña **Precios**. El precio de venta es costo + ganancia por perfume. Cambia los valores y guarda; aplica desde el siguiente pedido. Para cambiar el costo de un perfume, edítalo en el Catálogo.
- **Agregar perfumes nuevos:** Catálogo → **Agregar perfume** (código, marca, nombre, género, categoría, costo). Después sube su foto.

---

## Si algo falla

| Qué ves | Qué significa | Qué hacer |
|---|---|---|
| Aviso "Modo demostración" en la tienda | `config.js` sigue con los datos de ejemplo | Repite el Paso 5 y vuelve a subir el archivo a GitHub |
| Aviso "No pudimos cargar el catálogo en línea" | Falta ejecutar el 01 o el 02, o el proyecto está pausado | Revisa que los SQL corrieron; en Supabase pulsa "Restore project" si está pausado |
| En el panel: "Sin permiso" | Tu correo no está en administradores | Repite el Paso 3, punto 5 y 6 con el mismo correo |
| En el panel: "Correo o contraseña incorrectos" | Usuario mal creado | Authentication → Users: restablece la contraseña |
| Al subir fotos: error de permiso | El usuario no es administrador o falta el bucket | Ejecuta de nuevo el 01 y el 03 |
| Un cliente ve "ya no está disponible" al enviar | Alguien lo marcó agotado mientras armaba su caja | Es normal; la tienda lo quita de su caja y le pide elegir otro |
| Cambié `config.js` y no se nota | Caché del navegador | Recarga forzada (Ctrl + Shift + R) |

## Lo que debes tener en cuenta

1. **Plan gratuito de Supabase:** el proyecto se pausa si pasa una semana sin actividad y no incluye respaldos automáticos. Si la tienda va a ser tu negocio real, evalúa el plan Pro, y descarga los pedidos periódicamente (Table Editor → box_orders → Export to CSV).
2. **Contraseña de administrador:** usa una fuerte y no la compartas por WhatsApp. Si un socio sale del negocio, borra su usuario en Authentication.
3. **Spam:** cualquier persona con el enlace puede crear pedidos. Si empiezas a recibir pedidos falsos, avísame y agregamos una verificación anti-robots.
4. **Cantidades de las cajas (8, 12, 24):** viven en `index.html` (constante `TIERS`) y en la tabla `box_tiers`. Si algún día las cambias, hay que actualizar los dos lugares.
5. **Compartir inventario con MOTOSA PARFUM:** más adelante se puede apuntar esta tienda a la misma tabla de productos. Es un trabajo aparte; la estructura está pensada para eso.

## Para actualizar la web después
En GitHub, abre el archivo (por ejemplo `index.html`) → lápiz de editar → cambia → **Commit changes**. Cloudflare publica la nueva versión solo en uno o dos minutos.
