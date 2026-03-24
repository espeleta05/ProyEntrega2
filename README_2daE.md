# Segunda Entrega (Demo sin Base de Datos)

Esta carpeta contiene una version funcional visual del sistema en Flask + HTML, sin conexion a base de datos.

## Credenciales demo
- Usuario: `admin`
- Contrasena: `123`

## Que incluye
- Backend Flask con datos hardcodeados en memoria.
- HTML completos con sufijo `_2daE`.
- CSS copiados desde el proyecto original.
- Scripts SQL para PostgreSQL normalizados y con SP simples.

## Ejecutar
1. Crear y activar entorno virtual (opcional).
2. Instalar dependencias:
   - `pip install -r segunda_entrega/requirements_2daE.txt`
3. Ejecutar:
   - `python segunda_entrega/app_2daE.py`
4. Abrir:
   - `http://127.0.0.1:5000`

## Nota
Los registros se guardan solo en memoria del proceso. Al reiniciar Flask, vuelven a los valores de ejemplo.
