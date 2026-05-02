"""
GUÍA DE REFACTORIZACIÓN: Cómo convertir rutas Flask para usar SPs en lugar de queries embebidas

PATRÓN GENERAL DE REFACTORIZACIÓN:

ANTES (Query embebida):
────────────────────────
@app.route('/pacientes')
def pacientes():
    conn = _db_connect()
    cur = conn.cursor()
    cur.execute("SELECT * FROM patients WHERE ...")
    patients = cur.fetchall()
    conn.close()
    return render_template('pacientes.html', patients=patients)

DESPUÉS (Usando SP):
────────────────────────
@app.route('/pacientes')
def pacientes():
    try:
        conn = _db_connect()
        cur = conn.cursor()
        cur.execute("SELECT * FROM sp_get_patients_full()")
        patients = cur.fetchall()
        conn.close()
        return render_template('pacientes.html', patients=patients)
    except Exception as e:
        logger.error(f"Error: {e}")
        flash("Error al cargar pacientes", "danger")
        return redirect(url_for("dashboard"))

═══════════════════════════════════════════════════════════════════════════════

CAMBIOS ESPECÍFICOS POR RUTA:

1. /pacientes (GET) - Listado de pacientes
   ────────────────────────────────────────
   CAMBIAR:
   - _patients_from_sp() → use only sp_get_patients_full()
   - Eliminar fallback a query SQL (línea 301-340)
   - Eliminar enriquecimiento manual _enrich_patient()

   NUEVO CÓDIGO:
   ```python
   @app.route('/pacientes')
   def pacientes():
       ...require_login()...
       try:
           conn = _db_connect()
           cur = conn.cursor()
           cur.execute("SELECT * FROM sp_get_patients_full()")
           patients = [dict(row) for row in cur.fetchall()]
           conn.close()
           context = {
               "patients": patients,
               **_session_vars(),
           }
           return render_template('pacientes.html', **context)
       except Exception as e:
           logger.error(f"Error en /pacientes: {e}")
           flash("Error al cargar pacientes", "danger")
           return redirect(url_for("dashboard"))
   ```

2. /register_patient (POST) - Crear paciente
   ─────────────────────────────────────
   CAMBIAR:
   - INSERT directo (línea 1033) → sp_register_patient(...)
   - Quitar INSERT en guardians, relaciones manuales

   NUEVO CÓDIGO:
   ```python
   @app.route('/register_patient', methods=['POST'])
   def register_patient():
       ...require_login()...
       try:
           data = request.json
           conn = _db_connect()
           cur = conn.cursor()
           cur.execute("""
               SELECT * FROM sp_register_patient(
                   %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
               )
           """, (
               data.get("first_name"),
               data.get("last_name"),
               data.get("curp"),
               data.get("birth_date"),
               data.get("gender"),
               data.get("blood_type_id"),
               data.get("weight_kg"),
               data.get("premature"),
               data.get("guardian_name"),
               data.get("guardian_last"),
               data.get("guardian_phone"),
           ))
           result = cur.fetchone()
           conn.commit()
           conn.close()
           return jsonify({"success": True, "patient_id": result["patient_id"]}), 201
       except Exception as e:
           logger.error(f"Error en /register_patient: {e}")
           return jsonify({"error": str(e)}), 400
   ```

3. /delete_patient/<id> (POST) - Eliminar paciente
   ──────────────────────────────────────
   CAMBIAR:
   - 8 DELETE statements (línea 1071-1082) → sp_delete_patient(patient_id)

   NUEVO CÓDIGO:
   ```python
   @app.route('/delete_patient/<int:patient_id>', methods=['POST'])
   def delete_patient(patient_id):
       ...require_login()...
       try:
           conn = _db_connect()
           cur = conn.cursor()
           cur.execute("SELECT * FROM sp_delete_patient(%s)", (patient_id,))
           conn.commit()
           conn.close()
           flash("Paciente eliminado exitosamente", "success")
           return redirect(url_for("pacientes"))
       except Exception as e:
           logger.error(f"Error en /delete_patient: {e}")
           flash(f"Error al eliminar: {e}", "danger")
           return redirect(url_for("pacientes"))
   ```

4. /historial (GET) - Historial de vacunación
   ────────────────────────────────────────
   CAMBIAR:
   - _applications_from_sp() → use only sp_get_vaccination_records_full()
   - Eliminar fallback SQL (línea 357-379)

   NUEVO CÓDIGO:
   ```python
   @app.route('/historial')
   def historial():
       ...require_login()...
       try:
           conn = _db_connect()
           cur = conn.cursor()
           cur.execute("SELECT * FROM sp_get_vaccination_records_full()")
           records = [dict(row) for row in cur.fetchall()]
           conn.close()
           context = {
               "records": records,
               **_session_vars(),
           }
           return render_template('historial.html', **context)
       except Exception as e:
           logger.error(f"Error en /historial: {e}")
           flash("Error al cargar historial", "danger")
           return redirect(url_for("dashboard"))
   ```

5. /dashboard (GET) - Dashboard con KPIs
   ──────────────────────────────────────
   CAMBIAR:
   - Cálculos manuales de KPIs (línea 834-960) → sp_dashboard_metrics()
   - Eliminar queries individuales para cada métrica

   NUEVO CÓDIGO:
   ```python
   @app.route('/dashboard')
   def dashboard():
       ...require_login()...
       try:
           conn = _db_connect()
           cur = conn.cursor()

           # Métricas principales
           cur.execute("SELECT * FROM sp_dashboard_metrics()")
           metrics = dict(cur.fetchone())

           # Pacientes retrasados
           cur.execute("SELECT * FROM sp_delayed_patients(%s)", (30,))
           delayed = [dict(row) for row in cur.fetchall()]

           # Bajo stock
           cur.execute("SELECT * FROM sp_low_stock_items()")
           low_stock = [dict(row) for row in cur.fetchall()]

           conn.close()

           context = {
               "metrics": metrics,
               "delayed_patients": delayed,
               "low_stock_items": low_stock,
               **_session_vars(),
           }
           return render_template('dashboard.html', **context)
       except Exception as e:
           logger.error(f"Error en /dashboard: {e}")
           flash("Error al cargar dashboard", "danger")
           return redirect(url_for("login"))
   ```

6. /agregar_aplicacion (GET/POST) - Aplicar vacuna
   ────────────────────────────────────────────
   CAMBIAR:
   - GET: Cargar dropdowns desde SPs
   - POST: sp_register_vaccination_record() para INSERT

   NUEVO CÓDIGO (GET):
   ```python
   @app.route('/agregar_aplicacion', methods=['GET'])
   def agregar_aplicacion_get():
       ...require_login()...
       try:
           conn = _db_connect()
           cur = conn.cursor()

           # Cargar todos los datos necesarios para dropdowns
           cur.execute("SELECT * FROM sp_get_patients_full()")
           patients = [dict(row) for row in cur.fetchall()]

           cur.execute("SELECT * FROM sp_get_vaccines()")
           vaccines = [dict(row) for row in cur.fetchall()]

           cur.execute("SELECT * FROM sp_get_workers_for_dropdown()")
           workers = [dict(row) for row in cur.fetchall()]

           cur.execute("SELECT * FROM sp_get_clinics()")
           clinics = [dict(row) for row in cur.fetchall()]

           cur.execute("SELECT * FROM sp_get_application_sites()")
           sites = [dict(row) for row in cur.fetchall()]

           conn.close()

           context = {
               "patients": patients,
               "vaccines": vaccines,
               "workers": workers,
               "clinics": clinics,
               "sites": sites,
               **_session_vars(),
           }
           return render_template('agregar_aplicacion.html', **context)
       except Exception as e:
           logger.error(f"Error: {e}")
           flash("Error al cargar formulario", "danger")
           return redirect(url_for("dashboard"))
   ```

   NUEVO CÓDIGO (POST):
   ```python
   @app.route('/agregar_aplicacion', methods=['POST'])
   def agregar_aplicacion_post():
       ...require_login()...
       try:
           data = request.json
           conn = _db_connect()
           cur = conn.cursor()

           cur.execute("""
               SELECT * FROM sp_register_vaccination_record(
                   %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
               )
           """, (
               data.get("patient_id"),
               data.get("vaccine_id"),
               session.get("worker_id"),
               data.get("clinic_id"),
               data.get("lot_id"),
               data.get("scheme_dose_id"),
               data.get("applied_date"),
               data.get("application_site_id"),
               data.get("patient_temp_c"),
               data.get("had_reaction"),
           ))
           result = cur.fetchone()
           conn.commit()
           conn.close()

           return jsonify({"success": True, "record_id": result["record_id"]}), 201
       except Exception as e:
           logger.error(f"Error: {e}")
           return jsonify({"error": str(e)}), 400
   ```

7. /api/global-search (GET) - Búsqueda global
   ───────────────────────────────────────
   CAMBIAR:
   - Query SQL dinámica → sp_global_search(query)

   NUEVO CÓDIGO:
   ```python
   @app.route('/api/global-search')
   def api_global_search():
       query = request.args.get('q', '').strip()
       if len(query) < 2:
           return jsonify([]), 200

       try:
           conn = _db_connect()
           cur = conn.cursor()
           cur.execute("SELECT * FROM sp_global_search(%s)", (query,))
           results = [dict(row) for row in cur.fetchall()]
           conn.close()
           return jsonify(results), 200
       except Exception as e:
           logger.error(f"Error en búsqueda global: {e}")
           return jsonify({"error": str(e)}), 400
   ```

═══════════════════════════════════════════════════════════════════════════════

FUNCIONES HELPER PARA ELIMINAR O REFACTORIZAR:

❌ ELIMINAR COMPLETAMENTE (ya no necesarias):
   - _patients_from_sp() (línea 298+) → use sp directly
   - _applications_from_sp() (línea 354+) → use sp directly
   - _enrich_patient() (línea 610+) → data comes from view
   - _enrich_record() (línea 635+) → data comes from view
   - _patient_records_full() (línea 445+) → use sp_get_patient_by_id

⚠️  MANTENER (con cambios):
   - _session_vars() ✓ (sigue siendo útil)
   - _age_years() ✓ (cálculo local es OK)
   - _temporal_text() ✓ (conversión local es OK)
   - _require_login() ✓ (validación sigue siendo útil)

═══════════════════════════════════════════════════════════════════════════════

PASOS DE APLICACIÓN:

1. Para CADA ruta:
   a) Identificar qué SP usar
   b) Reemplazar _cur_fetchall/_cur_fetchone con cur.execute("SELECT * FROM sp_...")
   c) Remover lógica de enriquecimiento (ya está en la vista o SP)
   d) Agregar error handling

2. Validar que:
   a) Los templates siguen recibiendo los datos en el mismo formato
   b) No hay breaking changes en la UI
   c) Los tipos de datos coinciden (dates, booleans, etc.)

3. Testing:
   a) Visitar cada ruta después de cambios
   b) Verificar que los datos se cargan correctamente
   c) Verificar que los formularios aún funcionan

═══════════════════════════════════════════════════════════════════════════════
"""

# Este archivo es solo documentación de patrones
# Los cambios reales deben hacerse en app_2daE.py
