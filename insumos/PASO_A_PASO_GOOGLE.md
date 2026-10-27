# Planillas de Google → Supabase: instalación (opción B)

Una sola vez. Al terminar, Supabase lee las planillas cada 30 minutos sin intervención.
Nada de esto modifica las planillas: la cuenta técnica solo tiene permiso de lectura.

**Secretos:** la clave .json de Google, la clave `sb_secret_` y la URL de Healthchecks se cargan
directo en Supabase. Nunca se pegan en el chat ni se guardan en el repositorio.

## Parte 1 · Google Cloud (con leandrogiomprini@gmail.com)

1. Entrar a https://console.cloud.google.com con la cuenta **gmail** (no la de happyfood.com.ar).
   Aceptar los términos si los pide. No hace falta tarjeta.
2. Arriba a la izquierda, selector de proyecto → **Proyecto nuevo** → nombre `happyfood-datos` → **Crear**.
   Cuando termine, elegirlo en el selector.
3. En la barra de búsqueda de arriba escribir **Google Sheets API** → abrirla → **Habilitar**.
   Repetir con **Google Drive API** → **Habilitar**.
4. Menú ☰ → **IAM y administración** → **Cuentas de servicio** → **+ Crear cuenta de servicio**.
   Nombre: `supabase-lector` → **Crear y continuar** → en "Permisos" no elegir nada → **Continuar** → **Listo**.
5. En la lista, copiar el **email** de la cuenta nueva (termina en `.iam.gserviceaccount.com`).
   Se usa en la parte 2.
6. Entrar a la cuenta → pestaña **Claves** → **Agregar clave** → **Crear clave nueva** → **JSON** → **Crear**.
   Se descarga un archivo `.json`. Es la llave: no mandarlo por chat ni mail.

## Parte 2 · Compartir las planillas con la cuenta técnica (como Lector)

En cada archivo: **Compartir** → pegar el email del paso 5 → rol **Lector** → destildar **Notificar** → **Compartir**.
Si avisa que la cuenta es externa a la organización, confirmar.

| # | Planilla | Link |
|---|---|---|
| 1 | ConteoStockMPyEnvases | https://docs.google.com/spreadsheets/d/1hF4u7DKpaoNTH4y9Elo9kE4oNjNjHVpOmZh_saJ9lU8 |
| 2 | Happy Food - Compras R-COM02 | https://docs.google.com/spreadsheets/d/1RfFVytTdq_UyaIvVn-JoL3nYO391gaxRPPGyVWTOcjU |
| 3 | Happy Food - PRODUCCIÓN | https://docs.google.com/spreadsheets/d/1CZEC7YuURKd6JJKRHyXquVYY-ETB_DOEUT148EqawGA |
| 4 | Planificación de la producción semanal | https://docs.google.com/spreadsheets/d/1bmctylGk4K99Nc4e6s4kujyd-ztzbLR6ruzaLa701zs |
| 5 | Reporte de pedidos pendientes | https://docs.google.com/spreadsheets/d/1T1WdLnR6UTDRnlHLf57xYK8twYQ-e1AWODicytga2UY |
| 6 | Control de stock-KG | https://docs.google.com/spreadsheets/d/1Kv0DQjxqwH2zkEiKg1Izp1t-Jl2zuac2xi4ExRKcmQY |
| 7 | Happy Food - Pedidos | https://docs.google.com/spreadsheets/d/1Sr_ep7G2cpRSeH3YNMm0lzaFlHGuMk8Mio6qHb3Le_Q |
| 8 | Control Stock de Insumos.xlsx | https://drive.google.com/file/d/1sd7nyXZjGsot2TE91553eYVwPXCfoNbY |

Si en alguna no aparece la opción de compartir (2, 3 y 7 son de Jorge), pedirle a Jorge que lo haga.
Si la cuenta de happyfood.com.ar no deja compartir con cuentas externas (1, 4 y 8), se habilita en la
consola de administración de Google Workspace: Apps → Drive y Documentos → Configuración de uso compartido.

## Parte 3 · Supabase

1. **Clave para el reloj:** Project Settings → **API Keys** → sección Secret keys → **Add new secret key**
   → nombre `happyfood_cron` → crear → copiar el valor (`sb_secret_...`).
2. **Guardarla en el Vault:** SQL Editor → pestaña nueva → pegar, reemplazando el texto entre comillas:
   ```sql
   select vault.create_secret('PEGAR_ACA_LA_CLAVE_sb_secret', 'happyfood_cron_key');
   ```
   → **Run**. (Si la consulta queda guardada en el historial, borrar la pestaña después.)
3. **Llave de Google en la función:** Edge Functions → **Secrets** → **Add new secret**
   → Name `GOOGLE_SA_JSON` → Value: abrir el `.json` del paso 1.6 con TextEdit, **Cmd+A, Cmd+C** y pegar todo → **Save**.
4. **Publicar la función:** Edge Functions → **Deploy a new function** → **Via Editor** → nombre
   `happyfood-sync-hojas` → borrar el código de ejemplo y pegar todo `index.ts` → **Deploy function**.
   Después, en la función → **Details** → desactivar **Verify JWT with legacy secret** → **Save**
   (igual que en happyfood-sync y happyfood-sync-tablas).
5. **Base:** SQL Editor → pestaña nueva → pegar `012_hojas_google.sql` → **Run**.
6. **Primera lectura:** SQL Editor → `select hojas.disparar();` → **Run** (devuelve 19).
   Esperar un minuto y correr `select * from hojas.estado;`
   Cada pestaña tiene que tener `filas` > 0 y `ultimo_error` vacío. Si alguna tiene error, el texto dice qué hacer
   (falta compartir, o el nombre de la pestaña es otro y lista los nombres reales).
7. **Alerta:** en Healthchecks.io → **Add Check** → nombre "Hojas a Supabase" → Period 30 minutes, Grace 30 minutes
   → copiar su URL de ping → SQL Editor:
   ```sql
   select vault.create_secret('PEGAR_ACA_LA_URL_DE_HEALTHCHECKS', 'hc_hojas_url');
   ```
