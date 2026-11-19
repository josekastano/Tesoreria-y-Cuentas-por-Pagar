-- -----------------------------------------------------------------------------|
-- SCRIPT ADSO ERP                                         						|
-- Script de creacion de tablas del sistema automatizado   						|
-- Autor: Carlos Eduardo Perez & equipo de ADSO 3171727    						|
-- Versión: 1.4 - Noviembre de 2026                          					|
-- Script ejecutable local: versión 1.4 (14-nov-2026)        					|
--   Cambios: secciones "CAMBIOS 1.1", "CAMBIOS 1.3" y     						|
--   "CAMBIOS 1.4" al final; columnas nuevas marcadas.     						|
--   (compras 14-nov) Compras actualizado: borrado 3.8,  						|
--   tablas, vistas, datos, auditoría 10.3, menús,      						|
--   insert v1.8 / update v1.7 / delete v1.3 y trigger  						|
--   de EPP (SST). Buscar "(compras 14-nov)".           						|
--   (gehnom 14-nov) Gestión Humana y Nómina sincronizado 						|
--   con db_adsoerp_old: borrado 3.0 y 3.7, tablas, 9.9  						|
--   dependencias, auditoría 10.4, funciones 11.3 y     						|
--   triggers de negocio. Buscar "(gehnom 14-nov)".     						|
--   (14-nov) Las funciones se movieron a fun_generales.sql.					|
--   Aquí queda el modelo: tablas, tipos, secuencias,      						|
--   índices, vistas, datos, fun_audit_trail (la necesitan 						|
--   los triggers de auditoría) y triggers de auditoría.   						|
--   (usuarios 14-nov) tab_usuarios (ind_admin, primer      |
--   ingreso, caducidad), tab_pmtros_grales (val_ipc,        |
--   val_cadu_pass) y tab_intento_clave, como en la BD.      |
--   (errores 15-nov) Se quitó el bloque viejo de tab_enc_archivo_plano     |
--   de 9.9 (Tesorería ya la crea igual que la BD) y el INSERT repetido   |
--   de tab_naturaleza_tributaria.                                         |
--   ORDEN DE EJECUCIÓN: 1) script_bd_erpadso_ejecutable_local_1.10.sql (modelo) |
--                       2) fun_generales.sql (funciones del sistema y menús) |
--                       3) las funciones de cada módulo                      |
-- -----------------------------------------------------------------------------|

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- -------------------------------------------------------------------
-- 1. CONFIGURACIÓN INICIAL
-- Establecer que si algo falla, se detenga el script inmediatamente.
-- -------------------------------------------------------------------
SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;

-- --------------------------------------------------------------------------------------
-- 2.9 (15-nov) BORRADO PREVIO DE VISTAS Y LLAVES FORÁNEAS (sin CASCADE)
--   Permite correr el script varias veces sobre la misma base. Primero se quitan las
--   vistas y todas las llaves foráneas del esquema public; así ningún DROP TABLE de
--   abajo choca con otra tabla, sin importar el orden de las secciones. Todo se vuelve
--   a crear más abajo. En una base vacía no hace nada.
-- --------------------------------------------------------------------------------------
DO $borrado$
DECLARE
    r         RECORD;
    wborradas INTEGER;
BEGIN
    -- Vistas: en cada vuelta se borran las que no tienen otra vista encima.
    LOOP
        wborradas := 0;
        FOR r IN
            SELECT n.nspname, c.relname, c.relkind
              FROM pg_class c
              JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE n.nspname = 'public'
               AND c.relkind IN ('v', 'm')
               AND NOT EXISTS (SELECT 1
                                 FROM pg_depend d
                                 JOIN pg_rewrite rw ON rw.oid = d.objid
                                WHERE d.classid  = 'pg_rewrite'::regclass
                                  AND d.refobjid = c.oid
                                  AND rw.ev_class <> c.oid)
        LOOP
            IF r.relkind = 'm' THEN
                EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I.%I', r.nspname, r.relname);
            ELSE
                EXECUTE format('DROP VIEW IF EXISTS %I.%I', r.nspname, r.relname);
            END IF;
            wborradas := wborradas + 1;
        END LOOP;
        EXIT WHEN wborradas = 0;
    END LOOP;

    -- Llaves foráneas: se quitan todas; las vuelven a crear los CREATE TABLE de abajo.
    FOR r IN
        SELECT n.nspname, c.relname, con.conname
          FROM pg_constraint con
          JOIN pg_class c     ON c.oid = con.conrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE con.contype = 'f'
           AND n.nspname = 'public'
    LOOP
        EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT IF EXISTS %I', r.nspname, r.relname, r.conname);
    END LOOP;
END;
$borrado$;

-- ------------------------------------------------------------------------------------------
-- 3.0 (gehnom 14-nov) BORRADO PREVIO DE TABLAS PUENTE DE GESTIÓN HUMANA
--   Referencian tablas de Tesorería, Notificaciones y GEHNOM; se borran antes que los demás
--   módulos para que los DROP de cada sección no fallen al volver a correr el script.
-- -------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS tab_log_alerta_contrato;
DROP TABLE IF EXISTS tab_param_aviso;
DROP TABLE IF EXISTS tab_evento_notificacion;
DROP TABLE IF EXISTS tab_modulo_alerta;
-- -----------------------------------------------------------
-- 3.1 BORRADO DE TABLAS PARA TESORERÍA Y CUENTAS POR PAGAR
-- -----------------------------------------------------------
DROP TABLE IF EXISTS tab_pagos_inversion;
DROP TABLE IF EXISTS tab_pagos_nomina;
DROP TABLE IF EXISTS tab_pagos_cxp;
DROP TABLE IF EXISTS tab_codigos_respuesta_banco;
DROP TABLE IF EXISTS tab_det_archivo_inversion;
DROP TABLE IF EXISTS tab_det_archivo_nomina;
DROP TABLE IF EXISTS tab_det_archivo_plano;
DROP TABLE IF EXISTS tab_enc_archivo_plano;
DROP TABLE IF EXISTS tab_det_cronopagos;
DROP TABLE IF EXISTS tab_enc_cronopagos;
DROP TABLE IF EXISTS tab_cuotasxfactura;
DROP TABLE IF EXISTS tab_cuentasxpagar;
DROP TABLE IF EXISTS tab_bancoxprov;
DROP TABLE IF EXISTS tab_ctas_empresa;
DROP TABLE IF EXISTS tab_det_caja_menor;
DROP TABLE IF EXISTS tab_enc_caja_menor;
DROP TABLE IF EXISTS tab_pmtros_tescxp;

-------------------------------------------------------------------------------------------------------
-- 3.2 ELIMINACIoN DE TABLAS Y SECUENCIAS DE GESTION DOCUMENTAL Y CALIDAD
--------------------------------------------------------------------------------------------------------
ALTER TABLE IF EXISTS tab_evaluacion_calidad_ia DROP CONSTRAINT IF EXISTS fk_eval_solicitud;

DROP TABLE IF EXISTS tab_workflow_expediente;
DROP TABLE IF EXISTS tab_permiso_acceso;
DROP TABLE IF EXISTS tab_accion_workflow_doc;
DROP SEQUENCE IF EXISTS seq_workflow_expediente;
DROP SEQUENCE IF EXISTS seq_permiso_acceso;
DROP SEQUENCE IF EXISTS seq_archivo_digital;
DROP TABLE IF EXISTS tab_eval_criterio_ia;
DROP TABLE IF EXISTS tab_solicitud_certificacion;
DROP TABLE IF EXISTS tab_evaluacion_calidad_ia;
DROP TABLE IF EXISTS tab_prompt_ia;
DROP TABLE IF EXISTS tab_parametro_calidad;
DROP TABLE IF EXISTS tab_workflow;
DROP TABLE IF EXISTS tab_doc_anexo;
DROP TABLE IF EXISTS tab_accion_correctiva;
DROP TABLE IF EXISTS tab_hallazgo;
DROP TABLE IF EXISTS tab_auditorias;
DROP TABLE IF EXISTS tab_certificacion;
DROP TABLE IF EXISTS tab_bitacora_proceso;
DROP TABLE IF EXISTS tab_entrada_proceso;
DROP TABLE IF EXISTS tab_tipo_dato_entrada;
DROP TABLE IF EXISTS tab_procesos;
DROP SEQUENCE IF EXISTS seq_workflow;
DROP SEQUENCE IF EXISTS seq_solicitud_certificacion;
DROP SEQUENCE IF EXISTS seq_bitacora_proceso;
DROP SEQUENCE IF EXISTS seq_tipo_dato_entrada;
DROP SEQUENCE IF EXISTS seq_accion_correctiva;
DROP SEQUENCE IF EXISTS seq_hallazgo;
DROP SEQUENCE IF EXISTS seq_auditoria;
DROP SEQUENCE IF EXISTS seq_proceso;
DROP TABLE IF EXISTS tab_doc_archivo;
DROP TABLE IF EXISTS tab_doc_norma;
DROP TABLE IF EXISTS tab_det_documento;
DROP TABLE IF EXISTS tab_enc_documento;
DROP TABLE IF EXISTS tab_estado_documento;
DROP TABLE IF EXISTS tab_normas;
DROP TABLE IF EXISTS tab_codigo_pqrs;
DROP SEQUENCE IF EXISTS seq_codigo_pqrs;
DROP TABLE IF EXISTS tab_consecutivo_pqrs;
DROP TABLE IF EXISTS tab_log_alerta_pqrs;
DROP TABLE IF EXISTS tab_param_alerta_pqrs;
DROP SEQUENCE IF EXISTS seq_param_alerta_pqrs;
DROP TABLE IF EXISTS tab_anexo_pqrs;
DROP TABLE IF EXISTS tab_respuesta_pqrs;
DROP SEQUENCE IF EXISTS seq_respuesta_pqrs;
DROP TABLE IF EXISTS tab_seg_pqrs;
DROP SEQUENCE IF EXISTS seq_seg_pqrs;
DROP TABLE IF EXISTS tab_det_pqrs;
DROP SEQUENCE IF EXISTS seq_det_pqrs;
DROP TABLE IF EXISTS tab_enc_pqrs;
DROP TABLE IF EXISTS tab_motivo_pqrs;
DROP TABLE IF EXISTS tab_estado_pqrs;
DROP TABLE IF EXISTS tab_param_venc_pqrs;
DROP TABLE IF EXISTS tab_tipo_pqrs;
DROP TABLE IF EXISTS tab_fuente_columna;
DROP TABLE IF EXISTS tab_fuente_alerta;
DROP TABLE IF EXISTS tab_agenda_vencimiento;
DROP SEQUENCE IF EXISTS seq_agenda_vencimiento;
DROP TABLE IF EXISTS tab_log_alerta;
DROP TABLE IF EXISTS tab_param_alerta;
DROP SEQUENCE IF EXISTS seq_param_alerta;
DROP TABLE IF EXISTS tab_param_aviso;
DROP TABLE IF EXISTS tab_evento_notificacion;
DROP TABLE IF EXISTS tab_modulo_alerta;
DROP TABLE IF EXISTS tab_notificaciones;
DROP SEQUENCE IF EXISTS seq_envio_mensaje;
DROP SEQUENCE IF EXISTS seq_notificacion;
DROP TABLE IF EXISTS tab_anexo_correspondencia;
DROP TABLE IF EXISTS tab_doc_expediente;
DROP TABLE IF EXISTS tab_expediente;
DROP TABLE IF EXISTS tab_indexacion;
DROP SEQUENCE IF EXISTS seq_anexo_correspondencia;
DROP SEQUENCE IF EXISTS seq_expediente;
DROP SEQUENCE IF EXISTS seq_indexacion;
DROP SEQUENCE IF EXISTS seq_consecutivo_radicado;
DROP TABLE IF EXISTS tab_correspondencia;
DROP TABLE IF EXISTS tab_accion_workflow;
DROP TABLE IF EXISTS tab_estado_correspondencia;
DROP TABLE IF EXISTS tab_tabla_retencion;
DROP TABLE IF EXISTS tab_tipo_documento;

-- -----------------------------------------------
-- 3.3 BORRADO DE TABLAS PARA ANÁLISIS FINANCIERO
-- -----------------------------------------------
DROP VIEW IF EXISTS vw_cuotas_inversion;
DROP VIEW IF EXISTS vw_proyeccion_mensual;
DROP VIEW IF EXISTS vw_analisis_desviacion_mensual;
DROP VIEW IF EXISTS vw_analisis_desviacion_area;

DROP TABLE IF EXISTS tab_cuotas_inversion;
DROP TABLE IF EXISTS tab_inversiones;
DROP TABLE IF EXISTS tab_val_ind;
DROP TABLE IF EXISTS tab_indicadores;
DROP TABLE IF EXISTS tab_proyectos;
DROP TABLE IF EXISTS tab_inversores;
DROP TABLE IF EXISTS tab_pmtros_financieros;

-- ----------------------------------------------
-- 3.4 BORRADO DE TABLAS PARA FACTURACIÓN
-- ----------------------------------------------
 DROP TABLE IF EXISTS tab_factus_mapeo;
DROP TABLE IF EXISTS tab_pmtros_facturacion;                                         
DROP TABLE IF EXISTS tab_aplicacion_nota_cartera;
DROP TABLE IF EXISTS tab_aplicacion_nota_factura;
DROP TABLE IF EXISTS tab_aplicacion_nota;                      -- tabla de la V.1.9 (ya no se crea)
DROP TABLE IF EXISTS tab_nota_elect;
DROP TABLE IF EXISTS tab_det_notas;
DROP TABLE IF EXISTS tab_enc_notas;
DROP TABLE IF EXISTS tab_motivo_nota;                                                                                                                                             
DROP TABLE IF EXISTS tab_autorizaciones_credito;
DROP TABLE IF EXISTS tab_acuerdos_recuperaciones;
DROP TABLE IF EXISTS tab_acuerdos_pago;
DROP TABLE IF EXISTS tab_recuperaciones_cartera;
DROP TABLE IF EXISTS tab_edades_cartera;
DROP TABLE IF EXISTS tab_respuestas_castigo;
DROP TABLE IF EXISTS tab_det_solicitud_castigo;
DROP TABLE IF EXISTS tab_solicitudes_castigo;
DROP TABLE IF EXISTS tab_promesas_pago;
DROP TABLE IF EXISTS tab_gestiones_cobro;
DROP TABLE IF EXISTS tab_pagos_cartera;
DROP TABLE IF EXISTS tab_carteras;
DROP TABLE IF EXISTS tab_pagos; 
DROP TABLE IF EXISTS tab_fac_electronicas;                                           
DROP TABLE IF EXISTS tab_det_facturas;                                               
DROP TABLE IF EXISTS tab_enc_facturas;
DROP TABLE IF EXISTS tab_resoluciones_dian;                                               
DROP TABLE IF EXISTS tab_det_cotizaciones;                                           
DROP TABLE IF EXISTS tab_enc_cotizaciones;                                           
DROP TABLE IF EXISTS tab_vendedores;                                                                                               
DROP TABLE IF EXISTS tab_clientes;                                                  
DROP TABLE IF EXISTS tab_forma_pagos; 
-- ----------------------------------------------
-- 3.5 BORRADO DE TABLAS PARA MARKETING
-- ----------------------------------------------
DROP TABLE IF EXISTS tab_pmtros_correo;
DROP TABLE IF EXISTS tab_remitente_correo;
DROP TABLE IF EXISTS tab_baja_correo;
DROP TABLE IF EXISTS tab_cola_correos;
DROP TABLE IF EXISTS tab_camp_prod;
DROP TABLE IF EXISTS tab_pedido_factura;
DROP TABLE IF EXISTS tab_det_pedidos;
DROP TABLE IF EXISTS tab_enc_pedidos;
DROP TABLE IF EXISTS tab_lead_camp_tracker;
DROP TABLE IF EXISTS tab_rate_limit_promo;
DROP TABLE IF EXISTS tab_tracker_campana_canal;
DROP TABLE IF EXISTS tab_historial_asignacion_lead;
DROP TABLE IF EXISTS tab_canal_tipo_interaccion;
DROP TABLE IF EXISTS tab_envios;
DROP TABLE IF EXISTS tab_contactos_adicionales;
DROP TABLE IF EXISTS tab_plantillas_correo;
DROP TABLE IF EXISTS tab_evento_correo;
DROP TABLE IF EXISTS tab_medicion_kpi;
DROP TABLE IF EXISTS tab_kpis_marcom;
DROP TABLE IF EXISTS tab_presupuesto_evento;
DROP TABLE IF EXISTS tab_presupuesto_campana;
DROP TABLE IF EXISTS tab_prod_camp;
DROP TABLE IF EXISTS tab_even_lead;
DROP TABLE IF EXISTS tab_evento;
DROP TABLE IF EXISTS tab_proximas_acciones;
DROP TABLE IF EXISTS tab_interacciones;
DROP TABLE IF EXISTS tab_tipos_interaccion_marcom;
DROP TABLE IF EXISTS tab_cliente_camp;
DROP TABLE IF EXISTS tab_lead_camp;
DROP TABLE IF EXISTS tab_segmentacion_cliente;
DROP TABLE IF EXISTS tab_segmentacion_lead;
DROP TABLE IF EXISTS tab_leads;
DROP TABLE IF EXISTS tab_campana_canal;
DROP TABLE IF EXISTS tab_campanas;
DROP TABLE IF EXISTS tab_tipo_campana;
DROP TABLE IF EXISTS tab_motivos_perdida;
DROP TABLE IF EXISTS tab_valores_segmentacion;
DROP TABLE IF EXISTS tab_criterios_segmentacion;
DROP TABLE IF EXISTS tab_canales;
DROP TABLE IF EXISTS tab_etapas_funnel;
DROP TABLE IF EXISTS tab_pmtros_marcom;
DROP TABLE IF EXISTS tab_vendedores_activos;
DROP TABLE IF EXISTS tab_genero;

-- Motor de reglas viejo y legado eliminado (no se vuelven a crear)
DROP TABLE IF EXISTS tab_condiciones_regla_marcom;
DROP TABLE IF EXISTS tab_reglas_segmentacion;
DROP TABLE IF EXISTS tab_operadores_marcom;
DROP TABLE IF EXISTS tab_campos_segmentacion_marcom;
DROP TABLE IF EXISTS tab_atributos_marcom;
DROP TABLE IF EXISTS tab_tablas_marcom;
DROP TABLE IF EXISTS tab_vendedores_marcom;
DROP TABLE IF EXISTS tab_cargos_vendedor_marcom;


-- ----------------------------------------------
-- 3.6 BORRADO DE TABLAS PARA SST
-- ----------------------------------------------

DROP TABLE IF EXISTS tab_accidentes;
DROP TABLE IF EXISTS tab_auditorias_sst;
DROP TABLE IF EXISTS tab_asist_copasst; 
DROP TABLE IF EXISTS tab_reu_copasst;
DROP TABLE IF EXISTS tab_miem_copasst; 
DROP TABLE IF EXISTS tab_copasst; 
DROP TABLE IF EXISTS tab_emergencia; 
DROP TABLE IF EXISTS tab_brigadistas; 
DROP TABLE IF EXISTS tab_brigada;
DROP TABLE IF EXISTS tab_asis_cap;
DROP TABLE IF EXISTS tab_capacitaciones;
DROP TABLE IF EXISTS tab_docentes;
DROP TABLE IF EXISTS tab_temas_cap;
DROP TABLE IF EXISTS tab_incapacidades;
DROP TABLE IF EXISTS tab_tipo_incapacidad;
DROP TABLE IF EXISTS tab_det_ex_ingreso;
DROP TABLE IF EXISTS tab_enc_ex_ingreso;
DROP TABLE IF EXISTS tab_examenes;
DROP TABLE IF EXISTS tab_epp_inspeccion;
DROP TABLE IF EXISTS tab_epp_asignacion;
DROP TABLE IF EXISTS tab_epp; 
DROP TABLE IF EXISTS tab_tipo_acc;
-- (15-nov) Tablas de SST que se creaban pero no se borraban:
DROP TABLE IF EXISTS tab_correcciones_acc;
DROP TABLE IF EXISTS tab_reportes_acc;
DROP TABLE IF EXISTS tab_simulacro_brigadista;
DROP TABLE IF EXISTS tab_simulacro;
DROP TABLE IF EXISTS tab_dotacion_brigada;
DROP TABLE IF EXISTS tab_convocados_cap;
DROP TABLE IF EXISTS tab_solicitar_cap_emp;
DROP TABLE IF EXISTS tab_solicitar_cap;
DROP TABLE IF EXISTS tab_tipo_cap;
DROP TABLE IF EXISTS tab_categoria_epp;
DROP TABLE IF EXISTS tab_tipo_lesion;
DROP TABLE IF EXISTS tab_partes_cuerpo;

-- ----------------------------------------------
-- 3.7 BORRADO DE TABLAS PARA GESTIÓN HUMANA
-- (gehnom 14-nov) actualizado: tablas nuevas de GEHNOM, en orden de dependencias
-- ----------------------------------------------

ALTER TABLE IF EXISTS tab_req_personal DROP CONSTRAINT IF EXISTS tab_req_personal_id_empleado_contratado_fkey;
DROP TABLE IF EXISTS tab_log_alerta_contrato;
DROP TABLE IF EXISTS tab_vacaciones;
DROP TABLE IF EXISTS tab_prestaciones;
DROP TABLE IF EXISTS tab_nomina_electronica;
DROP TABLE IF EXISTS tab_nomina_empleador;
DROP TABLE IF EXISTS tab_nomina_avisos;
DROP TABLE IF EXISTS tab_nomina_detalle;
DROP TABLE IF EXISTS tab_nomina;
DROP TABLE IF EXISTS tab_procesos_disciplinarios;
DROP TABLE IF EXISTS tab_novedades;
DROP TABLE IF EXISTS tab_conceptos;
DROP TABLE IF EXISTS tab_prestamos_pagos;
DROP TABLE IF EXISTS tab_prestamos;
DROP TABLE IF EXISTS tab_req_contratados;
DROP TABLE IF EXISTS tab_empleados;
DROP TABLE IF EXISTS tab_candidatos;
DROP TABLE IF EXISTS tab_req_personal;
DROP TABLE IF EXISTS tab_tipos_contrato;
DROP TABLE IF EXISTS tab_entidades;
DROP TABLE IF EXISTS tab_cargos;
DROP TABLE IF EXISTS tab_profesiones;
DROP TABLE IF EXISTS tab_escolaridad;
DROP TABLE IF EXISTS tab_pmtros_legales;
DROP SEQUENCE IF EXISTS seq_tab_novedades;

-- ----------------------------------------------
-- 3.8 BORRADO DE TABLAS PARA COMPRAS
-- (compras 14-nov) borrado actualizado (tablas nuevas de Compras, en orden de dependencias)
-- ----------------------------------------------

DROP VIEW  IF EXISTS vw_convenios_aptos;
DROP VIEW  IF EXISTS vw_semaforo_ordcomp;
DROP TABLE IF EXISTS tab_det_devprov;
DROP TABLE IF EXISTS tab_enc_devprov;
DROP TABLE IF EXISTS tab_conf_solcomp;
DROP TABLE IF EXISTS tab_transportadoras;
DROP TABLE IF EXISTS tab_motivos_novedad;
DROP TABLE IF EXISTS tab_medios_envio;
DROP TABLE IF EXISTS tab_medios_reembolso;
DROP TABLE IF EXISTS tab_det_ordcomp_solcomp;
DROP TABLE IF EXISTS tab_consol_solcomp;
DROP TABLE IF EXISTS tab_asig_prov_solcomp;
DROP TABLE IF EXISTS tab_det_seg_ordcomp;
DROP TABLE IF EXISTS tab_seg_ordcomp;
DROP TABLE IF EXISTS tab_det_ordcomp;
DROP TABLE IF EXISTS tab_enc_ordcomp;
DROP TABLE IF EXISTS tab_det_solcomp;
DROP TABLE IF EXISTS tab_enc_solcomp;
DROP TABLE IF EXISTS tab_prodxprov;
DROP TABLE IF EXISTS tab_prodxarea;
DROP TABLE IF EXISTS tab_productos;
DROP TABLE IF EXISTS tab_eval_prov;
DROP TABLE IF EXISTS tab_proveedores;
DROP TABLE IF EXISTS tab_pmtros_compras;
DROP TABLE IF EXISTS tab_naturaleza_tributaria;      -- Catálogo tributario (Facturación); lo referencia tab_productos

-- ----------------------------------------------
-- 3.9 BORRADO DE TABLAS PARA CONTABILIDAD
-- ----------------------------------------------
DROP TABLE IF EXISTS tab_rechazo_linea_presupuesto;
DROP TABLE IF EXISTS tab_det_presupuesto_mensual;
DROP TABLE IF EXISTS tab_det_historico_presupuesto;
DROP TABLE IF EXISTS tab_historico_presupuesto;
DROP TABLE IF EXISTS tab_det_plantilla_presupuesto;
DROP TABLE IF EXISTS tab_plantilla_presupuesto;
DROP TABLE IF EXISTS tab_det_comprobantes;       
DROP TABLE IF EXISTS tab_ejecucion_presupuesto;  
DROP TABLE IF EXISTS tab_det_presupuesto;        
DROP TABLE IF EXISTS tab_enc_comprobantes;    
DROP TABLE IF EXISTS tab_estado_comprobantes;
DROP TABLE IF EXISTS tab_planeacion_presupuesto; 
DROP TABLE IF EXISTS tab_enc_presupuesto;            
DROP TABLE IF EXISTS tab_depreciacion;           
DROP TABLE IF EXISTS tab_act_fijos;              
DROP TABLE IF EXISTS tab_parametros_contab;      
DROP TABLE IF EXISTS tab_periodos_contables;     
DROP TABLE IF EXISTS tab_tip_comprobantes;       
DROP TABLE IF EXISTS tab_tipo_presupuesto;       
DROP TABLE IF EXISTS tab_period_presupuesto;     
DROP TABLE IF EXISTS tab_cat_activos;            
DROP TABLE IF EXISTS tab_puc;        
-- ----------------------------------------------
-- 3.10 BORRADO DE TABLAS GENERAL
-- ----------------------------------------------

DROP TABLE IF EXISTS tab_accesos_usuario;                -- (1.4) creada en CAMBIOS 1.4 (depende de tab_usuarios y tab_menus)
DROP TABLE IF EXISTS tab_intento_clave;                  -- (usuarios 14-nov) intentos de recuperar clave
DROP SEQUENCE IF EXISTS seq_intento_clave;               -- (usuarios 14-nov)
DROP TABLE IF EXISTS tab_codigo_clave;                   -- (1.4) creada en CAMBIOS 1.4 (depende de tab_usuarios)
DROP TABLE IF EXISTS tab_config_dashboard;
DROP TABLE IF EXISTS tab_riesgos;
DROP TABLE IF EXISTS tab_areas;
DROP TABLE IF EXISTS tab_sesiones;
DROP TABLE IF EXISTS tab_menu_usuarios;
DROP TABLE IF EXISTS tab_menus;
DROP TABLE IF EXISTS tab_usuarios;
DROP TABLE IF EXISTS tab_festivos;
DROP TABLE IF EXISTS tab_bancos;
DROP TABLE IF EXISTS tab_terceros;
DROP TABLE IF EXISTS tab_tel_prefijo;
DROP TABLE IF EXISTS tab_tipo_identidad;
DROP TABLE IF EXISTS tab_cat_terceros;
DROP TABLE IF EXISTS tab_restricciones;
DROP TABLE IF EXISTS tab_ciudades;
DROP TABLE IF EXISTS tab_dptos;
DROP TABLE IF EXISTS tab_menu_palettes;
DROP TABLE IF EXISTS tab_temporadas;                       -- (temporadas 18-nov)
DROP TABLE IF EXISTS tab_pmtros_grales;
DROP TABLE IF EXISTS tab_audit_trail;
DROP TABLE IF EXISTS tab_cat_errores;
-- (15-nov) Sin CASCADE: primero se borran las funciones que reciben o devuelven el tipo
-- (firmas viejas de fun_insert/update_pmtros_grales); fun_generales las vuelve a crear.
DO $borrado_tipo$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT DISTINCT d.objid::regprocedure AS firma
          FROM pg_depend d
         WHERE d.classid    = 'pg_proc'::regclass
           AND d.refclassid = 'pg_type'::regclass
           AND d.refobjid IN (SELECT ty.oid FROM pg_type ty
                               WHERE ty.typname IN ('datos_ubicacion', '_datos_ubicacion'))
    LOOP
        EXECUTE format('DROP FUNCTION IF EXISTS %s', r.firma);
    END LOOP;
END;
$borrado_tipo$;
DROP TYPE  IF EXISTS DATOS_UBICACION;

-- ------------------------------------------------------------
-- 4. CREACIÓN DE TABLAS MAS USADAS
-- Estas tablas son esenciales y usadas por todos los módulos.
-- ------------------------------------------------------------

--ESTRUCTURA DE DATOS DE UBICACIÓN DE LOS TERCEROS DEL SISTEMA (Se usa en la tabla de terceros y en la tabla de parámetros generales para la empresa).

CREATE TYPE DATOS_UBICACION AS
(
	nom_corto           VARCHAR,             --nombre corto del lugar (ej: Barrio, Vereda, etc.)
    direccion           VARCHAR,             --direcion del tercero
    tel_fijo            DECIMAL,             --telefono fijo del tercero (7 a 10 dígitos dependiendo de la ciudad)
    id_prefijo_movil    DECIMAL,             --prefijo del celular del tercero
    tel_movil           DECIMAL,             --celular del tercero
    email               VARCHAR              --email del tercero
);

-- MANEJO DE ERRORES TRANSVERSAL (Tabla de códigos de error SQLSTATE y mensajes asociados).

CREATE TABLE tab_cat_errores (
    cod_sqlstate    VARCHAR     NOT NULL CHECK(LENGTH(cod_sqlstate) = 5),                        -- Codigo SQLSTATE del error
    mensaje         VARCHAR     NOT NULL CHECK(LENGTH(mensaje) >= 4 AND LENGTH(mensaje) <= 255), -- Mensaje descriptivo del error    
    PRIMARY KEY(cod_sqlstate)
);

-- 1. SEGURIDAD Y ACCESOS (Usuarios creados en Bases de Datos).

CREATE TABLE tab_usuarios
(
    id_usuario          VARCHAR         NOT NULL CHECK(LENGTH(id_usuario) >= 5),
    nom_usuario         VARCHAR         NOT NULL CHECK(LENGTH(nom_usuario) >= 8),
    pass_usuario        VARCHAR(255)    NOT NULL CHECK(LENGTH(pass_usuario) >= 12),
    mail_usuario        VARCHAR         NOT NULL CHECK(mail_usuario ~* '^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$'),
    foto_usuario        VARCHAR         CHECK(LENGTH(foto_usuario) >= 3) DEFAULT 'sin_foto',
    ind_admin           BOOLEAN         NOT NULL DEFAULT FALSE,                     -- (usuarios 14-nov) antes ind_usuario: TRUE = administrador
    ind_estado          BOOLEAN         NOT NULL DEFAULT TRUE,
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,
    firma_electronica   TEXT,                                                       -- NUEVO
    fec_creacion        TIMESTAMPTZ(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP,         -- (usuarios 14-nov) fecha de creación del usuario
    ind_primer_vez      BOOLEAN         NOT NULL DEFAULT TRUE,                      -- (usuarios 14-nov) TRUE = clave temporal: debe cambiarla al entrar
    fec_cambio_pass     TIMESTAMPTZ(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP,         -- (usuarios 14-nov) último cambio de clave (caducidad, val_cadu_pass)
    PRIMARY KEY(id_usuario)
);

-- 2. TABLA PARA CUMPLIMIENTO DE SESIÓN ÚNICA (Requerimientos).

CREATE TABLE tab_sesiones
(
    id_sesion             INTEGER        NOT NULL,
    id_usuario            VARCHAR        NOT NULL CHECK(LENGTH(id_usuario) >= 5),
    token_csrf            VARCHAR(128)   NOT NULL CHECK (LENGTH(token_csrf) >= 32),
    user_browser          TEXT,
    ip_direccion          VARCHAR,
    fec_inicio            TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hora_inicio           TIME(0)        NOT NULL,  
    fec_final             TIMESTAMPTZ(3) NULL,
    ind_estado            BOOLEAN        NOT NULL,
    fec_ultima_actividad  TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,   -- (15-nov) última señal del navegador; libera sesiones abandonadas (fun_cerrar_sesiones_abandonadas)
    PRIMARY KEY (id_sesion, id_usuario),
    FOREIGN KEY (id_usuario) REFERENCES tab_usuarios(id_usuario) ON DELETE CASCADE
);
-- 3. TABLAS DE MENUS (Menus que se crean para asignar a los usuarios y evitar usar roles).

CREATE TABLE tab_menus
(
    id_menu             VARCHAR(255)   NOT NULL,                                 -- ID único del menú. Formato jerárquico con puntos: '1', '1.11', '1.11.111'. Raíces: '1', '2', ..., '11'.
    nom_menu            VARCHAR(255)   NOT NULL CHECK(LENGTH(nom_menu) <= 100),  -- Nombre del menú para mostrar en la interfaz (ej: Configuración, Parámetros, etc.)
    ind_id_padre        VARCHAR(255)   NOT NULL,                                 -- ID del menú padre. '0' si es raíz. Ej: '1.11' tiene padre '1'.
    nom_programa        VARCHAR(255)   NOT NULL DEFAULT 'no_aplica',             -- Nombre del programa o ruta que se ejecuta al hacer clic en el menú (ej: 'modules/compro/productos.php')
    descripcion         TEXT                    DEFAULT '',                      -- (1.1) Para qué sirve el menú (se muestra en Menús)
    PRIMARY KEY(id_menu)
);




-- 4. TABLAS DE MENUS POR USUARIO (para asignar menus sin necesidad de que todos los usuarios tengan los mismos).

CREATE TABLE tab_menu_usuarios
(
    id_usuario          VARCHAR(255) NOT NULL CHECK(LENGTH(id_usuario) >= 5) REFERENCES tab_usuarios(id_usuario),    -- ID del usuario al que se le asigna el menú (FK a tab_usuarios)
    id_menu             VARCHAR(255) NOT NULL REFERENCES tab_menus(id_menu),                                         -- ID del menú asignado al usuario (FK a tab_menus)
    PRIMARY KEY(id_usuario, id_menu)
);

-- 5. TABLA DE ÁREAS DE LA EMPRESA (Áreas creadas y asignadas a un responsable por su id de usuario del sistema).

CREATE TABLE IF NOT EXISTS tab_areas
(
    id_area             DECIMAL(5,0)    NOT NULL CHECK (id_area > 0),                                                       -- ID del área
    id_responsable      VARCHAR         NOT NULL CHECK(LENGTH(id_responsable) >= 5),                                        -- Usuario responsable del área
    nom_area            VARCHAR         NOT NULL CHECK (LENGTH(nom_area) >= 3),                                             -- Nombre del área (ej: Finanzas, Recursos Humanos, etc.)
    descrip_area        TEXT            NOT NULL DEFAULT 'Sin descripción de área',                                         -- Descripción detallada del área y sus funciones
    mail_area           VARCHAR         NOT NULL CHECK(mail_area ~* '^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$'),    -- Email corporativo del área
    tel_oficina         DECIMAL(10,0)   NOT NULL CHECK(tel_oficina >= 0 AND tel_oficina < 9999999999),                      -- Teléfono de la oficina del área
    ubi_oficina         VARCHAR         NOT NULL CHECK(LENGTH(ubi_oficina) >= 3),                                           -- Edificio, piso, oficina
    horario_atencion    VARCHAR         NOT NULL CHECK(LENGTH(horario_atencion) >= 3),                                      -- Lunes a Viernes 8am-5pm
    ind_estado          BOOLEAN         NOT NULL DEFAULT TRUE,                                                              -- Activo/Inactivo
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE, --TRUE: Borrado lógico (Inactivo) / FALSE: Activo	       
    PRIMARY KEY (id_area),
    FOREIGN KEY (id_responsable) REFERENCES tab_usuarios(id_usuario)
);

-- 5.1 TABLA ÁREA ↔ MÓDULO (16-nov-2026): qué módulo dirige cada área.
--     Módulo = menú de primer nivel (tab_menus.ind_id_padre = '0'), p. ej. '8' Recursos Humanos.
--     Un área puede dirigir varios módulos; cada módulo tiene una sola área dueña (UNIQUE id_menu).
--     El jefe de un módulo es el id_responsable de su área: fun_jefe_modulo / fun_es_jefe_modulo.
--     Solo se escribe con fun_set_area_modulos (valida que el menú sea de primer nivel).

CREATE TABLE IF NOT EXISTS tab_area_modulo
(
    id_area             DECIMAL(5,0)    NOT NULL,                                       -- Área dueña del módulo
    id_menu             VARCHAR         NOT NULL,                                       -- Menú de primer nivel (módulo)
    fec_registro        TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP,             -- Cuándo se asignó
    PRIMARY KEY (id_area, id_menu),
    CONSTRAINT uq_area_modulo_menu UNIQUE (id_menu),
    FOREIGN KEY (id_area) REFERENCES tab_areas(id_area),
    FOREIGN KEY (id_menu) REFERENCES tab_menus(id_menu) ON DELETE CASCADE
);

-- 6. TABLA PARAMETROS GENERALES

CREATE TABLE IF NOT EXISTS tab_pmtros_grales
(
    id_empresa	        VARCHAR(10)		NOT NULL,													                    --identificador de la empresa
    nom_empresa	        VARCHAR         NOT NULL CHECK(LENGTH(nom_empresa) >= 5 AND LENGTH(nom_empresa) <= 60),         --nombre de la empresa
    datos_residencia    DATOS_UBICACION,                                                                                --Estructura de datos de residencia de la empresa
    nom_replegal        VARCHAR	        NOT NULL CHECK(LENGTH(nom_replegal) >= 5 AND LENGTH(nom_replegal) <= 60),       --nombre del representante legal
    val_poriva	        DECIMAL(2,0)	NOT NULL CHECK(val_poriva   >= 0   AND val_poriva   < 100) DEFAULT 0,           --valor porcentaje iva
    val_pordesc	        DECIMAL(2,0)	NOT NULL CHECK(val_pordesc   >= 0   AND val_pordesc < 100) DEFAULT 0,           --valor porcentaje descuento
    val_porrete	        DECIMAL(2,0)	NOT NULL CHECK(val_porrete  >= 0   AND val_porrete < 100) DEFAULT 0,            --valor porcentaje retencion
    val_reteica	        DECIMAL(2,0)	NOT NULL CHECK(val_reteica  >= 0   AND val_reteica  < 100) DEFAULT 0,           --valor porcentaje reteica
    val_porutil	        DECIMAL(3,0)	NOT NULL CHECK(val_porutil  >= 0   AND val_porutil  <= 100) DEFAULT 0,          --valor porcentaje utilidad
    val_latitud	        DECIMAL(18,16)	NOT NULL CHECK(val_latitud  >= -5  AND val_latitud  <= 17),	                    --valor latitud
    val_longitud	    DECIMAL(18,16)	NOT NULL CHECK(val_longitud >= -82 AND val_longitud <= -66),                    --valor longitud
    anio_fiscal         DECIMAL(4,0)    NOT NULL,                                                                       --Año fiscal en el estamos actualmente
    mes_fiscal          DECIMAL(2,0)    NOT NULL,                                                                       --mes fiscal en el que estamos actualmente
    ind_autorete        BOOLEAN	        NOT NULL, --TRUE = autorete / FALSE = no autorete                               --indicador autoretenedor
    riesgo_arl          CHAR(1)         NOT NULL UNIQUE CHECK(LENGTH(riesgo_arl) >=1 AND LENGTH(riesgo_arl) <= 5),        -- 1 = 0.522%, 2 = 1.044%, 3 = 2.436%, 4 = 4.350%, 5 = 6.960% PORCENTAJE QUE DEBE PAGAR LA ARL POR EL RIESGO
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE, --TRUE: Borrado lógico (Inactivo) / FALSE: Activo	    --indicador de borrado lógico
    val_ipc             DECIMAL(6,4)    NOT NULL DEFAULT 0.0000 CHECK(val_ipc >= 0 AND val_ipc <= 100),                 -- (usuarios 14-nov) IPC anual (%) (módulo financiero)
    val_cadu_pass       DECIMAL(3,0)    NOT NULL DEFAULT 90 CHECK(val_cadu_pass >= 0 AND val_cadu_pass <= 365),         -- (usuarios 14-nov) días de vigencia de la clave (0 = no caduca)
    nom_logo            VARCHAR(40)     NOT NULL DEFAULT 'ND' CHECK(nom_logo = 'ND' OR nom_logo ~ '^logo_[0-9a-f]{16}\.(png|jpg|webp)$'), -- (logo 17-nov) archivo del logo en html/img/empresa/ ('ND' = logo de ADSO ERP)
    ind_logo_mono       BOOLEAN         NOT NULL DEFAULT FALSE,                                                         -- (logo 17-nov) TRUE = logo de un solo color: en fondos oscuros se pinta en blanco

    PRIMARY KEY(id_empresa),
    CONSTRAINT verificar_anio CHECK(anio_fiscal = EXTRACT (YEAR FROM CURRENT_DATE)), 
    CONSTRAINT verificar_mes  CHECK(mes_fiscal  = EXTRACT (MONTH FROM CURRENT_DATE)) 
);


CREATE TABLE IF NOT EXISTS tab_menu_palettes
(
    id_palette          VARCHAR(30)     NOT NULL,                                           -- Identificador único de la paleta (ej: 'blue_pro')
    nom_palette         VARCHAR(50)     NOT NULL,                                           -- Nombre descriptivo (ej: 'Azul Profesional')
    des_palette         TEXT            NOT NULL DEFAULT 'Sin descripción de la paleta',    -- Descripción de la paleta
    val_primary_color   VARCHAR(7)      NOT NULL DEFAULT '#1a1a2e',                       -- Color principal del menú (gradiente inicio)
    val_secondary_color VARCHAR(7)      NOT NULL DEFAULT '#16213e',                       -- Color secundario del menú (gradiente fin)
    val_accent_color    VARCHAR(7)      NOT NULL DEFAULT '#00d9ff',                       -- Color de acento (hover, active, iconos)
    val_text_color      VARCHAR(7)      NOT NULL DEFAULT '#ffffff',                       -- Color del texto en el menú superior
    val_hover_color     VARCHAR(7)      NOT NULL DEFAULT '#00d9ff',                       -- Color al pasar el mouse
    val_sidebar_bg      VARCHAR(7)      NOT NULL DEFAULT '#ffffff',                       -- Fondo del sidebar
    val_sidebar_text    VARCHAR(7)      NOT NULL DEFAULT '#555555',                       -- Color del texto en sidebar
    val_sidebar_hover   VARCHAR(7)      NOT NULL DEFAULT '#f4f7ff',                       -- Fondo al pasar el mouse
    val_active_bg       VARCHAR(7)      NOT NULL DEFAULT '#00aaff',                       -- Color del item activo
    num_orden           INTEGER         NOT NULL DEFAULT 0,                                 -- Orden de visualización
    ind_active          BOOLEAN         NOT NULL DEFAULT FALSE,                             -- Si es la paleta por defecto
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                             -- TRUE: Borrado lógico / FALSE: Activo
    PRIMARY KEY (id_palette)
);

-- (temporadas 18-nov) Modo Navidad y otras fechas especiales
-- ---------------------------------------------------------------------------
-- TABLA tab_temporadas
-- Una fila por temporada. Las fechas son día y mes (se repiten cada año) y el
-- rango puede cruzar el año (1-dic → 7-ene).
-- ind_modo: 'A' automático por fechas · 'E' encendida siempre · 'X' apagada
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_temporadas
(
    id_temporada    VARCHAR(20)     NOT NULL CHECK(id_temporada ~ '^[a-z0-9_]{3,20}$'),                     -- identificador (ej: 'navidad')
    nom_temporada   VARCHAR(40)     NOT NULL CHECK(LENGTH(nom_temporada) >= 3 AND LENGTH(nom_temporada) <= 40), -- nombre visible
    ind_modo        CHAR(1)         NOT NULL DEFAULT 'A' CHECK(ind_modo IN ('A', 'E', 'X')),                -- A automático / E encendida / X apagada
    val_mes_inicio  DECIMAL(2,0)    NOT NULL CHECK(val_mes_inicio BETWEEN 1 AND 12),                         -- mes en que empieza
    val_dia_inicio  DECIMAL(2,0)    NOT NULL CHECK(val_dia_inicio BETWEEN 1 AND 31),                         -- día en que empieza
    val_mes_fin     DECIMAL(2,0)    NOT NULL CHECK(val_mes_fin BETWEEN 1 AND 12),                            -- mes en que termina
    val_dia_fin     DECIMAL(2,0)    NOT NULL CHECK(val_dia_fin BETWEEN 1 AND 31),                            -- día en que termina (incluido)
    des_saludo      VARCHAR(120)    NOT NULL CHECK(LENGTH(des_saludo) >= 3),                                 -- saludo que se muestra en todo el sitio
    des_horario     VARCHAR(200)    NOT NULL DEFAULT 'ND',                                                   -- aviso de horario en la landing ('ND' = no se muestra)
    ind_borrado     BOOLEAN         NOT NULL DEFAULT FALSE,                                                  -- TRUE: borrado lógico / FALSE: activa
    PRIMARY KEY (id_temporada)
);


-- 7. TABLA DEPARTAMENTOS DE COLOMBIA 

CREATE TABLE IF NOT EXISTS tab_dptos
(
    id_dpto	            VARCHAR         NOT NULL CHECK(LENGTH(id_dpto) = 2),                                            --identificador del departamento
    nom_dpto	        VARCHAR	        NOT NULL CHECK(LENGTH(nom_dpto) >= 4 AND LENGTH(nom_dpto) <= 20),               --nombre del departamento
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE, --TRUE: Borrado lógico (Inactivo) / FALSE: Activo       --indicador de borrado lógico
    PRIMARY KEY(id_dpto)
);


-- 8. TABLA CIUDADES DE COLOMBIA

CREATE TABLE IF NOT EXISTS tab_ciudades
(
    id_ciudad	        VARCHAR	        NOT NULL CHECK(LENGTH(id_ciudad) = 5),									    	--identificador de la ciudad									
    nom_ciudad	        VARCHAR	        NOT NULL CHECK(LENGTH(nom_ciudad) >= 3 AND LENGTH(nom_ciudad) <= 30), 		    --nombre de la ciudad
    id_dpto     	    VARCHAR	        NOT NULL CHECK(LENGTH(id_dpto) = 2),											--identidicador del departamento
    ind_capital	        BOOLEAN	        NOT NULL,   --True = capital / false = no capital							    --indicador de la capital
    cod_postal	        VARCHAR	        NOT NULL CHECK(LENGTH(cod_postal) = 6),										    --codigo postal
    val_latitud         DECIMAL(18,16)	NOT NULL CHECK(val_latitud >= -5    AND val_latitud <= 17), 					--valor latitud
    val_longitud        DECIMAL(18,16)  NOT NULL CHECK(val_longitud >= -82  AND val_longitud <= -66), 				    --valor longitud
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE, --TRUE: Borrado lógico (Inactivo) / FALSE: Activo	    --indicador de borrado lógico

    PRIMARY KEY(id_ciudad),
    FOREIGN KEY (id_dpto) REFERENCES tab_dptos(id_dpto)
);

-----------------------------------------------------------------------------------
-- TABLA DE CATEGORIAS DE TERCEROS                                      	     --
-----------------------------------------------------------------------------------		

CREATE TABLE IF NOT EXISTS tab_cat_terceros
(			
	id_cat_tercero 		DECIMAL(2,0)	NOT NULL CHECK(id_cat_tercero > 0 AND id_cat_tercero <= 99),					    --identificador de la categoria 
	nom_cat_tercero		VARCHAR			NOT NULL CHECK(LENGTH(nom_cat_tercero) >= 4 AND LENGTH(nom_cat_tercero) <= 50),	    --Nombre de la categoria tercero
	PRIMARY KEY(id_cat_tercero)			
);			
INSERT INTO tab_cat_terceros VALUES(1,'CLIENTE');			
INSERT INTO tab_cat_terceros VALUES(2,'VENDEDOR');			
INSERT INTO tab_cat_terceros VALUES(3,'EMPLEADO');			
INSERT INTO tab_cat_terceros VALUES(4,'LEAD');			
INSERT INTO tab_cat_terceros VALUES(5,'PROVEEDOR');			
			
-----------------------------------------------------------------------------------
-- TABLA DE RESTRICCIONES DE LOS TERCEROS, QUE IMPIDEN SU ACCESO AL SISTEMA	     --
-----------------------------------------------------------------------------------			
CREATE TABLE IF NOT EXISTS tab_restricciones			
(			
	id_restriccion		DECIMAL(2,0)	NOT NULL CHECK(id_restriccion > 0 AND id_restriccion <= 99),				        --identificador de la restrinción	
	nom_restriccion		VARCHAR			NOT NULL CHECK(LENGTH(nom_restriccion) >= 4 AND LENGTH(nom_restriccion) <= 50),	    --Nombre de la restrinción
	PRIMARY KEY(id_restriccion)			
);	
INSERT INTO tab_restricciones VALUES(99,'No aplica.');			
INSERT INTO tab_restricciones VALUES(1,'Finalización Contrato Mutuo Acuerdo');			
INSERT INTO tab_restricciones VALUES(2,'Vacaciones Colectivas');			
INSERT INTO tab_restricciones VALUES(3,'Inhabilidad Legal');			
INSERT INTO tab_restricciones VALUES(4,'Restricción Día Festivo');			

CREATE TABLE tab_tipo_identidad 
(
    id_tipo    	VARCHAR(5)   NOT NULL CHECK(id_tipo ~ '^[A-Z]{2,5}$'),                           --  tipo de documento
    nom_tipo    VARCHAR      NOT NULL check(LENGTH(nom_tipo) >= 5 AND LENGTH(nom_tipo) <= 50),    -- Nombre del tipo de documnento
    PRIMARY KEY(id_tipo)
);

CREATE TABLE tab_tel_prefijo
(
    id_prefijo  DECIMAL(4,0)    NOT NULL CHECK(id_prefijo > 0 AND id_prefijo <= 9999),
    nom_pais    VARCHAR(50)     NOT NULL CHECK(LENGTH(nom_pais) >= 4 AND LENGTH(nom_pais) <= 50),
    PRIMARY KEY(id_prefijo)
);

-------------------------
-- TABLA DE TERCEROS.  --
------------------------- 
--ES TRANSVERSAL. TODA PERSONA DEBE ESTAR REGISTRADA EN ESTA TABLA.			
-- TIENE EXTENSIONES COMO CLIENTES, VENDEDORES, EMPLEADO, ETC. Y CADA EXTENSIÓN TIENE LOS DATOS PARTICULARES			
CREATE TABLE IF NOT EXISTS tab_terceros			
(			
    id_tipo        		VARCHAR(5)      NOT NULL CHECK(id_tipo ~ '^[A-Z]{2,5}$'),                                   --  tipo de documento
    id_tercero          VARCHAR(10)     NOT NULL CHECK(id_tercero ~ '^[A-Z0-9]{7,10}$'),		                    --  identificador de terceros
	ind_tipo_tercero	BOOLEAN			NOT NULL, --TRUE:Jurídica / FALSE:Natural								    --  tipo de tercero si es persona natural o jurídica
	id_cat_tercero		DECIMAL(2,0)	NOT NULL CHECK(id_cat_tercero > 0 AND id_cat_tercero <= 99),			    --  identifiador de la categoria 
	nom_tercero			VARCHAR			NOT NULL CHECK(LENGTH(nom_tercero) >= 4 AND LENGTH(nom_tercero) <= 50),	    --  nombre del tercero
	dir_tercero			DATOS_UBICACION,																		    --  Estructura de   datos de ubicación de terceros
	id_ciudad			VARCHAR			NOT NULL ,																    --  identificador de ciudad
	id_restriccion		DECIMAL(2,0)	NOT NULL CHECK(id_restriccion > 0 AND id_restriccion <= 99),			    --  identificador de las restrincion
	ind_estado			BOOLEAN			NOT NULL, --TRUE:Activo ( FALSE:Inactivo)								    --  indicador de estado del tercero
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE, --TRUE: Borrado lógico (Inactivo) / FALSE: Activo   --  indicador de borrado lógico
	PRIMARY KEY(id_tercero),			
	FOREIGN KEY(id_ciudad)			REFERENCES tab_ciudades(id_ciudad),			
	FOREIGN KEY(id_cat_tercero)		REFERENCES tab_cat_terceros(id_cat_tercero),			
	FOREIGN KEY(id_restriccion)		REFERENCES tab_restricciones(id_restriccion),
    FOREIGN KEY(id_tipo)            REFERENCES tab_tipo_identidad(id_tipo)
);

-------------------------
-- TABLA DE BANCOS.    --
------------------------- 
CREATE TABLE IF NOT EXISTS tab_bancos
(
    id_banco			VARCHAR     	NOT NULL CHECK(LENGTH(id_banco) >= 6 AND (LENGTH(id_banco) <= 10)),														        --identificador del banco
    nom_banco			VARCHAR			NOT NULL CHECK(LENGTH(nom_banco) >= 4 AND LENGTH(nom_banco) <= 50),	        --nombre del banco
    ind_estado			BOOLEAN			NOT NULL, --TRUE:Activo ( FALSE:Inactivo)								    --indicador de estado del banco
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE, --TRUE: Borrado lógico (Inactivo) / FALSE: Activo   --indicador de borrado lógico
    PRIMARY KEY(id_banco)
);

-----------------------
-- TABLA DE FESTIVOS --
-----------------------
CREATE TABLE IF NOT EXISTS tab_festivos
(
    id_festivo         DECIMAL(4,0)         NOT NULL CHECK((id_festivo >= 0 AND id_festivo <= 9999)),                                                   -- Identificador del día festivo
    fecha              DATE                 NOT NULL DEFAULT CURRENT_DATE,                                                                              -- Fecha de el día festivo (no se restringe a futuro: debe poder cargarse el calendario completo del año)
    nom_festivo        VARCHAR(50)          NOT NULL CHECK((LENGTH(nom_festivo) >= 3) AND (LENGTH(nom_festivo) <= 50)) DEFAULT 'Día sin especificar',   -- Nombre descriptivo
    ind_borrado        BOOLEAN              NOT NULL DEFAULT FALSE,                   										                            -- TRUE: Borrado lógico (Inactivo) / FALSE: Activo
     
    PRIMARY KEY (id_festivo)
);
-----------------------------------------
--MÓDULO DE CONTABILIDAD Y PRESUPUESTO --
-----------------------------------------


-------------------------------------------------------------------
--
--      PLAN UNICO DE CUENTAS (PUC)
--
--------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_puc
(
    id_nivel            DECIMAL(1,0)    NOT NULL CHECK(id_nivel >=  1 AND id_nivel <= 9),        -- Nivel jerárquico (1-9)
    id_cod_puc          VARCHAR(20)     NOT NULL, -- CHECK(id_cod_puc > 0),                      -- Código de la cuenta (ej: 110505)
    nom_cuenta          VARCHAR(60)     NOT NULL CHECK(LENGTH(nom_cuenta) >= 3),                 -- Nombre de la cuenta
    ind_natura          BOOLEAN         NOT NULL,                                                -- TRUE=Débito, FALSE=Crédito
    descrip_puc         VARCHAR(200)    DEFAULT 'N/A',                                           -- Descripción opcional
    cod_superior        VARCHAR(20)     NOT NULL,                                                -- Código del padre (0 si nivel 1)
    ind_req_tercero     BOOLEAN         NOT NULL DEFAULT FALSE,                                  -- Requiere tercero (cliente/proveedor)
    ind_estado          BOOLEAN         NOT NULL DEFAULT TRUE,                                   -- TRUE=activo, FALSE=inactivo
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                  -- Borrado lógico
    val_saldo           NUMERIC(18,2)   NOT NULL DEFAULT 0,                                      -- (1.3) Saldo según naturaleza (calculado por fun_recalcular_saldo_puc)
    id_tercero          VARCHAR(10),                                                             -- (1.3) Tercero de la cuenta (FK al final del script)
    PRIMARY KEY(id_nivel, id_cod_puc),                                                           -- Llave primaria compuesta
    CONSTRAINT chk_puc_codigo   CHECK(id_cod_puc ~ '^[0-9]+$'),                                  -- Solo números en el código  -- REVISAR CON PEREZ  --
    CONSTRAINT chk_puc_superior
    CHECK(                                                                                       -- Regla jerárquica
        (id_nivel = 1 AND cod_superior = '0') OR                                                 -- Nivel 1: superior = 0
        (id_nivel > 1 AND cod_superior != '0' AND LENGTH(cod_superior) < LENGTH(id_cod_puc))     -- Niveles >1: superior existe y es más corto
    )
);


-------------------------------------------------------------------
--
--      ACTIVOS FIJOS Y DEPRECIACIÓN
--
--------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS tab_cat_activos
(
    id_categoria_act    DECIMAL(2,0)    NOT NULL CHECK(id_categoria_act BETWEEN 1 AND 99),                  -- ID de categoría (1-99)
    nom_categoria       VARCHAR(30)     NOT NULL CHECK(LENGTH(nom_categoria) >= 3),                         -- Nombre (ej: Equipo de Cómputo)
    vida_util_meses     DECIMAL(3,0)    NOT NULL DEFAULT 60,                                                -- Vida útil en meses
    metodo_depreciacion CHAR(1)         NOT NULL DEFAULT 'L' CHECK(metodo_depreciacion IN ('L', 'S')),      -- L=Linea Recta, S=Saldo Decreciente
    ind_estado          BOOLEAN         NOT NULL DEFAULT TRUE,                                              -- TRUE=activo
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                             -- Borrado lógico
    PRIMARY KEY(id_categoria_act)                                                                           -- Llave primaria simple
);


CREATE TABLE IF NOT EXISTS tab_act_fijos
(
    id_activo           DECIMAL(10,0)   NOT NULL CHECK(id_activo > 0),                                     -- ID del activo
    id_categoria_act    DECIMAL(2,0)    NOT NULL,                                                          -- Categoría (FK)
    num_placa           VARCHAR(20)     NOT NULL UNIQUE,                                                   -- Código único del activo
    nom_activo          VARCHAR(30)     NOT NULL CHECK(LENGTH(nom_activo) >= 3),                           -- Nombre
    fecha_compra        DATE            NOT NULL CHECK(fecha_compra <= CURRENT_DATE),                      -- Fecha de compra
    val_compra          DECIMAL(15,0)   NOT NULL CHECK(val_compra > 0),                                    -- Valor de compra
    val_residual        DECIMAL(15,0)   NOT NULL DEFAULT 0,                                                -- Valor residual
    depre_acumulada     DECIMAL(15,0) NOT NULL DEFAULT 0,                                                  -- Depreciación acumulada
    ind_estado_activo   CHAR(1)         NOT NULL DEFAULT 'A' CHECK(ind_estado_activo IN ('A', 'B', 'D')),  -- A=Activo, B=Baja, D=Depreciado
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                            -- Borrado lógico
    PRIMARY KEY(id_activo),                                                                                -- Llave primaria
    FOREIGN KEY(id_categoria_act) REFERENCES tab_cat_activos(id_categoria_act),                            -- FK a categoría
    CONSTRAINT chk_activo_residual CHECK (val_residual < val_compra),                                      -- Residual debe ser menor a compra
    CONSTRAINT chk_activo_depreciacion CHECK (depre_acumulada <= (val_compra - val_residual))              -- No depreciar más de lo debido
);


CREATE TABLE IF NOT EXISTS tab_depreciacion
(
    id_depreciacion     DECIMAL(10,0)   NOT NULL CHECK(id_depreciacion > 0),                                     -- ID de depreciación
    id_activo           DECIMAL(10,0)   NOT NULL,                                                                -- Activo
    fec_mes             DECIMAL(10,0)   NOT NULL,                                                                -- Fecha del mes de depreciación (YYYYMM)
    val_depreciacion    DECIMAL(15,0)   NOT NULL CHECK(val_depreciacion > 0),                                    -- Valor depreciado este período
    depreciacion_acumulada_antes DECIMAL(15,0) NOT NULL,                                                         -- Acumulado ANTES de esta depreciación
    depreciacion_acumulada_despues DECIMAL(15,0) NOT NULL,                                                       -- Acumulado DESPUÉS de esta depreciación
    id_comprobante      DECIMAL(10,0),                                                                           -- Comprobante contable asociado
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                                  -- Borrado lógico
    PRIMARY KEY(id_depreciacion),                                                                                -- Llave primaria
    FOREIGN KEY(id_activo) REFERENCES tab_act_fijos(id_activo),                                                  -- FK a activo
    CONSTRAINT chk_depreciacion_aumenta CHECK (depreciacion_acumulada_despues > depreciacion_acumulada_antes)    -- La depreciación siempre aumenta
);

-------------------------------------------------------------------
--
--      PRESUPUESTO
--
--------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS tab_period_presupuesto
(
    id_periodo          DECIMAL(10,0)   NOT NULL CHECK(id_periodo > 0),                         -- ID del período
    anio_periodo        DECIMAL(4,0)    NOT NULL CHECK(anio_periodo BETWEEN 2000 AND 2100),     -- Año (2000-2100)
    mes_periodo         DECIMAL(2,0)    NOT NULL CHECK(mes_periodo BETWEEN 1 AND 12),           -- Mes (1-12)
    ind_estado          BOOLEAN         NOT NULL DEFAULT TRUE,                                  -- TRUE=activo
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                 -- Borrado lógico
    PRIMARY KEY(id_periodo)                                                                     -- Llave primaria
);

CREATE TABLE IF NOT EXISTS tab_tipo_presupuesto
(
    id_tipo_presupuesto DECIMAL(10,0)   NOT NULL CHECK(id_tipo_presupuesto > 0),                -- ID del tipo
    nom_tipo            VARCHAR(30)     NOT NULL CHECK(LENGTH(nom_tipo) >= 3),                  -- Nombre del tipo
    descrip_tipo        VARCHAR(200)    DEFAULT '',                                             -- Descripción
    ind_estado          BOOLEAN         NOT NULL DEFAULT TRUE,                                  -- TRUE=activo
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                 -- Borrado lógico
    PRIMARY KEY(id_tipo_presupuesto)                                                            -- Llave primaria
);

CREATE TABLE IF NOT EXISTS tab_enc_presupuesto
(
    id_presupuesto          DECIMAL(10,0)   NOT NULL CHECK(id_presupuesto > 0),                 -- ID del presupuesto
    id_area                 DECIMAL(10,0)   NOT NULL,                                           -- Área (FK)
    id_periodo              DECIMAL(10,0)   NOT NULL,                                           -- Período contable (FK)
    id_tipo_presupuesto     DECIMAL(10,0)   NOT NULL,                                           -- Tipo de presupuesto (FK)
    descrip_presupuesto     VARCHAR(200)    DEFAULT '',                                         -- Descripción
    fecha_aprobacion        DATE,                                                               -- Fecha de aprobación
    total_presupuesto       DECIMAL(15,0)   NOT NULL DEFAULT 0,                                 -- TOTAL PRESUPUESTO (SUMATORIA DE LOS ITEMS DEL MES)
    ind_borrado             BOOLEAN         NOT NULL DEFAULT FALSE,                             -- Borrado lógico
    PRIMARY KEY(id_presupuesto),                                                                -- Llave primaria
    FOREIGN KEY(id_area)        REFERENCES tab_areas(id_area),                                  -- FK a área
    FOREIGN KEY(id_periodo)     REFERENCES tab_period_presupuesto(id_periodo),                  -- FK a período
    FOREIGN KEY(id_tipo_presupuesto)  REFERENCES tab_tipo_presupuesto(id_tipo_presupuesto)      -- FK a tipo
);

CREATE TABLE IF NOT EXISTS tab_planeacion_presupuesto
(
    id_plan                 DECIMAL(10,0)   NOT NULL CHECK(id_plan > 0),                        -- ID del plan
    id_area                 DECIMAL(10,0)   NOT NULL,                                           -- Área (FK)
    id_periodo              DECIMAL(10,0)   NOT NULL,                                           -- Período contable (FK)
    id_nivel                DECIMAL(1,0)    NOT NULL CHECK(id_nivel >=  1 AND id_nivel <= 9),        -- Nivel jerárquico (1-9)
    id_cod_puc              VARCHAR(20)     NOT NULL,                                           --
    val_planeado            DECIMAL(15,0)   NOT NULL CHECK(val_planeado >= 0),                  --
    val_ejecutado           DECIMAL(15,0)   NOT NULL DEFAULT 0,                                 --
    ind_mes_cerrado         BOOLEAN         NOT NULL DEFAULT FALSE,                             -- TRUE=mes cerrado, no se permiten cambios
    ind_borrado             BOOLEAN         NOT NULL DEFAULT FALSE,                             -- Borrado lógico
    PRIMARY KEY(id_plan),                                                                       -- Llave primaria
    FOREIGN KEY(id_area) REFERENCES tab_areas(id_area),                                         -- FK a área
    FOREIGN KEY(id_periodo) REFERENCES tab_period_presupuesto(id_periodo),                      -- FK a período
    FOREIGN KEY(id_nivel, id_cod_puc) REFERENCES tab_puc(id_nivel, id_cod_puc)                  -- FK a PUC
);

CREATE TABLE IF NOT EXISTS tab_det_presupuesto
(
    id_det_presupuesto      DECIMAL(10,0)   NOT NULL,                                                   -- ID del detalle
    id_presupuesto          DECIMAL(10,0)   NOT NULL,                                                   -- Presupuesto (FK)
    id_plan                 DECIMAL(10,0)   NOT NULL,                                                   -- Plan (FK)
    monto_aprobado          DECIMAL(15,0)   NOT NULL CHECK(monto_aprobado >= 0),                        -- Monto aprobado
    monto_comprometido      DECIMAL(15,0)   NOT NULL DEFAULT 0,                                         -- Monto comprometido (pedidos)
    monto_ejecutado         DECIMAL(15,0)   NOT NULL DEFAULT 0,                                         -- Monto ejecutado (real)
    ind_borrado             BOOLEAN         NOT NULL DEFAULT FALSE,                                     -- Borrado lógico
    PRIMARY KEY(id_det_presupuesto),                                                                    -- Llave primaria
    FOREIGN KEY(id_presupuesto) REFERENCES tab_enc_presupuesto(id_presupuesto),                         -- FK a presupuesto
    FOREIGN KEY(id_plan)        REFERENCES tab_planeacion_presupuesto(id_plan),                         -- FK a plan
    CONSTRAINT chk_det_presupuesto_comprometido CHECK (monto_comprometido <= monto_aprobado),           -- No comprometer más de lo aprobado
    CONSTRAINT chk_det_presupuesto_ejecutado    CHECK (monto_ejecutado <= monto_aprobado)               -- No ejecutar más de lo aprobado
);

-- ===================================================================
-- PLANTILLA DE PRESUPUESTO (GLOBAL — la define el gerente general)
-- ===================================================================

CREATE TABLE IF NOT EXISTS tab_plantilla_presupuesto
(
    id_plantilla        DECIMAL(10,0)   NOT NULL CHECK (id_plantilla > 0),
    nom_plantilla       VARCHAR(100)    NOT NULL CHECK (LENGTH(TRIM(nom_plantilla)) >= 5),
    anio_plantilla      DECIMAL(4,0)    NOT NULL CHECK (anio_plantilla BETWEEN 2000 AND 2100),
    id_tipo_presupuesto DECIMAL(10,0)   NOT NULL,
    ind_estado          BOOLEAN         NOT NULL DEFAULT TRUE,
    fec_registro        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fec_modif           TIMESTAMP,
    usuario_crea        VARCHAR(50)     NOT NULL,
    usuario_modif       VARCHAR(50),
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,
    PRIMARY KEY (id_plantilla),
    FOREIGN KEY (id_tipo_presupuesto) REFERENCES tab_tipo_presupuesto(id_tipo_presupuesto)
);

-- Índice: solo una plantilla activa por (año, tipo)
CREATE UNIQUE INDEX IF NOT EXISTS idx_plant_unica_activa
    ON tab_plantilla_presupuesto(anio_plantilla, id_tipo_presupuesto)
    WHERE ind_borrado = FALSE AND ind_estado = TRUE;

CREATE INDEX IF NOT EXISTS idx_plant_anio
    ON tab_plantilla_presupuesto(anio_plantilla)
    WHERE ind_borrado = FALSE;


-- -------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS tab_det_plantilla_presupuesto
(
    id_det_plantilla    DECIMAL(10,0)   NOT NULL CHECK (id_det_plantilla > 0),
    id_plantilla        DECIMAL(10,0)   NOT NULL,
    id_nivel            DECIMAL(1,0)    NOT NULL CHECK (id_nivel BETWEEN 1 AND 9),
    id_cod_puc          VARCHAR(20)     NOT NULL,
    num_orden           DECIMAL(4,0)    NOT NULL DEFAULT 0,       -- ordenado por código PUC
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,
    PRIMARY KEY (id_det_plantilla),
    FOREIGN KEY (id_plantilla) REFERENCES tab_plantilla_presupuesto(id_plantilla) ON DELETE CASCADE,
    FOREIGN KEY (id_nivel, id_cod_puc) REFERENCES tab_puc(id_nivel, id_cod_puc)
);

-- Una cuenta no puede estar dos veces en la misma plantilla.
CREATE UNIQUE INDEX IF NOT EXISTS idx_det_plant_cuenta_unica
    ON tab_det_plantilla_presupuesto(id_plantilla, id_nivel, id_cod_puc)
    WHERE ind_borrado = FALSE;

CREATE INDEX IF NOT EXISTS idx_det_plant_plantilla
    ON tab_det_plantilla_presupuesto(id_plantilla, num_orden)
    WHERE ind_borrado = FALSE;

-- ===================================================================
-- DETALLE MENSUAL DEL PRESUPUESTO
-- ===================================================================
CREATE TABLE IF NOT EXISTS tab_det_presupuesto_mensual
(
    id_det_presupuesto  DECIMAL(10,0)   NOT NULL,
    num_mes             DECIMAL(2,0)    NOT NULL CHECK (num_mes BETWEEN 1 AND 12),
    val_estimado        DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK (val_estimado       >= 0),
    val_aprobado        DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK (val_aprobado       >= 0),
    val_comprometido    DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK (val_comprometido   >= 0),
    val_ejercido        DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK (val_ejercido       >= 0),
    val_presu_anterior  DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK (val_presu_anterior >= 0),
    fec_actualiza       TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario_actualiza   VARCHAR(50)     NOT NULL,
    PRIMARY KEY (id_det_presupuesto, num_mes),
    FOREIGN KEY (id_det_presupuesto) REFERENCES tab_det_presupuesto(id_det_presupuesto) ON DELETE CASCADE,
    -- chk_dpm_aprobado fue ELIMINADO (ya no bloquea aprobar > estimado)
    CONSTRAINT chk_dpm_comprom  CHECK (val_comprometido <= val_aprobado),
    CONSTRAINT chk_dpm_ejercido CHECK (val_ejercido     <= val_aprobado)
);

CREATE INDEX IF NOT EXISTS idx_dpm_detalle
    ON tab_det_presupuesto_mensual(id_det_presupuesto);

-- ===================================================================
-- HISTÓRICO DE PRESUPUESTO (snapshot inmutable al cierre anual)
-- ===================================================================

CREATE TABLE IF NOT EXISTS tab_historico_presupuesto
(
    id_historico        DECIMAL(10,0)   NOT NULL CHECK (id_historico > 0),
    anio_historico      DECIMAL(4,0)    NOT NULL CHECK (anio_historico BETWEEN 2000 AND 2100),
    id_area             DECIMAL(5,0)    NOT NULL,
    id_tipo_presupuesto DECIMAL(10,0)   NOT NULL,
    id_pre_origen       DECIMAL(10,0)   NOT NULL,     -- FK lógica al encabezado original
    total_estimado      DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK (total_estimado >= 0),
    total_aprobado      DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK (total_aprobado >= 0),
    total_ejercido      DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK (total_ejercido >= 0),
    fec_cierre          TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario_cierre      VARCHAR(50)     NOT NULL,
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,
    PRIMARY KEY (id_historico),
    FOREIGN KEY (id_area)             REFERENCES tab_areas(id_area),
    FOREIGN KEY (id_tipo_presupuesto) REFERENCES tab_tipo_presupuesto(id_tipo_presupuesto)
);

-- Un solo histórico activo por (año, área, tipo).
CREATE UNIQUE INDEX IF NOT EXISTS idx_hist_unico
    ON tab_historico_presupuesto(anio_historico, id_area, id_tipo_presupuesto)
    WHERE ind_borrado = FALSE;

CREATE INDEX IF NOT EXISTS idx_hist_anio_area
    ON tab_historico_presupuesto(anio_historico, id_area)
    WHERE ind_borrado = FALSE;

-- -------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS tab_det_historico_presupuesto
(
    id_historico        DECIMAL(10,0)   NOT NULL,
    id_nivel            DECIMAL(1,0)    NOT NULL CHECK (id_nivel BETWEEN 1 AND 9),
    id_cod_puc          VARCHAR(20)     NOT NULL,
    num_mes             DECIMAL(2,0)    NOT NULL CHECK (num_mes BETWEEN 1 AND 12),
    val_estimado        DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK (val_estimado >= 0),
    val_aprobado        DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK (val_aprobado >= 0),
    val_ejercido        DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK (val_ejercido >= 0),
    PRIMARY KEY (id_historico, id_nivel, id_cod_puc, num_mes),
    FOREIGN KEY (id_historico)        REFERENCES tab_historico_presupuesto(id_historico) ON DELETE CASCADE,
    FOREIGN KEY (id_nivel, id_cod_puc) REFERENCES tab_puc(id_nivel, id_cod_puc)
);

CREATE INDEX IF NOT EXISTS idx_det_hist_puc
    ON tab_det_historico_presupuesto(id_nivel, id_cod_puc);
-------------------------------------------------------------------
--
--      COMPROBANTES CONTABLES
--
--------------------------------------------------------------------


CREATE TABLE IF NOT EXISTS tab_tip_comprobantes
(
    id_tipcomprobante   SMALLINT   NOT NULL CHECK(id_tipcomprobante > 0),                       -- ID del tipo
    nom_tipcomprobante  VARCHAR(30)     NOT NULL CHECK(LENGTH(nom_tipcomprobante) >= 3),        -- Nombre
    num_inicial         DECIMAL(10,0)   NOT NULL DEFAULT 0,                                     -- Número inicial
    num_final           DECIMAL(10,0)   NOT NULL DEFAULT 0,                                     -- Número final
    num_actual          DECIMAL(10,0)   NOT NULL DEFAULT 0,                                     -- Número actual
    ind_estado          BOOLEAN         NOT NULL DEFAULT TRUE,                                  -- TRUE=activo
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                 -- Borrado lógico
    PRIMARY KEY(id_tipcomprobante)                                                              -- Llave primaria
);

CREATE TABLE IF NOT EXISTS tab_estado_comprobantes
(
    id_estado   SMALLINT    NOT NULL,
    nom_estado  VARCHAR     NOT NULL,
    PRIMARY KEY(id_estado)
);

INSERT INTO tab_estado_comprobantes VALUES(99,'Genérico');
INSERT INTO tab_estado_comprobantes VALUES(1, 'Borrador');
INSERT INTO tab_estado_comprobantes VALUES(4, 'Enviado');
INSERT INTO tab_estado_comprobantes VALUES(5, 'Aprobado');
INSERT INTO tab_estado_comprobantes VALUES(6, 'Rechazado');


CREATE TABLE IF NOT EXISTS tab_enc_comprobantes
(
    num_comprobante         DECIMAL(10,0)   NOT NULL,
    id_tipcomprobante       SMALLINT        NOT NULL,
    fecha_comprobante       DATE            NOT NULL CHECK(fecha_comprobante <= CURRENT_DATE),
    val_concepto            VARCHAR(200)    NOT NULL,
    total_debe              DECIMAL(15,0)   NOT NULL DEFAULT 0,
    total_haber             DECIMAL(15,0)   NOT NULL DEFAULT 0,
    id_estado               SMALLINT        NOT NULL DEFAULT 99,
    -- Trazabilidad
    usuario_crea            VARCHAR(50),
    -- Firma del elaborador (jefe de área que envía)
    firma_elaboro           TEXT,
    fec_firma_elaboro       TIMESTAMP WITHOUT TIME ZONE,
    usuario_elaboro         VARCHAR(50),
    -- Firma del aprobador (gerente/contador que aprueba)
    firma_aprobo            TEXT,
    fec_firma_aprobo        TIMESTAMP WITHOUT TIME ZONE,
    usuario_aprobo          VARCHAR(50),
    -- Rechazo
    motivo_rechazo          TEXT,
    fec_rechazo             TIMESTAMP WITHOUT TIME ZONE,
    usuario_rechazo         VARCHAR(50),
    ind_borrado             BOOLEAN         NOT NULL DEFAULT FALSE,
    PRIMARY KEY(num_comprobante, id_tipcomprobante),
    FOREIGN KEY(id_tipcomprobante) REFERENCES tab_tip_comprobantes(id_tipcomprobante),
    FOREIGN KEY(id_estado)         REFERENCES tab_estado_comprobantes(id_estado)
);

CREATE SEQUENCE IF NOT EXISTS seq_rechazo_linea_presupuesto
    START WITH 1 INCREMENT BY 1 NO CYCLE;

CREATE TABLE IF NOT EXISTS tab_rechazo_linea_presupuesto
(
    id_rechazo_linea    DECIMAL(10,0)   NOT NULL,
    id_presupuesto      DECIMAL(10,0)   NOT NULL,
    id_det_presupuesto  DECIMAL(10,0)   NOT NULL,
    motivo              VARCHAR(250)    NOT NULL,
    val_max_sugerido    DECIMAL(15,0)   NULL,
    fec_rechazo         TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario_rechaza     VARCHAR(50)     NOT NULL,
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,
    PRIMARY KEY (id_rechazo_linea),
    FOREIGN KEY (id_presupuesto)     REFERENCES tab_enc_presupuesto(id_presupuesto),
    FOREIGN KEY (id_det_presupuesto) REFERENCES tab_det_presupuesto(id_det_presupuesto)
);

CREATE INDEX IF NOT EXISTS idx_rechazo_linea_presupuesto
    ON tab_rechazo_linea_presupuesto(id_presupuesto)
    WHERE ind_borrado = FALSE;

CREATE INDEX IF NOT EXISTS idx_rechazo_linea_detalle
    ON tab_rechazo_linea_presupuesto(id_det_presupuesto)
    WHERE ind_borrado = FALSE;
    

CREATE TABLE IF NOT EXISTS tab_det_comprobantes
(
    num_comprobante     DECIMAL(10,0)   NOT NULL,                                                       --
    id_tipcomprobante   SMALLINT        NOT NULL,                                                       -- Tipo (FK)
    num_linea 		SMALLINT 	NOT NULL,                                                                        -- Agregar esta columna
    id_nivel            DECIMAL(1,0)    NOT NULL CHECK(id_nivel >=  1 AND id_nivel <= 9),               -- Nivel jerárquico (1-9)
    id_cod_puc          VARCHAR(20)     NOT NULL,                                                       -- Cuenta PUC (FK)
    descrip_det_comp    VARCHAR(200)    DEFAULT '',                                                     -- Descripción de la línea
    valor_debito        DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK(valor_debito >= 0),                    -- Valor débito
    valor_credito       DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK(valor_credito >= 0),                   -- Valor crédito
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                         -- Borrado lógico
    PRIMARY KEY(num_comprobante, id_tipcomprobante, num_linea),                                         -- Llave primaria
    FOREIGN KEY(num_comprobante, id_tipcomprobante) REFERENCES tab_enc_comprobantes(num_comprobante, id_tipcomprobante) ON DELETE CASCADE,
    FOREIGN KEY(id_nivel, id_cod_puc) REFERENCES tab_puc(id_nivel, id_cod_puc),                         -- FK a PUC
    CONSTRAINT chk_det_comprobante_xor CHECK (                                                          -- Una línea NO puede tener débito y crédito a la vez
    (valor_debito > 0 AND valor_credito = 0) OR (valor_debito = 0 AND valor_credito > 0))
);

CREATE TABLE IF NOT EXISTS tab_ejecucion_presupuesto
(
    id_ejecucion            DECIMAL(10,0)   NOT NULL,                                             -- ID de ejecución
    id_plan                 DECIMAL(10,0)   NOT NULL,                                             -- Plan (FK)
    num_comprobante         DECIMAL(10,0)   NOT NULL,                                             -- Comprobante (FK)
    id_tipcomprobante       SMALLINT        NOT NULL,                                             -- Tipo de comprobante (FK)
    id_det_presupuesto      DECIMAL(10,0)   NOT NULL,                                             -- Detalle (FK)
    valor_real              DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK(valor_real >= 0),            -- Valor real ejecutado
    fecha_registro          DATE            NOT NULL DEFAULT CURRENT_DATE,                        -- Fecha de registro
    ind_borrado             BOOLEAN         NOT NULL DEFAULT FALSE,                               -- Borrado lógico
    PRIMARY KEY(id_ejecucion),                                                                    -- Llave primaria
    FOREIGN KEY(id_plan) REFERENCES tab_planeacion_presupuesto(id_plan),                          -- FK a plan
    FOREIGN KEY(num_comprobante, id_tipcomprobante) REFERENCES tab_enc_comprobantes(num_comprobante, id_tipcomprobante),
    FOREIGN KEY(id_det_presupuesto) REFERENCES tab_det_presupuesto(id_det_presupuesto)   -- FK a detalle
);


CREATE TABLE IF NOT EXISTS tab_parametros_contab
(
    id_empresa          VARCHAR(10)   NOT NULL,															         -- Empresa
    anio_contable       DECIMAL(4,0)    NOT NULL CHECK(anio_contable >= 2000),                                     -- Año contable actual
    mes_contable        DECIMAL(2,0)    NOT NULL CHECK(mes_contable BETWEEN 1 AND 12),                             -- Mes contable actual
    ind_estado_period   BOOLEAN         NOT NULL DEFAULT TRUE,                                                     -- TRUE=período activo
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                                    -- Borrado lógico
    fec_cierre_programado DATE,                                                                                    -- (1.3) Fecha programada de cierre
    motivo_cierre       VARCHAR(250),                                                                              -- (1.3) Motivo del cierre
    observaciones       VARCHAR(500),                                                                              -- (1.3) Observaciones
    val_ipc             NUMERIC(6,2)    NOT NULL DEFAULT 0,                                                        -- (1.3) IPC anual (%) para indexar el presupuesto
    pct_alerta_presup   NUMERIC(5,2)    NOT NULL DEFAULT 80,                                                       -- (1.3) % de ejecución que dispara la alerta
    ind_bloqueo_presup  BOOLEAN         NOT NULL DEFAULT FALSE,                                                    -- (1.3) TRUE: no se ejecuta por encima de lo aprobado
    usuario_cierre      VARCHAR,                                                                                   -- (1.3) Quién cerró el período
    fec_cierre          TIMESTAMP,                                                                                 -- (1.3) Cuándo se cerró
    usuario_modif       VARCHAR,                                                                                   -- (1.3) Último usuario que modificó
    fec_ultima_modif    TIMESTAMP,                                                                                 -- (1.3) Última modificación
    PRIMARY KEY(id_empresa),                                                                                       -- Llave primaria
    CONSTRAINT chk_pc_val_ipc    CHECK (val_ipc BETWEEN -50 AND 100),                                              -- (1.3)
    CONSTRAINT chk_pc_pct_alerta CHECK (pct_alerta_presup BETWEEN 1 AND 100),                                      -- (1.3)
    CONSTRAINT chk_pc_anio_max   CHECK (anio_contable <= 2100),                                                    -- (1.3)
    FOREIGN KEY(id_empresa) REFERENCES tab_pmtros_grales(id_empresa)                                               -- FK a empresa
);

---------------------------------------------
--FIN MÓDULO DE CONTABILIDAD Y PRESUPUESTO --
---------------------------------------------

------------------------------
-- TABLA TIPO DE RIESGOS    --
------------------------------

CREATE TABLE IF NOT EXISTS 	tab_riesgos
(
	id_riesgo				DECIMAL(2,0)		NOT NULL          CHECK(id_riesgo >= 1 AND id_riesgo <= 99),                  -- IDENTIFICADOR DE LOS RIESGOS (SST, GESTIÓN DOCUMENTAL)
    nom_riesgo              VARCHAR         	NOT NULL          CHECK(LENGTH(nom_riesgo) >= 5 AND LENGTH(nom_riesgo)<=100),   -- NOMBRE ASIGNADO AL RIESGO DEPENDIENDO SU CLASIFICACIÓN
	nivel_riesgo			DECIMAL(1,0)    	NOT NULL          CHECK(nivel_riesgo >=1 AND nivel_riesgo<=5),                   -- CLASE I = OFICINISTAS, CLASE II : (como la confección de tejidos y textiles) y ciertas labores agrícolas, CLASE III :  Aplica a procesos de manufactura más complejos, como la fabricación de alimentos, licores, tabaco y productos de cuero o plástico. CLASE IV:   Agrupa procesos industriales pesados y actividades de transporte, CLASE V:  Corresponde a las actividades de mayor peligro e impacto, como la construcción, explotación minera y petrolera, canteras, areneras y manejo de explosivos
	categoria_riesgo		DECIMAL(1,0)		NOT NULL          CHECK(categoria_riesgo >=1 AND categoria_riesgo <= 6),        -- 1 para Físicos, 2 para Químicos, 3 para Biológicos, 4 para Ergonómicos o biomecánicos, 5 para Psicosociales, 6 para Psicosociales.
    riesgo_arl             CHAR(1)         	    NOT NULL,      -- 1 = 0.522%, 2 = 1.044%, 3 = 2.436%, 4 = 4.350%, 5 = 6.960% PORCENTAJE QUE DEBE PAGAR LA ARL POR EL RIESGO
	ind_borrado				BOOLEAN				NOT NULL 	                                                                    DEFAULT FALSE,	
	PRIMARY KEY(id_riesgo)
);

-- ----------------------------------------------------------------------
-- (compras 14-nov) Tablas, vistas y datos iniciales de Compras
-- Traído del script ejecutable de Compras (reemplaza la versión vieja de este archivo).
-- ----------------------------------------------------------------------
-------------------------------------
-- MODULO DE COMPRAS Y PROVEEDORES --
-------------------------------------

-- TABLA DE PAREÁMETROS DE COMPRAS
CREATE TABLE IF NOT EXISTS tab_pmtros_compras 
(
    id_empresa           VARCHAR(10)     NOT NULL CHECK(id_empresa ~ '^[1-9][0-9]{7,9}$'),                                         -- Identificador de la empresa (ID empresa)
    val_puntaje_sel_prov SMALLINT        NOT NULL CHECK(val_puntaje_sel_prov >= 0 AND val_puntaje_sel_prov <= 100) DEFAULT 80,     -- Puntaje de selección de proveedor (0-100)
    val_porutil          DECIMAL(2,0)    NOT NULL CHECK(val_porutil >= 0 AND val_porutil < 100) DEFAULT 0,                         -- % Margen de utilidad
    val_stock_min        DECIMAL(3,0)    NOT NULL CHECK(val_stock_min >= 1 AND val_stock_min <= 999) DEFAULT 1,                                                    -- Stock mínimo (definido por el usuario)
    val_dias_margen_fecha DECIMAL(2,0)   NOT NULL CHECK(val_dias_margen_fecha >= 1 AND val_dias_margen_fecha <= 90) DEFAULT 30,                                     -- Días que la fecha requerida puede pasar de la fecha mínima (1-90)
    val_hora_corte       TIME            NOT NULL DEFAULT '16:00',                                                                                                 -- Hora diaria de consolidación de solicitudes aprobadas
    id_ciudad_entrega    VARCHAR         NOT NULL CHECK(LENGTH(id_ciudad_entrega) = 5),                                                                            -- Ciudad de entrega por defecto de las órdenes de compra
    val_pts_dia_retraso  DECIMAL(2,0)    NOT NULL CHECK(val_pts_dia_retraso >= 1 AND val_pts_dia_retraso <= 50) DEFAULT 5,                                         -- Evaluación automática: puntos de puntualidad que resta cada día de retraso (1-50)
    PRIMARY KEY(id_empresa),
    FOREIGN KEY(id_empresa) REFERENCES tab_pmtros_grales(id_empresa),
    FOREIGN KEY(id_ciudad_entrega) REFERENCES tab_ciudades(id_ciudad)
);

-----------------------
-- TABLA PROVEEDORES --
-----------------------
CREATE TABLE IF NOT EXISTS tab_proveedores
(
    id_proveedor        VARCHAR(10)     NOT NULL CHECK(id_proveedor ~ '^[A-Z0-9]{7,10}$'),                                                                               -- Identificador del proveedor (ID empresa)
    val_sigla           VARCHAR         NOT NULL CHECK(LENGTH(val_sigla) >= 2 AND LENGTH(val_sigla) <= 10 AND val_sigla ~ '^[A-Za-zÁÉÍÓÚáéíóúÑñÜü0-9.&-]+$'),                                                              -- Sigla del proveedor (ej. "PROV1")
    val_latitud         DECIMAL(18,16)  NOT NULL CHECK(val_latitud >= -4 AND val_latitud <= 80) DEFAULT  4.0000000000000000,                                             -- Latitud geográfica del proveedor
    val_longitud        DECIMAL(18,16)  NOT NULL CHECK(val_longitud >= -80 AND val_longitud <= -50) DEFAULT -72.0000000000000000,                                        -- Latitud geográfica del proveedor
    nom_contacto        VARCHAR         NOT NULL CHECK(LENGTH(nom_contacto) >= 5 AND LENGTH(nom_contacto) <= 60 AND nom_contacto ~ '^[A-Za-zÁÉÍÓÚáéíóúÑñÜü0-9 .,&()/''-]+$') DEFAULT 'Sin nombre del contacto',                      -- Nombre del contacto
    tel_contacto        DECIMAL(10,0)   NOT NULL CHECK(tel_contacto >= 0) DEFAULT 0,                                                                                     -- Teléfono del contacto
    nom_cont_contab     VARCHAR         NOT NULL CHECK(LENGTH(nom_cont_contab) >= 5 AND LENGTH(nom_cont_contab) <= 60 AND nom_cont_contab ~ '^[A-Za-zÁÉÍÓÚáéíóúÑñÜü0-9 .,&()/''-]+$') DEFAULT 'Sin nombre del contacto contabilidad',   -- Nombre del contacto contable
    tel_cont_contab     DECIMAL(10,0)   NOT NULL CHECK(tel_cont_contab >= 0) DEFAULT 0,                                                                                  -- Teléfono del contacto contable
    ind_retenedor       BOOLEAN         NOT NULL DEFAULT FALSE,                                                                                                          -- TRUE = Retenedor / FALSE = No retenedor
    ind_credito         BOOLEAN         NOT NULL DEFAULT FALSE,                                                                                                          -- TRUE = Acepta credito / FALSE = No acepta credito         
    ind_num_cuotas      DECIMAL(2,0)    NOT NULL CHECK (ind_num_cuotas >= 1 AND ind_num_cuotas <= 12) DEFAULT 1,                                                         -- Número de cuotas máximo para pagos a crédito (1-12)
    ind_dias_pago       DECIMAL(3,0)    NOT NULL CHECK(ind_dias_pago >= 0 AND ind_dias_pago <= 120) DEFAULT 0,                                                                                   -- Días de pago acordados con el proveedor
    val_saldo_deuda     DECIMAL(11,0)   NOT NULL CHECK(val_saldo_deuda >= 0 AND val_saldo_deuda <= 99999999999) DEFAULT 0,                                               -- Saldo de deuda actual con el proveedor
    val_tiempo_entrega  DECIMAL(3,0)    NOT NULL CHECK(val_tiempo_entrega >= 0 AND val_tiempo_entrega <= 365) DEFAULT 0,                                                 -- Días de entrega del proveedor
    fec_registro        DATE            NOT NULL DEFAULT CURRENT_DATE,                                                                                                   -- Fecha de registro del proveedor
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                                                                                          -- TRUE = Borrado / FALSE = Activo 
    PRIMARY KEY(id_proveedor),
    FOREIGN KEY(id_proveedor) REFERENCES tab_terceros(id_tercero)
);

-------------------------------------
-- TABLA EVALUACIÓN DE PROVEEDORES --
-------------------------------------
CREATE TABLE IF NOT EXISTS tab_eval_prov
(
    id_eva_prov         DECIMAL(3,0)    NOT NULL CHECK(id_eva_prov > 0 AND id_eva_prov <= 999),                            -- Identificador de la evaluación
    id_proveedor        VARCHAR(10)     NOT NULL CHECK(id_proveedor ~ '^[A-Z0-9]{7,10}$'),                                 -- Identificador del proveedor
    fec_evaluacion      DATE            NOT NULL DEFAULT CURRENT_DATE,                                                     -- Fecha de la evaluación
    val_punt_calidad    DECIMAL(3,0)    NOT NULL CHECK(val_punt_calidad >= 0 AND val_punt_calidad <= 100) DEFAULT 0,       -- Puntaje de calidad (0-100)
    val_punt_puntual    DECIMAL(3,0)    NOT NULL CHECK(val_punt_puntual >= 0 AND val_punt_puntual <= 100) DEFAULT 0,       -- Puntaje de puntualidad (0-100)
    val_puntaje_total   DECIMAL(4,2)    NOT NULL CHECK(val_puntaje_total >= 0 AND val_puntaje_total <= 100) DEFAULT 0,     -- Puntaje total (calculado por trigger)
    val_coments         TEXT            NOT NULL CHECK(LENGTH(TRIM(val_coments)) > 0 AND val_coments ~ '^[A-Za-zÁÉÍÓÚáéíóúÑñÜü0-9 \n\r.,;:¿?¡!()"''%/-]+$') DEFAULT 'Sin comentarios',            -- Comentarios de la evaluación
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                                            -- TRUE = Borrado / FALSE = Activo
    PRIMARY KEY(id_eva_prov),
    FOREIGN KEY(id_proveedor) REFERENCES tab_proveedores(id_proveedor)
);
-- Una sola evaluación activa por proveedor (la evaluación automática la actualiza; no crea otra)
CREATE UNIQUE INDEX IF NOT EXISTS uq_eval_prov_activa ON tab_eval_prov(id_proveedor) WHERE ind_borrado = FALSE;

-------------------------------------------
-- TABLA NATURALEZA TRIBUTARIA (CATÁLOGO) --
-------------------------------------------
-- Catálogo de impuestos del módulo de Facturación (Ventas). Se crea aquí, antes de
-- tab_productos, porque cada producto apunta a su naturaleza (id_naturaleza).
-- La tarifa del producto (IVA / INC / exento / excluido) se lee de este catálogo:
-- tab_productos ya NO guarda el porcentaje (se eliminó val_poriva).
-- Los CHECK son los mismos que valida fun_valida_naturaleza_tributaria (Facturación).
CREATE TABLE IF NOT EXISTS tab_naturaleza_tributaria
(
    id_naturaleza       DECIMAL(4,0)    NOT NULL CHECK(id_naturaleza > 0 AND id_naturaleza <= 9999),                                       -- Identificador de la naturaleza tributaria
    nom_naturaleza      VARCHAR(60)     NOT NULL CHECK(LENGTH(TRIM(nom_naturaleza)) >= 3 AND LENGTH(TRIM(nom_naturaleza)) <= 60),          -- Nombre (ej. 'IVA General 19%')
    tip_impuesto        VARCHAR(10)     NOT NULL CHECK(tip_impuesto IN ('IVA','INC','EXCLUIDO','EXENTO','RETEFTE','RETEIVA','RETEICA','ICL')), -- Tipo de impuesto
    cod_dian            VARCHAR(4)      NOT NULL CHECK(cod_dian IN ('01','04','05','06','07','22','ZZ')),                                 -- Código DIAN del tributo
    val_tarifa          DECIMAL(5,2)    NOT NULL CHECK(val_tarifa >= 0 AND val_tarifa <= 100) DEFAULT 0,                                   -- Tarifa en porcentaje
    ind_descontable     BOOLEAN         NOT NULL DEFAULT FALSE,                                                                            -- TRUE = Descontable (solo IVA y EXENTO)
    ind_base_sobre_iva  BOOLEAN         NOT NULL DEFAULT FALSE,                                                                            -- TRUE = Base sobre el valor del IVA (solo RETEIVA)
    ind_estado          BOOLEAN         NOT NULL DEFAULT TRUE,                                                                             -- TRUE = Activa / FALSE = Inactiva
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                                                            -- TRUE = Borrada / FALSE = Activa
    observaciones       VARCHAR(250)    NOT NULL DEFAULT '',                                                                               -- Observaciones
    PRIMARY KEY(id_naturaleza),
    CONSTRAINT exento_excluido_tarifa_0 CHECK(tip_impuesto NOT IN ('EXCLUIDO','EXENTO') OR val_tarifa = 0),
    CONSTRAINT descontable_valido       CHECK(NOT ind_descontable OR tip_impuesto IN ('IVA','EXENTO')),
    CONSTRAINT base_sobre_iva_valida    CHECK(NOT ind_base_sobre_iva OR tip_impuesto = 'RETEIVA')
);

-- Datos iniciales del catálogo (entregados por Facturación). El 1 es el DEFAULT de tab_productos.
INSERT INTO tab_naturaleza_tributaria (id_naturaleza, nom_naturaleza, tip_impuesto, cod_dian, val_tarifa, ind_descontable, ind_base_sobre_iva, observaciones) VALUES
(1, 'IVA 19%',                'IVA',      '01', 19.00, TRUE,  FALSE, 'Tarifa general de IVA'),
(2, 'IVA 5%',                 'IVA',      '01',  5.00, TRUE,  FALSE, 'Tarifa diferencial de IVA'),
(3, 'IVA 0% (Exento)',        'EXENTO',   '01',  0.00, TRUE,  FALSE, 'Bienes y servicios exentos: tarifa 0 con derecho a descuento'),
(4, 'Excluido de IVA',        'EXCLUIDO', '01',  0.00, FALSE, FALSE, 'Bienes y servicios excluidos'),
(5, 'INC 8%',                 'INC',      '04',  8.00, FALSE, FALSE, 'Impuesto Nacional al Consumo'),
(6, 'ReteFuente servicios 4%','RETEFTE',  '05',  4.00, FALSE, FALSE, 'Retención en la fuente por servicios'),
(7, 'ReteIVA 15% del IVA',    'RETEIVA',  '06', 15.00, FALSE, TRUE,  'Retención de IVA: 15% sobre el valor del IVA');
---------------------
-- TABLA PRODUCTOS --
---------------------
CREATE TABLE IF NOT EXISTS tab_productos
(
    id_producto         DECIMAL(3,0)    NOT NULL CHECK(id_producto > 0 AND id_producto <= 999),                            -- Identificador del producto
    ind_tip_producto    BOOLEAN         NOT NULL,                                                                          -- TRUE = comercial / FALSE = interno
    ind_tipo_bien       BOOLEAN         NOT NULL,                                                                          -- TRUE = Bien  / FALSE = Servicio
    id_area             DECIMAL(5,0)    NOT NULL CHECK(id_area > 0),                                             -- Área a la que pertenece el producto interno (1 = "Compras comerciales)"
    nom_producto        VARCHAR(60)     NOT NULL CHECK(LENGTH(nom_producto) >= 4 AND LENGTH(nom_producto) <= 60 AND nom_producto ~ '^[A-Za-zÁÉÍÓÚáéíóúÑñÜü0-9 .,&()/''-]+$'),          -- Nombre del producto
    id_naturaleza       DECIMAL(4,0)    NOT NULL DEFAULT 1,                                                                -- Naturaleza tributaria (IVA/INC/exento/excluido); la tarifa está en tab_naturaleza_tributaria
    val_exist           DECIMAL(3,0)    NOT NULL CHECK(val_exist >= 0 AND val_exist <= 999) DEFAULT 0,                     -- Existencias del producto
    val_venta           DECIMAL(11,0)   NOT NULL CHECK(val_venta >= 0 AND val_venta <= 99999999999) DEFAULT 0,             -- Valor de venta
    ind_disponible      BOOLEAN         NOT NULL DEFAULT FALSE,                                                            -- TRUE = Disponible para venta / FALSE = No disponible para venta
    ind_estado          BOOLEAN         NOT NULL DEFAULT TRUE,                                                             -- TRUE = Activo / FALSE = Inactivo
    ind_uso_general     BOOLEAN         NOT NULL DEFAULT FALSE,                                                            -- TRUE = Lo pueden pedir todas las áreas / FALSE = Solo las de tab_prodxarea
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                                            -- TRUE = Borrado / FALSE = Activo
    PRIMARY KEY(id_producto),
    FOREIGN KEY(id_naturaleza) REFERENCES tab_naturaleza_tributaria(id_naturaleza)
);

-------------------------------
-- TABLA PRODUCTOS POR ÁREA --
-------------------------------
-- Áreas que pueden pedir cada producto (si no es de uso general). El área
-- responsable (tab_productos.id_area) siempre queda incluida.
CREATE TABLE IF NOT EXISTS tab_prodxarea
(
    id_producto         DECIMAL(3,0)    NOT NULL CHECK(id_producto > 0 AND id_producto <= 999),                            -- Identificador del producto
    id_area             DECIMAL(5,0)    NOT NULL CHECK(id_area > 0),                                                       -- Área que puede pedirlo
    PRIMARY KEY(id_producto, id_area),
    FOREIGN KEY(id_producto) REFERENCES tab_productos(id_producto),
    FOREIGN KEY(id_area)     REFERENCES tab_areas(id_area)
);

-----------------------------------
-- TABLA PRODUCTOS POR PROVEEDOR --
-----------------------------------
CREATE TABLE IF NOT EXISTS tab_prodxprov
(
    id_proveedor        VARCHAR(10)     NOT NULL CHECK(id_proveedor ~ '^[A-Z0-9]{7,10}$'),                                 -- Identificador del proveedor
    id_producto         DECIMAL(3,0)    NOT NULL CHECK(id_producto > 0 AND id_producto <= 999),                            -- Identificador del producto
    val_costo           DECIMAL(11,0)   NOT NULL CHECK(val_costo >= 0 AND val_costo <= 99999999999) DEFAULT 0,             -- Costo del producto
    val_pordesc         DECIMAL(2,0)    NOT NULL CHECK(val_pordesc >= 0 AND val_pordesc < 100) DEFAULT 0,                  -- % Descuento del proveedor
    ind_disponible      BOOLEAN         NOT NULL DEFAULT TRUE,                                                             -- TRUE = Disponible para compra / FALSE = No disponible para compra
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                                            -- TRUE = Borrado / FALSE = Activo
    PRIMARY KEY(id_proveedor, id_producto),
    FOREIGN KEY(id_proveedor) REFERENCES tab_proveedores(id_proveedor),
    FOREIGN KEY(id_producto)  REFERENCES tab_productos(id_producto)
);

-----------------------------------------------------------------
-- TABLA ENCABEZADO SOLICITUD DE COMPRA POR ÁREA (REQUISICIÓN) --
-----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_enc_solcomp
(
    id_solcompra        DECIMAL(6,0)    NOT NULL CHECK(id_solcompra > 0),                                                  -- Identificador de la solicitud
    id_area             DECIMAL(5,0)    NOT NULL CHECK(id_area > 0),                                                       -- Área que solicita la compra
    fec_solicitud       DATE            NOT NULL DEFAULT CURRENT_DATE,                                                     -- Fecha de solicitud
    fec_requerida       DATE            NOT NULL,                                                                          -- Fecha requerida (>= fec_solicitud)
    val_justificacion   TEXT            NOT NULL CHECK(LENGTH(TRIM(val_justificacion)) > 0 AND val_justificacion ~ '^[A-Za-zÁÉÍÓÚáéíóúÑñÜü0-9 \n\r.,;:¿?¡!()"''%/-]+$') DEFAULT 'Sin justificación',  -- Justificación de la solicitud
    ind_estado          DECIMAL(1,0)    NOT NULL CHECK(ind_estado >= 1 AND ind_estado <= 3) DEFAULT 2,                     -- 1=Aprobado, 2=Pendiente, 3=Anulado
    PRIMARY KEY(id_solcompra),
    FOREIGN KEY(id_area) REFERENCES tab_areas(id_area),
    CONSTRAINT fec_requerida_valida CHECK(fec_requerida >= fec_solicitud)
);

------------------------------------------------
-- TABLA DETALLE SOLICITUD DE COMPRA POR ÁREA --
------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_det_solcomp
(
    id_solcompra        DECIMAL(6,0)    NOT NULL CHECK(id_solcompra > 0),                                                  -- Identificador de la solicitud
    id_producto         DECIMAL(3,0)    NOT NULL CHECK(id_producto > 0 AND id_producto <= 999),                            -- Identificador del producto
    val_cantidad        DECIMAL(3,0)    NOT NULL CHECK(val_cantidad > 0 AND val_cantidad <= 999) DEFAULT 1,                -- Cantidad solicitada
    PRIMARY KEY(id_solcompra, id_producto),
    FOREIGN KEY(id_solcompra) REFERENCES tab_enc_solcomp(id_solcompra),
    FOREIGN KEY(id_producto)  REFERENCES tab_productos(id_producto)
);

-------------------------------------------
-- TABLA ENCABEZADO DE ÓRDENES DE COMPRA --
-------------------------------------------
CREATE TABLE IF NOT EXISTS tab_enc_ordcomp
(
    id_ordencompra      DECIMAL(6,0)    NOT NULL CHECK(id_ordencompra > 0),                                                -- Identificador de la orden de compra
    id_proveedor        VARCHAR(10)     NOT NULL CHECK(id_proveedor ~ '^[A-Z0-9]{7,10}$'),                                 -- Identificador del proveedor
    fec_emision         DATE            NOT NULL DEFAULT CURRENT_DATE,                                                     -- Fecha de emisión
    id_ciudad           VARCHAR         NOT NULL CHECK(LENGTH(id_ciudad) = 5),                                             -- Identificador de la ciudad
    ind_estado          DECIMAL(1,0)    NOT NULL CHECK(ind_estado >= 1 AND ind_estado <= 3) DEFAULT 2,                     -- 1=Aprobado, 2=Pendiente, 3=Anulado
    val_total           DECIMAL(11,0)   NOT NULL CHECK(val_total >= 0 AND val_total <= 99999999999) DEFAULT 0,             -- Valor total de la orden
    met_pago            BOOLEAN         NOT NULL DEFAULT FALSE,                                                            -- true = crédito, false = contado
    PRIMARY KEY(id_ordencompra),
    FOREIGN KEY(id_proveedor) REFERENCES tab_proveedores(id_proveedor),
    FOREIGN KEY(id_ciudad)    REFERENCES tab_ciudades(id_ciudad)
);
-- El origen de cada cantidad (qué solicitud y área la pidió) ya no va en el encabezado:
-- se guarda por línea en tab_det_ordcomp_solcomp. Una orden sin filas allí es una orden directa.

----------------------------------------
-- TABLA DETALLE DE ÓRDENES DE COMPRA --
----------------------------------------
CREATE TABLE IF NOT EXISTS tab_det_ordcomp
(
    id_ordencompra      DECIMAL(6,0)    NOT NULL CHECK(id_ordencompra > 0),                                                -- Identificador de la orden de compra
    id_producto         DECIMAL(3,0)    NOT NULL CHECK(id_producto > 0 AND id_producto <= 999),                            -- Identificador del producto
    val_cantidad        DECIMAL(3,0)    NOT NULL CHECK(val_cantidad > 0 AND val_cantidad <= 999) DEFAULT 1,                -- Cantidad pedida
    val_descuento       DECIMAL(11,0)   NOT NULL CHECK(val_descuento >= 0 AND val_descuento <= 99999999999) DEFAULT 0,     -- Valor descuento (costo * %desc)
    val_iva             DECIMAL(11,0)   NOT NULL CHECK(val_iva >= 0 AND val_iva <= 99999999999) DEFAULT 0,                 -- Valor IVA
    val_neto            DECIMAL(11,0)   NOT NULL CHECK(val_neto >= 0 AND val_neto <= 99999999999) DEFAULT 0,               -- Valor neto
    PRIMARY KEY(id_ordencompra, id_producto),
    FOREIGN KEY(id_ordencompra) REFERENCES tab_enc_ordcomp(id_ordencompra),
    FOREIGN KEY(id_producto)    REFERENCES tab_productos(id_producto)
);

--------------------------------------------------
-- TABLA SEGUIMIENTO DE ÓRDENES DE COMPRA (ENC) --
--------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_seg_ordcomp
(
    id_ordencompra      DECIMAL(6,0)    NOT NULL CHECK(id_ordencompra > 0),                                                -- Identificador de la orden de compra
    fec_aprobacion      DATE            NOT NULL DEFAULT CURRENT_DATE,                                                     -- Se llena via trigger cuando ind_estado cambia a 1
    fec_limite          DATE            NOT NULL,                                                                          -- fec_aprobacion + val_tiempo_entrega de tab_proveedores (se llena via trigger)
    ind_estado          DECIMAL(1,0)    NOT NULL CHECK(ind_estado >= 1 AND ind_estado <= 3) DEFAULT 1,                     -- 1=En espera, 2=Parcial, 3=Completo
    val_observacion     TEXT            NOT NULL  CHECK(LENGTH(TRIM(val_observacion)) > 0 AND val_observacion ~ '^[A-Za-zÁÉÍÓÚáéíóúÑñÜü0-9 \n\r.,;:¿?¡!()"''%/-]+$') DEFAULT 'Sin observaciones',                   -- Detalles si hubo problema
    PRIMARY KEY(id_ordencompra),
    FOREIGN KEY(id_ordencompra) REFERENCES tab_enc_ordcomp(id_ordencompra)
);

----------------------------------------------------
-- TABLA DETALLE SEGUIMIENTO DE ÓRDENES DE COMPRA --
----------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_det_seg_ordcomp
(
    id_ordencompra      DECIMAL(6,0)    NOT NULL CHECK(id_ordencompra > 0),                                                -- Identificador de la orden de compra
    id_producto         DECIMAL(3,0)    NOT NULL CHECK(id_producto > 0 AND id_producto <= 999),                            -- Identificador del producto
    val_cant_esperada   DECIMAL(3,0)    NOT NULL CHECK(val_cant_esperada > 0 AND val_cant_esperada <= 999),                -- Cantidad pedida original (no cambia)
    val_cant_recibida   DECIMAL(3,0)    NOT NULL CHECK(val_cant_recibida >= 0 AND val_cant_recibida <= 999) DEFAULT 0,     -- Cantidad recibida acumulada
    fec_recepcion       DATE            NULL,                                                                              -- Fecha de última recepción (NULL si aún no llega)
    PRIMARY KEY(id_ordencompra, id_producto),
    FOREIGN KEY(id_ordencompra) REFERENCES tab_seg_ordcomp(id_ordencompra),
    FOREIGN KEY(id_producto)    REFERENCES tab_productos(id_producto),
    CONSTRAINT cant_valida CHECK(val_cant_recibida <= val_cant_esperada)                                                   -- No puede recibirse más de lo pedido
);

--------------------------------------------
-- VISTA SEMAFORIZACIÓN ÓRDENES DE COMPRA --
--------------------------------------------
CREATE OR REPLACE VIEW vw_semaforo_ordcomp AS
SELECT
    s.id_ordencompra,
    o.id_proveedor,
    s.fec_aprobacion,
    s.fec_limite,
    
    s.ind_estado,
    s.fec_limite - CURRENT_DATE AS dias_restantes,
    CASE
        WHEN s.ind_estado = 3                           THEN 'COMPLETO'  -- ⚪
        WHEN s.fec_limite - CURRENT_DATE < 0            THEN 'VENCIDO'   -- 🔴
        WHEN s.fec_limite - CURRENT_DATE <= 3           THEN 'CRITICO'   -- 🔴
        WHEN s.fec_limite - CURRENT_DATE <= 7           THEN 'PROXIMO'   -- 🟡
        ELSE                                                 'A TIEMPO'  -- 🟢
    END AS semaforo
FROM tab_seg_ordcomp s
JOIN tab_enc_ordcomp o ON s.id_ordencompra = o.id_ordencompra;

----------------------------------------------------------------
-- TABLA ASIGNACIÓN DE PROVEEDOR A LAS LÍNEAS DE LA SOLICITUD --
----------------------------------------------------------------
-- Se llena al aprobar la solicitud (automático o manual). La línea queda
-- "en espera de orden" hasta que se consolida.
CREATE TABLE IF NOT EXISTS tab_asig_prov_solcomp
(
    id_solcompra        DECIMAL(6,0)    NOT NULL CHECK(id_solcompra > 0),                                                  -- Identificador de la solicitud
    id_producto         DECIMAL(3,0)    NOT NULL CHECK(id_producto > 0 AND id_producto <= 999),                            -- Identificador del producto
    id_proveedor        VARCHAR(10)     NOT NULL CHECK(id_proveedor ~ '^[A-Z0-9]{7,10}$'),                                 -- Proveedor asignado al aprobar
    ind_automatico      BOOLEAN         NOT NULL DEFAULT TRUE,                                                             -- TRUE = asignado automáticamente / FALSE = manual
    fec_asignacion      DATE            NOT NULL DEFAULT CURRENT_DATE,                                                     -- Fecha de la asignación (aprobación)
    PRIMARY KEY(id_solcompra, id_producto),
    FOREIGN KEY(id_solcompra, id_producto) REFERENCES tab_det_solcomp(id_solcompra, id_producto),
    FOREIGN KEY(id_proveedor, id_producto) REFERENCES tab_prodxprov(id_proveedor, id_producto)                             -- Solo un proveedor con convenio para ese producto
);

------------------------------------------------
-- TABLA REGISTRO DE CONSOLIDACIONES (HISTORIAL) --
------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_consol_solcomp
(
    id_consolidacion    DECIMAL(6,0)    NOT NULL CHECK(id_consolidacion > 0),                                              -- Identificador de la consolidación
    fec_consolidacion   TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP,                                                -- Fecha y hora en que se consolidó
    ind_automatica      BOOLEAN         NOT NULL DEFAULT FALSE,                                                            -- TRUE = corte automático / FALSE = manual (botón "Consolidar ahora")
    id_usuario          VARCHAR         NOT NULL CHECK(LENGTH(id_usuario) >= 5) DEFAULT 'SISTEMA',                         -- Usuario que consolidó ('SISTEMA' en el corte automático)
    val_ordenes         DECIMAL(3,0)    NOT NULL CHECK(val_ordenes >= 0 AND val_ordenes <= 999) DEFAULT 0,                 -- Órdenes generadas o actualizadas
    val_lineas          DECIMAL(4,0)    NOT NULL CHECK(val_lineas >= 0 AND val_lineas <= 9999) DEFAULT 0,                  -- Líneas de solicitud consolidadas
    val_omitidas        DECIMAL(4,0)    NOT NULL CHECK(val_omitidas >= 0 AND val_omitidas <= 9999) DEFAULT 0,              -- Líneas que se saltaron por no caber en el stock máximo (siguen en espera)
    PRIMARY KEY(id_consolidacion)
);

-----------------------------------------------------------------------
-- TABLA ORIGEN DE LAS LÍNEAS DE LA ORDEN (ORDEN <-> SOLICITUD/ÁREA) --
-----------------------------------------------------------------------
-- Cuánto de cada línea de la orden aporta cada línea de solicitud.
-- Ej: orden 15, resma x 25 = 15 de la solicitud 4 (área A) + 10 de la solicitud 6 (área B).
CREATE TABLE IF NOT EXISTS tab_det_ordcomp_solcomp
(
    id_ordencompra      DECIMAL(6,0)    NOT NULL CHECK(id_ordencompra > 0),                                                -- Identificador de la orden de compra
    id_producto         DECIMAL(3,0)    NOT NULL CHECK(id_producto > 0 AND id_producto <= 999),                            -- Identificador del producto
    id_solcompra        DECIMAL(6,0)    NOT NULL CHECK(id_solcompra > 0),                                                  -- Solicitud de donde viene la cantidad
    id_consolidacion    DECIMAL(6,0)    NOT NULL CHECK(id_consolidacion > 0),                                              -- Consolidación que la generó
    val_cantidad        DECIMAL(3,0)    NOT NULL CHECK(val_cantidad > 0 AND val_cantidad <= 999),                          -- Cantidad que aporta esa solicitud
    val_cant_recibida   DECIMAL(3,0)    NOT NULL CHECK(val_cant_recibida >= 0 AND val_cant_recibida <= 999) DEFAULT 0,     -- Cantidad ya entregada al área
    PRIMARY KEY(id_ordencompra, id_producto, id_solcompra),
    UNIQUE(id_solcompra, id_producto),                                                                                     -- Cada línea de solicitud se ordena una sola vez
    FOREIGN KEY(id_ordencompra, id_producto) REFERENCES tab_det_ordcomp(id_ordencompra, id_producto),
    FOREIGN KEY(id_solcompra, id_producto)   REFERENCES tab_det_solcomp(id_solcompra, id_producto),
    FOREIGN KEY(id_consolidacion)            REFERENCES tab_consol_solcomp(id_consolidacion),
    CONSTRAINT cant_recibida_area_valida CHECK(val_cant_recibida <= val_cantidad)                                          -- No se entrega al área más de lo que pidió
);

-----------------------------------------------------------------------
-- CATÁLOGOS DE DEVOLUCIONES (los administra el usuario)               --
-----------------------------------------------------------------------
-- Transportadoras, motivos de novedad, medios de envío y de reembolso. El registro 0 de
-- motivos / medios lo usa el sistema (Sin novedad / Sin enviar / Sin dato).
-- Se administran en Compras -> Configuración -> Tablas maestras -> Catálogos de devoluciones.
-- ---------------------------------------------------------------------
-- TRANSPORTADORAS
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_transportadoras
(
    id_transportadora   DECIMAL(3,0)    NOT NULL CHECK(id_transportadora > 0 AND id_transportadora <= 999),                -- Identificador
    nom_transportadora  VARCHAR(60)     NOT NULL CHECK(LENGTH(TRIM(nom_transportadora)) >= 2
                                                   AND nom_transportadora ~ '^[A-Za-zÁÉÍÓÚáéíóúÑñÜü0-9 .,&()/''-]+$'),  -- Nombre (lista blanca de nombres)
    num_nit             VARCHAR(12)     NULL CHECK(num_nit ~ '^[0-9]{6,10}(-[0-9])?$'),                                    -- NIT (opcional), con o sin dígito de verificación
    tel_contacto        VARCHAR(10)     NULL CHECK(tel_contacto ~ '^[0-9]{7,10}$'),                                        -- Teléfono (opcional)
    url_rastreo         VARCHAR(200)    NULL CHECK(url_rastreo ~ '^https://[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(/[A-Za-z0-9._~/?=&%{}+:#-]*)?$'
                                                   AND POSITION('{guia}' IN url_rastreo) > 0),                             -- Página de rastreo (https) con {guia} donde va el número
    ind_estado          BOOLEAN         NOT NULL DEFAULT TRUE,                                                             -- TRUE = activa (aparece para elegir)
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                                            -- Borrado lógico
    PRIMARY KEY(id_transportadora)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_transportadoras_nombre ON tab_transportadoras(LOWER(TRIM(nom_transportadora))) WHERE ind_borrado = FALSE;

-- ---------------------------------------------------------------------
-- MOTIVOS DE NOVEDAD (0 = Sin novedad: lo usa el sistema, no se edita)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_motivos_novedad
(
    id_motivo               DECIMAL(2,0)    NOT NULL CHECK(id_motivo >= 0 AND id_motivo <= 99),                            -- Identificador (0 = Sin novedad)
    nom_motivo              VARCHAR(40)     NOT NULL CHECK(LENGTH(TRIM(nom_motivo)) >= 3
                                                       AND nom_motivo ~ '^[A-Za-zÁÉÍÓÚáéíóúÑñÜü0-9 .,&()/''-]+$'),      -- Nombre
    des_motivo              VARCHAR(200)    NOT NULL CHECK(LENGTH(TRIM(des_motivo)) > 0
                                                       AND des_motivo ~ '^[A-Za-zÁÉÍÓÚáéíóúÑñÜü0-9 \n\r.,;:¿?¡!()"''%/-]+$') DEFAULT 'Sin descripción', -- Ayuda para el área
    ind_genera_devolucion   BOOLEAN         NOT NULL DEFAULT TRUE,                                                         -- TRUE = la novedad crea/completa la devolución al proveedor
    ind_estado              BOOLEAN         NOT NULL DEFAULT TRUE,
    ind_borrado             BOOLEAN         NOT NULL DEFAULT FALSE,
    PRIMARY KEY(id_motivo)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_motivos_novedad_nombre ON tab_motivos_novedad(LOWER(TRIM(nom_motivo))) WHERE ind_borrado = FALSE;

INSERT INTO tab_motivos_novedad (id_motivo, nom_motivo, des_motivo, ind_genera_devolucion) VALUES
    (0, 'Sin novedad',               'Llegó bien. Uso interno del sistema.',          FALSE),
    (1, 'Dañado',                    'Llegó roto, golpeado o mojado.',               TRUE),
    (2, 'Defectuoso',                'Llegó bien pero no funciona.',                 TRUE),
    (3, 'No corresponde a lo pedido','Otra referencia, talla, color o cantidad.',    TRUE),
    (4, 'Vencido',                   'Llegó vencido o muy cerca de vencer.',         TRUE),
    (5, 'Faltante',                  'Se facturó pero no llegó.',                    TRUE)
ON CONFLICT (id_motivo) DO NOTHING;

-- ---------------------------------------------------------------------
-- MEDIOS DE ENVÍO (0 = Sin enviar: lo usa el sistema, no se edita)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_medios_envio
(
    id_medio_envio              DECIMAL(2,0)    NOT NULL CHECK(id_medio_envio >= 0 AND id_medio_envio <= 99),          -- Identificador (0 = Sin enviar)
    nom_medio_envio             VARCHAR(50)     NOT NULL CHECK(LENGTH(TRIM(nom_medio_envio)) >= 3
                                                           AND nom_medio_envio ~ '^[A-Za-zÁÉÍÓÚáéíóúÑñÜü0-9 .,&()/''-]+$'), -- Nombre
    ind_exige_transportadora    BOOLEAN         NOT NULL DEFAULT FALSE,                                                -- TRUE = hay que elegir la transportadora
    ind_exige_guia              BOOLEAN         NOT NULL DEFAULT FALSE,                                                -- TRUE = el número de guía es obligatorio
    ind_estado                  BOOLEAN         NOT NULL DEFAULT TRUE,
    ind_borrado                 BOOLEAN         NOT NULL DEFAULT FALSE,
    PRIMARY KEY(id_medio_envio),
    CONSTRAINT medenv_guia CHECK(NOT ind_exige_transportadora OR ind_exige_guia)                                       -- Con transportadora siempre hay guía
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_medios_envio_nombre ON tab_medios_envio(LOWER(TRIM(nom_medio_envio))) WHERE ind_borrado = FALSE;

INSERT INTO tab_medios_envio (id_medio_envio, nom_medio_envio, ind_exige_transportadora, ind_exige_guia) VALUES
    (0, 'Sin enviar',                       FALSE, FALSE),
    (1, 'Transportadora',                   TRUE,  TRUE),
    (2, 'Mensajería propia',                FALSE, FALSE),
    (3, 'La recoge el proveedor',           FALSE, FALSE),
    (4, 'Se lleva a un punto del proveedor', FALSE, FALSE)
ON CONFLICT (id_medio_envio) DO NOTHING;

-- ---------------------------------------------------------------------
-- MEDIOS DE REEMBOLSO (0 = Sin dato: lo usa el sistema, no se edita)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_medios_reembolso
(
    id_medio_reembolso  DECIMAL(2,0)    NOT NULL CHECK(id_medio_reembolso >= 0 AND id_medio_reembolso <= 99),          -- Identificador (0 = Sin dato)
    nom_medio_reembolso VARCHAR(40)     NOT NULL CHECK(LENGTH(TRIM(nom_medio_reembolso)) >= 3
                                                   AND nom_medio_reembolso ~ '^[A-Za-zÁÉÍÓÚáéíóúÑñÜü0-9 .,&()/''-]+$'),  -- Nombre
    ind_estado          BOOLEAN         NOT NULL DEFAULT TRUE,
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,
    PRIMARY KEY(id_medio_reembolso)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_medios_reembolso_nombre ON tab_medios_reembolso(LOWER(TRIM(nom_medio_reembolso))) WHERE ind_borrado = FALSE;

INSERT INTO tab_medios_reembolso (id_medio_reembolso, nom_medio_reembolso) VALUES
    (0, 'Sin dato'),
    (1, 'Transferencia'),
    (2, 'Consignación'),
    (3, 'Efectivo'),
    (4, 'Cheque')
ON CONFLICT (id_medio_reembolso) DO NOTHING;

-----------------------------------------------------------------------
-- TABLA CONFIRMACIÓN DE RECIBIDO POR EL ÁREA (ACUSE DE RECIBO)       --
-----------------------------------------------------------------------
-- Cada fila es una confirmación del responsable del área sobre una línea ya entregada:
-- cuánto llegó conforme y cuánto con novedad (y por qué). Se puede confirmar por partes.
-- Bienes: sobre lo entregado por Compras. Servicios: es el acta de recibo a satisfacción.
CREATE TABLE IF NOT EXISTS tab_conf_solcomp
(
    id_conformidad      DECIMAL(8,0)    NOT NULL CHECK(id_conformidad > 0),                                                -- Identificador de la confirmación
    id_ordencompra      DECIMAL(6,0)    NOT NULL CHECK(id_ordencompra > 0),                                                -- Orden de compra de donde vino la línea
    id_producto         DECIMAL(3,0)    NOT NULL CHECK(id_producto > 0 AND id_producto <= 999),                            -- Producto confirmado
    id_solcompra        DECIMAL(6,0)    NOT NULL CHECK(id_solcompra > 0),                                                  -- Solicitud del área
    fec_conformidad     TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP,                                                -- Cuándo confirmó el área
    id_usuario          VARCHAR         NOT NULL CHECK(LENGTH(id_usuario) >= 5),                                           -- Quién confirmó (responsable del área)
    ind_tipo_bien       BOOLEAN         NOT NULL,                                                                          -- TRUE = bien / FALSE = servicio (al momento de confirmar)
    val_cant_conforme   DECIMAL(3,0)    NOT NULL CHECK(val_cant_conforme >= 0 AND val_cant_conforme <= 999) DEFAULT 0,    -- Unidades que llegaron bien
    val_cant_novedad    DECIMAL(3,0)    NOT NULL CHECK(val_cant_novedad >= 0 AND val_cant_novedad <= 999) DEFAULT 0,      -- Unidades con novedad
    ind_motivo_novedad  DECIMAL(2,0)    NOT NULL DEFAULT 0,                                                                -- Motivo (catálogo tab_motivos_novedad; 0 = Sin novedad)
    val_observacion     TEXT            NOT NULL CHECK(LENGTH(TRIM(val_observacion)) > 0 AND LENGTH(val_observacion) <= 500
                                                   AND val_observacion ~ '^[A-Za-zÁÉÍÓÚáéíóúÑñÜü0-9 \n\r.,;:¿?¡!()"''%/-]+$') DEFAULT 'Sin observaciones', -- Observación del área (lista blanca de texto)
    fec_prestacion      DATE            NULL,                                                                              -- Servicios: fecha en que se prestó (NULL en bienes)
    val_unit_base       DECIMAL(11,0)   NOT NULL CHECK(val_unit_base >= 0) DEFAULT 0,                                      -- Valor unitario sin IVA en la orden (para presupuesto/causación)
    val_unit_iva        DECIMAL(11,0)   NOT NULL CHECK(val_unit_iva >= 0) DEFAULT 0,                                       -- IVA unitario en la orden
    PRIMARY KEY(id_conformidad),
    FOREIGN KEY(id_ordencompra, id_producto, id_solcompra) REFERENCES tab_det_ordcomp_solcomp(id_ordencompra, id_producto, id_solcompra),
    FOREIGN KEY(id_usuario) REFERENCES tab_usuarios(id_usuario),
    CONSTRAINT fk_conf_motivo FOREIGN KEY(ind_motivo_novedad) REFERENCES tab_motivos_novedad(id_motivo),
    CONSTRAINT conf_cantidad_valida  CHECK(val_cant_conforme + val_cant_novedad > 0),                                     -- Se confirma al menos una unidad
    CONSTRAINT conf_motivo_valido    CHECK((val_cant_novedad = 0 AND ind_motivo_novedad = 0)
                                        OR (val_cant_novedad > 0 AND ind_motivo_novedad >= 1)),                           -- Novedad <=> motivo
    CONSTRAINT conf_fec_prestacion   CHECK((ind_tipo_bien = TRUE AND fec_prestacion IS NULL)
                                        OR (ind_tipo_bien = FALSE AND fec_prestacion IS NOT NULL))                         -- Solo los servicios llevan fecha de prestación
);

CREATE INDEX IF NOT EXISTS idx_conf_solcomp_linea ON tab_conf_solcomp(id_solcompra, id_producto);
CREATE INDEX IF NOT EXISTS idx_conf_solcomp_orden ON tab_conf_solcomp(id_ordencompra);

-----------------------------------------------------------------------
-- TABLAS DEVOLUCIONES AL PROVEEDOR                                    --
-----------------------------------------------------------------------
-- Estados: 1=Reportada (la crea sola la novedad del área), 2=Recibida en Compras,
-- 3=Enviada al proveedor (RMA, medio, guía, costo), 4=Cerrada, 5=Anulada.
-- Resolución por línea: 1=Reposición, 2=Nota crédito, 3=Reembolso, 4=Reparación/garantía,
-- 5=Rechazada por el proveedor, 6=Baja.
-- ---------------------------------------------------------------------
-- ENCABEZADO DE LA DEVOLUCIÓN
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_enc_devprov
(
    id_devolucion       DECIMAL(6,0)    NOT NULL CHECK(id_devolucion > 0),                                                 -- Identificador de la devolución
    id_ordencompra      DECIMAL(6,0)    NOT NULL CHECK(id_ordencompra > 0),                                                -- Orden de compra de donde vino lo devuelto
    id_proveedor        VARCHAR(10)     NOT NULL CHECK(id_proveedor ~ '^[A-Z0-9]{7,10}$'),                                 -- Proveedor al que se devuelve
    fec_reporte         TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP,                                                -- Cuándo se creó (primera novedad reportada)
    ind_estado          DECIMAL(1,0)    NOT NULL CHECK(ind_estado >= 1 AND ind_estado <= 5) DEFAULT 1,                     -- 1=Reportada, 2=Recibida en Compras, 3=Enviada al proveedor, 4=Cerrada, 5=Anulada
    fec_recibida        TIMESTAMPTZ     NULL,                                                                              -- Cuándo la recibió Compras
    id_usuario_recibe   VARCHAR         NULL CHECK(LENGTH(id_usuario_recibe) >= 5),                                        -- Quién la recibió en Compras
    num_rma             VARCHAR(30)     NULL CHECK(num_rma ~ '^[A-Za-z0-9][A-Za-z0-9./-]{0,29}$'),                         -- Autorización de devolución del proveedor (RMA), si la da
    ind_medio_envio     DECIMAL(2,0)    NOT NULL DEFAULT 0,                                                                -- Medio de envío (catálogo tab_medios_envio; 0 = Sin enviar)
    id_transportadora   DECIMAL(3,0)    NULL,                                                                              -- Transportadora (catálogo tab_transportadoras), si el medio la exige
    nom_transportadora  VARCHAR(60)     NULL CHECK(LENGTH(TRIM(nom_transportadora)) >= 2
                                                   AND nom_transportadora ~ '^[A-Za-zÁÉÍÓÚáéíóúÑñÜü0-9 .,&()/''-]+$'),  -- Nombre de la transportadora tal como estaba al enviar
    num_guia            VARCHAR(40)     NULL CHECK(num_guia ~ '^[A-Za-z0-9][A-Za-z0-9-]{2,39}$'),                          -- Número de guía de la transportadora
    fec_envio           DATE            NULL,                                                                              -- Fecha en que salió hacia el proveedor
    val_costo_envio     DECIMAL(11,0)   NOT NULL CHECK(val_costo_envio >= 0 AND val_costo_envio <= 99999999999) DEFAULT 0, -- Costo del envío
    ind_asume_costo     DECIMAL(1,0)    NOT NULL CHECK(ind_asume_costo >= 0 AND ind_asume_costo <= 2) DEFAULT 0,           -- 0=Sin costo, 1=Lo asume el proveedor, 2=Lo asume la empresa
    id_usuario_despacha VARCHAR         NULL CHECK(LENGTH(id_usuario_despacha) >= 5),                                      -- Quién la despachó
    fec_cierre          TIMESTAMPTZ     NULL,                                                                              -- Cuándo quedó cerrada o anulada
    val_observacion     TEXT            NOT NULL CHECK(LENGTH(TRIM(val_observacion)) > 0 AND LENGTH(val_observacion) <= 500
                                                   AND val_observacion ~ '^[A-Za-zÁÉÍÓÚáéíóúÑñÜü0-9 \n\r.,;:¿?¡!()"''%/-]+$') DEFAULT 'Sin observaciones', -- Observación de Compras
    PRIMARY KEY(id_devolucion),
    FOREIGN KEY(id_ordencompra)      REFERENCES tab_enc_ordcomp(id_ordencompra),
    FOREIGN KEY(id_proveedor)        REFERENCES tab_proveedores(id_proveedor),
    FOREIGN KEY(id_usuario_recibe)   REFERENCES tab_usuarios(id_usuario),
    FOREIGN KEY(id_usuario_despacha) REFERENCES tab_usuarios(id_usuario),
    CONSTRAINT devprov_recibida   CHECK(ind_estado IN (1, 5) OR (fec_recibida IS NOT NULL AND id_usuario_recibe IS NOT NULL)),        -- Desde "Recibida" se sabe quién y cuándo
    CONSTRAINT devprov_envio      CHECK(ind_estado NOT IN (3, 4)
                                     OR (ind_medio_envio >= 1 AND fec_envio IS NOT NULL AND id_usuario_despacha IS NOT NULL)),       -- Enviada/Cerrada: con medio, fecha y quién despachó
    CONSTRAINT fk_devprov_medio_envio    FOREIGN KEY(ind_medio_envio)   REFERENCES tab_medios_envio(id_medio_envio),
    CONSTRAINT fk_devprov_transportadora FOREIGN KEY(id_transportadora) REFERENCES tab_transportadoras(id_transportadora),
    CONSTRAINT devprov_transp_nombre CHECK(id_transportadora IS NULL OR nom_transportadora IS NOT NULL),                    -- Con transportadora, su nombre
    CONSTRAINT devprov_costo      CHECK((val_costo_envio = 0 AND ind_asume_costo = 0) OR (val_costo_envio > 0 AND ind_asume_costo >= 1)), -- Si hay costo, quién lo asume
    CONSTRAINT devprov_cierre     CHECK(ind_estado NOT IN (4, 5) OR fec_cierre IS NOT NULL)                                       -- Cerrada/Anulada: con fecha
);

-- Solo una devolución "Reportada" abierta por orden de compra (las novedades nuevas se suman a ella)
CREATE UNIQUE INDEX IF NOT EXISTS uq_devprov_reportada_orden ON tab_enc_devprov(id_ordencompra) WHERE ind_estado = 1;
CREATE INDEX IF NOT EXISTS idx_devprov_proveedor ON tab_enc_devprov(id_proveedor);

-- ---------------------------------------------------------------------
-- DETALLE: una línea por cada confirmación con novedad del área
-- (tab_conf_solcomp), con la cantidad y el motivo que reportó el área.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_det_devprov
(
    id_devolucion       DECIMAL(6,0)    NOT NULL CHECK(id_devolucion > 0),                                                 -- Devolución
    id_conformidad      DECIMAL(8,0)    NOT NULL CHECK(id_conformidad > 0),                                                -- Confirmación del área que reportó la novedad
    id_producto         DECIMAL(3,0)    NOT NULL CHECK(id_producto > 0 AND id_producto <= 999),                            -- Producto devuelto
    val_cantidad        DECIMAL(3,0)    NOT NULL CHECK(val_cantidad > 0 AND val_cantidad <= 999),                          -- Unidades devueltas (las de la novedad)
    ind_motivo          DECIMAL(2,0)    NOT NULL CHECK(ind_motivo >= 1),                                                   -- Motivo (catálogo tab_motivos_novedad)
    val_unit_base       DECIMAL(11,0)   NOT NULL CHECK(val_unit_base >= 0) DEFAULT 0,                                      -- Valor unitario sin IVA (de la orden)
    val_unit_iva        DECIMAL(11,0)   NOT NULL CHECK(val_unit_iva >= 0) DEFAULT 0,                                       -- IVA unitario (de la orden)
    ind_resolucion      DECIMAL(1,0)    NOT NULL CHECK(ind_resolucion >= 0 AND ind_resolucion <= 6) DEFAULT 0,             -- 0=Pendiente, 1=Reposición, 2=Nota crédito, 3=Reembolso, 4=Reparación/garantía, 5=Rechazada por el proveedor, 6=Baja
    num_nota_credito    VARCHAR(30)     NULL CHECK(num_nota_credito ~ '^[A-Za-z0-9][A-Za-z0-9./-]{0,29}$'),                -- Número de la nota crédito del proveedor
    val_resolucion      DECIMAL(11,0)   NOT NULL CHECK(val_resolucion >= 0 AND val_resolucion <= 99999999999) DEFAULT 0,   -- Valor de la nota crédito o del reembolso
    val_saldo_favor     DECIMAL(11,0)   NOT NULL CHECK(val_saldo_favor >= 0) DEFAULT 0,                                    -- Nota crédito que supera la deuda: excedente a favor de la empresa
    fec_reembolso       DATE            NULL,                                                                              -- Reembolso: fecha en que llegó el dinero (opcional)
    ind_medio_reembolso DECIMAL(2,0)    NOT NULL DEFAULT 0,                                                                -- Reembolso: medio (catálogo tab_medios_reembolso; 0 = Sin dato)
    fec_resolucion      TIMESTAMPTZ     NULL,                                                                              -- Cuándo se registró la resolución
    id_usuario_resuelve VARCHAR         NULL CHECK(LENGTH(id_usuario_resuelve) >= 5),                                      -- Quién la registró
    val_obs_resolucion  TEXT            NOT NULL CHECK(LENGTH(TRIM(val_obs_resolucion)) > 0 AND LENGTH(val_obs_resolucion) <= 500
                                                   AND val_obs_resolucion ~ '^[A-Za-zÁÉÍÓÚáéíóúÑñÜü0-9 \n\r.,;:¿?¡!()"''%/-]+$') DEFAULT 'Sin observaciones', -- Observación de la resolución
    PRIMARY KEY(id_devolucion, id_conformidad),
    UNIQUE(id_conformidad),                                                                                                -- Una novedad se devuelve una sola vez
    FOREIGN KEY(id_devolucion)       REFERENCES tab_enc_devprov(id_devolucion),
    FOREIGN KEY(id_conformidad)      REFERENCES tab_conf_solcomp(id_conformidad),
    FOREIGN KEY(id_producto)         REFERENCES tab_productos(id_producto),
    FOREIGN KEY(id_usuario_resuelve) REFERENCES tab_usuarios(id_usuario),
    CONSTRAINT fk_detdev_motivo          FOREIGN KEY(ind_motivo)          REFERENCES tab_motivos_novedad(id_motivo),
    CONSTRAINT fk_detdev_medio_reembolso FOREIGN KEY(ind_medio_reembolso) REFERENCES tab_medios_reembolso(id_medio_reembolso),
    CONSTRAINT detdev_resuelta    CHECK((ind_resolucion = 0 AND fec_resolucion IS NULL AND id_usuario_resuelve IS NULL)
                                     OR (ind_resolucion > 0 AND fec_resolucion IS NOT NULL AND id_usuario_resuelve IS NOT NULL)),   -- Resuelta: quién y cuándo
    CONSTRAINT detdev_nota        CHECK(ind_resolucion <> 2 OR (num_nota_credito IS NOT NULL AND val_resolucion > 0)),            -- Nota crédito: número y valor
    CONSTRAINT detdev_reembolso   CHECK(ind_resolucion <> 3 OR (num_nota_credito IS NOT NULL AND val_resolucion > 0)),            -- Reembolso: también con nota crédito (número y valor)
    CONSTRAINT detdev_sin_valor   CHECK(ind_resolucion IN (2, 3) OR (val_resolucion = 0 AND num_nota_credito IS NULL)),           -- Las demás no llevan valor
    CONSTRAINT detdev_saldo_favor CHECK((ind_resolucion = 2 AND val_saldo_favor <= val_resolucion) OR val_saldo_favor = 0),       -- Saldo a favor: solo nota crédito y hasta su valor
    CONSTRAINT detdev_datos_reemb CHECK(ind_resolucion = 3 OR (fec_reembolso IS NULL AND ind_medio_reembolso = 0))                -- Fecha y medio del pago: solo reembolso
);

CREATE INDEX IF NOT EXISTS idx_det_devprov_producto ON tab_det_devprov(id_producto);

--------------------------------------------------------------
-- VISTA CONVENIOS APTOS (PROVEEDOR + PRODUCTO QUE SE PUEDEN COMPRAR) --
--------------------------------------------------------------
-- Un convenio es apto si: no está borrado, está disponible y tiene costo,
-- el proveedor no está borrado y está activo, y el proveedor está calificado
-- (puntaje >= mínimo de Parámetros de compras) o todavía no tiene evaluación.
-- Los evaluados por debajo del mínimo quedan fuera.
CREATE OR REPLACE VIEW vw_convenios_aptos AS
SELECT
    pp.id_proveedor,
    pp.id_producto,
    pp.val_costo,
    pp.val_pordesc,
    ROUND(pp.val_costo * (100 - pp.val_pordesc) / 100) AS val_costo_neto,
    p.val_tiempo_entrega,
    e.val_puntaje_total,                                                       -- NULL = sin evaluación
    CASE WHEN e.id_eva_prov IS NULL THEN FALSE ELSE TRUE END AS ind_evaluado   -- FALSE = proveedor nuevo (sin evaluación)
FROM tab_prodxprov pp
JOIN tab_proveedores p ON p.id_proveedor = pp.id_proveedor
                      AND p.ind_borrado  = FALSE
JOIN tab_terceros    t ON t.id_tercero   = p.id_proveedor
                      AND t.ind_borrado  = FALSE
                      AND t.ind_estado   = TRUE
LEFT JOIN tab_eval_prov e ON e.id_proveedor = pp.id_proveedor
                         AND e.ind_borrado  = FALSE
WHERE pp.ind_borrado    = FALSE
  AND pp.ind_disponible = TRUE
  AND pp.val_costo      > 0
  AND (e.id_eva_prov IS NULL
       OR e.val_puntaje_total >= COALESCE((SELECT c.val_puntaje_sel_prov
                                             FROM tab_pmtros_grales  g
                                             JOIN tab_pmtros_compras c ON c.id_empresa = g.id_empresa
                                            WHERE g.ind_borrado = FALSE
                                            ORDER BY g.id_empresa
                                            LIMIT 1), 80));


-------------------------------------------------------------------------------
--
-- FUNCIONA HASTA ACA
--
-------------------------------------------------------------------------------

--------------------------------------------
-- MÓDULO DE GESTIÓN HUMANA Y NÓMINA --
--------------------------------------------

/*******************************************************************************
 * Descripción: Creación de tablas para gestión de Talento Humano y Nómina.
 *******************************************************************************/

-- 1. TABLA DE PARAMETROS LEGALES
CREATE TABLE IF NOT EXISTS tab_pmtros_legales
(
    id_empresa                VARCHAR(10)             NOT NULL DEFAULT '0000000000',            -- Número de identificación de la empresa
    ano                       INTEGER                 NOT NULL DEFAULT 2026,                    -- Año de vigencia
    val_smlv                  DECIMAL(10,0)           NOT NULL DEFAULT 1750905,                 -- Valor salario miniomo legal vigente
    val_aux_transp            DECIMAL(10,0)           NOT NULL DEFAULT 249095,                  -- Valor auxilio de transporte
    val_tope_rete             DECIMAL(10,0)           NOT NULL DEFAULT 4975530,                 -- Valor tope para retención (la retención por salarios solo aplica si la base gravable supera las 95 UVT (aprox.  $4.975.530).)
    pct_calculo_ibc           DECIMAL(5,2)            NOT NULL DEFAULT 40.00,                   -- Porcentaje calculo IBC (40%)
    pct_salud_emplea          DECIMAL(5,2)            NOT NULL DEFAULT 4.00,
    pct_pension_empld         DECIMAL(5,2)            NOT NULL DEFAULT 4.00,
    pct_solidaridad           DECIMAL(5,2)            NOT NULL DEFAULT 1.00,
    pct_salud_emplr           DECIMAL(5,2)            NOT NULL DEFAULT 8.50,
    pct_pension_emplr         DECIMAL(5,2)            NOT NULL DEFAULT 12.00,
    pct_arl                   DECIMAL(6,3)            NOT NULL DEFAULT 0.522,
    pct_sena                  DECIMAL(5,2)            NOT NULL DEFAULT 2.00,
    pct_icbf                  DECIMAL(5,2)            NOT NULL DEFAULT 3.00,
    pct_ccf                   DECIMAL(5,2)            NOT NULL DEFAULT 4.00,
    pct_prima                 DECIMAL(5,2)            NOT NULL DEFAULT 8.33,
    pct_cesantias             DECIMAL(5,2)            NOT NULL DEFAULT 8.33,
    pct_intereses_ces         DECIMAL(5,2)            NOT NULL DEFAULT 12.00,
    dias_vacaciones           INTEGER                 NOT NULL DEFAULT 15,
    jornada_max_horas         INTEGER                 NOT NULL DEFAULT 42,
    hora_inicio_noct          TIME                    NOT NULL DEFAULT '19:00:00'::time without time zone,
    hora_fin_noct             TIME                    NOT NULL DEFAULT '06:00:00'::time without time zone,
    pct_rec_nocturno          DECIMAL(5,2)            NOT NULL DEFAULT 35.00,
    pct_rec_dominical         DECIMAL(5,2)            NOT NULL DEFAULT 90.00,
    pct_rec_dom_noct          DECIMAL(5,2)            NOT NULL DEFAULT 125.00,
    pct_extra_diurna          DECIMAL(5,2)            NOT NULL DEFAULT 25.00,
    pct_extra_nocturna        DECIMAL(5,2)            NOT NULL DEFAULT 75.00,
    pct_extra_dominical       DECIMAL(5,2)            NOT NULL DEFAULT 100.00,
    ind_borrado               BOOLEAN                 NOT NULL DEFAULT false,
    pct_lic_maternidad        DECIMAL(5,2)            NOT NULL DEFAULT 100.00,                  -- (gehnom 14-nov) nueva
    pct_lic_paternidad        DECIMAL(5,2)            NOT NULL DEFAULT 100.00,                  -- (gehnom 14-nov) nueva
    pct_incap_gen_dias1_2     DECIMAL(5,2)            NOT NULL DEFAULT 66.67,                   -- (gehnom 14-nov) nueva
    pct_incap_gen_dias3_90    DECIMAL(5,2)            NOT NULL DEFAULT 66.67,                   -- (gehnom 14-nov) nueva
    pct_incap_gen_dias91_180  DECIMAL(5,2)            NOT NULL DEFAULT 50.00,                   -- (gehnom 14-nov) nueva
    pct_incap_laboral_arl     DECIMAL(5,2)            NOT NULL DEFAULT 100.00,                  -- (gehnom 14-nov) nueva
    horas_mes                 DECIMAL(4,0)            NOT NULL DEFAULT 240,                     -- (gehnom 14-nov) nueva
    tipo_periodo_nomina       VARCHAR(10)             NOT NULL DEFAULT 'QUINCENAL',             -- (gehnom 14-nov) nueva
    tope_aux_transp_smlv      DECIMAL(3,1)            NOT NULL DEFAULT 2.0,                     -- (gehnom 14-nov) nueva
    val_uvt                   DECIMAL(10,0)           NOT NULL DEFAULT 52374,                   -- (gehnom 14-nov) nueva
    pct_extra_dom_noct        DECIMAL(5,2)            NOT NULL DEFAULT 165,                     -- (gehnom 14-nov) nueva
    pct_arl_1                 DECIMAL(6,3)            NOT NULL DEFAULT 0.522,                   -- (gehnom 14-nov) nueva
    pct_arl_2                 DECIMAL(6,3)            NOT NULL DEFAULT 1.044,                   -- (gehnom 14-nov) nueva
    pct_arl_3                 DECIMAL(6,3)            NOT NULL DEFAULT 2.436,                   -- (gehnom 14-nov) nueva
    pct_arl_4                 DECIMAL(6,3)            NOT NULL DEFAULT 4.350,                   -- (gehnom 14-nov) nueva
    pct_arl_5                 DECIMAL(6,3)            NOT NULL DEFAULT 6.960,                   -- (gehnom 14-nov) nueva
    pct_vacaciones            DECIMAL(5,2)            NOT NULL DEFAULT 4.17,                    -- (gehnom 14-nov) nueva
    tope_ibc_smlv             DECIMAL(4,1)            NOT NULL DEFAULT 25,                      -- (gehnom 14-nov) nueva
    ind_exonera_114           BOOLEAN                 NOT NULL DEFAULT true,                    -- (gehnom 14-nov) nueva
    tope_exonera_smlv         DECIMAL(4,1)            NOT NULL DEFAULT 10,                      -- (gehnom 14-nov) nueva
    ind_incap_piso_smlv       BOOLEAN                 NOT NULL DEFAULT true,                    -- (gehnom 14-nov) nueva
    pct_renta_exenta          DECIMAL(5,2)            NOT NULL DEFAULT 25,                      -- (gehnom 14-nov) nueva
    tope_exenta_uvt_anual     DECIMAL(6,0)            NOT NULL DEFAULT 790,                     -- (gehnom 14-nov) nueva
    pct_max_cuota_prestamo    DECIMAL(5,2)            NOT NULL DEFAULT 50,                      -- (gehnom 14-nov) nueva
    pct_max_vac_dinero        DECIMAL(5,2)            NOT NULL DEFAULT 50,                      -- (gehnom 14-nov) nueva
    dias_anio_nomina          DECIMAL(3,0)            NOT NULL DEFAULT 360,                     -- (gehnom 14-nov) nueva
    indem_tope_smlv           DECIMAL(4,1)            NOT NULL DEFAULT 10,                      -- (gehnom 14-nov) nueva
    indem_dias_ini_bajo       DECIMAL(3,0)            NOT NULL DEFAULT 30,                      -- (gehnom 14-nov) nueva
    indem_dias_adic_bajo      DECIMAL(3,0)            NOT NULL DEFAULT 20,                      -- (gehnom 14-nov) nueva
    indem_dias_ini_alto       DECIMAL(3,0)            NOT NULL DEFAULT 20,                      -- (gehnom 14-nov) nueva
    indem_dias_adic_alto      DECIMAL(3,0)            NOT NULL DEFAULT 15,                      -- (gehnom 14-nov) nueva
    indem_dias_min_fijo       DECIMAL(3,0)            NOT NULL DEFAULT 15,                      -- (gehnom 14-nov) nueva
    pct_rete_indem            DECIMAL(5,2)            NOT NULL DEFAULT 20,                      -- (gehnom 14-nov) nueva
    uvt_tope_rete_indem       DECIMAL(6,0)            NOT NULL DEFAULT 204,                     -- (gehnom 14-nov) nueva
    rangos_solidaridad        JSONB                   NOT NULL DEFAULT '[{"adicional": 0, "desde_smlv": 4}, {"adicional": 0.2, "desde_smlv": 16}, {"adicional": 0.4, "desde_smlv": 17}, {"adicional": 0.6, "desde_smlv": 18}, {"adicional": 0.8, "desde_smlv": 19}, {"adicional": 1, "desde_smlv": 20}]'::jsonb, -- (gehnom 14-nov) nueva
    rangos_retencion          JSONB                   NOT NULL DEFAULT '[{"pct": 19, "suma_uvt": 0, "desde_uvt": 95}, {"pct": 28, "suma_uvt": 10, "desde_uvt": 150}, {"pct": 33, "suma_uvt": 69, "desde_uvt": 360}, {"pct": 35, "suma_uvt": 162, "desde_uvt": 640}, {"pct": 37, "suma_uvt": 268, "desde_uvt": 945}, {"pct": 39, "suma_uvt": 770, "desde_uvt": 2300}]'::jsonb, -- (gehnom 14-nov) nueva
    txt_avisos_gh             VARCHAR(200)            NOT NULL DEFAULT '',                      -- (gehnom 14-nov) nueva
    CONSTRAINT tab_pmtros_legales_pkey PRIMARY KEY (id_empresa, ano),
    CONSTRAINT chk_dias_vacaciones CHECK ((dias_vacaciones > 0)),
    CONSTRAINT chk_jornada_max_horas CHECK ((jornada_max_horas > 0)),
    CONSTRAINT chk_pct_arl CHECK (((pct_arl >= (0)::numeric) AND (pct_arl <= (100)::numeric))),
    CONSTRAINT chk_pct_ccf CHECK (((pct_ccf >= (0)::numeric) AND (pct_ccf <= (100)::numeric))),
    CONSTRAINT chk_pct_cesantias CHECK (((pct_cesantias >= (0)::numeric) AND (pct_cesantias <= (100)::numeric))),
    CONSTRAINT chk_pct_extra_diurna CHECK (((pct_extra_diurna >= (0)::numeric) AND (pct_extra_diurna <= (100)::numeric))),
    CONSTRAINT chk_pct_extra_dominical CHECK (((pct_extra_dominical >= (0)::numeric) AND (pct_extra_dominical <= (300)::numeric))),
    CONSTRAINT chk_pct_extra_nocturna CHECK (((pct_extra_nocturna >= (0)::numeric) AND (pct_extra_nocturna <= (100)::numeric))),
    CONSTRAINT chk_pct_icbf CHECK (((pct_icbf >= (0)::numeric) AND (pct_icbf <= (100)::numeric))),
    CONSTRAINT chk_pct_intereses_ces CHECK (((pct_intereses_ces >= (0)::numeric) AND (pct_intereses_ces <= (100)::numeric))),
    CONSTRAINT chk_pct_pension_empld CHECK (((pct_pension_empld >= (0)::numeric) AND (pct_pension_empld <= (100)::numeric))),
    CONSTRAINT chk_pct_pension_emplr CHECK (((pct_pension_emplr >= (0)::numeric) AND (pct_pension_emplr <= (100)::numeric))),
    CONSTRAINT chk_pct_prima CHECK (((pct_prima >= (0)::numeric) AND (pct_prima <= (100)::numeric))),
    CONSTRAINT chk_pct_rec_dom_noct CHECK (((pct_rec_dom_noct >= (0)::numeric) AND (pct_rec_dom_noct <= (300)::numeric))),
    CONSTRAINT chk_pct_rec_dominical CHECK (((pct_rec_dominical >= (0)::numeric) AND (pct_rec_dominical <= (100)::numeric))),
    CONSTRAINT chk_pct_rec_nocturno CHECK (((pct_rec_nocturno >= (0)::numeric) AND (pct_rec_nocturno <= (100)::numeric))),
    CONSTRAINT chk_pct_salud_emplea CHECK (((pct_salud_emplea >= (0)::numeric) AND (pct_salud_emplea <= (100)::numeric))),
    CONSTRAINT chk_pct_salud_emplr CHECK (((pct_salud_emplr >= (0)::numeric) AND (pct_salud_emplr <= (100)::numeric))),
    CONSTRAINT chk_pct_sena CHECK (((pct_sena >= (0)::numeric) AND (pct_sena <= (100)::numeric))),
    CONSTRAINT chk_pct_solidaridad CHECK (((pct_solidaridad >= (0)::numeric) AND (pct_solidaridad <= (100)::numeric))),
    CONSTRAINT chk_tipo_periodo_nomina CHECK (((tipo_periodo_nomina)::text = ANY (ARRAY[('MENSUAL'::character varying)::text, ('QUINCENAL'::character varying)::text]))),
    CONSTRAINT chk_tope_aux_transp_smlv CHECK ((tope_aux_transp_smlv > (0)::numeric))
);


--2. TABLA DE NIVEL DE ESCOLARIDAD
CREATE TABLE IF NOT EXISTS tab_escolaridad
(
    id_escolar                VARCHAR(5)              NOT NULL DEFAULT 'ESC00',                 -- Código único (ej: 'ESC01' A ESC99)
    nom_escolar               VARCHAR(20)             NOT NULL DEFAULT 'SIN ESCOLARIDAD',       -- Nombre del nivel educativo (ej:
    ind_borrado               BOOLEAN                 NOT NULL DEFAULT false,
    CONSTRAINT tab_escolaridad_pkey PRIMARY KEY (id_escolar),
    CONSTRAINT chk_escolaridad_nom CHECK (((nom_escolar)::text = ANY (ARRAY[('BACHILLER'::character varying)::text, ('AUXILIAR'::character varying)::text, ('TECNICO'::character varying)::text, ('TECNOLOGO'::character varying)::text, ('PROFESIONAL'::character varying)::text, ('ESPECIALISTA'::character varying)::text, ('MAGISTER'::character varying)::text, ('DOCTORADO'::character varying)::text, ('SIN ESCOLARIDAD'::character varying)::text])))
);


--3. TABLA DE PROFESIONES
CREATE TABLE IF NOT EXISTS tab_profesiones
(
    id_profesion              VARCHAR(8)              NOT NULL DEFAULT 'PROF000',               -- Código único (ej: 'PROF001 A PROF999)')
    nom_profesion             VARCHAR(100)            NOT NULL DEFAULT 'SIN PROFESIÓN',         -- Nombre oficial de la carrera o título
    ind_borrado               BOOLEAN                 NOT NULL DEFAULT false,
    CONSTRAINT tab_profesiones_pkey PRIMARY KEY (id_profesion)
);


--4. TABLA DE CARGOS
CREATE TABLE IF NOT EXISTS tab_cargos
(
    id_cargo                  VARCHAR(5)              NOT NULL DEFAULT 'CAR00',                 -- Número de identificación del cargo
    nom_cargo                 VARCHAR(50)             NOT NULL DEFAULT 'SIN CARGO',             -- Nombre del cargo
    ind_borrado               BOOLEAN                 NOT NULL DEFAULT false,
    CONSTRAINT tab_cargos_pkey PRIMARY KEY (id_cargo)
);
CREATE INDEX IF NOT EXISTS idx_nom_cargo ON tab_cargos (nom_cargo);


--5. TABLA DE ENTIDADES
CREATE TABLE IF NOT EXISTS tab_entidades
(
    id_entidad                VARCHAR(10)             NOT NULL DEFAULT '0000000000',
    nom_entidad               VARCHAR(60)             NOT NULL DEFAULT 'SIN NOMBRE DE ENTIDAD',
    ind_eps                   BOOLEAN                 NOT NULL DEFAULT false,
    ind_ccf                   BOOLEAN                 NOT NULL DEFAULT false,
    ind_arl                   BOOLEAN                 NOT NULL DEFAULT false,
    ind_afp                   BOOLEAN                 NOT NULL DEFAULT false,
    ind_sena                  BOOLEAN                 NOT NULL DEFAULT false,
    ind_borrado               BOOLEAN                 NOT NULL DEFAULT false,
    CONSTRAINT tab_entidades_pkey PRIMARY KEY (id_entidad)
);


--6. TABLA DE TIPOS DE CONTRATO (gehnom 14-nov) (catálogo; tab_empleados.id_tipo_contrato apunta aquí)
CREATE TABLE IF NOT EXISTS tab_tipos_contrato
(
    id_tipo_contrato          VARCHAR(5)              NOT NULL,
    nom_tipo_contrato         VARCHAR(30)             NOT NULL,
    ind_fecha_fin             BOOLEAN                 NOT NULL DEFAULT false,
    ind_borrado               BOOLEAN                 NOT NULL DEFAULT false,
    CONSTRAINT tab_tipos_contrato_pkey PRIMARY KEY (id_tipo_contrato),
    CONSTRAINT uq_tipos_contrato_nom UNIQUE (nom_tipo_contrato),
    CONSTRAINT chk_tipos_contrato_id CHECK (((id_tipo_contrato)::text ~ '^TC[0-9]{2}$'::text))
);


--7. TABLA DE REQUERIMIENTOS DE PERSONAL (gehnom 14-nov) (solicitudes de las áreas a Gestión Humana)
CREATE TABLE IF NOT EXISTS tab_req_personal
(
    id_req                    VARCHAR                 NOT NULL,
    id_area                   DECIMAL(5,0)            NOT NULL,
    id_cargo                  VARCHAR(5)              NOT NULL,
    id_escolar                VARCHAR(5)              NOT NULL DEFAULT 'ESC00',
    cant_solicitada           INTEGER                 NOT NULL,
    perfil_requerido          TEXT                    NOT NULL DEFAULT 'Sin perfil especificado',
    ind_estado_solicitud      VARCHAR(12)             NOT NULL DEFAULT 'PENDIENTE',
    obs_rrhh                  TEXT                    NOT NULL DEFAULT '',
    id_empleado_contratado    VARCHAR(10),
    fec_venc_req              DATE                    NOT NULL,
    fec_solicitud             TIMESTAMP               NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fec_contratacion          TIMESTAMP,
    ind_borrado               BOOLEAN                 NOT NULL DEFAULT false,
    ind_estado                BOOLEAN                 NOT NULL DEFAULT true,
    id_tipo_contrato          VARCHAR(5)              NOT NULL,
    CONSTRAINT tab_req_personal_pkey PRIMARY KEY (id_req, id_area),
    CONSTRAINT tab_req_personal_id_area_fkey FOREIGN KEY (id_area) REFERENCES tab_areas(id_area),
    CONSTRAINT tab_req_personal_id_cargo_fkey FOREIGN KEY (id_cargo) REFERENCES tab_cargos(id_cargo),
    CONSTRAINT tab_req_personal_id_escolar_fkey FOREIGN KEY (id_escolar) REFERENCES tab_escolaridad(id_escolar),
    CONSTRAINT tab_req_personal_id_tipo_contrato_fkey FOREIGN KEY (id_tipo_contrato) REFERENCES tab_tipos_contrato(id_tipo_contrato),
    CONSTRAINT chk_req_cant CHECK (((cant_solicitada > 0) AND (cant_solicitada <= 999))),
    CONSTRAINT chk_req_estado CHECK (((ind_estado_solicitud)::text = ANY (ARRAY[('PENDIENTE'::character varying)::text, ('APROBADA'::character varying)::text, ('RECHAZADA'::character varying)::text, ('CERRADA'::character varying)::text])))
);
CREATE INDEX IF NOT EXISTS idx_req_area ON tab_req_personal (id_area);
CREATE INDEX IF NOT EXISTS idx_req_estado ON tab_req_personal (ind_estado_solicitud);


--8. TABLA DE CANDIDATOS
CREATE TABLE IF NOT EXISTS tab_candidatos
(
    id_candidato              VARCHAR(10)             NOT NULL DEFAULT '0000000000',            -- Número de identificación del candidato
    nom_candidato             VARCHAR(100)            NOT NULL DEFAULT 'SIN NOMBRE DE CANDIDATO', -- Nombres del candidato
    ape_candidato             VARCHAR(100)            NOT NULL DEFAULT 'SIN APELLIDO DE CANDIDATO', -- Apellidos del candidato
    id_tipo                   VARCHAR(5)              NOT NULL DEFAULT 'CC',                    -- Tipo de documento del candidato (C.C, C.E, PTT, etc)  PENDIEMTE MIRAR TABLA NUEVA DE TIPO DE DOCUMENTO
    dir_empleado              DATOS_UBICACION,                                                  -- TYPE PARA DIRECCION TELEFONO Y MAIL
    id_ciudad                 VARCHAR(5)              NOT NULL DEFAULT '00000',                 -- CIUDAD DE RESIDENCIA DEL CANDIDATO
    fec_nacimiento            DATE                    NOT NULL DEFAULT '0001-01-01'::date,      -- FECHA NACIMIENTO DEL CANDIDATO
    ind_genero                BOOLEAN                 NOT NULL DEFAULT true,                    -- GENERO BIOLOGICO DEL CANDIDATO (TRUE=MASCULINO O FALSE=FEMENINO)
    nom_vacante               VARCHAR(20),
    prueba_1                  DECIMAL(4,2)            NOT NULL DEFAULT 0.00,                    -- Resultado prueba técnica
    prueba_2                  DECIMAL(4,2)            NOT NULL DEFAULT 0.00,                    -- Pruebas Psicotécnicas (Personalidad y Aptitud)
    prueba_3                  DECIMAL(4,2)            NOT NULL DEFAULT 0.00,                    -- Resultado prueba de habilidades blandas
    ind_estado                BOOLEAN                 NOT NULL DEFAULT true,                    -- TRUE = activo, FALSE = inactivo
    ind_borrado               BOOLEAN                 NOT NULL DEFAULT false,
    id_cargo                  VARCHAR(5)              NOT NULL,
    id_req                    VARCHAR,                                                          -- (gehnom 14-nov) nueva
    id_area                   DECIMAL(5,0),
    CONSTRAINT tab_candidatos_pkey PRIMARY KEY (id_candidato),
    CONSTRAINT tab_candidatos_id_cargo_fkey FOREIGN KEY (id_cargo) REFERENCES tab_cargos(id_cargo),
    CONSTRAINT tab_candidatos_id_ciudad_fkey FOREIGN KEY (id_ciudad) REFERENCES tab_ciudades(id_ciudad),
    CONSTRAINT tab_candidatos_id_tipo_fkey FOREIGN KEY (id_tipo) REFERENCES tab_tipo_identidad(id_tipo),
    CONSTRAINT tab_candidatos_req_fkey FOREIGN KEY (id_req, id_area) REFERENCES tab_req_personal(id_req, id_area),
    CONSTRAINT chk_candidato_fec_nac CHECK ((fec_nacimiento <= CURRENT_DATE)),
    CONSTRAINT chk_candidato_id_tipo CHECK (((id_tipo)::text = ANY (ARRAY[('CC'::character varying)::text, ('TI'::character varying)::text, ('CE'::character varying)::text, ('PT'::character varying)::text, ('PE'::character varying)::text, ('PA'::character varying)::text]))),
    CONSTRAINT chk_candidato_prueba1 CHECK (((prueba_1 >= (0)::numeric) AND (prueba_1 <= (100)::numeric))),
    CONSTRAINT chk_candidato_prueba2 CHECK (((prueba_2 >= (0)::numeric) AND (prueba_2 <= (100)::numeric))),
    CONSTRAINT chk_candidato_prueba3 CHECK (((prueba_3 >= (0)::numeric) AND (prueba_3 <= (100)::numeric))),
    CONSTRAINT chk_candidato_req CHECK (((id_req IS NULL) = (id_area IS NULL)))
);
CREATE INDEX IF NOT EXISTS idx_candidato_cargo ON tab_candidatos (id_cargo);
CREATE INDEX IF NOT EXISTS idx_nom_candidato ON tab_candidatos (nom_candidato);
CREATE INDEX IF NOT EXISTS idx_nom_vacante ON tab_candidatos (nom_vacante);


--9. TABLA DE EMPLEADOS
CREATE TABLE IF NOT EXISTS tab_empleados
(
    id_empleado               VARCHAR(10)             NOT NULL DEFAULT '0000000000',            -- Número de identificación del empleado
    nom_empleado              VARCHAR(100)            NOT NULL DEFAULT 'SIN NOMBRE DE EMPLEADO', -- Nombres del empleado
    ape_empleado              VARCHAR(100)            NOT NULL DEFAULT 'SIN APELLIDO DE EMPLEADO', -- Apellidos del empleado
    id_tipo                   VARCHAR(5)              NOT NULL DEFAULT 'SIN TIPO DE DOCUMENTO DE EMPLEADO', -- Tipo de documento del empleado (C.C, C.E, PTT, etc)
    tipo_sangre               VARCHAR(5)              NOT NULL DEFAULT 'SIN TIPO DE SANGRE DE EMPLEADO', -- Tipo de samgre del empleado
    fec_nacimiento            DATE                    NOT NULL DEFAULT '0001-01-01'::date,      -- Fecha de nacimiento del empleado
    ind_genero                BOOLEAN                 NOT NULL DEFAULT true,                    -- Genero del empleado (true= masculino, false= femenino)
    estado_civil              VARCHAR(15)             NOT NULL DEFAULT 'SIN ESTADO CIVIL DE EMPLEADO', -- Estado civil del empleado (Soltero, casado, etc)
    dir_empleado              DATOS_UBICACION         NOT NULL,                                 -- Datos de contacto del empleado
    nom_conyuge               VARCHAR(100)            NOT NULL DEFAULT 'SIN NOMBRE CÓNYUGE EMPLEADO', -- Nombre conyuge del empleado
    num_hijos                 DECIMAL(2,0)            NOT NULL DEFAULT 0,                       -- Número de hijos del empleado
    nom_contac_emer           VARCHAR(100)            NOT NULL DEFAULT 'SIN NOMBRE CONTACTO EMERGENCIA EMPLEADO', -- Nombre del contacto de emergencia del empleado
    datos_contac_emer         DATOS_UBICACION         NOT NULL,                                 -- Datos contacto de emergencia del empleado
    id_cargo                  VARCHAR(5)              NOT NULL DEFAULT 'CAR00',                 -- Número de identificación del cargo
    id_area                   DECIMAL(5,0)            NOT NULL,                                 -- Número de identificación del área
    id_profesion              VARCHAR(8)              NOT NULL DEFAULT 'PROF000',               -- Número de identificación de la profesión
    id_entidad_eps            VARCHAR(10)             NOT NULL DEFAULT '0000000000',            -- nombre de la eps del empleado
    id_entidad_ccf            VARCHAR(10)             NOT NULL DEFAULT '0000000000',            -- nombre caja de compensasión del empleado
    id_entidad_afp            VARCHAR(10)             NOT NULL DEFAULT '0000000000',            -- nombre del fondo de pension del empleado
    id_entidad_arl            VARCHAR(10)             NOT NULL DEFAULT '0000000000',            -- nombre ARL del empleado
    fec_ingreso               DATE                    NOT NULL DEFAULT '1900-01-01'::date,      -- fecha en la que ingreso a la empresa
    fec_retiro                DATE                    NOT NULL DEFAULT '2050-01-01'::date,      -- fecha hasta la que trabajo
    val_salario               DECIMAL(12,0)           NOT NULL DEFAULT 1750905,                 -- salario del empleado
    mail_corporativo          VARCHAR(30)             NOT NULL DEFAULT 'SIN CORREO CORPORATIVO DE EMPLEADO', -- correo corporativo del empleado
    ult_vacaciones            DATE                    NOT NULL DEFAULT '1900-01-01'::date,      -- ULTIMO PERIODO DE VACACIONES
    id_riesgo                 DECIMAL(1,0)            NOT NULL DEFAULT 0,                       -- nivel de riesgo laboral
    id_banco                  VARCHAR                 NOT NULL,                                 -- nombre de banco para pago
    num_cuenta                VARCHAR(20)             NOT NULL,                                 -- numero de cuenta bancaria para pagos
    ind_auditor               BOOLEAN                 NOT NULL DEFAULT false,                   -- ¿Es perfil auditor?
    ind_estado                BOOLEAN                 NOT NULL DEFAULT true,                    -- TRUE = ACTIVO FALSE = INACTIVO ¿Activo o Inactivo?
    ind_contratista           BOOLEAN                 NOT NULL DEFAULT false,                   -- TRUE=CONTRATISTA ¿Es de planta o contratista?
    ind_borrado               BOOLEAN                 NOT NULL DEFAULT false,
    url_hoja_vida             VARCHAR(255)            NOT NULL DEFAULT '',                      -- (gehnom 14-nov) nueva
    ind_es_vendedor           BOOLEAN                 NOT NULL DEFAULT false,                   -- (gehnom 14-nov) nueva
    id_tipo_contrato          VARCHAR(5)              NOT NULL DEFAULT 'TC01',                  -- (gehnom 14-nov) nueva
    fec_fin_contrato          DATE,                                                             -- (gehnom 14-nov) nueva
    url_contrato              VARCHAR(255)            NOT NULL DEFAULT '',                      -- (gehnom 14-nov) nueva
    ind_tipocuenta            BOOLEAN                 NOT NULL DEFAULT false,                   -- (gehnom 14-nov) nueva
    CONSTRAINT tab_empleados_pkey PRIMARY KEY (id_empleado),
    CONSTRAINT tab_empleados_id_area_fkey FOREIGN KEY (id_area) REFERENCES tab_areas(id_area),
    CONSTRAINT tab_empleados_id_banco_fkey FOREIGN KEY (id_banco) REFERENCES tab_bancos(id_banco),
    CONSTRAINT tab_empleados_id_cargo_fkey FOREIGN KEY (id_cargo) REFERENCES tab_cargos(id_cargo),
    CONSTRAINT tab_empleados_id_entidad_afp_fkey FOREIGN KEY (id_entidad_afp) REFERENCES tab_entidades(id_entidad),
    CONSTRAINT tab_empleados_id_entidad_arl_fkey FOREIGN KEY (id_entidad_arl) REFERENCES tab_entidades(id_entidad),
    CONSTRAINT tab_empleados_id_entidad_ccf_fkey FOREIGN KEY (id_entidad_ccf) REFERENCES tab_entidades(id_entidad),
    CONSTRAINT tab_empleados_id_entidad_eps_fkey FOREIGN KEY (id_entidad_eps) REFERENCES tab_entidades(id_entidad),
    CONSTRAINT tab_empleados_id_profesion_fkey FOREIGN KEY (id_profesion) REFERENCES tab_profesiones(id_profesion),
    CONSTRAINT tab_empleados_id_riesgo_fkey FOREIGN KEY (id_riesgo) REFERENCES tab_riesgos(id_riesgo),
    CONSTRAINT tab_empleados_id_tipo_contrato_fkey FOREIGN KEY (id_tipo_contrato) REFERENCES tab_tipos_contrato(id_tipo_contrato),
    CONSTRAINT tab_empleados_id_tipo_fkey FOREIGN KEY (id_tipo) REFERENCES tab_tipo_identidad(id_tipo),
    CONSTRAINT chk_empleado_fec_fin_contrato CHECK (((fec_fin_contrato IS NULL) OR (fec_fin_contrato > fec_ingreso))),
    CONSTRAINT chk_empleado_fec_ingreso CHECK ((fec_ingreso >= '1900-01-01'::date)),
    CONSTRAINT chk_empleado_fec_nac CHECK ((fec_nacimiento <= CURRENT_DATE)),
    CONSTRAINT chk_empleado_fec_retiro CHECK ((fec_retiro >= fec_ingreso)),
    CONSTRAINT chk_empleado_hijos CHECK ((num_hijos >= (0)::numeric)),
    CONSTRAINT chk_empleado_salario CHECK ((val_salario > (0)::numeric)),
    CONSTRAINT chk_empleado_ult_vacaciones CHECK ((ult_vacaciones >= fec_ingreso))
);


--9.1 TABLA DE CONTRATADOS POR REQUERIMIENTO (gehnom 14-nov)
CREATE TABLE IF NOT EXISTS tab_req_contratados
(
    id_req                    VARCHAR                 NOT NULL,
    id_area                   DECIMAL(5,0)            NOT NULL,
    id_empleado               VARCHAR(10)             NOT NULL,
    id_candidato              VARCHAR(10)             NOT NULL,
    fec_contratacion          TIMESTAMP               NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_usuario                VARCHAR(10)             NOT NULL,
    ind_borrado               BOOLEAN                 NOT NULL DEFAULT false,
    CONSTRAINT tab_req_contratados_pkey PRIMARY KEY (id_req, id_area, id_empleado),
    CONSTRAINT tab_req_contratados_emp_fkey FOREIGN KEY (id_empleado) REFERENCES tab_empleados(id_empleado),
    CONSTRAINT tab_req_contratados_req_fkey FOREIGN KEY (id_req, id_area) REFERENCES tab_req_personal(id_req, id_area),
    CONSTRAINT tab_req_contratados_usr_fkey FOREIGN KEY (id_usuario) REFERENCES tab_usuarios(id_usuario)
);
CREATE INDEX IF NOT EXISTS idx_req_contratados_req ON tab_req_contratados (id_req, id_area);


--10. TABLA DE PRESTAMOS
CREATE TABLE IF NOT EXISTS tab_prestamos
(
    id_prestamo               VARCHAR(10)             NOT NULL DEFAULT 'PRES000000',            -- ID préstamo
    id_empleado               VARCHAR(10)             NOT NULL DEFAULT '0000000000',            -- Empleado deudor
    val_prestamo              DECIMAL(12,2)           NOT NULL,                                 -- Monto prestado
    num_cuotas                INTEGER                 NOT NULL,                                 -- Plazo en meses
    tasa_intereses            DECIMAL(5,2)            NOT NULL,                                 -- Interés cobrado
    fecha_inicio              DATE                    NOT NULL DEFAULT CURRENT_DATE,            -- Fecha entrega
    fecha_fin                 DATE                    NOT NULL DEFAULT '2050-01-01'::date,      -- Fecha fin pago
    ind_estado                BOOLEAN                 NOT NULL DEFAULT false,                   -- ¿Deuda vigente?
    ind_borrado               BOOLEAN                 NOT NULL DEFAULT false,
    CONSTRAINT tab_prestamos_pkey PRIMARY KEY (id_prestamo),
    CONSTRAINT tab_prestamos_id_empleado_fkey FOREIGN KEY (id_empleado) REFERENCES tab_empleados(id_empleado),
    CONSTRAINT chk_prestamo_cuotas CHECK ((num_cuotas > 0)),
    CONSTRAINT chk_prestamo_fechas CHECK ((fecha_fin >= fecha_inicio)),
    CONSTRAINT chk_prestamo_tasa CHECK ((tasa_intereses >= (0)::numeric)),
    CONSTRAINT chk_prestamo_valor CHECK ((val_prestamo > (0)::numeric))
);


--10.1 TABLA DE CUOTAS DE PRÉSTAMO DESCONTADAS EN NÓMINA (gehnom 14-nov)
CREATE TABLE IF NOT EXISTS tab_prestamos_pagos
(
    id_prestamo               VARCHAR(10)             NOT NULL,
    ano_nomina                DECIMAL(4,0)            NOT NULL,
    mes_nomina                DECIMAL(2,0)            NOT NULL,
    val_periodo               DECIMAL(1,0)            NOT NULL,
    val_cuota                 DECIMAL(12,0)           NOT NULL,
    val_interes               DECIMAL(12,0)           NOT NULL,
    val_capital               DECIMAL(12,0)           NOT NULL,
    val_saldo                 DECIMAL(12,0)           NOT NULL,
    fec_pago                  DATE                    NOT NULL DEFAULT ((CURRENT_TIMESTAMP AT TIME ZONE 'America/Bogota'::text))::date,
    CONSTRAINT tab_prestamos_pagos_pkey PRIMARY KEY (id_prestamo, ano_nomina, mes_nomina, val_periodo),
    CONSTRAINT fk_prestamos_pagos_prestamo FOREIGN KEY (id_prestamo) REFERENCES tab_prestamos(id_prestamo),
    CONSTRAINT chk_prestamos_pagos_cuota CHECK ((val_cuota >= (0)::numeric)),
    CONSTRAINT chk_prestamos_pagos_mes CHECK (((mes_nomina >= (1)::numeric) AND (mes_nomina <= (12)::numeric))),
    CONSTRAINT chk_prestamos_pagos_periodo CHECK ((val_periodo = ANY (ARRAY[(1)::numeric, (2)::numeric]))),
    CONSTRAINT chk_prestamos_pagos_saldo CHECK ((val_saldo >= (0)::numeric))
);


--11. TABLA DE CONCEPTO DE NOMINA
CREATE TABLE IF NOT EXISTS tab_conceptos
(
    id_concepto               VARCHAR(10)             NOT NULL DEFAULT 'CONC000000',            -- ID concepto (ej: 001)
    nom_concepto              VARCHAR(50)             NOT NULL DEFAULT 'SIN NOMBRE DE CONCEPTO', -- Salario, Hora Extra, Recargo Nocturno, Incapacidad, Prima, o Deducción.
    ind_obligatorio           BOOLEAN                 NOT NULL DEFAULT true,                    -- TRUE = SI APLICA  FALSE = NO APLICA
    ind_devengado             BOOLEAN                 NOT NULL DEFAULT false,                   -- TRUE = DEVENGADO FALSE = DEDUCIDO
    val_concepto              INTEGER                 NOT NULL,
    ind_borrado               BOOLEAN                 NOT NULL DEFAULT false,
    tipo_calculo              VARCHAR(15)             NOT NULL DEFAULT 'DIRECTO',               -- (gehnom 14-nov) nueva
    cod_param                 VARCHAR(20),                                                      -- (gehnom 14-nov) nueva
    ind_salarial              BOOLEAN                 NOT NULL DEFAULT false,                   -- (gehnom 14-nov) nueva
    CONSTRAINT tab_conceptos_pkey PRIMARY KEY (id_concepto),
    CONSTRAINT chk_concepto_tipo_calculo CHECK (((tipo_calculo)::text = ANY (ARRAY['RECARGO'::text, 'POR_DIA'::text, 'DIRECTO'::text, 'FIJO'::text, 'LEGAL'::text]))),
    CONSTRAINT chk_concepto_valor CHECK ((val_concepto > 0))
);
CREATE INDEX IF NOT EXISTS idx_nom_concepto ON tab_conceptos (nom_concepto);


--12. TABLA DE NOVEDADES
CREATE SEQUENCE IF NOT EXISTS seq_tab_novedades;
CREATE TABLE IF NOT EXISTS tab_novedades
(
    ano_nomina                DECIMAL(4,0)            NOT NULL,
    mes_nomina                DECIMAL(2,0)            NOT NULL,
    val_periodo               DECIMAL(1,0)            NOT NULL,
    id_empleado               VARCHAR(10)             NOT NULL,                                 -- Empleado afectado
    id_concepto               VARCHAR(10)             NOT NULL,                                 -- Tipo de novedad
    num_dias_trab             DECIMAL(2,0)            NOT NULL DEFAULT 0,
    val_novedad               DECIMAL(9,0)            NOT NULL,
    fec_novedad               DATE                    NOT NULL,
    ind_borrado               BOOLEAN                 NOT NULL DEFAULT false,
    id_novedad                INTEGER                 NOT NULL DEFAULT nextval('seq_tab_novedades'::regclass), -- (gehnom 14-nov) nueva
    ind_periodo               BOOLEAN                 NOT NULL,                                 -- (gehnom 14-nov) nueva
    cant_nov                  DECIMAL(5,2)            NOT NULL,                                 -- (gehnom 14-nov) nueva
    ind_estado                BOOLEAN                 NOT NULL DEFAULT false,                   -- (gehnom 14-nov) nueva
    CONSTRAINT tab_novedades_pkey PRIMARY KEY (ano_nomina, mes_nomina, val_periodo, id_empleado, id_concepto, fec_novedad),
    CONSTRAINT uq_novedades_id UNIQUE (id_novedad),
    CONSTRAINT fk_novedades_concepto FOREIGN KEY (id_concepto) REFERENCES tab_conceptos(id_concepto),
    CONSTRAINT fk_novedades_empleado FOREIGN KEY (id_empleado) REFERENCES tab_empleados(id_empleado),
    CONSTRAINT chk_novedades_dias CHECK ((num_dias_trab >= (0)::numeric)),
    CONSTRAINT chk_novedades_fecha CHECK ((fec_novedad <= CURRENT_DATE)),
    CONSTRAINT chk_novedades_mes CHECK (((mes_nomina >= (1)::numeric) AND (mes_nomina <= (12)::numeric))),
    CONSTRAINT chk_novedades_periodo CHECK ((val_periodo = ANY (ARRAY[(1)::numeric, (2)::numeric])))
);
ALTER SEQUENCE seq_tab_novedades OWNED BY tab_novedades.id_novedad;


--13. TABLA DE PROCESOS DISCIPLINARIOS
CREATE TABLE IF NOT EXISTS tab_procesos_disciplinarios
(
    id_proceso                VARCHAR(20)             NOT NULL,
    id_empleado               VARCHAR(10)             NOT NULL,
    fec_proceso               DATE                    NOT NULL,
    motivo                    TEXT                    NOT NULL,
    ind_estado_proceso        BOOLEAN                 NOT NULL,                                 -- 'En descargos', 'Cerrado', 'Anulado'
    sancion_final             VARCHAR(100),                                                     -- 'Llamado de atención', 'Suspension X días'
    ind_borrado               BOOLEAN                 NOT NULL DEFAULT false,
    CONSTRAINT tab_procesos_disciplinarios_pkey PRIMARY KEY (id_proceso),
    CONSTRAINT tab_procesos_disciplinarios_id_empleado_fkey FOREIGN KEY (id_empleado) REFERENCES tab_empleados(id_empleado),
    CONSTRAINT chk_proceso_fecha CHECK ((fec_proceso <= CURRENT_DATE))
);


--14. TABLA DE NÓMINA
CREATE TABLE IF NOT EXISTS tab_nomina
(
    ano_nomina                DECIMAL(4,0)            NOT NULL,
    mes_nomina                DECIMAL(2,0)            NOT NULL,
    val_periodo               DECIMAL(1,0)            NOT NULL,
    id_empleado               VARCHAR(10)             NOT NULL,
    tot_devengado             DECIMAL(10,0)           DEFAULT 0,
    tot_deducido              DECIMAL(10,0)           DEFAULT 0,
    val_neto                  DECIMAL(10,0)           NOT NULL,                                 -- valor neto a pagar al empleado
    ind_cerrado               BOOLEAN                 NOT NULL,                                 -- true: cerrada, false: abierta
    ind_borrado               BOOLEAN                 NOT NULL DEFAULT false,
    ind_periodo               BOOLEAN                 NOT NULL,                                 -- (gehnom 14-nov) nueva
    dias_trab                 DECIMAL(2,0)            NOT NULL,                                 -- (gehnom 14-nov) nueva
    ind_pagado                BOOLEAN                 NOT NULL DEFAULT false,                   -- (gehnom 14-nov) nueva
    val_ibc                   DECIMAL(12,0)           NOT NULL DEFAULT 0,                       -- (gehnom 14-nov) nueva
    val_salarial              DECIMAL(12,0)           NOT NULL DEFAULT 0,                       -- (gehnom 14-nov) nueva
    val_no_salarial           DECIMAL(12,0)           NOT NULL DEFAULT 0,                       -- (gehnom 14-nov) nueva
    estado_pago               DECIMAL(1,0)            NOT NULL DEFAULT 0,                       -- (gehnom 14-nov) nueva
    fec_pago                  DATE,                                                             -- (gehnom 14-nov) nueva
    id_archivo_plano          DECIMAL(10,0),                                                    -- (gehnom 14-nov) nueva
    CONSTRAINT tab_nomina_pkey PRIMARY KEY (ano_nomina, mes_nomina, val_periodo, id_empleado),
    CONSTRAINT tab_nomina_id_empleado_fkey FOREIGN KEY (id_empleado) REFERENCES tab_empleados(id_empleado),
    CONSTRAINT chk_nomina_deducido CHECK ((tot_deducido >= (0)::numeric)),
    CONSTRAINT chk_nomina_devengado CHECK ((tot_devengado >= (0)::numeric)),
    CONSTRAINT chk_nomina_dias CHECK (((dias_trab >= (1)::numeric) AND (dias_trab <= (30)::numeric))),
    CONSTRAINT chk_nomina_estado_pago CHECK ((estado_pago = ANY (ARRAY[(0)::numeric, (1)::numeric, (2)::numeric, (3)::numeric]))),
    CONSTRAINT chk_nomina_mes CHECK (((mes_nomina >= (1)::numeric) AND (mes_nomina <= (12)::numeric))),
    CONSTRAINT chk_nomina_neto CHECK ((val_neto >= (0)::numeric)),
    CONSTRAINT chk_nomina_periodo CHECK ((val_periodo = ANY (ARRAY[(1)::numeric, (2)::numeric])))
);
CREATE INDEX IF NOT EXISTS idx_nomina_estado_pago ON tab_nomina (estado_pago);


--14.1 TABLA DE DETALLE DE NÓMINA POR CONCEPTO (gehnom 14-nov)
CREATE TABLE IF NOT EXISTS tab_nomina_detalle
(
    ano_nomina                DECIMAL(4,0)            NOT NULL,
    mes_nomina                DECIMAL(2,0)            NOT NULL,
    val_periodo               DECIMAL(1,0)            NOT NULL,
    id_empleado               VARCHAR(10)             NOT NULL,
    id_concepto               VARCHAR(10)             NOT NULL,
    ind_devengado             BOOLEAN                 NOT NULL,
    cant                      DECIMAL(6,2)            NOT NULL DEFAULT 1,
    val_concepto              DECIMAL(12,0)           NOT NULL,
    CONSTRAINT tab_nomina_detalle_pkey PRIMARY KEY (ano_nomina, mes_nomina, val_periodo, id_empleado, id_concepto),
    CONSTRAINT fk_nomina_detalle_cabecera FOREIGN KEY (ano_nomina, mes_nomina, val_periodo, id_empleado) REFERENCES tab_nomina(ano_nomina, mes_nomina, val_periodo, id_empleado) ON DELETE CASCADE,
    CONSTRAINT fk_nomina_detalle_concepto FOREIGN KEY (id_concepto) REFERENCES tab_conceptos(id_concepto),
    CONSTRAINT chk_nomina_detalle_mes CHECK (((mes_nomina >= (1)::numeric) AND (mes_nomina <= (12)::numeric))),
    CONSTRAINT chk_nomina_detalle_periodo CHECK ((val_periodo = ANY (ARRAY[(1)::numeric, (2)::numeric]))),
    CONSTRAINT chk_nomina_detalle_valor CHECK ((val_concepto >= (0)::numeric))
);


--14.2 TABLA DE AVISOS DE LA LIQUIDACIÓN (gehnom 14-nov)
CREATE TABLE IF NOT EXISTS tab_nomina_avisos
(
    id_aviso                  SERIAL,
    ano_nomina                DECIMAL(4,0)            NOT NULL,
    mes_nomina                DECIMAL(2,0)            NOT NULL,
    val_periodo               DECIMAL(1,0)            NOT NULL,
    id_empleado               VARCHAR,
    des_aviso                 TEXT                    NOT NULL,
    CONSTRAINT tab_nomina_avisos_pkey PRIMARY KEY (id_aviso)
);
CREATE INDEX IF NOT EXISTS idx_nomina_avisos_periodo ON tab_nomina_avisos (ano_nomina, mes_nomina, val_periodo);


--14.3 TABLA DE APORTES Y PROVISIONES DEL EMPLEADOR (gehnom 14-nov)
CREATE TABLE IF NOT EXISTS tab_nomina_empleador
(
    ano_nomina                DECIMAL(4,0)            NOT NULL,
    mes_nomina                DECIMAL(2,0)            NOT NULL,
    val_periodo               DECIMAL(1,0)            NOT NULL,
    id_empleado               VARCHAR                 NOT NULL,
    val_base_ibc              DECIMAL(12,0)           NOT NULL DEFAULT 0,
    val_base_arl              DECIMAL(12,0)           NOT NULL DEFAULT 0,
    val_base_parafiscal       DECIMAL(12,0)           NOT NULL DEFAULT 0,
    val_base_prestacion       DECIMAL(12,0)           NOT NULL DEFAULT 0,
    val_base_vacaciones       DECIMAL(12,0)           NOT NULL DEFAULT 0,
    pct_arl_aplicado          DECIMAL(6,3)            NOT NULL DEFAULT 0,
    ind_exonerado             BOOLEAN                 NOT NULL DEFAULT false,
    val_salud                 DECIMAL(12,0)           NOT NULL DEFAULT 0,
    val_pension               DECIMAL(12,0)           NOT NULL DEFAULT 0,
    val_arl                   DECIMAL(12,0)           NOT NULL DEFAULT 0,
    val_sena                  DECIMAL(12,0)           NOT NULL DEFAULT 0,
    val_icbf                  DECIMAL(12,0)           NOT NULL DEFAULT 0,
    val_ccf                   DECIMAL(12,0)           NOT NULL DEFAULT 0,
    val_prov_prima            DECIMAL(12,0)           NOT NULL DEFAULT 0,
    val_prov_cesantias        DECIMAL(12,0)           NOT NULL DEFAULT 0,
    val_prov_intereses        DECIMAL(12,0)           NOT NULL DEFAULT 0,
    val_prov_vacaciones       DECIMAL(12,0)           NOT NULL DEFAULT 0,
    CONSTRAINT tab_nomina_empleador_pkey PRIMARY KEY (ano_nomina, mes_nomina, val_periodo, id_empleado),
    CONSTRAINT fk_nomina_empleador_cabecera FOREIGN KEY (ano_nomina, mes_nomina, val_periodo, id_empleado) REFERENCES tab_nomina(ano_nomina, mes_nomina, val_periodo, id_empleado)
);


--15. TABLA DE NÓMINA ELECTRÓNICA (DIAN)
CREATE TABLE IF NOT EXISTS tab_nomina_electronica
(
    id_nomina_electronica     VARCHAR(10)             NOT NULL,
    periodo_mes               INTEGER                 NOT NULL,
    periodo_ano               INTEGER                 NOT NULL,
    archivo_xml               TEXT,                                                             -- XML generado
    track_id                  VARCHAR(100),                                                     -- ID de envío a DIAN
    estado_envio              VARCHAR(30)             DEFAULT 'PENDIENTE',                      -- PENDIENTE, ENVIADO, ACEPTADO, RECHAZADO
    fecha_envio               DATE,
    respuesta_dian            TEXT,
    ind_borrado               BOOLEAN                 NOT NULL DEFAULT false,
    CONSTRAINT tab_nomina_electronica_pkey PRIMARY KEY (id_nomina_electronica),
    CONSTRAINT chk_periodo_ano CHECK ((periodo_ano >= 2000)),
    CONSTRAINT chk_periodo_mes CHECK (((periodo_mes >= 1) AND (periodo_mes <= 12)))
);


--16. TABLA DE PRESTACIONES SOCIALES (prima, cesantías, intereses, vacaciones, retiro) (gehnom 14-nov)
CREATE TABLE IF NOT EXISTS tab_prestaciones
(
    id_prestacion             SERIAL,
    id_empleado               VARCHAR                 NOT NULL,
    tipo                      VARCHAR(20)             NOT NULL,
    ano                       DECIMAL(4,0)            NOT NULL,
    periodo                   DECIMAL(1,0)            NOT NULL DEFAULT 0,
    origen                    VARCHAR(10)             NOT NULL DEFAULT 'PERIODICA',
    fec_ini                   DATE                    NOT NULL,
    fec_fin                   DATE                    NOT NULL,
    dias                      DECIMAL(6,2)            NOT NULL DEFAULT 0,
    val_base                  DECIMAL(12,0)           NOT NULL DEFAULT 0,
    val_valor                 DECIMAL(12,0)           NOT NULL DEFAULT 0,
    val_retencion             DECIMAL(12,0)           NOT NULL DEFAULT 0,
    val_neto                  DECIMAL(12,0)           NOT NULL DEFAULT 0,
    ind_pagado                BOOLEAN                 NOT NULL DEFAULT false,
    fec_pago                  DATE,
    ind_borrado               BOOLEAN                 NOT NULL DEFAULT false,
    CONSTRAINT tab_prestaciones_pkey PRIMARY KEY (id_prestacion),
    CONSTRAINT tab_prestaciones_id_empleado_fkey FOREIGN KEY (id_empleado) REFERENCES tab_empleados(id_empleado),
    CONSTRAINT chk_prestacion_neto CHECK ((val_neto >= (0)::numeric)),
    CONSTRAINT chk_prestacion_origen CHECK (((origen)::text = ANY (ARRAY[('PERIODICA'::character varying)::text, ('RETIRO'::character varying)::text]))),
    CONSTRAINT chk_prestacion_tipo CHECK (((tipo)::text = ANY (ARRAY[('PRIMA'::character varying)::text, ('CESANTIAS'::character varying)::text, ('INTERESES_CESANTIAS'::character varying)::text, ('VACACIONES_DINERO'::character varying)::text, ('INDEMNIZACION'::character varying)::text])))
);
CREATE INDEX IF NOT EXISTS idx_prestaciones_ano ON tab_prestaciones (ano, tipo);
CREATE UNIQUE INDEX IF NOT EXISTS uq_prestacion_vigente ON tab_prestaciones (id_empleado, tipo, ano, periodo) WHERE ((ind_borrado = false) AND ((tipo)::text <> 'VACACIONES_DINERO'::text));


--17. TABLA DE VACACIONES (gehnom 14-nov)
CREATE TABLE IF NOT EXISTS tab_vacaciones
(
    id_vacacion               SERIAL,
    id_empleado               VARCHAR                 NOT NULL,
    tipo                      VARCHAR(10)             NOT NULL,
    fec_ini                   DATE                    NOT NULL,
    dias_habiles              DECIMAL(5,2)            NOT NULL,
    dias_calendario           DECIMAL(5,2)            NOT NULL DEFAULT 0,
    ind_borrado               BOOLEAN                 NOT NULL DEFAULT false,
    CONSTRAINT tab_vacaciones_pkey PRIMARY KEY (id_vacacion),
    CONSTRAINT tab_vacaciones_id_empleado_fkey FOREIGN KEY (id_empleado) REFERENCES tab_empleados(id_empleado),
    CONSTRAINT chk_vacacion_dias CHECK ((dias_habiles > (0)::numeric)),
    CONSTRAINT chk_vacacion_tipo CHECK (((tipo)::text = ANY (ARRAY[('DISFRUTE'::character varying)::text, ('DINERO'::character varying)::text, ('AJUSTE'::character varying)::text, ('RETIRO'::character varying)::text])))
);


--18. TABLA DE BITÁCORA DE ALERTAS DE VENCIMIENTO DE CONTRATO (gehnom 14-nov)
CREATE TABLE IF NOT EXISTS tab_log_alerta_contrato
(
    id_empleado               VARCHAR(10)             NOT NULL,
    fec_fin_contrato          DATE                    NOT NULL,
    num_hito                  DECIMAL(2,0)            NOT NULL,
    id_usuario_destino        VARCHAR                 NOT NULL,
    dias_restantes            INTEGER                 NOT NULL,
    id_notificacion           DECIMAL(8,0)            NOT NULL,
    fec_envio                 TIMESTAMPTZ             NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tab_log_alerta_contrato_pkey PRIMARY KEY (id_empleado, fec_fin_contrato, num_hito, id_usuario_destino),
    CONSTRAINT tab_log_alerta_contrato_id_empleado_fkey FOREIGN KEY (id_empleado) REFERENCES tab_empleados(id_empleado),
    CONSTRAINT chk_log_alerta_contrato_hito CHECK ((num_hito = ANY (ARRAY[(30)::numeric, (7)::numeric, (0)::numeric])))
);

-- (gehnom 14-nov) Llaves foráneas circulares entre tablas de GEHNOM (la tabla destino se crea después)
ALTER TABLE tab_req_personal ADD CONSTRAINT tab_req_personal_id_empleado_contratado_fkey FOREIGN KEY (id_empleado_contratado) REFERENCES tab_empleados(id_empleado);

----------------------------------------------
-- MÓDULO DE SEGURIDAD Y SALUD EN EL TRABAJO -
----------------------------------------------

------------------------------
-- TABLA TIPO DE ACCIDENTES --
------------------------------

CREATE TABLE IF NOT EXISTS  tab_tipo_acc
(
    id_tipo_acc         	DECIMAL(4,0)		NOT NULL      	CHECK(id_tipo_acc >= 1 AND id_tipo_acc <= 9999),                        --IDENTIFICADOR PARA EL TIPO DE ACCIDENTE
    nom_tipo_acc           	VARCHAR(60)    		NOT NULL      	CHECK(LENGTH(TRIM(nom_tipo_acc)) >= 3),                                 --NOMBRE DEL TIPO DE ACCIDENTE (EJ: CAÍDA A NIVEL, GOLPE CON OBJETO, CONTACTO ELÉCTRICO)
    desc_tipo_acc         	TEXT                NOT NULL        DEFAULT 'SIN DESCRIPCIÓN',                                              --DESCRIPCIÓN DEL TIPO DE ACCIDENTE
    ind_borrado				BOOLEAN				NOT NULL 		DEFAULT FALSE,
	PRIMARY KEY (id_tipo_acc),
	UNIQUE (nom_tipo_acc)
);

-- Carga inicial con el mecanismo o forma del accidente del FURAT
-- (Res. 156 de 2005). Se puede ampliar desde Accidentes.php.
INSERT INTO tab_tipo_acc (id_tipo_acc, nom_tipo_acc, desc_tipo_acc) VALUES
    (1, 'CAÍDA DE PERSONAS',                                          'CAÍDA DEL TRABAJADOR A UN MISMO NIVEL O DESDE ALTURA.'),
    (2, 'CAÍDA DE OBJETOS',                                           'OBJETOS, HERRAMIENTAS O MATERIALES QUE CAEN SOBRE EL TRABAJADOR.'),
    (3, 'PISADAS, CHOQUES O GOLPES',                                  'PISADAS SOBRE OBJETOS, CHOQUES CONTRA OBJETOS O GOLPES POR OBJETOS EN MOVIMIENTO.'),
    (4, 'ATRAPAMIENTOS',                                              'ATRAPAMIENTO POR UN OBJETO O ENTRE OBJETOS, MÁQUINAS O PARTES EN MOVIMIENTO.'),
    (5, 'SOBREESFUERZO, ESFUERZO EXCESIVO O FALSO MOVIMIENTO',        'LESIÓN POR LEVANTAR, EMPUJAR O HALAR CARGAS, O POR UN MOVIMIENTO BRUSCO O MAL EJECUTADO.'),
    (6, 'EXPOSICIÓN O CONTACTO CON TEMPERATURA EXTREMA',              'CONTACTO CON SUPERFICIES, LÍQUIDOS O AMBIENTES MUY CALIENTES O MUY FRÍOS.'),
    (7, 'EXPOSICIÓN O CONTACTO CON LA ELECTRICIDAD',                  'CONTACTO DIRECTO O INDIRECTO CON LA CORRIENTE ELÉCTRICA.'),
    (8, 'EXPOSICIÓN O CONTACTO CON SUSTANCIAS NOCIVAS O RADIACIONES', 'CONTACTO, INHALACIÓN O INGESTIÓN DE SUSTANCIAS NOCIVAS, RADIACIONES O SALPICADURAS.'),
    (9, 'OTRO',                                                       'MECANISMO NO CLASIFICADO EN LAS OPCIONES ANTERIORES.');


---------------------------------
-- TABLA PARTES DEL CUERPO (SST) --
---------------------------------
-- Catalogo de la parte del cuerpo afectada en un accidente. Se carga con la
-- clasificacion del FURAT (Res. 156 de 2005) y se puede ampliar desde
-- Accidentes.php.
CREATE TABLE IF NOT EXISTS tab_partes_cuerpo
(
    id_parte_cuerpo         DECIMAL(3,0)        NOT NULL        CHECK(id_parte_cuerpo >= 1 AND id_parte_cuerpo <= 999),                 --IDENTIFICADOR DE LA PARTE DEL CUERPO
    nom_parte_cuerpo        VARCHAR(60)         NOT NULL        CHECK(LENGTH(TRIM(nom_parte_cuerpo)) >= 3),                             --NOMBRE DE LA PARTE DEL CUERPO (EJ: CABEZA, MANOS, PIES)
    ind_borrado             BOOLEAN             NOT NULL        DEFAULT FALSE,
    PRIMARY KEY (id_parte_cuerpo),
    UNIQUE (nom_parte_cuerpo)
);

INSERT INTO tab_partes_cuerpo (id_parte_cuerpo, nom_parte_cuerpo) VALUES
    (1,  'CABEZA'),
    (2,  'OJOS'),
    (3,  'CUELLO'),
    (4,  'TRONCO (ESPALDA, COLUMNA, PELVIS)'),
    (5,  'TÓRAX'),
    (6,  'ABDOMEN'),
    (7,  'MIEMBROS SUPERIORES'),
    (8,  'MANOS'),
    (9,  'MIEMBROS INFERIORES'),
    (10, 'PIES'),
    (11, 'UBICACIONES MÚLTIPLES'),
    (12, 'LESIONES GENERALES U OTRAS');


---------------------------------
-- TABLA TIPOS DE LESIÓN (SST) --
---------------------------------
-- Catalogo del tipo de lesion sufrida en un accidente. Se carga con la
-- clasificacion del FURAT (Res. 156 de 2005) y se puede ampliar desde
-- Accidentes.php.
CREATE TABLE IF NOT EXISTS tab_tipo_lesion
(
    id_tipo_lesion          DECIMAL(3,0)        NOT NULL        CHECK(id_tipo_lesion >= 1 AND id_tipo_lesion <= 999),                   --IDENTIFICADOR DEL TIPO DE LESIÓN
    nom_tipo_lesion         VARCHAR(100)        NOT NULL        CHECK(LENGTH(TRIM(nom_tipo_lesion)) >= 3),                              --NOMBRE DEL TIPO DE LESIÓN (EJ: FRACTURA, HERIDA, QUEMADURA)
    ind_borrado             BOOLEAN             NOT NULL        DEFAULT FALSE,
    PRIMARY KEY (id_tipo_lesion),
    UNIQUE (nom_tipo_lesion)
);

INSERT INTO tab_tipo_lesion (id_tipo_lesion, nom_tipo_lesion) VALUES
    (1,  'FRACTURA'),
    (2,  'LUXACIÓN'),
    (3,  'TORCEDURA, ESGUINCE, DESGARRO MUSCULAR, HERNIA O LACERACIÓN DE MÚSCULO O TENDÓN SIN HERIDA'),
    (4,  'CONMOCIÓN O TRAUMA INTERNO'),
    (5,  'AMPUTACIÓN O ENUCLEACIÓN'),
    (6,  'HERIDA'),
    (7,  'TRAUMA SUPERFICIAL'),
    (8,  'GOLPE, CONTUSIÓN O APLASTAMIENTO'),
    (9,  'QUEMADURA'),
    (10, 'ENVENENAMIENTO, INTOXICACIÓN AGUDA O ALERGIA'),
    (11, 'EFECTO DEL TIEMPO, DEL CLIMA U OTRO RELACIONADO CON EL AMBIENTE'),
    (12, 'ASFIXIA'),
    (13, 'EFECTO DE LA ELECTRICIDAD'),
    (14, 'EFECTO NOCIVO DE LA RADIACIÓN'),
    (15, 'LESIONES MÚLTIPLES'),
    (16, 'OTRO');


-----------------------------
-- TABLA CATEGORÍAS DE EPP --
-----------------------------
-- Catalogo de la categoria del EPP segun la parte del cuerpo que protege.
-- Reemplaza la lista que estaba quemada en el front. Se debe crear ANTES que
-- tab_epp porque tab_epp la referencia.
-- Carga inicial con la clasificacion de la Res. 2400 de 1979 (Titulo IV,
-- Cap. II, Art. 177 y Arts. 186-192) y la Res. 4272 de 2021 (trabajo en
-- alturas). Los ids 1 a 7 conservan el significado de la lista anterior del
-- front para no dañar los EPP ya registrados; el 7 pasa de 'NO APLICA' a 'OTRO'.
CREATE TABLE IF NOT EXISTS tab_categoria_epp
(
    id_categoria_epp        DECIMAL(2,0)        NOT NULL        CHECK(id_categoria_epp >= 1 AND id_categoria_epp <= 99),                --IDENTIFICADOR DE LA CATEGORÍA DEL EPP
    nom_categoria_epp       VARCHAR(60)         NOT NULL        CHECK(LENGTH(TRIM(nom_categoria_epp)) >= 3),                            --NOMBRE DE LA CATEGORÍA (EJ: CABEZA, OJOS Y ROSTRO, MANOS Y BRAZOS)
    desc_categoria_epp      TEXT                NOT NULL        DEFAULT 'SIN DESCRIPCIÓN',                                              --QUÉ ELEMENTOS INCLUYE Y NORMA QUE LA SOPORTA
    ind_borrado             BOOLEAN             NOT NULL        DEFAULT FALSE,
    PRIMARY KEY (id_categoria_epp),
    UNIQUE (nom_categoria_epp)
);
 
INSERT INTO tab_categoria_epp (id_categoria_epp, nom_categoria_epp, desc_categoria_epp) VALUES
    (1, 'PROTECCIÓN DE LA CABEZA',                  'CASCOS DE SEGURIDAD Y COFIAS. RES. 2400/1979 ART. 177 NUM. 1.'),
    (2, 'PROTECCIÓN DE OJOS Y ROSTRO',              'GAFAS, MONOGAFAS, CARETAS, PANTALLAS Y FILTROS PARA SOLDADURA. RES. 2400/1979 ART. 177 NUM. 2 Y ARTS. 179-181, 193-195.'),
    (3, 'PROTECCIÓN DE MANOS Y BRAZOS',             'GUANTES (DIELÉCTRICOS, CUERO, CAUCHO, NITRILO, MALLA), GUANTELETES Y MANGAS. RES. 2400/1979 ART. 177 NUM. 4.'),
    (4, 'PROTECCIÓN DE VÍAS RESPIRATORIAS',         'TAPABOCAS, RESPIRADORES CON FILTRO O CARTUCHO, MÁSCARAS Y EQUIPOS CON SUMINISTRO DE AIRE. RES. 2400/1979 ART. 177 NUM. 3 Y ARTS. 182-185, 196-201.'),
    (5, 'PROTECCIÓN CONTRA CAÍDAS',                 'ARNÉS DE CUERPO COMPLETO, ESLINGAS, CONECTORES, LÍNEAS DE VIDA Y RETRÁCTILES. RES. 2400/1979 ARTS. 188-191 Y RES. 4272/2021.'),
    (6, 'PROTECCIÓN AUDITIVA',                      'TAPONES Y PROTECTORES AUDITIVOS TIPO COPA. RES. 2400/1979 ART. 177 NUM. 1.'),
    (7, 'OTRO',                                     'ELEMENTO NO CLASIFICADO EN LAS CATEGORÍAS ANTERIORES.'),
    (8, 'PROTECCIÓN DE PIES Y PIERNAS',             'BOTAS Y CALZADO DE SEGURIDAD (PUNTERA, DIELÉCTRICO, CAUCHO), POLAINAS Y CANILLERAS. RES. 2400/1979 ART. 177 NUM. 5.'),
    (9, 'PROTECCIÓN DEL TRONCO Y CUERPO',           'DELANTALES, MANDILES, OVEROLES Y TRAJES CONTRA QUÍMICOS, CALOR O RADIACIÓN, Y CHALECOS REFLECTIVOS. RES. 2400/1979 ART. 177 NUM. 6 Y ARTS. 186-187, 192.');


----------------------
-- TABLA EPP        --
----------------------
-- Todo EPP es tambien un producto de tab_productos (modulo de compras) para
-- poder pedirlo en las ordenes de compra. id_epp ES el id_producto: mismo id
-- en las dos tablas, igual que tab_proveedores.id_proveedor es el id_tercero.
-- Por eso el script de compras (tab_productos) se corre ANTES que este.
-- El trigger tri_epp_crea_producto (tri_epp_productos.sql) crea el producto
-- y le pone al EPP ese mismo id.
CREATE TABLE IF NOT EXISTS tab_epp
(
    id_epp                  DECIMAL(3,0)    NOT NULL        CHECK   (id_epp >= 1 AND id_epp <= 999),                                    -- MISMO ID DEL PRODUCTO EN tab_productos (mismo rango 1-999)
    nom_epp                 VARCHAR(100)    NOT NULL        CHECK   (LENGTH(nom_epp) >= 5 AND LENGTH(nom_epp) <= 100),                  -- NOMBRE DESCRIPTIVO DEL TIPO DE EPP (EJ: 'CASCO DIELÉCTRICO CLASE E'). Las funciones lo limitan a 60 porque se copia a tab_productos.nom_producto
    id_categoria_epp        DECIMAL(2,0)    NOT NULL,                                                                                           -- CATEGORÍA DEL EPP (tab_categoria_epp)
    valor_riesgo            DECIMAL(1,0)    NOT NULL        CHECK   (valor_riesgo >= 0 AND valor_riesgo <= 4),                          -- NIVEL DE RIESGO QUE CUBRE EL EPP (0-4)
    desc_epp                TEXT            NOT NULL        DEFAULT 'Sin descripción del EPP.',                                         -- DESCRIPCIÓN DETALLADA DEL EPP: MATERIALES, ESPECIFICACIONES TÉCNICAS, USOS RECOMENDADOS
    vida_util_m             DATE            NOT NULL,                                                                                           -- FECHA HASTA LA QUE EL EPP ES ÚTIL. Que sea futura se valida en fun_insert_epp / fun_update_epp: un CHECK con CURRENT_DATE haría fallar cualquier UPDATE de la fila cuando el EPP se vence
    cant_epp                DECIMAL(2,0)    NOT NULL        CHECK   (cant_epp >= 0 AND cant_epp <= 99) DEFAULT 0,                       -- CANTIDAD DEL EPP DISPONIBLE PARA PODER ASIGNAR.
    ind_activo              BOOLEAN         NOT NULL        DEFAULT TRUE,                                                               -- ESTADO DEL REGISTRO: TRUE = ACTIVO PARA NUEVAS ASIGNACIONES, FALSE = DESCONTINUADO
    ind_borrado             BOOLEAN         NOT NULL        DEFAULT FALSE,
    PRIMARY KEY (id_epp),
    FOREIGN KEY (id_epp)            REFERENCES tab_productos(id_producto),
    FOREIGN KEY (id_categoria_epp)  REFERENCES tab_categoria_epp(id_categoria_epp)
);


-----------------------------
-- TABLA ASIGNACIÓN DE EPP --
-----------------------------
CREATE TABLE IF NOT EXISTS tab_epp_asignacion
(
    id_asignacion       DECIMAL(4,0)    NOT NULL        CHECK (id_asignacion >= 1 AND id_asignacion <= 9999),               -- Identificador de la asignación del epp para cada empleado.
    id_epp         		DECIMAL(3,0)    NOT NULL        CHECK (id_epp >= 1 AND id_epp <= 999),                               -- Referencia al tipo de EPP asignado (ej: Casco, Gafas, Arnés)
    id_empleado         VARCHAR(10)     NOT NULL        CHECK (LENGTH(id_empleado) >= 6 AND LENGTH(id_empleado) <= 10 ),    -- Empleado que recibe el EPP
    fecha_asignacion    DATE            NOT NULL        CHECK (fecha_asignacion <= CURRENT_DATE),                           -- Fecha en que se entregó físicamente el EPP al trabajador. Debe ser menor o igual a la fecha actual (no se puede asignar en futuro)
    fecha_venci         DATE            NOT NULL        CHECK (fecha_venci > fecha_asignacion),                             -- Fecha hasta la cual el EPP asignado es válido. Debe ser posterior a fecha_asignacion y no superar tab_epp.vida_util_m (validado en la función de inserción)
    ind_estado          CHAR(1)         NOT NULL        DEFAULT 'A'    CHECK (ind_estado IN ('A', 'D', 'V', 'B')),          -- Estado del epp asignado: A=Asignado, D=Devuelto, V=Vencido, B=Baja
    obser_epp_asig      TEXT, 						                                                                        -- Observaciones generales: condición al entregar, instrucciones especiales, etc.
    ind_borrado			BOOLEAN		    NOT NULL 		DEFAULT FALSE,	
    PRIMARY KEY (id_asignacion),
    FOREIGN KEY (id_epp) 			REFERENCES tab_epp(id_epp),
    FOREIGN KEY (id_empleado) 		REFERENCES tab_empleados(id_empleado)
);

CREATE UNIQUE INDEX uq_epp_asignacion_activa
ON tab_epp_asignacion (id_epp, id_empleado)
WHERE ind_estado = 'A' AND ind_borrado = FALSE;


-----------------------------
-- TABLA INSPECCIÓN DE EPP  --
-----------------------------

CREATE TABLE IF NOT EXISTS tab_epp_inspeccion
(
    id_inspeccion_epp   DECIMAL(6,0)    NOT NULL        CHECK (id_inspeccion_epp >= 1 AND id_inspeccion_epp <= 999999),                 -- Identificador único de cada inspección realizada
    id_asignacion       DECIMAL(4,0)    NOT NULL        CHECK (id_asignacion >= 1 AND id_asignacion <= 9999),                           -- Referencia a la asignación específica que se está inspeccionando. Permite saber qué trabajador tiene el EPP y desde cuándo
    fecha_inspeccion    DATE            NOT NULL        CHECK (fecha_inspeccion <= CURRENT_DATE),                                       -- Fecha en que se realizó la inspección física del EPP. No puede ser futura (solo inspecciones pasadas o actuales)
    resultado           CHAR(1)         NOT NULL        CHECK (resultado IN ('A', 'N', 'R')),                                           -- A = APROBADO, N = NO APROBADO, R = REQUIERE MANTENIMIENTO.
    proxima_inspeccion  DATE                            CHECK (proxima_inspeccion IS NULL OR proxima_inspeccion > fecha_inspeccion),    -- Fecha sugerida para la próxima inspección (ej: 3 meses, 6 meses según riesgo)
    obser_inspeccion    TEXT, 					                                                                                        -- Detalles específicos de la inspección: qué se revisó, qué se encontró. Ej: 'Grietas en la suela del casco', 'Arnés con costuras desgastadas'
    id_empleado         VARCHAR(10)     NOT NULL        CHECK (LENGTH(id_empleado) >= 6 AND LENGTH(id_empleado) <= 10),                 -- Id del empleado que realizó la inspección (SST, supervisor, brigadista). Permite trazabilidad y rendición de cuentas
    ind_borrado		    BOOLEAN		    NOT NULL 		DEFAULT FALSE,	
    PRIMARY KEY (id_inspeccion_epp),
    FOREIGN KEY (id_asignacion) REFERENCES tab_epp_asignacion(id_asignacion),
    FOREIGN KEY (id_empleado)   REFERENCES tab_empleados(id_empleado)
);


---------------------
--TABLA DE EXAMENES--
---------------------

CREATE TABLE IF NOT EXISTS tab_examenes 
(
  id_examen             DECIMAL(4,0)                                NOT NULL        CHECK (id_examen >= 1 and id_examen <= 9999),				    -- Indicador del examen
  nom_examen            VARCHAR                                     NOT NULL        CHECK (LENGTH(nom_examen) >= 5 AND LENGTH(nom_examen) <= 100),  -- Nombre del examen a realizar
  obser_examen          TEXT,                                                                                                                       -- Observaciones del examen (qué incluye, requisitos, etc.)
  ind_borrado		    BOOLEAN				                        NOT NULL 		DEFAULT FALSE,	                                                -- Indicador de borrado lógico
  PRIMARY KEY(id_examen)
);


-----------------------------------------
--TABLA DE ENCABEZADO EXAMEN DE INGRESO--
-----------------------------------------
CREATE TABLE IF NOT EXISTS tab_enc_ex_ingreso
(
  id_empleado         VARCHAR(10)                                  NOT NULL         CHECK (LENGTH(id_empleado) >= 6 AND LENGTH(id_empleado) <= 10 ),	    -- Indicador del empleado.
  fec_examen          TIMESTAMP WITHOUT TIME ZONE                  NOT NULL         CHECK (fec_examen <= CURRENT_TIMESTAMP),                                -- Fecha en que se realizó el examen.
  ind_tipo_examen     CHAR(3)                                      NOT NULL         CHECK (ind_tipo_examen IN ('ING', 'PER', 'RET', 'POS')),                -- INGRESO, PERIODICO, RETIRO, POST-INCAPACIDAD.
  ind_aptitud         CHAR(1)                                      NOT NULL         CHECK (ind_aptitud IN ('A', 'N', 'R')),                                 -- APTO, NO APTO, APTO CON RESTRICCIONES.
  aclaraciones        VARCHAR(300)                                 NOT NULL         ,                                                                       -- Aclaraciones adicionales sobre la aptitud del empleado, especialmente si es "APTO CON RESTRICCIONES". Aquí se detallan las limitaciones específicas o recomendaciones médicas para el empleado.
  ind_restri_lab      BOOLEAN                                      NOT NULL         ,                                                                       -- Indicador de restricciones laborales
  medico_examen       TEXT                                         NOT NULL         ,                                                                       -- Nombre del médico o profesional de la salud que realizó el examen, así como su especialidad o número de licencia, si es relevante.                                                                                                                                                                                                                                                                                                                                                                               
  res_examen          VARCHAR                                      NOT NULL         ,                                                                       -- Resolucion del examen
  ind_borrado		  BOOLEAN									   NOT NULL 		DEFAULT FALSE,	
  PRIMARY KEY(id_empleado,fec_examen),
  FOREIGN KEY (id_empleado) REFERENCES tab_empleados(id_empleado)
);


-----------------------------------------
--TABLA DE DETALLE EXAMEN DE INGRESO   --
-----------------------------------------

CREATE TABLE IF NOT EXISTS tab_det_ex_ingreso
(
 id_empleado        VARCHAR(10)                                   NOT NULL,                                      -- Identificador del empleado al que se le realizó el examen de ingreso.
 fec_examen         TIMESTAMP WITHOUT TIME ZONE                   NOT NULL,                                      -- Fecha del examen de encabezado al que pertenece este detalle. Junto con id_empleado, referencia al encabezado exacto en tab_enc_ex_ingreso.
 id_examen          DECIMAL(4,0)                                  NOT NULL,                                      -- Identificador del examen.
 ruta_resultado     VARCHAR                                       NOT NULL,                                      -- Ruta o enlace al documento digital del resultado específico de este examen.
 ind_borrado		BOOLEAN										  NOT NULL 		DEFAULT FALSE,	
 PRIMARY KEY(id_empleado, fec_examen, id_examen),
 FOREIGN KEY (id_empleado, fec_examen) REFERENCES tab_enc_ex_ingreso(id_empleado, fec_examen),
 FOREIGN KEY (id_examen)               REFERENCES tab_examenes(id_examen)
);


-------------------------------
--TABLA TIPO DE INCAPACIDADES--
-------------------------------

CREATE TABLE IF NOT EXISTS tab_tipo_incapacidad
(
 id_tipo_inca           DECIMAL(4,0)                               NOT NULL     CHECK (id_tipo_inca >= 1 AND id_tipo_inca <= 9999),                      -- Identificador del tipo de incapacidad.
 nom_tipo_inca          VARCHAR(80)                                NOT NULL     CHECK (LENGTH(TRIM(nom_tipo_inca)) >= 3),                                -- Nombre del tipo (ENFERMEDAD GENERAL, ACCIDENTE DE TRABAJO, ...).
 ind_origen             CHAR(1)                                    NOT NULL     CHECK (ind_origen IN ('C', 'L')),                                        -- ORIGEN: (C) COMÚN -> EPS, (L) LABORAL -> ARL.
 clasi_tipo_incapacidad CHAR(3)                                    NOT NULL     CHECK (clasi_tipo_incapacidad IN ('IT', 'IPP', 'INV', 'LIC')),          -- (IT) INCAPACIDAD TEMPORAL, (IPP) INCAPACIDAD PERMANENTE PARCIAL, (INV) INVALIDEZ, (LIC) LICENCIA.
 desc_tipo_inca         TEXT                                       NOT NULL     DEFAULT 'SIN DESCRIPCIÓN',                                               -- Qué incluye y norma que lo rige.
 ind_borrado	        BOOLEAN									   NOT NULL     DEFAULT FALSE,
 PRIMARY KEY(id_tipo_inca),
 UNIQUE (nom_tipo_inca),
 CHECK (clasi_tipo_incapacidad <> 'LIC' OR ind_origen = 'C')                                                                                             -- Las licencias siempre son de origen común (las paga la EPS).
);

INSERT INTO tab_tipo_incapacidad (id_tipo_inca, nom_tipo_inca, ind_origen, clasi_tipo_incapacidad, desc_tipo_inca) VALUES
    (1, 'ENFERMEDAD GENERAL',                    'C', 'IT',  'ENFERMEDAD AJENA A LA ACTIVIDAD LABORAL (GRIPA, CIRUGÍA, ETC.)'),
    (2, 'ACCIDENTE COMÚN',                       'C', 'IT',  'ACCIDENTE QUE NO OCURRE POR CAUSA O CON OCASIÓN DEL TRABAJO (EN CASA, FIN DE SEMANA)'),
    (3, 'ACCIDENTE DE TRABAJO',                  'L', 'IT',  'SUCESO REPENTINO POR CAUSA O CON OCASIÓN DEL TRABAJO.'),
    (4, 'ENFERMEDAD LABORAL',                    'L', 'IT',  'CONTRAÍDA POR EXPOSICIÓN A FACTORES DE RIESGO DEL TRABAJO.');


---------------------
--TABLA DE DOCENTES--
---------------------

CREATE TABLE IF NOT EXISTS tab_docentes
(
  id_docente                VARCHAR(10)                           NOT NULL        CHECK (LENGTH(id_docente)>=6 AND LENGTH(id_docente)<=10),                             -- Identificador del docente que realiza la capacitación.
  nom_docente               VARCHAR                               NOT NULL        CHECK (LENGTH(nom_docente) >= 2 AND LENGTH(nom_docente) <= 50),                       -- Nombres del docente.
  ape_docente               VARCHAR                               NOT NULL        CHECK (LENGTH(ape_docente) >= 2 AND LENGTH(ape_docente) <= 50),                       -- Apellidos del docente.
  correo_docente            VARCHAR                               NOT NULL        CHECK (correo_docente ~* '^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$'),         -- Correo electrónico del docente.
  tel_docente               VARCHAR(15)                           NOT NULL        CHECK (LENGTH(tel_docente) >= 7 AND LENGTH(tel_docente) <= 15),                       -- Teléfono de contacto del docente.                      
  ind_extint                BOOLEAN                               NOT NULL        DEFAULT TRUE,                                                                         -- TRUE: INTERNO FALSE: EXTERNO
  ind_borrado				BOOLEAN								  NOT NULL        DEFAULT FALSE,	
  PRIMARY KEY (id_docente)
);


------------------------------------
--TABLA TIPOS DE CAPACITACIÓN     --
------------------------------------
CREATE TABLE IF NOT EXISTS tab_tipo_cap
(
    id_tipo_cap             DECIMAL(2,0)                          NOT NULL         CHECK(id_tipo_cap >= 1 AND id_tipo_cap <= 99),                  -- Identificador del tipo de capacitación.
    nom_tipo_cap            VARCHAR(60)                           NOT NULL         CHECK(LENGTH(TRIM(nom_tipo_cap)) >= 3),                         -- Nombre del tipo (INDUCCIÓN, REINDUCCIÓN, ...).
    desc_tipo_cap           TEXT                                  NOT NULL         DEFAULT 'SIN DESCRIPCIÓN',                                      -- Qué incluye y norma que lo soporta.
    ind_borrado				BOOLEAN								  NOT NULL 		   DEFAULT FALSE,
    PRIMARY KEY (id_tipo_cap),
    UNIQUE (nom_tipo_cap)
);

INSERT INTO tab_tipo_cap (id_tipo_cap, nom_tipo_cap, desc_tipo_cap) VALUES
    (1, 'INDUCCIÓN',                'AL INGRESAR A LA EMPRESA, ANTES DE INICIAR LABORES, SIN IMPORTAR LA FORMA DE VINCULACIÓN. DECRETO 1072/2015 ART. 2.2.4.6.11.'),
    (2, 'REINDUCCIÓN',              'ACTUALIZACIÓN PARA TRABAJADORES ANTIGUOS O CUANDO CAMBIAN EL CARGO, LOS PROCESOS O LOS RIESGOS. DECRETO 1072/2015 ART. 2.2.4.6.11; RES. 0312/2019.'),
    (3, 'ESPECÍFICA DEL CARGO',     'PELIGROS Y CONTROLES PROPIOS DEL PUESTO DE TRABAJO. DECRETO 1072/2015 ART. 2.2.4.6.11.'),
    (4, 'TAREAS DE ALTO RIESGO',    'TRABAJO EN ALTURAS (RES. 4272/2021), ESPACIOS CONFINADOS (RES. 0491/2020), RIESGO ELÉCTRICO, ENTRE OTRAS. REQUIEREN CERTIFICACIÓN Y REENTRENAMIENTO.'),
    (5, 'COMITÉS',                  'FORMACIÓN DE LOS INTEGRANTES DEL COPASST Y DEL COMITÉ DE CONVIVENCIA LABORAL. RES. 0312/2019.'),
    (6, 'SG-SST',                   'FORMACIÓN SOBRE EL SISTEMA DE GESTIÓN, INCLUIDO EL CURSO VIRTUAL DE 50 HORAS PARA RESPONSABLES DEL SG-SST. RES. 4927/2016.'),
    (7, 'OTRA',                     'TEMA QUE NO ENCAJA EN LOS TIPOS ANTERIORES.');


------------------------------------
--TABLA TEMAS DE CAPACITACIÓN     --
------------------------------------

CREATE TABLE IF NOT EXISTS tab_temas_cap
(
    id_tema_cap             DECIMAL(4,0)                          NOT NULL         CHECK(id_tema_cap >= 1 AND id_tema_cap <= 9999),                -- Identificador del tema de la capacitación.
    id_tipo_cap             DECIMAL(2,0)                          NOT NULL,                                                                        -- Tipo de capacitación (tab_tipo_cap).
    nom_tema                VARCHAR(120)                          NOT NULL         CHECK(LENGTH(TRIM(nom_tema)) >= 3),                             -- Nombre de la capacitación o programa de salud.
    desc_tema               TEXT                                  NOT NULL         DEFAULT 'SIN DESCRIPCIÓN',                                      -- Objetivo y contenido del tema.
    ind_programa_salud      BOOLEAN                               NOT NULL         DEFAULT FALSE,                                                  -- TRUE = el tema pertenece a un programa de salud.
    ind_obligatorio         BOOLEAN                               NOT NULL         DEFAULT TRUE,                                                   -- TRUE = lo exige la ley o el SG-SST; FALSE = opcional (bienestar, etc.).
    vigencia_meses          DECIMAL(3,0)                                           CHECK(vigencia_meses IS NULL OR (vigencia_meses >= 1 AND vigencia_meses <= 120)), -- Cada cuántos meses se debe repetir (ej: 12 para alturas). NULL = no vence.
    normativa_tema          VARCHAR(200),                                                                                                          -- Norma que lo exige (ej: RES. 4272/2021). NULL si no aplica.
    ind_borrado				BOOLEAN								  NOT NULL 		   DEFAULT FALSE,
    PRIMARY KEY (id_tema_cap),
    UNIQUE (nom_tema),
    FOREIGN KEY (id_tipo_cap) REFERENCES tab_tipo_cap(id_tipo_cap)
);


---------------------------
--TABLA DE CAPACITACIONES--
---------------------------

CREATE TABLE IF NOT EXISTS tab_capacitaciones
(
 id_capacitacion          DECIMAL(4,0)                          NOT NULL    CHECK (id_capacitacion >=1 AND id_capacitacion <= 9999),    -- Identificador de la capacitación
 id_docente               VARCHAR(10)                           NOT NULL    CHECK (LENGTH(id_docente)>=6 AND LENGTH(id_docente)<=10),   -- Identificador del docente que imparte la capacitación.
 id_tema_cap              DECIMAL(4,0)                          NOT NULL    CHECK (id_tema_cap >= 1 AND id_tema_cap <= 9999),           -- Identificador del tema de capacitación.
 id_area                  DECIMAL(5,0),                                                                                                 -- Área a la que va dirigida la capacitación. NULL = toda la empresa
 fec_capacita             TIMESTAMP WITHOUT TIME ZONE           NOT NULL,                                                               -- Fecha en la que se realizará la capacitación. Que sea futura se valida al insertar: un CHECK con CURRENT_TIMESTAMP bloquea cualquier UPDATE cuando la fecha ya pasó.
 val_durac_capaci         DECIMAL(4,1)                          NOT NULL    CHECK (val_durac_capaci > 0),                               -- Duración de la capacitación en horas, admite medias horas (ej: 1.5, 2, 8).
 mod_capaci               CHAR(1)                               NOT NULL    CHECK (mod_capaci IN ('P', 'V', 'M')),                      -- PRESENCIAL, VIRTUAL, MIXTA
 enlace_capaci            VARCHAR(500)                                      CHECK (enlace_capaci IS NULL OR enlace_capaci ~* '^https?://[^[:space:]]+$'), -- Enlace de la reunión (Meet, Teams, Zoom...). NULL si no aplica.
 obser_capaci             TEXT                                  NOT NULL    DEFAULT 'SIN OBSERVACIONES',                                -- Observaciones u objetivo de la capacitación.
 ind_borrado			  BOOLEAN								NOT NULL    DEFAULT FALSE,
PRIMARY KEY(id_capacitacion),
FOREIGN KEY (id_docente) REFERENCES tab_docentes(id_docente),
FOREIGN KEY (id_tema_cap) REFERENCES tab_temas_cap(id_tema_cap),
FOREIGN KEY (id_area) REFERENCES tab_areas(id_area)
);


------------------------------------------
--TABLA DE SOLICITUDES DE CAPACITACIÓN  --
------------------------------------------
-- La hace el encargado de área (tab_areas.id_responsable). 
 
CREATE TABLE IF NOT EXISTS tab_solicitar_cap
(
 id_solicitud_cap         DECIMAL(4,0)                          NOT NULL    CHECK (id_solicitud_cap >= 1 AND id_solicitud_cap <= 9999),  -- Identificador de la solicitud.
 id_area                  DECIMAL(5,0)                          NOT NULL,                                                                -- Área que solicita (la del encargado que la hace).
 id_usuario               VARCHAR                               NOT NULL    CHECK (LENGTH(id_usuario) >= 5),                             -- Usuario que solicita (responsable del área).
 id_tema_cap              DECIMAL(4,0)                          NOT NULL    CHECK (id_tema_cap >= 1 AND id_tema_cap <= 9999),            -- Tema que se necesita.
 motivo_solicitud         TEXT                                  NOT NULL    CHECK (LENGTH(TRIM(motivo_solicitud)) >= 10),                -- Por qué se necesita (ej: personal nuevo, accidente, cambio de proceso).
 fec_sugerida             DATE,                                                                                                          -- Para cuándo se necesita. NULL = sin fecha. Que sea futura se valida al insertar (igual que fec_capacita).
 fec_solicitud            DATE                                  NOT NULL    DEFAULT CURRENT_DATE,                                        -- Fecha en que se hizo la solicitud.
 estado_solicitud         CHAR(1)                               NOT NULL    DEFAULT 'P'     CHECK (estado_solicitud IN ('P', 'A', 'R')), -- (P) PENDIENTE (A) APROBADA (R) RECHAZADA
 motivo_rechazo           TEXT,                                                                                                          -- Por qué SST la rechazó. NULL si no está rechazada.
 id_capacitacion          DECIMAL(4,0)                                      CHECK (id_capacitacion IS NULL OR (id_capacitacion >= 1 AND id_capacitacion <= 9999)), -- Capacitación que se programó al aprobarla. NULL mientras no se programe.
 ind_borrado			  BOOLEAN								NOT NULL    DEFAULT FALSE,
PRIMARY KEY (id_solicitud_cap),
FOREIGN KEY (id_area)         REFERENCES tab_areas(id_area),
FOREIGN KEY (id_usuario)      REFERENCES tab_usuarios(id_usuario),
FOREIGN KEY (id_tema_cap)     REFERENCES tab_temas_cap(id_tema_cap),
FOREIGN KEY (id_capacitacion) REFERENCES tab_capacitaciones(id_capacitacion)
);


---------------------------------------------------
--TABLA DE EMPLEADOS DE LA SOLICITUD DE CAPACITACIÓN--
---------------------------------------------------
 
CREATE TABLE IF NOT EXISTS tab_solicitar_cap_emp
(
    id_solicitud_cap        DECIMAL(4,0)                          NOT NULL      CHECK (id_solicitud_cap >= 1 AND id_solicitud_cap <= 9999),     -- IDENTIFICADOR DE LA SOLICITUD
    id_empleado             VARCHAR(10)                           NOT NULL      CHECK (LENGTH(id_empleado) >= 6 AND LENGTH(id_empleado) <= 10), -- EMPLEADO QUE ASISTIRÍA
    ind_borrado				BOOLEAN								  NOT NULL 		DEFAULT FALSE,
    PRIMARY KEY (id_solicitud_cap, id_empleado),
    FOREIGN KEY (id_solicitud_cap)  REFERENCES tab_solicitar_cap(id_solicitud_cap),
    FOREIGN KEY (id_empleado)       REFERENCES tab_empleados(id_empleado)
); 


-------------------------------------
--TABLA DE EMPLEADOS QUE ASISTIRÁN --
-------------------------------------

CREATE TABLE IF NOT EXISTS tab_convocados_cap
(
    id_capacitacion         DECIMAL(4,0)                          NOT NULL      CHECK (id_capacitacion >= 1 AND id_capacitacion <= 9999),       -- IDENTIFICADOR DE LA CAPACITACIÓN
    id_empleado             VARCHAR(10)                           NOT NULL      CHECK (LENGTH(id_empleado) >= 6 AND LENGTH(id_empleado) <= 10), -- EMPLEADO QUE DEBE ASISTIR
    fec_convocatoria        DATE                                  NOT NULL      DEFAULT CURRENT_DATE,                                           -- FECHA EN QUE SE LE CONVOCÓ
    ind_borrado				BOOLEAN								  NOT NULL 		DEFAULT FALSE,
    PRIMARY KEY (id_capacitacion, id_empleado),
    FOREIGN KEY (id_capacitacion)   REFERENCES tab_capacitaciones(id_capacitacion),
    FOREIGN KEY (id_empleado)       REFERENCES tab_empleados(id_empleado)
);


-----------------------------------
--TABLA ASISTENCIA A CAPACITACIÓN--
-----------------------------------

CREATE TABLE IF NOT EXISTS tab_asis_cap
(
    id_capacitacion         DECIMAL(4,0)                          NOT NULL      CHECK (id_capacitacion >=1 AND id_capacitacion <= 9999),    -- IDENTIFICADOR DE LA CAPACITACIÓN
    id_empleado             VARCHAR(10)                           NOT NULL      CHECK (LENGTH(id_empleado)>=6 AND LENGTH(id_empleado)<=10), -- IDENTIFICADOR DEL EMPLEADO
    fec_asis                DATE                                  NOT NULL      CHECK (fec_asis <= CURRENT_DATE),                           -- FECHA DE ASISTENCIA A LA CAPACITACIÓN
    ind_asistio             BOOLEAN                               NOT NULL,                                                                 -- Indicador de la asistencia (programas de salud y capacitaciones): TRUE = ASISTIÓ, FALSE = NO ASISTIÓ
    ind_borrado				BOOLEAN								  NOT NULL 		DEFAULT FALSE,
    PRIMARY KEY (id_capacitacion, id_empleado),
    FOREIGN KEY (id_capacitacion, id_empleado) REFERENCES tab_convocados_cap(id_capacitacion, id_empleado)                                  -- Solo se registra asistencia de quien fue convocado
);


---------------------
--TABLA  DE BRIGADA--
---------------------
CREATE TABLE IF NOT EXISTS tab_brigada
(
  id_brigada               DECIMAL(4,0)                          NOT NULL       CHECK (id_brigada >=1 AND id_brigada <= 9999),      -- Identificador de la brigada. 
  nom_brigada              VARCHAR                               NOT NULL       CHECK (LENGTH(nom_brigada) >= 5),                   -- Nombre de la brigada de emergencia.
  tipo_brigada             CHAR(1)                               NOT NULL       DEFAULT 'M'  CHECK (tipo_brigada IN ('P', 'I', 'E', 'M')),   -- P: PRIMEROS AUXILIOS, I: CONTRA INCENDIOS, E: EVACUACIÓN Y RESCATE, M: INTEGRAL (MIXTA)
  id_area                  DECIMAL(5,0),                                                                                        -- Área / centro de trabajo que cubre. NULL = toda la empresa
  turno_brigada            CHAR(1)                               NOT NULL       DEFAULT 'T'  CHECK (turno_brigada IN ('D', 'N', 'T')),      -- D: DIURNO, N: NOCTURNO, T: TODOS LOS TURNOS
  fec_conformacion         DATE                                  NOT NULL       DEFAULT CURRENT_DATE  CHECK (fec_conformacion <= CURRENT_DATE), -- Fecha del acta de conformación
  id_coordinador           VARCHAR(10),                                                                                         -- Empleado jefe / coordinador de la brigada
  ind_borrado			   BOOLEAN								 NOT NULL 		DEFAULT FALSE,	                                    -- Indicador de borrado lógico para la brigada
  PRIMARY KEY(id_brigada),
  FOREIGN KEY (id_area)         REFERENCES tab_areas(id_area),
  FOREIGN KEY (id_coordinador)  REFERENCES tab_empleados(id_empleado)
);


-------------------------
--TABLA  DE BRIGADISTAS--
-------------------------
CREATE TABLE IF NOT EXISTS tab_brigadistas
(
  id_brigadista             VARCHAR(10)                          NOT NULL         CHECK (LENGTH(id_brigadista) >= 6 AND LENGTH(id_brigadista) <= 10 ),      -- Identificador de los brigadistas (miembros)
  id_brigada                DECIMAL(4,0)                         NOT NULL          CHECK (id_brigada >=1 AND id_brigada <= 9999),                           -- Identificador de la brigada    
  id_empleado               VARCHAR(10)                          NOT NULL         CHECK (id_empleado ~ '^[1-9][0-9]{7,9}$'),                                -- Identificador del empleado que hace parte de los brigadistas.      
  rol_brigadista            CHAR(1)                              NOT NULL         CHECK (rol_brigadista IN ('L','E')),                                      -- LIDERAZGO Y OPERACIÓN, EQUIPOS OPERATIVOS ESPECIALIZADOS.
  fec_ingreso_bri           DATE                                 NOT NULL         DEFAULT CURRENT_DATE  CHECK (fec_ingreso_bri <= CURRENT_DATE),            -- Fecha en que entró a la brigada
  fec_retiro_bri            DATE,                                                                                                                         -- Fecha en que salió de la brigada (NULL = activo)
  ind_voluntario            BOOLEAN                              NOT NULL         DEFAULT TRUE,                                                             -- TRUE: aceptó voluntariamente ser brigadista
  fec_aptitud_medica        DATE,                                                                                                                         -- Último concepto médico de aptitud (buena práctica)
  ind_borrado			    BOOLEAN							     NOT NULL 		  DEFAULT FALSE,
  PRIMARY KEY (id_brigadista),
  CONSTRAINT chk_bri_fec_retiro CHECK (fec_retiro_bri IS NULL OR fec_retiro_bri >= fec_ingreso_bri),
  FOREIGN KEY (id_brigada)      REFERENCES tab_brigada(id_brigada),
  FOREIGN KEY (id_empleado)     REFERENCES tab_empleados(id_empleado)
);

-- Un empleado solo puede tener un registro activo de brigadista.
CREATE UNIQUE INDEX uq_brigadista_empleado_activo
ON tab_brigadistas (id_empleado)
WHERE ind_borrado = FALSE;


------------------------
--TABLA  DE EMERGENCIA--
------------------------
CREATE TABLE IF NOT EXISTS tab_emergencia
(
  id_emergencia        DECIMAL(4,0)                          NOT NULL       CHECK (id_emergencia >=1 AND id_emergencia <=9999),      -- Identificador de la emergencia.
  fecha_emer           TIMESTAMP WITHOUT TIME ZONE           NOT NULL       CHECK (fecha_emer <= CURRENT_TIMESTAMP),                 -- Fecha y hora en que ocurrió la emergencia.
  tipo_emer            CHAR(1)                               NOT NULL       CHECK (tipo_emer IN ('I', 'S', 'M', 'O')),               -- INCENDIO, SISMO, MÉDICA, OTRO
  desc_emer            TEXT                                  NOT NULL       DEFAULT 'Sin descripción de emergencia.',                -- Descripción detallada de la emergencia, incluyendo qué ocurrió, cómo se manejó la situación, y cualquier lección aprendida o medida correctiva implementada posteriormente.
  id_brigada           DECIMAL(4,0),                                                                                                  -- Brigada que respondió (NULL = no registrada)
  ind_borrado		   BOOLEAN								 NOT NULL 		DEFAULT FALSE,
  PRIMARY KEY(id_emergencia),
  FOREIGN KEY (id_brigada) REFERENCES tab_brigada(id_brigada)
);


------------------------------------
--TABLA  DE DOTACIÓN DE BRIGADA   --
--(equipo de emergencia, no EPP)  --
------------------------------------
CREATE TABLE IF NOT EXISTS tab_dotacion_brigada
(
  id_dotacion          DECIMAL(6,0)                          NOT NULL       CHECK (id_dotacion >= 1),                                      -- Identificador del elemento
  id_brigada           DECIMAL(4,0)                          NOT NULL,                                                                     -- Brigada a la que pertenece
  nom_elemento         VARCHAR(100)                          NOT NULL       CHECK (LENGTH(TRIM(nom_elemento)) >= 3),                       -- Camilla, botiquín, extintor, chaleco, radio, DEA...
  cant_elemento        DECIMAL(4,0)                          NOT NULL       CHECK (cant_elemento > 0),                                     -- Cantidad
  estado_elemento      CHAR(1)                               NOT NULL       DEFAULT 'B'  CHECK (estado_elemento IN ('B', 'R', 'M')),       -- B: BUENO, R: REGULAR, M: MALO / FUERA DE SERVICIO
  ubi_elemento         VARCHAR(100)                          NOT NULL       CHECK (LENGTH(TRIM(ubi_elemento)) >= 3),                       -- Dónde está guardado
  fec_ult_inspeccion   DATE                                                 CHECK (fec_ult_inspeccion <= CURRENT_DATE),                    -- Última inspección
  fec_prox_inspeccion  DATE,                                                                                                               -- Próxima inspección programada
  ind_borrado          BOOLEAN                               NOT NULL       DEFAULT FALSE,
  PRIMARY KEY (id_dotacion),
  CONSTRAINT chk_dot_prox_inspeccion CHECK (fec_prox_inspeccion IS NULL OR fec_ult_inspeccion IS NULL OR fec_prox_inspeccion > fec_ult_inspeccion),
  FOREIGN KEY (id_brigada) REFERENCES tab_brigada(id_brigada)
);


-----------------------
--TABLA  DE SIMULACRO--
-----------------------
CREATE TABLE IF NOT EXISTS tab_simulacro
(
  id_simulacro         DECIMAL(4,0)                          NOT NULL       CHECK (id_simulacro >= 1 AND id_simulacro <= 9999),            -- Identificador del simulacro
  fec_simulacro        TIMESTAMP WITHOUT TIME ZONE           NOT NULL       CHECK (fec_simulacro <= CURRENT_TIMESTAMP),                    -- Fecha y hora en que se hizo
  tipo_simulacro       CHAR(1)                               NOT NULL       CHECK (tipo_simulacro IN ('I', 'S', 'M', 'E', 'O')),           -- INCENDIO, SISMO, MÉDICA, EVACUACIÓN, OTRO
  id_area              DECIMAL(5,0),                                                                                                       -- Área / centro de trabajo. NULL = toda la empresa
  turno_simulacro      CHAR(1)                               NOT NULL       DEFAULT 'D'  CHECK (turno_simulacro IN ('D', 'N')),            -- D: DIURNO, N: NOCTURNO
  num_participantes    DECIMAL(5,0)                          NOT NULL       CHECK (num_participantes >= 0),                                -- Trabajadores que participaron
  tiempo_evac_min      DECIMAL(5,1)                                         CHECK (tiempo_evac_min IS NULL OR tiempo_evac_min > 0),        -- Tiempo total de evacuación en minutos
  hallazgos_sim        TEXT                                  NOT NULL       DEFAULT 'Sin hallazgos registrados.',                          -- Qué falló / qué funcionó
  plan_mejora_sim      TEXT,                                                                                                               -- Acciones de mejora derivadas
  ind_borrado          BOOLEAN                               NOT NULL       DEFAULT FALSE,
  PRIMARY KEY (id_simulacro),
  FOREIGN KEY (id_area) REFERENCES tab_areas(id_area)
);


----------------------------------------------
--TABLA  DE PARTICIPACIÓN EN SIMULACROS     --
----------------------------------------------
CREATE TABLE IF NOT EXISTS tab_simulacro_brigadista
(
  id_simulacro         DECIMAL(4,0)                          NOT NULL,                                                                     -- Simulacro
  id_brigadista        VARCHAR(10)                           NOT NULL,                                                                     -- Brigadista convocado
  ind_asistio          BOOLEAN                               NOT NULL,                                                                     -- TRUE = participó
  obs_desempeno        TEXT,                                                                                                               -- Observación del desempeño
  ind_borrado          BOOLEAN                               NOT NULL       DEFAULT FALSE,
  PRIMARY KEY (id_simulacro, id_brigadista),
  FOREIGN KEY (id_simulacro)  REFERENCES tab_simulacro(id_simulacro),
  FOREIGN KEY (id_brigadista) REFERENCES tab_brigadistas(id_brigadista)
);


-----------------
--TABLA COPASST--
-----------------

CREATE TABLE IF NOT EXISTS tab_copasst
(
    id_copasst             DECIMAL(4,0)             NOT NULL                        CHECK(id_copasst >= 0),                     -- IDENTIFICADOR DEL COPASST
    tipo_comite            VARCHAR(7)               NOT NULL    DEFAULT 'COPASST'   CHECK(tipo_comite IN ('COPASST','VIGIA')),  -- COPASST (10 O MÁS TRABAJADORES) O VIGÍA SST (MENOS DE 10), DECRETO 1295/1994 ART. 35
    num_trabajadores       DECIMAL(6,0)             NOT NULL                        CHECK(num_trabajadores > 0),                -- NÚMERO DE TRABAJADORES AL CONFORMAR EL COMITÉ (DEFINE CUÁNTOS MIEMBROS EXIGE LA RES. 2013/1986 ART. 2)
    fec_convocatoria       DATE                                                     CHECK(fec_convocatoria <= CURRENT_DATE),    -- FECHA DE LA CONVOCATORIA A ELECCIONES DE LOS REPRESENTANTES DE LOS TRABAJADORES
    fec_eleccion           DATE                     NOT NULL                        CHECK(fec_eleccion <= CURRENT_DATE),        -- FECHA DE LA VOTACIÓN DE LOS REPRESENTANTES DE LOS TRABAJADORES
    num_act_eleccion       DECIMAL(4,0)             NOT NULL                        CHECK(num_act_eleccion >= 0),               -- NÚMERO DEL ACTA DE ESCRUTINIO / VOTACIÓN
    periodo_inicio         DATE                     NOT NULL                        CHECK(periodo_inicio <= CURRENT_DATE),      -- FECHA DE INICIO DEL COPASST
    periodo_fin            DATE                     NOT NULL,                                                                   -- FECHA DE FIN DEL COPASST (PUEDE SER FUTURA: EL PERIODO ES DE 2 AÑOS)
    num_act_consti         DECIMAL(4,0)                                             CHECK(num_act_consti >= 0),                 -- NUMERO ACTA DE CONSTITUCION DEL COPASST
    ind_borrado			   BOOLEAN					NOT NULL 						DEFAULT FALSE,
    PRIMARY KEY (id_copasst),
    CHECK(periodo_fin > periodo_inicio AND periodo_fin <= periodo_inicio + INTERVAL '2 years'),                                 -- PERIODO MÁXIMO DE 2 AÑOS (DECRETO 1295/1994 ART. 63)
    CHECK(fec_eleccion <= periodo_inicio),
    CHECK(fec_convocatoria <= fec_eleccion)
);


-------------------------
--TABLA MIEMBRO COPASST--
-------------------------

CREATE TABLE IF NOT EXISTS tab_miem_copasst
(
    id_copasst              DECIMAL(4,0)            NOT NULL                         CHECK(id_copasst >= 0),                    -- IDENTIFICADOR DEL COPASST
    id_empleado             VARCHAR(10)             NOT NULL                         CHECK(id_empleado ~ '^[1-9][0-9]{7,9}$'),  -- Identificador del empleado que es miembro del COPASST
    tipo_repre              VARCHAR(10)             NOT NULL                         CHECK(tipo_repre IN ('EMPLEADOR','TRABAJADOR')),            -- A QUIÉN REPRESENTA EN EL COMITÉ PARITARIO
    ind_principal           BOOLEAN                 NOT NULL,                                                                   -- TRUE = PRINCIPAL, FALSE = SUPLENTE
    rol_comite              VARCHAR(10)             NOT NULL    DEFAULT 'MIEMBRO'    CHECK(rol_comite IN ('PRESIDENTE','SECRETARIO','MIEMBRO')),  -- ROL DENTRO DEL COMITÉ (RES. 2013/1986 ART. 9)
    id_principal            VARCHAR(10),                                                                                        -- SI ES SUPLENTE: EMPLEADO PRINCIPAL AL QUE SUPLE
    fec_ingreso             DATE                    NOT NULL                         CHECK(fec_ingreso <= CURRENT_DATE),        -- FECHA EN QUE ENTRA AL COMITÉ
    fec_retiro              DATE,                                                                                               -- FECHA EN QUE SALE DEL COMITÉ (NULL = ACTIVO)
    ind_borrado				BOOLEAN				    NOT NULL 						 DEFAULT FALSE,
    PRIMARY KEY (id_copasst,id_empleado),
    FOREIGN KEY (id_copasst) REFERENCES tab_copasst(id_copasst),
    FOREIGN KEY (id_empleado) REFERENCES tab_empleados(id_empleado),
    FOREIGN KEY (id_copasst,id_principal) REFERENCES tab_miem_copasst(id_copasst,id_empleado),
    CHECK(fec_retiro >= fec_ingreso)
);


-------------------------
--TABLA REUNIÓN COPASST--
-------------------------
CREATE TABLE IF NOT EXISTS tab_reu_copasst
(
    id_reunion              DECIMAL(4,0)                        NOT NULL                           CHECK(id_reunion >= 0),          -- IDENTIFICADOR DE LA REUNIÓN DEL COPASST
    id_copasst              DECIMAL(4,0)                        NOT NULL                           CHECK(id_copasst >= 0),          -- IDENTIFICADOR DEL COPASST AL QUE PERTENECE LA REUNIÓN
    fec_reu                 TIMESTAMP WITHOUT TIME ZONE         NOT NULL                           CHECK(fec_reu <= CURRENT_TIMESTAMP),  -- FECHA Y HORA DE INICIO DE LA REUNIÓN DEL COPASST
    hora_fin                TIME                                NOT NULL,                                                           -- HORA EN QUE TERMINÓ LA REUNIÓN
    tipo_reu                VARCHAR(15)                         NOT NULL                           DEFAULT 'ORDINARIA',             -- ORDINARIA: AL MENOS UNA AL MES | EXTRAORDINARIA: POR ACCIDENTE GRAVE O RIESGO INMINENTE (RES. 2013/1986 ART. 7)
    lugar_reu               VARCHAR(100)                        NOT NULL,                                                           -- LUGAR DONDE SE REALIZÓ LA REUNIÓN
    motivo_extra            TEXT,                                                                                                   -- MOTIVO DE LA REUNIÓN EXTRAORDINARIA (ACCIDENTE GRAVE O RIESGO INMINENTE). NULL SI ES ORDINARIA
    temas_reu               TEXT                                NOT NULL,                                                           -- TEMAS TRATADOS EN LA REUNIÓN DEL COPASST: DESCRIPCIÓN DETALLADA DE LOS PUNTOS ABORDADOS, DECISIONES TOMADAS, Y ACCIONES A SEGUIR. ESTO PERMITE LLEVAR UN REGISTRO CLARO DE LO DISCUTIDO EN CADA REUNIÓN Y FACILITA EL SEGUIMIENTO DE LAS TAREAS ASIGNADAS.
    acuer_reu_copasst       TEXT                                NOT NULL,                                                           -- ACUERDOS TOMADOS EN LA REUNIÓN DEL COPASST: DESCRIPCIÓN DE LOS ACUERDOS ESPECÍFICOS A LOS QUE SE LLEGÓ DURANTE LA REUNIÓN, INCLUYENDO QUIÉN ES RESPONSABLE DE CADA ACUERDO Y LOS PLAZOS PARA SU CUMPLIMIENTO. ESTO AYUDA A GARANTIZAR QUE LOS ACUERDOS SEAN CLAROS Y SE PUEDAN SEGUIR EFECTIVAMENTE.
    num_act_reu             DECIMAL(4,0)                        NOT NULL,                                                           -- NÚMERO DE ACTA DE LA REUNIÓN DEL COPASST, PARA REFERENCIA Y ARCHIVO. NO SE REPITE DENTRO DEL MISMO COMITÉ (SE VALIDA EN fun_insert_reu_copasst)
    ind_borrado				BOOLEAN								NOT NULL 		                    DEFAULT FALSE,
    PRIMARY KEY (id_reunion),
    FOREIGN KEY (id_copasst) REFERENCES tab_copasst(id_copasst),
    CONSTRAINT chk_reu_tipo CHECK(tipo_reu IN ('ORDINARIA', 'EXTRAORDINARIA')),
    CONSTRAINT chk_reu_hora_fin CHECK(hora_fin > fec_reu::TIME),
    CONSTRAINT chk_reu_motivo_extra CHECK(tipo_reu = 'ORDINARIA' OR NULLIF(TRIM(motivo_extra), '') IS NOT NULL)
);


----------------------------
--TABLA ASISTENCIA COPASST--
----------------------------
CREATE TABLE IF NOT EXISTS tab_asist_copasst
(
  id_asistencia           DECIMAL(5,0)                          NOT NULL        CHECK (id_asistencia >=1 AND id_asistencia <= 99999),       -- Identificador único de la asistencia al copasst
  id_reunion              DECIMAL(4,0)                          NOT NULL        CHECK (id_reunion >= 1 AND id_reunion <= 9999),             -- Identificador de la reunión del copasst a la que se asistió 
  id_copasst              DECIMAL(4,0)                          NOT NULL        CHECK(id_copasst >= 0),          							-- IDENTIFICADOR DEL COPASST AL QUE PERTENECE LA REUNIÓN	
  id_empleado             VARCHAR(10)                           NOT NULL        CHECK (id_empleado ~ '^[1-9][0-9]{7,9}$'),   				-- Identificador del miembro del copasst que asistió a la reunión, Referencia a la tabla de miembros del copasst para saber quién asistió a cada reunión.
  ind_asistio             BOOLEAN                               NOT NULL,                                                                   -- Indicador de asistencia a la reunión del copasst: TRUE = ASISTIÓ, FALSE = NO ASISTIÓ
  ind_borrado			  BOOLEAN								NOT NULL 		DEFAULT FALSE,	
  PRIMARY KEY(id_asistencia),
  FOREIGN KEY (id_reunion) REFERENCES tab_reu_copasst(id_reunion),
  FOREIGN KEY (id_copasst,id_empleado) REFERENCES tab_miem_copasst(id_copasst,id_empleado)
);


---------------------------
--TABLA DE AUDITORIAS SST--
---------------------------
CREATE TABLE IF NOT EXISTS tab_auditorias_sst
( 
  id_auditorias         DECIMAL(4,0)                          NOT NULL          CHECK (id_auditorias >=1 AND id_auditorias <= 9999),            -- Identificador de la auditoría de SST realizada.
  id_empleado           VARCHAR(10)                           NOT NULL          CHECK (LENGTH(id_empleado)>=6 AND LENGTH(id_empleado)<=10),     -- Identificador del empleado que realiza la auditoría de SST, Referencia a la tabla de empleados para saber quién realizó cada auditoría.
  id_area               DECIMAL(15,0)                         NOT NULL          ,                                                               -- Identificador del área a la que pertenece la auditoría de SST.
  fecha_audi            TIMESTAMP WITHOUT TIME ZONE           NOT NULL          ,                                                               -- Fecha en que se realizó la auditoría de SST.
  val_hallazgos         BOOLEAN                               NOT NULL          ,                                                               -- Hallazgos encontrados durante la auditoría de SST TRUE = HAY FALSE = NO HAY.
  acciones_correc       TEXT                                  NOT NULL          ,                                                               -- Acciones correctivas implementadas tras la auditoría de SST.
  ind_conformidad       BOOLEAN                               NOT NULL          ,                                                               -- Indicador de conformidad en la auditoría de SST: TRUE = CONFORME, FALSE = NO CONFORME.
  ind_borrado			BOOLEAN								  NOT NULL 		    DEFAULT FALSE,	
  PRIMARY KEY(id_auditorias),
  FOREIGN KEY (id_empleado) 	REFERENCES tab_empleados(id_empleado),
  FOREIGN KEY (id_area) 		REFERENCES tab_areas(id_area)
);


--------------------
--TABLA ACCIDENTES--
--------------------
CREATE TABLE IF NOT EXISTS tab_accidentes
(
	 id_accidente     	DECIMAL(6,0)                           NOT NULL         CHECK (id_accidente >= 1),                                     -- Identificador único del accidente.
	 id_empleado      	VARCHAR(10)                            NOT NULL,                                                                       -- Identificador del empleado involucrado en el accidente.
	 id_tipo_acc      	DECIMAL(4,0)                           NOT NULL,                                                                       -- Identificador del tipo de accidente.
	 id_area          	DECIMAL(5,0)                           NOT NULL,                                                                       -- Área donde ocurrió el accidente.
	 ind_gravedad     	CHAR(1)                                NOT NULL         CHECK (ind_gravedad IN ('L','G','M')),                         -- GRAVEDAD DEL ACCIDENTE: (L) LEVE (G) GRAVE (M) MORTAL
	 fec_acc          	TIMESTAMP WITHOUT TIME ZONE            NOT NULL         CHECK (fec_acc <= CURRENT_TIMESTAMP),                          -- FECHA Y HORA EN QUE OCURRIÓ EL ACCIDENTE
	 lugar_acc        	VARCHAR(150)                           NOT NULL,                                                                       -- Lugar exacto donde ocurrió el accidente.
	 causa_acc        	VARCHAR(500)                           NOT NULL,                                                                       -- Causa del accidente.
	 id_parte_cuerpo  	DECIMAL(3,0)                           NOT NULL,                                                                       -- Parte del cuerpo afectada (tab_partes_cuerpo).
	 id_tipo_lesion   	DECIMAL(3,0)                           NOT NULL,                                                                       -- Tipo de lesión (tab_tipo_lesion).
	 ind_en_jornada   	BOOLEAN                                NOT NULL         DEFAULT TRUE,                                                  -- TRUE = OCURRIÓ DENTRO DE LA JORNADA LABORAL, FALSE = FUERA DE ELLA
	 estado_acc       	CHAR(1)                                NOT NULL         DEFAULT 'R'        CHECK (estado_acc IN ('R','A','I','C')),    -- ESTADO DEL CASO: (R) REGISTRADO EN EL ERP (A) REPORTADO A LA ARL (I) EN INVESTIGACIÓN (C) CERRADO
	 obser_acc        	TEXT                                   NOT NULL         DEFAULT 'SIN OBSERVACIONES',                                   -- OBSERVACIONES DEL ACCIDENTE
	 ind_borrado	  	BOOLEAN								   NOT NULL 		DEFAULT FALSE,
 
 PRIMARY KEY(id_accidente),
 FOREIGN KEY (id_empleado) REFERENCES tab_empleados(id_empleado),
 FOREIGN KEY (id_tipo_acc) REFERENCES tab_tipo_acc(id_tipo_acc),
 FOREIGN KEY (id_area)     REFERENCES tab_areas(id_area),
 FOREIGN KEY (id_parte_cuerpo) REFERENCES tab_partes_cuerpo(id_parte_cuerpo),
 FOREIGN KEY (id_tipo_lesion)  REFERENCES tab_tipo_lesion(id_tipo_lesion)
);


---------------------------
-- TABLA DE INCAPACIDADES--
---------------------------

CREATE TABLE IF NOT EXISTS tab_incapacidades
(
 id_incapacidad   DECIMAL(6,0)                                   NOT NULL       CHECK (id_incapacidad >= 1),                                    -- Identificador de la incapacidad.
 id_empleado      VARCHAR(10)                                    NOT NULL       CHECK (LENGTH(id_empleado)>=6 AND LENGTH(id_empleado)<=10),     -- Identificador del empleado.
 id_tipo_inca     DECIMAL(4,0)                                   NOT NULL       CHECK (id_tipo_inca >=1 AND id_tipo_inca <= 9999),              -- Identificador del tipo de incapacidad.
 id_entidad       VARCHAR(10)                                    NOT NULL,                                                                      -- Entidad que la reconoce (EPS si es común, ARL si es laboral).
 id_accidente     DECIMAL(6,0)                                   NULL,                                                                          -- Accidente que la originó. Obligatorio si el tipo es de origen laboral; NULL si es común.
 num_certificado  VARCHAR(30)                                    NOT NULL       CHECK (LENGTH(TRIM(num_certificado)) >= 3),                     -- Número del certificado de incapacidad que expide la EPS o la ARL.
 fecha_inicio     DATE                                           NOT NULL       CHECK (fecha_inicio <= CURRENT_DATE),                           -- Fecha de inicio de la incapacidad.
 dias_incap       DECIMAL(3,0)                                   NOT NULL       CHECK (dias_incap>0 AND dias_incap<=999),                        -- Días de incapacidad, con los que se va a calcular la fecha final de la incapacidad.,
 fecha_fin        DATE                                           NOT NULL       CHECK (fecha_fin >= fecha_inicio),                              -- Fecha final de la incapacidad.
 ruta_soporte     VARCHAR(500)                                   NULL,                                                                          -- Ruta web del certificado escaneado.
 fec_registro     DATE                                           NOT NULL       DEFAULT CURRENT_DATE,                                           -- Fecha en que se registró en el ERP.
 obser_inca       TEXT                                           NOT NULL       DEFAULT 'SIN OBSERVACIONES',                                    -- OBSERVACIONES DE LA INCAPACIDAD
 ind_borrado	  BOOLEAN										 NOT NULL       DEFAULT FALSE,

PRIMARY KEY(id_incapacidad),                                                                                                          -- Un mismo certificado no se registra dos veces.
FOREIGN KEY (id_empleado)   REFERENCES tab_empleados(id_empleado),
FOREIGN KEY (id_tipo_inca)  REFERENCES tab_tipo_incapacidad(id_tipo_inca),
FOREIGN KEY (id_entidad)    REFERENCES tab_entidades(id_entidad),
FOREIGN KEY (id_accidente)  REFERENCES tab_accidentes(id_accidente)
);


----------------------------------------
--TABLA REPORTES DE ACCIDENTES A LA ARL--
----------------------------------------
-- El FURAT que se envia a la ARL: uno solo por accidente (UNIQUE). Las
-- correcciones van en tab_correcciones_acc. La ARL se guarda como copia del
-- momento: si el empleado cambia de ARL despues, el reporte sigue diciendo a
-- cual se envio. Solo se inserta con fun_insert_reportes_acc, que tambien
-- llena tab_accidentes.fec_reporte_arl.
CREATE TABLE IF NOT EXISTS tab_reportes_acc
(
	 id_reporte       	DECIMAL(6,0)                           NOT NULL         CHECK (id_reporte >= 1),                                       -- Identificador único del reporte.
	 id_accidente     	DECIMAL(6,0)                           NOT NULL,                                                                       -- Accidente reportado.
	 id_entidad       	VARCHAR(10)                            NOT NULL,                                                                       -- ARL a la que se envió (tab_entidades con ind_arl = TRUE).
	 fec_reporte      	DATE                                   NOT NULL         DEFAULT CURRENT_DATE,                                          -- Fecha en que se envió el FURAT a la ARL.
	 num_radicado     	VARCHAR(30)                            NOT NULL         CHECK (LENGTH(TRIM(num_radicado)) >= 3),                       -- Número de radicado que devuelve la ARL.
	 ind_medio        	CHAR(1)                                NOT NULL         CHECK (ind_medio IN ('P','C','F')),                            -- MEDIO DEL REPORTE: (P) PORTAL WEB (C) CORREO (F) FÍSICO
	 ruta_soporte     	VARCHAR(500)                           NULL,                                                                           -- Ruta web del FURAT o comprobante cargado.
	 id_usuario       	VARCHAR                                NOT NULL,                                                                       -- Usuario del ERP que registró el reporte.
	 obser_reporte    	TEXT                                   NOT NULL         DEFAULT 'SIN OBSERVACIONES',                                   -- OBSERVACIONES DEL REPORTE
	 ind_borrado	  	BOOLEAN								   NOT NULL 		DEFAULT FALSE,

 PRIMARY KEY(id_reporte),
 UNIQUE (id_accidente),
 FOREIGN KEY (id_accidente) REFERENCES tab_accidentes(id_accidente),
 FOREIGN KEY (id_entidad)   REFERENCES tab_entidades(id_entidad),
 FOREIGN KEY (id_usuario)   REFERENCES tab_usuarios(id_usuario)
);


-------------------------------------------------
--TABLA CORRECCIONES DEL REPORTE A LA ARL      --
-------------------------------------------------
-- Cada correccion o ampliacion del FURAT ya enviado (cambio de gravedad, dato
-- errado, aclaracion que pide la ARL). No lleva radicado propio: va con el del
-- reporte al que pertenece. No cambia la fecha del reporte inicial,
-- que es la que cuenta para el plazo legal. Solo se inserta con
-- fun_insert_correcciones_acc.
CREATE TABLE IF NOT EXISTS tab_correcciones_acc
(
	 id_correccion     	DECIMAL(6,0)                           NOT NULL         CHECK (id_correccion >= 1),                                    -- Identificador único de la corrección.
	 id_reporte       	DECIMAL(6,0)                           NOT NULL,                                                                       -- Reporte que se corrige.
	 fec_correccion   	DATE                                   NOT NULL         DEFAULT CURRENT_DATE,                                          -- Fecha en que se envió la corrección a la ARL.
	 motivo_correccion	TEXT                                   NOT NULL         CHECK (LENGTH(TRIM(motivo_correccion)) >= 10),                 -- Qué se corrigió y por qué (ej. cambio de gravedad).
	 ind_medio        	CHAR(1)                                NOT NULL         CHECK (ind_medio IN ('P','C','F')),                            -- MEDIO DE LA CORRECCIÓN: (P) PORTAL WEB (C) CORREO (F) FÍSICO
	 ruta_soporte     	VARCHAR(500)                           NULL,                                                                           -- Ruta web del soporte de la corrección.
	 id_usuario       	VARCHAR                                NOT NULL,                                                                       -- Usuario del ERP que registró la corrección.
	 ind_borrado	  	BOOLEAN								   NOT NULL 		DEFAULT FALSE,

 PRIMARY KEY(id_correccion),
 FOREIGN KEY (id_reporte)   REFERENCES tab_reportes_acc(id_reporte),
 FOREIGN KEY (id_usuario)   REFERENCES tab_usuarios(id_usuario)
);


-----------------------------------
--MÓDULO DE MARKETING Y COMERCIAL--
-----------------------------------
-- ===============================================================
-- 1. tab_genero
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_genero
(
    id_genero   SMALLINT    NOT NULL PRIMARY KEY CHECK(id_genero >= 0),
    nom_genero  VARCHAR(30) NOT NULL,
    ind_estado  BOOLEAN     NOT NULL DEFAULT TRUE,
    ind_borrado BOOLEAN     NOT NULL DEFAULT FALSE
);


-- ===============================================================
-- 2. tab_vendedores_activos
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_vendedores_activos
(
    id_vendedor  VARCHAR(10)  NOT NULL PRIMARY KEY,
    nom_vendedor VARCHAR(201) NOT NULL,
    ind_vigente  BOOLEAN      NOT NULL DEFAULT TRUE
);


-- ===============================================================
-- 3. tab_pmtros_marcom
-- val_score_min_caliente > val_score_min_tibio (temperatura coherente).
-- Los cinco techos val_max_pts_* suman exactamente 100 (el CHECK va en el último: val_max_pts_compra).
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_pmtros_marcom
(
    id_empresa                   VARCHAR(10)   NOT NULL PRIMARY KEY,
    val_dias_sin_interaccion     DECIMAL(3,0)  NOT NULL DEFAULT 15   CHECK(val_dias_sin_interaccion >= 1 AND val_dias_sin_interaccion <= 365),
    val_dias_expiracion_lead     DECIMAL(3,0)  NOT NULL DEFAULT 90   CHECK(val_dias_expiracion_lead >= 1 AND val_dias_expiracion_lead <= 365),
    val_score_min_tibio          DECIMAL(3,0)  NOT NULL DEFAULT 40   CHECK(val_score_min_tibio >= 1 AND val_score_min_tibio <= 99),
    val_score_min_caliente       DECIMAL(3,0)  NOT NULL DEFAULT 70   CHECK(val_score_min_caliente >= 2 AND val_score_min_caliente <= 100) CHECK(val_score_min_caliente > val_score_min_tibio),
    val_max_contactos_adic       DECIMAL(2,0)  NOT NULL DEFAULT 2    CHECK(val_max_contactos_adic >= 1 AND val_max_contactos_adic <= 20),
    val_presupuesto_defecto      DECIMAL(12,0) NOT NULL DEFAULT 0    CHECK(val_presupuesto_defecto >= 0),
    val_meta_apertura_email      DECIMAL(3,0)  NOT NULL DEFAULT 20   CHECK(val_meta_apertura_email >= 1 AND val_meta_apertura_email <= 100),
    val_penalizacion_inactividad DECIMAL(2,0)  NOT NULL DEFAULT 5    CHECK(val_penalizacion_inactividad >= 1 AND val_penalizacion_inactividad <= 20),
    val_puntos_interaccion       DECIMAL(2,0)  NOT NULL DEFAULT 5    CHECK(val_puntos_interaccion >= 1 AND val_puntos_interaccion <= 20),
    val_puntos_apertura_email    DECIMAL(2,0)  NOT NULL DEFAULT 3    CHECK(val_puntos_apertura_email >= 1 AND val_puntos_apertura_email <= 20),
    val_puntos_clic_email        DECIMAL(2,0)  NOT NULL DEFAULT 5    CHECK(val_puntos_clic_email >= 1 AND val_puntos_clic_email <= 20),
    val_max_pts_segmentacion     DECIMAL(2,0)  NOT NULL DEFAULT 30   CHECK(val_max_pts_segmentacion >= 1 AND val_max_pts_segmentacion <= 100),
    val_max_pts_interacciones    DECIMAL(2,0)  NOT NULL DEFAULT 20   CHECK(val_max_pts_interacciones >= 1 AND val_max_pts_interacciones <= 100),
    val_max_pts_aperturas        DECIMAL(2,0)  NOT NULL DEFAULT 15   CHECK(val_max_pts_aperturas >= 1 AND val_max_pts_aperturas <= 100),
    val_max_pts_clics            DECIMAL(2,0)  NOT NULL DEFAULT 15   CHECK(val_max_pts_clics >= 1 AND val_max_pts_clics <= 100),
    val_max_pts_compra           DECIMAL(2,0)  NOT NULL DEFAULT 20   CHECK(val_max_pts_compra >= 1 AND val_max_pts_compra <= 100) CHECK(val_max_pts_segmentacion + val_max_pts_interacciones + val_max_pts_aperturas + val_max_pts_clics + val_max_pts_compra = 100),
    val_monto_referencia_compra  DECIMAL(12,0) NOT NULL DEFAULT 5000 CHECK(val_monto_referencia_compra > 0),
    val_max_descuento            DECIMAL(3,0)  NOT NULL DEFAULT 15   CHECK(val_max_descuento >= 0 AND val_max_descuento <= 100),
    FOREIGN KEY(id_empresa) REFERENCES tab_pmtros_grales(id_empresa)
);


-- ===============================================================
-- 4. tab_etapas_funnel
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_etapas_funnel
(
    id_etapa        DECIMAL(2,0) NOT NULL PRIMARY KEY CHECK(id_etapa > 0 AND id_etapa <= 99),
    nom_etapa       VARCHAR(50)  NOT NULL             CHECK(LENGTH(TRIM(nom_etapa)) >= 3),
    ind_etapa_final BOOLEAN      NOT NULL,
    ind_estado      BOOLEAN      NOT NULL DEFAULT TRUE,
    ind_borrado     BOOLEAN      NOT NULL DEFAULT FALSE,
    ind_es_perdido  BOOLEAN      NOT NULL DEFAULT FALSE
);


-- ===============================================================
-- 5. tab_canales
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_canales
(
    id_canal    DECIMAL(2,0) NOT NULL PRIMARY KEY CHECK(id_canal > 0 AND id_canal <= 99),
    nom_canal   VARCHAR(50)  NOT NULL             CHECK(LENGTH(TRIM(nom_canal)) >= 3),
    ind_estado  BOOLEAN      NOT NULL DEFAULT TRUE,
    ind_borrado BOOLEAN      NOT NULL DEFAULT FALSE
);


-- ===============================================================
-- 6. tab_criterios_segmentacion
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_criterios_segmentacion
(
    id_criterio  DECIMAL(2,0) NOT NULL PRIMARY KEY CHECK(id_criterio > 0 AND id_criterio <= 99),
    nom_criterio VARCHAR(50)  NOT NULL             CHECK(LENGTH(TRIM(nom_criterio)) >= 3),
    ind_estado   BOOLEAN      NOT NULL DEFAULT TRUE,
    ind_borrado  BOOLEAN      NOT NULL DEFAULT FALSE
);


-- ===============================================================
-- 7. tab_valores_segmentacion
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_valores_segmentacion
(
    id_criterio DECIMAL(2,0) NOT NULL CHECK(id_criterio > 0 AND id_criterio <= 99),
    id_valor    DECIMAL(2,0) NOT NULL CHECK(id_valor > 0 AND id_valor <= 99),
    nom_valor   VARCHAR(60)  NOT NULL CHECK(LENGTH(TRIM(nom_valor)) >= 3),
    des_valor   VARCHAR(250) NOT NULL CHECK(LENGTH(TRIM(des_valor)) >= 10),
    val_peso    DECIMAL(4,2) NOT NULL CHECK(val_peso >= 0.00 AND val_peso <= 10.00),
    ind_estado  BOOLEAN      NOT NULL DEFAULT TRUE,
    ind_borrado BOOLEAN      NOT NULL DEFAULT FALSE,
    PRIMARY KEY(id_criterio, id_valor),
    UNIQUE(id_criterio, nom_valor),
    FOREIGN KEY(id_criterio) REFERENCES tab_criterios_segmentacion(id_criterio)
);


-- ===============================================================
-- 8. tab_motivos_perdida
-- id 0 = "Sin pérdida" (registro especial).
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_motivos_perdida
(
    id_motivo_perdida SMALLINT     GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 99) PRIMARY KEY,   -- solo PostgreSQL
    nom_motivo        VARCHAR(60)  NOT NULL CHECK(LENGTH(TRIM(nom_motivo)) >= 3),
    des_motivo        VARCHAR(250) NOT NULL CHECK(LENGTH(TRIM(des_motivo)) >= 10),
    ind_estado        BOOLEAN      NOT NULL DEFAULT TRUE,
    ind_borrado       BOOLEAN      NOT NULL DEFAULT FALSE
);


-- ===============================================================
-- 9. tab_tipo_campana
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_tipo_campana
(
    id_tipo_campana  DECIMAL(2,0) NOT NULL PRIMARY KEY CHECK(id_tipo_campana > 0 AND id_tipo_campana <= 99),
    nom_tipo_campana VARCHAR(50)  NOT NULL             CHECK(LENGTH(TRIM(nom_tipo_campana)) >= 3),
    des_tipo_campana VARCHAR(250) NOT NULL             CHECK(LENGTH(TRIM(des_tipo_campana)) >= 10),
    ind_estado       BOOLEAN      NOT NULL DEFAULT TRUE,
    ind_borrado      BOOLEAN      NOT NULL DEFAULT FALSE
);


-- ===============================================================
-- 10. tab_campanas
-- Fechas TIMESTAMPTZ, hora Bogotá. fec_fin debe ser posterior a fec_inicio.
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_campanas
(
    id_campana      BIGINT       GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 999999) PRIMARY KEY,   -- solo PostgreSQL
    id_tipo_campana DECIMAL(2,0) NOT NULL CHECK(id_tipo_campana > 0 AND id_tipo_campana <= 99),
    nom_campana     VARCHAR(120) NOT NULL CHECK(LENGTH(TRIM(nom_campana)) >= 3),
    fec_inicio      TIMESTAMPTZ  NOT NULL,
    fec_fin         TIMESTAMPTZ  NOT NULL CHECK(fec_fin > fec_inicio),
    ind_estado      BOOLEAN      NOT NULL DEFAULT TRUE,
    ind_borrado     BOOLEAN      NOT NULL DEFAULT FALSE,
    FOREIGN KEY(id_tipo_campana) REFERENCES tab_tipo_campana(id_tipo_campana)
);


-- ===============================================================
-- 11. tab_campana_canal
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_campana_canal
(
    id_campana BIGINT       NOT NULL CHECK(id_campana > 0 AND id_campana <= 999999),
    id_canal   DECIMAL(2,0) NOT NULL CHECK(id_canal > 0 AND id_canal <= 99),
    PRIMARY KEY(id_campana, id_canal),
    FOREIGN KEY(id_campana) REFERENCES tab_campanas(id_campana),
    FOREIGN KEY(id_canal)   REFERENCES tab_canales(id_canal)
);


-- ===============================================================
-- 12. tab_leads
-- id_tercero: 'NOESCLIENT' = aún no es cliente. Solo puede tener tercero real si id_etapa = 6 (Ganado)
--             (el CHECK de esa regla va en id_etapa; id_etapa = 6 es deuda conocida).
-- id_genero: FK a tab_genero (0 = sin asignar).
-- id_tipo: FK a tab_tipo_identidad (otro módulo).
-- fec_conversion: admite NULL (fun_kpis usa IS NOT NULL). Es la única columna del módulo que lo admite.
-- val_score: columna calculada (suma de los cinco puntajes).
-- fec_nacimi: '9999-12-31' = sin dato; si hay fecha, NIT cualquier fecha pasada, persona natural >= 16 años.
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_leads
(
    id_lead               BIGINT        GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9999999999) PRIMARY KEY,   -- solo PostgreSQL
    id_tercero            VARCHAR(10)   NOT NULL DEFAULT 'NOESCLIENT' CHECK(id_tercero = 'NOESCLIENT' OR id_tercero ~ '^[A-Z0-9]{7,10}$'),   -- solo PostgreSQL (expresión regular)
    nom_lead              VARCHAR(100)  NOT NULL                      CHECK(LENGTH(TRIM(nom_lead)) >= 3),
    tel_lead              DECIMAL(10,0) NOT NULL                      CHECK(tel_lead >= 1000000000),
    email_lead            VARCHAR(120)  NOT NULL                      CHECK(email_lead ~* '^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$'),   -- solo PostgreSQL (expresión regular)
    id_ciudad             VARCHAR(5)    NOT NULL,
    id_canal              DECIMAL(2,0)  NOT NULL                      CHECK(id_canal > 0 AND id_canal <= 99),
    fec_registro          DATE          NOT NULL DEFAULT CURRENT_DATE,
    id_etapa              DECIMAL(2,0)  NOT NULL DEFAULT 1            CHECK(id_etapa > 0 AND id_etapa <= 99) CHECK(id_tercero = 'NOESCLIENT' OR id_etapa = 6),
    id_motivo_perdida     SMALLINT      NOT NULL DEFAULT 0            CHECK(id_motivo_perdida >= 0 AND id_motivo_perdida <= 99),
    ind_estado            BOOLEAN       NOT NULL DEFAULT TRUE,
    ind_borrado           BOOLEAN       NOT NULL DEFAULT FALSE,
    val_pts_segmentacion  DECIMAL(3,0)  NOT NULL DEFAULT 0            CHECK(val_pts_segmentacion  >= 0),
    val_pts_interacciones DECIMAL(3,0)  NOT NULL DEFAULT 0            CHECK(val_pts_interacciones >= 0),
    val_pts_aperturas     DECIMAL(3,0)  NOT NULL DEFAULT 0            CHECK(val_pts_aperturas     >= 0),
    val_pts_clics         DECIMAL(3,0)  NOT NULL DEFAULT 0            CHECK(val_pts_clics         >= 0),
    val_pts_compra        DECIMAL(3,0)  NOT NULL DEFAULT 0            CHECK(val_pts_compra        >= 0),
    val_score             DECIMAL(3,0)  GENERATED ALWAYS AS (val_pts_segmentacion + val_pts_interacciones + val_pts_aperturas + val_pts_clics + val_pts_compra) STORED NOT NULL CHECK(val_score >= 0 AND val_score <= 100),   -- solo PostgreSQL (columna calculada)
    id_vendedor           VARCHAR(10)   NOT NULL DEFAULT 'SINASIGNAR',
    fec_conversion        DATE,
    cedula_conocida       VARCHAR(10)   NOT NULL DEFAULT 'SINCEDULA',
    id_tipo               VARCHAR(5)    NOT NULL DEFAULT 'ND',
    fec_nacimi            DATE          NOT NULL DEFAULT '9999-12-31' CHECK(fec_nacimi = '9999-12-31' OR (id_tipo = 'NIT' AND fec_nacimi <= CURRENT_DATE) OR EXTRACT(YEAR FROM AGE(fec_nacimi)) >= 16),
    id_genero             SMALLINT      NOT NULL DEFAULT 0,
    ind_acepto_datos      BOOLEAN       NOT NULL DEFAULT TRUE,
    FOREIGN KEY(id_tercero)        REFERENCES tab_terceros(id_tercero),           -- otro módulo
    FOREIGN KEY(id_ciudad)         REFERENCES tab_ciudades(id_ciudad),            -- otro módulo
    FOREIGN KEY(id_canal)          REFERENCES tab_canales(id_canal),
    FOREIGN KEY(id_etapa)          REFERENCES tab_etapas_funnel(id_etapa),
    FOREIGN KEY(id_motivo_perdida) REFERENCES tab_motivos_perdida(id_motivo_perdida),
    FOREIGN KEY(id_vendedor)       REFERENCES tab_vendedores_activos(id_vendedor),
    FOREIGN KEY(id_tipo)           REFERENCES tab_tipo_identidad(id_tipo),        -- otro módulo
    FOREIGN KEY(id_genero)         REFERENCES tab_genero(id_genero)
);


-- ===============================================================
-- 13. tab_segmentacion_lead
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_segmentacion_lead
(
    id_lead        BIGINT       NOT NULL,
    id_criterio    DECIMAL(2,0) NOT NULL CHECK(id_criterio > 0 AND id_criterio <= 99),
    id_valor       DECIMAL(2,0) NOT NULL CHECK(id_valor > 0 AND id_valor <= 99),
    fec_asignacion TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ind_borrado    BOOLEAN      NOT NULL DEFAULT FALSE,
    PRIMARY KEY(id_lead, id_criterio),
    FOREIGN KEY(id_lead)               REFERENCES tab_leads(id_lead),
    FOREIGN KEY(id_criterio, id_valor) REFERENCES tab_valores_segmentacion(id_criterio, id_valor)
);


-- ===============================================================
-- 14. tab_segmentacion_cliente
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_segmentacion_cliente
(
    id_tercero     VARCHAR(10)  NOT NULL CHECK(id_tercero ~ '^[1-9][0-9]{7,9}$'),   -- solo PostgreSQL (expresión regular)
    id_criterio    DECIMAL(2,0) NOT NULL CHECK(id_criterio > 0 AND id_criterio <= 99),
    id_valor       DECIMAL(2,0) NOT NULL CHECK(id_valor > 0 AND id_valor <= 99),
    fec_asignacion TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ind_borrado    BOOLEAN      NOT NULL DEFAULT FALSE,
    PRIMARY KEY(id_tercero, id_criterio),
    FOREIGN KEY(id_tercero)            REFERENCES tab_terceros(id_tercero),   -- otro módulo
    FOREIGN KEY(id_criterio, id_valor) REFERENCES tab_valores_segmentacion(id_criterio, id_valor)
);


-- ===============================================================
-- 15. tab_lead_camp
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_lead_camp
(
    id_lead          BIGINT       NOT NULL,
    id_campana       BIGINT       NOT NULL CHECK(id_campana > 0 AND id_campana <= 999999),
    fec_asignacion   DATE         NOT NULL DEFAULT CURRENT_DATE,
    id_etapa_entrada DECIMAL(2,0) NOT NULL CHECK(id_etapa_entrada > 0 AND id_etapa_entrada <= 99),
    ind_origen       DECIMAL(1,0) NOT NULL CHECK(ind_origen IN (1, 2, 3)),   -- 1 Manual · 2 Automático · 3 Importado
    ind_estado       BOOLEAN      NOT NULL DEFAULT TRUE,
    PRIMARY KEY(id_lead, id_campana),
    FOREIGN KEY(id_lead)          REFERENCES tab_leads(id_lead),
    FOREIGN KEY(id_campana)       REFERENCES tab_campanas(id_campana),
    FOREIGN KEY(id_etapa_entrada) REFERENCES tab_etapas_funnel(id_etapa)
);


-- ===============================================================
-- 16. tab_cliente_camp
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_cliente_camp
(
    id_tercero     VARCHAR(10) NOT NULL,
    id_campana     BIGINT      NOT NULL CHECK(id_campana > 0 AND id_campana <= 999999),
    fec_asignacion DATE        NOT NULL DEFAULT CURRENT_DATE,
    ind_estado     BOOLEAN     NOT NULL DEFAULT TRUE,
    PRIMARY KEY(id_tercero, id_campana),
    FOREIGN KEY(id_tercero) REFERENCES tab_terceros(id_tercero),   -- otro módulo
    FOREIGN KEY(id_campana) REFERENCES tab_campanas(id_campana)
);


-- ===============================================================
-- 17. tab_tipos_interaccion_marcom
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_tipos_interaccion_marcom
(
    id_tip_interaccion   BIGINT      GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9999999999) PRIMARY KEY,   -- solo PostgreSQL
    nom_tipo_interaccion VARCHAR(50) NOT NULL CHECK(LENGTH(TRIM(nom_tipo_interaccion)) >= 3),
    ind_estado           BOOLEAN     NOT NULL DEFAULT TRUE,
    ind_borrado          BOOLEAN     NOT NULL DEFAULT FALSE
);


-- ===============================================================
-- 18. tab_interacciones
-- id_lead = 0 cuando la interacción es de un tercero; id_tercero = 'NOESLEAD' cuando es de un lead.
-- Un solo dueño: el CHECK de esa regla va en ind_es_lead.
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_interacciones
(
    id_interaccion      BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY CHECK(id_interaccion > 0 AND id_interaccion <= 9999999999),   -- solo PostgreSQL
    id_lead             BIGINT       NOT NULL DEFAULT 0,
    id_tercero          VARCHAR(10)  NOT NULL DEFAULT 'NOESLEAD',
    ind_es_lead         BOOLEAN      NOT NULL CHECK((ind_es_lead = TRUE AND id_lead <> 0 AND id_tercero = 'NOESLEAD') OR (ind_es_lead = FALSE AND id_tercero <> 'NOESLEAD' AND id_lead = 0)),
    id_vendedor         VARCHAR(10)  NOT NULL,
    id_canal            DECIMAL(2,0) NOT NULL                                 CHECK(id_canal > 0 AND id_canal <= 99),
    fec_interaccion     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_tipo_interaccion BIGINT       NOT NULL                                 CHECK(id_tipo_interaccion > 0 AND id_tipo_interaccion <= 99),
    des_resultado       VARCHAR(250) NOT NULL                                 CHECK(LENGTH(TRIM(des_resultado)) >= 3),
    FOREIGN KEY(id_lead)             REFERENCES tab_leads(id_lead),
    FOREIGN KEY(id_tercero)          REFERENCES tab_terceros(id_tercero),   -- otro módulo
    FOREIGN KEY(id_vendedor)         REFERENCES tab_terceros(id_tercero),   -- otro módulo
    FOREIGN KEY(id_canal)            REFERENCES tab_canales(id_canal),
    FOREIGN KEY(id_tipo_interaccion) REFERENCES tab_tipos_interaccion_marcom(id_tip_interaccion)
);


-- ===============================================================
-- 19. tab_proximas_acciones
-- fec_completada: '9999-12-31' = pendiente (sin fecha real); fecha real = completada.
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_proximas_acciones
(
    id_accion      BIGINT       GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9999999999) PRIMARY KEY,   -- solo PostgreSQL
    id_interaccion BIGINT       NOT NULL CHECK(id_interaccion > 0 AND id_interaccion <= 9999999999),
    fec_accion     DATE         NOT NULL,
    des_accion     VARCHAR(250) NOT NULL CHECK(LENGTH(TRIM(des_accion)) >= 10),
    ind_completada BOOLEAN      NOT NULL DEFAULT FALSE,
    fec_completada DATE         NOT NULL DEFAULT '9999-12-31' CHECK((ind_completada = FALSE AND fec_completada = '9999-12-31') OR (ind_completada = TRUE AND fec_completada < '9999-12-31')),
    FOREIGN KEY(id_interaccion) REFERENCES tab_interacciones(id_interaccion)
);


-- ===============================================================
-- 20. tab_evento
-- id_campana = 0 cuando el evento no pertenece a una campaña.
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_evento
(
    id_evento      DECIMAL(6,0) NOT NULL PRIMARY KEY CHECK(id_evento > 0 AND id_evento <= 999999),
    id_campana     BIGINT       NOT NULL DEFAULT 0   CHECK(id_campana >= 0 AND id_campana <= 999999),
    id_responsable VARCHAR(10)  NOT NULL,
    nom_evento     VARCHAR(120) NOT NULL             CHECK(LENGTH(TRIM(nom_evento)) >= 3),
    des_evento     VARCHAR(250) NOT NULL             CHECK(LENGTH(TRIM(des_evento)) >= 10),
    lug_evento     VARCHAR(250) NOT NULL             CHECK(LENGTH(TRIM(lug_evento)) >= 3),
    val_cupo       DECIMAL(4,0) NOT NULL             CHECK(val_cupo > 0 AND val_cupo <= 9999),
    fec_inicio     TIMESTAMPTZ  NOT NULL,
    fec_fin        TIMESTAMPTZ  NOT NULL             CHECK(fec_fin > fec_inicio),
    ind_estado     BOOLEAN      NOT NULL DEFAULT TRUE,
    ind_borrado    BOOLEAN      NOT NULL DEFAULT FALSE,
    FOREIGN KEY(id_campana)     REFERENCES tab_campanas(id_campana),
    FOREIGN KEY(id_responsable) REFERENCES tab_terceros(id_tercero)   -- otro módulo
);


-- ===============================================================
-- 21. tab_even_lead
-- ind_estado: 1 Invitado · 2 Confirmado · 3 Asistió · 4 No asistió.
-- El CHECK de coherencia de fechas va en ind_estado. '9999-12-31' = "aún no ocurrió".
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_even_lead
(
    id_evento        DECIMAL(6,0) NOT NULL CHECK(id_evento > 0 AND id_evento <= 999999),
    id_lead          BIGINT       NOT NULL,
    fec_invitacion   DATE         NOT NULL DEFAULT CURRENT_DATE,
    fec_confirmacion DATE         NOT NULL DEFAULT '9999-12-31',
    fec_asistencia   DATE         NOT NULL DEFAULT '9999-12-31',
    ind_estado       DECIMAL(1,0) NOT NULL CHECK(ind_estado IN (1, 2, 3, 4))
                                           CHECK((ind_estado = 1 AND fec_confirmacion = '9999-12-31' AND fec_asistencia = '9999-12-31')
                                              OR (ind_estado = 2 AND fec_confirmacion < '9999-12-31' AND fec_asistencia = '9999-12-31')
                                              OR (ind_estado = 3 AND fec_confirmacion < '9999-12-31' AND fec_asistencia < '9999-12-31')
                                              OR (ind_estado = 4 AND fec_confirmacion < '9999-12-31' AND fec_asistencia = '9999-12-31')),
    PRIMARY KEY(id_evento, id_lead),
    FOREIGN KEY(id_evento) REFERENCES tab_evento(id_evento),
    FOREIGN KEY(id_lead)   REFERENCES tab_leads(id_lead)
);


-- ===============================================================
-- 22. tab_prod_camp
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_prod_camp
(
    id_campana     BIGINT       NOT NULL CHECK(id_campana > 0 AND id_campana <= 999999),
    id_producto    DECIMAL(3,0) NOT NULL CHECK(id_producto > 0 AND id_producto <= 999),
    fec_asignacion DATE         NOT NULL DEFAULT CURRENT_DATE,
    ind_estado     BOOLEAN      NOT NULL DEFAULT TRUE,
    ind_borrado    BOOLEAN      NOT NULL DEFAULT FALSE,
    PRIMARY KEY(id_campana, id_producto),
    FOREIGN KEY(id_campana)  REFERENCES tab_campanas(id_campana),
    FOREIGN KEY(id_producto) REFERENCES tab_productos(id_producto)   -- otro módulo
);


-- ===============================================================
-- 23. tab_presupuesto_campana
-- ind_estado: 1 Pendiente · 2 Aprobado · 3 Rechazado. No se ejecuta más de lo aprobado.
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_presupuesto_campana
(
    id_presupuesto  DECIMAL(6,0)  NOT NULL PRIMARY KEY CHECK(id_presupuesto > 0 AND id_presupuesto <= 999999),
    id_campana      BIGINT        NOT NULL             CHECK(id_campana > 0 AND id_campana <= 999999),
    val_aprobado    DECIMAL(12,0) NOT NULL             CHECK(val_aprobado >= 0),
    val_ejecutado   DECIMAL(12,0) NOT NULL DEFAULT 0   CHECK(val_ejecutado >= 0) CHECK(val_ejecutado <= val_aprobado),
    fec_presupuesto DATE          NOT NULL DEFAULT CURRENT_DATE,
    ind_estado      DECIMAL(1,0)  NOT NULL DEFAULT 1   CHECK(ind_estado IN (1, 2, 3)),
    ind_borrado     BOOLEAN       NOT NULL DEFAULT FALSE,
    FOREIGN KEY(id_campana) REFERENCES tab_campanas(id_campana)
);


-- ===============================================================
-- 24. tab_presupuesto_evento
-- ind_estado: 1 Pendiente · 2 Aprobado · 3 Rechazado. No se ejecuta más de lo aprobado.
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_presupuesto_evento
(
    id_presupuesto  DECIMAL(6,0)  NOT NULL PRIMARY KEY CHECK(id_presupuesto > 0 AND id_presupuesto <= 999999),
    id_evento       DECIMAL(6,0)  NOT NULL             CHECK(id_evento > 0 AND id_evento <= 999999),
    val_aprobado    DECIMAL(12,0) NOT NULL             CHECK(val_aprobado >= 0),
    val_ejecutado   DECIMAL(12,0) NOT NULL DEFAULT 0   CHECK(val_ejecutado >= 0) CHECK(val_ejecutado <= val_aprobado),
    fec_presupuesto DATE          NOT NULL DEFAULT CURRENT_DATE,
    ind_estado      DECIMAL(1,0)  NOT NULL DEFAULT 1   CHECK(ind_estado IN (1, 2, 3)),
    ind_borrado     BOOLEAN       NOT NULL DEFAULT FALSE,
    FOREIGN KEY(id_evento) REFERENCES tab_evento(id_evento)
);


-- ===============================================================
-- 25. tab_kpis_marcom
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_kpis_marcom
(
    id_kpi      DECIMAL(2,0) NOT NULL PRIMARY KEY CHECK(id_kpi > 0 AND id_kpi <= 99),
    nom_kpi     VARCHAR(60)  NOT NULL             CHECK(LENGTH(nom_kpi) >= 3),
    des_kpi     TEXT         NOT NULL,
    ind_estado  BOOLEAN      NOT NULL,
    ind_borrado BOOLEAN      NOT NULL DEFAULT FALSE
);


-- ===============================================================
-- 26. tab_medicion_kpi
-- fec_periodo: siempre el primer día del mes.
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_medicion_kpi
(
    id_campana               BIGINT        NOT NULL CHECK(id_campana > 0 AND id_campana <= 999999),
    id_kpi                   DECIMAL(2,0)  NOT NULL CHECK(id_kpi > 0 AND id_kpi <= 99),
    fec_periodo              DATE          NOT NULL CHECK(EXTRACT(DAY FROM fec_periodo) = 1),
    val_medicion             DECIMAL(12,2) NOT NULL,
    fec_ultima_actualizacion TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY(id_campana, id_kpi, fec_periodo),
    FOREIGN KEY(id_campana) REFERENCES tab_campanas(id_campana),
    FOREIGN KEY(id_kpi)     REFERENCES tab_kpis_marcom(id_kpi)
);


-- ===============================================================
-- 27. tab_evento_correo
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_evento_correo
(
    cod_evento          VARCHAR(30)  NOT NULL PRIMARY KEY CHECK(cod_evento ~ '^[A-Z_]{3,30}$'),   -- solo PostgreSQL (expresión regular)
    nom_evento          VARCHAR(80)  NOT NULL             CHECK(LENGTH(TRIM(nom_evento)) >= 3),
    des_variables       VARCHAR(250) NOT NULL DEFAULT '',
    ind_requiere_baja   BOOLEAN      NOT NULL DEFAULT FALSE,   -- TRUE = lleva enlace de baja y respeta la lista de bajas (correos comerciales)
    ind_estado          BOOLEAN      NOT NULL DEFAULT TRUE,    -- FALSE = el evento está apagado (no se encola nada)
    ind_borrado         BOOLEAN      NOT NULL DEFAULT FALSE,
    id_area             DECIMAL(5,0) NOT NULL DEFAULT 0   CHECK(id_area >= 0),   -- 0 = sin área (centinela, no hay FK); si no, tab_areas.id_area
    des_remitente_email VARCHAR(120) NOT NULL DEFAULT ''  CHECK(des_remitente_email = LOWER(des_remitente_email))
);


-- ===============================================================
-- 28. tab_plantillas_correo
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_plantillas_correo
(
    id_plantilla    SMALLINT     GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9999) PRIMARY KEY,   -- solo PostgreSQL
    id_canal        DECIMAL(2,0) NOT NULL CHECK(id_canal > 0 AND id_canal <= 99),
    nom_plantilla   VARCHAR(120) NOT NULL CHECK(LENGTH(nom_plantilla) >= 3),
    des_contenido   TEXT         NOT NULL,
    ind_generada_ia BOOLEAN      NOT NULL DEFAULT FALSE,
    ind_estado      BOOLEAN      NOT NULL,
    ind_borrado     BOOLEAN      NOT NULL DEFAULT FALSE,
    cod_evento      VARCHAR(30)  NOT NULL DEFAULT 'SINEVENTO',
    des_asunto      VARCHAR(150) NOT NULL DEFAULT '',
    FOREIGN KEY(id_canal)   REFERENCES tab_canales(id_canal),
    FOREIGN KEY(cod_evento) REFERENCES tab_evento_correo(cod_evento)
);

-- solo PostgreSQL (índice parcial: solo indexa las filas que cumplen el WHERE)
CREATE UNIQUE INDEX IF NOT EXISTS idx_plantilla_evento_activa ON tab_plantillas_correo (cod_evento)
    WHERE cod_evento <> 'SINEVENTO' AND ind_estado = TRUE AND ind_borrado = FALSE;


-- ===============================================================
-- 29. tab_contactos_adicionales
-- id_contacto sin IDENTITY (así estaba).
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_contactos_adicionales
(
    id_contacto    DECIMAL(6,0)  NOT NULL PRIMARY KEY CHECK(id_contacto > 0 AND id_contacto <= 999999),
    id_tercero     VARCHAR(10)   NOT NULL,
    nom_contacto   VARCHAR(120)  NOT NULL             CHECK(LENGTH(TRIM(nom_contacto)) >= 3),
    car_contacto   VARCHAR(60)   NOT NULL             CHECK(LENGTH(TRIM(car_contacto)) >= 2),
    tel_contacto   DECIMAL(10,0) NOT NULL             CHECK(tel_contacto >= 1000000000),
    email_contacto VARCHAR(120)  NOT NULL             CHECK(LENGTH(TRIM(email_contacto)) >= 6),
    ind_estado     BOOLEAN       NOT NULL DEFAULT TRUE,
    ind_borrado    BOOLEAN       NOT NULL DEFAULT FALSE,
    FOREIGN KEY(id_tercero) REFERENCES tab_terceros(id_tercero)   -- otro módulo
);


-- ===============================================================
-- 30. tab_envios
-- '9999-12-31 00:00:00' = aún no ocurrió. Sin apertura no hay clic.
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_envios
(
    id_envio     DECIMAL(10,0) NOT NULL PRIMARY KEY CHECK(id_envio > 0 AND id_envio <= 9999999999),
    id_campana   BIGINT        NOT NULL             CHECK(id_campana > 0 AND id_campana <= 999999),
    id_plantilla SMALLINT      NOT NULL             CHECK(id_plantilla > 0 AND id_plantilla <= 9999),
    id_tercero   VARCHAR(10)   NOT NULL,
    id_canal     DECIMAL(2,0)  NOT NULL             CHECK(id_canal > 0 AND id_canal <= 99),
    fec_envio    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cod_tracking VARCHAR(64)   NOT NULL UNIQUE      CHECK(LENGTH(TRIM(cod_tracking)) = 36),
    fec_apertura TIMESTAMP     NOT NULL DEFAULT '9999-12-31 00:00:00' CHECK(fec_apertura = '9999-12-31 00:00:00' OR fec_apertura >= fec_envio),
    fec_clic     TIMESTAMP     NOT NULL DEFAULT '9999-12-31 00:00:00' CHECK(fec_clic = '9999-12-31 00:00:00' OR fec_clic >= fec_envio)
                                                                      CHECK((fec_apertura = '9999-12-31 00:00:00' AND fec_clic = '9999-12-31 00:00:00')
                                                                         OR (fec_apertura < '9999-12-31 00:00:00' AND fec_clic = '9999-12-31 00:00:00')
                                                                         OR (fec_apertura < '9999-12-31 00:00:00' AND fec_clic < '9999-12-31 00:00:00')),
    ind_estado   BOOLEAN       NOT NULL DEFAULT TRUE,
    FOREIGN KEY(id_campana)   REFERENCES tab_campanas(id_campana),
    FOREIGN KEY(id_plantilla) REFERENCES tab_plantillas_correo(id_plantilla),
    FOREIGN KEY(id_tercero)   REFERENCES tab_terceros(id_tercero),   -- otro módulo
    FOREIGN KEY(id_canal)     REFERENCES tab_canales(id_canal)
);


-- ===============================================================
-- 31. tab_canal_tipo_interaccion
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_canal_tipo_interaccion
(
    id_canal           DECIMAL(2,0) NOT NULL CHECK(id_canal > 0 AND id_canal <= 99),
    id_tip_interaccion BIGINT       NOT NULL,
    ind_borrado        BOOLEAN      NOT NULL DEFAULT FALSE,
    PRIMARY KEY(id_canal, id_tip_interaccion),
    FOREIGN KEY(id_canal)           REFERENCES tab_canales(id_canal),
    FOREIGN KEY(id_tip_interaccion) REFERENCES tab_tipos_interaccion_marcom(id_tip_interaccion)
);


-- ===============================================================
-- 32. tab_historial_asignacion_lead
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_historial_asignacion_lead
(
    id_historial      BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,   -- solo PostgreSQL
    id_lead           BIGINT      NOT NULL,
    id_vendedor_ant   VARCHAR(10) NOT NULL,
    id_vendedor_nue   VARCHAR(10) NOT NULL,
    id_usuario_asigna VARCHAR(10) NOT NULL,
    fec_asignacion    TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(id_lead)         REFERENCES tab_leads(id_lead),
    FOREIGN KEY(id_vendedor_ant) REFERENCES tab_vendedores_activos(id_vendedor),
    FOREIGN KEY(id_vendedor_nue) REFERENCES tab_vendedores_activos(id_vendedor)
);


-- ===============================================================
-- 33. tab_tracker_campana_canal
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_tracker_campana_canal
(
    id_tracker   BIGINT       GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9999999999) PRIMARY KEY,   -- solo PostgreSQL
    id_campana   BIGINT       NOT NULL CHECK(id_campana > 0 AND id_campana <= 999999),
    id_canal     DECIMAL(2,0) NOT NULL CHECK(id_canal > 0 AND id_canal <= 99),
    cod_tracker  VARCHAR(50)  NOT NULL UNIQUE CHECK(LENGTH(TRIM(cod_tracker)) >= 3),
    nom_tracker  VARCHAR(100) NOT NULL CHECK(LENGTH(TRIM(nom_tracker)) >= 3),
    fec_creacion TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ind_estado   BOOLEAN      NOT NULL DEFAULT TRUE,
    ind_borrado  BOOLEAN      NOT NULL DEFAULT FALSE,
    FOREIGN KEY(id_campana) REFERENCES tab_campanas(id_campana),
    FOREIGN KEY(id_canal)   REFERENCES tab_canales(id_canal)
);


-- ===============================================================
-- 34. tab_rate_limit_promo
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_rate_limit_promo
(
    ip_origen   VARCHAR(45) NOT NULL,
    fec_intento TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_intento  BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY   -- solo PostgreSQL
);

CREATE INDEX IF NOT EXISTS idx_rate_limit_promo_ip_fecha ON tab_rate_limit_promo (ip_origen, fec_intento);


-- ===============================================================
-- 35. tab_lead_camp_tracker
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_lead_camp_tracker
(
    id_lead    BIGINT NOT NULL,
    id_campana BIGINT NOT NULL,
    id_tracker BIGINT NOT NULL,
    PRIMARY KEY(id_lead, id_campana),
    FOREIGN KEY(id_lead, id_campana) REFERENCES tab_lead_camp(id_lead, id_campana),
    FOREIGN KEY(id_tracker)          REFERENCES tab_tracker_campana_canal(id_tracker)
);


-- ===============================================================
-- 36. tab_enc_pedidos
-- Estados (ind_estado): 1 Borrador · 2 Confirmado · 3 Enviado a facturación · 4 Anulado.
-- Fechas: TIMESTAMPTZ; centinela de "aún no ocurrió" = 9999-12-31 00:00:00-05.
-- Montos: enteros en pesos, DECIMAL(10,0), como tab_enc_facturas.
-- id_formapago: sin FK a tab_forma_pagos en la base.
-- Reglas entre columnas (cada CHECK va en una de las columnas que usa):
--   · id_cliente: con cliente real desde que se confirma (en Borrador o Anulado puede faltar).
--   · fec_confirmacion: vacía en Borrador, llena en Confirmado y Enviado.
--   · des_motivo_anulacion: motivo y fecha reales solo si el estado es 4.
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_enc_pedidos
(
    id_pedido            BIGINT        GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9999999999) PRIMARY KEY,   -- solo PostgreSQL
    id_lead              BIGINT        NOT NULL,
    id_cliente           VARCHAR(10)   NOT NULL DEFAULT 'NOESCLIENT' CHECK(ind_estado IN (1, 4) OR id_cliente <> 'NOESCLIENT'),
    id_vendedor          VARCHAR(10)   NOT NULL           CHECK(id_vendedor <> 'SINASIGNAR'),   -- Todo pedido tiene vendedor real
    id_ciudad            VARCHAR(10)   NOT NULL,
    id_formapago         DECIMAL(4,0)  NOT NULL           CHECK(id_formapago > 0 AND id_formapago < 9999),
    id_campana           BIGINT        NOT NULL DEFAULT 0 CHECK(id_campana >= 0 AND id_campana <= 999999),
    fec_pedido           TIMESTAMPTZ   NOT NULL DEFAULT now(),
    fec_confirmacion     TIMESTAMPTZ   NOT NULL DEFAULT '9999-12-31 00:00:00-05' CHECK((ind_estado = 1 AND fec_confirmacion = '9999-12-31 00:00:00-05') OR (ind_estado IN (2, 3) AND fec_confirmacion <> '9999-12-31 00:00:00-05') OR ind_estado = 4),
    fec_anulacion        TIMESTAMPTZ   NOT NULL DEFAULT '9999-12-31 00:00:00-05',
    ind_estado           DECIMAL(1,0)  NOT NULL DEFAULT 1 CHECK(ind_estado IN (1, 2, 3, 4)),
    des_motivo_anulacion VARCHAR(250)  NOT NULL DEFAULT 'ND' CHECK((ind_estado = 4 AND des_motivo_anulacion <> 'ND' AND fec_anulacion <> '9999-12-31 00:00:00-05') OR (ind_estado <> 4 AND des_motivo_anulacion = 'ND' AND fec_anulacion = '9999-12-31 00:00:00-05')),
    val_total_des        DECIMAL(10,0) NOT NULL DEFAULT 0 CHECK(val_total_des >= 0),
    val_total_iva        DECIMAL(10,0) NOT NULL DEFAULT 0 CHECK(val_total_iva >= 0),
    val_total            DECIMAL(10,0) NOT NULL DEFAULT 0 CHECK(val_total >= 0),
    ind_borrado          BOOLEAN       NOT NULL DEFAULT FALSE,
    FOREIGN KEY(id_lead)     REFERENCES tab_leads(id_lead),
    FOREIGN KEY(id_vendedor) REFERENCES tab_vendedores_activos(id_vendedor),
    FOREIGN KEY(id_ciudad)   REFERENCES tab_ciudades(id_ciudad),   -- otro módulo
    FOREIGN KEY(id_campana)  REFERENCES tab_campanas(id_campana)
);


-- ===============================================================
-- 37. tab_det_pedidos
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_det_pedidos
(
    id_pedido     BIGINT        NOT NULL,
    id_producto   DECIMAL(3,0)  NOT NULL,
    val_cantidad  DECIMAL(4,0)  NOT NULL           CHECK(val_cantidad > 0 AND val_cantidad <= 9999),
    val_precio    DECIMAL(11,0) NOT NULL           CHECK(val_precio >= 0),
    por_descuento DECIMAL(3,0)  NOT NULL DEFAULT 0 CHECK(por_descuento >= 0 AND por_descuento <= 100),
    val_poriva    DECIMAL(2,0)  NOT NULL DEFAULT 0 CHECK(val_poriva >= 0),
    val_bruto     DECIMAL(10,0) NOT NULL           CHECK(val_bruto >= 0),
    val_descuento DECIMAL(10,0) NOT NULL DEFAULT 0 CHECK(val_descuento >= 0),
    val_iva       DECIMAL(10,0) NOT NULL DEFAULT 0 CHECK(val_iva >= 0),
    val_neto      DECIMAL(10,0) NOT NULL           CHECK(val_neto >= 0),
    PRIMARY KEY(id_pedido, id_producto),
    FOREIGN KEY(id_pedido)   REFERENCES tab_enc_pedidos(id_pedido),
    FOREIGN KEY(id_producto) REFERENCES tab_productos(id_producto)   -- otro módulo
);


-- ===============================================================
-- 38. tab_pedido_factura
-- Puente pedido-factura; lo llena fun_convertir_pedido_a_factura.
-- Un pedido tiene una sola factura y una factura viene de un solo pedido (UNIQUE en cada columna).
-- id_factura: sin FK a tab_enc_facturas en la base (así estaba).
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_pedido_factura
(
    id_pedido   BIGINT      NOT NULL UNIQUE,
    id_factura  VARCHAR(10) NOT NULL UNIQUE,
    fec_vinculo TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(id_pedido, id_factura),
    FOREIGN KEY(id_pedido) REFERENCES tab_enc_pedidos(id_pedido)
);


-- ===============================================================
-- 39. tab_camp_prod
-- Productos que promueve cada campaña (N:M). La campaña 0 ("Sin campaña") no promueve productos.
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_camp_prod
(
    id_campana  BIGINT       NOT NULL CHECK(id_campana > 0 AND id_campana <= 999999),
    id_producto DECIMAL(3,0) NOT NULL,
    ind_borrado BOOLEAN      NOT NULL DEFAULT FALSE,
    PRIMARY KEY(id_campana, id_producto),
    FOREIGN KEY(id_campana)  REFERENCES tab_campanas(id_campana),
    FOREIGN KEY(id_producto) REFERENCES tab_productos(id_producto)   -- otro módulo
);


-- ===============================================================
-- 40. tab_cola_correos
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_cola_correos
(
    id_correo        BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,   -- solo PostgreSQL
    cod_evento       VARCHAR(30)  NOT NULL,
    id_lead          BIGINT       NOT NULL DEFAULT 0,   -- 0 = sin lead asociado
    des_destinatario VARCHAR(120) NOT NULL           CHECK(des_destinatario ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),   -- solo PostgreSQL (expresión regular)
    nom_destinatario VARCHAR(100) NOT NULL DEFAULT '',
    des_asunto       VARCHAR(200) NOT NULL           CHECK(LENGTH(TRIM(des_asunto)) >= 1),
    des_cuerpo       TEXT         NOT NULL,
    ind_estado       SMALLINT     NOT NULL DEFAULT 1 CHECK(ind_estado BETWEEN 1 AND 4),
    num_intentos     SMALLINT     NOT NULL DEFAULT 0 CHECK(num_intentos >= 0),
    fec_encolado     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    fec_prox_intento TIMESTAMPTZ  NOT NULL DEFAULT now(),
    fec_ult_intento  TIMESTAMPTZ  NOT NULL DEFAULT '9999-12-30 19:00:00-05',
    fec_envio        TIMESTAMPTZ  NOT NULL DEFAULT '9999-12-30 19:00:00-05',
    des_error        VARCHAR(300) NOT NULL DEFAULT '',
    FOREIGN KEY(cod_evento) REFERENCES tab_evento_correo(cod_evento)
);

-- solo PostgreSQL (índice parcial: solo indexa las filas que cumplen el WHERE)
CREATE INDEX IF NOT EXISTS idx_cola_correos_pendientes ON tab_cola_correos (fec_prox_intento)
    WHERE ind_estado IN (1, 2);


-- ===============================================================
-- 41. tab_baja_correo
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_baja_correo
(
    des_email VARCHAR(120) NOT NULL PRIMARY KEY CHECK(des_email = LOWER(des_email)),
    fec_baja  TIMESTAMPTZ  NOT NULL DEFAULT now()
);


-- ===============================================================
-- 42. tab_remitente_correo
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_remitente_correo
(
    des_email     VARCHAR(120) NOT NULL PRIMARY KEY CHECK(des_email = LOWER(des_email) AND des_email ~ '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$'),   -- solo PostgreSQL (expresión regular)
    nom_remitente VARCHAR(100) NOT NULL             CHECK(LENGTH(TRIM(nom_remitente)) >= 3),
    ind_estado    BOOLEAN      NOT NULL DEFAULT TRUE,
    ind_borrado   BOOLEAN      NOT NULL DEFAULT FALSE
);


-- ===============================================================
-- 43. tab_pmtros_correo
-- ===============================================================
CREATE TABLE IF NOT EXISTS tab_pmtros_correo
(
    cod_pmtros VARCHAR(30)  NOT NULL PRIMARY KEY CHECK(cod_pmtros ~ '^[A-Z_]{3,30}$'),   -- solo PostgreSQL (expresión regular)
    val_pmtros TEXT         NOT NULL DEFAULT '',
    des_pmtros VARCHAR(150) NOT NULL
);

-- ----------------------------------------------------------------
-- MÓDULO DE FACTURACIÓN
-- ----------------------------------------------------------------
----------------------------------------------------------
----------------------------------------------------------
--TABLA PARA PARÁMETROS DE PROCESO FACTURACIÓN Y CARTERA -
----------------------------------------------------------

CREATE TABLE IF NOT EXISTS tab_pmtros_facturacion
(
    -- LEGACY: val_res_aut, fec_venc, fec_res_aut, val_prefijofac, val_facini/actual/fin ya no se usan: la numeración
    -- de facturas vive en tab_resoluciones_dian. Quedan opcionales (NULL) para no romper datos existentes.
    id_empresa                      VARCHAR(10)                 NOT NULL,                                                                                --identificador de la empresa                                                                  
    val_prefijocot                  VARCHAR(4)                  NOT NULL CHECK(LENGTH(TRIM(val_prefijocot)) >=1 AND LENGTH(TRIM(val_prefijocot)) <=4 ),  --el prefijo de la cotizacion
	val_cotini	                    DECIMAL(6,0)		        NOT NULL CHECK(val_cotini > 0),                                                          -- Valor inicial de la cotizacion 
    val_cotactual                   DECIMAL(6,0)                NOT NULL CHECK(val_cotactual >= val_cotini),                                             -- Valor actual de la cotizacion 
    val_intcorriente                DECIMAL(5,2)                NOT NULL CHECK( val_intcorriente >= 0 AND val_intcorriente <= 99  ),                     --tasa de interés corriente MENSUAL (%) que se cobra al financiar en cuotas
    val_pesosXpuntos                DECIMAL(10,0)               NOT NULL CHECK(val_pesosXpuntos > 0),                                                    -- Valor equivalente de pesos por puntos (Ejmp: Por cada 10 mil se da un punto)
    val_interesmora                 DECIMAL(5,2)                NOT NULL CHECK(val_interesmora >= 0 AND val_interesmora <= 100),                         -- tasa de interés de mora MENSUAL (%); se liquida por día sobre el capital vencido
    val_diascartera                 DECIMAL(3,0)                NOT NULL CHECK(val_diascartera IN (30, 60, 90, 180)),                         -- Número de días máximo para castigar cartera
    val_dias_vig_cot                DECIMAL(3,0)                NOT NULL DEFAULT 15 CHECK(val_dias_vig_cot >= 1 AND val_dias_vig_cot <= 365),             -- Días de vigencia de la cotización (por defecto 15)
    val_min_gestiones               DECIMAL(2,0)                NOT NULL DEFAULT 1 CHECK(val_min_gestiones >= 0 AND val_min_gestiones <= 99),      -- Gestiones de cobro exigidas antes de castigar una cuota (0 = no exige). Lo decide la empresa
    val_max_cuotas                  DECIMAL(2,0)                NOT NULL DEFAULT 1 CHECK(val_max_cuotas >= 1 AND val_max_cuotas <= 24),            -- Máximo de cuotas que la empresa permite en una factura a crédito
    ind_periodicidad                CHAR(1)                     NOT NULL DEFAULT 'M' CHECK(ind_periodicidad IN ('S', 'Q', 'M')),                    -- Cada cuánto vence una cuota: S semanal (7 días) / Q quincenal (15) / M mensual (30)
    ind_borrado                     BOOLEAN                     NOT NULL DEFAULT FALSE, --TRUE: Borrado lógico (Inactivo) / FALSE: Activo	             --indicador de borrado lógico
    PRIMARY KEY(id_empresa),
    FOREIGN KEY(id_empresa) REFERENCES tab_pmtros_grales(id_empresa)
); 
------------------------
--TABLA PARA CLIENTES --
------------------------
--CUANDO CATEGORÍA DEL TERCERO LO SEA
CREATE TABLE IF NOT EXISTS tab_clientes
(
    id_cliente                      VARCHAR(10)                 NOT NULL CHECK(LENGTH(TRIM(id_cliente)) >=6),	                           -- identificador del cliente	
    id_tipo        		            VARCHAR(5)                  NOT NULL CHECK(id_tipo ~ '^[A-Z]{2,5}$'),                                   --  tipo de documento						                                           --identificaion del tipo de documentacion
    fec_nacimi      	            DATE                        NOT NULL CONSTRAINT ck_clientes_fecha_no_futura CHECK (fec_nacimi <= CURRENT_DATE), -- nacimiento (persona) o constitución (empresa); edad mínima: trigger
    val_edad                        DECIMAL(3,0)                NOT NULL CONSTRAINT ck_clientes_val_edad CHECK(val_edad >= 0 AND val_edad <= 200), -- edad (una empresa puede tener más de 99 años)
    id_genero                       SMALLINT                    NOT NULL CHECK(id_genero > 0),                                             -- genero del cliente (FK a tab_genero; 0 = sin asignar no es válido)
    val_puntos                      DECIMAL(10,0)               NOT NULL CHECK (val_puntos >=0 AND val_puntos <=9999999999),               -- Puntaje para valoracion del credito al cliente
    ind_credito                     BOOLEAN                     NOT NULL DEFAULT FALSE, --TRUE=APROBADO O FALSE = NO APROBADO,             -- el cliente puede tener credito para pago
    val_cupocredito                 DECIMAL(12,0)               NOT NULL CHECK(val_cupocredito >= 0 AND val_cupocredito <=999999999999),   -- valor aprobado de credito al cliente
    val_diascartera                 DECIMAL(3,0)                NOT NULL CHECK(val_diascartera >= 0 AND val_diascartera <= 120),           -- Días de cartera para el cliente en facturas
    ind_estado                      BOOLEAN                     NOT NULL DEFAULT TRUE, --TRUE=Activo / FALSE=No activo                     -- Indicador de estado del cliente
    ind_borrado                     BOOLEAN                     NOT NULL DEFAULT FALSE, --TRUE: Borrado lógico (Inactivo) / FALSE: Activo  -- indicador de borrado lógico
    ind_gran_contribuyente          BOOLEAN                     NOT NULL DEFAULT FALSE,                                                    -- Gran contribuyente
    ind_autorretenedor              BOOLEAN                     NOT NULL DEFAULT FALSE,                                                    -- Autorretenedor
    ind_resp_iva                    BOOLEAN                     NOT NULL DEFAULT TRUE,                                                     -- Responsable de IVA
    ind_regimen_simple              BOOLEAN                     NOT NULL DEFAULT FALSE,                                                    -- Régimen simple de tributación
    ind_retefte_aplica              BOOLEAN                     NOT NULL DEFAULT TRUE,                                                     -- Se le aplica retención en la fuente
    ind_reteiva_aplica              BOOLEAN                     NOT NULL DEFAULT TRUE,                                                     -- Se le aplica retención de IVA
    ind_reteica_aplica              BOOLEAN                     NOT NULL DEFAULT TRUE,                                                     -- Se le aplica retención de ICA
    PRIMARY KEY(id_cliente),
    FOREIGN KEY(id_cliente)         REFERENCES tab_terceros(id_tercero),
    FOREIGN KEY(id_tipo)         REFERENCES tab_tipo_identidad(id_tipo),
    FOREIGN KEY(id_genero)       REFERENCES tab_genero(id_genero)
);
-------------------------
-- TABLA DE VENDEDORES --
-------------------------
--CUANDO CATEGORÍA DEL TERCERO LO SEA
CREATE TABLE IF NOT EXISTS tab_vendedores
(
	id_vendedor                     VARCHAR(10)                 NOT NULL DEFAULT '0000000000',                                            -- Número de identificación del empleado
    val_porcomision                 DECIMAL(2,0)                NOT NULL CHECK(val_porcomision>=1 AND val_porcomision<=99),               --el porcentaje de la comision que gana el vendedor
    val_ven_acumu                   DECIMAL(15,0)               NOT NULL CHECK(val_ven_acumu>=0 AND val_ven_acumu<=999999999999999),      --El Valor de ventas acomuladas del vendedor
    ind_estado                      BOOLEAN                     NOT NULL DEFAULT TRUE, --TRUE=Activo / FALSE=No activo                    --indicador del estado del vendedor
    ind_borrado                     BOOLEAN                     NOT NULL DEFAULT FALSE, --TRUE: Borrado lógico (Inactivo) / FALSE: Activo --indicador de borrado lógico
	PRIMARY KEY (id_vendedor),
    FOREIGN KEY(id_vendedor)        REFERENCES tab_empleados(id_empleado)
);

-----------------------------------------
-- TABLA DE ENCABEZADO DE COTIZACIONES --
-----------------------------------------
CREATE TABLE IF NOT EXISTS tab_enc_cotizaciones
(
	id_cotizacion                   VARCHAR(10)                 NOT NULL CHECK(LENGTH(TRIM(id_cotizacion))>=8),                             --identificador de la cotizacionss
	id_cliente                      VARCHAR(10)                 NOT NULL CHECK(LENGTH(TRIM(id_cliente)) >=6),           					--identificador del cliente
    id_ciudad                       VARCHAR                     NOT NULL CHECK(LENGTH(id_ciudad)=5),                                        --identificador de la ciudad
	id_vendedor                     VARCHAR(10)                 NOT NULL CHECK(LENGTH(TRIM(id_vendedor)) >=6),          					--identificador del vendedor
	fec_cotizacion                  DATE                        NOT NULL CHECK(fec_cotizacion <= CURRENT_DATE),                             --fecha de la creacion de la cotizacion
	fec_vencimiento                 DATE                        NOT NULL CHECK(fec_vencimiento >= fec_cotizacion),                          --fecha de vencimiento de la cotizacion
    val_total_des                   DECIMAL(10,0)               NOT NULL CHECK(val_total_des <= 9999999999),                                 --total de descuennto  de la cotizacion
    val_total_IVA                   DECIMAL(10,0)               NOT NULL CHECK(val_total_IVA <= 9999999999),                                 --total de IVA de la cotizacion
	val_total                       DECIMAL(10,0)               NOT NULL CHECK(val_total <= 9999999999),                                    --total de la cotizacion
	ind_estado                      BOOLEAN                     NOT NULL DEFAULT TRUE, -- TRUE=Vigente / FALSE=Vencida                      --indicador de estado de la cotizacion
    ind_borrado                     BOOLEAN                     NOT NULL DEFAULT FALSE,--TRUE: Borrado lógico (Inactivo) / FALSE: Activo	--indicador de borrado lógico
    ind_aceptada                    CHAR(1)                      NOT NULL DEFAULT 'P' CHECK(ind_aceptada IN ('P','A','R')), -- 'P' = pendiente / 'A' = aceptada por el cliente / 'R' = rechazada
    ind_facturada                   BOOLEAN                     NOT NULL DEFAULT FALSE,-- TRUE = ya fue convertida a factura. Evita doble facturación
	PRIMARY KEY (id_cotizacion),
	FOREIGN KEY (id_cliente)        REFERENCES tab_clientes(id_cliente),
    FOREIGN KEY (id_vendedor)       REFERENCES tab_vendedores(id_vendedor),
	FOREIGN KEY (id_ciudad)         REFERENCES tab_ciudades(id_ciudad)
);
--------------------------------------
-- TABLA DE DETALLE DE COTIZACIONES --
--------------------------------------
CREATE TABLE IF NOT EXISTS tab_det_cotizaciones
(
    id_cotizacion                   VARCHAR(10)                 NOT NULL CHECK(LENGTH(TRIM(id_cotizacion)) >=8),                      --identificador de la cotizacion
    id_producto                     DECIMAL(3,0)                NOT NULL CHECK(id_producto >=0 AND id_producto <=999),                --identificador del producto 
    val_cantidad                    DECIMAL(4,0)                NOT NULL CHECK(val_cantidad >=0 AND val_cantidad <=9999),             --cantidad de productos cotizados
    val_pordesc                     DECIMAL(3,0)                NOT NULL CHECK(val_pordesc >=0 AND val_pordesc <=100),                --el porcentaje del descuento
	val_descuento		            DECIMAL(10,0)		        NOT NULL CHECK(val_descuento>=0 AND val_descuento<=9999999999),       --valor de decuento de la cotizacion
    val_iva                         DECIMAL(10,0)               NOT NULL CHECK(val_iva <= 9999999999),	                              --valor del impuesto del iva
    val_reteica                     DECIMAL(10,0)               NOT NULL CHECK(val_reteica <= 9999999999),                            --valor de impuesto de retencion ICA
    val_neto                        DECIMAL(10,0)               NOT NULL CHECK(val_neto <= 9999999999),                               --valor neto de la cotizacion
    val_observa                     VARCHAR(255)                NOT NULL DEFAULT 'Sin observaciones',                                 --observaciones de la cotizacion
    val_inc                         DECIMAL(10,0)               NOT NULL DEFAULT 0 CHECK(val_inc >= 0),                               --valor del Impuesto Nacional al Consumo de la línea
    val_retefte                     DECIMAL(10,0)               NOT NULL DEFAULT 0 CHECK(val_retefte >= 0),                           --retención en la fuente sugerida para la línea
    val_reteiva                     DECIMAL(10,0)               NOT NULL DEFAULT 0 CHECK(val_reteiva >= 0),                           --retención de IVA sugerida para la línea
    id_naturaleza                   DECIMAL(4,0)                NOT NULL DEFAULT 1,                                                   --naturaleza tributaria de la línea (FK tab_naturaleza_tributaria)
	PRIMARY KEY(id_cotizacion,id_producto),
    FOREIGN KEY(id_cotizacion)      REFERENCES tab_enc_cotizaciones(id_cotizacion),
    FOREIGN KEY(id_naturaleza)      REFERENCES tab_naturaleza_tributaria(id_naturaleza),
    FOREIGN KEY(id_producto)        REFERENCES tab_productos(id_producto)
);
--------------------------
-- TABLA DE FORMA PAGOS --
--------------------------
CREATE TABLE IF NOT EXISTS tab_forma_pagos
(
	id_formapago                    DECIMAL(4,0)             NOT NULL CHECK(id_formapago >= 0 AND id_formapago <= 9999), --identificador de la forma de pago
	nom_formapago                   VARCHAR                     NOT NULL CHECK(LENGTH(nom_formapago) >= 3),                 --nombre de la forma de pago
    ind_borrado                     BOOLEAN                     NOT NULL DEFAULT FALSE,                                     --TRUE: Borrado lógico (Inactivo) / FALSE: Activo	     --indicador de borrado lógico
	PRIMARY KEY(id_formapago)
);
---------------------------------------
-- TABLA DE RESOLUCIONES DIAN          --
---------------------------------------
-- Resoluciones de numeración autorizadas por la DIAN (prefijo, rango, vigencia, clave técnica y consecutivo). Varias filas.
-- Reemplaza a la numeración que antes vivía en tab_pmtros_facturacion (val_res_aut, val_prefijofac, val_facini/actual/fin).
CREATE TABLE IF NOT EXISTS tab_resoluciones_dian
(
    id_resolucion                   SMALLINT                    GENERATED ALWAYS AS IDENTITY (INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 9999 CACHE 1),
    ind_tipo_numeracion             DECIMAL(1,0)                NOT NULL DEFAULT 1 CHECK(ind_tipo_numeracion IN (1,2)),                   -- 1 = Factura electrónica / 2 = Talonario de contingencia
    val_res_aut                     VARCHAR(14)                 NOT NULL CHECK(val_res_aut ~ '^[0-9]{11,14}$'),                           -- Número de la resolución (11 a 14 dígitos)
    val_prefijo                     VARCHAR(4)                  NOT NULL DEFAULT '' CHECK(val_prefijo ~ '^[A-Z0-9]{0,4}$'),               -- Prefijo (0 a 4 caracteres alfanuméricos en mayúscula)
    val_desde                       DECIMAL(10,0)               NOT NULL CHECK(val_desde >= 1),                                           -- Primer número autorizado
    val_hasta                       DECIMAL(10,0)               NOT NULL,                                                                 -- Último número autorizado
    val_actual                      DECIMAL(10,0)               NOT NULL,                                                                 -- Siguiente número a usar. Si es val_hasta + 1 el rango está agotado
    fec_res_aut                     DATE                        NOT NULL,                                                                 -- Fecha de la resolución
    fec_ini_vig                     DATE                        NOT NULL,                                                                 -- Inicio de vigencia
    fec_fin_vig                     DATE                        NOT NULL,                                                                 -- Fin de vigencia
    val_clave_tecnica               VARCHAR(64)                 NOT NULL DEFAULT '',                                                                     -- Clave técnica (ClTec) de la resolución; se usa en el cálculo del CUFE. Dato sensible
    cod_ambiente                    DECIMAL(1,0)                NOT NULL DEFAULT 2 CHECK(cod_ambiente IN (1,2)),                          -- 1 = Producción / 2 = Habilitación (pruebas ante la DIAN)
    ind_activa                      BOOLEAN                     NOT NULL DEFAULT TRUE,                                                    -- TRUE = en uso
    ind_borrado                     BOOLEAN                     NOT NULL DEFAULT FALSE, --TRUE: Borrado lógico / FALSE: Activo            -- indicador de borrado lógico
    factus_range_id                 INTEGER                     NOT NULL DEFAULT 0 CHECK(factus_range_id >= 0),                                                                     -- ID del rango en Factus (numbering_range_id); se llena con cli/factus_sincronizar_rangos.php
    PRIMARY KEY(id_resolucion),
    CONSTRAINT uq_res_resolucion    UNIQUE(val_res_aut, val_prefijo),
    CONSTRAINT ck_res_rango         CHECK(val_hasta >= val_desde),
    CONSTRAINT ck_res_actual        CHECK(val_actual >= val_desde AND val_actual <= val_hasta + 1),
    CONSTRAINT ck_res_vigencia      CHECK(fec_fin_vig >= fec_ini_vig),
    CONSTRAINT ck_res_clave_tecnica CHECK(NOT (ind_tipo_numeracion = 1 AND ind_activa) OR COALESCE(LENGTH(TRIM(val_clave_tecnica)),0) >= 10)  -- obligatoria para activar una resolución de factura electrónica
);
-- Una sola resolución activa por tipo + prefijo + ambiente
CREATE UNIQUE INDEX IF NOT EXISTS uq_res_activa ON tab_resoluciones_dian(ind_tipo_numeracion, val_prefijo, cod_ambiente) WHERE ind_activa = TRUE AND ind_borrado = FALSE;
------------------------------------
-- TABLA DE ENCABEZADO DE FACTURA --
------------------------------------
CREATE TABLE IF NOT EXISTS tab_enc_facturas
(
	id_factura                      VARCHAR(10)                 NOT NULL CHECK(LENGTH(TRIM(id_factura)) >=8),   	             --identificador de la factura
	id_cliente                      VARCHAR(10)                 NOT NULL CHECK(LENGTH(TRIM(id_cliente)) >=6),                    --identificador del cliente
	id_vendedor                     VARCHAR(10)                 NOT NULL CHECK(LENGTH(TRIM(id_vendedor)) >=6),                   --identificador del vendedor
	fec_factura                     DATE                        NOT NULL CHECK(fec_factura <= CURRENT_DATE),                     --fecha de la creacion de la factura
    id_ciudad                       VARCHAR                     NOT NULL CHECK(LENGTH(id_ciudad)=5),                             --identificador de la ciudad
	id_formapago                    DECIMAL(4,0)                NOT NULL CHECK(id_formapago >= 0 AND id_formapago <= 9999),   --identificador de la forma de pago
    val_total_des                   DECIMAL(10,0)               NOT NULL CHECK(val_total_des <= 9999999999),                     --total de descuennto  de la factura
    val_total_IVA                   DECIMAL(10,0)               NOT NULL CHECK(val_total_IVA <= 9999999999),                     --total de IVA de la factura
	val_total                       DECIMAL(10,0)               NOT NULL CHECK(val_total <= 9999999999),                         --total de la factura
	ind_estado                      BOOLEAN                     NOT NULL DEFAULT TRUE, -- TRUE=Activa / FALSE=Vencida            --indicador de estado de la factura
    ind_cerrada                     BOOLEAN                     NOT NULL DEFAULT FALSE, -- TRUE=impresa / FALSE=Abierta          --indicador de cierre de la factura impresa
    id_resolucion                   SMALLINT                    NOT NULL DEFAULT 0,                                                            --resolución DIAN con la que se numeró (FK tab_resoluciones_dian)
    val_total_inc                   DECIMAL(12,0)               NOT NULL DEFAULT 0 CHECK(val_total_inc >= 0),                    --total del Impuesto Nacional al Consumo
    val_total_retefte               DECIMAL(12,0)               NOT NULL DEFAULT 0 CHECK(val_total_retefte >= 0),                --total retención en la fuente
    val_total_reteiva               DECIMAL(12,0)               NOT NULL DEFAULT 0 CHECK(val_total_reteiva >= 0),                --total retención de IVA
    val_total_reteica               DECIMAL(12,0)               NOT NULL DEFAULT 0 CHECK(val_total_reteica >= 0),                --total retención de ICA
    val_total_pagar                 DECIMAL(12,0)               NOT NULL DEFAULT 0 CHECK(val_total_pagar >= 0),                  --Total factura + IVA + INC - retenciones. Es lo que realmente paga el cliente
    val_puntos                      DECIMAL(10,0)               NOT NULL DEFAULT 0 CHECK(val_puntos >= 0),                       --puntos que la factura sumó al cliente al cerrarse
    ind_origen                      VARCHAR(12)                 NOT NULL DEFAULT 'FACTURACION',                                  --origen: FACTURACION (directa), COTIZACION o PEDIDO
    id_doc_origen                   VARCHAR(15)                 NOT NULL DEFAULT 0,                                              --número de la cotización o del pedido de origen
    val_num_cuotas                  DECIMAL(2,0)                NOT NULL DEFAULT 1,                                              --en cuántas cuotas se paga (1 si es de contado; a crédito lo elige el usuario hasta el máximo de Parámetros)
    CONSTRAINT ck_fac_num_cuotas CHECK(val_num_cuotas >= 1 AND val_num_cuotas <= 24),
    CONSTRAINT ck_fac_origen CHECK(ind_origen IN ('FACTURACION', 'COTIZACION', 'PEDIDO')
                                   AND (ind_origen = 'FACTURACION' OR (id_doc_origen IS NOT NULL AND LENGTH(TRIM(id_doc_origen)) > 0))),
	PRIMARY KEY (id_factura),
	FOREIGN KEY (id_cliente)        REFERENCES tab_clientes(id_cliente),
    FOREIGN KEY (id_ciudad)         REFERENCES tab_ciudades(id_ciudad),
	FOREIGN KEY (id_vendedor)       REFERENCES tab_vendedores(id_vendedor),
	FOREIGN KEY (id_formapago)      REFERENCES tab_forma_pagos(id_formapago),
    FOREIGN KEY (id_resolucion)     REFERENCES tab_resoluciones_dian(id_resolucion)
);
---------------------------------
-- TABLA DE DETALLE DE FACTURA --
---------------------------------
CREATE TABLE IF NOT EXISTS tab_det_facturas
(
    id_factura                      VARCHAR(10)                 NOT NULL CHECK(LENGTH(TRIM(id_factura)) >=8),                    --identificador de la factura
    id_producto                     DECIMAL(3,0)                NOT NULL CHECK(id_producto >=0 AND id_producto <=999),           --identificador del producto 
    val_cantidad                    DECIMAL(4,0)                NOT NULL CHECK(val_cantidad >=0 AND val_cantidad <=9999),        --cantidad de venta del producto
	val_bruto			            DECIMAL(10,0)		        NOT NULL CHECK (val_bruto >=0 AND val_bruto<=9999999999),        --valor bruto de la factura
    por_descuento                   DECIMAL(3,0)                NOT NULL CHECK(por_descuento >=0 AND por_descuento <= 100),      --el porcentaje del descuento de la factura
    val_descuento                   DECIMAL(10,0)               NOT NULL CHECK(val_descuento <= 9999999999),                     --valor descuento de la factura
    val_iva                         DECIMAL(10,0)               NOT NULL CHECK(val_iva >=0 AND val_iva <= 9999999999),	         --valor del impuesto del iva
    val_reica                       DECIMAL(10,0)               NOT NULL CHECK(val_reica >= 0 AND val_reica <= 9999999999),      --valor de impuesto de retencion ICA
    val_neto                        DECIMAL(10,0)               NOT NULL CHECK(val_neto >= 0 AND val_neto <= 9999999999),	     --valor neto de la factura	
    val_observa                     VARCHAR(255)                NOT NULL DEFAULT 'Sin observaciones',                            --observaciones de la factura
    val_base_iva                    DECIMAL(12,0)               NOT NULL DEFAULT 0 CHECK(val_base_iva >= 0),                     --base gravable sobre la que se calculó el IVA
    val_base_inc                    DECIMAL(12,0)               NOT NULL DEFAULT 0 CHECK(val_base_inc >= 0),                     --base gravable del INC (puede diferir de la del IVA)
    val_inc                         DECIMAL(12,0)               NOT NULL DEFAULT 0 CHECK(val_inc >= 0),                          --valor del Impuesto Nacional al Consumo de la línea
    val_retefte                     DECIMAL(12,0)               NOT NULL DEFAULT 0 CHECK(val_retefte >= 0),                      --retención en la fuente sugerida para la línea
    val_reteiva                     DECIMAL(12,0)               NOT NULL DEFAULT 0 CHECK(val_reteiva >= 0),                      --retención de IVA sugerida para la línea (15% del IVA)
    id_naturaleza                   DECIMAL(4,0)                NOT NULL DEFAULT 1,                                              --naturaleza tributaria de la línea (FK tab_naturaleza_tributaria)
    PRIMARY KEY(id_factura,id_producto),
    FOREIGN KEY(id_factura)         REFERENCES tab_enc_facturas(id_factura),
    FOREIGN KEY(id_producto)        REFERENCES tab_productos(id_producto),
    FOREIGN KEY(id_naturaleza)      REFERENCES tab_naturaleza_tributaria(id_naturaleza)
);
---------------------------------
-- TABLA DE FACTURA ELECTRONICA--
---------------------------------
CREATE TABLE IF NOT EXISTS tab_fac_electronicas
(
    id_factura                      VARCHAR(10)                 NOT NULL CHECK(LENGTH(TRIM(id_factura)) >=8),                                    --Identificador de factura
    cufe                            VARCHAR                     NOT NULL DEFAULT '',                                                                     --CUFE; '' mientras Factus/DIAN no validen el documento
    qr_code                         TEXT                        NOT NULL DEFAULT '',                                                                     --Enlace QR de consulta en la DIAN
    xml_firmado                     TEXT                        NOT NULL DEFAULT '',                                                                     --XML firmado (ya no se guarda aquí: lo custodia Factus)
    estado_dian                     VARCHAR(20)                 NOT NULL CHECK(estado_dian IN('pendiente', 'enviando', 'enviado', 'rechazado','aceptado')), --Estado según la DIAN (enviando = reserva en curso; enviado = pendiente de validación)
    fec_envio_dian                  DATE                        NOT NULL CHECK(fec_envio_dian <= CURRENT_DATE),                                  --Fecha de envío de la factura electrónica
    mensaje_dian                    VARCHAR(500)                NOT NULL DEFAULT 'Sin observaciones',                                            --Mensaje de respuesta de la DIAN/Factus
    ref_factus                      VARCHAR(60)                 NOT NULL DEFAULT '',                                                                            --reference_code enviado a Factus (evita duplicados al reintentar)
    factus_number                   VARCHAR(30)                 NOT NULL DEFAULT '',                                                                            --Número legal asignado por Factus (p. ej. SETP990000001)
    public_url                      TEXT                        NOT NULL DEFAULT '',                                                                            --URL pública del documento en Factus
    factus_http                     SMALLINT                    NOT NULL DEFAULT 0,                                                                            --Último código HTTP de Factus
    respuesta                       JSONB                       NOT NULL DEFAULT '{}'::jsonb,                                                                            --Última respuesta completa de Factus
    intentos                        SMALLINT                    NOT NULL DEFAULT 0,                                                              --Número de intentos de envío
    fec_actualiza                   TIMESTAMP                   NOT NULL DEFAULT now(),                                                          --Última actualización del estado
    fec_validacion                  TIMESTAMP                   NOT NULL DEFAULT TIMESTAMP '9999-12-31 00:00:00',                                                                            --Momento en que la DIAN validó el documento
    usuario_envio                   VARCHAR(255)                NOT NULL DEFAULT '',                                                                            --Usuario que envió/reintentó
    PRIMARY KEY(id_factura),
    FOREIGN KEY(id_factura)         REFERENCES tab_enc_facturas(id_factura)
);
------------------------
-- TABLA DE LOS PAGOS --
------------------------
CREATE TABLE IF NOT EXISTS tab_pagos
(
    id_pago          	            DECIMAL(5,0)                 NOT NULL CHECK(id_pago >=0 AND id_pago<=99999), 							--identificador de pago
    id_factura                      VARCHAR(10)                  NOT NULL CHECK(LENGTH(TRIM(id_factura)) >=8),								--identificador de la factura
    fec_pago                        DATE                         NOT NULL CHECK(fec_pago <=CURRENT_DATE),     								--fecha de Realizacion del pago
    val_pagar                       DECIMAL(12,0)                NOT NULL  CHECK(val_pagar >=0 AND val_pagar<=999999999999),				--valor del pago a realizar
    referencia_pago                 VARCHAR                      NOT NULL  CHECK(LENGTH(referencia_pago) <=100),							--referencia de pago	
    ind_est_pag                     VARCHAR                      NOT NULL  CHECK(ind_est_pag IN('APROBADO','RECHAZADO','PENDIENTE')),		--estado de pago
    val_observa       	            VARCHAR                      NOT NULL  DEFAULT 'Sin observaciones',										--observaciones de la factura
    ind_borrado                     BOOLEAN                      NOT NULL  DEFAULT FALSE, --TRUE: Borrado lógico (Inactivo) / FALSE: Activo	--indicador de borrado lógico					
    id_formapago                    DECIMAL(4,0)                 NOT NULL,                                                         --tipo de pago (forma de pago)
    PRIMARY KEY (id_pago),   
    FOREIGN KEY(id_factura)         REFERENCES tab_enc_facturas (id_factura),
    CONSTRAINT fk_pagos_formapago FOREIGN KEY(id_formapago) REFERENCES tab_forma_pagos(id_formapago)
    
);
----------------------
--TABLA DE CARTERAS --
----------------------
-- ESTA TABLA ES PARA LAS FACTURAS QUE SE OBTUVIERON POR MEDIO DE CREDITO
CREATE TABLE IF NOT EXISTS tab_carteras
(
    id_cartera                      DECIMAL(5,0)                NOT NULL CHECK(id_cartera >=0 AND id_cartera <=99999),					     --identificador del credito
    id_factura                      VARCHAR(10)                 NOT NULL CHECK(LENGTH(TRIM(id_factura)) >=8),                                --Identificador de factura
    val_monto                       DECIMAL(12,0)               NOT NULL CHECK(val_monto >=0 AND val_monto <=999999999999),				     --valor de la cuota a pagar
    val_pendiente                   DECIMAL(12,0)               NOT NULL CHECK(val_pendiente >=0),		                                     --saldo pendiente a pagar de la cartera
    fec_ini_pago                    DATE                        NOT NULL,								 --fecha inicial del pago a realizar
    fec_prox_pago                   DATE                        NOT NULL CHECK(fec_prox_pago >= fec_ini_pago),								 --Fecha del proximo pago a realizar
    val_intecorri                   DECIMAL(10,0)               NOT NULL CHECK(val_intecorri>= 0),							                 --valor de intereses de corriente de la cartera
    val_mora                        DECIMAL(10,0)               NOT NULL CHECK(val_mora>=0),							                     --valor de moras de la cartera
    ind_estado                      VARCHAR                     NOT NULL CHECK(ind_estado IN ('Pagada','vencida','pendiente','perdida','recuperada')),    --estado de la cuota: perdida = castigada / recuperada = estaba castigada y el cliente la pagó
    ind_borrado                     BOOLEAN                     NOT NULL DEFAULT FALSE, --TRUE: Borrado lógico (Inactivo) / FALSE: Activo	 --indicador de borrado lógico
    val_num_cuota                   DECIMAL(2,0)                NOT NULL DEFAULT 1,                                                      --número de la cuota dentro de la factura (1 de N)
    fec_liq_mora                    DATE                        NOT NULL,                                                                --hasta qué día se le sumó la mora
    CONSTRAINT ck_carteras_num_cuota CHECK (val_num_cuota >= 1 AND val_num_cuota <= 24),
    CONSTRAINT ck_carteras_liq_mora  CHECK (fec_liq_mora >= fec_prox_pago),
    PRIMARY KEY(id_cartera),
    FOREIGN KEY(id_factura)       REFERENCES tab_enc_facturas(id_factura)
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_carteras_factura_cuota ON tab_carteras (id_factura, val_num_cuota) WHERE ind_borrado = FALSE;
----------------------------------------------
--TABLA DE PAGOS (ABONOS) DE CADA CUOTA      --
----------------------------------------------
-- Relaciona cada pago con la cuota de cartera que abonó. Reemplaza a tab_carteras.id_pago (que era nulo
-- hasta el primer abono y solo guardaba el último): aquí queda el historial completo, sin nulos.
CREATE TABLE IF NOT EXISTS tab_pagos_cartera
(
    id_pago                         DECIMAL(5,0)                NOT NULL,                                   --pago (abono) registrado
    id_cartera                      DECIMAL(5,0)                NOT NULL,                                   --cuota de cartera que se abonó
    val_aplicado                    DECIMAL(12,0)               NOT NULL CHECK(val_aplicado > 0),           --valor del pago aplicado a la cuota
    ind_borrado                     BOOLEAN                     NOT NULL DEFAULT FALSE,                     --TRUE: Borrado lógico (Inactivo) / FALSE: Activo
    val_pag_mora                    DECIMAL(12,0)               NOT NULL DEFAULT 0,                         --parte del abono que pagó mora
    val_pag_interes                 DECIMAL(12,0)               NOT NULL DEFAULT 0,                         --parte del abono que pagó interés corriente
    val_pag_capital                 DECIMAL(12,0)               NOT NULL DEFAULT 0,                         --parte del abono que pagó capital
    val_saldo_ant                   DECIMAL(12,0)               NOT NULL DEFAULT 0,                         --saldo de la cuota antes del abono (0 = abono anterior a la V.2.4)
    val_saldo_nuevo                 DECIMAL(12,0)               NOT NULL DEFAULT 0,                         --saldo de la cuota después del abono
    CONSTRAINT ck_pagos_cartera_partes CHECK (val_pag_mora >= 0 AND val_pag_interes >= 0 AND val_pag_capital >= 0
                                              AND val_pag_mora + val_pag_interes + val_pag_capital = val_aplicado),
    CONSTRAINT ck_pagos_cartera_saldos CHECK (val_saldo_ant >= 0 AND val_saldo_nuevo >= 0),
    PRIMARY KEY(id_pago, id_cartera),
    FOREIGN KEY(id_pago)          REFERENCES tab_pagos(id_pago),
    FOREIGN KEY(id_cartera)       REFERENCES tab_carteras(id_cartera)
);
CREATE INDEX IF NOT EXISTS ix_pagos_cartera_cuota ON tab_pagos_cartera (id_cartera);

--------------------------------------------------------------
-- V.2.1  GESTIÓN DE COBRO Y CASTIGO DE CARTERA CON APROBACIÓN --
--------------------------------------------------------------
-- Gestiones de cobro: constancia de cada intento de cobro sobre una cuota de cartera
CREATE TABLE IF NOT EXISTS tab_gestiones_cobro
(
    id_gestion      DECIMAL(10,0)   NOT NULL CHECK(id_gestion > 0),                             -- Consecutivo de la gestión
    id_cartera      DECIMAL(5,0)    NOT NULL,                                                   -- Cuota de cartera gestionada
    id_usuario      VARCHAR         NOT NULL,                                                   -- Usuario que hizo la gestión
    fec_gestion     TIMESTAMP       NOT NULL DEFAULT now(),                                     -- Momento de la gestión
    ind_tipo        CHAR(1)         NOT NULL CHECK(ind_tipo IN ('L','C','W','V','T')),          -- L llamada / C correo / W WhatsApp / V visita / T carta
    ind_resultado   CHAR(1)         NOT NULL CHECK(ind_resultado IN ('N','P','A','R')),         -- N no contesta / P promesa de pago / A acuerdo de pago / R se niega a pagar
    val_observa     VARCHAR(500)    NOT NULL CHECK(LENGTH(TRIM(val_observa)) >= 5),             -- Qué se habló o qué pasó
    ind_borrado     BOOLEAN         NOT NULL DEFAULT FALSE,                                     -- TRUE: Borrado lógico / FALSE: Activo
    PRIMARY KEY(id_gestion),
    FOREIGN KEY(id_cartera) REFERENCES tab_carteras(id_cartera),
    FOREIGN KEY(id_usuario) REFERENCES tab_usuarios(id_usuario)
);
CREATE INDEX IF NOT EXISTS ix_gestiones_cuota ON tab_gestiones_cobro (id_cartera);

-- Promesa o acuerdo de pago que salió de una gestión (solo las gestiones con resultado P o A tienen fila aquí)
CREATE TABLE IF NOT EXISTS tab_promesas_pago
(
    id_gestion      DECIMAL(10,0)   NOT NULL,                                                   -- Gestión en la que el cliente prometió
    fec_promesa     DATE            NOT NULL,                                                   -- Fecha en que prometió pagar
    val_promesa     DECIMAL(12,0)   NOT NULL CHECK(val_promesa > 0),                            -- Valor que prometió pagar
    ind_estado      CHAR(1)         NOT NULL DEFAULT 'P' CHECK(ind_estado IN ('P','C','I')),    -- P pendiente / C cumplida / I incumplida
    PRIMARY KEY(id_gestion),
    FOREIGN KEY(id_gestion) REFERENCES tab_gestiones_cobro(id_gestion)
);
CREATE INDEX IF NOT EXISTS ix_promesas_pendientes ON tab_promesas_pago (fec_promesa) WHERE ind_estado = 'P';

-- Solicitud de castigo: quién pide castigar y por qué
CREATE TABLE IF NOT EXISTS tab_solicitudes_castigo
(
    id_solicitud        DECIMAL(10,0)   NOT NULL CHECK(id_solicitud > 0),                       -- Consecutivo de la solicitud
    id_usuario_solicita VARCHAR         NOT NULL,                                               -- Usuario que solicita el castigo
    fec_solicitud       TIMESTAMP       NOT NULL DEFAULT now(),                                 -- Momento de la solicitud
    val_motivo          VARCHAR(500)    NOT NULL CHECK(LENGTH(TRIM(val_motivo)) >= 10),         -- Motivo del castigo (obligatorio)
    ind_estado          CHAR(1)         NOT NULL DEFAULT 'S' CHECK(ind_estado IN ('S','A','R')),-- S solicitada / A aprobada / R rechazada
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                 -- TRUE: Borrado lógico / FALSE: Activo
    PRIMARY KEY(id_solicitud),
    FOREIGN KEY(id_usuario_solicita) REFERENCES tab_usuarios(id_usuario)
);

-- Cuotas incluidas en cada solicitud, con el saldo que se pide castigar
CREATE TABLE IF NOT EXISTS tab_det_solicitud_castigo
(
    id_solicitud    DECIMAL(10,0)   NOT NULL,                                                   -- Solicitud
    id_cartera      DECIMAL(5,0)    NOT NULL,                                                   -- Cuota de cartera a castigar
    val_castigado   DECIMAL(12,0)   NOT NULL CHECK(val_castigado > 0),                          -- Saldo pendiente de la cuota al solicitar
    PRIMARY KEY(id_solicitud, id_cartera),
    FOREIGN KEY(id_solicitud) REFERENCES tab_solicitudes_castigo(id_solicitud),
    FOREIGN KEY(id_cartera)   REFERENCES tab_carteras(id_cartera)
);
CREATE INDEX IF NOT EXISTS ix_det_sol_castigo_cuota ON tab_det_solicitud_castigo (id_cartera);

----------------------------------------------------------------
-- V.2.3  DESPUÉS DEL CASTIGO: RECUPERACIÓN Y BLOQUEO DE CRÉDITO --
----------------------------------------------------------------
-- Recuperaciones: pagos que entran sobre una cuota ya castigada. Van aparte de tab_pagos_cartera porque
--    no son cobro de cartera activa: contablemente son un ingreso por recuperación.
CREATE TABLE IF NOT EXISTS tab_recuperaciones_cartera
(
    id_pago         DECIMAL(5,0)    NOT NULL,                              -- Pago con el que el cliente recuperó
    id_cartera      DECIMAL(5,0)    NOT NULL,                              -- Cuota castigada que se recupera
    id_usuario      VARCHAR         NOT NULL,                              -- Usuario que registró la recuperación
    val_recuperado  DECIMAL(12,0)   NOT NULL CHECK(val_recuperado > 0),    -- Valor recuperado con este pago
    ind_borrado     BOOLEAN         NOT NULL DEFAULT FALSE,                -- TRUE: Borrado lógico / FALSE: Activo
    val_saldo_ant   DECIMAL(12,0)   NOT NULL DEFAULT 0,                    -- Saldo castigado antes de esta recuperación
    val_saldo_nuevo DECIMAL(12,0)   NOT NULL DEFAULT 0,                    -- Saldo castigado después de esta recuperación
    val_rec_mora    DECIMAL(12,0)   NOT NULL DEFAULT 0,                    -- V.2.6: parte de la recuperación que pagó mora
    val_rec_interes DECIMAL(12,0)   NOT NULL DEFAULT 0,                    -- V.2.6: parte que pagó interés corriente
    val_rec_capital DECIMAL(12,0)   NOT NULL DEFAULT 0,                    -- V.2.6: parte que pagó capital
    CONSTRAINT ck_recuperaciones_saldos CHECK (val_saldo_ant >= 0 AND val_saldo_nuevo >= 0),
    CONSTRAINT ck_recuperaciones_partes CHECK (val_rec_mora >= 0 AND val_rec_interes >= 0 AND val_rec_capital >= 0
                                               AND val_rec_mora + val_rec_interes + val_rec_capital = val_recuperado),
    PRIMARY KEY(id_pago),
    FOREIGN KEY(id_pago)    REFERENCES tab_pagos(id_pago),
    FOREIGN KEY(id_cartera) REFERENCES tab_carteras(id_cartera),
    FOREIGN KEY(id_usuario) REFERENCES tab_usuarios(id_usuario)
);
CREATE INDEX IF NOT EXISTS ix_recuperaciones_cuota ON tab_recuperaciones_cartera (id_cartera);

----------------------------------------------------------------
-- V.2.6  ACUERDOS DE PAGO SOBRE CARTERA CASTIGADA                --
----------------------------------------------------------------
-- Acuerdo de pago: el cliente se compromete a pagar una parte de lo que debe de una cuota castigada antes
-- de una fecha límite, y la empresa le perdona (condona) el resto. Quien hace el acuerdo escribe cuánto se
-- perdona de mora, de interés corriente y de capital. Lo crea solo un jefe de área o un administrador.
--   V vigente / C cumplido (pagó lo acordado: se aplica el perdón y la cuota queda recuperada en $0)
--   I incumplido (pasó la fecha límite sin completar: no hay perdón) / A anulado (sin pagos, por error).
CREATE TABLE IF NOT EXISTS tab_acuerdos_pago
(
    id_acuerdo          DECIMAL(10,0)   NOT NULL CHECK(id_acuerdo > 0),                         -- Consecutivo del acuerdo
    id_cartera          DECIMAL(5,0)    NOT NULL,                                               -- Cuota castigada que se negocia
    id_usuario          VARCHAR         NOT NULL,                                               -- Jefe de área o administrador que lo hace
    fec_acuerdo         TIMESTAMP       NOT NULL DEFAULT now(),                                 -- Momento del acuerdo
    fec_limite          DATE            NOT NULL,                                               -- Último día para pagar lo acordado
    val_saldo_ant       DECIMAL(12,0)   NOT NULL CHECK(val_saldo_ant > 0),                      -- Saldo castigado al hacer el acuerdo
    val_mora_ant        DECIMAL(12,0)   NOT NULL DEFAULT 0 CHECK(val_mora_ant >= 0),            -- De ese saldo: mora
    val_interes_ant     DECIMAL(12,0)   NOT NULL DEFAULT 0 CHECK(val_interes_ant >= 0),         -- De ese saldo: interés corriente
    val_capital_ant     DECIMAL(12,0)   NOT NULL DEFAULT 0 CHECK(val_capital_ant >= 0),         -- De ese saldo: capital
    val_condona_mora    DECIMAL(12,0)   NOT NULL DEFAULT 0 CHECK(val_condona_mora >= 0),        -- Mora que se perdona
    val_condona_interes DECIMAL(12,0)   NOT NULL DEFAULT 0 CHECK(val_condona_interes >= 0),     -- Interés corriente que se perdona
    val_condona_capital DECIMAL(12,0)   NOT NULL DEFAULT 0 CHECK(val_condona_capital >= 0),     -- Capital que se perdona (quita)
    val_acordado        DECIMAL(12,0)   NOT NULL CHECK(val_acordado > 0),                       -- Lo que el cliente debe pagar
    val_recaudado       DECIMAL(12,0)   NOT NULL DEFAULT 0,                                     -- Lo que ha pagado dentro del acuerdo
    val_observa         VARCHAR(500)    NOT NULL CHECK(LENGTH(TRIM(val_observa)) >= 10),        -- Qué se negoció y con quién (soporte)
    ind_estado          CHAR(1)         NOT NULL DEFAULT 'V' CHECK(ind_estado IN ('V','C','I','A')), -- V vigente / C cumplido / I incumplido / A anulado
    fec_cierre          DATE            NOT NULL DEFAULT '9999-12-31',                          -- Día en que se cumplió, incumplió o anuló (9999-12-31 = sigue vigente)
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                 -- TRUE: Borrado lógico / FALSE: Activo
    CONSTRAINT ck_acuerdos_desglose CHECK (val_mora_ant + val_interes_ant + val_capital_ant = val_saldo_ant),
    CONSTRAINT ck_acuerdos_condona  CHECK (val_condona_mora <= val_mora_ant AND val_condona_interes <= val_interes_ant
                                           AND val_condona_capital <= val_capital_ant),
    CONSTRAINT ck_acuerdos_acordado CHECK (val_acordado = val_saldo_ant - val_condona_mora - val_condona_interes - val_condona_capital),
    CONSTRAINT ck_acuerdos_recaudado CHECK (val_recaudado >= 0 AND val_recaudado <= val_acordado),
    CONSTRAINT ck_acuerdos_fechas   CHECK (fec_limite >= CAST(fec_acuerdo AS DATE)),
    PRIMARY KEY(id_acuerdo),
    FOREIGN KEY(id_cartera) REFERENCES tab_carteras(id_cartera),
    FOREIGN KEY(id_usuario) REFERENCES tab_usuarios(id_usuario)
);
-- Una cuota tiene a lo sumo un acuerdo vigente
CREATE UNIQUE INDEX IF NOT EXISTS ux_acuerdos_vigente ON tab_acuerdos_pago (id_cartera) WHERE ind_estado = 'V' AND ind_borrado = FALSE;
CREATE INDEX IF NOT EXISTS ix_acuerdos_cuota ON tab_acuerdos_pago (id_cartera);

-- Pagos hechos dentro de cada acuerdo (cada recuperación pertenece a lo sumo a un acuerdo)
CREATE TABLE IF NOT EXISTS tab_acuerdos_recuperaciones
(
    id_pago             DECIMAL(5,0)    NOT NULL,                                               -- Recuperación (pago)
    id_acuerdo          DECIMAL(10,0)   NOT NULL,                                               -- Acuerdo en el que se pagó
    PRIMARY KEY(id_pago),
    FOREIGN KEY(id_pago)    REFERENCES tab_recuperaciones_cartera(id_pago),
    FOREIGN KEY(id_acuerdo) REFERENCES tab_acuerdos_pago(id_acuerdo)
);
CREATE INDEX IF NOT EXISTS ix_acuerdos_rec_acuerdo ON tab_acuerdos_recuperaciones (id_acuerdo);

-- Autorizaciones de crédito: un cliente con cartera castigada queda bloqueado para facturar a crédito.
--    Un jefe de área o administrador puede autorizarlo por un tiempo, dejando el motivo.
CREATE TABLE IF NOT EXISTS tab_autorizaciones_credito
(
    id_autorizacion     DECIMAL(10,0)   NOT NULL CHECK(id_autorizacion > 0),                    -- Consecutivo
    id_cliente          VARCHAR(10)     NOT NULL,                                               -- Cliente autorizado
    id_usuario_autoriza VARCHAR         NOT NULL,                                               -- Jefe de área o administrador que autoriza
    fec_autorizacion    TIMESTAMP       NOT NULL DEFAULT now(),                                 -- Momento de la autorización
    fec_vence           DATE            NOT NULL,                                               -- Último día en que vale la autorización
    val_motivo          VARCHAR(500)    NOT NULL CHECK(LENGTH(TRIM(val_motivo)) >= 10),         -- Por qué se autoriza
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                 -- TRUE: revocada / FALSE: activa
    PRIMARY KEY(id_autorizacion),
    FOREIGN KEY(id_cliente)          REFERENCES tab_clientes(id_cliente),
    FOREIGN KEY(id_usuario_autoriza) REFERENCES tab_usuarios(id_usuario)
);
CREATE INDEX IF NOT EXISTS ix_autorizaciones_cliente ON tab_autorizaciones_credito (id_cliente);

----------------------------------------------------------------
-- V.2.2  EDADES DE CARTERA Y PORCENTAJE DE PROVISIÓN           --
----------------------------------------------------------------
-- Rangos de días de mora y qué porcentaje del saldo se provisiona en cada uno. No trae datos:
-- cada empresa registra los suyos (Cartera por Tiempo > Configurar rangos).
CREATE TABLE IF NOT EXISTS tab_edades_cartera
(
    id_edad             DECIMAL(3,0)    NOT NULL CHECK(id_edad > 0),                                        -- Consecutivo del rango
    val_dias_desde      DECIMAL(4,0)    NOT NULL CHECK(val_dias_desde >= 0 AND val_dias_desde <= 9999),     -- Días de mora desde (incluido)
    val_dias_hasta      DECIMAL(4,0)    NOT NULL CHECK(val_dias_hasta >= val_dias_desde AND val_dias_hasta <= 9999),  -- Días de mora hasta (incluido). 9999 = en adelante
    val_por_provision   DECIMAL(5,2)    NOT NULL DEFAULT 0 CHECK(val_por_provision >= 0 AND val_por_provision <= 100), -- % del saldo que se provisiona en este rango
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                             -- TRUE: Borrado lógico / FALSE: Activo
    PRIMARY KEY(id_edad)
);

-- Respuesta a la solicitud: quién aprobó o rechazó (solo existe cuando ya se respondió; así no hay aprobador nulo)
CREATE TABLE IF NOT EXISTS tab_respuestas_castigo
(
    id_solicitud        DECIMAL(10,0)   NOT NULL,                                               -- Solicitud respondida
    id_usuario_responde VARCHAR         NOT NULL,                                               -- Jefe de área o administrador que respondió
    fec_respuesta       TIMESTAMP       NOT NULL DEFAULT now(),                                 -- Momento de la respuesta
    ind_decision        CHAR(1)         NOT NULL CHECK(ind_decision IN ('A','R')),              -- A aprobada / R rechazada
    val_observa         VARCHAR(500)    NOT NULL DEFAULT '',                                    -- Observación (obligatoria al rechazar)
    PRIMARY KEY(id_solicitud),
    FOREIGN KEY(id_solicitud)        REFERENCES tab_solicitudes_castigo(id_solicitud),
    FOREIGN KEY(id_usuario_responde) REFERENCES tab_usuarios(id_usuario)
);

-- =============================================================================
-- CATÁLOGO DE MOTIVOS DIAN
-- =============================================================================
CREATE TABLE IF NOT EXISTS tab_motivo_nota
(
    id_motivo_nota      DECIMAL(3,0)    NOT NULL CHECK(id_motivo_nota > 0),                     -- Identificador del motivo de la nota
    ind_tipo_nota       BOOLEAN         NOT NULL DEFAULT FALSE, -- FALSE: CREDITO / TRUE:DEBITO --INDICADOR DE TIPO DE NOTA
    cod_dian            DECIMAL(1,0)    NOT NULL CHECK(cod_dian >= 1 AND cod_dian <= 6),        -- NC: códigos 1-6 | ND: códigos 1-3 (Res. 000042)
    nom_motivo          VARCHAR(100)    NOT NULL CHECK(LENGTH(TRIM(nom_motivo)) >= 5),          -- Descripción del motivo de la nota (Ej: "Devolución total por incumplimiento de pago")
    afecta_inventario   BOOLEAN         NOT NULL DEFAULT FALSE,                                 -- TRUE: La nota afecta inventario  / FALSE: No afecta inventario
    afecta_cliente      BOOLEAN         NOT NULL DEFAULT TRUE,                                  -- TRUE: La nota afecta tercero / FALSE: No afecta tercero 
    afecta_cartera      BOOLEAN         NOT NULL DEFAULT TRUE,                                  -- Solo afecta cartera en caso de que el motivo sea por incumplimiento de pago o por corrección de datos (cod_dian = 3 o 4)
    afecta_comision     BOOLEAN         NOT NULL DEFAULT FALSE,                                 -- Solo afecta comisión en caso de que el motivo sea por devolución total o parcial (cod_dian = 1 o 2)
    ind_estado          BOOLEAN         NOT NULL DEFAULT TRUE,                                  -- Solo los motivos activos pueden ser usados en la creación de notas
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                 -- TRUE: Borrado lógico (Inactivo) / FALSE: Activo
    PRIMARY KEY(id_motivo_nota)  
);
-- =============================================================================
    -- ENCABEZADO DE LA NOTA
-- =============================================================================
CREATE TABLE IF NOT EXISTS tab_enc_notas
(
    id_nota             DECIMAL(10,0)   NOT NULL CHECK(id_nota > 0),                                                                                                    -- Identificador único de la nota de crédito o débito
    ind_tipo_nota       BOOLEAN         NOT NULL DEFAULT FALSE, -- FALSE: CREDITO / TRUE:DEBITO                                                                         --INDICADOR DE TIPO DE NOTA                                                                                         -- Relación con el tipo de nota (1=NC, 2=ND)
    id_motivo_nota      DECIMAL(3,0)    NOT NULL CHECK(id_motivo_nota > 0),                                                                                             -- Relación con el motivo de la nota (ver tabla tab_motivo_nota)                                                                                                                      --identificador de la empresa
    id_cliente          VARCHAR(10)     NOT NULL CHECK(LENGTH(TRIM(id_cliente)) >= 6),                                                                                  -- Relación con el cliente al que se le emite la nota 
    id_vendedor         VARCHAR(10)     NOT NULL CHECK(LENGTH(TRIM(id_vendedor)) >= 6),                                                              -- Relación con el vendedor asociado a la nota. Puede ser NULL si no se desea asociar un vendedor.
    id_factura_ref      VARCHAR(10)     NOT NULL CHECK(LENGTH(TRIM(id_factura_ref)) >= 8),                                                                              -- Relación con la factura a la que se refiere la nota. Se asume que toda nota hace referencia a una factura, aunque en algunos casos podría no ser obligatorio.
    cufe_ref            VARCHAR(96)     NOT NULL,                                                                                                                       -- CUFE de la factura referenciada (SHA-384, 96 chars)
    prefijo_nota        VARCHAR(4)      NOT NULL CHECK(LENGTH(TRIM(prefijo_nota)) >= 1),                                                                                -- 'NC' o 'ND'
    num_nota            DECIMAL(10,0)   NOT NULL CHECK(num_nota > 0),                                                                                                   -- Número consecutivo de la nota por empresa y tipo de nota 
    fec_emi_nota        DATE            NOT NULL CHECK(fec_emi_nota <= CURRENT_DATE),                                                                                   --   Fecha de emisión de la nota 
    fec_ven_nota        DATE            NOT NULL CHECK(fec_ven_nota >= fec_emi_nota),                                                                                   -- En NC = fec_emi_nota; en ND puede ser posterior
    val_subtotal        DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK(val_subtotal >= 0),                                                                                    -- Valor subtotal de la nota                                     
    val_descuento       DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK(val_descuento >= 0),                                                                                   -- Valor total de descuentos aplicados en la nota 
    val_iva             DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK(val_iva >= 0),                                                                                         -- Valor total de IVA aplicado en la nota 
    val_total           DECIMAL(15,0)   NOT NULL CHECK(val_total >= 0),                                                                                                 -- Valor total de la nota . En NC este valor es el que se le descuenta al cliente, en ND es el que se le suma.
    val_aplicado        DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK(val_aplicado >= 0),                                                                                    -- Valor total aplicado de la nota a facturas o cartera . En NC este valor se va descontando del val_total a medida que se aplica la nota, en ND se va sumando al val_total.
    val_pendiente       DECIMAL(15,0)   NOT NULL           CHECK(val_pendiente >= 0),                                                                                   -- Valor pendiente por aplicar de la nota a facturas o cartera . En NC este valor se va descontando del val_total a medida que se aplica la nota, en ND se va sumando al val_total.
    observacion         VARCHAR(255)    NOT NULL DEFAULT 'Sin observaciones',                                                                                           -- Observaciones generales de la nota
     ind_estado          VARCHAR(20)    NOT NULL CHECK(ind_estado IN ( 'BORRADOR', 'EMITIDA', 'ENVIADA_DIAN', 'ACEPTADA_DIAN', 'RECHAZADA_DIAN', 'ANULADA' )),          -- Indicador del estado de la nota en su ciclo de vida
    ind_borrado         BOOLEAN         NOT NULL DEFAULT FALSE,                                                                                                         -- TRUE: Borrado lógico (Inactivo) / FALSE: Activo
    PRIMARY KEY(id_nota),
    FOREIGN KEY(id_motivo_nota) REFERENCES tab_motivo_nota(id_motivo_nota),
    FOREIGN KEY(id_cliente)     REFERENCES tab_clientes(id_cliente),
    FOREIGN KEY(id_vendedor)    REFERENCES tab_vendedores(id_vendedor),
    FOREIGN KEY(id_factura_ref) REFERENCES tab_enc_facturas(id_factura),
    UNIQUE( prefijo_nota, num_nota)
);
CREATE INDEX IF NOT EXISTS idx_enc_notas_factura_ref ON tab_enc_notas(id_factura_ref);
CREATE INDEX IF NOT EXISTS idx_enc_notas_cliente_fecha ON tab_enc_notas(id_cliente, fec_emi_nota);
CREATE INDEX IF NOT EXISTS idx_enc_notas_estado ON tab_enc_notas(ind_estado) WHERE ind_borrado = FALSE;
-- =============================================================================
--  – DETALLE DE NOTA 
-- =============================================================================
CREATE TABLE IF NOT EXISTS tab_det_notas
(
    id_nota             DECIMAL(10,0)   NOT NULL CHECK(id_nota > 0 ),                                                        -- identificador de la nota al que se relaciona el detalle 
    id_producto         DECIMAL(3,0)    NOT NULL CHECK(id_producto >= 0 AND id_producto <= 999),                            -- identificador del producto o servicio de la línea de detalle
    val_cantidad        DECIMAL(4,0)    NOT NULL CHECK(val_cantidad > 0 AND val_cantidad <= 9999),                          -- cantidad de producto o servicio de la línea de detalle
    val_precio_unit     DECIMAL(15,0)   NOT NULL CHECK(val_precio_unit >= 0),                                               -- valor del precio unitario del producto o servicio de la línea de detalle
    por_descuento       DECIMAL(3,0)    NOT NULL DEFAULT 0 CHECK(por_descuento >= 0 AND por_descuento <= 100),              -- porcentaje de descuento aplicado en la línea de detalle (en caso de que el descuento sea proporcional al porcentaje, sino se puede calcular a partir del val_descuento)
    val_descuento       DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK(val_descuento >= 0 AND val_descuento <=999999999999999),   --   valor del descuento aplicado en la línea de detalle
    val_iva             DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK(val_iva >= 0 AND val_iva <=999999999999999),               -- valor del IVA aplicado en la línea de detalle   
    val_neto            DECIMAL(15,0)   NOT NULL CHECK(val_neto >= 0 AND val_neto <=999999999999999),                       -- valor neto
    val_inc             DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK(val_inc >= 0),                                                  -- Valor del INC de la línea
    val_retefte         DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK(val_retefte >= 0),                                              -- Retención en la fuente de la línea
    val_reteiva         DECIMAL(15,0)   NOT NULL DEFAULT 0 CHECK(val_reteiva >= 0),                                              -- Retención de IVA de la línea
    id_naturaleza       DECIMAL(4,0)    NOT NULL DEFAULT 1,                                                                      -- Naturaleza tributaria de la línea (FK tab_naturaleza_tributaria)
    PRIMARY KEY(id_nota, id_producto),
    FOREIGN KEY(id_nota) REFERENCES tab_enc_notas(id_nota),
    FOREIGN KEY(id_producto) REFERENCES tab_productos(id_producto),
    FOREIGN KEY(id_naturaleza) REFERENCES tab_naturaleza_tributaria(id_naturaleza)
);
 -- =============================================================================
-- TRANSMISIÓN ELECTRÓNICA DIAN (CUDE, XML, QR)
-- =============================================================================
CREATE TABLE IF NOT EXISTS tab_nota_elect
(
    id_nota             DECIMAL(10,0)   NOT NULL CHECK(id_nota > 0),                                                        -- Relación con la nota
    cude                VARCHAR(96)     NOT NULL DEFAULT '',                                                                        -- CUDE; '' mientras Factus/DIAN no validen el documento
    xml_firmado         TEXT            NOT NULL DEFAULT '',                                                                        -- XML firmado (lo custodia Factus)
    qr_code             TEXT            NOT NULL DEFAULT '',                                                                        -- Enlace QR de consulta en la DIAN
    estado_dian         VARCHAR(20)     NOT NULL CHECK(estado_dian IN ('pendiente','enviando','enviado','rechazado','aceptado')), -- Estado según la DIAN
    fec_envio_dian      DATE            NOT NULL DEFAULT CURRENT_DATE CHECK(fec_envio_dian <= CURRENT_DATE),                -- Fecha de envío
    mensaje_dian        VARCHAR(500)    NOT NULL DEFAULT 'SIN MENSAJE',                                                     -- Mensaje de respuesta de la DIAN/Factus
    ref_factus          VARCHAR(60)     NOT NULL DEFAULT '',                                                                               -- reference_code enviado a Factus (NC-<id> / ND-<id>)
    factus_number       VARCHAR(30)     NOT NULL DEFAULT '',                                                                               -- Número legal asignado por Factus
    public_url          TEXT            NOT NULL DEFAULT '',                                                                               -- URL pública del documento en Factus
    factus_http         SMALLINT        NOT NULL DEFAULT 0,                                                                               -- Último código HTTP de Factus
    respuesta           JSONB           NOT NULL DEFAULT '{}'::jsonb,                                                                               -- Última respuesta completa de Factus
    intentos            SMALLINT        NOT NULL DEFAULT 0,                                                                 -- Número de intentos de envío
    fec_actualiza       TIMESTAMP       NOT NULL DEFAULT now(),                                                             -- Última actualización del estado
    fec_validacion      TIMESTAMP       NOT NULL DEFAULT TIMESTAMP '9999-12-31 00:00:00',                                                                               -- Momento en que la DIAN validó el documento
    usuario_envio       VARCHAR(255)    NOT NULL DEFAULT '',                                                                               -- Usuario que envió/reintentó
    PRIMARY KEY(id_nota),
    FOREIGN KEY(id_nota) REFERENCES tab_enc_notas(id_nota)
);
  
-- =============================================================================
-- APLICACIÓN DE NOTAS A FACTURAS O CARTERA
-- =============================================================================
-- V.2.0: antes era UNA tabla (tab_aplicacion_nota) con id_factura e id_cartera, y una de las dos siempre quedaba
-- en NULL. Ahora hay una tabla por destino, cada una con su llave foránea obligatoria.
CREATE TABLE IF NOT EXISTS tab_aplicacion_nota_factura
(
    id_aplicacion           DECIMAL(10,0)   NOT NULL CHECK(id_aplicacion > 0),              -- Identificador de la aplicación (consecutivo único entre las dos tablas)
    id_nota                 DECIMAL(10,0)   NOT NULL CHECK(id_nota > 0),                    -- Nota crédito cuyo saldo se aplica
    id_factura              VARCHAR(10)     NOT NULL CHECK(LENGTH(TRIM(id_factura)) >= 8),    -- Factura a la que se aplica el saldo
    valor_aplicado          DECIMAL(15,0)   NOT NULL CHECK(valor_aplicado > 0),             -- Valor de la nota que se aplica
    saldo_anterior_nota     DECIMAL(15,0)   NOT NULL CHECK(saldo_anterior_nota >= 0),       -- Saldo de la nota antes de aplicar
    saldo_despues_nota      DECIMAL(15,0)   NOT NULL CHECK(saldo_despues_nota >= 0),        -- Saldo de la nota después de aplicar
    fec_aplicacion          DATE            NOT NULL DEFAULT CURRENT_DATE,                  -- Fecha de la aplicación
    observacion             VARCHAR(250)    NOT NULL DEFAULT 'Sin observaciones',           -- Observaciones de esta aplicación
    ind_borrado             BOOLEAN         NOT NULL DEFAULT FALSE,                         -- TRUE: Borrado lógico (Inactivo) / FALSE: Activo

    PRIMARY KEY(id_aplicacion),
    FOREIGN KEY(id_nota) REFERENCES tab_enc_notas(id_nota),
    FOREIGN KEY(id_factura) REFERENCES tab_enc_facturas(id_factura)
);

CREATE TABLE IF NOT EXISTS tab_aplicacion_nota_cartera
(
    id_aplicacion           DECIMAL(10,0)   NOT NULL CHECK(id_aplicacion > 0),              -- Identificador de la aplicación (consecutivo único entre las dos tablas)
    id_nota                 DECIMAL(10,0)   NOT NULL CHECK(id_nota > 0),                    -- Nota crédito cuyo saldo se aplica
    id_cartera              DECIMAL(5,0)    NOT NULL CHECK(id_cartera >= 0 AND id_cartera <= 99999),  -- Cuota de cartera a la que se aplica el saldo
    valor_aplicado          DECIMAL(15,0)   NOT NULL CHECK(valor_aplicado > 0),             -- Valor de la nota que se aplica
    saldo_anterior_nota     DECIMAL(15,0)   NOT NULL CHECK(saldo_anterior_nota >= 0),       -- Saldo de la nota antes de aplicar
    saldo_despues_nota      DECIMAL(15,0)   NOT NULL CHECK(saldo_despues_nota >= 0),        -- Saldo de la nota después de aplicar
    fec_aplicacion          DATE            NOT NULL DEFAULT CURRENT_DATE,                  -- Fecha de la aplicación
    observacion             VARCHAR(250)    NOT NULL DEFAULT 'Sin observaciones',           -- Observaciones de esta aplicación
    ind_borrado             BOOLEAN         NOT NULL DEFAULT FALSE,                         -- TRUE: Borrado lógico (Inactivo) / FALSE: Activo

    PRIMARY KEY(id_aplicacion),
    FOREIGN KEY(id_nota) REFERENCES tab_enc_notas(id_nota),
    FOREIGN KEY(id_cartera) REFERENCES tab_carteras(id_cartera)
);

-- cufe / cude / qr: únicos solo cuando ya tienen dato ('' = aún sin respuesta de la DIAN)
CREATE UNIQUE INDEX IF NOT EXISTS ux_fac_elect_cufe  ON tab_fac_electronicas (cufe)         WHERE cufe    <> '';
CREATE UNIQUE INDEX IF NOT EXISTS ux_fac_elect_qr    ON tab_fac_electronicas (md5(qr_code)) WHERE qr_code <> '';
CREATE UNIQUE INDEX IF NOT EXISTS ux_nota_elect_cude ON tab_nota_elect (cude)               WHERE cude    <> '';
CREATE UNIQUE INDEX IF NOT EXISTS ux_nota_elect_qr   ON tab_nota_elect (md5(qr_code))       WHERE qr_code <> '';
---------------------------------------------------
-- HOMOLOGACIONES ERP -> CÓDIGOS FACTUS / DIAN     --
---------------------------------------------------
-- grupo: tipo_identidad (id_tipo -> código DIAN) | forma_pago_form (id_formapago -> 1 contado | 2 crédito)
--        forma_pago_metodo (id_formapago -> método de pago DIAN; 10 = efectivo, 42 = consignación, 48/49 = tarjeta)
CREATE TABLE IF NOT EXISTS tab_factus_mapeo
(
    grupo                           VARCHAR(30)                 NOT NULL CHECK(grupo IN ('tipo_identidad','forma_pago_form','forma_pago_metodo')),
    clave                           VARCHAR(30)                 NOT NULL,                                                         -- código del ERP
    valor_factus                    VARCHAR(30)                 NOT NULL,                                                         -- código que entiende Factus/DIAN
    nota                            VARCHAR(120)                NOT NULL DEFAULT '',
    PRIMARY KEY(grupo, clave)
);
INSERT INTO tab_factus_mapeo (grupo, clave, valor_factus, nota) VALUES
('tipo_identidad','RC','11','Registro civil'), ('tipo_identidad','TI','12','Tarjeta de identidad'),
('tipo_identidad','CC','13','Cédula de ciudadanía'), ('tipo_identidad','TE','21','Tarjeta de extranjería'),
('tipo_identidad','CE','22','Cédula de extranjería'), ('tipo_identidad','NIT','31','NIT'),
('tipo_identidad','PA','41','Pasaporte'), ('tipo_identidad','PEP','47','PEP');

----------------------------------------------
-- MÓDULO DE ANALISIS FINANCIERO
----------------------------------------------
-- *************************************
-- ** TABLA DE PARÁMETROS FINANCIEROS **
-- *************************************
CREATE TABLE IF NOT EXISTS tab_pmtros_financieros (
    id_pmtro_financiero     VARCHAR        NOT NULL           CHECK (LENGTH(TRIM(id_pmtro_financiero)) BETWEEN 1 AND 20), -- Identificador del parámetro financiero
    id_empresa              VARCHAR(20)    NOT NULL DEFAULT '899999034',                                                  -- Identificador de la empresa (multi-tenancy)
    inventario              DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (inventario >= 0),                                    -- Valor total de existencias disponibles
    efectivo                DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (efectivo >= 0),                                      -- Dinero en caja y bancos
    equiv_efectivo          DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (equiv_efectivo >= 0),                                -- Inversiones de alta liquidez equivalentes al efectivo
    activos_totales         DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (activos_totales >= 0),                               -- Suma de activos corrientes y no corrientes
    pasivos_corrientes      DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (pasivos_corrientes >= 0),                            -- Obligaciones a corto plazo de la empresa
    pasivo_financiero       DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (pasivo_financiero >= 0),                             -- Deudas financieras con terceros
    pasivos_totales         DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (pasivos_totales >= 0),                               -- Suma de pasivos corrientes y no corrientes
    patrimonio              DECIMAL(18,2)  NOT NULL DEFAULT 0,                                                            -- Valor neto patrimonial (permite negativo por pérdidas acumuladas)
    ventas                  DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (ventas >= 0),                                        -- Ingresos por ventas netas
    costo_de_ventas         DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (costo_de_ventas >= 0),                               -- Costos directos de producción o ventas
    utilidad_operativa      DECIMAL(18,2)  NOT NULL DEFAULT 0,                                                            -- Beneficio/pérdida operativa (permite negativos)
    interes                 DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (interes >= 0),                                       -- Gastos por intereses financieros
    utilidad_neta           DECIMAL(18,2)  NOT NULL DEFAULT 0,                                                            -- Resultado neto después de impuestos (permite pérdidas)
    depreciacion            DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (depreciacion >= 0),                                  -- Depreciación acumulada del periodo
    amortizacion            DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (amortizacion >= 0),                                  -- Amortización contable del periodo
    gastos_administrativos  DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (gastos_administrativos >= 0),                        -- Gastos indirectos administrativos
    gastos_ventas           DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (gastos_ventas >= 0),                                 -- Gastos indirectos de comercialización y ventas
    impuestos               DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (impuestos >= 0),                                     -- Obligaciones fiscales del periodo
    cxc_promedio            DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (cxc_promedio >= 0),                                  -- Saldo/promedio de cuentas por cobrar
    ventas_credito          DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (ventas_credito >= 0),                                -- Ventas realizadas a crédito en el periodo
    inv_promedio            DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (inv_promedio >= 0),                                  -- Promedio de inventario del periodo
    compras_credito         DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (compras_credito >= 0),                               -- Compras realizadas a crédito en el periodo
    cxp_promedio            DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (cxp_promedio >= 0),                                  -- Saldo/promedio de cuentas por pagar
    capital_invertido       DECIMAL(18,2)  NOT NULL DEFAULT 0 CHECK (capital_invertido >= 0),                             -- Capital invertido en la empresa
    ind_borrado             BOOLEAN        NOT NULL DEFAULT FALSE,                                                        -- TRUE: Borrado lógico / FALSE: Activo
    PRIMARY KEY (id_pmtro_financiero)
);

-- *************************
-- ** TABLA DE INVERSORES **
-- *************************
CREATE TABLE IF NOT EXISTS tab_inversores (
    id_inversor           VARCHAR(10)   NOT NULL CHECK (id_inversor ~ '^[A-Z0-9]{7,10}$'),                                                     -- Identificación del inversor (= id_tercero)
    id_ciudad             VARCHAR(5)    NOT NULL CHECK (LENGTH(TRIM(id_ciudad)) = 5),                                                           -- Identificación de la ciudad
    nom_inversor          VARCHAR(60)   NOT NULL CHECK (LENGTH(TRIM(nom_inversor)) BETWEEN 5 AND 60),                                           -- Nombre del inversor
    tipo_inversor         BOOLEAN       NOT NULL,                                                                                               -- TRUE = Natural / FALSE = Jurídico
    tel_inversor          DECIMAL(10,0) NOT NULL CHECK (tel_inversor >= 0),                                                                     -- Teléfono del inversor
    email_inversor        VARCHAR(120)  NOT NULL CHECK (LENGTH(TRIM(email_inversor)) BETWEEN 5 AND 120 AND email_inversor LIKE '%@%.%'),          -- Correo electrónico del inversor
    estado_inversor       VARCHAR(20)   NOT NULL CHECK (estado_inversor IN ('ACTIVO','INACTIVO','SUSPENDIDO')),                                -- Estado del inversor
    dir_inversor          VARCHAR(254)  NOT NULL CHECK (LENGTH(TRIM(dir_inversor)) BETWEEN 1 AND 254),                                          -- Dirección del inversor
    id_empresa            VARCHAR(20)   NOT NULL DEFAULT '899999034',                                                                           -- Identificador de la empresa (multi-tenancy)
    ind_borrado           BOOLEAN       NOT NULL DEFAULT FALSE,                                                                                 -- TRUE: Borrado lógico / FALSE: Activo
    id_tipo               VARCHAR(5),                                                                                                           -- Tipo de documento (tab_tipo_identidad)
    id_banco              VARCHAR,                                                                                                              -- Banco de la cuenta de destino (tab_bancos)
    ind_tipocuenta        BOOLEAN       NOT NULL DEFAULT FALSE,                                                                                 -- TRUE = Corriente / FALSE = Ahorros
    num_cuenta            VARCHAR(20)   CHECK (num_cuenta IS NULL OR num_cuenta ~ '^[0-9]{6,20}$'),                                             -- Cuenta de destino (solo dígitos, entre 6 y 20)
    id_prefijo_movil      DECIMAL(4,0)  DEFAULT 57,                                                                                             -- Prefijo telefónico móvil (tab_tel_prefijo)
    PRIMARY KEY (id_inversor),
    FOREIGN KEY (id_ciudad)        REFERENCES tab_ciudades(id_ciudad),
    FOREIGN KEY (id_inversor)      REFERENCES tab_terceros(id_tercero),
    FOREIGN KEY (id_tipo)          REFERENCES tab_tipo_identidad(id_tipo),
    FOREIGN KEY (id_banco)         REFERENCES tab_bancos(id_banco),
    FOREIGN KEY (id_prefijo_movil) REFERENCES tab_tel_prefijo(id_prefijo)
);

-- ************************
-- ** TABLA DE PROYECTOS **
-- ************************
CREATE TABLE IF NOT EXISTS tab_proyectos (
    id_proyecto           VARCHAR       NOT NULL CHECK (LENGTH(TRIM(id_proyecto)) BETWEEN 1 AND 10),                                            -- Identificador del proyecto
    nom_proyecto          VARCHAR       NOT NULL CHECK (LENGTH(TRIM(nom_proyecto)) BETWEEN 1 AND 254),                                          -- Nombre del proyecto
    alcance_proyecto      TEXT          NOT NULL CHECK (LENGTH(TRIM(alcance_proyecto)) > 0),                                                    -- Alcance del proyecto
    costo_proyecto        DECIMAL(18,2) NOT NULL CHECK (costo_proyecto > 0),                                                                    -- Costo del proyecto
    fec_inicio            DATE          NOT NULL CHECK (fec_inicio >= '2025-01-01'),                                                            -- Fecha de inicio del proyecto
    fec_fin               DATE          NOT NULL CHECK (fec_fin > fec_inicio),                                                                  -- Fecha de finalización del proyecto
    resp_proyecto         VARCHAR       NOT NULL CHECK (LENGTH(TRIM(resp_proyecto)) BETWEEN 5 AND 60),                                          -- Responsable del proyecto
    estado_proyecto       VARCHAR       NOT NULL CHECK (estado_proyecto IN ('ACTIVO','SUSPENDIDO','CANCELADO','COMPLETADO')),                    -- Estado del proyecto
    id_empresa            VARCHAR(20)   NOT NULL DEFAULT '899999034',                                                                           -- Identificador de la empresa (multi-tenancy)
    ind_borrado           BOOLEAN       NOT NULL DEFAULT FALSE,                                                                                 -- TRUE: Borrado lógico / FALSE: Activo
    PRIMARY KEY (id_proyecto)
);

-- **************************
-- ** TABLA DE INDICADORES **
-- **************************
CREATE TABLE IF NOT EXISTS tab_indicadores (
    id_ind                VARCHAR       NOT NULL CHECK (LENGTH(TRIM(id_ind)) BETWEEN 1 AND 50),                                                 -- Identificador del indicador
    nom_ind               TEXT          NOT NULL CHECK (LENGTH(TRIM(nom_ind)) > 0),                                                             -- Nombre del indicador
    tip_ind               VARCHAR       NOT NULL CHECK (tip_ind IN ('Rentabilidad','Liquidez','Endeudamiento','Rotación')),                      -- Tipo de indicador
    uni_medicion          VARCHAR       NOT NULL CHECK (LENGTH(TRIM(uni_medicion)) BETWEEN 1 AND 20),                                           -- Unidad de medición del indicador
    fuente_ind            VARCHAR       NOT NULL CHECK (LENGTH(TRIM(fuente_ind)) BETWEEN 1 AND 255),                                            -- Fuente de información para el cálculo
    variable_ind          VARCHAR       NOT NULL CHECK (LENGTH(TRIM(variable_ind)) BETWEEN 1 AND 255),                                          -- Variables del indicador
    formula               VARCHAR       NOT NULL CHECK (LENGTH(TRIM(formula)) BETWEEN 1 AND 255),                                               -- Fórmula para calcular el indicador
    semaforo_ind          VARCHAR       NOT NULL CHECK (LENGTH(TRIM(semaforo_ind)) > 0),                                                        -- Descripción del semáforo del indicador
    frecu_ind             VARCHAR       NOT NULL CHECK (frecu_ind IN ('DIARIO','SEMANAL','MENSUAL','ANUAL')),                                  -- Frecuencia de cálculo
    tole_ind              DECIMAL(18,4) NOT NULL CHECK (tole_ind >= 0),                                                                         -- Tolerancia para el semáforo
    sentido_ind           VARCHAR(10)   NOT NULL DEFAULT 'ASC' CHECK (sentido_ind IN ('ASC', 'DESC')),                                          -- Sentido direccional: ASC (mayor mejor) / DESC (menor mejor)
    umbral_optimo         DECIMAL(18,4) NOT NULL DEFAULT 10.0000,                                                                               -- Umbral óptimo del semáforo
    umbral_critico        DECIMAL(18,4) NOT NULL DEFAULT 0.0000,                                                                                -- Umbral crítico del semáforo
    ultimo_calculo        TIMESTAMP     CHECK (ultimo_calculo IS NULL OR ultimo_calculo <= CURRENT_TIMESTAMP),                                  -- Fecha del último cálculo
    responsable_calculo   VARCHAR       NOT NULL CHECK (LENGTH(TRIM(responsable_calculo)) BETWEEN 5 AND 60),                                    -- Responsable del cálculo del indicador
    id_empresa            VARCHAR(20)   NOT NULL DEFAULT '899999034',                                                                           -- Identificador de la empresa (multi-tenancy)
    ind_borrado           BOOLEAN       NOT NULL DEFAULT FALSE,                                                                                 -- TRUE: Borrado lógico / FALSE: Activo
    PRIMARY KEY (id_ind)
);

-- **********************************
-- ** TABLA DE VALOR DEL INDICADOR **
-- **********************************
CREATE TABLE IF NOT EXISTS tab_val_ind (
    id_ind                VARCHAR       NOT NULL CHECK (LENGTH(TRIM(id_ind)) BETWEEN 1 AND 50),                                                 -- Identificador del indicador
    fec_calculo           DATE          NOT NULL,                                                                                               -- Fecha del cálculo del indicador
    id_pmtro_financiero   VARCHAR       NOT NULL CHECK (LENGTH(TRIM(id_pmtro_financiero)) BETWEEN 1 AND 20),                                    -- Identificador del parámetro financiero
    val_calculado         DECIMAL(18,4) NOT NULL,                                                                                               -- Valor calculado del indicador (permite negativos en rentabilidad)
    id_empresa            VARCHAR(20)   NOT NULL DEFAULT '899999034',                                                                           -- Identificador de la empresa (multi-tenancy)
    ind_borrado           BOOLEAN       NOT NULL DEFAULT FALSE,                                                                                 -- TRUE: Borrado lógico / FALSE: Activo
    PRIMARY KEY (id_ind, id_pmtro_financiero),
    FOREIGN KEY (id_pmtro_financiero) REFERENCES tab_pmtros_financieros(id_pmtro_financiero),
    FOREIGN KEY (id_ind)              REFERENCES tab_indicadores(id_ind)
);

-- ********************************
-- **    TABLA DE INVERSIONES    **
-- ********************************
CREATE TABLE IF NOT EXISTS tab_inversiones (
    id_proyecto           VARCHAR       NOT NULL CHECK (LENGTH(TRIM(id_proyecto)) BETWEEN 1 AND 10),                                            -- Identificador del proyecto
    id_inversor           VARCHAR(10)   NOT NULL CHECK (id_inversor ~ '^[A-Z0-9]{7,10}$'),                                                     -- Identificación del inversor
    val_participacion     DECIMAL(5,2)  NOT NULL CHECK (val_participacion > 0 AND val_participacion <= 100),                                    -- Porcentaje de participación del inversor
    entidad_financiera    VARCHAR       NOT NULL CHECK (LENGTH(TRIM(entidad_financiera)) BETWEEN 2 AND 100),                                    -- Entidad financiera
    monto_inversion       DECIMAL(18,2) NOT NULL CHECK (monto_inversion > 0),                                                                   -- Monto de la inversión
    tasa_interes          DECIMAL(5,2)  NOT NULL CHECK (tasa_interes BETWEEN 0 AND 100),                                                        -- Tasa de interés nominal
    tasa_efectividad      DECIMAL(5,2)  NOT NULL CHECK (tasa_efectividad BETWEEN 0 AND 100 AND tasa_efectividad >= tasa_interes),               -- Tasa efectiva anual (E.A.)
    fecha_inicio          DATE          NOT NULL CHECK (fecha_inicio >= '2025-01-01'),                                                          -- Fecha de inicio
    fecha_vencimiento     DATE          NOT NULL CHECK (fecha_vencimiento > fecha_inicio),                                                      -- Fecha de vencimiento
    estado_inversion      VARCHAR       NOT NULL CHECK (estado_inversion IN ('VIGENTE','VENCIDA','RENOVADA','CANCELADA','LIQUIDADA')),         -- Estado de la inversión
    id_empresa            VARCHAR(20)   NOT NULL DEFAULT '899999034',                                                                           -- Identificador de la empresa (multi-tenancy)
    ind_borrado           BOOLEAN       NOT NULL DEFAULT FALSE,                                                                                 -- TRUE: Borrado lógico / FALSE: Activo
    modalidad_pago        DECIMAL(1,0)  NOT NULL DEFAULT 2 CHECK (modalidad_pago IN (1, 2)),                                                    -- 1 = intereses mensuales / 2 = pago único al vencimiento
    por_retencion         DECIMAL(5,2)  NOT NULL DEFAULT 7.00 CHECK (por_retencion BETWEEN 0 AND 100),                                          -- % de retención en la fuente sobre los intereses
    fec_aporte            DATE,                                                                                                                 -- Fecha en que entró el aporte (NULL = sin confirmar)
    PRIMARY KEY (id_proyecto, id_inversor),
    FOREIGN KEY (id_proyecto) REFERENCES tab_proyectos(id_proyecto),
    FOREIGN KEY (id_inversor) REFERENCES tab_inversores(id_inversor)
);

-- ***************************************
-- ** TABLA DE CUOTAS DE LA INVERSIÓN   **
-- ***************************************
CREATE TABLE IF NOT EXISTS tab_cuotas_inversion (
    id_proyecto           VARCHAR       NOT NULL,                                                                                               -- Proyecto de la inversión
    id_inversor           VARCHAR(10)   NOT NULL,                                                                                               -- Inversor de la inversión
    id_cuota              DECIMAL(3,0)  NOT NULL CHECK (id_cuota >= 1 AND id_cuota <= 999),                                                     -- Número de la cuota
    fec_vencimiento       DATE          NOT NULL,                                                                                               -- Día desde el que se puede pagar
    val_capital           DECIMAL(18,0) NOT NULL DEFAULT 0 CHECK (val_capital   >= 0),                                                          -- Capital que se devuelve en esta cuota
    val_interes           DECIMAL(18,0) NOT NULL DEFAULT 0 CHECK (val_interes   >= 0),                                                          -- Interés bruto de la cuota
    val_retencion         DECIMAL(18,0) NOT NULL DEFAULT 0 CHECK (val_retencion >= 0),                                                          -- Retención en la fuente sobre el interés
    val_neto              DECIMAL(18,0) NOT NULL CHECK (val_neto > 0 AND val_neto = val_capital + val_interes - val_retencion),                 -- Valor a girar al inversor
    ind_aprobada          BOOLEAN       NOT NULL DEFAULT FALSE CHECK (ind_aprobada = FALSE OR (id_usuario_aprueba IS NOT NULL AND fec_aprobacion IS NOT NULL)), -- TRUE = aprobada para pago
    id_usuario_aprueba    VARCHAR,                                                                                                              -- Quién la aprobó
    fec_aprobacion        DATE,                                                                                                                 -- Cuándo la aprobó
    estado_pago           DECIMAL(1,0)  NOT NULL DEFAULT 0 CHECK (estado_pago IN (0, 1, 2, 3)),                                                 -- 0 sin enviar, 1 enviada, 2 pagada, 3 rechazada
    fec_pago              DATE,                                                                                                                 -- Fecha en que el banco pagó (NULL si no está pagada)
    id_archivo_plano      DECIMAL(10,0),                                                                                                        -- Último archivo plano de Tesorería en el que fue (informativo)
    id_empresa            VARCHAR(20)   NOT NULL DEFAULT '899999034',                                                                           -- Identificador de la empresa (multi-tenancy)
    PRIMARY KEY (id_proyecto, id_inversor, id_cuota),
    FOREIGN KEY (id_proyecto, id_inversor) REFERENCES tab_inversiones(id_proyecto, id_inversor)
);
-- ------------
-- 2. ÍNDICES 
-- ------------
CREATE INDEX IF NOT EXISTS idx_pmtros_fin_empresa_borrado ON tab_pmtros_financieros (id_empresa, ind_borrado, id_pmtro_financiero DESC);
CREATE INDEX IF NOT EXISTS idx_indicadores_tipo_borrado   ON tab_indicadores (id_empresa, ind_borrado, tip_ind);
CREATE INDEX IF NOT EXISTS idx_val_ind_periodo_borrado    ON tab_val_ind (id_pmtro_financiero, ind_borrado, fec_calculo DESC);
CREATE INDEX IF NOT EXISTS idx_inversiones_proy_estado    ON tab_inversiones (id_proyecto, ind_borrado, estado_inversion);
CREATE INDEX IF NOT EXISTS idx_proyectos_estado_borrado   ON tab_proyectos (id_empresa, ind_borrado, estado_proyecto);
CREATE INDEX IF NOT EXISTS idx_inversores_estado_borrado  ON tab_inversores (id_empresa, ind_borrado, estado_inversor);
CREATE INDEX IF NOT EXISTS idx_cuotas_inv_estado          ON tab_cuotas_inversion (estado_pago, ind_aprobada);   -- "cuotas aprobadas pendientes de enviar"
CREATE INDEX IF NOT EXISTS idx_cuotas_inv_vencimiento     ON tab_cuotas_inversion (fec_vencimiento);             -- "cuotas que vencen esta semana"

--------------------------------------
-- MÓDULO DE GESTION DE CALIDAD
--------------------------------------

--------------------------------------------------------------------------------------------------------
-- TABLA: tab_tipo_documento
-- Clasifica los documentos segun su naturaleza juridica o administrativa.
-- Permite aplicar politicas de retencion documental especificas por tipo de documento
-- y define los plazos de respuesta estandar segun la normativa legal (Ley 594 de 2000).
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_tipo_documento
(
    id_tipo              DECIMAL(3,0)               NOT NULL CHECK (id_tipo BETWEEN 1 AND 100),                        -- Identificador numerico unico (1 a 100). Clave primaria.
    nom_tipo             VARCHAR                    NOT NULL CHECK (char_length(trim(nom_tipo)) BETWEEN 3 AND 20),     -- Nombre: FACTURA, CONTRATO, CERTIFICADO, ACTA, OFICIO.
    cod_tipo             VARCHAR                    NOT NULL CHECK (cod_tipo ~ '^[A-Z0-9]{2,10}$'),                    -- Codigo alfanumerico corto (solo mayusculas y numeros). Ej: FAC01, CON02.
    dias_respuesta       DECIMAL(2,0)               NOT NULL CHECK (dias_respuesta BETWEEN 1 AND 99) DEFAULT 15,       -- Dias estandar de respuesta (1-99). Por defecto 15.
    id_festivo           DECIMAL(4,0)               NOT NULL CHECK (id_festivo >= 0 AND id_festivo <= 99) DEFAULT 0,   -- FK al calendario de festivos. Define si se cuentan dias naturales o habiles.
    ind_publico          BOOLEAN                    NOT NULL DEFAULT TRUE,                                             -- Indicador para saber si el archivo es visible para todos o no.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                            -- Borrado logico: TRUE = eliminado, FALSE = activo.
    PRIMARY KEY (id_tipo),
    FOREIGN KEY (id_festivo) REFERENCES tab_festivos(id_festivo)
);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_tabla_retencion
-- Define las politicas de conservacion, archivo y disposicion final de los documentos
-- segun la Ley General de Archivos (Ley 594 de 2000).
-- Establece cuantos años debe permanecer un documento en el archivo de gestion (oficina),
-- cuantos en el archivo central (bodega) y que hacer al final del ciclo
-- (conservar para siempre, eliminar o seleccionar).
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_tabla_retencion
(
    id_retencion          DECIMAL(5,0)              NOT NULL CHECK (id_retencion BETWEEN 1 AND 9999),                                              -- Identificador unico de la politica (1 a 9,999). Clave primaria.
    id_tipo               DECIMAL(3,0)              NOT NULL CHECK (id_tipo BETWEEN 1 AND 100),                                                    -- FK al tipo de documento asociado.
    nom_serie             VARCHAR                   NOT NULL CHECK (char_length(trim(nom_serie)) BETWEEN 3 AND 150),                               -- Serie documental. Ej: "Gestion de Personal".
    nom_subserie          VARCHAR                   NOT NULL CHECK (char_length(trim(nom_subserie)) BETWEEN 1 AND 150) DEFAULT 'SIN_SUBSERIE',     -- Subserie. Ej: "Hojas de Vida".
    anos_archivo_gestion  DECIMAL(3,0)              NOT NULL CHECK (anos_archivo_gestion BETWEEN 1 AND 10) DEFAULT 2,                              -- Años en archivo de gestion (1-10). Por defecto 2.
    anos_archivo_central  DECIMAL(3,0)              NOT NULL CHECK (anos_archivo_central BETWEEN 1 AND 30) DEFAULT 8,                              -- Años en archivo central (1-30). Por defecto 8.
    disposicion_final     VARCHAR                   NOT NULL CHECK (disposicion_final IN ('CONSERVACION_TOTAL','ELIMINACION','SELECCION')),        -- Accion final: conservar, eliminar o seleccionar.
    soporte_fisico        BOOLEAN                   NOT NULL DEFAULT FALSE,                                                                        -- ¿Se conserva en formato fisico? Por defecto FALSE.
    soporte_electronico   BOOLEAN                   NOT NULL DEFAULT TRUE,                                                                         -- ¿Se conserva en formato digital? Por defecto TRUE.
    ind_borrado           BOOLEAN                   NOT NULL DEFAULT FALSE,                                                                        -- Borrado logico.
    PRIMARY KEY (id_retencion),
    CONSTRAINT chk_soporte_valido CHECK ((soporte_fisico = TRUE AND soporte_electronico = FALSE) OR (soporte_fisico = FALSE AND soporte_electronico = TRUE)),
    FOREIGN KEY (id_tipo) REFERENCES tab_tipo_documento(id_tipo)
);
-- Indices para optimizar consultas por tipo de documento.
CREATE INDEX idx_trd_tipo ON tab_tabla_retencion(id_tipo);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_estado_correspondencia
-- Define las etapas del ciclo de vida por las que pasa una comunicacion.
-- Permite el seguimiento y control de las comunicaciones, sabiendo en todo momento
-- si estan radicadas, asignadas, en proceso, respondidas, cerradas, anuladas o vencidas.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_estado_correspondencia
(
    id_estado            DECIMAL(2,0)               NOT NULL CHECK (id_estado BETWEEN 1 AND 20),                           -- Identificador unico (1 a 20). Clave primaria.
    val_estado           VARCHAR                    NOT NULL CHECK (char_length(trim(val_estado)) BETWEEN 3 AND 15),       -- Estado: RADICADO, ASIGNADO, EN_PROCESO, RESPONDIDO, CERRADO, ANULADO, VENCIDO.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- Borrado logico.
    PRIMARY KEY (id_estado)
);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_accion_workflow
-- Catalogo de acciones del Workflow de calidad y de la bitacora de procesos.
-- id_area NULL = accion general (aplica a todas las areas). ind_sistema = la usa el sistema en la
-- bitacora: no se puede renombrar, cambiar de area ni inactivar.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_accion_workflow
(
    id_accion            DECIMAL(2,0)               NOT NULL CHECK (id_accion BETWEEN 1 AND 99),                           -- Identificador unico de la accion (1 a 99). Clave primaria.
    nom_accion           VARCHAR                    NOT NULL CHECK (char_length(trim(nom_accion)) BETWEEN 3 AND 15),       -- Nombre / codigo de la accion. Ej: REVISAR, EVALUAR_IA.
    id_area              DECIMAL(5,0)                        CHECK (id_area > 0),                                          -- Area que la ejecuta. NULL = accion general.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- Borrado logico.
    ind_sistema          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- TRUE = accion protegida del sistema (bitacora).
    PRIMARY KEY (id_accion),
    FOREIGN KEY (id_area) REFERENCES tab_areas(id_area)
);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_correspondencia
-- Es la tabla principal que registra cada comunicacion recibida por la organizacion.
-- Almacena la informacion basica de cada correspondencia: numero de radicado (unico),
-- remitente, asunto, fechas, estado, tipo de documento, origen, nivel de acceso,
-- politica de retencion, area destino y tercero asociado.
-- Sigue el Acuerdo 001 de 2024 del AGN para el formato del numero de radicado (14 digitos).
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_correspondencia
(
    id_correspondencia   VARCHAR                    NOT NULL CHECK (id_correspondencia ~ '^[0-9]{14}$'),                                  -- Identificador unico interno. 14 digitos numericos. Clave primaria.
    num_radicado         VARCHAR                    NOT NULL CHECK (num_radicado ~ '^[0-9]{14}$'),                                        -- Numero de radicado oficial. 14 digitos. Unico.
    id_tipo              DECIMAL(3,0)               NOT NULL CHECK (id_tipo BETWEEN 1 AND 100),                                           -- FK al tipo de documento. Define la naturaleza del documento.
    id_canal             DECIMAL(2,0)               NOT NULL CHECK (id_canal > 0 AND id_canal <= 99),                                     -- FK al canal de entrada.
    id_estado            DECIMAL(2,0)               NOT NULL CHECK (id_estado BETWEEN 1 AND 20),                                          -- FK al estado actual. Define la etapa del ciclo de vida.
    ind_publico          BOOLEAN                    NOT NULL DEFAULT TRUE,                                                                -- Indicador para saber si el archivo es visible para todos o no.
    id_retencion         DECIMAL(5,0)               NOT NULL CHECK (id_retencion BETWEEN 1 AND 9999),                                     -- FK a politica de retencion. Define su ciclo de vida.
    nom_remitente        VARCHAR                    NOT NULL CHECK (char_length(trim(nom_remitente)) BETWEEN 3 AND 255),                  -- Nombre del remitente.
    ent_remitente        VARCHAR                    NOT NULL CHECK (char_length(trim(ent_remitente)) BETWEEN 1 AND 255) DEFAULT 'NO_APLICA', -- Entidad del remitente.
    asunto               TEXT                       NOT NULL CHECK (char_length(trim(asunto)) BETWEEN 5 AND 500) DEFAULT 'SIN_ASUNTO',    -- Asunto o descripcion breve.
    fec_documento        DATE                       NOT NULL CHECK (fec_documento <= CURRENT_DATE),                                       -- Fecha del documento original. No puede ser futura.
    fec_recepcion        TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                               -- Fecha y hora de recepcion. Por defecto now().
    id_festivo           DECIMAL(4,0)               NOT NULL CHECK (id_festivo >= 0 AND id_festivo <= 99) DEFAULT 0,                      -- FK al calendario de festivos. Define si se cuentan dias naturales o habiles.
    ind_fisico           BOOLEAN                    NOT NULL DEFAULT FALSE,                                                               -- ¿Existe version fisica? Por defecto FALSE.
    id_area_destino      DECIMAL(5,0)               NOT NULL CHECK (id_area_destino > 0),                                                 -- FK al area destino. Define a quien se dirige.
    id_tercero           VARCHAR                    NOT NULL CHECK (id_tercero ~ '^[A-Z0-9]{7,10}$'),                                     -- FK al tercero remitente (misma regla de tab_terceros).
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                               -- Borrado logico.
    id_usuario_radica    VARCHAR                             CHECK (char_length(trim(id_usuario_radica)) >= 5),                           -- FK al usuario que radico (lo marca fun_marcar_radicador_correspondencia).
    PRIMARY KEY (id_correspondencia),
    CONSTRAINT uq_enc_corr_radicado UNIQUE (num_radicado),
    FOREIGN KEY (id_tipo)          REFERENCES tab_tipo_documento(id_tipo),
    FOREIGN KEY (id_canal)         REFERENCES tab_canales(id_canal),
    FOREIGN KEY (id_estado)        REFERENCES tab_estado_correspondencia(id_estado),
    FOREIGN KEY (id_retencion)     REFERENCES tab_tabla_retencion(id_retencion),
    FOREIGN KEY (id_festivo)       REFERENCES tab_festivos(id_festivo),
    FOREIGN KEY (id_area_destino)  REFERENCES tab_areas(id_area),
    FOREIGN KEY (id_tercero)       REFERENCES tab_terceros(id_tercero),
    FOREIGN KEY (id_usuario_radica) REFERENCES tab_usuarios(id_usuario)
);
-- Indices para optimizar consultas por estado, area, fecha de recepcion, numero de radicado y radicador.
CREATE INDEX idx_enc_corr_estado    ON tab_correspondencia(id_estado);
CREATE INDEX idx_enc_corr_area      ON tab_correspondencia(id_area_destino);
CREATE INDEX idx_enc_corr_recepcion ON tab_correspondencia(fec_recepcion);
CREATE INDEX idx_enc_corr_radicado  ON tab_correspondencia(num_radicado);
CREATE INDEX idx_corr_usuario_radica ON tab_correspondencia(id_usuario_radica);
--------------------------------------------------------------------------------------------------------
-- SECUENCIAS DE CORRESPONDENCIA Y EXPEDIENTES
-- seq_consecutivo_radicado: numero de radicado de correspondencia.
-- seq_indexacion:           registros de indexacion.
-- seq_expediente:           consecutivo de expedientes (EXP-AAAAMMDD-NNN).
-- seq_anexo_correspondencia: reservada para anexos de correspondencia.
--------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS seq_consecutivo_radicado  START WITH 1 INCREMENT BY 1 NO CYCLE;
CREATE SEQUENCE IF NOT EXISTS seq_indexacion            START WITH 1 INCREMENT BY 1 NO CYCLE;
CREATE SEQUENCE IF NOT EXISTS seq_expediente            START WITH 1 INCREMENT BY 1 NO CYCLE;
CREATE SEQUENCE IF NOT EXISTS seq_anexo_correspondencia START WITH 1 INCREMENT BY 1 NO CYCLE;
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_indexacion
-- Palabras clave de cada correspondencia para el buscador documental.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_indexacion
(
    id_indexacion        DECIMAL(10,0)              NOT NULL DEFAULT nextval('seq_indexacion'),                            -- Identificador unico. Secuencia seq_indexacion. Clave primaria.
    id_correspondencia   VARCHAR                    NOT NULL CHECK (id_correspondencia ~ '^[0-9]{14}$'),                   -- FK a la correspondencia padre.
    palabras_clave       VARCHAR                    NOT NULL DEFAULT 'SIN_PALABRAS_CLAVES' CHECK (char_length(palabras_clave) <= 500), -- Palabras clave para busqueda. Ej: "contrato,2024".
    id_tipo              DECIMAL(3,0)               NOT NULL CHECK (id_tipo BETWEEN 1 AND 100),                            -- FK al tipo de documento principal.
    fec_indexacion       TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                -- Fecha y hora de indexacion. Por defecto now().
    id_indexador         VARCHAR                    NOT NULL CHECK (id_indexador ~ '^[A-Z0-9]{7,10}$'),                    -- FK al tercero que indexa (misma regla de tab_terceros).
    ind_publico          BOOLEAN                    NOT NULL DEFAULT TRUE,                                                 -- ¿Visible en busquedas publicas?
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- Borrado logico.
    PRIMARY KEY (id_indexacion),
    FOREIGN KEY (id_correspondencia) REFERENCES tab_correspondencia(id_correspondencia),
    FOREIGN KEY (id_tipo)            REFERENCES tab_tipo_documento(id_tipo),
    FOREIGN KEY (id_indexador)       REFERENCES tab_terceros(id_tercero)
);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_expediente
-- Agrupa y organiza la correspondencia y los documentos relacionados en expedientes digitales.
-- Permite crear carpetas virtuales que reunen todas las comunicaciones relacionadas
-- con un mismo proceso, caso, cliente o proyecto. Sigue el Acuerdo 001 de 2024 del AGN.
-- Utiliza dos identificadores: id_expediente (interno) y cod_expediente (legible para usuarios).
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_expediente
(
    id_expediente        VARCHAR                    NOT NULL CHECK (char_length(trim(id_expediente)) BETWEEN 1 AND 17),     -- Identificador interno. Ej: EXP-20261114-001. Clave primaria.
    nom_expediente       VARCHAR                    NOT NULL CHECK (char_length(trim(nom_expediente)) BETWEEN 1 AND 255),   -- Nombre descriptivo del expediente.
    cod_expediente       VARCHAR                    NOT NULL CHECK (cod_expediente ~ '^[A-Z0-9-]{3,30}$'),                  -- Codigo legible para usuarios. Ej: "EXP-2026-001". Unico.
    id_tipo              DECIMAL(3,0)               NOT NULL CHECK (id_tipo BETWEEN 1 AND 100),                             -- FK al tipo de documento principal.
    id_area              DECIMAL(5,0)               NOT NULL CHECK (id_area > 0),                                           -- FK al area responsable.
    ind_publico          BOOLEAN                    NOT NULL DEFAULT TRUE,                                                  -- Indicador para saber si el archivo es visible para todos o no.
    id_retencion         DECIMAL(5,0)               NOT NULL CHECK (id_retencion BETWEEN 1 AND 9999),                       -- FK a politica de retencion.
    fec_apertura         DATE                       NOT NULL CHECK (fec_apertura <= CURRENT_DATE),                          -- Fecha de apertura. No puede ser futura.
    fec_cierre           DATE                       NOT NULL CHECK (fec_cierre >= fec_apertura),                            -- Fecha de cierre. Debe ser >= fec_apertura.
    fec_disposicion      DATE                       NOT NULL CHECK (fec_disposicion >= fec_apertura),                       -- Fecha de disposicion final.
    ind_activo           BOOLEAN                    NOT NULL DEFAULT TRUE,                                                  -- ¿Expediente activo? TRUE = puede recibir documentos.
    resumen              TEXT                       NOT NULL DEFAULT 'SIN_RESUMEN' CHECK (char_length(trim(resumen)) >= 1), -- Resumen del contenido.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                 -- Borrado logico.
    PRIMARY KEY (id_expediente),
    CONSTRAINT uq_expediente_cod UNIQUE (cod_expediente),
    CONSTRAINT chk_fechas_expediente CHECK (fec_cierre >= fec_apertura AND fec_disposicion >= fec_apertura),
    FOREIGN KEY (id_tipo)      REFERENCES tab_tipo_documento(id_tipo),
    FOREIGN KEY (id_area)      REFERENCES tab_areas(id_area),
    FOREIGN KEY (id_retencion) REFERENCES tab_tabla_retencion(id_retencion)
);
-- Indices para optimizar consultas por area, estado y codigo.
CREATE INDEX idx_expediente_area   ON tab_expediente(id_area);
CREATE INDEX idx_expediente_activo ON tab_expediente(ind_activo);
CREATE INDEX idx_expediente_cod    ON tab_expediente(cod_expediente);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_doc_expediente
-- Establece la relacion entre los documentos de correspondencia y los expedientes digitales.
-- Actua como tabla intermedia (puente) que permite una relacion muchos a muchos:
-- una correspondencia puede estar en multiples expedientes y un expediente puede
-- contener multiples correspondencias.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_doc_expediente
(
    id_expediente        VARCHAR                    NOT NULL CHECK (char_length(trim(id_expediente)) BETWEEN 1 AND 17),     -- FK al expediente. Parte de PK compuesta.
    id_correspondencia   VARCHAR                    NOT NULL CHECK (id_correspondencia ~ '^[0-9]{14}$'),                    -- FK a la correspondencia. Parte de PK compuesta.
    fec_incorporacion    TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                 -- Fecha y hora de incorporacion al expediente.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                 -- Borrado logico.
    PRIMARY KEY (id_expediente, id_correspondencia),
    FOREIGN KEY (id_expediente)      REFERENCES tab_expediente(id_expediente),
    FOREIGN KEY (id_correspondencia) REFERENCES tab_correspondencia(id_correspondencia)
);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_anexo_correspondencia
-- Un solo archivo digital (PDF/JPG/PNG) por correspondencia radicada. UNIQUE en id_correspondencia.
-- El archivo fisico queda en disco (modules/gedcal/dosc_gedcal/); aqui solo va el metadato.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_anexo_correspondencia
(
    id_archivo           VARCHAR                    NOT NULL CHECK (id_archivo ~ '^FILE-[A-Z0-9]{15,60}$'),                 -- Identificador del archivo.
    id_correspondencia   VARCHAR                    NOT NULL CHECK (id_correspondencia ~ '^[0-9]{14}$'),                    -- FK a la correspondencia (una sola por radicado).
    nom_archivo          VARCHAR                    NOT NULL CHECK (nom_archivo ~ '^[A-Za-z0-9 ._-]{1,255}$'),              -- Nombre original saneado.
    tamano_bytes         BIGINT                     NOT NULL CHECK (tamano_bytes BETWEEN 1 AND 52428800),                   -- Maximo 50MB.
    val_formato          VARCHAR                    NOT NULL CHECK (val_formato IN ('PDF','JPG','PNG')),                    -- Formato permitido.
    fec_carga            TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                 -- Fecha de carga.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                 -- Borrado logico.
    PRIMARY KEY (id_archivo),
    CONSTRAINT uq_anexo_correspondencia_unico UNIQUE (id_correspondencia),
    FOREIGN KEY (id_correspondencia) REFERENCES tab_correspondencia(id_correspondencia)
);
--------------------------------------------------------------------------------------------------------
-- SECUENCIA: seq_notificacion
-- Proposito: Genera identificadores unicos para cada notificacion.
--------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS seq_notificacion START WITH 1 INCREMENT BY 1 NO CYCLE;
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_notificaciones
-- Servicio de notificaciones de TODO el ERP (campana, avisos emergentes y mensajes entre personas).
-- Cualquier modulo crea notificaciones con fun_insert_notificacion / fun_notificar_evento.
--   val_clase: ALERTA (vencimientos), PROCESO (eventos de los modulos) o MENSAJE (entre personas).
--   val_nivel: color del semaforo (tab_param_aviso).
--   url_destino: menu_principal.php?path=X-Y a donde lleva el clic (NULL = no navega).
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_notificaciones
(
    id_notificacion       DECIMAL(8,0)               NOT NULL DEFAULT nextval('seq_notificacion'),                                               -- Identificador unico. Clave primaria.
    id_correspondencia    VARCHAR                             CHECK (id_correspondencia IS NULL OR id_correspondencia ~ '^[0-9]{14}$'),          -- Opcional: correspondencia relacionada.
    id_expediente         VARCHAR                             CHECK (id_expediente IS NULL OR char_length(trim(id_expediente)) BETWEEN 1 AND 17), -- Opcional: expediente relacionado.
    id_usuario_destino    VARCHAR                    NOT NULL CHECK (char_length(trim(id_usuario_destino)) >= 5),                                -- FK al usuario que recibe (misma regla de tab_usuarios).
    id_usuario_origen     VARCHAR                    NOT NULL CHECK (char_length(trim(id_usuario_origen)) >= 5),                                 -- FK al usuario que envia (misma regla de tab_usuarios).
    tipo_notificacion     VARCHAR                    NOT NULL CHECK (char_length(trim(tipo_notificacion)) BETWEEN 1 AND 30),                     -- Tipo: info, alerta, pqrs, correspondencia, workflow...
    mensaje               TEXT                       NOT NULL DEFAULT 'SIN_MENSAJE',                                                             -- Texto del aviso (fun_insert_notificacion lo valida).
    ind_leido             BOOLEAN                    NOT NULL DEFAULT FALSE,                                                                     -- ¿Ya la leyo el destinatario?
    fec_creacion          TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT CURRENT_TIMESTAMP,                                                         -- Fecha y hora de creacion.
    fec_lectura           TIMESTAMP WITH TIME ZONE,                                                                                              -- Fecha y hora de lectura.
    url_destino           VARCHAR                             CHECK (char_length(url_destino) <= 255),                                           -- Pantalla a la que lleva el clic. NULL = no navega.
    ind_borrado           BOOLEAN                    NOT NULL DEFAULT FALSE,                                                                     -- Borrado logico.
    val_nivel             VARCHAR                    NOT NULL DEFAULT 'VERDE' CHECK (val_nivel IN ('VERDE','AMARILLO','ROJO','AZUL')),           -- Nivel del semaforo de avisos.
    cod_origen            VARCHAR                             CHECK (char_length(cod_origen) <= 40),                                             -- Evento o regla que la genero (ej. PQRS, GH_CONTRATO_VENCE).
    id_registro           VARCHAR                             CHECK (char_length(id_registro) <= 40),                                            -- Registro de origen (radicado, hallazgo, empleado...).
    fec_limite_aplazar    DATE,                                                                                                                  -- Hasta cuando se puede aplazar una alerta roja.
    fec_aplazada_hasta    TIMESTAMP WITH TIME ZONE,                                                                                              -- Aplazada por el usuario hasta esta hora.
    ind_descartada        BOOLEAN                    NOT NULL DEFAULT FALSE,                                                                     -- TRUE = el usuario la descarto y no vuelve a saltar.
    fec_aviso_mostrado    TIMESTAMP WITH TIME ZONE,                                                                                              -- Cuando salto como aviso emergente.
    txt_grupo             VARCHAR                             CHECK (char_length(txt_grupo) <= 120),                                             -- Grupo destinatario (@menu, @jefe de area, @todos).
    val_clase             VARCHAR                    NOT NULL DEFAULT 'PROCESO' CHECK (val_clase IN ('ALERTA','PROCESO','MENSAJE')),             -- Pestaña de la campana.
    id_envio              DECIMAL(10,0),                                                                                                         -- Agrupa a todos los destinatarios de un mismo mensaje.
    id_notificacion_padre DECIMAL(8,0),                                                                                                          -- Mensaje al que responde (hilo de conversacion).
    PRIMARY KEY (id_notificacion),
    FOREIGN KEY (id_correspondencia)    REFERENCES tab_correspondencia(id_correspondencia),
    FOREIGN KEY (id_expediente)         REFERENCES tab_expediente(id_expediente),
    FOREIGN KEY (id_usuario_destino)    REFERENCES tab_usuarios(id_usuario),
    FOREIGN KEY (id_usuario_origen)     REFERENCES tab_usuarios(id_usuario),
    FOREIGN KEY (id_notificacion_padre) REFERENCES tab_notificaciones(id_notificacion)
);
-- Indices de la campana (bandeja, pendientes, mensajes y avisos por registro de origen).
CREATE INDEX idx_notificaciones_usuario       ON tab_notificaciones(id_usuario_destino);
CREATE INDEX idx_notificaciones_leido         ON tab_notificaciones(ind_leido);
CREATE INDEX idx_notificaciones_fec_creacion  ON tab_notificaciones(fec_creacion);
CREATE INDEX idx_notificaciones_origen        ON tab_notificaciones(id_usuario_origen);
CREATE INDEX idx_notif_bandeja                ON tab_notificaciones(id_usuario_destino, fec_creacion DESC) WHERE ind_borrado = FALSE;
CREATE INDEX idx_notif_pendientes             ON tab_notificaciones(id_usuario_destino) WHERE ind_leido = FALSE AND ind_borrado = FALSE;
CREATE INDEX idx_notif_envio                  ON tab_notificaciones(id_usuario_origen, id_envio) WHERE val_clase = 'MENSAJE';
CREATE INDEX idx_notif_origen_registro        ON tab_notificaciones(cod_origen, id_registro, id_usuario_destino) WHERE cod_origen IS NOT NULL;
--------------------------------------------------------------------------------------------------------
-- SECUENCIA: seq_envio_mensaje
-- Proposito: numero de envio (id_envio) que agrupa a todos los destinatarios de un mismo mensaje.
--------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS seq_envio_mensaje START WITH 1 INCREMENT BY 1 NO CYCLE;
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_modulo_alerta
-- Catalogo de modulos del ERP que generan alertas de vencimiento (PQRS, correspondencia, hallazgos,
-- contratos de Gestion Humana...). Lo usa la pantalla Parametrizacion de alertas.
-- ind_configurable = el modulo se conecto indicando tabla y columnas (txt_tabla, txt_col_*).
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_modulo_alerta
(
    cod_modulo           VARCHAR                    NOT NULL CHECK (cod_modulo ~ '^[A-Z_]{3,20}$'),                                       -- Codigo del modulo. Clave primaria.
    nom_modulo           VARCHAR                    NOT NULL CHECK (char_length(trim(nom_modulo)) BETWEEN 3 AND 60),                      -- Nombre visible.
    txt_icono            VARCHAR                    NOT NULL DEFAULT 'fa-bell' CHECK (txt_icono ~ '^fa-[a-z0-9-]{2,36}$'),                -- Icono Font Awesome.
    txt_destinatario     VARCHAR                    NOT NULL CHECK (char_length(trim(txt_destinatario)) BETWEEN 3 AND 120),               -- A quien le llega el aviso (texto de ayuda).
    txt_fecha_vigilada   VARCHAR                    NOT NULL CHECK (char_length(trim(txt_fecha_vigilada)) BETWEEN 3 AND 160),             -- Que fecha se vigila (texto de ayuda).
    val_dias_max         DECIMAL(2,0)               NOT NULL CHECK (val_dias_max BETWEEN 1 AND 90),                                       -- Maximo de dias de anticipacion permitido.
    ind_copia_jefe       BOOLEAN                    NOT NULL DEFAULT FALSE,                                                               -- ¿Permite enviar copia al jefe del area?
    txt_mensaje_defecto  VARCHAR                    NOT NULL CHECK (char_length(trim(txt_mensaje_defecto)) BETWEEN 10 AND 300),           -- Plantilla por defecto del aviso.
    num_orden            DECIMAL(2,0)               NOT NULL DEFAULT 99,                                                                  -- Orden en la pantalla.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                               -- Borrado logico.
    ind_estado           BOOLEAN                    NOT NULL DEFAULT TRUE,                                                                -- TRUE = activo; FALSE = pausado.
    ind_configurable     BOOLEAN                    NOT NULL DEFAULT FALSE,                                                               -- TRUE = conectado por tabla/columnas (ver CHECK de fuente).
    txt_tabla            VARCHAR                             CHECK (char_length(txt_tabla) <= 63),                                        -- Tabla vigilada (nombre de PostgreSQL: maximo 63).
    txt_col_codigo       VARCHAR                             CHECK (char_length(txt_col_codigo) <= 63),                                   -- Columna con el codigo del registro.
    txt_col_nombre       VARCHAR                             CHECK (char_length(txt_col_nombre) <= 63),                                   -- Columna con el nombre del registro.
    txt_col_fecha        VARCHAR                             CHECK (char_length(txt_col_fecha) <= 63),                                    -- Columna con la fecha de vencimiento.
    val_tipo_destino     VARCHAR                             CHECK (val_tipo_destino IS NULL OR val_tipo_destino IN ('USUARIO','AREA')),  -- La columna destino es un usuario o un area.
    txt_col_destino      VARCHAR                             CHECK (char_length(txt_col_destino) <= 63),                                  -- Columna con el destinatario.
    txt_col_estado       VARCHAR                             CHECK (char_length(txt_col_estado) <= 63),                                   -- Columna de estado (opcional).
    txt_estados_cierre   VARCHAR                             CHECK (char_length(txt_estados_cierre) <= 300),                              -- Estados que cierran el registro (no avisar).
    txt_programa         VARCHAR                             CHECK (char_length(txt_programa) <= 120),                                    -- Pantalla del menu que abre el aviso.
    id_usuario_registro  VARCHAR                             CHECK (char_length(trim(id_usuario_registro)) >= 5),                         -- FK a quien lo configuro.
    fec_registro         TIMESTAMP WITH TIME ZONE,                                                                                        -- Fecha de la ultima configuracion.
    ind_completo         BOOLEAN                    NOT NULL DEFAULT TRUE,                                                                -- FALSE = falta que el administrador lo complete.
    PRIMARY KEY (cod_modulo),
    CONSTRAINT ck_modulo_alerta_fuente CHECK (ind_configurable = FALSE
                                              OR (txt_tabla IS NOT NULL AND txt_col_codigo IS NOT NULL AND txt_col_nombre IS NOT NULL
                                                  AND txt_col_fecha IS NOT NULL AND val_tipo_destino IN ('USUARIO','AREA')
                                                  AND txt_col_destino IS NOT NULL AND txt_programa IS NOT NULL)),
    FOREIGN KEY (id_usuario_registro) REFERENCES tab_usuarios(id_usuario)
);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_evento_notificacion
-- Eventos que generan aviso inmediato (radicar, asignar, auditar, GH_CONTRATO_VENCE...).
-- Cada uno se enciende o apaga desde la Parametrizacion de alertas. Los modulos que no estan en
-- tab_modulo_alerta se identifican con txt_modulo_erp.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_evento_notificacion
(
    cod_evento           VARCHAR                    NOT NULL CHECK (cod_evento ~ '^[A-Z_]{3,30}$'),                                       -- Codigo del evento. Clave primaria.
    cod_modulo           VARCHAR                             CHECK (cod_modulo IS NULL OR cod_modulo ~ '^[A-Z_]{3,20}$'),                 -- FK al modulo del catalogo (opcional).
    nom_evento           VARCHAR                    NOT NULL CHECK (char_length(trim(nom_evento)) BETWEEN 5 AND 100),                     -- Nombre visible.
    txt_destinatario     VARCHAR                    NOT NULL CHECK (char_length(trim(txt_destinatario)) BETWEEN 3 AND 120),               -- A quien le llega (texto de ayuda).
    ind_activo           BOOLEAN                    NOT NULL DEFAULT TRUE,                                                                -- Interruptor del evento.
    num_orden            DECIMAL(2,0)               NOT NULL DEFAULT 99,                                                                  -- Orden en la pantalla.
    id_usuario_registro  VARCHAR                             CHECK (char_length(trim(id_usuario_registro)) >= 5),                         -- FK a quien lo cambio por ultima vez.
    fec_registro         TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                               -- Fecha del ultimo cambio.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                               -- Borrado logico.
    txt_modulo_erp       VARCHAR                             CHECK (char_length(txt_modulo_erp) <= 60),                                   -- Modulo del ERP cuando no esta en el catalogo.
    PRIMARY KEY (cod_evento),
    CONSTRAINT ck_evento_modulo CHECK (cod_modulo IS NOT NULL OR char_length(trim(COALESCE(txt_modulo_erp, ''))) >= 3),
    FOREIGN KEY (cod_modulo)          REFERENCES tab_modulo_alerta(cod_modulo),
    FOREIGN KEY (id_usuario_registro) REFERENCES tab_usuarios(id_usuario)
);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_param_aviso
-- Semaforo de los avisos emergentes: color, segundos en pantalla y umbral en dias de cada nivel.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_param_aviso
(
    val_nivel            VARCHAR                    NOT NULL CHECK (val_nivel IN ('VERDE','AMARILLO','ROJO','AZUL')),                     -- Nivel. Clave primaria.
    nom_nivel            VARCHAR                    NOT NULL CHECK (char_length(trim(nom_nivel)) BETWEEN 3 AND 40),                       -- Nombre visible.
    txt_color            VARCHAR                    NOT NULL CHECK (txt_color ~ '^#[0-9A-Fa-f]{6}$'),                                     -- Color hexadecimal.
    val_segundos         DECIMAL(3,0)               NOT NULL CHECK (val_segundos BETWEEN 0 AND 120),                                      -- Segundos en pantalla (0 = hasta que se cierre).
    val_dias_umbral      DECIMAL(2,0)                        CHECK (val_dias_umbral BETWEEN 0 AND 30),                                    -- Dias para pasar a este nivel.
    num_orden            DECIMAL(1,0)               NOT NULL,                                                                             -- Orden del semaforo.
    id_usuario_registro  VARCHAR                             CHECK (char_length(trim(id_usuario_registro)) >= 5),                         -- FK a quien lo cambio por ultima vez.
    fec_registro         TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                               -- Fecha del ultimo cambio.
    PRIMARY KEY (val_nivel),
    FOREIGN KEY (id_usuario_registro) REFERENCES tab_usuarios(id_usuario)
);
--------------------------------------------------------------------------------------------------------
-- SECUENCIA: seq_param_alerta
-- Proposito: identificadores de las reglas de vencimiento de los modulos (excepto PQRS).
--------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS seq_param_alerta START WITH 1 INCREMENT BY 1 NO CYCLE;
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_param_alerta
-- Regla "proximo a vencer" de cada modulo del catalogo (una por modulo): dias de anticipacion,
-- frecuencia, copia al jefe y plantilla del aviso. PQRS tiene sus reglas aparte (tab_param_alerta_pqrs).
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_param_alerta
(
    id_alerta            DECIMAL(3,0)               NOT NULL DEFAULT nextval('seq_param_alerta') CHECK (id_alerta BETWEEN 1 AND 999),       -- Identificador de la regla. Clave primaria.
    cod_modulo           VARCHAR                    NOT NULL CHECK (cod_modulo ~ '^[A-Z_]{3,20}$'),                                       -- FK al modulo del catalogo. Una regla por modulo.
    dias_anticipacion    DECIMAL(2,0)               NOT NULL CHECK (dias_anticipacion BETWEEN 1 AND 90),                                  -- Dias habiles antes del vencimiento en que empieza a avisar.
    ind_repetir          BOOLEAN                    NOT NULL DEFAULT TRUE,                                                                -- TRUE = avisa cada dia habil; FALSE = un solo aviso.
    ind_avisar_jefe      BOOLEAN                    NOT NULL DEFAULT FALSE,                                                               -- TRUE = copia al jefe del area.
    txt_mensaje          VARCHAR                    NOT NULL CHECK (char_length(trim(txt_mensaje)) BETWEEN 10 AND 300),                   -- Plantilla: {codigo}, {nombre}, {fecha}, {dias}.
    ind_estado           BOOLEAN                    NOT NULL DEFAULT TRUE,                                                                -- TRUE = activa; FALSE = pausada.
    id_usuario_registro  VARCHAR                    NOT NULL CHECK (char_length(trim(id_usuario_registro)) >= 5),                         -- FK a quien configuro la regla.
    fec_registro         TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                               -- Fecha de la ultima configuracion.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                               -- Borrado logico.
    PRIMARY KEY (id_alerta),
    CONSTRAINT uq_param_alerta_modulo UNIQUE (cod_modulo),
    FOREIGN KEY (cod_modulo)          REFERENCES tab_modulo_alerta(cod_modulo),
    FOREIGN KEY (id_usuario_registro) REFERENCES tab_usuarios(id_usuario)
);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_log_alerta
-- Bitacora de avisos de vencimiento enviados por los modulos. La PK (modulo, registro, destinatario,
-- dia) garantiza maximo un aviso por dia a cada persona.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_log_alerta
(
    cod_modulo           VARCHAR                    NOT NULL CHECK (cod_modulo ~ '^[A-Z_]{3,20}$'),                                       -- FK al modulo que genero el aviso.
    id_registro          VARCHAR                    NOT NULL CHECK (char_length(trim(id_registro)) BETWEEN 1 AND 30),                     -- Registro avisado (radicado, hallazgo, accion...).
    id_usuario_destino   VARCHAR                    NOT NULL CHECK (char_length(trim(id_usuario_destino)) >= 5),                          -- FK a quien recibio el aviso.
    fec_alerta           DATE                       NOT NULL DEFAULT CURRENT_DATE,                                                        -- Dia del aviso.
    id_alerta            DECIMAL(3,0)               NOT NULL CHECK (id_alerta BETWEEN 1 AND 999),                                         -- FK a la regla que lo genero.
    dias_restantes       DECIMAL(2,0)               NOT NULL CHECK (dias_restantes BETWEEN 0 AND 90),                                     -- Dias habiles que faltaban.
    id_notificacion      DECIMAL(8,0)               NOT NULL,                                                                             -- FK a la notificacion creada.
    fec_envio            TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                               -- Momento exacto del envio.
    PRIMARY KEY (cod_modulo, id_registro, id_usuario_destino, fec_alerta),
    FOREIGN KEY (cod_modulo)         REFERENCES tab_modulo_alerta(cod_modulo),
    FOREIGN KEY (id_alerta)          REFERENCES tab_param_alerta(id_alerta),
    FOREIGN KEY (id_usuario_destino) REFERENCES tab_usuarios(id_usuario),
    FOREIGN KEY (id_notificacion)    REFERENCES tab_notificaciones(id_notificacion)
);
CREATE INDEX idx_log_alerta_modulo_fecha ON tab_log_alerta(fec_alerta);
--------------------------------------------------------------------------------------------------------
-- SECUENCIA: seq_agenda_vencimiento
-- Proposito: identificadores de la agenda de vencimientos.
--------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS seq_agenda_vencimiento START WITH 1 INCREMENT BY 1 NO CYCLE;
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_agenda_vencimiento
-- Agenda de vencimientos que alimentan los triggers de cada modulo (PQRS, correspondencia, hallazgos,
-- acciones, auditorias, certificaciones...). El generador de alertas lee de aqui en lugar de armar
-- consultas por modulo. Destino: un usuario, un area o los administradores.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_agenda_vencimiento
(
    id_agenda            DECIMAL(12,0)              NOT NULL DEFAULT nextval('seq_agenda_vencimiento'),                                   -- Llave automatica. Clave primaria.
    cod_modulo           VARCHAR                    NOT NULL CHECK (cod_modulo ~ '^[A-Z_]{3,20}$'),                                       -- FK al modulo.
    id_registro          VARCHAR                    NOT NULL CHECK (char_length(trim(id_registro)) BETWEEN 1 AND 30),                     -- Registro vigilado.
    val_rol              VARCHAR                    NOT NULL DEFAULT 'RESPONSABLE' CHECK (val_rol IN ('RESPONSABLE','JEFE')),             -- A quien va: responsable o su jefe.
    id_usuario_destino   VARCHAR                             CHECK (char_length(trim(id_usuario_destino)) >= 5),                          -- FK al usuario destino (opcional).
    id_area              DECIMAL(5,0)                        CHECK (id_area > 0),                                                         -- FK al area destino (opcional).
    ind_admins           BOOLEAN                    NOT NULL DEFAULT FALSE,                                                               -- TRUE = a los administradores.
    txt_nombre           VARCHAR                    NOT NULL CHECK (char_length(txt_nombre) <= 200),                                      -- Nombre del registro para el aviso.
    txt_subtipo          VARCHAR                             CHECK (char_length(txt_subtipo) <= 30),                                      -- Subtipo (ej. tipo de PQRS) para elegir la regla.
    fec_vence            DATE                       NOT NULL,                                                                             -- Fecha de vencimiento vigilada.
    txt_programa         VARCHAR                             CHECK (char_length(txt_programa) <= 120),                                    -- Pantalla que abre el aviso.
    ind_activo           BOOLEAN                    NOT NULL DEFAULT TRUE,                                                                -- FALSE = el registro ya se cerro.
    fec_registro         TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                               -- Fecha de registro.
    fec_actualizacion    TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                               -- Ultima actualizacion.
    PRIMARY KEY (id_agenda),
    CONSTRAINT ck_agenda_destino CHECK (id_usuario_destino IS NOT NULL OR id_area IS NOT NULL OR ind_admins),
    FOREIGN KEY (cod_modulo)         REFERENCES tab_modulo_alerta(cod_modulo),
    FOREIGN KEY (id_usuario_destino) REFERENCES tab_usuarios(id_usuario),
    FOREIGN KEY (id_area)            REFERENCES tab_areas(id_area)
);
CREATE INDEX idx_agenda_activa ON tab_agenda_vencimiento(cod_modulo, fec_vence) WHERE ind_activo;
-- Un solo registro por modulo, registro, rol y destino.
CREATE UNIQUE INDEX uq_agenda_destino ON tab_agenda_vencimiento(cod_modulo, id_registro, val_rol, COALESCE(id_usuario_destino, ''), COALESCE(id_area, -1));
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_fuente_alerta
-- Tablas de otros modulos que se pueden conectar al motor de alertas (pantalla "Conectar modulo").
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_fuente_alerta
(
    txt_tabla            VARCHAR                    NOT NULL CHECK (txt_tabla ~ '^tab_[a-z0-9_]{1,59}$'),                                 -- Tabla fuente. Clave primaria.
    nom_fuente           VARCHAR                    NOT NULL CHECK (char_length(trim(nom_fuente)) BETWEEN 3 AND 60),                      -- Nombre visible.
    txt_modulo_erp       VARCHAR                    NOT NULL CHECK (char_length(trim(txt_modulo_erp)) BETWEEN 3 AND 60),                  -- Modulo del ERP al que pertenece.
    ind_estado           BOOLEAN                    NOT NULL DEFAULT TRUE,                                                                -- TRUE = disponible.
    id_usuario_registro  VARCHAR                    NOT NULL CHECK (char_length(trim(id_usuario_registro)) >= 5),                         -- FK a quien la registro.
    fec_registro         TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                               -- Fecha de registro.
    PRIMARY KEY (txt_tabla),
    FOREIGN KEY (id_usuario_registro) REFERENCES tab_usuarios(id_usuario)
);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_fuente_columna
-- Columnas de cada tabla fuente y el papel que cumplen en la alerta (codigo, nombre, fecha, usuario,
-- area, estado).
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_fuente_columna
(
    txt_tabla            VARCHAR                    NOT NULL CHECK (txt_tabla ~ '^tab_[a-z0-9_]{1,59}$'),                                 -- FK a la tabla fuente. Parte de PK.
    txt_columna          VARCHAR                    NOT NULL CHECK (txt_columna ~ '^[a-z_][a-z0-9_]{0,62}$'),                             -- Columna. Parte de PK.
    val_rol              VARCHAR                    NOT NULL CHECK (val_rol IN ('CODIGO','NOMBRE','FECHA','USUARIO','AREA','ESTADO')),    -- Papel de la columna. Parte de PK.
    nom_columna          VARCHAR                    NOT NULL CHECK (char_length(trim(nom_columna)) BETWEEN 2 AND 60),                     -- Nombre visible.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                               -- Borrado logico.
    PRIMARY KEY (txt_tabla, txt_columna, val_rol),
    FOREIGN KEY (txt_tabla) REFERENCES tab_fuente_alerta(txt_tabla)
);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_tipo_pqrs
-- Clasifica los tipos de Peticiones, Quejas, Reclamos, Sugerencias y Felicitaciones.
-- Permite categorizar la naturaleza de la solicitud del ciudadano para aplicar
-- los plazos de respuesta correspondientes segun la ley (Ley 1755 de 2015).
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_tipo_pqrs
(
    id_tipo_pqrs         DECIMAL(2,0)               NOT NULL CHECK (id_tipo_pqrs BETWEEN 1 AND 10),                        -- Identificador unico (1 a 10). Clave primaria.
    nom_pqr              VARCHAR                    NOT NULL CHECK (char_length(trim(nom_pqr)) BETWEEN 1 AND 15),          -- Nombre: PETICION, QUEJA, RECLAMO...
    ind_estado           BOOLEAN                    NOT NULL DEFAULT TRUE,                                                 -- ¿Tipo activo? Por defecto TRUE.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- Borrado logico.
    PRIMARY KEY (id_tipo_pqrs)
);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_param_venc_pqrs
-- Define los parametros de vencimiento para cada tipo y subtipo de PQRS segun la normativa legal.
-- Establece los dias habiles base para responder, la posibilidad de prorroga y su duracion,
-- y el fundamento legal aplicable. Sigue la Ley 1755 de 2015 y el CPACA.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_param_venc_pqrs
(
    id_tipo_pqrs            DECIMAL(2,0)            NOT NULL CHECK (id_tipo_pqrs BETWEEN 1 AND 10),                        -- FK al tipo de PQRS. Parte de PK compuesta.
    nom_subtipo             VARCHAR                 NOT NULL CHECK (char_length(trim(nom_subtipo)) BETWEEN 1 AND 60),      -- Subtipo: GENERAL, DERECHO_PETICION, etc.
    dias_habiles_base       DECIMAL(3,0)            NOT NULL CHECK (dias_habiles_base BETWEEN 1 AND 60),                   -- Dias habiles base para respuesta.
    dias_habiles_prorroga   DECIMAL(3,0)            NOT NULL CHECK (dias_habiles_prorroga BETWEEN 0 AND 30) DEFAULT 0,     -- Dias de prorroga permitidos.
    ind_prorroga_permitida  BOOLEAN                 NOT NULL DEFAULT FALSE,                                                -- ¿Se permite prorroga?
    base_legal              VARCHAR                 NOT NULL CHECK (char_length(trim(base_legal)) BETWEEN 5 AND 255),      -- Fundamento legal. Ej: "Ley 1755 de 2015, Articulo 14".
    ind_borrado             BOOLEAN                 NOT NULL DEFAULT FALSE,                                                -- Borrado logico.
    PRIMARY KEY (id_tipo_pqrs, nom_subtipo),
    CONSTRAINT chk_dias_prorroga CHECK (dias_habiles_prorroga = 0 OR ind_prorroga_permitida = TRUE),
    FOREIGN KEY (id_tipo_pqrs) REFERENCES tab_tipo_pqrs(id_tipo_pqrs)
);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_estado_pqrs
-- Define las etapas del ciclo de vida por las que pasa una solicitud de PQRS.
-- Permite el seguimiento y control de las PQRS, sabiendo en todo momento si estan
-- recibidas, asignadas, en estudio, respondidas, cerradas, rechazadas o anuladas.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_estado_pqrs
(
    id_estado_pqrs       DECIMAL(2,0)               NOT NULL CHECK (id_estado_pqrs BETWEEN 1 AND 15),                                                                      -- Identificador unico (1 a 15). Clave primaria.
    val_estado_pqrs      VARCHAR                    NOT NULL CHECK (val_estado_pqrs IN ('RECIBIDA','ASIGNADA','EN_ESTUDIO','RESPONDIDA','CERRADA','RECHAZADA','ANULADA')), -- Estado de la PQRS.
    ind_estado           BOOLEAN                    NOT NULL DEFAULT TRUE,                                                                                                 -- ¿Estado activo? Por defecto TRUE.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                                                                -- Borrado logico.
    PRIMARY KEY (id_estado_pqrs)
);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_motivo_pqrs
-- Motivos para clasificar las PQRS. Cada motivo tiene un area responsable: define a quien
-- llega la PQRS que se radica desde el portal publico.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_motivo_pqrs
(
    id_motivo            VARCHAR                    NOT NULL CHECK (id_motivo ~ '^[A-Z0-9_]{3,20}$'),                      -- Identificador unico. Clave primaria. Ej: 'SERVICIOS'.
    nom_motivo           VARCHAR                    NOT NULL CHECK (char_length(trim(nom_motivo)) BETWEEN 3 AND 100),      -- Nombre descriptivo. Ej: "Problemas con facturacion".
    ind_estado           BOOLEAN                    NOT NULL DEFAULT TRUE,                                                 -- ¿Motivo activo?
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- Borrado logico.
    id_area              DECIMAL(5,0)               NOT NULL CHECK (id_area > 0),                                          -- Area responsable de atender el motivo.
    PRIMARY KEY (id_motivo),
    FOREIGN KEY (id_area) REFERENCES tab_areas(id_area)
);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_enc_pqrs
-- Es la tabla principal que registra la informacion basica de cada solicitud de PQRS.
-- Almacena el radicado, tipo, canal, estado, motivo, area responsable, solicitante,
-- asunto, fechas de radicacion y vencimiento, y si es anonima o requiere respuesta.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_enc_pqrs
(
    id_radicado              VARCHAR                    NOT NULL CHECK (id_radicado ~ '^PQRS-[0-9]{4}-[0-9]{6}$'),         -- Radicado unico. Formato: PQRS-AAAA-XXXXXX. Clave primaria.
    id_tipo_pqrs             DECIMAL(2,0)               NOT NULL CHECK (id_tipo_pqrs BETWEEN 1 AND 10),                    -- FK al tipo de PQRS.
    id_canal                 DECIMAL(2,0)               NOT NULL CHECK (id_canal > 0 AND id_canal <= 99),                  -- FK al canal de entrada.
    id_estado_pqrs           DECIMAL(2,0)               NOT NULL CHECK (id_estado_pqrs BETWEEN 1 AND 15),                  -- FK al estado actual.
    id_motivo                VARCHAR                    NOT NULL CHECK (id_motivo ~ '^[A-Z0-9_]{3,20}$'),                  -- FK al motivo.
    id_area                  DECIMAL(5,0)               NOT NULL CHECK (id_area > 0),                                      -- FK al area responsable.
    id_tercero               VARCHAR                    NOT NULL CHECK (id_tercero ~ '^[A-Z0-9]{7,10}$'),                  -- FK al solicitante (ANONIMO para las anonimas).
    id_usuario               VARCHAR                    NOT NULL CHECK (char_length(trim(id_usuario)) >= 5),               -- FK al usuario que radico (portalpqrs desde el portal).
    asunto                   TEXT                       NOT NULL CHECK (char_length(trim(asunto)) BETWEEN 5 AND 255),      -- Asunto de la solicitud.
    fec_radicado             TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                            -- Fecha y hora de radicacion.
    fec_vencimiento          DATE                       NOT NULL,                                                          -- Fecha limite de respuesta (la calcula insertar_enc_pqrs; ver chk_pqrs_vencimiento).
    ind_anonimo              BOOLEAN                    NOT NULL DEFAULT FALSE,                                            -- ¿Solicitud anonima? Si es TRUE, no requiere identificacion.
    ind_requiere_respuesta   BOOLEAN                    NOT NULL DEFAULT TRUE,                                             -- ¿Requiere respuesta formal?
    ind_archivado            BOOLEAN                    NOT NULL DEFAULT FALSE,                                            -- TRUE = ya respondida y archivada (sale de la bandeja activa).
    fec_archivado            TIMESTAMP WITH TIME ZONE,                                                                     -- Fecha en que se archivo.
    ind_borrado              BOOLEAN                    NOT NULL DEFAULT FALSE,                                            -- Borrado logico.
    txt_motivo_otro          VARCHAR                    NOT NULL DEFAULT 'NO_APLICA' CHECK (char_length(trim(txt_motivo_otro)) BETWEEN 3 AND 100), -- Motivo escrito por el ciudadano cuando elige "Otro" en el portal.
    PRIMARY KEY (id_radicado),
    CONSTRAINT chk_pqrs_vencimiento CHECK (fec_vencimiento >= fec_radicado::date),
    FOREIGN KEY (id_tipo_pqrs)   REFERENCES tab_tipo_pqrs(id_tipo_pqrs),
    FOREIGN KEY (id_canal)       REFERENCES tab_canales(id_canal),
    FOREIGN KEY (id_estado_pqrs) REFERENCES tab_estado_pqrs(id_estado_pqrs),
    FOREIGN KEY (id_motivo)      REFERENCES tab_motivo_pqrs(id_motivo),
    FOREIGN KEY (id_area)        REFERENCES tab_areas(id_area),
    FOREIGN KEY (id_tercero)     REFERENCES tab_terceros(id_tercero),
    FOREIGN KEY (id_usuario)     REFERENCES tab_usuarios(id_usuario)
);
-- Indices para optimizar consultas por estado, area, tipo, fechas y anonimos.
CREATE INDEX idx_enc_pqrs_estado       ON tab_enc_pqrs(id_estado_pqrs);
CREATE INDEX idx_enc_pqrs_area         ON tab_enc_pqrs(id_area);
CREATE INDEX idx_enc_pqrs_tipo         ON tab_enc_pqrs(id_tipo_pqrs);
CREATE INDEX idx_enc_pqrs_radicado     ON tab_enc_pqrs(fec_radicado);
CREATE INDEX idx_enc_pqrs_vence        ON tab_enc_pqrs(fec_vencimiento);
CREATE INDEX idx_enc_pqrs_estado_vence ON tab_enc_pqrs(id_estado_pqrs, fec_vencimiento);
CREATE INDEX idx_enc_pqrs_anonimo      ON tab_enc_pqrs(ind_anonimo) WHERE ind_anonimo = TRUE;
--------------------------------------------------------------------------------------------------------
-- SECUENCIA: seq_det_pqrs
-- Proposito: Genera identificadores unicos para cada registro de detalle de PQRS.
--------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS seq_det_pqrs START WITH 1 INCREMENT BY 1 NO CYCLE;
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_det_pqrs
-- Almacena informacion detallada y complementaria de cada solicitud de PQRS.
-- Registra la prioridad, tiempos de respuesta (real y proyectado), fechas de asignacion,
-- inicio de gestion, ultima gestion y cierre definitivo, asi como el gestor responsable,
-- el usuario que cerro, la calificacion del solicitante y comentarios de cierre.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_det_pqrs
(
    id_detalle_pqrs             DECIMAL(12,0)              NOT NULL DEFAULT nextval('seq_det_pqrs'),                                                        -- Identificador unico. Clave primaria.
    id_radicado                 VARCHAR                    NOT NULL CHECK (id_radicado ~ '^PQRS-[0-9]{4}-[0-9]{6}$'),                                       -- FK al radicado.
    val_prioridad               VARCHAR                    NOT NULL DEFAULT 'NORMAL' CHECK (val_prioridad IN ('BAJA','NORMAL','ALTA','URGENTE','CRITICA')), -- Nivel de prioridad.
    tiempo_respuesta_real       INTEGER                    NOT NULL DEFAULT 0 CHECK (tiempo_respuesta_real BETWEEN 0 AND 365),                              -- Dias reales que tomo responder.
    tiempo_respuesta_proyectado INTEGER                             CHECK (tiempo_respuesta_proyectado BETWEEN 0 AND 365) DEFAULT 0,                        -- Dias proyectados para respuesta.
    fec_asignacion              TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT CURRENT_TIMESTAMP,                                                              -- Fecha y hora de asignacion a un gestor.
    fec_inicio_gestion          TIMESTAMP WITH TIME ZONE   NOT NULL CHECK (fec_inicio_gestion >= fec_asignacion),                                           -- Fecha de inicio real de gestion.
    fec_ultima_gestion          TIMESTAMP WITH TIME ZONE   NOT NULL CHECK (fec_ultima_gestion >= fec_inicio_gestion),                                       -- Fecha de ultima actividad.
    fec_cierre_definitivo       TIMESTAMP WITH TIME ZONE   NOT NULL,                                                                                        -- Fecha de cierre definitivo.
    id_usuario_gestor           VARCHAR                    NOT NULL CHECK (char_length(trim(id_usuario_gestor)) >= 5),                                      -- FK al usuario gestor.
    id_usuario_cierre           VARCHAR                    NOT NULL CHECK (char_length(trim(id_usuario_cierre)) >= 5),                                      -- FK al usuario que cerro.
    calificacion_solicitante    DECIMAL(2,0)                        CHECK (calificacion_solicitante BETWEEN 1 AND 5),                                       -- Calificacion 1-5 estrellas.
    comentario_cierre           TEXT                       NOT NULL DEFAULT 'SIN_COMENTARIO',                                                               -- Comentario de cierre.
    ind_borrado                 BOOLEAN                    NOT NULL DEFAULT FALSE,                                                                          -- Borrado logico.
    PRIMARY KEY (id_detalle_pqrs),
    CONSTRAINT chk_fechas_gestion CHECK ((fec_inicio_gestion IS NULL OR fec_inicio_gestion >= fec_asignacion) AND (fec_cierre_definitivo IS NULL OR fec_cierre_definitivo >= fec_inicio_gestion)),
    FOREIGN KEY (id_radicado)       REFERENCES tab_enc_pqrs(id_radicado),
    FOREIGN KEY (id_usuario_gestor) REFERENCES tab_usuarios(id_usuario),
    FOREIGN KEY (id_usuario_cierre) REFERENCES tab_usuarios(id_usuario)
);
-- Indices para optimizar consultas por radicado, prioridad, gestor y fechas clave.
CREATE INDEX idx_det_pqrs_radicado       ON tab_det_pqrs(id_radicado);
CREATE INDEX idx_det_pqrs_prioridad      ON tab_det_pqrs(val_prioridad);
CREATE INDEX idx_det_pqrs_gestor         ON tab_det_pqrs(id_usuario_gestor);
CREATE INDEX idx_det_pqrs_fec_asignacion ON tab_det_pqrs(fec_asignacion) WHERE fec_asignacion IS NOT NULL;
CREATE INDEX idx_det_pqrs_fec_cierre     ON tab_det_pqrs(fec_cierre_definitivo) WHERE fec_cierre_definitivo IS NOT NULL;
--------------------------------------------------------------------------------------------------------
-- SECUENCIA: seq_seg_pqrs
-- Proposito: Genera identificadores unicos para cada registro de seguimiento de PQRS.
--------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS seq_seg_pqrs START WITH 1 INCREMENT BY 1 NO CYCLE;
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_seg_pqrs
-- Bitacora de cada PQRS: cambios de estado y notas de seguimiento (una nota se guarda con
-- estado origen = estado destino). Registra quien lo hizo y cuando.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_seg_pqrs
(
    id_seguimiento       DECIMAL(18,0)              NOT NULL DEFAULT nextval('seq_seg_pqrs'),                              -- Identificador unico. Clave primaria.
    id_radicado          VARCHAR                    NOT NULL CHECK (id_radicado ~ '^PQRS-[0-9]{4}-[0-9]{6}$'),             -- FK al radicado.
    id_estado_origen     DECIMAL(2,0)               NOT NULL CHECK (id_estado_origen BETWEEN 1 AND 15),                    -- Estado antes del cambio.
    id_estado_destino    DECIMAL(2,0)               NOT NULL CHECK (id_estado_destino BETWEEN 1 AND 15),                   -- Estado despues del cambio.
    fec_accion           TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                -- Fecha y hora del cambio.
    observacion          TEXT                       NOT NULL DEFAULT 'SIN_OBSERVACION',                                    -- Nota o motivo del movimiento.
    id_usuario           VARCHAR                    NOT NULL CHECK (char_length(trim(id_usuario)) >= 5),                   -- FK al usuario que registro el movimiento.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- Borrado logico.
    PRIMARY KEY (id_seguimiento),
    FOREIGN KEY (id_radicado)       REFERENCES tab_enc_pqrs(id_radicado),
    FOREIGN KEY (id_estado_origen)  REFERENCES tab_estado_pqrs(id_estado_pqrs),
    FOREIGN KEY (id_estado_destino) REFERENCES tab_estado_pqrs(id_estado_pqrs),
    FOREIGN KEY (id_usuario)        REFERENCES tab_usuarios(id_usuario)
);
-- Indices para optimizar consultas por radicado y por fecha de accion.
CREATE INDEX idx_seg_pqrs_radicado ON tab_seg_pqrs(id_radicado);
CREATE INDEX idx_seg_pqrs_fecha    ON tab_seg_pqrs(fec_accion);
--------------------------------------------------------------------------------------------------------
-- SECUENCIA: seq_respuesta_pqrs
-- Proposito: Genera identificadores unicos para cada respuesta registrada en PQRS.
--------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS seq_respuesta_pqrs START WITH 1 INCREMENT BY 1 NO CYCLE;
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_respuesta_pqrs
-- Registra las respuestas proporcionadas a cada solicitud de PQRS.
-- Almacena la respuesta enviada al solicitante, el canal de respuesta,
-- si es la respuesta final, quien la genero y cuando.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_respuesta_pqrs
(
    id_respuesta         DECIMAL(18,0)              NOT NULL DEFAULT nextval('seq_respuesta_pqrs'),                        -- Identificador unico. Clave primaria.
    id_radicado          VARCHAR                    NOT NULL CHECK (id_radicado ~ '^PQRS-[0-9]{4}-[0-9]{6}$'),             -- FK al radicado.
    canal_respuesta      DECIMAL(2,0)               NOT NULL CHECK (canal_respuesta BETWEEN 1 AND 20),                     -- FK al canal por el que se respondio.
    ind_respuesta_final  BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- ¿Es la respuesta final? Solo una puede ser TRUE por radicado.
    fec_respuesta        TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                -- Fecha y hora de la respuesta.
    texto_respuesta      TEXT                       NOT NULL CHECK (char_length(trim(texto_respuesta)) BETWEEN 5 AND 4000), -- Texto oficial que ve el ciudadano en el portal.
    id_usuario           VARCHAR                    NOT NULL CHECK (char_length(trim(id_usuario)) >= 5),                   -- FK al usuario que redacto la respuesta.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- Borrado logico.
    PRIMARY KEY (id_respuesta),
    FOREIGN KEY (id_radicado)     REFERENCES tab_enc_pqrs(id_radicado),
    FOREIGN KEY (canal_respuesta) REFERENCES tab_canales(id_canal),
    FOREIGN KEY (id_usuario)      REFERENCES tab_usuarios(id_usuario)
);
-- Una sola respuesta final por PQRS y busqueda por radicado.
CREATE UNIQUE INDEX idx_uq_respuesta_final_pqrs ON tab_respuesta_pqrs(id_radicado) WHERE ind_respuesta_final = TRUE;
CREATE INDEX idx_respuesta_pqrs_radicado        ON tab_respuesta_pqrs(id_radicado);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_anexo_pqrs
-- Almacena los anexos o archivos adjuntos relacionados con las solicitudes de PQRS o sus respuestas.
-- Permite adjuntar archivos (PDF, JPG, PNG) a una PQRS o a una respuesta especifica.
-- Cada anexo debe pertenecer a un solo padre (radicado o respuesta).
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_anexo_pqrs
(
    id_anexo_pqrs        VARCHAR                    NOT NULL CHECK (id_anexo_pqrs ~ '^ANX-[A-Z0-9]{5,10}$'),                            -- Identificador unico. Formato: ANX-XXXXX. Clave primaria.
    id_radicado          VARCHAR                             CHECK (id_radicado IS NULL OR id_radicado ~ '^PQRS-[0-9]{4}-[0-9]{6}$'),   -- FK al radicado (si el anexo pertenece al radicado).
    id_respuesta         DECIMAL(18,0)                       CHECK (id_respuesta IS NULL OR id_respuesta >= 1),                         -- FK a la respuesta (si el anexo pertenece a la respuesta).
    nom_anexo            VARCHAR                    NOT NULL CHECK (nom_anexo ~ '^[A-Za-z0-9._-]{1,255}$'),                             -- Nombre del archivo.
    tamano_bytes         BIGINT                     NOT NULL CHECK (tamano_bytes BETWEEN 1 AND 52428800),                               -- Tamaño en bytes (maximo 50MB).
    val_formato          VARCHAR                    NOT NULL CHECK (val_formato IN ('PDF','JPG','PNG')),                                -- Formato del archivo.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                             -- Borrado logico.
    PRIMARY KEY (id_anexo_pqrs),
    CONSTRAINT chk_anexo_pqrs_un_padre CHECK ((CASE WHEN id_radicado IS NOT NULL THEN 1 ELSE 0 END) + (CASE WHEN id_respuesta IS NOT NULL THEN 1 ELSE 0 END) = 1),
    FOREIGN KEY (id_radicado)  REFERENCES tab_enc_pqrs(id_radicado),
    FOREIGN KEY (id_respuesta) REFERENCES tab_respuesta_pqrs(id_respuesta)
);
--------------------------------------------------------------------------------------------------------
-- SECUENCIA: seq_param_alerta_pqrs
-- Proposito: Genera los identificadores de las reglas de alerta de PQRS.
--------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS seq_param_alerta_pqrs START WITH 1 INCREMENT BY 1 NO CYCLE;
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_param_alerta_pqrs
-- Reglas de alerta "proxima a vencer" por tipo de PQRS. La regla con id_tipo_pqrs NULL es la
-- regla GENERAL: aplica a los tipos que no tienen una regla propia activa.
-- La alerta llega a la campana del gestor asignado (tab_det_pqrs.id_usuario_gestor) cuando a la
-- PQRS le quedan dias_anticipacion dias habiles o menos para vencer (sin sabados, domingos ni festivos).
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_param_alerta_pqrs
(
    id_alerta            DECIMAL(3,0)               NOT NULL DEFAULT nextval('seq_param_alerta_pqrs') CHECK (id_alerta BETWEEN 1 AND 999),  -- Identificador de la regla. Clave primaria.
    id_tipo_pqrs         DECIMAL(2,0)                        CHECK (id_tipo_pqrs BETWEEN 1 AND 10),                                         -- Tipo de PQRS al que aplica. NULL = regla GENERAL.
    dias_anticipacion    DECIMAL(2,0)               NOT NULL CHECK (dias_anticipacion BETWEEN 1 AND 30),                                    -- Dias habiles antes del vencimiento en que empieza a avisar.
    ind_repetir          BOOLEAN                    NOT NULL DEFAULT TRUE,                                                                  -- TRUE = avisa cada dia habil hasta el vencimiento; FALSE = un solo aviso.
    txt_mensaje          VARCHAR                    NOT NULL DEFAULT 'La PQRS {radicado} ({tipo}) vence el {fecha}. Quedan {dias} día(s) hábil(es) para responder.'
                                                             CHECK (char_length(trim(txt_mensaje)) BETWEEN 10 AND 300),                     -- Plantilla: {radicado}, {tipo}, {asunto}, {fecha}, {dias}.
    ind_estado           BOOLEAN                    NOT NULL DEFAULT TRUE,                                                                  -- TRUE = activa; FALSE = pausada (no envia avisos pero se conserva).
    id_usuario_registro  VARCHAR                    NOT NULL CHECK (char_length(trim(id_usuario_registro)) >= 5),                           -- FK al usuario que configuro la regla; figura como remitente del aviso.
    fec_registro         TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                                 -- Fecha de la ultima configuracion.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                                 -- Borrado logico.
    PRIMARY KEY (id_alerta),
    FOREIGN KEY (id_tipo_pqrs)        REFERENCES tab_tipo_pqrs(id_tipo_pqrs),
    FOREIGN KEY (id_usuario_registro) REFERENCES tab_usuarios(id_usuario)
);
-- Una sola regla por tipo (y una sola GENERAL), incluidas las inactivas: se reactivan, no se duplican.
CREATE UNIQUE INDEX uq_param_alerta_tipo ON tab_param_alerta_pqrs ((COALESCE(id_tipo_pqrs, 0)));
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_log_alerta_pqrs
-- Bitacora de avisos automaticos enviados. La PK (radicado, dia) garantiza maximo un aviso por PQRS
-- por dia aunque varios usuarios abran el sistema al mismo tiempo.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_log_alerta_pqrs
(
    id_radicado          VARCHAR                    NOT NULL CHECK (id_radicado ~ '^PQRS-[0-9]{4}-[0-9]{6}$'),             -- PQRS avisada.
    fec_alerta           DATE                       NOT NULL DEFAULT CURRENT_DATE,                                         -- Dia del aviso.
    id_alerta            DECIMAL(3,0)               NOT NULL CHECK (id_alerta BETWEEN 1 AND 999),                          -- Regla que lo genero.
    id_usuario_destino   VARCHAR                    NOT NULL CHECK (char_length(trim(id_usuario_destino)) >= 5),           -- Gestor que recibio el aviso.
    dias_restantes       DECIMAL(2,0)               NOT NULL CHECK (dias_restantes BETWEEN 0 AND 30),                      -- Dias habiles que faltaban.
    id_notificacion      DECIMAL(8,0)               NOT NULL,                                                              -- Notificacion creada en la campana.
    fec_envio            TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                -- Momento exacto del envio.
    PRIMARY KEY (id_radicado, fec_alerta),
    FOREIGN KEY (id_radicado)        REFERENCES tab_enc_pqrs(id_radicado),
    FOREIGN KEY (id_alerta)          REFERENCES tab_param_alerta_pqrs(id_alerta),
    FOREIGN KEY (id_usuario_destino) REFERENCES tab_usuarios(id_usuario),
    FOREIGN KEY (id_notificacion)    REFERENCES tab_notificaciones(id_notificacion)
);
CREATE INDEX idx_log_alerta_fecha ON tab_log_alerta_pqrs(fec_alerta);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_consecutivo_pqrs
-- Ultimo consecutivo de radicado por año (PQRS-AAAA-NNNNNN): se reinicia cada año y no se choca
-- aunque dos personas radiquen al mismo tiempo (la funcion bloquea la fila del año).
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_consecutivo_pqrs
(
    val_anio             DECIMAL(4,0)               NOT NULL CHECK (val_anio BETWEEN 2000 AND 9999),                                      -- Año. Clave primaria.
    val_ultimo           DECIMAL(6,0)               NOT NULL CHECK (val_ultimo BETWEEN 0 AND 999999),                                     -- Ultimo numero usado en el año.
    PRIMARY KEY (val_anio)
);
--------------------------------------------------------------------------------------------------------
-- SECUENCIA: seq_codigo_pqrs
-- Proposito: identificadores de los codigos de verificacion del portal publico.
--------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS seq_codigo_pqrs START WITH 1 INCREMENT BY 1 NO CYCLE;
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_codigo_pqrs
-- Codigos de verificacion enviados al correo para consultar PQRS por numero de documento en el portal.
-- Solo se guarda el hash (SHA-256) del codigo; vale una vez, vence y tiene limite de intentos.
-- Sin FK a tab_terceros a proposito: se valida el documento sin revelar si existe o no.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_codigo_pqrs
(
    id_codigo            DECIMAL(12,0)              NOT NULL DEFAULT nextval('seq_codigo_pqrs'),                                          -- Llave automatica. Clave primaria.
    id_tercero           VARCHAR                    NOT NULL CHECK (id_tercero ~ '^[A-Z0-9]{5,20}$'),                                     -- Documento consultado.
    txt_hash             VARCHAR                    NOT NULL CHECK (txt_hash ~ '^[0-9a-f]{64}$'),                                         -- SHA-256 del codigo enviado.
    txt_ip               VARCHAR                    NOT NULL DEFAULT 'SIN_IP' CHECK (char_length(txt_ip) BETWEEN 1 AND 45),               -- IP que lo pidio (limite de solicitudes).
    fec_creacion         TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                               -- Cuando se genero.
    fec_vence            TIMESTAMP WITH TIME ZONE   NOT NULL,                                                                             -- Hasta cuando vale.
    val_intentos         DECIMAL(1,0)               NOT NULL DEFAULT 0 CHECK (val_intentos BETWEEN 0 AND 5),                              -- Intentos fallidos.
    ind_usado            BOOLEAN                    NOT NULL DEFAULT FALSE,                                                               -- TRUE = ya se uso.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                               -- Borrado logico.
    PRIMARY KEY (id_codigo),
    CONSTRAINT chk_codigo_pqrs_vence CHECK (fec_vence > fec_creacion)
);
CREATE INDEX idx_codigo_pqrs_tercero ON tab_codigo_pqrs(id_tercero, fec_creacion);
CREATE INDEX idx_codigo_pqrs_ip      ON tab_codigo_pqrs(txt_ip, fec_creacion);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_normas
-- Define las normas de calidad aplicables a los procesos documentales.
-- Catalogo de normas (ISO 9001, ISO 14001, NTC, etc.) que sirve como base
-- para las certificaciones y para asociar documentos de calidad con los estandares que cumplen.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_normas
(
    id_norma             VARCHAR                    NOT NULL CHECK (id_norma ~ '^[A-Z]{2,5}-[0-9]{4,6}$'),                 -- Identificador unico. Formato: ISO-9001. Clave primaria.
    nom_norma            VARCHAR                    NOT NULL CHECK (char_length(trim(nom_norma)) BETWEEN 5 AND 255),       -- Nombre completo. Ej: ISO 9001:2015 Sistemas de gestion de la calidad.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- Borrado logico.
    PRIMARY KEY (id_norma)
);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_estado_documento
-- Define los estados de los documentos gestionados en el sistema de calidad.
-- Permite el control del ciclo de vida de los documentos de calidad (manuales, procedimientos,
-- instructivos, formatos, politicas, registros).
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_estado_documento
(
    id_estado            DECIMAL(2,0)               NOT NULL CHECK (id_estado BETWEEN 1 AND 20),                           -- Identificador unico (1 a 20). Clave primaria.
    val_estado           VARCHAR                    NOT NULL CHECK (char_length(trim(val_estado)) BETWEEN 3 AND 15),       -- Estado: BORRADOR, EN_REVISION, APROBADO, PUBLICADO, OBSOLETO...
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- Borrado logico.
    PRIMARY KEY (id_estado)
);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_enc_documento
-- Es la tabla principal que registra la informacion basica de cada documento gestionado en el sistema de calidad.
-- Almacena el titulo, tipo de documento, estado actual, area responsable, resumen,
-- vigencia, fechas de publicacion y revision, y el tercero responsable.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_enc_documento
(
    id_documento         VARCHAR                    NOT NULL CHECK (id_documento ~ '^DOC-[A-Z0-9]{5,15}$'),                -- Identificador unico. Formato: DOC-XXXXX. Clave primaria.
    nom_titulo           VARCHAR                    NOT NULL CHECK (char_length(trim(nom_titulo)) BETWEEN 5 AND 255),      -- Titulo del documento.
    id_estado            DECIMAL(2,0)               NOT NULL CHECK (id_estado BETWEEN 1 AND 20),                           -- FK al estado actual.
    id_area              DECIMAL(5,0)               NOT NULL CHECK (id_area > 0),                                          -- FK al area responsable.
    resumen              VARCHAR                    NOT NULL CHECK (char_length(trim(resumen)) BETWEEN 5 AND 2000) DEFAULT 'Sin Resumen', -- Resumen del documento.
    ind_vigencia         BOOLEAN                    NOT NULL DEFAULT TRUE,                                                 -- ¿Documento vigente?
    fec_publicacion      DATE                       NOT NULL CHECK (fec_publicacion <= CURRENT_DATE),                      -- Fecha de publicacion.
    fec_revision         DATE                       NOT NULL CHECK (fec_revision >= fec_publicacion),                      -- Fecha de proxima revision.
    id_tercero           VARCHAR                    NOT NULL CHECK (id_tercero ~ '^[A-Z0-9]{7,10}$'),                      -- FK al tercero responsable.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- Borrado logico.
    PRIMARY KEY (id_documento),
    CONSTRAINT chk_fechas_documento CHECK (fec_revision >= fec_publicacion),
    FOREIGN KEY (id_estado)  REFERENCES tab_estado_documento(id_estado),
    FOREIGN KEY (id_area)    REFERENCES tab_areas(id_area),
    FOREIGN KEY (id_tercero) REFERENCES tab_terceros(id_tercero)
);
-- Indices para optimizar consultas frecuentes por estado, area y fechas.
CREATE INDEX idx_enc_documento_estado ON tab_enc_documento(id_estado);
CREATE INDEX idx_enc_documento_area   ON tab_enc_documento(id_area);
CREATE INDEX idx_enc_documento_fec    ON tab_enc_documento(fec_publicacion);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_det_documento
-- Registra las diferentes versiones de cada documento gestionado en el sistema de calidad.
-- Permite el control de versiones de los documentos. Cada vez que un documento se modifica,
-- se crea una nueva version con su propio identificador, numero de version y fecha.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_det_documento
(
    id_version           VARCHAR                    NOT NULL CHECK (id_version ~ '^VER-[0-9]{8}-[0-9]{3}$'),               -- Identificador unico. Formato VER-AAAAMMDD-XXX. Clave primaria.
    id_documento         VARCHAR                    NOT NULL CHECK (id_documento ~ '^DOC-[A-Z0-9]{5,15}$'),                -- FK al documento.
    num_version          INTEGER                    NOT NULL CHECK (num_version BETWEEN 1 AND 999) DEFAULT 1,              -- Numero de version.
    fec_version          TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                -- Fecha y hora de creacion de la version.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- Borrado logico.
    PRIMARY KEY (id_version),
    CONSTRAINT uq_doc_num_version UNIQUE (id_documento, num_version),
    CONSTRAINT chk_version_unica CHECK (num_version = CAST(substring(id_version from '[0-9]{3}$') AS INTEGER)),
    FOREIGN KEY (id_documento) REFERENCES tab_enc_documento(id_documento)
);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_doc_norma
-- Establece la relacion entre los documentos de calidad y las normas aplicables.
-- Permite una relacion muchos a muchos: un documento puede estar asociado a multiples normas
-- y una norma puede estar asociada a multiples documentos.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_doc_norma
(
    id_documento         VARCHAR                    NOT NULL CHECK (id_documento ~ '^DOC-[A-Z0-9]{5,15}$'),                -- FK al documento. Parte de PK.
    id_norma             VARCHAR                    NOT NULL CHECK (id_norma ~ '^[A-Z]{2,5}-[0-9]{4,6}$'),                 -- FK a la norma. Parte de PK.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- Borrado logico.
    PRIMARY KEY (id_documento, id_norma),
    FOREIGN KEY (id_documento) REFERENCES tab_enc_documento(id_documento),
    FOREIGN KEY (id_norma)     REFERENCES tab_normas(id_norma)
);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_doc_archivo
-- Almacena los archivos asociados a cada version de los documentos de calidad.
-- Permite subir y gestionar los archivos digitales (PDF, JPG, PNG) que contienen
-- el contenido real de cada version de un documento.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_doc_archivo
(
    id_archivo           VARCHAR                    NOT NULL CHECK (id_archivo ~ '^FILE-[A-Z0-9]{15,60}$'),                -- Identificador unico. Formato: FILE-XXXXX. Clave primaria.
    id_version           VARCHAR                    NOT NULL CHECK (id_version ~ '^VER-[0-9]{8}-[0-9]{3}$'),               -- FK a la version del documento.
    nom_archivo          VARCHAR                    NOT NULL CHECK (nom_archivo ~ '^[A-Za-z0-9._-]{1,255}$'),              -- Nombre del archivo.
    tamano_bytes         BIGINT                     NOT NULL CHECK (tamano_bytes BETWEEN 1 AND 52428800),                  -- Tamaño en bytes (maximo 50MB).
    val_formato          VARCHAR                    NOT NULL CHECK (val_formato IN ('PDF','JPG','PNG')),                   -- Formato del archivo.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- Borrado logico.
    PRIMARY KEY (id_archivo),
    FOREIGN KEY (id_version) REFERENCES tab_det_documento(id_version)
);
--------------------------------------------------------------------------------------------------------
-- SECUENCIAS DE CALIDAD (llaves automaticas)
-- seq_proceso: PROC-00001 · seq_auditoria: consecutivo de auditorias · seq_hallazgo: H00001
-- seq_accion_correctiva: AC-AAAA000001 · seq_tipo_dato_entrada · seq_bitacora_proceso
-- seq_solicitud_certificacion · seq_workflow: transiciones del workflow documental.
--------------------------------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS seq_proceso                 START WITH 1 INCREMENT BY 1 NO CYCLE;
CREATE SEQUENCE IF NOT EXISTS seq_auditoria               START WITH 1 INCREMENT BY 1 MAXVALUE 999999 NO CYCLE;
CREATE SEQUENCE IF NOT EXISTS seq_hallazgo                START WITH 1 INCREMENT BY 1 NO CYCLE;
CREATE SEQUENCE IF NOT EXISTS seq_accion_correctiva       START WITH 1 INCREMENT BY 1 NO CYCLE;
CREATE SEQUENCE IF NOT EXISTS seq_tipo_dato_entrada       START WITH 1 INCREMENT BY 1 MAXVALUE 999 NO CYCLE;
CREATE SEQUENCE IF NOT EXISTS seq_bitacora_proceso        START WITH 1 INCREMENT BY 1 NO CYCLE;
CREATE SEQUENCE IF NOT EXISTS seq_solicitud_certificacion START WITH 1 INCREMENT BY 1 NO CYCLE;
CREATE SEQUENCE IF NOT EXISTS seq_workflow                START WITH 1 INCREMENT BY 1 NO CYCLE;
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_procesos
-- Mapa de procesos de la organizacion. Cada proceso tiene un objetivo, un area responsable y una
-- descripcion guiada (entradas, pasos, salidas, riesgos) que la IA evalua contra el rubro de calidad.
-- val_estado_calidad recorre el ciclo Workflow -> IA -> Auditoria / Certificacion.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_procesos
(
    id_proceso           VARCHAR                    NOT NULL CHECK (id_proceso ~ '^PROC-[A-Z0-9]{5,50}$'),                 -- Formato PROC-00001 (fun_generar_id_proceso). Clave primaria.
    nom_proceso          VARCHAR                    NOT NULL CHECK (char_length(trim(nom_proceso)) BETWEEN 5 AND 255),     -- Nombre del proceso.
    objetivo             VARCHAR                    NOT NULL DEFAULT 'Sin Objetivo' CHECK (char_length(trim(objetivo)) BETWEEN 10 AND 2000), -- Objetivo del proceso.
    fec_creacion         DATE                       NOT NULL CHECK (fec_creacion <= CURRENT_DATE),                         -- Fecha de creacion.
    ind_activo           BOOLEAN                    NOT NULL DEFAULT TRUE,                                                 -- ¿Proceso activo?
    ind_en_ejecucion     BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- ¿En ejecucion actualmente?
    id_area              DECIMAL(5,0)               NOT NULL CHECK (id_area > 0),                                          -- FK al area responsable.
    entradas             TEXT                                CHECK (entradas IS NULL OR char_length(trim(entradas)) BETWEEN 3 AND 4000),                   -- Resumen de entradas (detalle tipificado en tab_entrada_proceso).
    pasos_principales    TEXT                                CHECK (pasos_principales IS NULL OR char_length(trim(pasos_principales)) BETWEEN 3 AND 6000), -- Pasos en orden (lista numerada).
    salida_esperada      TEXT                                CHECK (salida_esperada IS NULL OR char_length(trim(salida_esperada)) BETWEEN 3 AND 4000),     -- Lo que entrega el proceso (una o varias salidas).
    riesgos_conocidos    TEXT                                CHECK (riesgos_conocidos IS NULL OR char_length(trim(riesgos_conocidos)) BETWEEN 3 AND 4000), -- Que suele fallar (opcional).
    val_estado_calidad   VARCHAR                    NOT NULL DEFAULT 'BORRADOR' CHECK (val_estado_calidad IN ('BORRADOR','EVALUADO','EN_AUDITORIA','APROBADO','REQUIERE_AJUSTES','EN_CERTIFICACION','CERTIFICADO')), -- Estado del ciclo de calidad.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- Borrado logico.
    PRIMARY KEY (id_proceso),
    FOREIGN KEY (id_area) REFERENCES tab_areas(id_area)
);
-- Indices para optimizar consultas por area responsable y estado del proceso.
CREATE INDEX idx_procesos_area           ON tab_procesos(id_area);
CREATE INDEX idx_procesos_activo         ON tab_procesos(ind_activo) WHERE ind_activo = TRUE;
CREATE INDEX idx_procesos_estado_calidad ON tab_procesos(val_estado_calidad);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_tipo_dato_entrada
--------------------------------------------------------------------------------------------------------
-- Tabla maestra de tipos de dato para las entradas de un proceso (documento fisico, formulario,
-- aprobacion...). Llave automatica por secuencia.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_tipo_dato_entrada
(
    id_tipo_dato         DECIMAL(3,0)               NOT NULL DEFAULT nextval('seq_tipo_dato_entrada') CHECK (id_tipo_dato BETWEEN 1 AND 999), -- Llave automatica.
    nom_tipo_dato        VARCHAR                    NOT NULL CHECK (char_length(trim(nom_tipo_dato)) BETWEEN 3 AND 40),                       -- Ej: Documento fisico.
    txt_descripcion      VARCHAR                    NOT NULL CHECK (char_length(trim(txt_descripcion)) BETWEEN 5 AND 255),                    -- Ayuda para elegirlo y contexto para la IA.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                                    -- Borrado logico.
    PRIMARY KEY (id_tipo_dato)
);
-- No se repite el nombre entre los activos.
CREATE UNIQUE INDEX uq_tipo_dato_nombre ON tab_tipo_dato_entrada (upper(trim(nom_tipo_dato))) WHERE ind_borrado = FALSE;
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_entrada_proceso
--------------------------------------------------------------------------------------------------------
-- Cada entrada de un proceso con su tipo de dato. Se reemplaza completa cada vez que se guarda la
-- descripcion.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_entrada_proceso
(
    id_proceso           VARCHAR                    NOT NULL CHECK (id_proceso ~ '^PROC-[A-Z0-9]{5,50}$'),                 -- FK al proceso. Parte de PK.
    num_orden            DECIMAL(3,0)               NOT NULL CHECK (num_orden BETWEEN 1 AND 200),                          -- Orden en la lista. Parte de PK.
    txt_entrada          VARCHAR                    NOT NULL CHECK (char_length(trim(txt_entrada)) BETWEEN 2 AND 150),     -- Que entra al proceso.
    id_tipo_dato         DECIMAL(3,0)               NOT NULL CHECK (id_tipo_dato BETWEEN 1 AND 999),                       -- FK al tipo de dato de la entrada.
    PRIMARY KEY (id_proceso, num_orden),
    FOREIGN KEY (id_proceso)   REFERENCES tab_procesos(id_proceso),
    FOREIGN KEY (id_tipo_dato) REFERENCES tab_tipo_dato_entrada(id_tipo_dato)
);
CREATE INDEX idx_entrada_proceso_tipo ON tab_entrada_proceso(id_tipo_dato);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_bitacora_proceso
--------------------------------------------------------------------------------------------------------
-- Bitacora de transiciones del proceso (crear, describir, evaluar con IA, enviar a auditoria...),
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_bitacora_proceso
(
    id_bitacora          DECIMAL(12,0)              NOT NULL DEFAULT nextval('seq_bitacora_proceso'),                      -- Llave automatica.
    id_proceso           VARCHAR                    NOT NULL CHECK (id_proceso ~ '^PROC-[A-Z0-9]{5,50}$'),                 -- FK al proceso afectado.
    id_accion            DECIMAL(2,0)                        CHECK (id_accion BETWEEN 1 AND 99),                           -- FK a la accion del catalogo (puede faltar si se inactivo).
    cod_accion           VARCHAR                    NOT NULL CHECK (char_length(trim(cod_accion)) BETWEEN 1 AND 15),       -- Codigo de la accion (se conserva aunque cambie el catalogo).
    val_estado_origen    VARCHAR                             CHECK (char_length(val_estado_origen) <= 20),                 -- Estado de calidad antes.
    val_estado_destino   VARCHAR                             CHECK (char_length(val_estado_destino) <= 20),                -- Estado de calidad despues.
    txt_detalle          VARCHAR                             CHECK (char_length(txt_detalle) <= 500),                      -- Detalle legible.
    id_usuario           VARCHAR                             CHECK (char_length(trim(id_usuario)) >= 5),                   -- FK a quien lo hizo.
    fec_registro         TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                -- Cuando.
    PRIMARY KEY (id_bitacora),
    FOREIGN KEY (id_proceso) REFERENCES tab_procesos(id_proceso),
    FOREIGN KEY (id_accion)  REFERENCES tab_accion_workflow(id_accion),
    FOREIGN KEY (id_usuario) REFERENCES tab_usuarios(id_usuario)
);
CREATE INDEX idx_bitacora_proceso ON tab_bitacora_proceso(id_proceso, fec_registro DESC);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_certificacion
--------------------------------------------------------------------------------------------------------
-- Registra las certificaciones obtenidas por la organizacion bajo una norma especifica.
-- Permite gestionar el portafolio de certificaciones (vigente, suspendida, retirada), su alcance
-- (proceso certificado) y el ente certificador, para planificar renovaciones y auditorias.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_certificacion
(
    id_certificacion      DECIMAL(6,0)              NOT NULL CHECK (id_certificacion BETWEEN 1 AND 999999),                  -- Identificador unico. Clave primaria.
    nom_certificacion     VARCHAR                   NOT NULL CHECK (char_length(trim(nom_certificacion)) BETWEEN 5 AND 255), -- Nombre descriptivo.
    id_norma              VARCHAR                   NOT NULL CHECK (id_norma ~ '^[A-Z]{2,5}-[0-9]{4,6}$'),                   -- FK a la norma asociada.
    fec_emision           DATE                      NOT NULL CHECK (fec_emision <= CURRENT_DATE),                            -- Fecha de emision. No puede ser futura.
    fec_vencimiento       DATE                      NOT NULL CHECK (fec_vencimiento > fec_emision),                          -- Fecha de vencimiento. Debe ser posterior a emision.
    ind_borrado           BOOLEAN                   NOT NULL DEFAULT FALSE,                                                  -- Borrado logico.
    val_estado            VARCHAR                   NOT NULL DEFAULT 'VIGENTE' CHECK (val_estado IN ('VIGENTE','SUSPENDIDA','RETIRADA')), -- Estado de la certificacion.
    id_proceso            VARCHAR                            CHECK (id_proceso IS NULL OR id_proceso ~ '^PROC-[A-Z0-9]{5,50}$'),     -- Alcance: proceso certificado (NULL = toda la organizacion).
    nom_ente_certificador VARCHAR                            CHECK (char_length(nom_ente_certificador) <= 150),              -- ICONTEC, SGS, Bureau Veritas...
    txt_motivo_estado     VARCHAR                            CHECK (char_length(txt_motivo_estado) <= 500),                  -- Por que se suspendio o retiro.
    PRIMARY KEY (id_certificacion),
    CONSTRAINT chk_certificacion_vigencia CHECK (fec_vencimiento > fec_emision),
    FOREIGN KEY (id_norma)   REFERENCES tab_normas(id_norma),
    FOREIGN KEY (id_proceso) REFERENCES tab_procesos(id_proceso)
);
-- Indices para optimizar consultas por norma y por nombre de certificacion.
CREATE INDEX idx_certificacion_norma ON tab_certificacion(id_norma);
CREATE INDEX idx_nom_certificacion   ON tab_certificacion(nom_certificacion);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_auditorias
--------------------------------------------------------------------------------------------------------
-- Auditorias de calidad al estilo ISO 19011 / ISO/IEC 17021: plan (objetivo, alcance, criterios,
-- auditor lider, parte), etapas PLANIFICADA -> EN_EJECUCION -> CERRADA / CANCELADA y resultado
-- APROBADA / APROBADA_CON_PAC / NO_APROBADA. fec_auditoria es la FECHA PROGRAMADA.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_auditorias
(
    id_auditoria              DECIMAL(6,0)          NOT NULL DEFAULT nextval('seq_auditoria') CHECK (id_auditoria BETWEEN 1 AND 999999), -- Consecutivo automatico. Clave primaria.
    nom_auditoria             VARCHAR               NOT NULL CHECK (char_length(trim(nom_auditoria)) BETWEEN 5 AND 255),             -- Nombre de la auditoria.
    id_proceso                VARCHAR               NOT NULL CHECK (id_proceso ~ '^PROC-[A-Z0-9]{5,50}$'),                           -- FK al proceso auditado.
    tipo_auditoria            VARCHAR               NOT NULL CHECK (tipo_auditoria IN ('INTERNA','EXTERNA','CERTIFICACION')),        -- INTERNA / EXTERNA (CERTIFICACION solo las anteriores al modelo nuevo).
    id_certificacion          DECIMAL(6,0)                   CHECK (id_certificacion BETWEEN 1 AND 999999),                          -- Certificacion asociada (una interna no siempre la tiene).
    fec_auditoria             DATE                  NOT NULL,                                                                        -- Fecha programada (puede ser futura; se valida en las funciones).
    val_resultado             VARCHAR               NOT NULL DEFAULT 'PENDIENTE' CHECK (val_resultado IN ('PENDIENTE','APROBADA','APROBADA_CON_PAC','NO_APROBADA')), -- Resultado.
    txt_observacion           TEXT                           CHECK (txt_observacion IS NULL OR char_length(trim(txt_observacion)) BETWEEN 5 AND 2000), -- Conclusion / justificacion del resultado.
    fec_resultado             DATE,                                                                                                  -- Fecha en que se registro el resultado.
    id_usuario_resultado      VARCHAR                        CHECK (char_length(trim(id_usuario_resultado)) >= 5),                   -- FK al auditor que registro el resultado.
    ind_borrado               BOOLEAN               NOT NULL DEFAULT FALSE,                                                          -- Borrado logico.
    val_etapa                 VARCHAR               NOT NULL DEFAULT 'PLANIFICADA' CHECK (val_etapa IN ('PLANIFICADA','EN_EJECUCION','CERRADA','CANCELADA')), -- Etapa ISO 19011.
    val_parte                 VARCHAR               NOT NULL DEFAULT 'PRIMERA' CHECK (val_parte IN ('PRIMERA','SEGUNDA','TERCERA')), -- Primera, segunda o tercera parte.
    nom_ente_externo          VARCHAR                        CHECK (char_length(nom_ente_externo) <= 150),                           -- Cliente u organismo certificador.
    id_usuario_lider          VARCHAR                        CHECK (char_length(trim(id_usuario_lider)) >= 5),                       -- FK al auditor lider.
    txt_objetivo              VARCHAR                        CHECK (char_length(txt_objetivo) <= 1000),                              -- Plan: objetivo.
    txt_alcance               VARCHAR                        CHECK (char_length(txt_alcance) <= 1000),                               -- Plan: alcance.
    txt_criterios             VARCHAR                        CHECK (char_length(txt_criterios) <= 1000),                             -- Normas / requisitos contra los que se audita.
    fec_ejecucion             DATE,                                                                                                  -- Inicio real.
    val_estado_proceso_previo VARCHAR                        CHECK (char_length(val_estado_proceso_previo) <= 20),                   -- Estado del proceso antes (se devuelve si se cancela).
    id_auditoria_origen       DECIMAL(6,0)                   CHECK (id_auditoria_origen BETWEEN 1 AND 999999),                       -- Auditoria de la que es seguimiento.
    txt_motivo_cancelacion    VARCHAR                        CHECK (char_length(txt_motivo_cancelacion) <= 500),                     -- Por que se cancelo.
    PRIMARY KEY (id_auditoria),
    CONSTRAINT chk_auditoria_resultado  CHECK (val_resultado = 'PENDIENTE' OR (fec_resultado IS NOT NULL AND txt_observacion IS NOT NULL)),
    CONSTRAINT chk_auditoria_parte_tipo CHECK ((tipo_auditoria = 'INTERNA' AND val_parte = 'PRIMERA') OR tipo_auditoria <> 'INTERNA'),
    FOREIGN KEY (id_proceso)           REFERENCES tab_procesos(id_proceso),
    FOREIGN KEY (id_certificacion)     REFERENCES tab_certificacion(id_certificacion),
    FOREIGN KEY (id_usuario_resultado) REFERENCES tab_usuarios(id_usuario),
    FOREIGN KEY (id_usuario_lider)     REFERENCES tab_usuarios(id_usuario),
    FOREIGN KEY (id_auditoria_origen)  REFERENCES tab_auditorias(id_auditoria)
);
-- Indices para optimizar consultas por proceso, certificacion, tipo y etapa.
CREATE INDEX idx_auditoria_proceso       ON tab_auditorias(id_proceso);
CREATE INDEX idx_auditoria_certificacion ON tab_auditorias(id_certificacion);
CREATE INDEX idx_auditoria_tipo          ON tab_auditorias(tipo_auditoria);
CREATE INDEX idx_auditoria_etapa         ON tab_auditorias(val_etapa);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_hallazgo
--------------------------------------------------------------------------------------------------------
-- Hallazgos de auditoria tipificados (ISO 19011): FORTALEZA, OPORTUNIDAD_MEJORA, NC_MENOR, NC_MAYOR,
-- con requisito incumplido, evidencia objetiva, plazo del plan de accion y cierre.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_hallazgo
(
    id_hallazgo          VARCHAR                    NOT NULL CHECK (id_hallazgo ~ '^[A-Z0-9]{6}$'),                         -- Codigo automatico H00001 (fun_generar_id_hallazgo). Clave primaria.
    id_auditoria         DECIMAL(6,0)               NOT NULL CHECK (id_auditoria BETWEEN 1 AND 999999),                     -- FK a la auditoria.
    val_severidad        VARCHAR                    NOT NULL CHECK (val_severidad IN ('BAJA','MEDIA','ALTA','CRITICA')),    -- Severidad del hallazgo.
    ind_estado           BOOLEAN                    NOT NULL DEFAULT TRUE,                                                  -- TRUE = Abierto, FALSE = Cerrado.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                 -- Borrado logico.
    val_tipo             VARCHAR                    NOT NULL DEFAULT 'NC_MENOR' CHECK (val_tipo IN ('FORTALEZA','OPORTUNIDAD_MEJORA','NC_MENOR','NC_MAYOR')), -- Tipo ISO 19011.
    val_estado           VARCHAR                    NOT NULL DEFAULT 'ABIERTO' CHECK (val_estado IN ('ABIERTO','EN_TRATAMIENTO','CERRADO')), -- Estado del hallazgo.
    txt_requisito        VARCHAR                             CHECK (char_length(txt_requisito) <= 150),                     -- Requisito incumplido. Ej: ISO 9001:2015 numeral 7.5.3.
    txt_descripcion      VARCHAR                             CHECK (char_length(txt_descripcion) <= 2000),                  -- Que se encontro.
    txt_evidencia        VARCHAR                             CHECK (char_length(txt_evidencia) <= 2000),                    -- Evidencia objetiva.
    fec_registro         TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                 -- Cuando se registro.
    id_usuario_registro  VARCHAR                             CHECK (char_length(trim(id_usuario_registro)) >= 5),           -- FK a quien lo registro.
    fec_limite_pac       DATE,                                                                                              -- Plazo para el plan de accion.
    fec_cierre           DATE,                                                                                              -- Fecha de cierre.
    id_usuario_cierre    VARCHAR                             CHECK (char_length(trim(id_usuario_cierre)) >= 5),             -- FK a quien lo cerro.
    txt_cierre           VARCHAR                             CHECK (char_length(txt_cierre) <= 1000),                       -- Nota de cierre.
    PRIMARY KEY (id_hallazgo),
    FOREIGN KEY (id_auditoria)        REFERENCES tab_auditorias(id_auditoria),
    FOREIGN KEY (id_usuario_registro) REFERENCES tab_usuarios(id_usuario),
    FOREIGN KEY (id_usuario_cierre)   REFERENCES tab_usuarios(id_usuario)
);
-- Indices para optimizar consultas por auditoria, estado y tipo.
CREATE INDEX idx_hallazgo_auditoria        ON tab_hallazgo(id_auditoria);
CREATE INDEX idx_hallazgo_auditoria_estado ON tab_hallazgo(id_auditoria, ind_estado);
CREATE INDEX idx_hallazgo_tipo_estado      ON tab_hallazgo(val_tipo, val_estado);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_accion_correctiva
--------------------------------------------------------------------------------------------------------
-- Plan de accion correctiva (ISO 9001:2015 numeral 10.2): causa raiz, accion, responsable,
-- compromiso, ejecucion con evidencia y verificacion de eficacia.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_accion_correctiva
(
    id_accion              VARCHAR                  NOT NULL CHECK (id_accion ~ '^AC-[0-9]{10}$'),                          -- Codigo automatico AC-AAAA000001. Clave primaria.
    id_hallazgo            VARCHAR                  NOT NULL CHECK (id_hallazgo ~ '^[A-Z0-9]{6}$'),                         -- FK al hallazgo.
    id_tercero             VARCHAR                           CHECK (id_tercero IS NULL OR id_tercero ~ '^[A-Z0-9]{7,10}$'), -- (Historico) el responsable ahora es un usuario.
    fec_compromiso         DATE                     NOT NULL,                                                               -- Fecha compromiso (se valida contra hoy en la funcion).
    fec_ejecucion          DATE,                                                                                            -- Fecha real de ejecucion.
    val_estado             VARCHAR                  NOT NULL DEFAULT 'ABIERTA' CHECK (val_estado IN ('ABIERTA','EN_PROCESO','EJECUTADA','CERRADA','CANCELADA')), -- Estado.
    ind_borrado            BOOLEAN                  NOT NULL DEFAULT FALSE,                                                 -- Borrado logico.
    val_tipo_accion        VARCHAR                  NOT NULL DEFAULT 'CORRECTIVA' CHECK (val_tipo_accion IN ('CORRECCION','CORRECTIVA','PREVENTIVA','MEJORA')), -- Tipo de accion.
    txt_causa_raiz         VARCHAR                           CHECK (txt_causa_raiz IS NULL OR char_length(trim(txt_causa_raiz)) BETWEEN 10 AND 2000), -- Analisis de causa raiz.
    txt_accion             VARCHAR                           CHECK (txt_accion IS NULL OR char_length(trim(txt_accion)) BETWEEN 10 AND 2000),         -- Que se va a hacer.
    id_usuario_responsable VARCHAR                           CHECK (char_length(trim(id_usuario_responsable)) >= 5),        -- FK al responsable de ejecutarla.
    txt_evidencia          VARCHAR                           CHECK (char_length(txt_evidencia) <= 2000),                    -- Evidencia de ejecucion.
    ind_eficaz             BOOLEAN,                                                                                         -- Resultado de la verificacion de eficacia.
    txt_verificacion       VARCHAR                           CHECK (char_length(txt_verificacion) <= 2000),                 -- Nota de la verificacion.
    fec_verificacion       DATE,                                                                                            -- Fecha de la verificacion.
    id_usuario_verifica    VARCHAR                           CHECK (char_length(trim(id_usuario_verifica)) >= 5),           -- FK a quien verifico.
    fec_registro           TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),                                                 -- Cuando se registro.
    id_usuario_registro    VARCHAR                           CHECK (char_length(trim(id_usuario_registro)) >= 5),           -- FK a quien la registro.
    PRIMARY KEY (id_accion),
    CONSTRAINT chk_ac_ejecucion CHECK (val_estado NOT IN ('EJECUTADA','CERRADA') OR fec_ejecucion IS NOT NULL),
    CONSTRAINT chk_ac_cierre    CHECK (val_estado <> 'CERRADA' OR (ind_eficaz = TRUE AND fec_verificacion IS NOT NULL)),
    FOREIGN KEY (id_hallazgo)            REFERENCES tab_hallazgo(id_hallazgo),
    FOREIGN KEY (id_tercero)             REFERENCES tab_terceros(id_tercero),
    FOREIGN KEY (id_usuario_responsable) REFERENCES tab_usuarios(id_usuario),
    FOREIGN KEY (id_usuario_verifica)    REFERENCES tab_usuarios(id_usuario),
    FOREIGN KEY (id_usuario_registro)    REFERENCES tab_usuarios(id_usuario)
);
-- Indices para optimizar consultas por hallazgo y estado de la accion.
CREATE INDEX idx_ac_hallazgo ON tab_accion_correctiva(id_hallazgo);
CREATE INDEX idx_ac_estado   ON tab_accion_correctiva(val_estado);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_doc_anexo
--------------------------------------------------------------------------------------------------------
-- Almacena los anexos relacionados con documentos, versiones o hallazgos del sistema de calidad.
-- Cada anexo pertenece a un solo padre (documento, version o hallazgo).
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_doc_anexo
(
    id_anexo             VARCHAR                    NOT NULL CHECK (id_anexo ~ '^ANX-[A-Z0-9]{5,10}$'),                         -- Identificador unico. Formato: ANX-XXXXX. Clave primaria.
    id_documento         VARCHAR                             CHECK (id_documento IS NULL OR id_documento ~ '^DOC-[A-Z0-9]{5,15}$'), -- FK al documento (opcional).
    id_version           VARCHAR                             CHECK (id_version IS NULL OR id_version ~ '^VER-[0-9]{8}-[0-9]{3}$'),  -- FK a la version (opcional).
    id_hallazgo          VARCHAR                             CHECK (id_hallazgo IS NULL OR id_hallazgo ~ '^[A-Z0-9]{6}$'),          -- FK al hallazgo (opcional).
    nom_anexo            VARCHAR                    NOT NULL CHECK (nom_anexo ~ '^[A-Za-z0-9._-]{1,255}$'),                     -- Nombre del anexo.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                     -- Borrado logico.
    PRIMARY KEY (id_anexo),
    CONSTRAINT chk_anexo_un_solo_padre CHECK ((CASE WHEN id_documento IS NOT NULL THEN 1 ELSE 0 END) + (CASE WHEN id_version IS NOT NULL THEN 1 ELSE 0 END) + (CASE WHEN id_hallazgo IS NOT NULL THEN 1 ELSE 0 END) = 1),
    FOREIGN KEY (id_documento) REFERENCES tab_enc_documento(id_documento),
    FOREIGN KEY (id_version)   REFERENCES tab_det_documento(id_version),
    FOREIGN KEY (id_hallazgo)  REFERENCES tab_hallazgo(id_hallazgo)
);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_workflow
--------------------------------------------------------------------------------------------------------
-- Registra las transiciones realizadas en el flujo de trabajo de gestion documental de calidad.
-- Registra cada cambio de estado de un documento, que accion lo provoco, desde que estado,
-- hacia que estado y cuando.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_workflow
(
    id_workflow          DECIMAL(18,0)              NOT NULL DEFAULT nextval('seq_workflow'),                              -- Identificador unico. Clave primaria.
    id_documento         VARCHAR                    NOT NULL CHECK (id_documento ~ '^DOC-[A-Z0-9]{5,15}$'),                -- FK al documento.
    id_version           VARCHAR                    NOT NULL CHECK (id_version ~ '^VER-[0-9]{8}-[0-9]{3}$'),               -- FK a la version.
    id_accion            DECIMAL(2,0)               NOT NULL CHECK (id_accion BETWEEN 1 AND 99),                           -- FK a la accion que provoco la transicion.
    id_estado_origen     DECIMAL(2,0)               NOT NULL CHECK (id_estado_origen BETWEEN 1 AND 20),                    -- Estado antes de la accion.
    id_estado_destino    DECIMAL(2,0)               NOT NULL CHECK (id_estado_destino BETWEEN 1 AND 20),                   -- Estado despues de la accion.
    fec_transicion       TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                -- Fecha y hora de la transicion.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- Borrado logico.
    PRIMARY KEY (id_workflow),
    CONSTRAINT chk_wf_estados_diferentes CHECK (id_estado_origen <> id_estado_destino),
    FOREIGN KEY (id_documento)      REFERENCES tab_enc_documento(id_documento),
    FOREIGN KEY (id_version)        REFERENCES tab_det_documento(id_version),
    FOREIGN KEY (id_accion)         REFERENCES tab_accion_workflow(id_accion),
    FOREIGN KEY (id_estado_origen)  REFERENCES tab_estado_documento(id_estado),
    FOREIGN KEY (id_estado_destino) REFERENCES tab_estado_documento(id_estado)
);
-- Indices para optimizar consultas por documento y version.
CREATE INDEX idx_wf_doc_documento ON tab_workflow(id_documento);
CREATE INDEX idx_wf_doc_version   ON tab_workflow(id_version);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_parametro_calidad
--------------------------------------------------------------------------------------------------------
-- Rubro configurable contra el que la IA evalua los procesos (Parametros de Calidad).
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_parametro_calidad
(
    id_parametro         DECIMAL(4,0)               NOT NULL CHECK (id_parametro BETWEEN 1 AND 9999),                      -- Identificador. Clave primaria.
    nom_parametro        VARCHAR                    NOT NULL CHECK (char_length(trim(nom_parametro)) BETWEEN 3 AND 150),   -- Criterio.
    descripcion          TEXT                       NOT NULL CHECK (char_length(trim(descripcion)) BETWEEN 10 AND 500),    -- Que debe revisar la IA.
    val_peso             DECIMAL(3,0)               NOT NULL CHECK (val_peso BETWEEN 1 AND 100),                           -- Peso relativo (%).
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- Borrado logico.
    PRIMARY KEY (id_parametro)
);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_prompt_ia
--------------------------------------------------------------------------------------------------------
-- Prompt de la IA guardado en la BD y versionado. 
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_prompt_ia
(
    cod_prompt           VARCHAR                    NOT NULL CHECK (cod_prompt ~ '^[A-Z0-9_]{3,30}$'),                     -- Ej: EVAL_PROCESO. Parte de PK.
    num_version          DECIMAL(4,0)               NOT NULL CHECK (num_version BETWEEN 1 AND 9999),                       -- Version. Parte de PK.
    txt_plantilla        TEXT                       NOT NULL CHECK (char_length(trim(txt_plantilla)) >= 200),              -- Texto del prompt con marcadores {{...}}.
    txt_descripcion      VARCHAR                    NOT NULL DEFAULT 'Sin descripción' CHECK (char_length(txt_descripcion) <= 255), -- Que cambio en esta version.
    ind_activo           BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- Solo una version activa por prompt.
    fec_registro         TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                -- Fecha de registro.
    id_usuario_registro  VARCHAR                             CHECK (char_length(trim(id_usuario_registro)) >= 5),          -- FK a quien la registro.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- Borrado logico.
    PRIMARY KEY (cod_prompt, num_version),
    FOREIGN KEY (id_usuario_registro) REFERENCES tab_usuarios(id_usuario)
);
-- Solo una version activa por prompt.
CREATE UNIQUE INDEX uq_prompt_activo ON tab_prompt_ia(cod_prompt) WHERE ind_activo = TRUE AND ind_borrado = FALSE;
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_evaluacion_calidad_ia
--------------------------------------------------------------------------------------------------------
-- Evaluaciones hechas por IA: SIEMPRE son sugerencia. val_decision registra lo que decidio la persona
-- (ACEPTADA = se creo una auditoria o una solicitud de certificacion, DESCARTADA = no se usa).
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_evaluacion_calidad_ia
(
    id_evaluacion           VARCHAR                    NOT NULL CHECK (id_evaluacion ~ '^EVAL-[A-Z0-9]{10,15}$'),                  -- Identificador. Clave primaria.
    id_proceso              VARCHAR                    NOT NULL CHECK (id_proceso ~ '^PROC-[A-Z0-9]{5,50}$'),                      -- FK al proceso evaluado.
    id_usuario_solicito     VARCHAR                    NOT NULL CHECK (char_length(trim(id_usuario_solicito)) >= 5),               -- FK a quien pidio la evaluacion.
    fec_evaluacion          TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                     -- Fecha de la evaluacion.
    val_puntaje_calidad     DECIMAL(5,2)               NOT NULL CHECK (val_puntaje_calidad BETWEEN 0 AND 100),                     -- Puntaje final (con reglas de rigor).
    val_nivel_impacto       VARCHAR                    NOT NULL CHECK (val_nivel_impacto IN ('BAJO','MEDIO','ALTO','CRITICO')),    -- Impacto si el proceso falla.
    val_nivel_recuperacion  VARCHAR                    NOT NULL CHECK (val_nivel_recuperacion IN ('BAJO','MEDIO','ALTO','CRITICO')), -- Dificultad de recuperarse.
    val_nivel_costo         VARCHAR                    NOT NULL CHECK (val_nivel_costo IN ('BAJO','MEDIO','ALTO','CRITICO')),      -- Costo relativo de una falla.
    txt_justificacion       TEXT                       NOT NULL CHECK (char_length(trim(txt_justificacion)) >= 10),                -- Sintesis de la IA.
    json_respuesta_completa JSONB                      NOT NULL,                                                                   -- Respuesta completa de la IA.
    val_decision            VARCHAR                    NOT NULL DEFAULT 'PENDIENTE' CHECK (val_decision IN ('PENDIENTE','ACEPTADA','DESCARTADA')), -- Decision humana.
    fec_decision            TIMESTAMP WITH TIME ZONE,                                                                              -- Cuando se decidio.
    id_usuario_decision     VARCHAR                             CHECK (char_length(trim(id_usuario_decision)) >= 5),               -- FK a quien decidio.
    id_auditoria            DECIMAL(6,0)                        CHECK (id_auditoria BETWEEN 1 AND 999999),                         -- Auditoria creada al aceptar.
    ind_borrado             BOOLEAN                    NOT NULL DEFAULT FALSE,                                                     -- Borrado logico.
    num_version_prompt      DECIMAL(4,0)                        CHECK (num_version_prompt BETWEEN 1 AND 9999),                     -- Version del prompt usada.
    val_puntaje_bruto       DECIMAL(5,2)                        CHECK (val_puntaje_bruto BETWEEN 0 AND 100),                       -- Suma ponderada antes de las reglas de rigor.
    val_puntaje_ia          DECIMAL(5,2)                        CHECK (val_puntaje_ia BETWEEN 0 AND 100),                          -- Lo que dijo la IA (solo referencia).
    txt_ajuste              VARCHAR                             CHECK (char_length(txt_ajuste) <= 500),                            -- Regla de rigor aplicada.
    id_solicitud            DECIMAL(8,0)                        CHECK (id_solicitud >= 1),                                         -- Solicitud de certificacion creada al aceptar (FK al final de la seccion).
    PRIMARY KEY (id_evaluacion),
    -- Aceptada = se creo una auditoria O una solicitud de certificacion.
    CONSTRAINT chk_eval_decision CHECK ((val_decision = 'ACEPTADA') = (id_auditoria IS NOT NULL OR id_solicitud IS NOT NULL)),
    FOREIGN KEY (id_proceso)          REFERENCES tab_procesos(id_proceso),
    FOREIGN KEY (id_usuario_solicito) REFERENCES tab_usuarios(id_usuario),
    FOREIGN KEY (id_usuario_decision) REFERENCES tab_usuarios(id_usuario),
    FOREIGN KEY (id_auditoria)        REFERENCES tab_auditorias(id_auditoria)
);
CREATE INDEX idx_evaluacion_proceso  ON tab_evaluacion_calidad_ia(id_proceso);
CREATE INDEX idx_evaluacion_decision ON tab_evaluacion_calidad_ia(val_decision);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_solicitud_certificacion
--------------------------------------------------------------------------------------------------------
-- Solicitudes de certificacion que llegan desde Workflow; se otorgan o rechazan en Certificaciones.
-- Referencia circular con tab_evaluacion_calidad_ia (la solicitud nace de una evaluacion y la
-- evaluacion guarda la solicitud que creo): la llave de la evaluacion hacia esta tabla se declara
-- abajo, cuando ya existen las dos.
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_solicitud_certificacion
(
    id_solicitud         DECIMAL(8,0)               NOT NULL DEFAULT nextval('seq_solicitud_certificacion'),               -- Llave automatica. Clave primaria.
    id_proceso           VARCHAR                    NOT NULL CHECK (id_proceso ~ '^PROC-[A-Z0-9]{5,50}$'),                 -- FK al proceso que se quiere certificar.
    id_norma             VARCHAR                    NOT NULL CHECK (id_norma ~ '^[A-Z]{2,5}-[0-9]{4,6}$'),                 -- FK a la norma objetivo.
    id_evaluacion        VARCHAR                             CHECK (id_evaluacion IS NULL OR id_evaluacion ~ '^EVAL-[A-Z0-9]{10,15}$'), -- Evaluacion de IA que la origino.
    val_estado           VARCHAR                    NOT NULL DEFAULT 'PENDIENTE' CHECK (val_estado IN ('PENDIENTE','OTORGADA','RECHAZADA','CANCELADA')), -- Estado.
    txt_observacion      VARCHAR                             CHECK (char_length(txt_observacion) <= 2000),                 -- Motivo del rechazo / nota.
    fec_solicitud        TIMESTAMP WITH TIME ZONE   NOT NULL DEFAULT now(),                                                -- Fecha de la solicitud.
    id_usuario_solicita  VARCHAR                    NOT NULL CHECK (char_length(trim(id_usuario_solicita)) >= 5),          -- FK a quien la solicito.
    fec_resolucion       TIMESTAMP WITH TIME ZONE,                                                                         -- Fecha de la resolucion.
    id_usuario_resuelve  VARCHAR                             CHECK (char_length(trim(id_usuario_resuelve)) >= 5),          -- FK a quien la resolvio.
    id_certificacion     DECIMAL(6,0)                        CHECK (id_certificacion BETWEEN 1 AND 999999),                -- Certificacion creada al otorgar.
    ind_borrado          BOOLEAN                    NOT NULL DEFAULT FALSE,                                                -- Borrado logico.
    PRIMARY KEY (id_solicitud),
    CONSTRAINT chk_solicitud_otorgada  CHECK (val_estado <> 'OTORGADA'  OR id_certificacion IS NOT NULL),
    CONSTRAINT chk_solicitud_rechazada CHECK (val_estado <> 'RECHAZADA' OR char_length(trim(COALESCE(txt_observacion, ''))) >= 10),
    FOREIGN KEY (id_proceso)          REFERENCES tab_procesos(id_proceso),
    FOREIGN KEY (id_norma)            REFERENCES tab_normas(id_norma),
    FOREIGN KEY (id_evaluacion)       REFERENCES tab_evaluacion_calidad_ia(id_evaluacion),
    FOREIGN KEY (id_usuario_solicita) REFERENCES tab_usuarios(id_usuario),
    FOREIGN KEY (id_usuario_resuelve) REFERENCES tab_usuarios(id_usuario),
    FOREIGN KEY (id_certificacion)    REFERENCES tab_certificacion(id_certificacion)
);
-- Una sola solicitud pendiente por proceso.
CREATE UNIQUE INDEX uq_solicitud_pendiente ON tab_solicitud_certificacion(id_proceso) WHERE val_estado = 'PENDIENTE' AND ind_borrado = FALSE;
-- Llave foranea circular evaluacion IA -> solicitud de certificacion (las dos tablas ya existen).
ALTER TABLE tab_evaluacion_calidad_ia ADD CONSTRAINT fk_eval_solicitud
      FOREIGN KEY (id_solicitud) REFERENCES tab_solicitud_certificacion(id_solicitud);
--------------------------------------------------------------------------------------------------------
-- TABLA: tab_eval_criterio_ia
--------------------------------------------------------------------------------------------------------
-- Desglose del puntaje de cada evaluacion por criterio del rubro (copia del nombre y peso del momento).
--------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tab_eval_criterio_ia
(
    id_evaluacion        VARCHAR                    NOT NULL CHECK (id_evaluacion ~ '^EVAL-[A-Z0-9]{10,15}$'),             -- FK a la evaluacion. Parte de PK.
    id_parametro         DECIMAL(4,0)               NOT NULL CHECK (id_parametro BETWEEN 1 AND 9999),                      -- FK al criterio. Parte de PK.
    nom_parametro        VARCHAR                    NOT NULL CHECK (char_length(trim(nom_parametro)) BETWEEN 1 AND 150),   -- Copia: el rubro puede cambiar despues.
    val_peso             DECIMAL(3,0)               NOT NULL CHECK (val_peso BETWEEN 1 AND 100),                           -- Peso del criterio en ese momento.
    val_peso_norm        DECIMAL(6,3)               NOT NULL CHECK (val_peso_norm BETWEEN 0 AND 100),                      -- Peso / suma de pesos x 100.
    val_puntaje          DECIMAL(5,2)               NOT NULL CHECK (val_puntaje BETWEEN 0 AND 100),                        -- Puntaje del criterio.
    val_cumplimiento     VARCHAR                    NOT NULL CHECK (val_cumplimiento IN ('CUMPLE','PARCIAL','NO_CUMPLE','SIN_EVIDENCIA')), -- Cumplimiento.
    val_aporte           DECIMAL(6,2)               NOT NULL,                                                              -- peso_norm x puntaje / 100.
    txt_evidencia        VARCHAR                             CHECK (char_length(txt_evidencia) <= 600),                    -- Parte de la descripcion que sustenta el puntaje.
    txt_brecha           VARCHAR                             CHECK (char_length(txt_brecha) <= 600),                       -- Que falta para llegar a 100.
    PRIMARY KEY (id_evaluacion, id_parametro),
    FOREIGN KEY (id_evaluacion) REFERENCES tab_evaluacion_calidad_ia(id_evaluacion),
    FOREIGN KEY (id_parametro)  REFERENCES tab_parametro_calidad(id_parametro)
);



----------------------------------------------
-- MÓDULO DE TESORERIA
----------------------------------------------
--------------------------------------------
-- TABLA DE PARÁMETROS DE TESORERÍA Y CXP --
--------------------------------------------
-- TABLA 1: Parámetros de Tesorería
CREATE TABLE tab_pmtros_tescxp
(
    id_empresa	        VARCHAR(10)		    NOT NULL,													                                    -- Identificador de la empresa
    fec_diapago1        DECIMAL(1,0)        NOT NULL CHECK((fec_diapago1) >= 1 AND (fec_diapago1) <= 6) DEFAULT 1,                          -- Día #1 en el que la empresa decide pagar
    fec_diapago2        DECIMAL(1,0)        NOT NULL CHECK((fec_diapago2) >= 1 AND (fec_diapago2) <= 6) DEFAULT 3,                          -- Día #2 en el que la empresa decide pagar
    fec_diapago3        DECIMAL(1,0)        NOT NULL CHECK((fec_diapago3) >= 1 AND (fec_diapago3) <= 6) DEFAULT 5,                          -- Día #3 en el que la empresa decide pagar
    val_min_reembolso   DECIMAL(8,0)        NOT NULL CHECK((val_min_reembolso >= 0) AND (val_min_reembolso <= 99999999)) DEFAULT 0,         -- Valor mínimo de reembolso para crear otra caja menor
    ind_borrado         BOOLEAN             NOT NULL DEFAULT FALSE,                                                                         -- TRUE: Borrado lógico (Inactivo) / FALSE: Activo

    PRIMARY KEY         (id_empresa),
    FOREIGN KEY         (id_empresa)        REFERENCES tab_pmtros_grales(id_empresa)                                                                                                   
);

-------------------------
-- TABLA DE CAJA MENOR --
-------------------------
-- TABLA 2: Cajas Menores (fondos fijos asignados)
CREATE TABLE tab_enc_caja_menor
(
    id_caja_menor 		DECIMAL(10,0)		NOT NULL CHECK(id_caja_menor > 0 AND id_caja_menor <= 9999999999),				                    -- ID de caja (hasta 9,999,999,999)
    nom_caja_menor 		VARCHAR(50) 		NOT NULL CHECK(LENGTH(nom_caja_menor) >= 3 AND LENGTH(nom_caja_menor) <= 50) DEFAULT 'Caja Menor',  -- Nombre descriptivo
    monto_asignado 		DECIMAL(8,0) 		NOT NULL CHECK(monto_asignado >= 0 AND monto_asignado <= 99999999) DEFAULT 0,				        -- Fondo fijo asignado
    monto_disponible 	DECIMAL(8,0) 		NOT NULL CHECK(monto_disponible >= 0 AND monto_disponible <= 99999999),			                    -- Saldo disponible
    fecha_apertura 		DATE 				NOT NULL DEFAULT CURRENT_DATE,                                      								-- Fecha de creación (la app valida que no sea futura al abrir la caja)
    fecha_cierre 		DATE,																									                -- Fecha de cierre (NULL si está activa)
    ind_estado_caja_m 	BOOLEAN 			NOT NULL DEFAULT TRUE,																                -- TRUE = Activa / FALSE = Cerrada
	ind_borrado         BOOLEAN             NOT NULL DEFAULT FALSE,                                                                             -- TRUE: Borrado lógico (Inactivo) / FALSE: Activo
	
    PRIMARY KEY         (id_caja_menor),
	
    CONSTRAINT chk_caja_fechas              CHECK(fecha_cierre IS NULL OR fecha_cierre >= fecha_apertura),
    CONSTRAINT chk_caja_disponible          CHECK(monto_disponible <= monto_asignado)
);

----------------------------------------
-- TABLA DE MOVIMIENTOS DE CAJA MENOR --
----------------------------------------
-- TABLA 3: Movimientos de Caja Menor (ingresos y egresos)
CREATE TABLE tab_det_caja_menor
(
    id_caja_menor 		DECIMAL(10,0) 		NOT NULL CHECK(id_caja_menor > 0 AND id_caja_menor <= 9999999999),                          -- ID de caja (hasta 9,999,999,999)
    id_movimiento 		DECIMAL(10,0) 		NOT NULL CHECK(id_movimiento > 0 AND id_movimiento <= 9999999999),                          -- ID del movimiento hecho en la caja
    concepto 			VARCHAR(200) 		NOT NULL CHECK(LENGTH(concepto) > 0 AND LENGTH(concepto) <= 200) DEFAULT 'Sin especificar', -- Descripción del movimiento
    val_movimiento 		DECIMAL(8,0) 		NOT NULL CHECK(val_movimiento >= 1 AND val_movimiento <= 99999999) DEFAULT 1,               -- Valor del movimiento
    fecha_movimiento 	DATE 				NOT NULL DEFAULT CURRENT_DATE,                                                              -- Fecha del movimiento (se permite registro retroactivo: el soporte llega después del gasto)
    ind_estado 			DECIMAL(1,0) 		NOT NULL DEFAULT 1 CHECK((ind_estado >= 1) AND (ind_estado <= 3)),                          -- 1 = Pendiente, 2 = Aprobado, 3 = Reembolsado

    PRIMARY KEY         (id_caja_menor, id_movimiento),
    FOREIGN KEY         (id_caja_menor)     REFERENCES tab_enc_caja_menor(id_caja_menor)
);
-- Consultas tipo: "fecha es la que se realizó un movimiento en la caja menor"
CREATE INDEX IF NOT EXISTS idx_mov_caja_fecha ON tab_det_caja_menor(fecha_movimiento);

-- Consultas tipo: "movimientos que se hayan realizado en una caja menor en específico"
CREATE INDEX IF NOT EXISTS idx_mov_caja_caja ON tab_det_caja_menor(id_caja_menor);

------------------------------------
-- TABLA DE CUENTAS DE LA EMPRESA --
------------------------------------
-- TABLA 4: Cuentas de la empresa
CREATE TABLE tab_ctas_empresa
(
    id_empresa	        VARCHAR(10)		    NOT NULL,													                                    -- Identificador de la empresa                                              -- Identificador (NIT) de la empresa
    cta_empresa         VARCHAR(16)         NOT NULL CHECK(LENGTH(cta_empresa) >= 10 AND LENGTH(cta_empresa) <= 16) DEFAULT '0000000000',   -- Número de cuenta bancaria de la empresa
    id_banco            VARCHAR             NOT NULL,                                                                                           -- Identificador del banco
    ind_tipocuenta      BOOLEAN             NOT NULL DEFAULT FALSE,                                                                         -- TRUE = Corriente / FALSE = Ahorros
    ind_borrado         BOOLEAN             NOT NULL DEFAULT FALSE,                                                                         -- TRUE: Borrado lógico (Inactivo) / FALSE: Activo

    PRIMARY KEY         (id_empresa,cta_empresa),         
    FOREIGN KEY         (id_empresa)        REFERENCES tab_pmtros_grales(id_empresa),   
    FOREIGN KEY         (id_banco)          REFERENCES tab_bancos(id_banco)                                                                             
);

--------------------------------------------------
--        TABLA DE BANCOS POR PROVEEDORES       --
--------------------------------------------------
-- TABLA 5: Tabla de bancos por proveedores
CREATE TABLE IF NOT EXISTS tab_bancoxprov
(
    id_proveedor        VARCHAR(10)         NOT NULL CHECK(id_proveedor ~ '^[1-9][0-9]{7,9}$') DEFAULT '2222222222',                            -- Identificador (NIT) del proveedor
    cta_proveedor       VARCHAR(16)         NOT NULL CHECK(LENGTH(cta_proveedor) >= 10 AND LENGTH(cta_proveedor) <= 16) DEFAULT '0000000000',   -- Número de cuenta bancaria del proveedor
    id_banco            VARCHAR             NOT NULL,                                                                                           -- Identificador del banco 
    ind_tipocuenta      BOOLEAN             NOT NULL DEFAULT FALSE,                                                                             -- TRUE = Corriente / FALSE = Ahorros
    ind_borrado         BOOLEAN             NOT NULL DEFAULT FALSE,                                                                             -- TRUE: Borrado lógico (Inactivo) / FALSE: Activo

    PRIMARY KEY         (id_proveedor,cta_proveedor),                                                                                 
    FOREIGN KEY         (id_proveedor)      REFERENCES tab_proveedores(id_proveedor),
    FOREIGN KEY         (id_banco)          REFERENCES tab_bancos(id_banco)
);

--------------------------------
-- TABLA DE CUENTAS POR PAGAR --
--------------------------------
-- TABLA 6: Tabla de Cuentas por pagar
CREATE TABLE tab_cuentasxpagar
(
    id_factura          DECIMAL(8,0)        NOT NULL CHECK((id_factura) >= 1 AND (id_factura) <= 99999999),                                     -- Identificador de la factura
    id_proveedor        VARCHAR(10)         NOT NULL CHECK(id_proveedor ~ '^[1-9][0-9]{7,9}$') DEFAULT '2222222222',                            -- Identificador (NIT) del proveedor
    id_ordencompra      DECIMAL(6,0)            NULL CHECK (id_ordencompra IS NULL OR id_ordencompra > 0),                                                                 -- Identificador de la orden de compra
    fec_emision         DATE                NOT NULL DEFAULT CURRENT_DATE,                                                                      -- Fecha de emisión de la factura
    fec_vencimiento     DATE                NOT NULL CHECK (fec_vencimiento > fec_emision),                                                     -- FECHA DE PAGO FACTURA (FECHA EMISIÓN + DIAS DE PAGO)
    val_factura         DECIMAL(10,0)       NOT NULL CHECK((val_factura) >= 0 AND (val_factura) <= 9999999999),                                 -- Monto total de la factura
    val_saldo           DECIMAL(10,0)       NOT NULL CHECK((val_saldo >= 0) AND (val_saldo <= 9999999999)),                                     -- Valor restante para terminar de pagar la factura
    num_cuotas          DECIMAL(2,0)        NOT NULL CHECK((num_cuotas) >= 1 AND (num_cuotas) <= 99),                                           -- Número de cuotas totales en las que se acordó la factura
    ind_estado          BOOLEAN             NOT NULL DEFAULT FALSE,                                                                             -- TRUE = Pagado O FALSE = En deuda

    PRIMARY KEY         (id_factura),                                                                                           
    FOREIGN KEY         (id_proveedor)      REFERENCES tab_proveedores(id_proveedor),
    FOREIGN KEY         (id_ordencompra)    REFERENCES tab_enc_ordcomp(id_ordencompra)  
);
-- Consultas tipo: "facturas pendientes de un proveedor"
CREATE INDEX idx_facturas_proveedor         ON tab_cuentasxpagar(id_proveedor);

-- Consultas tipo: "facturas vencidas hoy"
CREATE INDEX idx_facturas_vencimiento       ON tab_cuentasxpagar(fec_vencimiento);

-- Consultas tipo: "todas las facturas pendientes"
CREATE INDEX idx_facturas_estado            ON tab_cuentasxpagar(ind_estado);

------------------------------
-- TABLA DE CUOTAS FACTURAS --
------------------------------
-- TABLA 7: Tabla de cuotas por facturas
CREATE TABLE tab_cuotasxfactura
(
    id_factura          DECIMAL(8,0)        NOT NULL CHECK((id_factura) >= 1 AND (id_factura) <= 99999999),                     -- Identificador de la factura
    id_cuota            DECIMAL(2,0)        NOT NULL CHECK((id_cuota) >= 1 AND (id_cuota) <= 99),                               -- Número de cuota de la factura
    fec_vencimiento     DATE 				NOT NULL,                                                                           -- Fecha en la que vence cada cuota
    val_cuota           DECIMAL(10,0)       NOT NULL CHECK((val_cuota) >= 0 AND (val_cuota) <= 9999999999),                     -- Monto total de la factura
    ind_pagada          BOOLEAN             NOT NULL DEFAULT FALSE,                                                             -- TRUE = Pagado / FALSE = Pendiente

    PRIMARY KEY(id_factura,id_cuota),
    FOREIGN KEY(id_factura)                 REFERENCES tab_cuentasxpagar(id_factura)  
);
-- Consultas tipo: "cuotas pendientes de esta factura"
CREATE INDEX idx_cuotas_pagada ON tab_cuotasxfactura(ind_pagada);

-- Consultas tipo: "cuotas que vencen esta semana"
CREATE INDEX idx_cuotas_vencimiento ON tab_cuotasxfactura(fec_vencimiento);

------------------------------------------------
-- TABLA DE ENCABEZADO DE CRONOGRAMA DE PAGOS --
------------------------------------------------
-- TABLA 8: Tabla de encabezado cronograma de pagos
CREATE TABLE tab_enc_cronopagos
(
    id_cronograma       DECIMAL(10,0) 		NOT NULL CHECK((id_cronograma) >= 0 AND (id_cronograma) <= 9999999999),             -- Identificador del cronograma
    nom_cronograma      VARCHAR(30)         NOT NULL CHECK(LENGTH(nom_cronograma) >= 3 AND (LENGTH(nom_cronograma) <= 30)) DEFAULT 'Cronograma de pago',   -- Nombre del cronograma de pago
    fec_programacion    DATE                NOT NULL,                                                                           -- Fecha para la cual se planificó pagar dicho cronograma (la app valida que sea futura al crearlo)
    total_a_pagar       DECIMAL(10,0)       NOT NULL CHECK((total_a_pagar) >= 0 AND (total_a_pagar) <= 9999999999),             -- Monto total a pagar por ese cronograma
    ind_estado          BOOLEAN             NOT NULL DEFAULT FALSE,                                                             -- TRUE = Pagado / FALSE = Pendiente
	ind_borrado         BOOLEAN             NOT NULL DEFAULT FALSE,                                                             -- TRUE: Borrado lógico (Inactivo) / FALSE: Activo

    PRIMARY KEY(id_cronograma)
);
-- Consultas tipo: "fecha en las que se va a realizar un cronograma"
CREATE INDEX idx_crono_fec_prog ON tab_enc_cronopagos(fec_programacion);

-- Consultas tipo: "cronogramas pendientes o pagados"
CREATE INDEX idx_crono_estado   ON tab_enc_cronopagos(ind_estado);

---------------------------------------------
-- TABLA DE DETALLE DE CRONOGRAMA DE PAGOS --
---------------------------------------------
-- TABLA 9: Tabla de detalle de cronograma de pagos
CREATE TABLE tab_det_cronopagos
(
    id_cronograma       DECIMAL(10,0) 		NOT NULL CHECK((id_cronograma) >= 0 AND (id_cronograma) <= 9999999999),             						   -- Identificador del cronograma
	id_factura          DECIMAL(8,0)        NOT NULL CHECK((id_factura) >= 1 AND (id_factura) <= 99999999),                     						   -- Identificador de la factura
    id_cuota            DECIMAL(2,0)        NOT NULL CHECK((id_cuota) >= 1 AND (id_cuota) <= 99),                              						       -- Número de cuota que se va a pagar en el cronograma
    val_a_pagar         DECIMAL(10,0)       NOT NULL CHECK((val_a_pagar) >= 0 AND (val_a_pagar) <= 9999999999),                                            -- Monto a pagar por cada cuota factura

    PRIMARY KEY(id_cronograma,id_factura,id_cuota),
    FOREIGN KEY(id_cronograma)              REFERENCES tab_enc_cronopagos(id_cronograma),
    FOREIGN KEY(id_factura,id_cuota)        REFERENCES tab_cuotasxfactura(id_factura,id_cuota)
    -- Sin UNIQUE (id_factura, id_cuota): una cuota que el banco RECHAZÓ se
    -- programa en un cronograma nuevo. fun_insert_det_cronopagos valida que no
    -- esté en otro cronograma salvo que allí haya sido rechazada.
);
-- Consultas tipo: "¿en qué cronogramas ha estado esta cuota?"
CREATE INDEX idx_det_cronopagos_cuota ON tab_det_cronopagos(id_factura, id_cuota);

------------------------------------------
-- TABLA DE ENCABEZADO DE ARCHIVO PLANO --
------------------------------------------
-- TABLA 10: Tabla de encabezado de archivo plano
CREATE TABLE tab_enc_archivo_plano 
(
    id_archivo_plano      DECIMAL(10,0) NOT NULL CHECK((id_archivo_plano) >= 0 AND (id_archivo_plano) <= 9999999999),                       -- Identificador del archivo plano
    nom_archivo           VARCHAR(30)   NOT NULL CHECK(LENGTH(nom_archivo) >= 3 AND (LENGTH(nom_archivo) <= 30)) DEFAULT 'archivo_plano',   -- Nombre del archivo plano
    id_empresa	          VARCHAR(10)	NOT NULL,													                                        -- Identificador de la empresa
    nom_empresa	          VARCHAR       NOT NULL CHECK(LENGTH(nom_empresa) >= 5 AND LENGTH(nom_empresa) <= 60),                             -- Nombre de la empresa
    id_banco              VARCHAR       NOT NULL,                                                                                           -- Identificador del banco
    ind_tipocuenta        BOOLEAN       NOT NULL DEFAULT FALSE,                                                                             -- TRUE = Corriente / FALSE = Ahorros
    cta_empresa           VARCHAR(16)   NOT NULL CHECK(LENGTH(cta_empresa) >= 10 AND LENGTH(cta_empresa) <= 16),                            -- Número de cuenta bancaria de la empresa de la cuál va a salir el dinero
    fecha_aplicacion      DATE          NOT NULL DEFAULT CURRENT_DATE,
    fec_generacion        DATE,                                                                                                             -- Fecha de generación del archivo(NULL Si no se ha creado)
    ind_generado          BOOLEAN       NOT NULL DEFAULT FALSE,                                                                             -- Indicador de generado del archivo

    PRIMARY KEY(id_archivo_plano),
    FOREIGN KEY(id_empresa,cta_empresa)     REFERENCES tab_ctas_empresa(id_empresa,cta_empresa),
    FOREIGN KEY(id_banco)                   REFERENCES tab_bancos(id_banco)
);
-- Consultas tipo: "archivos planos que se hayan generado o no"
CREATE INDEX idx_archplano_generado ON tab_enc_archivo_plano(ind_generado);

------------------------------------
-- TABLA DE DETALLE ARCHIVO PLANO --
------------------------------------
-- TABLA 11: Tabla de detalle de archivo plano
CREATE TABLE tab_det_archivo_plano 
(
    id_archivo_plano            DECIMAL(10,0)  NOT NULL CHECK((id_archivo_plano) >= 0 AND (id_archivo_plano) <= 9999999999),    -- Identificador del archivo plano
    id_cronograma               DECIMAL(10,0)  NOT NULL CHECK((id_cronograma) >= 0 AND (id_cronograma) <= 9999999999),          -- Identificador del cronograma
    id_factura                  DECIMAL(8,0)   NOT NULL CHECK((id_factura) >= 1 AND (id_factura) <= 99999999),                  -- Identificador de la factura
    id_cuota                    DECIMAL(2,0)   NOT NULL CHECK((id_cuota) >= 1 AND (id_cuota) <= 99),                            -- Número de cuota que se va a pagar en el cronograma
    -- ID FACTURA E ID CUOTA NO SE VE REFLEJADO EN EL ARCHIVO PLANO PORQUE AL BANCO NO LE INTERESA SABER ESTO PARA PAGAR, SOLO ESTÁ AGREGADO
    -- PODER TENER EL CONTROL DE LAS FACTURAS AÑADIDAS AL ARCHIVO PLANO.

    id_tipo        		        VARCHAR(5)     NOT NULL CHECK(id_tipo ~ '^[A-Z]{2,5}$'),                                   --  tipo de documento
    id_proveedor                VARCHAR(10)    NOT NULL CHECK(id_proveedor ~ '^[A-Z0-9]{7,10}$'),                                                                               -- Identificador del proveedor (ID empresa)
    nom_tercero			        VARCHAR	       NOT NULL CHECK(LENGTH(nom_tercero) >= 4 AND LENGTH(nom_tercero) <= 50),	    --  nombre del tercero
    id_banco                    VARCHAR        NOT NULL,                                                                                           -- Identificador del banco
    ind_tipocuenta              BOOLEAN        NOT NULL DEFAULT FALSE,                                                                             -- TRUE = Corriente / FALSE = Ahorros
    cta_proveedor               VARCHAR(16)    NOT NULL CHECK(LENGTH(cta_proveedor) >= 10 AND LENGTH(cta_proveedor) <= 16),   -- Número de cuenta de destino para pagar
    val_a_pagar                 NUMERIC(10,0)  NOT NULL CHECK((val_a_pagar) > 0 ),  
    concepto                    VARCHAR(80),

    PRIMARY KEY(id_archivo_plano,id_cronograma,id_factura,id_cuota),
    FOREIGN KEY(id_archivo_plano)                   REFERENCES tab_enc_archivo_plano(id_archivo_plano),
    FOREIGN KEY(id_cronograma,id_factura,id_cuota)  REFERENCES tab_det_cronopagos(id_cronograma,id_factura,id_cuota),
    FOREIGN KEY(id_proveedor,cta_proveedor)         REFERENCES tab_bancoxprov(id_proveedor,cta_proveedor),
    FOREIGN KEY(id_banco)                           REFERENCES tab_bancos(id_banco)
    -- Sin UNIQUE (id_factura, id_cuota): una cuota RECHAZADA puede ir a otro archivo
    -- plano. fun_insert_det_archivo_plano valida que no esté en otro archivo vigente.
);
-- Consultas tipo: "¿en qué archivos planos ha estado esta cuota?"
CREATE INDEX idx_detarch_cuota ON tab_det_archivo_plano(id_factura, id_cuota);

--------------------------------------------------------------------------------------------------------------------------------------
-- INTEGRACIÓN CON NÓMINA (modules/gehnom → Liquidar Nómina → "Enviar a Tesorería")
-- Requiere las columnas estado_pago, fec_pago e id_archivo_plano en tab_nomina
--------------------------------------------------------------------------------------------------------------------------------------
-- TABLA 12: DETALLE DEL ARCHIVO PLANO DE NÓMINA
--------------------------------------------------------------------------------------------------------------------------------------
-- Una línea por empleado. Igual que tab_det_archivo_plano, guarda una COPIA
-- de los datos bancarios del día del envío: si después cambian en
-- tab_empleados, el archivo sigue reflejando lo que se mandó al banco.
CREATE TABLE tab_det_archivo_nomina
(
    id_archivo_plano    DECIMAL(10,0)   NOT NULL CHECK(id_archivo_plano >= 0 AND id_archivo_plano <= 9999999999),
    ano_nomina          DECIMAL(4,0)    NOT NULL,
    mes_nomina          DECIMAL(2,0)    NOT NULL CHECK(mes_nomina BETWEEN 1 AND 12),
    val_periodo         DECIMAL(1,0)    NOT NULL CHECK(val_periodo IN (1, 2)),
    id_empleado         VARCHAR(10)     NOT NULL,
    id_tipo             VARCHAR(5)      NOT NULL CHECK(id_tipo ~ '^[A-Z]{2,5}$'),                       -- Tipo de documento del empleado
    nom_empleado        VARCHAR(100)    NOT NULL CHECK(LENGTH(nom_empleado) >= 3),                      -- Nombres + apellidos
    id_banco            VARCHAR         NOT NULL,                                                       -- Banco de destino
    ind_tipocuenta      BOOLEAN         NOT NULL DEFAULT FALSE,                                         -- TRUE = Corriente / FALSE = Ahorros
    num_cuenta          VARCHAR(20)     NOT NULL CHECK(num_cuenta ~ '^[0-9]{6,20}$'),                   -- Cuenta de destino
    val_a_pagar         NUMERIC(10,0)   NOT NULL CHECK(val_a_pagar > 0),                                -- val_neto de tab_nomina
    concepto            VARCHAR(80),

    PRIMARY KEY (id_archivo_plano, ano_nomina, mes_nomina, val_periodo, id_empleado),
    FOREIGN KEY (id_archivo_plano)                                  REFERENCES tab_enc_archivo_plano(id_archivo_plano),
    FOREIGN KEY (ano_nomina, mes_nomina, val_periodo, id_empleado)  REFERENCES tab_nomina(ano_nomina, mes_nomina, val_periodo, id_empleado),
    FOREIGN KEY (id_banco)                                          REFERENCES tab_bancos(id_banco)
);
-- Consultas tipo: "¿en qué archivos ha ido este empleado en esta quincena?"
CREATE INDEX idx_detnom_empleado ON tab_det_archivo_nomina(ano_nomina, mes_nomina, val_periodo, id_empleado);

--------------------------------------------------------------------------------------------------------------------------------------
-- INTEGRACIÓN CON EL ÁREA FINANCIERA (pago de inversiones)
-- Financiero envía sus cuotas aprobadas con fun_enviar_inversiones_tesoreria.
-- El ENCABEZADO es el normal (tab_enc_archivo_plano, sin columnas extra): lo
-- que distingue un archivo de inversiones es que sus líneas están aquí.
-- Requiere tab_cuotas_inversion (módulo Financiero, con estado_pago, fec_pago
-- e id_archivo_plano) y los datos bancarios en tab_inversores: este script se
-- corre DESPUÉS del de Financiero.
--------------------------------------------------------------------------------------------------------------------------------------
-- TABLA 13: DETALLE DEL ARCHIVO PLANO DE INVERSIONES
--------------------------------------------------------------------------------------------------------------------------------------
-- Una línea por cuota. Igual que tab_det_archivo_nomina, guarda una COPIA de
-- los datos bancarios del día del envío: si después cambian en
-- tab_inversores, el archivo sigue reflejando lo que se mandó al banco.
CREATE TABLE tab_det_archivo_inversion
(
    id_archivo_plano    DECIMAL(10,0)   NOT NULL CHECK(id_archivo_plano >= 0 AND id_archivo_plano <= 9999999999),
    id_proyecto         VARCHAR         NOT NULL,
    id_inversor         VARCHAR(10)     NOT NULL,
    id_cuota            DECIMAL(3,0)    NOT NULL,
    id_tipo             VARCHAR(5)      NOT NULL CHECK(id_tipo ~ '^[A-Z]{2,5}$'),                       -- Tipo de documento del inversor
    nom_inversor        VARCHAR(100)    NOT NULL CHECK(LENGTH(nom_inversor) >= 3),
    id_banco            VARCHAR         NOT NULL,                                                       -- Banco de destino
    ind_tipocuenta      BOOLEAN         NOT NULL DEFAULT FALSE,                                         -- TRUE = Corriente / FALSE = Ahorros
    num_cuenta          VARCHAR(20)     NOT NULL CHECK(num_cuenta ~ '^[0-9]{6,20}$'),                   -- Cuenta de destino
    val_a_pagar         NUMERIC(10,0)   NOT NULL CHECK(val_a_pagar > 0),                                -- val_neto de tab_cuotas_inversion
    concepto            VARCHAR(80),

    PRIMARY KEY (id_archivo_plano, id_proyecto, id_inversor, id_cuota),
    FOREIGN KEY (id_archivo_plano)                      REFERENCES tab_enc_archivo_plano(id_archivo_plano),
    FOREIGN KEY (id_proyecto, id_inversor, id_cuota)    REFERENCES tab_cuotas_inversion(id_proyecto, id_inversor, id_cuota),
    FOREIGN KEY (id_banco)                              REFERENCES tab_bancos(id_banco)
);
-- Consultas tipo: "¿en qué archivos ha ido esta cuota?"
CREATE INDEX idx_detinv_cuota ON tab_det_archivo_inversion(id_proyecto, id_inversor, id_cuota);

-------------------------------------
-- TABLA DE MOTIVOS DE RECHAZO     --
-------------------------------------
-- TABLA 14: Catálogo de respuestas de bancos. Lo usa tab_pagos
-- ind_borrado permite dar de baja un motivo sin romper los registros históricos.
CREATE TABLE tab_codigos_respuesta_banco
(
    id_codigo       		VARCHAR(10)  NOT NULL CHECK(LENGTH(id_codigo) >= 1 AND LENGTH(id_codigo) <= 10),   -- Código que devuelve el banco
	id_banco                VARCHAR      NOT NULL,
    des_motivo              VARCHAR(100) NOT NULL CHECK(LENGTH(des_motivo) >= 3),               -- Descripción del motivo
    ind_borrado             BOOLEAN      NOT NULL DEFAULT FALSE,                                -- TRUE: Borrado lógico (Inactivo) / FALSE: Activo

    PRIMARY KEY (id_codigo,id_banco),
	FOREIGN KEY (id_banco)                REFERENCES tab_bancos(id_banco)
);

-----------------------
-- TABLA DE PAGOS    --
-----------------------
-- TABLA 15: registra cada intento de pago de una CUOTA DE FACTURA (aprobado o
-- rechazado). 
-- Nunca se borra un intento rechazado.
-- Alcance: aquí van únicamente los pagos de cuotas. Caja menor y sus
-- reembolsos NO entran a esta tabla (ver tab_det_caja_menor).
-- estado_pago: 1 = PENDIENTE, 2 = APROBADO, 3 = RECHAZADO.
-- Al aprobar, fun_insert_pagos_cxp / fun_update_pagos_cxp marcan la cuota como
-- pagada y cierran el cronograma; los triggers descuentan los saldos.
CREATE TABLE tab_pagos_cxp
(
    id_pago             DECIMAL(10,0) NOT NULL CHECK(id_pago >= 1 AND id_pago <= 9999999999),
    id_factura          DECIMAL(8,0)  NOT NULL,
    id_cuota            DECIMAL(2,0)  NOT NULL,
    id_archivo_plano    DECIMAL(10,0) NOT NULL,
	id_cronograma       DECIMAL(10,0) NOT NULL,
    fec_pago            DATE          NOT NULL DEFAULT CURRENT_DATE,                                    -- un pago se registra cuando ya ocurrió; la app valida que no sea futura al registrarlo
    val_pago            DECIMAL(10,0) NOT NULL CHECK(val_pago > 0 AND val_pago <= 9999999999),
    estado_pago         DECIMAL(1,0)  NOT NULL DEFAULT 1 CHECK(estado_pago IN (1,2,3)),
    id_codigo       	VARCHAR(10)   NOT NULL CHECK(LENGTH(id_codigo) >= 1 AND LENGTH(id_codigo) <= 10),   -- Código que devuelve el banco
	id_banco            VARCHAR       NOT NULL,                                                         -- Banco que respondió (el de la cuenta de origen del archivo plano)

    PRIMARY KEY (id_pago),
    FOREIGN KEY (id_factura, id_cuota)                                  REFERENCES tab_cuotasxfactura(id_factura, id_cuota),
    FOREIGN KEY (id_archivo_plano,id_cronograma,id_factura,id_cuota)    REFERENCES tab_det_archivo_plano(id_archivo_plano,id_cronograma,id_factura,id_cuota),
    FOREIGN KEY (id_codigo, id_banco)                                   REFERENCES tab_codigos_respuesta_banco(id_codigo, id_banco)
);
-- Una cuota solo puede tener UN pago APROBADO. El índice es parcial a propósito:
-- los intentos RECHAZADOS no cuentan, así una cuota se puede reintentar las veces
-- que haga falta, pero aprobarse una sola vez.
CREATE UNIQUE INDEX uq_pago_aprobado_cuota ON tab_pagos_cxp(id_factura, id_cuota) WHERE estado_pago = 2;


--------------------------------------------------------------------------------------------------------------------------------------
-- TABLA 16: PAGOS DE NÓMINA (respuesta del banco por empleado)
--------------------------------------------------------------------------------------------------------------------------------------
-- Mismo modelo que tab_pagos_cxp: cada intento queda registrado (aprobado o
-- rechazado) y nunca se borra un rechazo.
-- estado_pago: 1 = PENDIENTE, 2 = APROBADO, 3 = RECHAZADO.
CREATE TABLE tab_pagos_nomina
(
    id_pago_nomina      DECIMAL(10,0)   NOT NULL CHECK(id_pago_nomina >= 1 AND id_pago_nomina <= 9999999999),
    id_archivo_plano    DECIMAL(10,0)   NOT NULL,
    ano_nomina          DECIMAL(4,0)    NOT NULL,
    mes_nomina          DECIMAL(2,0)    NOT NULL,
    val_periodo         DECIMAL(1,0)    NOT NULL,
    id_empleado         VARCHAR(10)     NOT NULL,
    fec_pago            DATE            NOT NULL DEFAULT CURRENT_DATE,
    val_pago            DECIMAL(10,0)   NOT NULL CHECK(val_pago > 0 AND val_pago <= 9999999999),
    estado_pago         DECIMAL(1,0)    NOT NULL DEFAULT 1 CHECK(estado_pago IN (1, 2, 3)),
    id_codigo           VARCHAR(10)     NOT NULL CHECK(LENGTH(id_codigo) >= 1 AND LENGTH(id_codigo) <= 10),
    id_banco            VARCHAR         NOT NULL,                                                       -- Banco que respondió (el de la cuenta de origen)

    PRIMARY KEY (id_pago_nomina),
    FOREIGN KEY (id_archivo_plano, ano_nomina, mes_nomina, val_periodo, id_empleado)
                REFERENCES tab_det_archivo_nomina(id_archivo_plano, ano_nomina, mes_nomina, val_periodo, id_empleado),
    FOREIGN KEY (id_codigo, id_banco) REFERENCES tab_codigos_respuesta_banco(id_codigo, id_banco)
);
-- Un empleado solo puede tener UN pago APROBADO por periodo (los rechazos no cuentan).
CREATE UNIQUE INDEX uq_pago_nomina_aprobado
    ON tab_pagos_nomina(ano_nomina, mes_nomina, val_periodo, id_empleado) WHERE estado_pago = 2;


--------------------------------------------------------------------------------------------------------------------------------------
-- TABLA 17: PAGOS DE INVERSIONES (respuesta del banco por cuota)
--------------------------------------------------------------------------------------------------------------------------------------
-- Mismo modelo que tab_pagos_cxp y tab_pagos_nomina: cada intento queda
-- registrado (aprobado o rechazado) y nunca se borra un rechazo.
-- estado_pago: 1 = PENDIENTE, 2 = APROBADO, 3 = RECHAZADO.
CREATE TABLE tab_pagos_inversion
(
    id_pago_inversion   DECIMAL(10,0)   NOT NULL CHECK(id_pago_inversion >= 1 AND id_pago_inversion <= 9999999999),
    id_archivo_plano    DECIMAL(10,0)   NOT NULL,
    id_proyecto         VARCHAR         NOT NULL,
    id_inversor         VARCHAR(10)     NOT NULL,
    id_cuota            DECIMAL(3,0)    NOT NULL,
    fec_pago            DATE            NOT NULL DEFAULT CURRENT_DATE,
    val_pago            DECIMAL(10,0)   NOT NULL CHECK(val_pago > 0 AND val_pago <= 9999999999),
    estado_pago         DECIMAL(1,0)    NOT NULL DEFAULT 1 CHECK(estado_pago IN (1, 2, 3)),
    id_codigo           VARCHAR(10)     NOT NULL CHECK(LENGTH(id_codigo) >= 1 AND LENGTH(id_codigo) <= 10),
    id_banco            VARCHAR         NOT NULL,                                                       -- Banco que respondió (el de la cuenta de origen)

    PRIMARY KEY (id_pago_inversion),
    FOREIGN KEY (id_archivo_plano, id_proyecto, id_inversor, id_cuota)
                REFERENCES tab_det_archivo_inversion(id_archivo_plano, id_proyecto, id_inversor, id_cuota),
    FOREIGN KEY (id_codigo, id_banco) REFERENCES tab_codigos_respuesta_banco(id_codigo, id_banco)
);
-- Una cuota solo puede tener UN pago APROBADO (los rechazos no cuentan).
CREATE UNIQUE INDEX uq_pago_inversion_aprobado
    ON tab_pagos_inversion(id_proyecto, id_inversor, id_cuota) WHERE estado_pago = 2;





---------
-- 7. CONFIGURACIÓN DEL SEARCH_PATH (Ruta de Búsqueda)
-- Esto permite que los módulos accedan a 'public' sin prefijo.
-- Se establece el path por defecto para que las consultas busquen 
-- primero en 'public' y luego en el esquema actual de la sesión.
-- (Aunque las aplicaciones siempre deberían usar el prefijo por seguridad, 
-- esta es una configuración común).
-- ---------------------------------------------------

-- Ejemplo de configuración para un usuario específico (opcional, pero recomendado 
-- si se crean roles específicos para cada módulo).
-- ALTER USER app_user SET search_path TO "$user", public;

-- Configuración general de la base de datos (para quien no tenga un path definido)
--ALTER DATABASE db_erpadso SET search_path TO public, "$user";

-- ---------------------------------------------------------------------
-- 8. CREACIÓN DE TRIGGER DE AUDITORÍA PARA LAS TABLAS. ESTRUCTURA TYPE
------------------------------------------------------------------------

-- ---------------------------------------------------
-- 02_create_audit_trail.sql
-- Creación de la tabla de registros de auditoría 
-- y la función de trigger.
-- ---------------------------------------------------
-- DATA INICIAL DE PRUEBA
-- (usuarios 14-nov) columnas explícitas: antes era posicional y los TRUE caían en foto_usuario y firma_electronica.
-- ind_primer_vez queda en TRUE (por defecto): la clave inicial se debe cambiar en el primer ingreso.
INSERT INTO tab_usuarios (id_usuario, nom_usuario, pass_usuario, mail_usuario, ind_admin, ind_estado)
VALUES('admin','Administrador del Sistema',CRYPT('Admin123456!', GEN_SALT('bf')),
       'admin@correo.edu',TRUE,TRUE)
ON CONFLICT (id_usuario) DO NOTHING;

-- CREACIÓN DE EXTENSIÓN PARA ENCRIPTACIÓN
CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- ENCRIPTAR CLAVE DE ADMIN
UPDATE tab_usuarios SET pass_usuario = crypt('Admin123456!', gen_salt('bf')) 
WHERE id_usuario = 'admin';
-- ---------------------------------------------------
-- 9. CREAR LA TABLA CENTRAL DE REGISTROS DE AUDITORÍA
-- Ubicada en 'public' para un acceso sencillo desde todos los esquemas.
-- ---------------------------------------------------
CREATE TABLE tab_audit_trail
(
    id_auditoria            BIGSERIAL                   NOT NULL,
    id_usuario              VARCHAR,                                              -- Usuario ERP autenticado (tab_usuarios.id_usuario); NULL si no hubo sesión activa
    ip_conexion             VARCHAR,                                              -- IP de la conexión que ejecutó el cambio; se captura siempre que sea posible
    nom_operacion           CHAR(2)                     NOT NULL,                  -- Tipo de operación auditada
    fec_operacion           TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    dato_viejo              JSONB                       NOT NULL,                 -- En UPDATE: solo columnas que cambiaron (OLD). En borrados: fila completa (OLD)
    dato_nuevo              JSONB                       NOT NULL,                 -- En UPDATE: solo columnas que cambiaron (NEW). En BORRADO_FISICO: se repite OLD
    nom_tabla               VARCHAR                     NOT NULL,                 -- Tabla origen del cambio (TG_TABLE_NAME)
    PRIMARY KEY (id_auditoria),
    CONSTRAINT chk_audit_usuario CHECK (id_usuario IS NOT NULL OR ip_conexion IS NOT NULL)
);

-- Índices de apoyo para las consultas más frecuentes de auditoría: por tabla+fecha, por usuario y por IP.
CREATE INDEX IF NOT EXISTS idx_audit_tabla_fecha ON tab_audit_trail (nom_tabla, fec_operacion DESC);

-- ----------------------------------
-- FUNCIÓN DE TRIGGER DE AUDITORÍA --
-- ----------------------------------


CREATE OR REPLACE FUNCTION fun_audit_trail() RETURNS TRIGGER AS $$
DECLARE
    wid_usuario         tab_usuarios.id_usuario%TYPE;  -- Esto es TEXT
    wip                 VARCHAR;
    woperacion          varchar;
    wind_borrado        BOOLEAN;
    wold_borrado        BOOLEAN;
    wnew_borrado        BOOLEAN;
    old_diff            JSONB;
    new_diff            JSONB;
BEGIN
    -- 1. Recuperar el ID de usuario desde las variables de sesión (TEXTO)
    wid_usuario := COALESCE(current_setting('myapp.user_id', TRUE), '0');

    -- 2. Si no se recibió o es '0', asignar un usuario por defecto que EXISTA en tab_usuarios
    IF wid_usuario = '0' OR wid_usuario IS NULL OR wid_usuario = '' THEN
        wid_usuario := 'admin';   -- Cambia por un ID real que exista en tu tabla
    END IF;

    -- 3. IP
    wip := COALESCE(current_setting('myapp.user_ip', TRUE), '0.0.0.0');
	 IF wip = '::1' OR wip = '127.0.0.1' THEN
        wip := 'localhost';
    END IF;

    -- 4. Validar que el usuario exista en tab_usuarios (comparación TEXT vs TEXT)
    IF NOT EXISTS (SELECT 1 FROM tab_usuarios WHERE id_usuario = wid_usuario) THEN
        -- Si no existe, asignar un fallback (por ejemplo, 'admin')
        wid_usuario := 'admin';
        RAISE NOTICE 'Usuario % no encontrado, usando admin', wid_usuario;
    END IF;

    -- 5. Lógica para INSERT
    IF (TG_OP = 'INSERT') THEN 
        INSERT INTO tab_audit_trail (id_usuario, ip_conexion, nom_operacion, dato_viejo, dato_nuevo, nom_tabla)
        VALUES (wid_usuario, wip, 'I', '{}'::jsonb, to_jsonb(NEW), TG_TABLE_NAME);
        RETURN NEW;
    END IF;

    -- 6. Lógica para DELETE
    IF (TG_OP = 'DELETE') THEN
        INSERT INTO tab_audit_trail (id_usuario, ip_conexion, nom_operacion, dato_viejo, dato_nuevo, nom_tabla)
        VALUES (wid_usuario, wip, 'DF', to_jsonb(OLD), '{}'::jsonb, TG_TABLE_NAME); 
        RETURN OLD;
    END IF;

    -- 7. Lógica para UPDATE (detectando borrado lógico)
    wind_borrado := (to_jsonb(NEW) ? 'ind_borrado');
    IF wind_borrado THEN
        wold_borrado := (to_jsonb(OLD)->>'ind_borrado')::BOOLEAN;
        wnew_borrado := (to_jsonb(NEW)->>'ind_borrado')::BOOLEAN;
        
        IF (wold_borrado = FALSE AND wnew_borrado = TRUE) THEN
            woperacion := 'BL';
        ELSIF (wold_borrado = TRUE AND wnew_borrado = FALSE) THEN
            woperacion := 'R';
        ELSE
            woperacion := 'U';
        END IF;
    ELSE
        woperacion := 'U'; 
    END IF;

    -- 8. Calcular diferencias (JSONB)
     IF woperacion IN ('U', 'BL', 'R') THEN
        IF to_jsonb(OLD) IS DISTINCT FROM to_jsonb(NEW) THEN
            SELECT jsonb_object_agg(o.key, o.value) INTO old_diff
            FROM jsonb_each(to_jsonb(OLD)) o
            WHERE to_jsonb(OLD) -> o.key IS DISTINCT FROM to_jsonb(NEW) -> o.key;
            
            SELECT jsonb_object_agg(n.key, n.value) INTO new_diff
            FROM jsonb_each(to_jsonb(NEW)) n
            WHERE to_jsonb(OLD) -> n.key IS DISTINCT FROM to_jsonb(NEW) -> n.key;
        ELSE
            old_diff := to_jsonb(OLD);
            new_diff := to_jsonb(NEW);
        END IF;
    ELSE
        old_diff := to_jsonb(OLD);
        new_diff := to_jsonb(NEW);
    END IF;

    -- 9. Enmascarar datos sensibles
    IF TG_TABLE_NAME = 'tab_usuarios' THEN
        old_diff := old_diff - 'pass_usuario';
        new_diff := new_diff - 'pass_usuario';
    END IF;

    -- 10. Insertar en la tabla de auditoría
    INSERT INTO tab_audit_trail (id_usuario, ip_conexion, nom_operacion, dato_viejo, dato_nuevo, nom_tabla)
    VALUES (wid_usuario, wip, woperacion, old_diff, new_diff, TG_TABLE_NAME);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TABLE IF NOT EXISTS tab_config_dashboard (
    id_widget       VARCHAR(30)     PRIMARY KEY,
    nom_widget      VARCHAR(100)    NOT NULL,
    ind_activo      BOOLEAN         NOT NULL DEFAULT TRUE,
    orden           INTEGER         NOT NULL DEFAULT 0
);

-- Insertar los widgets disponibles por defecto (todos activos)
INSERT INTO tab_config_dashboard (id_widget, nom_widget, ind_activo, orden) VALUES
('reloj_fecha', 'Reloj y Fecha en Vivo', TRUE, 1),
('trm_dolar', 'Precio del Dólar (TRM Colombia)', TRUE, 2),
('clima_local', 'Clima Local (Bogotá)', TRUE, 3),
('tips_dia', 'Tips y Mensajes del Día', TRUE, 4),
('accesos_rapidos', 'Accesos Rápidos a Módulos', TRUE, 5)
ON CONFLICT (id_widget) DO NOTHING;


-- SECURITY DEFINER: el trigger se ejecuta con los permisos de quien creó la función,
-- garantizando que cualquier usuario de la app pueda insertar en tab_audit_trail
-- sin necesidad de otorgarle permisos directos sobre esa tabla.


-- Notificaciones: módulos que generan alertas
CREATE TABLE IF NOT EXISTS tab_modulo_alerta
(
    cod_modulo                VARCHAR(20)             NOT NULL,
    nom_modulo                VARCHAR(60)             NOT NULL,
    txt_icono                 VARCHAR(40)             NOT NULL DEFAULT 'fa-bell',
    txt_destinatario          VARCHAR(120)            NOT NULL,
    txt_fecha_vigilada        VARCHAR(160)            NOT NULL,
    val_dias_max              DECIMAL(2,0)            NOT NULL,
    ind_copia_jefe            BOOLEAN                 NOT NULL DEFAULT false,
    txt_mensaje_defecto       VARCHAR(300)            NOT NULL,
    num_orden                 DECIMAL(2,0)            NOT NULL DEFAULT 99,
    ind_borrado               BOOLEAN                 NOT NULL DEFAULT false,
    ind_estado                BOOLEAN                 NOT NULL DEFAULT true,
    ind_configurable          BOOLEAN                 NOT NULL DEFAULT false,
    txt_tabla                 VARCHAR(63),
    txt_col_codigo            VARCHAR(63),
    txt_col_nombre            VARCHAR(63),
    txt_col_fecha             VARCHAR(63),
    val_tipo_destino          VARCHAR(7),
    txt_col_destino           VARCHAR(63),
    txt_col_estado            VARCHAR(63),
    txt_estados_cierre        VARCHAR(300),
    txt_programa              VARCHAR(120),
    id_usuario_registro       VARCHAR,
    fec_registro              TIMESTAMPTZ,
    ind_completo              BOOLEAN                 NOT NULL DEFAULT true,
    CONSTRAINT tab_modulo_alerta_pkey PRIMARY KEY (cod_modulo),
    CONSTRAINT fk_modulo_alerta_usuario FOREIGN KEY (id_usuario_registro) REFERENCES tab_usuarios(id_usuario),
    CONSTRAINT ck_modulo_alerta_fuente CHECK (((ind_configurable = false) OR ((txt_tabla IS NOT NULL) AND (txt_col_codigo IS NOT NULL) AND (txt_col_nombre IS NOT NULL) AND (txt_col_fecha IS NOT NULL) AND ((val_tipo_destino)::text = ANY (ARRAY[('USUARIO'::character varying)::text, ('AREA'::character varying)::text])) AND (txt_col_destino IS NOT NULL) AND (txt_programa IS NOT NULL)))),
    CONSTRAINT tab_modulo_alerta_cod_modulo_check CHECK (((cod_modulo)::text ~ '^[A-Z_]{3,20}$'::text)),
    CONSTRAINT tab_modulo_alerta_nom_modulo_check CHECK (((char_length(TRIM(BOTH FROM nom_modulo)) >= 3) AND (char_length(TRIM(BOTH FROM nom_modulo)) <= 60))),
    CONSTRAINT tab_modulo_alerta_txt_destinatario_check CHECK (((char_length(TRIM(BOTH FROM txt_destinatario)) >= 3) AND (char_length(TRIM(BOTH FROM txt_destinatario)) <= 120))),
    CONSTRAINT tab_modulo_alerta_txt_fecha_vigilada_check CHECK (((char_length(TRIM(BOTH FROM txt_fecha_vigilada)) >= 3) AND (char_length(TRIM(BOTH FROM txt_fecha_vigilada)) <= 160))),
    CONSTRAINT tab_modulo_alerta_txt_icono_check CHECK (((txt_icono)::text ~ '^fa-[a-z0-9-]{2,36}$'::text)),
    CONSTRAINT tab_modulo_alerta_txt_mensaje_defecto_check CHECK (((char_length(TRIM(BOTH FROM txt_mensaje_defecto)) >= 10) AND (char_length(TRIM(BOTH FROM txt_mensaje_defecto)) <= 300))),
    CONSTRAINT tab_modulo_alerta_val_dias_max_check CHECK (((val_dias_max >= (1)::numeric) AND (val_dias_max <= (90)::numeric)))
);

-- Notificaciones: eventos que se pueden activar o apagar (GH_CONTRATO_VENCE, etc.)
CREATE TABLE IF NOT EXISTS tab_evento_notificacion
(
    cod_evento                VARCHAR(30)             NOT NULL,
    cod_modulo                VARCHAR(20),
    nom_evento                VARCHAR(100)            NOT NULL,
    txt_destinatario          VARCHAR(120)            NOT NULL,
    ind_activo                BOOLEAN                 NOT NULL DEFAULT true,
    num_orden                 DECIMAL(2,0)            NOT NULL DEFAULT 99,
    id_usuario_registro       VARCHAR,
    fec_registro              TIMESTAMPTZ             NOT NULL DEFAULT now(),
    ind_borrado               BOOLEAN                 NOT NULL DEFAULT false,
    txt_modulo_erp            VARCHAR(60),
    CONSTRAINT tab_evento_notificacion_pkey PRIMARY KEY (cod_evento),
    CONSTRAINT tab_evento_notificacion_cod_modulo_fkey FOREIGN KEY (cod_modulo) REFERENCES tab_modulo_alerta(cod_modulo),
    CONSTRAINT tab_evento_notificacion_id_usuario_registro_fkey FOREIGN KEY (id_usuario_registro) REFERENCES tab_usuarios(id_usuario),
    CONSTRAINT ck_evento_modulo CHECK (((cod_modulo IS NOT NULL) OR (char_length(TRIM(BOTH FROM COALESCE(txt_modulo_erp, ''::character varying))) >= 3))),
    CONSTRAINT tab_evento_notificacion_cod_evento_check CHECK (((cod_evento)::text ~ '^[A-Z_]{3,30}$'::text)),
    CONSTRAINT tab_evento_notificacion_nom_evento_check CHECK (((char_length(TRIM(BOTH FROM nom_evento)) >= 5) AND (char_length(TRIM(BOTH FROM nom_evento)) <= 100))),
    CONSTRAINT tab_evento_notificacion_txt_destinatario_check CHECK (((char_length(TRIM(BOTH FROM txt_destinatario)) >= 3) AND (char_length(TRIM(BOTH FROM txt_destinatario)) <= 120)))
);

-- Notificaciones: niveles del semáforo de avisos (umbral en días, color)
CREATE TABLE IF NOT EXISTS tab_param_aviso
(
    val_nivel                 VARCHAR(8)              NOT NULL,
    nom_nivel                 VARCHAR(40)             NOT NULL,
    txt_color                 VARCHAR(7)              NOT NULL,
    val_segundos              DECIMAL(3,0)            NOT NULL,
    val_dias_umbral           DECIMAL(2,0),
    num_orden                 DECIMAL(1,0)            NOT NULL,
    id_usuario_registro       VARCHAR,
    fec_registro              TIMESTAMPTZ             NOT NULL DEFAULT now(),
    CONSTRAINT tab_param_aviso_pkey PRIMARY KEY (val_nivel),
    CONSTRAINT tab_param_aviso_id_usuario_registro_fkey FOREIGN KEY (id_usuario_registro) REFERENCES tab_usuarios(id_usuario),
    CONSTRAINT ck_param_aviso_nivel CHECK (((val_nivel)::text = ANY (ARRAY[('VERDE'::character varying)::text, ('AMARILLO'::character varying)::text, ('ROJO'::character varying)::text, ('AZUL'::character varying)::text]))),
    CONSTRAINT tab_param_aviso_nom_nivel_check CHECK (((char_length(TRIM(BOTH FROM nom_nivel)) >= 3) AND (char_length(TRIM(BOTH FROM nom_nivel)) <= 40))),
    CONSTRAINT tab_param_aviso_txt_color_check CHECK (((txt_color)::text ~ '^#[0-9A-Fa-f]{6}$'::text)),
    CONSTRAINT tab_param_aviso_val_dias_umbral_check CHECK (((val_dias_umbral >= (0)::numeric) AND (val_dias_umbral <= (30)::numeric))),
    CONSTRAINT tab_param_aviso_val_segundos_check CHECK (((val_segundos >= (0)::numeric) AND (val_segundos <= (120)::numeric)))
);

-- tab_notificaciones: columnas del motor de alertas/avisos (semáforo, aplazar, descartar, grupo).
ALTER TABLE tab_notificaciones ADD COLUMN IF NOT EXISTS val_nivel VARCHAR(8) NOT NULL DEFAULT 'VERDE';
ALTER TABLE tab_notificaciones ADD COLUMN IF NOT EXISTS cod_origen VARCHAR(40);
ALTER TABLE tab_notificaciones ADD COLUMN IF NOT EXISTS id_registro VARCHAR(40);
ALTER TABLE tab_notificaciones ADD COLUMN IF NOT EXISTS fec_limite_aplazar DATE;
ALTER TABLE tab_notificaciones ADD COLUMN IF NOT EXISTS fec_aplazada_hasta TIMESTAMPTZ;
ALTER TABLE tab_notificaciones ADD COLUMN IF NOT EXISTS ind_descartada BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE tab_notificaciones ADD COLUMN IF NOT EXISTS fec_aviso_mostrado TIMESTAMPTZ;
ALTER TABLE tab_notificaciones ADD COLUMN IF NOT EXISTS txt_grupo VARCHAR(120);
ALTER TABLE tab_notificaciones ADD COLUMN IF NOT EXISTS val_clase VARCHAR(8) NOT NULL DEFAULT 'PROCESO';
ALTER TABLE tab_notificaciones ADD COLUMN IF NOT EXISTS id_envio DECIMAL(10,0);
ALTER TABLE tab_notificaciones ADD COLUMN IF NOT EXISTS id_notificacion_padre DECIMAL(8,0);
ALTER TABLE tab_notificaciones ADD CONSTRAINT fk_notificacion_padre FOREIGN KEY (id_notificacion_padre) REFERENCES tab_notificaciones(id_notificacion);
ALTER TABLE tab_notificaciones ADD CONSTRAINT ck_notificacion_clase CHECK (((val_clase)::text = ANY (ARRAY[('ALERTA'::character varying)::text, ('PROCESO'::character varying)::text, ('MENSAJE'::character varying)::text])));
ALTER TABLE tab_notificaciones ADD CONSTRAINT ck_notificacion_nivel CHECK (((val_nivel)::text = ANY (ARRAY[('VERDE'::character varying)::text, ('AMARILLO'::character varying)::text, ('ROJO'::character varying)::text, ('AZUL'::character varying)::text])));
CREATE INDEX IF NOT EXISTS idx_notif_bandeja ON tab_notificaciones (id_usuario_destino, fec_creacion DESC) WHERE (ind_borrado = false);
CREATE INDEX IF NOT EXISTS idx_notif_envio ON tab_notificaciones (id_usuario_origen, id_envio) WHERE ((val_clase)::text = 'MENSAJE'::text);
CREATE INDEX IF NOT EXISTS idx_notif_origen_registro ON tab_notificaciones (cod_origen, id_registro, id_usuario_destino) WHERE (cod_origen IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_notif_pendientes ON tab_notificaciones (id_usuario_destino) WHERE ((ind_leido = false) AND (ind_borrado = false));
CREATE INDEX IF NOT EXISTS idx_notificaciones_fec_creacion ON tab_notificaciones (fec_creacion);
CREATE INDEX IF NOT EXISTS idx_notificaciones_leido ON tab_notificaciones (ind_leido);
CREATE INDEX IF NOT EXISTS idx_notificaciones_origen ON tab_notificaciones (id_usuario_origen);
CREATE INDEX IF NOT EXISTS idx_notificaciones_usuario ON tab_notificaciones (id_usuario_destino);



----------------------------------------------------------------
-- 10.1 CREACION DE TRIGGERS PARA AUDITORIAS TABLAS GENERALES --
---------------------------------------------------------------- 

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_dptos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_ciudades
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_cat_terceros
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_restricciones
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_terceros
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_areas
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_area_modulo
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_menus
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_usuarios
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_bancos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_festivos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
-------------------------------------------------------------------
-- 10.3 CREACION DE TRIGGERS PARA AUDITORIAS TABLAS CONTABILIDAD --
-------------------------------------------------------------------

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_enc_presupuesto
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_det_presupuesto
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_ejecucion_presupuesto
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_planeacion_presupuesto
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_tipo_presupuesto
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_period_presupuesto
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_tip_comprobantes
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_enc_comprobantes
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_det_comprobantes
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_act_fijos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_depreciacion
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_cat_activos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_parametros_contab
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_puc
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();


-- ----------------------------------------------------------------------
-- (compras 14-nov) Auditoría de las tablas de Compras
-- Traído del script ejecutable de Compras (reemplaza la versión vieja de este archivo).
-- ----------------------------------------------------------------------
--------------------------------------------------------------
-- 10.3 CREACION DE TRIGGERS PARA AUDITORIAS TABLAS COMPRAS --
--------------------------------------------------------------
CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_pmtros_compras
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_naturaleza_tributaria
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_proveedores
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_eval_prov
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_productos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_prodxprov
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_prodxarea
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_enc_solcomp
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_det_solcomp
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_enc_ordcomp
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_det_ordcomp
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_seg_ordcomp
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_det_seg_ordcomp
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_asig_prov_solcomp
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_consol_solcomp
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_det_ordcomp_solcomp
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_transportadoras
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_motivos_novedad
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_medios_envio
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_medios_reembolso
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_conf_solcomp
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_enc_devprov
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_det_devprov
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

------------------------------------------------------------------------------
-- 10.4 CREACION DE TRIGGERS PARA AUDITORIAS TABLAS GESTIÓN HUMANA Y NÓMINA -- (gehnom 14-nov) completo
------------------------------------------------------------------------------

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_pmtros_legales
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_escolaridad
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_profesiones
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_cargos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_entidades
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_tipos_contrato
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_req_personal
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_candidatos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_empleados
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_req_contratados
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_prestamos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_prestamos_pagos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_conceptos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_novedades
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_procesos_disciplinarios
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_nomina
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_nomina_detalle
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_nomina_avisos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_nomina_empleador
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_nomina_electronica
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_prestaciones
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_vacaciones
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_modulo_alerta
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_evento_notificacion
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR DELETE OR UPDATE ON tab_param_aviso
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

----------------------------------------------------------
-- 10.5 CREACION DE TRIGGERS PARA AUDITORIAS TABLAS SST --
----------------------------------------------------------
CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_accidentes
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_asis_cap
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_asist_copasst
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_auditorias_sst
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_brigada
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_brigadistas
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_capacitaciones
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_copasst
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_det_ex_ingreso
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_docentes
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_emergencia
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_enc_ex_ingreso
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_epp
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_epp_asignacion
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_epp_inspeccion
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_examenes
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_incapacidades
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_miem_copasst
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_reu_copasst
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_riesgos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_temas_cap
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_tipo_acc
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_tipo_incapacidad
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-----------------------------------------------------------------------------
-- 10.6 CREACION DE TRIGGERS PARA AUDITORIAS TABLAS MARKETING Y COMERICIAL -- 
-----------------------------------------------------------------------------
-- 01. tab_genero
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_genero
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 02. tab_vendedores_activos
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_vendedores_activos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 03. tab_pmtros_marcom
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_pmtros_marcom
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 04. tab_etapas_funnel
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_etapas_funnel
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 05. tab_canales
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_canales
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 06. tab_criterios_segmentacion
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_criterios_segmentacion
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 07. tab_valores_segmentacion
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_valores_segmentacion
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 08. tab_motivos_perdida
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_motivos_perdida
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 09. tab_tipo_campana
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_tipo_campana
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 10. tab_campanas
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_campanas
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 11. tab_campana_canal
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_campana_canal
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 12. tab_leads
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_leads
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 13. tab_segmentacion_lead
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_segmentacion_lead
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 14. tab_segmentacion_cliente
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_segmentacion_cliente
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 15. tab_lead_camp
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_lead_camp
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 16. tab_cliente_camp
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_cliente_camp
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 17. tab_tipos_interaccion_marcom
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_tipos_interaccion_marcom
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 18. tab_interacciones
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_interacciones
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 19. tab_proximas_acciones
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_proximas_acciones
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 20. tab_evento
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_evento
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 21. tab_even_lead
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_even_lead
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 22. tab_prod_camp
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_prod_camp
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 23. tab_presupuesto_campana
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_presupuesto_campana
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 24. tab_presupuesto_evento
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_presupuesto_evento
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 25. tab_kpis_marcom
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_kpis_marcom
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 26. tab_medicion_kpi
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_medicion_kpi
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 27. tab_evento_correo
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_evento_correo
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 28. tab_plantillas_correo
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_plantillas_correo
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 29. tab_contactos_adicionales
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_contactos_adicionales
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 30. tab_envios
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_envios
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 31. tab_canal_tipo_interaccion
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_canal_tipo_interaccion
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 32. tab_historial_asignacion_lead
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_historial_asignacion_lead
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 33. tab_tracker_campana_canal
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_tracker_campana_canal
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 34. tab_rate_limit_promo
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_rate_limit_promo
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 35. tab_lead_camp_tracker
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_lead_camp_tracker
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 36. tab_enc_pedidos
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_enc_pedidos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 37. tab_det_pedidos
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_det_pedidos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 38. tab_pedido_factura
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_pedido_factura
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 39. tab_camp_prod
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_camp_prod
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 40. tab_cola_correos
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_cola_correos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 41. tab_baja_correo
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_baja_correo
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 42. tab_remitente_correo
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_remitente_correo
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-- 43. tab_pmtros_correo
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_pmtros_correo
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

----------------------------------------------------------------------------
-- 10.7 CREACION DE TRIGGERS PARA AUDITORIAS TABLAS FACTURACIÓN Y CARTERA --
----------------------------------------------------------------------------

CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_pmtros_facturacion
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_motivo_nota
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_enc_notas
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_det_notas
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail  AFTER INSERT OR UPDATE OR DELETE  ON tab_nota_elect
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_aplicacion_nota_factura
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_aplicacion_nota_cartera
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_pagos_cartera
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_gestiones_cobro
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_promesas_pago
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_solicitudes_castigo
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_det_solicitud_castigo
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_respuestas_castigo
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_edades_cartera
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_recuperaciones_cartera
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_acuerdos_pago
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_acuerdos_recuperaciones
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_autorizaciones_credito
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_pagos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_carteras
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_fac_electronicas
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_det_facturas
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_enc_facturas
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_det_cotizaciones
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_enc_cotizaciones
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_vendedores
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_clientes
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_forma_pagos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_resoluciones_dian
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE  ON tab_factus_mapeo
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

--------------------------------------------------------------------
-- 10.8 CREACIÓN DE TRIGGERS PARA AUDITORIAS TABLAS TESORERÍA Y CXP --
--------------------------------------------------------------------
CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_pagos_inversion
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_pagos_nomina
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_pagos_cxp
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_codigos_respuesta_banco
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_det_archivo_inversion
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_det_archivo_nomina
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_det_archivo_plano
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_enc_archivo_plano
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_det_cronopagos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_enc_cronopagos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_cuotasxfactura
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_cuentasxpagar
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_bancoxprov
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_ctas_empresa
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_det_caja_menor
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_enc_caja_menor
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_pmtros_tescxp
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

-----------------------------------------------------------------------------------
-- 10.9 CREACION DE TRIGGERS PARA AUDITORIAS TABLAS GESTIÓN DOCUMENTAL Y CALIDAD --
-----------------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_tipo_documento
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_tabla_retencion
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_estado_correspondencia
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_accion_workflow
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_correspondencia
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_indexacion
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_expediente
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_doc_expediente
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_anexo_correspondencia
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_notificaciones
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_modulo_alerta
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_evento_notificacion
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_param_aviso
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_tipo_pqrs
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_param_venc_pqrs
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_estado_pqrs
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_motivo_pqrs
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_enc_pqrs
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_det_pqrs
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_seg_pqrs
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_respuesta_pqrs
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_anexo_pqrs
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_param_alerta_pqrs
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_normas
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_estado_documento
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_enc_documento
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_det_documento
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_doc_norma
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_doc_archivo
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_procesos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_tipo_dato_entrada
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_entrada_proceso
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_certificacion
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_auditorias
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_hallazgo
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_accion_correctiva
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_doc_anexo
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_workflow
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_parametro_calidad
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_prompt_ia
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_evaluacion_calidad_ia
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_solicitud_certificacion
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_param_alerta
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_fuente_alerta
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

CREATE OR REPLACE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_fuente_columna
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

------------------------------------------------------------------
-- 10.10 CREACION DE TRIGGERS PARA AUDITORIAS TABLAS FINANCIERA --
------------------------------------------------------------------
DROP TRIGGER IF EXISTS tri_audit_trail ON tab_pmtros_financieros;
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_pmtros_financieros
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

DROP TRIGGER IF EXISTS tri_audit_trail ON tab_inversores;
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_inversores
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

DROP TRIGGER IF EXISTS tri_audit_trail ON tab_proyectos;
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_proyectos
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

DROP TRIGGER IF EXISTS tri_audit_trail ON tab_indicadores;
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_indicadores
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

DROP TRIGGER IF EXISTS tri_audit_trail ON tab_val_ind;
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_val_ind
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

DROP TRIGGER IF EXISTS tri_audit_trail ON tab_inversiones;
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_inversiones
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

DROP TRIGGER IF EXISTS tri_audit_trail ON tab_cuotas_inversion;
CREATE TRIGGER tri_audit_trail AFTER INSERT OR UPDATE OR DELETE ON tab_cuotas_inversion
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();




INSERT INTO tab_menu_palettes (
    id_palette, 
    nom_palette, 
    des_palette, 
    val_primary_color, 
    val_secondary_color, 
    val_accent_color, 
    val_text_color, 
    val_hover_color, 
    val_sidebar_bg, 
    val_sidebar_text, 
    val_sidebar_hover, 
    val_active_bg, 
    num_orden, 
    ind_active, 
    ind_borrado
) VALUES
('corp_navy', 'Corporate Navy', 'Paleta corporativa tradicional para empresas', '#1B2A4A', '#2C3E6B', '#4A6FA5', '#FFFFFF', '#4A6FA5', '#FFFFFF', '#1B2A4A', '#E8EDF2', '#2C3E6B', 1, FALSE, FALSE),
('modern_exec', 'Modern Executive', 'Paleta ejecutiva moderna y sobria', '#0F172A', '#1E293B', '#334155', '#FFFFFF', '#64748B', '#FFFFFF', '#0F172A', '#F1F5F9', '#1E293B', 2, FALSE, FALSE),
('tech_startup', 'Tech Startup', 'Paleta tecnológica para startups innovadoras', '#0A0A0A', '#1A1A2E', '#16213E', '#FFFFFF', '#E94560', '#FFFFFF', '#0A0A0A', '#1A1A2E', '#0F3460', 3, FALSE, FALSE),
('financial_trust', 'Financial Trust', 'Paleta para sector financiero y bancario', '#003D5C', '#006A8E', '#0091AD', '#FFFFFF', '#00B4D8', '#FFFFFF', '#003D5C', '#F0F4F8', '#006A8E', 4, FALSE, FALSE),
('healthcare_clean', 'Healthcare Clean', 'Paleta para sector salud y hospitales', '#1A535C', '#4ECDC4', '#F7FFF7', '#1A535C', '#FFE66D', '#FFFFFF', '#1A535C', '#F0F8F0', '#4ECDC4', 5, FALSE, FALSE),
('luxury_gold', 'Luxury Gold', 'Paleta de lujo para alta gama', '#1A1A1A', '#2D2D2D', '#C5A572', '#FFFFFF', '#D4AF37', '#FFFFFF', '#1A1A1A', '#F5F0EB', '#C5A572', 6, FALSE, FALSE),
('minimalist_gray', 'Minimalist Gray', 'Paleta minimalista y elegante', '#1F2937', '#374151', '#6B7280', '#FFFFFF', '#9CA3AF', '#FFFFFF', '#1F2937', '#F3F4F6', '#374151', 7, FALSE, FALSE),
('nature_green', 'Nature Green', 'Paleta basada en naturaleza y sostenibilidad', '#0D3B2E', '#1B5E3C', '#2E7D32', '#FFFFFF', '#4CAF50', '#FFFFFF', '#0D3B2E', '#E8F5E9', '#1B5E3C', 8, FALSE, FALSE),
('sunset_warm', 'Sunset Warm', 'Paleta cálida de atardecer', '#4A1A2A', '#7A2A3A', '#C45A3A', '#FFFFFF', '#E88A5A', '#FFFFFF', '#4A1A2A', '#FFD5AA', '#7A2A3A', 9, FALSE, FALSE),
('ocean_deep', 'Ocean Deep', 'Paleta de océano profundo', '#0A1628', '#0D2847', '#1A4A7A', '#FFFFFF', '#2A7AAA', '#FFFFFF', '#0A1628', '#D4E8F5', '#0D2847', 10, FALSE, FALSE),
('elegant_rose', 'Elegant Rose', 'Paleta elegante con rosas', '#2A1A2A', '#4A2A3A', '#7A4A5A', '#FFFFFF', '#C49AA0', '#FFFFFF', '#2A1A2A', '#F5E8EA', '#4A2A3A', 11, FALSE, FALSE),
('urban_concrete', 'Urban Concrete', 'Paleta urbana de concreto', '#2C2C2C', '#4A4A4A', '#6A6A6A', '#FFFFFF', '#9A9A9A', '#FFFFFF', '#2C2C2C', '#EAEAEA', '#4A4A4A', 12, FALSE, FALSE),
('forest_dark', 'Forest Dark', 'Paleta de bosque oscuro', '#0A1A0A', '#1A2A1A', '#2A4A2A', '#FFFFFF', '#3A6A3A', '#FFFFFF', '#0A1A0A', '#E8F0E8', '#1A2A1A', 13, FALSE, FALSE),
('royal_purple', 'Royal Purple', 'Paleta púrpura real', '#1A0A2A', '#2A1A4A', '#4A2A7A', '#FFFFFF', '#7A4AAA', '#FFFFFF', '#1A0A2A', '#E8D4F5', '#2A1A4A', 14, FALSE, FALSE),
('warm_earth', 'Warm Earth', 'Paleta tierra cálida', '#3A2A1A', '#5A3A2A', '#8A5A3A', '#FFFFFF', '#BA8A5A', '#FFFFFF', '#3A2A1A', '#F0E0D0', '#5A3A2A', 15, FALSE, FALSE),
('cool_blue', 'Cool Blue', 'Paleta azul frío', '#0A1A2A', '#1A3A5A', '#2A5A8A', '#FFFFFF', '#4A8ABA', '#FFFFFF', '#0A1A2A', '#D4E8F5', '#1A3A5A', 16, FALSE, FALSE),
('coral_reef', 'Coral Reef', 'Paleta de arrecife coral', '#1A2A3A', '#3A5A6A', '#6A8A9A', '#FFFFFF', '#C46A5A', '#FFFFFF', '#1A2A3A', '#F5D4C4', '#3A5A6A', 17, FALSE, FALSE),
('graphite_dark', 'Graphite Dark', 'Paleta grafito oscuro', '#0A0A0A', '#1A1A1A', '#2A2A2A', '#FFFFFF', '#4A4A4A', '#FFFFFF', '#0A0A0A', '#F0F0F0', '#1A1A1A', 18, FALSE, FALSE),
('mint_fresh', 'Mint Fresh', 'Paleta menta fresca', '#0A2A1A', '#1A4A2A', '#2A7A4A', '#FFFFFF', '#5ABA8A', '#FFFFFF', '#0A2A1A', '#E8F5F0', '#1A4A2A', 19, FALSE, FALSE),
('classic_red', 'Classic Red', 'Paleta rojo clásico', '#2A0A0A', '#4A1A1A', '#7A2A2A', '#FFFFFF', '#BA4A3A', '#FFFFFF', '#2A0A0A', '#F5E0E0', '#4A1A1A', 20, FALSE, FALSE);

-- (temporadas 18-nov) Navidad, automática del 1-dic al 7-ene
-- ---------------------------------------------------------------------------
-- DATO INICIAL: Navidad, automática del 1-dic al 7-ene (no duplica)
-- ---------------------------------------------------------------------------
INSERT INTO tab_temporadas (id_temporada, nom_temporada, ind_modo,
                            val_mes_inicio, val_dia_inicio, val_mes_fin, val_dia_fin,
                            des_saludo, des_horario, ind_borrado)
VALUES ('navidad', 'Navidad', 'A', 12, 1, 1, 7,
        '¡Felices fiestas! Gracias por este año juntos',
        'ND', FALSE)
ON CONFLICT (id_temporada) DO NOTHING;

-- ================================================================
-- TRIGGER DE AUDITORÍA PARA tab_pmtros_grales
-- ================================================================
CREATE OR REPLACE TRIGGER tri_audit_trail
AFTER INSERT OR UPDATE OR DELETE ON tab_pmtros_grales
FOR EACH ROW EXECUTE FUNCTION fun_audit_trail();

INSERT INTO tab_cat_errores (cod_sqlstate, mensaje) VALUES

-- ✅ Éxito / advertencias
('00000', 'Operación realizada correctamente'),
('01000', 'Advertencia general'),
('02000', 'No se encontraron datos'),

-- 🔐 Integridad (LOS MÁS IMPORTANTES)
('23505', 'El registro ya existe (duplicado)'),
('23503', 'El valor no existe o está relacionado con otros datos'),
('23502', 'Un campo obligatorio está vacío'),
('23514', 'El valor no cumple las reglas permitidas'),

-- 📊 Datos inválidos
('22001', 'El texto es demasiado largo'),
('22003', 'El número está fuera de rango'),
('22004', 'No se permite valor nulo'),
('22007', 'Formato de fecha incorrecto'),
('22012', 'No se puede dividir entre cero'),
('22P02', 'Formato de dato inválido'),

-- 🧠 Lógica / consultas
('42P01', 'La tabla no existe'),
('42703', 'La columna no existe'),
('42601', 'Error de sintaxis en la consulta'),
('42804', 'Tipo de dato incorrecto'),
('42883', 'La función no existe'),

-- 🔁 Transacciones
('40001', 'Conflicto de transacción, intente nuevamente'),
('40P01', 'Se detectó un bloqueo entre procesos'),

-- 🔒 Permisos
('42501', 'No tiene permisos para realizar esta acción'),

-- 🌐 Conexión
('08003', 'La conexión no está activa'),
('08006', 'Error en la conexión a la base de datos'),

-- ⚙️ Sistema / recursos
('53000', 'Recursos insuficientes'),
('53100', 'No hay espacio en disco'),
('53200', 'Memoria insuficiente'),

-- ⚠️ Estado / ejecución
('25000', 'Estado de transacción inválido'),
('25P02', 'La transacción falló previamente'),

-- 🧩 PL/pgSQL
('P0001', 'Error generado manualmente'),
('P0002', 'No se encontraron resultados'),
('P0003', 'Se encontraron demasiados resultados'),

-- 🧨 Otros útiles
('21000', 'Error: se esperaban menos resultados'),
('2200F', 'Texto vacío no permitido'),
('2200L', 'Documento XML inválido'),
('22032', 'JSON inválido');

-- ----------------------------------------------------------------------
-- Prefijos telefónicos (Parámetros Generales → celular de la empresa)
-- Origen: scripts/tab_tel_prefijo_datos.sql
-- ----------------------------------------------------------------------
-- =====================================================================
-- DATOS: tab_tel_prefijo (prefijos telefónicos internacionales)
-- Lo usa Parámetros Generales (celular de la empresa) y puede usarlo
-- cualquier módulo que pida un teléfono móvil.
-- id_prefijo es la llave: un registro por prefijo (+1 = EE. UU. y Canadá).
-- Se puede ejecutar varias veces: ON CONFLICT no duplica.
-- =====================================================================
INSERT INTO tab_tel_prefijo (id_prefijo, nom_pais) VALUES
    (57,  'Colombia'),
    (1,   'Estados Unidos / Canadá'),
    (52,  'México'),
    (502, 'Guatemala'),
    (503, 'El Salvador'),
    (504, 'Honduras'),
    (505, 'Nicaragua'),
    (506, 'Costa Rica'),
    (507, 'Panamá'),
    (509, 'Haití'),
    (53,  'Cuba'),
    (1809,'República Dominicana'),
    (1787,'Puerto Rico'),
    (58,  'Venezuela'),
    (593, 'Ecuador'),
    (51,  'Perú'),
    (591, 'Bolivia'),
    (55,  'Brasil'),
    (56,  'Chile'),
    (54,  'Argentina'),
    (595, 'Paraguay'),
    (598, 'Uruguay'),
    (34,  'España'),
    (351, 'Portugal'),
    (33,  'Francia'),
    (39,  'Italia'),
    (49,  'Alemania'),
    (44,  'Reino Unido'),
    (31,  'Países Bajos'),
    (41,  'Suiza'),
    (86,  'China'),
    (81,  'Japón'),
    (82,  'Corea del Sur'),
    (91,  'India'),
    (61,  'Australia'),
    (972, 'Israel'),
    (971, 'Emiratos Árabes Unidos')
ON CONFLICT (id_prefijo) DO NOTHING;


-- ======================================================================
-- CAMBIOS 1.3 (14-nov-2026)
-- Contabilidad (Parámetros contables y PUC) y Parámetros generales
-- (terceros, tipos de documento, categoría de errores).
-- Cada bloque copia su archivo de origen; todos se pueden ejecutar
-- varias veces.
-- ======================================================================


-- ----------------------------------------------------------------------
-- Categoría de errores (mensajes nuevos)
-- (1.3) Origen: scripts/functions/fun_mensaje_errores.sql
-- ----------------------------------------------------------------------
-- =====================================================================
-- CATEGORÍA DE ERRORES: tab_cat_errores + fun_mensaje_error
-- Todas las funciones terminan con:
--     EXCEPTION WHEN OTHERS THEN
--         RAISE EXCEPTION '%', fun_mensaje_error(SQLSTATE, SQLERRM);
-- Así el usuario nunca ve un SQLSTATE: recibe el texto de la validación
-- (P0001) o el mensaje catalogado para ese código.
-- =====================================================================

CREATE TABLE IF NOT EXISTS tab_cat_errores
(
    cod_sqlstate  VARCHAR NOT NULL CHECK (LENGTH(cod_sqlstate) = 5),
    mensaje       VARCHAR NOT NULL CHECK (LENGTH(mensaje) BETWEEN 4 AND 255),
    PRIMARY KEY (cod_sqlstate)
);

INSERT INTO tab_cat_errores (cod_sqlstate, mensaje) VALUES
    -- Éxito y advertencias
    ('00000', 'Operación realizada correctamente'),
    ('01000', 'Advertencia general'),
    ('02000', 'No se encontraron datos'),
    -- Integridad
    ('23505', 'El registro ya existe'),
    ('23503', 'El valor no existe o está relacionado con otros datos'),
    ('23502', 'Un campo obligatorio está vacío'),
    ('23514', 'Un valor no cumple las reglas permitidas'),
    -- Datos inválidos
    ('22001', 'El texto es demasiado largo'),
    ('22003', 'El número está fuera de rango'),
    ('22004', 'No se permite valor nulo'),
    ('22007', 'Formato de fecha incorrecto'),
    ('22008', 'La fecha está fuera del rango permitido'),
    ('22012', 'No se puede dividir entre cero'),
    ('22P02', 'Formato de dato inválido'),
    ('2200F', 'Texto vacío no permitido'),
    ('2200L', 'Documento XML inválido'),
    ('22032', 'JSON inválido'),
    -- Objetos y consultas
    ('42P01', 'La información solicitada no está disponible'),
    ('42703', 'La información solicitada no está disponible'),
    ('42601', 'La consulta no se pudo procesar'),
    ('42804', 'Tipo de dato incorrecto'),
    ('42883', 'La operación solicitada no está disponible'),
    ('21000', 'Se esperaba un solo resultado'),
    -- Transacciones
    ('40001', 'Conflicto de transacción, intente nuevamente'),
    ('40P01', 'Se detectó un bloqueo entre procesos, intente nuevamente'),
    ('25000', 'Estado de transacción inválido'),
    ('25P02', 'La transacción falló previamente'),
    -- Permisos
    ('42501', 'No tiene permisos para realizar esta acción'),
    -- Conexión
    ('08003', 'La conexión no está activa'),
    ('08006', 'Error en la conexión a la base de datos'),
    -- Recursos
    ('53000', 'Recursos insuficientes'),
    ('53100', 'No hay espacio en disco'),
    ('53200', 'Memoria insuficiente'),
    -- PL/pgSQL
    ('P0001', 'Error de validación'),
    ('P0002', 'No se encontraron resultados'),
    ('P0003', 'Se encontraron demasiados resultados')
ON CONFLICT (cod_sqlstate) DO UPDATE SET mensaje = EXCLUDED.mensaje;

-- ----------------------------------------------------------------------
-- Tipos de documento (Terceros y PUC)
-- (1.3) Origen: scripts/tab_tipo_identidad_datos.sql
-- ----------------------------------------------------------------------
-- =====================================================================
-- DATOS: tab_tipo_identidad (tipos de documento, códigos usados por la DIAN)
-- Los usan Terceros y el PUC (crear tercero desde la cuenta).
-- Se puede ejecutar varias veces: ON CONFLICT no duplica.
-- =====================================================================
INSERT INTO tab_tipo_identidad (id_tipo, nom_tipo) VALUES
    ('CC',   'Cédula de ciudadanía'),
    ('NIT',  'Número de identificación tributaria'),
    ('CE',   'Cédula de extranjería'),
    ('TI',   'Tarjeta de identidad'),
    ('RC',   'Registro civil'),
    ('PA',   'Pasaporte'),
    ('PEP',  'Permiso especial de permanencia'),
    ('PPT',  'Permiso por protección temporal'),
    ('NUIP', 'Número único de identificación personal'),
    ('DIE',  'Documento de identificación extranjero')
ON CONFLICT (id_tipo) DO NOTHING;

-- ----------------------------------------------------------------------
-- Parámetros contables: estructura y limpieza
-- (1.3) Origen: src/modules/contab/script/tab_parametros_contab.sql
-- ----------------------------------------------------------------------
-- =====================================================================
-- PARÁMETROS CONTABLES (tab_parametros_contab)
-- Estructura que usa la vista parametros_contab.php.
-- Se puede ejecutar varias veces: solo agrega lo que falte.
-- =====================================================================

ALTER TABLE tab_parametros_contab
    ADD COLUMN IF NOT EXISTS fec_cierre_programado DATE,
    ADD COLUMN IF NOT EXISTS motivo_cierre         VARCHAR(250),
    ADD COLUMN IF NOT EXISTS observaciones         VARCHAR(500),
    ADD COLUMN IF NOT EXISTS val_ipc               NUMERIC(6,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS pct_alerta_presup     NUMERIC(5,2) NOT NULL DEFAULT 80,
    ADD COLUMN IF NOT EXISTS ind_bloqueo_presup    BOOLEAN      NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS usuario_cierre        VARCHAR,
    ADD COLUMN IF NOT EXISTS fec_cierre            TIMESTAMP,
    ADD COLUMN IF NOT EXISTS usuario_modif         VARCHAR,
    ADD COLUMN IF NOT EXISTS fec_ultima_modif      TIMESTAMP;

COMMENT ON COLUMN tab_parametros_contab.val_ipc            IS 'IPC anual (%) con el que se indexa el presupuesto';
COMMENT ON COLUMN tab_parametros_contab.pct_alerta_presup  IS 'Porcentaje de ejecución presupuestal que dispara la alerta';
COMMENT ON COLUMN tab_parametros_contab.ind_bloqueo_presup IS 'TRUE: no se permite ejecutar por encima de lo aprobado';

-- Restricciones (solo si no existen)
DO $BODY$
BEGIN
    IF NOT EXISTS (SELECT a.conname FROM pg_constraint AS a WHERE a.conname = 'chk_pc_val_ipc') THEN
        ALTER TABLE tab_parametros_contab
            ADD CONSTRAINT chk_pc_val_ipc CHECK (val_ipc BETWEEN -50 AND 100);
    END IF;
    IF NOT EXISTS (SELECT a.conname FROM pg_constraint AS a WHERE a.conname = 'chk_pc_pct_alerta') THEN
        ALTER TABLE tab_parametros_contab
            ADD CONSTRAINT chk_pc_pct_alerta CHECK (pct_alerta_presup BETWEEN 1 AND 100);
    END IF;
    IF NOT EXISTS (SELECT a.conname FROM pg_constraint AS a WHERE a.conname = 'chk_pc_anio_max') THEN
        ALTER TABLE tab_parametros_contab
            ADD CONSTRAINT chk_pc_anio_max CHECK (anio_contable <= 2100);
    END IF;
END;
$BODY$;

-- Columnas y tabla de la versión del 13/11/2026 que se descartaron
ALTER TABLE tab_parametros_contab
    DROP COLUMN IF EXISTS ind_grupo_niif,
    DROP COLUMN IF EXISTS cod_moneda,
    DROP COLUMN IF EXISTS niv_movimiento,
    DROP COLUMN IF EXISTS cta_utilidad,
    DROP COLUMN IF EXISTS cta_perdida,
    DROP COLUMN IF EXISTS cta_cierre;
DROP TABLE IF EXISTS tab_indicadores_econ;

-- ----------------------------------------------------------------------
-- PUC: saldo y tercero
-- (1.3) Origen: src/modules/contab/script/migracion_puc_saldo_tercero.sql
-- ----------------------------------------------------------------------
-- =====================================================================
-- MIGRACIÓN: tab_puc — saldo y tercero (2026-11-13)
--
-- val_saldo   Saldo de la cuenta según su naturaleza (débito: debe - haber;
--             crédito: haber - debe). Lo calcula el sistema con los
--             comprobantes APROBADOS de la cuenta y de todas sus subcuentas
--             (por eso una clase, grupo o cuenta suma a sus hijas).
--             Nadie lo escribe a mano: ver fun_recalcular_saldo_puc y los
--             triggers de tab_det_comprobantes / tab_enc_comprobantes.
-- id_tercero  Tercero asociado a la cuenta cuando ind_req_tercero = TRUE.
--
-- Regla contable: una cuenta con saldo distinto de cero no se puede
-- modificar ni eliminar (la hacen cumplir fun_update_puc / fun_delete_puc).
--
-- Se puede ejecutar varias veces.
-- Después ejecutar, en este orden:
--   script/functions/fun_recalcular_saldo_puc.sql
--   script/fun_inserts/fun_insert_puc.sql
--   script/fun_updates/fun_update_puc.sql
--   script/fun_deletes/fun_delete_puc.sql
-- =====================================================================

ALTER TABLE tab_puc ADD COLUMN IF NOT EXISTS val_saldo  NUMERIC(18,2) NOT NULL DEFAULT 0;
ALTER TABLE tab_puc ADD COLUMN IF NOT EXISTS id_tercero VARCHAR(10);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tab_puc_id_tercero_fkey') THEN
        ALTER TABLE tab_puc
            ADD CONSTRAINT tab_puc_id_tercero_fkey
            FOREIGN KEY (id_tercero) REFERENCES tab_terceros(id_tercero);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_puc_id_tercero ON tab_puc (id_tercero);

COMMENT ON COLUMN tab_puc.val_saldo  IS 'Saldo según la naturaleza. Calculado: comprobantes aprobados de la cuenta y sus subcuentas.';
COMMENT ON COLUMN tab_puc.id_tercero IS 'Tercero de la cuenta (obligatorio cuando ind_req_tercero = TRUE).';


-- ======================================================================
-- CAMBIOS 1.4 (14-nov-2026)
-- Funciones que el PHP llamaba y no existían, correcciones de funciones
-- que fallaban al ejecutarse, tablas/columnas/secuencias faltantes y la
-- carga del PUC. Cada bloque copia su archivo de origen (un archivo por
-- función). Todo el script se puede ejecutar varias veces.
-- ======================================================================


-- ======================================================================
-- 1.4-A  TABLAS, COLUMNAS Y SECUENCIAS FALTANTES
-- ======================================================================


-- ----------------------------------------------------------------------
-- Accesos rápidos del inicio (menu_principal.php)
-- (1.4) Origen: scripts/tablas/tab_accesos_usuario.sql
-- ----------------------------------------------------------------------
-- ================================================================
-- ACCESOS RÁPIDOS REALES (menu_principal.php → widget accesos_rapidos)
-- Registra cuántas veces abre cada usuario cada opción del menú.
-- El dashboard muestra las más usadas por el usuario.
-- Ejecutar una vez en cada base de datos (local y servidor).
-- ================================================================
CREATE TABLE IF NOT EXISTS tab_accesos_usuario
(
    id_usuario   VARCHAR        NOT NULL,
    id_menu      VARCHAR(255)   NOT NULL,                 -- opción final (la que tiene programa)
    val_path     VARCHAR(1000)  NOT NULL,                 -- ruta completa: '1-1.12-1.12.121'
    val_visitas  INTEGER        NOT NULL DEFAULT 1 CHECK (val_visitas > 0),
    fec_ultimo   TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_usuario, id_menu),
    FOREIGN KEY (id_usuario) REFERENCES tab_usuarios(id_usuario) ON DELETE CASCADE,
    FOREIGN KEY (id_menu)    REFERENCES tab_menus(id_menu)       ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_accesos_usuario_top
    ON tab_accesos_usuario (id_usuario, val_visitas DESC, fec_ultimo DESC);


-- ----------------------------------------------------------------------
-- Recuperar contraseña: tab_codigo_clave + funciones (auth/recuperar.php)
-- (1.4) Origen: auth/scripts/recuperar_clave.sql
-- ----------------------------------------------------------------------
-- =====================================================================
-- auth/scripts/recuperar_clave.sql
-- Recuperación de contraseña con código de 6 dígitos enviado al correo
-- del usuario (cuenta de SOPORTE). Mismo patrón que tab_codigo_pqrs (GEDCAL).
--
-- Se puede ejecutar varias veces: no lleva DROP de tablas.
--
-- Flujo:
--   1. PHP genera el código (random_int), calcula su huella HMAC-SHA256 con
--      'soporte.secreto' de /var/www/config/config_correo.php y llama a
--      fun_generar_codigo_clave. En la BD NUNCA se guarda el código.
--   2. Si el correo no sale, PHP llama a fun_anular_codigo_clave.
--   3. El usuario digita el código y la nueva contraseña: PHP calcula la
--      huella, el hash bcrypt de la clave y llama a fun_cambiar_clave_con_codigo,
--      que en UNA transacción valida el código, cambia la clave y cierra
--      todas las sesiones activas del usuario (fun_update_sesion).
--
-- Claves de advisory lock usadas (hashtextextended):
--   'codigo_clave:<id_usuario>'   (generar y cambiar, por usuario)
-- =====================================================================


-- =====================================================================
-- TABLA Y SECUENCIA
-- =====================================================================
CREATE SEQUENCE IF NOT EXISTS seq_codigo_clave;

CREATE TABLE IF NOT EXISTS tab_codigo_clave (
    id_codigo     NUMERIC(12,0)  NOT NULL DEFAULT nextval('seq_codigo_clave'),
    id_usuario    VARCHAR        NOT NULL,                        -- tab_usuarios.id_usuario
    txt_hash      VARCHAR(64)    NOT NULL,                        -- HMAC-SHA256 (hex) de usuario|código
    txt_ip        VARCHAR(45)    NOT NULL DEFAULT 'SIN_IP',       -- IPv4/IPv6 de quien pidió el código
    fec_creacion  TIMESTAMPTZ    NOT NULL DEFAULT now(),
    fec_vence     TIMESTAMPTZ    NOT NULL,
    val_intentos  NUMERIC(1,0)   NOT NULL DEFAULT 0,              -- intentos fallidos (máx. 5)
    ind_usado     BOOLEAN        NOT NULL DEFAULT FALSE,          -- usado, reemplazado o agotado
    ind_borrado   BOOLEAN        NOT NULL DEFAULT FALSE,          -- anulado (el correo no salió)
    CONSTRAINT tab_codigo_clave_pkey               PRIMARY KEY (id_codigo),
    CONSTRAINT fk_codigo_clave_usuario             FOREIGN KEY (id_usuario) REFERENCES tab_usuarios (id_usuario),
    CONSTRAINT tab_codigo_clave_txt_hash_check     CHECK (txt_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT tab_codigo_clave_val_intentos_check CHECK (val_intentos BETWEEN 0 AND 5),
    CONSTRAINT chk_codigo_clave_vence              CHECK (fec_vence > fec_creacion)
);

ALTER SEQUENCE seq_codigo_clave OWNED BY tab_codigo_clave.id_codigo;

CREATE INDEX IF NOT EXISTS idx_codigo_clave_usuario ON tab_codigo_clave (id_usuario, fec_creacion);
CREATE INDEX IF NOT EXISTS idx_codigo_clave_ip      ON tab_codigo_clave (txt_ip, fec_creacion);

COMMENT ON TABLE tab_codigo_clave IS 'Códigos de un solo uso para recuperar la contraseña. Solo guarda la huella HMAC, nunca el código.';

-- (usuarios 14-nov) tab_intento_clave: bitácora de intentos de recuperar la clave (límite por usuario y por IP).
--   PISTA = se mostró la pista del correo; CORREO_MAL / CORREO_OK = el usuario digitó su correo.
--   Origen: auth/scripts/recuperar_clave.sql (sincronizado con db_adsoerp_old).
CREATE SEQUENCE IF NOT EXISTS seq_intento_clave;

CREATE TABLE IF NOT EXISTS tab_intento_clave (
    id_intento    NUMERIC(12,0)  NOT NULL DEFAULT nextval('seq_intento_clave'),
    id_usuario    VARCHAR(50)    NOT NULL,                        -- usuario digitado (puede no existir)
    txt_ip        VARCHAR(45)    NOT NULL DEFAULT 'SIN_IP',
    txt_tipo      VARCHAR(12)    NOT NULL,
    fec_creacion  TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT tab_intento_clave_pkey          PRIMARY KEY (id_intento),
    CONSTRAINT tab_intento_clave_txt_tipo_check CHECK (txt_tipo IN ('PISTA', 'CORREO_MAL', 'CORREO_OK'))
);

ALTER SEQUENCE seq_intento_clave OWNED BY tab_intento_clave.id_intento;

CREATE INDEX IF NOT EXISTS idx_intento_clave_usuario ON tab_intento_clave (id_usuario, txt_tipo, fec_creacion);
CREATE INDEX IF NOT EXISTS idx_intento_clave_ip      ON tab_intento_clave (txt_ip, txt_tipo, fec_creacion);


-- ----------------------------------------------------------------------
-- Depreciación: columna fecha_proceso
-- (1.4) Origen: src/modules/contab/script/migracion_depreciacion_fecha_proceso.sql
-- ----------------------------------------------------------------------
-- =====================================================================
-- MIGRACIÓN: tab_depreciacion.fecha_proceso
-- fun_count_depreciacion, fun_list_meses_depreciacion,
-- fun_list_movimientos_depreciacion y depreciacion.php leen la columna
-- fecha_proceso (cuándo se procesó el mes), pero tab_depreciacion no la
-- tenía en el script 1.3: la pantalla de Depreciación fallaba con
-- "no existe la columna d.fecha_proceso".
--
-- Se agrega con DEFAULT CURRENT_TIMESTAMP, así fun_procesar_depreciacion_mes
-- (que no la menciona en su INSERT) la llena sola. Idempotente.
-- =====================================================================

ALTER TABLE tab_depreciacion
    ADD COLUMN IF NOT EXISTS fecha_proceso TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP;

COMMENT ON COLUMN tab_depreciacion.fecha_proceso IS 'Fecha y hora en que se procesó la depreciación del mes';


-- ----------------------------------------------------------------------
-- Plantillas de presupuesto: secuencias
-- (1.4) Origen: src/modules/contab/script/seq_plantilla_presupuesto.sql
-- ----------------------------------------------------------------------
-- =====================================================================
-- SECUENCIAS: seq_plantilla_presupuesto / seq_det_plantilla_presupuesto
-- Consecutivos de tab_plantilla_presupuesto y tab_det_plantilla_presupuesto.
-- fun_insert_plantilla_presupuesto usa seq_plantilla_presupuesto, pero
-- ningún script la creaba (las plantillas no se podían crear).
-- fun_insert_det_plantilla usa seq_det_plantilla_presupuesto.
-- Ejecutar ANTES de las funciones de plantilla. Es idempotente: si las
-- tablas ya tienen datos, la secuencia continúa desde el máximo.
-- =====================================================================

CREATE SEQUENCE IF NOT EXISTS seq_plantilla_presupuesto     START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS seq_det_plantilla_presupuesto START WITH 1 INCREMENT BY 1;

SELECT setval('seq_plantilla_presupuesto',
              GREATEST((SELECT COALESCE(MAX(id_plantilla), 0) FROM tab_plantilla_presupuesto), 1)::BIGINT,
              (SELECT COUNT(*) > 0 FROM tab_plantilla_presupuesto));

SELECT setval('seq_det_plantilla_presupuesto',
              GREATEST((SELECT COALESCE(MAX(id_det_plantilla), 0) FROM tab_det_plantilla_presupuesto), 1)::BIGINT,
              (SELECT COUNT(*) > 0 FROM tab_det_plantilla_presupuesto));


-- ======================================================================
-- 1.4-B  DATOS: PUC COLOMBIA (Decreto 2650 de 1993)
-- ======================================================================


-- ----------------------------------------------------------------------
-- Plan Único de Cuentas
-- (1.4) Origen: src/modules/contab/script/inserts/puc_inserts.sql
-- ----------------------------------------------------------------------
-- ================================================================
-- PUC COLOMBIA - DECRETO 2650 DE 1993
-- ENTREGA 1: Clase 1 (ACTIVO) — Grupos 11, 12, 13
-- ================================================================
-- Sin transacción - INSERTs directos
-- ================================================================
ALTER TABLE tab_puc 
    ALTER COLUMN nom_cuenta TYPE VARCHAR(120);

-- Ampliar descrip_puc por si acaso (algunas descripciones largas)
ALTER TABLE tab_puc 
    ALTER COLUMN descrip_puc TYPE VARCHAR(300);

-- ============================================================
-- NIVEL 1 — CLASE 1: ACTIVO
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(1, '1', 'ACTIVO', TRUE, 'Bienes y derechos tangibles e intangibles de propiedad del ente económico', '0', FALSE, TRUE, FALSE);

-- ============================================================
-- NIVEL 2 — GRUPOS DEL ACTIVO
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '11', 'DISPONIBLE', TRUE, 'Recursos de liquidez inmediata', '1', FALSE, TRUE, FALSE),
(2, '12', 'INVERSIONES', TRUE, 'Inversiones en acciones, títulos valores y otros documentos negociables', '1', FALSE, TRUE, FALSE),
(2, '13', 'DEUDORES', TRUE, 'Deudas a cargo de terceros y a favor del ente económico', '1', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 11 — DISPONIBLE
-- ============================================================

-- Nivel 4
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '1105', 'CAJA', TRUE, 'Existencia en dinero efectivo o en cheques', '11', FALSE, TRUE, FALSE),
(4, '1110', 'BANCOS', TRUE, 'Depósitos en moneda nacional y extranjera en bancos', '11', FALSE, TRUE, FALSE),
(4, '1115', 'REMESAS EN TRANSITO', TRUE, 'Cheques sobregiros negociados pendientes de confirmación', '11', FALSE, TRUE, FALSE),
(4, '1120', 'CUENTAS DE AHORRO', TRUE, 'Fondos en cuentas de ahorro en entidades financieras', '11', FALSE, TRUE, FALSE),
(4, '1125', 'FONDOS', TRUE, 'Dineros en poder de funcionarios para fines especiales', '11', FALSE, TRUE, FALSE);

-- Nivel 6 — CAJA (1105)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '110505', 'CAJA GENERAL', TRUE, 'Dinero en efectivo de la caja general', '1105', FALSE, TRUE, FALSE),
(6, '110510', 'CAJAS MENORES', TRUE, 'Fondos fijos de caja menor', '1105', FALSE, TRUE, FALSE),
(6, '110515', 'MONEDA EXTRANJERA', TRUE, 'Dinero en efectivo en moneda extranjera', '1105', FALSE, TRUE, FALSE);

-- Nivel 6 — BANCOS (1110)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '111005', 'MONEDA NACIONAL', TRUE, 'Depósitos en bancos en moneda nacional', '1110', FALSE, TRUE, FALSE),
(6, '111010', 'MONEDA EXTRANJERA', TRUE, 'Depósitos en bancos en moneda extranjera', '1110', FALSE, TRUE, FALSE);

-- Nivel 6 — REMESAS EN TRANSITO (1115)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '111505', 'MONEDA NACIONAL', TRUE, 'Remesas en tránsito moneda nacional', '1115', FALSE, TRUE, FALSE),
(6, '111510', 'MONEDA EXTRANJERA', TRUE, 'Remesas en tránsito moneda extranjera', '1115', FALSE, TRUE, FALSE);

-- Nivel 6 — CUENTAS DE AHORRO (1120)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '112005', 'BANCOS', TRUE, 'Cuentas de ahorro en bancos', '1120', FALSE, TRUE, FALSE),
(6, '112010', 'CORPORACIONES DE AHORRO Y VIVIENDA', TRUE, 'Cuentas de ahorro en CAV', '1120', FALSE, TRUE, FALSE),
(6, '112015', 'ORGANISMOS COOPERATIVOS FINANCIEROS', TRUE, 'Cuentas de ahorro en cooperativas', '1120', FALSE, TRUE, FALSE);

-- Nivel 6 — FONDOS (1125)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '112505', 'ROTATORIOS MONEDA NACIONAL', TRUE, 'Fondos rotatorios en moneda nacional', '1125', FALSE, TRUE, FALSE),
(6, '112510', 'ROTATORIOS MONEDA EXTRANJERA', TRUE, 'Fondos rotatorios en moneda extranjera', '1125', FALSE, TRUE, FALSE),
(6, '112515', 'ESPECIALES MONEDA NACIONAL', TRUE, 'Fondos especiales en moneda nacional', '1125', FALSE, TRUE, FALSE),
(6, '112520', 'ESPECIALES MONEDA EXTRANJERA', TRUE, 'Fondos especiales en moneda extranjera', '1125', FALSE, TRUE, FALSE),
(6, '112525', 'DE AMORTIZACION MONEDA NACIONAL', TRUE, 'Fondos de amortización moneda nacional', '1125', FALSE, TRUE, FALSE),
(6, '112530', 'DE AMORTIZACION MONEDA EXTRANJERA', TRUE, 'Fondos de amortización moneda extranjera', '1125', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 12 — INVERSIONES
-- ============================================================

-- Nivel 4
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '1205', 'ACCIONES', TRUE, 'Inversiones en sociedades por acciones', '12', FALSE, TRUE, FALSE),
(4, '1210', 'CUOTAS O PARTES DE INTERES SOCIAL', TRUE, 'Inversiones en sociedades limitadas', '12', FALSE, TRUE, FALSE),
(4, '1215', 'BONOS', TRUE, 'Inversiones en bonos', '12', FALSE, TRUE, FALSE),
(4, '1220', 'CEDULAS', TRUE, 'Inversiones en cédulas', '12', FALSE, TRUE, FALSE),
(4, '1225', 'CERTIFICADOS', TRUE, 'Inversiones en certificados', '12', FALSE, TRUE, FALSE),
(4, '1230', 'PAPELES COMERCIALES', TRUE, 'Inversiones en papeles comerciales', '12', FALSE, TRUE, FALSE),
(4, '1235', 'TITULOS', TRUE, 'Inversiones en títulos', '12', FALSE, TRUE, FALSE),
(4, '1240', 'ACEPTACIONES BANCARIAS O FINANCIERAS', TRUE, 'Aceptaciones bancarias', '12', FALSE, TRUE, FALSE),
(4, '1245', 'DERECHOS FIDUCIARIOS', TRUE, 'Derechos en fiducias', '12', FALSE, TRUE, FALSE),
(4, '1250', 'DERECHOS DE RECOMPRA DE INVERSIONES NEGOCIADAS (REPOS)', TRUE, 'REPOS', '12', FALSE, TRUE, FALSE),
(4, '1255', 'OBLIGATORIAS', TRUE, 'Inversiones obligatorias', '12', FALSE, TRUE, FALSE),
(4, '1260', 'CUENTAS EN PARTICIPACION', TRUE, 'Cuentas en participación', '12', FALSE, TRUE, FALSE),
(4, '1295', 'OTRAS INVERSIONES', TRUE, 'Otras inversiones', '12', FALSE, TRUE, FALSE),
(4, '1299', 'PROVISIONES', FALSE, 'Provisión para inversiones', '12', FALSE, TRUE, FALSE);

-- Nivel 6 — ACCIONES (1205)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '120505', 'AGRICULTURA, GANADERIA, CAZA Y SILVICULTURA', TRUE, 'Acciones sector agropecuario', '1205', FALSE, TRUE, FALSE),
(6, '120510', 'PESCA', TRUE, 'Acciones sector pesca', '1205', FALSE, TRUE, FALSE),
(6, '120515', 'EXPLOTACION DE MINAS Y CANTERAS', TRUE, 'Acciones sector minero', '1205', FALSE, TRUE, FALSE),
(6, '120520', 'INDUSTRIA MANUFACTURERA', TRUE, 'Acciones sector manufacturero', '1205', FALSE, TRUE, FALSE),
(6, '120525', 'SUMINISTRO DE ELECTRICIDAD, GAS Y AGUA', TRUE, 'Acciones sector servicios públicos', '1205', FALSE, TRUE, FALSE),
(6, '120530', 'CONSTRUCCION', TRUE, 'Acciones sector construcción', '1205', FALSE, TRUE, FALSE),
(6, '120535', 'COMERCIO AL POR MAYOR Y AL POR MENOR', TRUE, 'Acciones sector comercio', '1205', FALSE, TRUE, FALSE),
(6, '120540', 'HOTELES Y RESTAURANTES', TRUE, 'Acciones sector hotelero', '1205', FALSE, TRUE, FALSE),
(6, '120545', 'TRANSPORTE, ALMACENAMIENTO Y COMUNICACIONES', TRUE, 'Acciones sector transporte', '1205', FALSE, TRUE, FALSE),
(6, '120550', 'ACTIVIDAD FINANCIERA', TRUE, 'Acciones sector financiero', '1205', FALSE, TRUE, FALSE),
(6, '120555', 'ACTIVIDADES INMOBILIARIAS, EMPRESARIALES Y DE ALQUILER', TRUE, 'Acciones sector inmobiliario', '1205', FALSE, TRUE, FALSE),
(6, '120560', 'ENSEÑANZA', TRUE, 'Acciones sector educación', '1205', FALSE, TRUE, FALSE),
(6, '120565', 'SERVICIOS SOCIALES Y DE SALUD', TRUE, 'Acciones sector salud', '1205', FALSE, TRUE, FALSE),
(6, '120570', 'OTRAS ACTIVIDADES DE SERVICIOS COMUNITARIOS, SOCIALES Y PERSONALES', TRUE, 'Acciones otros servicios', '1205', FALSE, TRUE, FALSE),
(6, '120599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste por inflación acciones', '1205', FALSE, TRUE, FALSE);

-- Nivel 6 — CUOTAS O PARTES DE INTERES SOCIAL (1210)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '121005', 'AGRICULTURA, GANADERIA, CAZA Y SILVICULTURA', TRUE, 'Cuotas sector agropecuario', '1210', FALSE, TRUE, FALSE),
(6, '121010', 'PESCA', TRUE, 'Cuotas sector pesca', '1210', FALSE, TRUE, FALSE),
(6, '121015', 'EXPLOTACION DE MINAS Y CANTERAS', TRUE, 'Cuotas sector minero', '1210', FALSE, TRUE, FALSE),
(6, '121020', 'INDUSTRIA MANUFACTURERA', TRUE, 'Cuotas sector manufacturero', '1210', FALSE, TRUE, FALSE),
(6, '121025', 'SUMINISTRO DE ELECTRICIDAD, GAS Y AGUA', TRUE, 'Cuotas sector servicios públicos', '1210', FALSE, TRUE, FALSE),
(6, '121030', 'CONSTRUCCION', TRUE, 'Cuotas sector construcción', '1210', FALSE, TRUE, FALSE),
(6, '121035', 'COMERCIO AL POR MAYOR Y AL POR MENOR', TRUE, 'Cuotas sector comercio', '1210', FALSE, TRUE, FALSE),
(6, '121040', 'HOTELES Y RESTAURANTES', TRUE, 'Cuotas sector hotelero', '1210', FALSE, TRUE, FALSE),
(6, '121045', 'TRANSPORTE, ALMACENAMIENTO Y COMUNICACIONES', TRUE, 'Cuotas sector transporte', '1210', FALSE, TRUE, FALSE),
(6, '121050', 'ACTIVIDAD FINANCIERA', TRUE, 'Cuotas sector financiero', '1210', FALSE, TRUE, FALSE),
(6, '121055', 'ACTIVIDADES INMOBILIARIAS, EMPRESARIALES Y DE ALQUILER', TRUE, 'Cuotas sector inmobiliario', '1210', FALSE, TRUE, FALSE),
(6, '121060', 'ENSEÑANZA', TRUE, 'Cuotas sector educación', '1210', FALSE, TRUE, FALSE),
(6, '121065', 'SERVICIOS SOCIALES Y DE SALUD', TRUE, 'Cuotas sector salud', '1210', FALSE, TRUE, FALSE),
(6, '121070', 'OTRAS ACTIVIDADES DE SERVICIOS COMUNITARIOS, SOCIALES Y PERSONALES', TRUE, 'Cuotas otros servicios', '1210', FALSE, TRUE, FALSE),
(6, '121099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste por inflación cuotas', '1210', FALSE, TRUE, FALSE);

-- Nivel 6 — BONOS (1215)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '121505', 'BONOS PUBLICOS MONEDA NACIONAL', TRUE, 'Bonos públicos MN', '1215', FALSE, TRUE, FALSE),
(6, '121510', 'BONOS PUBLICOS MONEDA EXTRANJERA', TRUE, 'Bonos públicos ME', '1215', FALSE, TRUE, FALSE),
(6, '121515', 'BONOS ORDINARIOS', TRUE, 'Bonos ordinarios', '1215', FALSE, TRUE, FALSE),
(6, '121520', 'BONOS CONVERTIBLES EN ACCIONES', TRUE, 'Bonos convertibles', '1215', FALSE, TRUE, FALSE),
(6, '121595', 'OTROS', TRUE, 'Otros bonos', '1215', FALSE, TRUE, FALSE);

-- Nivel 6 — CEDULAS (1220)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '122005', 'CEDULAS DE CAPITALIZACION', TRUE, 'Cédulas de capitalización', '1220', FALSE, TRUE, FALSE),
(6, '122010', 'CEDULAS HIPOTECARIAS', TRUE, 'Cédulas hipotecarias', '1220', FALSE, TRUE, FALSE),
(6, '122015', 'CEDULAS DE INVERSION', TRUE, 'Cédulas de inversión', '1220', FALSE, TRUE, FALSE),
(6, '122095', 'OTRAS', TRUE, 'Otras cédulas', '1220', FALSE, TRUE, FALSE);

-- Nivel 6 — CERTIFICADOS (1225)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '122505', 'CERTIFICADOS DE DEPOSITO A TERMINO (C.D.T.)', TRUE, 'CDT', '1225', FALSE, TRUE, FALSE),
(6, '122510', 'CERTIFICADOS DE DEPOSITO DE AHORRO', TRUE, 'CDA', '1225', FALSE, TRUE, FALSE),
(6, '122515', 'CERTIFICADOS DE AHORRO DE VALOR CONSTANTE (C.A.V.C.)', TRUE, 'CAVC', '1225', FALSE, TRUE, FALSE),
(6, '122520', 'CERTIFICADOS DE CAMBIO', TRUE, 'Certificados de cambio', '1225', FALSE, TRUE, FALSE),
(6, '122525', 'CERTIFICADOS CAFETEROS VALORIZABLES', TRUE, 'Certificados cafeteros', '1225', FALSE, TRUE, FALSE),
(6, '122530', 'CERTIFICADOS ELECTRICOS VALORIZABLES (C.E.V.)', TRUE, 'CEV', '1225', FALSE, TRUE, FALSE),
(6, '122535', 'CERTIFICADOS DE REEMBOLSO TRIBUTARIO (C.E.R.T.)', TRUE, 'CERT', '1225', FALSE, TRUE, FALSE),
(6, '122540', 'CERTIFICADOS DE DESARROLLO TURISTICO', TRUE, 'Certificados turísticos', '1225', FALSE, TRUE, FALSE),
(6, '122545', 'CERTIFICADOS DE INVERSION FORESTAL (C.I.F.)', TRUE, 'CIF', '1225', FALSE, TRUE, FALSE),
(6, '122595', 'OTROS', TRUE, 'Otros certificados', '1225', FALSE, TRUE, FALSE);

-- Nivel 6 — PAPELES COMERCIALES (1230)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '123005', 'EMPRESAS COMERCIALES', TRUE, 'Papeles empresas comerciales', '1230', FALSE, TRUE, FALSE),
(6, '123010', 'EMPRESAS INDUSTRIALES', TRUE, 'Papeles empresas industriales', '1230', FALSE, TRUE, FALSE),
(6, '123015', 'EMPRESAS DE SERVICIOS', TRUE, 'Papeles empresas servicios', '1230', FALSE, TRUE, FALSE);

-- Nivel 6 — TITULOS (1235)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '123505', 'TITULOS DE DESARROLLO AGROPECUARIO', TRUE, 'TDA', '1235', FALSE, TRUE, FALSE),
(6, '123510', 'TITULOS CANJEABLES POR CERTIFICADOS DE CAMBIO', TRUE, 'TCC', '1235', FALSE, TRUE, FALSE),
(6, '123515', 'TITULOS DE TESORERIA (T.E.S.)', TRUE, 'TES', '1235', FALSE, TRUE, FALSE),
(6, '123520', 'TITULOS DE PARTICIPACION', TRUE, 'Títulos de participación', '1235', FALSE, TRUE, FALSE),
(6, '123525', 'TITULOS DE CREDITO DE FOMENTO', TRUE, 'TCF', '1235', FALSE, TRUE, FALSE),
(6, '123530', 'TITULOS FINANCIEROS AGROINDUSTRIALES (T.F.A.)', TRUE, 'TFA', '1235', FALSE, TRUE, FALSE),
(6, '123535', 'TITULOS DE AHORRO CAFETERO (T.A.C.)', TRUE, 'TAC', '1235', FALSE, TRUE, FALSE),
(6, '123540', 'TITULOS DE AHORRO NACIONAL (T.A.N.)', TRUE, 'TAN', '1235', FALSE, TRUE, FALSE),
(6, '123545', 'TITULOS ENERGETICOS DE RENTABILIDAD CRECIENTE (T.E.R.)', TRUE, 'TER', '1235', FALSE, TRUE, FALSE),
(6, '123550', 'TITULOS DE AHORRO EDUCATIVO (T.A.E.)', TRUE, 'TAE', '1235', FALSE, TRUE, FALSE),
(6, '123555', 'TITULOS FINANCIEROS INDUSTRIALES Y COMERCIALES', TRUE, 'TFIC', '1235', FALSE, TRUE, FALSE),
(6, '123560', 'TESOROS', TRUE, 'Tesoros', '1235', FALSE, TRUE, FALSE),
(6, '123565', 'TITULOS DE DEVOLUCION DE IMPUESTOS NACIONALES (TIDIS)', TRUE, 'TIDIS', '1235', FALSE, TRUE, FALSE),
(6, '123570', 'TITULOS INMOBILIARIOS', TRUE, 'Títulos inmobiliarios', '1235', FALSE, TRUE, FALSE),
(6, '123595', 'OTROS', TRUE, 'Otros títulos', '1235', FALSE, TRUE, FALSE);

-- Nivel 6 — ACEPTACIONES BANCARIAS (1240)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '124005', 'BANCOS COMERCIALES', TRUE, 'Aceptaciones bancos comerciales', '1240', FALSE, TRUE, FALSE),
(6, '124010', 'COMPANIAS DE FINANCIAMIENTO COMERCIAL', TRUE, 'Aceptaciones CFC', '1240', FALSE, TRUE, FALSE),
(6, '124015', 'CORPORACIONES FINANCIERAS', TRUE, 'Aceptaciones corporaciones', '1240', FALSE, TRUE, FALSE),
(6, '124095', 'OTRAS', TRUE, 'Otras aceptaciones', '1240', FALSE, TRUE, FALSE);

-- Nivel 6 — DERECHOS FIDUCIARIOS (1245)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '124505', 'FIDEICOMISOS DE INVERSION MONEDA NACIONAL', TRUE, 'Fideicomisos MN', '1245', FALSE, TRUE, FALSE),
(6, '124510', 'FIDEICOMISOS DE INVERSION MONEDA EXTRANJERA', TRUE, 'Fideicomisos ME', '1245', FALSE, TRUE, FALSE);

-- Nivel 6 — DERECHOS DE RECOMPRA (1250)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '125005', 'ACCIONES', TRUE, 'REPOS acciones', '1250', FALSE, TRUE, FALSE),
(6, '125010', 'CUOTAS O PARTES DE INTERES SOCIAL', TRUE, 'REPOS cuotas', '1250', FALSE, TRUE, FALSE),
(6, '125015', 'BONOS', TRUE, 'REPOS bonos', '1250', FALSE, TRUE, FALSE),
(6, '125020', 'CEDULAS', TRUE, 'REPOS cédulas', '1250', FALSE, TRUE, FALSE),
(6, '125025', 'CERTIFICADOS', TRUE, 'REPOS certificados', '1250', FALSE, TRUE, FALSE),
(6, '125030', 'PAPELES COMERCIALES', TRUE, 'REPOS papeles', '1250', FALSE, TRUE, FALSE),
(6, '125035', 'TITULOS', TRUE, 'REPOS títulos', '1250', FALSE, TRUE, FALSE),
(6, '125040', 'ACEPTACIONES BANCARIAS O FINANCIERAS', TRUE, 'REPOS aceptaciones', '1250', FALSE, TRUE, FALSE),
(6, '125095', 'OTROS', TRUE, 'Otros REPOS', '1250', FALSE, TRUE, FALSE),
(6, '125099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación REPOS', '1250', FALSE, TRUE, FALSE);

-- Nivel 6 — OBLIGATORIAS (1255)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '125505', 'BONOS DE FINANCIAMIENTO ESPECIAL', TRUE, 'Bonos especiales', '1255', FALSE, TRUE, FALSE),
(6, '125510', 'BONOS DE FINANCIAMIENTO PRESUPUESTAL', TRUE, 'Bonos presupuestales', '1255', FALSE, TRUE, FALSE),
(6, '125515', 'BONOS PARA DESARROLLO SOCIAL Y SEGURIDAD INTERNA (B.D.S.I.)', TRUE, 'BDSI', '1255', FALSE, TRUE, FALSE),
(6, '125595', 'OTRAS', TRUE, 'Otras obligatorias', '1255', FALSE, TRUE, FALSE);

-- Nivel 6 — CUENTAS EN PARTICIPACION (1260)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '126099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación cuentas participación', '1260', FALSE, TRUE, FALSE);

-- Nivel 6 — OTRAS INVERSIONES (1295)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '129505', 'APORTES EN COOPERATIVAS', TRUE, 'Aportes cooperativas', '1295', FALSE, TRUE, FALSE),
(6, '129510', 'DERECHOS EN CLUBES SOCIALES', TRUE, 'Clubes sociales', '1295', FALSE, TRUE, FALSE),
(6, '129515', 'ACCIONES O DERECHOS EN CLUBES DEPORTIVOS', TRUE, 'Clubes deportivos', '1295', FALSE, TRUE, FALSE),
(6, '129520', 'BONOS EN COLEGIOS', TRUE, 'Bonos colegios', '1295', FALSE, TRUE, FALSE),
(6, '129595', 'DIVERSAS', TRUE, 'Inversiones diversas', '1295', FALSE, TRUE, FALSE),
(6, '129599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación otras inversiones', '1295', FALSE, TRUE, FALSE);

-- Nivel 6 — PROVISIONES INVERSIONES (1299)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '129905', 'ACCIONES', FALSE, 'Provisión acciones', '1299', FALSE, TRUE, FALSE),
(6, '129910', 'CUOTAS O PARTES DE INTERES SOCIAL', FALSE, 'Provisión cuotas', '1299', FALSE, TRUE, FALSE),
(6, '129915', 'BONOS', FALSE, 'Provisión bonos', '1299', FALSE, TRUE, FALSE),
(6, '129920', 'CEDULAS', FALSE, 'Provisión cédulas', '1299', FALSE, TRUE, FALSE),
(6, '129925', 'CERTIFICADOS', FALSE, 'Provisión certificados', '1299', FALSE, TRUE, FALSE),
(6, '129930', 'PAPELES COMERCIALES', FALSE, 'Provisión papeles', '1299', FALSE, TRUE, FALSE),
(6, '129935', 'TITULOS', FALSE, 'Provisión títulos', '1299', FALSE, TRUE, FALSE),
(6, '129940', 'ACEPTACIONES BANCARIAS O FINANCIERAS', FALSE, 'Provisión aceptaciones', '1299', FALSE, TRUE, FALSE),
(6, '129945', 'DERECHOS FIDUCIARIOS', FALSE, 'Provisión fiducias', '1299', FALSE, TRUE, FALSE),
(6, '129950', 'DERECHOS DE RECOMPRA DE INVERSIONES NEGOCIADAS', FALSE, 'Provisión REPOS', '1299', FALSE, TRUE, FALSE),
(6, '129955', 'OBLIGATORIAS', FALSE, 'Provisión obligatorias', '1299', FALSE, TRUE, FALSE),
(6, '129960', 'CUENTAS EN PARTICIPACION', FALSE, 'Provisión cuentas participación', '1299', FALSE, TRUE, FALSE),
(6, '129995', 'OTRAS INVERSIONES', FALSE, 'Provisión otras inversiones', '1299', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 13 — DEUDORES
-- ============================================================

-- Nivel 4
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '1305', 'CLIENTES', TRUE, 'Valores a favor por ventas a clientes', '13', TRUE, TRUE, FALSE),
(4, '1310', 'CUENTAS CORRIENTES COMERCIALES', TRUE, 'Cuentas corrientes comerciales', '13', TRUE, TRUE, FALSE),
(4, '1315', 'CUENTAS POR COBRAR A CASA MATRIZ', TRUE, 'Cuentas por cobrar a casa matriz', '13', FALSE, TRUE, FALSE),
(4, '1320', 'CUENTAS POR COBRAR A VINCULADOS ECONOMICOS', TRUE, 'Cuentas por cobrar a vinculados', '13', FALSE, TRUE, FALSE),
(4, '1323', 'CUENTAS POR COBRAR A DIRECTORES', TRUE, 'Cuentas por cobrar a directores', '13', FALSE, TRUE, FALSE),
(4, '1325', 'CUENTAS POR COBRAR A SOCIOS Y ACCIONISTAS', TRUE, 'Cuentas por cobrar a socios', '13', FALSE, TRUE, FALSE),
(4, '1328', 'APORTES POR COBRAR', TRUE, 'Aportes por cobrar', '13', FALSE, TRUE, FALSE),
(4, '1330', 'ANTICIPOS Y AVANCES', TRUE, 'Anticipos y avances a terceros', '13', TRUE, TRUE, FALSE),
(4, '1332', 'CUENTAS DE OPERACION CONJUNTA', TRUE, 'Cuentas de operación conjunta', '13', FALSE, TRUE, FALSE),
(4, '1335', 'DEPOSITOS', TRUE, 'Depósitos entregados', '13', FALSE, TRUE, FALSE),
(4, '1340', 'PROMESAS DE COMPRA VENTA', TRUE, 'Promesas de compraventa', '13', FALSE, TRUE, FALSE),
(4, '1345', 'INGRESOS POR COBRAR', TRUE, 'Ingresos causados pendientes de cobro', '13', FALSE, TRUE, FALSE),
(4, '1350', 'RETENCION SOBRE CONTRATOS', TRUE, 'Retenciones sobre contratos', '13', FALSE, TRUE, FALSE),
(4, '1355', 'ANTICIPO DE IMPUESTOS Y CONTRIBUCIONES O SALDOS A FAVOR', TRUE, 'Anticipos de impuestos', '13', FALSE, TRUE, FALSE),
(4, '1360', 'RECLAMACIONES', TRUE, 'Reclamaciones a aseguradoras', '13', FALSE, TRUE, FALSE),
(4, '1365', 'CUENTAS POR COBRAR A TRABAJADORES', TRUE, 'Préstamos a trabajadores', '13', TRUE, TRUE, FALSE),
(4, '1370', 'PRESTAMOS A PARTICULARES', TRUE, 'Préstamos a particulares', '13', TRUE, TRUE, FALSE),
(4, '1380', 'DEUDORES VARIOS', TRUE, 'Deudores varios', '13', FALSE, TRUE, FALSE),
(4, '1385', 'DERECHOS DE RECOMPRA DE CARTERA NEGOCIADA', TRUE, 'Derechos de recompra cartera', '13', FALSE, TRUE, FALSE),
(4, '1390', 'DEUDAS DE DIFICIL COBRO', TRUE, 'Deudas de difícil cobro', '13', FALSE, TRUE, FALSE),
(4, '1399', 'PROVISIONES', FALSE, 'Provisión para deudores', '13', FALSE, TRUE, FALSE);

-- Nivel 6 — CLIENTES (1305)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '130505', 'NACIONALES', TRUE, 'Clientes nacionales', '1305', TRUE, TRUE, FALSE),
(6, '130510', 'DEL EXTERIOR', TRUE, 'Clientes del exterior', '1305', TRUE, TRUE, FALSE),
(6, '130515', 'DEUDORES DEL SISTEMA', TRUE, 'Deudores del sistema', '1305', TRUE, TRUE, FALSE);

-- Nivel 6 — CUENTAS CORRIENTES COMERCIALES (1310)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '131005', 'CASA MATRIZ', TRUE, 'Cuentas corrientes casa matriz', '1310', TRUE, TRUE, FALSE),
(6, '131010', 'COMPAÑIAS VINCULADAS', TRUE, 'Cuentas corrientes vinculadas', '1310', TRUE, TRUE, FALSE),
(6, '131015', 'ACCIONISTAS O SOCIOS', TRUE, 'Cuentas corrientes socios', '1310', TRUE, TRUE, FALSE),
(6, '131020', 'PARTICULARES', TRUE, 'Cuentas corrientes particulares', '1310', TRUE, TRUE, FALSE),
(6, '131095', 'OTRAS', TRUE, 'Otras cuentas corrientes', '1310', TRUE, TRUE, FALSE);

-- Nivel 6 — CUENTAS POR COBRAR A CASA MATRIZ (1315)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '131505', 'VENTAS', TRUE, 'Ventas a casa matriz', '1315', FALSE, TRUE, FALSE),
(6, '131510', 'PAGOS A NOMBRE DE CASA MATRIZ', TRUE, 'Pagos a nombre casa matriz', '1315', FALSE, TRUE, FALSE),
(6, '131515', 'VALORES RECIBIDOS POR CASA MATRIZ', TRUE, 'Valores recibidos casa matriz', '1315', FALSE, TRUE, FALSE),
(6, '131520', 'PRESTAMOS', TRUE, 'Préstamos a casa matriz', '1315', FALSE, TRUE, FALSE);

-- Nivel 6 — CUENTAS POR COBRAR A VINCULADOS (1320)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '132005', 'FILIALES', TRUE, 'Cuentas por cobrar a filiales', '1320', FALSE, TRUE, FALSE),
(6, '132010', 'SUBSIDIARIAS', TRUE, 'Cuentas por cobrar a subsidiarias', '1320', FALSE, TRUE, FALSE),
(6, '132015', 'SUCURSALES', TRUE, 'Cuentas por cobrar a sucursales', '1320', FALSE, TRUE, FALSE);

-- Nivel 6 — CUENTAS POR COBRAR A DIRECTORES (1323)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '132301', 'A D.R.2894/94, ART.7', TRUE, 'Cuentas por cobrar a directores', '1323', FALSE, TRUE, FALSE),
(6, '132398', 'A D.R.2894/94, ART.7', TRUE, 'Cuentas por cobrar a directores 2', '1323', FALSE, TRUE, FALSE);

-- Nivel 6 — CUENTAS POR COBRAR A SOCIOS Y ACCIONISTAS (1325)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '132505', 'A SOCIOS', TRUE, 'Cuentas por cobrar a socios', '1325', FALSE, TRUE, FALSE),
(6, '132510', 'A ACCIONISTAS', TRUE, 'Cuentas por cobrar a accionistas', '1325', FALSE, TRUE, FALSE);

-- Nivel 6 — APORTES POR COBRAR (1328)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '132801', 'APORTES POR COBRAR 132801 A 132898', TRUE, 'Aportes por cobrar rango', '1328', FALSE, TRUE, FALSE),
(6, '132898', 'APORTES POR COBRAR FIN RANGO', TRUE, 'Aportes por cobrar fin rango', '1328', FALSE, TRUE, FALSE);

-- Nivel 6 — ANTICIPOS Y AVANCES (1330)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '133005', 'A PROVEEDORES', TRUE, 'Anticipos a proveedores', '1330', TRUE, TRUE, FALSE),
(6, '133010', 'A CONTRATISTAS', TRUE, 'Anticipos a contratistas', '1330', TRUE, TRUE, FALSE),
(6, '133015', 'A TRABAJADORES', TRUE, 'Anticipos a trabajadores', '1330', TRUE, TRUE, FALSE),
(6, '133020', 'A AGENTES', TRUE, 'Anticipos a agentes', '1330', TRUE, TRUE, FALSE),
(6, '133025', 'A CONCESIONARIOS', TRUE, 'Anticipos a concesionarios', '1330', TRUE, TRUE, FALSE),
(6, '133030', 'DE ADJUDICACIONES', TRUE, 'Anticipos adjudicaciones', '1330', FALSE, TRUE, FALSE),
(6, '133095', 'OTROS', TRUE, 'Otros anticipos', '1330', TRUE, TRUE, FALSE),
(6, '133099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación anticipos', '1330', FALSE, TRUE, FALSE);

-- Nivel 6 — CUENTAS DE OPERACION CONJUNTA (1332)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '133201', 'CUENTAS DE OPERACION CONJUNTA 133201 A 133298', TRUE, 'Operación conjunta rango', '1332', FALSE, TRUE, FALSE),
(6, '133298', 'CUENTAS DE OPERACION CONJUNTA FIN RANGO', TRUE, 'Operación conjunta fin rango', '1332', FALSE, TRUE, FALSE);

-- Nivel 6 — DEPOSITOS (1335)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '133505', 'PARA IMPORTACIONES', TRUE, 'Depósitos para importaciones', '1335', FALSE, TRUE, FALSE),
(6, '133510', 'PARA SERVICIOS', TRUE, 'Depósitos para servicios', '1335', FALSE, TRUE, FALSE),
(6, '133515', 'PARA CONTRATOS', TRUE, 'Depósitos para contratos', '1335', FALSE, TRUE, FALSE),
(6, '133520', 'PARA RESPONSABILIDADES', TRUE, 'Depósitos para responsabilidades', '1335', FALSE, TRUE, FALSE),
(6, '133525', 'PARA JUICIOS EJECUTIVOS', TRUE, 'Depósitos para juicios', '1335', FALSE, TRUE, FALSE),
(6, '133530', 'PARA ADQUISICION DE ACCIONES, CUOTAS O DERECHOS SOCIALES', TRUE, 'Depósitos para adquisiciones', '1335', FALSE, TRUE, FALSE),
(6, '133535', 'EN GARANTIA', TRUE, 'Depósitos en garantía', '1335', FALSE, TRUE, FALSE),
(6, '133595', 'OTROS', TRUE, 'Otros depósitos', '1335', FALSE, TRUE, FALSE);

-- Nivel 6 — PROMESAS DE COMPRAVENTA (1340)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '134005', 'DE BIENES RAICES', TRUE, 'Promesas bienes raíces', '1340', FALSE, TRUE, FALSE),
(6, '134010', 'DE MAQUINARIA Y EQUIPO', TRUE, 'Promesas maquinaria', '1340', FALSE, TRUE, FALSE),
(6, '134015', 'DE FLOTA Y EQUIPO DE TRANSPORTE', TRUE, 'Promesas flota y equipo', '1340', FALSE, TRUE, FALSE),
(6, '134020', 'DE FLOTA Y EQUIPO AEREO', TRUE, 'Promesas flota aérea', '1340', FALSE, TRUE, FALSE),
(6, '134025', 'DE FLOTA Y EQUIPO FERREO', TRUE, 'Promesas flota férrea', '1340', FALSE, TRUE, FALSE),
(6, '134030', 'DE FLOTA Y EQUIPO FLUVIAL Y/O MARITIMO', TRUE, 'Promesas flota fluvial', '1340', FALSE, TRUE, FALSE),
(6, '134035', 'DE SEMOVIENTES', TRUE, 'Promesas semovientes', '1340', FALSE, TRUE, FALSE),
(6, '134095', 'DE OTROS BIENES', TRUE, 'Promesas otros bienes', '1340', FALSE, TRUE, FALSE);

-- Nivel 6 — INGRESOS POR COBRAR (1345)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '134505', 'DIVIDENDOS Y/O PARTICIPACIONES', TRUE, 'Dividendos por cobrar', '1345', FALSE, TRUE, FALSE),
(6, '134510', 'INTERESES', TRUE, 'Intereses por cobrar', '1345', FALSE, TRUE, FALSE),
(6, '134515', 'COMISIONES', TRUE, 'Comisiones por cobrar', '1345', FALSE, TRUE, FALSE),
(6, '134520', 'HONORARIOS', TRUE, 'Honorarios por cobrar', '1345', FALSE, TRUE, FALSE),
(6, '134525', 'SERVICIOS', TRUE, 'Servicios por cobrar', '1345', FALSE, TRUE, FALSE),
(6, '134530', 'ARRENDAMIENTOS', TRUE, 'Arrendamientos por cobrar', '1345', FALSE, TRUE, FALSE),
(6, '134535', 'CERT POR COBRAR', TRUE, 'CERT por cobrar', '1345', FALSE, TRUE, FALSE),
(6, '134595', 'OTROS', TRUE, 'Otros ingresos por cobrar', '1345', FALSE, TRUE, FALSE);

-- Nivel 6 — RETENCION SOBRE CONTRATOS (1350)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '135005', 'DE CONSTRUCCION', TRUE, 'Retención construcción', '1350', FALSE, TRUE, FALSE),
(6, '135010', 'DE PRESTACION DE SERVICIOS', TRUE, 'Retención servicios', '1350', FALSE, TRUE, FALSE),
(6, '135095', 'OTROS', TRUE, 'Otras retenciones', '1350', FALSE, TRUE, FALSE);

-- Nivel 6 — ANTICIPO DE IMPUESTOS (1355)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '135505', 'ANTICIPO DE IMPUESTOS DE RENTA Y COMPLEMENTARIOS', TRUE, 'Anticipo renta', '1355', FALSE, TRUE, FALSE),
(6, '135510', 'ANTICIPO DE IMPUESTOS DE INDUSTRIA Y COMERCIO', TRUE, 'Anticipo ICA', '1355', FALSE, TRUE, FALSE),
(6, '135515', 'RETENCION EN LA FUENTE', TRUE, 'Retención en la fuente', '1355', FALSE, TRUE, FALSE),
(6, '135517', 'IMPUESTO A LAS VENTAS RETENIDO', TRUE, 'IVA retenido', '1355', FALSE, TRUE, FALSE),
(6, '135518', 'IMPUESTO DE INDUSTRIA Y COMERCIO RETENIDO', TRUE, 'ICA retenido', '1355', FALSE, TRUE, FALSE),
(6, '135520', 'SOBRANTES EN LIQUIDACION PRIVADA DE IMPUESTOS', TRUE, 'Sobrantes liquidación', '1355', FALSE, TRUE, FALSE),
(6, '135595', 'OTROS', TRUE, 'Otros anticipos', '1355', FALSE, TRUE, FALSE);

-- Nivel 6 — RECLAMACIONES (1360)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '136005', 'A COMPAÑIAS ASEGURADORAS', TRUE, 'Reclamaciones a aseguradoras', '1360', FALSE, TRUE, FALSE),
(6, '136010', 'A TRANSPORTADORES', TRUE, 'Reclamaciones a transportadores', '1360', FALSE, TRUE, FALSE),
(6, '136095', 'OTRAS', TRUE, 'Otras reclamaciones', '1360', FALSE, TRUE, FALSE);

-- Nivel 6 — CUENTAS POR COBRAR A TRABAJADORES (1365)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '136505', 'PRESTAMOS', TRUE, 'Préstamos a trabajadores', '1365', TRUE, TRUE, FALSE),
(6, '136510', 'FALTANTES EN CAJA', TRUE, 'Faltantes en caja', '1365', TRUE, TRUE, FALSE),
(6, '136515', 'FALTANTES EN INVENTARIOS', TRUE, 'Faltantes en inventarios', '1365', TRUE, TRUE, FALSE),
(6, '136595', 'OTROS', TRUE, 'Otras cuentas por cobrar trabajadores', '1365', TRUE, TRUE, FALSE);

-- Nivel 6 — PRESTAMOS A PARTICULARES (1370)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '137005', 'PRESTAMOS A PARTICULARES', TRUE, 'Préstamos a particulares', '1370', TRUE, TRUE, FALSE);

-- Nivel 6 — DEUDORES VARIOS (1380)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '138005', 'DEPOSITARIOS DE GANADO EN PARTICIPACION', TRUE, 'Depositarios ganado', '1380', FALSE, TRUE, FALSE),
(6, '138010', 'COMISIONISTAS DE BOLSAS', TRUE, 'Comisionistas de bolsas', '1380', FALSE, TRUE, FALSE),
(6, '138015', 'FONDO DE INVERSION', TRUE, 'Fondos de inversión', '1380', FALSE, TRUE, FALSE),
(6, '138020', 'CUENTAS POR COBRAR DE TERCEROS', TRUE, 'Cuentas por cobrar terceros', '1380', FALSE, TRUE, FALSE),
(6, '138025', 'PAGOS POR CUENTA DE TERCEROS', TRUE, 'Pagos por cuenta terceros', '1380', FALSE, TRUE, FALSE),
(6, '138030', 'FONDOS DE INVERSION SOCIAL', TRUE, 'Fondos inversión social', '1380', FALSE, TRUE, FALSE),
(6, '138095', 'OTROS', TRUE, 'Otros deudores varios', '1380', FALSE, TRUE, FALSE);

-- Nivel 6 — DERECHOS DE RECOMPRA DE CARTERA (1385)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '138501', 'DERECHOS DE RECOMPRA DE CARTERA 138501 A 138598', TRUE, 'Recompra cartera rango', '1385', FALSE, TRUE, FALSE),
(6, '138598', 'DERECHOS DE RECOMPRA DE CARTERA FIN RANGO', TRUE, 'Recompra cartera fin', '1385', FALSE, TRUE, FALSE);

-- Nivel 6 — DEUDAS DE DIFICIL COBRO (1390)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '139001', 'DEUDAS DE DIFICIL COBRO 139001 A 139098', TRUE, 'Deudas difícil cobro rango', '1390', FALSE, TRUE, FALSE),
(6, '139098', 'DEUDAS DE DIFICIL COBRO FIN RANGO', TRUE, 'Deudas difícil cobro fin', '1390', FALSE, TRUE, FALSE);

-- Nivel 6 — PROVISIONES DEUDORES (1399)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '139905', 'CLIENTES', FALSE, 'Provisión clientes', '1399', FALSE, TRUE, FALSE),
(6, '139910', 'CUENTAS CORRIENTES COMERCIALES', FALSE, 'Provisión cuentas corrientes', '1399', FALSE, TRUE, FALSE),
(6, '139915', 'CUENTAS POR COBRAR A CASA MATRIZ', FALSE, 'Provisión casa matriz', '1399', FALSE, TRUE, FALSE),
(6, '139920', 'CUENTAS POR COBRAR A VINCULADOS ECONOMICOS', FALSE, 'Provisión vinculados', '1399', FALSE, TRUE, FALSE),
(6, '139925', 'CUENTAS POR COBRAR A SOCIOS Y ACCIONISTAS', FALSE, 'Provisión socios', '1399', FALSE, TRUE, FALSE),
(6, '139930', 'ANTICIPOS Y AVANCES', FALSE, 'Provisión anticipos', '1399', FALSE, TRUE, FALSE),
(6, '139932', 'CUENTAS DE OPERACION CONJUNTA', FALSE, 'Provisión operación conjunta', '1399', FALSE, TRUE, FALSE),
(6, '139935', 'DEPOSITOS', FALSE, 'Provisión depósitos', '1399', FALSE, TRUE, FALSE),
(6, '139940', 'PROMESAS DE COMPRAVENTA', FALSE, 'Provisión promesas', '1399', FALSE, TRUE, FALSE),
(6, '139945', 'INGRESOS POR COBRAR', FALSE, 'Provisión ingresos por cobrar', '1399', FALSE, TRUE, FALSE),
(6, '139950', 'RETENCION SOBRE CONTRATOS', FALSE, 'Provisión retenciones', '1399', FALSE, TRUE, FALSE),
(6, '139955', 'RECLAMACIONES', FALSE, 'Provisión reclamaciones', '1399', FALSE, TRUE, FALSE),
(6, '139960', 'CUENTAS POR COBRAR A TRABAJADORES', FALSE, 'Provisión trabajadores', '1399', FALSE, TRUE, FALSE),
(6, '139965', 'PRESTAMOS A PARTICULARES', FALSE, 'Provisión préstamos', '1399', FALSE, TRUE, FALSE),
(6, '139975', 'DEUDORES VARIOS', FALSE, 'Provisión deudores varios', '1399', FALSE, TRUE, FALSE),
(6, '139980', 'DERECHOS DE RECOMPRA DE CARTERA NEGOCIADA', FALSE, 'Provisión recompra cartera', '1399', FALSE, TRUE, FALSE);

-- ============================================================
-- VERIFICACIÓN
-- ============================================================
-- Ejecuta esto para verificar:
-- SELECT id_nivel, COUNT(*) FROM tab_puc GROUP BY id_nivel ORDER BY id_nivel;
-- SELECT COUNT(*) FROM tab_puc;

-- Total esperado en esta entrega: ~150 registros


-- ================================================================
-- PUC COLOMBIA - DECRETO 2650 DE 1993
-- ENTREGA 2: Clase 1 (14-19) + Clase 2 (21-23)
-- ================================================================

-- ============================================================
-- GRUPO 14 — INVENTARIOS
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '14', 'INVENTARIOS', TRUE, 'Artículos, materiales, suministros, productos y recursos para usar o vender', '1', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '1405', 'MATERIAS PRIMAS', TRUE, 'Materiales para proceso productivo', '14', FALSE, TRUE, FALSE),
(4, '1410', 'PRODUCTOS EN PROCESO', TRUE, 'Productos semielaborados', '14', FALSE, TRUE, FALSE),
(4, '1415', 'OBRAS DE CONSTRUCCION EN CURSO', TRUE, 'Obras de construcción', '14', FALSE, TRUE, FALSE),
(4, '1417', 'OBRAS DE URBANISMO', TRUE, 'Obras de urbanismo', '14', FALSE, TRUE, FALSE),
(4, '1420', 'CONTRATOS EN EJECUCION', TRUE, 'Contratos en ejecución', '14', FALSE, TRUE, FALSE),
(4, '1425', 'CULTIVOS EN DESARROLLO', TRUE, 'Cultivos en desarrollo', '14', FALSE, TRUE, FALSE),
(4, '1428', 'PLANTACIONES AGRICOLAS', TRUE, 'Plantaciones agrícolas', '14', FALSE, TRUE, FALSE),
(4, '1430', 'PRODUCTOS TERMINADOS', TRUE, 'Productos terminados', '14', FALSE, TRUE, FALSE),
(4, '1435', 'MERCANCIAS NO FABRICADAS POR LA EMPRESA', TRUE, 'Mercancías para la venta', '14', FALSE, TRUE, FALSE),
(4, '1440', 'BIENES RAICES PARA LA VENTA', TRUE, 'Bienes raíces para venta', '14', FALSE, TRUE, FALSE),
(4, '1445', 'SEMOVIENTES', TRUE, 'Animales', '14', FALSE, TRUE, FALSE),
(4, '1450', 'TERRENOS', TRUE, 'Terrenos para venta', '14', FALSE, TRUE, FALSE),
(4, '1455', 'MATERIALES, REPUESTOS Y ACCESORIOS', TRUE, 'Materiales y repuestos', '14', FALSE, TRUE, FALSE),
(4, '1460', 'ENVASES Y EMPAQUES', TRUE, 'Envases y empaques', '14', FALSE, TRUE, FALSE),
(4, '1465', 'INVENTARIOS EN TRANSITO', TRUE, 'Inventarios en tránsito', '14', FALSE, TRUE, FALSE),
(4, '1499', 'PROVISIONES', FALSE, 'Provisión para inventarios', '14', FALSE, TRUE, FALSE);

-- Subcuentas 1405
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '140501', 'MATERIAS PRIMAS 140501 A 140598', TRUE, 'Materias primas rango', '1405', FALSE, TRUE, FALSE),
(6, '140598', 'MATERIAS PRIMAS FIN RANGO', TRUE, 'Materias primas fin', '1405', FALSE, TRUE, FALSE),
(6, '140599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación materias primas', '1405', FALSE, TRUE, FALSE);

-- Subcuentas 1410
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '141001', 'PRODUCTOS EN PROCESO 141001 A 141098', TRUE, 'Productos proceso rango', '1410', FALSE, TRUE, FALSE),
(6, '141098', 'PRODUCTOS EN PROCESO FIN RANGO', TRUE, 'Productos proceso fin', '1410', FALSE, TRUE, FALSE),
(6, '141099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación productos proceso', '1410', FALSE, TRUE, FALSE);

-- Subcuentas 1415
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '141501', 'OBRAS DE CONSTRUCCION 141501 A 141598', TRUE, 'Obras construcción rango', '1415', FALSE, TRUE, FALSE),
(6, '141598', 'OBRAS DE CONSTRUCCION FIN RANGO', TRUE, 'Obras construcción fin', '1415', FALSE, TRUE, FALSE),
(6, '141599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación obras', '1415', FALSE, TRUE, FALSE);

-- Subcuentas 1417
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '141701', 'OBRAS DE URBANISMO 141701 A 141798', TRUE, 'Obras urbanismo rango', '1417', FALSE, TRUE, FALSE),
(6, '141798', 'OBRAS DE URBANISMO FIN RANGO', TRUE, 'Obras urbanismo fin', '1417', FALSE, TRUE, FALSE),
(6, '141799', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación obras urbanismo', '1417', FALSE, TRUE, FALSE);

-- Subcuentas 1420
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '142001', 'CONTRATOS EN EJECUCION 142001 A 142098', TRUE, 'Contratos ejecución rango', '1420', FALSE, TRUE, FALSE),
(6, '142098', 'CONTRATOS EN EJECUCION FIN RANGO', TRUE, 'Contratos ejecución fin', '1420', FALSE, TRUE, FALSE),
(6, '142099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación contratos', '1420', FALSE, TRUE, FALSE);

-- Subcuentas 1425
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '142501', 'CULTIVOS EN DESARROLLO 142501 A 142598', TRUE, 'Cultivos rango', '1425', FALSE, TRUE, FALSE),
(6, '142598', 'CULTIVOS EN DESARROLLO FIN RANGO', TRUE, 'Cultivos fin', '1425', FALSE, TRUE, FALSE),
(6, '142599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación cultivos', '1425', FALSE, TRUE, FALSE);

-- Subcuentas 1428
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '142801', 'PLANTACIONES AGRICOLAS 142801 A 142898', TRUE, 'Plantaciones rango', '1428', FALSE, TRUE, FALSE),
(6, '142898', 'PLANTACIONES AGRICOLAS FIN RANGO', TRUE, 'Plantaciones fin', '1428', FALSE, TRUE, FALSE),
(6, '142899', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación plantaciones', '1428', FALSE, TRUE, FALSE);

-- Subcuentas 1430
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '143005', 'PRODUCTOS MANUFACTURADOS', TRUE, 'Productos manufacturados', '1430', FALSE, TRUE, FALSE),
(6, '143010', 'PRODUCTOS EXTRAIDOS Y/O PROCESADOS', TRUE, 'Productos extraídos', '1430', FALSE, TRUE, FALSE),
(6, '143015', 'PRODUCTOS AGRICOLAS Y FORESTALES', TRUE, 'Productos agrícolas', '1430', FALSE, TRUE, FALSE),
(6, '143020', 'SUBPRODUCTOS', TRUE, 'Subproductos', '1430', FALSE, TRUE, FALSE),
(6, '143095', 'OTROS', TRUE, 'Otros productos', '1430', FALSE, TRUE, FALSE),
(6, '143099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación productos', '1430', FALSE, TRUE, FALSE);

-- Subcuentas 1435
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '143501', 'MERCANCIAS NO FABRICADAS 143501 A 143598', TRUE, 'Mercancías rango', '1435', FALSE, TRUE, FALSE),
(6, '143598', 'MERCANCIAS NO FABRICADAS FIN RANGO', TRUE, 'Mercancías fin', '1435', FALSE, TRUE, FALSE),
(6, '143599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación mercancías', '1435', FALSE, TRUE, FALSE);

-- Subcuentas 1440
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '144001', 'BIENES RAICES 144001 A 144098', TRUE, 'Bienes raíces rango', '1440', FALSE, TRUE, FALSE),
(6, '144098', 'BIENES RAICES FIN RANGO', TRUE, 'Bienes raíces fin', '1440', FALSE, TRUE, FALSE),
(6, '144099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación bienes raíces', '1440', FALSE, TRUE, FALSE);

-- Subcuentas 1445
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '144505', 'ESPECIES MAYORES', TRUE, 'Especies mayores', '1445', FALSE, TRUE, FALSE),
(6, '144510', 'ESPECIES MENORES', TRUE, 'Especies menores', '1445', FALSE, TRUE, FALSE),
(6, '144599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación semovientes', '1445', FALSE, TRUE, FALSE);

-- Subcuentas 1450
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '145005', 'POR URBANIZAR', TRUE, 'Terrenos por urbanizar', '1450', FALSE, TRUE, FALSE),
(6, '145010', 'URBANIZADOS POR CONSTRUIR', TRUE, 'Urbanizados por construir', '1450', FALSE, TRUE, FALSE),
(6, '145099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación terrenos', '1450', FALSE, TRUE, FALSE);

-- Subcuentas 1455
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '145505', 'COMBUSTIBLES Y LUBRICANTES', TRUE, 'Combustibles', '1455', FALSE, TRUE, FALSE),
(6, '145510', 'ABONOS Y FERTILIZANTES', TRUE, 'Abonos', '1455', FALSE, TRUE, FALSE),
(6, '145515', 'SEMILLAS TERMINADAS', TRUE, 'Semillas', '1455', FALSE, TRUE, FALSE),
(6, '145520', 'FUNGICIDAS Y HERBICIDAS', TRUE, 'Fungicidas', '1455', FALSE, TRUE, FALSE),
(6, '145525', 'MATERIALES Y REPUESTOS', TRUE, 'Materiales y repuestos', '1455', FALSE, TRUE, FALSE),
(6, '145530', 'LOZA Y CRISTALERIA', TRUE, 'Loza y cristalería', '1455', FALSE, TRUE, FALSE),
(6, '145535', 'HERRAMIENTAS', TRUE, 'Herramientas', '1455', FALSE, TRUE, FALSE),
(6, '145540', 'MEDICINAS', TRUE, 'Medicinas', '1455', FALSE, TRUE, FALSE),
(6, '145545', 'ELEMENTOS HOSPITALARIOS', TRUE, 'Elementos hospitalarios', '1455', FALSE, TRUE, FALSE),
(6, '145550', 'INSTRUMENTAL QUIRURGICO', TRUE, 'Instrumental quirúrgico', '1455', FALSE, TRUE, FALSE),
(6, '145555', 'DOTACION Y SUMINISTRO A TRABAJADORES', TRUE, 'Dotación', '1455', FALSE, TRUE, FALSE),
(6, '145560', 'ELEMENTOS DE ROPERIA Y LENCERIA', TRUE, 'Ropería', '1455', FALSE, TRUE, FALSE),
(6, '145595', 'OTROS', TRUE, 'Otros materiales', '1455', FALSE, TRUE, FALSE),
(6, '145599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación materiales', '1455', FALSE, TRUE, FALSE);

-- Subcuentas 1460
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '146001', 'ENVASES Y EMPAQUES 146001 A 146098', TRUE, 'Envases rango', '1460', FALSE, TRUE, FALSE),
(6, '146098', 'ENVASES Y EMPAQUES FIN RANGO', TRUE, 'Envases fin', '1460', FALSE, TRUE, FALSE),
(6, '146099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación envases', '1460', FALSE, TRUE, FALSE);

-- Subcuentas 1465
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '146501', 'INVENTARIOS EN TRANSITO 146501 A 146598', TRUE, 'Inventarios tránsito rango', '1465', FALSE, TRUE, FALSE),
(6, '146598', 'INVENTARIOS EN TRANSITO FIN RANGO', TRUE, 'Inventarios tránsito fin', '1465', FALSE, TRUE, FALSE),
(6, '146599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación inventarios tránsito', '1465', FALSE, TRUE, FALSE);

-- Subcuentas 1499
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '149905', 'PARA OBSOLESCENCIA', FALSE, 'Provisión obsolescencia', '1499', FALSE, TRUE, FALSE),
(6, '149910', 'PARA DIFERENCIA DE INVENTARIO FISICO', FALSE, 'Provisión diferencia inventario', '1499', FALSE, TRUE, FALSE),
(6, '149915', 'PARA PERDIDAS DE INVENTARIOS', FALSE, 'Provisión pérdidas', '1499', FALSE, TRUE, FALSE),
(6, '149920', 'LIFO', FALSE, 'Provisión LIFO', '1499', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 15 — PROPIEDADES PLANTA Y EQUIPO
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '15', 'PROPIEDADES PLANTA Y EQUIPO', TRUE, 'Bienes tangibles de uso permanente para el desarrollo del objeto social', '1', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '1504', 'TERRENOS', TRUE, 'Terrenos de propiedad del ente', '15', FALSE, TRUE, FALSE),
(4, '1506', 'MATERIALES PROYECTOS PETROLEROS', TRUE, 'Materiales proyectos petroleros', '15', FALSE, TRUE, FALSE),
(4, '1508', 'CONSTRUCCIONES EN CURSO', TRUE, 'Construcciones en curso', '15', FALSE, TRUE, FALSE),
(4, '1512', 'MAQUINARIA Y EQUIPOS EN MONTAJE', TRUE, 'Maquinaria en montaje', '15', FALSE, TRUE, FALSE),
(4, '1516', 'CONSTRUCCIONES Y EDIFICACIONES', TRUE, 'Construcciones y edificaciones', '15', FALSE, TRUE, FALSE),
(4, '1520', 'MAQUINARIA Y EQUIPO', TRUE, 'Maquinaria y equipo', '15', FALSE, TRUE, FALSE),
(4, '1524', 'EQUIPO DE OFICINA', TRUE, 'Equipo de oficina', '15', FALSE, TRUE, FALSE),
(4, '1528', 'EQUIPO DE COMPUTACION Y COMUNICACION', TRUE, 'Equipo de cómputo y comunicaciones', '15', FALSE, TRUE, FALSE),
(4, '1532', 'EQUIPO MEDICO - CIENTIFICO', TRUE, 'Equipo médico-científico', '15', FALSE, TRUE, FALSE),
(4, '1536', 'EQUIPO DE HOTELES Y RESTAURANTES', TRUE, 'Equipo de hoteles y restaurantes', '15', FALSE, TRUE, FALSE),
(4, '1540', 'FLOTA Y EQUIPO DE TRANSPORTE', TRUE, 'Vehículos y equipo de transporte', '15', FALSE, TRUE, FALSE),
(4, '1544', 'FLOTA Y EQUIPO FLUVIAL Y/O MARITIMO', TRUE, 'Equipo fluvial y marítimo', '15', FALSE, TRUE, FALSE),
(4, '1548', 'FLOTA Y EQUIPO AEREO', TRUE, 'Equipo aéreo', '15', FALSE, TRUE, FALSE),
(4, '1552', 'FLOTA Y EQUIPO FERREO', TRUE, 'Equipo férreo', '15', FALSE, TRUE, FALSE),
(4, '1556', 'ACUEDUCTOS PLANTAS Y REDES', TRUE, 'Acueductos, plantas y redes', '15', FALSE, TRUE, FALSE),
(4, '1560', 'ARMAMENTO DE VIGILANCIA', TRUE, 'Armamento de vigilancia', '15', FALSE, TRUE, FALSE),
(4, '1562', 'ENVASES Y EMPAQUES', TRUE, 'Envases y empaques retornables', '15', FALSE, TRUE, FALSE),
(4, '1564', 'PLANTACIONES AGRICOLAS Y FORESTALES', TRUE, 'Plantaciones agrícolas y forestales', '15', FALSE, TRUE, FALSE),
(4, '1568', 'VIAS DE COMUNICACION', TRUE, 'Vías de comunicación', '15', FALSE, TRUE, FALSE),
(4, '1572', 'MINAS Y CANTERAS', TRUE, 'Minas y canteras', '15', FALSE, TRUE, FALSE),
(4, '1576', 'POZOS ARTESIANOS', TRUE, 'Pozos artesianos', '15', FALSE, TRUE, FALSE),
(4, '1580', 'YACIMIENTOS', TRUE, 'Yacimientos', '15', FALSE, TRUE, FALSE),
(4, '1584', 'SEMOVIENTES', TRUE, 'Semovientes de trabajo', '15', FALSE, TRUE, FALSE),
(4, '1588', 'PROPIEDADES PLANTA Y EQUIPO EN TRANSITO', TRUE, 'PPE en tránsito', '15', FALSE, TRUE, FALSE),
(4, '1592', 'DEPRECIACION ACUMULADA', FALSE, 'Depreciación acumulada (CRÉDITO)', '15', FALSE, TRUE, FALSE),
(4, '1596', 'DEPRECIACION DIFERIDA', FALSE, 'Depreciación diferida', '15', FALSE, TRUE, FALSE),
(4, '1597', 'AMORTIZACION ACUMULADA', FALSE, 'Amortización acumulada', '15', FALSE, TRUE, FALSE),
(4, '1598', 'AGOTAMIENTO ACUMULADO', FALSE, 'Agotamiento acumulado', '15', FALSE, TRUE, FALSE),
(4, '1599', 'PROVISIONES', FALSE, 'Provisión PPE', '15', FALSE, TRUE, FALSE);

-- Subcuentas 1504
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '150405', 'URBANOS', TRUE, 'Terrenos urbanos', '1504', FALSE, TRUE, FALSE),
(6, '150410', 'RURALES', TRUE, 'Terrenos rurales', '1504', FALSE, TRUE, FALSE),
(6, '150499', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación terrenos', '1504', FALSE, TRUE, FALSE);

-- Subcuentas 1506
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '150605', 'TUBERIAS Y EQUIPO', TRUE, 'Tuberías y equipo', '1506', FALSE, TRUE, FALSE),
(6, '150610', 'COSTOS DE IMPORTACION MATERIALES', TRUE, 'Costos importación materiales', '1506', FALSE, TRUE, FALSE),
(6, '150615', 'PROYECTOS DE CONSTRUCCION', TRUE, 'Proyectos construcción', '1506', FALSE, TRUE, FALSE),
(6, '150699', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación materiales petroleros', '1506', FALSE, TRUE, FALSE);

-- Subcuentas 1508
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '150805', 'CONSTRUCCIONES Y EDIFICACIONES', TRUE, 'Construcciones', '1508', FALSE, TRUE, FALSE),
(6, '150810', 'ACUEDUCTOS PLANTAS Y REDES', TRUE, 'Acueductos', '1508', FALSE, TRUE, FALSE),
(6, '150815', 'VIAS DE COMUNICACION', TRUE, 'Vías', '1508', FALSE, TRUE, FALSE),
(6, '150820', 'POZOS ARTESIANOS', TRUE, 'Pozos', '1508', FALSE, TRUE, FALSE),
(6, '150825', 'PROYECTOS DE EXPLORACION', TRUE, 'Proyectos exploración', '1508', FALSE, TRUE, FALSE),
(6, '150830', 'PROYECTOS DE DESARROLLO', TRUE, 'Proyectos desarrollo', '1508', FALSE, TRUE, FALSE),
(6, '150899', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación construcciones curso', '1508', FALSE, TRUE, FALSE);

-- Subcuentas 1512
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '151205', 'MAQUINARIA Y EQUIPO', TRUE, 'Maquinaria en montaje', '1512', FALSE, TRUE, FALSE),
(6, '151210', 'EQUIPO DE OFICINA', TRUE, 'Equipo oficina en montaje', '1512', FALSE, TRUE, FALSE),
(6, '151215', 'EQUIPO DE COMPUTACION Y COMUNICACION', TRUE, 'Equipo computación en montaje', '1512', FALSE, TRUE, FALSE),
(6, '151220', 'EQUIPO MEDICO-CIENTIFICO', TRUE, 'Equipo médico en montaje', '1512', FALSE, TRUE, FALSE),
(6, '151225', 'EQUIPO DE HOTELES Y RESTAURANTES', TRUE, 'Equipo hoteles en montaje', '1512', FALSE, TRUE, FALSE),
(6, '151230', 'FLOTA Y EQUIPO DE TRANSPORTE', TRUE, 'Flota en montaje', '1512', FALSE, TRUE, FALSE),
(6, '151235', 'FLOTA Y EQUIPO FLUVIAL Y/O MARITIMO', TRUE, 'Flota fluvial en montaje', '1512', FALSE, TRUE, FALSE),
(6, '151240', 'FLOTA Y EQUIPO AEREO', TRUE, 'Flota aérea en montaje', '1512', FALSE, TRUE, FALSE),
(6, '151245', 'FLOTA Y EQUIPO FERREO', TRUE, 'Flota férrea en montaje', '1512', FALSE, TRUE, FALSE),
(6, '151250', 'PLANTAS Y REDES', TRUE, 'Plantas y redes en montaje', '1512', FALSE, TRUE, FALSE),
(6, '151299', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación maquinaria montaje', '1512', FALSE, TRUE, FALSE);

-- Subcuentas 1516
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '151605', 'EDIFICIOS', TRUE, 'Edificios', '1516', FALSE, TRUE, FALSE),
(6, '151610', 'OFICINAS', TRUE, 'Oficinas', '1516', FALSE, TRUE, FALSE),
(6, '151615', 'ALMACENES', TRUE, 'Almacenes', '1516', FALSE, TRUE, FALSE),
(6, '151620', 'FABRICAS Y PLANTAS INDUSTRIALES', TRUE, 'Fábricas', '1516', FALSE, TRUE, FALSE),
(6, '151625', 'SALAS DE EXHIBICION Y VENTAS', TRUE, 'Salas exhibición', '1516', FALSE, TRUE, FALSE),
(6, '151630', 'CAFETERIA Y CASINOS', TRUE, 'Cafetería y casinos', '1516', FALSE, TRUE, FALSE),
(6, '151635', 'SILOS', TRUE, 'Silos', '1516', FALSE, TRUE, FALSE),
(6, '151640', 'INVERNADEROS', TRUE, 'Invernaderos', '1516', FALSE, TRUE, FALSE),
(6, '151645', 'CASETAS Y CAMPAMENTOS', TRUE, 'Casetas', '1516', FALSE, TRUE, FALSE),
(6, '151650', 'INSTALACIONES AGROPECUARIAS', TRUE, 'Instalaciones agropecuarias', '1516', FALSE, TRUE, FALSE),
(6, '151655', 'VIVIENDAS PARA EMPLEADOS Y OBREROS', TRUE, 'Viviendas empleados', '1516', FALSE, TRUE, FALSE),
(6, '151660', 'TERMINAL DE BUSES Y TAXIS', TRUE, 'Terminal buses', '1516', FALSE, TRUE, FALSE),
(6, '151663', 'TERMINAL MARITIMO', TRUE, 'Terminal marítimo', '1516', FALSE, TRUE, FALSE),
(6, '151665', 'TERMINAL FERREO', TRUE, 'Terminal férreo', '1516', FALSE, TRUE, FALSE),
(6, '151670', 'PARQUEADEROS, GARAJES Y DEPOSITOS', TRUE, 'Parqueaderos', '1516', FALSE, TRUE, FALSE),
(6, '151675', 'HANGARES', TRUE, 'Hangares', '1516', FALSE, TRUE, FALSE),
(6, '151680', 'BODEGAS', TRUE, 'Bodegas', '1516', FALSE, TRUE, FALSE),
(6, '151695', 'OTROS', TRUE, 'Otras construcciones', '1516', FALSE, TRUE, FALSE),
(6, '151699', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación construcciones', '1516', FALSE, TRUE, FALSE);

-- Subcuentas 1520
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '152001', 'MAQUINARIA Y EQUIPO 152001 A 152098', TRUE, 'Maquinaria rango', '1520', FALSE, TRUE, FALSE),
(6, '152098', 'MAQUINARIA Y EQUIPO FIN RANGO', TRUE, 'Maquinaria fin', '1520', FALSE, TRUE, FALSE),
(6, '152099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación maquinaria', '1520', FALSE, TRUE, FALSE);

-- Subcuentas 1524
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '152405', 'MUEBLES Y ENSERES', TRUE, 'Muebles y enseres', '1524', FALSE, TRUE, FALSE),
(6, '152410', 'EQUIPOS', TRUE, 'Equipos oficina', '1524', FALSE, TRUE, FALSE),
(6, '152495', 'OTROS', TRUE, 'Otros equipo oficina', '1524', FALSE, TRUE, FALSE),
(6, '152499', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación equipo oficina', '1524', FALSE, TRUE, FALSE);

-- Subcuentas 1528
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '152805', 'EQUIPOS DE PROCESAMIENTO DE DATOS', TRUE, 'Equipos cómputo', '1528', FALSE, TRUE, FALSE),
(6, '152810', 'EQUIPOS DE TELECOMUNICACIONES', TRUE, 'Equipos telecom', '1528', FALSE, TRUE, FALSE),
(6, '152815', 'EQUIPOS DE RADIO', TRUE, 'Equipos radio', '1528', FALSE, TRUE, FALSE),
(6, '152820', 'SATELITES Y ANTENAS', TRUE, 'Satélites y antenas', '1528', FALSE, TRUE, FALSE),
(6, '152825', 'LINEAS TELEFONICAS', TRUE, 'Líneas telefónicas', '1528', FALSE, TRUE, FALSE),
(6, '152895', 'OTROS', TRUE, 'Otros equipos cómputo', '1528', FALSE, TRUE, FALSE),
(6, '152899', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación cómputo', '1528', FALSE, TRUE, FALSE);

-- Subcuentas 1532
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '153205', 'MEDICO', TRUE, 'Equipo médico', '1532', FALSE, TRUE, FALSE),
(6, '153210', 'ODONTOLOGICO', TRUE, 'Equipo odontológico', '1532', FALSE, TRUE, FALSE),
(6, '153215', 'LABORATORIO', TRUE, 'Equipo laboratorio', '1532', FALSE, TRUE, FALSE),
(6, '153220', 'INSTRUMENTAL', TRUE, 'Instrumental médico', '1532', FALSE, TRUE, FALSE),
(6, '153295', 'OTROS', TRUE, 'Otros equipo médico', '1532', FALSE, TRUE, FALSE),
(6, '153299', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación médico', '1532', FALSE, TRUE, FALSE);

-- Subcuentas 1536
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '153605', 'DE HABITACIONES', TRUE, 'Equipo habitaciones', '1536', FALSE, TRUE, FALSE),
(6, '153610', 'DE COMESTIBLES Y BEBIDAS', TRUE, 'Equipo comestibles', '1536', FALSE, TRUE, FALSE),
(6, '153695', 'OTROS', TRUE, 'Otros equipo hoteles', '1536', FALSE, TRUE, FALSE),
(6, '153699', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación hoteles', '1536', FALSE, TRUE, FALSE);

-- Subcuentas 1540
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '154005', 'AUTOS, CAMIONETAS Y CAMPEROS', TRUE, 'Autos y camionetas', '1540', FALSE, TRUE, FALSE),
(6, '154008', 'CAMIONES, VOLQUETAS Y FURGONES', TRUE, 'Camiones', '1540', FALSE, TRUE, FALSE),
(6, '154010', 'TRACTOMULAS Y REMOLQUES', TRUE, 'Tractomulas', '1540', FALSE, TRUE, FALSE),
(6, '154015', 'BUSES Y BUSETAS', TRUE, 'Buses', '1540', FALSE, TRUE, FALSE),
(6, '154017', 'RECOLECTORES Y CONTENEDORES', TRUE, 'Recolectores', '1540', FALSE, TRUE, FALSE),
(6, '154020', 'MONTACARGAS', TRUE, 'Montacargas', '1540', FALSE, TRUE, FALSE),
(6, '154025', 'PALAS Y GRUAS', TRUE, 'Palas y grúas', '1540', FALSE, TRUE, FALSE),
(6, '154030', 'MOTOCICLETAS', TRUE, 'Motocicletas', '1540', FALSE, TRUE, FALSE),
(6, '154035', 'BICICLETAS', TRUE, 'Bicicletas', '1540', FALSE, TRUE, FALSE),
(6, '154040', 'ESTIBAS Y CARRETAS', TRUE, 'Estibas', '1540', FALSE, TRUE, FALSE),
(6, '154045', 'BANDAS TRANSPORTADORAS', TRUE, 'Bandas', '1540', FALSE, TRUE, FALSE),
(6, '154095', 'OTROS', TRUE, 'Otros flota', '1540', FALSE, TRUE, FALSE),
(6, '154099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación flota', '1540', FALSE, TRUE, FALSE);

-- Subcuentas 1544
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '154405', 'BUQUES', TRUE, 'Buques', '1544', FALSE, TRUE, FALSE),
(6, '154410', 'LANCHAS', TRUE, 'Lanchas', '1544', FALSE, TRUE, FALSE),
(6, '154415', 'REMOLCADORAS', TRUE, 'Remolcadoras', '1544', FALSE, TRUE, FALSE),
(6, '154420', 'BOTES', TRUE, 'Botes', '1544', FALSE, TRUE, FALSE),
(6, '154425', 'BOYAS', TRUE, 'Boyas', '1544', FALSE, TRUE, FALSE),
(6, '154430', 'AMARRES', TRUE, 'Amarres', '1544', FALSE, TRUE, FALSE),
(6, '154435', 'CONTENEDORES Y CHASSISES', TRUE, 'Contenedores', '1544', FALSE, TRUE, FALSE),
(6, '154440', 'GABARRAS', TRUE, 'Gabarras', '1544', FALSE, TRUE, FALSE),
(6, '154495', 'OTROS', TRUE, 'Otros equipo fluvial', '1544', FALSE, TRUE, FALSE),
(6, '154499', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación fluvial', '1544', FALSE, TRUE, FALSE);

-- Subcuentas 1548
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '154805', 'AVIONES', TRUE, 'Aviones', '1548', FALSE, TRUE, FALSE),
(6, '154810', 'AVIONETAS', TRUE, 'Avionetas', '1548', FALSE, TRUE, FALSE),
(6, '154815', 'HELICOPTEROS', TRUE, 'Helicópteros', '1548', FALSE, TRUE, FALSE),
(6, '154820', 'TURBINAS Y MOTORES', TRUE, 'Turbinas', '1548', FALSE, TRUE, FALSE),
(6, '154825', 'MANUALES DE ENTRENAMIENTO PERSONAL TECNICO', TRUE, 'Manuales entrenamiento', '1548', FALSE, TRUE, FALSE),
(6, '154830', 'EQUIPOS DE VUELO', TRUE, 'Equipos de vuelo', '1548', FALSE, TRUE, FALSE),
(6, '154895', 'OTROS', TRUE, 'Otros equipo aéreo', '1548', FALSE, TRUE, FALSE),
(6, '154899', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación aéreo', '1548', FALSE, TRUE, FALSE);

-- Subcuentas 1552
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '155205', 'LOCOMOTORAS', TRUE, 'Locomotoras', '1552', FALSE, TRUE, FALSE),
(6, '155210', 'VAGONES', TRUE, 'Vagones', '1552', FALSE, TRUE, FALSE),
(6, '155215', 'REDES FERREAS', TRUE, 'Redes férreas', '1552', FALSE, TRUE, FALSE),
(6, '155295', 'OTROS', TRUE, 'Otros equipo férreo', '1552', FALSE, TRUE, FALSE),
(6, '155299', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación férreo', '1552', FALSE, TRUE, FALSE);

-- Subcuentas 1556
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '155605', 'INSTALACIONES PARA AGUA Y ENERGIA', TRUE, 'Instalaciones agua y energía', '1556', FALSE, TRUE, FALSE),
(6, '155610', 'ACUEDUCTO ACEQUIAS Y CANALIZACIONES', TRUE, 'Acueductos', '1556', FALSE, TRUE, FALSE),
(6, '155615', 'PLANTAS DE GENERACION HIDRAULICA', TRUE, 'Plantas hidráulicas', '1556', FALSE, TRUE, FALSE),
(6, '155620', 'PLANTAS DE GENERACION TERMICA', TRUE, 'Plantas térmicas', '1556', FALSE, TRUE, FALSE),
(6, '155625', 'PLANTAS DE GENERACION A GAS', TRUE, 'Plantas a gas', '1556', FALSE, TRUE, FALSE),
(6, '155628', 'PLANTAS DE GENERACION DIESEL, GASOLINA Y PETROLEO', TRUE, 'Plantas diésel', '1556', FALSE, TRUE, FALSE),
(6, '155630', 'PLANTAS DE DISTRIBUCION', TRUE, 'Plantas distribución', '1556', FALSE, TRUE, FALSE),
(6, '155635', 'PLANTAS DE TRANSMISION Y SUBESTACIONES', TRUE, 'Plantas transmisión', '1556', FALSE, TRUE, FALSE),
(6, '155640', 'OLEODUCTOS', TRUE, 'Oleoductos', '1556', FALSE, TRUE, FALSE),
(6, '155645', 'GASODUCTOS', TRUE, 'Gasoductos', '1556', FALSE, TRUE, FALSE),
(6, '155647', 'POLIDUCTOS', TRUE, 'Poliductos', '1556', FALSE, TRUE, FALSE),
(6, '155650', 'REDES DE DISTRIBUCION', TRUE, 'Redes distribución', '1556', FALSE, TRUE, FALSE),
(6, '155655', 'PLANTAS DE TRATAMIENTO', TRUE, 'Plantas tratamiento', '1556', FALSE, TRUE, FALSE),
(6, '155660', 'REDES DE RECOLECCION DE AGUAS NEGRAS', TRUE, 'Redes aguas negras', '1556', FALSE, TRUE, FALSE),
(6, '155665', 'INSTALACIONES Y EQUIPO DE BOMBEO', TRUE, 'Equipo bombeo', '1556', FALSE, TRUE, FALSE),
(6, '155670', 'REDES DE DISTRIBUCION DE VAPOR', TRUE, 'Redes vapor', '1556', FALSE, TRUE, FALSE),
(6, '155675', 'REDES DE AIRE', TRUE, 'Redes aire', '1556', FALSE, TRUE, FALSE),
(6, '155680', 'REDES ALIMENTACION DE GAS', TRUE, 'Redes gas', '1556', FALSE, TRUE, FALSE),
(6, '155682', 'REDES EXTERNAS DE TELEFONIA', TRUE, 'Redes telefonía', '1556', FALSE, TRUE, FALSE),
(6, '155685', 'PLANTAS DESHIDRATADORAS', TRUE, 'Plantas deshidratadoras', '1556', FALSE, TRUE, FALSE),
(6, '155695', 'OTROS', TRUE, 'Otros acueductos', '1556', FALSE, TRUE, FALSE),
(6, '155699', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación acueductos', '1556', FALSE, TRUE, FALSE);

-- Subcuentas 1560
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '156001', 'ARMAMENTO DE VIGILANCIA 156001 A 156098', TRUE, 'Armamento rango', '1560', FALSE, TRUE, FALSE),
(6, '156098', 'ARMAMENTO DE VIGILANCIA FIN RANGO', TRUE, 'Armamento fin', '1560', FALSE, TRUE, FALSE),
(6, '156099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación armamento', '1560', FALSE, TRUE, FALSE);

-- Subcuentas 1562
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '156201', 'ENVASES Y EMPAQUES 156201 A 156298', TRUE, 'Envases rango', '1562', FALSE, TRUE, FALSE),
(6, '156298', 'ENVASES Y EMPAQUES FIN RANGO', TRUE, 'Envases fin', '1562', FALSE, TRUE, FALSE),
(6, '156299', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación envases', '1562', FALSE, TRUE, FALSE);

-- Subcuentas 1564
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '156405', 'CULTIVOS EN DESARROLLO', TRUE, 'Cultivos en desarrollo', '1564', FALSE, TRUE, FALSE),
(6, '156410', 'CULTIVOS AMORTIZABLES', TRUE, 'Cultivos amortizables', '1564', FALSE, TRUE, FALSE),
(6, '156499', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación plantaciones', '1564', FALSE, TRUE, FALSE);

-- Subcuentas 1568
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '156805', 'PAVIMENTACION Y PATIOS', TRUE, 'Pavimentación', '1568', FALSE, TRUE, FALSE),
(6, '156810', 'VIAS', TRUE, 'Vías', '1568', FALSE, TRUE, FALSE),
(6, '156815', 'PUENTES', TRUE, 'Puentes', '1568', FALSE, TRUE, FALSE),
(6, '156820', 'CALLES', TRUE, 'Calles', '1568', FALSE, TRUE, FALSE),
(6, '156825', 'AERODROMOS', TRUE, 'Aeródromos', '1568', FALSE, TRUE, FALSE),
(6, '156895', 'OTROS', TRUE, 'Otras vías', '1568', FALSE, TRUE, FALSE),
(6, '156899', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación vías', '1568', FALSE, TRUE, FALSE);

-- Subcuentas 1572
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '157205', 'MINAS', TRUE, 'Minas', '1572', FALSE, TRUE, FALSE),
(6, '157210', 'CANTERAS', TRUE, 'Canteras', '1572', FALSE, TRUE, FALSE),
(6, '157299', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación minas', '1572', FALSE, TRUE, FALSE);

-- Subcuentas 1576
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '157601', 'POZOS ARTESIANOS 157601 A 157698', TRUE, 'Pozos rango', '1576', FALSE, TRUE, FALSE),
(6, '157698', 'POZOS ARTESIANOS FIN RANGO', TRUE, 'Pozos fin', '1576', FALSE, TRUE, FALSE),
(6, '157699', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación pozos', '1576', FALSE, TRUE, FALSE);

-- Subcuentas 1580
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '158001', 'YACIMIENTOS 158001 A 158098', TRUE, 'Yacimientos rango', '1580', FALSE, TRUE, FALSE),
(6, '158098', 'YACIMIENTOS FIN RANGO', TRUE, 'Yacimientos fin', '1580', FALSE, TRUE, FALSE),
(6, '158099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación yacimientos', '1580', FALSE, TRUE, FALSE);

-- Subcuentas 1584
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '158405', 'ESPECIES MENORES', TRUE, 'Especies menores trabajo', '1584', FALSE, TRUE, FALSE),
(6, '158410', 'ESPECIES MAYORES', TRUE, 'Especies mayores trabajo', '1584', FALSE, TRUE, FALSE),
(6, '158499', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación semovientes', '1584', FALSE, TRUE, FALSE);

-- Subcuentas 1588
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '158805', 'MAQUINARIA Y EQUIPO', TRUE, 'Maquinaria en tránsito', '1588', FALSE, TRUE, FALSE),
(6, '158810', 'EQUIPO DE OFICINA', TRUE, 'Equipo oficina en tránsito', '1588', FALSE, TRUE, FALSE),
(6, '158815', 'EQUIPO DE COMPUTACION Y COMUNICACION', TRUE, 'Equipo cómputo en tránsito', '1588', FALSE, TRUE, FALSE),
(6, '158820', 'EQUIPO MEDICO CIENTIFICO', TRUE, 'Equipo médico en tránsito', '1588', FALSE, TRUE, FALSE),
(6, '158825', 'EQUIPO DE HOTELES Y RESTAURANTES', TRUE, 'Equipo hoteles en tránsito', '1588', FALSE, TRUE, FALSE),
(6, '158830', 'FLOTA Y EQUIPO DE TRANSPORTE', TRUE, 'Flota en tránsito', '1588', FALSE, TRUE, FALSE),
(6, '158835', 'FLOTA Y EQUIPO FLUVIAL Y/O MARITIMO', TRUE, 'Flota fluvial en tránsito', '1588', FALSE, TRUE, FALSE),
(6, '158840', 'FLOTA Y EQUIPO AEREO', TRUE, 'Flota aérea en tránsito', '1588', FALSE, TRUE, FALSE),
(6, '158845', 'FLOTA Y EQUIPO FERREO', TRUE, 'Flota férrea en tránsito', '1588', FALSE, TRUE, FALSE),
(6, '158850', 'PLANTAS Y REDES', TRUE, 'Plantas en tránsito', '1588', FALSE, TRUE, FALSE),
(6, '158855', 'ARMAMENTO DE VIGILANCIA', TRUE, 'Armamento en tránsito', '1588', FALSE, TRUE, FALSE),
(6, '158860', 'SEMOVIENTES', TRUE, 'Semovientes en tránsito', '1588', FALSE, TRUE, FALSE),
(6, '158865', 'ENVASES Y EMPAQUES', TRUE, 'Envases en tránsito', '1588', FALSE, TRUE, FALSE),
(6, '158899', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación PPE tránsito', '1588', FALSE, TRUE, FALSE);

-- Subcuentas 1592 (Depreciación Acumulada - CRÉDITO)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '159205', 'CONSTRUCCIONES Y EDIFICACIONES', FALSE, 'Depreciación construcciones', '1592', FALSE, TRUE, FALSE),
(6, '159210', 'MAQUINARIA Y EQUIPO', FALSE, 'Depreciación maquinaria', '1592', FALSE, TRUE, FALSE),
(6, '159215', 'EQUIPO DE OFICINA', FALSE, 'Depreciación equipo oficina', '1592', FALSE, TRUE, FALSE),
(6, '159220', 'EQUIPO DE COMPUTACION Y COMUNICACION', FALSE, 'Depreciación cómputo', '1592', FALSE, TRUE, FALSE),
(6, '159225', 'EQUIPO MEDICO CIENTIFICO', FALSE, 'Depreciación médico', '1592', FALSE, TRUE, FALSE),
(6, '159230', 'EQUIPO DE HOTELES Y RESTAURANTES', FALSE, 'Depreciación hoteles', '1592', FALSE, TRUE, FALSE),
(6, '159235', 'FLOTA Y EQUIPO DE TRANSPORTE', FALSE, 'Depreciación flota', '1592', FALSE, TRUE, FALSE),
(6, '159240', 'FLOTA Y EQUIPO FLUVIAL Y/O MARITIMO', FALSE, 'Depreciación fluvial', '1592', FALSE, TRUE, FALSE),
(6, '159245', 'FLOTA Y EQUIPO AEREO', FALSE, 'Depreciación aéreo', '1592', FALSE, TRUE, FALSE),
(6, '159250', 'FLOTA Y EQUIPO FERREO', FALSE, 'Depreciación férreo', '1592', FALSE, TRUE, FALSE),
(6, '159255', 'ACUEDUCTOS PLANTAS Y REDES', FALSE, 'Depreciación acueductos', '1592', FALSE, TRUE, FALSE),
(6, '159260', 'ARMAMENTO DE VIGILANCIA', FALSE, 'Depreciación armamento', '1592', FALSE, TRUE, FALSE),
(6, '159265', 'ENVASES Y EMPAQUES', FALSE, 'Depreciación envases', '1592', FALSE, TRUE, FALSE),
(6, '159299', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación depreciación', '1592', FALSE, TRUE, FALSE);

-- Subcuentas 1596 (Depreciación Diferida - CRÉDITO)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '159605', 'EXCESO FISCAL SOBRE LA CONTABLE', FALSE, 'Exceso fiscal', '1596', FALSE, TRUE, FALSE),
(6, '159610', 'DEFECTO FISCAL SOBRE LA CONTABLE (CR)', FALSE, 'Defecto fiscal', '1596', FALSE, TRUE, FALSE),
(6, '159699', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación depreciación diferida', '1596', FALSE, TRUE, FALSE);

-- Subcuentas 1597
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '159705', 'PLANTACIONES AGRICOLAS Y FORESTALES', FALSE, 'Amortización plantaciones', '1597', FALSE, TRUE, FALSE),
(6, '159710', 'VIAS DE COMUNICACION', FALSE, 'Amortización vías', '1597', FALSE, TRUE, FALSE),
(6, '159715', 'SEMOVIENTES', FALSE, 'Amortización semovientes', '1597', FALSE, TRUE, FALSE),
(6, '159799', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación amortización', '1597', FALSE, TRUE, FALSE);

-- Subcuentas 1598
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '159805', 'MINAS Y CANTERAS', FALSE, 'Agotamiento minas', '1598', FALSE, TRUE, FALSE),
(6, '159815', 'POZOS ARTESIANOS', FALSE, 'Agotamiento pozos', '1598', FALSE, TRUE, FALSE),
(6, '159820', 'YACIMIENTOS', FALSE, 'Agotamiento yacimientos', '1598', FALSE, TRUE, FALSE),
(6, '159899', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación agotamiento', '1598', FALSE, TRUE, FALSE);

-- Subcuentas 1599 (Provisiones PPE - CRÉDITO)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '159904', 'TERRENOS', FALSE, 'Provisión terrenos', '1599', FALSE, TRUE, FALSE),
(6, '159906', 'MATERIALES PROYECTOS PETROLEROS', FALSE, 'Provisión materiales petroleros', '1599', FALSE, TRUE, FALSE),
(6, '159908', 'CONSTRUCCIONES EN CURSO', FALSE, 'Provisión construcciones curso', '1599', FALSE, TRUE, FALSE),
(6, '159912', 'MAQUINARIA EN MONTAJE', FALSE, 'Provisión maquinaria montaje', '1599', FALSE, TRUE, FALSE),
(6, '159916', 'CONSTRUCCIONES Y EDIFICACIONES', FALSE, 'Provisión construcciones', '1599', FALSE, TRUE, FALSE),
(6, '159920', 'MAQUINARIA Y EQUIPO', FALSE, 'Provisión maquinaria', '1599', FALSE, TRUE, FALSE),
(6, '159924', 'EQUIPO DE OFICINA', FALSE, 'Provisión equipo oficina', '1599', FALSE, TRUE, FALSE),
(6, '159928', 'EQUIPO DE COMPUTACION Y COMUNICACION', FALSE, 'Provisión cómputo', '1599', FALSE, TRUE, FALSE),
(6, '159932', 'EQUIPO MEDICO CIENTIFICO', FALSE, 'Provisión médico', '1599', FALSE, TRUE, FALSE),
(6, '159936', 'EQUIPO DE HOTELES Y RESTAURANTES', FALSE, 'Provisión hoteles', '1599', FALSE, TRUE, FALSE),
(6, '159940', 'FLOTA Y EQUIPO DE TRANSPORTE', FALSE, 'Provisión flota', '1599', FALSE, TRUE, FALSE),
(6, '159944', 'FLOTA Y EQUIPO FLUVIAL Y/O MARITIMO', FALSE, 'Provisión fluvial', '1599', FALSE, TRUE, FALSE),
(6, '159948', 'FLOTA Y EQUIPO AEREO', FALSE, 'Provisión aéreo', '1599', FALSE, TRUE, FALSE),
(6, '159952', 'FLOTA Y EQUIPO FERREO', FALSE, 'Provisión férreo', '1599', FALSE, TRUE, FALSE),
(6, '159956', 'ACUEDUCTOS, PLANTAS Y REDES', FALSE, 'Provisión acueductos', '1599', FALSE, TRUE, FALSE),
(6, '159960', 'ARMAMENTO DE VIGILANCIA', FALSE, 'Provisión armamento', '1599', FALSE, TRUE, FALSE),
(6, '159962', 'ENVASES Y EMPAQUES', FALSE, 'Provisión envases', '1599', FALSE, TRUE, FALSE),
(6, '159964', 'PLANTACIONES AGRICOLAS Y FORESTALES', FALSE, 'Provisión plantaciones', '1599', FALSE, TRUE, FALSE),
(6, '159968', 'VIAS DE COMUNICACION', FALSE, 'Provisión vías', '1599', FALSE, TRUE, FALSE),
(6, '159972', 'MINAS Y CANTERAS', FALSE, 'Provisión minas', '1599', FALSE, TRUE, FALSE),
(6, '159980', 'POZOS ARTESIANOS', FALSE, 'Provisión pozos', '1599', FALSE, TRUE, FALSE),
(6, '159984', 'YACIMIENTOS', FALSE, 'Provisión yacimientos', '1599', FALSE, TRUE, FALSE),
(6, '159988', 'SEMOVIENTES', FALSE, 'Provisión semovientes', '1599', FALSE, TRUE, FALSE),
(6, '159992', 'PROPIEDADES PLANTA Y EQUIPO EN TRANSITO', FALSE, 'Provisión PPE tránsito', '1599', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 16 — INTANGIBLES
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '16', 'INTANGIBLES', TRUE, 'Bienes inmateriales representados en derechos, privilegios o ventajas', '1', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '1605', 'CREDITO MERCANTIL', TRUE, 'Crédito mercantil', '16', FALSE, TRUE, FALSE),
(4, '1610', 'MARCAS', TRUE, 'Marcas', '16', FALSE, TRUE, FALSE),
(4, '1615', 'PATENTES', TRUE, 'Patentes', '16', FALSE, TRUE, FALSE),
(4, '1620', 'CONCESIONES Y FRANQUICIAS', TRUE, 'Concesiones y franquicias', '16', FALSE, TRUE, FALSE),
(4, '1625', 'DERECHOS', TRUE, 'Derechos', '16', FALSE, TRUE, FALSE),
(4, '1630', 'KNOW HOW', TRUE, 'Know How', '16', FALSE, TRUE, FALSE),
(4, '1635', 'LICENCIAS', TRUE, 'Licencias', '16', FALSE, TRUE, FALSE),
(4, '1698', 'DEPRECIACION Y/O AMORTIZACION ACUMULADA', FALSE, 'Amortización acumulada intangibles', '16', FALSE, TRUE, FALSE),
(4, '1699', 'PROVISIONES', FALSE, 'Provisión intangibles', '16', FALSE, TRUE, FALSE);

-- Subcuentas 1605
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '160505', 'FORMADO O ESTIMADO', TRUE, 'Crédito mercantil formado', '1605', FALSE, TRUE, FALSE),
(6, '160510', 'ADQUIRIDO O COMPRADO', TRUE, 'Crédito mercantil adquirido', '1605', FALSE, TRUE, FALSE),
(6, '160599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación crédito mercantil', '1605', FALSE, TRUE, FALSE);

-- Subcuentas 1610
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '161005', 'ADQUIRIDAS', TRUE, 'Marcas adquiridas', '1610', FALSE, TRUE, FALSE),
(6, '161010', 'FORMADAS', TRUE, 'Marcas formadas', '1610', FALSE, TRUE, FALSE),
(6, '161099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación marcas', '1610', FALSE, TRUE, FALSE);

-- Subcuentas 1615
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '161505', 'ADQUIRIDAS', TRUE, 'Patentes adquiridas', '1615', FALSE, TRUE, FALSE),
(6, '161510', 'FORMADAS', TRUE, 'Patentes formadas', '1615', FALSE, TRUE, FALSE),
(6, '161599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación patentes', '1615', FALSE, TRUE, FALSE);

-- Subcuentas 1620
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '162005', 'CONCESIONES', TRUE, 'Concesiones', '1620', FALSE, TRUE, FALSE),
(6, '162010', 'FRANQUICIAS', TRUE, 'Franquicias', '1620', FALSE, TRUE, FALSE),
(6, '162099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación concesiones', '1620', FALSE, TRUE, FALSE);

-- Subcuentas 1625
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '162505', 'DERECHOS DE AUTOR', TRUE, 'Derechos de autor', '1625', FALSE, TRUE, FALSE),
(6, '162510', 'PUESTO DE BOLSA', TRUE, 'Puesto de bolsa', '1625', FALSE, TRUE, FALSE),
(6, '162515', 'EN FIDEICOMISOS INMOBILIARIOS', TRUE, 'Fideicomisos inmobiliarios', '1625', FALSE, TRUE, FALSE),
(6, '162520', 'EN FIDEICOMISOS DE GARANTIA', TRUE, 'Fideicomisos garantía', '1625', FALSE, TRUE, FALSE),
(6, '162525', 'EN FIDEICOMISOS DE ADMINISTRACION', TRUE, 'Fideicomisos administración', '1625', FALSE, TRUE, FALSE),
(6, '162530', 'DE EXHIBICION - PELICULAS', TRUE, 'Exhibición películas', '1625', FALSE, TRUE, FALSE),
(6, '162535', 'EN BIENES RECIBIDOS EN ARRENDAMIENTO FINANCIERO (LEASING)', TRUE, 'Leasing', '1625', FALSE, TRUE, FALSE),
(6, '162595', 'OTROS', TRUE, 'Otros derechos', '1625', FALSE, TRUE, FALSE),
(6, '162599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación derechos', '1625', FALSE, TRUE, FALSE);

-- Subcuentas 1630
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '163001', 'KNOW HOW 163001 A 163098', TRUE, 'Know how rango', '1630', FALSE, TRUE, FALSE),
(6, '163098', 'KNOW HOW FIN RANGO', TRUE, 'Know how fin', '1630', FALSE, TRUE, FALSE),
(6, '163099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación know how', '1630', FALSE, TRUE, FALSE);

-- Subcuentas 1635
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '163501', 'LICENCIAS 163501 A 163598', TRUE, 'Licencias rango', '1635', FALSE, TRUE, FALSE),
(6, '163598', 'LICENCIAS FIN RANGO', TRUE, 'Licencias fin', '1635', FALSE, TRUE, FALSE),
(6, '163599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación licencias', '1635', FALSE, TRUE, FALSE);

-- Subcuentas 1698 (Amortización Acumulada Intangibles - CRÉDITO)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '169805', 'CREDITO MERCANTIL', FALSE, 'Amortización crédito mercantil', '1698', FALSE, TRUE, FALSE),
(6, '169810', 'MARCAS', FALSE, 'Amortización marcas', '1698', FALSE, TRUE, FALSE),
(6, '169815', 'PATENTES', FALSE, 'Amortización patentes', '1698', FALSE, TRUE, FALSE),
(6, '169820', 'CONCESIONES Y FRANQUICIAS', FALSE, 'Amortización concesiones', '1698', FALSE, TRUE, FALSE),
(6, '169830', 'DERECHOS', FALSE, 'Amortización derechos', '1698', FALSE, TRUE, FALSE),
(6, '169835', 'KNOW HOW', FALSE, 'Amortización know how', '1698', FALSE, TRUE, FALSE),
(6, '169840', 'LICENCIAS', FALSE, 'Amortización licencias', '1698', FALSE, TRUE, FALSE),
(6, '169899', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación amortización intangibles', '1698', FALSE, TRUE, FALSE);

-- Subcuentas 1699 (Provisiones Intangibles - CRÉDITO)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '169901', 'PROVISIONES 169901 A 169998', FALSE, 'Provisiones rango', '1699', FALSE, TRUE, FALSE),
(6, '169998', 'PROVISIONES FIN RANGO', FALSE, 'Provisiones fin', '1699', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 17 — DIFERIDOS
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '17', 'DIFERIDOS', TRUE, 'Gastos pagados por anticipado y cargos diferidos', '1', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '1705', 'GASTOS PAGADOS POR ANTICIPADO', TRUE, 'Gastos pagados por anticipado', '17', FALSE, TRUE, FALSE),
(4, '1710', 'CARGOS DIFERIDOS', TRUE, 'Cargos diferidos', '17', FALSE, TRUE, FALSE),
(4, '1715', 'COSTOS DE EXPLORACION POR AMORTIZAR', TRUE, 'Costos exploración', '17', FALSE, TRUE, FALSE),
(4, '1720', 'COSTOS DE EXPLOTACION Y DESARROLLO', TRUE, 'Costos explotación', '17', FALSE, TRUE, FALSE),
(4, '1730', 'CARGOS POR CORRECCION MONETARIA DIFERIDA', TRUE, 'Corrección monetaria diferida', '17', FALSE, TRUE, FALSE),
(4, '1798', 'AMORTIZACION ACUMULADA', FALSE, 'Amortización acumulada diferidos', '17', FALSE, TRUE, FALSE);

-- Subcuentas 1705
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '170505', 'INTERESES', TRUE, 'Intereses anticipados', '1705', FALSE, TRUE, FALSE),
(6, '170510', 'HONORARIOS', TRUE, 'Honorarios anticipados', '1705', FALSE, TRUE, FALSE),
(6, '170515', 'COMISIONES', TRUE, 'Comisiones anticipadas', '1705', FALSE, TRUE, FALSE),
(6, '170520', 'SEGUROS Y FIANZAS', TRUE, 'Seguros y fianzas anticipados', '1705', FALSE, TRUE, FALSE),
(6, '170525', 'ARRENDAMIENTOS', TRUE, 'Arrendamientos anticipados', '1705', FALSE, TRUE, FALSE),
(6, '170530', 'BODEGAJES', TRUE, 'Bodegajes anticipados', '1705', FALSE, TRUE, FALSE),
(6, '170535', 'MANTENIMIENTO EQUIPOS', TRUE, 'Mantenimiento anticipado', '1705', FALSE, TRUE, FALSE),
(6, '170540', 'SERVICIOS', TRUE, 'Servicios anticipados', '1705', FALSE, TRUE, FALSE),
(6, '170545', 'SUSCRIPCIONES', TRUE, 'Suscripciones anticipadas', '1705', FALSE, TRUE, FALSE),
(6, '170595', 'OTROS', TRUE, 'Otros gastos anticipados', '1705', FALSE, TRUE, FALSE);

-- Subcuentas 1710
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '171004', 'ORGANIZACION Y PREOPERATIVOS', TRUE, 'Organización y preoperativos', '1710', FALSE, TRUE, FALSE),
(6, '171008', 'REMODELACIONES', TRUE, 'Remodelaciones', '1710', FALSE, TRUE, FALSE),
(6, '171012', 'ESTUDIOS, INVESTIGACIONES Y PROYECTOS', TRUE, 'Estudios y proyectos', '1710', FALSE, TRUE, FALSE),
(6, '171016', 'PROGRAMAS PARA COMPUTADOR (SOFTWARE)', TRUE, 'Software', '1710', FALSE, TRUE, FALSE),
(6, '171020', 'UTILES Y PAPELERIA', TRUE, 'Útiles y papelería', '1710', FALSE, TRUE, FALSE),
(6, '171024', 'MEJORAS A PROPIEDADES AJENAS', TRUE, 'Mejoras propiedades ajenas', '1710', FALSE, TRUE, FALSE),
(6, '171028', 'CONTRIBUCIONES Y AFILIACIONES', TRUE, 'Contribuciones', '1710', FALSE, TRUE, FALSE),
(6, '171032', 'ENTRENAMIENTO DE PERSONAL', TRUE, 'Entrenamiento personal', '1710', FALSE, TRUE, FALSE),
(6, '171036', 'FERIAS Y EXPOSICIONES', TRUE, 'Ferias y exposiciones', '1710', FALSE, TRUE, FALSE),
(6, '171040', 'LICENCIAS', TRUE, 'Licencias', '1710', FALSE, TRUE, FALSE),
(6, '171044', 'PUBLICIDAD, PROPAGANDA Y PROMOCION', TRUE, 'Publicidad y propaganda', '1710', FALSE, TRUE, FALSE),
(6, '171048', 'ELEMENTOS DE ASEO Y CAFETERIA', TRUE, 'Aseo y cafetería', '1710', FALSE, TRUE, FALSE),
(6, '171052', 'MOLDES Y TROQUELES', TRUE, 'Moldes y troqueles', '1710', FALSE, TRUE, FALSE),
(6, '171056', 'INSTRUMENTAL QUIRURGICO', TRUE, 'Instrumental quirúrgico', '1710', FALSE, TRUE, FALSE),
(6, '171060', 'DOTACION Y SUMINISTRO A TRABAJADORES', TRUE, 'Dotación', '1710', FALSE, TRUE, FALSE),
(6, '171064', 'ELEMENTOS DE ROPERIA Y LENCERIA', TRUE, 'Ropería', '1710', FALSE, TRUE, FALSE),
(6, '171068', 'LOZA Y CRISTALERIA', TRUE, 'Loza y cristalería', '1710', FALSE, TRUE, FALSE),
(6, '171069', 'PLATERIA', TRUE, 'Platería', '1710', FALSE, TRUE, FALSE),
(6, '171070', 'CUBIERTERIA', TRUE, 'Cubiertería', '1710', FALSE, TRUE, FALSE),
(6, '171076', 'IMPUESTO DE RENTA DIFERIDO DEBITOS POR DIFERENCIAS TEMPORALES', TRUE, 'Impuesto renta diferido débitos', '1710', FALSE, TRUE, FALSE),
(6, '171080', 'CONCURSOS Y LICITACIONES', TRUE, 'Concursos y licitaciones', '1710', FALSE, TRUE, FALSE),
(6, '171095', 'OTROS', TRUE, 'Otros cargos diferidos', '1710', FALSE, TRUE, FALSE),
(6, '171099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación cargos diferidos', '1710', FALSE, TRUE, FALSE);

-- Subcuentas 1715
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '171505', 'POZOS SECOS', TRUE, 'Pozos secos', '1715', FALSE, TRUE, FALSE),
(6, '171510', 'POZOS NO COMERCIALES', TRUE, 'Pozos no comerciales', '1715', FALSE, TRUE, FALSE),
(6, '171515', 'OTROS COSTOS DE EXPLORACION', TRUE, 'Otros costos exploración', '1715', FALSE, TRUE, FALSE),
(6, '171599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación exploración', '1715', FALSE, TRUE, FALSE);

-- Subcuentas 1720
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '172005', 'PERFORACION Y EXPLOTACION', TRUE, 'Perforación y explotación', '1720', FALSE, TRUE, FALSE),
(6, '172010', 'PERFORACIONES CAMPOS EN DESARROLLO', TRUE, 'Perforaciones desarrollo', '1720', FALSE, TRUE, FALSE),
(6, '172015', 'FACILIDADES DE PRODUCCION', TRUE, 'Facilidades producción', '1720', FALSE, TRUE, FALSE),
(6, '172020', 'SERVICIO A POZOS', TRUE, 'Servicio a pozos', '1720', FALSE, TRUE, FALSE),
(6, '172099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación explotación', '1720', FALSE, TRUE, FALSE);

-- Subcuentas 1730
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '173001', 'CARGOS POR CORRECCION MONETARIA 173001 A 173098', TRUE, 'Corrección monetaria rango', '1730', FALSE, TRUE, FALSE),
(6, '173098', 'CARGOS POR CORRECCION MONETARIA FIN RANGO', TRUE, 'Corrección monetaria fin', '1730', FALSE, TRUE, FALSE);

-- Subcuentas 1798
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '179805', 'COSTOS DE EXPLORACION POR AMORTIZAR', FALSE, 'Amortización exploración', '1798', FALSE, TRUE, FALSE),
(6, '179810', 'COSTOS DE EXPLOTACION Y DESARROLLO', FALSE, 'Amortización explotación', '1798', FALSE, TRUE, FALSE),
(6, '179899', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación amortización diferidos', '1798', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 18 — OTROS ACTIVOS
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '18', 'OTROS ACTIVOS', TRUE, 'Bienes no clasificables en cuentas anteriores', '1', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '1805', 'BIENES DE ARTE Y CULTURA', TRUE, 'Bienes de arte y cultura', '18', FALSE, TRUE, FALSE),
(4, '1895', 'DIVERSOS', TRUE, 'Otros activos diversos', '18', FALSE, TRUE, FALSE),
(4, '1899', 'PROVISIONES', FALSE, 'Provisión otros activos', '18', FALSE, TRUE, FALSE);

-- Subcuentas 1805
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '180505', 'OBRAS DE ARTE', TRUE, 'Obras de arte', '1805', FALSE, TRUE, FALSE),
(6, '180510', 'BIBLIOTECAS', TRUE, 'Bibliotecas', '1805', FALSE, TRUE, FALSE),
(6, '180595', 'OTROS', TRUE, 'Otros bienes arte', '1805', FALSE, TRUE, FALSE),
(6, '180599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación bienes arte', '1805', FALSE, TRUE, FALSE);

-- Subcuentas 1895
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '189505', 'MAQUINAS PORTEADORAS', TRUE, 'Máquinas porteadoras', '1895', FALSE, TRUE, FALSE),
(6, '189510', 'BIENES ENTREGADOS EN COMODATO', TRUE, 'Bienes en comodato', '1895', FALSE, TRUE, FALSE),
(6, '189515', 'AMORTIZACION ACUMULADA DE BIENES ENTREGADOS EN COMODATO (CR)', FALSE, 'Amortización bienes comodato', '1895', FALSE, TRUE, FALSE),
(6, '189520', 'BIENES RECIBIDOS EN PAGO', TRUE, 'Bienes recibidos en pago', '1895', FALSE, TRUE, FALSE),
(6, '189525', 'DERECHOS SUCESORALES', TRUE, 'Derechos sucesorales', '1895', FALSE, TRUE, FALSE),
(6, '189530', 'ESTAMPILLAS', TRUE, 'Estampillas', '1895', FALSE, TRUE, FALSE),
(6, '189595', 'OTROS', TRUE, 'Otros activos diversos', '1895', FALSE, TRUE, FALSE),
(6, '189599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación otros activos', '1895', FALSE, TRUE, FALSE);

-- Subcuentas 1899
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '189905', 'BIENES DE ARTE Y CULTURA', FALSE, 'Provisión bienes arte', '1899', FALSE, TRUE, FALSE),
(6, '189995', 'DIVERSOS', FALSE, 'Provisión otros activos', '1899', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 19 — VALORIZACIONES
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '19', 'VALORIZACIONES', TRUE, 'Utilidad potencial no realizada de inversiones y PPE', '1', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '1905', 'DE INVERSIONES', TRUE, 'Valorización inversiones', '19', FALSE, TRUE, FALSE),
(4, '1910', 'DE PROPIEDADES PLANTA Y EQUIPO', TRUE, 'Valorización PPE', '19', FALSE, TRUE, FALSE),
(4, '1995', 'DE OTROS ACTIVOS', TRUE, 'Valorización otros activos', '19', FALSE, TRUE, FALSE);

-- Subcuentas 1905
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '190505', 'ACCIONES', TRUE, 'Valorización acciones', '1905', FALSE, TRUE, FALSE),
(6, '190510', 'CUOTAS O PARTES DE INTERES SOCIAL', TRUE, 'Valorización cuotas', '1905', FALSE, TRUE, FALSE),
(6, '190515', 'DERECHOS FIDUCIARIOS', TRUE, 'Valorización fiducias', '1905', FALSE, TRUE, FALSE);

-- Subcuentas 1910
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '191004', 'TERRENOS', TRUE, 'Valorización terrenos', '1910', FALSE, TRUE, FALSE),
(6, '191006', 'MATERIALES PROYECTOS PETROLEROS', TRUE, 'Valorización materiales petroleros', '1910', FALSE, TRUE, FALSE),
(6, '191008', 'CONSTRUCCIONES Y EDIFICACIONES', TRUE, 'Valorización construcciones', '1910', FALSE, TRUE, FALSE),
(6, '191012', 'MAQUINARIA Y EQUIPO', TRUE, 'Valorización maquinaria', '1910', FALSE, TRUE, FALSE),
(6, '191016', 'EQUIPO DE OFICINA', TRUE, 'Valorización equipo oficina', '1910', FALSE, TRUE, FALSE),
(6, '191020', 'EQUIPO DE COMPUTACION Y COMUNICACION', TRUE, 'Valorización cómputo', '1910', FALSE, TRUE, FALSE),
(6, '191024', 'EQUIPO MEDICO CIENTIFICO', TRUE, 'Valorización médico', '1910', FALSE, TRUE, FALSE),
(6, '191028', 'EQUIPO DE HOTELES Y RESTAURANTES', TRUE, 'Valorización hoteles', '1910', FALSE, TRUE, FALSE),
(6, '191032', 'FLOTA Y EQUIPO DE TRANSPORTE', TRUE, 'Valorización flota', '1910', FALSE, TRUE, FALSE),
(6, '191036', 'FLOTA Y EQUIPO FLUVIAL Y/O MARITIMO', TRUE, 'Valorización fluvial', '1910', FALSE, TRUE, FALSE),
(6, '191040', 'FLOTA Y EQUIPO AEREO', TRUE, 'Valorización aéreo', '1910', FALSE, TRUE, FALSE),
(6, '191044', 'FLOTA Y EQUIPO FERREO', TRUE, 'Valorización férreo', '1910', FALSE, TRUE, FALSE),
(6, '191048', 'ACUEDUCTOS PLANTAS Y REDES', TRUE, 'Valorización acueductos', '1910', FALSE, TRUE, FALSE),
(6, '191052', 'ARMAMENTO DE VIGILANCIA', TRUE, 'Valorización armamento', '1910', FALSE, TRUE, FALSE),
(6, '191056', 'ENVASES Y EMPAQUES', TRUE, 'Valorización envases', '1910', FALSE, TRUE, FALSE),
(6, '191060', 'PLANTACIONES AGRICOLAS Y FORESTALES', TRUE, 'Valorización plantaciones', '1910', FALSE, TRUE, FALSE),
(6, '191064', 'VIAS DE COMUNICACION', TRUE, 'Valorización vías', '1910', FALSE, TRUE, FALSE),
(6, '191068', 'MINAS Y CANTERAS', TRUE, 'Valorización minas', '1910', FALSE, TRUE, FALSE),
(6, '191072', 'POZOS ARTESIANOS', TRUE, 'Valorización pozos', '1910', FALSE, TRUE, FALSE),
(6, '191076', 'YACIMIENTOS', TRUE, 'Valorización yacimientos', '1910', FALSE, TRUE, FALSE),
(6, '191080', 'SEMOVIENTES', TRUE, 'Valorización semovientes', '1910', FALSE, TRUE, FALSE);

-- Subcuentas 1995
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '199505', 'BIENES DE ARTE Y CULTURA', TRUE, 'Valorización bienes arte', '1995', FALSE, TRUE, FALSE),
(6, '199510', 'BIENES ENTREGADOS EN COMODATO', TRUE, 'Valorización bienes comodato', '1995', FALSE, TRUE, FALSE),
(6, '199515', 'BIENES RECIBIDOS EN PAGO', TRUE, 'Valorización bienes pago', '1995', FALSE, TRUE, FALSE),
(6, '199520', 'INVENTARIO DE SEMOVIENTES', TRUE, 'Valorización inventario semovientes', '1995', FALSE, TRUE, FALSE);

-- ============================================================
-- CLASE 2: PASIVO (naturaleza CRÉDITO)
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(1, '2', 'PASIVO', FALSE, 'Obligaciones contraídas por el ente económico, pagaderas en dinero, bienes o servicios', '0', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '21', 'OBLIGACIONES FINANCIERAS', FALSE, 'Obligaciones con establecimientos de crédito u otras instituciones financieras', '2', FALSE, TRUE, FALSE),
(2, '22', 'PROVEEDORES', FALSE, 'Obligaciones por adquisición de bienes o servicios', '2', FALSE, TRUE, FALSE),
(2, '23', 'CUENTAS POR PAGAR', FALSE, 'Obligaciones a favor de terceros por conceptos diferentes a proveedores', '2', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 21 — OBLIGACIONES FINANCIERAS
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '2105', 'BANCOS NACIONALES', FALSE, 'Obligaciones con bancos nacionales', '21', FALSE, TRUE, FALSE),
(4, '2110', 'BANCOS DEL EXTERIOR', FALSE, 'Obligaciones con bancos del exterior', '21', FALSE, TRUE, FALSE),
(4, '2115', 'CORPORACIONES FINANCIERAS', FALSE, 'Obligaciones con corporaciones financieras', '21', FALSE, TRUE, FALSE),
(4, '2120', 'COMPANIAS DE FINANCIAMIENTO COMERCIAL', FALSE, 'Obligaciones con CFC', '21', FALSE, TRUE, FALSE),
(4, '2125', 'CORPORACIONES DE AHORRO Y VIVIENDA', FALSE, 'Obligaciones con CAV', '21', FALSE, TRUE, FALSE),
(4, '2130', 'ENTIDADES FINANCIERAS DEL EXTERIOR', FALSE, 'Obligaciones con entidades financieras del exterior', '21', FALSE, TRUE, FALSE),
(4, '2135', 'COMPROMISOS DE RECOMPRA DE INVERSIONES NEGOCIADAS', FALSE, 'Compromisos de recompra', '21', FALSE, TRUE, FALSE),
(4, '2140', 'COMPROMISOS DE RECOMPRA DE CARTERA NEGOCIADA', FALSE, 'Recompra cartera negociada', '21', FALSE, TRUE, FALSE),
(4, '2145', 'OBLIGACIONES GUBERNAMENTALES', FALSE, 'Obligaciones con el gobierno', '21', FALSE, TRUE, FALSE),
(4, '2195', 'OTRAS OBLIGACIONES', FALSE, 'Otras obligaciones financieras', '21', FALSE, TRUE, FALSE);

-- Subcuentas 2105
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '210505', 'SOBREGIROS', FALSE, 'Sobregiros bancarios', '2105', FALSE, TRUE, FALSE),
(6, '210510', 'PAGARES', FALSE, 'Pagarés', '2105', FALSE, TRUE, FALSE),
(6, '210515', 'CARTAS DE CREDITO', FALSE, 'Cartas de crédito', '2105', FALSE, TRUE, FALSE),
(6, '210520', 'ACEPTACIONES BANCARIAS', FALSE, 'Aceptaciones bancarias', '2105', FALSE, TRUE, FALSE);

-- Subcuentas 2110
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '211005', 'SOBREGIROS', FALSE, 'Sobregiros exterior', '2110', FALSE, TRUE, FALSE),
(6, '211010', 'PAGARES', FALSE, 'Pagarés exterior', '2110', FALSE, TRUE, FALSE),
(6, '211015', 'CARTAS DE CREDITO', FALSE, 'Cartas de crédito exterior', '2110', FALSE, TRUE, FALSE),
(6, '211020', 'ACEPTACIONES BANCARIAS', FALSE, 'Aceptaciones bancarias exterior', '2110', FALSE, TRUE, FALSE);

-- Subcuentas 2115
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '211505', 'PAGARES', FALSE, 'Pagarés corporaciones', '2115', FALSE, TRUE, FALSE),
(6, '211510', 'ACEPTACIONES FINANCIERAS', FALSE, 'Aceptaciones financieras', '2115', FALSE, TRUE, FALSE),
(6, '211515', 'CARTAS DE CREDITO', FALSE, 'Cartas de crédito corporaciones', '2115', FALSE, TRUE, FALSE),
(6, '211520', 'CONTRATOS DE ARRENDAMIENTO FINANCIERO (LEASING)', FALSE, 'Leasing', '2115', FALSE, TRUE, FALSE);

-- Subcuentas 2120
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '212005', 'PAGARES', FALSE, 'Pagarés CFC', '2120', FALSE, TRUE, FALSE),
(6, '212010', 'ACEPTACIONES FINANCIERAS', FALSE, 'Aceptaciones financieras CFC', '2120', FALSE, TRUE, FALSE),
(6, '212020', 'CONTRATOS DE ARRENDAMIENTO FINANCIERO (LEASING)', FALSE, 'Leasing CFC', '2120', FALSE, TRUE, FALSE);

-- Subcuentas 2125
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '212505', 'SOBREGIROS', FALSE, 'Sobregiros CAV', '2125', FALSE, TRUE, FALSE),
(6, '212510', 'PAGARES', FALSE, 'Pagarés CAV', '2125', FALSE, TRUE, FALSE),
(6, '212515', 'HIPOTECARIAS', FALSE, 'Hipotecarias', '2125', FALSE, TRUE, FALSE);

-- Subcuentas 2130
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '213001', 'ENTIDADES FINANCIERAS DEL EXTERIOR 213001 A 213098', FALSE, 'Entidades exterior rango', '2130', FALSE, TRUE, FALSE),
(6, '213098', 'ENTIDADES FINANCIERAS DEL EXTERIOR FIN RANGO', FALSE, 'Entidades exterior fin', '2130', FALSE, TRUE, FALSE);

-- Subcuentas 2135
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '213505', 'ACCIONES', FALSE, 'Recompra acciones', '2135', FALSE, TRUE, FALSE),
(6, '213510', 'CUOTAS O PARTES DE INTERES SOCIAL', FALSE, 'Recompra cuotas', '2135', FALSE, TRUE, FALSE),
(6, '213515', 'BONOS', FALSE, 'Recompra bonos', '2135', FALSE, TRUE, FALSE),
(6, '213520', 'CEDULAS', FALSE, 'Recompra cédulas', '2135', FALSE, TRUE, FALSE),
(6, '213525', 'CERTIFICADOS', FALSE, 'Recompra certificados', '2135', FALSE, TRUE, FALSE),
(6, '213530', 'PAPELES COMERCIALES', FALSE, 'Recompra papeles', '2135', FALSE, TRUE, FALSE),
(6, '213535', 'TITULOS', FALSE, 'Recompra títulos', '2135', FALSE, TRUE, FALSE),
(6, '213540', 'ACEPTACIONES BANCARIAS O FINANCIERAS', FALSE, 'Recompra aceptaciones', '2135', FALSE, TRUE, FALSE),
(6, '213595', 'OTROS', FALSE, 'Recompra otros', '2135', FALSE, TRUE, FALSE);

-- Subcuentas 2140
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '214001', 'COMPROMISOS DE RECOMPRA DE CARTERA 214001 A 214098', FALSE, 'Recompra cartera rango', '2140', FALSE, TRUE, FALSE),
(6, '214098', 'COMPROMISOS DE RECOMPRA DE CARTERA FIN RANGO', FALSE, 'Recompra cartera fin', '2140', FALSE, TRUE, FALSE);

-- Subcuentas 2145
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '214505', 'GOBIERNO NACIONAL', FALSE, 'Obligaciones gobierno nacional', '2145', FALSE, TRUE, FALSE),
(6, '214510', 'ENTIDADES OFICIALES', FALSE, 'Obligaciones entidades oficiales', '2145', FALSE, TRUE, FALSE);

-- Subcuentas 2195
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '219505', 'PARTICULARES', FALSE, 'Obligaciones particulares', '2195', FALSE, TRUE, FALSE),
(6, '219510', 'COMPAÑIAS VINCULADAS', FALSE, 'Obligaciones vinculadas', '2195', FALSE, TRUE, FALSE),
(6, '219515', 'CASA MATRIZ', FALSE, 'Obligaciones casa matriz', '2195', FALSE, TRUE, FALSE),
(6, '219520', 'SOCIOS O ACCIONISTAS', FALSE, 'Obligaciones socios', '2195', FALSE, TRUE, FALSE),
(6, '219525', 'FONDOS Y COOPERATIVAS', FALSE, 'Obligaciones fondos', '2195', FALSE, TRUE, FALSE),
(6, '219530', 'DIRECTORES', FALSE, 'Obligaciones directores', '2195', FALSE, TRUE, FALSE),
(6, '219595', 'OTRAS', FALSE, 'Otras obligaciones', '2195', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 22 — PROVEEDORES
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '2205', 'NACIONALES', FALSE, 'Proveedores nacionales', '22', TRUE, TRUE, FALSE),
(4, '2210', 'DEL EXTERIOR', FALSE, 'Proveedores del exterior', '22', TRUE, TRUE, FALSE),
(4, '2215', 'CUENTAS CORRIENTES COMERCIALES', FALSE, 'Cuentas corrientes comerciales', '22', TRUE, TRUE, FALSE),
(4, '2220', 'CASA MATRIZ', FALSE, 'Proveedores casa matriz', '22', FALSE, TRUE, FALSE),
(4, '2225', 'COMPAÑIAS VINCULADAS', FALSE, 'Proveedores vinculados', '22', FALSE, TRUE, FALSE);

-- Subcuentas 2205
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '220501', 'NACIONALES 220501 A 220598', FALSE, 'Proveedores nacionales rango', '2205', TRUE, TRUE, FALSE),
(6, '220598', 'NACIONALES FIN RANGO', FALSE, 'Proveedores nacionales fin', '2205', TRUE, TRUE, FALSE);

-- Subcuentas 2210
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '221001', 'DEL EXTERIOR 221001 A 221098', FALSE, 'Proveedores exterior rango', '2210', TRUE, TRUE, FALSE),
(6, '221098', 'DEL EXTERIOR FIN RANGO', FALSE, 'Proveedores exterior fin', '2210', TRUE, TRUE, FALSE);

-- Subcuentas 2215
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '221501', 'CUENTAS CORRIENTES COMERCIALES 221501 A 221598', FALSE, 'Cuentas corrientes rango', '2215', TRUE, TRUE, FALSE),
(6, '221598', 'CUENTAS CORRIENTES COMERCIALES FIN RANGO', FALSE, 'Cuentas corrientes fin', '2215', TRUE, TRUE, FALSE);

-- Subcuentas 2220
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '222001', 'CASA MATRIZ 222001 A 222098', FALSE, 'Casa matriz rango', '2220', FALSE, TRUE, FALSE),
(6, '222098', 'CASA MATRIZ FIN RANGO', FALSE, 'Casa matriz fin', '2220', FALSE, TRUE, FALSE);

-- Subcuentas 2225
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '222501', 'COMPAÑIAS VINCULADAS 222501 A 222598', FALSE, 'Vinculadas rango', '2225', FALSE, TRUE, FALSE),
(6, '222598', 'COMPAÑIAS VINCULADAS FIN RANGO', FALSE, 'Vinculadas fin', '2225', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 23 — CUENTAS POR PAGAR
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '2305', 'CUENTAS CORRIENTES COMERCIALES', FALSE, 'Cuentas corrientes comerciales', '23', TRUE, TRUE, FALSE),
(4, '2310', 'A CASA MATRIZ', FALSE, 'Cuentas por pagar a casa matriz', '23', FALSE, TRUE, FALSE),
(4, '2315', 'A COMPAÑIAS VINCULADAS', FALSE, 'Cuentas por pagar a vinculadas', '23', FALSE, TRUE, FALSE),
(4, '2320', 'A CONTRATISTAS', FALSE, 'Cuentas por pagar a contratistas', '23', TRUE, TRUE, FALSE),
(4, '2330', 'ORDENES DE COMPRA POR UTILIZAR', FALSE, 'Órdenes de compra por utilizar', '23', FALSE, TRUE, FALSE),
(4, '2335', 'COSTOS Y GASTOS POR PAGAR', FALSE, 'Costos y gastos por pagar', '23', FALSE, TRUE, FALSE),
(4, '2340', 'INSTALAMENTOS POR PAGAR', FALSE, 'Instalamentos por pagar', '23', FALSE, TRUE, FALSE),
(4, '2345', 'ACREEDORES OFICIALES', FALSE, 'Acreedores oficiales', '23', FALSE, TRUE, FALSE),
(4, '2350', 'REGALIAS POR PAGAR', FALSE, 'Regalías por pagar', '23', FALSE, TRUE, FALSE),
(4, '2355', 'DEUDAS CON ACCIONISTAS O SOCIOS', FALSE, 'Deudas con accionistas o socios', '23', FALSE, TRUE, FALSE),
(4, '2357', 'DEUDAS CON DIRECTORES', FALSE, 'Deudas con directores', '23', FALSE, TRUE, FALSE),
(4, '2360', 'DIVIDENDOS O PARTICIPACIONES POR PAGAR', FALSE, 'Dividendos por pagar', '23', FALSE, TRUE, FALSE),
(4, '2365', 'RETENCION EN LA FUENTE', FALSE, 'Retención en la fuente', '23', FALSE, TRUE, FALSE),
(4, '2367', 'IMPUESTO A LAS VENTAS RETENIDO', FALSE, 'IVA retenido', '23', FALSE, TRUE, FALSE),
(4, '2368', 'IMPUESTO DE INDUSTRIA Y COMERCIO RETENIDO', FALSE, 'ICA retenido', '23', FALSE, TRUE, FALSE),
(4, '2370', 'RETENCIONES Y APORTES DE NOMINA', FALSE, 'Retenciones y aportes nómina', '23', FALSE, TRUE, FALSE),
(4, '2375', 'CUOTAS POR DEVOLVER', FALSE, 'Cuotas por devolver', '23', FALSE, TRUE, FALSE),
(4, '2380', 'ACREEDORES VARIOS', FALSE, 'Acreedores varios', '23', FALSE, TRUE, FALSE);

-- Subcuentas 2305
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '230501', 'CUENTAS CORRIENTES COMERCIALES 230501 A 230598', FALSE, 'Cuentas corrientes rango', '2305', TRUE, TRUE, FALSE),
(6, '230598', 'CUENTAS CORRIENTES COMERCIALES FIN RANGO', FALSE, 'Cuentas corrientes fin', '2305', TRUE, TRUE, FALSE);

-- Subcuentas 2310
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '231001', 'A CASA MATRIZ 231001 A 231098', FALSE, 'Casa matriz rango', '2310', FALSE, TRUE, FALSE),
(6, '231098', 'A CASA MATRIZ FIN RANGO', FALSE, 'Casa matriz fin', '2310', FALSE, TRUE, FALSE);

-- Subcuentas 2315
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '231501', 'A COMPAÑIAS VINCULADAS 231501 A 231598', FALSE, 'Vinculadas rango', '2315', FALSE, TRUE, FALSE),
(6, '231598', 'A COMPAÑIAS VINCULADAS FIN RANGO', FALSE, 'Vinculadas fin', '2315', FALSE, TRUE, FALSE);

-- Subcuentas 2320
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '232001', 'A CONTRATISTAS 232001 A 232098', FALSE, 'Contratistas rango', '2320', TRUE, TRUE, FALSE),
(6, '232098', 'A CONTRATISTAS FIN RANGO', FALSE, 'Contratistas fin', '2320', TRUE, TRUE, FALSE);

-- Subcuentas 2330
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '233001', 'ORDENES DE COMPRA 233001 A 233098', FALSE, 'Órdenes compra rango', '2330', FALSE, TRUE, FALSE),
(6, '233098', 'ORDENES DE COMPRA FIN RANGO', FALSE, 'Órdenes compra fin', '2330', FALSE, TRUE, FALSE);

-- Subcuentas 2335
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '233505', 'GASTOS FINANCIEROS', FALSE, 'Gastos financieros por pagar', '2335', FALSE, TRUE, FALSE),
(6, '233510', 'GASTOS LEGALES', FALSE, 'Gastos legales por pagar', '2335', FALSE, TRUE, FALSE),
(6, '233515', 'LIBROS, SUSCRIPCIONES, PERIODICOS Y REVISTAS', FALSE, 'Libros y suscripciones', '2335', FALSE, TRUE, FALSE),
(6, '233520', 'COMISIONES', FALSE, 'Comisiones por pagar', '2335', FALSE, TRUE, FALSE),
(6, '233525', 'HONORARIOS', FALSE, 'Honorarios por pagar', '2335', FALSE, TRUE, FALSE),
(6, '233530', 'SERVICIOS TECNICOS', FALSE, 'Servicios técnicos', '2335', FALSE, TRUE, FALSE),
(6, '233535', 'SERVICIOS DE MANTENIMIENTO', FALSE, 'Servicios de mantenimiento', '2335', FALSE, TRUE, FALSE),
(6, '233540', 'ARRENDAMIENTOS', FALSE, 'Arrendamientos por pagar', '2335', FALSE, TRUE, FALSE),
(6, '233545', 'TRANSPORTES, FLETES Y ACARREOS', FALSE, 'Transportes por pagar', '2335', FALSE, TRUE, FALSE),
(6, '233550', 'SERVICIOS PUBLICOS', FALSE, 'Servicios públicos por pagar', '2335', FALSE, TRUE, FALSE),
(6, '233555', 'SEGUROS', FALSE, 'Seguros por pagar', '2335', FALSE, TRUE, FALSE),
(6, '233560', 'GASTOS DE VIAJE', FALSE, 'Gastos de viaje por pagar', '2335', FALSE, TRUE, FALSE),
(6, '233565', 'GASTOS DE REPRESENTACION Y RELACIONES PUBLICAS', FALSE, 'Representación por pagar', '2335', FALSE, TRUE, FALSE),
(6, '233570', 'SERVICIOS ADUANEROS', FALSE, 'Servicios aduaneros', '2335', FALSE, TRUE, FALSE),
(6, '233595', 'OTROS', FALSE, 'Otros gastos por pagar', '2335', FALSE, TRUE, FALSE);

-- Subcuentas 2340
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '234001', 'INSTALAMENTOS 234001 A 234098', FALSE, 'Instalamentos rango', '2340', FALSE, TRUE, FALSE),
(6, '234098', 'INSTALAMENTOS FIN RANGO', FALSE, 'Instalamentos fin', '2340', FALSE, TRUE, FALSE);

-- Subcuentas 2345
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '234501', 'ACREEDORES OFICIALES 234501 A 234598', FALSE, 'Acreedores oficiales rango', '2345', FALSE, TRUE, FALSE),
(6, '234598', 'ACREEDORES OFICIALES FIN RANGO', FALSE, 'Acreedores oficiales fin', '2345', FALSE, TRUE, FALSE);

-- Subcuentas 2350
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '235001', 'REGALIAS 235001 A 235098', FALSE, 'Regalías rango', '2350', FALSE, TRUE, FALSE),
(6, '235098', 'REGALIAS FIN RANGO', FALSE, 'Regalías fin', '2350', FALSE, TRUE, FALSE);

-- Subcuentas 2355
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '235505', 'ACCIONISTAS', FALSE, 'Deudas accionistas', '2355', FALSE, TRUE, FALSE),
(6, '235510', 'SOCIOS', FALSE, 'Deudas socios', '2355', FALSE, TRUE, FALSE);

-- Subcuentas 2357
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '235701', 'DEUDAS CON DIRECTORES 235701 A 235798', FALSE, 'Deudas directores rango', '2357', FALSE, TRUE, FALSE),
(6, '235798', 'DEUDAS CON DIRECTORES FIN RANGO', FALSE, 'Deudas directores fin', '2357', FALSE, TRUE, FALSE);

-- Subcuentas 2360
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '236005', 'DIVIDENDOS', FALSE, 'Dividendos por pagar', '2360', FALSE, TRUE, FALSE),
(6, '236010', 'PARTICIPACIONES', FALSE, 'Participaciones por pagar', '2360', FALSE, TRUE, FALSE);

-- Subcuentas 2365
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '236505', 'SALARIOS Y PAGOS LABORALES', FALSE, 'Retención salarios', '2365', FALSE, TRUE, FALSE),
(6, '236510', 'DIVIDENDOS Y/O PARTICIPACIONES', FALSE, 'Retención dividendos', '2365', FALSE, TRUE, FALSE),
(6, '236515', 'HONORARIOS', FALSE, 'Retención honorarios', '2365', FALSE, TRUE, FALSE),
(6, '236520', 'COMISIONES', FALSE, 'Retención comisiones', '2365', FALSE, TRUE, FALSE),
(6, '236525', 'SERVICIOS', FALSE, 'Retención servicios', '2365', FALSE, TRUE, FALSE),
(6, '236530', 'ARRENDAMIENTOS', FALSE, 'Retención arrendamientos', '2365', FALSE, TRUE, FALSE),
(6, '236535', 'RENDIMIENTOS FINANCIEROS', FALSE, 'Retención rendimientos', '2365', FALSE, TRUE, FALSE),
(6, '236540', 'COMPRAS', FALSE, 'Retención compras', '2365', FALSE, TRUE, FALSE),
(6, '236545', 'LOTERIAS, RIFAS, APUESTAS Y SIMILARES', FALSE, 'Retención loterías', '2365', FALSE, TRUE, FALSE),
(6, '236550', 'POR PAGOS AL EXTERIOR', FALSE, 'Retención pagos exterior', '2365', FALSE, TRUE, FALSE),
(6, '236555', 'POR INGRESOS OBTENIDOS EN EL EXTERIOR', FALSE, 'Retención ingresos exterior', '2365', FALSE, TRUE, FALSE),
(6, '236560', 'ENAJENACION PROPIEDADES PLANTA Y EQUIPO PERSONAS NATURALES', FALSE, 'Retención enajenación PPE', '2365', FALSE, TRUE, FALSE),
(6, '236565', 'POR IMPUESTO DE TIMBRE', FALSE, 'Retención timbre', '2365', FALSE, TRUE, FALSE),
(6, '236570', 'OTRAS RETENCIONES Y PATRIMONIO', FALSE, 'Otras retenciones', '2365', FALSE, TRUE, FALSE),
(6, '236575', 'AUTORRETENCIONES', FALSE, 'Autorretenciones', '2365', FALSE, TRUE, FALSE);

-- Subcuentas 2367
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '236701', 'IMPUESTO A LAS VENTAS RETENIDO 236701 A 236798', FALSE, 'IVA retenido rango', '2367', FALSE, TRUE, FALSE),
(6, '236798', 'IMPUESTO A LAS VENTAS RETENIDO FIN RANGO', FALSE, 'IVA retenido fin', '2367', FALSE, TRUE, FALSE);

-- Subcuentas 2368
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '236801', 'IMPUESTO DE INDUSTRIA Y COMERCIO RETENIDO 236801 A 236898', FALSE, 'ICA retenido rango', '2368', FALSE, TRUE, FALSE),
(6, '236898', 'IMPUESTO DE INDUSTRIA Y COMERCIO RETENIDO FIN RANGO', FALSE, 'ICA retenido fin', '2368', FALSE, TRUE, FALSE);

-- Subcuentas 2370
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '237005', 'APORTES A ENTIDADES PROMOTORAS DE SALUD EPS', FALSE, 'Aportes EPS', '2370', FALSE, TRUE, FALSE),
(6, '237006', 'APORTES A ADMINISTRADORAS DE RIESGOS PROFESIONALES ARP', FALSE, 'Aportes ARP', '2370', FALSE, TRUE, FALSE),
(6, '237010', 'APORTES AL I.C.B.F., SENA Y CAJAS DE COMPENSACION', FALSE, 'Aportes ICBF SENA CCF', '2370', FALSE, TRUE, FALSE),
(6, '237015', 'APORTES AL F.I.C.', FALSE, 'Aportes FIC', '2370', FALSE, TRUE, FALSE),
(6, '237025', 'EMBARGOS JUDICIALES', FALSE, 'Embargos judiciales', '2370', FALSE, TRUE, FALSE),
(6, '237030', 'LIBRANZAS', FALSE, 'Libranzas', '2370', FALSE, TRUE, FALSE),
(6, '237035', 'SINDICATOS', FALSE, 'Sindicatos', '2370', FALSE, TRUE, FALSE),
(6, '237040', 'COOPERATIVAS', FALSE, 'Cooperativas', '2370', FALSE, TRUE, FALSE),
(6, '237045', 'FONDOS', FALSE, 'Fondos', '2370', FALSE, TRUE, FALSE),
(6, '237095', 'OTROS', FALSE, 'Otras retenciones nómina', '2370', FALSE, TRUE, FALSE);

-- Subcuentas 2375
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '237501', 'CUOTAS POR DEVOLVER 237501 A 237598', FALSE, 'Cuotas devolver rango', '2375', FALSE, TRUE, FALSE),
(6, '237598', 'CUOTAS POR DEVOLVER FIN RANGO', FALSE, 'Cuotas devolver fin', '2375', FALSE, TRUE, FALSE);

-- Subcuentas 2380
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '238005', 'DEPOSITARIOS', FALSE, 'Depositarios', '2380', FALSE, TRUE, FALSE),
(6, '238010', 'COMISIONISTAS DE BOLSAS', FALSE, 'Comisionistas bolsas', '2380', FALSE, TRUE, FALSE),
(6, '238015', 'SOCIEDAD ADMINISTRADORA - FONDOS DE INVERSION', FALSE, 'Fondos inversión', '2380', FALSE, TRUE, FALSE),
(6, '238020', 'REINTEGROS POR PAGAR', FALSE, 'Reintegros por pagar', '2380', FALSE, TRUE, FALSE),
(6, '238025', 'FONDO DE PERSEVERANCIA', FALSE, 'Fondo perseverancia', '2380', FALSE, TRUE, FALSE),
(6, '238030', 'FONDOS DE CESANTIAS Y/O PENSIONES', FALSE, 'Fondos cesantías', '2380', FALSE, TRUE, FALSE),
(6, '238035', 'DONACIONES ASIGNADAS POR PAGAR', FALSE, 'Donaciones por pagar', '2380', FALSE, TRUE, FALSE),
(6, '238095', 'OTROS', FALSE, 'Otros acreedores', '2380', FALSE, TRUE, FALSE);

-- ============================================================
-- VERIFICACIÓN
-- ============================================================
-- Ejecuta esto para verificar:
-- SELECT COUNT(*) FROM tab_puc;
-- SELECT id_nivel, COUNT(*) FROM tab_puc GROUP BY id_nivel ORDER BY id_nivel;


-- ================================================================
-- PUC COLOMBIA - DECRETO 2650 DE 1993
-- ENTREGA 3: Clase 2 (24-29) + Clase 3 (Patrimonio)
-- ================================================================

-- ============================================================
-- GRUPO 24 — IMPUESTOS, GRAVAMENES Y TASAS
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '24', 'IMPUESTOS, GRAVAMENES Y TASAS', FALSE, 'Gravámenes de carácter general y obligatorios a favor del Estado', '2', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '2404', 'DE RENTA Y COMPLEMENTARIOS', FALSE, 'Impuesto de renta y complementarios', '24', FALSE, TRUE, FALSE),
(4, '2408', 'IMPUESTO SOBRE LAS VENTAS POR PAGAR', FALSE, 'IVA por pagar', '24', FALSE, TRUE, FALSE),
(4, '2412', 'DE INDUSTRIA Y COMERCIO', FALSE, 'Impuesto de industria y comercio', '24', FALSE, TRUE, FALSE),
(4, '2416', 'A LA PROPIEDAD RAIZ', FALSE, 'Impuesto predial', '24', FALSE, TRUE, FALSE),
(4, '2420', 'DERECHOS SOBRE INSTRUMENTOS PUBLICOS', FALSE, 'Derechos sobre instrumentos públicos', '24', FALSE, TRUE, FALSE),
(4, '2424', 'DE VALORIZACION', FALSE, 'Impuesto de valorización', '24', FALSE, TRUE, FALSE),
(4, '2428', 'DE TURISMO', FALSE, 'Impuesto de turismo', '24', FALSE, TRUE, FALSE),
(4, '2432', 'TASA POR UTILIZACION DE PUERTOS', FALSE, 'Tasas por puertos', '24', FALSE, TRUE, FALSE),
(4, '2436', 'DE VEHICULOS', FALSE, 'Impuesto de vehículos', '24', FALSE, TRUE, FALSE),
(4, '2440', 'DE ESPECTACULOS PUBLICOS', FALSE, 'Impuesto espectáculos públicos', '24', FALSE, TRUE, FALSE),
(4, '2444', 'DE HIDROCARBUROS Y MINAS', FALSE, 'Impuesto hidrocarburos y minas', '24', FALSE, TRUE, FALSE),
(4, '2448', 'REGALIAS E IMPUESTOS A LA PEQUEÑA Y MEDIANA MINERIA', FALSE, 'Regalías minería', '24', FALSE, TRUE, FALSE),
(4, '2452', 'A LAS EXPORTACIONES CAFETERAS', FALSE, 'Impuesto exportaciones cafeteras', '24', FALSE, TRUE, FALSE),
(4, '2456', 'A LAS IMPORTACIONES', FALSE, 'Impuesto a las importaciones', '24', FALSE, TRUE, FALSE),
(4, '2460', 'CUOTAS DE FOMENTO', FALSE, 'Cuotas de fomento', '24', FALSE, TRUE, FALSE),
(4, '2464', 'DE LICORES, CERVEZAS Y CIGARRILLOS', FALSE, 'Impuesto licores y cigarrillos', '24', FALSE, TRUE, FALSE),
(4, '2468', 'AL SACRIFICIO DE GANADO', FALSE, 'Impuesto sacrificio ganado', '24', FALSE, TRUE, FALSE),
(4, '2472', 'AL AZAR Y JUEGOS', FALSE, 'Impuesto azar y juegos', '24', FALSE, TRUE, FALSE),
(4, '2476', 'GRAVAMENES Y REGALIAS POR UTILIZACION DEL SUELO', FALSE, 'Gravámenes utilización suelo', '24', FALSE, TRUE, FALSE),
(4, '2495', 'OTROS', FALSE, 'Otros impuestos', '24', FALSE, TRUE, FALSE);

-- Subcuentas 2404
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '240405', 'VIGENCIA FISCAL CORRIENTE', FALSE, 'Renta vigencia corriente', '2404', FALSE, TRUE, FALSE),
(6, '240410', 'VIGENCIAS FISCALES ANTERIORES', FALSE, 'Renta vigencias anteriores', '2404', FALSE, TRUE, FALSE);

-- Subcuentas 2408
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '240801', 'IMPUESTO SOBRE LAS VENTAS POR PAGAR 240801 A 240898', FALSE, 'IVA por pagar rango', '2408', FALSE, TRUE, FALSE),
(6, '240898', 'IMPUESTO SOBRE LAS VENTAS POR PAGAR FIN RANGO', FALSE, 'IVA por pagar fin', '2408', FALSE, TRUE, FALSE);

-- Subcuentas 2412
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '241205', 'VIGENCIA FISCAL CORRIENTE', FALSE, 'ICA vigencia corriente', '2412', FALSE, TRUE, FALSE),
(6, '241210', 'VIGENCIAS FISCALES ANTERIORES', FALSE, 'ICA vigencias anteriores', '2412', FALSE, TRUE, FALSE);

-- Subcuentas 2416
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '241601', 'A LA PROPIEDAD RAIZ 241601 A 241698', FALSE, 'Predial rango', '2416', FALSE, TRUE, FALSE),
(6, '241698', 'A LA PROPIEDAD RAIZ FIN RANGO', FALSE, 'Predial fin', '2416', FALSE, TRUE, FALSE);

-- Subcuentas 2420
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '242001', 'DERECHOS SOBRE INSTRUMENTOS 242001 A 242098', FALSE, 'Instrumentos rango', '2420', FALSE, TRUE, FALSE),
(6, '242098', 'DERECHOS SOBRE INSTRUMENTOS FIN RANGO', FALSE, 'Instrumentos fin', '2420', FALSE, TRUE, FALSE);

-- Subcuentas 2424
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '242405', 'VIGENCIA FISCAL CORRIENTE', FALSE, 'Valorización corriente', '2424', FALSE, TRUE, FALSE),
(6, '242410', 'VIGENCIAS FISCALES ANTERIORES', FALSE, 'Valorización anteriores', '2424', FALSE, TRUE, FALSE);

-- Subcuentas 2428
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '242801', 'DE TURISMO 242801 A 242898', FALSE, 'Turismo rango', '2428', FALSE, TRUE, FALSE),
(6, '242898', 'DE TURISMO FIN RANGO', FALSE, 'Turismo fin', '2428', FALSE, TRUE, FALSE);

-- Subcuentas 2432
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '243201', 'TASA POR UTILIZACION DE PUERTOS 243201 A 243298', FALSE, 'Puertos rango', '2432', FALSE, TRUE, FALSE),
(6, '243298', 'TASA POR UTILIZACION DE PUERTOS FIN RANGO', FALSE, 'Puertos fin', '2432', FALSE, TRUE, FALSE);

-- Subcuentas 2436
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '243605', 'VIGENCIA FISCAL CORRIENTE', FALSE, 'Vehículos corriente', '2436', FALSE, TRUE, FALSE),
(6, '243610', 'VIGENCIAS FISCALES ANTERIORES', FALSE, 'Vehículos anteriores', '2436', FALSE, TRUE, FALSE);

-- Subcuentas 2440
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '244001', 'DE ESPECTACULOS PUBLICOS 244001 A 244098', FALSE, 'Espectáculos rango', '2440', FALSE, TRUE, FALSE),
(6, '244098', 'DE ESPECTACULOS PUBLICOS FIN RANGO', FALSE, 'Espectáculos fin', '2440', FALSE, TRUE, FALSE);

-- Subcuentas 2444
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '244405', 'DE HIDROCARBUROS', FALSE, 'Hidrocarburos', '2444', FALSE, TRUE, FALSE),
(6, '244410', 'DE MINAS', FALSE, 'Minas', '2444', FALSE, TRUE, FALSE);

-- Subcuentas 2448
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '244801', 'REGALIAS E IMPUESTOS MINERIA 244801 A 244898', FALSE, 'Regalías minería rango', '2448', FALSE, TRUE, FALSE),
(6, '244898', 'REGALIAS E IMPUESTOS MINERIA FIN RANGO', FALSE, 'Regalías minería fin', '2448', FALSE, TRUE, FALSE);

-- Subcuentas 2452
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '245201', 'A LAS EXPORTACIONES CAFETERAS 245201 A 245298', FALSE, 'Exportaciones café rango', '2452', FALSE, TRUE, FALSE),
(6, '245298', 'A LAS EXPORTACIONES CAFETERAS FIN RANGO', FALSE, 'Exportaciones café fin', '2452', FALSE, TRUE, FALSE);

-- Subcuentas 2456
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '245601', 'A LAS IMPORTACIONES 245601 A 245698', FALSE, 'Importaciones rango', '2456', FALSE, TRUE, FALSE),
(6, '245698', 'A LAS IMPORTACIONES FIN RANGO', FALSE, 'Importaciones fin', '2456', FALSE, TRUE, FALSE);

-- Subcuentas 2460
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '246001', 'CUOTAS DE FOMENTO 246001 A 246098', FALSE, 'Cuotas fomento rango', '2460', FALSE, TRUE, FALSE),
(6, '246098', 'CUOTAS DE FOMENTO FIN RANGO', FALSE, 'Cuotas fomento fin', '2460', FALSE, TRUE, FALSE);

-- Subcuentas 2464
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '246405', 'DE LICORES', FALSE, 'Licores', '2464', FALSE, TRUE, FALSE),
(6, '246410', 'DE CERVEZAS', FALSE, 'Cervezas', '2464', FALSE, TRUE, FALSE),
(6, '246415', 'DE CIGARRILLOS', FALSE, 'Cigarrillos', '2464', FALSE, TRUE, FALSE);

-- Subcuentas 2468
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '246801', 'AL SACRIFICIO DE GANADO 246801 A 246898', FALSE, 'Sacrificio ganado rango', '2468', FALSE, TRUE, FALSE),
(6, '246898', 'AL SACRIFICIO DE GANADO FIN RANGO', FALSE, 'Sacrificio ganado fin', '2468', FALSE, TRUE, FALSE);

-- Subcuentas 2472
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '247201', 'AL AZAR Y JUEGOS 247201 A 247298', FALSE, 'Azar y juegos rango', '2472', FALSE, TRUE, FALSE),
(6, '247298', 'AL AZAR Y JUEGOS FIN RANGO', FALSE, 'Azar y juegos fin', '2472', FALSE, TRUE, FALSE);

-- Subcuentas 2476
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '247601', 'GRAVAMENES Y REGALIAS 247601 A 247698', FALSE, 'Gravámenes suelo rango', '2476', FALSE, TRUE, FALSE),
(6, '247698', 'GRAVAMENES Y REGALIAS FIN RANGO', FALSE, 'Gravámenes suelo fin', '2476', FALSE, TRUE, FALSE);

-- Subcuentas 2495
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '249501', 'OTROS IMPUESTOS 249501 A 249598', FALSE, 'Otros impuestos rango', '2495', FALSE, TRUE, FALSE),
(6, '249598', 'OTROS IMPUESTOS FIN RANGO', FALSE, 'Otros impuestos fin', '2495', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 25 — OBLIGACIONES LABORALES
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '25', 'OBLIGACIONES LABORALES', FALSE, 'Pasivos a favor de trabajadores y extrabajadores', '2', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '2505', 'SALARIOS POR PAGAR', FALSE, 'Salarios por pagar', '25', FALSE, TRUE, FALSE),
(4, '2510', 'CESANTIAS CONSOLIDADAS', FALSE, 'Cesantías consolidadas', '25', FALSE, TRUE, FALSE),
(4, '2515', 'INTERESES SOBRE CESANTIAS', FALSE, 'Intereses sobre cesantías', '25', FALSE, TRUE, FALSE),
(4, '2520', 'PRIMA DE SERVICIOS', FALSE, 'Prima de servicios', '25', FALSE, TRUE, FALSE),
(4, '2525', 'VACACIONES CONSOLIDADAS', FALSE, 'Vacaciones consolidadas', '25', FALSE, TRUE, FALSE),
(4, '2530', 'PRESTACIONES EXTRALEGALES', FALSE, 'Prestaciones extralegales', '25', FALSE, TRUE, FALSE),
(4, '2532', 'PENSIONES POR PAGAR', FALSE, 'Pensiones por pagar', '25', FALSE, TRUE, FALSE),
(4, '2535', 'CUOTAS PARTES PENSIONES DE JUBILACION', FALSE, 'Cuotas partes pensiones', '25', FALSE, TRUE, FALSE),
(4, '2540', 'INDEMNIZACIONES LABORALES', FALSE, 'Indemnizaciones laborales', '25', FALSE, TRUE, FALSE);

-- Subcuentas 2505
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '250501', 'SALARIOS POR PAGAR 250501 A 250598', FALSE, 'Salarios rango', '2505', FALSE, TRUE, FALSE),
(6, '250598', 'SALARIOS POR PAGAR FIN RANGO', FALSE, 'Salarios fin', '2505', FALSE, TRUE, FALSE);

-- Subcuentas 2510
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '251005', 'LEY LABORAL ANTERIOR', FALSE, 'Cesantías ley anterior', '2510', FALSE, TRUE, FALSE),
(6, '251010', 'LEY 50 DE 1990 Y NORMAS POSTERIORES', FALSE, 'Cesantías ley 50', '2510', FALSE, TRUE, FALSE);

-- Subcuentas 2515
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '251501', 'INTERESES SOBRE CESANTIAS 251501 A 251598', FALSE, 'Intereses cesantías rango', '2515', FALSE, TRUE, FALSE),
(6, '251598', 'INTERESES SOBRE CESANTIAS FIN RANGO', FALSE, 'Intereses cesantías fin', '2515', FALSE, TRUE, FALSE);

-- Subcuentas 2520
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '252001', 'PRIMA DE SERVICIOS 252001 A 252098', FALSE, 'Prima rango', '2520', FALSE, TRUE, FALSE),
(6, '252098', 'PRIMA DE SERVICIOS FIN RANGO', FALSE, 'Prima fin', '2520', FALSE, TRUE, FALSE);

-- Subcuentas 2525
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '252501', 'VACACIONES CONSOLIDADAS 252501 A 252598', FALSE, 'Vacaciones rango', '2525', FALSE, TRUE, FALSE),
(6, '252598', 'VACACIONES CONSOLIDADAS FIN RANGO', FALSE, 'Vacaciones fin', '2525', FALSE, TRUE, FALSE);

-- Subcuentas 2530
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '253005', 'PRIMAS', FALSE, 'Primas extralegales', '2530', FALSE, TRUE, FALSE),
(6, '253010', 'AUXILIOS', FALSE, 'Auxilios', '2530', FALSE, TRUE, FALSE),
(6, '253015', 'DOTACION Y SUMINISTRO A TRABAJADORES', FALSE, 'Dotación', '2530', FALSE, TRUE, FALSE),
(6, '253020', 'BONIFICACIONES', FALSE, 'Bonificaciones', '2530', FALSE, TRUE, FALSE),
(6, '253025', 'SEGUROS', FALSE, 'Seguros', '2530', FALSE, TRUE, FALSE),
(6, '253095', 'OTRAS', FALSE, 'Otras prestaciones', '2530', FALSE, TRUE, FALSE);

-- Subcuentas 2532
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '253201', 'PENSIONES POR PAGAR 253201 A 253298', FALSE, 'Pensiones rango', '2532', FALSE, TRUE, FALSE),
(6, '253298', 'PENSIONES POR PAGAR FIN RANGO', FALSE, 'Pensiones fin', '2532', FALSE, TRUE, FALSE);

-- Subcuentas 2535
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '253501', 'CUOTAS PARTES PENSIONES 253501 A 253598', FALSE, 'Cuotas pensiones rango', '2535', FALSE, TRUE, FALSE),
(6, '253598', 'CUOTAS PARTES PENSIONES FIN RANGO', FALSE, 'Cuotas pensiones fin', '2535', FALSE, TRUE, FALSE);

-- Subcuentas 2540
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '254001', 'INDEMNIZACIONES LABORALES 254001 A 254098', FALSE, 'Indemnizaciones rango', '2540', FALSE, TRUE, FALSE),
(6, '254098', 'INDEMNIZACIONES LABORALES FIN RANGO', FALSE, 'Indemnizaciones fin', '2540', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 26 — PASIVOS ESTIMADOS Y PROVISIONES
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '26', 'PASIVOS ESTIMADOS Y PROVISIONES', FALSE, 'Valores provisionados por obligaciones para costos y gastos', '2', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '2605', 'PARA COSTOS Y GASTOS', FALSE, 'Provisión para costos y gastos', '26', FALSE, TRUE, FALSE),
(4, '2610', 'PARA OBLIGACIONES LABORALES', FALSE, 'Provisión obligaciones laborales', '26', FALSE, TRUE, FALSE),
(4, '2615', 'PARA OBLIGACIONES FISCALES', FALSE, 'Provisión obligaciones fiscales', '26', FALSE, TRUE, FALSE),
(4, '2620', 'PENSIONES DE JUBILACION', FALSE, 'Pensiones de jubilación', '26', FALSE, TRUE, FALSE),
(4, '2625', 'PARA OBRAS DE URBANISMO', FALSE, 'Provisión obras de urbanismo', '26', FALSE, TRUE, FALSE),
(4, '2630', 'PARA MANTENIMIENTO Y REPARACIONES', FALSE, 'Provisión mantenimiento', '26', FALSE, TRUE, FALSE),
(4, '2635', 'PARA CONTINGENCIAS', FALSE, 'Provisión contingencias', '26', FALSE, TRUE, FALSE),
(4, '2640', 'PARA OBLIGACIONES DE GARANTIAS', FALSE, 'Provisión garantías', '26', FALSE, TRUE, FALSE),
(4, '2695', 'PROVISIONES DIVERSAS', FALSE, 'Provisiones diversas', '26', FALSE, TRUE, FALSE);

-- Subcuentas 2605
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '260505', 'INTERESES', FALSE, 'Provisión intereses', '2605', FALSE, TRUE, FALSE),
(6, '260510', 'COMISIONES', FALSE, 'Provisión comisiones', '2605', FALSE, TRUE, FALSE),
(6, '260515', 'HONORARIOS', FALSE, 'Provisión honorarios', '2605', FALSE, TRUE, FALSE),
(6, '260520', 'SERVICIOS TECNICOS', FALSE, 'Provisión servicios técnicos', '2605', FALSE, TRUE, FALSE),
(6, '260525', 'TRANSPORTES, FLETES Y ACARREOS', FALSE, 'Provisión transportes', '2605', FALSE, TRUE, FALSE),
(6, '260530', 'GASTOS DE VIAJE', FALSE, 'Provisión gastos viaje', '2605', FALSE, TRUE, FALSE),
(6, '260535', 'SERVICIOS PUBLICOS', FALSE, 'Provisión servicios públicos', '2605', FALSE, TRUE, FALSE),
(6, '260540', 'REGALIAS', FALSE, 'Provisión regalías', '2605', FALSE, TRUE, FALSE),
(6, '260545', 'GARANTIAS', FALSE, 'Provisión garantías', '2605', FALSE, TRUE, FALSE),
(6, '260550', 'MATERIALES Y REPUESTOS', FALSE, 'Provisión materiales', '2605', FALSE, TRUE, FALSE),
(6, '260595', 'OTROS', FALSE, 'Otras provisiones', '2605', FALSE, TRUE, FALSE);

-- Subcuentas 2610
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '261005', 'CESANTIAS', FALSE, 'Provisión cesantías', '2610', FALSE, TRUE, FALSE),
(6, '261010', 'INTERESES SOBRE CESANTIAS', FALSE, 'Provisión intereses cesantías', '2610', FALSE, TRUE, FALSE),
(6, '261015', 'VACACIONES', FALSE, 'Provisión vacaciones', '2610', FALSE, TRUE, FALSE),
(6, '261020', 'PRIMA DE SERVICIOS', FALSE, 'Provisión prima', '2610', FALSE, TRUE, FALSE),
(6, '261025', 'PRESTACIONES EXTRALEGALES', FALSE, 'Provisión prestaciones extralegales', '2610', FALSE, TRUE, FALSE),
(6, '261030', 'VIATICOS', FALSE, 'Provisión viáticos', '2610', FALSE, TRUE, FALSE),
(6, '261095', 'OTRAS', FALSE, 'Otras provisiones laborales', '2610', FALSE, TRUE, FALSE);

-- Subcuentas 2615
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '261505', 'DE RENTA Y COMPLEMENTARIOS', FALSE, 'Provisión renta', '2615', FALSE, TRUE, FALSE),
(6, '261510', 'DE INDUSTRIA Y COMERCIO', FALSE, 'Provisión ICA', '2615', FALSE, TRUE, FALSE),
(6, '261515', 'TASA POR UTILIZACION DE PUERTOS', FALSE, 'Provisión puertos', '2615', FALSE, TRUE, FALSE),
(6, '261520', 'DE VEHICULOS', FALSE, 'Provisión vehículos', '2615', FALSE, TRUE, FALSE),
(6, '261525', 'DE HIDROCARBUROS Y MINAS', FALSE, 'Provisión hidrocarburos', '2615', FALSE, TRUE, FALSE),
(6, '261595', 'OTROS', FALSE, 'Otras provisiones fiscales', '2615', FALSE, TRUE, FALSE);

-- Subcuentas 2620
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '262005', 'CALCULO ACTUARIAL PENSIONES DE JUBILACION', FALSE, 'Cálculo actuarial', '2620', FALSE, TRUE, FALSE),
(6, '262010', 'PENSIONES DE JUBILACION POR AMORTIZAR (DB)', TRUE, 'Pensiones por amortizar (débito)', '2620', FALSE, TRUE, FALSE);

-- Subcuentas 2625
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '262505', 'ACUEDUCTO Y ALCANTARILLADO', FALSE, 'Urbanismo acueducto', '2625', FALSE, TRUE, FALSE),
(6, '262510', 'ENERGIA ELECTRICA', FALSE, 'Urbanismo energía', '2625', FALSE, TRUE, FALSE),
(6, '262515', 'TELEFONOS', FALSE, 'Urbanismo teléfonos', '2625', FALSE, TRUE, FALSE),
(6, '262595', 'OTROS', FALSE, 'Otros urbanismo', '2625', FALSE, TRUE, FALSE);

-- Subcuentas 2630
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '263005', 'TERRENOS', FALSE, 'Mantenimiento terrenos', '2630', FALSE, TRUE, FALSE),
(6, '263010', 'CONSTRUCCIONES Y EDIFICACIONES', FALSE, 'Mantenimiento construcciones', '2630', FALSE, TRUE, FALSE),
(6, '263015', 'MAQUINARIA Y EQUIPO', FALSE, 'Mantenimiento maquinaria', '2630', FALSE, TRUE, FALSE),
(6, '263020', 'EQUIPO DE OFICINA', FALSE, 'Mantenimiento equipo oficina', '2630', FALSE, TRUE, FALSE),
(6, '263025', 'EQUIPO DE COMPUTACION Y COMUNICACION', FALSE, 'Mantenimiento cómputo', '2630', FALSE, TRUE, FALSE),
(6, '263030', 'EQUIPO MEDICO - CIENTIFICO', FALSE, 'Mantenimiento médico', '2630', FALSE, TRUE, FALSE),
(6, '263035', 'EQUIPO DE HOTELES Y RESTAURANTES', FALSE, 'Mantenimiento hoteles', '2630', FALSE, TRUE, FALSE),
(6, '263040', 'FLOTA Y EQUIPO DE TRANSPORTE', FALSE, 'Mantenimiento flota', '2630', FALSE, TRUE, FALSE),
(6, '263045', 'FLOTA Y EQUIPO FLUVIAL Y/O MARITIMO', FALSE, 'Mantenimiento fluvial', '2630', FALSE, TRUE, FALSE),
(6, '263050', 'FLOTA Y EQUIPO AEREO', FALSE, 'Mantenimiento aéreo', '2630', FALSE, TRUE, FALSE),
(6, '263055', 'FLOTA Y EQUIPO FERREO', FALSE, 'Mantenimiento férreo', '2630', FALSE, TRUE, FALSE),
(6, '263060', 'ACUEDUCTOS PLANTAS Y REDES', FALSE, 'Mantenimiento acueductos', '2630', FALSE, TRUE, FALSE),
(6, '263065', 'ARMAMENTO DE VIGILANCIA', FALSE, 'Mantenimiento armamento', '2630', FALSE, TRUE, FALSE),
(6, '263070', 'ENVASES Y EMPAQUES', FALSE, 'Mantenimiento envases', '2630', FALSE, TRUE, FALSE),
(6, '263075', 'PLANTACIONES AGRICOLAS Y FORESTALES', FALSE, 'Mantenimiento plantaciones', '2630', FALSE, TRUE, FALSE),
(6, '263080', 'VIAS DE CUMUNICACION', FALSE, 'Mantenimiento vías', '2630', FALSE, TRUE, FALSE),
(6, '263085', 'POZOS ARTESIANOS', FALSE, 'Mantenimiento pozos', '2630', FALSE, TRUE, FALSE),
(6, '263095', 'OTROS', FALSE, 'Otros mantenimientos', '2630', FALSE, TRUE, FALSE);

-- Subcuentas 2635
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '263505', 'MULTAS Y SANCIONES AUTORIDADES ADMINISTRATIVAS', FALSE, 'Multas administrativas', '2635', FALSE, TRUE, FALSE),
(6, '263510', 'INTERESES POR MULTAS Y SANCIONES', FALSE, 'Intereses multas', '2635', FALSE, TRUE, FALSE),
(6, '263515', 'RECLAMOS', FALSE, 'Reclamos', '2635', FALSE, TRUE, FALSE),
(6, '263520', 'LABORALES', FALSE, 'Contingencias laborales', '2635', FALSE, TRUE, FALSE),
(6, '263525', 'CIVILES', FALSE, 'Contingencias civiles', '2635', FALSE, TRUE, FALSE),
(6, '263530', 'PENALES', FALSE, 'Contingencias penales', '2635', FALSE, TRUE, FALSE),
(6, '263535', 'ADMINISTRATIVOS', FALSE, 'Contingencias administrativas', '2635', FALSE, TRUE, FALSE),
(6, '263540', 'COMERCIALES', FALSE, 'Contingencias comerciales', '2635', FALSE, TRUE, FALSE),
(6, '263595', 'OTRAS', FALSE, 'Otras contingencias', '2635', FALSE, TRUE, FALSE);

-- Subcuentas 2640
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '264001', 'PARA OBLIGACIONES DE GARANTIAS 264001 A 264098', FALSE, 'Garantías rango', '2640', FALSE, TRUE, FALSE),
(6, '264098', 'PARA OBLIGACIONES DE GARANTIAS FIN RANGO', FALSE, 'Garantías fin', '2640', FALSE, TRUE, FALSE);

-- Subcuentas 2695
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '269505', 'PARA BENEFICENCIA', FALSE, 'Provisión beneficencia', '2695', FALSE, TRUE, FALSE),
(6, '269510', 'PARA COMUNICACIONES', FALSE, 'Provisión comunicaciones', '2695', FALSE, TRUE, FALSE),
(6, '269515', 'PARA PERDIDA EN TRANSPORTE', FALSE, 'Provisión pérdida transporte', '2695', FALSE, TRUE, FALSE),
(6, '269520', 'PARA OPERACION', FALSE, 'Provisión operación', '2695', FALSE, TRUE, FALSE),
(6, '269525', 'PARA PROTECCION DE BIENES AGOTABLES', FALSE, 'Provisión bienes agotables', '2695', FALSE, TRUE, FALSE),
(6, '269530', 'PARA AJUSTES EN REDENCION DE UNIDADES', FALSE, 'Provisión redención unidades', '2695', FALSE, TRUE, FALSE),
(6, '269535', 'AUTOSEGURO', FALSE, 'Autoseguro', '2695', FALSE, TRUE, FALSE),
(6, '269540', 'PLANES Y PROGRAMAS DE REFORESTACION Y ELECTRIFICACION', FALSE, 'Reforestación', '2695', FALSE, TRUE, FALSE),
(6, '269595', 'OTRAS', FALSE, 'Otras provisiones', '2695', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 27 — DIFERIDOS
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '27', 'DIFERIDOS', FALSE, 'Ingresos no causados recibidos de clientes', '2', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '2705', 'INGRESOS RECIBIDOS POR ANTICIPADO', FALSE, 'Ingresos recibidos por anticipado', '27', FALSE, TRUE, FALSE),
(4, '2710', 'ABONOS DIFERIDOS', FALSE, 'Abonos diferidos', '27', FALSE, TRUE, FALSE),
(4, '2715', 'UTILIDAD DIFERIDA EN VENTAS A PLAZOS', FALSE, 'Utilidad diferida ventas a plazos', '27', FALSE, TRUE, FALSE),
(4, '2720', 'CREDITO POR CORRECCION MONETARIA DIFERIDA', FALSE, 'Crédito por corrección monetaria', '27', FALSE, TRUE, FALSE),
(4, '2725', 'IMPUESTOS DIFERIDOS', FALSE, 'Impuestos diferidos', '27', FALSE, TRUE, FALSE);

-- Subcuentas 2705
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '270505', 'INTERESES', FALSE, 'Intereses anticipados', '2705', FALSE, TRUE, FALSE),
(6, '270510', 'COMISIONES', FALSE, 'Comisiones anticipadas', '2705', FALSE, TRUE, FALSE),
(6, '270515', 'ARRENDAMIENTOS', FALSE, 'Arrendamientos anticipados', '2705', FALSE, TRUE, FALSE),
(6, '270520', 'HONORARIOS', FALSE, 'Honorarios anticipados', '2705', FALSE, TRUE, FALSE),
(6, '270525', 'SERVICIOS TECNICOS', FALSE, 'Servicios técnicos anticipados', '2705', FALSE, TRUE, FALSE),
(6, '270530', 'DE SUSCRIPTORES', FALSE, 'Suscriptores', '2705', FALSE, TRUE, FALSE),
(6, '270535', 'TRANSPORTES, FLETES Y ACARREOS', FALSE, 'Transportes anticipados', '2705', FALSE, TRUE, FALSE),
(6, '270540', 'MERCANCIA EN TRANSITO YA VENDIDA', FALSE, 'Mercancía en tránsito', '2705', FALSE, TRUE, FALSE),
(6, '270545', 'MATRICULAS Y PENSIONES', FALSE, 'Matrículas y pensiones', '2705', FALSE, TRUE, FALSE),
(6, '270550', 'CUOTAS DE ADMINISTRACION', FALSE, 'Cuotas administración', '2705', FALSE, TRUE, FALSE),
(6, '270595', 'OTROS', FALSE, 'Otros ingresos anticipados', '2705', FALSE, TRUE, FALSE);

-- Subcuentas 2710
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '271005', 'REAJUSTE DEL SISTEMA', FALSE, 'Reajuste del sistema', '2710', FALSE, TRUE, FALSE);

-- Subcuentas 2715
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '271501', 'UTILIDAD DIFERIDA VENTAS 271501 A 271598', FALSE, 'Utilidad diferida rango', '2715', FALSE, TRUE, FALSE),
(6, '271598', 'UTILIDAD DIFERIDA VENTAS FIN RANGO', FALSE, 'Utilidad diferida fin', '2715', FALSE, TRUE, FALSE);

-- Subcuentas 2720
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '272001', 'CREDITO CORRECCION MONETARIA 272001 A 272098', FALSE, 'Corrección monetaria rango', '2720', FALSE, TRUE, FALSE),
(6, '272098', 'CREDITO CORRECCION MONETARIA FIN RANGO', FALSE, 'Corrección monetaria fin', '2720', FALSE, TRUE, FALSE);

-- Subcuentas 2725
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '272505', 'POR DEPRECIACION FLEXIBLE', FALSE, 'Impuesto diferido depreciación', '2725', FALSE, TRUE, FALSE),
(6, '272595', 'DIVERSOS', FALSE, 'Impuestos diferidos diversos', '2725', FALSE, TRUE, FALSE),
(6, '272599', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación impuestos diferidos', '2725', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 28 — OTROS PASIVOS
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '28', 'OTROS PASIVOS', FALSE, 'Obligaciones que por su naturaleza especial no se incluyen en otros grupos', '2', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '2805', 'ANTICIPOS Y AVANCES RECIBIDOS', FALSE, 'Anticipos recibidos de clientes', '28', FALSE, TRUE, FALSE),
(4, '2810', 'DEPOSITOS RECIBIDOS', FALSE, 'Depósitos recibidos', '28', FALSE, TRUE, FALSE),
(4, '2815', 'INGRESOS RECIBIDOS PARA TERCEROS', FALSE, 'Ingresos recibidos para terceros', '28', FALSE, TRUE, FALSE),
(4, '2820', 'CUENTAS DE OPERACION CONJUNTA', FALSE, 'Cuentas de operación conjunta', '28', FALSE, TRUE, FALSE),
(4, '2825', 'RETENCIONES A TERCEROS SOBRE CONTRATOS', FALSE, 'Retenciones a terceros', '28', FALSE, TRUE, FALSE),
(4, '2830', 'EMBARGOS JUDICIALES', FALSE, 'Embargos judiciales', '28', FALSE, TRUE, FALSE),
(4, '2835', 'ACREEDORES DEL SISTEMA', FALSE, 'Acreedores del sistema', '28', FALSE, TRUE, FALSE),
(4, '2840', 'CUENTAS EN PARTICIPACION', FALSE, 'Cuentas en participación', '28', FALSE, TRUE, FALSE),
(4, '2895', 'DIVERSOS', FALSE, 'Otros pasivos diversos', '28', FALSE, TRUE, FALSE);

-- Subcuentas 2805
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '280505', 'DE CLIENTES', FALSE, 'Anticipos de clientes', '2805', FALSE, TRUE, FALSE),
(6, '280510', 'SOBRE CONTRATOS', FALSE, 'Anticipos sobre contratos', '2805', FALSE, TRUE, FALSE),
(6, '280515', 'PARA OBRAS EN PROCESO', FALSE, 'Anticipos obras en proceso', '2805', FALSE, TRUE, FALSE),
(6, '280595', 'OTROS', FALSE, 'Otros anticipos', '2805', FALSE, TRUE, FALSE);

-- Subcuentas 2810
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '281005', 'PARA FUTURA SUSCRIPCION DE ACCIONES', FALSE, 'Depósitos suscripción', '2810', FALSE, TRUE, FALSE),
(6, '281010', 'PARA FUTURO PAGO DE CUOTAS O DERECHOS SOCIALES', FALSE, 'Depósitos cuotas sociales', '2810', FALSE, TRUE, FALSE),
(6, '281015', 'PARA GARANTIA EN LA PRESTACION DE SERVICIOS', FALSE, 'Depósitos garantía servicios', '2810', FALSE, TRUE, FALSE),
(6, '281020', 'PARA GARANTIA DE CONTRATOS', FALSE, 'Depósitos garantía contratos', '2810', FALSE, TRUE, FALSE),
(6, '281025', 'DE LICITACIONES', FALSE, 'Depósitos licitaciones', '2810', FALSE, TRUE, FALSE),
(6, '281030', 'DE MANEJO DE BIENES', FALSE, 'Depósitos manejo bienes', '2810', FALSE, TRUE, FALSE),
(6, '281035', 'FONDO DE RESERVA', FALSE, 'Fondo de reserva', '2810', FALSE, TRUE, FALSE),
(6, '281095', 'OTROS', FALSE, 'Otros depósitos', '2810', FALSE, TRUE, FALSE);

-- Subcuentas 2815
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '281505', 'VALORES RECIBIDOS PARA TERCEROS', FALSE, 'Valores recibidos terceros', '2815', FALSE, TRUE, FALSE),
(6, '281510', 'VENTA POR CUENTA DE TERCEROS', FALSE, 'Ventas por cuenta terceros', '2815', FALSE, TRUE, FALSE);

-- Subcuentas 2820
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '282001', 'CUENTAS DE OPERACION CONJUNTA 282001 A 282098', FALSE, 'Operación conjunta rango', '2820', FALSE, TRUE, FALSE),
(6, '282098', 'CUENTAS DE OPERACION CONJUNTA FIN RANGO', FALSE, 'Operación conjunta fin', '2820', FALSE, TRUE, FALSE);

-- Subcuentas 2825
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '282505', 'CUMPLIMIENTO OBLIGACIONES LABORALES', FALSE, 'Cumplimiento obligaciones', '2825', FALSE, TRUE, FALSE),
(6, '282510', 'PARA ESTABILIDAD DE OBRA', FALSE, 'Estabilidad obra', '2825', FALSE, TRUE, FALSE),
(6, '282515', 'GARANTIA CUMPLIMIENTO DE CONTRATOS', FALSE, 'Garantía contratos', '2825', FALSE, TRUE, FALSE);

-- Subcuentas 2830
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '283005', 'INDEMNIZACIONES', FALSE, 'Indemnizaciones', '2830', FALSE, TRUE, FALSE),
(6, '283010', 'DEPOSITOS JUDICIALES', FALSE, 'Depósitos judiciales', '2830', FALSE, TRUE, FALSE);

-- Subcuentas 2835
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '283505', 'CUOTAS NETAS', FALSE, 'Cuotas netas', '2835', FALSE, TRUE, FALSE),
(6, '283510', 'GRUPOS EN FORMACION', FALSE, 'Grupos en formación', '2835', FALSE, TRUE, FALSE);

-- Subcuentas 2840
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '284001', 'CUENTAS EN PARTICIPACION 284001 A 284098', FALSE, 'Cuentas participación rango', '2840', FALSE, TRUE, FALSE),
(6, '284098', 'CUENTAS EN PARTICIPACION FIN RANGO', FALSE, 'Cuentas participación fin', '2840', FALSE, TRUE, FALSE);

-- Subcuentas 2895
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '289505', 'PRESTAMOS DE PRODUCTOS', FALSE, 'Préstamos productos', '2895', FALSE, TRUE, FALSE),
(6, '289510', 'REEMBOLSO DE COSTOS EXPLORATORIOS', FALSE, 'Reembolso costos', '2895', FALSE, TRUE, FALSE),
(6, '289515', 'PROGRAMA DE EXTENSION AGROPECUARIA', FALSE, 'Extensión agropecuaria', '2895', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 29 — BONOS Y PAPELES COMERCIALES
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '29', 'BONOS Y PAPELES COMERCIALES', FALSE, 'Bonos y papeles comerciales emitidos', '2', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '2905', 'BONOS EN CIRCULACION', FALSE, 'Bonos en circulación', '29', FALSE, TRUE, FALSE),
(4, '2910', 'BONOS OBLIGATORIAMENTE CONVERTIBLES EN ACCIONES', FALSE, 'Bonos convertibles', '29', FALSE, TRUE, FALSE),
(4, '2915', 'PAPELES COMERCIALES', FALSE, 'Papeles comerciales', '29', FALSE, TRUE, FALSE),
(4, '2920', 'BONOS PENSIONALES', FALSE, 'Bonos pensionales', '29', FALSE, TRUE, FALSE),
(4, '2925', 'TITULOS PENSIONALES', FALSE, 'Títulos pensionales', '29', FALSE, TRUE, FALSE);

-- Subcuentas 2905
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '290501', 'BONOS EN CIRCULACION 290501 A 290598', FALSE, 'Bonos circulación rango', '2905', FALSE, TRUE, FALSE),
(6, '290598', 'BONOS EN CIRCULACION FIN RANGO', FALSE, 'Bonos circulación fin', '2905', FALSE, TRUE, FALSE);

-- Subcuentas 2910
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '291001', 'BONOS OBLIGATORIAMENTE CONVERTIBLES 291001 A 291098', FALSE, 'Bonos convertibles rango', '2910', FALSE, TRUE, FALSE),
(6, '291098', 'BONOS OBLIGATORIAMENTE CONVERTIBLES FIN RANGO', FALSE, 'Bonos convertibles fin', '2910', FALSE, TRUE, FALSE);

-- Subcuentas 2915
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '291501', 'PAPELES COMERCIALES 291501 A 291598', FALSE, 'Papeles comerciales rango', '2915', FALSE, TRUE, FALSE),
(6, '291598', 'PAPELES COMERCIALES FIN RANGO', FALSE, 'Papeles comerciales fin', '2915', FALSE, TRUE, FALSE);

-- Subcuentas 2920
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '292005', 'VALOR BONOS PENSIONALES', FALSE, 'Valor bonos pensionales', '2920', FALSE, TRUE, FALSE),
(6, '292010', 'BONOS PENSIONALES POR AMORTIZAR (DB)', TRUE, 'Bonos pensionales por amortizar (débito)', '2920', FALSE, TRUE, FALSE),
(6, '292015', 'INTERESES CAUSADOS SOBRE BONOS PENSIONALES', FALSE, 'Intereses bonos pensionales', '2920', FALSE, TRUE, FALSE);

-- Subcuentas 2925
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '292505', 'VALOR TITULOS PENSIONALES', FALSE, 'Valor títulos pensionales', '2925', FALSE, TRUE, FALSE),
(6, '292510', 'TITULOS PENSIONALES POR AMORTIZAR (DB)', TRUE, 'Títulos por amortizar (débito)', '2925', FALSE, TRUE, FALSE),
(6, '292515', 'INTERESES CAUSADOS SOBRE TITULOS PENSIONALES', FALSE, 'Intereses títulos pensionales', '2925', FALSE, TRUE, FALSE);

-- ============================================================
-- CLASE 3: PATRIMONIO (naturaleza CRÉDITO)
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(1, '3', 'PATRIMONIO', FALSE, 'Valor residual de comparar el activo total menos el pasivo externo', '0', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '31', 'CAPITAL SOCIAL', FALSE, 'Aportes de los accionistas, socios o propietarios', '3', FALSE, TRUE, FALSE),
(2, '32', 'SUPERAVIT DE CAPITAL', FALSE, 'Incremento patrimonial por prima en colocación, donaciones, etc', '3', FALSE, TRUE, FALSE),
(2, '33', 'RESERVAS', FALSE, 'Valores apropiados de utilidades por mandato legal o estatutario', '3', FALSE, TRUE, FALSE),
(2, '34', 'REVALORIZACION DEL PATRIMONIO', FALSE, 'Incremento patrimonial por ajustes por inflación y saneamientos', '3', FALSE, TRUE, FALSE),
(2, '35', 'DIVIDENDOS O PARTICIPACIONES DECRETADOS EN ACCIONES O CUOTAS', FALSE, 'Dividendos decretados en acciones o cuotas', '3', FALSE, TRUE, FALSE),
(2, '36', 'RESULTADOS DEL EJERCICIO', FALSE, 'Utilidades o pérdidas del ejercicio', '3', FALSE, TRUE, FALSE),
(2, '37', 'RESULTADOS DE EJERCICIOS ANTERIORES', FALSE, 'Utilidades acumuladas y pérdidas acumuladas', '3', FALSE, TRUE, FALSE),
(2, '38', 'SUPERAVIT POR VALORIZACIONES', FALSE, 'Valorizaciones de inversiones, PPE y otros activos', '3', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 31 — CAPITAL SOCIAL
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '3105', 'CAPITAL SUSCRITO Y PAGADO', FALSE, 'Capital suscrito y pagado', '31', FALSE, TRUE, FALSE),
(4, '3110', 'ACCIONES, CUOTAS O PARTES DE INTERES SOCIAL PROPIAS READQUIRIDAS (DB)', TRUE, 'Acciones propias readquiridas (débito)', '31', FALSE, TRUE, FALSE),
(4, '3115', 'APORTES SOCIALES', FALSE, 'Aportes sociales', '31', FALSE, TRUE, FALSE),
(4, '3120', 'CAPITAL ASIGNADO', FALSE, 'Capital asignado a sucursales', '31', FALSE, TRUE, FALSE),
(4, '3125', 'INVERSION SUPLEMENTARIA AL CAPITAL ASIGNADO', FALSE, 'Inversión suplementaria', '31', FALSE, TRUE, FALSE),
(4, '3130', 'CAPITAL DE PERSONAS NATURALES', FALSE, 'Capital personas naturales', '31', FALSE, TRUE, FALSE),
(4, '3135', 'APORTES DEL ESTADO', FALSE, 'Aportes del Estado', '31', FALSE, TRUE, FALSE),
(4, '3140', 'FONDO SOCIAL', FALSE, 'Fondo social', '31', FALSE, TRUE, FALSE);

-- Subcuentas 3105
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '310505', 'CAPITAL AUTORIZADO', FALSE, 'Capital autorizado', '3105', FALSE, TRUE, FALSE),
(6, '310510', 'CAPITAL POR SUSCRIBIR (DB)', TRUE, 'Capital por suscribir (débito)', '3105', FALSE, TRUE, FALSE),
(6, '310515', 'CAPITAL SUSCRITO POR COBRAR (DB)', TRUE, 'Capital suscrito por cobrar (débito)', '3105', FALSE, TRUE, FALSE);

-- Subcuentas 3110
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '311005', 'ACCIONES PROPIAS READQUIRIDAS (DB)', TRUE, 'Acciones propias readquiridas', '3110', FALSE, TRUE, FALSE),
(6, '311010', 'CUOTAS O PARTES DE INTERES SOCIAL PROPIAS READQUIRIDAS (DB)', TRUE, 'Cuotas propias readquiridas', '3110', FALSE, TRUE, FALSE);

-- Subcuentas 3115
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '311505', 'CUOTAS O PARTES DE INTERES SOCIAL', FALSE, 'Cuotas o partes sociales', '3115', FALSE, TRUE, FALSE),
(6, '311510', 'APORTES DE SOCIOS - FONDO MUTUO DE INVERSION', FALSE, 'Aportes fondo mutuo', '3115', FALSE, TRUE, FALSE),
(6, '311515', 'CONTRIBUCION DE LA EMPRESA - FONDO MUTUO DE INVERSION', FALSE, 'Contribución fondo mutuo', '3115', FALSE, TRUE, FALSE),
(6, '311520', 'SUSCRIPCIONES DEL PUBLICO', FALSE, 'Suscripciones del público', '3115', FALSE, TRUE, FALSE);

-- Subcuentas 3120
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '312001', 'CAPITAL ASIGNADO 312001 A 312098', FALSE, 'Capital asignado rango', '3120', FALSE, TRUE, FALSE),
(6, '312098', 'CAPITAL ASIGNADO FIN RANGO', FALSE, 'Capital asignado fin', '3120', FALSE, TRUE, FALSE);

-- Subcuentas 3125
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '312501', 'INVERSION SUPLEMENTARIA 312501 A 312598', FALSE, 'Inversión suplementaria rango', '3125', FALSE, TRUE, FALSE),
(6, '312598', 'INVERSION SUPLEMENTARIA FIN RANGO', FALSE, 'Inversión suplementaria fin', '3125', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 32 — SUPERAVIT DE CAPITAL
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '3205', 'PRIMA EN COLOCACION DE ACCIONES, CUOTAS O PARTES DE INTERES SOCIAL', FALSE, 'Prima en colocación', '32', FALSE, TRUE, FALSE),
(4, '3210', 'DONACIONES', FALSE, 'Donaciones', '32', FALSE, TRUE, FALSE),
(4, '3215', 'CREDITO MERCANTIL', FALSE, 'Crédito mercantil', '32', FALSE, TRUE, FALSE),
(4, '3220', 'KNOW HOW', FALSE, 'Know How', '32', FALSE, TRUE, FALSE),
(4, '3225', 'SUPERAVIT METODO DE PARTICIPACION', FALSE, 'Superávit método participación', '32', FALSE, TRUE, FALSE);

-- Subcuentas 3205
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '320505', 'PRIMA EN COLOCACION DE ACCIONES', FALSE, 'Prima acciones', '3205', FALSE, TRUE, FALSE),
(6, '320510', 'PRIMA EN COLOCACION DE CUOTAS O PARTES DE INTERES SOCIAL', FALSE, 'Prima cuotas', '3205', FALSE, TRUE, FALSE),
(6, '320515', 'PRIMA EN COLOCACION DE CUOTAS O PARTES DE INTERES SOCIAL', FALSE, 'Prima cuotas 2', '3205', FALSE, TRUE, FALSE);

-- Subcuentas 3210
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '321005', 'EN DINERO', FALSE, 'Donaciones en dinero', '3210', FALSE, TRUE, FALSE),
(6, '321010', 'EN VALORES MOBILIARIOS', FALSE, 'Donaciones valores', '3210', FALSE, TRUE, FALSE),
(6, '321015', 'EN BIENES MUEBLES', FALSE, 'Donaciones muebles', '3210', FALSE, TRUE, FALSE),
(6, '321020', 'EN BIENES INMUEBLES', FALSE, 'Donaciones inmuebles', '3210', FALSE, TRUE, FALSE),
(6, '321025', 'EN INTANGIBLES', FALSE, 'Donaciones intangibles', '3210', FALSE, TRUE, FALSE);

-- Subcuentas 3215
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '321501', 'CREDITO MERCANTIL 321501 A 321598', FALSE, 'Crédito mercantil rango', '3215', FALSE, TRUE, FALSE),
(6, '321598', 'CREDITO MERCANTIL FIN RANGO', FALSE, 'Crédito mercantil fin', '3215', FALSE, TRUE, FALSE);

-- Subcuentas 3220
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '322001', 'KNOW HOW 322001 A 322098', FALSE, 'Know how rango', '3220', FALSE, TRUE, FALSE),
(6, '322098', 'KNOW HOW FIN RANGO', FALSE, 'Know how fin', '3220', FALSE, TRUE, FALSE);

-- Subcuentas 3225
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '322505', 'DE ACCIONES', FALSE, 'Superávit acciones', '3225', FALSE, TRUE, FALSE),
(6, '322510', 'DE CUOTAS O PARTES DE INTERES SOCIAL', FALSE, 'Superávit cuotas', '3225', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 33 — RESERVAS
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '3305', 'RESERVAS OBLIGATORIAS', FALSE, 'Reservas obligatorias', '33', FALSE, TRUE, FALSE),
(4, '3310', 'RESERVAS ESTATUTARIAS', FALSE, 'Reservas estatutarias', '33', FALSE, TRUE, FALSE),
(4, '3315', 'RESERVAS OCASIONALES', FALSE, 'Reservas ocasionales', '33', FALSE, TRUE, FALSE);

-- Subcuentas 3305
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '330505', 'RESERVA LEGAL', FALSE, 'Reserva legal', '3305', FALSE, TRUE, FALSE),
(6, '330510', 'RESERVAS POR DISPOSICIONES FISCALES', FALSE, 'Reservas fiscales', '3305', FALSE, TRUE, FALSE),
(6, '330515', 'RESERVA PARA READQUISICION DE ACCIONES', FALSE, 'Readquisición acciones', '3305', FALSE, TRUE, FALSE),
(6, '330516', 'ACCIONES PROPIAS READQUIRIDAS (DB)', TRUE, 'Acciones propias readquiridas', '3305', FALSE, TRUE, FALSE),
(6, '330517', 'RESERVA PARA READQUISICION DE CUOTAS O PARTES DE INTERES SOCIAL', FALSE, 'Readquisición cuotas', '3305', FALSE, TRUE, FALSE),
(6, '330518', 'CUOTAS O PARTES DE INTERES SOCIAL PROPIAS READQUIRIDAS (DB)', TRUE, 'Cuotas propias readquiridas', '3305', FALSE, TRUE, FALSE),
(6, '330520', 'RESERVA PARA EXTENSION AGROPECUARIA', FALSE, 'Extensión agropecuaria', '3305', FALSE, TRUE, FALSE),
(6, '330525', 'RESERVA LEY 7a. DE 1990', FALSE, 'Reserva ley 7', '3305', FALSE, TRUE, FALSE),
(6, '330530', 'RESERVA PARA REPOSICION DE SEMOVIENTES', FALSE, 'Reposición semovientes', '3305', FALSE, TRUE, FALSE),
(6, '330535', 'RESERVA LEY 4a DE 1980', FALSE, 'Reserva ley 4', '3305', FALSE, TRUE, FALSE),
(6, '330595', 'OTRAS', FALSE, 'Otras reservas obligatorias', '3305', FALSE, TRUE, FALSE);

-- Subcuentas 3310
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '331005', 'PARA FUTURAS CAPITALIZACIONES', FALSE, 'Capitalizaciones', '3310', FALSE, TRUE, FALSE),
(6, '331010', 'PARA REPOSICION DE ACTIVOS', FALSE, 'Reposición activos', '3310', FALSE, TRUE, FALSE),
(6, '331015', 'PARA FUTUROS ENSANCHES', FALSE, 'Futuros ensanches', '3310', FALSE, TRUE, FALSE),
(6, '331095', 'OTRAS', FALSE, 'Otras estatutarias', '3310', FALSE, TRUE, FALSE);

-- Subcuentas 3315
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '331505', 'PARA BENEFICENCIA Y CIVISMO', FALSE, 'Beneficencia', '3315', FALSE, TRUE, FALSE),
(6, '331510', 'PARA FUTURAS CAPITALIZACIONES', FALSE, 'Capitalizaciones ocasional', '3315', FALSE, TRUE, FALSE),
(6, '331515', 'PARA FUTUROS ENSANCHES', FALSE, 'Ensanches ocasional', '3315', FALSE, TRUE, FALSE),
(6, '331520', 'PARA ADQUISICION O REPOSICION DE PROPIEDADES PLANTA Y EQUIPO', FALSE, 'Adquisición PPE', '3315', FALSE, TRUE, FALSE),
(6, '331525', 'PARA INVESTIGACIONES Y DESARROLLO', FALSE, 'Investigación', '3315', FALSE, TRUE, FALSE),
(6, '331530', 'PARA FOMENTO ECONOMICO', FALSE, 'Fomento económico', '3315', FALSE, TRUE, FALSE),
(6, '331535', 'PARA CAPITAL DE TRABAJO', FALSE, 'Capital trabajo', '3315', FALSE, TRUE, FALSE),
(6, '331540', 'PARA ESTABILIZACION DE RENDIMIENTOS', FALSE, 'Estabilización', '3315', FALSE, TRUE, FALSE),
(6, '331545', 'A DISPOSICION DEL MAXIMO ORGANO SOCIAL', FALSE, 'Disposición órgano social', '3315', FALSE, TRUE, FALSE),
(6, '331595', 'OTRAS', FALSE, 'Otras ocasionales', '3315', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 34 — REVALORIZACION DEL PATRIMONIO
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '3405', 'AJUSTES POR INFLACION', FALSE, 'Ajustes por inflación', '34', FALSE, TRUE, FALSE),
(4, '3410', 'SANEAMIENTO FISCAL', FALSE, 'Saneamiento fiscal', '34', FALSE, TRUE, FALSE),
(4, '3415', 'AJUSTES POR INFLACION DECRETO 3019 DE 1989', FALSE, 'Ajustes decreto 3019', '34', FALSE, TRUE, FALSE);

-- Subcuentas 3405
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '340505', 'DE CAPITAL SOCIAL', FALSE, 'Ajuste capital social', '3405', FALSE, TRUE, FALSE),
(6, '340510', 'DE SUPERAVIT DE CAPITAL', FALSE, 'Ajuste superávit capital', '3405', FALSE, TRUE, FALSE),
(6, '340515', 'DE RESERVAS', FALSE, 'Ajuste reservas', '3405', FALSE, TRUE, FALSE),
(6, '340520', 'DE RESULTADOS DE EJERCICIOS ANTERIORES', FALSE, 'Ajuste resultados', '3405', FALSE, TRUE, FALSE),
(6, '340525', 'DE ACTIVOS EN PERIODO IMPRODUCTIVO', FALSE, 'Ajuste activos improductivos', '3405', FALSE, TRUE, FALSE),
(6, '340530', 'DE SANEAMIENTO FISCAL', FALSE, 'Ajuste saneamiento fiscal', '3405', FALSE, TRUE, FALSE),
(6, '340535', 'DE AJUSTES DECRETO 3019 DE 1989', FALSE, 'Ajuste decreto 3019', '3405', FALSE, TRUE, FALSE),
(6, '340540', 'DE DIVIDENDOS Y PARTICIPACIONES DECRETADAS EN ACCIONES, CUOTAS O PARTES DE INTERES SOCIAL', FALSE, 'Dividendos en acciones', '3405', FALSE, TRUE, FALSE),
(6, '340545', 'SUPERAVIT METODO DE PARTICIPACION', FALSE, 'Superávit método participación', '3405', FALSE, TRUE, FALSE);

-- Subcuentas 3410
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '341001', 'SANEAMIENTO FISCAL 341001 A 341098', FALSE, 'Saneamiento rango', '3410', FALSE, TRUE, FALSE),
(6, '341098', 'SANEAMIENTO FISCAL FIN RANGO', FALSE, 'Saneamiento fin', '3410', FALSE, TRUE, FALSE);

-- Subcuentas 3415
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '341501', 'AJUSTES DECRETO 3019 341501 A 341598', FALSE, 'Decreto 3019 rango', '3415', FALSE, TRUE, FALSE),
(6, '341598', 'AJUSTES DECRETO 3019 FIN RANGO', FALSE, 'Decreto 3019 fin', '3415', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 35 — DIVIDENDOS O PARTICIPACIONES DECRETADOS EN ACCIONES
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '3505', 'DIVIDENDOS DECRETADOS EN ACCIONES', FALSE, 'Dividendos decretados en acciones', '35', FALSE, TRUE, FALSE),
(4, '3510', 'PARTICIONES DECRETADAS EN CUOTAS O PARTES DE INTERES SOCIAL', FALSE, 'Participaciones en cuotas', '35', FALSE, TRUE, FALSE);

-- Subcuentas 3505
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '350501', 'DIVIDENDOS DECRETADOS 350501 A 350598', FALSE, 'Dividendos rango', '3505', FALSE, TRUE, FALSE),
(6, '350598', 'DIVIDENDOS DECRETADOS FIN RANGO', FALSE, 'Dividendos fin', '3505', FALSE, TRUE, FALSE);

-- Subcuentas 3510
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '351001', 'PARTICIPACIONES DECRETADAS 351001 A 351098', FALSE, 'Participaciones rango', '3510', FALSE, TRUE, FALSE),
(6, '351098', 'PARTICIPACIONES DECRETADAS FIN RANGO', FALSE, 'Participaciones fin', '3510', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 36 — RESULTADOS DEL EJERCICIO
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '3605', 'UTILIDAD DEL EJERCICIO', FALSE, 'Utilidad del ejercicio', '36', FALSE, TRUE, FALSE),
(4, '3610', 'PERDIDA DEL EJERCICIO', TRUE, 'Pérdida del ejercicio (débito)', '36', FALSE, TRUE, FALSE);

-- Subcuentas 3605
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '360501', 'UTILIDAD DEL EJERCICIO 360501 A 360598', FALSE, 'Utilidad rango', '3605', FALSE, TRUE, FALSE),
(6, '360598', 'UTILIDAD DEL EJERCICIO FIN RANGO', FALSE, 'Utilidad fin', '3605', FALSE, TRUE, FALSE);

-- Subcuentas 3610
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '361001', 'PERDIDA DEL EJERCICIO 361001 A 361098', TRUE, 'Pérdida rango', '3610', FALSE, TRUE, FALSE),
(6, '361098', 'PERDIDA DEL EJERCICIO FIN RANGO', TRUE, 'Pérdida fin', '3610', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 37 — RESULTADOS DE EJERCICIOS ANTERIORES
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '3705', 'UTILIDADES ACUMULADAS', FALSE, 'Utilidades acumuladas', '37', FALSE, TRUE, FALSE),
(4, '3710', 'PERDIDAS ACUMULADAS', TRUE, 'Pérdidas acumuladas (débito)', '37', FALSE, TRUE, FALSE);

-- Subcuentas 3705
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '370501', 'UTILIDADES ACUMULADAS 370501 A 370598', FALSE, 'Utilidades acumuladas rango', '3705', FALSE, TRUE, FALSE),
(6, '370598', 'UTILIDADES ACUMULADAS FIN RANGO', FALSE, 'Utilidades acumuladas fin', '3705', FALSE, TRUE, FALSE);

-- Subcuentas 3710
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '371001', 'PERDIDAS ACUMULADAS 371001 A 371098', TRUE, 'Pérdidas acumuladas rango', '3710', FALSE, TRUE, FALSE),
(6, '371098', 'PERDIDAS ACUMULADAS FIN RANGO', TRUE, 'Pérdidas acumuladas fin', '3710', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 38 — SUPERAVIT POR VALORIZACIONES
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '3805', 'DE INVERSIONES', FALSE, 'Superávit inversiones', '38', FALSE, TRUE, FALSE),
(4, '3810', 'DE PROPIEDADES PLANTA Y EQUIPO', FALSE, 'Superávit PPE', '38', FALSE, TRUE, FALSE),
(4, '3895', 'DE OTROS ACTIVOS', FALSE, 'Superávit otros activos', '38', FALSE, TRUE, FALSE);

-- Subcuentas 3805
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '380505', 'ACCIONES', FALSE, 'Superávit acciones', '3805', FALSE, TRUE, FALSE),
(6, '380510', 'CUOTAS O PARTES DE INTERES SOCIAL', FALSE, 'Superávit cuotas', '3805', FALSE, TRUE, FALSE),
(6, '380515', 'DERECHOS FIDUCIARIOS', FALSE, 'Superávit fiducias', '3805', FALSE, TRUE, FALSE);

-- Subcuentas 3810
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '381004', 'TERRENOS', FALSE, 'Superávit terrenos', '3810', FALSE, TRUE, FALSE),
(6, '381006', 'MATERIALES PROYECTOS PETROLEROS', FALSE, 'Superávit materiales petroleros', '3810', FALSE, TRUE, FALSE),
(6, '381008', 'CONSTRUCCIONES Y EDIFICACIONES', FALSE, 'Superávit construcciones', '3810', FALSE, TRUE, FALSE),
(6, '381012', 'MAQUINARIA Y EQUIPO', FALSE, 'Superávit maquinaria', '3810', FALSE, TRUE, FALSE),
(6, '381016', 'EQUIPO DE OFICINA', FALSE, 'Superávit equipo oficina', '3810', FALSE, TRUE, FALSE),
(6, '381020', 'EQUIPO DE COMPUTACION Y COMUNICACION', FALSE, 'Superávit cómputo', '3810', FALSE, TRUE, FALSE),
(6, '381024', 'EQUIPO MEDICO CIENTIFICO', FALSE, 'Superávit médico', '3810', FALSE, TRUE, FALSE),
(6, '381028', 'EQUIPO DE HOTELES Y RESTAURANTES', FALSE, 'Superávit hoteles', '3810', FALSE, TRUE, FALSE),
(6, '381032', 'FLOTA Y EQUIPO DE TRANSPORTE', FALSE, 'Superávit flota', '3810', FALSE, TRUE, FALSE),
(6, '381036', 'FLOTA Y EQUIPO FLUVIAL Y/O MARITIMO', FALSE, 'Superávit fluvial', '3810', FALSE, TRUE, FALSE),
(6, '381040', 'FLOTA Y EQUIPO AEREO', FALSE, 'Superávit aéreo', '3810', FALSE, TRUE, FALSE),
(6, '381044', 'FLOTA Y EQUIPO FERREO', FALSE, 'Superávit férreo', '3810', FALSE, TRUE, FALSE),
(6, '381048', 'ACUEDUCTOS PLANTAS Y REDES', FALSE, 'Superávit acueductos', '3810', FALSE, TRUE, FALSE),
(6, '381052', 'ARMAMENTO DE VIGILANCIA', FALSE, 'Superávit armamento', '3810', FALSE, TRUE, FALSE),
(6, '381056', 'ENVASES Y EMPAQUES', FALSE, 'Superávit envases', '3810', FALSE, TRUE, FALSE),
(6, '381060', 'PLANTACIONES AGRICOLAS Y FORESTALES', FALSE, 'Superávit plantaciones', '3810', FALSE, TRUE, FALSE),
(6, '381064', 'VIAS DE COMUNICACION', FALSE, 'Superávit vías', '3810', FALSE, TRUE, FALSE),
(6, '381068', 'MINAS Y CANTERAS', FALSE, 'Superávit minas', '3810', FALSE, TRUE, FALSE),
(6, '381072', 'POZOS ARTESIANOS', FALSE, 'Superávit pozos', '3810', FALSE, TRUE, FALSE),
(6, '381076', 'YACIMIENTOS', FALSE, 'Superávit yacimientos', '3810', FALSE, TRUE, FALSE),
(6, '381080', 'SEMOVIENTES', FALSE, 'Superávit semovientes', '3810', FALSE, TRUE, FALSE);

-- Subcuentas 3895
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '389505', 'BIENES DE ARTE Y CULTURA', FALSE, 'Superávit bienes arte', '3895', FALSE, TRUE, FALSE),
(6, '389510', 'BIENES ENTREGADOS EN COMODATO', FALSE, 'Superávit comodato', '3895', FALSE, TRUE, FALSE),
(6, '389515', 'BIENES RECIBIDOS EN PAGO', FALSE, 'Superávit bienes pago', '3895', FALSE, TRUE, FALSE),
(6, '389520', 'INVENTARIO DE SEMOVIENTES', FALSE, 'Superávit inventario semovientes', '3895', FALSE, TRUE, FALSE);

-- ============================================================
-- VERIFICACIÓN
-- ============================================================
-- SELECT COUNT(*) FROM tab_puc;
-- SELECT id_nivel, COUNT(*) FROM tab_puc GROUP BY id_nivel ORDER BY id_nivel;


-- ================================================================
-- PUC COLOMBIA - DECRETO 2650 DE 1993
-- ENTREGA 4: Clase 4 (INGRESOS)
-- ================================================================

-- ============================================================
-- CLASE 4: INGRESOS (naturaleza CRÉDITO)
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(1, '4', 'INGRESOS', FALSE, 'Beneficios operativos y financieros del ente económico', '0', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 41 — OPERACIONALES
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '41', 'OPERACIONALES', FALSE, 'Ingresos del objeto social principal', '4', FALSE, TRUE, FALSE);

-- Nivel 4
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '4105', 'AGRICULTURA, GANADERIA, CAZA Y SILVICULTURA', FALSE, 'Ingresos agropecuarios', '41', FALSE, TRUE, FALSE),
(4, '4110', 'PESCA', FALSE, 'Ingresos por pesca', '41', FALSE, TRUE, FALSE),
(4, '4115', 'EXPLOTACION DE MINAS Y CANTERAS', FALSE, 'Ingresos por explotación minera', '41', FALSE, TRUE, FALSE),
(4, '4120', 'INDUSTRIAS MANUFACTURERAS', FALSE, 'Ingresos manufactureros', '41', FALSE, TRUE, FALSE),
(4, '4125', 'SUMINISTRO DE ELECTRICIDAD, GAS Y AGUA', FALSE, 'Ingresos servicios públicos', '41', FALSE, TRUE, FALSE),
(4, '4130', 'CONSTRUCCION', FALSE, 'Ingresos por construcción', '41', FALSE, TRUE, FALSE),
(4, '4135', 'COMERCIO AL POR MAYOR Y AL POR MENOR', FALSE, 'Ingresos por comercio', '41', FALSE, TRUE, FALSE),
(4, '4140', 'HOTELES Y RESTAURANTES', FALSE, 'Ingresos hoteleros y restaurantes', '41', FALSE, TRUE, FALSE),
(4, '4145', 'TRANSPORTE, ALMACENAMIENTO Y COMUNICACIONES', FALSE, 'Ingresos por transporte', '41', FALSE, TRUE, FALSE),
(4, '4150', 'ACTIVIDAD FINANCIERA', FALSE, 'Ingresos financieros propios del objeto social', '41', FALSE, TRUE, FALSE),
(4, '4155', 'ACTIVIDADES INMOBILIARIAS, EMPRESARIALES Y DE ALQUILER', FALSE, 'Ingresos inmobiliarios y de alquiler', '41', FALSE, TRUE, FALSE),
(4, '4160', 'ENSEÑANZA', FALSE, 'Ingresos por enseñanza', '41', FALSE, TRUE, FALSE),
(4, '4165', 'SERVICIOS SOCIALES Y DE SALUD', FALSE, 'Ingresos sociales y de salud', '41', FALSE, TRUE, FALSE),
(4, '4170', 'OTRAS ACTIVIDADES DE SERVICIOS COMUNITARIOS, SOCIALES Y PERSONALES', FALSE, 'Otros servicios', '41', FALSE, TRUE, FALSE),
(4, '4175', 'DEVOLUCIONES EN VENTAS (DB)', TRUE, 'Devoluciones en ventas (débito)', '41', FALSE, TRUE, FALSE);

-- Subcuentas 4105
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '410505', 'CULTIVO DE CEREALES', FALSE, 'Cultivo de cereales', '4105', FALSE, TRUE, FALSE),
(6, '410510', 'CULTIVOS DE HORTALIZAS, LEGUMBRES Y PLANTAS ORNAMENTALES', FALSE, 'Hortalizas', '4105', FALSE, TRUE, FALSE),
(6, '410515', 'CULTIVOS DE FRUTAS, NUECES Y PLANTAS AROMATICAS', FALSE, 'Frutas', '4105', FALSE, TRUE, FALSE),
(6, '410520', 'CULTIVO DE CAFE', FALSE, 'Cultivo de café', '4105', FALSE, TRUE, FALSE),
(6, '410525', 'CULTIVO DE FLORES', FALSE, 'Cultivo de flores', '4105', FALSE, TRUE, FALSE),
(6, '410530', 'CULTIVO DE CAÑA DE AZUCAR', FALSE, 'Caña de azúcar', '4105', FALSE, TRUE, FALSE),
(6, '410535', 'CULTIVO DE ALGODON Y PLANTAS PARA MATERIAL TEXTIL', FALSE, 'Algodón', '4105', FALSE, TRUE, FALSE),
(6, '410540', 'CULTIVO DE BANANO', FALSE, 'Banano', '4105', FALSE, TRUE, FALSE),
(6, '410545', 'OTROS CULTIVOS AGRICOLAS', FALSE, 'Otros cultivos', '4105', FALSE, TRUE, FALSE),
(6, '410550', 'CRIA DE OVEJAS, CABRAS, ASNOS, MULAS Y BURDEGANOS', FALSE, 'Cría ovejas', '4105', FALSE, TRUE, FALSE),
(6, '410555', 'CRIA DE GANADO CABALLAR Y VACUNO', FALSE, 'Cría ganado', '4105', FALSE, TRUE, FALSE),
(6, '410560', 'PRODUCCION AVICOLA', FALSE, 'Producción avícola', '4105', FALSE, TRUE, FALSE),
(6, '410565', 'CRIA DE OTROS ANIMALES', FALSE, 'Otras crías', '4105', FALSE, TRUE, FALSE),
(6, '410570', 'SERVICIOS AGRICOLAS Y GANADEROS', FALSE, 'Servicios agropecuarios', '4105', FALSE, TRUE, FALSE),
(6, '410575', 'ACTIVIDAD DE CAZA', FALSE, 'Caza', '4105', FALSE, TRUE, FALSE),
(6, '410580', 'ACTIVIDAD DE SILVICULTURA', FALSE, 'Silvicultura', '4105', FALSE, TRUE, FALSE),
(6, '410595', 'ACTIVIDADES CONEXAS', FALSE, 'Actividades conexas', '4105', FALSE, TRUE, FALSE),
(6, '410599', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación agro', '4105', FALSE, TRUE, FALSE);

-- Subcuentas 4110
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '411005', 'ACTIVIDAD DE PESCA', FALSE, 'Pesca', '4110', FALSE, TRUE, FALSE),
(6, '411010', 'EXPLOTACION DE CRIADEROS DE PECES', FALSE, 'Criaderos', '4110', FALSE, TRUE, FALSE),
(6, '411095', 'ACTIVIDADES CONEXAS', FALSE, 'Actividades conexas pesca', '4110', FALSE, TRUE, FALSE),
(6, '411099', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación pesca', '4110', FALSE, TRUE, FALSE);

-- Subcuentas 4115
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '411505', 'CARBON', FALSE, 'Carbón', '4115', FALSE, TRUE, FALSE),
(6, '411510', 'PETROLEO CRUDO', FALSE, 'Petróleo crudo', '4115', FALSE, TRUE, FALSE),
(6, '411512', 'GAS NATURAL', FALSE, 'Gas natural', '4115', FALSE, TRUE, FALSE),
(6, '411514', 'SERVICIOS RELACIONADOS CON EXTRACCION DE PETROLEO Y GAS', FALSE, 'Servicios extracción', '4115', FALSE, TRUE, FALSE),
(6, '411515', 'MINERALES DE HIERRO', FALSE, 'Minerales hierro', '4115', FALSE, TRUE, FALSE),
(6, '411520', 'MINERALES METALIFEROS NO FERROSOS', FALSE, 'Minerales no ferrosos', '4115', FALSE, TRUE, FALSE),
(6, '411525', 'PIEDRA, ARENA Y ARCILLA', FALSE, 'Piedra y arena', '4115', FALSE, TRUE, FALSE),
(6, '411527', 'PIEDRAS PRECIOSAS', FALSE, 'Piedras preciosas', '4115', FALSE, TRUE, FALSE),
(6, '411528', 'ORO', FALSE, 'Oro', '4115', FALSE, TRUE, FALSE),
(6, '411530', 'OTRAS MINAS Y CANTERAS', FALSE, 'Otras minas', '4115', FALSE, TRUE, FALSE),
(6, '411532', 'PRESTACION DE SERVICIOS SECTOR MINERO', FALSE, 'Servicios mineros', '4115', FALSE, TRUE, FALSE),
(6, '411595', 'ACTIVIDADES CONEXAS', FALSE, 'Actividades conexas', '4115', FALSE, TRUE, FALSE),
(6, '411599', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación minas', '4115', FALSE, TRUE, FALSE);

-- Subcuentas 4120
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '412001', 'PRODUCCION Y PROCESAMIENTO DE CARNES Y PRODUCTOS CARNICOS', FALSE, 'Carnes', '4120', FALSE, TRUE, FALSE),
(6, '412002', 'PRODUCTOS DE PESCADO', FALSE, 'Productos pescado', '4120', FALSE, TRUE, FALSE),
(6, '412003', 'PRODUCTOS DE FRUTAS, LEGUMBRES Y HORTALIZAS', FALSE, 'Frutas y hortalizas', '4120', FALSE, TRUE, FALSE),
(6, '412004', 'ELABORACION DE ACEITES Y GRASAS', FALSE, 'Aceites y grasas', '4120', FALSE, TRUE, FALSE),
(6, '412005', 'ELABORACION DE PRODUCTOS LACTEOS', FALSE, 'Lácteos', '4120', FALSE, TRUE, FALSE),
(6, '412006', 'ELABORACION DE PRODUCTOS DE MOLINERIA', FALSE, 'Molineria', '4120', FALSE, TRUE, FALSE),
(6, '412007', 'ELABORACION DE ALMIDONES Y DERIVADOS', FALSE, 'Almidones', '4120', FALSE, TRUE, FALSE),
(6, '412008', 'ELABORACION DE ALIMENTOS PARA ANIMALES', FALSE, 'Alimentos animales', '4120', FALSE, TRUE, FALSE),
(6, '412009', 'ELABORACION DE PRODUCTOS PARA PANADERIA', FALSE, 'Panadería', '4120', FALSE, TRUE, FALSE),
(6, '412010', 'ELABORACION DE AZUCAR Y MELAZAS', FALSE, 'Azúcar', '4120', FALSE, TRUE, FALSE),
(6, '412011', 'ELABORACION DE CACAO, CHOCOLATE Y CONFITERIA', FALSE, 'Cacao', '4120', FALSE, TRUE, FALSE),
(6, '412012', 'ELABORACION DE PASTAS Y PRODUCTOS FARINACEOS', FALSE, 'Pastas', '4120', FALSE, TRUE, FALSE),
(6, '412013', 'ELABORACION DE PRODUCTOS DE CAFE', FALSE, 'Productos café', '4120', FALSE, TRUE, FALSE),
(6, '412014', 'ELABORACION DE OTROS PRODUCTOS ALIMENTICIOS', FALSE, 'Otros alimentos', '4120', FALSE, TRUE, FALSE),
(6, '412015', 'ELABORACION DE BEBIDAS ALCOHOLICAS Y ALCOHOL ETILICO', FALSE, 'Bebidas alcohólicas', '4120', FALSE, TRUE, FALSE),
(6, '412016', 'ELABORACION DE VINOS', FALSE, 'Vinos', '4120', FALSE, TRUE, FALSE),
(6, '412017', 'ELABORACION DE BEBIDAS MALTEADAS Y DE MALTA', FALSE, 'Bebidas malteadas', '4120', FALSE, TRUE, FALSE),
(6, '412018', 'ELABORACION DE BEBIDAS NO ALCOHOLICAS', FALSE, 'Bebidas no alcohólicas', '4120', FALSE, TRUE, FALSE),
(6, '412019', 'ELABORACION DE PRODUCTOS DE TABACO', FALSE, 'Tabaco', '4120', FALSE, TRUE, FALSE),
(6, '412020', 'PREPARACION E HILATURA DE FIBRAS TEXTILES Y TEJEDURIA', FALSE, 'Fibras textiles', '4120', FALSE, TRUE, FALSE),
(6, '412021', 'ACABADO DE PRODUCTOS TEXTILES', FALSE, 'Acabado textiles', '4120', FALSE, TRUE, FALSE),
(6, '412022', 'ELABORACION DE ARTICULOS DE MATERIALES TEXTILES', FALSE, 'Artículos textiles', '4120', FALSE, TRUE, FALSE),
(6, '412023', 'ELABORACION DE TAPICES Y ALFOMBRAS', FALSE, 'Tapices', '4120', FALSE, TRUE, FALSE),
(6, '412024', 'ELABORACION DE CUERDAS, CORDELES, BRAMANTES Y REDES', FALSE, 'Cuerdas', '4120', FALSE, TRUE, FALSE),
(6, '412025', 'ELABORACION DE OTROS PRODUCTOS TEXTILES', FALSE, 'Otros textiles', '4120', FALSE, TRUE, FALSE),
(6, '412026', 'ELABORACION DE TEJIDOS', FALSE, 'Tejidos', '4120', FALSE, TRUE, FALSE),
(6, '412027', 'ELABORACION DE PRENDAS DE VESTIR', FALSE, 'Prendas vestir', '4120', FALSE, TRUE, FALSE),
(6, '412028', 'PREPARACION, ADOBO Y TEÑIDO DE PIELES', FALSE, 'Pieles', '4120', FALSE, TRUE, FALSE),
(6, '412029', 'CURTIDO, ADOBO O PREPARACION DE CUERO', FALSE, 'Cuero', '4120', FALSE, TRUE, FALSE),
(6, '412030', 'ELABORACION DE MALETAS, BOLSOS Y SIMILARES', FALSE, 'Maletas', '4120', FALSE, TRUE, FALSE),
(6, '412031', 'ELABORACION DE CALZADO', FALSE, 'Calzado', '4120', FALSE, TRUE, FALSE),
(6, '412032', 'PRODUCCION DE MADERA, ARTICULOS DE MADERA Y CORCHO', FALSE, 'Madera', '4120', FALSE, TRUE, FALSE),
(6, '412033', 'ELABORACION DE PASTA Y PRODUCTOS DE MADERA, PAPEL Y CARTON', FALSE, 'Papel y cartón', '4120', FALSE, TRUE, FALSE),
(6, '412034', 'EDICIONES Y PUBLICACIONES', FALSE, 'Ediciones', '4120', FALSE, TRUE, FALSE),
(6, '412035', 'IMPRESION', FALSE, 'Impresión', '4120', FALSE, TRUE, FALSE),
(6, '412036', 'SERVICIOS RELACIONADOS CON LA EDICION Y LA IMPRESION', FALSE, 'Servicios edición', '4120', FALSE, TRUE, FALSE),
(6, '412037', 'REPRODUCCION DE GRABACIONES', FALSE, 'Reproducción grabaciones', '4120', FALSE, TRUE, FALSE),
(6, '412038', 'ELABORACION DE PRODUCTOS DE HORNO DE COQUE', FALSE, 'Coque', '4120', FALSE, TRUE, FALSE),
(6, '412039', 'ELABORACION DE PRODUCTOS DE LA REFINACION DE PETROLEO', FALSE, 'Refinación petróleo', '4120', FALSE, TRUE, FALSE),
(6, '412040', 'ELABORACION DE SUSTANCIAS QUIMICAS BASICAS', FALSE, 'Químicas básicas', '4120', FALSE, TRUE, FALSE),
(6, '412041', 'ELABORACION DE ABONOS Y COMPUESTOS DE NITROGENO', FALSE, 'Abonos', '4120', FALSE, TRUE, FALSE),
(6, '412042', 'ELABORACION DE PLASTICO Y CAUCHO SINTETICO', FALSE, 'Plástico', '4120', FALSE, TRUE, FALSE),
(6, '412043', 'ELABORACION DE PRODUCTOS QUIMICOS DE USO AGROPECUARIO', FALSE, 'Químicos agro', '4120', FALSE, TRUE, FALSE),
(6, '412044', 'ELABORACION DE PINTURAS, TINTAS Y MASILLAS', FALSE, 'Pinturas', '4120', FALSE, TRUE, FALSE),
(6, '412045', 'ELABORACION DE PRODUCTOS FARMACEUTICOS Y BOTANICOS', FALSE, 'Farmacéuticos', '4120', FALSE, TRUE, FALSE),
(6, '412046', 'ELABORACION DE JABONES, DETERGENTES Y PREPARADOS DE TOCADOR', FALSE, 'Jabones', '4120', FALSE, TRUE, FALSE),
(6, '412047', 'ELABORACION DE OTROS PRODUCTOS QUIMICOS', FALSE, 'Otros químicos', '4120', FALSE, TRUE, FALSE),
(6, '412048', 'ELABORACION DE FIBRAS', FALSE, 'Fibras', '4120', FALSE, TRUE, FALSE),
(6, '412049', 'ELABORACION DE OTROS PRODUCTOS DE CAUCHO', FALSE, 'Caucho', '4120', FALSE, TRUE, FALSE),
(6, '412050', 'ELABORACION DE PRODUCTOS DE PLASTICO', FALSE, 'Productos plástico', '4120', FALSE, TRUE, FALSE),
(6, '412051', 'ELABORACION DE VIDRIO Y PRODUCTOS DE VIDRIO', FALSE, 'Vidrio', '4120', FALSE, TRUE, FALSE),
(6, '412052', 'ELABORACION DE PRODUCTOS DE CERAMICA, LOZA, PIEDRA, ARCILLA Y PORCELANA', FALSE, 'Cerámica', '4120', FALSE, TRUE, FALSE),
(6, '412053', 'ELABORACION DE CEMENTO, CAL Y YESO', FALSE, 'Cemento', '4120', FALSE, TRUE, FALSE),
(6, '412054', 'ELABORACION DE ARTICULOS DE HORMIGON, CEMENTO Y YESO', FALSE, 'Artículos cemento', '4120', FALSE, TRUE, FALSE),
(6, '412055', 'CORTE, TALLADO Y ACABADO DE LA PIEDRA', FALSE, 'Piedra', '4120', FALSE, TRUE, FALSE),
(6, '412056', 'ELABORACION DE OTROS PRODUCTOS MINERALES NO METALICOS', FALSE, 'Otros minerales', '4120', FALSE, TRUE, FALSE),
(6, '412057', 'INDUSTRIAS BASICAS Y FUNDICION DE HIERRO Y ACERO', FALSE, 'Hierro y acero', '4120', FALSE, TRUE, FALSE),
(6, '412058', 'PRODUCTOS PRIMARIOS DE METALES PRECIOSOS Y DE METALES NO FERROSOS', FALSE, 'Metales preciosos', '4120', FALSE, TRUE, FALSE),
(6, '412059', 'FUNDICION DE METALES NO FERROSOS', FALSE, 'Fundición', '4120', FALSE, TRUE, FALSE),
(6, '412060', 'FABRICACION DE PRODUCTOS METALICOS PARA USO ESTRUCTURAL', FALSE, 'Metálicos estructural', '4120', FALSE, TRUE, FALSE),
(6, '412061', 'FORJA, PRENSADO, ESTAMPADO, LAMINADO DE METAL Y PULVIMETALURGIA', FALSE, 'Forja', '4120', FALSE, TRUE, FALSE),
(6, '412062', 'REVESTIMIENTO DE METALES Y OBRAS DE INGENIERIA MECANICA', FALSE, 'Revestimiento metales', '4120', FALSE, TRUE, FALSE),
(6, '412063', 'FABRICACION DE ARTICULOS DE FERRETERIA', FALSE, 'Ferretería', '4120', FALSE, TRUE, FALSE),
(6, '412064', 'ELABORACION DE OTROS PRODUCTOS DE METAL', FALSE, 'Otros metálicos', '4120', FALSE, TRUE, FALSE),
(6, '412065', 'FABRICACION DE MAQUINARIA Y EQUIPO', FALSE, 'Maquinaria', '4120', FALSE, TRUE, FALSE),
(6, '412066', 'FABRICACION DE EQUIPOS DE ELEVACION Y MANIPULACION', FALSE, 'Elevación', '4120', FALSE, TRUE, FALSE),
(6, '412067', 'ELABORACION DE APARATOS DE USO DOMESTICO', FALSE, 'Aparatos domésticos', '4120', FALSE, TRUE, FALSE),
(6, '412068', 'ELABORACION DE EQUIPO DE OFICINA', FALSE, 'Equipo oficina', '4120', FALSE, TRUE, FALSE),
(6, '412069', 'ELABORACION DE PILAS Y BATERIAS PRIMARIAS', FALSE, 'Pilas', '4120', FALSE, TRUE, FALSE),
(6, '412070', 'ELABORACION DE EQUIPO DE ILUMINACION', FALSE, 'Iluminación', '4120', FALSE, TRUE, FALSE),
(6, '412071', 'ELABORACION DE OTROS TIPOS DE EQUIPO ELECTRICO', FALSE, 'Equipo eléctrico', '4120', FALSE, TRUE, FALSE),
(6, '412072', 'FABRICACION DE EQUIPOS DE RADIO, TELEVISION Y COMUNICACIONES', FALSE, 'Radio y TV', '4120', FALSE, TRUE, FALSE),
(6, '412073', 'FABRICACION DE APARATOS E INSTRUMENTOS MEDICOS', FALSE, 'Aparatos médicos', '4120', FALSE, TRUE, FALSE),
(6, '412074', 'FABRICACION DE INSTRUMENTOS DE MEDICION Y CONTROL', FALSE, 'Medición', '4120', FALSE, TRUE, FALSE),
(6, '412075', 'FABRICACION DE INSTRUMENTOS DE OPTICA Y EQUIPO FOTOGRAFICO', FALSE, 'Óptica', '4120', FALSE, TRUE, FALSE),
(6, '412076', 'FABRICACION DE RELOJES', FALSE, 'Relojes', '4120', FALSE, TRUE, FALSE),
(6, '412077', 'FABRICACION DE VEHICULOS AUTOMOTORES', FALSE, 'Vehículos', '4120', FALSE, TRUE, FALSE),
(6, '412078', 'FABRICACION DE CARROCERIAS PARA AUTOMOTORES', FALSE, 'Carrocerías', '4120', FALSE, TRUE, FALSE),
(6, '412079', 'FABRICACION DE PARTES PIEZAS Y ACCESORIOS PARA AUTOMOTORES', FALSE, 'Partes autos', '4120', FALSE, TRUE, FALSE),
(6, '412080', 'FABRICACION Y REPARACION DE BUQUES Y OTRAS EMBARCACIONES', FALSE, 'Buques', '4120', FALSE, TRUE, FALSE),
(6, '412081', 'FABRICACION DE LOCOMOTORAS Y MATERIAL RODANTE PARA FERROCARRILES', FALSE, 'Locomotoras', '4120', FALSE, TRUE, FALSE),
(6, '412082', 'FABRICACION DE AERONAVES', FALSE, 'Aeronaves', '4120', FALSE, TRUE, FALSE),
(6, '412083', 'FABRICACION DE MOTOCICLETAS', FALSE, 'Motocicletas', '4120', FALSE, TRUE, FALSE),
(6, '412084', 'FABRICACION DE BICICLETAS Y SILLAS DE RUEDAS', FALSE, 'Bicicletas', '4120', FALSE, TRUE, FALSE),
(6, '412085', 'FABRICACION DE OTROS TIPOS DE TRANSPORTE', FALSE, 'Otros transportes', '4120', FALSE, TRUE, FALSE),
(6, '412086', 'FABRICACION DE MUEBLES', FALSE, 'Muebles', '4120', FALSE, TRUE, FALSE),
(6, '412087', 'FABRICACION DE JOYAS Y ARTICULOS CONEXOS', FALSE, 'Joyas', '4120', FALSE, TRUE, FALSE),
(6, '412088', 'FABRICACION DE INSTRUMENTOS DE MUSICA', FALSE, 'Instrumentos musicales', '4120', FALSE, TRUE, FALSE),
(6, '412089', 'FABRICACION DE ARTICULOS Y EQUIPO PARA DEPORTE', FALSE, 'Artículos deporte', '4120', FALSE, TRUE, FALSE),
(6, '412090', 'FABRICACION DE JUEGOS Y JUGUETES', FALSE, 'Juegos y juguetes', '4120', FALSE, TRUE, FALSE),
(6, '412091', 'RECICLAMIENTO DE DESPERDICIOS', FALSE, 'Reciclaje', '4120', FALSE, TRUE, FALSE),
(6, '412095', 'PRODUCTOS DE OTRAS INDUSTRIAS MANUFACTURERAS', FALSE, 'Otras manufacturas', '4120', FALSE, TRUE, FALSE),
(6, '412099', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación manufactura', '4120', FALSE, TRUE, FALSE);

-- Subcuentas 4125
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '412505', 'GENERACION, CAPTACION Y DISTRIBUCION DE ENERGIA ELECTRICA', FALSE, 'Energía eléctrica', '4125', FALSE, TRUE, FALSE),
(6, '412510', 'FABRICACION DE GAS Y DISTRIBUCION DE COMBUSTIBLES GASEOSOS', FALSE, 'Gas', '4125', FALSE, TRUE, FALSE),
(6, '412515', 'CAPTACION, DEPURACION Y DISTRIBUCION DE AGUA', FALSE, 'Agua', '4125', FALSE, TRUE, FALSE),
(6, '412595', 'ACTIVIDADES CONEXAS', FALSE, 'Actividades conexas servicios', '4125', FALSE, TRUE, FALSE),
(6, '412599', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación servicios públicos', '4125', FALSE, TRUE, FALSE);

-- Subcuentas 4130
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '413005', 'PREPARACION DE TERRENOS', FALSE, 'Preparación terrenos', '4130', FALSE, TRUE, FALSE),
(6, '413010', 'CONSTRUCCION DE EDIFICIOS Y OBRAS DE INGENIERIA CIVIL', FALSE, 'Construcción edificios', '4130', FALSE, TRUE, FALSE),
(6, '413015', 'ACONDICIONAMIENTO DE EDIFICIOS', FALSE, 'Acondicionamiento', '4130', FALSE, TRUE, FALSE),
(6, '413020', 'TERMINACION DE EDIFICACIONES', FALSE, 'Terminación', '4130', FALSE, TRUE, FALSE),
(6, '413025', 'ALQUILER DE EQUIPO CON OPERARIOS', FALSE, 'Alquiler equipo', '4130', FALSE, TRUE, FALSE),
(6, '413095', 'ACTIVIDADES CONEXAS', FALSE, 'Actividades conexas construcción', '4130', FALSE, TRUE, FALSE),
(6, '413099', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación construcción', '4130', FALSE, TRUE, FALSE);

-- Subcuentas 4135
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '413502', 'VENTA DE VEHICULOS AUTOMOTORES', FALSE, 'Venta vehículos', '4135', FALSE, TRUE, FALSE),
(6, '413504', 'MANTENIMIENTO, REPARACION Y LAVADO DE VEHICULOS AUTOMOTORES', FALSE, 'Mantenimiento vehículos', '4135', FALSE, TRUE, FALSE),
(6, '413506', 'VENTA DE PARTES, PIEZAS Y ACCESORIOS DE VEHICULOS AUTOMOTORES', FALSE, 'Partes vehículos', '4135', FALSE, TRUE, FALSE),
(6, '413508', 'VENTA DE COMBUSTIBLES SOLIDOS, LIQUIDOS, GASEOSOS', FALSE, 'Combustibles', '4135', FALSE, TRUE, FALSE),
(6, '413510', 'VENTA DE LUBRICANTES, ADITIVOS, LLANTAS Y LUJOS PARA AUTOMOTORES', FALSE, 'Lubricantes', '4135', FALSE, TRUE, FALSE),
(6, '413512', 'VENTA A CAMBIO DE RETRIBUCIÓN O POR CONTRATA', FALSE, 'Venta por contrata', '4135', FALSE, TRUE, FALSE),
(6, '413514', 'VENTA DE INSUMOS, MATERIAS PRIMAS AGROPECUARIAS Y FLORES', FALSE, 'Insumos agro', '4135', FALSE, TRUE, FALSE),
(6, '413516', 'VENTA DE OTROS INSUMOS Y MATERIAS PRIMAS NO AGROPECUARIAS', FALSE, 'Otros insumos', '4135', FALSE, TRUE, FALSE),
(6, '413518', 'VENTA DE ANIMALES VIVOS Y CUEROS', FALSE, 'Animales vivos', '4135', FALSE, TRUE, FALSE),
(6, '413520', 'VENTA DE PRODUCTOS EN ALMACENES NO ESPECIALIZADOS', FALSE, 'Almacenes no especializados', '4135', FALSE, TRUE, FALSE),
(6, '413522', 'VENTA DE PRODUCTOS AGROPECUARIOS', FALSE, 'Productos agro', '4135', FALSE, TRUE, FALSE),
(6, '413524', 'VENTA DE PRODUCTOS TEXTILES, DE VESTIR, DE CUERO Y CALZADO', FALSE, 'Textiles y calzado', '4135', FALSE, TRUE, FALSE),
(6, '413526', 'VENTA DE PAPEL Y CARTON', FALSE, 'Papel y cartón', '4135', FALSE, TRUE, FALSE),
(6, '413528', 'VENTA DE LIBROS, REVISTAS, ELEMENTOS DE PAPELERIA, UTILES Y TEXTOS ESCOLARES', FALSE, 'Libros y papelería', '4135', FALSE, TRUE, FALSE),
(6, '413530', 'VENTA DE JUEGOS, JUGUETES Y ARTICULOS DEPORTIVOS', FALSE, 'Juegos y deportes', '4135', FALSE, TRUE, FALSE),
(6, '413532', 'VENTA DE INSTRUMENTOS QUIRURGICOS Y ORTOPEDICOS', FALSE, 'Instr. quirúrgicos', '4135', FALSE, TRUE, FALSE),
(6, '413534', 'VENTA DE ARTICULOS EN RELOJERIAS Y JOYERIAS', FALSE, 'Relojerías', '4135', FALSE, TRUE, FALSE),
(6, '413536', 'VENTA DE ELECTRODOMESTICOS Y MUEBLES', FALSE, 'Electrodomésticos', '4135', FALSE, TRUE, FALSE),
(6, '413538', 'VENTA DE PRODUCTOS DE ASEO, FARMACEUTICOS, MEDICINALES, Y ARTICULOS DE TOCADOR', FALSE, 'Aseo y farmacia', '4135', FALSE, TRUE, FALSE),
(6, '413540', 'VENTA DE CUBIERTOS, VAJILLAS, CRISTALERIA, PORCELANAS, CERAMICAS Y OTROS ARTICULOS DE USO DOMESTICO', FALSE, 'Vajillas', '4135', FALSE, TRUE, FALSE),
(6, '413542', 'VENTA DE MATERIALES DE CONSTRUCCION, FONTANERIA Y CALEFACCION', FALSE, 'Materiales construcción', '4135', FALSE, TRUE, FALSE),
(6, '413544', 'VENTA DE PINTURAS Y LACAS', FALSE, 'Pinturas', '4135', FALSE, TRUE, FALSE),
(6, '413546', 'VENTA DE PRODUCTOS DE VIDRIOS Y MARQUETERIA', FALSE, 'Vidrios', '4135', FALSE, TRUE, FALSE),
(6, '413548', 'VENTA DE HERRAMIENTAS Y ARTICULOS DE FERRETERIA', FALSE, 'Herramientas', '4135', FALSE, TRUE, FALSE),
(6, '413550', 'VENTA DE QUIMICOS', FALSE, 'Químicos', '4135', FALSE, TRUE, FALSE),
(6, '413552', 'VENTA DE PRODUCTOS INTERMEDIOS, DESPERDICIOS Y DESECHOS', FALSE, 'Desperdicios', '4135', FALSE, TRUE, FALSE),
(6, '413554', 'VENTA DE MAQUINARIA, EQUIPO DE OFICINA Y PROGRAMAS DE COMPUTADOR', FALSE, 'Maquinaria', '4135', FALSE, TRUE, FALSE),
(6, '413556', 'VENTA DE ARTICULOS EN CACHARRERIAS Y MISCELANEAS', FALSE, 'Cacharrerías', '4135', FALSE, TRUE, FALSE),
(6, '413558', 'VENTA DE INSTRUMENTOS MUSICALES', FALSE, 'Instr. musicales', '4135', FALSE, TRUE, FALSE),
(6, '413560', 'VENTA DE ARTICULOS EN CASAS DE EMPEÑO Y PRENDERIAS', FALSE, 'Casas empeño', '4135', FALSE, TRUE, FALSE),
(6, '413562', 'VENTA DE EQUIPO FOTOGRAFICO', FALSE, 'Equipo fotográfico', '4135', FALSE, TRUE, FALSE),
(6, '413564', 'VENTA DE EQUIPO OPTICO Y DE PRECISION', FALSE, 'Equipo óptico', '4135', FALSE, TRUE, FALSE),
(6, '413566', 'VENTA DE EMPAQUES', FALSE, 'Empaques', '4135', FALSE, TRUE, FALSE),
(6, '413568', 'VENTA DE EQUIPO PROFESIONAL Y CIENTIFICO', FALSE, 'Equipo científico', '4135', FALSE, TRUE, FALSE),
(6, '413570', 'VENTA DE LOTERIAS, RIFAS, CHANCE, APUESTAS Y SIMILARES', FALSE, 'Loterías', '4135', FALSE, TRUE, FALSE),
(6, '413572', 'REPARACION DE EFECTOS PERSONALES Y ELECTRODOMESTICOS', FALSE, 'Reparaciones', '4135', FALSE, TRUE, FALSE),
(6, '413595', 'VENTA DE OTROS PRODUCTOS', FALSE, 'Otros productos', '4135', FALSE, TRUE, FALSE),
(6, '413599', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación comercio', '4135', FALSE, TRUE, FALSE);

-- Subcuentas 4140
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '414005', 'HOTELERIA', FALSE, 'Hotelería', '4140', FALSE, TRUE, FALSE),
(6, '414010', 'CAMPAMENTO Y OTROS TIPOS DE HOSPEDAJE', FALSE, 'Campamentos', '4140', FALSE, TRUE, FALSE),
(6, '414015', 'RESTAURANTES', FALSE, 'Restaurantes', '4140', FALSE, TRUE, FALSE),
(6, '414020', 'BARES Y CANTINAS', FALSE, 'Bares y cantinas', '4140', FALSE, TRUE, FALSE),
(6, '414095', 'ACTIVIDADES CONEXAS', FALSE, 'Actividades conexas hotelería', '4140', FALSE, TRUE, FALSE),
(6, '414099', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación hotelería', '4140', FALSE, TRUE, FALSE);

-- Subcuentas 4145
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '414505', 'SERVICIO DE TRANSPORTE POR CARRETERA', FALSE, 'Transporte carretera', '4145', FALSE, TRUE, FALSE),
(6, '414510', 'SERVICIO DE TRANSPORTE POR VIA FERREA', FALSE, 'Transporte férreo', '4145', FALSE, TRUE, FALSE),
(6, '414515', 'SERVICIO DE TRANSPORTE POR VIA ACUATICA', FALSE, 'Transporte acuático', '4145', FALSE, TRUE, FALSE),
(6, '414520', 'SERVICIO DE TRANSPORTE POR VIA AEREA', FALSE, 'Transporte aéreo', '4145', FALSE, TRUE, FALSE),
(6, '414525', 'SERVICIO DE TRANSPORTE POR TUBERIAS', FALSE, 'Transporte tuberías', '4145', FALSE, TRUE, FALSE),
(6, '414530', 'MANIPULACION DE CARGA', FALSE, 'Manipulación carga', '4145', FALSE, TRUE, FALSE),
(6, '414535', 'ALMACENAMIENTO Y DEPOSITO', FALSE, 'Almacenamiento', '4145', FALSE, TRUE, FALSE),
(6, '414540', 'SERVICIOS COMPLEMENTARIOS PARA EL TRANSPORTE', FALSE, 'Servicios transporte', '4145', FALSE, TRUE, FALSE),
(6, '414545', 'AGENCIAS DE VIAJE', FALSE, 'Agencias viaje', '4145', FALSE, TRUE, FALSE),
(6, '414550', 'OTRAS AGENCIAS DE TRANSPORTE', FALSE, 'Otras agencias', '4145', FALSE, TRUE, FALSE),
(6, '414555', 'SERVICIO POSTAL Y DE CORREO', FALSE, 'Servicio postal', '4145', FALSE, TRUE, FALSE),
(6, '414560', 'SERVICIO TELEFONICO', FALSE, 'Telefonía', '4145', FALSE, TRUE, FALSE),
(6, '414565', 'SERVICIO DE TELEGRAFO', FALSE, 'Telégrafo', '4145', FALSE, TRUE, FALSE),
(6, '414570', 'SERVICIO DE TRANSMISION DE DATOS', FALSE, 'Transmisión datos', '4145', FALSE, TRUE, FALSE),
(6, '414575', 'SERVICIO DE RADIO Y TELEVISION POR CABLE', FALSE, 'Radio y TV cable', '4145', FALSE, TRUE, FALSE),
(6, '414580', 'TRANSMISION DE SONIDO E IMAGENES POR CONTRATO', FALSE, 'Transmisión sonido', '4145', FALSE, TRUE, FALSE),
(6, '414595', 'ACTIVIDADES CONEXAS', FALSE, 'Actividades conexas transporte', '4145', FALSE, TRUE, FALSE),
(6, '414599', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación transporte', '4145', FALSE, TRUE, FALSE);

-- Subcuentas 4150
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '415005', 'VENTA DE INVERSIONES', FALSE, 'Venta inversiones', '4150', FALSE, TRUE, FALSE),
(6, '415010', 'DIVIDENDOS DE SOCIEDADES ANONIMAS Y/O ASIMILADAS', FALSE, 'Dividendos S.A.', '4150', FALSE, TRUE, FALSE),
(6, '415015', 'PARTICIPACIONES DE SOCIEDADES LIMITADAS Y/O ASIMILADAS', FALSE, 'Participaciones Ltda', '4150', FALSE, TRUE, FALSE),
(6, '415020', 'INTERESES', FALSE, 'Intereses', '4150', FALSE, TRUE, FALSE),
(6, '415025', 'REAJUSTE MONETARIO - UPAC', FALSE, 'Reajuste UPAC', '4150', FALSE, TRUE, FALSE),
(6, '415030', 'COMISIONES', FALSE, 'Comisiones', '4150', FALSE, TRUE, FALSE),
(6, '415035', 'OPERACIONES DE DESCUENTO', FALSE, 'Descuentos', '4150', FALSE, TRUE, FALSE),
(6, '415040', 'CUOTAS DE INSCRIPCION - CONSORCIOS', FALSE, 'Inscripción consorcios', '4150', FALSE, TRUE, FALSE),
(6, '415045', 'CUOTAS DE ADMINISTRACION - CONSORCIOS', FALSE, 'Administración consorcios', '4150', FALSE, TRUE, FALSE),
(6, '415050', 'REAJUSTE DEL SISTEMA - CONSORCIOS', FALSE, 'Reajuste consorcios', '4150', FALSE, TRUE, FALSE),
(6, '415055', 'ELIMINACION DE SUSCRIPTORES - CONSORCIOS', FALSE, 'Eliminación suscriptores', '4150', FALSE, TRUE, FALSE),
(6, '415060', 'CUOTAS DE INGRESO O RETIRO - SOCIEDAD ADMINISTRADORA', FALSE, 'Cuotas ingreso', '4150', FALSE, TRUE, FALSE),
(6, '415065', 'SERVICIOS A COMISIONISTAS', FALSE, 'Servicios comisionistas', '4150', FALSE, TRUE, FALSE),
(6, '415070', 'INSCRIPCIONES Y CUOTAS', FALSE, 'Inscripciones', '4150', FALSE, TRUE, FALSE),
(6, '415075', 'RECUPERACION DE GARANTIAS', FALSE, 'Recuperación garantías', '4150', FALSE, TRUE, FALSE),
(6, '415080', 'INGRESOS METODO DE PARTICIPACION', FALSE, 'Método participación', '4150', FALSE, TRUE, FALSE),
(6, '415095', 'ACTIVIDADES CONEXAS', FALSE, 'Actividades conexas financieras', '4150', FALSE, TRUE, FALSE),
(6, '415099', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación financiera', '4150', FALSE, TRUE, FALSE);

-- Subcuentas 4155
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '415505', 'ARRENDAMIENTOS DE BIENES INMUEBLES', FALSE, 'Arrendamientos inmuebles', '4155', FALSE, TRUE, FALSE),
(6, '415510', 'INMOBILIARIAS POR RETRIBUCION O CONTRATA', FALSE, 'Inmobiliarias', '4155', FALSE, TRUE, FALSE),
(6, '415515', 'ALQUILER EQUIPO DE TRANSPORTE', FALSE, 'Alquiler transporte', '4155', FALSE, TRUE, FALSE),
(6, '415520', 'ALQUILER MAQUINARIA Y EQUIPO', FALSE, 'Alquiler maquinaria', '4155', FALSE, TRUE, FALSE),
(6, '415525', 'ALQUILER DE EFECTOS PERSONALES Y ENSERES DOMESTICOS', FALSE, 'Alquiler enseres', '4155', FALSE, TRUE, FALSE),
(6, '415530', 'CONSULTORIA EN EQUIPO Y PROGRAMAS DE INFORMATICA', FALSE, 'Consultoría informática', '4155', FALSE, TRUE, FALSE),
(6, '415535', 'PROCESAMIENTO DE DATOS', FALSE, 'Procesamiento datos', '4155', FALSE, TRUE, FALSE),
(6, '415540', 'MANTENIMIENTO Y REPARACION DE MAQUINARIA DE OFICINA', FALSE, 'Mantenimiento oficina', '4155', FALSE, TRUE, FALSE),
(6, '415545', 'INVESTIGACIONES CIENTIFICAS Y DE DESARROLLO', FALSE, 'Investigación', '4155', FALSE, TRUE, FALSE),
(6, '415550', 'ACTIVIDADES EMPRESARIALES DE CONSULTORIA', FALSE, 'Consultoría empresarial', '4155', FALSE, TRUE, FALSE),
(6, '415555', 'PUBLICIDAD', FALSE, 'Publicidad', '4155', FALSE, TRUE, FALSE),
(6, '415560', 'DOTACION DE PERSONAL', FALSE, 'Dotación personal', '4155', FALSE, TRUE, FALSE),
(6, '415565', 'INVESTIGACION Y SEGURIDAD', FALSE, 'Investigación seguridad', '4155', FALSE, TRUE, FALSE),
(6, '415570', 'LIMPIEZA DE INMUEBLES', FALSE, 'Limpieza inmuebles', '4155', FALSE, TRUE, FALSE),
(6, '415575', 'FOTOGRAFIA', FALSE, 'Fotografía', '4155', FALSE, TRUE, FALSE),
(6, '415580', 'ENVASE Y EMPAQUE', FALSE, 'Envase y empaque', '4155', FALSE, TRUE, FALSE),
(6, '415585', 'FOTOCOPIADO', FALSE, 'Fotocopiado', '4155', FALSE, TRUE, FALSE),
(6, '415590', 'MANTENIMIENTO Y REPARACION DE MAQUINARIA Y EQUIPO', FALSE, 'Mantenimiento maquinaria', '4155', FALSE, TRUE, FALSE),
(6, '415595', 'ACTIVIDADES CONEXAS', FALSE, 'Actividades conexas alquiler', '4155', FALSE, TRUE, FALSE),
(6, '415599', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación alquiler', '4155', FALSE, TRUE, FALSE);

-- Subcuentas 4160
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '416005', 'ACTIVIDADES RELACIONADAS CON LA EDUCACION', FALSE, 'Educación', '4160', FALSE, TRUE, FALSE),
(6, '416095', 'ACTIVIDADES CONEXAS', FALSE, 'Actividades conexas educación', '4160', FALSE, TRUE, FALSE),
(6, '416099', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación educación', '4160', FALSE, TRUE, FALSE);

-- Subcuentas 4165
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '416505', 'SERVICIO HOSPITALARIO', FALSE, 'Servicio hospitalario', '4165', FALSE, TRUE, FALSE),
(6, '416510', 'SERVICIO MEDICO', FALSE, 'Servicio médico', '4165', FALSE, TRUE, FALSE),
(6, '416515', 'SERVICIO ODONTOLOGICO', FALSE, 'Servicio odontológico', '4165', FALSE, TRUE, FALSE),
(6, '416520', 'SERVICIO DE LABORATORIO', FALSE, 'Servicio laboratorio', '4165', FALSE, TRUE, FALSE),
(6, '416525', 'ACTIVIDADES VETERINARIAS', FALSE, 'Veterinaria', '4165', FALSE, TRUE, FALSE),
(6, '416530', 'ACTIVIDADES DE SERVICIOS SOCIALES', FALSE, 'Servicios sociales', '4165', FALSE, TRUE, FALSE),
(6, '416595', 'ACTIVIDADES CONEXAS', FALSE, 'Actividades conexas salud', '4165', FALSE, TRUE, FALSE),
(6, '416599', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación salud', '4165', FALSE, TRUE, FALSE);

-- Subcuentas 4170
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '417005', 'ELIMINACION DE DESPERDICIOS Y AGUAS RESIDUALES', FALSE, 'Eliminación desperdicios', '4170', FALSE, TRUE, FALSE),
(6, '417010', 'ACTIVIDADES DE ASOCIACION', FALSE, 'Asociaciones', '4170', FALSE, TRUE, FALSE),
(6, '417015', 'PRODUCCION Y DISTRIBUCION DE FILMES Y VIDEOCINTAS', FALSE, 'Filmes', '4170', FALSE, TRUE, FALSE),
(6, '417020', 'EXHIBICION DE FILMES Y VIDEOCINTAS', FALSE, 'Exhibición filmes', '4170', FALSE, TRUE, FALSE),
(6, '417025', 'ACTIVIDAD DE RADIO Y TELEVISION', FALSE, 'Radio y TV', '4170', FALSE, TRUE, FALSE),
(6, '417030', 'ACTIVIDAD TEATRAL, MUSICAL Y ARTISTICA', FALSE, 'Teatral y artística', '4170', FALSE, TRUE, FALSE),
(6, '417035', 'GRABACION Y PRODUCCION DE DISCOS', FALSE, 'Grabación discos', '4170', FALSE, TRUE, FALSE),
(6, '417040', 'ENTRETENIMIENTO Y ESPARCIMIENTO', FALSE, 'Entretenimiento', '4170', FALSE, TRUE, FALSE),
(6, '417045', 'AGENCIAS DE NOTICIAS', FALSE, 'Agencias noticias', '4170', FALSE, TRUE, FALSE),
(6, '417050', 'LAVANDERIAS Y SIMILARES', FALSE, 'Lavanderías', '4170', FALSE, TRUE, FALSE),
(6, '417055', 'PELUQUERIAS Y SIMILARES', FALSE, 'Peluquerías', '4170', FALSE, TRUE, FALSE),
(6, '417060', 'SERVICIOS FUNERARIOS', FALSE, 'Servicios funerarios', '4170', FALSE, TRUE, FALSE),
(6, '417065', 'ZONAS FRANCAS', FALSE, 'Zonas francas', '4170', FALSE, TRUE, FALSE),
(6, '417095', 'ACTIVIDADES CONEXAS', FALSE, 'Actividades conexas otros', '4170', FALSE, TRUE, FALSE),
(6, '417099', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación otros', '4170', FALSE, TRUE, FALSE);

-- Subcuentas 4175 (Devoluciones en ventas - DÉBITO)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '417501', 'DEVOLUCIONES EN VENTAS 417501 A 417598', TRUE, 'Devoluciones ventas rango', '4175', FALSE, TRUE, FALSE),
(6, '417598', 'DEVOLUCIONES EN VENTAS FIN RANGO', TRUE, 'Devoluciones ventas fin', '4175', FALSE, TRUE, FALSE),
(6, '417599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación devoluciones', '4175', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 42 — NO OPERACIONALES
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '42', 'NO OPERACIONALES', FALSE, 'Ingresos diferentes al objeto social', '4', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '4205', 'OTRAS VENTAS', FALSE, 'Venta ocasional de bienes', '42', FALSE, TRUE, FALSE),
(4, '4210', 'FINANCIEROS', FALSE, 'Ingresos financieros', '42', FALSE, TRUE, FALSE),
(4, '4215', 'DIVIDENDOS Y PARTICIPACIONES', FALSE, 'Dividendos y participaciones', '42', FALSE, TRUE, FALSE),
(4, '4218', 'INGRESOS METODO DE PARTICIPACION', FALSE, 'Ingresos método participación', '42', FALSE, TRUE, FALSE),
(4, '4220', 'ARRENDAMIENTOS', FALSE, 'Arrendamientos no operacionales', '42', FALSE, TRUE, FALSE),
(4, '4225', 'COMISIONES', FALSE, 'Comisiones no operacionales', '42', FALSE, TRUE, FALSE),
(4, '4230', 'HONORARIOS', FALSE, 'Honorarios no operacionales', '42', FALSE, TRUE, FALSE),
(4, '4235', 'SERVICIOS', FALSE, 'Servicios no operacionales', '42', FALSE, TRUE, FALSE),
(4, '4240', 'UTILIDAD EN VENTA DE INVERSIONES', FALSE, 'Utilidad venta inversiones', '42', FALSE, TRUE, FALSE),
(4, '4245', 'UTILIDAD EN VENTA DE PROPIEDADES PLANTA Y EQUIPO', FALSE, 'Utilidad venta PPE', '42', FALSE, TRUE, FALSE),
(4, '4248', 'UTILIDAD EN VENTA DE OTROS BIENES', FALSE, 'Utilidad venta otros bienes', '42', FALSE, TRUE, FALSE),
(4, '4250', 'RECUPERACIONES', FALSE, 'Recuperaciones', '42', FALSE, TRUE, FALSE),
(4, '4255', 'INDEMNIZACIONES', FALSE, 'Indemnizaciones', '42', FALSE, TRUE, FALSE),
(4, '4260', 'PARTICIPACIONES EN CONCESIONES', FALSE, 'Participaciones en concesiones', '42', FALSE, TRUE, FALSE),
(4, '4265', 'INGRESOS DE EJERCICIOS ANTERIORES', FALSE, 'Ingresos ejercicios anteriores', '42', FALSE, TRUE, FALSE),
(4, '4275', 'DEVOLUCIONES EN OTRAS VENTAS (DB)', TRUE, 'Devoluciones otras ventas (débito)', '42', FALSE, TRUE, FALSE),
(4, '4295', 'DIVERSOS', FALSE, 'Ingresos diversos', '42', FALSE, TRUE, FALSE);

-- Subcuentas 4205
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '420505', 'MATERIA PRIMA', FALSE, 'Venta materia prima', '4205', FALSE, TRUE, FALSE),
(6, '420510', 'MATERIAL DE DESECHO', FALSE, 'Venta material desecho', '4205', FALSE, TRUE, FALSE),
(6, '420515', 'MATERIALES VARIOS', FALSE, 'Materiales varios', '4205', FALSE, TRUE, FALSE),
(6, '420520', 'PRODUCTOS DE DIVERSIFICACION', FALSE, 'Diversificación', '4205', FALSE, TRUE, FALSE),
(6, '420525', 'EXCEDENTES DE EXPORTACION', FALSE, 'Excedentes exportación', '4205', FALSE, TRUE, FALSE),
(6, '420530', 'ENVASES Y EMPAQUES', FALSE, 'Envases y empaques', '4205', FALSE, TRUE, FALSE),
(6, '420535', 'PRODUCTOS AGRICOLAS', FALSE, 'Productos agrícolas', '4205', FALSE, TRUE, FALSE),
(6, '420540', 'DE PROPAGANDA', FALSE, 'Material propaganda', '4205', FALSE, TRUE, FALSE),
(6, '420545', 'PRODUCTOS EN REMATE', FALSE, 'Remates', '4205', FALSE, TRUE, FALSE),
(6, '420550', 'COMBUSTIBLES Y LUBRICANTES', FALSE, 'Combustibles', '4205', FALSE, TRUE, FALSE),
(6, '420599', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación otras ventas', '4205', FALSE, TRUE, FALSE);

-- Subcuentas 4210
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '421005', 'INTERESES', FALSE, 'Intereses', '4210', FALSE, TRUE, FALSE),
(6, '421010', 'REAJUSTE MONETARIO - UPAC', FALSE, 'Reajuste UPAC', '4210', FALSE, TRUE, FALSE),
(6, '421015', 'DESCUENTOS AMORTIZADOS', FALSE, 'Descuentos amortizados', '4210', FALSE, TRUE, FALSE),
(6, '421020', 'DIFERENCIA EN CAMBIO', FALSE, 'Diferencia en cambio', '4210', FALSE, TRUE, FALSE),
(6, '421025', 'FINANCIACION VEHICULOS', FALSE, 'Financiación vehículos', '4210', FALSE, TRUE, FALSE),
(6, '421030', 'FINANCIACION SISTEMAS DE VIAJES', FALSE, 'Financiación viajes', '4210', FALSE, TRUE, FALSE),
(6, '421035', 'ACEPTACIONES BANCARIAS', FALSE, 'Aceptaciones bancarias', '4210', FALSE, TRUE, FALSE),
(6, '421040', 'DESCUENTOS COMERCIALES CONDICIONADOS', FALSE, 'Descuentos comerciales', '4210', FALSE, TRUE, FALSE),
(6, '421045', 'DESCUENTOS BANCARIOS', FALSE, 'Descuentos bancarios', '4210', FALSE, TRUE, FALSE),
(6, '421050', 'COMISIONES CHEQUES DE OTRAS PLAZAS', FALSE, 'Comisiones cheques', '4210', FALSE, TRUE, FALSE),
(6, '421055', 'MULTAS Y RECARGOS', FALSE, 'Multas y recargos', '4210', FALSE, TRUE, FALSE),
(6, '421060', 'SANCIONES CHEQUES DEVUELTOS', FALSE, 'Sanciones cheques', '4210', FALSE, TRUE, FALSE),
(6, '421095', 'OTROS', FALSE, 'Otros financieros', '4210', FALSE, TRUE, FALSE),
(6, '421099', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación financieros', '4210', FALSE, TRUE, FALSE);

-- Subcuentas 4215
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '421505', 'DE SOCIEDADES ANONIMAS Y/O ASIMILADAS', FALSE, 'Dividendos S.A.', '4215', FALSE, TRUE, FALSE),
(6, '421510', 'DE SOCIEDADES LIMITADAS Y/O ASIMILADAS', FALSE, 'Dividendos Ltda', '4215', FALSE, TRUE, FALSE),
(6, '421599', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación dividendos', '4215', FALSE, TRUE, FALSE);

-- Subcuentas 4218
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '421805', 'DE SOCIEDADES ANONIMAS Y/O ASIMILADAS', FALSE, 'Método participación S.A.', '4218', FALSE, TRUE, FALSE),
(6, '421810', 'DE SOCIEDADES LIMITADAS Y/O ASIMILADAS', FALSE, 'Método participación Ltda', '4218', FALSE, TRUE, FALSE);

-- Subcuentas 4220
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '422005', 'TERRENOS', FALSE, 'Arrendamiento terrenos', '4220', FALSE, TRUE, FALSE),
(6, '422010', 'CONSTRUCCIONES Y EDIFICIOS', FALSE, 'Arrendamiento construcciones', '4220', FALSE, TRUE, FALSE),
(6, '422015', 'MAQUINARIA Y EQUIPO', FALSE, 'Arrendamiento maquinaria', '4220', FALSE, TRUE, FALSE),
(6, '422020', 'EQUIPO DE OFICINA', FALSE, 'Arrendamiento equipo oficina', '4220', FALSE, TRUE, FALSE),
(6, '422025', 'EQUIPO DE COMPUTACION Y COMUNICACION', FALSE, 'Arrendamiento cómputo', '4220', FALSE, TRUE, FALSE),
(6, '422030', 'EQUIPO MEDICO - CIENTIFICO', FALSE, 'Arrendamiento médico', '4220', FALSE, TRUE, FALSE),
(6, '422035', 'EQUIPO DE HOTELES Y RESTAURANTES', FALSE, 'Arrendamiento hoteles', '4220', FALSE, TRUE, FALSE),
(6, '422040', 'FLOTA Y EQUIPO DE TRANSPORTE', FALSE, 'Arrendamiento flota', '4220', FALSE, TRUE, FALSE),
(6, '422045', 'FLOTA Y EQUIPO FLUVIAL Y/O MARITIMO', FALSE, 'Arrendamiento fluvial', '4220', FALSE, TRUE, FALSE),
(6, '422050', 'FLOTA Y EQUIPO AEREO', FALSE, 'Arrendamiento aéreo', '4220', FALSE, TRUE, FALSE),
(6, '422055', 'FLOTA Y EQUIPO FERREO', FALSE, 'Arrendamiento férreo', '4220', FALSE, TRUE, FALSE),
(6, '422060', 'ACUEDUCTOS PLANTAS Y REDES', FALSE, 'Arrendamiento acueductos', '4220', FALSE, TRUE, FALSE),
(6, '422062', 'ENVASES Y EMPAQUES', FALSE, 'Arrendamiento envases', '4220', FALSE, TRUE, FALSE),
(6, '422065', 'PLANTACIONES AGRICOLAS Y FORESTALES', FALSE, 'Arrendamiento plantaciones', '4220', FALSE, TRUE, FALSE),
(6, '422070', 'AERODROMOS', FALSE, 'Arrendamiento aeródromos', '4220', FALSE, TRUE, FALSE),
(6, '422075', 'SEMOVIENTES', FALSE, 'Arrendamiento semovientes', '4220', FALSE, TRUE, FALSE),
(6, '422099', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación arrendamientos', '4220', FALSE, TRUE, FALSE);

-- Subcuentas 4225
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '422505', 'SOBRE INVERSIONES', FALSE, 'Comisiones inversiones', '4225', FALSE, TRUE, FALSE),
(6, '422510', 'DE CONCESIONARIOS', FALSE, 'Comisiones concesionarios', '4225', FALSE, TRUE, FALSE),
(6, '422515', 'DE ACTIVIDADES FINANCIERAS', FALSE, 'Comisiones financieras', '4225', FALSE, TRUE, FALSE),
(6, '422520', 'POR VENTA DE SERVICIOS DE TALLER', FALSE, 'Comisiones taller', '4225', FALSE, TRUE, FALSE),
(6, '422525', 'POR VENTA DE SEGUROS', FALSE, 'Comisiones seguros', '4225', FALSE, TRUE, FALSE),
(6, '422530', 'POR INGRESOS PARA TERCEROS', FALSE, 'Comisiones terceros', '4225', FALSE, TRUE, FALSE),
(6, '422535', 'POR DISTRIBUCION DE PELICULAS', FALSE, 'Comisiones películas', '4225', FALSE, TRUE, FALSE),
(6, '422540', 'DERECHOS DE AUTOR', FALSE, 'Derechos autor', '4225', FALSE, TRUE, FALSE),
(6, '422545', 'DERECHOS DE PROGRAMACION', FALSE, 'Derechos programación', '4225', FALSE, TRUE, FALSE),
(6, '422599', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación comisiones', '4225', FALSE, TRUE, FALSE);

-- Subcuentas 4230
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '423005', 'ASESORIAS', FALSE, 'Asesorías', '4230', FALSE, TRUE, FALSE),
(6, '423010', 'ASISTENCIA TECNICA', FALSE, 'Asistencia técnica', '4230', FALSE, TRUE, FALSE),
(6, '423015', 'ADMINISTRACION DE VINCULADAS', FALSE, 'Administración vinculadas', '4230', FALSE, TRUE, FALSE),
(6, '423099', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación honorarios', '4230', FALSE, TRUE, FALSE);

-- Subcuentas 4235
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '423505', 'DE BASCULA', FALSE, 'Servicios báscula', '4235', FALSE, TRUE, FALSE),
(6, '423510', 'DE TRANSPORTE', FALSE, 'Servicios transporte', '4235', FALSE, TRUE, FALSE),
(6, '423515', 'DE PRENSA', FALSE, 'Servicios prensa', '4235', FALSE, TRUE, FALSE),
(6, '423520', 'ADMINISTRATIVOS', FALSE, 'Servicios administrativos', '4235', FALSE, TRUE, FALSE),
(6, '423525', 'TECNICOS', FALSE, 'Servicios técnicos', '4235', FALSE, TRUE, FALSE),
(6, '423530', 'DE COMPUTACION', FALSE, 'Servicios computación', '4235', FALSE, TRUE, FALSE),
(6, '423535', 'DE TELEFAX', FALSE, 'Servicios telefax', '4235', FALSE, TRUE, FALSE),
(6, '423540', 'TALLER DE VEHICULOS', FALSE, 'Taller vehículos', '4235', FALSE, TRUE, FALSE),
(6, '423545', 'DE RECEPCION DE AERONAVES', FALSE, 'Recepción aeronaves', '4235', FALSE, TRUE, FALSE),
(6, '423550', 'DE TRANSPORTE PROGRAMA GAS NATURAL', FALSE, 'Transporte gas', '4235', FALSE, TRUE, FALSE),
(6, '423555', 'POR CONTRATOS', FALSE, 'Servicios por contratos', '4235', FALSE, TRUE, FALSE),
(6, '423560', 'DE TRILLLA', FALSE, 'Servicios trilla', '4235', FALSE, TRUE, FALSE),
(6, '423565', 'DE MANTENIMIENTO', FALSE, 'Servicios mantenimiento', '4235', FALSE, TRUE, FALSE),
(6, '423570', 'AL PERSONAL', FALSE, 'Servicios al personal', '4235', FALSE, TRUE, FALSE),
(6, '423575', 'DE CASINO', FALSE, 'Servicios casino', '4235', FALSE, TRUE, FALSE),
(6, '423580', 'FLETES', FALSE, 'Fletes', '4235', FALSE, TRUE, FALSE),
(6, '423585', 'ENTRE COMPANIAS', FALSE, 'Servicios entre compañías', '4235', FALSE, TRUE, FALSE),
(6, '423595', 'OTROS', FALSE, 'Otros servicios', '4235', FALSE, TRUE, FALSE),
(6, '423599', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación servicios', '4235', FALSE, TRUE, FALSE);

-- Subcuentas 4240
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '424005', 'ACCIONES', FALSE, 'Utilidad acciones', '4240', FALSE, TRUE, FALSE),
(6, '424010', 'CUOTAS O PARTES DE INTERES SOCIAL', FALSE, 'Utilidad cuotas', '4240', FALSE, TRUE, FALSE),
(6, '424015', 'BONOS', FALSE, 'Utilidad bonos', '4240', FALSE, TRUE, FALSE),
(6, '424020', 'CEDULAS', FALSE, 'Utilidad cédulas', '4240', FALSE, TRUE, FALSE),
(6, '424025', 'CERTIFICADOS', FALSE, 'Utilidad certificados', '4240', FALSE, TRUE, FALSE),
(6, '424030', 'PAPELES COMERCIALES', FALSE, 'Utilidad papeles', '4240', FALSE, TRUE, FALSE),
(6, '424035', 'TITULOS', FALSE, 'Utilidad títulos', '4240', FALSE, TRUE, FALSE),
(6, '424045', 'DERECHOS FIDUCIARIOS', FALSE, 'Utilidad fiducias', '4240', FALSE, TRUE, FALSE),
(6, '424050', 'OBLIGATORIAS', FALSE, 'Utilidad obligatorias', '4240', FALSE, TRUE, FALSE),
(6, '424095', 'OTRAS', FALSE, 'Utilidad otras inversiones', '4240', FALSE, TRUE, FALSE),
(6, '424099', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación utilidad inversiones', '4240', FALSE, TRUE, FALSE);

-- Subcuentas 4245
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '424504', 'TERRENOS', FALSE, 'Utilidad terrenos', '4245', FALSE, TRUE, FALSE),
(6, '424506', 'MATERIALES INDUSTRIA PETROLERA', FALSE, 'Utilidad materiales petroleros', '4245', FALSE, TRUE, FALSE),
(6, '424508', 'CONSTRUCCIONES EN CURSO', FALSE, 'Utilidad construcciones curso', '4245', FALSE, TRUE, FALSE),
(6, '424512', 'MAQUINARIA EN MONTAJE', FALSE, 'Utilidad maquinaria montaje', '4245', FALSE, TRUE, FALSE),
(6, '424516', 'CONSTRUCCIONES Y EDIFICACIONES', FALSE, 'Utilidad construcciones', '4245', FALSE, TRUE, FALSE),
(6, '424520', 'MAQUINARIA Y EQUIPO', FALSE, 'Utilidad maquinaria', '4245', FALSE, TRUE, FALSE),
(6, '424524', 'EQUIPO DE OFICINA', FALSE, 'Utilidad equipo oficina', '4245', FALSE, TRUE, FALSE),
(6, '424528', 'EQUIPO DE COMPUTACION Y COMUNICACION', FALSE, 'Utilidad cómputo', '4245', FALSE, TRUE, FALSE),
(6, '424532', 'EQUIPO MEDICO - CIENTIFICO', FALSE, 'Utilidad médico', '4245', FALSE, TRUE, FALSE),
(6, '424536', 'EQUIPO DE HOTELES Y RESTAURANTES', FALSE, 'Utilidad hoteles', '4245', FALSE, TRUE, FALSE),
(6, '424540', 'FLOTA Y EQUIPO DE TRANSPORTE', FALSE, 'Utilidad flota', '4245', FALSE, TRUE, FALSE),
(6, '424544', 'FLOTA Y EQUIPO FLUVIAL Y/O MARITIMO', FALSE, 'Utilidad fluvial', '4245', FALSE, TRUE, FALSE),
(6, '424548', 'FLOTA Y EQUIPO AEREO', FALSE, 'Utilidad aéreo', '4245', FALSE, TRUE, FALSE),
(6, '424552', 'FLOTA Y EQUIPO FERREO', FALSE, 'Utilidad férreo', '4245', FALSE, TRUE, FALSE),
(6, '424556', 'ACUEDUCTOS PLANTAS Y REDES', FALSE, 'Utilidad acueductos', '4245', FALSE, TRUE, FALSE),
(6, '424560', 'ARMAMENTO DE VIGILANCIA', FALSE, 'Utilidad armamento', '4245', FALSE, TRUE, FALSE),
(6, '424562', 'ENVASES Y EMPAQUES', FALSE, 'Utilidad envases', '4245', FALSE, TRUE, FALSE),
(6, '424564', 'PLANTACIONES AGRICOLAS Y FORESTALES', FALSE, 'Utilidad plantaciones', '4245', FALSE, TRUE, FALSE),
(6, '424568', 'VIAS DE COMUNICACION', FALSE, 'Utilidad vías', '4245', FALSE, TRUE, FALSE),
(6, '424572', 'MINAS Y CANTERAS', FALSE, 'Utilidad minas', '4245', FALSE, TRUE, FALSE),
(6, '424580', 'POZOS ARTESIANOS', FALSE, 'Utilidad pozos', '4245', FALSE, TRUE, FALSE),
(6, '424584', 'YACIMIENTOS', FALSE, 'Utilidad yacimientos', '4245', FALSE, TRUE, FALSE),
(6, '424588', 'SEMOVIENTES', FALSE, 'Utilidad semovientes', '4245', FALSE, TRUE, FALSE),
(6, '424599', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación utilidad PPE', '4245', FALSE, TRUE, FALSE);

-- Subcuentas 4248
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '424805', 'INTANGIBLES', FALSE, 'Utilidad intangibles', '4248', FALSE, TRUE, FALSE),
(6, '424810', 'OTROS ACTIVOS', FALSE, 'Utilidad otros activos', '4248', FALSE, TRUE, FALSE),
(6, '424899', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación utilidad otros', '4248', FALSE, TRUE, FALSE);

-- Subcuentas 4250
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '425005', 'DEUDAS MALAS', FALSE, 'Recuperación deudas malas', '4250', FALSE, TRUE, FALSE),
(6, '425010', 'SEGUROS', FALSE, 'Recuperación seguros', '4250', FALSE, TRUE, FALSE),
(6, '425015', 'RECLAMOS', FALSE, 'Recuperación reclamos', '4250', FALSE, TRUE, FALSE),
(6, '425020', 'REINTEGRO POR PERSONAL EN COMISION', FALSE, 'Reintegro personal', '4250', FALSE, TRUE, FALSE),
(6, '425025', 'REINTEGRO GARANTIAS', FALSE, 'Reintegro garantías', '4250', FALSE, TRUE, FALSE),
(6, '425030', 'DESCUENTOS CONCEDIDOS', FALSE, 'Descuentos concedidos', '4250', FALSE, TRUE, FALSE),
(6, '425035', 'DE PROVISIONES', FALSE, 'Reintegro provisiones', '4250', FALSE, TRUE, FALSE),
(6, '425040', 'GASTOS BANCARIOS', FALSE, 'Recuperación gastos bancarios', '4250', FALSE, TRUE, FALSE),
(6, '425045', 'DE DEPRECIACION', FALSE, 'Recuperación depreciación', '4250', FALSE, TRUE, FALSE),
(6, '425050', 'REINTEGRO DE OTROS COSTOS Y GASTOS', FALSE, 'Reintegro otros costos', '4250', FALSE, TRUE, FALSE),
(6, '425099', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación recuperaciones', '4250', FALSE, TRUE, FALSE);

-- Subcuentas 4255
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '425505', 'POR SINIESTRO', FALSE, 'Indemnización siniestro', '4255', FALSE, TRUE, FALSE),
(6, '425510', 'POR SUMINISTROS', FALSE, 'Indemnización suministros', '4255', FALSE, TRUE, FALSE),
(6, '425515', 'LUCRO CESANTE COMPANÍAS DE SEGUROS', FALSE, 'Lucro cesante', '4255', FALSE, TRUE, FALSE),
(6, '425520', 'DAÑO EMERGENTE COMPANÍAS DE SEGUROS', FALSE, 'Daño emergente', '4255', FALSE, TRUE, FALSE),
(6, '425525', 'POR PERDIDA DE MERCANCIA', FALSE, 'Pérdida mercancía', '4255', FALSE, TRUE, FALSE),
(6, '425530', 'POR INCUMPLIMIENTO DE CONTRATOS', FALSE, 'Incumplimiento contratos', '4255', FALSE, TRUE, FALSE),
(6, '425535', 'DE TERCEROS', FALSE, 'Indemnización terceros', '4255', FALSE, TRUE, FALSE),
(6, '425540', 'POR INCAPACIDADES I.S.S.', FALSE, 'Incapacidades ISS', '4255', FALSE, TRUE, FALSE),
(6, '425595', 'OTRAS', FALSE, 'Otras indemnizaciones', '4255', FALSE, TRUE, FALSE),
(6, '425599', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación indemnizaciones', '4255', FALSE, TRUE, FALSE);

-- Subcuentas 4260
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '426001', 'PARTICIPACIONES EN CONCESIONES 426001 A 426098', FALSE, 'Concesiones rango', '4260', FALSE, TRUE, FALSE),
(6, '426098', 'PARTICIPACIONES EN CONCESIONES FIN RANGO', FALSE, 'Concesiones fin', '4260', FALSE, TRUE, FALSE),
(6, '426099', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación concesiones', '4260', FALSE, TRUE, FALSE);

-- Subcuentas 4265
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '426501', 'INGRESOS DE EJERCICIOS ANTERIORES 426501 A 426598', FALSE, 'Ingresos anteriores rango', '4265', FALSE, TRUE, FALSE),
(6, '426598', 'INGRESOS DE EJERCICIOS ANTERIORES FIN RANGO', FALSE, 'Ingresos anteriores fin', '4265', FALSE, TRUE, FALSE),
(6, '426599', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación ingresos anteriores', '4265', FALSE, TRUE, FALSE);

-- Subcuentas 4275 (Devoluciones en otras ventas - DÉBITO)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '427501', 'DEVOLUCIONES OTRAS VENTAS 427501 A 427598', TRUE, 'Devoluciones otras ventas rango', '4275', FALSE, TRUE, FALSE),
(6, '427598', 'DEVOLUCIONES OTRAS VENTAS FIN RANGO', TRUE, 'Devoluciones otras ventas fin', '4275', FALSE, TRUE, FALSE),
(6, '427599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación devoluciones otras', '4275', FALSE, TRUE, FALSE);

-- Subcuentas 4295
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '429503', 'CERT', FALSE, 'CERT', '4295', FALSE, TRUE, FALSE),
(6, '429505', 'APROVECHAMIENTOS', FALSE, 'Aprovechamientos', '4295', FALSE, TRUE, FALSE),
(6, '429507', 'AUXILIOS', FALSE, 'Auxilios', '4295', FALSE, TRUE, FALSE),
(6, '429509', 'SUBVENCIONES', FALSE, 'Subvenciones', '4295', FALSE, TRUE, FALSE),
(6, '429511', 'INGRESOS POR INVESTIGACION Y DESARROLLO', FALSE, 'Investigación y desarrollo', '4295', FALSE, TRUE, FALSE),
(6, '429513', 'POR TRABAJOS EJECUTADOS', FALSE, 'Trabajos ejecutados', '4295', FALSE, TRUE, FALSE),
(6, '429515', 'REGALIAS', FALSE, 'Regalías', '4295', FALSE, TRUE, FALSE),
(6, '429517', 'DERIVADOS DE LAS EXPORTACIONES', FALSE, 'Derivados exportaciones', '4295', FALSE, TRUE, FALSE),
(6, '429519', 'OTROS INGRESOS DE EXPLOTACION', FALSE, 'Otros explotación', '4295', FALSE, TRUE, FALSE),
(6, '429521', 'DE LA ACTIVIDAD GANADERA', FALSE, 'Actividad ganadera', '4295', FALSE, TRUE, FALSE),
(6, '429525', 'DERECHOS Y LICITACIONES', FALSE, 'Derechos y licitaciones', '4295', FALSE, TRUE, FALSE),
(6, '429530', 'INGRESOS POR ELEMENTOS PERDIDOS', FALSE, 'Elementos perdidos', '4295', FALSE, TRUE, FALSE),
(6, '429533', 'MULTAS Y RECARGOS', FALSE, 'Multas y recargos', '4295', FALSE, TRUE, FALSE),
(6, '429535', 'PREAVISOS DESCONTADOS', FALSE, 'Preavisos descontados', '4295', FALSE, TRUE, FALSE),
(6, '429537', 'RECLAMOS', FALSE, 'Reclamos', '4295', FALSE, TRUE, FALSE),
(6, '429540', 'RECOBRO DE DAÑOS', FALSE, 'Recobro daños', '4295', FALSE, TRUE, FALSE),
(6, '429543', 'PREMIOS', FALSE, 'Premios', '4295', FALSE, TRUE, FALSE),
(6, '429545', 'BONIFICACIONES', FALSE, 'Bonificaciones', '4295', FALSE, TRUE, FALSE),
(6, '429547', 'PRODUCTOS DESCONTADOS', FALSE, 'Productos descontados', '4295', FALSE, TRUE, FALSE),
(6, '429549', 'RECONOCIMIENTOS I.S.S.', FALSE, 'Reconocimientos ISS', '4295', FALSE, TRUE, FALSE),
(6, '429551', 'EXCEDENTES', FALSE, 'Excedentes', '4295', FALSE, TRUE, FALSE),
(6, '429553', 'SOBRANTES DE CAJA', FALSE, 'Sobrantes caja', '4295', FALSE, TRUE, FALSE),
(6, '429555', 'SOBRANTES EN LIQUIDACION FLETES', FALSE, 'Sobrantes fletes', '4295', FALSE, TRUE, FALSE),
(6, '429557', 'SUBSIDIOS ESTATALES', FALSE, 'Subsidios estatales', '4295', FALSE, TRUE, FALSE),
(6, '429559', 'CAPACITACION DISTRIBUIDORES', FALSE, 'Capacitación distribuidores', '4295', FALSE, TRUE, FALSE),
(6, '429561', 'DE ESCRITURACION', FALSE, 'Escrituración', '4295', FALSE, TRUE, FALSE),
(6, '429563', 'REGISTRO PROMESAS DE VENTA', FALSE, 'Registro promesas', '4295', FALSE, TRUE, FALSE),
(6, '429567', 'UTILES, PAPELERIA Y FOTOCOPIAS', FALSE, 'Útiles y papelería', '4295', FALSE, TRUE, FALSE),
(6, '429571', 'RESULTADOS MATRICULAS Y TRASPASOS', FALSE, 'Matrículas', '4295', FALSE, TRUE, FALSE),
(6, '429573', 'DECORACIONES', FALSE, 'Decoraciones', '4295', FALSE, TRUE, FALSE),
(6, '429575', 'MANEJO DE CARGA', FALSE, 'Manejo de carga', '4295', FALSE, TRUE, FALSE),
(6, '429579', 'HISTORIA CLINICA', FALSE, 'Historia clínica', '4295', FALSE, TRUE, FALSE),
(6, '429581', 'AJUSTE AL PESO', FALSE, 'Ajuste al peso', '4295', FALSE, TRUE, FALSE),
(6, '429583', 'LLAMADAS TELEFONICAS', FALSE, 'Llamadas telefónicas', '4295', FALSE, TRUE, FALSE),
(6, '429599', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación diversos', '4295', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 47 — AJUSTES POR INFLACION (INGRESOS)
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '47', 'AJUSTES POR INFLACION', FALSE, 'Contrapartida de ajustes por inflación', '4', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '4705', 'CORRECCION MONETARIA', FALSE, 'Corrección monetaria', '47', FALSE, TRUE, FALSE);

-- Subcuentas 4705
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '470505', 'INVERSIONES (CR)', FALSE, 'Corrección inversiones', '4705', FALSE, TRUE, FALSE),
(6, '470510', 'INVENTARIOS (CR)', FALSE, 'Corrección inventarios', '4705', FALSE, TRUE, FALSE),
(6, '470515', 'PROPIEDADES, PLANTA Y EQUIPO (CR)', FALSE, 'Corrección PPE', '4705', FALSE, TRUE, FALSE),
(6, '470520', 'INTANGIBLES (CR)', FALSE, 'Corrección intangibles', '4705', FALSE, TRUE, FALSE),
(6, '470525', 'ACTIVOS DIFERIDOS', FALSE, 'Corrección activos diferidos', '4705', FALSE, TRUE, FALSE),
(6, '470530', 'OTROS ACTIVOS (CR)', FALSE, 'Corrección otros activos', '4705', FALSE, TRUE, FALSE),
(6, '470535', 'PASIVOS SUJETOS DE AJUSTE', FALSE, 'Corrección pasivos', '4705', FALSE, TRUE, FALSE),
(6, '470540', 'PATRIMONIO', FALSE, 'Corrección patrimonio', '4705', FALSE, TRUE, FALSE),
(6, '470545', 'DEPRECIACION ACUMULADA (DB)', TRUE, 'Corrección depreciación (débito)', '4705', FALSE, TRUE, FALSE),
(6, '470550', 'DEPRECIACION DIFERIDA (CR)', FALSE, 'Corrección depreciación diferida', '4705', FALSE, TRUE, FALSE),
(6, '470555', 'AGOTAMIENTO ACUMULADO (DB)', TRUE, 'Corrección agotamiento (débito)', '4705', FALSE, TRUE, FALSE),
(6, '470560', 'AMORTIZACION ACUMULADA (DB)', TRUE, 'Corrección amortización (débito)', '4705', FALSE, TRUE, FALSE),
(6, '470565', 'INGRESOS OPERACIONALES (DB)', TRUE, 'Corrección ingresos operacionales (débito)', '4705', FALSE, TRUE, FALSE),
(6, '470568', 'DEVOLUCIONES EN VENTAS (CR)', FALSE, 'Corrección devoluciones ventas', '4705', FALSE, TRUE, FALSE),
(6, '470570', 'INGRESOS NO OPERACIONALES (DB)', TRUE, 'Corrección ingresos no operacionales (débito)', '4705', FALSE, TRUE, FALSE),
(6, '470575', 'GASTOS OPERACIONALES DE ADMINISTRACION (CR)', FALSE, 'Corrección gastos admin', '4705', FALSE, TRUE, FALSE),
(6, '470580', 'GASTOS OPERACIONALES DE VENTAS (CR)', FALSE, 'Corrección gastos ventas', '4705', FALSE, TRUE, FALSE),
(6, '470585', 'GASTOS NO OPERACIONALES (CR)', FALSE, 'Corrección gastos no operacionales', '4705', FALSE, TRUE, FALSE),
(6, '470590', 'COMPRAS (CR)', FALSE, 'Corrección compras', '4705', FALSE, TRUE, FALSE),
(6, '470591', 'DEVOLUCIONES EN COMPRAS (DB)', TRUE, 'Corrección devoluciones compras (débito)', '4705', FALSE, TRUE, FALSE),
(6, '470592', 'COSTO DE VENTAS (CR)', FALSE, 'Corrección costo ventas', '4705', FALSE, TRUE, FALSE),
(6, '470594', 'COSTOS DE PRODUCCION O DE OPERACION (CR)', FALSE, 'Corrección costos producción', '4705', FALSE, TRUE, FALSE);

-- ============================================================
-- VERIFICACIÓN
-- ============================================================
-- SELECT COUNT(*) FROM tab_puc;
-- SELECT id_nivel, COUNT(*) FROM tab_puc GROUP BY id_nivel ORDER BY id_nivel;

-- ================================================================
-- PUC COLOMBIA - DECRETO 2650 DE 1993
-- ENTREGA 5: Clase 5 (GASTOS) — Grupos 51 y 52
-- ================================================================

-- ============================================================
-- CLASE 5: GASTOS (naturaleza DÉBITO)
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(1, '5', 'GASTOS', TRUE, 'Cargos operativos y financieros en que incurre el ente económico', '0', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 51 — OPERACIONALES DE ADMINISTRACION
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '51', 'OPERACIONALES DE ADMINISTRACION', TRUE, 'Gastos ocasionados en la gestión administrativa', '5', FALSE, TRUE, FALSE);

-- Nivel 4
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '5105', 'GASTOS DE PERSONAL', TRUE, 'Gastos de personal administrativo', '51', FALSE, TRUE, FALSE),
(4, '5110', 'HONORARIOS', TRUE, 'Honorarios administrativos', '51', FALSE, TRUE, FALSE),
(4, '5115', 'IMPUESTOS', TRUE, 'Impuestos administrativos', '51', FALSE, TRUE, FALSE),
(4, '5120', 'ARRENDAMIENTOS', TRUE, 'Arrendamientos administrativos', '51', FALSE, TRUE, FALSE),
(4, '5125', 'CONTRIBUCIONES Y AFILIACIONES', TRUE, 'Contribuciones y afiliaciones', '51', FALSE, TRUE, FALSE),
(4, '5130', 'SEGUROS', TRUE, 'Seguros administrativos', '51', FALSE, TRUE, FALSE),
(4, '5135', 'SERVICIOS', TRUE, 'Servicios administrativos', '51', FALSE, TRUE, FALSE),
(4, '5140', 'GASTOS LEGALES', TRUE, 'Gastos legales', '51', FALSE, TRUE, FALSE),
(4, '5145', 'MANTENIMIENTO Y REPARACIONES', TRUE, 'Mantenimiento y reparaciones', '51', FALSE, TRUE, FALSE),
(4, '5150', 'ADECUACION E INSTALACION', TRUE, 'Adecuación e instalación', '51', FALSE, TRUE, FALSE),
(4, '5155', 'GASTOS DE VIAJE', TRUE, 'Gastos de viaje', '51', FALSE, TRUE, FALSE),
(4, '5160', 'DEPRECIACIONES', TRUE, 'Depreciaciones', '51', FALSE, TRUE, FALSE),
(4, '5165', 'AMORTIZACIONES', TRUE, 'Amortizaciones', '51', FALSE, TRUE, FALSE),
(4, '5195', 'DIVERSOS', TRUE, 'Gastos diversos', '51', FALSE, TRUE, FALSE),
(4, '5199', 'PROVISIONES', TRUE, 'Provisiones administrativas', '51', FALSE, TRUE, FALSE);

-- Subcuentas 5105
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '510503', 'SALARIO INTEGRAL', TRUE, 'Salario integral', '5105', FALSE, TRUE, FALSE),
(6, '510506', 'SUELDOS', TRUE, 'Sueldos', '5105', FALSE, TRUE, FALSE),
(6, '510512', 'JORNALES', TRUE, 'Jornales', '5105', FALSE, TRUE, FALSE),
(6, '510515', 'HORAS EXTRAS Y RECARGOS', TRUE, 'Horas extras', '5105', FALSE, TRUE, FALSE),
(6, '510518', 'COMISIONES', TRUE, 'Comisiones', '5105', FALSE, TRUE, FALSE),
(6, '510521', 'VIATICOS', TRUE, 'Viáticos', '5105', FALSE, TRUE, FALSE),
(6, '510524', 'INCAPACIDADES', TRUE, 'Incapacidades', '5105', FALSE, TRUE, FALSE),
(6, '510527', 'AUXILIO DE TRANSPORTE', TRUE, 'Auxilio de transporte', '5105', FALSE, TRUE, FALSE),
(6, '510530', 'CESANTIAS', TRUE, 'Cesantías', '5105', FALSE, TRUE, FALSE),
(6, '510533', 'INTERESES SOBRE CESANTIAS', TRUE, 'Intereses cesantías', '5105', FALSE, TRUE, FALSE),
(6, '510536', 'PRIMA DE SERVICIOS', TRUE, 'Prima de servicios', '5105', FALSE, TRUE, FALSE),
(6, '510539', 'VACACIONES', TRUE, 'Vacaciones', '5105', FALSE, TRUE, FALSE),
(6, '510542', 'PRIMAS EXTRALEGALES', TRUE, 'Primas extralegales', '5105', FALSE, TRUE, FALSE),
(6, '510545', 'AUXILIOS', TRUE, 'Auxilios', '5105', FALSE, TRUE, FALSE),
(6, '510548', 'BONIFICACIONES', TRUE, 'Bonificaciones', '5105', FALSE, TRUE, FALSE),
(6, '510551', 'DOTACION Y SUMINISTRO A TRABAJADORES', TRUE, 'Dotación', '5105', FALSE, TRUE, FALSE),
(6, '510554', 'SEGUROS', TRUE, 'Seguros personal', '5105', FALSE, TRUE, FALSE),
(6, '510557', 'CUOTAS PARTES PENSIONES DE JUBILACION', TRUE, 'Cuotas partes pensiones', '5105', FALSE, TRUE, FALSE),
(6, '510558', 'AMORTIZACION CALCULO ACTUARIAL PENSIONES DE JUBILACION', TRUE, 'Amortización cálculo actuarial', '5105', FALSE, TRUE, FALSE),
(6, '510559', 'PENSIONES DE JUBILACION', TRUE, 'Pensiones de jubilación', '5105', FALSE, TRUE, FALSE),
(6, '510560', 'INDEMNIZACIONES LABORALES', TRUE, 'Indemnizaciones', '5105', FALSE, TRUE, FALSE),
(6, '510561', 'AMORTIZACION BONOS PENSIONALES', TRUE, 'Amortización bonos pensionales', '5105', FALSE, TRUE, FALSE),
(6, '510562', 'AMORTIZACION TITULOS PENSIONALES', TRUE, 'Amortización títulos pensionales', '5105', FALSE, TRUE, FALSE),
(6, '510563', 'CAPACITACION AL PERSONAL', TRUE, 'Capacitación', '5105', FALSE, TRUE, FALSE),
(6, '510566', 'GASTOS DEPORTIVOS Y DE RECREACION', TRUE, 'Gastos deportivos', '5105', FALSE, TRUE, FALSE),
(6, '510568', 'APORTES A ADMINISTRADORAS DE RIESGOS PROFESIONALES ARP', TRUE, 'Aportes ARP', '5105', FALSE, TRUE, FALSE),
(6, '510569', 'APORTES A ENTIDADES PROMOTORAS DE SALUD EPS', TRUE, 'Aportes EPS', '5105', FALSE, TRUE, FALSE),
(6, '510570', 'APORTES A FONDOS DE PENSIONES Y/O CESANTIAS', TRUE, 'Aportes fondos', '5105', FALSE, TRUE, FALSE),
(6, '510572', 'APORTES CAJAS DE COMPENSACION FAMILIAR', TRUE, 'Aportes CCF', '5105', FALSE, TRUE, FALSE),
(6, '510575', 'APORTES I.C.B.F.', TRUE, 'Aportes ICBF', '5105', FALSE, TRUE, FALSE),
(6, '510578', 'SENA', TRUE, 'Aportes SENA', '5105', FALSE, TRUE, FALSE),
(6, '510581', 'APORTES SINDICALES', TRUE, 'Aportes sindicales', '5105', FALSE, TRUE, FALSE),
(6, '510584', 'GASTOS MEDICOS Y DROGAS', TRUE, 'Gastos médicos', '5105', FALSE, TRUE, FALSE),
(6, '510595', 'OTROS', TRUE, 'Otros gastos personal', '5105', FALSE, TRUE, FALSE),
(6, '510599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación personal', '5105', FALSE, TRUE, FALSE);

-- Subcuentas 5110
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '511005', 'JUNTA DIRECTIVA', TRUE, 'Honorarios junta', '5110', FALSE, TRUE, FALSE),
(6, '511010', 'REVISORIA FISCAL', TRUE, 'Revisoría fiscal', '5110', FALSE, TRUE, FALSE),
(6, '511015', 'AUDITORIA EXTERNA', TRUE, 'Auditoría externa', '5110', FALSE, TRUE, FALSE),
(6, '511020', 'AVALUOS', TRUE, 'Avalúos', '5110', FALSE, TRUE, FALSE),
(6, '511025', 'ASESORIA JURIDICA', TRUE, 'Asesoría jurídica', '5110', FALSE, TRUE, FALSE),
(6, '511030', 'ASESORIA FINANCIERA', TRUE, 'Asesoría financiera', '5110', FALSE, TRUE, FALSE),
(6, '511035', 'ASESORIA TECNICA', TRUE, 'Asesoría técnica', '5110', FALSE, TRUE, FALSE),
(6, '511095', 'OTROS', TRUE, 'Otros honorarios', '5110', FALSE, TRUE, FALSE),
(6, '511099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación honorarios', '5110', FALSE, TRUE, FALSE);

-- Subcuentas 5115
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '511505', 'INDUSTRIA Y COMERCIO', TRUE, 'ICA', '5115', FALSE, TRUE, FALSE),
(6, '511510', 'DE TIMBRES', TRUE, 'Impuesto timbres', '5115', FALSE, TRUE, FALSE),
(6, '511515', 'A LA PROPIEDAD RAIZ', TRUE, 'Predial', '5115', FALSE, TRUE, FALSE),
(6, '511520', 'DERECHOS SOBRE INSTRUMENTOS PUBLICOS', TRUE, 'Instrumentos públicos', '5115', FALSE, TRUE, FALSE),
(6, '511525', 'DE VALORIZACION', TRUE, 'Valorización', '5115', FALSE, TRUE, FALSE),
(6, '511530', 'DE TURISMO', TRUE, 'Turismo', '5115', FALSE, TRUE, FALSE),
(6, '511535', 'TASA POR UTILIZACION DE PUERTOS', TRUE, 'Puertos', '5115', FALSE, TRUE, FALSE),
(6, '511540', 'DE VEHICULOS', TRUE, 'Vehículos', '5115', FALSE, TRUE, FALSE),
(6, '511545', 'DE ESPECTACULOS PUBLICOS', TRUE, 'Espectáculos', '5115', FALSE, TRUE, FALSE),
(6, '511550', 'CUOTAS DE FOMENTO', TRUE, 'Cuotas fomento', '5115', FALSE, TRUE, FALSE),
(6, '511570', 'IVA DESCONTABLE', TRUE, 'IVA descontable', '5115', FALSE, TRUE, FALSE),
(6, '511595', 'OTROS', TRUE, 'Otros impuestos', '5115', FALSE, TRUE, FALSE),
(6, '511599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación impuestos', '5115', FALSE, TRUE, FALSE);

-- Subcuentas 5120
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '512005', 'TERRENOS', TRUE, 'Arrendamiento terrenos', '5120', FALSE, TRUE, FALSE),
(6, '512010', 'CONSTRUCCIONES Y EDIFICACIONES', TRUE, 'Arrendamiento construcciones', '5120', FALSE, TRUE, FALSE),
(6, '512015', 'MAQUINARIA Y EQUIPO', TRUE, 'Arrendamiento maquinaria', '5120', FALSE, TRUE, FALSE),
(6, '512020', 'EQUIPO DE OFICINA', TRUE, 'Arrendamiento equipo oficina', '5120', FALSE, TRUE, FALSE),
(6, '512025', 'EQUIPO DE COMPUTACION Y COMUNICACION', TRUE, 'Arrendamiento cómputo', '5120', FALSE, TRUE, FALSE),
(6, '512030', 'EQUIPO MEDICO - CIENTIFICO', TRUE, 'Arrendamiento médico', '5120', FALSE, TRUE, FALSE),
(6, '512035', 'EQUIPO DE HOTELES Y RESTAURANTES', TRUE, 'Arrendamiento hoteles', '5120', FALSE, TRUE, FALSE),
(6, '512040', 'FLOTA Y EQUIPO DE TRANSPORTE', TRUE, 'Arrendamiento flota', '5120', FALSE, TRUE, FALSE),
(6, '512045', 'FLOTA Y EQUIPO FLUVIAL Y/O MARITIMO', TRUE, 'Arrendamiento fluvial', '5120', FALSE, TRUE, FALSE),
(6, '512050', 'FLOTA Y EQUIPO AEREO', TRUE, 'Arrendamiento aéreo', '5120', FALSE, TRUE, FALSE),
(6, '512055', 'FLOTA Y EQUIPO FERREO', TRUE, 'Arrendamiento férreo', '5120', FALSE, TRUE, FALSE),
(6, '512060', 'ACUEDUCTOS PLANTAS Y REDES', TRUE, 'Arrendamiento acueductos', '5120', FALSE, TRUE, FALSE),
(6, '512065', 'AERODROMOS', TRUE, 'Arrendamiento aeródromos', '5120', FALSE, TRUE, FALSE),
(6, '512070', 'SEMOVIENTES', TRUE, 'Arrendamiento semovientes', '5120', FALSE, TRUE, FALSE),
(6, '512095', 'OTROS', TRUE, 'Otros arrendamientos', '5120', FALSE, TRUE, FALSE),
(6, '512099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación arrendamientos', '5120', FALSE, TRUE, FALSE);

-- Subcuentas 5125
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '512505', 'CONTRIBUCIONES', TRUE, 'Contribuciones', '5125', FALSE, TRUE, FALSE),
(6, '512510', 'AFILIACIONES Y SOSTENIMIENTO', TRUE, 'Afiliaciones', '5125', FALSE, TRUE, FALSE),
(6, '512599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación contribuciones', '5125', FALSE, TRUE, FALSE);

-- Subcuentas 5130
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '513005', 'MANEJO', TRUE, 'Seguro manejo', '5130', FALSE, TRUE, FALSE),
(6, '513010', 'CUMPLIMIENTO', TRUE, 'Seguro cumplimiento', '5130', FALSE, TRUE, FALSE),
(6, '513015', 'CORRIENTE DEBIL', TRUE, 'Corriente débil', '5130', FALSE, TRUE, FALSE),
(6, '513020', 'VIDA COLECTIVA', TRUE, 'Vida colectiva', '5130', FALSE, TRUE, FALSE),
(6, '513025', 'INCENDIO', TRUE, 'Incendio', '5130', FALSE, TRUE, FALSE),
(6, '513030', 'TERREMOTO', TRUE, 'Terremoto', '5130', FALSE, TRUE, FALSE),
(6, '513035', 'SUSTRACCION Y HURTO', TRUE, 'Sustracción y hurto', '5130', FALSE, TRUE, FALSE),
(6, '513040', 'FLOTA Y EQUIPO DE TRANSPORTE', TRUE, 'Flota transporte', '5130', FALSE, TRUE, FALSE),
(6, '513045', 'FLOTA Y EQUIPO FLUVIAL Y/O MARITIMO', TRUE, 'Flota fluvial', '5130', FALSE, TRUE, FALSE),
(6, '513050', 'FLOTA Y EQUIPO AEREO', TRUE, 'Flota aérea', '5130', FALSE, TRUE, FALSE),
(6, '513055', 'FLOTA Y EQUIPO FERREO', TRUE, 'Flota férrea', '5130', FALSE, TRUE, FALSE),
(6, '513060', 'RESPONSABILIDAD CIVIL Y EXTRACONTRACTUAL', TRUE, 'Responsabilidad civil', '5130', FALSE, TRUE, FALSE),
(6, '513065', 'VUELO', TRUE, 'Seguro vuelo', '5130', FALSE, TRUE, FALSE),
(6, '513070', 'ROTURA DE MAQUINARIA', TRUE, 'Rotura maquinaria', '5130', FALSE, TRUE, FALSE),
(6, '513075', 'OBLIGATORIO ACCIDENTE DE TRANSITO', TRUE, 'SOAT', '5130', FALSE, TRUE, FALSE),
(6, '513080', 'LUCRO CESANTE', TRUE, 'Lucro cesante', '5130', FALSE, TRUE, FALSE),
(6, '513085', 'TRANSPORTE DE MERCANCIA', TRUE, 'Transporte mercancía', '5130', FALSE, TRUE, FALSE),
(6, '513095', 'OTROS', TRUE, 'Otros seguros', '5130', FALSE, TRUE, FALSE),
(6, '513099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación seguros', '5130', FALSE, TRUE, FALSE);

-- Subcuentas 5135
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '513505', 'ASEO Y VIGILANCIA', TRUE, 'Aseo y vigilancia', '5135', FALSE, TRUE, FALSE),
(6, '513510', 'TEMPORALES', TRUE, 'Temporales', '5135', FALSE, TRUE, FALSE),
(6, '513515', 'ASISTENCIA TECNICA', TRUE, 'Asistencia técnica', '5135', FALSE, TRUE, FALSE),
(6, '513520', 'PROCESAMIENTO ELECTRONICO DE DATOS', TRUE, 'Procesamiento datos', '5135', FALSE, TRUE, FALSE),
(6, '513525', 'ACUEDUCTO Y ALCANTARILLADO', TRUE, 'Acueducto', '5135', FALSE, TRUE, FALSE),
(6, '513530', 'ENERGIA ELECTRICA', TRUE, 'Energía eléctrica', '5135', FALSE, TRUE, FALSE),
(6, '513535', 'TELEFONO', TRUE, 'Teléfono', '5135', FALSE, TRUE, FALSE),
(6, '513540', 'CORREO, PORTES Y TELEGRAMAS', TRUE, 'Correo', '5135', FALSE, TRUE, FALSE),
(6, '513545', 'FAX Y TELEX', TRUE, 'Fax y télex', '5135', FALSE, TRUE, FALSE),
(6, '513550', 'TRANSPORTE, FLETES Y ACARREOS', TRUE, 'Transporte', '5135', FALSE, TRUE, FALSE),
(6, '513555', 'GAS', TRUE, 'Gas', '5135', FALSE, TRUE, FALSE),
(6, '513595', 'OTROS', TRUE, 'Otros servicios', '5135', FALSE, TRUE, FALSE),
(6, '513599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación servicios', '5135', FALSE, TRUE, FALSE);

-- Subcuentas 5140
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '514005', 'NOTARIALES', TRUE, 'Gastos notariales', '5140', FALSE, TRUE, FALSE),
(6, '514010', 'REGISTRO MERCANTIL', TRUE, 'Registro mercantil', '5140', FALSE, TRUE, FALSE),
(6, '514015', 'TRAMITES Y LICENCIAS', TRUE, 'Trámites y licencias', '5140', FALSE, TRUE, FALSE),
(6, '514020', 'ADUANEROS', TRUE, 'Aduaneros', '5140', FALSE, TRUE, FALSE),
(6, '514025', 'CONSULARES', TRUE, 'Consulares', '5140', FALSE, TRUE, FALSE),
(6, '514095', 'OTROS', TRUE, 'Otros gastos legales', '5140', FALSE, TRUE, FALSE),
(6, '514099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación legales', '5140', FALSE, TRUE, FALSE);

-- Subcuentas 5145
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '514505', 'TERRENOS', TRUE, 'Mantenimiento terrenos', '5145', FALSE, TRUE, FALSE),
(6, '514510', 'CONSTRUCCIONES Y EDIFICACIONES', TRUE, 'Mantenimiento construcciones', '5145', FALSE, TRUE, FALSE),
(6, '514515', 'MAQUINARIA Y EQUIPO', TRUE, 'Mantenimiento maquinaria', '5145', FALSE, TRUE, FALSE),
(6, '514520', 'EQUIPO DE OFICINA', TRUE, 'Mantenimiento equipo oficina', '5145', FALSE, TRUE, FALSE),
(6, '514525', 'EQUIPO DE COMPUTACION Y COMUNICACION', TRUE, 'Mantenimiento cómputo', '5145', FALSE, TRUE, FALSE),
(6, '514530', 'EQUIPO MEDICO-CIENTIFICO', TRUE, 'Mantenimiento médico', '5145', FALSE, TRUE, FALSE),
(6, '514535', 'EQUIPO DE HOTELES Y RESTAURANTES', TRUE, 'Mantenimiento hoteles', '5145', FALSE, TRUE, FALSE),
(6, '514540', 'FLOTA Y EQUIPO DE TRANSPORTE', TRUE, 'Mantenimiento flota', '5145', FALSE, TRUE, FALSE),
(6, '514545', 'FLOTA Y EQUIPO FLUVIAL Y/O MARITIMO', TRUE, 'Mantenimiento fluvial', '5145', FALSE, TRUE, FALSE),
(6, '514550', 'FLOTA Y EQUIPO AEREO', TRUE, 'Mantenimiento aéreo', '5145', FALSE, TRUE, FALSE),
(6, '514555', 'FLOTA Y EQUIPO FERREO', TRUE, 'Mantenimiento férreo', '5145', FALSE, TRUE, FALSE),
(6, '514560', 'ACUEDUCTOS PLANTAS Y REDES', TRUE, 'Mantenimiento acueductos', '5145', FALSE, TRUE, FALSE),
(6, '514565', 'ARMAMENTO DE VIGILANCIA', TRUE, 'Mantenimiento armamento', '5145', FALSE, TRUE, FALSE),
(6, '514570', 'VIAS DE COMUNICACION', TRUE, 'Mantenimiento vías', '5145', FALSE, TRUE, FALSE),
(6, '514599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación mantenimiento', '5145', FALSE, TRUE, FALSE);

-- Subcuentas 5150
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '515005', 'INSTALACIONES ELECTRICAS', TRUE, 'Instalaciones eléctricas', '5150', FALSE, TRUE, FALSE),
(6, '515010', 'ARREGLOS ORNAMENTALES', TRUE, 'Arreglos ornamentales', '5150', FALSE, TRUE, FALSE),
(6, '515015', 'REPARACIONES LOCATIVAS', TRUE, 'Reparaciones locativas', '5150', FALSE, TRUE, FALSE),
(6, '515095', 'OTROS', TRUE, 'Otros adecuación', '5150', FALSE, TRUE, FALSE),
(6, '515099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación adecuación', '5150', FALSE, TRUE, FALSE);

-- Subcuentas 5155
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '515505', 'ALOJAMIENTO Y MANUTENCION', TRUE, 'Alojamiento', '5155', FALSE, TRUE, FALSE),
(6, '515510', 'PASAJES FLUVIALES Y/O MARITIMOS', TRUE, 'Pasajes fluviales', '5155', FALSE, TRUE, FALSE),
(6, '515515', 'PASAJES AEREOS', TRUE, 'Pasajes aéreos', '5155', FALSE, TRUE, FALSE),
(6, '515520', 'PASAJES TERRESTRES', TRUE, 'Pasajes terrestres', '5155', FALSE, TRUE, FALSE),
(6, '515525', 'PASAJES FERREOS', TRUE, 'Pasajes férreos', '5155', FALSE, TRUE, FALSE),
(6, '515595', 'OTROS', TRUE, 'Otros gastos viaje', '5155', FALSE, TRUE, FALSE),
(6, '515599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación viaje', '5155', FALSE, TRUE, FALSE);

-- Subcuentas 5160
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '516005', 'CONSTRUCCIONES Y EDIFICACIONES', TRUE, 'Depreciación construcciones', '5160', FALSE, TRUE, FALSE),
(6, '516010', 'MAQUINARIA Y EQUIPO', TRUE, 'Depreciación maquinaria', '5160', FALSE, TRUE, FALSE),
(6, '516015', 'EQUIPO DE OFICINA', TRUE, 'Depreciación equipo oficina', '5160', FALSE, TRUE, FALSE),
(6, '516020', 'EQUIPO DE COMPUTACION Y COMUNICACION', TRUE, 'Depreciación cómputo', '5160', FALSE, TRUE, FALSE),
(6, '516025', 'EQUIPO MEDICO - CIENTIFICO', TRUE, 'Depreciación médico', '5160', FALSE, TRUE, FALSE),
(6, '516030', 'EQUIPO DE HOTELES Y RESTAURANTES', TRUE, 'Depreciación hoteles', '5160', FALSE, TRUE, FALSE),
(6, '516035', 'FLOTA Y EQUIPO DE TRANSPORTE', TRUE, 'Depreciación flota', '5160', FALSE, TRUE, FALSE),
(6, '516040', 'FLOTA Y EQUIPO FLUVIAL Y/O MARITIMO', TRUE, 'Depreciación fluvial', '5160', FALSE, TRUE, FALSE),
(6, '516045', 'FLOTA Y EQUIPO AEREO', TRUE, 'Depreciación aéreo', '5160', FALSE, TRUE, FALSE),
(6, '516050', 'FLOTA Y EQUIPO FERREO', TRUE, 'Depreciación férreo', '5160', FALSE, TRUE, FALSE),
(6, '516055', 'ACUEDUCTOS, PLANTAS Y REDES', TRUE, 'Depreciación acueductos', '5160', FALSE, TRUE, FALSE),
(6, '516060', 'ARMAMENTO DE VIGILANCIA', TRUE, 'Depreciación armamento', '5160', FALSE, TRUE, FALSE),
(6, '516099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación depreciación', '5160', FALSE, TRUE, FALSE);

-- Subcuentas 5165
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '516505', 'VIAS DE COMUNICACION', TRUE, 'Amortización vías', '5165', FALSE, TRUE, FALSE),
(6, '516510', 'INTANGIBLES', TRUE, 'Amortización intangibles', '5165', FALSE, TRUE, FALSE),
(6, '516515', 'CARGOS DIFERIDOS', TRUE, 'Amortización cargos diferidos', '5165', FALSE, TRUE, FALSE),
(6, '516595', 'OTRAS', TRUE, 'Otras amortizaciones', '5165', FALSE, TRUE, FALSE),
(6, '516599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación amortizaciones', '5165', FALSE, TRUE, FALSE);

-- Subcuentas 5195
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '519505', 'COMISIONES', TRUE, 'Comisiones', '5195', FALSE, TRUE, FALSE),
(6, '519510', 'LIBROS, SUSCRIPCIONES, PERIODICOS Y REVISTAS', TRUE, 'Libros y suscripciones', '5195', FALSE, TRUE, FALSE),
(6, '519515', 'MUSICA AMBIENTAL', TRUE, 'Música ambiental', '5195', FALSE, TRUE, FALSE),
(6, '519520', 'GASTOS DE REPRESENTACION Y RELACIONES PUBLICAS', TRUE, 'Representación', '5195', FALSE, TRUE, FALSE),
(6, '519525', 'ELEMENTOS DE ASEO Y CAFETERIA', TRUE, 'Aseo y cafetería', '5195', FALSE, TRUE, FALSE),
(6, '519530', 'UTILES, PAPELERIA Y FOTOCOPIAS', TRUE, 'Útiles y papelería', '5195', FALSE, TRUE, FALSE),
(6, '519535', 'COMBUSTIBLES Y LUBRICANTES', TRUE, 'Combustibles', '5195', FALSE, TRUE, FALSE),
(6, '519540', 'ENVASES Y EMPAQUES', TRUE, 'Envases', '5195', FALSE, TRUE, FALSE),
(6, '519545', 'TAXIS Y BUSES', TRUE, 'Taxis y buses', '5195', FALSE, TRUE, FALSE),
(6, '519550', 'ESTAMPILLAS', TRUE, 'Estampillas', '5195', FALSE, TRUE, FALSE),
(6, '519555', 'MICROFILMACION', TRUE, 'Microfilmación', '5195', FALSE, TRUE, FALSE),
(6, '519560', 'CASINO Y RESTAURANTE', TRUE, 'Casino', '5195', FALSE, TRUE, FALSE),
(6, '519565', 'PARQUEADEROS', TRUE, 'Parqueaderos', '5195', FALSE, TRUE, FALSE),
(6, '519570', 'INDEMNIZACION POR DANOS A TERCEROS', TRUE, 'Indemnización terceros', '5195', FALSE, TRUE, FALSE),
(6, '519575', 'POLVORA Y SIMILARES', TRUE, 'Pólvora', '5195', FALSE, TRUE, FALSE),
(6, '519595', 'OTROS', TRUE, 'Otros gastos diversos', '5195', FALSE, TRUE, FALSE),
(6, '519599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación diversos', '5195', FALSE, TRUE, FALSE);

-- Subcuentas 5199
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '519905', 'INVERSIONES', TRUE, 'Provisión inversiones', '5199', FALSE, TRUE, FALSE),
(6, '519910', 'DEUDORES', TRUE, 'Provisión deudores', '5199', FALSE, TRUE, FALSE),
(6, '519915', 'PROPIEDADES, PLANTA Y EQUIPO', TRUE, 'Provisión PPE', '5199', FALSE, TRUE, FALSE),
(6, '519995', 'OTROS ACTIVOS', TRUE, 'Provisión otros activos', '5199', FALSE, TRUE, FALSE),
(6, '519999', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación provisiones', '5199', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 52 — OPERACIONALES DE VENTAS
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '52', 'OPERACIONALES DE VENTAS', TRUE, 'Gastos ocasionados en la gestión de ventas', '5', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '5205', 'GASTOS DE PERSONAL', TRUE, 'Gastos de personal de ventas', '52', FALSE, TRUE, FALSE),
(4, '5210', 'HONORARIOS', TRUE, 'Honorarios de ventas', '52', FALSE, TRUE, FALSE),
(4, '5215', 'IMPUESTOS', TRUE, 'Impuestos de ventas', '52', FALSE, TRUE, FALSE),
(4, '5220', 'ARRENDAMIENTOS', TRUE, 'Arrendamientos de ventas', '52', FALSE, TRUE, FALSE),
(4, '5225', 'CONTRIBUCIONES Y AFILIACIONES', TRUE, 'Contribuciones y afiliaciones', '52', FALSE, TRUE, FALSE),
(4, '5230', 'SEGUROS', TRUE, 'Seguros de ventas', '52', FALSE, TRUE, FALSE),
(4, '5235', 'SERVICIOS', TRUE, 'Servicios de ventas', '52', FALSE, TRUE, FALSE),
(4, '5240', 'GASTOS LEGALES', TRUE, 'Gastos legales de ventas', '52', FALSE, TRUE, FALSE),
(4, '5245', 'MANTENIMIENTO Y REPARACIONES', TRUE, 'Mantenimiento y reparaciones', '52', FALSE, TRUE, FALSE),
(4, '5250', 'ADECUACION E INSTALACION', TRUE, 'Adecuación e instalación', '52', FALSE, TRUE, FALSE),
(4, '5255', 'GASTOS DE VIAJE', TRUE, 'Gastos de viaje', '52', FALSE, TRUE, FALSE),
(4, '5260', 'DEPRECIACIONES', TRUE, 'Depreciaciones', '52', FALSE, TRUE, FALSE),
(4, '5265', 'AMORTIZACIONES', TRUE, 'Amortizaciones', '52', FALSE, TRUE, FALSE),
(4, '5270', 'FINANCIEROS - REAJUSTE DEL SISTEMA', TRUE, 'Financieros reajuste', '52', FALSE, TRUE, FALSE),
(4, '5275', 'PERDIDAS METODO DE PARTICIPACION', TRUE, 'Pérdidas método participación', '52', FALSE, TRUE, FALSE),
(4, '5295', 'DIVERSOS', TRUE, 'Gastos diversos de ventas', '52', FALSE, TRUE, FALSE),
(4, '5299', 'PROVISIONES', TRUE, 'Provisiones de ventas', '52', FALSE, TRUE, FALSE);

-- Subcuentas 5205 (mismas que 5105)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '520503', 'SALARIO INTEGRAL', TRUE, 'Salario integral', '5205', FALSE, TRUE, FALSE),
(6, '520506', 'SUELDOS', TRUE, 'Sueldos', '5205', FALSE, TRUE, FALSE),
(6, '520512', 'JORNALES', TRUE, 'Jornales', '5205', FALSE, TRUE, FALSE),
(6, '520515', 'HORAS EXTRAS Y RECARGOS', TRUE, 'Horas extras', '5205', FALSE, TRUE, FALSE),
(6, '520518', 'COMISIONES', TRUE, 'Comisiones', '5205', FALSE, TRUE, FALSE),
(6, '520521', 'VIATICOS', TRUE, 'Viáticos', '5205', FALSE, TRUE, FALSE),
(6, '520524', 'INCAPACIDADES', TRUE, 'Incapacidades', '5205', FALSE, TRUE, FALSE),
(6, '520527', 'AUXILIO DE TRANSPORTE', TRUE, 'Auxilio transporte', '5205', FALSE, TRUE, FALSE),
(6, '520530', 'CESANTIAS', TRUE, 'Cesantías', '5205', FALSE, TRUE, FALSE),
(6, '520533', 'INTERESES SOBRE CESANTIAS', TRUE, 'Intereses cesantías', '5205', FALSE, TRUE, FALSE),
(6, '520536', 'PRIMA DE SERVICIOS', TRUE, 'Prima', '5205', FALSE, TRUE, FALSE),
(6, '520539', 'VACACIONES', TRUE, 'Vacaciones', '5205', FALSE, TRUE, FALSE),
(6, '520542', 'PRIMAS EXTRALEGALES', TRUE, 'Primas extralegales', '5205', FALSE, TRUE, FALSE),
(6, '520545', 'AUXILIOS', TRUE, 'Auxilios', '5205', FALSE, TRUE, FALSE),
(6, '520548', 'BONIFICACIONES', TRUE, 'Bonificaciones', '5205', FALSE, TRUE, FALSE),
(6, '520551', 'DOTACION Y SUMINISTRO A TRABAJADORES', TRUE, 'Dotación', '5205', FALSE, TRUE, FALSE),
(6, '520554', 'SEGUROS', TRUE, 'Seguros personal', '5205', FALSE, TRUE, FALSE),
(6, '520557', 'CUOTAS PARTES PENSIONES DE JUBILACION', TRUE, 'Cuotas partes pensiones', '5205', FALSE, TRUE, FALSE),
(6, '520558', 'AMORTIZACION CALCULO ACTUARIAL PENSIONES DE JUBILACION', TRUE, 'Cálculo actuarial', '5205', FALSE, TRUE, FALSE),
(6, '520559', 'PENSIONES DE JUBILACION', TRUE, 'Pensiones', '5205', FALSE, TRUE, FALSE),
(6, '520560', 'INDEMNIZACIONES LABORALES', TRUE, 'Indemnizaciones', '5205', FALSE, TRUE, FALSE),
(6, '520561', 'AMORTIZACION BONOS PENSIONALES', TRUE, 'Bonos pensionales', '5205', FALSE, TRUE, FALSE),
(6, '520562', 'AMORTIZACION TITULOS PENSIONALES', TRUE, 'Títulos pensionales', '5205', FALSE, TRUE, FALSE),
(6, '520563', 'CAPACITACION AL PERSONAL', TRUE, 'Capacitación', '5205', FALSE, TRUE, FALSE),
(6, '520566', 'GASTOS DEPORTIVOS Y DE RECREACION', TRUE, 'Gastos deportivos', '5205', FALSE, TRUE, FALSE),
(6, '520568', 'APORTES A ADMINISTRADORAS DE RIESGOS PROFESIONALES ARP', TRUE, 'Aportes ARP', '5205', FALSE, TRUE, FALSE),
(6, '520569', 'APORTES A ENTIDADES PROMOTORAS DE SALUD EPS', TRUE, 'Aportes EPS', '5205', FALSE, TRUE, FALSE),
(6, '520570', 'APORTES A FONDOS DE PENSIONES Y/O CESANTIAS', TRUE, 'Aportes fondos', '5205', FALSE, TRUE, FALSE),
(6, '520572', 'APORTES CAJAS DE COMPENSACION FAMILIAR', TRUE, 'Aportes CCF', '5205', FALSE, TRUE, FALSE),
(6, '520575', 'APORTES I.C.B.F.', TRUE, 'Aportes ICBF', '5205', FALSE, TRUE, FALSE),
(6, '520578', 'SENA', TRUE, 'Aportes SENA', '5205', FALSE, TRUE, FALSE),
(6, '520581', 'APORTES SINDICALES', TRUE, 'Aportes sindicales', '5205', FALSE, TRUE, FALSE),
(6, '520584', 'GASTOS MEDICOS Y DROGAS', TRUE, 'Gastos médicos', '5205', FALSE, TRUE, FALSE),
(6, '520595', 'OTROS', TRUE, 'Otros gastos personal', '5205', FALSE, TRUE, FALSE),
(6, '520599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación personal', '5205', FALSE, TRUE, FALSE);

-- Subcuentas 5210
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '521005', 'JUNTA DIRECTIVA', TRUE, 'Honorarios junta', '5210', FALSE, TRUE, FALSE),
(6, '521010', 'REVISORIA FISCAL', TRUE, 'Revisoría', '5210', FALSE, TRUE, FALSE),
(6, '521015', 'AUDITORIA EXTERNA', TRUE, 'Auditoría', '5210', FALSE, TRUE, FALSE),
(6, '521020', 'AVALUOS', TRUE, 'Avalúos', '5210', FALSE, TRUE, FALSE),
(6, '521025', 'ASESORIA JURIDICA', TRUE, 'Asesoría jurídica', '5210', FALSE, TRUE, FALSE),
(6, '521030', 'ASESORIA FINANCIERA', TRUE, 'Asesoría financiera', '5210', FALSE, TRUE, FALSE),
(6, '521035', 'ASESORIA TECNICA', TRUE, 'Asesoría técnica', '5210', FALSE, TRUE, FALSE),
(6, '521095', 'OTROS', TRUE, 'Otros honorarios', '5210', FALSE, TRUE, FALSE),
(6, '521099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación honorarios', '5210', FALSE, TRUE, FALSE);

-- Subcuentas 5215
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '521505', 'INDUSTRIA Y COMERCIO', TRUE, 'ICA', '5215', FALSE, TRUE, FALSE),
(6, '521510', 'DE TIMBRES', TRUE, 'Timbres', '5215', FALSE, TRUE, FALSE),
(6, '521515', 'A LA PROPIEDAD RAIZ', TRUE, 'Predial', '5215', FALSE, TRUE, FALSE),
(6, '521520', 'DERECHOS SOBRE INSTRUMENTOS PUBLICOS', TRUE, 'Instrumentos públicos', '5215', FALSE, TRUE, FALSE),
(6, '521525', 'DE VALORIZACION', TRUE, 'Valorización', '5215', FALSE, TRUE, FALSE),
(6, '521530', 'DE TURISMO', TRUE, 'Turismo', '5215', FALSE, TRUE, FALSE),
(6, '521535', 'TASA POR UTILIZACION DE PUERTOS', TRUE, 'Puertos', '5215', FALSE, TRUE, FALSE),
(6, '521540', 'DE VEHICULOS', TRUE, 'Vehículos', '5215', FALSE, TRUE, FALSE),
(6, '521545', 'DE ESPECTACULOS PUBLICOS', TRUE, 'Espectáculos', '5215', FALSE, TRUE, FALSE),
(6, '521550', 'CUOTAS DE FOMENTO', TRUE, 'Cuotas fomento', '5215', FALSE, TRUE, FALSE),
(6, '521555', 'LICORES', TRUE, 'Licores', '5215', FALSE, TRUE, FALSE),
(6, '521560', 'CERVEZAS', TRUE, 'Cervezas', '5215', FALSE, TRUE, FALSE),
(6, '521565', 'CIGARRILLOS', TRUE, 'Cigarrillos', '5215', FALSE, TRUE, FALSE),
(6, '521570', 'IVA DESCONTABLE', TRUE, 'IVA descontable', '5215', FALSE, TRUE, FALSE),
(6, '521595', 'OTROS', TRUE, 'Otros impuestos', '5215', FALSE, TRUE, FALSE),
(6, '521599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación impuestos', '5215', FALSE, TRUE, FALSE);

-- Subcuentas 5220
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '522005', 'TERRENOS', TRUE, 'Arrendamiento terrenos', '5220', FALSE, TRUE, FALSE),
(6, '522010', 'CONSTRUCCIONES Y EDIFICACIONES', TRUE, 'Arrendamiento construcciones', '5220', FALSE, TRUE, FALSE),
(6, '522015', 'MAQUINARIA Y EQUIPO', TRUE, 'Arrendamiento maquinaria', '5220', FALSE, TRUE, FALSE),
(6, '522020', 'EQUIPO DE OFICINA', TRUE, 'Arrendamiento equipo oficina', '5220', FALSE, TRUE, FALSE),
(6, '522025', 'EQUIPO DE COMPUTACION Y COMUNICACION', TRUE, 'Arrendamiento cómputo', '5220', FALSE, TRUE, FALSE),
(6, '522030', 'EQUIPO MEDICO - CIENTIFICO', TRUE, 'Arrendamiento médico', '5220', FALSE, TRUE, FALSE),
(6, '522035', 'EQUIPO DE HOTELES Y RESTAURANTES', TRUE, 'Arrendamiento hoteles', '5220', FALSE, TRUE, FALSE),
(6, '522040', 'FLOTA Y EQUIPO DE TRANSPORTE', TRUE, 'Arrendamiento flota', '5220', FALSE, TRUE, FALSE),
(6, '522045', 'FLOTA Y EQUIPO FLUVIAL Y/O MARITIMO', TRUE, 'Arrendamiento fluvial', '5220', FALSE, TRUE, FALSE),
(6, '522050', 'FLOTA Y EQUIPO AEREO', TRUE, 'Arrendamiento aéreo', '5220', FALSE, TRUE, FALSE),
(6, '522055', 'FLOTA Y EQUIPO FERREO', TRUE, 'Arrendamiento férreo', '5220', FALSE, TRUE, FALSE),
(6, '522060', 'ACUEDUCTOS PLANTAS Y REDES', TRUE, 'Arrendamiento acueductos', '5220', FALSE, TRUE, FALSE),
(6, '522065', 'AERODROMOS', TRUE, 'Arrendamiento aeródromos', '5220', FALSE, TRUE, FALSE),
(6, '522070', 'SEMOVIENTES', TRUE, 'Arrendamiento semovientes', '5220', FALSE, TRUE, FALSE),
(6, '522095', 'OTROS', TRUE, 'Otros arrendamientos', '5220', FALSE, TRUE, FALSE),
(6, '522099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación arrendamientos', '5220', FALSE, TRUE, FALSE);

-- Subcuentas 5225
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '522505', 'CONTRIBUCIONES', TRUE, 'Contribuciones', '5225', FALSE, TRUE, FALSE),
(6, '522510', 'AFILIACIONES Y SOSTENIMIENTO', TRUE, 'Afiliaciones', '5225', FALSE, TRUE, FALSE),
(6, '522599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación contribuciones', '5225', FALSE, TRUE, FALSE);

-- Subcuentas 5230
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '523005', 'MANEJO', TRUE, 'Seguro manejo', '5230', FALSE, TRUE, FALSE),
(6, '523010', 'CUMPLIMIENTO', TRUE, 'Cumplimiento', '5230', FALSE, TRUE, FALSE),
(6, '523015', 'CORRIENTE DEBIL', TRUE, 'Corriente débil', '5230', FALSE, TRUE, FALSE),
(6, '523020', 'VIDA COLECTIVA', TRUE, 'Vida colectiva', '5230', FALSE, TRUE, FALSE),
(6, '523025', 'INCENDIO', TRUE, 'Incendio', '5230', FALSE, TRUE, FALSE),
(6, '523030', 'TERREMOTO', TRUE, 'Terremoto', '5230', FALSE, TRUE, FALSE),
(6, '523035', 'SUSTRACCION Y HURTO', TRUE, 'Sustracción', '5230', FALSE, TRUE, FALSE),
(6, '523040', 'FLOTA Y EQUIPO DE TRANSPORTE', TRUE, 'Flota', '5230', FALSE, TRUE, FALSE),
(6, '523045', 'FLOTA Y EQUIPO FLUVIAL Y/O MARITIMO', TRUE, 'Flota fluvial', '5230', FALSE, TRUE, FALSE),
(6, '523050', 'FLOTA Y EQUIPO AEREO', TRUE, 'Flota aérea', '5230', FALSE, TRUE, FALSE),
(6, '523055', 'FLOTA Y EQUIPO FERREO', TRUE, 'Flota férrea', '5230', FALSE, TRUE, FALSE),
(6, '523060', 'RESPONSABILIDAD CIVIL Y EXTRACONTRACTUAL', TRUE, 'Responsabilidad civil', '5230', FALSE, TRUE, FALSE),
(6, '523065', 'VUELO', TRUE, 'Vuelo', '5230', FALSE, TRUE, FALSE),
(6, '523070', 'ROTURA DE MAQUINARIA', TRUE, 'Rotura maquinaria', '5230', FALSE, TRUE, FALSE),
(6, '523075', 'OBLIGATORIO ACCIDENTE DE TRANSITO', TRUE, 'SOAT', '5230', FALSE, TRUE, FALSE),
(6, '523080', 'LUCRO CESANTE', TRUE, 'Lucro cesante', '5230', FALSE, TRUE, FALSE),
(6, '523095', 'OTROS', TRUE, 'Otros seguros', '5230', FALSE, TRUE, FALSE),
(6, '523099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación seguros', '5230', FALSE, TRUE, FALSE);

-- Subcuentas 5235
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '523505', 'ASEO Y VIGILANCIA', TRUE, 'Aseo y vigilancia', '5235', FALSE, TRUE, FALSE),
(6, '523510', 'TEMPORALES', TRUE, 'Temporales', '5235', FALSE, TRUE, FALSE),
(6, '523515', 'ASISTENCIA TECNICA', TRUE, 'Asistencia técnica', '5235', FALSE, TRUE, FALSE),
(6, '523520', 'PROCESAMIENTO ELECTRONICO DE DATOS', TRUE, 'Procesamiento datos', '5235', FALSE, TRUE, FALSE),
(6, '523525', 'ACUEDUCTO Y ALCANTARILLADO', TRUE, 'Acueducto', '5235', FALSE, TRUE, FALSE),
(6, '523530', 'ENERGIA ELECTRICA', TRUE, 'Energía', '5235', FALSE, TRUE, FALSE),
(6, '523535', 'TELEFONO', TRUE, 'Teléfono', '5235', FALSE, TRUE, FALSE),
(6, '523540', 'CORREO, PORTES Y TELEGRAMAS', TRUE, 'Correo', '5235', FALSE, TRUE, FALSE),
(6, '523545', 'FAX Y TELEX', TRUE, 'Fax y télex', '5235', FALSE, TRUE, FALSE),
(6, '523550', 'TRANSPORTE, FLETES Y ACARREOS', TRUE, 'Transporte', '5235', FALSE, TRUE, FALSE),
(6, '523555', 'GAS', TRUE, 'Gas', '5235', FALSE, TRUE, FALSE),
(6, '523560', 'PUBLICIDAD, PROPAGANDA Y PROMOCION', TRUE, 'Publicidad', '5235', FALSE, TRUE, FALSE),
(6, '523595', 'OTROS', TRUE, 'Otros servicios', '5235', FALSE, TRUE, FALSE),
(6, '523599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación servicios', '5235', FALSE, TRUE, FALSE);

-- Subcuentas 5240
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '524005', 'NOTARIALES', TRUE, 'Notariales', '5240', FALSE, TRUE, FALSE),
(6, '524010', 'REGISTRO MERCANTIL', TRUE, 'Registro mercantil', '5240', FALSE, TRUE, FALSE),
(6, '524015', 'TRAMITES Y LICENCIAS', TRUE, 'Trámites', '5240', FALSE, TRUE, FALSE),
(6, '524020', 'ADUANEROS', TRUE, 'Aduaneros', '5240', FALSE, TRUE, FALSE),
(6, '524025', 'CONSULARES', TRUE, 'Consulares', '5240', FALSE, TRUE, FALSE),
(6, '524095', 'OTROS', TRUE, 'Otros legales', '5240', FALSE, TRUE, FALSE),
(6, '524099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación legales', '5240', FALSE, TRUE, FALSE);

-- Subcuentas 5245
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '524505', 'TERRENOS', TRUE, 'Mantenimiento terrenos', '5245', FALSE, TRUE, FALSE),
(6, '524510', 'CONSTRUCCIONES Y EDIFICACIONES', TRUE, 'Mantenimiento construcciones', '5245', FALSE, TRUE, FALSE),
(6, '524515', 'MAQUINARIA Y EQUIPO', TRUE, 'Mantenimiento maquinaria', '5245', FALSE, TRUE, FALSE),
(6, '524520', 'EQUIPO DE OFICINA', TRUE, 'Mantenimiento equipo oficina', '5245', FALSE, TRUE, FALSE),
(6, '524525', 'EQUIPO DE COMPUTACION Y COMUNICACION', TRUE, 'Mantenimiento cómputo', '5245', FALSE, TRUE, FALSE),
(6, '524530', 'EQUIPO MEDICO - CIENTIFICO', TRUE, 'Mantenimiento médico', '5245', FALSE, TRUE, FALSE),
(6, '524535', 'EQUIPO DE HOTELES Y RESTAURANTES', TRUE, 'Mantenimiento hoteles', '5245', FALSE, TRUE, FALSE),
(6, '524540', 'FLOTA Y EQUIPO DE TRANSPORTE', TRUE, 'Mantenimiento flota', '5245', FALSE, TRUE, FALSE),
(6, '524545', 'FLOTA Y EQUIPO FLUVIAL Y/O MARITIMO', TRUE, 'Mantenimiento fluvial', '5245', FALSE, TRUE, FALSE),
(6, '524550', 'FLOTA Y EQUIPO AEREO', TRUE, 'Mantenimiento aéreo', '5245', FALSE, TRUE, FALSE),
(6, '524555', 'FLOTA Y EQUIPO FERREO', TRUE, 'Mantenimiento férreo', '5245', FALSE, TRUE, FALSE),
(6, '524560', 'ACUEDUCTOS PLANTAS Y REDES', TRUE, 'Mantenimiento acueductos', '5245', FALSE, TRUE, FALSE),
(6, '524565', 'ARMAMENTO DE VIGILANCIA', TRUE, 'Mantenimiento armamento', '5245', FALSE, TRUE, FALSE),
(6, '524570', 'VIAS DE COMUNICACION', TRUE, 'Mantenimiento vías', '5245', FALSE, TRUE, FALSE),
(6, '524599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación mantenimiento', '5245', FALSE, TRUE, FALSE);

-- Subcuentas 5250
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '525005', 'INSTALACIONES ELECTRICAS', TRUE, 'Instalaciones eléctricas', '5250', FALSE, TRUE, FALSE),
(6, '525010', 'ARREGLOS ORNAMENTALES', TRUE, 'Arreglos ornamentales', '5250', FALSE, TRUE, FALSE),
(6, '525015', 'REPARACIONES LOCATIVAS', TRUE, 'Reparaciones locativas', '5250', FALSE, TRUE, FALSE),
(6, '525095', 'OTROS', TRUE, 'Otros adecuación', '5250', FALSE, TRUE, FALSE),
(6, '525099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación adecuación', '5250', FALSE, TRUE, FALSE);

-- Subcuentas 5255
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '525505', 'ALOJAMIENTO Y MANUTENCION', TRUE, 'Alojamiento', '5255', FALSE, TRUE, FALSE),
(6, '525510', 'PASAJES FLUVIALES Y/O MARITIMOS', TRUE, 'Pasajes fluviales', '5255', FALSE, TRUE, FALSE),
(6, '525515', 'PASAJES AEREOS', TRUE, 'Pasajes aéreos', '5255', FALSE, TRUE, FALSE),
(6, '525520', 'PASAJES TERRESTRES', TRUE, 'Pasajes terrestres', '5255', FALSE, TRUE, FALSE),
(6, '525525', 'PASAJES FERREOS', TRUE, 'Pasajes férreos', '5255', FALSE, TRUE, FALSE),
(6, '525595', 'OTROS', TRUE, 'Otros gastos viaje', '5255', FALSE, TRUE, FALSE),
(6, '525599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación viaje', '5255', FALSE, TRUE, FALSE);

-- Subcuentas 5260
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '526005', 'CONSTRUCCIONES Y EDIFICACIONES', TRUE, 'Depreciación construcciones', '5260', FALSE, TRUE, FALSE),
(6, '526010', 'MAQUINARIA Y EQUIPO', TRUE, 'Depreciación maquinaria', '5260', FALSE, TRUE, FALSE),
(6, '526015', 'EQUIPO DE OFICINA', TRUE, 'Depreciación equipo oficina', '5260', FALSE, TRUE, FALSE),
(6, '526020', 'EQUIPO DE COMPUTACION Y COMUNICACION', TRUE, 'Depreciación cómputo', '5260', FALSE, TRUE, FALSE),
(6, '526025', 'EQUIPO MEDICO - CIENTIFICO', TRUE, 'Depreciación médico', '5260', FALSE, TRUE, FALSE),
(6, '526030', 'EQUIPO DE HOTELES Y RESTAURANTES', TRUE, 'Depreciación hoteles', '5260', FALSE, TRUE, FALSE),
(6, '526035', 'FLOTA Y EQUIPO DE TRANSPORTE', TRUE, 'Depreciación flota', '5260', FALSE, TRUE, FALSE),
(6, '526040', 'FLOTA Y EQUIPO FLUVIAL Y/O MARITIMO', TRUE, 'Depreciación fluvial', '5260', FALSE, TRUE, FALSE),
(6, '526045', 'FLOTA Y EQUIPO AEREO', TRUE, 'Depreciación aéreo', '5260', FALSE, TRUE, FALSE),
(6, '526050', 'FLOTA Y EQUIPO FERREO', TRUE, 'Depreciación férreo', '5260', FALSE, TRUE, FALSE),
(6, '526055', 'ACUEDUCTOS, PLANTAS Y REDES', TRUE, 'Depreciación acueductos', '5260', FALSE, TRUE, FALSE),
(6, '526060', 'ARMAMENTO DE VIGILANCIA', TRUE, 'Depreciación armamento', '5260', FALSE, TRUE, FALSE),
(6, '526065', 'ENVASES Y EMPAQUES', TRUE, 'Depreciación envases', '5260', FALSE, TRUE, FALSE),
(6, '526099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación depreciación', '5260', FALSE, TRUE, FALSE);

-- Subcuentas 5265
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '526505', 'VIAS DE COMUNICACION', TRUE, 'Amortización vías', '5265', FALSE, TRUE, FALSE),
(6, '526510', 'INTANGIBLES', TRUE, 'Amortización intangibles', '5265', FALSE, TRUE, FALSE),
(6, '526515', 'CARGOS DIFERIDOS', TRUE, 'Amortización cargos diferidos', '5265', FALSE, TRUE, FALSE),
(6, '526595', 'OTRAS', TRUE, 'Otras amortizaciones', '5265', FALSE, TRUE, FALSE),
(6, '526599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación amortizaciones', '5265', FALSE, TRUE, FALSE);

-- Subcuentas 5270
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '527001', 'FINANCIEROS REAJUSTE SISTEMA 527001 A 527098', TRUE, 'Reajuste sistema rango', '5270', FALSE, TRUE, FALSE),
(6, '527098', 'FINANCIEROS REAJUSTE SISTEMA FIN RANGO', TRUE, 'Reajuste sistema fin', '5270', FALSE, TRUE, FALSE),
(6, '527099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación reajuste', '5270', FALSE, TRUE, FALSE);

-- Subcuentas 5275
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '527505', 'DE SOCIEDADES ANONIMAS Y/O ASIMILADAS', TRUE, 'Pérdidas S.A.', '5275', FALSE, TRUE, FALSE),
(6, '527510', 'DE SOCIEDADES LIMITADAS Y/O ASIMILADAS', TRUE, 'Pérdidas Ltda', '5275', FALSE, TRUE, FALSE);

-- Subcuentas 5295
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '529505', 'COMISIONES', TRUE, 'Comisiones', '5295', FALSE, TRUE, FALSE),
(6, '529510', 'LIBROS, SUSCRIPCIONES, PERIODICOS Y REVISTAS', TRUE, 'Libros', '5295', FALSE, TRUE, FALSE),
(6, '529515', 'MUSICA AMBIENTAL', TRUE, 'Música', '5295', FALSE, TRUE, FALSE),
(6, '529520', 'GASTOS DE REPRESENTACION Y RELACIONES PUBLICAS', TRUE, 'Representación', '5295', FALSE, TRUE, FALSE),
(6, '529525', 'ELEMENTOS DE ASEO Y CAFETERIA', TRUE, 'Aseo', '5295', FALSE, TRUE, FALSE),
(6, '529530', 'UTILES, PAPELERIA Y FOTOCOPIAS', TRUE, 'Papelería', '5295', FALSE, TRUE, FALSE),
(6, '529535', 'COMBUSTIBLES Y LUBRICANTES', TRUE, 'Combustibles', '5295', FALSE, TRUE, FALSE),
(6, '529540', 'ENVASES Y EMPAQUES', TRUE, 'Envases', '5295', FALSE, TRUE, FALSE),
(6, '529545', 'TAXIS Y BUSES', TRUE, 'Taxis', '5295', FALSE, TRUE, FALSE),
(6, '529550', 'ESTAMPILLAS', TRUE, 'Estampillas', '5295', FALSE, TRUE, FALSE),
(6, '529555', 'MICROFILMACION', TRUE, 'Microfilmación', '5295', FALSE, TRUE, FALSE),
(6, '529560', 'CASINO Y RESTAURANTE', TRUE, 'Casino', '5295', FALSE, TRUE, FALSE),
(6, '529565', 'PARQUEADEROS', TRUE, 'Parqueaderos', '5295', FALSE, TRUE, FALSE),
(6, '529570', 'INDEMNIZACION POR DANOS A TERCEROS', TRUE, 'Indemnización', '5295', FALSE, TRUE, FALSE),
(6, '529575', 'POLVORA Y SIMILARES', TRUE, 'Pólvora', '5295', FALSE, TRUE, FALSE),
(6, '529595', 'OTROS', TRUE, 'Otros diversos', '5295', FALSE, TRUE, FALSE),
(6, '529599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación diversos', '5295', FALSE, TRUE, FALSE);

-- Subcuentas 5299
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '529905', 'INVERSIONES', TRUE, 'Provisión inversiones', '5299', FALSE, TRUE, FALSE),
(6, '529910', 'DEUDORES', TRUE, 'Provisión deudores', '5299', FALSE, TRUE, FALSE),
(6, '529915', 'INVENTARIOS', TRUE, 'Provisión inventarios', '5299', FALSE, TRUE, FALSE),
(6, '529920', 'PROPIEDADES, PLANTA Y EQUIPO', TRUE, 'Provisión PPE', '5299', FALSE, TRUE, FALSE),
(6, '529995', 'OTROS ACTIVOS', TRUE, 'Provisión otros activos', '5299', FALSE, TRUE, FALSE),
(6, '529999', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación provisiones', '5299', FALSE, TRUE, FALSE);

-- ============================================================
-- VERIFICACIÓN
-- ============================================================
-- SELECT COUNT(*) FROM tab_puc;
-- SELECT id_nivel, COUNT(*) FROM tab_puc GROUP BY id_nivel ORDER BY id_nivel;

-- ================================================================
-- PUC COLOMBIA - DECRETO 2650 DE 1993
-- ENTREGA 6: Clase 5 (53-59) + Clase 6 (Costos de Ventas)
-- ================================================================

-- ============================================================
-- GRUPO 53 — NO OPERACIONALES
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '53', 'NO OPERACIONALES', TRUE, 'Gastos no relacionados directamente con la explotación', '5', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '5305', 'FINANCIEROS', TRUE, 'Gastos financieros', '53', FALSE, TRUE, FALSE),
(4, '5310', 'PERDIDA EN VENTA Y RETIRO DE BIENES', TRUE, 'Pérdida venta y retiro de bienes', '53', FALSE, TRUE, FALSE),
(4, '5313', 'PERDIDAS METODO DE PARTICIPACION', TRUE, 'Pérdidas método participación', '53', FALSE, TRUE, FALSE),
(4, '5315', 'GASTOS EXTRAORDINARIOS', TRUE, 'Gastos extraordinarios', '53', FALSE, TRUE, FALSE),
(4, '5395', 'GASTOS DIVERSOS', TRUE, 'Gastos diversos', '53', FALSE, TRUE, FALSE);

-- Subcuentas 5305
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '530505', 'GASTOS BANCARIOS', TRUE, 'Gastos bancarios', '5305', FALSE, TRUE, FALSE),
(6, '530510', 'REAJUSTE MONETARIO - UPAC', TRUE, 'Reajuste UPAC', '5305', FALSE, TRUE, FALSE),
(6, '530515', 'COMISIONES', TRUE, 'Comisiones', '5305', FALSE, TRUE, FALSE),
(6, '530520', 'INTERESES', TRUE, 'Intereses', '5305', FALSE, TRUE, FALSE),
(6, '530525', 'DIFERENCIA EN CAMBIO', TRUE, 'Diferencia en cambio', '5305', FALSE, TRUE, FALSE),
(6, '530530', 'GASTOS EN NEGOCIACION CERTIFICADOS DE CAMBIO', TRUE, 'Gastos certificados cambio', '5305', FALSE, TRUE, FALSE),
(6, '530535', 'DESCUENTOS COMERCIALES CONDICIONADOS', TRUE, 'Descuentos comerciales', '5305', FALSE, TRUE, FALSE),
(6, '530540', 'GASTOS MANEJO Y EMISION DE BONOS', TRUE, 'Gastos bonos', '5305', FALSE, TRUE, FALSE),
(6, '530545', 'PRIMA AMORTIZADA', TRUE, 'Prima amortizada', '5305', FALSE, TRUE, FALSE),
(6, '530595', 'OTROS', TRUE, 'Otros financieros', '5305', FALSE, TRUE, FALSE),
(6, '530599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación financieros', '5305', FALSE, TRUE, FALSE);

-- Subcuentas 5310
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '531005', 'VENTA DE INVERSIONES', TRUE, 'Pérdida venta inversiones', '5310', FALSE, TRUE, FALSE),
(6, '531010', 'VENTA DE CARTERA', TRUE, 'Pérdida venta cartera', '5310', FALSE, TRUE, FALSE),
(6, '531015', 'VENTA DE PROPIEDADES PLANTA Y EQUIPO', TRUE, 'Pérdida venta PPE', '5310', FALSE, TRUE, FALSE),
(6, '531020', 'VENTA DE INTANGIBLES', TRUE, 'Pérdida venta intangibles', '5310', FALSE, TRUE, FALSE),
(6, '531025', 'VENTA DE OTROS ACTIVOS', TRUE, 'Pérdida venta otros', '5310', FALSE, TRUE, FALSE),
(6, '531030', 'RETIRO DE PROPIEDADES PLANTA Y EQUIPO', TRUE, 'Pérdida retiro PPE', '5310', FALSE, TRUE, FALSE),
(6, '531035', 'RETIRO DE OTROS ACTIVOS', TRUE, 'Pérdida retiro otros', '5310', FALSE, TRUE, FALSE),
(6, '531040', 'PERDIDAS POR SINIESTROS', TRUE, 'Pérdida siniestros', '5310', FALSE, TRUE, FALSE),
(6, '531095', 'OTROS', TRUE, 'Otros pérdidas', '5310', FALSE, TRUE, FALSE),
(6, '531099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación pérdidas', '5310', FALSE, TRUE, FALSE);

-- Subcuentas 5313
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '531305', 'DE SOCIEDADES ANONIMAS Y/O ASIMILADAS', TRUE, 'Pérdidas método participación S.A.', '5313', FALSE, TRUE, FALSE),
(6, '531310', 'DE SOCIEDADES LIMITADAS Y/O ASIMILADAS', TRUE, 'Pérdidas método participación Ltda', '5313', FALSE, TRUE, FALSE);

-- Subcuentas 5315
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '531505', 'COSTAS Y PROCESOS JUDICIALES', TRUE, 'Costas judiciales', '5315', FALSE, TRUE, FALSE),
(6, '531510', 'ACTIVIDADES CULTURALES Y CIVICAS', TRUE, 'Actividades culturales', '5315', FALSE, TRUE, FALSE),
(6, '531515', 'COSTOS Y GASTOS DE EJERCICIOS ANTERIORES', TRUE, 'Gastos ejercicios anteriores', '5315', FALSE, TRUE, FALSE),
(6, '531520', 'IMPUESTOS ASUMIDOS', TRUE, 'Impuestos asumidos', '5315', FALSE, TRUE, FALSE),
(6, '531595', 'OTROS', TRUE, 'Otros extraordinarios', '5315', FALSE, TRUE, FALSE),
(6, '531599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación extraordinarios', '5315', FALSE, TRUE, FALSE);

-- Subcuentas 5395
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '539505', 'DEMANDAS LABORALES', TRUE, 'Demandas laborales', '5395', FALSE, TRUE, FALSE),
(6, '539510', 'DEMANDAS POR INCUMPLIMIENTO DE CONTRATOS', TRUE, 'Demandas contratos', '5395', FALSE, TRUE, FALSE),
(6, '539515', 'INDEMNIZACIONES', TRUE, 'Indemnizaciones', '5395', FALSE, TRUE, FALSE),
(6, '539520', 'MULTAS, SANCIONES Y LITIGIOS', TRUE, 'Multas y sanciones', '5395', FALSE, TRUE, FALSE),
(6, '539525', 'DONACIONES', TRUE, 'Donaciones', '5395', FALSE, TRUE, FALSE),
(6, '539530', 'CONSTITUCION DE GARANTIAS', TRUE, 'Constitución garantías', '5395', FALSE, TRUE, FALSE),
(6, '539535', 'AMORTIZACION DE BIENES ENTREGADOS EN COMODATO', TRUE, 'Amortización comodato', '5395', FALSE, TRUE, FALSE),
(6, '539595', 'OTROS', TRUE, 'Otros gastos diversos', '5395', FALSE, TRUE, FALSE),
(6, '539599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación diversos', '5395', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 54 — IMPUESTO DE RENTA Y COMPLEMENTARIOS
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '54', 'IMPUESTO DE RENTA Y COMPLEMENTARIOS', TRUE, 'Impuesto de renta y complementarios', '5', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '5405', 'IMPUESTO DE RENTA Y COMPLEMENTARIOS', TRUE, 'Impuesto de renta', '54', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '540505', 'IMPUESTO DE RENTA Y COMPLEMENTARIOS', TRUE, 'Impuesto de renta', '5405', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 59 — GANANCIAS Y PERDIDAS
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '59', 'GANANCIAS Y PERDIDAS', TRUE, 'Cuenta de cierre de resultados', '5', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '5905', 'GANANCIAS Y PERDIDAS', TRUE, 'Utilidad o pérdida del ejercicio', '59', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '590505', 'GANANCIAS Y PERDIDAS', TRUE, 'Resultado del ejercicio', '5905', FALSE, TRUE, FALSE);

-- ============================================================
-- CLASE 6: COSTOS DE VENTAS (naturaleza DÉBITO)
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(1, '6', 'COSTOS DE VENTAS', TRUE, 'Costos directos e indirectos de los productos vendidos', '0', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 61 — COSTO DE VENTAS Y DE PRESTACION DE SERVICIOS
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '61', 'COSTO DE VENTAS Y DE PRESTACION DE SERVICIOS', TRUE, 'Monto asignado a artículos vendidos y servicios prestados', '6', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '6105', 'AGRICULTURA, GANADERIA, CAZA Y SILVICULTURA', TRUE, 'Costo agropecuario', '61', FALSE, TRUE, FALSE),
(4, '6110', 'PESCA', TRUE, 'Costo de pesca', '61', FALSE, TRUE, FALSE),
(4, '6115', 'EXPLOTACION DE MINAS Y CANTERAS', TRUE, 'Costo de explotación minera', '61', FALSE, TRUE, FALSE),
(4, '6120', 'INDUSTRIAS MANUFACTURERAS', TRUE, 'Costo manufacturero', '61', FALSE, TRUE, FALSE),
(4, '6125', 'SUMINISTRO DE ELECTRICIDAD, GAS Y AGUA', TRUE, 'Costo servicios públicos', '61', FALSE, TRUE, FALSE),
(4, '6130', 'CONSTRUCCION', TRUE, 'Costo de construcción', '61', FALSE, TRUE, FALSE),
(4, '6135', 'COMERCIO AL POR MAYOR Y AL POR MENOR', TRUE, 'Costo de comercio', '61', FALSE, TRUE, FALSE),
(4, '6140', 'HOTELES Y RESTAURANTES', TRUE, 'Costo hotelero y restaurantes', '61', FALSE, TRUE, FALSE),
(4, '6145', 'TRANSPORTE, ALMACENAMIENTO Y COMUNICACIONES', TRUE, 'Costo por transporte', '61', FALSE, TRUE, FALSE),
(4, '6150', 'ACTIVIDAD FINANCIERA', TRUE, 'Costo financiero', '61', FALSE, TRUE, FALSE),
(4, '6155', 'ACTIVIDADES INMOBILIARIAS, EMPRESARIALES Y DE ALQUILER', TRUE, 'Costo inmobiliario y alquiler', '61', FALSE, TRUE, FALSE),
(4, '6160', 'ENSEÑANZA', TRUE, 'Costo de enseñanza', '61', FALSE, TRUE, FALSE),
(4, '6165', 'SERVICIOS SOCIALES Y DE SALUD', TRUE, 'Costo social y salud', '61', FALSE, TRUE, FALSE),
(4, '6170', 'OTRAS ACTIVIDADES DE SERVICIOS COMUNITARIOS, SOCIALES Y PERSONALES', TRUE, 'Otros costos', '61', FALSE, TRUE, FALSE);

-- Subcuentas 6105
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '610505', 'CULTIVO DE CEREALES', TRUE, 'Costo cereales', '6105', FALSE, TRUE, FALSE),
(6, '610510', 'CULTIVOS DE HORTALIZAS, LEGUMBRES Y PLANTAS ORNAMENTALES', TRUE, 'Costo hortalizas', '6105', FALSE, TRUE, FALSE),
(6, '610515', 'CULTIVOS DE FRUTAS, NUECES Y PLANTAS AROMATICAS', TRUE, 'Costo frutas', '6105', FALSE, TRUE, FALSE),
(6, '610520', 'CULTIVO DE CAFE', TRUE, 'Costo café', '6105', FALSE, TRUE, FALSE),
(6, '610525', 'CULTIVO DE FLORES', TRUE, 'Costo flores', '6105', FALSE, TRUE, FALSE),
(6, '610530', 'CULTIVO DE CAÑA DE AZUCAR', TRUE, 'Costo caña', '6105', FALSE, TRUE, FALSE),
(6, '610535', 'CULTIVO DE ALGODON Y PLANTAS PARA MATERIAL TEXTIL', TRUE, 'Costo algodón', '6105', FALSE, TRUE, FALSE),
(6, '610540', 'CULTIVO DE BANANO', TRUE, 'Costo banano', '6105', FALSE, TRUE, FALSE),
(6, '610545', 'OTROS CULTIVOS AGRICOLAS', TRUE, 'Otros cultivos', '6105', FALSE, TRUE, FALSE),
(6, '610550', 'CRIA DE OVEJAS, CABRAS, ASNOS, MULAS Y BURDEGANOS', TRUE, 'Cría ovejas', '6105', FALSE, TRUE, FALSE),
(6, '610555', 'CRIA DE GANADO CABALLAR Y VACUNO', TRUE, 'Cría ganado', '6105', FALSE, TRUE, FALSE),
(6, '610560', 'PRODUCCION AVICOLA', TRUE, 'Avicultura', '6105', FALSE, TRUE, FALSE),
(6, '610565', 'CRIA DE OTROS ANIMALES', TRUE, 'Otras crías', '6105', FALSE, TRUE, FALSE),
(6, '610570', 'SERVICIOS AGRICOLAS Y GANADEROS', TRUE, 'Servicios agro', '6105', FALSE, TRUE, FALSE),
(6, '610575', 'ACTIVIDAD DE CAZA', TRUE, 'Caza', '6105', FALSE, TRUE, FALSE),
(6, '610580', 'ACTIVIDAD DE SILVICULTURA', TRUE, 'Silvicultura', '6105', FALSE, TRUE, FALSE),
(6, '610595', 'ACTIVIDADES CONEXAS', TRUE, 'Actividades conexas', '6105', FALSE, TRUE, FALSE),
(6, '610599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación agro', '6105', FALSE, TRUE, FALSE);

-- Subcuentas 6110
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '611005', 'ACTIVIDAD DE PESCA', TRUE, 'Pesca', '6110', FALSE, TRUE, FALSE),
(6, '611010', 'EXPLOTACION DE CRIADEROS DE PECES', TRUE, 'Criaderos', '6110', FALSE, TRUE, FALSE),
(6, '611095', 'ACTIVIDADES CONEXAS', TRUE, 'Actividades conexas pesca', '6110', FALSE, TRUE, FALSE),
(6, '611099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación pesca', '6110', FALSE, TRUE, FALSE);

-- Subcuentas 6115
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '611505', 'CARBON', TRUE, 'Carbón', '6115', FALSE, TRUE, FALSE),
(6, '611510', 'PETROLEO CRUDO', TRUE, 'Petróleo', '6115', FALSE, TRUE, FALSE),
(6, '611512', 'GAS NATURAL', TRUE, 'Gas natural', '6115', FALSE, TRUE, FALSE),
(6, '611514', 'SERVICIOS RELACIONADOS CON EXTRACCION DE PETROLEO Y GAS', TRUE, 'Servicios extracción', '6115', FALSE, TRUE, FALSE),
(6, '611515', 'MINERALES DE HIERRO', TRUE, 'Minerales hierro', '6115', FALSE, TRUE, FALSE),
(6, '611520', 'MINERALES METALIFEROS NO FERROSOS', TRUE, 'Minerales no ferrosos', '6115', FALSE, TRUE, FALSE),
(6, '611525', 'PIEDRA, ARENA Y ARCILLA', TRUE, 'Piedra y arena', '6115', FALSE, TRUE, FALSE),
(6, '611527', 'PIEDRAS PRECIOSAS', TRUE, 'Piedras preciosas', '6115', FALSE, TRUE, FALSE),
(6, '611528', 'ORO', TRUE, 'Oro', '6115', FALSE, TRUE, FALSE),
(6, '611530', 'OTRAS MINAS Y CANTERAS', TRUE, 'Otras minas', '6115', FALSE, TRUE, FALSE),
(6, '611532', 'PRESTACION DE SERVICIOS SECTOR MINERO', TRUE, 'Servicios mineros', '6115', FALSE, TRUE, FALSE),
(6, '611595', 'ACTIVIDADES CONEXAS', TRUE, 'Actividades conexas', '6115', FALSE, TRUE, FALSE),
(6, '611599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación minas', '6115', FALSE, TRUE, FALSE);

-- Subcuentas 6120
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '612001', 'PRODUCCION Y PROCESAMIENTO DE CARNES Y PRODUCTOS CARNICOS', TRUE, 'Carnes', '6120', FALSE, TRUE, FALSE),
(6, '612002', 'PRODUCTOS DE PESCADO', TRUE, 'Pescado', '6120', FALSE, TRUE, FALSE),
(6, '612003', 'PRODUCTOS DE FRUTAS, LEGUMBRES Y HORTALIZAS', TRUE, 'Frutas', '6120', FALSE, TRUE, FALSE),
(6, '612004', 'ELABORACION DE ACEITES Y GRASAS', TRUE, 'Aceites', '6120', FALSE, TRUE, FALSE),
(6, '612005', 'ELABORACION DE PRODUCTOS LACTEOS', TRUE, 'Lácteos', '6120', FALSE, TRUE, FALSE),
(6, '612006', 'ELABORACION DE PRODUCTOS DE MOLINERIA', TRUE, 'Molineria', '6120', FALSE, TRUE, FALSE),
(6, '612007', 'ELABORACION DE ALMIDONES Y DERIVADOS', TRUE, 'Almidones', '6120', FALSE, TRUE, FALSE),
(6, '612008', 'ELABORACION DE ALIMENTOS PARA ANIMALES', TRUE, 'Alimentos animales', '6120', FALSE, TRUE, FALSE),
(6, '612009', 'ELABORACION DE PRODUCTOS PARA PANADERIA', TRUE, 'Panadería', '6120', FALSE, TRUE, FALSE),
(6, '612010', 'ELABORACION DE AZUCAR Y MELAZAS', TRUE, 'Azúcar', '6120', FALSE, TRUE, FALSE),
(6, '612011', 'ELABORACION DE CACAO, CHOCOLATE Y CONFITERIA', TRUE, 'Cacao', '6120', FALSE, TRUE, FALSE),
(6, '612012', 'ELABORACION DE PASTAS Y PRODUCTOS FARINACEOS', TRUE, 'Pastas', '6120', FALSE, TRUE, FALSE),
(6, '612013', 'ELABORACION DE PRODUCTOS DE CAFE', TRUE, 'Café procesado', '6120', FALSE, TRUE, FALSE),
(6, '612014', 'ELABORACION DE OTROS PRODUCTOS ALIMENTICIOS', TRUE, 'Otros alimentos', '6120', FALSE, TRUE, FALSE),
(6, '612015', 'ELABORACION DE BEBIDAS ALCOHOLICAS Y ALCOHOL ETILICO', TRUE, 'Bebidas alcohólicas', '6120', FALSE, TRUE, FALSE),
(6, '612016', 'ELABORACION DE VINOS', TRUE, 'Vinos', '6120', FALSE, TRUE, FALSE),
(6, '612017', 'ELABORACION DE BEBIDAS MALTEADAS Y DE MALTA', TRUE, 'Malta', '6120', FALSE, TRUE, FALSE),
(6, '612018', 'ELABORACION DE BEBIDAS NO ALCOHOLICAS', TRUE, 'Bebidas no alcohólicas', '6120', FALSE, TRUE, FALSE),
(6, '612019', 'ELABORACION DE PRODUCTOS DE TABACO', TRUE, 'Tabaco', '6120', FALSE, TRUE, FALSE),
(6, '612020', 'PREPARACION E HILATURA DE FIBRAS TEXTILES Y TEJEDURIA', TRUE, 'Fibras', '6120', FALSE, TRUE, FALSE),
(6, '612021', 'ACABADO DE PRODUCTOS TEXTILES', TRUE, 'Acabado textiles', '6120', FALSE, TRUE, FALSE),
(6, '612022', 'ELABORACION DE ARTICULOS DE MATERIALES TEXTILES', TRUE, 'Textiles', '6120', FALSE, TRUE, FALSE),
(6, '612023', 'ELABORACION DE TAPICES Y ALFOMBRAS', TRUE, 'Tapices', '6120', FALSE, TRUE, FALSE),
(6, '612024', 'ELABORACION DE CUERDAS, CORDELES, BRAMANTES Y REDES', TRUE, 'Cuerdas', '6120', FALSE, TRUE, FALSE),
(6, '612025', 'ELABORACION DE OTROS PRODUCTOS TEXTILES', TRUE, 'Otros textiles', '6120', FALSE, TRUE, FALSE),
(6, '612026', 'ELABORACION DE TEJIDOS', TRUE, 'Tejidos', '6120', FALSE, TRUE, FALSE),
(6, '612027', 'ELABORACION DE PRENDAS DE VESTIR', TRUE, 'Prendas vestir', '6120', FALSE, TRUE, FALSE),
(6, '612028', 'PREPARACION, ADOBO Y TEÑIDO DE PIELES', TRUE, 'Pieles', '6120', FALSE, TRUE, FALSE),
(6, '612029', 'CURTIDO, ADOBO O PREPARACION DE CUERO', TRUE, 'Cuero', '6120', FALSE, TRUE, FALSE),
(6, '612030', 'ELABORACION DE MALETAS, BOLSOS Y SIMILARES', TRUE, 'Maletas', '6120', FALSE, TRUE, FALSE),
(6, '612031', 'ELABORACION DE CALZADO', TRUE, 'Calzado', '6120', FALSE, TRUE, FALSE),
(6, '612032', 'PRODUCCION DE MADERA, ARTICULOS DE MADERA Y CORCHO', TRUE, 'Madera', '6120', FALSE, TRUE, FALSE),
(6, '612033', 'ELABORACION DE PASTA Y PRODUCTOS DE MADERA, PAPEL Y CARTON', TRUE, 'Papel', '6120', FALSE, TRUE, FALSE),
(6, '612034', 'EDICIONES Y PUBLICACIONES', TRUE, 'Ediciones', '6120', FALSE, TRUE, FALSE),
(6, '612035', 'IMPRESION', TRUE, 'Impresión', '6120', FALSE, TRUE, FALSE),
(6, '612036', 'SERVICIOS RELACIONADOS CON LA EDICION Y LA IMPRESION', TRUE, 'Servicios edición', '6120', FALSE, TRUE, FALSE),
(6, '612037', 'REPRODUCCION DE GRABACIONES', TRUE, 'Reproducción', '6120', FALSE, TRUE, FALSE),
(6, '612038', 'ELABORACION DE PRODUCTOS DE HORNO DE COQUE', TRUE, 'Coque', '6120', FALSE, TRUE, FALSE),
(6, '612039', 'ELABORACION DE PRODUCTOS DE LA REFINACION DE PETROLEO', TRUE, 'Refinación', '6120', FALSE, TRUE, FALSE),
(6, '612040', 'ELABORACION DE SUSTANCIAS QUIMICAS BASICAS', TRUE, 'Químicas', '6120', FALSE, TRUE, FALSE),
(6, '612041', 'ELABORACION DE ABONOS Y COMPUESTOS DE NITROGENO', TRUE, 'Abonos', '6120', FALSE, TRUE, FALSE),
(6, '612042', 'ELABORACION DE PLASTICO Y CAUCHO SINTETICO', TRUE, 'Plástico', '6120', FALSE, TRUE, FALSE),
(6, '612043', 'ELABORACION DE PRODUCTOS QUIMICOS DE USO AGROPECUARIO', TRUE, 'Químicos agro', '6120', FALSE, TRUE, FALSE),
(6, '612044', 'ELABORACION DE PINTURAS, TINTAS Y MASILLAS', TRUE, 'Pinturas', '6120', FALSE, TRUE, FALSE),
(6, '612045', 'ELABORACION DE PRODUCTOS FARMACEUTICOS Y BOTANICOS', TRUE, 'Farmacéuticos', '6120', FALSE, TRUE, FALSE),
(6, '612046', 'ELABORACION DE JABONES, DETERGENTES Y PREPARADOS DE TOCADOR', TRUE, 'Jabones', '6120', FALSE, TRUE, FALSE),
(6, '612047', 'ELABORACION DE OTROS PRODUCTOS QUIMICOS', TRUE, 'Otros químicos', '6120', FALSE, TRUE, FALSE),
(6, '612048', 'ELABORACION DE FIBRAS', TRUE, 'Fibras sintéticas', '6120', FALSE, TRUE, FALSE),
(6, '612049', 'ELABORACION DE OTROS PRODUCTOS DE CAUCHO', TRUE, 'Caucho', '6120', FALSE, TRUE, FALSE),
(6, '612050', 'ELABORACION DE PRODUCTOS DE PLASTICO', TRUE, 'Productos plástico', '6120', FALSE, TRUE, FALSE),
(6, '612051', 'ELABORACION DE VIDRIO Y PRODUCTOS DE VIDRIO', TRUE, 'Vidrio', '6120', FALSE, TRUE, FALSE),
(6, '612052', 'ELABORACION DE PRODUCTOS DE CERAMICA, LOZA, PIEDRA, ARCILLA Y PORCELANA', TRUE, 'Cerámica', '6120', FALSE, TRUE, FALSE),
(6, '612053', 'ELABORACION DE CEMENTO, CAL Y YESO', TRUE, 'Cemento', '6120', FALSE, TRUE, FALSE),
(6, '612054', 'ELABORACION DE ARTICULOS DE HORMIGON, CEMENTO Y YESO', TRUE, 'Hormigón', '6120', FALSE, TRUE, FALSE),
(6, '612055', 'CORTE, TALLADO Y ACABADO DE LA PIEDRA', TRUE, 'Piedra', '6120', FALSE, TRUE, FALSE),
(6, '612056', 'ELABORACION DE OTROS PRODUCTOS MINERALES NO METALICOS', TRUE, 'Minerales no metálicos', '6120', FALSE, TRUE, FALSE),
(6, '612057', 'INDUSTRIAS BASICAS Y FUNDICION DE HIERRO Y ACERO', TRUE, 'Hierro', '6120', FALSE, TRUE, FALSE),
(6, '612058', 'PRODUCTOS PRIMARIOS DE METALES PRECIOSOS Y DE METALES NO FERROSOS', TRUE, 'Metales preciosos', '6120', FALSE, TRUE, FALSE),
(6, '612059', 'FUNDICION DE METALES NO FERROSOS', TRUE, 'Fundición', '6120', FALSE, TRUE, FALSE),
(6, '612060', 'FABRICACION DE PRODUCTOS METALICOS PARA USO ESTRUCTURAL', TRUE, 'Metálicos', '6120', FALSE, TRUE, FALSE),
(6, '612061', 'FORJA, PRENSADO, ESTAMPADO, LAMINADO DE METAL Y PULVIMETALURGIA', TRUE, 'Forja', '6120', FALSE, TRUE, FALSE),
(6, '612062', 'REVESTIMIENTO DE METALES Y OBRAS DE INGENIERIA MECANICA', TRUE, 'Revestimiento', '6120', FALSE, TRUE, FALSE),
(6, '612063', 'FABRICACION DE ARTICULOS DE FERRETERIA', TRUE, 'Ferretería', '6120', FALSE, TRUE, FALSE),
(6, '612064', 'ELABORACION DE OTROS PRODUCTOS DE METAL', TRUE, 'Otros metálicos', '6120', FALSE, TRUE, FALSE),
(6, '612065', 'FABRICACION DE MAQUINARIA Y EQUIPO', TRUE, 'Maquinaria', '6120', FALSE, TRUE, FALSE),
(6, '612066', 'FABRICACION DE EQUIPOS DE ELEVACION Y MANIPULACION', TRUE, 'Elevación', '6120', FALSE, TRUE, FALSE),
(6, '612067', 'ELABORACION DE APARATOS DE USO DOMESTICO', TRUE, 'Domésticos', '6120', FALSE, TRUE, FALSE),
(6, '612068', 'ELABORACION DE EQUIPO DE OFICINA', TRUE, 'Equipo oficina', '6120', FALSE, TRUE, FALSE),
(6, '612069', 'ELABORACION DE PILAS Y BATERIAS PRIMARIAS', TRUE, 'Pilas', '6120', FALSE, TRUE, FALSE),
(6, '612070', 'ELABORACION DE EQUIPO DE ILUMINACION', TRUE, 'Iluminación', '6120', FALSE, TRUE, FALSE),
(6, '612071', 'ELABORACION DE OTROS TIPOS DE EQUIPO ELECTRICO', TRUE, 'Equipo eléctrico', '6120', FALSE, TRUE, FALSE),
(6, '612072', 'FABRICACION DE EQUIPOS DE RADIO, TELEVISION Y COMUNICACIONES', TRUE, 'Radio y TV', '6120', FALSE, TRUE, FALSE),
(6, '612073', 'FABRICACION DE APARATOS E INSTRUMENTOS MEDICOS', TRUE, 'Aparatos médicos', '6120', FALSE, TRUE, FALSE),
(6, '612074', 'FABRICACION DE INSTRUMENTOS DE MEDICION Y CONTROL', TRUE, 'Medición', '6120', FALSE, TRUE, FALSE),
(6, '612075', 'FABRICACION DE INSTRUMENTOS DE OPTICA Y EQUIPO FOTOGRAFICO', TRUE, 'Óptica', '6120', FALSE, TRUE, FALSE),
(6, '612076', 'FABRICACION DE RELOJES', TRUE, 'Relojes', '6120', FALSE, TRUE, FALSE),
(6, '612077', 'FABRICACION DE VEHICULOS AUTOMOTORES', TRUE, 'Vehículos', '6120', FALSE, TRUE, FALSE),
(6, '612078', 'FABRICACION DE CARROCERIAS PARA AUTOMOTORES', TRUE, 'Carrocerías', '6120', FALSE, TRUE, FALSE),
(6, '612079', 'FABRICACION DE PARTES PIEZAS Y ACCESORIOS PARA AUTOMOTORES', TRUE, 'Partes autos', '6120', FALSE, TRUE, FALSE),
(6, '612080', 'FABRICACION Y REPARACION DE BUQUES Y OTRAS EMBARCACIONES', TRUE, 'Buques', '6120', FALSE, TRUE, FALSE),
(6, '612081', 'FABRICACION DE LOCOMOTORAS Y MATERIAL RODANTE PARA FERROCARRILES', TRUE, 'Locomotoras', '6120', FALSE, TRUE, FALSE),
(6, '612082', 'FABRICACION DE AERONAVES', TRUE, 'Aeronaves', '6120', FALSE, TRUE, FALSE),
(6, '612083', 'FABRICACION DE MOTOCICLETAS', TRUE, 'Motocicletas', '6120', FALSE, TRUE, FALSE),
(6, '612084', 'FABRICACION DE BICICLETAS Y SILLAS DE RUEDAS', TRUE, 'Bicicletas', '6120', FALSE, TRUE, FALSE),
(6, '612085', 'FABRICACION DE OTROS TIPOS DE TRANSPORTE', TRUE, 'Otros transportes', '6120', FALSE, TRUE, FALSE),
(6, '612086', 'FABRICACION DE MUEBLES', TRUE, 'Muebles', '6120', FALSE, TRUE, FALSE),
(6, '612087', 'FABRICACION DE JOYAS Y ARTICULOS CONEXOS', TRUE, 'Joyas', '6120', FALSE, TRUE, FALSE),
(6, '612088', 'FABRICACION DE INSTRUMENTOS DE MUSICA', TRUE, 'Instr. musicales', '6120', FALSE, TRUE, FALSE),
(6, '612089', 'FABRICACION DE ARTICULOS Y EQUIPO PARA DEPORTE', TRUE, 'Deporte', '6120', FALSE, TRUE, FALSE),
(6, '612090', 'FABRICACION DE JUEGOS Y JUGUETES', TRUE, 'Juegos', '6120', FALSE, TRUE, FALSE),
(6, '612091', 'RECICLAMIENTO DE DESPERDICIOS', TRUE, 'Reciclaje', '6120', FALSE, TRUE, FALSE),
(6, '612095', 'PRODUCTOS DE OTRAS INDUSTRIAS MANUFACTURERAS', TRUE, 'Otras manufacturas', '6120', FALSE, TRUE, FALSE),
(6, '612099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación manufactura', '6120', FALSE, TRUE, FALSE);

-- Subcuentas 6125
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '612505', 'GENERACION, CAPTACION Y DISTRIBUCION DE ENERGIA ELECTRICA', TRUE, 'Energía', '6125', FALSE, TRUE, FALSE),
(6, '612510', 'FABRICACION DE GAS Y DISTRIBUCION DE COMBUSTIBLES GASEOSOS', TRUE, 'Gas', '6125', FALSE, TRUE, FALSE),
(6, '612515', 'CAPTACION, DEPURACION Y DISTRIBUCION DE AGUA', TRUE, 'Agua', '6125', FALSE, TRUE, FALSE),
(6, '612595', 'ACTIVIDADES CONEXAS', TRUE, 'Actividades conexas', '6125', FALSE, TRUE, FALSE),
(6, '612599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación servicios', '6125', FALSE, TRUE, FALSE);

-- Subcuentas 6130
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '613005', 'PREPARACION DE TERRENOS', TRUE, 'Preparación terrenos', '6130', FALSE, TRUE, FALSE),
(6, '613010', 'CONSTRUCCION DE EDIFICIOS Y OBRAS DE INGENIERIA CIVIL', TRUE, 'Construcción', '6130', FALSE, TRUE, FALSE),
(6, '613015', 'ACONDICIONAMIENTO DE EDIFICIOS', TRUE, 'Acondicionamiento', '6130', FALSE, TRUE, FALSE),
(6, '613020', 'TERMINACION DE EDIFICACIONES', TRUE, 'Terminación', '6130', FALSE, TRUE, FALSE),
(6, '613025', 'ALQUILER DE EQUIPO CON OPERARIO', TRUE, 'Alquiler equipo', '6130', FALSE, TRUE, FALSE),
(6, '613095', 'ACTIVIDADES CONEXAS', TRUE, 'Actividades conexas', '6130', FALSE, TRUE, FALSE),
(6, '613099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación construcción', '6130', FALSE, TRUE, FALSE);

-- Subcuentas 6135
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '613502', 'VENTA DE VEHICULOS AUTOMOTORES', TRUE, 'Venta vehículos', '6135', FALSE, TRUE, FALSE),
(6, '613504', 'MANTENIMIENTO, REPARACION Y LAVADO DE VEHICULOS AUTOMOTORES', TRUE, 'Mantenimiento vehículos', '6135', FALSE, TRUE, FALSE),
(6, '613506', 'VENTA DE PARTES, PIEZAS Y ACCESORIOS DE VEHICULOS AUTOMOTORES', TRUE, 'Partes vehículos', '6135', FALSE, TRUE, FALSE),
(6, '613508', 'VENTA DE COMBUSTIBLES SOLIDOS, LIQUIDOS, GASEOSOS', TRUE, 'Combustibles', '6135', FALSE, TRUE, FALSE),
(6, '613510', 'VENTA DE LUBRICANTES, ADITIVOS, LLANTAS Y LUJOS PARA AUTOMOTORES', TRUE, 'Lubricantes', '6135', FALSE, TRUE, FALSE),
(6, '613512', 'VENTA A CAMBIO DE RETRIBUCION O POR CONTRATA', TRUE, 'Venta contrata', '6135', FALSE, TRUE, FALSE),
(6, '613514', 'VENTA DE INSUMOS, MATERIAS PRIMAS AGROPECUARIAS Y FLORES', TRUE, 'Insumos agro', '6135', FALSE, TRUE, FALSE),
(6, '613516', 'VENTA DE OTROS INSUMOS Y MATERIAS PRIMAS NO AGROPECUARIAS', TRUE, 'Otros insumos', '6135', FALSE, TRUE, FALSE),
(6, '613518', 'VENTA DE ANIMALES VIVOS Y CUEROS', TRUE, 'Animales', '6135', FALSE, TRUE, FALSE),
(6, '613520', 'VENTA DE PRODUCTOS EN ALMACENES NO ESPECIALIZADOS', TRUE, 'No especializados', '6135', FALSE, TRUE, FALSE),
(6, '613522', 'VENTA DE PRODUCTOS AGROPECUARIOS', TRUE, 'Agropecuarios', '6135', FALSE, TRUE, FALSE),
(6, '613524', 'VENTA DE PRODUCTOS TEXTILES, DE VESTIR, DE CUERO Y CALZADO', TRUE, 'Textiles', '6135', FALSE, TRUE, FALSE),
(6, '613526', 'VENTA DE PAPEL Y CARTON', TRUE, 'Papel', '6135', FALSE, TRUE, FALSE),
(6, '613528', 'VENTA DE LIBROS, REVISTAS, ELEMENTOS DE PAPELERIA, UTILES Y TEXTOS ESCOLARES', TRUE, 'Libros', '6135', FALSE, TRUE, FALSE),
(6, '613530', 'VENTA DE JUEGOS, JUGUETES Y ARTICULOS DEPORTIVOS', TRUE, 'Juegos', '6135', FALSE, TRUE, FALSE),
(6, '613532', 'VENTA DE INSTRUMENTOS QUIRURGICOS Y ORTOPEDICOS', TRUE, 'Quirúrgicos', '6135', FALSE, TRUE, FALSE),
(6, '613534', 'VENTA DE ARTICULOS EN RELOJERIAS Y JOYERIAS', TRUE, 'Relojerías', '6135', FALSE, TRUE, FALSE),
(6, '613536', 'VENTA DE ELECTRODOMESTICOS Y MUEBLES', TRUE, 'Electrodomésticos', '6135', FALSE, TRUE, FALSE),
(6, '613538', 'VENTA DE PRODUCTOS DE ASEO, FARMACEUTICOS, MEDICINALES, Y ARTICULOS DE TOCADOR', TRUE, 'Aseo y farmacia', '6135', FALSE, TRUE, FALSE),
(6, '613540', 'VENTA DE CUBIERTOS, VAJILLAS, CRISTALERIA, PORCELANAS, CERAMICAS Y OTROS ARTICULOS DE USO DOMESTICO', TRUE, 'Vajillas', '6135', FALSE, TRUE, FALSE),
(6, '613542', 'VENTA DE MATERIALES DE CONSTRUCCION, FONTANERIA Y CALEFACCION', TRUE, 'Materiales', '6135', FALSE, TRUE, FALSE),
(6, '613544', 'VENTA DE PINTURAS Y LACAS', TRUE, 'Pinturas', '6135', FALSE, TRUE, FALSE),
(6, '613546', 'VENTA DE PRODUCTOS DE VIDRIOS Y MARQUETERIA', TRUE, 'Vidrios', '6135', FALSE, TRUE, FALSE),
(6, '613548', 'VENTA DE HERRAMIENTAS Y ARTICULOS DE FERRETERIA', TRUE, 'Herramientas', '6135', FALSE, TRUE, FALSE),
(6, '613550', 'VENTA DE QUIMICOS', TRUE, 'Químicos', '6135', FALSE, TRUE, FALSE),
(6, '613552', 'VENTA DE PRODUCTOS INTERMEDIOS, DESPERDICIOS Y DESECHOS', TRUE, 'Desperdicios', '6135', FALSE, TRUE, FALSE),
(6, '613554', 'VENTA DE MAQUINARIA, EQUIPO DE OFICINA Y PROGRAMAS DE COMPUTADOR', TRUE, 'Maquinaria', '6135', FALSE, TRUE, FALSE),
(6, '613556', 'VENTA DE ARTICULOS EN CACHARRERIAS Y MISCELANEAS', TRUE, 'Cacharrerías', '6135', FALSE, TRUE, FALSE),
(6, '613558', 'VENTA DE INSTRUMENTOS MUSICALES', TRUE, 'Musicales', '6135', FALSE, TRUE, FALSE),
(6, '613560', 'VENTA DE ARTICULOS EN CASAS DE EMPEÑO Y PRENDERIAS', TRUE, 'Empeños', '6135', FALSE, TRUE, FALSE),
(6, '613562', 'VENTA DE EQUIPO FOTOGRAFICO', TRUE, 'Fotográfico', '6135', FALSE, TRUE, FALSE),
(6, '613564', 'VENTA DE EQUIPO OPTICO Y DE PRECISION', TRUE, 'Óptico', '6135', FALSE, TRUE, FALSE),
(6, '613566', 'VENTA DE EMPAQUES', TRUE, 'Empaques', '6135', FALSE, TRUE, FALSE),
(6, '613568', 'VENTA DE EQUIPO PROFESIONAL Y CIENTIFICO', TRUE, 'Científico', '6135', FALSE, TRUE, FALSE),
(6, '613570', 'VENTA DE LOTERIAS, RIFAS, CHANCE, APUESTAS Y SIMILARES', TRUE, 'Loterías', '6135', FALSE, TRUE, FALSE),
(6, '613572', 'REPARACION DE EFECTOS PERSONALES Y ELECTRODOMESTICOS', TRUE, 'Reparaciones', '6135', FALSE, TRUE, FALSE),
(6, '613595', 'VENTA DE OTROS PRODUCTOS', TRUE, 'Otros productos', '6135', FALSE, TRUE, FALSE),
(6, '613599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación comercio', '6135', FALSE, TRUE, FALSE);

-- Subcuentas 6140
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '614005', 'HOTELERIA', TRUE, 'Hotelería', '6140', FALSE, TRUE, FALSE),
(6, '614010', 'CAMPAMENTO Y OTROS TIPOS DE HOSPEDAJE', TRUE, 'Campamentos', '6140', FALSE, TRUE, FALSE),
(6, '614015', 'RESTAURANTES', TRUE, 'Restaurantes', '6140', FALSE, TRUE, FALSE),
(6, '614020', 'BARES Y CANTINAS', TRUE, 'Bares', '6140', FALSE, TRUE, FALSE),
(6, '614095', 'ACTIVIDADES CONEXAS', TRUE, 'Actividades conexas', '6140', FALSE, TRUE, FALSE),
(6, '614099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación hotelería', '6140', FALSE, TRUE, FALSE);

-- Subcuentas 6145
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '614505', 'SERVICIO DE TRANSPORTE POR CARRETERA', TRUE, 'Transporte carretera', '6145', FALSE, TRUE, FALSE),
(6, '614510', 'SERVICIO DE TRANSPORTE POR VIA FERREA', TRUE, 'Transporte férreo', '6145', FALSE, TRUE, FALSE),
(6, '614515', 'SERVICIO DE TRANSPORTE POR VIA ACUATICA', TRUE, 'Transporte acuático', '6145', FALSE, TRUE, FALSE),
(6, '614520', 'SERVICIO DE TRANSPORTE POR VIA AEREA', TRUE, 'Transporte aéreo', '6145', FALSE, TRUE, FALSE),
(6, '614525', 'SERVICIO DE TRANSPORTE POR TUBERIAS', TRUE, 'Transporte tuberías', '6145', FALSE, TRUE, FALSE),
(6, '614530', 'MANIPULACION DE CARGA', TRUE, 'Carga', '6145', FALSE, TRUE, FALSE),
(6, '614535', 'ALMACENAMIENTO Y DEPOSITO', TRUE, 'Almacenamiento', '6145', FALSE, TRUE, FALSE),
(6, '614540', 'SERVICIOS COMPLEMENTARIOS PARA EL TRANSPORTE', TRUE, 'Servicios transporte', '6145', FALSE, TRUE, FALSE),
(6, '614545', 'AGENCIAS DE VIAJE', TRUE, 'Agencias viaje', '6145', FALSE, TRUE, FALSE),
(6, '614550', 'OTRAS AGENCIAS DE TRANSPORTE', TRUE, 'Otras agencias', '6145', FALSE, TRUE, FALSE),
(6, '614555', 'SERVICIO POSTAL Y DE CORREO', TRUE, 'Postal', '6145', FALSE, TRUE, FALSE),
(6, '614560', 'SERVICIO TELEFONICO', TRUE, 'Telefonía', '6145', FALSE, TRUE, FALSE),
(6, '614565', 'SERVICIO DE TELEGRAFO', TRUE, 'Telégrafo', '6145', FALSE, TRUE, FALSE),
(6, '614570', 'SERVICIO DE TRANSMISION DE DATOS', TRUE, 'Transmisión datos', '6145', FALSE, TRUE, FALSE),
(6, '614575', 'SERVICIO DE RADIO Y TELEVISION POR CABLE', TRUE, 'Radio y TV', '6145', FALSE, TRUE, FALSE),
(6, '614580', 'TRANSMISION DE SONIDO E IMAGENES POR CONTRATO', TRUE, 'Transmisión', '6145', FALSE, TRUE, FALSE),
(6, '614595', 'ACTIVIDADES CONEXAS', TRUE, 'Actividades conexas', '6145', FALSE, TRUE, FALSE),
(6, '614599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación transporte', '6145', FALSE, TRUE, FALSE);

-- Subcuentas 6150
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '615005', 'DE INVERSIONES', TRUE, 'Costo inversiones', '6150', FALSE, TRUE, FALSE),
(6, '615010', 'DE SERVICIO DE BOLSA', TRUE, 'Servicio de bolsa', '6150', FALSE, TRUE, FALSE),
(6, '615099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación financieros', '6150', FALSE, TRUE, FALSE);

-- Subcuentas 6155
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '615505', 'ARRENDAMIENTOS DE BIENES INMUEBLES', TRUE, 'Arrendamientos inmuebles', '6155', FALSE, TRUE, FALSE),
(6, '615510', 'INMOBILIARIAS POR RETRIBUCION O CONTRATA', TRUE, 'Inmobiliarias', '6155', FALSE, TRUE, FALSE),
(6, '615515', 'ALQUILER EQUIPO DE TRANSPORTE', TRUE, 'Alquiler transporte', '6155', FALSE, TRUE, FALSE),
(6, '615520', 'ALQUILER MAQUINARIA Y EQUIPO', TRUE, 'Alquiler maquinaria', '6155', FALSE, TRUE, FALSE),
(6, '615525', 'ALQUILER DE EFECTOS PERSONALES Y ENSERES DOMESTICOS', TRUE, 'Alquiler enseres', '6155', FALSE, TRUE, FALSE),
(6, '615530', 'CONSULTORIA EN EQUIPO Y PROGRAMAS DE INFORMATICA', TRUE, 'Consultoría', '6155', FALSE, TRUE, FALSE),
(6, '615535', 'PROCESAMIENTO DE DATOS', TRUE, 'Procesamiento', '6155', FALSE, TRUE, FALSE),
(6, '615540', 'MANTENIMIENTO Y REPARACION DE MAQUINARIA DE OFICINA', TRUE, 'Mantenimiento', '6155', FALSE, TRUE, FALSE),
(6, '615545', 'INVESTIGACIONES CIENTIFICAS Y DE DESARROLLO', TRUE, 'Investigación', '6155', FALSE, TRUE, FALSE),
(6, '615550', 'ACTIVIDADES EMPRESARIALES DE CONSULTORIA', TRUE, 'Consultoría empresarial', '6155', FALSE, TRUE, FALSE),
(6, '615555', 'PUBLICIDAD', TRUE, 'Publicidad', '6155', FALSE, TRUE, FALSE),
(6, '615560', 'DOTACION DE PERSONAL', TRUE, 'Dotación', '6155', FALSE, TRUE, FALSE),
(6, '615565', 'INVESTIGACION Y SEGURIDAD', TRUE, 'Investigación', '6155', FALSE, TRUE, FALSE),
(6, '615570', 'LIMPIEZA DE INMUEBLES', TRUE, 'Limpieza', '6155', FALSE, TRUE, FALSE),
(6, '615575', 'FOTOGRAFIA', TRUE, 'Fotografía', '6155', FALSE, TRUE, FALSE),
(6, '615580', 'ENVASE Y EMPAQUE', TRUE, 'Envase', '6155', FALSE, TRUE, FALSE),
(6, '615585', 'FOTOCOPIADO', TRUE, 'Fotocopiado', '6155', FALSE, TRUE, FALSE),
(6, '615590', 'MANTENIMIENTO Y REPARACION DE MAQUINARIA Y EQUIPO', TRUE, 'Mantenimiento maquinaria', '6155', FALSE, TRUE, FALSE),
(6, '615595', 'ACTIVIDADES CONEXAS', TRUE, 'Actividades conexas', '6155', FALSE, TRUE, FALSE),
(6, '615599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación alquiler', '6155', FALSE, TRUE, FALSE);

-- Subcuentas 6160
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '616005', 'ACTIVIDADES RELACIONADAS CON LA EDUCACION', TRUE, 'Educación', '6160', FALSE, TRUE, FALSE),
(6, '616095', 'ACTIVIDADES CONEXAS', TRUE, 'Actividades conexas', '6160', FALSE, TRUE, FALSE),
(6, '616099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación educación', '6160', FALSE, TRUE, FALSE);

-- Subcuentas 6165
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '616505', 'SERVICIO HOSPITALARIO', TRUE, 'Hospitalario', '6165', FALSE, TRUE, FALSE),
(6, '616510', 'SERVICIO MEDICO', TRUE, 'Médico', '6165', FALSE, TRUE, FALSE),
(6, '616515', 'SERVICIO ODONTOLOGICO', TRUE, 'Odontológico', '6165', FALSE, TRUE, FALSE),
(6, '616520', 'SERVICIO DE LABORATORIO', TRUE, 'Laboratorio', '6165', FALSE, TRUE, FALSE),
(6, '616525', 'ACTIVIDADES VETERINARIAS', TRUE, 'Veterinaria', '6165', FALSE, TRUE, FALSE),
(6, '616530', 'ACTIVIDADES DE SERVICIOS SOCIALES', TRUE, 'Sociales', '6165', FALSE, TRUE, FALSE),
(6, '616595', 'ACTIVIDADES CONEXAS', TRUE, 'Actividades conexas', '6165', FALSE, TRUE, FALSE),
(6, '616599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación salud', '6165', FALSE, TRUE, FALSE);

-- Subcuentas 6170
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '617005', 'ELIMINACION DE DESPERDICIOS Y AGUAS RESIDUALES', TRUE, 'Desperdicios', '6170', FALSE, TRUE, FALSE),
(6, '617010', 'ACTIVIDADES DE ASOCIACION', TRUE, 'Asociaciones', '6170', FALSE, TRUE, FALSE),
(6, '617015', 'PRODUCCION Y DISTRIBUCION DE FILMES Y VIDEOCINTAS', TRUE, 'Filmes', '6170', FALSE, TRUE, FALSE),
(6, '617020', 'EXHIBICION DE FILMES Y VIDEOCINTAS', TRUE, 'Exhibición', '6170', FALSE, TRUE, FALSE),
(6, '617025', 'ACTIVIDAD DE RADIO Y TELEVISION', TRUE, 'Radio y TV', '6170', FALSE, TRUE, FALSE),
(6, '617030', 'ACTIVIDAD TEATRAL, MUSICAL Y ARTISTICA', TRUE, 'Teatral', '6170', FALSE, TRUE, FALSE),
(6, '617035', 'GRABACION Y PRODUCCION DE DISCOS', TRUE, 'Grabación', '6170', FALSE, TRUE, FALSE),
(6, '617040', 'ENTRETENIMIENTO Y ESPARCIMIENTO', TRUE, 'Entretenimiento', '6170', FALSE, TRUE, FALSE),
(6, '617045', 'AGENCIAS DE NOTICIAS', TRUE, 'Noticias', '6170', FALSE, TRUE, FALSE),
(6, '617050', 'LAVANDERIAS Y SIMILARES', TRUE, 'Lavanderías', '6170', FALSE, TRUE, FALSE),
(6, '617055', 'PELUQUERIAS Y SIMILARES', TRUE, 'Peluquerías', '6170', FALSE, TRUE, FALSE),
(6, '617060', 'SERVICIOS FUNERARIOS', TRUE, 'Funerarios', '6170', FALSE, TRUE, FALSE),
(6, '617065', 'ZONAS FRANCAS', TRUE, 'Zonas francas', '6170', FALSE, TRUE, FALSE),
(6, '617095', 'ACTIVIDADES CONEXAS', TRUE, 'Actividades conexas', '6170', FALSE, TRUE, FALSE),
(6, '617099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación otros', '6170', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 62 — COMPRAS
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '62', 'COMPRAS', TRUE, 'Adquisición de materias primas, materiales y mercancías', '6', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '6205', 'DE MERCANCIAS', TRUE, 'Compras de mercancías', '62', FALSE, TRUE, FALSE),
(4, '6210', 'DE MATERIAS PRIMAS', TRUE, 'Compras de materias primas', '62', FALSE, TRUE, FALSE),
(4, '6215', 'DE MATERIALES INDIRECTOS', TRUE, 'Compras de materiales indirectos', '62', FALSE, TRUE, FALSE),
(4, '6220', 'COMPRA DE ENERGIA', TRUE, 'Compra de energía', '62', FALSE, TRUE, FALSE),
(4, '6225', 'DEVOLUCIONES EN COMPRAS (CR)', FALSE, 'Devoluciones en compras', '62', FALSE, TRUE, FALSE);

-- Subcuentas 6205
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '620501', 'DE MERCANCIAS 620501 A 620598', TRUE, 'Mercancías rango', '6205', FALSE, TRUE, FALSE),
(6, '620598', 'DE MERCANCIAS FIN RANGO', TRUE, 'Mercancías fin', '6205', FALSE, TRUE, FALSE),
(6, '620599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación mercancías', '6205', FALSE, TRUE, FALSE);

-- Subcuentas 6210
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '621001', 'DE MATERIAS PRIMAS 621001 A 621098', TRUE, 'Materias primas rango', '6210', FALSE, TRUE, FALSE),
(6, '621098', 'DE MATERIAS PRIMAS FIN RANGO', TRUE, 'Materias primas fin', '6210', FALSE, TRUE, FALSE),
(6, '621099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación materias primas', '6210', FALSE, TRUE, FALSE);

-- Subcuentas 6215
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '621501', 'DE MATERIALES INDIRECTOS 621501 A 621598', TRUE, 'Materiales indirectos rango', '6215', FALSE, TRUE, FALSE),
(6, '621598', 'DE MATERIALES INDIRECTOS FIN RANGO', TRUE, 'Materiales indirectos fin', '6215', FALSE, TRUE, FALSE),
(6, '621599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación materiales indirectos', '6215', FALSE, TRUE, FALSE);

-- Subcuentas 6220
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '622001', 'COMPRA DE ENERGIA 622001 A 622098', TRUE, 'Energía rango', '6220', FALSE, TRUE, FALSE),
(6, '622098', 'COMPRA DE ENERGIA FIN RANGO', TRUE, 'Energía fin', '6220', FALSE, TRUE, FALSE),
(6, '622099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación energía', '6220', FALSE, TRUE, FALSE);

-- Subcuentas 6225 (CRÉDITO)
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '622501', 'DEVOLUCIONES EN COMPRAS 622501 A 622598', FALSE, 'Devoluciones compras rango', '6225', FALSE, TRUE, FALSE),
(6, '622598', 'DEVOLUCIONES EN COMPRAS FIN RANGO', FALSE, 'Devoluciones compras fin', '6225', FALSE, TRUE, FALSE),
(6, '622599', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación devoluciones', '6225', FALSE, TRUE, FALSE);

-- ============================================================
-- VERIFICACIÓN
-- ============================================================
-- SELECT COUNT(*) FROM tab_puc;
-- SELECT id_nivel, COUNT(*) FROM tab_puc GROUP BY id_nivel ORDER BY id_nivel;

-- ================================================================
-- PUC COLOMBIA - DECRETO 2650 DE 1993
-- ENTREGA 7: Clase 7 (Producción) + Clases 8 y 9 (Órdenes)
-- ================================================================

-- ============================================================
-- CLASE 7: COSTOS DE PRODUCCION O DE OPERACION (DÉBITO)
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(1, '7', 'COSTOS DE PRODUCCION O DE OPERACION', TRUE, 'Erogaciones asociadas a la elaboración o producción de bienes o servicios', '0', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 71 — MATERIA PRIMA
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '71', 'MATERIA PRIMA', TRUE, 'Materiales directos del proceso productivo', '7', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '7101', 'MATERIA PRIMA', TRUE, 'Materia prima', '71', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '710101', 'MATERIA PRIMA 710101 A 710199', TRUE, 'Materia prima rango', '7101', FALSE, TRUE, FALSE),
(6, '710199', 'MATERIA PRIMA FIN RANGO', TRUE, 'Materia prima fin', '7101', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 72 — MANO DE OBRA DIRECTA
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '72', 'MANO DE OBRA DIRECTA', TRUE, 'Salarios y prestaciones del personal directo', '7', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '7201', 'MANO DE OBRA DIRECTA', TRUE, 'Mano de obra directa', '72', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '720101', 'MANO DE OBRA DIRECTA 720101 A 720199', TRUE, 'Mano de obra directa rango', '7201', FALSE, TRUE, FALSE),
(6, '720199', 'MANO DE OBRA DIRECTA FIN RANGO', TRUE, 'Mano de obra directa fin', '7201', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 73 — COSTOS INDIRECTOS
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '73', 'COSTOS INDIRECTOS', TRUE, 'Materiales indirectos y demás costos aplicables', '7', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '7301', 'COSTOS INDIRECTOS', TRUE, 'Costos indirectos de fabricación', '73', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '730101', 'COSTOS INDIRECTOS 730101 A 730199', TRUE, 'Costos indirectos rango', '7301', FALSE, TRUE, FALSE),
(6, '730199', 'COSTOS INDIRECTOS FIN RANGO', TRUE, 'Costos indirectos fin', '7301', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 74 — CONTRATOS DE SERVICIOS
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '74', 'CONTRATOS DE SERVICIOS', TRUE, 'Costos de servicios contratados para el proceso productivo', '7', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '7401', 'CONTRATOS DE SERVICIOS', TRUE, 'Contratos de servicios', '74', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '740101', 'CONTRATOS DE SERVICIOS 740101 A 740199', TRUE, 'Contratos servicios rango', '7401', FALSE, TRUE, FALSE),
(6, '740199', 'CONTRATOS DE SERVICIOS FIN RANGO', TRUE, 'Contratos servicios fin', '7401', FALSE, TRUE, FALSE);

-- ============================================================
-- CLASE 8: CUENTAS DE ORDEN DEUDORAS (DÉBITO)
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(1, '8', 'CUENTAS DE ORDEN DEUDORAS', TRUE, 'Hechos o circunstancias que pueden generar derechos', '0', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 81 — DERECHOS CONTINGENTES
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '81', 'DERECHOS CONTINGENTES', TRUE, 'Compromisos o contratos que pueden derivar derechos', '8', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '8105', 'BIENES Y VALORES ENTREGADOS EN CUSTODIA', TRUE, 'Bienes entregados en custodia', '81', FALSE, TRUE, FALSE),
(4, '8110', 'BIENES Y VALORES ENTREGADOS EN GARANTIA', TRUE, 'Bienes entregados en garantía', '81', FALSE, TRUE, FALSE),
(4, '8115', 'BIENES Y VALORES EN PODER DE TERCEROS', TRUE, 'Bienes en poder de terceros', '81', FALSE, TRUE, FALSE),
(4, '8120', 'LITIGIOS Y/O DEMANDAS', TRUE, 'Litigios y demandas', '81', FALSE, TRUE, FALSE),
(4, '8125', 'PROMESAS DE COMPRAVENTA', TRUE, 'Promesas de compraventa', '81', FALSE, TRUE, FALSE),
(4, '8195', 'DIVERSAS', TRUE, 'Derechos contingentes diversos', '81', FALSE, TRUE, FALSE);

-- Subcuentas 8105
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '810505', 'VALORES MOBILIARIOS', TRUE, 'Valores mobiliarios', '8105', FALSE, TRUE, FALSE),
(6, '810510', 'BIENES MUEBLES', TRUE, 'Bienes muebles', '8105', FALSE, TRUE, FALSE),
(6, '810599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación custodia', '8105', FALSE, TRUE, FALSE);

-- Subcuentas 8110
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '811005', 'VALORES MOBILIARIOS', TRUE, 'Valores mobiliarios', '8110', FALSE, TRUE, FALSE),
(6, '811010', 'BIENES MUEBLES', TRUE, 'Bienes muebles', '8110', FALSE, TRUE, FALSE),
(6, '811015', 'BIENES INMUEBLES', TRUE, 'Bienes inmuebles', '8110', FALSE, TRUE, FALSE),
(6, '811020', 'CONTRATOS DE GANADO EN PARTICIPACION', TRUE, 'Ganado en participación', '8110', FALSE, TRUE, FALSE),
(6, '811099', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación garantía', '8110', FALSE, TRUE, FALSE);

-- Subcuentas 8115
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '811505', 'EN ARRENDAMIENTO', TRUE, 'Bienes en arrendamiento', '8115', FALSE, TRUE, FALSE),
(6, '811510', 'EN PRESTAMO', TRUE, 'Bienes en préstamo', '8115', FALSE, TRUE, FALSE),
(6, '811515', 'EN DEPOSITO', TRUE, 'Bienes en depósito', '8115', FALSE, TRUE, FALSE),
(6, '811520', 'EN CONSIGNACION', TRUE, 'Bienes en consignación', '8115', FALSE, TRUE, FALSE),
(6, '811599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación poder terceros', '8115', FALSE, TRUE, FALSE);

-- Subcuentas 8120
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '812005', 'EJECUTIVOS', TRUE, 'Litigios ejecutivos', '8120', FALSE, TRUE, FALSE),
(6, '812010', 'INCUMPLIMIENTO DE CONTRATOS', TRUE, 'Incumplimiento contratos', '8120', FALSE, TRUE, FALSE);

-- Subcuentas 8125
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '812501', 'PROMESAS DE COMPRAVENTA 812501 A 812599', TRUE, 'Promesas rango', '8125', FALSE, TRUE, FALSE),
(6, '812599', 'PROMESAS DE COMPRAVENTA FIN RANGO', TRUE, 'Promesas fin', '8125', FALSE, TRUE, FALSE);

-- Subcuentas 8195
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '819505', 'VALORES ADQUIRIDOS POR RECIBIR', TRUE, 'Valores por recibir', '8195', FALSE, TRUE, FALSE),
(6, '819595', 'OTRAS', TRUE, 'Otras', '8195', FALSE, TRUE, FALSE),
(6, '819599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación diversas', '8195', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 82 — DEUDORAS FISCALES
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '82', 'DEUDORAS FISCALES', TRUE, 'Diferencias entre contabilidad y declaraciones tributarias', '8', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '8201', 'DEUDORAS FISCALES', TRUE, 'Deudoras fiscales', '82', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '820101', 'DEUDORAS FISCALES 820101 A 820199', TRUE, 'Deudoras fiscales rango', '8201', FALSE, TRUE, FALSE),
(6, '820199', 'DEUDORAS FISCALES FIN RANGO', TRUE, 'Deudoras fiscales fin', '8201', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 83 — DEUDORAS DE CONTROL
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '83', 'DEUDORAS DE CONTROL', TRUE, 'Operaciones con terceros a favor del ente', '8', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '8305', 'BIENES RECIBIDOS EN ARRENDAMIENTO FINANCIERO', TRUE, 'Leasing financiero', '83', FALSE, TRUE, FALSE),
(4, '8310', 'TITULOS DE INVERSION NO COLOCADOS', TRUE, 'Títulos no colocados', '83', FALSE, TRUE, FALSE),
(4, '8315', 'PROPIEDADES PLANTA Y EQUIPO TOTALMENTE DEPRECIADOS, AGOTADOS Y/O AMORTIZADOS', TRUE, 'PPE totalmente depreciados', '83', FALSE, TRUE, FALSE),
(4, '8320', 'CREDITOS A FAVOR NO UTILIZADOS', TRUE, 'Créditos a favor no utilizados', '83', FALSE, TRUE, FALSE),
(4, '8325', 'ACTIVOS CASTIGADOS', TRUE, 'Activos castigados', '83', FALSE, TRUE, FALSE),
(4, '8330', 'TITULOS DE INVERSION AMORTIZADOS', TRUE, 'Títulos amortizados', '83', FALSE, TRUE, FALSE),
(4, '8335', 'CAPITALIZACION POR REVALORIZACION DE PATRIMONIO', TRUE, 'Capitalización revalorización', '83', FALSE, TRUE, FALSE),
(4, '8395', 'OTRAS CUENTAS DEUDORAS DE CONTROL', TRUE, 'Otras deudoras de control', '83', FALSE, TRUE, FALSE),
(4, '8399', 'AJUSTES POR INFLACION ACTIVOS', TRUE, 'Ajustes por inflación activos', '83', FALSE, TRUE, FALSE);

-- Subcuentas 8305
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '830505', 'BIENES MUEBLES', TRUE, 'Bienes muebles leasing', '8305', FALSE, TRUE, FALSE),
(6, '830510', 'BIENES INMUEBLES', TRUE, 'Bienes inmuebles leasing', '8305', FALSE, TRUE, FALSE),
(6, '830599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación leasing', '8305', FALSE, TRUE, FALSE);

-- Subcuentas 8310
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '831005', 'ACCIONES', TRUE, 'Acciones no colocadas', '8310', FALSE, TRUE, FALSE),
(6, '831010', 'BONOS', TRUE, 'Bonos no colocados', '8310', FALSE, TRUE, FALSE),
(6, '831095', 'OTROS', TRUE, 'Otros títulos', '8310', FALSE, TRUE, FALSE);

-- Subcuentas 8315
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '831506', 'MATERIALES PROYECTOS PETROLEROS', TRUE, 'Materiales petroleros', '8315', FALSE, TRUE, FALSE),
(6, '831516', 'CONSTRUCCIONES Y EDIFICACIONES', TRUE, 'Construcciones', '8315', FALSE, TRUE, FALSE),
(6, '831520', 'MAQUINARIA Y EQUIPO', TRUE, 'Maquinaria', '8315', FALSE, TRUE, FALSE),
(6, '831524', 'EQUIPO DE OFICINA', TRUE, 'Equipo oficina', '8315', FALSE, TRUE, FALSE),
(6, '831528', 'EQUIPO DE COMPUTACION Y COMUNICACION', TRUE, 'Equipo cómputo', '8315', FALSE, TRUE, FALSE),
(6, '831532', 'EQUIPO MEDICO - CIENTIFICO', TRUE, 'Equipo médico', '8315', FALSE, TRUE, FALSE),
(6, '831536', 'EQUIPO DE HOTELES Y RESTAURANTES', TRUE, 'Equipo hoteles', '8315', FALSE, TRUE, FALSE),
(6, '831540', 'FLOTA Y EQUIPO DE TRANSPORTE', TRUE, 'Flota', '8315', FALSE, TRUE, FALSE),
(6, '831544', 'FLOTA Y EQUIPO FLUVIAL Y/O MARITIMO', TRUE, 'Flota fluvial', '8315', FALSE, TRUE, FALSE),
(6, '831548', 'FLOTA Y EQUIPO AEREO', TRUE, 'Flota aérea', '8315', FALSE, TRUE, FALSE),
(6, '831552', 'FLOTA Y EQUIPO FERREO', TRUE, 'Flota férrea', '8315', FALSE, TRUE, FALSE),
(6, '831556', 'ACUEDUCTOS, PLANTAS Y REDES', TRUE, 'Acueductos', '8315', FALSE, TRUE, FALSE),
(6, '831560', 'ARMAMENTO DE VIGILANCIA', TRUE, 'Armamento', '8315', FALSE, TRUE, FALSE),
(6, '831562', 'ENVASES Y EMPAQUES', TRUE, 'Envases', '8315', FALSE, TRUE, FALSE),
(6, '831564', 'PLANTACIONES AGRICOLAS Y FORESTALES', TRUE, 'Plantaciones', '8315', FALSE, TRUE, FALSE),
(6, '831568', 'VIAS DE COMUNICACION', TRUE, 'Vías', '8315', FALSE, TRUE, FALSE),
(6, '831572', 'MINAS Y CANTERAS', TRUE, 'Minas', '8315', FALSE, TRUE, FALSE),
(6, '831576', 'POZOS ARTESIANOS', TRUE, 'Pozos', '8315', FALSE, TRUE, FALSE),
(6, '831580', 'YACIMIENTOS', TRUE, 'Yacimientos', '8315', FALSE, TRUE, FALSE),
(6, '831584', 'SEMOVIENTES', TRUE, 'Semovientes', '8315', FALSE, TRUE, FALSE),
(6, '831599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación PPE', '8315', FALSE, TRUE, FALSE);

-- Subcuentas 8320
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '832005', 'PAIS', TRUE, 'Créditos país', '8320', FALSE, TRUE, FALSE),
(6, '832010', 'EXTERIOR', TRUE, 'Créditos exterior', '8320', FALSE, TRUE, FALSE);

-- Subcuentas 8325
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '832505', 'INVERSIONES', TRUE, 'Inversiones castigadas', '8325', FALSE, TRUE, FALSE),
(6, '832510', 'DEUDORES', TRUE, 'Deudores castigados', '8325', FALSE, TRUE, FALSE),
(6, '832595', 'OTROS ACTIVOS', TRUE, 'Otros activos castigados', '8325', FALSE, TRUE, FALSE);

-- Subcuentas 8330
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '833005', 'BONOS', TRUE, 'Bonos amortizados', '8330', FALSE, TRUE, FALSE),
(6, '833095', 'OTROS', TRUE, 'Otros títulos amortizados', '8330', FALSE, TRUE, FALSE);

-- Subcuentas 8335
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '833501', 'CAPITALIZACION POR REVALORIZACION 833501 A 833599', TRUE, 'Capitalización rango', '8335', FALSE, TRUE, FALSE),
(6, '833599', 'CAPITALIZACION POR REVALORIZACION FIN RANGO', TRUE, 'Capitalización fin', '8335', FALSE, TRUE, FALSE);

-- Subcuentas 8395
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '839505', 'CHEQUES POSTFECHADOS', TRUE, 'Cheques postfechados', '8395', FALSE, TRUE, FALSE),
(6, '839510', 'CERTIFICADOS DE DEPOSITO A TERMINO', TRUE, 'CDT', '8395', FALSE, TRUE, FALSE),
(6, '839515', 'CHEQUES DEVUELTOS', TRUE, 'Cheques devueltos', '8395', FALSE, TRUE, FALSE),
(6, '839520', 'BIENES Y VALORES EN FIDEICOMISO', TRUE, 'Fideicomisos', '8395', FALSE, TRUE, FALSE),
(6, '839525', 'INTERESES SOBRE DEUDAS VENCIDAS', TRUE, 'Intereses deudas vencidas', '8395', FALSE, TRUE, FALSE),
(6, '839595', 'DIVERSAS', TRUE, 'Diversas', '8395', FALSE, TRUE, FALSE),
(6, '839599', 'AJUSTES POR INFLACION', TRUE, 'Ajuste inflación control', '8395', FALSE, TRUE, FALSE);

-- Subcuentas 8399
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '839905', 'INVERSIONES', TRUE, 'Ajuste inversiones', '8399', FALSE, TRUE, FALSE),
(6, '839910', 'INVENTARIOS', TRUE, 'Ajuste inventarios', '8399', FALSE, TRUE, FALSE),
(6, '839915', 'PROPIEDADES PLANTA Y EQUIPO', TRUE, 'Ajuste PPE', '8399', FALSE, TRUE, FALSE),
(6, '839920', 'INTANGIBLES', TRUE, 'Ajuste intangibles', '8399', FALSE, TRUE, FALSE),
(6, '839925', 'CARGOS DIFERIDOS', TRUE, 'Ajuste cargos diferidos', '8399', FALSE, TRUE, FALSE),
(6, '839995', 'OTROS ACTIVOS', TRUE, 'Ajuste otros activos', '8399', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPOS 84, 85, 86 — CONTRAPARTIDAS (CRÉDITO)
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '84', 'DERECHOS CONTINGENTES POR CONTRA (CR)', FALSE, 'Contrapartida grupo 81', '8', FALSE, TRUE, FALSE),
(2, '85', 'DEUDORAS FISCALES POR CONTRA (CR)', FALSE, 'Contrapartida grupo 82', '8', FALSE, TRUE, FALSE),
(2, '86', 'DEUDORAS DE CONTROL POR CONTRA (CR)', FALSE, 'Contrapartida grupo 83', '8', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '8401', 'DERECHOS CONTINGENTES POR CONTRA', FALSE, 'Contrapartida derechos contingentes', '84', FALSE, TRUE, FALSE),
(4, '8501', 'DEUDORAS FISCALES POR CONTRA', FALSE, 'Contrapartida deudoras fiscales', '85', FALSE, TRUE, FALSE),
(4, '8601', 'DEUDORAS DE CONTROL POR CONTRA', FALSE, 'Contrapartida deudoras de control', '86', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '840101', 'DERECHOS CONTINGENTES POR CONTRA 840101 A 840199', FALSE, 'Contrapartida rango', '8401', FALSE, TRUE, FALSE),
(6, '840199', 'DERECHOS CONTINGENTES POR CONTRA FIN RANGO', FALSE, 'Contrapartida fin', '8401', FALSE, TRUE, FALSE),
(6, '850101', 'DEUDORAS FISCALES POR CONTRA 850101 A 850199', FALSE, 'Contrapartida fiscal rango', '8501', FALSE, TRUE, FALSE),
(6, '850199', 'DEUDORAS FISCALES POR CONTRA FIN RANGO', FALSE, 'Contrapartida fiscal fin', '8501', FALSE, TRUE, FALSE),
(6, '860101', 'DEUDORAS DE CONTROL POR CONTRA 860101 A 860199', FALSE, 'Contrapartida control rango', '8601', FALSE, TRUE, FALSE),
(6, '860199', 'DEUDORAS DE CONTROL POR CONTRA FIN RANGO', FALSE, 'Contrapartida control fin', '8601', FALSE, TRUE, FALSE);

-- ============================================================
-- CLASE 9: CUENTAS DE ORDEN ACREEDORAS (CRÉDITO)
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(1, '9', 'CUENTAS DE ORDEN ACREEDORAS', FALSE, 'Compromisos o contratos que pueden derivar obligaciones', '0', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 91 — RESPONSABILIDADES CONTINGENTES
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '91', 'RESPONSABILIDADES CONTINGENTES', FALSE, 'Compromisos que pueden derivar obligaciones', '9', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '9105', 'BIENES Y VALORES RECIBIDOS EN CUSTODIA', FALSE, 'Bienes recibidos en custodia', '91', FALSE, TRUE, FALSE),
(4, '9110', 'BIENES Y VALORES RECIBIDOS EN GARANTIA', FALSE, 'Bienes recibidos en garantía', '91', FALSE, TRUE, FALSE),
(4, '9115', 'BIENES Y VALORES RECIBIDOS DE TERCEROS', FALSE, 'Bienes recibidos de terceros', '91', FALSE, TRUE, FALSE),
(4, '9120', 'LITIGIOS Y/O DEMANDAS', FALSE, 'Litigios y demandas', '91', FALSE, TRUE, FALSE),
(4, '9125', 'PROMESAS DE COMPRA VENTA', FALSE, 'Promesas de compraventa', '91', FALSE, TRUE, FALSE),
(4, '9130', 'CONTRATOS DE ADMINISTRACION DELEGADA', FALSE, 'Contratos administración delegada', '91', FALSE, TRUE, FALSE),
(4, '9135', 'CUENTAS EN PARTICIPACION', FALSE, 'Cuentas en participación', '91', FALSE, TRUE, FALSE),
(4, '9195', 'OTRAS RESPONSABILIIDADES CONTINGENTES', FALSE, 'Otras responsabilidades', '91', FALSE, TRUE, FALSE);

-- Subcuentas 9105
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '910505', 'VALORES MOBILIARIOS', FALSE, 'Valores mobiliarios', '9105', FALSE, TRUE, FALSE),
(6, '910510', 'BIENES MUEBLES', FALSE, 'Bienes muebles', '9105', FALSE, TRUE, FALSE),
(6, '910599', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación custodia', '9105', FALSE, TRUE, FALSE);

-- Subcuentas 9110
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '911005', 'VALORES MOBILIARIOS', FALSE, 'Valores mobiliarios', '9110', FALSE, TRUE, FALSE),
(6, '911010', 'BIENES MUEBLES', FALSE, 'Bienes muebles', '9110', FALSE, TRUE, FALSE),
(6, '911015', 'BIENES INMUEBLES', FALSE, 'Bienes inmuebles', '9110', FALSE, TRUE, FALSE),
(6, '911020', 'CONTRATOS DE GANADO EN PARTICIPACION', FALSE, 'Ganado participación', '9110', FALSE, TRUE, FALSE),
(6, '911099', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación garantía', '9110', FALSE, TRUE, FALSE);

-- Subcuentas 9115
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '911505', 'EN ARRENDAMIENTO', FALSE, 'En arrendamiento', '9115', FALSE, TRUE, FALSE),
(6, '911510', 'EN PRESTAMO', FALSE, 'En préstamo', '9115', FALSE, TRUE, FALSE),
(6, '911515', 'EN DEPOSITO', FALSE, 'En depósito', '9115', FALSE, TRUE, FALSE),
(6, '911520', 'EN CONSIGNACION', FALSE, 'En consignación', '9115', FALSE, TRUE, FALSE),
(6, '911525', 'EN COMODATO', FALSE, 'En comodato', '9115', FALSE, TRUE, FALSE),
(6, '911599', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación terceros', '9115', FALSE, TRUE, FALSE);

-- Subcuentas 9120
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '912005', 'LABORALES', FALSE, 'Litigios laborales', '9120', FALSE, TRUE, FALSE),
(6, '912010', 'CIVILES', FALSE, 'Litigios civiles', '9120', FALSE, TRUE, FALSE),
(6, '912015', 'ADMINISTRATIVOS O ARBITRALES', FALSE, 'Litigios administrativos', '9120', FALSE, TRUE, FALSE),
(6, '912020', 'TRIBUTARIOS', FALSE, 'Litigios tributarios', '9120', FALSE, TRUE, FALSE);

-- Subcuentas 9125
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '912501', 'PROMESAS DE COMPRAVENTA 912501 A 912599', FALSE, 'Promesas rango', '9125', FALSE, TRUE, FALSE),
(6, '912599', 'PROMESAS DE COMPRAVENTA FIN RANGO', FALSE, 'Promesas fin', '9125', FALSE, TRUE, FALSE);

-- Subcuentas 9130
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '913001', 'CONTRATOS ADMON DELEGADA 913001 A 913099', FALSE, 'Administración delegada rango', '9130', FALSE, TRUE, FALSE),
(6, '913099', 'CONTRATOS ADMON DELEGADA FIN RANGO', FALSE, 'Administración delegada fin', '9130', FALSE, TRUE, FALSE);

-- Subcuentas 9135
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '913501', 'CUENTAS EN PARTICIPACION 913501 A 913599', FALSE, 'Cuentas participación rango', '9135', FALSE, TRUE, FALSE),
(6, '913599', 'CUENTAS EN PARTICIPACION FIN RANGO', FALSE, 'Cuentas participación fin', '9135', FALSE, TRUE, FALSE);

-- Subcuentas 9195
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '919501', 'OTRAS RESPONSABILIDADES 919501 A 919599', FALSE, 'Otras responsabilidades rango', '9195', FALSE, TRUE, FALSE),
(6, '919599', 'OTRAS RESPONSABILIDADES FIN RANGO', FALSE, 'Otras responsabilidades fin', '9195', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 92 — ACREEDORAS FISCALES
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '92', 'ACREEDORAS FISCALES', FALSE, 'Diferencias fiscales crédito', '9', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '9201', 'ACREEDORAS FISCALES', FALSE, 'Acreedoras fiscales', '92', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '920101', 'ACREEDORAS FISCALES 920101 A 920199', FALSE, 'Acreedoras fiscales rango', '9201', FALSE, TRUE, FALSE),
(6, '920199', 'ACREEDORAS FISCALES FIN RANGO', FALSE, 'Acreedoras fiscales fin', '9201', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPO 93 — ACREEDORAS DE CONTROL
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '93', 'ACREEDORAS DE CONTROL', FALSE, 'Operaciones a cargo del ente', '9', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '9305', 'CONTRATOS DE ARRENDAMIENTO FINANCIERO', FALSE, 'Contratos leasing', '93', FALSE, TRUE, FALSE),
(4, '9395', 'OTRAS CUENTAS DE ORDEN ACREEDORAS DE CONTROL', FALSE, 'Otras acreedoras control', '93', FALSE, TRUE, FALSE),
(4, '9399', 'AJUSTES POR INFLACION PATRIMONIO', FALSE, 'Ajustes por inflación patrimonio', '93', FALSE, TRUE, FALSE);

-- Subcuentas 9305
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '930505', 'BIENES MUEBLES', FALSE, 'Bienes muebles leasing', '9305', FALSE, TRUE, FALSE),
(6, '930510', 'BIENES INMUEBLES', FALSE, 'Bienes inmuebles leasing', '9305', FALSE, TRUE, FALSE);

-- Subcuentas 9395
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '939505', 'DOCUMENTOS POR COBRAR DESCONTADOS', FALSE, 'Documentos descontados', '9395', FALSE, TRUE, FALSE),
(6, '939510', 'CONVENIOS DE PAGO', FALSE, 'Convenios de pago', '9395', FALSE, TRUE, FALSE),
(6, '939515', 'CONTRATOS DE CONSTRUCCIONES E INSTALACIONES POR EJECUTAR', FALSE, 'Contratos por ejecutar', '9395', FALSE, TRUE, FALSE),
(6, '939520', 'PEDIDOS COLOCADOS', FALSE, 'Pedidos colocados', '9395', FALSE, TRUE, FALSE),
(6, '939525', 'ADJUDICACIONES PENDIENTES DE LEGALIZAR', FALSE, 'Adjudicaciones pendientes', '9395', FALSE, TRUE, FALSE),
(6, '939530', 'RESERVA ARTICULO 30. LEY 4/80', FALSE, 'Reserva ley 4/80', '9395', FALSE, TRUE, FALSE),
(6, '939535', 'RESERVA COSTO REPOSICION SEMOVIENTES', FALSE, 'Reserva semovientes', '9395', FALSE, TRUE, FALSE),
(6, '939595', 'DIVERSAS', FALSE, 'Diversas', '9395', FALSE, TRUE, FALSE),
(6, '939599', 'AJUSTES POR INFLACION', FALSE, 'Ajuste inflación control', '9395', FALSE, TRUE, FALSE);

-- Subcuentas 9399
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '939905', 'CAPITAL SOCIAL', FALSE, 'Ajuste capital social', '9399', FALSE, TRUE, FALSE),
(6, '939910', 'SUPERAVIT DE CAPITAL', FALSE, 'Ajuste superávit capital', '9399', FALSE, TRUE, FALSE),
(6, '939915', 'RESERVAS', FALSE, 'Ajuste reservas', '9399', FALSE, TRUE, FALSE),
(6, '939925', 'DIVIDENDOS O PARTICIPACIONES DECRETADAS EN ACCIONES, CUOTAS O PARTES DE INTERES SOCIAL', FALSE, 'Ajuste dividendos en acciones', '9399', FALSE, TRUE, FALSE),
(6, '939930', 'RESULTADOS DE EJERCICIOS ANTERIORES', FALSE, 'Ajuste resultados anteriores', '9399', FALSE, TRUE, FALSE);

-- ============================================================
-- GRUPOS 94, 95, 96 — CONTRAPARTIDAS (DÉBITO)
-- ============================================================
INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(2, '94', 'RESPONSABILIDADES CONTINGENTES POR CONTRA (DB)', TRUE, 'Contrapartida grupo 91', '9', FALSE, TRUE, FALSE),
(2, '95', 'ACREEDORAS FISCALES POR CONTRA (DB)', TRUE, 'Contrapartida grupo 92', '9', FALSE, TRUE, FALSE),
(2, '96', 'ACREEDORAS DE CONTROL POR CONTRA (DB)', TRUE, 'Contrapartida grupo 93', '9', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(4, '9401', 'RESPONSABILIDADES CONTINGENTES POR CONTRA', TRUE, 'Contrapartida responsabilidades', '94', FALSE, TRUE, FALSE),
(4, '9501', 'ACREEDORAS FISCALES POR CONTRA', TRUE, 'Contrapartida acreedoras fiscales', '95', FALSE, TRUE, FALSE),
(4, '9601', 'ACREEDORAS DE CONTROL POR CONTRA', TRUE, 'Contrapartida acreedoras control', '96', FALSE, TRUE, FALSE);

INSERT INTO tab_puc (id_nivel, id_cod_puc, nom_cuenta, ind_natura, descrip_puc, cod_superior, ind_req_tercero, ind_estado, ind_borrado) VALUES
(6, '940101', 'RESPONSABILIDADES POR CONTRA 940101 A 940199', TRUE, 'Contrapartida rango', '9401', FALSE, TRUE, FALSE),
(6, '940199', 'RESPONSABILIDADES POR CONTRA FIN RANGO', TRUE, 'Contrapartida fin', '9401', FALSE, TRUE, FALSE),
(6, '950101', 'ACREEDORAS FISCALES POR CONTRA 950101 A 950199', TRUE, 'Contrapartida fiscal rango', '9501', FALSE, TRUE, FALSE),
(6, '950199', 'ACREEDORAS FISCALES POR CONTRA FIN RANGO', TRUE, 'Contrapartida fiscal fin', '9501', FALSE, TRUE, FALSE),
(6, '960101', 'ACREEDORAS DE CONTROL POR CONTRA 960101 A 960199', TRUE, 'Contrapartida control rango', '9601', FALSE, TRUE, FALSE),
(6, '960199', 'ACREEDORAS DE CONTROL POR CONTRA FIN RANGO', TRUE, 'Contrapartida control fin', '9601', FALSE, TRUE, FALSE);

-- ============================================================
-- VERIFICACIÓN FINAL
-- ============================================================
SELECT 'PUC cargado correctamente' AS status, COUNT(*) AS total_registros FROM tab_puc;

SELECT id_nivel, COUNT(*) AS cantidad 
  FROM tab_puc 
 GROUP BY id_nivel 
 ORDER BY id_nivel;

SELECT COUNT(*) AS totales_activos FROM tab_puc WHERE ind_borrado = FALSE;

