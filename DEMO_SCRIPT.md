# Script de Demo — ImmuniCare Sistema de Vacunación
**Duración estimada:** 8-10 minutos  
**Herramienta sugerida:** OBS Studio o Loom  
**Resolución:** 1920×1080, navegador en pantalla completa

---

## ANTES DE GRABAR

- Tener el servidor corriendo: `python app_2daE.py`
- Abrir el navegador en `http://localhost:5000`
- Tener abierta una segunda pestaña con `/tutor/login`
- Limpiar el historial del navegador para que no aparezcan autocompletados
- Tener listo un paciente de prueba registrado (ej. "Sofía Ramírez", 4 años)

---

## ESCENA 1 — Introducción (0:00 – 0:30)

**Pantalla:** Página de inicio `/`

> "ImmuniCare es un sistema de gestión de vacunación pediátrica que integra
> PostgreSQL, MongoDB, NFC y generación de documentos PDF.
> Vamos a recorrer el flujo completo de una jornada de vacunación,
> desde que el paciente llega a la clínica hasta que se emite su comprobante."

---

## ESCENA 2 — Login por roles (0:30 – 1:00)

**Pantalla:** `/login`

> "El sistema tiene cinco roles diferenciados: Administrador, Médico,
> Enfermero, Recepcionista y Almacén. Cada uno ve únicamente
> las secciones que le corresponden."

- Escribe las credenciales del **Administrador** y presiona Entrar
- Muestra brevemente el menú completo que tiene disponible

---

## ESCENA 3 — Dashboard con KPIs en tiempo real (1:00 – 2:00)

**Pantalla:** `/dashboard`

> "El dashboard ejecuta el SP sp_dashboard_kpis y muestra métricas
> en tiempo real: total de pacientes activos, porcentaje de cobertura
> de esquema completo, dosis atrasadas y alertas de stock."

- Señala los 4 KPI cards en la parte superior
- Desplázate hacia las gráficas

> "Las gráficas muestran dosis aplicadas por grupo de edad,
> tendencia mensual de aplicaciones y las vacunas con mayor retraso.
> Todos estos datos se calculan directamente desde PostgreSQL
> y se complementan con agregaciones de MongoDB."

- Señala la gráfica de dosis por grupo de edad
- Señala la gráfica de tendencia mensual

---

## ESCENA 4 — Registro de paciente y tutor (2:00 – 3:00)

**Pantalla:** `/pacientes` → botón "Nuevo paciente"

> "Registramos a un nuevo paciente pediátrico.
> El sistema vincula automáticamente al tutor principal —
> padre, madre o responsable legal — mediante la tabla
> patient_guardian_relations con el campo is_primary."

- Llena el formulario con datos de prueba (nombre, fecha de nacimiento, CURP)
- Llena los datos del tutor (nombre, teléfono, correo)
- Haz clic en Guardar
- Muestra la ficha del paciente recién creado

---

## ESCENA 5 — Asignación de tarjeta NFC (3:00 – 3:30)

**Pantalla:** Ficha del paciente → sección NFC

> "Cada paciente puede tener una tarjeta NFC física.
> Al asignarla, el sistema vincula el UID del chip
> con el patient_id en la base de datos."

- Muestra el campo de asignación NFC
- Ingresa un UID de prueba y guarda

> "Esta tarjeta le permitirá al tutor hacer check-in
> en recepción simplemente acercándola al lector."

---

## ESCENA 6 — Esquema vacunal del paciente (3:30 – 4:30)

**Pantalla:** `/esquema_paciente/<id>`

> "El sistema genera automáticamente el esquema de vacunación
> personalizado según la edad del paciente.
> La vista v_patient_vaccination_scheme_base calcula el estado
> de cada dosis: Aplicada, Pendiente o Atrasada."

- Señala las dosis en verde (Aplicada)
- Señala las dosis en rojo o naranja (Atrasada / Pendiente)

> "Las dosis atrasadas se resaltan visualmente para que
> el personal clínico priorice su aplicación."

---

## ESCENA 7 — Aplicación de una dosis con validaciones clínicas (4:30 – 5:45)

**Pantalla:** `/agregar_aplicacion`

> "Ahora aplicamos una vacuna. El SP sp_apply_vaccine
> ejecuta automáticamente cuatro validaciones antes de registrar la dosis."

- Selecciona el paciente "Sofía Ramírez"
- Selecciona la vacuna
- Selecciona el lote

> "Primero verifica que el paciente tenga la edad mínima requerida.
> Segundo, que haya pasado el intervalo mínimo desde la dosis anterior.
> Tercero, que el lote no esté vencido.
> Cuarto, que la temperatura de conservación sea correcta."

- Completa el formulario y guarda

> "Al registrarse la dosis, el sistema actualiza el inventario del lote
> en PostgreSQL y sincroniza el registro a MongoDB en la colección
> historial_vacunacion para análisis posteriores."

---

## ESCENA 8 — Comprobante PDF con código QR (5:45 – 6:30)

**Pantalla:** Cambia al login de tutor `/tutor/login`

> "El tutor tiene su propio portal. Iniciamos sesión
> con sus credenciales para ver lo que él ve."

- Inicia sesión como tutor
- Navega a la ficha del paciente → Historial

> "El tutor puede descargar el comprobante de vacunación en PDF.
> El sistema lo genera con ReportLab: incluye los datos del paciente,
> la vacuna, el lote, la temperatura de conservación
> y un código QR de verificación."

- Haz clic en "Descargar comprobante"
- Muestra el PDF generado
- Acerca el zoom al código QR

> "El QR contiene la firma digital del registro
> en formato IMMUNICARE://VERIFY para verificación externa."

---

## ESCENA 9 — Reportes públicos (6:30 – 7:30)

**Pantalla:** Regresa al login de Admin → `/reportes-publicos`

> "El módulo de reportes públicos muestra cobertura vacunal
> agregada por municipio y zona geográfica.
> Los datos combinan consultas de PostgreSQL con agregaciones
> de la colección historial_vacunacion de MongoDB."

- Señala el mapa o gráfica de cobertura geográfica
- Señala los KPIs del reporte (total de dosis, población alcanzada, cobertura %)

> "Estas métricas permiten a las autoridades de salud
> identificar zonas con baja cobertura y dirigir campañas."

---

## ESCENA 10 — Inventario y alertas de stock (7:30 – 8:15)

**Pantalla:** `/almacen/dashboard` o `/almacen/lotes`

> "El módulo de almacén controla los lotes de vacunas.
> El sistema genera alertas automáticas cuando el stock
> de un lote cae a 10 unidades o menos,
> o cuando un lote vence en los próximos 30 días."

- Señala los lotes con alerta de stock bajo (badge rojo)
- Señala los lotes próximos a vencer

> "Cada aplicación de vacuna descuenta automáticamente
> una unidad del lote seleccionado, manteniendo el inventario
> siempre actualizado en tiempo real."

---

## ESCENA 11 — Cierre (8:15 – 8:45)

**Pantalla:** Vuelve al `/dashboard`

> "En resumen, ImmuniCare cubre el ciclo completo
> de gestión de vacunación pediátrica:
> registro de pacientes y tutores,
> esquema vacunal personalizado con estados automáticos,
> aplicación de dosis con validaciones clínicas,
> control de inventario por lote,
> comprobantes PDF con QR,
> reportes geográficos,
> y arquitectura híbrida PostgreSQL más MongoDB.
> Todo bajo un sistema de roles que segmenta el acceso
> según la función de cada trabajador."

---

## NOTAS DE EDICIÓN

- Corta los tiempos muertos mientras cargan las páginas
- Añade zoom (150%) cuando muestres formularios para que se lean bien
- Si usas OBS: activa "Resaltar cursor del mouse" para que sea fácil seguirlo
- Música de fondo opcional: mantenerla al 10% de volumen para no distraer
- Duración ideal del video final editado: **6-7 minutos**
